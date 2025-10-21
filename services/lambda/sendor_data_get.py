import json
import os
import pg8000


def lambda_handler(event, context):
    db_host = os.environ.get("DB_HOST")
    db_name = os.environ.get("DB_NAME", "sensordb")
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD")
    db_port = int(os.environ.get("DB_PORT", "5432"))

    try:
        conn = pg8000.connect(host=db_host, database=db_name, user=db_user, password=db_password, port=db_port)
        cur = conn.cursor()
        # Tabla de ejemplo para datos de sensor
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS sensor_data (
                id SERIAL PRIMARY KEY,
                created_at TIMESTAMP DEFAULT NOW(),
                payload JSONB
            );
            """
        )
        cur.execute("SELECT id, created_at, payload FROM sensor_data ORDER BY id DESC LIMIT 100;")
        rows = cur.fetchall()
        colnames = [d[0] for d in cur.description]
        data = [dict(zip(colnames, r)) for r in rows]
        cur.close()
        conn.close()
        return {"statusCode": 200, "body": json.dumps(data, default=str)}
    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
