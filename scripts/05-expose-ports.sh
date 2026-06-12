#!/bin/bash
echo "========================================================="
echo "🔌 MEMBUKA JALUR AKSES DARI LUAR VIRTUALBOX (BACKGROUND)"
echo "========================================================="

# Mematikan proses port-forward lama jika ada agar tidak bentrok
pkill -f "port-forward"

# Menjalankan port-forward di background (diam-diam)
nohup minikube kubectl -- port-forward service/api-gateway 8080:3000 -n parking-fabric --address 0.0.0.0 > /dev/null 2>&1 &
nohup minikube kubectl -- port-forward service/grafana 3000:3000 -n monitoring --address 0.0.0.0 > /dev/null 2>&1 &
nohup minikube kubectl -- port-forward service/mosquitto 30883:1883 -n parking-fabric --address 0.0.0.0 > /dev/null 2>&1 &

echo "✅ Jembatan jaringan sukses dibangun!"
echo "🌐 API Gateway  : http://192.168.56.108:8080"
echo "📊 Grafana      : http://192.168.56.108:3000"
echo "📡 MQTT Broker  : mqtt://192.168.56.108:30883"
echo "========================================================="
