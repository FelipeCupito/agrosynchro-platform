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
                userid SERIAL PRIMARY KEY,
                mail   VARCHAR(255) NOT NULL UNIQUE
            );
        """)
        
        logger.info("Creating parameters table...")
        cursor.execute("""
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
        
        logger.info("Creating sensor_data table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sensor_data (
                id SERIAL PRIMARY KEY,
                userid     INTEGER REFERENCES users(userid),
                timestamp  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                temp       FLOAT,
                hum        FLOAT,
                soil       FLOAT
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
        logger.info("Creating reports table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS reports (
                id SERIAL primary key,
                userid     INTEGER REFERENCES users(userid),
                time  date NOT NULL DEFAULT CURRENT_DATE,
                report text not null,
                unique (userid,  time)
                );
        """)

        conn.commit()
        conn.close()
        logger.info("✅ Database migration completed successfully!")
        
    except Exception as e:
        logger.error(f"❌ Migration failed: {e}")
        exit(1)

if __name__ == "__main__":
    run_migrations()