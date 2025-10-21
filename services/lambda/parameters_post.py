
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
            cur.execute("SELECT 1 FROM users WHERE userid = %s", (userid,))
            if cur.fetchone() is None:
                cur.close()
                conn.close()
                return add_cors_headers({"statusCode": 404, "body": json.dumps({"error": f"userid {userid} not found"})})

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
