import logging
import os
from typing import Dict, Any
from prometheus_api_client import PrometheusConnect

logger = logging.getLogger(__name__)

class MetricsCollector:
    def __init__(self, prometheus_url: str = "http://prometheus-service.monitoring.svc:9090"):
        self.prom = PrometheusConnect(url=prometheus_url, disable_ssl=True)
        self.zones = ['zone-a', 'zone-b', 'zone-c']
        # Menerima target zone dinamis dari Kubernetes (Default: zone-a)
        self.target_zone = os.getenv("TARGET_ZONE", "zone-a")
        logger.info(f"✅ MetricsCollector connected to {prometheus_url}. Target Zone: {self.target_zone}")

    def get_metrics(self) -> Dict[str, Any]:
        metrics_data = {z: {'cpu_usage': 0.0, 'queue_size': 0.0} for z in self.zones}
        
        cpu_query = 'rate(process_cpu_seconds_total{kubernetes_pod_name=~".*peer-zone.*"}[1m]) * 100'
        queue_query = 'api_gateway_queue_length' 

        try:
            cpu_results = self.prom.custom_query(query=cpu_query)
            queue_results = self.prom.custom_query(query=queue_query)
            
            # --- 1. Parsing Data CPU (RATA-RATA Per Zona) ---
            cpu_lists = {z: [] for z in self.zones} # Menyimpan daftar CPU semua Pod di tiap zona
            
            for res in cpu_results:
                pod_name = res['metric'].get('kubernetes_pod_name', '') or res['metric'].get('pod', '')
                for zone in self.zones:
                    if zone in pod_name:
                        val = float(res['value'][1])
                        cpu_lists[zone].append(val)
            
            # Hitung Rata-rata (Average) CPU untuk mencegah Flapping
            for zone in self.zones:
                if len(cpu_lists[zone]) > 0:
                    metrics_data[zone]['cpu_usage'] = sum(cpu_lists[zone]) / len(cpu_lists[zone])
                else:
                    metrics_data[zone]['cpu_usage'] = 0.0
            
            # --- 2. Parsing Data Queue (Global Gateway) ---
            global_queue_length = 0.0
            for res in queue_results:
                val = float(res['value'][1])
                global_queue_length = max(global_queue_length, val)

            # --- 3. TARGETING DINAMIS ABSOLUT ---
            # Mengunci beban antrean secara mutlak ke Target Zona yang sedang diuji
            if global_queue_length > 0:
                metrics_data[self.target_zone]['queue_size'] = global_queue_length

        except Exception as e:
            logger.error(f"❌ Prometheus Query Failed: {e}")

        return metrics_data