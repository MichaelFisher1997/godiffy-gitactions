# GoDiffy Action + Demo Context

This file summarizes the current setup and decisions so you can safely reset the conversation without losing context.

## Repositories in this workspace

- Root: `/home/micqdf/github/godiffy-gitactions`
  - Contains:
    - `action.yml` (Node-based GoDiffy action definition)
    - `index.js` (Node implementation entrypoint)
    - `godiffy-github-actions/` (legacy composite/Bash action implementation)
    - `godiffy-github-demo/` (demo app + workflow using the action)

## Target end state (what we actually want)

A simple GitHub Action that:

1. Uploads screenshots to GoDiffy.
2. Optionally creates a visual comparison report on PRs.
3. Uses a fixed, predictable baseline strategy:
   - Baseline branch: `master` (configurable, default `master`).
   - Baseline commit:
     - `latest` = most recent upload on the baseline branch.
4. If there is no suitable baseline yet:
   - Do NOT fail the workflow.
   - Just log a warning and skip report creation.
5. Provides clear outputs for consumers:
   - `report-url`
   - `total-comparisons`
   - `differences-found`

The goal is minimal configuration and no surprising failures.

## Two implementations (current state)

Right now there are effectively two implementations present:

1. Node-based action (preferred)
   - Files:
     - `action.yml` (at repo root)
     - `index.js`
   - Type: JavaScript action using `using: node20`.
   - Behavior:
     - Reads inputs:
       - `api-key`, `site-id`, `images-path`, `base-url`
       - `baseline-branch` (default `master`)
       - `baseline-commit` (default `latest`)
       - `create-report` (default `false`)
       - `algorithm` (default `pixelmatch`)
       - `threshold` (default `0.1`)
     - Uploads all images from `images-path` via `/api/v2/uploads`.
     - If `create-report` is not `true`:
       - Exits successfully after uploads.
     - If `create-report` is `true` on a `pull_request` event:
       - Candidate = `GITHUB_REF_NAME` + `GITHUB_SHA`.
       - Baseline resolution:
         - If `baseline-commit != "latest"`: use that commit directly.
         - If `baseline-commit == "latest"`:
           - GET `/api/v2/uploads?siteId=...`.
           - Filter to `branch == baseline-branch`.
           - Pick newest by `createdAt` → `baselineCommit`.
           - If none found: log warning, exit 0 (skip report).
       - Fetch baseline uploads for `(baseline-branch, baselineCommit)`.
       - Build comparisons matching `objectKey` between baseline and candidate.
       - If no comparisons: log warning, exit 0 (skip report).
       - POST report to `/api/v2/sites/{siteId}/reports`.
       - On success, set outputs:
         - `report-url`
         - `total-comparisons`
         - `differences-found`.

2. Legacy composite/Bash action (transitional)
   - Directory: `godiffy-github-actions/`
   - Key files:
     - `action.yml` (composite)
     - `main.sh`, `upload.sh`, `generate-report.sh`
   - Behavior:
     - `main.sh` calls `upload.sh` and `generate-report.sh`.
     - `generate-report.sh`:
       - Supports `baseline-commit=latest` and picks latest commit on `baseline-branch`.
       - If no baseline is found:
         - Logs a warning and exits 0 (skip report).
       - Builds comparisons by matching `objectKey`.
       - Creates report via API.
     - `main.sh` has been patched to:
       - Call `generate-report.sh`.
       - If it exits 0 with non-JSON output (e.g. only warnings):
         - Treat as "report skipped" and exit 0, without feeding that into `jq`.
       - Only parse report JSON when a report object (with `id`) is returned.

## Demo workflow configuration

- File: `godiffy-github-demo/.github/workflows/screenshots.yml`
- Relevant step (after edits):

```yaml
- name: Upload screenshots and (if PR) create GoDiffy report
  id: godiffy
  uses: MichaelFisher1997/godiffy-gitactions@dev
  with:
    api-key: ${{ secrets.GODIFFY_API_KEY }}
    images-path: './screenshots'
    site-id: '9b85b790-c00e-4cfa-aed8-848617a6dd8d'
    base-url: https://godiffy-backend-dev.up.railway.app
    baseline-branch: master
    baseline-commit: latest
    create-report: ${{ github.event_name == 'pull_request' }}
```

- PR comment step uses:
  - `steps.godiffy.outputs['report-url']`
  - `steps.godiffy.outputs['total-comparisons']`
  - `steps.godiffy.outputs['differences-found']`

## Recommended cleanup path

To fully converge on the simple design:

1. Use the Node-based action at the repo root as the canonical implementation.
2. Gradually retire the `godiffy-github-actions/` composite/Bash implementation once consumers are migrated.
3. Ensure tags/refs (e.g. `@dev`, `@v1`) point to versions where:
   - `action.yml` uses `using: node20` and `index.js`.
   - No external caller is still depending on `main.sh`/`generate-report.sh`.

## Invariants to remember after reset

- Baseline:
  - Keyed by `(baseline-branch, baseline-commit)`.
  - `latest` means: latest upload commit on that branch.
- Candidate:
  - Current branch + commit from GitHub env.
- Missing baseline or comparisons:
  - Never fail the workflow.
  - Only warn and skip report.
- Real errors (upload/report API failures):
  - Should fail the workflow with a clear `::error::` message.

You can now reset the chat. This file is the source of truth for what the current code is intended to do and how the two repos fit together.