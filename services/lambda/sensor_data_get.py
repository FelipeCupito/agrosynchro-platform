import json
import os
import pg8000
import base64
from cors_headers import add_cors_headers


def decode_jwt_payload(token):
    """Decodifica el payload del JWT sin verificar la firma"""
    try:
        parts = token.split('.')
        if len(parts) != 3:
            return None
        payload = parts[1]
        padding = 4 - len(payload) % 4
        if padding != 4:
            payload += '=' * padding
        decoded = base64.urlsafe_b64decode(payload)
        return json.loads(decoded)
    except Exception as e:
        print(f"❌ Error decoding JWT: {e}")
        return None


def lambda_handler(event, context):
    db_host = os.environ.get("DB_HOST")
    db_name = os.environ.get("DB_NAME", "sensordb")
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD")
    db_port = int(os.environ.get("DB_PORT", "5432"))

    try:
        # Verificar Bearer token
        bearer_token = None
        if 'headers' in event and event['headers']:
            for header_key in event['headers']:
                if header_key.lower() == 'authorization':
                    auth_header = event['headers'][header_key]
                    if auth_header and auth_header.startswith('Bearer '):
                        bearer_token = auth_header[7:]
                    break
        
        if not bearer_token:
            return add_cors_headers({
                "statusCode": 403,
                "body": json.dumps({"error": "Forbidden: Missing authorization token"})
            })
        
        # Decodificar JWT y extraer sub
        jwt_payload = decode_jwt_payload(bearer_token)
        if not jwt_payload:
            return add_cors_headers({
                "statusCode": 403,
                "body": json.dumps({"error": "Forbidden: Invalid token"})
            })
        
        token_sub = jwt_payload.get('sub') or jwt_payload.get('cognito:username')
        if not token_sub:
            return add_cors_headers({
                "statusCode": 403,
                "body": json.dumps({"error": "Forbidden: Invalid token payload"})
            })

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
        
        # Validar que el cognito_sub del usuario coincida con el token
        cur.execute("SELECT cognito_sub FROM users WHERE userid = %s", (user_id,))
        result = cur.fetchone()
        
        if not result:
            cur.close()
            conn.close()
            return add_cors_headers({
                "statusCode": 404,
                "body": json.dumps({"error": "User not found"})
            })
        
        db_cognito_sub = result[0]
        
        if db_cognito_sub != token_sub:
            cur.close()
            conn.close()
            return add_cors_headers({
                "statusCode": 403,
                "body": json.dumps({"error": "Forbidden: Token does not match user"})
            })

        # Si la validación pasa, obtener los datos del sensor
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
