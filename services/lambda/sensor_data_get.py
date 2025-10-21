import json
import os
import pg8000
from cors_headers import add_cors_headers

def lambda_handler(event, context):
    db_host = os.environ.get("DB_HOST")
    db_name = os.environ.get("DB_NAME", "sensordb")
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD")
    db_port = int(os.environ.get("DB_PORT", "5432"))

    try:
        # Obtener el user_id del query parameter
        user_id = None
        if 'queryStringParameters' in event and event['queryStringParameters'] and 'user_id' in event['queryStringParameters']:
            user_id = event['queryStringParameters']['user_id']

        if not user_id:
            return add_cors_headers({
                "statusCode": 400,
                "body": json.dumps({"error": "Missing required parameter: user_id"})
            })

        conn = pg8000.connect(host=db_host, database=db_name, user=db_user, password=db_password, port=db_port)
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, userid, timestamp, temp, hum, soil
            FROM sensor_data
            WHERE userid = %s
            ORDER BY timestamp DESC;
            """,
            (user_id,)
        )
        rows = cur.fetchall()
        colnames = [d[0] for d in cur.description]
        raw_data = [dict(zip(colnames, r)) for r in rows]

        # Transformar los datos al formato esperado por el frontend
        transformed_data = []
        for row in raw_data:
            timestamp = row['timestamp']
            # Si timestamp es datetime, convertir a string ISO
            if hasattr(timestamp, 'isoformat'):
                timestamp = timestamp.isoformat()
            for measure in ['temp', 'hum', 'soil']:
                if row[measure] is not None:
                    transformed_data.append({
                        'timestamp': timestamp,
                        'measure': measure.upper(),
                        'value': float(row[measure])
                    })

        cur.close()
        conn.close()
        return add_cors_headers({
            "statusCode": 200,
            "body": json.dumps({"success": True, "data": transformed_data})
        })
    except Exception as e:
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        })
