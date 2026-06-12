const { connect, signers } = require('@hyperledger/fabric-gateway');
const grpc = require('@grpc/grpc-js');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const channelName = 'channel-zone-a';
const chaincodeName = 'parking-cc';
const mspId = 'ZoneAMSP';

// MENGGUNAKAN DOMAIN SESUAI /etc/hosts BARU ANDA
const peerEndpoint = 'peer0.zone-a.parking.com:7051';
const peerHostAlias = 'peer0.zone-a.parking.com';

const cryptoPath = path.resolve(__dirname, '..', 'fabric-network', 'crypto-config', 'peerOrganizations', 'zone-a.parking.com');
const certPath = path.join(cryptoPath, 'users', 'User1@zone-a.parking.com', 'msp', 'signcerts', 'User1@zone-a.parking.com-cert.pem');
const keyPath = path.join(cryptoPath, 'users', 'User1@zone-a.parking.com', 'msp', 'keystore', 'priv_sk');
const tlsCertPath = path.join(cryptoPath, 'peers', 'peer0.zone-a.parking.com', 'tls', 'ca.crt');

async function main() {
    console.log("🌊 Memulai LOAD GENERATOR - Skenario B (BEBAN MERATA & AUTO-RECONNECT)...");

    const tlsRootCert = await fs.promises.readFile(tlsCertPath);
    const credentials = await fs.promises.readFile(certPath);
    const privateKeyPem = await fs.promises.readFile(keyPath);
    const privateKey = crypto.createPrivateKey(privateKeyPem);
    const signer = signers.newPrivateKeySigner(privateKey);

    let counter = 1;
    const BATCH_SIZE = 50; // Putus koneksi setiap 50 transaksi agar K8s Load Balancer bekerja

    while (true) {
        console.log(`\n🔄 [RECONNECT] Membuka Koneksi Baru via Gerbang Service (Batch ${counter} - ${counter + BATCH_SIZE - 1})...`);
        
        const tlsCredentials = grpc.credentials.createSsl(tlsRootCert);
        const client = new grpc.Client(peerEndpoint, tlsCredentials, {
            'grpc.ssl_target_name_override': peerHostAlias,
            'grpc.max_receive_message_length': -1,
            'grpc.max_send_message_length': -1,
        });

        const gateway = connect({ client, identity: { mspId, credentials }, signer });

        try {
            const network = gateway.getNetwork(channelName);
            const contract = network.getContract(chaincodeName);

            const promises = [];
            for (let i = 0; i < BATCH_SIZE; i++) {
                const spotId = `spot-mrt-${counter % 1000}`;
                const targetZone = 'zone-a'; 

                // Masukkan ke array tanpa 'await' di depan
                promises.push(
                    contract.submitTransaction('UpdateSpotStatus', spotId, 'occupied', targetZone)
                    .then(() => process.stdout.write('✅'))
                    .catch(err => process.stdout.write('❌'))
                );
                counter++;
            }

            // Eksekusi semuanya sekaligus dan tunggu sampai selesai
            await Promise.all(promises);
        } finally {
            // TUTUP KONEKSI SECARA PAKSA! Ini akan memaksa Istio/K8s Service memindahkan trafik ke pod baru
            gateway.close();
            client.close();
            console.log(`\n🔌 [DISCONNECT] Koneksi diputus. Mencari IP Pod baru...`);
            await new Promise(resolve => setTimeout(resolve, 1000)); // Jeda 1 detik sebelum Reconnect
        }
    }
}

main().catch(console.error);