#!/bin/bash
# scripts/03-upload-to-k8s.sh
# VERSI FINAL: Upload Secrets (FIXED PEER SECRET NAME)

set -e

FABRIC_ROOT="fabric-network"
CRYPTO_CONFIG="$FABRIC_ROOT/crypto-config"
CHANNEL_ARTIFACTS="$FABRIC_ROOT/channel-artifacts"
NAMESPACE="parking-fabric"

echo "📦 Uploading Fabric Materials to Kubernetes..."

# 1. BUAT NAMESPACE
minikube kubectl -- create namespace $NAMESPACE --dry-run=client -o yaml | minikube kubectl -- apply -f -
minikube kubectl -- create namespace monitoring --dry-run=client -o yaml | minikube kubectl -- apply -f -

# 2. UPLOAD ARTIFACTS
minikube kubectl -- create configmap genesis-block --from-file=genesis.block=$CHANNEL_ARTIFACTS/genesis.block -n $NAMESPACE --dry-run=client -o yaml | minikube kubectl -- apply -f -
minikube kubectl -- create configmap channel-artifacts --from-file=$CHANNEL_ARTIFACTS -n $NAMESPACE --dry-run=client -o yaml | minikube kubectl -- apply -f -

# 3. UPLOAD ORDERER SECRETS (3 Node Raft)
echo "🔐 Step 3: Uploading 3 Orderer Secrets..."
for i in 1 2 3; do
  ORD_HOST="orderer${i}.parking.com"
  ORD_PATH="$CRYPTO_CONFIG/ordererOrganizations/parking.com/orderers/$ORD_HOST"
  ORD_USER="$CRYPTO_CONFIG/ordererOrganizations/parking.com/users/Admin@parking.com/msp"
  ORD_KEY=$(ls $ORD_PATH/msp/keystore/*_sk | head -n 1)

  minikube kubectl -- create secret generic orderer${i}-msp-secret \
    --from-file=server.crt=$ORD_PATH/tls/server.crt \
    --from-file=server.key=$ORD_PATH/tls/server.key \
    --from-file=ca.crt=$ORD_PATH/tls/ca.crt \
    --from-file=signcert.pem=$ORD_PATH/msp/signcerts/${ORD_HOST}-cert.pem \
    --from-file=keystore.pem=$ORD_KEY \
    --from-file=cacert.pem=$ORD_PATH/msp/cacerts/ca.parking.com-cert.pem \
    --from-file=tlscacert.pem=$ORD_PATH/msp/tlscacerts/tlsca.parking.com-cert.pem \
    --from-file=admincert.pem=$ORD_USER/signcerts/Admin@parking.com-cert.pem \
    -n $NAMESPACE --dry-run=client -o yaml | minikube kubectl -- apply -f -
done

# 4. UPLOAD PEER SECRETS (Zone A, B, C)
echo "🔐 Step 4: Uploading Peer Secrets..."
for zone in zone-a zone-b zone-c; do
  PEER_PATH="$CRYPTO_CONFIG/peerOrganizations/${zone}.parking.com/peers/peer0.${zone}.parking.com"
  PEER_ADMIN="$CRYPTO_CONFIG/peerOrganizations/${zone}.parking.com/users/Admin@${zone}.parking.com/msp"
  PEER_KEY=$(ls $PEER_PATH/msp/keystore/*_sk | head -n 1)

  # MSP Secret (FIXED: dihapus akhiran -secret nya agar cocok dengan K8s YAML)
  minikube kubectl -- create secret generic ${zone}-msp \
    --from-file=signcert.pem=$PEER_PATH/msp/signcerts/peer0.${zone}.parking.com-cert.pem \
    --from-file=keystore.pem=$PEER_KEY \
    --from-file=cacert.pem=$PEER_PATH/msp/cacerts/ca.${zone}.parking.com-cert.pem \
    --from-file=tlscacert.pem=$PEER_PATH/msp/tlscacerts/tlsca.${zone}.parking.com-cert.pem \
    --from-file=admincert.pem=$PEER_ADMIN/signcerts/Admin@${zone}.parking.com-cert.pem \
    -n $NAMESPACE --dry-run=client -o yaml | minikube kubectl -- apply -f -

  # TLS Secret
  minikube kubectl -- create secret generic ${zone}-tls \
    --from-file=server.crt=$PEER_PATH/tls/server.crt \
    --from-file=server.key=$PEER_PATH/tls/server.key \
    --from-file=ca.crt=$PEER_PATH/tls/ca.crt \
    -n $NAMESPACE --dry-run=client -o yaml | minikube kubectl -- apply -f -
done

# 5. UPLOAD ADMIN USER SECRET
echo "👤 Step 5: Uploading Admin User Secret (Zone A)..."
ADMIN_PATH="$CRYPTO_CONFIG/peerOrganizations/zone-a.parking.com/users/Admin@zone-a.parking.com/msp"
ADMIN_KEY=$(ls $ADMIN_PATH/keystore/*_sk | head -n 1)

minikube kubectl -- create secret generic zone-a-admin \
  --from-file=admincert.pem=$ADMIN_PATH/signcerts/Admin@zone-a.parking.com-cert.pem \
  --from-file=cacert.pem=$ADMIN_PATH/cacerts/ca.zone-a.parking.com-cert.pem \
  --from-file=keystore.pem=$ADMIN_KEY \
  --from-file=signcert.pem=$ADMIN_PATH/signcerts/Admin@zone-a.parking.com-cert.pem \
  --from-file=tlscacert.pem=$ADMIN_PATH/tlscacerts/tlsca.zone-a.parking.com-cert.pem \
  --from-file=config.yaml=$ADMIN_PATH/config.yaml \
  -n $NAMESPACE --dry-run=client -o yaml | minikube kubectl -- apply -f -

eval $(minikube docker-env)

docker network create parking-fabric || true

docker pull hyperledger/fabric-ccenv:2.5
docker pull hyperledger/fabric-baseos:2.5

echo "✅ Semua konfigurasi dan secret berhasil diunggah!"