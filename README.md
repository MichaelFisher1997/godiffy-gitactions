# Godiffy Visual Regression GitHub Action

Upload visual regression test screenshots to Godiffy and generate comparison reports between branches.

## Features

- 📤 **Upload screenshots** from any testing tool (Playwright, Puppeteer, Cypress, etc.)
- 📊 **Generate comparison reports** between branches (e.g., feature vs main)
- 🎯 **Visual diff detection** with configurable algorithms and thresholds
- 📋 **Detailed summaries** in GitHub Actions UI
- 🔧 **No build step required** - pure Bash implementation

## Quick Start

### Mode 1: Upload Only

```yaml
name: Upload Screenshots
on: [push, pull_request]

jobs:
  upload:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run tests and capture screenshots
        run: npm run test:screenshots
        
      - name: Upload screenshots to Godiffy
        uses: MichaelFisher1997/godiffy-gitactions@v1
        with:
          api-key: ${{ secrets.GODIFFY_API_KEY }}
          images-path: './screenshots'
          site-id: 'my-website'
```

### Mode 2: Upload + Generate Report

```yaml
name: Visual Regression Tests
on: [pull_request]

jobs:
  visual-regression:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run tests and capture screenshots
        run: npm run test:screenshots
        
      - name: Upload and compare screenshots
        uses: MichaelFisher1997/godiffy-gitactions@v1
        with:
          api-key: ${{ secrets.GODIFFY_API_KEY }}
          images-path: './screenshots'
          site-id: 'my-website'
          create-report: true
          baseline-branch: 'main'
          report-name: 'PR #${{ github.event.pull_request.number }} Visual Regression'
```

## Inputs

### Required Inputs

| Input | Description |
|-------|-------------|
| `api-key` | Godiffy API key for authentication |
| `images-path` | Path to folder containing images (relative or absolute) |
| `site-id` | Godiffy site identifier |

### Optional Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `branch` | `${{ github.ref_name }}` | Git branch name |
| `commit` | `${{ github.sha }}` | Git commit SHA |
| `base-url` | `https://godiffy-backend-dev.up.railway.app` | Godiffy API base URL |
| `create-report` | `false` | Whether to generate a comparison report |
| `baseline-branch` | - | Branch to compare against (required if `create-report: true`) |
| `baseline-commit` | `latest` | Commit SHA to compare against |
| `report-name` | Auto-generated | Custom name for the report |
| `report-description` | - | Description for the report |
| `comparison-algorithm` | `pixelmatch` | Algorithm to use (`pixelmatch`, `ssim`) |
| `comparison-threshold` | `0.1` | Threshold for differences (0.0-1.0) |

## Outputs

| Output | Description |
|--------|-------------|
| `upload-count` | Number of images successfully uploaded |
| `failed-count` | Number of images that failed to upload |
| `upload-ids` | JSON array of upload IDs |
| `report-id` | Report ID if report was created |
| `report-url` | URL to view the report in Godiffy dashboard |
| `differences-found` | Boolean indicating if visual differences were detected |
| `total-comparisons` | Number of image comparisons performed |

## Setup

### 1. Get Godiffy API Key

1. Sign up at [Godiffy](https://godiffy.com)
2. Create a site in your dashboard
3. Generate an API key in site settings
4. Add the API key to your GitHub repository secrets:

```bash
# In your GitHub repo settings → Secrets and variables → Actions
GODIFFY_API_KEY=your_api_key_here
```

### 2. Prepare Screenshots

The action works with any screenshot tool. Just ensure your screenshots are saved to a directory:

```bash
# Example with Playwright
const { test } = require('@playwright/test');

test('capture screenshots', async ({ page }) => {
  await page.goto('https://your-site.com');
  await page.screenshot({ path: 'screenshots/homepage.png' });
  await page.goto('https://your-site.com/products');
  await page.screenshot({ path: 'screenshots/products.png' });
});
```

## Advanced Examples

### Multi-Branch Workflow

```yaml
name: Visual Regression
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  upload:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: npm ci
        
      - name: Run visual tests
        run: npm run test:visual
        
      - name: Upload to Godiffy
        uses: MichaelFisher1997/godiffy-gitactions@v1
        with:
          api-key: ${{ secrets.GODIFFY_API_KEY }}
          images-path: './screenshots'
          site-id: 'my-app'
          create-report: ${{ github.event_name == 'pull_request' }}
          baseline-branch: 'main'
          comparison-threshold: '0.05'
```

### Matrix Testing

```yaml
name: Cross-Browser Visual Tests
on: [push]

jobs:
  visual-tests:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        browser: [chromium, firefox, webkit]
    steps:
      - uses: actions/checkout@v4
      
      - name: Run ${{ matrix.browser }} tests
        run: npm run test:visual:${{ matrix.browser }}
        
      - name: Upload screenshots
        uses: MichaelFisher1997/godiffy-gitactions@v1
        with:
          api-key: ${{ secrets.GODIFFY_API_KEY }}
          images-path: './screenshots/${{ matrix.browser }}'
          site-id: 'my-app'
          branch: '${{ github.ref_name }}-${{ matrix.browser }}'
```

## Troubleshooting

### Common Issues

#### "api-key is required"
Ensure you've added `GODIFFY_API_KEY` to your repository secrets.

#### "No matching baseline images found"
- Ensure the baseline branch has uploaded screenshots
- Check that screenshot paths match between branches
- Verify `baseline-branch` is set correctly

#### "Upload failed for image.png"
- Check image format (PNG, JPEG, WebP supported)
- Verify file size limits
- Ensure API key has proper permissions

### Debug Mode

Add debug output to troubleshoot issues:

```yaml
- name: Upload with debug
  uses: godiffy/upload-action@v1
  env:
    ACTIONS_STEP_DEBUG: true
  with:
    api-key: ${{ secrets.GODIFFY_API_KEY }}
    images-path: './screenshots'
    site-id: 'my-site'
```

## API Reference

This action uses the Godiffy API v2. For more details, see the [Godiffy API documentation](https://docs.godiffy.com).

### Endpoints Used

- `POST /api/v2/sites/{siteId}/uploads` - Upload images
- `GET /api/v2/sites/{siteId}/uploads` - List uploads
- `POST /api/v2/sites/{siteId}/reports` - Create comparison report
- `GET /api/v2/sites/{siteId}/reports/{reportId}` - Get report results

## Usage

This action is available at `MichaelFisher1997/godiffy-gitactions`. Use it in your GitHub workflows as shown in the examples above.

### Repository URL
- **GitHub**: https://github.com/MichaelFisher1997/godiffy-gitactions
- **Action**: `MichaelFisher1997/godiffy-gitactions@v1`

### Quick Setup

1. **Add the action to your workflow** (see examples above)
2. **Set up secrets** in your GitHub repository:
   - Go to Settings → Secrets and variables → Actions
   - Click "New repository secret"
   - Add `GODIFFY_API_KEY` with your Godiffy API key
3. **Configure your site ID** in the action inputs
4. **Run your workflow** to upload screenshots

## Contributing

1. Fork this repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- 📖 [Documentation](https://docs.godiffy.com)
- 🐛 [Issues](https://github.com/MichaelFisher1997/godiffy-gitactions/issues)
- 💬 [Discussions](https://github.com/MichaelFisher1997/godiffy-gitactions/discussions)

---

Made with ❤️ by [Godiffy](https://godiffy.com)