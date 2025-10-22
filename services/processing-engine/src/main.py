#!/usr/bin/env python3
"""
AgroSynchro IoT Consumer
Processes sensor data messages and drone image jobs from AWS services
"""

import os
import json
import smtplib
import threading
import time
import boto3
import psycopg2
from flask import Flask, jsonify
from flask_cors import CORS
from datetime import datetime
from email.mime.text import MIMEText
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

# Alert configuration (SMTP)
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
# Worker thread
# ---------------------
worker_running = False

def get_user_parameters(user_id):
    """Retrieve threshold configuration and contact email for a user."""
    conn = None
    try:
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
            SELECT 
                p.min_temperature, p.max_temperature,
                p.min_humidity,    p.max_humidity,
                p.min_soil_moisture, p.max_soil_moisture,
                u.mail
            FROM parameters p
            JOIN users u ON p.userid = u.userid
            WHERE p.userid = %s
            """,
            (user_id,)
        )
        row = cursor.fetchone()
        cursor.close()
        if not row:
            return None
        return {
            "min_temperature": to_float(row[0]),
            "max_temperature": to_float(row[1]),
            "min_humidity": to_float(row[2]),
            "max_humidity": to_float(row[3]),
            "min_soil_moisture": to_float(row[4]),
            "max_soil_moisture": to_float(row[5]),
            "email": row[6],
        }
    except Exception as exc:
        logger.error(f"Error fetching user parameters: {exc}")
        return None
    finally:
        if conn:
            conn.close()


def send_email_alert(user_email, user_id, measurement, value, expected_range):
    """Send alert email when sensor value exceeds configured thresholds."""
    recipient = user_email or ALERT_EMAIL
    if not recipient:
        logger.warning("No email recipient available; skipping alert.")
        return

    subject = f"⚠️ Alerta de sensor para usuario {user_id}"
    body = (
        f"El sensor del usuario {user_id} reportó un valor fuera de rango:\n\n"
        f"- Medición: {measurement}\n"
        f"- Valor recibido: {value}\n"
        f"- Rango esperado: {expected_range}\n\n"
        f"Hora: {datetime.now().isoformat()}"
    )
    message = MIMEText(body)
    message["Subject"] = subject
    message["From"] = SMTP_USER
    message["To"] = recipient

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.sendmail(SMTP_USER, [recipient], message.as_string())
        logger.info(f"Alert email sent to {recipient}")
    except Exception as exc:
        logger.error(f"Failed to send alert email: {exc}")


def format_expected_range(min_value, max_value):
    lower = min_value if min_value is not None else "-∞"
    upper = max_value if max_value is not None else "∞"
    return f"{lower} - {upper}"


def is_out_of_range(value, min_value, max_value):
    if value is None:
        return False
    if (min_value is not None) and value < min_value:
        return True
    if (max_value is not None) and value > max_value:
        return True
    return False


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def insert_sensor_data(user_id, timestamp, temperature, humidity, soil_moisture):
    try:
        logger.info(f"🔄 Inserting sensor data: user_id={user_id}, timestamp={timestamp}, temperature={temperature}, humidity={humidity}, soil_moisture={soil_moisture}")
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASS,
            dbname=DB_NAME
        )
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO sensor_data (userid, timestamp, temp, hum, soil) VALUES (%s, %s, %s, %s, %s)",
            (user_id, timestamp, temperature, humidity, soil_moisture),
        )
        conn.commit()
        conn.close()
        logger.info(f"✅ Successfully inserted sensor data for user {user_id}")
    except Exception as e:
        logger.error(f"❌ Failed to insert sensor data: {e}")
        raise


def worker():
    global worker_running
    try:
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
                    VisibilityTimeout=300  # 5 minutes to process
                )
                
                messages = response.get('Messages', [])
                if not messages:
                    logger.debug("No messages received")
                    continue
                    
                logger.info(f"📨 Received {len(messages)} sensor messages")
                
                for message in messages:
                    try:
                        payload = json.loads(message['Body'])
                        logger.info(f"🔍 Processing sensor message: {payload}")
                        
                        user_id = payload.get("user_id") or payload.get("userid")
                        measurements = payload.get("measurements") or {}
                        timestamp = payload.get("timestamp") or measurements.get("timestamp") or time.strftime("%Y-%m-%d %H:%M:%S")

                        temp = payload.get("temperature")
                        if temp is None:
                            temp = measurements.get("temperature")

                        hum = payload.get("humidity")
                        if hum is None:
                            hum = measurements.get("humidity")

                        soil = payload.get("soil_moisture")
                        if soil is None:
                            soil = measurements.get("soil_moisture")

                        temp = to_float(temp)
                        hum = to_float(hum)
                        soil = to_float(soil)

                        if not user_id:
                            logger.warning("No user_id in message, skipping")
                            continue
                        try:
                            db_user_id = int(user_id)
                        except (TypeError, ValueError):
                            logger.error(f"Invalid user_id received: {user_id}")
                            continue

                        logger.info(f"💾 Saving sensor data for user {db_user_id}: temp={temp}, hum={hum}, soil={soil}")

                        insert_sensor_data(db_user_id, timestamp, temp, hum, soil)
                        logger.info(f"✅ Saved sensor data: for user {db_user_id}")

                        parameters = get_user_parameters(db_user_id)
                        if parameters:
                            recipient = parameters.get("email")

                            if is_out_of_range(
                                temp,
                                parameters.get("min_temperature"),
                                parameters.get("max_temperature"),
                            ):
                                send_email_alert(
                                    recipient,
                                    db_user_id,
                                    "temperature",
                                    temp,
                                    format_expected_range(
                                        parameters.get("min_temperature"),
                                        parameters.get("max_temperature"),
                                    ),
                                )

                            if is_out_of_range(
                                hum,
                                parameters.get("min_humidity"),
                                parameters.get("max_humidity"),
                            ):
                                send_email_alert(
                                    recipient,
                                    db_user_id,
                                    "humidity",
                                    hum,
                                    format_expected_range(
                                        parameters.get("min_humidity"),
                                        parameters.get("max_humidity"),
                                    ),
                                )

                            if is_out_of_range(
                                soil,
                                parameters.get("min_soil_moisture"),
                                parameters.get("max_soil_moisture"),
                            ):
                                send_email_alert(
                                    recipient,
                                    db_user_id,
                                    "soil_moisture",
                                    soil,
                                    format_expected_range(
                                        parameters.get("min_soil_moisture"),
                                        parameters.get("max_soil_moisture"),
                                    ),
                                )
                        
                        # Delete message from queue after successful processing
                        sqs.delete_message(
                            QueueUrl=SQS_QUEUE_URL,
                            ReceiptHandle=message['ReceiptHandle']
                        )
                        logger.info("📤 Message processed and deleted from queue")
                        
                    except json.JSONDecodeError as e:
                        logger.error(f"Invalid JSON in message: {e}")
                    except Exception as e:
                        logger.error(f"Error processing message: {e}")

            except Exception as e:
                logger.error(f"Worker error: {e}")
                time.sleep(2)
                
    except Exception as e:
        logger.error(f"❌ Failed to start SQS worker: {e}")
        raise


# ---------------------
# API endpoints
# ---------------------
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
        
        logger.info("Ensuring users table schema...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                userid SERIAL PRIMARY KEY,
                mail TEXT NOT NULL UNIQUE,
                cognito_sub TEXT UNIQUE,
                name TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cursor.execute("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'users' AND column_name = 'id'
                ) AND NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'users' AND column_name = 'userid'
                ) THEN
                    EXECUTE 'ALTER TABLE users RENAME COLUMN id TO userid';
                END IF;
            END
            $$;
        """)
        cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS cognito_sub TEXT UNIQUE;")
        cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS name TEXT;")
        cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;")
        cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;")

        logger.info("Ensuring parameters table schema...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS parameters (
                id SERIAL PRIMARY KEY,
                userid INTEGER NOT NULL REFERENCES users(userid),
                min_temperature REAL,
                max_temperature REAL,
                min_humidity REAL,
                max_humidity REAL,
                min_soil_moisture REAL,
                max_soil_moisture REAL
            )
        """)
        cursor.execute("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'parameters' AND column_name = 'user_id'
                ) AND NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'parameters' AND column_name = 'userid'
                ) THEN
                    EXECUTE 'ALTER TABLE parameters RENAME COLUMN user_id TO userid';
                END IF;
            END
            $$;
        """)
        cursor.execute("ALTER TABLE parameters ADD CONSTRAINT IF NOT EXISTS uq_parameters_userid UNIQUE (userid);")

        logger.info("Ensuring sensor_data table schema...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sensor_data (
                id SERIAL PRIMARY KEY,
                userid INTEGER NOT NULL REFERENCES users(userid),
                timestamp TIMESTAMP NOT NULL,
                measure TEXT NOT NULL,
                value REAL NOT NULL
            )
        """)
        cursor.execute("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'sensor_data' AND column_name = 'user_id'
                ) AND NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'sensor_data' AND column_name = 'userid'
                ) THEN
                    EXECUTE 'ALTER TABLE sensor_data RENAME COLUMN user_id TO userid';
                END IF;
            END
            $$;
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
    
    # Iniciar workers automáticamente
    worker_running = True
    
    # SQS worker for sensor data processing
    try:
        sqs_worker_thread = threading.Thread(target=worker, daemon=True)
        sqs_worker_thread.start()
        logger.info("✅ SQS worker started automatically")
    except Exception as e:
        logger.error(f"❌ Failed to start SQS worker: {e}")
    
    # Image worker for S3 polling
    try:
        image_worker_thread = threading.Thread(target=image_polling_worker, daemon=True)
        image_worker_thread.start()
        logger.info("✅ Image processing worker started automatically")
    except Exception as e:
        logger.error(f"❌ Failed to start image worker: {e}")
    
    app.run(host="0.0.0.0", port=8080, debug=False)
