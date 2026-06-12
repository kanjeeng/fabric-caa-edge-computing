#!/bin/bash
# scripts/compare-methods.sh

set -e

echo "🔬 CANA vs HPA vs Static Comparison Test"
echo ""

# Test configurations
METHODS=("cana" "hpa" "static")
TEST_DURATION=900  # 15 minutes per method
RESULTS_DIR="./test-results"

mkdir -p $RESULTS_DIR

echo "Test Configuration:"
echo "  Duration per method: ${TEST_DURATION}s (15 min)"
echo "  Total test time: $((TEST_DURATION * 3 / 60)) minutes"
echo "  Results directory: ${RESULTS_DIR}"
echo ""

read -p "Start comparison test? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

for METHOD in "${METHODS[@]}"; do
    echo ""
    echo "=" * 60
    echo "Testing Method: ${METHOD^^}"
    echo "=" * 60
    echo ""
    
    case $METHOD in
        "cana")
            echo "📊 Method: CANA Controller (Contribution-Aware)"
            # CANA is already deployed
            kubectl scale deployment caa-controller --replicas=1 -n parking-fabric
            kubectl scale deployment peer-zone-a --replicas=1 -n parking-fabric
            kubectl scale deployment peer-zone-b --replicas=1 -n parking-fabric
            kubectl scale deployment peer-zone-c --replicas=1 -n parking-fabric
            ;;
        
        "hpa")
            echo "📊 Method: Kubernetes HPA (CPU-based)"
            # Disable CANA controller
            kubectl scale deployment caa-controller --replicas=0 -n parking-fabric
            
            # Apply HPA
            cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: peer-zone-a-hpa
  namespace: parking-fabric
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: peer-zone-a
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: peer-zone-b-hpa
  namespace: parking-fabric
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: peer-zone-b
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: peer-zone-c-hpa
  namespace: parking-fabric
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: peer-zone-c
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF
            ;;
        
        "static")
            echo "📊 Method: Static Sharding (No autoscaling)"
            # Disable CANA and HPA
            kubectl scale deployment caa-controller --replicas=0 -n parking-fabric
            kubectl delete hpa --all -n parking-fabric 2>/dev/null || true
            
            # Fixed 2 replicas per zone
            kubectl scale deployment peer-zone-a --replicas=2 -n parking-fabric
            kubectl scale deployment peer-zone-b --replicas=2 -n parking-fabric
            kubectl scale deployment peer-zone-c --replicas=2 -n parking-fabric
            ;;
    esac
    
    echo "⏳ Waiting for system stabilization (30s)..."
    sleep 30
    
    echo "🚀 Starting test for ${METHOD}..."
    
    # Run metrics collection in background
    python3 scripts/collect-metrics.py <<EOF &
${TEST_DURATION}
10
EOF
    METRICS_PID=$!
    
    # Run load test
    cd iot-simulator/
    MQTT_BROKER="$(minikube ip):30883" \
    INTERVAL_MS=5000 \
    OCCUPANCY_MULT=1.5 \
    DURATION_S=${TEST_DURATION} \
    node simulator-test.js &
    SIMULATOR_PID=$!
    
    cd ..
    
    # Wait for test to complete
    wait $SIMULATOR_PID
    wait $METRICS_PID
    
    # Move results
    mv metrics-results.json ${RESULTS_DIR}/metrics-${METHOD}.json
    
    echo "✅ Test completed for ${METHOD}"
    echo ""
    
    # Cooldown between tests
    if [ "$METHOD" != "static" ]; then
        echo "💤 Cooldown period (60s)..."
        sleep 60
    fi
done

echo ""
echo "=" * 60
echo "✅ ALL TESTS COMPLETED!"
echo "=" * 60
echo ""
echo "Results saved in: ${RESULTS_DIR}/"
echo ""
echo "Generate comparison report:"
echo "  python3 scripts/analyze-comparison.py ${RESULTS_DIR}"