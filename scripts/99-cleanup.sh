#!/bin/bash
# scripts/99-cleanup.sh

set -e

echo "🧹 Cleaning up CANA Blockchain..."

read -p "Delete entire Minikube cluster? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting Minikube cluster..."
    minikube delete
    echo "✅ Cluster deleted"
else
    echo "Deleting parking-fabric namespace only..."
    kubectl delete namespace parking-fabric --wait=true
    echo "✅ Namespace deleted"
fi

echo ""
echo "Cleanup options:"
echo "  - Remove Docker images: docker rmi caa-controller mqtt-bridge api-gateway"
echo "  - Remove test results: rm -rf test-results/"
echo "  - Remove crypto materials: rm -rf fabric-network/crypto-config fabric-network/channel-artifacts"