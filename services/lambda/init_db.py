import json
import os
import pg8000

def lambda_handler(event, context):
    """
    Lambda de inicialización: crea las tablas base en RDS PostgreSQL.
    Se ejecuta una sola vez durante el deploy de Terraform.
    """
    db_host = os.environ.get("DB_HOST")
    db_name = os.environ.get("DB_NAME", "sensordb")
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD")
    db_port = int(os.environ.get("DB_PORT", "5432"))

    try:
        # Conectar a la base
        conn = pg8000.connect(
            host=db_host,
            database=db_name,
            user=db_user,
            password=db_password,
            port=db_port,
        )
        cur = conn.cursor()

        # Crear tabla users y asegurar autoincrement en userid
        cur.execute("""
            CREATE TABLE IF NOT EXISTS users (
                userid SERIAL PRIMARY KEY,
                mail   VARCHAR(255) NOT NULL UNIQUE
            );
        """)

        
       
        cur.execute("""
            CREATE TABLE IF NOT EXISTS parameters (
                id SERIAL PRIMARY KEY,
                userid             INTEGER REFERENCES users(userid),
                min_temperature    FLOAT,
                max_temperature    FLOAT,
                min_humidity       FLOAT,
                max_humidity       FLOAT,
                min_soil_moisture  FLOAT,
                max_soil_moisture  FLOAT,
                UNIQUE (userid)
            );
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS sensor_data (
                id SERIAL PRIMARY KEY,
                userid     INTEGER REFERENCES users(userid),
                timestamp  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                temp       FLOAT,
                hum        FLOAT,
                soil       FLOAT
                );
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS reports (
                id SERIAL primary key,
                userid     INTEGER REFERENCES users(userid),
                time  date NOT NULL DEFAULT CURRENT_DATE,
                report text not null,
                unique (userid,  time)
                );
        """)

        conn.commit()

        print("✅ Tablas creadas exitosamente")


        # Cerrar conexión
        cur.close()
        conn.close()

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Database initialized successfully"}),
        }

    except Exception as e:
        print(f"❌ Error inicializando la base: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)}),
        }
