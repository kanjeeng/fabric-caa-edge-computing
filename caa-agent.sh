#!/bin/bash
# cana-agent.sh
# VERSI FINAL - FIX SILENT ERROR, GENESIS BLOCK FETCH, GRPC TIMEOUT, & GHOST LOOP

echo "🤖 [CANA AGENT] Memulai Automasi Provisioning Node (Paralel & Pantang Menyerah)..."
echo "--------------------------------------------------------"

echo "📥 Meminta Application Channel Block (Block 0) dari Orderer..."
minikube kubectl -- exec admin-cli -n parking-fabric -- sh -c 'peer channel fetch 0 /tmp/app-channel.block -c channel-zone-a -o orderer1:7050 --ordererTLSHostnameOverride orderer1.parking.com --tls --cafile /opt/crypto-config/ordererOrganizations/parking.com/orderers/orderer1.parking.com/tls/ca.crt'

CHECK_FILE=$(minikube kubectl -- exec admin-cli -n parking-fabric -- ls /tmp/app-channel.block 2>/dev/null)
if [[ -z "$CHECK_FILE" ]]; then
    echo "❌ GAGAL: Block Aplikasi tidak ditemukan dari Orderer! Hentikan agen."
    exit 1
fi

echo "✅ Block Aplikasi murni berhasil disiapkan di /tmp/app-channel.block"
echo "--------------------------------------------------------"

PROCESSED_IPS=""

warmup_pod() {
    local IP=$1
    echo "🎯 [AGENT] Memproses Pod Baru: $IP ..."
    
    echo "   🔗 [$IP] Menginjeksi Join Channel..."
    minikube kubectl -- exec admin-cli -n parking-fabric -- sh -c "CORE_PEER_ADDRESS=$IP:7051 CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.zone-a.parking.com peer channel join -b /tmp/app-channel.block"
    
    echo "   📦 [$IP] Menginjeksi Install Chaincode (.tar.gz)..."
    minikube kubectl -- exec admin-cli -n parking-fabric -- sh -c "CORE_PEER_ADDRESS=$IP:7051 CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.zone-a.parking.com peer lifecycle chaincode install /tmp/parking-cc.tar.gz"
    
    echo "   ⏳ [$IP] Menunggu Peer mendownload Ledger dan Kompilasi (Sync Blocks)..."
    sleep 30 
    
    echo "   🔥 [$IP] Melakukan Tembakan Pemanasan (Memicu Build Container Docker)..."
    
    local attempt=1
    local max_attempts=30 # Maksimal 30 kali percobaan (sekitar 5 menit)
    
    while [ $attempt -le $max_attempts ]; do
        
        # --- FIX UTAMA: SENSOR DENYUT NADI (MENGHINDARI GHOST LOOP) ---
        # Cek ke K8s apakah IP ini masih ada di daftar Pod yang berstatus 'Running'
        IS_ALIVE=$(minikube kubectl -- get pods -n parking-fabric -l app=fabric-peer,zone=zone-a --field-selector=status.phase=Running -o jsonpath='{.items[*].status.podIP}')
        if [[ "$IS_ALIVE" != *"$IP"* ]]; then
            echo "      💀 [$IP] ABORT! Pod sudah mati atau Terminating karena Scale-Down. Menghentikan percobaan."
            break
        fi
        # ---------------------------------------------------------------
        
        echo "      [Percobaan $attempt] Menembak Peer $IP..."
        
        OUTPUT=$(minikube kubectl -- exec admin-cli -n parking-fabric -- sh -c "CORE_PEER_CLIENTCONNTIMEOUT=120s CORE_PEER_ADDRESS=$IP:7051 CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.zone-a.parking.com peer chaincode query -C channel-zone-a -n parking-cc -c '{\"Args\":[\"WarmupPing\"]}'" 2>&1)
        
        if [[ "$OUTPUT" == *"Function WarmupPing not found"* ]]; then
            echo "      ✅ BINGO! [$IP] Container Chaincode sudah BANGUN dan siap tempur."
            break
        else
            echo "      ⚠️ [$IP] Log Error: $OUTPUT"
            echo "      ⚠️ [$IP] Peer belum siap (Masih proses Build/Sync). Coba lagi dalam 10 detik..."
            sleep 10
        fi
        
        ((attempt++))
    done
    
    # PERBAIKAN DI SINI (mengganti 'do' menjadi 'then')
    if [ $attempt -gt $max_attempts ]; then
        echo "      ❌ [$IP] TIMEOUT! Gagal melakukan warmup setelah $max_attempts percobaan."
    fi
    
    echo "--------------------------------------------------------"
}

while true; do
    POD_IPS=$(minikube kubectl -- get pods -n parking-fabric -l app=fabric-peer,zone=zone-a --field-selector=status.phase=Running -o jsonpath='{.items[*].status.podIP}')
    
    for IP in $POD_IPS; do
        if [[ "$PROCESSED_IPS" != *"$IP "* ]]; then
            PROCESSED_IPS="$PROCESSED_IPS$IP " 
            warmup_pod "$IP" &
        fi
    done
    sleep 3
done