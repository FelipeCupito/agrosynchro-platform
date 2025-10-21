import json
import os
import pg8000
from cors_headers import add_cors_headers

def lambda_handler(event, context):
    # Debug: Imprimir el evento recibido
    print("Evento recibido:", json.dumps(event))
    
    # Obtener variables de entorno
    db_host = os.environ.get("DB_HOST")
    db_name = os.environ.get("DB_NAME", "sensordb")
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD")
    db_port = os.environ.get("DB_PORT", "5432")

    if not db_host or not db_password:
        print("❌ Error: Faltan variables de entorno necesarias")
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({
                "error": "Server configuration error",
                "details": "Missing required environment variables"
            })
        })

    try:
        # Conectar a la base
        conn = pg8000.connect(
            host=db_host,
            database=db_name,
            user=db_user,
            password=db_password,
            port=int(db_port),
        )
        cur = conn.cursor()
        
        # Ejecutar consulta
        cur.execute('SELECT userid, mail FROM users ORDER BY userid;')
        rows = cur.fetchall()
        
        # Convertir los resultados a una lista de diccionarios para mejor serialización
        results = [{"id": row[0], "email": row[1]} for row in rows]
        
        # Cerrar conexión
        cur.close()
        conn.close()
        
        # Retornar los datos como JSON con headers CORS
        return add_cors_headers({
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "success": True,
                "data": results
            })
        })

    except pg8000.InterfaceError as e:
        print("❌ Error de conexión a la base de datos:", e)
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({
                "error": "Database connection error",
                "details": str(e)
            })
        })
    except pg8000.ProgrammingError as e:
        print("❌ Error en la consulta SQL:", e)
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({
                "error": "Database query error",
                "details": str(e)
            })
        })
    except Exception as e:
        print("❌ Error inesperado:", e)
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({
                "error": "Internal server error",
                "details": str(e)
            })
        })


        # al final del archivo app.py

if __name__ == "__main__":
    event = {"path": "/users", "httpMethod": "GET"}
    response = lambda_handler(event, None)
    print(json.dumps(response, indent=2))