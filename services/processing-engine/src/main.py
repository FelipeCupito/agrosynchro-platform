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
DB_PASS = os.getenv("DB_PASSWORD", "agro123")
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
            # Poll SQS for messages
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20,  # Long polling
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



if __name__ == "__main__":
    logger.info("Starting Processing Engine (SQS version)...")
    get_aws_clients()
    app.run(host="0.0.0.0", port=8080, debug=False)
