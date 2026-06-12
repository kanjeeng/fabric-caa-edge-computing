const express = require('express');
const { connect, signers } = require('@hyperledger/fabric-gateway');
const grpc = require('@grpc/grpc-js');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const promClient = require('prom-client');
const dns = require('dns').promises;

const app = express();
const PORT = process.env.PORT || 3000;
app.use(express.json());

// --- 1. INISIALISASI PROMETHEUS METRICS ---
const collectDefaultMetrics = promClient.collectDefaultMetrics;
collectDefaultMetrics({ register: promClient.register });

// Metrik 1: Antrean 
const queueGauge = new promClient.Gauge({
    name: 'api_gateway_queue_length',
    help: 'Total transaksi yang sedang mengantre di memori API Gateway'
});

// Metrik 2: Latensi 
const latencyHistogram = new promClient.Histogram({
    name: 'api_gateway_latency',
    help: 'Waktu yang dibutuhkan (dalam detik) dari request masuk sampai sukses di-commit ke Ledger',
    labelNames: ['function_name'], 
    buckets: [0.1, 0.5, 1, 2, 5, 10, 20] 
});

// Metrik 3: Ready Peers (BARU DITAMBAHKAN UNTUK GRAFIK BAB 4)
const readyPeersGauge = new promClient.Gauge({
    name: 'api_gateway_ready_peers',
    help: 'Jumlah Peer yang sudah lolos karantina (Cold Start) dan siap memproses transaksi'
});

// Endpoint untuk di-scrape oleh Prometheus
app.get('/metrics', async (req, res) => {
    try {
        res.set('Content-Type', promClient.register.contentType);
        res.end(await promClient.register.metrics());
    } catch (ex) {
        res.status(500).end(ex);
    }
});
// ----------------------------------------

const mspId = 'ZoneAMSP';
const cryptoPath = path.resolve(__dirname, 'crypto-config', 'peerOrganizations', 'zone-a.parking.com');
const certPath = path.join(cryptoPath, 'users', 'User1@zone-a.parking.com', 'msp', 'signcerts', 'User1@zone-a.parking.com-cert.pem');
const keyPath = path.join(cryptoPath, 'users', 'User1@zone-a.parking.com', 'msp', 'keystore', 'priv_sk');
const tlsCertPath = path.join(cryptoPath, 'peers', 'peer0.zone-a.parking.com', 'tls', 'ca.crt');

const CONNECTIONS_PER_IP = 2;  
const TARGET_DNS_SERVICE = 'peer-zone-a.parking-fabric.svc.cluster.local';

let activeEndpoints = []; 
let quarantinedEndpoints = new Set(); 
let activePool = []; 
let currentConnectionIndex = 0;
let isInitialBoot = true; 

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));
const transactionQueue = [];
let isQueueRunning = false;

let MAX_CONCURRENCY = 5;    
let activeRequests = 0;     

async function startQueue() {
    if (isQueueRunning) return;
    isQueueRunning = true;

    while (transactionQueue.length > 0) {
        queueGauge.set(transactionQueue.length);

        if (activeRequests < MAX_CONCURRENCY) {
            activeRequests++;
            const { func, args, req, res, startTime } = transactionQueue.shift();

            executeTransactionAsync(func, args, req, res, startTime).finally(() => {
                activeRequests--; 
            });

            const podCount = activeEndpoints.length || 1;
            
            // --- UPDATE FINAL: MATEMATIKA TEORI ANTREAN YANG BENAR ---
            let dynamicDelay = 400; 

            if (podCount === 1) dynamicDelay = 2000;      // Kapasitas: 0.5 TPS
            else if (podCount === 2) dynamicDelay = 1000; // Kapasitas: 1.0 TPS
            else if (podCount === 3) dynamicDelay = 500;  // Kapasitas: 2.0 TPS
            else if (podCount === 4) dynamicDelay = 250;  // Kapasitas: 4.0 TPS
            else if (podCount >= 5) dynamicDelay = 150;   // Kapasitas: 6.6 TPS (Sanggup menyedot beban 5 TPS!)
            
            await sleep(dynamicDelay); 
            // ---------------------------------------------------------
        } else {
            await sleep(50);
        }
    }
    
    queueGauge.set(0); 
    isQueueRunning = false;
}

async function executeTransactionAsync(func, args, req, res, startTime) {
    try {
        const { contract, ip } = getConnectionFromPool();
        await contract.submitTransaction(func, ...args);
        
        const durationSeconds = (Date.now() - startTime) / 1000;
        latencyHistogram.labels(func).observe(durationSeconds);
        
        console.log(`✅ TX COMMITTED: [${func}] args: ${args[0]} (via Pod: ${ip}) | Latency: ${durationSeconds}s | [Slot: ${activeRequests}/${MAX_CONCURRENCY}]`);
        res.status(201).json({ status: 'SUCCESS' });
    } catch (error) {
        console.error(`❌ FABRIC ERROR [${args[0]}]:`, error.message);
        res.status(500).json({ error: 'Gagal memproses ke Blockchain' });
    }
}

async function createGrpcConnection(ip) {
    const tlsRootCert = fs.readFileSync(tlsCertPath);
    const tlsCredentials = grpc.credentials.createSsl(tlsRootCert);
    return new grpc.Client(`${ip}:7051`, tlsCredentials, {
        'grpc.ssl_target_name_override': 'peer0.zone-a.parking.com', 
        'grpc.keepalive_time_ms': 120000,
        'grpc.keepalive_timeout_ms': 20000,
        'grpc.http2.min_time_between_pings_ms': 120000,
        'grpc.http2.max_pings_without_data': 0
    });
}

async function buildNewPoolForActiveEndpoints() {
    if (activeEndpoints.length === 0) return;
    
    const newPool = [];
    for (const ip of activeEndpoints) {
        for (let i = 0; i < CONNECTIONS_PER_IP; i++) {
            try {
                const client = await createGrpcConnection(ip);
                const gateway = connect({
                    client,
                    identity: { mspId, credentials: fs.readFileSync(certPath) },
                    signer: signers.newPrivateKeySigner(crypto.createPrivateKey(fs.readFileSync(keyPath))),
                });
                const network = gateway.getNetwork('channel-zone-a');
                const contract = network.getContract('parking-cc');
                newPool.push({ client, gateway, contract, ip });
            } catch (error) {}
        }
    }

    if (newPool.length > 0) {
        const oldPool = activePool;
        activePool = newPool; 
        console.log(`✅ Trafik resmi dialihkan. Total Koneksi dalam Pool: ${activePool.length}\n`);
        setTimeout(() => {
            oldPool.forEach(conn => {
                try { conn.gateway.close(); conn.client.close(); } catch(e){}
            });
        }, 5000); 
    }
}

function probePodReadiness(ip) {
    let attempts = 0;
    const maxAttempts = 30; 
    const checkInterval = setInterval(async () => {
        attempts++;
        let client, gateway, isReady = false;
        try {
            client = await createGrpcConnection(ip);
            gateway = connect({
                client,
                identity: { mspId, credentials: fs.readFileSync(certPath) },
                signer: signers.newPrivateKeySigner(crypto.createPrivateKey(fs.readFileSync(keyPath))),
            });
            const network = gateway.getNetwork('channel-zone-a');
            const contract = network.getContract('parking-cc');
            await contract.evaluateTransaction('ReadSpot', 'probe-test');
            isReady = true; 
        } catch (err) {
            const errorMsg = err.message ? err.message.toLowerCase() : '';
            if (errorMsg.includes('does not exist')) isReady = true; 
        } finally {
            if (gateway) gateway.close();
            if (client) client.close();
        }

        if (isReady) {
            clearInterval(checkInterval);
            quarantinedEndpoints.delete(ip);
            if (!activeEndpoints.includes(ip)) {
                activeEndpoints.push(ip);
                console.log(`✅ [READY] Chaincode di Pod (${ip}) SUDAH AKTIF! Lulus Karantina.`);
                buildNewPoolForActiveEndpoints();
            }
        } else if (attempts >= maxAttempts) {
            clearInterval(checkInterval);
            quarantinedEndpoints.delete(ip);
        }
    }, 20000); 
}

async function checkDNSAndUpdatePool() {
    try {
        const discoveredIps = await dns.resolve4(TARGET_DNS_SERVICE);
        if (discoveredIps.length === 0) {
            readyPeersGauge.set(0); 
            return;
        }

        let poolNeedsRebuild = false;
        const originalCount = activeEndpoints.length;
        activeEndpoints = activeEndpoints.filter(ip => discoveredIps.includes(ip));
        if (activeEndpoints.length < originalCount) poolNeedsRebuild = true;

        discoveredIps.forEach(ip => {
            if (!activeEndpoints.includes(ip) && !quarantinedEndpoints.has(ip)) {
                if (isInitialBoot) {
                    console.log(`🚀 [BOOT] Pod awal terdeteksi (${ip}). Langsung diaktifkan.`);
                    activeEndpoints.push(ip);
                    poolNeedsRebuild = true;
                } else {
                    console.log(`⏳ [WARM-UP] K8s membuat Pod Baru (${ip}). Memulai Active Probe...`);
                    quarantinedEndpoints.add(ip);
                    probePodReadiness(ip);
                }
            }
        });

        if (isInitialBoot && activeEndpoints.length > 0) isInitialBoot = false;
        if (poolNeedsRebuild) buildNewPoolForActiveEndpoints();

        if (activeEndpoints.length > 0) {
            let newConcurrency = activeEndpoints.length; 
            if (MAX_CONCURRENCY !== newConcurrency) {
                MAX_CONCURRENCY = newConcurrency;
                console.log(`🚥 [AUTO-TUNING] Jumlah Pod Zone-A: ${activeEndpoints.length}. Gerbang Gateway: ${MAX_CONCURRENCY} Paralel`);
            }
        }

        // --- UPDATE METRIK GRAFANA SECARA REALTIME ---
        readyPeersGauge.set(activeEndpoints.length);
        // ---------------------------------------------

    } catch (err) {}
}

function getConnectionFromPool() {
    if (activePool.length === 0) throw new Error("Pool belum siap! Menunggu K8s...");
    const connection = activePool[currentConnectionIndex];
    currentConnectionIndex = (currentConnectionIndex + 1) % activePool.length;
    return connection;
}

app.post('/api/transactions', (req, res) => {
  const func = req.body.function || req.body.fcn;
  const args = req.body.args;
  if (!func || !args) return res.status(400).json({ error: 'Missing fields' });
  
  const startTime = Date.now();
  
  transactionQueue.push({ func, args, req, res, startTime });
  startQueue();
});

checkDNSAndUpdatePool().then(() => {
    setInterval(checkDNSAndUpdatePool, 5000);
    const waitInterval = setInterval(() => {
        if (activePool.length > 0) {
            clearInterval(waitInterval); 
            app.listen(PORT, '0.0.0.0', () => {
                console.log(`\n======================================================`);
                console.log(`🚀 API Gateway Berjalan di Port ${PORT}`);
                console.log(`✅ SILAKAN JALANKAN SIMULATOR SEKARANG!`);
                console.log(`======================================================\n`);
            });
        }
    }, 1000);
});