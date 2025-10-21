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
        body = json.loads(event.get("body") or "{}")
        
        # Soportar ambos formatos: mail (legacy) o cognito_sub + email
        cognito_sub = body.get("cognito_sub")
        email = body.get("email") or body.get("mail")
        name = body.get("name", email.split('@')[0] if email else None)
        
        if not email:
            return add_cors_headers({"statusCode": 400, "body": json.dumps({"error": "email is required"})})

        conn = pg8000.connect(host=db_host, database=db_name, user=db_user, password=db_password, port=db_port)
        cur = conn.cursor()

        # Actualizar tabla para soportar cognito_sub
        cur.execute("""
            CREATE TABLE IF NOT EXISTS users (
                userid SERIAL PRIMARY KEY,
                mail TEXT NOT NULL UNIQUE,
                cognito_sub TEXT UNIQUE,
                name TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)

        # Upsert: insertar si no existe, actualizar si existe
        if cognito_sub:
            cur.execute(
                """
                INSERT INTO users (mail, cognito_sub, name) 
                VALUES (%s, %s, %s)
                ON CONFLICT (mail) 
                DO UPDATE SET 
                    cognito_sub = EXCLUDED.cognito_sub,
                    name = EXCLUDED.name,
                    updated_at = CURRENT_TIMESTAMP
                RETURNING userid, mail, cognito_sub, name;
                """,
                (email, cognito_sub, name),
            )
        else:
            # Legacy: solo mail
            cur.execute(
                """
                INSERT INTO users (mail) VALUES (%s)
                ON CONFLICT (mail) DO NOTHING
                RETURNING userid, mail;
                """,
                (email,),
            )
        
        row = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        if row is None:
            # User already existed (for legacy path)
            return add_cors_headers({"statusCode": 200, "body": json.dumps({"message": "user exists", "email": email})})
        
        if cognito_sub:
            return add_cors_headers({
                "statusCode": 201, 
                "body": json.dumps({
                    "userid": row[0], 
                    "email": row[1],
                    "cognito_sub": row[2],
                    "name": row[3]
                })
            })
        else:
            return add_cors_headers({"statusCode": 201, "body": json.dumps({"userid": row[0], "mail": row[1]})})

    except Exception as e:
        return add_cors_headers({"statusCode": 500, "body": json.dumps({"error": str(e)})})
