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
from io import BytesIO
from PIL import Image, ImageDraw, ImageFont, ImageEnhance
import numpy as np

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
    subject = f"⚠️ Alerta sensor!"
    body = (
        f"Se reportó un valor fuera de rango:\n\n"
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
        SELECT 
               min_temperature, max_temperature,
               min_humidity, max_humidity,
               min_soil_moisture, max_soil_moisture,
               mail
        FROM parameters
        JOIN users ON parameters.userid = users.userid
        WHERE users.userid = %s
        """,
        (user_id,),
    )
    row = cursor.fetchone()
    conn.close()
    if row:
        return {
            "min_temperature": row[0],
            "max_temperature": row[1],
            "min_humidity": row[2],
            "max_humidity": row[3],
            "min_soil_moisture": row[4],
            "max_soil_moisture": row[5],
            "email": row[6],
        }
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
                        
                        user_id = payload.get("user_id")
                        timestamp = payload.get("timestamp", time.strftime("%Y-%m-%d %H:%M:%S"))
                        hum = payload.get("humidity")
                        temp = payload.get("temperature")
                        soil = payload.get("soil_moisture")

                        if not user_id:
                            logger.warning("No user_id in message, skipping")
                            continue

                        # Convertir valores a float para asegurar comparaciones numéricas
                        logger.info(f"� Converting sensor values to float...")
                        try:
                            hum = float(hum) if hum is not None else None
                            temp = float(temp) if temp is not None else None
                            soil = float(soil) if soil is not None else None
                            logger.info(f"✅ Conversion successful")
                        except (ValueError, TypeError) as e:
                            logger.error(f"❌ Invalid sensor values for user {user_id}: hum={hum}, temp={temp}, soil={soil}. Error: {e}")
                            continue

                        logger.info(f"📊 Sensor values (converted): user_id={user_id}, temp={temp} (type: {type(temp).__name__}), hum={hum} (type: {type(hum).__name__}), soil={soil} (type: {type(soil).__name__})")

                        # Obtener parámetros del usuario
                        logger.info(f"🔍 Fetching parameters for user {user_id}...")
                        parameters = get_user_parameters(user_id)
                        if parameters is None:
                            logger.warning(f"❌ User {user_id} not found in database, skipping message")
                            continue
                        
                        logger.info(f"📋 User parameters retrieved:")
                        logger.info(f"   - Email: {parameters.get('email', 'N/A')}")
                        logger.info(f"   - Temperature range: [{parameters.get('min_temperature', 'N/A')}, {parameters.get('max_temperature', 'N/A')}]")
                        logger.info(f"   - Humidity range: [{parameters.get('min_humidity', 'N/A')}, {parameters.get('max_humidity', 'N/A')}]")
                        logger.info(f"   - Soil moisture range: [{parameters.get('min_soil_moisture', 'N/A')}, {parameters.get('max_soil_moisture', 'N/A')}]")
                        
                        # Verificar alertas - HUMIDITY
                        if hum is not None and parameters.get('min_humidity') is not None and parameters.get('max_humidity') is not None:
                            logger.info(f"🔍 Checking HUMIDITY: {hum} vs range [{parameters['min_humidity']}, {parameters['max_humidity']}]")
                            
                            if hum > parameters['max_humidity']:
                                logger.warning(f"⚠️  HUMIDITY TOO HIGH! {hum} > {parameters['max_humidity']}")
                                logger.info(f"📧 Triggering email alert for HIGH humidity...")
                                send_email_alert(
                                    parameters['email'], user_id, "Humedad", hum,
                                    f"{parameters['min_humidity']} - {parameters['max_humidity']}"
                                )
                            elif hum < parameters['min_humidity']:
                                logger.warning(f"⚠️  HUMIDITY TOO LOW! {hum} < {parameters['min_humidity']}")
                                logger.info(f"📧 Triggering email alert for LOW humidity...")
                                send_email_alert(
                                    parameters['email'], user_id, "Humedad", hum,
                                    f"{parameters['min_humidity']} - {parameters['max_humidity']}"
                                )
                            else:
                                logger.info(f"✅ Humidity within range: {hum}")
                        else:
                            logger.info(f"ℹ️  Skipping humidity check (value or parameters missing)")
                        
                        # Verificar alertas - TEMPERATURE
                        if temp is not None and parameters.get('min_temperature') is not None and parameters.get('max_temperature') is not None:
                            logger.info(f"🔍 Checking TEMPERATURE: {temp} vs range [{parameters['min_temperature']}, {parameters['max_temperature']}]")
                            
                            if temp > parameters['max_temperature']:
                                logger.warning(f"⚠️  TEMPERATURE TOO HIGH! {temp} > {parameters['max_temperature']}")
                                logger.info(f"📧 Triggering email alert for HIGH temperature...")
                                send_email_alert(
                                    parameters['email'], user_id, "Temperatura", temp,
                                    f"{parameters['min_temperature']} - {parameters['max_temperature']}"
                                )
                            elif temp < parameters['min_temperature']:
                                logger.warning(f"⚠️  TEMPERATURE TOO LOW! {temp} < {parameters['min_temperature']}")
                                logger.info(f"📧 Triggering email alert for LOW temperature...")
                                send_email_alert(
                                    parameters['email'], user_id, "Temperatura", temp,
                                    f"{parameters['min_temperature']} - {parameters['max_temperature']}"
                                )
                            else:
                                logger.info(f"✅ Temperature within range: {temp}")
                        else:
                            logger.info(f"ℹ️  Skipping temperature check (value or parameters missing)")
                        
                        # Verificar alertas - SOIL MOISTURE
                        if soil is not None and parameters.get('min_soil_moisture') is not None and parameters.get('max_soil_moisture') is not None:
                            logger.info(f"🔍 Checking SOIL MOISTURE: {soil} vs range [{parameters['min_soil_moisture']}, {parameters['max_soil_moisture']}]")
                            
                            if soil > parameters['max_soil_moisture']:
                                logger.warning(f"⚠️  SOIL MOISTURE TOO HIGH! {soil} > {parameters['max_soil_moisture']}")
                                logger.info(f"📧 Triggering email alert for HIGH soil moisture...")
                                send_email_alert(
                                    parameters['email'], user_id, "Humedad del suelo", soil,
                                    f"{parameters['min_soil_moisture']} - {parameters['max_soil_moisture']}"
                                )
                            elif soil < parameters['min_soil_moisture']:
                                logger.warning(f"⚠️  SOIL MOISTURE TOO LOW! {soil} < {parameters['min_soil_moisture']}")
                                logger.info(f"📧 Triggering email alert for LOW soil moisture...")
                                send_email_alert(
                                    parameters['email'], user_id, "Humedad del suelo", soil,
                                    f"{parameters['min_soil_moisture']} - {parameters['max_soil_moisture']}"
                                )
                            else:
                                logger.info(f"✅ Soil moisture within range: {soil}")
                        else:
                            logger.info(f"ℹ️  Skipping soil moisture check (value or parameters missing)")

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

def extract_user_id_from_key(s3_key):
    """Extrae user_id del path S3"""
    # drone-images/2025/10/19/drone001_uuid.jpg → drone001
    try:
        filename = s3_key.split('/')[-1]
        return filename.split('_')[0]
    except:
        return "unknown"

def detect_fire(image):
    """
    Detecta presencia de fuego basado en análisis de color
    Busca píxeles con tonos naranja/rojo brillante característicos del fuego
    """
    img_array = np.array(image)
    
    # Separar canales RGB
    r = img_array[:, :, 0].astype(float)
    g = img_array[:, :, 1].astype(float)
    b = img_array[:, :, 2].astype(float)
    
    # Criterios para detectar fuego:
    # 1. Rojo alto (> 180)
    # 2. Verde moderado-bajo (< rojo)
    # 3. Azul bajo (< verde)
    # 4. Brillo alto (suma RGB > 400)
    
    fire_mask = (
        (r > 180) &  # Rojo intenso
        (g > 80) & (g < r * 0.8) &  # Verde presente pero menor que rojo
        (b < g * 0.7) &  # Azul mucho menor
        ((r + g + b) > 400)  # Brillo alto
    )
    
    # Calcular porcentaje de píxeles que parecen fuego
    total_pixels = fire_mask.size
    fire_pixels = np.sum(fire_mask)
    fire_percentage = (fire_pixels / total_pixels) * 100
    
    # Detectar regiones contiguas de fuego (clusters)
    fire_detected = fire_percentage > 0.5  # Más de 0.5% de la imagen
    
    return {
        'fire_detected': fire_detected,
        'fire_coverage': round(fire_percentage, 2),
        'fire_mask': fire_mask
    }


def calculate_vegetation_metrics(image):
    """Calcula métricas de vegetación basadas en análisis de color"""
    img_array = np.array(image)
    
    # Separar canales RGB
    r = img_array[:, :, 0].astype(float)
    g = img_array[:, :, 1].astype(float)
    b = img_array[:, :, 2].astype(float)
    
    # Calcular "índice de verdor" simple (más verde = más vegetación)
    # Formula: (Verde - Rojo) / (Verde + Rojo) normalizado
    with np.errstate(divide='ignore', invalid='ignore'):
        green_index = np.where((g + r) > 0, (g - r) / (g + r), 0)
    
    # Normalizar a 0-100
    green_percentage = np.clip(green_index, -1, 1)
    green_percentage = ((green_percentage + 1) / 2) * 100
    
    avg_green = float(np.mean(green_percentage))
    
    # Calcular brillo promedio
    brightness = float(np.mean(img_array))
    
    return {
        'green_coverage': round(avg_green, 1),
        'brightness': round(brightness, 1)
    }


def create_vegetation_heatmap(image, fire_info=None):
    """Crea un overlay SUTIL de mapa de calor sobre zonas verdes y FUEGO"""
    img_array = np.array(image)
    
    # Separar canales
    r = img_array[:, :, 0].astype(float)
    g = img_array[:, :, 1].astype(float)
    b = img_array[:, :, 2].astype(float)
    
    # Detectar píxeles "verdes" (donde verde > rojo y verde > azul)
    green_mask = (g > r * 1.1) & (g > b * 1.1)
    
    # Crear overlay
    overlay = img_array.copy()
    overlay[green_mask] = [0, 200, 0]  # Verde más suave
    
    # Si hay detección de fuego, resaltar en ROJO BRILLANTE
    if fire_info and fire_info['fire_detected']:
        fire_mask = fire_info['fire_mask']
        overlay[fire_mask] = [255, 50, 0]  # ROJO-NARANJA INTENSO para fuego
        logger.warning(f"🔥 FIRE DETECTED IN IMAGE! Coverage: {fire_info['fire_coverage']}%")
    
    # Mezclar original con overlay - MÁS SUTIL (20% overlay normal, 50% si hay fuego)
    blend_factor = 0.5 if (fire_info and fire_info['fire_detected']) else 0.2
    blended = (img_array * (1 - blend_factor) + overlay * blend_factor).astype(np.uint8)
    
    return Image.fromarray(blended)


def add_info_overlay(image, metrics, user_id, fire_info=None):
    """Agrega overlay de información sobre la imagen - TAMAÑO FIJO Y COMPACTO"""
    width, height = image.size
    
    # Intentar cargar fuentes con tamaños fijos
    try:
        font_title = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28)
        font_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
        font_alert = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 32)
    except:
        font_title = ImageFont.load_default()
        font_small = ImageFont.load_default()
        font_alert = ImageFont.load_default()
    
    # OVERLAY SUPERIOR COMPACTO - TAMAÑO FIJO (120px altura)
    overlay_height = 120
    overlay = Image.new('RGBA', image.size, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    overlay_draw.rectangle([(0, 0), (width, overlay_height)], fill=(0, 0, 0, 160))
    
    # Combinar overlay con imagen original
    image = image.convert('RGBA')
    image = Image.alpha_composite(image, overlay)
    image = image.convert('RGB')
    
    draw = ImageDraw.Draw(image)
    
    # Contenido del overlay superior
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    draw.text((15, 10), f"AgroSynchro - Análisis de Campo", fill=(255, 255, 255), font=font_title)
    draw.text((15, 45), f"📅 {timestamp}", fill=(200, 200, 200), font=font_small)
    draw.text((15, 75), f"🌱 Vegetación: {metrics['green_coverage']}%", fill=(100, 255, 100), font=font_small)
    
    # ALERTA DE FUEGO - ESQUINA INFERIOR DERECHA FIJA (si hay fuego)
    if fire_info and fire_info['fire_detected']:
        fire_box_width = 350
        fire_box_height = 80
        fire_x = width - fire_box_width - 15
        fire_y = height - fire_box_height - 15
        
        # Crear overlay rojo semi-transparente
        fire_overlay = Image.new('RGBA', image.size, (0, 0, 0, 0))
        fire_draw = ImageDraw.Draw(fire_overlay)
        fire_draw.rectangle(
            [(fire_x, fire_y), (fire_x + fire_box_width, fire_y + fire_box_height)], 
            fill=(220, 0, 0, 200)
        )
        
        image = image.convert('RGBA')
        image = Image.alpha_composite(image, fire_overlay)
        image = image.convert('RGB')
        
        # Texto de alerta
        fire_draw_final = ImageDraw.Draw(image)
        fire_draw_final.text((fire_x + 10, fire_y + 10), "🔥 FUEGO DETECTADO", fill=(255, 255, 255), font=font_alert)
        fire_draw_final.text((fire_x + 10, fire_y + 50), f"Cobertura: {fire_info['fire_coverage']}%", fill=(255, 255, 0), font=font_small)
    else:
        # Indicador de estado solo si NO hay fuego - ESQUINA INFERIOR DERECHA
        status_box_width = 200
        status_box_height = 50
        status_x = width - status_box_width - 15
        status_y = height - status_box_height - 15
        
        status_color = (100, 255, 100) if metrics['green_coverage'] > 50 else (255, 200, 100) if metrics['green_coverage'] > 30 else (255, 100, 100)
        status_text = "Excelente" if metrics['green_coverage'] > 50 else "Moderado" if metrics['green_coverage'] > 30 else "Bajo"
        
        status_overlay = Image.new('RGBA', image.size, (0, 0, 0, 0))
        status_draw = ImageDraw.Draw(status_overlay)
        status_draw.rectangle(
            [(status_x, status_y), (status_x + status_box_width, status_y + status_box_height)], 
            fill=(0, 0, 0, 160)
        )
        
        image = image.convert('RGBA')
        image = Image.alpha_composite(image, status_overlay)
        image = image.convert('RGB')
        
        status_draw_final = ImageDraw.Draw(image)
        status_draw_final.text((status_x + 10, status_y + 15), f"Estado: {status_text}", fill=status_color, font=font_small)
    
    return image


def simple_image_process(image_bytes):
    """
    Procesamiento de imagen agrícola con análisis visual
    - Detección de FUEGO 🔥
    - Mejora de contraste
    - Mapa de calor de vegetación
    - Overlay de información
    """
    try:
        # Abrir imagen desde bytes
        image = Image.open(BytesIO(image_bytes))
        
        # Convertir a RGB si es necesario
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # 1. DETECTAR FUEGO PRIMERO (crítico)
        fire_info = detect_fire(image)
        if fire_info['fire_detected']:
            logger.warning(f"🔥🔥🔥 FIRE ALERT! Coverage: {fire_info['fire_coverage']}% 🔥🔥🔥")
        
        # 2. Calcular métricas de vegetación
        metrics = calculate_vegetation_metrics(image)
        logger.info(f"📊 Image metrics: {metrics}")
        
        # 3. Mejorar contraste (hace la imagen más "clara")
        enhancer = ImageEnhance.Contrast(image)
        image = enhancer.enhance(1.3)  # 30% más contraste
        
        # 4. Mejorar saturación (hace los colores más vivos)
        enhancer = ImageEnhance.Color(image)
        image = enhancer.enhance(1.2)  # 20% más saturación
        
        # 5. Crear mapa de calor (vegetación + FUEGO)
        image = create_vegetation_heatmap(image, fire_info)
        
        # 6. Agregar overlay de información (incluye alerta de fuego)
        image = add_info_overlay(image, metrics, "user", fire_info)
        
        # 7. Resize a tamaño óptimo (si la imagen es muy grande)
        max_size = 1920  # Full HD
        if max(image.size) > max_size:
            image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
        
        # Convertir de vuelta a bytes
        output = BytesIO()
        image.save(output, format='JPEG', quality=85, optimize=True)
        processed_bytes = output.getvalue()
        
        logger.info(f"✅ Image processed: {len(image_bytes)} bytes → {len(processed_bytes)} bytes")
        
        # Devolver bytes procesados + info de fuego para alertas
        return processed_bytes, fire_info
        
    except Exception as e:
        logger.error(f"❌ Error processing image: {e}")
        # Si falla el procesamiento, devolver original sin info de fuego
        return image_bytes, {'fire_detected': False, 'fire_coverage': 0.0}

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


def save_to_db(user_id, raw_key, processed_key, field_status=None, confidence=None):
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
                user_id VARCHAR(255),
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
            INSERT INTO drone_images (user_id, raw_s3_key, processed_s3_key, field_status, analysis_confidence, analyzed_at) 
            VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        """, (user_id, raw_key, processed_key, field_status or 'unknown', confidence or 0.0))

        conn.commit()
        conn.close()
        logger.info(f"💾 Saved to DB: {user_id} - Status: {field_status} ({confidence:.2f})")
    except Exception as e:
        logger.error(f"Error saving to DB: {e}")

def process_image_from_s3(s3_key):
    """Descarga, procesa y guarda imagen con detección de fuego"""
    try:
        # Extraer user_id del s3_key
        user_id = extract_user_id_from_key(s3_key)
        
        # Descargar imagen
        response = s3_client.get_object(Bucket=RAW_IMAGES_BUCKET, Key=s3_key)
        image_data = response['Body'].read()
        
        # Procesar imagen (INCLUYE DETECCIÓN DE FUEGO)
        processed_data, fire_info = simple_image_process(image_data)
        
        # Analizar condición del campo
        field_status, confidence = analyze_field_condition(image_data)
        
        # Si se detectó fuego, cambiar el field_status
        if fire_info['fire_detected']:
            field_status = 'FIRE_DETECTED'
            confidence = fire_info['fire_coverage'] / 100.0
            logger.warning(f"🔥 Fire detected in image {s3_key}: {fire_info['fire_coverage']}%")
        
        # Subir imagen procesada
        processed_key = f"processed/{s3_key}"
        s3_client.put_object(
            Bucket=PROCESSED_IMAGES_BUCKET,
            Key=processed_key,
            Body=processed_data,
            ContentType='image/jpeg'
        )
        
        # Guardar en RDS con análisis
        save_to_db(user_id, s3_key, processed_key, field_status, confidence)
        
        logger.info(f"✅ Processed image: {s3_key} - Status: {field_status}")
        
    except Exception as e:
        logger.error(f"❌ Error processing {s3_key}: {e}")

def poll_s3_for_images():
    """Revisa S3 bucket por imágenes nuevas"""
    logger.info("Polling S3 for new images...")
    logger.info(f"S3 Client: {s3_client}")
    logger.info(f"RAW_IMAGES_BUCKET: {RAW_IMAGES_BUCKET}")
    try:
        
        if not s3_client or not RAW_IMAGES_BUCKET:
            logger.error("S3 client or RAW_IMAGES_BUCKET not configured")
            return

            
        # Listar objetos en raw-images bucket
        response = s3_client.list_objects_v2(
            Bucket=RAW_IMAGES_BUCKET,
            Prefix='drone-images/'
        )
        
        objects = response.get('Contents', [])
        logger.info(f"Found {len(objects)} objects in S3")
        
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
    logger.info("Image polling For the Worker started")

    
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
                user_id VARCHAR(255),
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