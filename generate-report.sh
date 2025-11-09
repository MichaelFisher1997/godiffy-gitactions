#!/bin/bash
set -e

echo "=== generate-report.sh started ===" >&2

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

echo "Starting report generation..."
echo "BASELINE_BRANCH=$BASELINE_BRANCH"
echo "BASELINE_COMMIT=$BASELINE_COMMIT"
echo "CANDIDATE_BRANCH=$CANDIDATE_BRANCH"
echo "CANDIDATE_COMMIT=$CANDIDATE_COMMIT"

echo "Fetching baseline uploads from $BASELINE_BRANCH@$BASELINE_COMMIT..."

# Fetch baseline uploads
if [ "$BASELINE_COMMIT" = "latest" ]; then
  echo "Looking for latest uploads on branch $BASELINE_BRANCH" >&2

  BASELINE_URL="$BASE_URL/api/v2/uploads?siteId=$(printf %s "$SITE_ID" | jq -sRr @uri)"
  BASELINE_RESPONSE=$(curl -s \
    -H "Authorization: Bearer $API_KEY" \
    "$BASELINE_URL")

  # Detect explicit API error objects (ignore jq failure)
  if echo "$BASELINE_RESPONSE" | jq -e 'type == "object" and has("error")' >/dev/null 2>&1; then
    echo "::error::Failed to fetch baseline uploads for latest commit on branch $BASELINE_BRANCH: $(echo "$BASELINE_RESPONSE" | jq -r '.error')" >&2
    exit 1
  fi

  # Baseline endpoint currently returns ALL uploads for the site.
  # We want the latest commit on the configured baseline branch.
  # NOTE: backend uses "branch" values like "2/merge" for PRs;
  # here we explicitly select only entries matching BASELINE_BRANCH.

  # Safely compute latest commit for the baseline branch from array
  BASELINE_COMMIT=$(echo "$BASELINE_RESPONSE" |
    jq -r --arg branch "$BASELINE_BRANCH" '
      map(select(.branch == $branch))
      | sort_by(.createdAt // "")
      | reverse
      | .[0].commit // empty
    ')


  if [ -z "$BASELINE_COMMIT" ]; then
    echo "::error::No uploads found for site $SITE_ID on branch $BASELINE_BRANCH when resolving latest baseline commit" >&2
    echo "DEBUG: Baseline latest response (no matching branch): $BASELINE_RESPONSE" >&2
    exit 1
  fi

  echo "Using latest commit: $BASELINE_COMMIT"
fi

# Fetch baseline uploads for specific commit
BASELINE_URL="$BASE_URL/api/v2/uploads?siteId=$(printf %s "$SITE_ID" | jq -sRr @uri)&branch=$(printf %s "$BASELINE_BRANCH" | jq -sRr @uri)&commit=$(printf %s "$BASELINE_COMMIT" | jq -sRr @uri)"

BASELINE_RESPONSE=$(curl -s \
  -H "Authorization: Bearer $API_KEY" \
  "$BASELINE_URL")

# Handle response structure - API returns direct array
BASELINE_UPLOADS=$(echo "$BASELINE_RESPONSE" | jq -c '.')

echo "Found $(echo "$BASELINE_UPLOADS" | jq '. | length') baseline uploads"

# Match candidate uploads with baseline uploads by path
# Ensure we have valid JSON and array
if echo "$UPLOAD_RESULTS" | jq -e 'has("successful")' >/dev/null 2>&1; then
  CANDIDATE_UPLOADS=$(echo "$UPLOAD_RESULTS" | jq -c '.successful')
else
  echo "::error::Unexpected upload results structure"
  CANDIDATE_UPLOADS="[]"
fi

echo "Found $(echo "$CANDIDATE_UPLOADS" | jq '. | length') candidate uploads"
COMPARISONS=()

while IFS= read -r candidate; do
  CANDIDATE_PATH=$(echo "$candidate" | jq -r '.objectKey')
  CANDIDATE_ID=$(echo "$candidate" | jq -r '.id')
  
  # Find matching baseline
  BASELINE_ID=$(echo "$BASELINE_UPLOADS" | jq -r --arg path "$CANDIDATE_PATH" '.[] | select(.objectKey == $path) | .id')
  
  if [ -n "$BASELINE_ID" ] && [ "$BASELINE_ID" != "null" ]; then
    echo "Creating comparison for $CANDIDATE_PATH"
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

echo "Built ${#COMPARISONS[@]} comparisons"

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