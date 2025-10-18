"""
Lambda function para procesar uploads de imágenes de drones
Recibe multipart/form-data desde API Gateway y sube a S3
"""

import json
import base64
import boto3
import os
from datetime import datetime
import uuid
import logging

# Configurar logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Cliente S3
s3_client = boto3.client('s3')

# Variables de ambiente
RAW_IMAGES_BUCKET = os.environ.get('RAW_IMAGES_BUCKET')
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'agrosynchro')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def handler(event, context):
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Verificar que el bucket existe
        if not RAW_IMAGES_BUCKET:
            return create_error_response(500, "RAW_IMAGES_BUCKET not configured")
        
        # Parsear el body del request
        body = event.get('body', '')
        is_base64 = event.get('isBase64Encoded', False)
        
        if is_base64:
            body = base64.b64decode(body)
        
        # Extraer headers
        headers = event.get('headers', {})
        content_type = headers.get('content-type', headers.get('Content-Type', ''))
        
        logger.info(f"Content-Type: {content_type}")
        
        # Verificar que es multipart/form-data
        if not content_type.startswith('multipart/form-data'):
            return create_error_response(400, "Content-Type must be multipart/form-data")
        
        # Procesar multipart data
        try:
            parsed_data = parse_multipart_data(body, content_type)
        except Exception as e:
            logger.error(f"Error parsing multipart data: {str(e)}")
            return create_error_response(400, f"Error parsing multipart data: {str(e)}")
        
        # Extraer datos requeridos
        image_data = parsed_data.get('image')
        drone_id = parsed_data.get('drone_id')
        timestamp = parsed_data.get('timestamp')
        
        if not image_data:
            return create_error_response(400, "Missing 'image' field")
        
        if not drone_id:
            return create_error_response(400, "Missing 'drone_id' field")
        
        # Usar timestamp actual si no se proporciona
        if not timestamp:
            timestamp = datetime.utcnow().isoformat() + 'Z'
        
        # Generar nombre único para el archivo
        file_id = str(uuid.uuid4())
        file_extension = get_file_extension(parsed_data.get('image_filename', 'image.jpg'))
        
        # Crear estructura de carpetas por fecha
        date_str = datetime.utcnow().strftime('%Y/%m/%d')
        s3_key = f"drone-images/{date_str}/{drone_id}_{file_id}{file_extension}"
        
        # Subir imagen a S3
        try:
            s3_client.put_object(
                Bucket=RAW_IMAGES_BUCKET,
                Key=s3_key,
                Body=image_data,
                ContentType=get_content_type(file_extension),
                Metadata={
                    'drone_id': drone_id,
                    'timestamp': timestamp,
                    'uploaded_at': datetime.utcnow().isoformat() + 'Z',
                    'environment': ENVIRONMENT
                }
            )
            
            logger.info(f"Successfully uploaded image to s3://{RAW_IMAGES_BUCKET}/{s3_key}")
            
        except Exception as e:
            logger.error(f"Error uploading to S3: {str(e)}")
            return create_error_response(500, f"Error uploading to S3: {str(e)}")
        
        # Respuesta exitosa
        response_body = {
            "success": True,
            "message": "Image uploaded successfully",
            "data": {
                "s3_path": f"s3://{RAW_IMAGES_BUCKET}/{s3_key}",
                "s3_key": s3_key,
                "drone_id": drone_id,
                "timestamp": timestamp,
                "uploaded_at": datetime.utcnow().isoformat() + 'Z'
            }
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_body)
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_error_response(500, f"Internal server error: {str(e)}")

def parse_multipart_data(body, content_type):
    """
    Parse multipart/form-data (simplified version)
    En producción se usaría una librería como python-multipart
    """
    # Extraer boundary del content-type
    boundary = None
    for part in content_type.split(';'):
        if 'boundary=' in part:
            boundary = part.split('boundary=')[1].strip()
            break
    
    if not boundary:
        raise ValueError("No boundary found in Content-Type")
    
    # Convertir a bytes si es string
    if isinstance(body, str):
        body = body.encode('utf-8')
    
    # Split por boundary
    boundary_bytes = f'--{boundary}'.encode('utf-8')
    parts = body.split(boundary_bytes)
    
    result = {}
    
    for part in parts:
        if not part or part == b'--\\r\\n' or part == b'--':
            continue
            
        # Split headers y body
        if b'\\r\\n\\r\\n' in part:
            headers_section, body_section = part.split(b'\\r\\n\\r\\n', 1)
        else:
            continue
            
        headers_text = headers_section.decode('utf-8', errors='ignore')
        
        # Parsear headers
        field_name = None
        filename = None
        
        for line in headers_text.split('\\r\\n'):
            if line.startswith('Content-Disposition'):
                # Extraer name y filename
                if 'name="' in line:
                    name_start = line.find('name="') + 6
                    name_end = line.find('"', name_start)
                    field_name = line[name_start:name_end]
                
                if 'filename="' in line:
                    filename_start = line.find('filename="') + 10
                    filename_end = line.find('"', filename_start)
                    filename = line[filename_start:filename_end]
        
        if field_name:
            # Limpiar body (remover \\r\\n al final)
            body_section = body_section.rstrip(b'\\r\\n')
            
            if field_name == 'image':
                result['image'] = body_section
                if filename:
                    result['image_filename'] = filename
            else:
                # Para campos de texto
                result[field_name] = body_section.decode('utf-8', errors='ignore')
    
    return result

def get_file_extension(filename):
    """Obtener extensión del archivo"""
    if '.' in filename:
        return '.' + filename.split('.')[-1].lower()
    return '.jpg'  # default

def get_content_type(file_extension):
    """Obtener content type basado en extensión"""
    content_types = {
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.png': 'image/png',
        '.gif': 'image/gif',
        '.webp': 'image/webp'
    }
    return content_types.get(file_extension.lower(), 'application/octet-stream')

def create_error_response(status_code, message):
    """Crear respuesta de error estándar"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'success': False,
            'error': message,
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        })
    }