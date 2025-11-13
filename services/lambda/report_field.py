import json
import os
import pg8000
import requests
import base64
from datetime import datetime, timedelta
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
    # --- Obtener parámetros ---
    user_id = None
    query_params = event.get("queryStringParameters") or {}

    if "user_id" in query_params:
        user_id = query_params["user_id"]

    if not user_id:
        return add_cors_headers({
            "statusCode": 400,
            "body": json.dumps({"error": "Missing required parameter: user_id"})
        })

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
    
    # Decodificar JWT y extraer username (cognito sub)
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

    # Obtener fecha del query param (por defecto ayer)
    date_str = query_params.get("date")
    if date_str:
        try:
            target_date = datetime.strptime(date_str, "%Y-%m-%d").date()
        except ValueError:
            return add_cors_headers({
                "statusCode": 400,
                "body": json.dumps({"error": "Invalid date format. Use YYYY-MM-DD"})
            })
    else:
        target_date = datetime.utcnow().date() - timedelta(days=1)

    # --- Configuración de base y API ---
    db_host = os.environ.get("DB_HOST")
    db_name = os.environ.get("DB_NAME", "sensordb")
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD")
    db_port = int(os.environ.get("DB_PORT", "5432"))
    gemini_api_key = os.environ.get("GEMINI_API_KEY", "insert api key here")

    try:
        # Conectar a la base de datos y validar usuario
        conn = pg8000.connect(
            host=db_host, database=db_name, user=db_user, password=db_password, port=db_port
        )
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
        
        # Rango horario del día seleccionado
        start = datetime.combine(target_date, datetime.min.time())
        end = datetime.combine(target_date, datetime.max.time())

        # --- Query a la base (reutilizamos la conexión) ---
        cur.execute(
            """
            SELECT timestamp, temp, hum, soil
            FROM sensor_data
            WHERE userid = %s AND timestamp >= %s AND timestamp <= %s
            ORDER BY timestamp ASC;
            """,
            (user_id, start, end)
        )
        rows = cur.fetchall()
        cur.close()
        conn.close()

        if not rows:
            return add_cors_headers({
                "statusCode": 200,
                "body": json.dumps({"report": f"No hay datos de sensores para la fecha {target_date}."})
            })

        # --- Armar prompt ---
        sensor_data = []
        for ts, temp, hum, soil in rows:
            ts_str = ts.isoformat() if hasattr(ts, "isoformat") else str(ts)
            sensor_data.append(f"{ts_str}: Temp={temp}, Hum={hum}, Soil={soil}")

        prompt = (
            "Eres un agrónomo experto. Analiza los siguientes datos de sensores del campo y genera un informe breve "
            "sobre el estado del campo y recomendaciones. Tendrás datos de la temperatura, humedad y humedad del suelo.\n"
            f"Fecha: {target_date}\n"
            "Datos:\n" + "\n".join(sensor_data)
        )

        # --- Llamar a la API de Gemini ---
        headers = {"Content-Type": "application/json"}
        params = {"key": gemini_api_key}
        payload = {
            "contents": [
                {"parts": [{"text": prompt}]}
            ]
        }

        response = requests.post(
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent",
            headers=headers,
            params=params,
            data=json.dumps(payload)
        )

        if response.status_code != 200:
            return add_cors_headers({
                "statusCode": 500,
                "body": json.dumps({
                    "error": "Error al consultar Gemini",
                    "details": response.text
                })
            })

        result = response.json()
        report = result["candidates"][0]["content"]["parts"][0]["text"]

        # --- Guardar el reporte en DB ---
        conn = pg8000.connect(
            host=db_host,
            database=db_name,
            user=db_user,
            password=db_password,
            port=db_port,
        )
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO reports(userid, time, report) VALUES (%s, %s, %s);
            """,
            (user_id, target_date, report)
        )
        conn.commit()
        cur.close()
        conn.close()

        return add_cors_headers({
            "statusCode": 200,
            "body": json.dumps({"report": report})
        })

    except Exception as e:
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        })