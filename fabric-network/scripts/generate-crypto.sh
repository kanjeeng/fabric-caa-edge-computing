#!/bin/bash
# fabric-network/scripts/generate-crypto.sh
# VERSI FINAL (3 ORDERER RAFT) - Penyesuaian Domain

set -e

# Pindah ke direktori root 'fabric-network'
cd "$(dirname "$0")/.."

FABRIC_VERSION="2.5.4"

# === PATH YANG BENAR ===
CRYPTO_CONFIG_OUTPUT_DIR="$(pwd)/crypto-config"
CRYPTO_CONFIG_INPUT_FILE="$(pwd)/crypto-config-lite.yaml" 
# ==========================

echo "🔐 Generating Fabric Crypto Materials..."

# Install cryptogen jika tidak ada
if ! command -v cryptogen &> /dev/null; then
    if [ -f "$(pwd)/bin/cryptogen" ]; then
        export PATH=$(pwd)/bin:$PATH
        echo "   Ditemukan cryptogen lokal di $(pwd)/bin"
    else
        echo "📦 Installing Fabric binaries (v$FABRIC_VERSION)..."
        curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh | bash -s -- $FABRIC_VERSION -d -s
        export PATH=$(pwd)/bin:$PATH
        echo "   PATH diatur untuk menyertakan: $(pwd)/bin"
    fi
else
     echo "   Menggunakan cryptogen global di $(which cryptogen)"
fi

# 1. Hapus Folder Crypto Lama agar bersih
if [ -d "$CRYPTO_CONFIG_OUTPUT_DIR" ]; then
    echo "🗑️ Menghapus sertifikat lama..."
    rm -rf "$CRYPTO_CONFIG_OUTPUT_DIR"
fi

# 2. Eksekusi Cryptogen
cryptogen generate --config="$CRYPTO_CONFIG_INPUT_FILE" --output="$CRYPTO_CONFIG_OUTPUT_DIR"

echo "🔧 Memperbaiki struktur Admincerts untuk K8s..."

# === Perbaiki Orderer Org ===
# KOREKSI DOMAIN: Sekarang menggunakan parking.com
ORG_NAME="parking.com"
echo "   - Memproses Orderer Org ($ORG_NAME)..."
ADMIN_CERT_SRC="${CRYPTO_CONFIG_OUTPUT_DIR}/ordererOrganizations/${ORG_NAME}/users/Admin@${ORG_NAME}/msp/signcerts/Admin@${ORG_NAME}-cert.pem"
ADMIN_CERT_DEST_DIR="${CRYPTO_CONFIG_OUTPUT_DIR}/ordererOrganizations/${ORG_NAME}/msp/admincerts"

if [ -f "$ADMIN_CERT_SRC" ]; then
    mkdir -p "$ADMIN_CERT_DEST_DIR"
    cp "$ADMIN_CERT_SRC" "$ADMIN_CERT_DEST_DIR/"
    echo "     ✅ Sertifikat Admin Org disalin ke $ADMIN_CERT_DEST_DIR"
else
    echo "     ❌ KRITIS: Sumber sertifikat Admin Orderer tidak ditemukan di $ADMIN_CERT_SRC"
    exit 1
fi

# === Perbaiki Peer Orgs ===
for zone in zone-a zone-b zone-c; do
    ORG_NAME="${zone}.parking.com"
    echo "   - Memproses Peer Org ($ORG_NAME)..."
    ADMIN_CERT_SRC="${CRYPTO_CONFIG_OUTPUT_DIR}/peerOrganizations/${ORG_NAME}/users/Admin@${ORG_NAME}/msp/signcerts/Admin@${ORG_NAME}-cert.pem"
    ADMIN_CERT_DEST_DIR="${CRYPTO_CONFIG_OUTPUT_DIR}/peerOrganizations/${ORG_NAME}/msp/admincerts"

    if [ -f "$ADMIN_CERT_SRC" ]; then
        mkdir -p "$ADMIN_CERT_DEST_DIR"
        cp "$ADMIN_CERT_SRC" "$ADMIN_CERT_DEST_DIR/"
        echo "     ✅ Sertifikat Admin Org disalin ke $ADMIN_CERT_DEST_DIR"
    else
        echo "     ❌ KRITIS: Sumber sertifikat Admin Peer tidak ditemukan di $ADMIN_CERT_SRC"
        exit 1
    fi
done

echo "🔧 Merename kunci privat CA agar mudah dibaca K8s..."
# KOREKSI LOOP DOMAIN
for org in parking.com zone-a.parking.com zone-b.parking.com zone-c.parking.com; do
    
    if [[ "$org" == "parking.com" ]]; then
        TYPE="ordererOrganizations"
    else
        TYPE="peerOrganizations"
    fi

    # Rename CA key
    CA_DIR="${CRYPTO_CONFIG_OUTPUT_DIR}/${TYPE}/${org}/ca"
    if [ -d "$CA_DIR" ]; then
        PRIV_KEY=$(ls "$CA_DIR"/*_sk 2>/dev/null | head -n 1)
        if [ -n "$PRIV_KEY" ] && [ "$(basename "$PRIV_KEY")" != "priv_sk" ]; then
            mv "$PRIV_KEY" "$CA_DIR/priv_sk"
            echo "     ✅ Rename CA key untuk $org"
        fi
    fi

    # Rename TLS CA key
    TLSCA_DIR="${CRYPTO_CONFIG_OUTPUT_DIR}/${TYPE}/${org}/tlsca"
    if [ -d "$TLSCA_DIR" ]; then
        TLS_PRIV_KEY=$(ls "$TLSCA_DIR"/*_sk 2>/dev/null | head -n 1)
        if [ -n "$TLS_PRIV_KEY" ] && [ "$(basename "$TLS_PRIV_KEY")" != "priv_sk" ]; then
            mv "$TLS_PRIV_KEY" "$TLSCA_DIR/priv_sk"
            echo "     ✅ Rename TLS CA key untuk $org"
        fi
    fi
done

echo "✅ Generate Crypto selesai dengan sukses!"