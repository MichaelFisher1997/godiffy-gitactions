# GitHub Action: Godiffy Visual Regression

## Overview
A GitHub Action that uploads visual regression test screenshots to Godiffy and generates comparison reports. Users run their own screenshot tool (Playwright, Puppeteer, etc.) and this action handles:
1. Uploading images to the Godiffy API
2. Creating comparison reports between branches (e.g., feature branch vs main)

## User Experience

### Mode 1: Upload Only
```yaml
# Upload screenshots without generating a report
- name: Upload screenshots to Godiffy
  uses: godiffy/upload-action@v1
  with:
    api-key: ${{ secrets.GODIFFY_API_KEY }}
    images-path: './screenshots'
    site-id: 'my-website'
    branch: ${{ github.ref_name }}
    commit: ${{ github.sha }}
```

### Mode 2: Upload + Generate Report
```yaml
# Upload screenshots and compare against baseline branch
- name: Upload and compare screenshots
  uses: godiffy/upload-action@v1
  with:
    api-key: ${{ secrets.GODIFFY_API_KEY }}
    images-path: './screenshots'
    site-id: 'my-website'
    branch: ${{ github.ref_name }}
    commit: ${{ github.sha }}
    # Report generation options
    create-report: true
    baseline-branch: 'main'
    baseline-commit: 'latest'  # or specific SHA
    report-name: 'PR #${{ github.event.pull_request.number }} Visual Regression'
```

## Requirements

### Inputs (action.yml)

#### Upload Inputs
- `api-key` (required): Godiffy API key for authentication
- `images-path` (required): Path to folder containing images (relative or absolute)
- `site-id` (required): Godiffy site identifier
- `branch` (optional): Git branch name (default: `${{ github.ref_name }}`)
- `commit` (optional): Git commit SHA (default: `${{ github.sha }}`)
- `base-url` (optional): Godiffy API base URL (default: `https://godiffy-backend-dev.up.railway.app`)

#### Report Generation Inputs
- `create-report` (optional): Whether to generate a comparison report (default: `false`)
- `baseline-branch` (optional): Branch to compare against (required if `create-report: true`)
- `baseline-commit` (optional): Commit SHA to compare against (default: `'latest'`)
- `report-name` (optional): Custom name for the report (default: auto-generated)
- `report-description` (optional): Description for the report
- `comparison-algorithm` (optional): Algorithm to use (`pixelmatch`, `ssim`, default: `pixelmatch`)
- `comparison-threshold` (optional): Threshold for differences (0.0-1.0, default: `0.1`)

### Outputs
- `upload-count`: Number of images successfully uploaded
- `failed-count`: Number of images that failed to upload
- `upload-ids`: JSON array of upload IDs returned by API
- `report-id`: Report ID if report was created
- `report-url`: URL to view the report in Godiffy dashboard
- `differences-found`: Boolean indicating if visual differences were detected
- `total-comparisons`: Number of image comparisons performed

## API Integration

### Authentication
All requests must include:
```
Authorization: Bearer <api-key>
```

### Endpoint: Upload Image
**POST** `/api/v2/sites/{siteId}/uploads`

**Headers:**
```
Authorization: Bearer <api-key>
Content-Type: multipart/form-data
```

**Form Data:**
- `file`: Image file (PNG, JPEG, WebP)
- `branch`: Git branch name
- `commit`: Git commit SHA
- `path`: Relative path of the screenshot (e.g., `/homepage.png`, `/products/item-1.png`)

**Response (200 OK):**
```json
{
  "id": "upload-uuid",
  "siteId": "site-uuid",
  "path": "/homepage.png",
  "branch": "main",
  "commit": "abc123",
  "url": "https://storage-url/image.png",
  "createdAt": "2024-01-01T00:00:00Z"
}
```

**Error Responses:**
- `401 Unauthorized`: Invalid or missing API key
- `404 Not Found`: Site ID doesn't exist or user doesn't have access
- `413 Payload Too Large`: Image exceeds size limit
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error

### Endpoint: Get Site Info (Optional - for validation)
**GET** `/api/v2/sites/{siteId}`

**Headers:**
```
Authorization: Bearer <api-key>
```

**Response (200 OK):**
```json
{
  "id": "site-uuid",
  "name": "My Website",
  "url": "https://example.com",
  "createdAt": "2024-01-01T00:00:00Z"
}
```

### Endpoint: Create Report
**POST** `/api/v2/sites/{siteId}/reports`

**Headers:**
```
Authorization: Bearer <api-key>
Content-Type: application/json
```

**Request Body:**
```json
{
  "name": "PR #123 Visual Regression",
  "description": "Comparing feature-branch against main",
  "baselineBranch": "main",
  "baselineCommit": "abc123def",
  "candidateBranch": "feature-branch",
  "candidateCommit": "xyz789ghi",
  "algorithm": "pixelmatch",
  "threshold": 0.1,
  "comparisons": [
    {
      "path": "/homepage.png",
      "baselineUploadId": "upload-uuid-1",
      "candidateUploadId": "upload-uuid-2"
    },
    {
      "path": "/products/item-1.png",
      "baselineUploadId": "upload-uuid-3",
      "candidateUploadId": "upload-uuid-4"
    }
  ]
}
```

**Response (200 OK):**
```json
{
  "id": "report-uuid",
  "siteId": "site-uuid",
  "name": "PR #123 Visual Regression",
  "description": "Comparing feature-branch against main",
  "baselineBranch": "main",
  "baselineCommit": "abc123def",
  "candidateBranch": "feature-branch",
  "candidateCommit": "xyz789ghi",
  "status": "completed",
  "totalComparisons": 2,
  "differencesFound": 1,
  "createdAt": "2024-01-01T00:00:00Z",
  "completedAt": "2024-01-01T00:00:05Z"
}
```

**Error Responses:**
- `400 Bad Request`: Missing required fields or invalid comparisons
- `402 Payment Required`: Feature not available on current plan
- `404 Not Found`: Site not found or baseline/candidate uploads not found

### Endpoint: List Uploads (for finding baseline images)
**GET** `/api/v2/sites/{siteId}/uploads?branch={branch}&commit={commit}`

**Headers:**
```
Authorization: Bearer <api-key>
```

**Query Parameters:**
- `branch` (required): Branch name to filter by
- `commit` (optional): Specific commit SHA. If omitted, returns all uploads for the branch

**Response (200 OK):**
```json
{
  "uploads": [
    {
      "id": "upload-uuid-1",
      "siteId": "site-uuid",
      "path": "/homepage.png",
      "branch": "main",
      "commit": "abc123def",
      "url": "https://storage-url/image.png",
      "createdAt": "2024-01-01T00:00:00Z"
    },
    {
      "id": "upload-uuid-2",
      "siteId": "site-uuid",
      "path": "/products/item-1.png",
      "branch": "main",
      "commit": "abc123def",
      "url": "https://storage-url/image2.png",
      "createdAt": "2024-01-01T00:00:01Z"
    }
  ],
  "total": 2
}
```

### Endpoint: Get Report
**GET** `/api/v2/sites/{siteId}/reports/{reportId}`

**Headers:**
```
Authorization: Bearer <api-key>
```

**Response (200 OK):**
```json
{
  "id": "report-uuid",
  "siteId": "site-uuid",
  "name": "PR #123 Visual Regression",
  "status": "completed",
  "totalComparisons": 2,
  "differencesFound": 1,
  "comparisons": [
    {
      "path": "/homepage.png",
      "baselineUrl": "https://storage/baseline.png",
      "candidateUrl": "https://storage/candidate.png",
      "diffUrl": "https://storage/diff.png",
      "diffPercentage": 0.05,
      "passed": true
    },
    {
      "path": "/products/item-1.png",
      "baselineUrl": "https://storage/baseline2.png",
      "candidateUrl": "https://storage/candidate2.png",
      "diffUrl": "https://storage/diff2.png",
      "diffPercentage": 0.15,
      "passed": false
    }
  ]
}
```

## Implementation Plan

### 1. Repository Structure
```
godiffy-upload-action/
├── action.yml              # Action metadata and inputs/outputs
├── upload.sh              # Upload images script
├── generate-report.sh     # Generate comparison report script
├── main.sh                # Main entry point script
├── README.md
└── LICENSE
```

**Note:** Examples will be provided in a separate demo repository with a fully implemented static site.

### 2. Main Script (main.sh)

```bash
#!/bin/bash
set -e

# Get inputs from action.yml (GitHub Actions sets these as env vars)
API_KEY="${INPUT_API_KEY}"
IMAGES_PATH="${INPUT_IMAGES_PATH}"
SITE_ID="${INPUT_SITE_ID}"
BRANCH="${INPUT_BRANCH:-${GITHUB_REF_NAME}}"
COMMIT="${INPUT_COMMIT:-${GITHUB_SHA}}"
BASE_URL="${INPUT_BASE_URL:-https://godiffy-backend-dev.up.railway.app}"

# Report generation inputs
CREATE_REPORT="${INPUT_CREATE_REPORT:-false}"
BASELINE_BRANCH="${INPUT_BASELINE_BRANCH}"
BASELINE_COMMIT="${INPUT_BASELINE_COMMIT:-latest}"
REPORT_NAME="${INPUT_REPORT_NAME}"
REPORT_DESCRIPTION="${INPUT_REPORT_DESCRIPTION}"
ALGORITHM="${INPUT_COMPARISON_ALGORITHM:-pixelmatch}"
THRESHOLD="${INPUT_COMPARISON_THRESHOLD:-0.1}"

# Validate required inputs
if [ -z "$API_KEY" ]; then
  echo "::error::api-key is required"
  exit 1
fi

if [ -z "$IMAGES_PATH" ]; then
  echo "::error::images-path is required"
  exit 1
fi

if [ -z "$SITE_ID" ]; then
  echo "::error::site-id is required"
  exit 1
fi

# Upload images
echo "::group::Uploading images"
UPLOAD_RESULTS=$(bash upload.sh "$BASE_URL" "$API_KEY" "$SITE_ID" "$BRANCH" "$COMMIT" "$IMAGES_PATH")
UPLOAD_EXIT_CODE=$?
echo "::endgroup::"

if [ $UPLOAD_EXIT_CODE -ne 0 ]; then
  echo "::error::Upload failed"
  exit 1
fi

# Parse upload results (JSON output from upload.sh)
UPLOAD_COUNT=$(echo "$UPLOAD_RESULTS" | jq -r '.successful | length')
FAILED_COUNT=$(echo "$UPLOAD_RESULTS" | jq -r '.failed | length')
UPLOAD_IDS=$(echo "$UPLOAD_RESULTS" | jq -c '[.successful[].id]')

# Set outputs
echo "upload-count=$UPLOAD_COUNT" >> $GITHUB_OUTPUT
echo "failed-count=$FAILED_COUNT" >> $GITHUB_OUTPUT
echo "upload-ids=$UPLOAD_IDS" >> $GITHUB_OUTPUT

echo "✅ Uploaded $UPLOAD_COUNT images successfully"
if [ "$FAILED_COUNT" -gt 0 ]; then
  echo "::warning::$FAILED_COUNT images failed to upload"
fi

# Generate report if requested
if [ "$CREATE_REPORT" = "true" ]; then
  if [ -z "$BASELINE_BRANCH" ]; then
    echo "::error::baseline-branch is required when create-report is true"
    exit 1
  fi

  echo "::group::Generating comparison report"
  REPORT_NAME="${REPORT_NAME:-$BRANCH vs $BASELINE_BRANCH}"
  
  REPORT_RESULTS=$(bash generate-report.sh \
    "$BASE_URL" \
    "$API_KEY" \
    "$SITE_ID" \
    "$UPLOAD_RESULTS" \
    "$BRANCH" \
    "$COMMIT" \
    "$BASELINE_BRANCH" \
    "$BASELINE_COMMIT" \
    "$REPORT_NAME" \
    "$REPORT_DESCRIPTION" \
    "$ALGORITHM" \
    "$THRESHOLD")
  
  REPORT_EXIT_CODE=$?
  echo "::endgroup::"

  if [ $REPORT_EXIT_CODE -ne 0 ]; then
    echo "::error::Report generation failed"
    exit 1
  fi

  # Parse report results
  REPORT_ID=$(echo "$REPORT_RESULTS" | jq -r '.id')
  TOTAL_COMPARISONS=$(echo "$REPORT_RESULTS" | jq -r '.totalComparisons')
  DIFFERENCES_FOUND=$(echo "$REPORT_RESULTS" | jq -r '.differencesFound')
  REPORT_URL="$BASE_URL/sites/$SITE_ID/reports/$REPORT_ID"

  # Set report outputs
  echo "report-id=$REPORT_ID" >> $GITHUB_OUTPUT
  echo "report-url=$REPORT_URL" >> $GITHUB_OUTPUT
  echo "differences-found=$([ $DIFFERENCES_FOUND -gt 0 ] && echo 'true' || echo 'false')" >> $GITHUB_OUTPUT
  echo "total-comparisons=$TOTAL_COMPARISONS" >> $GITHUB_OUTPUT

  # Create job summary
  {
    echo "## Godiffy Visual Regression Summary"
    echo ""
    echo "### Upload Status"
    echo "| Status | Count |"
    echo "|--------|-------|"
    echo "| ✅ Successful | $UPLOAD_COUNT |"
    echo "| ❌ Failed | $FAILED_COUNT |"
    echo ""
    echo "### Comparison Report"
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Total Comparisons | $TOTAL_COMPARISONS |"
    echo "| Differences Found | $DIFFERENCES_FOUND |"
    echo "| Report URL | [View Report]($REPORT_URL) |"
  } >> $GITHUB_STEP_SUMMARY

  if [ "$DIFFERENCES_FOUND" -gt 0 ]; then
    echo "::warning::⚠️ $DIFFERENCES_FOUND visual differences detected"
  fi
else
  # Create simple summary for upload-only
  {
    echo "## Godiffy Upload Summary"
    echo ""
    echo "| Status | Count |"
    echo "|--------|-------|"
    echo "| ✅ Successful | $UPLOAD_COUNT |"
    echo "| ❌ Failed | $FAILED_COUNT |"
  } >> $GITHUB_STEP_SUMMARY
fi

# Fail if uploads failed
if [ "$FAILED_COUNT" -gt 0 ]; then
  echo "::error::$FAILED_COUNT images failed to upload"
  exit 1
fi

echo "✅ Action completed successfully"
```

### 3. Upload Script (upload.sh)

```bash
#!/bin/bash
set -e

BASE_URL="$1"
API_KEY="$2"
SITE_ID="$3"
BRANCH="$4"
COMMIT="$5"
IMAGES_PATH="$6"

# Initialize result arrays
SUCCESSFUL=()
FAILED=()

# Find all image files recursively
while IFS= read -r -d '' file; do
  # Calculate relative path from images directory
  RELATIVE_PATH=$(realpath --relative-to="$IMAGES_PATH" "$file")
  # Ensure leading slash
  API_PATH="/$RELATIVE_PATH"
  
  echo "Uploading $API_PATH..."
  
  # Upload using curl with multipart form data
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $API_KEY" \
    -F "file=@$file" \
    -F "branch=$BRANCH" \
    -F "commit=$COMMIT" \
    -F "path=$API_PATH" \
    "$BASE_URL/api/v2/sites/$SITE_ID/uploads")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')
  
  if [ "$HTTP_CODE" -eq 200 ]; then
    UPLOAD_ID=$(echo "$BODY" | jq -r '.id')
    SUCCESSFUL+=("$(echo "$BODY" | jq -c '.')")
    echo "✅ Uploaded $API_PATH (ID: $UPLOAD_ID)"
  else
    ERROR_MSG=$(echo "$BODY" | jq -r '.error // "Unknown error"')
    FAILED+=("{\"file\":\"$API_PATH\",\"error\":\"$ERROR_MSG\"}")
    echo "::error::❌ Failed to upload $API_PATH: $ERROR_MSG"
  fi
done < <(find "$IMAGES_PATH" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) -print0)

# Output JSON results
jq -n \
  --argjson successful "$(printf '%s\n' "${SUCCESSFUL[@]}" | jq -s '.')" \
  --argjson failed "$(printf '%s\n' "${FAILED[@]}" | jq -s '.')" \
  '{successful: $successful, failed: $failed}'
```

### 4. Report Generation Script (generate-report.sh)

```bash
#!/bin/bash
set -e

BASE_URL="$1"
API_KEY="$2"
SITE_ID="$3"
UPLOAD_RESULTS="$4"  # JSON from upload.sh
CANDIDATE_BRANCH="$5"
CANDIDATE_COMMIT="$6"
BASELINE_BRANCH="$7"
BASELINE_COMMIT="$8"
REPORT_NAME="$9"
REPORT_DESCRIPTION="${10}"
ALGORITHM="${11}"
THRESHOLD="${12}"

echo "Fetching baseline uploads from $BASELINE_BRANCH@$BASELINE_COMMIT..."

# Fetch baseline uploads
if [ "$BASELINE_COMMIT" = "latest" ]; then
  # Get all uploads for the branch and find the most recent commit
  BASELINE_RESPONSE=$(curl -s \
    -H "Authorization: Bearer $API_KEY" \
    "$BASE_URL/api/v2/sites/$SITE_ID/uploads?branch=$(printf %s "$BASELINE_BRANCH" | jq -sRr @uri)")
  
  BASELINE_COMMIT=$(echo "$BASELINE_RESPONSE" | jq -r '.uploads[0].commit // empty')
  
  if [ -z "$BASELINE_COMMIT" ]; then
    echo "::error::No uploads found for branch $BASELINE_BRANCH"
    exit 1
  fi
  
  echo "Using latest commit: $BASELINE_COMMIT"
fi

# Fetch baseline uploads for specific commit
BASELINE_RESPONSE=$(curl -s \
  -H "Authorization: Bearer $API_KEY" \
  "$BASE_URL/api/v2/sites/$SITE_ID/uploads?branch=$(printf %s "$BASELINE_BRANCH" | jq -sRr @uri)&commit=$(printf %s "$BASELINE_COMMIT" | jq -sRr @uri)")

BASELINE_UPLOADS=$(echo "$BASELINE_RESPONSE" | jq -c '.uploads')

# Match candidate uploads with baseline uploads by path
CANDIDATE_UPLOADS=$(echo "$UPLOAD_RESULTS" | jq -c '.successful')
COMPARISONS=()

while IFS= read -r candidate; do
  CANDIDATE_PATH=$(echo "$candidate" | jq -r '.path')
  CANDIDATE_ID=$(echo "$candidate" | jq -r '.id')
  
  # Find matching baseline
  BASELINE_ID=$(echo "$BASELINE_UPLOADS" | jq -r --arg path "$CANDIDATE_PATH" '.[] | select(.path == $path) | .id')
  
  if [ -n "$BASELINE_ID" ]; then
    COMPARISON=$(jq -n \
      --arg path "$CANDIDATE_PATH" \
      --arg baselineId "$BASELINE_ID" \
      --arg candidateId "$CANDIDATE_ID" \
      '{path: $path, baselineUploadId: $baselineId, candidateUploadId: $candidateId}')
    COMPARISONS+=("$COMPARISON")
  else
    echo "::warning::No baseline found for $CANDIDATE_PATH"
  fi
done < <(echo "$CANDIDATE_UPLOADS" | jq -c '.[]')

if [ ${#COMPARISONS[@]} -eq 0 ]; then
  echo "::error::No matching baseline images found. Ensure $BASELINE_BRANCH has uploaded screenshots."
  exit 1
fi

echo "Creating report with ${#COMPARISONS[@]} comparisons..."

# Build comparisons JSON array
COMPARISONS_JSON=$(printf '%s\n' "${COMPARISONS[@]}" | jq -s '.')

# Create report
REPORT_PAYLOAD=$(jq -n \
  --arg name "$REPORT_NAME" \
  --arg description "$REPORT_DESCRIPTION" \
  --arg baselineBranch "$BASELINE_BRANCH" \
  --arg baselineCommit "$BASELINE_COMMIT" \
  --arg candidateBranch "$CANDIDATE_BRANCH" \
  --arg candidateCommit "$CANDIDATE_COMMIT" \
  --arg algorithm "$ALGORITHM" \
  --arg threshold "$THRESHOLD" \
  --argjson comparisons "$COMPARISONS_JSON" \
  '{
    name: $name,
    description: $description,
    baselineBranch: $baselineBranch,
    baselineCommit: $baselineCommit,
    candidateBranch: $candidateBranch,
    candidateCommit: $candidateCommit,
    algorithm: $algorithm,
    threshold: ($threshold | tonumber),
    comparisons: $comparisons
  }')

REPORT_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$REPORT_PAYLOAD" \
  "$BASE_URL/api/v2/sites/$SITE_ID/reports")

HTTP_CODE=$(echo "$REPORT_RESPONSE" | tail -n1)
BODY=$(echo "$REPORT_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ne 200 ]; then
  ERROR_MSG=$(echo "$BODY" | jq -r '.error // "Unknown error"')
  echo "::error::Failed to create report: $ERROR_MSG"
  exit 1
fi

# Output report result
echo "$BODY"
```

## action.yml Configuration

```yaml
name: 'Godiffy Visual Regression'
description: 'Upload visual regression test screenshots to Godiffy and generate comparison reports'
author: 'Godiffy'
branding:
  icon: 'camera'
  color: 'blue'

inputs:
  api-key:
    description: 'Godiffy API key for authentication'
    required: true
  images-path:
    description: 'Path to folder containing images (relative or absolute)'
    required: true
  site-id:
    description: 'Godiffy site identifier'
    required: true
  branch:
    description: 'Git branch name'
    required: false
    default: ${{ github.ref_name }}
  commit:
    description: 'Git commit SHA'
    required: false
    default: ${{ github.sha }}
  base-url:
    description: 'Godiffy API base URL'
    required: false
    default: 'https://godiffy-backend-dev.up.railway.app'
  create-report:
    description: 'Whether to generate a comparison report'
    required: false
    default: 'false'
  baseline-branch:
    description: 'Branch to compare against (required if create-report is true)'
    required: false
  baseline-commit:
    description: 'Commit SHA to compare against'
    required: false
    default: 'latest'
  report-name:
    description: 'Custom name for the report'
    required: false
  report-description:
    description: 'Description for the report'
    required: false
  comparison-algorithm:
    description: 'Algorithm to use (pixelmatch, ssim)'
    required: false
    default: 'pixelmatch'
  comparison-threshold:
    description: 'Threshold for differences (0.0-1.0)'
    required: false
    default: '0.1'

outputs:
  upload-count:
    description: 'Number of images successfully uploaded'
  failed-count:
    description: 'Number of images that failed to upload'
  upload-ids:
    description: 'JSON array of upload IDs'
  report-id:
    description: 'Report ID if report was created'
  report-url:
    description: 'URL to view the report in Godiffy dashboard'
  differences-found:
    description: 'Boolean indicating if visual differences were detected'
  total-comparisons:
    description: 'Number of image comparisons performed'

runs:
  using: 'composite'
  steps:
    - name: Run Godiffy action
      shell: bash
      run: |
        chmod +x ${{ github.action_path }}/main.sh
        chmod +x ${{ github.action_path }}/upload.sh
        chmod +x ${{ github.action_path }}/generate-report.sh
        ${{ github.action_path }}/main.sh
```

## Testing Plan

### Local Testing
1. Create a test site in Godiffy dev environment
2. Generate test API key
3. Create sample images in `./test-images/`
4. Run action locally using `act` or `@vercel/ncc`

### Integration Testing
1. Test against Railway backend: `https://godiffy-backend-dev.up.railway.app`
2. Verify uploads appear in Godiffy dashboard
3. Test report generation:
   - Upload baseline images to `main` branch
   - Upload candidate images to `feature` branch
   - Generate report comparing the two
   - Verify report shows differences correctly
4. Test error scenarios:
   - Invalid API key
   - Non-existent site ID
   - Empty images folder
   - Unsupported file types
   - Network failures
   - Missing baseline images for report
   - Report generation without Pro plan (402 error)

### CI Testing
1. Add workflow to action repo that tests itself
2. Use matrix strategy to test different Node versions
3. Test with various image folder structures

## Error Handling

### Graceful Failures
- Log each failed upload but continue processing
- Provide detailed error messages
- Set action as failed only if ALL uploads fail
- Include retry logic for transient network errors (3 retries with exponential backoff)

### User-Friendly Messages
```
❌ Upload failed for /homepage.png
   Reason: 401 Unauthorized - Invalid API key
   
💡 Make sure your GODIFFY_API_KEY secret is set correctly
```

## Documentation Requirements

### README.md
- Quick start guide
- All input parameters with descriptions
- Output descriptions
- Multiple example workflows
- Troubleshooting section
- Link to Godiffy docs

### Action Marketplace Listing
- Clear description: "Upload visual regression test screenshots to Godiffy"
- Icon: Camera or image icon
- Color: Brand color
- Tags: visual-testing, screenshots, regression-testing, qa

## Dependencies

### System Requirements
- `bash` - Shell scripting (available on all GitHub Actions runners)
- `curl` - HTTP requests (pre-installed on GitHub Actions runners)
- `jq` - JSON processing (pre-installed on GitHub Actions runners)
- `find` - File searching (pre-installed on GitHub Actions runners)

**No npm packages or build step required!**

## Release Strategy

### Versioning
- Follow semver: v1.0.0, v1.1.0, etc.
- Maintain major version tags: v1, v2
- Tag releases in git

### Distribution
- Bash scripts are committed directly (no compilation needed)
- Create GitHub releases with changelog
- Update major version tag on each release

## API Compatibility Notes

### Current Backend API (Railway)
- Base URL: `https://godiffy-backend-dev.up.railway.app`
- Authentication: Bearer token in Authorization header
- Upload endpoint: `POST /api/v2/sites/{siteId}/uploads`
- Required fields: `file`, `branch`, `commit`, `path`
- Supported formats: PNG, JPEG, WebP
- Max file size: Check with backend (likely 10MB)

### Future Considerations
- Support for production API URL when available
- Handle API versioning (v2 → v3)
- Support for batch upload endpoint if added
- Webhook notifications when processing complete

## Success Criteria
1. ✅ Action successfully uploads images to Railway backend
2. ✅ Action successfully generates comparison reports
3. ✅ Works with any screenshot tool (Playwright, Puppeteer, Cypress, etc.)
4. ✅ Clear error messages for common issues
5. ✅ Published to GitHub Marketplace
6. ✅ Comprehensive documentation
7. ✅ Handles rate limiting gracefully
8. ✅ Provides useful outputs for downstream jobs
9. ✅ No build step required (pure Bash)

## Next Steps for Implementation
1. Create new repo: `godiffy/upload-action`
2. Create the three Bash scripts (`main.sh`, `upload.sh`, `generate-report.sh`)
3. Create `action.yml` with inputs/outputs
4. Test against Railway dev backend
5. Write comprehensive README
6. Create separate demo repository with fully implemented static site examples
7. Publish to GitHub Marketplace
8. Add to Godiffy documentation

