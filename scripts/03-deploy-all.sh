#!/bin/bash
# scripts/03-deploy-all.sh
# VERSI FINAL: Deploy Infrastructure (3 Orderer Raft) + Admin CLI + MQTT + Controller

set -e

echo "🚀 Deploying Complete CANA Blockchain System..."

# Step 1: Deploy Fabric Core
echo "📦 Step 1: Deploying Hyperledger Fabric..."
minikube kubectl -- apply -f kubernetes/01-orderer.yaml
minikube kubectl -- apply -f kubernetes/02-peer-zone-a.yaml
minikube kubectl -- apply -f kubernetes/03-peer-zone-b.yaml 
minikube kubectl -- apply -f kubernetes/04-peer-zone-c.yaml
minikube kubectl -- apply -f kubernetes/00-monitoring-complete.yaml
minikube kubectl -- apply -f kubernetes/coredns-fix.yaml
minikube kubectl -- rollout restart deployment coredns -n kube-system

# --- TAMBAHAN PENTING: DEPLOY ADMIN CLI ---
echo "🛠️  Deploying Admin CLI (Required for Init Network)..."
minikube kubectl -- apply -f kubernetes/99-admin-cli.yaml
# ------------------------------------------

echo "⏳ Waiting for Fabric nodes..."
# KOREKSI: Menunggu ketiga Orderer secara terpisah
minikube kubectl -- wait --for=condition=available --timeout=300s \
  deployment/orderer1 \
  deployment/orderer2 \
  deployment/orderer3 \
  deployment/peer-zone-a \
  deployment/peer-zone-b \
  deployment/peer-zone-c \
  -n parking-fabric

# Step 2: Build All App Images (Root Context)
echo "🏗️ Step 2: Building Application Images (API, MQTT, CANA)..."
eval $(minikube docker-env)
# Build dari root folder (.) agar Dockerfile bisa melihat semua file, termasuk folder crypto-config
docker build -t mqtt-bridge:latest -f mqtt-bridge/Dockerfile .
docker build -t api-gateway:latest -f api-gateway/Dockerfile .
docker build -t caa-controller:latest -f caa-controller/Dockerfile .

# Step 3: Deploy Apps & Trigger Update
echo "📡 Step 3: Deploying App Layer & Triggering Hot-Reload..."
minikube kubectl -- apply -f kubernetes/06-mqtt-stack.yaml
minikube kubectl -- apply -f kubernetes/05-caa-controller.yaml

# KUNCI OTOMASI: Memaksa Kubernetes merestart 3 Pod ini agar langsung menggunakan image Docker yang baru dibuat!
minikube kubectl -- rollout restart deployment api-gateway mqtt-bridge caa-controller -n parking-fabric

echo "✅ COMPLETE DEPLOYMENT FINISHED!"
echo "Run 'kubectl get pods -n parking-fabric' to check status."

minikube kubectl -- get pods -n parking-fabric -o wide -w