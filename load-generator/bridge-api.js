const express = require('express');
const { exec } = require('child_process');
const cors = require('cors');

const app = express();
const PORT = 30883;

// Izinkan website mengakses API ini
app.use(cors());

// Endpoint untuk menarik data dari Ledger Fabric via CLI
app.get('/api/spots', (req, res) => {
    console.log('Sedang menarik data dari Blockchain...');
    
    // Ini adalah perintah "Sakti" yang baru saja kita tes dan terbukti berhasil!
    const cmd = `minikube kubectl -- exec pod/admin-cli -n parking-fabric -- bash -c "CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.zone-a.parking.com peer chaincode query -C channel-zone-a -n parking-cc -c '{\\"Args\\":[\\"GetAllSpots\\"]}'"`;

    exec(cmd, (error, stdout, stderr) => {
        if (error) {
            console.error(`Error eksekusi: ${error.message}`);
            return res.status(500).json({ success: false, error: error.message });
        }
        
        try {
            // Bersihkan output barangkali ada log tambahan, ambil JSON-nya saja
            const jsonString = stdout.trim();
            const data = JSON.parse(jsonString);
            
            console.log(`Berhasil menarik ${data.length} data parkir.`);
            res.json({
                success: true,
                count: data.length,
                data: data
            });
        } catch (parseError) {
            console.error('Gagal parse JSON:', parseError);
            res.status(500).json({ success: false, error: 'Gagal membaca respon blockchain' });
        }
    });
});

app.listen(PORT, () => {
    console.log('=================================');
    console.log(`🚀 BRIDGE API BERJALAN DI PORT ${PORT}`);
    console.log(`Buka http://localhost:${PORT}/api/spots di browser Anda`);
    console.log('=================================');
});