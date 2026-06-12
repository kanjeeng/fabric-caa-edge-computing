import logging
import time
from enum import Enum

logger = logging.getLogger(__name__)

class ActionType(Enum):
    NO_ACTION = "no_action"
    SCALE_UP = "scale_up"
    SCALE_DOWN = "scale_down"

class ScalingDecision:
    def __init__(self, action, zone, reason, target, current):
        self.action = action
        self.zone = zone
        self.reason = reason
        self.target_replicas = target
        self.current_replicas = current

class DecisionEngine:
    def __init__(self,
                 scale_up_threshold: float = 0.10, 
                 scale_down_threshold: float = 0.05,
                 max_replicas: int = 5,
                 cooldown: int = 45,        
                 max_step_up: int = 2):     
        
        self.up_threshold = scale_up_threshold
        self.down_threshold = scale_down_threshold
        self.max_replicas = max_replicas
        self.cooldown = cooldown
        self.max_step_up = max_step_up
        self.last_action_time = {}
        
        # --- FITUR BARU: SMART SCALE-DOWN VERIFICATION ---
        self.scale_down_verifications = {}
        self.required_verifications = 4 # Butuh 4 kali cek berturut-turut (~20 detik) sebelum boleh scale-down
        
        logger.info(f"✅ Smart Decision Engine: Threshold UP > {self.up_threshold}, MAX STEP = {self.max_step_up}, Cooldown = {self.cooldown}s, Scale-Down Verifications = {self.required_verifications}")

    def make_decision(self, zone: str, s_zone: float, current_replicas: int) -> ScalingDecision:
        # Inisialisasi dictionary verifikasi jika zona belum ada
        if zone not in self.scale_down_verifications:
            self.scale_down_verifications[zone] = 0

        # 1. GERBANG COOLDOWN
        if not self._check_cooldown(zone):
            return ScalingDecision(ActionType.NO_ACTION, zone, "⏳ Cooldown Aktif (Menunggu Pod Siap)", current_replicas, current_replicas)

        # 2. GERBANG PEMETAAN (Proportional Mapping berdasarkan skor stres s_zone)
        desired_replicas = 1
        if s_zone > 0.80:
            desired_replicas = 5    
        elif s_zone > 0.60:
            desired_replicas = 4    
        elif s_zone > 0.35:
            desired_replicas = 3    
        elif s_zone > self.up_threshold: 
            desired_replicas = 2    

        # 3. LOGIKA SCALE UP (Jika butuh Pod lebih dari yang ada sekarang)
        if desired_replicas > current_replicas:
            # Jika ada lonjakan beban, langsung RESET hitungan scale down ke 0
            self.scale_down_verifications[zone] = 0
            
            pods_to_add = desired_replicas - current_replicas
            if pods_to_add > self.max_step_up:
                pods_to_add = self.max_step_up 
                
            target = current_replicas + pods_to_add
            if target > self.max_replicas:
                target = self.max_replicas
                
            self._record_action(zone)
            return ScalingDecision(
                ActionType.SCALE_UP, 
                zone, 
                f"Stress {s_zone:.2f}. Butuh {desired_replicas} Pod, menambah {pods_to_add} Pod", 
                target,
                current_replicas
            )

        # 4. LOGIKA SCALE DOWN PINTAR (Menggunakan Jendela Waktu/Verifikasi)
        if s_zone < self.down_threshold and current_replicas > 1:
            self.scale_down_verifications[zone] += 1
            
            # Jika sudah sepi selama 4 kali pengecekan, baru matikan Pod
            if self.scale_down_verifications[zone] >= self.required_verifications:
                self._record_action(zone)
                self.scale_down_verifications[zone] = 0 # Reset kembali
                return ScalingDecision(
                    ActionType.SCALE_DOWN, 
                    zone, 
                    f"Trafik BENAR-BENAR Idle ({s_zone:.2f} < {self.down_threshold} selama {self.required_verifications} siklus)", 
                    current_replicas - 1,
                    current_replicas
                )
            else:
                return ScalingDecision(
                    ActionType.NO_ACTION, 
                    zone, 
                    f"Menahan Scale-Down. Verifikasi kesepian: {self.scale_down_verifications[zone]}/{self.required_verifications}", 
                    current_replicas, 
                    current_replicas
                )

        # 5. JIKA STABIL ATAU TRANSAKSI SEDANG BERJALAN LANCAR
        self.scale_down_verifications[zone] = 0 # Reset hitungan
        return ScalingDecision(ActionType.NO_ACTION, zone, f"Stabil/Menangani Spike (Stress: {s_zone:.2f})", current_replicas, current_replicas)

    def _check_cooldown(self, zone: str) -> bool:
        if zone not in self.last_action_time: return True
        return (time.time() - self.last_action_time[zone]) >= self.cooldown

    def _record_action(self, zone: str):
        self.last_action_time[zone] = time.time()