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
# Worker threads
# ---------------------
worker_thread = None
worker_running = False

image_worker_thread = None
image_worker_running = False


import psycopg2

from datetime import datetime

# Database configuration now uses environment variables from top of file



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


# ---------------------
# Image Processing Functions
# ---------------------

def get_unprocessed_images():
    """Lista imágenes en S3 Raw que no han sido procesadas"""
    try:
        sqs, s3 = get_aws_clients()
        if not s3 or not RAW_IMAGES_BUCKET:
            return []
            
        # Listar objetos en S3 raw images
        response = s3.list_objects_v2(
            Bucket=RAW_IMAGES_BUCKET,
            Prefix='drone-images/'
        )
        
        raw_images = []
        for obj in response.get('Contents', []):
            s3_key = obj['Key']
            # Solo procesar archivos de imagen
            if s3_key.lower().endswith(('.jpg', '.jpeg', '.png')):
                # Verificar si ya fue procesada
                if not is_image_already_processed(s3_key):
                    raw_images.append({
                        'key': s3_key,
                        'last_modified': obj['LastModified'],
                        'size': obj['Size']
                    })
        
        return raw_images
        
    except Exception as e:
        logger.error(f"Error listing unprocessed images: {e}")
        return []

def is_image_already_processed(s3_key):
    """Verificar si una imagen ya fue procesada"""
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
            "SELECT id FROM image_analysis WHERE original_s3_key = %s",
            (s3_key,)
        )
        result = cursor.fetchone()
        conn.close()
        
        return result is not None
        
    except Exception as e:
        logger.error(f"Error checking if image processed: {e}")
        return False  # En caso de error, reintentamos

def process_image(s3_key):
    """Procesar una imagen individual con delay simulado"""
    try:
        sqs, s3 = get_aws_clients()
        if not s3:
            logger.error("S3 client not available")
            return False
            
        logger.info(f"🖼️ Iniciando procesamiento de imagen: {s3_key}")
        
        # 1. Descargar imagen de S3 Raw
        logger.info(f"📥 Descargando imagen desde S3...")
        response = s3.get_object(Bucket=RAW_IMAGES_BUCKET, Key=s3_key)
        image_bytes = response['Body'].read()
        metadata = response.get('Metadata', {})
        
        drone_id = metadata.get('drone_id', 'unknown')
        timestamp = metadata.get('timestamp', datetime.utcnow().isoformat() + 'Z')
        
        logger.info(f"✅ Imagen descargada: {len(image_bytes)} bytes")
        
        # 2. DELAY SIMULADO - Simular procesamiento pesado de IA/ML
        processing_time = 60  # 1 minuto
        logger.info(f"🧠 Procesando imagen con IA (simulado)... esto tomará {processing_time} segundos")
        
        for i in range(0, processing_time, 10):  # Mostrar progreso cada 10s
            time.sleep(10)
            remaining = processing_time - i - 10
            if remaining > 0:
                logger.info(f"⏳ Procesando... {remaining} segundos restantes")
        
        logger.info(f"✅ Procesamiento IA completado")
        
        # 3. Generar análisis simulado
        analysis_result = generate_image_analysis(image_bytes, drone_id, timestamp, s3_key)
        
        # 4. Subir imagen procesada a S3 Processed
        processed_key = s3_key.replace('drone-images/', 'processed-images/')
        
        # Copiar imagen original al bucket procesado
        s3.copy_object(
            CopySource={'Bucket': RAW_IMAGES_BUCKET, 'Key': s3_key},
            Bucket=PROCESSED_IMAGES_BUCKET,
            Key=processed_key,
            MetadataDirective='REPLACE',
            Metadata={
                'processed_at': datetime.utcnow().isoformat() + 'Z',
                'processing_status': 'completed',
                'original_drone_id': drone_id
            }
        )
        
        # 5. Subir análisis JSON
        analysis_key = processed_key.replace('.jpg', '_analysis.json').replace('.png', '_analysis.json').replace('.jpeg', '_analysis.json')
        
        s3.put_object(
            Bucket=PROCESSED_IMAGES_BUCKET,
            Key=analysis_key,
            Body=json.dumps(analysis_result, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"📤 Resultados subidos a S3: {analysis_key}")
        
        # 6. Guardar metadatos en RDS
        save_image_analysis_to_db(drone_id, s3_key, processed_key, analysis_key, analysis_result, timestamp)
        
        logger.info(f"🎉 Procesamiento completo de {s3_key}")
        return True
        
    except Exception as e:
        logger.error(f"❌ Error procesando imagen {s3_key}: {e}")
        return False

def generate_image_analysis(image_bytes, drone_id, timestamp, s3_key):
    """Generar análisis simulado de la imagen"""
    import hashlib
    import random
    
    # Simular análisis más realista
    image_hash = hashlib.md5(image_bytes).hexdigest()
    image_size = len(image_bytes)
    
    # Simular métricas variables pero realistas
    vegetation_index = round(random.uniform(0.3, 0.95), 2)  # NDVI simulado
    crop_health = "healthy" if vegetation_index > 0.6 else "stressed" if vegetation_index > 0.4 else "poor"
    pest_probability = random.uniform(0.0, 0.3)  # Baja probabilidad de plagas
    disease_probability = random.uniform(0.0, 0.2)  # Baja probabilidad de enfermedades
    
    analysis_result = {
        "drone_id": drone_id,
        "timestamp": timestamp,
        "processed_at": datetime.utcnow().isoformat() + 'Z',
        "original_s3_key": s3_key,
        "image_metadata": {
            "hash": image_hash,
            "size_bytes": image_size,
            "format": "JPEG" if s3_key.lower().endswith('.jpg') else "PNG"
        },
        "analysis": {
            "vegetation_index": vegetation_index,
            "crop_health": crop_health,
            "pest_detected": pest_probability > 0.2,
            "pest_confidence": round(pest_probability, 2),
            "disease_detected": disease_probability > 0.15,
            "disease_confidence": round(disease_probability, 2),
            "soil_coverage": round(random.uniform(0.7, 0.95), 2),
            "plant_count_estimate": random.randint(150, 300)
        },
        "recommendations": [],
        "processing_info": {
            "algorithm_version": "1.2.0",
            "processing_time_seconds": 60,
            "confidence_score": round(random.uniform(0.85, 0.98), 2)
        }
    }
    
    # Añadir recomendaciones basadas en el análisis
    if analysis_result["analysis"]["crop_health"] == "stressed":
        analysis_result["recommendations"].append("Revisar niveles de irrigación")
        analysis_result["recommendations"].append("Considerar fertilización adicional")
    
    if analysis_result["analysis"]["pest_detected"]:
        analysis_result["recommendations"].append("Inspección de plagas recomendada")
        
    if analysis_result["analysis"]["disease_detected"]:
        analysis_result["recommendations"].append("Análisis fitosanitario recomendado")
    
    if not analysis_result["recommendations"]:
        analysis_result["recommendations"].append("Cultivo en buen estado - continuar monitoreo regular")
    
    return analysis_result

def save_image_analysis_to_db(drone_id, original_key, processed_key, analysis_key, analysis_data, timestamp):
    """Guardar análisis en base de datos"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASS,
            dbname=DB_NAME
        )
        cursor = conn.cursor()
        
        # Crear tabla si no existe
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS image_analysis (
                id SERIAL PRIMARY KEY,
                drone_id VARCHAR(255),
                original_s3_key TEXT,
                processed_s3_key TEXT,
                analysis_s3_key TEXT,
                analysis_data JSONB,
                vegetation_index DECIMAL(3,2),
                crop_health VARCHAR(50),
                pest_detected BOOLEAN,
                disease_detected BOOLEAN,
                timestamp TIMESTAMP,
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Extraer campos principales para queries fáciles
        analysis = analysis_data.get('analysis', {})
        vegetation_index = analysis.get('vegetation_index', 0.0)
        crop_health = analysis.get('crop_health', 'unknown')
        pest_detected = analysis.get('pest_detected', False)
        disease_detected = analysis.get('disease_detected', False)
        
        cursor.execute(
            """
            INSERT INTO image_analysis 
            (drone_id, original_s3_key, processed_s3_key, analysis_s3_key, analysis_data, 
             vegetation_index, crop_health, pest_detected, disease_detected, timestamp)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (drone_id, original_key, processed_key, analysis_key, json.dumps(analysis_data),
             vegetation_index, crop_health, pest_detected, disease_detected, timestamp)
        )
        
        conn.commit()
        conn.close()
        logger.info(f"💾 Análisis guardado en base de datos para drone {drone_id}")
        
    except Exception as e:
        logger.error(f"❌ Error guardando análisis en DB: {e}")
        raise

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
                        
                        user_id = payload.get("user_id")
                        timestamp = payload.get("timestamp", time.strftime("%Y-%m-%d %H:%M:%S"))
                        hum = payload.get("humidity")
                        temp = payload.get("temperature")
                        soil = payload.get("soil_moisture")

                        if not user_id:
                            logger.warning("No user_id in message, skipping")
                            continue

                        logger.info(f"💾 Saving sensor data for user {user_id}: temp={temp}, hum={hum}, soil={soil}")

                        insert_sensor_data(user_id, timestamp, temp, hum, soil)
                        logger.info(f"✅ Saved sensor data: for user {user_id}")
                        
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

def image_worker():
    """Worker para procesar imágenes cada 2 minutos"""
    global image_worker_running
    
    try:
        logger.info("🖼️ Image worker started - polling S3 every 2 minutes")
        
        while image_worker_running:
            try:
                # Buscar imágenes sin procesar
                unprocessed_images = get_unprocessed_images()
                
                if unprocessed_images:
                    logger.info(f"📸 Found {len(unprocessed_images)} unprocessed images")
                    
                    for image_info in unprocessed_images:
                        if not image_worker_running:  # Check if we should stop
                            break
                            
                        s3_key = image_info['key']
                        logger.info(f"🔄 Processing: {s3_key}")
                        
                        # Procesar imagen (incluye el delay de 1 minuto)
                        success = process_image(s3_key)
                        
                        if success:
                            logger.info(f"✅ Successfully processed: {s3_key}")
                        else:
                            logger.error(f"❌ Failed to process: {s3_key}")
                            
                        # Pequeña pausa entre imágenes para no sobrecargar
                        if image_worker_running:
                            time.sleep(5)
                else:
                    logger.debug("📸 No unprocessed images found")
                    
                # Esperar 2 minutos antes de la próxima verificación
                for i in range(120):  # 2 minutos = 120 segundos
                    if not image_worker_running:
                        break
                    time.sleep(1)
                    
            except Exception as e:
                logger.error(f"Image worker error: {e}")
                time.sleep(30)  # Esperar 30s en caso de error
                
    except Exception as e:
        logger.error(f"❌ Failed to start image worker: {e}")
        raise


# ---------------------
# API endpoints
# ---------------------
@app.route("/api/start", methods=["POST"])
def start_worker():
    global worker_thread, worker_running, image_worker_thread, image_worker_running
    
    messages = []
    
    # Start SQS worker
    if not worker_running:
        worker_running = True
        worker_thread = threading.Thread(target=worker, daemon=True)
        worker_thread.start()
        messages.append("SQS sensor worker started")
    else:
        messages.append("SQS sensor worker already running")
    
    # Start image worker  
    if not image_worker_running:
        image_worker_running = True
        image_worker_thread = threading.Thread(target=image_worker, daemon=True)
        image_worker_thread.start()
        messages.append("Image processing worker started")
    else:
        messages.append("Image processing worker already running")
    
    return jsonify({
        "success": True, 
        "message": " | ".join(messages),
        "workers": {
            "sqs_worker_running": worker_running,
            "image_worker_running": image_worker_running
        }
    })

@app.route("/api/stop", methods=["POST"])
def stop_worker():
    global worker_running, image_worker_running
    
    messages = []
    
    if worker_running:
        worker_running = False
        messages.append("SQS sensor worker stopping")
    
    if image_worker_running:
        image_worker_running = False
        messages.append("Image processing worker stopping")
        
    if not messages:
        return jsonify({"success": False, "message": "No workers running"}), 400
    
    return jsonify({
        "success": True, 
        "message": " | ".join(messages),
        "workers": {
            "sqs_worker_running": worker_running,
            "image_worker_running": image_worker_running
        }
    })

@app.route("/api/status", methods=["GET"])
def worker_status():
    """Status de ambos workers"""
    return jsonify({
        "workers": {
            "sqs_worker_running": worker_running,
            "image_worker_running": image_worker_running
        },
        "timestamp": datetime.now().isoformat()
    })


@app.route("/api/images/analysis", methods=["GET"])
def get_image_analysis():
    """Obtener análisis de imágenes procesadas"""
    try:
        # Parámetros opcionales
        drone_id = request.args.get('drone_id')
        limit = int(request.args.get('limit', 10))
        
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASS,
            dbname=DB_NAME
        )
        cursor = conn.cursor()
        
        # Query base
        query = """
            SELECT id, drone_id, original_s3_key, processed_s3_key, analysis_s3_key,
                   analysis_data, vegetation_index, crop_health, pest_detected, 
                   disease_detected, timestamp, processed_at
            FROM image_analysis
        """
        params = []
        
        # Filtro por drone_id si se especifica
        if drone_id:
            query += " WHERE drone_id = %s"
            params.append(drone_id)
            
        query += " ORDER BY processed_at DESC LIMIT %s"
        params.append(limit)
        
        cursor.execute(query, params)
        results = cursor.fetchall()
        
        analyses = []
        for row in results:
            analyses.append({
                "id": row[0],
                "drone_id": row[1],
                "original_s3_key": row[2],
                "processed_s3_key": row[3],
                "analysis_s3_key": row[4],
                "analysis_data": row[5],  # JSONB field
                "vegetation_index": float(row[6]) if row[6] else None,
                "crop_health": row[7],
                "pest_detected": row[8],
                "disease_detected": row[9],
                "timestamp": row[10].isoformat() if row[10] else None,
                "processed_at": row[11].isoformat() if row[11] else None
            })
        
        conn.close()
        
        return jsonify({
            "success": True,
            "count": len(analyses),
            "analyses": analyses
        })
        
    except Exception as e:
        logger.error(f"Error getting image analysis: {e}")
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

@app.route("/ping", methods=["GET"])
def ping():
    return jsonify({"status": "ok", "service": "processing-engine", "timestamp": datetime.now().isoformat()})

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


@app.route("/api/sensors/average", methods=["GET"])
def get_sensor_averages():
    """Get recent sensor data averages"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, user=DB_USER, 
            password=DB_PASS, dbname=DB_NAME
        )
        cursor = conn.cursor()
        
        # Get last 5 minutes of data for averages
        cursor.execute("""
            SELECT measure, AVG(value) as avg_value, COUNT(*) as count
            FROM sensor_data 
            WHERE timestamp >= NOW() - INTERVAL '5 minutes'
            GROUP BY measure
        """)
        
        results = cursor.fetchall()
        conn.close()
        
        averages = {}
        sensors_count = 0
        for measure, avg_value, count in results:
            averages[measure] = round(float(avg_value), 2)
            sensors_count += count
        
        return jsonify({
            "success": True,
            "data": {
                "timestamp": datetime.now().isoformat(),
                "sensors_count": sensors_count,
                "averages": averages
            }
        })
        
    except Exception as e:
        logger.error(f"Error getting sensor averages: {e}")
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


@app.route("/api/images/analysis", methods=["GET"])
def get_image_analysis():
    """Get recent image analysis results"""
    try:
        limit = request.args.get('limit', 10, type=int)
        
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, user=DB_USER, 
            password=DB_PASS, dbname=DB_NAME
        )
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT drone_id, raw_s3_key, processed_s3_key, field_status, 
                   analysis_confidence, analyzed_at, processed_at
            FROM drone_images 
            WHERE analyzed_at IS NOT NULL
            ORDER BY analyzed_at DESC 
            LIMIT %s
        """, (limit,))
        
        results = cursor.fetchall()
        conn.close()
        
        analyses = []
        for row in results:
            analyses.append({
                "drone_id": row[0],
                "raw_s3_key": row[1],
                "processed_s3_key": row[2],
                "field_status": row[3],
                "analysis_confidence": float(row[4]) if row[4] else 0.0,
                "analyzed_at": row[5].isoformat() if row[5] else None,
                "processed_at": row[6].isoformat() if row[6] else None
            })
        
        return jsonify({
            "success": True,
            "data": analyses,
            "count": len(analyses)
        })
        
    except Exception as e:
        logger.error(f"Error getting image analysis: {e}")
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


@app.route("/api/sensors/data", methods=["GET"])
def get_sensor_data():
    """Get recent sensor data for debugging/testing"""
    try:
        limit = request.args.get('limit', 20, type=int)
        user_id = request.args.get('user_id', None)
        
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, user=DB_USER, 
            password=DB_PASS, dbname=DB_NAME
        )
        cursor = conn.cursor()
        
        if user_id:
            cursor.execute("""
                SELECT user_id, timestamp, measure, value
                FROM sensor_data 
                WHERE user_id = %s
                ORDER BY timestamp DESC 
                LIMIT %s
            """, (user_id, limit))
        else:
            cursor.execute("""
                SELECT user_id, timestamp, measure, value
                FROM sensor_data 
                ORDER BY timestamp DESC 
                LIMIT %s
            """, (limit,))
        
        results = cursor.fetchall()
        conn.close()
        
        data = []
        for row in results:
            data.append({
                "user_id": row[0],
                "timestamp": row[1].isoformat() if row[1] else None,
                "measure": row[2],
                "value": float(row[3]) if row[3] else 0.0
            })
        
        return jsonify({
            "success": True,
            "data": data,
            "count": len(data)
        })
        
    except Exception as e:
        logger.error(f"Error getting sensor data: {e}")
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


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
                userid SERIAL PRIMARY KEY,
                mail   VARCHAR(255) NOT NULL UNIQUE
            );
        """)
        
        logger.info("Creating parameters table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS parameters (
                id SERIAL PRIMARY KEY,
                userid             INTEGER REFERENCES users(userid),
                min_temperature    FLOAT,
                max_temperature    FLOAT,
                min_humidity       FLOAT,
                max_humidity       FLOAT,
                min_soil_moisture  FLOAT,
                max_soil_moisture  FLOAT,
                UNIQUE (userid)
            );
        """)
        
        logger.info("Creating sensor_data table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sensor_data (
                id SERIAL PRIMARY KEY,
                userid     INTEGER REFERENCES users(userid),
                timestamp  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                temp       FLOAT,
                hum        FLOAT,
                soil       FLOAT
                );

        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS reports (
                id SERIAL primary key,
                userid     INTEGER REFERENCES users(userid),
                time  date NOT NULL DEFAULT CURRENT_DATE,
                report text not null,
                unique (userid,  time)
                );
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
