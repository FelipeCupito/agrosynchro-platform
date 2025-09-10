#!/usr/bin/env python3
"""
Simple Web Dashboard Backend API with basic ping endpoint
"""
from flask import Flask, jsonify, request
from flask_cors import CORS
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)


app = Flask(__name__)
CORS(app)

@app.route('/ping', methods=['GET'])
def ping():
    return jsonify({
        'status': 'ok',
        'service': 'web-dashboard-backend',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'web-dashboard-backend',
        'timestamp': datetime.now().isoformat()
    })



import psycopg2

from datetime import datetime

DB_PATH = "mock_db.sqlite"

DB_PATH = "mock.db"
DB_HOST = "postgres"  # o el nombre del servicio si estás en Docker Compose
DB_PORT = 5432
DB_USER = "agro"
DB_PASS = "agro123"
DB_NAME = "agrodb"


# --- Init DB ya lo tenés ---
@app.route("/api/initdb", methods=["POST"])
def init_db():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    CREATE TABLE if not exists users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT NOT NULL
)  """)

    cursor.execute("""
CREATE TABLE if not exists parameters (
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

    cursor.execute("""
    CREATE TABLE if not exists sensor_data (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    timestamp TIMESTAMP NOT NULL,
    measure TEXT NOT NULL,
    value REAL NOT NULL
)
""")

    conn.commit()
    conn.close()
    return {"status": "DB initialized with mock data"}


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS    )

# --- Users POST / GET ---
@app.route("/api/users", methods=["POST"])
def add_user():
    data = request.json
    username = data.get("username")
    email = data.get("email")
    if not username or not email:
        return {"error": "username and email required"}, 400

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO users (username, email) VALUES (%s, %s) RETURNING id",
        (username, email)
    )
    user_id = cursor.fetchone()[0]
    conn.commit()
    conn.close()
    return {"id": user_id, "username": username, "email": email}, 201


@app.route("/api/users", methods=["GET"])
def get_users():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT id, username, email FROM users")
    users = [{"id": row[0], "username": row[1], "email": row[2]} for row in cursor.fetchall()]
    conn.close()
    return jsonify(users)


# --- Parameters POST / GET ---
@app.route("/api/parameters", methods=["POST"])
def add_parameters():
    data = request.json
    user_id = data.get("user_id")
    parameters = data.get("parameters", {})

    if not user_id:
        return {"error": "user_id required"}, 400

    min_temperature = max_temperature = None
    min_humidity = max_humidity = None
    min_soil_moisture = max_soil_moisture = None

    if "temperature" in parameters:
        min_temperature = parameters["temperature"].get("min")
        max_temperature = parameters["temperature"].get("max")
    if "humidity" in parameters:
        min_humidity = parameters["humidity"].get("min")
        max_humidity = parameters["humidity"].get("max")
    if "soil_moisture" in parameters:
        min_soil_moisture = parameters["soil_moisture"].get("min")
        max_soil_moisture = parameters["soil_moisture"].get("max")

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO parameters (
            user_id,
            min_temperature, max_temperature,
            min_humidity, max_humidity,
            min_soil_moisture, max_soil_moisture
        ) VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id
    """, (
        user_id,
        min_temperature, max_temperature,
        min_humidity, max_humidity,
        min_soil_moisture, max_soil_moisture
    ))
    param_id = cursor.fetchone()[0]
    conn.commit()
    conn.close()

    return jsonify({
        "id": param_id,
        "user_id": user_id,
        "parameters": parameters
    }), 201


@app.route("/api/parameters", methods=["GET"])
def get_parameters():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT user_id,
               min_temperature, max_temperature,
               min_humidity, max_humidity,
               min_soil_moisture, max_soil_moisture
        FROM parameters
    """)
    params_list = []
    for row in cursor.fetchall():
        params_list.append({
            "user_id": row[0],
            "parameters": {
                "temperature": {"min": row[1], "max": row[2]},
                "humidity": {"min": row[3], "max": row[4]},
                "soil_moisture": {"min": row[5], "max": row[6]}
            }
        })
    conn.close()
    return jsonify(params_list)


# --- Sensor Data POST / GET ---
@app.route("/api/sensor_data", methods=["POST"])
def add_sensor_data():
    data = request.json
    user_id = data.get("user_id")
    measure = data.get("measure")
    value = data.get("value")
    timestamp = data.get("timestamp", datetime.utcnow().isoformat())

    if not all([user_id, measure, value]):
        return {"error": "user_id, measure, value required"}, 400

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO sensor_data (user_id, timestamp, measure, value)
        VALUES (%s, %s, %s, %s) RETURNING id
    """, (user_id, timestamp, measure, value))
    data_id = cursor.fetchone()[0]
    conn.commit()
    conn.close()
    return {"id": data_id, "user_id": user_id, "measure": measure, "value": value}, 201


@app.route("/api/sensor_data", methods=["GET"])
def get_sensor_data():
    user_id = request.args.get("user_id")
    measure = request.args.get("measure")

    conn = get_connection()
    cursor = conn.cursor()

    query = "SELECT id, user_id, timestamp, measure, value FROM sensor_data WHERE 1=1"
    params = []

    if user_id:
        query += " AND user_id=%s"
        params.append(user_id)
    if measure:
        query += " AND measure=%s"
        params.append(measure)

    cursor.execute(query, params)
    results = []
    for row in cursor.fetchall():
        results.append({
            "id": row[0],
            "user_id": row[1],
            "timestamp": row[2],
            "measure": row[3],
            "value": row[4]
        })

    conn.close()
    return jsonify(results)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False)