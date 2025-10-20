#!/usr/bin/env python3
"""
AgroSynchro IoT Consumer
Reads from Redis queue and sends email alerts when sensor data is abnormal
"""

import os
import json
import threading
import time
import boto3
import smtplib
from email.mime.text import MIMEText
from flask import Flask, jsonify, request
from flask_cors import CORS
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# ---------------------
# Environment configuration
# ---------------------
# AWS Configuration
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL")
AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
RAW_IMAGES_BUCKET = os.getenv("RAW_IMAGES_BUCKET")
PROCESSED_IMAGES_BUCKET = os.getenv("PROCESSED_IMAGES_BUCKET")

# Database Configuration
DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = int(os.getenv("DB_PORT", 5432))
DB_USER = os.getenv("DB_USER", "agro")
DB_PASS = os.getenv("DB_PASSWORD", "agro12345")
DB_NAME = os.getenv("DB_NAME", "agrodb")

# Configuración SMTP SendGrid
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", 587))
SMTP_USER = os.getenv("SMTP_USER", "partitba@gmail.com")
SMTP_PASS = os.getenv("SMTP_PASS", "zsxp daba umvz kzar")

ALERT_EMAIL = os.getenv("ALERT_EMAIL", "alertas@agrosynchro.com")

# AWS clients
sqs_client = None
s3_client = None


def get_aws_clients():
    global sqs_client, s3_client
    if sqs_client is None:
        try:
            sqs_client = boto3.client('sqs', region_name=AWS_REGION)
            s3_client = boto3.client('s3', region_name=AWS_REGION)
            logger.info("AWS clients initialized")
        except Exception as e:
            logger.error(f"AWS clients initialization failed: {e}")
            sqs_client = None
            s3_client = None
    return sqs_client, s3_client


# ---------------------
# Mail sender
# ---------------------
def send_email_alert(user_email, user_id, measurement, value, expected_range):
    logger.info("sending mail to: " + user_email)
    subject = f"⚠️ Alerta sensor {user_id}"
    body = (
        f"El sensor {user_id} reportó un valor fuera de rango:\n\n"
        f"- Medición: {measurement}\n"
        f"- Valor recibido: {value}\n"
        f"- Rango esperado: {expected_range}\n\n"
        f"Hora: {datetime.now().isoformat()}"
    )
    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = SMTP_USER
    msg["To"] = user_email

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.sendmail(SMTP_USER, [user_email], msg.as_string())
        logger.info(f"Alert email sent to {user_email}")
    except Exception as e:
        logger.error(f"Failed to send email: {e}")


# ---------------------
# Worker thread
# ---------------------
worker_thread = None
worker_running = False


import psycopg2

from datetime import datetime

DB_PATH = "mock_db.sqlite"

DB_PATH = "mock.db"
DB_HOST = "postgres"  # o el nombre del servicio si estás en Docker Compose
DB_PORT = 5432
DB_USER = "agro"
DB_PASS = "agro1234"
DB_NAME = "agrodb"



def get_user_parameters(user_id):
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS,
        dbname=DB_NAME
    )
    cursor = conn.cursor()

    cursor.execute(
        """
        SELECT temperature, humidity, soil_moisture,
               min_temperature, max_temperature,
               min_humidity, max_humidity,
               min_soil_moisture, max_soil_moisture,
               email
        FROM parameters
        JOIN users ON parameters.user_id = users.id
        WHERE user_id = %s
        """,
        (user_id,),
    )
    row = cursor.fetchone()
    conn.close()
    if row:
        return {
            "temperature": row[0],
            "humidity": row[1],
            "soil_moisture": row[2],
            "min_temperature": row[3],
            "max_temperature": row[4],
            "min_humidity": row[5],
            "max_humidity": row[6],
            "min_soil_moisture": row[7],
            "max_soil_moisture": row[8],
            "email": row[9],
        }
    return None

def insert_sensor_data(user_id, measure, value, timestamp):
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS,
        dbname=DB_NAME
    )
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO sensor_data (user_id, timestamp, measure, value) VALUES (%s, %s, %s, %s)",
        (user_id, timestamp, measure, value),
    )
    conn.commit()
    conn.close()


def worker():
    global worker_running
    sqs, s3 = get_aws_clients()
    if not sqs:
        logger.error("Worker stopped: AWS clients unavailable")
        return

    if not SQS_QUEUE_URL:
        logger.error("Worker stopped: SQS_QUEUE_URL not configured")
        return

    logger.info(f"Worker started, polling SQS queue: {SQS_QUEUE_URL}")
    while worker_running:
        try:
            # Poll SQS for messages with optimized long polling
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20,  # Long polling - SQS notifies immediately when messages arrive
                VisibilityTimeoutSeconds=300  # 5 minutes to process
            )
            
            messages = response.get('Messages', [])
            if not messages:
                logger.debug("No messages received")
                continue
                
            logger.info(f"Received {len(messages)} messages")
            
            for message in messages:
                try:
                    payload = json.loads(message['Body'])
                    
                    user_id = payload.get("user_id")
                    measurements = payload.get("measurements", {})
                    timestamp = payload.get("timestamp", time.strftime("%Y-%m-%d %H:%M:%S"))

                    if not user_id:
                        logger.warning("No user_id in message")
                        continue

                    params = get_user_parameters(user_id)
                    if not params:
                        logger.warning(f"No parameters found for user {user_id}")
                        continue

                    user_email = params["email"]

                    for measurement, value in measurements.items():
                        insert_sensor_data(user_id, measurement, value, timestamp)

                        min_val = params.get(f"min_{measurement}")
                        max_val = params.get(f"max_{measurement}")

                        if min_val is None or max_val is None:
                            continue

                        logger.info(f"Sensor {measurement}: value={value}, min={min_val}, max={max_val}")

                        if value < min_val or value > max_val:
                            logger.info(
                                f"ALERTA: User {user_id} {measurement}={value} fuera de rango {min_val}-{max_val}"
                            )
                            send_email_alert(user_email, user_id, measurement, value, (min_val, max_val))
                    
                    # Delete message from queue after successful processing
                    sqs.delete_message(
                        QueueUrl=SQS_QUEUE_URL,
                        ReceiptHandle=message['ReceiptHandle']
                    )
                    logger.info("Message processed and deleted from queue")
                    
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON in message: {e}")
                except Exception as e:
                    logger.error(f"Error processing message: {e}")

        except Exception as e:
            logger.error(f"Worker error: {e}")
            time.sleep(2)


# ---------------------
# API endpoints
# ---------------------
@app.route("/api/start", methods=["POST"])
def start_worker():
    global worker_thread, worker_running
    if worker_running:
        return jsonify({"success": False, "message": "Worker already running"}), 400

    worker_running = True
    worker_thread = threading.Thread(target=worker, daemon=True)
    worker_thread.start()
    return jsonify({"success": True, "message": "Worker started"})


@app.route("/api/stop", methods=["POST"])
def stop_worker():
    global worker_running
    if not worker_running:
        return jsonify({"success": False, "message": "Worker not running"}), 400
    worker_running = False
    return jsonify({"success": True, "message": "Worker stopping"})


@app.route("/ping", methods=["GET"])
def ping():
    return jsonify({"status": "ok", "service": "iot-consumer", "timestamp": datetime.now().isoformat()})

@app.route("/health", methods=["GET"])
def health():
    """Extended health check with database connectivity"""
    health_data = {
        "status": "ok",
        "service": "processing-engine", 
        "timestamp": datetime.now().isoformat(),
        "database": {"connected": False, "tables": []},
        "s3": {"configured": bool(RAW_IMAGES_BUCKET and PROCESSED_IMAGES_BUCKET)},
        "sqs": {"configured": bool(SQS_QUEUE_URL)}
    }
    
    # Check database connectivity and tables
    try:
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, user=DB_USER, 
            password=DB_PASS, dbname=DB_NAME, connect_timeout=5
        )
        cursor = conn.cursor()
        
        # Check if tables exist
        cursor.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
            ORDER BY table_name
        """)
        tables = [row[0] for row in cursor.fetchall()]
        
        # Count records in drone_images if exists
        drone_images_count = 0
        if 'drone_images' in tables:
            cursor.execute("SELECT COUNT(*) FROM drone_images")
            drone_images_count = cursor.fetchone()[0]
        
        conn.close()
        
        health_data["database"] = {
            "connected": True,
            "tables": tables,
            "drone_images_count": drone_images_count
        }
        
    except Exception as e:
        health_data["database"] = {
            "connected": False,
            "error": str(e)
        }
    
    return jsonify(health_data)


# ---------------------
# Image Processing Functions
# ---------------------
def is_image_processed(s3_key):
    """Verifica si la imagen ya fue procesada"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, user=DB_USER, 
            password=DB_PASS, dbname=DB_NAME
        )
        cursor = conn.cursor()
        cursor.execute("SELECT 1 FROM drone_images WHERE raw_s3_key = %s", (s3_key,))
        result = cursor.fetchone()
        conn.close()
        return result is not None
    except Exception as e:
        logger.error(f"Error checking if image processed: {e}")
        # En caso de error de BD, verificar si existe en S3 processed
        try:
            processed_key = f"processed/{s3_key}"
            s3_client.head_object(Bucket=PROCESSED_IMAGES_BUCKET, Key=processed_key)
            logger.info(f"Image found in processed bucket: {processed_key}")
            return True  # Existe en S3 processed, asumir que fue procesada
        except:
            logger.warning(f"Image not found in processed bucket, will process: {s3_key}")
            return False  # No existe en processed, procesar

def extract_drone_id_from_key(s3_key):
    """Extrae drone_id del path S3"""
    # drone-images/2025/10/19/drone001_uuid.jpg → drone001
    try:
        filename = s3_key.split('/')[-1]
        return filename.split('_')[0]
    except:
        return "unknown"

def simple_image_process(image_bytes):
    """Procesamiento básico de imagen"""
    # Por ahora, solo devolver la imagen original
    # Más adelante: resize, análisis, etc.
    return image_bytes

def analyze_field_condition(image_bytes):
    """Simula análisis de condición del campo basado en imagen"""
    import random
    from datetime import datetime
    
    # Simulación simple basada en "tamaño" de imagen
    image_size = len(image_bytes)
    
    # Lógica simulada de análisis
    conditions = ['excellent', 'good', 'fair', 'poor', 'critical']
    weights = [0.3, 0.35, 0.2, 0.1, 0.05]  # Más probable que sea bueno
    
    # Agregar algo de "inteligencia" basada en hora del día
    hour = datetime.now().hour
    if 6 <= hour <= 18:  # Día - mejor análisis
        weights = [0.4, 0.4, 0.15, 0.04, 0.01]
    else:  # Noche - menos confiable
        weights = [0.2, 0.3, 0.3, 0.15, 0.05]
    
    field_status = random.choices(conditions, weights=weights)[0]
    
    # Confianza simulada (0.0 - 1.0)
    confidence = random.uniform(0.7, 0.95) if field_status in ['excellent', 'good'] else random.uniform(0.6, 0.8)
    
    logger.info(f"🔍 Field analysis: {field_status} (confidence: {confidence:.2f})")
    return field_status, confidence


def save_to_db(drone_id, raw_key, processed_key, field_status=None, confidence=None):
    """Guarda metadatos en RDS"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, user=DB_USER, 
            password=DB_PASS, dbname=DB_NAME
        )
        cursor = conn.cursor()
        
        # Crear tabla si no existe (por seguridad) - versión actualizada
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS drone_images (
                id SERIAL PRIMARY KEY,
                drone_id VARCHAR(255),
                raw_s3_key VARCHAR(500),
                processed_s3_key VARCHAR(500),
                field_status VARCHAR(50) DEFAULT 'unknown',
                analysis_confidence REAL DEFAULT 0.0,
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                analyzed_at TIMESTAMP
            )
        """)
        
        # Insertar registro con análisis
        cursor.execute("""
            INSERT INTO drone_images (drone_id, raw_s3_key, processed_s3_key, field_status, analysis_confidence, analyzed_at) 
            VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        """, (drone_id, raw_key, processed_key, field_status or 'unknown', confidence or 0.0))
        
        conn.commit()
        conn.close()
        logger.info(f"💾 Saved to DB: {drone_id} - Status: {field_status} ({confidence:.2f})")
    except Exception as e:
        logger.error(f"Error saving to DB: {e}")

def process_image_from_s3(s3_key):
    """Descarga, procesa y guarda imagen"""
    try:
        # Extraer drone_id del s3_key
        drone_id = extract_drone_id_from_key(s3_key)
        
        # Descargar imagen
        response = s3_client.get_object(Bucket=RAW_IMAGES_BUCKET, Key=s3_key)
        image_data = response['Body'].read()
        
        # Procesar imagen (resize ejemplo)
        processed_data = simple_image_process(image_data)
        
        # Analizar condición del campo
        field_status, confidence = analyze_field_condition(image_data)
        
        # Subir imagen procesada
        processed_key = f"processed/{s3_key}"
        s3_client.put_object(
            Bucket=PROCESSED_IMAGES_BUCKET,
            Key=processed_key,
            Body=processed_data,
            ContentType='image/jpeg'
        )
        
        # Guardar en RDS con análisis
        save_to_db(drone_id, s3_key, processed_key, field_status, confidence)
        
        # Eliminar imagen raw después de procesamiento exitoso
        try:
            s3_client.delete_object(Bucket=RAW_IMAGES_BUCKET, Key=s3_key)
            logger.info(f"🗑️  Deleted raw image: {s3_key}")
        except Exception as delete_error:
            logger.error(f"⚠️  Warning: Could not delete raw image {s3_key}: {delete_error}")
        
        logger.info(f"✅ Processed image: {s3_key}")
        
    except Exception as e:
        logger.error(f"❌ Error processing {s3_key}: {e}")

def poll_s3_for_images():
    """Revisa S3 bucket por imágenes nuevas"""
    try:
        if not s3_client or not RAW_IMAGES_BUCKET:
            return
            
        # Listar objetos en raw-images bucket
        response = s3_client.list_objects_v2(
            Bucket=RAW_IMAGES_BUCKET,
            Prefix='drone-images/'
        )
        
        objects = response.get('Contents', [])
        logger.debug(f"Found {len(objects)} objects in S3")
        
        for obj in objects:
            s3_key = obj['Key']
            
            # Verificar si ya fue procesada
            if not is_image_processed(s3_key):
                logger.info(f"Processing new image: {s3_key}")
                process_image_from_s3(s3_key)
                
    except Exception as e:
        logger.error(f"Error polling S3: {e}")

def image_polling_worker():
    """Worker thread que revisa S3 cada 30 segundos"""
    global worker_running
    logger.info("Image polling worker started")
    
    while worker_running:
        poll_s3_for_images()
        time.sleep(30)  # Esperar 30 segundos
    
    logger.info("Image polling worker stopped")



def run_startup_migrations():
    """Run database migrations on container startup"""
    try:
        logger.info("🚀 Running startup database migrations...")
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, user=DB_USER, 
            password=DB_PASS, dbname=DB_NAME
        )
        cursor = conn.cursor()
        
        logger.info("Creating users table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                username TEXT NOT NULL,
                email TEXT NOT NULL
            )
        """)
        
        logger.info("Creating parameters table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS parameters (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id),
                temperature REAL,
                humidity REAL,
                soil_moisture REAL,
                min_temperature REAL,
                max_temperature REAL,
                min_humidity REAL,
                max_humidity REAL,
                min_soil_moisture REAL,
                max_soil_moisture REAL
            )
        """)
        
        logger.info("Creating sensor_data table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sensor_data (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id),
                timestamp TIMESTAMP NOT NULL,
                measure TEXT NOT NULL,
                value REAL NOT NULL
            )
        """)
        
        logger.info("Creating drone_images table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS drone_images (
                id SERIAL PRIMARY KEY,
                drone_id VARCHAR(255),
                raw_s3_key VARCHAR(500),
                processed_s3_key VARCHAR(500),
                field_status VARCHAR(50) DEFAULT 'unknown',
                analysis_confidence REAL DEFAULT 0.0,
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                analyzed_at TIMESTAMP
            )
        """)
        
        conn.commit()
        conn.close()
        logger.info("✅ Startup database migrations completed successfully!")
        
    except Exception as e:
        logger.error(f"❌ Startup migration failed: {e}")
        logger.warning("⚠️  Continuing without migrations - tables may not exist")

if __name__ == "__main__":
    logger.info("Starting Processing Engine (SQS + Image processing version)...")
    get_aws_clients()
    
    # Run migrations first
    run_startup_migrations()
    
    # Iniciar worker de imágenes automáticamente
    worker_running = True
    image_worker_thread = threading.Thread(target=image_polling_worker, daemon=True)
    image_worker_thread.start()
    logger.info("Image processing worker started automatically")
    
    app.run(host="0.0.0.0", port=8080, debug=False)
