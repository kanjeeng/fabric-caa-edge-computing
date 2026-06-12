#!/usr/bin/env python3
# scripts/analyze-comparison.py
"""
Analyze comparison test results
"""

import json
import sys
import statistics
from pathlib import Path

def load_results(results_dir):
    """Load all test results"""
    results = {}
    
    for method in ['cana', 'hpa', 'static']:
        file_path = Path(results_dir) / f"metrics-{method}.json"
        
        if file_path.exists():
            with open(file_path, 'r') as f:
                results[method] = json.load(f)
        else:
            print(f"⚠️  Warning: {file_path} not found")
    
    return results

def calculate_metrics(snapshots):
    """Calculate performance metrics from snapshots"""
    if not snapshots:
        return None
    
    zones = ['zone-a', 'zone-b', 'zone-c']
    
    # Calculate average replicas per zone
    zone_replicas = {z: [] for z in zones}
    stress_variances = []
    
    for snapshot in snapshots:
        replicas = []
        for zone in zones:
            if zone in snapshot['zones']:
                replica_count = snapshot['zones'][zone]['replicas']
                zone_replicas[zone].append(replica_count)
                replicas.append(replica_count)
        
        # Calculate stress variance for this snapshot
        if replicas:
            mean = statistics.mean(replicas)
            variance = statistics.variance(replicas) if len(replicas) > 1 else 0
            stress_variances.append(variance)
    
    # Calculate averages
    avg_replicas = {z: statistics.mean(counts) if counts else 0 
                    for z, counts in zone_replicas.items()}
    
    avg_stress_variance = statistics.mean(stress_variances) if stress_variances else 0
    
    # Calculate total pod-hours (resource efficiency)
    total_pod_hours = sum(avg_replicas.values()) * (len(snapshots) / 360)  # Assuming 10s interval
    
    return {
        'avg_replicas_per_zone': avg_replicas,
        'total_avg_replicas': statistics.mean(avg_replicas.values()),
        'avg_stress_variance': avg_stress_variance,
        'total_pod_hours': total_pod_hours,
        'total_snapshots': len(snapshots)
    }

def print_comparison(results):
    """Print comparison table"""
    print("\n" + "=" * 80)
    print("PERFORMANCE COMPARISON RESULTS")
    print("=" * 80)
    
    methods = ['cana', 'hpa', 'static']
    metrics = {}
    
    for method in methods:
        if method in results:
            metrics[method] = calculate_metrics(results[method]['snapshots'])
    
    # Print table
    print(f"\n{'Metric':<30} {'CANA':>15} {'HPA':>15} {'Static':>15}")
    print("-" * 80)
    
    # Average replicas
    print(f"{'Average Total Replicas':<30}", end='')
    for method in methods:
        if method in metrics and metrics[method]:
            print(f"{metrics[method]['total_avg_replicas']:>15.2f}", end='')
        else:
            print(f"{'N/A':>15}", end='')
    print()
    
    # Stress variance (load imbalance)
    print(f"{'Stress Variance':<30}", end='')
    for method in methods:
        if method in metrics and metrics[method]:
            print(f"{metrics[method]['avg_stress_variance']:>15.2f}", end='')
        else:
            print(f"{'N/A':>15}", end='')
    print()
    
    # Resource efficiency (lower is better)
    print(f"{'Total Pod-Hours':<30}", end='')
    for method in methods:
        if method in metrics and metrics[method]:
            print(f"{metrics[method]['total_pod_hours']:>15.2f}", end='')
        else:
            print(f"{'N/A':>15}", end='')
    print()
    
    print("\n" + "=" * 80)
    
    # Determine winner
    print("\n🏆 PERFORMANCE SUMMARY:")
    
    if 'cana' in metrics and metrics['cana']:
        cana_variance = metrics['cana']['avg_stress_variance']
        cana_pod_hours = metrics['cana']['total_pod_hours']
        
        print(f"\nCANA Controller:")
        print(f"  ✅ Stress Variance: {cana_variance:.2f} (Lower = Better Balance)")
        print(f"  ✅ Resource Efficiency: {cana_pod_hours:.2f} pod-hours")
        
        if 'hpa' in metrics and metrics['hpa']:
            hpa_variance = metrics['hpa']['avg_stress_variance']
            hpa_pod_hours = metrics['hpa']['total_pod_hours']
            
            variance_improvement = ((hpa_variance - cana_variance) / hpa_variance) * 100
            efficiency_improvement = ((hpa_pod_hours - cana_pod_hours) / hpa_pod_hours) * 100
            
            print(f"\nCANA vs HPA:")
            print(f"  📊 Load Balance Improvement: {variance_improvement:+.1f}%")
            print(f"  💰 Resource Efficiency Improvement: {efficiency_improvement:+.1f}%")
        
        if 'static' in metrics and metrics['static']:
            static_variance = metrics['static']['avg_stress_variance']
            static_pod_hours = metrics['static']['total_pod_hours']
            
            variance_improvement = ((static_variance - cana_variance) / static_variance) * 100
            efficiency_improvement = ((static_pod_hours - cana_pod_hours) / static_pod_hours) * 100
            
            print(f"\nCANA vs Static:")
            print(f"  📊 Load Balance Improvement: {variance_improvement:+.1f}%")
            print(f"  💰 Resource Efficiency Improvement: {efficiency_improvement:+.1f}%")
    
    print("\n" + "=" * 80)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze-comparison.py <results_directory>")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    
    print(f"📊 Analyzing results from: {results_dir}")
    
    results = load_results(results_dir)
    
    if not results:
        print("❌ No results found!")
        sys.exit(1)
    
    print_comparison(results)

if __name__ == "__main__":
    main()