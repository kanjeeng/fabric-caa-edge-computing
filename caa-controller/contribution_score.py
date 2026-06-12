import logging
from dataclasses import dataclass
from typing import List

logger = logging.getLogger(__name__)

@dataclass
class NodeMetrics:
    peer_id: str
    zone: str
    cpu_usage: float      
    queue_length: float   

class ContributionScoreCalculator:
    def __init__(self, alpha: float = 1.0, beta: float = 0.0, queue_max: int = 100):
        # Inisialisasi Bobot (Sesuai Proposal Bab 3.3.2)
        self.alpha = alpha
        self.beta = beta
        self.queue_max = queue_max
        logger.info(f"✅ Calculator Init: α={alpha}, β={beta}, Q_max={queue_max}")

    def calculate_ci(self, metrics: NodeMetrics) -> float:
        """
        Menghitung Skor Kontribusi (Ci) - Persamaan (1) & (2)
        """
        # 1. Normalisasi (Persamaan 1)
        # S_cpu = CPU / 100
        s_cpu = metrics.cpu_usage / 100.0
        
        # S_queue = min(1, Queue / QueueMax)
        s_queue = min(1.0, metrics.queue_length / self.queue_max)

        # 2. Hitung Ci (Persamaan 2)
        # Ci = α(1-Scpu) + β(1-Squeue)
        # Semakin tinggi Ci, semakin SEHAT node tersebut
        ci = (self.alpha * (1.0 - s_cpu)) + (self.beta * (1.0 - s_queue))
        
        return max(0.0, ci)

    def calculate_s_zone(self, ci_list: List[float]) -> float:
        """
        Menghitung Stres Zona (Szone) - Persamaan (3)
        Szone = 1 - Rata-rata Ci
        Semakin tinggi Szone, semakin STRES zona tersebut
        """
        if not ci_list: return 0.0
        
        avg_ci = sum(ci_list) / len(ci_list)
        
        # Persamaan (3)
        s_zone = 1.0 - avg_ci
        
        return max(0.0, s_zone)