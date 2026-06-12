
# 🚀 Panduan Setup & Load Testing Parking Blockchain (CAA)

Panduan ini berisi langkah-langkah dari nol (*from scratch*) untuk menjalankan arsitektur Hyperledger Fabric, Kubernetes, CAA Controller, dan mengeksekusi skenario *Stress Test*.

**Persiapan:** Buka setidaknya **5 Tab Terminal** sebelum memulai.

---

## 🖥️ TERMINAL 1: Inisialisasi & Deployment Jaringan

Terminal ini adalah pusat kontrol (*master*) Anda. Jalankan perintah di bawah ini secara berurutan.

**1. Reset & Start Minikube**

```bash
cd ~/Desktop/parking-blockchain-lite
minikube delete
minikube start --memory=8192 --cpus=4
eval $(minikube docker-env)

```

**2. Generate Crypto & Genesis Block**

```bash
cd scripts
./generate-crypto.sh
./generate-genesis.sh
cd ..

```

*(JEDA SEBENTAR: Pindah ke Terminal 2 untuk melakukan proses Mounting!)*

---

## 🖥️ TERMINAL 2: Mounting File Kriptografi (Background)

Jalankan perintah ini agar Kubernetes bisa membaca sertifikat Fabric dari *host* lokal Anda. Biarkan terminal ini terbuka.

```bash
nohup minikube mount /home/cana/Desktop/parking-blockchain-lite/fabric-network/crypto-config:/home/cana/Desktop/parking-blockchain-lite/fabric-network/crypto-config > minikube-mount.log 2>&1 &

```

*(KEMBALI KE TERMINAL 1)*

---

## 🖥️ TERMINAL 1 (Lanjutan): Deploy K8s & Fabric

Kembali ke Terminal 1, jalankan perintah ini untuk membangun dan menyebarkan seluruh *microservices*.

**3. Build Image & Deploy ke Kubernetes**

```bash
./scripts/99-cleanup.sh
./scripts/03-upload-to-k8s.sh
./scripts/03-deploy-all.sh

```

**4. Pantau Status Pod (Wajib Tunggu)**

```bash
minikube kubectl -- get pods -n parking-fabric -w

```

*(Tunggu sampai semua pod berstatus `Running`. Jika sudah, tekan **`CTRL+C`**).*

**5. Inisialisasi Jaringan & Warmup Chaincode**

```bash
./scripts/04-init-network.sh
./caa-agent.sh

```

---

## 🖥️ TERMINAL 3, 4, 5: Port-Forwarding (Akses Layanan)

Buka tab terminal baru untuk masing-masing perintah ini agar layanan bisa diakses dari luar Minikube. Biarkan terminal-terminal ini terus berjalan.

**TERMINAL 3 (Buka Akses API Gateway):**

```bash
minikube kubectl -- port-forward service/api-gateway 8080:3000 -n parking-fabric --address 0.0.0.0

```

**TERMINAL 4 (Buka Akses Grafana):**

```bash
minikube kubectl -- port-forward service/grafana 3000:3000 -n monitoring --address 0.0.0.0

```

**TERMINAL 5 (Buka Akses MQTT Broker):**

```bash
minikube kubectl -- port-forward service/mosquitto 30883:1883 -n parking-fabric --address 0.0.0.0

```

---

## 📊 SETUP DASBOR GRAFANA (Browser)

1. Buka Browser: `http://localhost:3000` (atau gunakan IP VirtualBox Anda).
2. Login ke Grafana.
3. Klik icon **`+`** di menu kiri -> Pilih **Import**.
4. Buka file *JSON Dashboard* Anda, salin seluruh isinya, dan *paste* ke dalam kotak *"Import via panel json"*.
5. Klik **Load** lalu **Import**.

---

## ⚡ TERMINAL 6: Eksekusi Skenario Pengujian (Load Test)

Buka terminal baru untuk mengatur skenario algoritma CAA dan menembakkan *Spike Load*.

**1. Set Skenario CAA (Contoh: Target Zone-A)**

```bash
cd ~/Desktop/parking-blockchain-lite/iot-simulator
./setup_skenario.sh -a 0.5 -b 0.5 -z zone-a

```

**2. Hajar Jaringan dengan Spike Load**

```bash
export MQTT_BROKER="localhost:30883"
node simulator_spike.js

```

*(Opsional) Jika ingin memantau proses Autoscaling (Pod bertambah/berkurang) secara realtime, buka Terminal 7:*

```bash
minikube kubectl -- get pods -n parking-fabric -o wide -w

```