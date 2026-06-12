#!/bin/bash
# fabric-network/scripts/generate-genesis.sh
# VERSI PATEN & DESENTRALISASI SEJATI (Hanya 1 Channel Utama Konsorsium)

set -e

# Pindah ke direktori root 'fabric-network'
cd "$(dirname "$0")/.."

# --- PENTING: Tambahkan bin ke PATH ---
if [ -d "$(pwd)/bin" ]; then
    export PATH=$(pwd)/bin:$PATH
else
    echo "🔎 'bin' folder not found, trying to download binaries..."
    curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh | bash -s -- 2.5.4 -d -s
    export PATH=$(pwd)/bin:$PATH
fi
# -----------------------------------

CHANNEL_ARTIFACTS="$(pwd)/channel-artifacts"
CONFIG_PATH="$(pwd)/config" 

export FABRIC_CFG_PATH=$CONFIG_PATH

echo "📦 Generating Genesis Block & Channel Artifacts..."

# Validasi
if [ ! -f "$CONFIG_PATH/configtx.yaml" ]; then
    echo "❌ Error: 'configtx.yaml' tidak ditemukan di $CONFIG_PATH"
    exit 1
fi
if ! command -v configtxgen &> /dev/null; then
    echo "❌ Error: 'configtxgen' tidak ditemukan di PATH."
    exit 1
fi

# 1. Bersihkan artifacts lama
rm -rf $CHANNEL_ARTIFACTS
mkdir -p $CHANNEL_ARTIFACTS

# 2. Generate genesis block
echo "🔨 Generating genesis block (System Channel)..."
configtxgen -profile ThreeZonesOrdererGenesis \
  -channelID system-channel \
  -outputBlock $CHANNEL_ARTIFACTS/genesis.block

# 3. Generate channel creation transactions
echo "📋 Generating channel transactions (Satu Channel Utama: channel-zone-a)..."
# KITA HANYA BUTUH 1 CHANNEL KARENA KETIGA ZONA SUDAH GABUNG DI SINI
configtxgen -profile ParkingZoneAChannel \
  -outputCreateChannelTx $CHANNEL_ARTIFACTS/channel-zone-a.tx \
  -channelID channel-zone-a

# 4. Generate anchor peer updates
echo "⚓ Generating anchor peer updates (Ketiga Zona di channel-zone-a)..."
# Perhatikan: Semua profile sekarang mengarah ke ParkingZoneAChannel
configtxgen -profile ParkingZoneAChannel \
  -outputAnchorPeersUpdate $CHANNEL_ARTIFACTS/ZoneAMSPanchors.tx \
  -channelID channel-zone-a \
  -asOrg ZoneAMSP

configtxgen -profile ParkingZoneAChannel \
  -outputAnchorPeersUpdate $CHANNEL_ARTIFACTS/ZoneBMSPanchors.tx \
  -channelID channel-zone-a \
  -asOrg ZoneBMSP

configtxgen -profile ParkingZoneAChannel \
  -outputAnchorPeersUpdate $CHANNEL_ARTIFACTS/ZoneCMSPanchors.tx \
  -channelID channel-zone-a \
  -asOrg ZoneCMSP

echo ""
echo "✅ Genesis block and all channel artifacts for Decentralized Network successfully generated!"
echo "📁 Files generated in: $CHANNEL_ARTIFACTS"
ls -lh $CHANNEL_ARTIFACTS