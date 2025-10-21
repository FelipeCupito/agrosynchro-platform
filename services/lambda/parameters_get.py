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
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "Missing required parameter: user_id"})
            }

        conn = pg8000.connect(host=db_host, database=db_name, user=db_user, password=db_password, port=db_port)
        cur = conn.cursor()

        cur.execute(
            """
            SELECT id, userid, min_temperature, max_temperature, min_humidity, max_humidity, min_soil_moisture, max_soil_moisture
            FROM parameters
            WHERE userid = %s
            ORDER BY id;
            """,
            (user_id,)
        )
        rows = cur.fetchall()
        colnames = [d[0] for d in cur.description]
        data = [dict(zip(colnames, r)) for r in rows]
        cur.close()
        conn.close()

        return add_cors_headers({
            "statusCode": 200,
            "body": json.dumps({"success": True, "data": data})
        })
    except Exception as e:
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        })
