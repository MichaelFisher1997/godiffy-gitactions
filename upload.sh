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
  
  # Get file info
  FILENAME=$(basename "$file")
  CONTENT_TYPE=$(file -b --mime-type "$file")
  
  echo "Uploading $API_PATH..." >&2
  
  # Encode image as base64
  BASE64_DATA=$(base64 -w 0 "$file")
  
  # Create JSON payload
  JSON_PAYLOAD=$(jq -n \
    --arg siteId "$SITE_ID" \
    --arg branch "$BRANCH" \
    --arg commit "$COMMIT" \
    --arg path "$API_PATH" \
    --arg fileName "$FILENAME" \
    --arg contentType "$CONTENT_TYPE" \
    --arg data "$BASE64_DATA" \
    '{
      siteId: $siteId,
      branch: $branch,
      commit: $commit,
      path: $path,
      fileName: $fileName,
      contentType: $contentType,
      data: $data
    }')
  
  # Upload using JSON with base64 data
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" \
    "$BASE_URL/api/v2/uploads")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')
  
  if [ "$HTTP_CODE" -eq 201 ]; then
    UPLOAD_ID=$(echo "$BODY" | jq -r '.upload.id')
    SUCCESSFUL+=("$(echo "$BODY" | jq -c '.upload')")
    echo "✅ Uploaded $API_PATH (ID: $UPLOAD_ID)" >&2
else
    if echo "$BODY" | jq . >/dev/null 2>&1; then
      ERROR_MSG=$(echo "$BODY" | jq -r '.error // "Unknown error"')
    else
      ERROR_MSG="Invalid JSON response: $BODY"
    fi
    FAILED+=("{\"file\":\"$API_PATH\",\"error\":\"$ERROR_MSG\"}")
    echo "::error::❌ Failed to upload $API_PATH: $ERROR_MSG" >&2
  fi
done < <(find "$IMAGES_PATH" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) -print0)

# Output JSON results
jq -n \
  --argjson successful "$(printf '%s\n' "${SUCCESSFUL[@]}" | jq -s '.')" \
  --argjson failed "$(printf '%s\n' "${FAILED[@]}" | jq -s '.')" \
  '{successful: $successful, failed: $failed}'