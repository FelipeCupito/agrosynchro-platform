#!/usr/bin/env python3
"""
AgroSynchro IoT Gateway API
Receives sensor data and drone images, queues them to Redis and uploads images to S3
"""
import os
import json
import uuid
import redis
import boto3
from datetime import datetime
from PIL import Image
from io import BytesIO
from flask import Flask, jsonify, request
from flask_cors import CORS
from botocore.exceptions import ClientError
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Environment configuration
REDIS_HOST = os.getenv('REDIS_HOST', 'redis')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', 'agroredispass123')
S3_ENDPOINT = os.getenv('S3_ENDPOINT', 'http://minio:9000')
S3_BUCKET = os.getenv('S3_BUCKET', 'agrosynchro-drone-images')
AWS_ACCESS_KEY_ID = os.getenv('AWS_ACCESS_KEY_ID', 'agrosynchro')
AWS_SECRET_ACCESS_KEY = os.getenv('AWS_SECRET_ACCESS_KEY', 'agrosynchro123')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')

# Initialize Redis connection
redis_client = None
s3_client = None

def get_redis_connection():
    """Get Redis connection with error handling"""
    global redis_client
    if redis_client is None:
        try:
            redis_client = redis.Redis(
                host=REDIS_HOST,
                port=REDIS_PORT,
                password=REDIS_PASSWORD,
                decode_responses=True,
                socket_connect_timeout=5,
                socket_timeout=5
            )
            redis_client.ping()
            logger.info("Redis connection established")
        except Exception as e:
            logger.error(f"Redis connection failed: {e}")
            redis_client = None
    return redis_client

def get_s3_client():
    """Get S3 client with error handling"""
    global s3_client
    if s3_client is None:
        try:
            s3_client = boto3.client(
                's3',
                endpoint_url=S3_ENDPOINT if S3_ENDPOINT else None,
                aws_access_key_id=AWS_ACCESS_KEY_ID,
                aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
                region_name=AWS_REGION
            )
            # Test S3 connection by checking if bucket exists
            try:
                s3_client.head_bucket(Bucket=S3_BUCKET)
            except ClientError as e:
                if e.response['Error']['Code'] == '404':
                    # Bucket doesn't exist, try to create it
                    s3_client.create_bucket(Bucket=S3_BUCKET)
                    logger.info(f"Created S3 bucket: {S3_BUCKET}")
            logger.info("S3 connection established")
        except Exception as e:
            logger.error(f"S3 connection failed: {e}")
            s3_client = None
    return s3_client

@app.route('/ping', methods=['GET'])
def ping():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'service': 'iot-gateway',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/health', methods=['GET'])
def health():
    """Detailed health check endpoint"""
    redis_status = 'connected' if get_redis_connection() else 'disconnected'
    s3_status = 'connected' if get_s3_client() else 'disconnected'
    
    return jsonify({
        'status': 'healthy' if redis_status == 'connected' else 'degraded',
        'service': 'iot-gateway',
        'timestamp': datetime.now().isoformat(),
        'dependencies': {
            'redis': redis_status,
            's3': s3_status
        }
    })

@app.route('/api/sensors/data', methods=['POST'])
def receive_sensor_data():
    """
    Receive sensor data from IoT devices and queue to Redis
    Expected JSON format:
    {
        "user_id": "TEMP_001",
        "timestamp": "2023-12-01T14:30:22Z",
        "measurements": {
            "temperature": 24.5,
            "humidity": 65.2,
            "soil_moisture": 45.3
        }
    }
    """
    try:
        # Validate request
        if not request.is_json:
            return jsonify({
                'success': False,
                'error': 'Content-Type must be application/json'
            }), 400
        
        data = request.get_json()
        
        # Validate required fields
        required_fields = ['user_id', 'timestamp', 'measurements']
        for field in required_fields:
            if field not in data:
                return jsonify({
                    'success': False,
                    'error': f'Missing required field: {field}'
                }), 400
        
        # Validate measurements
        measurements = data['measurements']
        if not isinstance(measurements, dict):
            return jsonify({
                'success': False,
                'error': 'measurements must be an object'
            }), 400
        
        # Validate measurement values are numeric
        for key, value in measurements.items():
            if not isinstance(value, (int, float)):
                return jsonify({
                    'success': False,
                    'error': f'measurement {key} must be numeric'
                }), 400
        
        # Get Redis connection
        redis_conn = get_redis_connection()
        if not redis_conn:
            return jsonify({
                'success': False,
                'error': 'Redis connection not available'
            }), 503
        
        # Add received timestamp
        data['received_at'] = datetime.now().isoformat()
        
        # Queue to Redis
        redis_conn.lpush('sensor_data', json.dumps(data))
        
        logger.info(f"Sensor data queued for sensor {data['user_id']}")
        
        return jsonify({
            'success': True,
            'message': 'Sensor data queued successfully'
        })
    
    except Exception as e:
        logger.error(f"Error processing sensor data: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

@app.route('/api/drones/image', methods=['POST'])
def receive_drone_image():
    """
    Receive drone image, upload to S3, and queue metadata to Redis
    Expected multipart/form-data with:
    - image: Image file (JPEG/PNG)
    - drone_id: Drone identifier
    - timestamp: Capture timestamp (optional, will use current time if not provided)
    """
    try:
        # Validate multipart form data
        if 'image' not in request.files:
            return jsonify({
                'success': False,
                'error': 'No image file provided'
            }), 400
        
        if 'drone_id' not in request.form:
            return jsonify({
                'success': False,
                'error': 'Missing drone_id parameter'
            }), 400
        
        image_file = request.files['image']
        drone_id = request.form['drone_id']
        timestamp = request.form.get('timestamp', datetime.now().isoformat())
        
        # Validate image file
        if image_file.filename == '':
            return jsonify({
                'success': False,
                'error': 'No image file selected'
            }), 400
        
        # Validate image format
        allowed_extensions = {'jpg', 'jpeg', 'png'}
        file_extension = image_file.filename.rsplit('.', 1)[1].lower() if '.' in image_file.filename else ''
        if file_extension not in allowed_extensions:
            return jsonify({
                'success': False,
                'error': 'Invalid image format. Only JPG, JPEG, PNG allowed'
            }), 400
        
        # Get S3 client
        s3 = get_s3_client()
        if not s3:
            return jsonify({
                'success': False,
                'error': 'S3 connection not available'
            }), 503
        
        # Generate unique filename
        file_id = str(uuid.uuid4())
        date_path = datetime.now().strftime('%Y/%m/%d')
        s3_key = f"drone-images/{date_path}/{drone_id}_{file_id}.{file_extension}"
        
        # Validate and process image
        try:
            image = Image.open(image_file)
            # Verify it's a valid image
            image.verify()
            # Reset file pointer after verify
            image_file.seek(0)
        except Exception as e:
            return jsonify({
                'success': False,
                'error': 'Invalid image file'
            }), 400
        
        # Upload to S3
        try:
            s3.upload_fileobj(
                image_file,
                S3_BUCKET,
                s3_key,
                ExtraArgs={'ContentType': f'image/{file_extension}'}
            )
            logger.info(f"Image uploaded to S3: {s3_key}")
        except Exception as e:
            logger.error(f"S3 upload failed: {e}")
            return jsonify({
                'success': False,
                'error': 'Failed to upload image to storage'
            }), 500
        
        # Get Redis connection and queue metadata
        redis_conn = get_redis_connection()
        if not redis_conn:
            # If Redis fails, we should probably delete the S3 object
            # For now, just log the warning
            logger.warning("Redis not available, image uploaded but not queued")
            return jsonify({
                'success': False,
                'error': 'Redis connection not available'
            }), 503
        
        # Create metadata for processing queue
        metadata = {
            'drone_id': drone_id,
            'timestamp': timestamp,
            's3_path': s3_key,
            'received_at': datetime.now().isoformat()
        }
        
        # Queue to Redis
        redis_conn.lpush('drone_data', json.dumps(metadata))
        
        logger.info(f"Drone image processed for drone {drone_id}")
        
        return jsonify({
            'success': True,
            's3_path': s3_key,
            'message': 'Image uploaded and queued successfully'
        })
    
    except Exception as e:
        logger.error(f"Error processing drone image: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

@app.route('/api/status', methods=['GET'])
def get_status():
    """Get gateway status and statistics"""
    try:
        redis_conn = get_redis_connection()
        
        sensor_queue_length = 0
        drone_queue_length = 0
        
        if redis_conn:
            try:
                sensor_queue_length = redis_conn.llen('sensor_data')
                drone_queue_length = redis_conn.llen('drone_data')
            except Exception as e:
                logger.warning(f"Failed to get queue lengths: {e}")
        
        return jsonify({
            'success': True,
            'service': 'iot-gateway',
            'timestamp': datetime.now().isoformat(),
            'queues': {
                'sensor_data': sensor_queue_length,
                'drone_data': drone_queue_length
            },
            'status': {
                'redis': 'connected' if redis_conn else 'disconnected',
                's3': 'connected' if get_s3_client() else 'disconnected'
            }
        })
    
    except Exception as e:
        logger.error(f"Error getting status: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

if __name__ == '__main__':
    logger.info("Starting IoT Gateway...")
    get_redis_connection()
    get_s3_client()
    
    app.run(host='0.0.0.0', port=8081, debug=False)