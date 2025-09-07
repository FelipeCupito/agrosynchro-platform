#!/usr/bin/env python3

import os
import json
import random
import threading
import time
import requests
from datetime import datetime
from io import BytesIO
from PIL import Image
from flask import Flask, jsonify, request
from flask_cors import CORS
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Environment configuration
IOT_GATEWAY_URL = os.getenv('IOT_GATEWAY_URL', 'http://iot-gateway:8081')
MOCK_INTERVAL_SENSORS = int(os.getenv('MOCK_INTERVAL_SENSORS', 30))  # seconds
MOCK_INTERVAL_DRONES = int(os.getenv('MOCK_INTERVAL_DRONES', 120))   # seconds

# Mock configuration
SENSORS = [
    {'id': 'SENSOR_001'},
    {'id': 'SENSOR_002'},
    {'id': 'SENSOR_003'},
    {'id': 'SENSOR_004'},
    {'id': 'SENSOR_005'},
]

DRONES = [
    {'id': 'DRONE_001'},
    {'id': 'DRONE_002'},
]

# Global state
simulation_running = False
simulation_thread = None
stats = {
    'sensor_messages_sent': 0,
    'drone_images_sent': 0,
    'last_sensor_message': None,
    'last_drone_image': None,
    'errors': 0
}

def generate_sensor_data(sensor):
    """Generate realistic sensor data based on sensor type"""
    base_values = {
        'temperature': {'min': 15.0, 'max': 35.0, 'unit': '°C'},
        'humidity': {'min': 30.0, 'max': 90.0, 'unit': '%'},
        'soil_moisture': {'min': 20.0, 'max': 80.0, 'unit': '%'}
    }
    
    measurements = {}
    temp_range = base_values['temperature']
    measurements['temperature'] = round(random.uniform(temp_range['min'], temp_range['max']), 1)
    hum_range = base_values['humidity']
    measurements['humidity'] = round(random.uniform(hum_range['min'], hum_range['max']), 1)
    soil_range = base_values['soil_moisture']
    measurements['soil_moisture'] = round(random.uniform(soil_range['min'], soil_range['max']), 1)
    
    return {
        'sensor_id': sensor['id'],
        'timestamp': datetime.now().isoformat(),
        'measurements': measurements
    }

def drone_image():
    """Load the test drone image from file"""
    try:
        with open('/app/test_image.jpg', 'rb') as f:
            img_buffer = BytesIO(f.read())
        
        img_buffer.seek(0)
        return img_buffer
        
    except FileNotFoundError:
        logger.error("test_image.jpg not found, creating a simple fallback image")
        img = Image.new('RGB', (200, 150), (34, 139, 34))
        img_buffer = BytesIO()
        img.save(img_buffer, format='JPEG', quality=85)
        img_buffer.seek(0)
        return img_buffer

def send_sensor_data():
    """Send sensor data to IoT Gateway"""
    try:
        sensor = random.choice(SENSORS)
        data = generate_sensor_data(sensor)
        
        response = requests.post(
            f"{IOT_GATEWAY_URL}/api/sensors/data",
            json=data,
            headers={'Content-Type': 'application/json'},
            timeout=10
        )
        
        if response.status_code == 200:
            stats['sensor_messages_sent'] += 1
            stats['last_sensor_message'] = {
                'sensor_id': data['sensor_id'],
                'timestamp': data['timestamp'],
                'status': 'success'
            }
            logger.info(f"Sensor data sent successfully: {data['sensor_id']}")
        else:
            stats['errors'] += 1
            logger.error(f"Failed to send sensor data: {response.status_code} - {response.text}")
            
    except Exception as e:
        stats['errors'] += 1
        logger.error(f"Error sending sensor data: {e}")

def send_drone_image():
    """Send drone image to IoT Gateway"""
    try:
        drone = random.choice(DRONES)
        image_buffer = drone_image()
        
        files = {
            'image': ('drone_image.jpg', image_buffer, 'image/jpeg')
        }
        data = {
            'drone_id': drone['id'],
            'timestamp': datetime.now().isoformat()
        }
        
        response = requests.post(
            f"{IOT_GATEWAY_URL}/api/drones/image",
            files=files,
            data=data,
            timeout=30
        )
        
        if response.status_code == 200:
            stats['drone_images_sent'] += 1
            response_data = response.json()
            stats['last_drone_image'] = {
                'drone_id': drone['id'],
                'timestamp': data['timestamp'],
                's3_path': response_data.get('s3_path'),
                'status': 'success'
            }
            logger.info(f"Drone image sent successfully: {drone['id']}")
        else:
            stats['errors'] += 1
            logger.error(f"Failed to send drone image: {response.status_code} - {response.text}")
            
    except Exception as e:
        stats['errors'] += 1
        logger.error(f"Error sending drone image: {e}")

def simulation_loop():
    """Main simulation loop that runs in background thread"""
    global simulation_running
    
    sensor_last_run = 0
    drone_last_run = 0
    
    while simulation_running:
        current_time = time.time()
        
        # Send sensor data
        if current_time - sensor_last_run >= MOCK_INTERVAL_SENSORS:
            send_sensor_data()
            sensor_last_run = current_time
        
        # Send drone image
        if current_time - drone_last_run >= MOCK_INTERVAL_DRONES:
            send_drone_image()
            drone_last_run = current_time
        
        # Sleep for 1 second to avoid busy waiting
        time.sleep(1)

@app.route('/ping', methods=['GET'])
def ping():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'service': 'mocks',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/health', methods=['GET'])
def health():
    """Detailed health check endpoint"""
    # Test IoT Gateway connectivity
    iot_gateway_status = 'disconnected'
    try:
        response = requests.get(f"{IOT_GATEWAY_URL}/ping", timeout=5)
        if response.status_code == 200:
            iot_gateway_status = 'connected'
    except:
        pass
    
    return jsonify({
        'status': 'healthy',
        'service': 'mocks',
        'timestamp': datetime.now().isoformat(),
        'simulation_running': simulation_running,
        'dependencies': {
            'iot_gateway': iot_gateway_status
        }
    })

@app.route('/api/simulation/start', methods=['POST'])
def start_simulation():
    """Start the IoT simulation"""
    global simulation_running, simulation_thread
    
    if simulation_running:
        return jsonify({
            'success': False,
            'message': 'Simulation is already running'
        }), 400
    
    simulation_running = True
    simulation_thread = threading.Thread(target=simulation_loop, daemon=True)
    simulation_thread.start()
    
    logger.info("IoT simulation started")
    
    return jsonify({
        'success': True,
        'message': 'IoT simulation started',
        'config': {
            'sensor_interval': MOCK_INTERVAL_SENSORS,
            'drone_interval': MOCK_INTERVAL_DRONES,
            'sensors_count': len(SENSORS),
            'drones_count': len(DRONES)
        }
    })

@app.route('/api/simulation/stop', methods=['POST'])
def stop_simulation():
    """Stop the IoT simulation"""
    global simulation_running
    
    if not simulation_running:
        return jsonify({
            'success': False,
            'message': 'Simulation is not running'
        }), 400
    
    simulation_running = False
    logger.info("IoT simulation stopped")
    
    return jsonify({
        'success': True,
        'message': 'IoT simulation stopped'
    })

@app.route('/api/simulation/status', methods=['GET'])
def get_simulation_status():
    """Get simulation status and statistics"""
    return jsonify({
        'success': True,
        'simulation_running': simulation_running,
        'stats': stats,
        'config': {
            'iot_gateway_url': IOT_GATEWAY_URL,
            'sensor_interval_seconds': MOCK_INTERVAL_SENSORS,
            'drone_interval_seconds': MOCK_INTERVAL_DRONES,
            'sensors': SENSORS,
            'drones': DRONES
        }
    })

@app.route('/api/simulation/send-sensor', methods=['POST'])
def manual_send_sensor():
    """Manually send a sensor data sample"""
    try:
        request_data = request.get_json() if request.is_json else {}
        sensor_id = request_data.get('sensor_id')
        
        if sensor_id:
            sensor = next((s for s in SENSORS if s['id'] == sensor_id), None)
            if not sensor:
                return jsonify({
                    'success': False,
                    'error': f'Sensor {sensor_id} not found'
                }), 404
        else:
            sensor = random.choice(SENSORS)
        
        send_sensor_data()
        
        return jsonify({
            'success': True,
            'message': f'Sensor data sent for {sensor["id"]}'
        })
        
    except Exception as e:
        logger.error(f"Error in manual sensor send: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

@app.route('/api/simulation/send-drone', methods=['POST'])
def manual_send_drone():
    """Manually send a drone image sample"""
    try:
        request_data = request.get_json() if request.is_json else {}
        drone_id = request_data.get('drone_id')
        
        if drone_id:
            drone = next((d for d in DRONES if d['id'] == drone_id), None)
            if not drone:
                return jsonify({
                    'success': False,
                    'error': f'Drone {drone_id} not found'
                }), 404
        else:
            drone = random.choice(DRONES)
        
        send_drone_image()
        
        return jsonify({
            'success': True,
            'message': f'Drone image sent for {drone["id"]}'
        })
        
    except Exception as e:
        logger.error(f"Error in manual drone send: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

if __name__ == '__main__':
    logger.info(f"Starting Mocks Service...")
    logger.info(f"IoT Gateway URL: {IOT_GATEWAY_URL}")
    logger.info(f"Sensor interval: {MOCK_INTERVAL_SENSORS}s")
    logger.info(f"Drone interval: {MOCK_INTERVAL_DRONES}s")
    
    app.run(host='0.0.0.0', port=9000, debug=False)