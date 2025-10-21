import json
import os
import pg8000
from cors_headers import add_cors_headers

def lambda_handler(event, context):
    # Obtener user_id y date del parámetro
    user_id = None
    date = None
    if 'queryStringParameters' in event and event['queryStringParameters']:
        user_id = event['queryStringParameters'].get('user_id')
        date = event['queryStringParameters'].get('date')

    db_host = os.environ.get("DB_HOST")
    db_name = os.environ.get("DB_NAME", "sensordb")
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD")
    db_port = int(os.environ.get("DB_PORT", "5432"))

    try:
        conn = pg8000.connect(host=db_host, database=db_name, user=db_user, password=db_password, port=db_port)
        cur = conn.cursor()
        # Consulta básica: filtrar por user_id y date si están presentes
        query = "SELECT time, userid, report FROM reports WHERE 1=1"
        params = []
        if user_id:
            query += " AND userid = %s"
            params.append(user_id)
        if date:
            query += " AND time = %s"
            params.append(date)
        query += " ORDER BY time DESC LIMIT 100;"
        cur.execute(query, tuple(params))
        rows = cur.fetchall()
        cur.close()
        conn.close()
        # Formatear resultados
        result = [
            {"date": str(row[0]), "userid": row[1], "report": row[2]}
            for row in rows
        ]
        return add_cors_headers({
            "statusCode": 200,
            "body": json.dumps({"reports": result})
        })
    except Exception as e:
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        })
