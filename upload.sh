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
  
  # Create JSON payload using printf to avoid command line length limits
  JSON_PAYLOAD=$(printf '{
    "siteId": "%s",
    "branch": "%s", 
    "commit": "%s",
    "path": "%s",
    "fileName": "%s",
    "contentType": "%s",
    "data": "%s"
  }' \
    "$SITE_ID" \
    "$BRANCH" \
    "$COMMIT" \
    "$API_PATH" \
    "$FILENAME" \
    "$CONTENT_TYPE" \
    "$BASE64_DATA")
  
  # Upload using JSON with base64 data via temp file
  TEMP_JSON=$(mktemp)
  echo "$JSON_PAYLOAD" > "$TEMP_JSON"
  
  echo "DEBUG: Uploading to $BASE_URL/api/v2/uploads" >&2
  echo "DEBUG: JSON payload: $(head -c 200 "$TEMP_JSON")..." >&2
  
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    --no-cors \
    -d @"$TEMP_JSON" \
    "$BASE_URL/api/v2/uploads")
  
  rm -f "$TEMP_JSON"
  
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
      ERROR_MSG="Invalid JSON response: HTML 405 error"
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