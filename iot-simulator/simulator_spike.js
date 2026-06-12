const mqtt = require('mqtt');

// --- KONFIGURASI BEBAN BERAT (SOFT-SPIKE LOAD) ---
const MQTT_BROKER = '192.168.56.107:30883';
// 1. Jumlah Sensor Parkir
const TOTAL_SPOTS = parseInt(process.env.TOTAL_SPOTS) || 100; 
// 2. Kecepatan Tembakan (TPS) di dalam Gelombang
const DELAY_MS = parseInt(process.env.DELAY_MS) || 200; // 1000ms / 200ms = 5 TPS
// 3. Waktu Jeda (Istirahat) Antar Gelombang
const BATCH_INTERVAL_MS = parseInt(process.env.INTERVAL_MS) || 0; // Jeda 0 detik (Non-stop)

// FOKUS HANYA KE ZONE A
const ZONES = ['zone-a']; 

console.log('='.repeat(60));
console.log('🔥 IoT Simulator: SOFT-SPIKE LOAD TEST (ZONE-A) 🔥');
console.log(`🔹 Target       : ${ZONES[0]}`);
console.log(`🔹 Total Spots  : ${TOTAL_SPOTS} Spots`);
console.log(`🔹 Jeda/Pesan   : ${DELAY_MS} ms`);
console.log(`🔹 Est. TPS     : ~${Math.floor(1000 / DELAY_MS)} Transaksi / Detik`);
console.log('='.repeat(60));

const client = mqtt.connect(`mqtt://${MQTT_BROKER}`);
let messagesSent = 0;

// 1. FUNGSI PEMBANTU UNTUK JEDA WAKTU (PROMISE DELAY)
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

client.on('connect', async () => {
    console.log('✅ Connected to MQTT broker. Memulai tembakan terukur (Soft-Spike)...\n');
    
    // 2. FUNGSI ASYNCHRONOUS UNTUK MENJALANKAN BATCH
    async function runBatch() {
        const zone = ZONES[0];
        
        for (let i = 0; i < TOTAL_SPOTS; i++) {
            const spotId = `spot-spike-${String(i + 1).padStart(3, '0')}`;
            const topic = `parking/${zone}/${spotId}`;
            
            // Randomize status agar data bervariasi
            const isOccupied = Math.random() < 0.7; 
            
            const payload = JSON.stringify({
                spot_id: spotId,
                zone_id: zone,
                status: isOccupied ? 'occupied' : 'available',
                timestamp: Date.now()
            });

            client.publish(topic, payload, (err) => {
                if (!err) messagesSent++;
            });

            // 3. JEDA EKSEKUSI SEBELUM MENGIRIM PESAN SELANJUTNYA
            await delay(DELAY_MS);
        }

        // Setelah 1 batch selesai (100 pesan dikirim), jalankan batch berikutnya
        setTimeout(runBatch, BATCH_INTERVAL_MS);
    }

    // Mulai eksekusi putaran pertama
    runBatch();

    // Laporan statistik setiap 5 detik
    setInterval(() => {
        const time = new Date().toLocaleTimeString();
        console.log(`📊 [${time}] Throughput aktual: ~${(messagesSent/5).toFixed(0)} TPS`);
        messagesSent = 0; 
    }, 5000);
});

client.on('error', (err) => console.error('❌ MQTT Error:', err.message));