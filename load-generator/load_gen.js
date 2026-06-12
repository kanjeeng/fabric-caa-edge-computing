// load-generator/load_gen.js (VERSI FINAL - TLS SECURE)
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
    console.log("🚀 Memulai Load Generator (Node.js SDK - Mode TLS SECURE)...");
    
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

        console.log("🔥 MEMULAI SERANGAN BEBAN TINGGI...");
        let txCount = 0;
        const startTime = Date.now();

        while (true) {
            const promises = [];
            for (let i = 0; i < 500; i++) { // Batch 20
                const spotId = `spot-${(txCount + i) % 100 + 1}`;
                promises.push(
                    contract.submitTransaction('UpdateSpotStatus', spotId, 'occupied', 'zone-a')
                        .catch(err => console.error(`❌ Gagal: ${err.message}`))
                );
            }
            await Promise.all(promises);
            txCount += 20;

            if (txCount % 100 === 0) {
                const elapsed = (Date.now() - startTime) / 1000;
                const tps = txCount / elapsed;
                console.log(`📈 Total: ${txCount} | TPS: ${tps.toFixed(2)}`);
            }
        }

    } finally {
        gateway.close();
        client.close();
    }
}
main().catch(console.error);