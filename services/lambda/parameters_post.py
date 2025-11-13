
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

        body = json.loads(event.get("body") or "{}")

        # Permite usar userid o mail para identificar al usuario
        userid = body.get("userid")
        mail = body.get("mail")

        required_fields = [
            "min_temperature",
            "max_temperature",
            "min_humidity",
            "max_humidity",
            "min_soil_moisture",
            "max_soil_moisture"
        ]
        for field in required_fields:
            if body.get(field) is None:
                return add_cors_headers({"statusCode": 400, "body": json.dumps({"error": f"Missing field: {field}"})})

        if userid is None and not mail:
            return add_cors_headers({"statusCode": 400, "body": json.dumps({"error": "Provide userid or mail"})})

        conn = pg8000.connect(host=db_host, database=db_name, user=db_user, password=db_password, port=db_port)
        cur = conn.cursor()

        # Resolver/crear usuario si vino por mail
        if userid is None and mail:
            cur.execute(
                """
                INSERT INTO users (mail) VALUES (%s)
                ON CONFLICT (mail) DO NOTHING
                RETURNING userid;
                """,
                (mail,)
            )
            row_user = cur.fetchone()
            if row_user is None:
                # Obtener userid existente por mail
                cur.execute("SELECT userid FROM users WHERE mail = %s", (mail,))
                row_user = cur.fetchone()
            if row_user is None:
                raise Exception("Failed to resolve userid for provided mail")
            userid = row_user[0]

        # Verificar que el usuario exista cuando viene por userid
        if userid is not None:
            cur.execute("SELECT cognito_sub FROM users WHERE userid = %s", (userid,))
            result = cur.fetchone()
            if result is None:
                cur.close()
                conn.close()
                return add_cors_headers({"statusCode": 404, "body": json.dumps({"error": f"userid {userid} not found"})})
            
            # Validar que el cognito_sub coincida con el token
            db_cognito_sub = result[0]
            if db_cognito_sub != token_sub:
                cur.close()
                conn.close()
                return add_cors_headers({
                    "statusCode": 403,
                    "body": json.dumps({"error": "Forbidden: Token does not match user"})
                })

        # Asegurar índice único por si falta
        cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS uq_parameters_userid ON parameters(userid);")

        # Upsert de parámetros por userid
        cur.execute(
            """
            INSERT INTO parameters (
                userid, min_temperature, max_temperature, min_humidity, max_humidity, min_soil_moisture, max_soil_moisture
            ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (userid) DO UPDATE SET
                min_temperature = EXCLUDED.min_temperature,
                max_temperature = EXCLUDED.max_temperature,
                min_humidity = EXCLUDED.min_humidity,
                max_humidity = EXCLUDED.max_humidity,
                min_soil_moisture = EXCLUDED.min_soil_moisture,
                max_soil_moisture = EXCLUDED.max_soil_moisture
            RETURNING id, userid, min_temperature, max_temperature, min_humidity, max_humidity, min_soil_moisture, max_soil_moisture;
            """,
            (
                userid,
                body["min_temperature"],
                body["max_temperature"],
                body["min_humidity"],
                body["max_humidity"],
                body["min_soil_moisture"],
                body["max_soil_moisture"]
            )
        )
        row = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return add_cors_headers({
            "statusCode": 200,
            "body": json.dumps({
                "id": row[0],
                "userid": row[1],
                "min_temperature": row[2],
                "max_temperature": row[3],
                "min_humidity": row[4],
                "max_humidity": row[5],
                "min_soil_moisture": row[6],
                "max_soil_moisture": row[7]
            })
        })
    except Exception as e:
        return add_cors_headers({"statusCode": 500, "body": json.dumps({"error": str(e)})})
