import json
import os
from datetime import datetime

import pg8000

from cors_headers import add_cors_headers


def lambda_handler(event, context):
    """
    Retrieve processed drone image analyses from RDS.
    Supports optional query parameters:
      - limit: integer number of records (default 10, max 100)
      - drone_id: filter by specific drone identifier
    """
    db_host = os.environ.get("DB_HOST")
    db_name = os.environ.get("DB_NAME", "sensordb")
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD")
    db_port = int(os.environ.get("DB_PORT", "5432"))

    if not db_host or not db_password:
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({
                "error": "Database configuration missing",
            })
        })

    params = event.get("queryStringParameters") or {}

    try:
        limit = int(params.get("limit", 10))
        if limit <= 0:
            limit = 10
        limit = min(limit, 100)
    except ValueError:
        return add_cors_headers({
            "statusCode": 400,
            "body": json.dumps({"error": "Invalid limit value"})
        })

    drone_id = params.get("drone_id")

    try:
        conn = pg8000.connect(
            host=db_host,
            database=db_name,
            user=db_user,
            password=db_password,
            port=db_port,
        )
        cursor = conn.cursor()

        base_query = """
            SELECT drone_id, raw_s3_key, processed_s3_key, field_status,
                   analysis_confidence, processed_at, analyzed_at
            FROM drone_images
            WHERE analyzed_at IS NOT NULL
        """
        query_params = []

        if drone_id:
            base_query += " AND drone_id = %s"
            query_params.append(drone_id)

        base_query += " ORDER BY analyzed_at DESC LIMIT %s"
        query_params.append(limit)

        cursor.execute(base_query, tuple(query_params))
        rows = cursor.fetchall()

        cursor.close()
        conn.close()

        records = []
        for row in rows:
            records.append({
                "drone_id": row[0],
                "raw_s3_key": row[1],
                "processed_s3_key": row[2],
                "field_status": row[3],
                "analysis_confidence": float(row[4]) if row[4] is not None else None,
                "processed_at": _to_iso(row[5]),
                "analyzed_at": _to_iso(row[6]),
            })

        return add_cors_headers({
            "statusCode": 200,
            "body": json.dumps({
                "success": True,
                "count": len(records),
                "data": records,
            })
        })

    except Exception as exc:  # pragma: no cover - network/db failures
        return add_cors_headers({
            "statusCode": 500,
            "body": json.dumps({
                "error": "Failed to retrieve drone image analysis",
                "details": str(exc),
            })
        })


def _to_iso(value):
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value if value is None else str(value)
