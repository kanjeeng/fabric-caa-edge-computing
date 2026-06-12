FROM node:18-slim
WORKDIR /app

# Ambil file dari folder api-gateway
COPY api-gateway/package*.json ./
RUN npm install --production
COPY api-gateway/server.js .

# KUNCI OTOMASI: Ambil sertifikat LANGSUNG dari sumber aslinya!
COPY fabric-network/crypto-config ./crypto-config

EXPOSE 3000
CMD ["node", "server.js"]