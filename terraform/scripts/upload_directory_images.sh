#!/bin/bash

# Script para subir múltiples imágenes de un directorio a POST /images
# Usage: ./upload_directory_images.sh <directory> <user_id>

set -e

if [ "$#" -lt 2 ]; then
    echo "❌ Usage: $0 <directory> <user_id>"
    echo ""
    echo "Example:"
    echo "  $0 /path/to/images 1"
    echo ""
    echo "This will upload all .jpg, .jpeg, and .png files from the directory"
    exit 1
fi

DIRECTORY=$1
USER_ID=$2

# Get API Gateway URL from Terraform
API_URL=$(cd .. && terraform output -raw api_gateway_invoke_url 2>/dev/null || echo "")

if [ -z "$API_URL" ]; then
    echo "❌ Could not get API Gateway URL from Terraform"
    exit 1
fi

echo "🚀 Batch Upload Images to POST /images"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Directory: $DIRECTORY"
echo "👤 User ID: $USER_ID"
echo "🔗 API URL: $API_URL/images"
echo ""

# Check if directory exists
if [ ! -d "$DIRECTORY" ]; then
    echo "❌ Error: Directory '$DIRECTORY' not found"
    exit 1
fi

# Count images
TOTAL_IMAGES=$(find "$DIRECTORY" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | wc -l | tr -d ' ')

if [ "$TOTAL_IMAGES" -eq 0 ]; then
    echo "❌ No images found in directory (looking for .jpg, .jpeg, .png)"
    exit 1
fi

echo "📊 Found $TOTAL_IMAGES image(s) to upload"
echo ""

# Counters
SUCCESS_COUNT=0
FAILED_COUNT=0
CURRENT=0

# Process each image
find "$DIRECTORY" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | while read IMAGE_FILE; do
    CURRENT=$((CURRENT + 1))
    FILENAME=$(basename "$IMAGE_FILE")
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$CURRENT/$TOTAL_IMAGES] 📸 Processing: $FILENAME"
    echo ""
    
    # Convert image to base64
    IMAGE_BASE64=$(base64 -i "$IMAGE_FILE" | tr -d '\n')
    
    # Get file size
    FILE_SIZE=$(wc -c < "$IMAGE_FILE" | tr -d ' ')
    echo "   📊 File size: $FILE_SIZE bytes"
    echo "   📊 Base64 size: ${#IMAGE_BASE64} characters"
    
    # Create JSON payload in temporary file
    TEMP_FILE=$(mktemp)
    cat > "$TEMP_FILE" <<EOF
{
  "user_id": "$USER_ID",
  "image": "$IMAGE_BASE64"
}
EOF
    
    echo "   🔄 Uploading..."
    
    # Send POST request using file
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      "$API_URL/images" \
      -H "Content-Type: application/json" \
      -d @"$TEMP_FILE")
    
    # Clean up temp file
    rm -f "$TEMP_FILE"
    
    # Split response body and status code
    HTTP_BODY=$(echo "$RESPONSE" | sed '$d')
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    # Check if successful
    if [ "$HTTP_CODE" = "201" ]; then
        echo "   ✅ SUCCESS - HTTP $HTTP_CODE"
        
        # Extract s3_key from response
        S3_KEY=$(echo "$HTTP_BODY" | jq -r '.data.s3_key' 2>/dev/null || echo "")
        if [ -n "$S3_KEY" ] && [ "$S3_KEY" != "null" ]; then
            echo "   📍 S3 Key: $S3_KEY"
        fi
        
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "   ❌ FAILED - HTTP $HTTP_CODE"
        echo "   Response: $HTTP_BODY" | jq '.' 2>/dev/null || echo "$HTTP_BODY"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
    
    echo ""
    
    # Small delay to avoid rate limiting
    sleep 0.5
done

# Final summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 UPLOAD SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total images: $TOTAL_IMAGES"
echo "✅ Successful: $SUCCESS_COUNT"
echo "❌ Failed: $FAILED_COUNT"
echo ""

if [ "$SUCCESS_COUNT" -gt 0 ]; then
    echo "💡 Images uploaded to S3 and will be processed automatically"
    echo "💡 Check processed images with: GET /images?user_id=$USER_ID"
fi

if [ "$FAILED_COUNT" -eq 0 ]; then
    echo "🎉 All images uploaded successfully!"
    exit 0
else
    echo "⚠️  Some images failed to upload"
    exit 1
fi
