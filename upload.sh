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
  
  echo "Uploading $API_PATH..." >&2
  
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
  
  echo "DEBUG: HTTP_CODE=$HTTP_CODE" >&2
  echo "DEBUG: BODY=$BODY" >&2
  
  if [ "$HTTP_CODE" -eq 200 ]; then
    UPLOAD_ID=$(echo "$BODY" | jq -r '.id')
    SUCCESSFUL+=("$(echo "$BODY" | jq -c '.')")
    echo "✅ Uploaded $API_PATH (ID: $UPLOAD_ID)" >&2
else
    echo "DEBUG: Non-200 response, attempting to parse error..." >&2
    if echo "$BODY" | jq . >/dev/null 2>&1; then
      ERROR_MSG=$(echo "$BODY" | jq -r '.error // "Unknown error"')
    else
      ERROR_MSG="Invalid JSON response: $BODY"
    fi
    FAILED+=("{\"file\":\"$API_PATH\",\"error\":\"$ERROR_MSG\"}")
    echo "::error::❌ Failed to upload $API_PATH: $ERROR_MSG" >&2
  fi
    FAILED+=("{\"file\":\"$API_PATH\",\"error\":\"$ERROR_MSG\"}")
    echo "::error::❌ Failed to upload $API_PATH: $ERROR_MSG"
  fi
done < <(find "$IMAGES_PATH" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) -print0)

# Output JSON results
jq -n \
  --argjson successful "$(printf '%s\n' "${SUCCESSFUL[@]}" | jq -s '.')" \
  --argjson failed "$(printf '%s\n' "${FAILED[@]}" | jq -s '.')" \
  '{successful: $successful, failed: $failed}'