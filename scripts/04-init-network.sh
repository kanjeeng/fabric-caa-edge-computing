#!/bin/bash
# scripts/04-init-network.sh
# VERSI FINAL - DNS FIX + TLS SAN FIX + 3 ORDERER RAFT

set -e
echo "🚀 MEMULAI INISIALISASI JARINGAN FABRIC DESENTRALISASI (3 ORDERER)..."

echo "📁 Menyiapkan struktur folder di dalam admin-cli..."
minikube kubectl -- exec -n parking-fabric admin-cli -- mkdir -p /opt/gopath/src/github.com/chaincode/parking /opt/crypto-config /opt/channel-artifacts

echo "📦 Menyalin data ke admin-cli..."
minikube kubectl -- cp chaincode/parking/. parking-fabric/admin-cli:/opt/gopath/src/github.com/chaincode/parking/
minikube kubectl -- cp fabric-network/crypto-config/. parking-fabric/admin-cli:/opt/crypto-config/
minikube kubectl -- cp fabric-network/channel-artifacts/. parking-fabric/admin-cli:/opt/channel-artifacts/

minikube kubectl -- exec -n parking-fabric admin-cli -- /bin/bash -c '
    # --- KUNCI PENYELAMAT: SUNTIK DNS KUBERNETES KE DALAM ADMIN-CLI ---
    echo "$ORDERER1_SERVICE_HOST orderer1.parking.com" >> /etc/hosts
    echo "$PEER_ZONE_A_SERVICE_HOST peer0.zone-a.parking.com" >> /etc/hosts
    echo "$PEER_ZONE_B_SERVICE_HOST peer0.zone-b.parking.com" >> /etc/hosts
    echo "$PEER_ZONE_C_SERVICE_HOST peer0.zone-c.parking.com" >> /etc/hosts
    # ------------------------------------------------------------------

    export PATH=$PATH:/etc/hyperledger/fabric/bin
    export FABRIC_CFG_PATH=/etc/hyperledger/fabric
    export CORE_PEER_TLS_ENABLED=true
    
    export ORDERER_CA=/opt/crypto-config/ordererOrganizations/parking.com/orderers/orderer1.parking.com/tls/ca.crt
    
    CHANNEL_NAME="channel-zone-a"
    ORDERER_ADDR="orderer1.parking.com:7050"
    
    CC_NAME="parking-cc"
    CC_VERSION="1.0"
    CC_SEQ="1"
    
    CC_POLICY="OR('\''ZoneAMSP.peer'\'', '\''ZoneBMSP.peer'\'', '\''ZoneCMSP.peer'\'')"

    setGlobals() {
        ORG=$1
        if [ "$ORG" == "A" ]; then
            export CORE_PEER_LOCALMSPID="ZoneAMSP"
            export CORE_PEER_TLS_ROOTCERT_FILE=/opt/crypto-config/peerOrganizations/zone-a.parking.com/peers/peer0.zone-a.parking.com/tls/ca.crt
            export CORE_PEER_MSPCONFIGPATH=/opt/crypto-config/peerOrganizations/zone-a.parking.com/users/Admin@zone-a.parking.com/msp
            # KEMBALI MENGGUNAKAN NAMA DOMAIN RESMI AGAR LOLOS CEK KTP TLS
            export CORE_PEER_ADDRESS=peer0.zone-a.parking.com:7051 
            export CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.zone-a.parking.com
        elif [ "$ORG" == "B" ]; then
            export CORE_PEER_LOCALMSPID="ZoneBMSP"
            export CORE_PEER_TLS_ROOTCERT_FILE=/opt/crypto-config/peerOrganizations/zone-b.parking.com/peers/peer0.zone-b.parking.com/tls/ca.crt
            export CORE_PEER_MSPCONFIGPATH=/opt/crypto-config/peerOrganizations/zone-b.parking.com/users/Admin@zone-b.parking.com/msp
            export CORE_PEER_ADDRESS=peer0.zone-b.parking.com:7051
            export CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.zone-b.parking.com
        elif [ "$ORG" == "C" ]; then
            export CORE_PEER_LOCALMSPID="ZoneCMSP"
            export CORE_PEER_TLS_ROOTCERT_FILE=/opt/crypto-config/peerOrganizations/zone-c.parking.com/peers/peer0.zone-c.parking.com/tls/ca.crt
            export CORE_PEER_MSPCONFIGPATH=/opt/crypto-config/peerOrganizations/zone-c.parking.com/users/Admin@zone-c.parking.com/msp
            export CORE_PEER_ADDRESS=peer0.zone-c.parking.com:7051
            export CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.zone-c.parking.com
        fi
        echo "🔄 Konteks diubah ke: Admin Zone $ORG ($CORE_PEER_ADDRESS)"
    }

    echo "-------------------------------------------------"
    echo ">>> A. CREATE & JOIN CHANNEL"
    echo "-------------------------------------------------"
    setGlobals "A"
    peer channel create -o $ORDERER_ADDR -c $CHANNEL_NAME -f /opt/channel-artifacts/channel-zone-a.tx --outputBlock /tmp/${CHANNEL_NAME}.block --tls --cafile $ORDERER_CA --ordererTLSHostnameOverride orderer1.parking.com || echo "Channel exists"

    for org in A B C; do
        setGlobals $org
        peer channel join -b /tmp/${CHANNEL_NAME}.block || echo "Already joined"
    done

    echo "-------------------------------------------------"
    echo ">>> B. UPDATE ANCHOR PEERS"
    echo "-------------------------------------------------"
    setGlobals "A"
    peer channel update -o $ORDERER_ADDR -c $CHANNEL_NAME -f /opt/channel-artifacts/ZoneAMSPanchors.tx --tls --cafile $ORDERER_CA --ordererTLSHostnameOverride orderer1.parking.com || echo "Anchor peer A already updated"
    setGlobals "B"
    peer channel update -o $ORDERER_ADDR -c $CHANNEL_NAME -f /opt/channel-artifacts/ZoneBMSPanchors.tx --tls --cafile $ORDERER_CA --ordererTLSHostnameOverride orderer1.parking.com || echo "Anchor peer B already updated"
    setGlobals "C"
    peer channel update -o $ORDERER_ADDR -c $CHANNEL_NAME -f /opt/channel-artifacts/ZoneCMSPanchors.tx --tls --cafile $ORDERER_CA --ordererTLSHostnameOverride orderer1.parking.com || echo "Anchor peer C already updated"

    echo "-------------------------------------------------"
    echo ">>> C. PACKAGING & INSTALL CHAINCODE"
    echo "-------------------------------------------------"
    setGlobals "A"
    cd /opt/gopath/src/github.com/chaincode/parking
    go mod tidy
    peer lifecycle chaincode package /tmp/${CC_NAME}.tar.gz --path . --lang golang --label ${CC_NAME}_${CC_VERSION}

    for org in A B C; do
        setGlobals $org
        peer lifecycle chaincode install /tmp/${CC_NAME}.tar.gz || echo "⚠️ Sudah terinstall"
    done

    setGlobals "A"
    PKG_ID=$(peer lifecycle chaincode queryinstalled | grep ${CC_NAME}_${CC_VERSION} | awk "{print \$3}" | sed "s/,//")
    echo "🔑 Package ID: $PKG_ID"

    echo "-------------------------------------------------"
    echo ">>> D. APPROVE CHAINCODE (DENGAN EXPLICIT POLICY)"
    echo "-------------------------------------------------"
    for org in A B C; do
        setGlobals $org
        echo "✅ Approving for Zone $org..."
        peer lifecycle chaincode approveformyorg -o $ORDERER_ADDR --channelID $CHANNEL_NAME --name $CC_NAME --version $CC_VERSION --package-id $PKG_ID --sequence $CC_SEQ --signature-policy "$CC_POLICY" --tls --cafile $ORDERER_CA --ordererTLSHostnameOverride orderer1.parking.com
    done
    
    echo "⏳ Menunggu ledger mencatat approval (10 detik)..."
    sleep 10

    echo "-------------------------------------------------"
    echo ">>> E. CHECK COMMIT READINESS"
    echo "-------------------------------------------------"
    setGlobals "A"
    peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name $CC_NAME --version $CC_VERSION --sequence $CC_SEQ --signature-policy "$CC_POLICY" --tls --cafile $ORDERER_CA --ordererTLSHostnameOverride orderer1.parking.com --output json

    echo "-------------------------------------------------"
    echo ">>> F. COMMIT CHAINCODE"
    echo "-------------------------------------------------"
    setGlobals "A"
    unset CORE_PEER_TLS_SERVERHOSTOVERRIDE
    
    echo "🚀 Executing Commit..."
    peer lifecycle chaincode commit -o $ORDERER_ADDR --channelID $CHANNEL_NAME --name $CC_NAME --version $CC_VERSION --sequence $CC_SEQ --signature-policy "$CC_POLICY" --tls --cafile $ORDERER_CA --ordererTLSHostnameOverride orderer1.parking.com \
        --peerAddresses peer0.zone-a.parking.com:7051 --tlsRootCertFiles /opt/crypto-config/peerOrganizations/zone-a.parking.com/peers/peer0.zone-a.parking.com/tls/ca.crt \
        --peerAddresses peer0.zone-b.parking.com:7051 --tlsRootCertFiles /opt/crypto-config/peerOrganizations/zone-b.parking.com/peers/peer0.zone-b.parking.com/tls/ca.crt \
        --peerAddresses peer0.zone-c.parking.com:7051 --tlsRootCertFiles /opt/crypto-config/peerOrganizations/zone-c.parking.com/peers/peer0.zone-c.parking.com/tls/ca.crt
    
    echo "⏳ Menunggu container chaincode menyala (60 detik)..."
    sleep 60
    
    echo "-------------------------------------------------"
    echo ">>> G. INVOKE INIT LEDGER"
    echo "-------------------------------------------------"
    peer chaincode invoke -o $ORDERER_ADDR -C $CHANNEL_NAME -n $CC_NAME -c "{\"function\":\"InitLedger\",\"Args\":[]}" --tls --cafile $ORDERER_CA --ordererTLSHostnameOverride orderer1.parking.com \
        --peerAddresses peer0.zone-a.parking.com:7051 --tlsRootCertFiles /opt/crypto-config/peerOrganizations/zone-a.parking.com/peers/peer0.zone-a.parking.com/tls/ca.crt \
        --peerAddresses peer0.zone-b.parking.com:7051 --tlsRootCertFiles /opt/crypto-config/peerOrganizations/zone-b.parking.com/peers/peer0.zone-b.parking.com/tls/ca.crt \
        --peerAddresses peer0.zone-c.parking.com:7051 --tlsRootCertFiles /opt/crypto-config/peerOrganizations/zone-c.parking.com/peers/peer0.zone-c.parking.com/tls/ca.crt

    echo "================================================="
    echo "✅ SUKSES! BLOCKCHAIN DESENTRALISASI 3 ZONA & 3 ORDERER SIAP!"
    echo "================================================="
'