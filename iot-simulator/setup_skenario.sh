#!/bin/bash
# setup_skenario.sh - Versi Super Dinamis (Alpha, Beta, Chaos, dan Zone Targeting)

ALPHA=""
BETA=""
CHAOS=""
TARGET_ZONE="zone-a" # Default
DIR="~/Desktop/parking-blockchain-lite/iot-simulator"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "========================================================="
            echo "🛠️ CARA PENGGUNAAN SETUP SKENARIO DINAMIS"
            echo "========================================================="
            echo "Usage: ./setup_skenario.sh [-a ALPHA] [-b BETA] [-c CHAOS_MS] [-z TARGET_ZONE]"
            echo ""
            echo "Opsi:"
            echo "  -a, --alpha   Bobot CPU (Contoh: 0.5)"
            echo "  -b, --beta    Bobot Queue (Contoh: 0.5)"
            echo "  -c, --chaos   Injeksi latensi ms (Contoh: 50, 150)"
            echo "  -z, --zone    Target Zona (Contoh: zone-a, zone-b, zone-c)"
            echo ""
            echo "Contoh Perintah:"
            echo "  1. Uji Zone A (CAA) : ./setup_skenario.sh -a 0.5 -b 0.5 -z zone-a"
            echo "  2. Uji Zone C (Chaos): ./setup_skenario.sh -a 0.5 -b 0.5 -c 100 -z zone-c"
            exit 0
            ;;
        -a|--alpha) ALPHA="$2"; shift ;;
        -b|--beta) BETA="$2"; shift ;;
        -c|--chaos) CHAOS="$2"; shift ;;
        -z|--zone) TARGET_ZONE="$2"; shift ;;
        *) echo "❌ Parameter tidak dikenal: $1"; exit 1 ;;
    esac
    shift
done

USE_CAA=false
if [[ -n "$ALPHA" && -n "$BETA" ]]; then
    USE_CAA=true
elif [[ -n "$ALPHA" || -n "$BETA" ]]; then
    echo "❌ Error: Masukkan KEDUANYA (-a dan -b) untuk CAA."
    exit 1
fi

echo "========================================================="
echo "🔍 [0/4] MEMERIKSA PRASYARAT INFRASTRUKTUR (CHAOS MESH)..."
echo "========================================================="
CHECK_CHAOS=$(minikube kubectl -- get crd networkchaos.chaos-mesh.org 2>/dev/null)

if [[ -z "$CHECK_CHAOS" ]]; then
    echo "⚠️ Memori Chaos Mesh tidak ditemukan di Minikube!"
    echo "🛠️ Memulai Auto-Instalasi via Helm..."
    helm repo add chaos-mesh https://charts.chaos-mesh.org
    helm repo update
    helm install chaos-mesh chaos-mesh/chaos-mesh -n=chaos-mesh --create-namespace
    
    echo "⏳ Menunggu Pod Chaos Mesh siap (Bisa memakan waktu 1-2 menit)..."
    sleep 10
    minikube kubectl -- wait --for=condition=ready pod -l app.kubernetes.io/instance=chaos-mesh -n chaos-mesh --timeout=300s
    echo "✅ Auto-Instalasi Chaos Mesh Selesai!"
else
    echo "✅ Chaos Mesh sudah aktif dan siap digunakan."
fi
echo "========================================================="

echo "🔄 [1/4] MERESET KONDISI CLUSTER & ISOLASI ZONA ($TARGET_ZONE)..."
echo "========================================================="

# Hapus HPA & Chaos lama
minikube kubectl -- delete hpa peer-zone-a-hpa peer-zone-b peer-zone-c -n parking-fabric --ignore-not-found=true
minikube kubectl -- scale deployment caa-controller --replicas=0 -n parking-fabric
minikube kubectl -- delete networkchaos regional-latency -n parking-fabric --ignore-not-found=true

# Logika Dinamis untuk Mengunci Zona
for z in zone-a zone-b zone-c; do
    if [ "$z" == "$TARGET_ZONE" ]; then
        echo "🔄 Mereset $z ke 1 Pod (Target Autoscaling)..."
    else
        echo "🔒 Mengunci $z ke 1 Pod (Ledger Statis)..."
    fi
    minikube kubectl -- scale deployment peer-$z --replicas=1 -n parking-fabric
done

# Reset komponen lain
minikube kubectl -- scale deployment mqtt-bridge --replicas=1 -n parking-fabric
minikube kubectl -- scale deployment api-gateway --replicas=1 -n parking-fabric

echo "🧹 Me-restart Cache Memori Gateway & MQTT..."
minikube kubectl -- rollout restart deployment api-gateway mqtt-bridge caa-controller -n parking-fabric

echo "⏳ Menunggu 20 detik agar sistem stabil..."
sleep 20

echo "🚀 [2/4] MENYIAPKAN AUTOSCALER..."
if [ "$USE_CAA" = true ]; then
    echo "✅ MENGAKTIFKAN CAA (Target: $TARGET_ZONE | Bobot CPU $ALPHA : Queue $BETA)..."
    # KUNCI PERBAIKAN: Mengirim variabel TARGET_ZONE ke dalam Pod CAA
    minikube kubectl -- set env deployment/caa-controller WEIGHT_CPU=$ALPHA WEIGHT_LATENCY=$BETA TARGET_ZONE=$TARGET_ZONE -n parking-fabric
    minikube kubectl -- scale deployment caa-controller --replicas=1 -n parking-fabric
else
    echo "✅ MENGAKTIFKAN HPA STANDAR KUBERNETES..."
    minikube kubectl -- apply -f $DIR/hpa-peer.yaml
fi

echo "🌪️ [3/4] MENYIAPKAN KONDISI JARINGAN..."
if [[ -n "$CHAOS" ]]; then
    echo "😈 KONDISI CHAOS: Menginjeksi Network Delay ${CHAOS}ms ke $TARGET_ZONE..."
    cat <<EOF | minikube kubectl -- apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: regional-latency
  namespace: parking-fabric
spec:
  action: delay
  mode: all
  selector:
    labelSelectors:
      "app": "fabric-peer"
      "zone": "${TARGET_ZONE}"
  delay:
    latency: "${CHAOS}ms"
    correlation: "100"
    jitter: "10ms"
EOF
else
    echo "☀️ KONDISI IDEAL: Jaringan normal."
fi

echo "🎯 [4/4] SETUP SELESAI UNTUK $TARGET_ZONE!"