#!/bin/bash
echo "=== 🕵️ PEMBUKTIAN JEBAKAN MAJORITY (HACKER WAY) ==="

echo "⏳ [1/4] Mematikan Zone B dan Zone C (Menyisakan Zone A saja)..."
minikube kubectl -- scale deployment peer-zone-b peer-zone-c --replicas=0 -n parking-fabric
sleep 15 # Tunggu Pod benar-benar mati

echo "🚀 [2/4] MENGUJI TRANSAKSI KE 1 ZONA SAJA..."
# Kita suntikkan IP lokal ke /etc/hosts agar lolos verifikasi sertifikat TLS!
minikube kubectl -- exec -n parking-fabric admin-cli -- /bin/bash -c '
    # 1. Ambil IP asli dari service Kubernetes
    IP_A=$(getent hosts peer-zone-a | awk "{ print \$1 }")
    # 2. Tulis ke /etc/hosts untuk menipu TLS
    echo "$IP_A peer0.zone-a.parking.com" >> /etc/hosts

    export CORE_PEER_LOCALMSPID=ZoneAMSP
    export CORE_PEER_ADDRESS=peer0.zone-a.parking.com:7051
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/msp/tlscacerts/tlscacert.pem
    export ORDERER_CA=/etc/hyperledger/orderer-tls/tlscacert.pem

    echo ">>> Mengirim Proposal hanya ke Zona A..."
    peer chaincode invoke -o orderer:7050 --tls --cafile $ORDERER_CA \
    -C channel-zone-a -n parking-cc \
    -c "{\"function\":\"InitLedger\",\"Args\":[]}" \
    --ordererTLSHostnameOverride orderer.orderer.parking.com \
    --peerAddresses peer0.zone-a.parking.com:7051 \
    --tlsRootCertFiles /etc/hyperledger/msp/tlscacerts/tlscacert.pem \
    --waitForEvent 2>&1
'
echo "--------------------------------------------------------"
echo "⚠️ PERHATIKAN ERROR DI ATAS!"
echo "Jika pesannya: 'transaction returned with failure: Error: endorsement policy failure', BUKTI PERTAMA TERCAPAI!"
echo "--------------------------------------------------------"

echo "⏳ [3/4] Menyalakan kembali Zone B (Sekarang ada 2 Zona)..."
minikube kubectl -- scale deployment peer-zone-b --replicas=1 -n parking-fabric
echo "Menunggu Zone B siap dan melakukan sinkronisasi blok (30 detik)..."
sleep 30

echo "🚀 [4/4] MENGUJI TRANSAKSI KE 2 ZONA (MAJORITY TERPENUHI)..."
minikube kubectl -- exec -n parking-fabric admin-cli -- /bin/bash -c '
    # 1. Ambil IP
    IP_A=$(getent hosts peer-zone-a | awk "{ print \$1 }")
    IP_B=$(getent hosts peer-zone-b | awk "{ print \$1 }")
    # 2. Tulis ke /etc/hosts
    echo "$IP_A peer0.zone-a.parking.com" >> /etc/hosts
    echo "$IP_B peer0.zone-b.parking.com" >> /etc/hosts

    export CORE_PEER_LOCALMSPID=ZoneAMSP
    export CORE_PEER_ADDRESS=peer0.zone-a.parking.com:7051
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/msp/tlscacerts/tlscacert.pem
    export ORDERER_CA=/etc/hyperledger/orderer-tls/tlscacert.pem

    echo ">>> Mengirim Proposal ke Zona A dan Zona B..."
    peer chaincode invoke -o orderer:7050 --tls --cafile $ORDERER_CA \
    -C channel-zone-a -n parking-cc \
    -c "{\"function\":\"InitLedger\",\"Args\":[]}" \
    --ordererTLSHostnameOverride orderer.orderer.parking.com \
    --peerAddresses peer0.zone-a.parking.com:7051 \
    --tlsRootCertFiles /etc/hyperledger/msp/tlscacerts/tlscacert.pem \
    --peerAddresses peer0.zone-b.parking.com:7051 \
    --tlsRootCertFiles /etc/hyperledger/msp/tlscacerts/tlscacert.pem \
    --waitForEvent 2>&1
'
echo "✅ JIKA STATUSNYA SUKSES, PEMBUKTIAN SELESAI!"
echo "Kesimpulan: Sistem MENOLAK keras jika hanya 1 tanda tangan, dan MENERIMA jika 2 tanda tangan terkumpul."