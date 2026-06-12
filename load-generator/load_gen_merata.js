const { connect, signers } = require('@hyperledger/fabric-gateway');
const grpc = require('@grpc/grpc-js');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

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
    console.log("🌊 Memulai LOAD GENERATOR - Skenario B (BEBAN MERATA)...");

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
        console.log(`✅ Terhubung langsung ke Peer ${peerEndpoint}`);
        const network = gateway.getNetwork(channelName);
        const contract = network.getContract(chaincodeName);
        console.log("⏱️  Speed: 1 Transaksi setiap 50ms (CEPAT!)");

        let counter = 1;

        while (true) {
            // LOGIKA MERATA (33% Zone A, 33% Zone B, 33% Zone C)
            const rand = Math.random();
            let targetZone = 'zone-a';
            if (rand > 0.33 && rand <= 0.66) targetZone = 'zone-b';
            else if (rand > 0.66) targetZone = 'zone-c';

            const spotId = `spot-mrt-${counter % 1000}`; 

            try {
                contract.submitTransaction('UpdateSpotStatus', spotId, 'occupied', targetZone)
                    .then(() => console.log(`[${counter}] ✅ Sukses -> ${targetZone.toUpperCase()}`))
                    .catch((err) => console.log(`[${counter}] ❌ Gagal: ${err.message}`));
            } catch (err) {}

            counter++;
            
            // FASE TIDUR SANGAT SINGKAT (50ms)
            await new Promise(resolve => setTimeout(resolve, 50));
        }
    } finally {
        gateway.close();
        client.close();
    }
}

main().catch(console.error);