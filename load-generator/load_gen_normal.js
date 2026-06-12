/*
 * LOAD GENERATOR - NORMAL MODE (HEARTBEAT)
 * Deskripsi: Mengirim transaksi santai (1 tx per 2 detik) menggunakan @hyperledger/fabric-gateway
 * Tujuannya: Menjaga Pod Peer agar tidak "tidur" (idle) dan mencegah error "No Metadata".
 */

const { connect, signers } = require('@hyperledger/fabric-gateway');
const grpc = require('@grpc/grpc-js');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// --- KONFIGURASI (SAMA PERSIS DENGAN FILE ANDA) ---
const channelName = 'channel-zone-a';
const chaincodeName = 'parking-cc';
const mspId = 'ZoneAMSP';
const peerEndpoint = 'localhost:7051';
const peerHostAlias = 'peer0.zone-a.parking.com';

const cryptoPath = path.resolve(__dirname, '..', 'fabric-network', 'crypto-config', 'peerOrganizations', 'zone-a.parking.com');
const certPath = path.join(cryptoPath, 'users', 'User1@zone-a.parking.com', 'msp', 'signcerts', 'User1@zone-a.parking.com-cert.pem');
const keyPath = path.join(cryptoPath, 'users', 'User1@zone-a.parking.com', 'msp', 'keystore', 'priv_sk');
const tlsCertPath = path.join(cryptoPath, 'peers', 'peer0.zone-a.parking.com', 'tls', 'ca.crt');

async function main() {
    console.log("💓 Memulai Normal Load (Heartbeat Mode)...");

    // --- SETUP KONEKSI (SAMA DENGAN SCRIPT LAMA) ---
    const tlsRootCert = await fs.promises.readFile(tlsCertPath);
    const tlsCredentials = grpc.credentials.createSsl(tlsRootCert);

    const client = new grpc.Client(peerEndpoint, tlsCredentials, {
        'grpc.ssl_target_name_override': peerHostAlias,
        'grpc.max_receive_message_length': -1,
        'grpc.max_send_message_length': -1,
    });

    const credentials = await fs.promises.readFile(certPath);
    const privateKeyPem = await fs.promises.readFile(keyPath);
    const privateKey = crypto.createPrivateKey(privateKeyPem);
    const signer = signers.newPrivateKeySigner(privateKey);

    const gateway = connect({ client, identity: { mspId, credentials }, signer });

    try {
        console.log(`✅ Terhubung ke ${channelName}`);
        const network = gateway.getNetwork(channelName);
        const contract = network.getContract(chaincodeName);

        console.log("⏱️  Speed: 1 Transaksi setiap 2 detik (Santai)");
        console.log("🛑 Tekan CTRL+C untuk berhenti...");

        let counter = 1;

        // --- LOOPING SANTAI (HEARTBEAT) ---
        while (true) {
            // Gunakan ID unik agar tidak bentrok
            const spotId = `spot-normal-${counter % 100}`; 
            
            process.stdout.write(`[${counter}] Kirim Heartbeat (${spotId})... `);

            try {
                // Panggil fungsi yang SAMA dengan script load test Anda
                // Parameter: (Function, SpotID, Status, ZoneID)
                await contract.submitTransaction('UpdateSpotStatus', spotId, 'occupied', 'zone-a');
                console.log(`✅ OK`);
            } catch (err) {
                // Kalau error, log saja tapi JANGAN berhenti (supaya keep-alive jalan terus)
                console.log(`⚠️  Skip: ${err.message}`);
            }

            counter++;

            // --- FASE TIDUR (SLEEP) ---
            // Ini kuncinya: Tunggu 2000ms (2 detik) sebelum kirim lagi
            await new Promise(resolve => setTimeout(resolve, 2000));
        }

    } finally {
        gateway.close();
        client.close();
    }
}

main().catch(console.error);