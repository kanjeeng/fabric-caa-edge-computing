#!/bin/bash
# scripts/02-setup-minikube.sh

set -e

echo "🚀 Setting up Minikube (Optimized for 8GB RAM VM)..."

# Verify kubectl is working
if ! kubectl version --client &> /dev/null; then
    echo "❌ kubectl is not working properly!"
    echo "   Please run: ./scripts/01-install-tools.sh first"
    exit 1
fi

# Stop existing cluster if any
echo "🧹 Cleaning up existing cluster..."
minikube delete 2>/dev/null || true

# Wait a bit for cleanup
sleep 3

# Start Minikube with REDUCED resources for 8GB VM
echo "📦 Starting Minikube..."
echo "   Resources: 4 CPU, 8GB RAM, 20GB Disk"
echo "   Driver: docker"
echo ""
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=20g \
  --driver=docker \
  --kubernetes-version=v1.28.0 \
  --extra-config=kubelet.housekeeping-interval=30s \
  --extra-config=kubelet.image-gc-high-threshold=90 \
  --extra-config=kubelet.image-gc-low-threshold=80 \
  --wait=all

# Enable addons (minimal)
echo "🔧 Enabling addons..."
minikube addons enable metrics-server
minikube addons enable default-storageclass
minikube addons enable storage-provisioner

# Verify cluster
echo "✅ Verifying cluster..."
kubectl cluster-info
kubectl get nodes

# Wait for metrics-server to be ready
echo ""
echo "⏳ Waiting for metrics-server to be ready (30s)..."
sleep 30

# Test metrics
echo "Testing metrics-server..."
kubectl top node || echo "⚠️  Metrics not ready yet (this is OK, will be ready soon)"

# Create namespace
echo "📂 Creating namespace..."
kubectl create namespace parking-fabric || echo "Namespace already exists"

# Set context
kubectl config set-context --current --namespace=parking-fabric

echo ""
echo "=" * 60
echo "✅ Minikube is ready!"
echo "=" * 60
echo ""
echo "Cluster Info:"
echo "  IP:        $(minikube ip)"
echo "  Version:   $(kubectl version --short | grep Server)"
echo "  Namespace: parking-fabric"
echo "  Resources: 3 CPU, 5GB RAM"
echo ""
echo "Useful Commands:"
echo "  Dashboard:       minikube dashboard"
echo "  SSH to cluster:  minikube ssh"
echo "  Stop cluster:    minikube stop"
echo "  Delete cluster:  minikube delete"
echo ""
echo "Next Steps:"
echo "  cd fabric-network/"
echo "  ./scripts/generate-crypto.sh"
echo ""