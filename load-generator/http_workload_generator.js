const axios = require('axios');

// Target ke API Gateway via Port-Forward 8080
const TARGET_URL = 'http://localhost:8080/api/parking/events'; 

async function sendNormalTraffic() {
    const payload = {
        channel: "channel-zone-a",
        data: {
            parkingId: "NORMAL-" + Math.floor(Math.random() * 100),
            status: "OCCUPIED",
            timestamp: new Date().toISOString()
        }
    };

    try {
        const response = await axios.post(TARGET_URL, payload);
        if (response.status === 201 || response.status === 200) {
            process.stdout.write('🟢 '); // Transaksi Berhasil
        }
    } catch (error) {
        process.stdout.write('🔴 '); // Gagal (Gateway atau Fabric bermasalah)
    }
}

console.log("🚀 Memulai Normal Load Test (1 Transaksi / Detik)...");
setInterval(sendNormalTraffic, 1000);