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
        mail = body.get("mail")
        if not mail:
            return add_cors_headers({"statusCode": 400, "body": json.dumps({"error": "mail is required"})})

        conn = pg8000.connect(host=db_host, database=db_name, user=db_user, password=db_password, port=db_port)
        cur = conn.cursor()

        cur.execute("""
            CREATE TABLE IF NOT EXISTS users (
                userid SERIAL PRIMARY KEY,
                mail TEXT NOT NULL UNIQUE
            );
        """)

        cur.execute(
            """
            INSERT INTO users (mail) VALUES (%s)
            ON CONFLICT (mail) DO NOTHING
            RETURNING userid, mail;
            """,
            (mail,),
        )
        row = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        if row is None:
            # already existed
            return add_cors_headers({"statusCode": 200, "body": json.dumps({"message": "user exists", "mail": mail})})
        return add_cors_headers({"statusCode": 201, "body": json.dumps({"userid": row[0], "mail": row[1]})})

    except Exception as e:
        return add_cors_headers({"statusCode": 500, "body": json.dumps({"error": str(e)})})
