import json
import os
import base64
import boto3
from datetime import datetime
from cors_headers import add_cors_headers



def lambda_handler(event, context):
    # S3 configuration
    raw_images_bucket = os.environ.get("RAW_IMAGES_BUCKET")
    aws_region = os.environ.get("AWS_REGION", "us-east-1")

    try:
        
        # Parsear el body
        if not event.get('body'):
            return add_cors_headers({
                "statusCode": 400,
                "body": json.dumps({"error": "Missing request body"})
            })
        
        try:
            body = json.loads(event['body'])
        except json.JSONDecodeError:
            return add_cors_headers({
                "statusCode": 400,
                "body": json.dumps({"error": "Invalid JSON in request body"})
            })
        
        # Obtener user_id del body
        user_id = body.get('user_id')
        if not user_id:
            return add_cors_headers({
                "statusCode": 400,
                "body": json.dumps({"error": "Missing required parameter: user_id"})
            })
        
        # Obtener la imagen en base64 del body
        image_base64 = body.get('image')
        if not image_base64:
            return add_cors_headers({
                "statusCode": 400,
                "body": json.dumps({"error": "Missing required parameter: image"})
            })
        
        # Verificar que el bucket esté configurado
        if not raw_images_bucket:
            return add_cors_headers({
                "statusCode": 500,
                "body": json.dumps({"error": "S3 bucket not configured"})
            })
        
        # Decodificar la imagen base64
        try:
            # Si viene con el prefijo data:image, quitarlo
            if ',' in image_base64:
                image_base64 = image_base64.split(',')[1]
            
            image_bytes = base64.b64decode(image_base64)
        except Exception as e:
            print(f"❌ Error decoding base64 image: {e}")
            return add_cors_headers({
                "statusCode": 400,
                "body": json.dumps({"error": "Invalid base64 image data"})
            })
        
        # Generar timestamp único
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        
        # Crear el nombre del archivo con formato: user_id_timestamp.jpg
        filename = f"{user_id}_{timestamp}.jpg"
        
        # Crear la key S3 con la estructura de carpetas
        s3_key = f"drone-images/{filename}"
        
        # Subir la imagen a S3
        s3_client = boto3.client('s3', region_name=aws_region)
        
        try:
            s3_client.put_object(
                Bucket=raw_images_bucket,
                Key=s3_key,
                Body=image_bytes,
                ContentType='image/jpeg',
                Metadata={
                    'user_id': str(user_id),
                    'uploaded_at': datetime.now().isoformat()
                }
            )
            
            print(f"✅ Image uploaded successfully: {s3_key}")
            
        except Exception as e:
            print(f"❌ Error uploading to S3: {e}")
            return add_cors_headers({
                "statusCode": 500,
                "body": json.dumps({"error": f"Failed to upload image to S3: {str(e)}"})
            })
        
        # Respuesta exitosa
        response_body = {
            "success": True,
            "message": "Image uploaded successfully",
            "data": {
                "s3_key": s3_key,
                "bucket": raw_images_bucket,
                "filename": filename,
                "uploaded_at": datetime.now().isoformat(),
                "size_bytes": len(image_bytes)
            }
        }
        
        print(f"✅ Successfully uploaded image for user {user_id}: {s3_key}")
        
        return add_cors_headers({
            "statusCode": 201,
            "body": json.dumps(response_body)
        })
        
    except Exception as e:
        print(f"❌ Error in post_image Lambda: {e}")
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({"error": f"Internal server error: {str(e)}"})
        })
