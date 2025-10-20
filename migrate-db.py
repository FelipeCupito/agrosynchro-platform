#!/usr/bin/env python3
import os
import psycopg2
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database Configuration from environment
DB_HOST = os.getenv("DB_HOST")
DB_PORT = int(os.getenv("DB_PORT", 5432))
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASSWORD")
DB_NAME = os.getenv("DB_NAME")

def run_migrations():
    """Execute database migrations"""
    try:
        logger.info(f"Connecting to database at {DB_HOST}:{DB_PORT}")
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASS,
            dbname=DB_NAME
        )
        cursor = conn.cursor()
        
        logger.info("Creating users table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                username TEXT NOT NULL,
                email TEXT NOT NULL
            )
        """)
        
        logger.info("Creating parameters table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS parameters (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id),
                temperature REAL,
                humidity REAL,
                soil_moisture REAL,
                min_temperature REAL,
                max_temperature REAL,
                min_humidity REAL,
                max_humidity REAL,
                min_soil_moisture REAL,
                max_soil_moisture REAL
            )
        """)
        
        logger.info("Creating sensor_data table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sensor_data (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id),
                timestamp TIMESTAMP NOT NULL,
                measure TEXT NOT NULL,
                value REAL NOT NULL
            )
        """)
        
        logger.info("Creating drone_images table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS drone_images (
                id SERIAL PRIMARY KEY,
                drone_id VARCHAR(255),
                raw_s3_key VARCHAR(500),
                processed_s3_key VARCHAR(500),
                field_status VARCHAR(50) DEFAULT 'unknown',
                analysis_confidence REAL DEFAULT 0.0,
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                analyzed_at TIMESTAMP
            )
        """)
        
        conn.commit()
        conn.close()
        logger.info("✅ Database migration completed successfully!")
        
    except Exception as e:
        logger.error(f"❌ Migration failed: {e}")
        exit(1)

if __name__ == "__main__":
    run_migrations()