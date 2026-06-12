import logging
import time
import sys
import threading
import os
from flask import Flask
from metrics_collector import MetricsCollector
from contribution_score import ContributionScoreCalculator, NodeMetrics
from decision_engine import DecisionEngine, ActionType
from k8s_client import K8sScalingClient

logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s [%(levelname)s] %(message)s', 
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("CANA-Main")
app = Flask(__name__)

class CANAController:
    def __init__(self):
        logger.info("Initializing CANA Controller Components...")
        try:
            self.metrics = MetricsCollector()
            
            alpha_val = float(os.getenv("WEIGHT_CPU", "0.5"))
            beta_val = float(os.getenv("WEIGHT_LATENCY", "0.5"))
            self.target_zone = os.getenv("TARGET_ZONE", "zone-a") # Membaca target zona
            
            self.calculator = ContributionScoreCalculator(alpha=alpha_val, beta=beta_val) 
            self.engine = DecisionEngine(scale_up_threshold=0.10, scale_down_threshold=0.05)
            self.k8s = K8sScalingClient()
            
            logger.info(f"🚀 CANA Started | Alpha: {alpha_val}, Beta: {beta_val}, Target: {self.target_zone.upper()}")

        except Exception as e:
            logger.error(f"❌ Initialization Failed: {e}")
            sys.exit(1)

    def run(self):
        logger.info("Waiting for system to stabilize (10s)...")
        time.sleep(10)
        
        while True:
            try:
                raw_data = self.metrics.get_metrics()
                
                for zone, data in raw_data.items():
                    # KUNCI ISOLASI DINAMIS: Bypass zona yang bukan merupakan target
                    if zone != self.target_zone:
                        continue

                    metric_obj = NodeMetrics(
                        peer_id=f"peer-{zone}", 
                        zone=zone, 
                        cpu_usage=data['cpu_usage'], 
                        queue_length=data['queue_size']
                    )
                    
                    ci = self.calculator.calculate_ci(metric_obj)
                    s_zone = self.calculator.calculate_s_zone([ci])
                    current_replicas = self.k8s.get_deployment_replicas(f"peer-{zone}")
                    decision = self.engine.make_decision(zone, s_zone, current_replicas)

                    log_msg = f"[{zone.upper()}] Stress:{s_zone:.2f} | Repl:{current_replicas}/{self.engine.max_replicas}"
                    
                    if decision.action != ActionType.NO_ACTION:
                        logger.info(f"{log_msg} | ⚡ ACTION: {decision.action.value} -> {decision.reason}")
                        self.k8s.execute_decision(decision)
                    else:
                        logger.info(f"{log_msg} | 💤 NO ACTION: {decision.reason}")
            
            except Exception as e:
                logger.error(f"⚠️ Loop Error: {e}")
            
            time.sleep(5)

@app.route('/health')
def health():
    return "OK", 200

if __name__ == "__main__":
    cana = CANAController()
    threading.Thread(target=cana.run, daemon=True).start()
    app.run(host="0.0.0.0", port=8080)