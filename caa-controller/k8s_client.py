"""
Kubernetes Client for executing scaling actions
"""

import logging
from kubernetes import client, config
from decision_engine import ScalingDecision, ActionType

logger = logging.getLogger(__name__)

class K8sScalingClient:
    """
    Execute scaling actions on Kubernetes deployments
    """
    
    def __init__(self, namespace: str = "parking-fabric"):
        """Initialize Kubernetes client"""
        self.namespace = namespace
        
        # Load config
        try:
            config.load_incluster_config()
        except:
            config.load_kube_config()
        
        self.apps_v1 = client.AppsV1Api()
        self.core_v1 = client.CoreV1Api()
        
        logger.info(f"K8sScalingClient initialized for namespace: {namespace}")
    
    def get_deployment_replicas(self, deployment_name: str) -> int:
        """Get current replica count for a deployment"""
        try:
            deployment = self.apps_v1.read_namespaced_deployment(
                name=deployment_name,
                namespace=self.namespace
            )
            return deployment.spec.replicas
        
        except Exception as e:
            logger.error(f"Failed to get replicas for {deployment_name}: {e}")
            return 0
    
    def scale_deployment(self, deployment_name: str, target_replicas: int) -> bool:
        """
        Scale a deployment to target replicas
        
        Args:
            deployment_name: e.g., "peer-zone-a"
            target_replicas: Desired replica count
        
        Returns:
            True if successful
        """
        try:
            # Patch deployment
            body = {
                'spec': {
                    'replicas': target_replicas
                }
            }
            
            self.apps_v1.patch_namespaced_deployment_scale(
                name=deployment_name,
                namespace=self.namespace,
                body=body
            )
            
            logger.info(f"✅ Scaled {deployment_name} to {target_replicas} replicas")
            return True
        
        except Exception as e:
            logger.error(f"❌ Failed to scale {deployment_name}: {e}")
            return False
    
    def execute_decision(self, decision: ScalingDecision) -> bool:
        """
        Execute a scaling decision
        
        Args:
            decision: ScalingDecision object
        
        Returns:
            True if action was executed successfully
        """
        if decision.action == ActionType.NO_ACTION:
            logger.debug(f"No action needed for {decision.zone}")
            return True
        
        # Map zone to deployment name
        deployment_name = f"peer-{decision.zone}"
        
        logger.info(
            f"🚀 Executing {decision.action.value} for {decision.zone}: "
            f"{decision.current_replicas} → {decision.target_replicas} "
            f"(Reason: {decision.reason})"
        )
        
        return self.scale_deployment(deployment_name, decision.target_replicas)
    
    def get_all_deployments_status(self) -> dict:
        """Get status of all peer deployments"""
        zones = ['zone-a', 'zone-b', 'zone-c']
        status = {}
        
        for zone in zones:
            deployment_name = f"peer-{zone}"
            replicas = self.get_deployment_replicas(deployment_name)
            status[zone] = {
                'deployment': deployment_name,
                'replicas': replicas
            }
        
        return status