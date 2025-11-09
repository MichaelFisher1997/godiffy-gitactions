#!/bin/bash
set -e

echo "=== SCRIPT STARTED ===" >&2
echo "DEBUG: All environment variables:" >&2
env | grep -E '^(GITHUB_|INPUT_|)' | sort >&2

# Debug trap to catch where script fails
trap 'echo "DEBUG: Script failed at line $LINENO with exit code $?" >&2; echo "DEBUG: Command was: $BASH_COMMAND" >&2' ERR

echo "DEBUG: generate-report.sh started successfully!"
echo "DEBUG: Script started with $# arguments"
echo "DEBUG: Arguments: $*"

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

echo "DEBUG: Starting report generation..."
echo "DEBUG: BASELINE_BRANCH=$BASELINE_BRANCH"
echo "DEBUG: BASELINE_COMMIT=$BASELINE_COMMIT"
echo "DEBUG: CANDIDATE_BRANCH=$CANDIDATE_BRANCH"
echo "DEBUG: CANDIDATE_COMMIT=$CANDIDATE_COMMIT"
echo "DEBUG: SITE_ID=$SITE_ID"
echo "DEBUG: BASE_URL=$BASE_URL"

echo "Fetching baseline uploads from $BASELINE_BRANCH@$BASELINE_COMMIT..."

# Fetch baseline uploads
if [ "$BASELINE_COMMIT" = "latest" ]; then
  echo "DEBUG: Looking for latest uploads on branch $BASELINE_BRANCH" >&2
  # Get uploads for the specific site
  BASELINE_URL="$BASE_URL/api/v2/uploads?siteId=$(printf %s "$SITE_ID" | jq -sRr @uri)"
  echo "DEBUG: Fetching from: $BASELINE_URL" >&2
  
  BASELINE_RESPONSE=$(curl -s \
    -H "Authorization: Bearer $API_KEY" \
    "$BASELINE_URL")
  
  echo "DEBUG: Baseline API response: $BASELINE_RESPONSE" >&2
  
  # Filter by branch and get most recent commit
  BASELINE_COMMIT=$(echo "$BASELINE_RESPONSE" | jq -r --arg branch "$BASELINE_BRANCH" '.[] | select(.branch == $branch) | .commit' | head -n1)
  
  echo "DEBUG: Extracted baseline commit: $BASELINE_COMMIT" >&2
  
  if [ -z "$BASELINE_COMMIT" ]; then
    echo "::error::No uploads found for site $SITE_ID on branch $BASELINE_BRANCH"
    echo "DEBUG: Full API response was: $BASELINE_RESPONSE" >&2
    exit 1
  fi
  
  echo "Using latest commit: $BASELINE_COMMIT"
fi

# Fetch baseline uploads for specific commit
echo "DEBUG: About to fetch baseline uploads..." >&2
BASELINE_URL="$BASE_URL/api/v2/uploads?siteId=$(printf %s "$SITE_ID" | jq -sRr @uri)&branch=$(printf %s "$BASELINE_BRANCH" | jq -sRr @uri)&commit=$(printf %s "$BASELINE_COMMIT" | jq -sRr @uri)"
echo "DEBUG: Baseline URL: $BASELINE_URL" >&2

BASELINE_RESPONSE=$(curl -s \
  -H "Authorization: Bearer $API_KEY" \
  "$BASELINE_URL")

CURL_EXIT_CODE=$?
echo "DEBUG: Curl exit code: $CURL_EXIT_CODE" >&2
echo "DEBUG: Baseline response: $BASELINE_RESPONSE" >&2
echo "DEBUG: About to check CURL_EXIT_CODE: $CURL_EXIT_CODE" >&2

if [ $CURL_EXIT_CODE -ne 0 ]; then
  echo "DEBUG: Curl failed with exit code $CURL_EXIT_CODE" >&2
  exit 1
fi

echo "DEBUG: Passed CURL_EXIT_CODE check, about to process baseline response" >&2

# Handle response structure - API returns direct array
echo "DEBUG: About to process baseline response with jq..."
BASELINE_UPLOADS=$(echo "$BASELINE_RESPONSE" | jq -c '.')
JQ_EXIT_CODE=$?
echo "DEBUG: jq exit code: $JQ_EXIT_CODE" >&2

if [ $JQ_EXIT_CODE -ne 0 ]; then
  echo "DEBUG: jq failed with exit code $JQ_EXIT_CODE" >&2
  echo "DEBUG: Baseline response that failed: $BASELINE_RESPONSE" >&2
  exit 1
fi

echo "DEBUG: About to print baseline uploads..." >&2
echo "DEBUG: Baseline uploads: $BASELINE_UPLOADS" >&2
echo "DEBUG: About to count baseline uploads..." >&2
echo "DEBUG: Baseline uploads count: $(echo "$BASELINE_UPLOADS" | jq '. | length')" >&2
echo "DEBUG: Finished counting baseline uploads..." >&2

# Match candidate uploads with baseline uploads by path
echo "DEBUG: About to print upload results..." >&2
echo "DEBUG: UPLOAD_RESULTS variable is set: ${UPLOAD_RESULTS+yes}" >&2
echo "DEBUG: UPLOAD_RESULTS length: ${#UPLOAD_RESULTS}" >&2
echo "DEBUG: Upload results (first 200 chars): $(echo "$UPLOAD_RESULTS" | head -c 200)..." >&2
echo "DEBUG: Finished printing upload results..." >&2

# Ensure we have valid JSON and array
if echo "$UPLOAD_RESULTS" | jq -e 'has("successful")' >/dev/null 2>&1; then
  CANDIDATE_UPLOADS=$(echo "$UPLOAD_RESULTS" | jq -c '.successful')
else
  echo "DEBUG: Unexpected upload results structure: $UPLOAD_RESULTS"
  CANDIDATE_UPLOADS="[]"
fi

echo "DEBUG: Candidate uploads: $CANDIDATE_UPLOADS"
echo "DEBUG: Candidate uploads count: $(echo "$CANDIDATE_UPLOADS" | jq '. | length')"
echo "DEBUG: About to start comparison loop..."
COMPARISONS=()

while IFS= read -r candidate; do
  echo "DEBUG: Processing candidate: $candidate"
  CANDIDATE_PATH=$(echo "$candidate" | jq -r '.path')
  CANDIDATE_ID=$(echo "$candidate" | jq -r '.id')
  echo "DEBUG: Extracted path: $CANDIDATE_PATH, id: $CANDIDATE_ID"
  
  # Find matching baseline
  BASELINE_ID=$(echo "$BASELINE_UPLOADS" | jq -r --arg path "$CANDIDATE_PATH" '.[] | select(.path == $path) | .id')
  echo "DEBUG: Found baseline ID for path $CANDIDATE_PATH: $BASELINE_ID"
  
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

echo "DEBUG: Total comparisons built: ${#COMPARISONS[@]}"
echo "DEBUG: Comparisons array: $(printf '%s\n' "${COMPARISONS[@]}" | jq -s '.')"

if [ ${#COMPARISONS[@]} -eq 0 ]; then
  echo "::error::No matching baseline images found. Ensure $BASELINE_BRANCH has uploaded screenshots."
  echo "DEBUG: Baseline uploads: $BASELINE_UPLOADS"
  echo "DEBUG: Candidate uploads: $CANDIDATE_UPLOADS"
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