import json
import os
import pg8000
import base64
import boto3
from datetime import datetime
from cors_headers import add_cors_headers


def decode_jwt_payload(token):
    """Decodifica el payload del JWT sin verificar la firma"""
    try:
        # JWT tiene 3 partes separadas por puntos: header.payload.signature
        parts = token.split('.')
        if len(parts) != 3:
            return None
        
        # Decodificar el payload (segunda parte)
        payload = parts[1]
        
        # Agregar padding si es necesario
        padding = 4 - len(payload) % 4
        if padding != 4:
            payload += '=' * padding
        
        # Decodificar base64
        decoded = base64.urlsafe_b64decode(payload)
        return json.loads(decoded)
    except Exception as e:
        print(f"❌ Error decoding JWT: {e}")
        return None


def generate_presigned_url(s3_client, bucket_name, s3_key, expiration=3600):
    """
    Genera una URL presigned para acceder a un objeto en S3
    
    Args:
        s3_client: Cliente boto3 de S3
        bucket_name: Nombre del bucket
        s3_key: Key del objeto en S3
        expiration: Tiempo de expiración en segundos (default: 3600 = 1 hora)
    
    Returns:
        URL presigned o None si hay error
    """
    try:
        if not s3_key or s3_key.strip() == '':
            return None
            
        url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': bucket_name,
                'Key': s3_key
            },
            ExpiresIn=expiration
        )
        return url
    except Exception as e:
        print(f"❌ Error generating presigned URL for {s3_key}: {e}")
        return None


def lambda_handler(event, context):
    # Database configuration
    db_host = os.environ.get("DB_HOST")
    db_name = os.environ.get("DB_NAME", "sensordb")
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD")
    db_port = int(os.environ.get("DB_PORT", "5432"))
    
    # S3 configuration
    raw_images_bucket = os.environ.get("RAW_IMAGES_BUCKET")
    processed_images_bucket = os.environ.get("PROCESSED_IMAGES_BUCKET")
    aws_region = os.environ.get("AWS_REGION", "us-east-1")  # AWS Lambda provides AWS_REGION automatically
    presigned_url_expiration = int(os.environ.get("PRESIGNED_URL_EXPIRATION", "3600"))

    try:
        # Verificar Bearer token
        bearer_token = None
        if 'headers' in event and event['headers']:
            for header_key in event['headers']:
                if header_key.lower() == 'authorization':
                    auth_header = event['headers'][header_key]
                    if auth_header and auth_header.startswith('Bearer '):
                        bearer_token = auth_header[7:]
                    break
        
        if not bearer_token:
            return add_cors_headers({
                "statusCode": 403,
                "body": json.dumps({"error": "Forbidden: Missing authorization token"})
            })
        
        # Decodificar JWT y extraer username (cognito sub)
        jwt_payload = decode_jwt_payload(bearer_token)
        if not jwt_payload:
            return add_cors_headers({
                "statusCode": 403,
                "body": json.dumps({"error": "Forbidden: Invalid token"})
            })
        
        token_sub = jwt_payload.get('sub') or jwt_payload.get('cognito:username')
        if not token_sub:
            return add_cors_headers({
                "statusCode": 403,
                "body": json.dumps({"error": "Forbidden: Invalid token payload"})
            })
        
        # Obtener user_id del query parameter
        user_id = None
        if 'queryStringParameters' in event and event['queryStringParameters'] and 'user_id' in event['queryStringParameters']:
            user_id = event['queryStringParameters']['user_id']

        if not user_id:
            return add_cors_headers({
                "statusCode": 400,
                "body": json.dumps({"error": "Missing required parameter: user_id"})
            })
        
        # Conectar a la base de datos
        conn = pg8000.connect(
            host=db_host,
            database=db_name,
            user=db_user,
            password=db_password,
            port=db_port
        )
        cur = conn.cursor()
        
        # Validar que el cognito_sub del usuario coincida con el token
        cur.execute("SELECT cognito_sub FROM users WHERE userid = %s", (user_id,))
        result = cur.fetchone()
        
        if not result:
            cur.close()
            conn.close()
            return add_cors_headers({
                "statusCode": 404,
                "body": json.dumps({"error": "User not found"})
            })
        
        user_cognito_sub = result[0]
        if user_cognito_sub != token_sub:
            cur.close()
            conn.close()
            return add_cors_headers({
                "statusCode": 403,
                "body": json.dumps({"error": "Forbidden: Token does not match user"})
            })
        
        # Consultar las imágenes del usuario
        cur.execute("""
            SELECT id, raw_s3_key, processed_s3_key, field_status, 
                   analysis_confidence, processed_at, analyzed_at
            FROM drone_images
            WHERE user_id = %s
            ORDER BY processed_at DESC
        """, (user_id,))
        
        rows = cur.fetchall()
        cur.close()
        conn.close()
        
        # Inicializar cliente S3
        s3_client = boto3.client('s3', region_name=aws_region)
        
        # Procesar cada imagen y generar URLs presigned
        images = []
        for row in rows:
            image_id, raw_s3_key, processed_s3_key, field_status, analysis_confidence, processed_at, analyzed_at = row
            
            # Generar URLs presigned para raw y processed
            raw_url = None
            if raw_s3_key and raw_images_bucket:
                raw_url = generate_presigned_url(s3_client, raw_images_bucket, raw_s3_key, presigned_url_expiration)
            
            processed_url = None
            if processed_s3_key and processed_images_bucket:
                processed_url = generate_presigned_url(s3_client, processed_images_bucket, processed_s3_key, presigned_url_expiration)
            
            # Formatear timestamps
            processed_at_iso = processed_at.isoformat() if processed_at else None
            analyzed_at_iso = analyzed_at.isoformat() if analyzed_at else None
            
            images.append({
                "id": image_id,
                "raw_s3_key": raw_s3_key,
                "processed_s3_key": processed_s3_key,
                "raw_url": raw_url,
                "processed_url": processed_url,
                "field_status": field_status,
                "analysis_confidence": float(analysis_confidence) if analysis_confidence else 0.0,
                "processed_at": processed_at_iso,
                "analyzed_at": analyzed_at_iso
            })
        
        # Respuesta exitosa
        response_body = {
            "user_id": user_id,
            "images": images,
            "count": len(images)
        }
        
        print(f"✅ Successfully retrieved {len(images)} images for user {user_id}")
        
        return add_cors_headers({
            "statusCode": 200,
            "body": json.dumps(response_body)
        })
        
    except Exception as e:
        print(f"❌ Error in get_images Lambda: {e}")
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({"error": f"Internal server error: {str(e)}"})
        })
