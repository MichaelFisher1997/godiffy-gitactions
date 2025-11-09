#!/bin/bash
set -e



# Get inputs from action.yml (GitHub Actions sets these as env vars)
# Handle both hyphen and underscore formats for backward compatibility
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
UPLOAD_RESULTS=$(bash "$GITHUB_ACTION_PATH/upload.sh" "$BASE_URL" "$API_KEY" "$SITE_ID" "$BRANCH" "$COMMIT" "$IMAGES_PATH")
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
  
  echo "DEBUG: About to call generate-report.sh with:"
  echo "DEBUG: BASE_URL=$BASE_URL"
  echo "DEBUG: API_KEY=***"
  echo "DEBUG: SITE_ID=$SITE_ID"
  echo "DEBUG: UPLOAD_RESULTS=$UPLOAD_RESULTS"
  echo "DEBUG: BRANCH=$BRANCH"
  echo "DEBUG: COMMIT=$COMMIT"
  echo "DEBUG: BASELINE_BRANCH=$BASELINE_BRANCH"
  echo "DEBUG: BASELINE_COMMIT=$BASELINE_COMMIT"
  echo "DEBUG: REPORT_NAME=$REPORT_NAME"
  echo "DEBUG: REPORT_DESCRIPTION=$REPORT_DESCRIPTION"
  echo "DEBUG: ALGORITHM=$ALGORITHM"
  echo "DEBUG: THRESHOLD=$THRESHOLD"
  
  REPORT_RESULTS=$(bash "$GITHUB_ACTION_PATH/generate-report.sh" \
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