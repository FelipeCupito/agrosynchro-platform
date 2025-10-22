import base64
import json
import logging
import os
import uuid
from datetime import datetime
from email.parser import BytesParser
from email.policy import default

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")

RAW_IMAGES_BUCKET = os.environ.get("RAW_IMAGES_BUCKET")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "agrosynchro")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")


def handler(event, context):
    try:
        logger.info("Received event: %s", json.dumps(event, default=str))

        if not RAW_IMAGES_BUCKET:
            return create_error_response(500, "RAW_IMAGES_BUCKET not configured")

        body = event.get("body", "")
        is_base64 = event.get("isBase64Encoded", False)
        body_bytes = base64.b64decode(body) if is_base64 else body.encode("utf-8")

        headers = event.get("headers", {})
        content_type = headers.get("content-type") or headers.get("Content-Type")
        if not content_type or not content_type.startswith("multipart/form-data"):
            return create_error_response(400, "Content-Type must be multipart/form-data")

        parsed_data = parse_multipart(body_bytes, content_type)

        image_part = parsed_data.get("image")
        drone_id = parsed_data.get("drone_id")
        timestamp = parsed_data.get("timestamp") or datetime.utcnow().isoformat() + "Z"

        if not image_part:
            return create_error_response(400, "Missing 'image' field")
        if not drone_id:
            return create_error_response(400, "Missing 'drone_id' field")

        file_extension = image_part.get("extension", ".jpg")
        file_id = str(uuid.uuid4())
        date_str = datetime.utcnow().strftime("%Y/%m/%d")
        s3_key = f"drone-images/{date_str}/{drone_id}_{file_id}{file_extension}"

        try:
            s3_client.put_object(
                Bucket=RAW_IMAGES_BUCKET,
                Key=s3_key,
                Body=image_part["content"],
                ContentType=image_part["content_type"],
                Metadata={
                    "drone_id": drone_id,
                    "timestamp": timestamp,
                    "uploaded_at": datetime.utcnow().isoformat() + "Z",
                    "environment": ENVIRONMENT,
                    "project": PROJECT_NAME,
                },
            )
        except Exception as exc:
            logger.exception("Error uploading to S3")
            return create_error_response(500, f"Error uploading to S3: {exc}")

        response_body = {
            "success": True,
            "message": "Image uploaded successfully",
            "data": {
                "s3_path": f"s3://{RAW_IMAGES_BUCKET}/{s3_key}",
                "s3_key": s3_key,
                "drone_id": drone_id,
                "timestamp": timestamp,
                "uploaded_at": datetime.utcnow().isoformat() + "Z",
            },
        }

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            },
            "body": json.dumps(response_body),
        }

    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("Unexpected error")
        return create_error_response(500, f"Internal server error: {exc}")


def parse_multipart(body_bytes, content_type):
    """Parse multipart form data using Python standard library."""
    parser = BytesParser(policy=default)
    message_bytes = f"Content-Type: {content_type}\r\n\r\n".encode("utf-8") + body_bytes
    message = parser.parsebytes(message_bytes)

    data = {}

    if not message.is_multipart():
        return data

    for part in message.iter_parts():
        name = part.get_param("name", header="Content-Disposition")
        if not name:
            continue

        filename = part.get_filename()
        if filename:
            extension = os.path.splitext(filename)[1].lower() or ".jpg"
            data["image"] = {
                "content": part.get_payload(decode=True),
                "content_type": part.get_content_type() or guess_content_type(extension),
                "extension": extension,
                "filename": filename,
            }
        else:
            payload = part.get_payload(decode=True)
            data[name] = payload.decode(part.get_content_charset() or "utf-8")

    return data


def guess_content_type(extension):
    mapping = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }
    return mapping.get(extension.lower(), "application/octet-stream")


def create_error_response(status_code, message):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(
            {
                "success": False,
                "error": message,
                "timestamp": datetime.utcnow().isoformat() + "Z",
            }
        ),
    }
