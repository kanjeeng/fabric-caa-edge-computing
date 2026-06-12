#!/usr/bin/env python3
# scripts/collect-metrics.py
"""
Collect and analyze CANA performance metrics
"""

import json
import time
import requests
from datetime import datetime
from kubernetes import client, config

# Load K8s config
config.load_kube_config()
v1 = client.CoreV1Api()
apps_v1 = client.AppsV1Api()
custom_api = client.CustomObjectsApi()

NAMESPACE = "parking-fabric"
OUTPUT_FILE = "metrics-results.json"

def get_pod_metrics(pod_name):
    """Get CPU and memory metrics for a pod"""
    try:
        metrics = custom_api.list_namespaced_custom_object(
            group="metrics.k8s.io",
            version="v1beta1",
            namespace=NAMESPACE,
            plural="pods"
        )
        
        for item in metrics.get('items', []):
            if item['metadata']['name'] == pod_name:
                cpu = item['containers'][0]['usage']['cpu']
                memory = item['containers'][0]['usage']['memory']
                return {
                    'cpu': cpu,
                    'memory': memory
                }
        return None
    except Exception as e:
        print(f"Error getting metrics for {pod_name}: {e}")
        return None

def get_deployment_replicas(deployment_name):
    """Get current replica count"""
    try:
        deployment = apps_v1.read_namespaced_deployment(
            name=deployment_name,
            namespace=NAMESPACE
        )
        return deployment.spec.replicas
    except Exception as e:
        print(f"Error getting replicas for {deployment_name}: {e}")
        return 0

def collect_snapshot():
    """Collect metrics snapshot"""
    snapshot = {
        'timestamp': datetime.utcnow().isoformat(),
        'zones': {}
    }
    
    zones = ['zone-a', 'zone-b', 'zone-c']
    
    for zone in zones:
        deployment_name = f"peer-{zone}"
        replicas = get_deployment_replicas(deployment_name)
        
        # Get pods for this deployment
        pods = v1.list_namespaced_pod(
            namespace=NAMESPACE,
            label_selector=f"app=fabric-peer,zone={zone}"
        )
        
        pod_metrics = []
        for pod in pods.items:
            if pod.status.phase == "Running":
                metrics = get_pod_metrics(pod.metadata.name)
                if metrics:
                    pod_metrics.append({
                        'pod_name': pod.metadata.name,
                        'metrics': metrics
                    })
        
        snapshot['zones'][zone] = {
            'replicas': replicas,
            'pods': pod_metrics
        }
    
    return snapshot

def main():
    print("=" * 60)
    print("CANA Metrics Collector")
    print("=" * 60)
    print(f"Namespace: {NAMESPACE}")
    print(f"Output: {OUTPUT_FILE}")
    print("")
    
    duration = int(input("Collection duration (seconds): "))
    interval = int(input("Collection interval (seconds): "))
    
    print(f"\nCollecting metrics every {interval}s for {duration}s...")
    print("Press Ctrl+C to stop early\n")
    
    results = {
        'test_config': {
            'duration': duration,
            'interval': interval,
            'start_time': datetime.utcnow().isoformat()
        },
        'snapshots': []
    }
    
    start_time = time.time()
    iteration = 0
    
    try:
        while time.time() - start_time < duration:
            iteration += 1
            print(f"[{iteration}] Collecting snapshot...")
            
            snapshot = collect_snapshot()
            results['snapshots'].append(snapshot)
            
            # Print summary
            for zone, data in snapshot['zones'].items():
                print(f"  {zone}: {data['replicas']} replicas, {len(data['pods'])} pods")
            
            print("")
            time.sleep(interval)
    
    except KeyboardInterrupt:
        print("\n⏹️  Collection stopped by user")
    
    # Save results
    results['test_config']['end_time'] = datetime.utcnow().isoformat()
    results['test_config']['total_snapshots'] = len(results['snapshots'])
    
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\n✅ Metrics saved to: {OUTPUT_FILE}")
    print(f"   Total snapshots: {len(results['snapshots'])}")
    
    # Basic analysis
    print("\n📊 Basic Analysis:")
    analyze_results(results)

def analyze_results(results):
    """Perform basic analysis"""
    snapshots = results['snapshots']
    
    if not snapshots:
        print("  No data to analyze")
        return
    
    # Calculate average replicas per zone
    zones = ['zone-a', 'zone-b', 'zone-c']
    
    for zone in zones:
        replica_counts = [s['zones'][zone]['replicas'] for s in snapshots if zone in s['zones']]
        
        if replica_counts:
            avg_replicas = sum(replica_counts) / len(replica_counts)
            min_replicas = min(replica_counts)
            max_replicas = max(replica_counts)
            
            print(f"\n  {zone}:")
            print(f"    Avg Replicas: {avg_replicas:.2f}")
            print(f"    Min Replicas: {min_replicas}")
            print(f"    Max Replicas: {max_replicas}")
            print(f"    Scaling Events: {max_replicas - min_replicas}")
    
    # Calculate stress variance (simplified)
    print("\n  Cluster Balance:")
    
    final_snapshot = snapshots[-1]
    replicas = [final_snapshot['zones'][z]['replicas'] for z in zones]
    
    mean_replicas = sum(replicas) / len(replicas)
    variance = sum((r - mean_replicas) ** 2 for r in replicas) / len(replicas)
    
    print(f"    Replica Distribution: {replicas}")
    print(f"    Mean: {mean_replicas:.2f}")
    print(f"    Variance: {variance:.2f}")
    
    if variance < 1.0:
        print(f"    Status: ✅ BALANCED")
    elif variance < 2.0:
        print(f"    Status: 🟡 MODERATE IMBALANCE")
    else:
        print(f"    Status: 🔴 HIGH IMBALANCE")

if __name__ == "__main__":
    main()