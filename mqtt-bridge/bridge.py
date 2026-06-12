"""
MQTT to Blockchain Bridge - FINAL VERSION
"""

import os
import json
import logging
import time
import requests
from datetime import datetime
import paho.mqtt.client as mqtt
import threading

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class MQTTBridge:
    def __init__(self):
        self.mqtt_host = os.getenv('MQTT_BROKER_HOST', 'mosquitto')
        self.mqtt_port = int(os.getenv('MQTT_BROKER_PORT', '1883'))
        self.api_gateway_url = os.getenv('API_GATEWAY_URL', 'http://api-gateway:3000')
        
        logger.info("🔧 MQTT Bridge Initializing...")
        logger.info(f"   MQTT: {self.mqtt_host}:{self.mqtt_port}")
        logger.info(f"   API: {self.api_gateway_url}")
        
        self.client = mqtt.Client(client_id="parking-bridge")
        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message
        
        self.messages_received = 0
        self.messages_sent = 0
    
    def _on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            logger.info("✅ Connected to MQTT Broker")
            topics = [
                "parking/zone-a/+",
                "parking/zone-b/+", 
                "parking/zone-c/+"
            ]
            for topic in topics:
                client.subscribe(topic)
                logger.info(f"   📬 Subscribed: {topic}")
        else:
            logger.error(f"❌ MQTT Connection failed: {rc}")
    
    def _on_message(self, client, userdata, msg):
        self.messages_received += 1
        
        try:
            payload = json.loads(msg.payload.decode())
            topic_parts = msg.topic.split('/')
            
            if len(topic_parts) == 3:
                zone = topic_parts[1]
                spot_id = topic_parts[2]
                
                # --- PERBAIKAN: GUNAKAN THREAD AGAR PARALEL (TIDAK ANTRE) ---
                threading.Thread(target=self._send_to_blockchain, args=(zone, spot_id, payload)).start()
                
        except Exception as e:
            logger.error(f"❌ Message processing error: {e}")
    
    def _send_to_blockchain(self, zone: str, spot_id: str, data: dict):
        try:
            # DISAMAKAN DENGAN load_gen_normal.js
            transaction = {
                'channel': f'channel-zone-a',
                'chaincode': 'parking-cc',          # PERBAIKAN: Harus parking-cc
                'function': 'UpdateSpotStatus',     # PERBAIKAN: Fungsi yang benar
                'args': [                           # PERBAIKAN: Hanya 3 argumen sesuai chaincode
                    spot_id,
                    data.get('status', 'unknown'),
                    zone
                ]
            }
            
            response = requests.post(
                f"{self.api_gateway_url}/api/transactions", # Tetap menembak ke sini
                json=transaction,
                timeout=60
            )
            
            if response.status_code in [200, 201]:
                self.messages_sent += 1
                logger.info(f"✅ Sent to blockchain: {spot_id}")
            else:
                logger.warning(f"⚠️  API Error: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"❌ Blockchain error: {e}")
    
    def _wait_for_services(self):
        """Wait for MQTT broker and API Gateway to be ready"""
        logger.info("⏳ Waiting for services...")
        
        # Wait for MQTT
        max_attempts = 30
        for attempt in range(max_attempts):
            try:
                logger.info(f"   MQTT attempt {attempt + 1}/{max_attempts}...")
                self.client.connect(self.mqtt_host, self.mqtt_port, 60)
                logger.info("✅ MQTT connected!")
                break
            except Exception as e:
                if attempt == max_attempts - 1:
                    logger.error(f"❌ MQTT connection failed: {e}")
                    raise
                time.sleep(2)
    
    def run(self):
        logger.info("🚀 Starting MQTT Bridge...")
        
        try:
            self._wait_for_services()
            self.client.loop_start()
            logger.info("🔄 MQTT loop started")
            
            # Keep running forever
            while True:
                time.sleep(10)
                logger.info(f"💓 Running... Received: {self.messages_received}, Sent: {self.messages_sent}")
                
        except KeyboardInterrupt:
            logger.info("🛑 Stopping...")
        except Exception as e:
            logger.error(f"💥 Fatal error: {e}")
        finally:
            self.client.loop_stop()
            self.client.disconnect()

if __name__ == "__main__":
    bridge = MQTTBridge()
    bridge.run()