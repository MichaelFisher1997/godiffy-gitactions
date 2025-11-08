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