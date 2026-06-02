# Gunakan base image Node.js yang sangat ringan
FROM node:18-alpine

# Tentukan direktori kerja di dalam container
WORKDIR /app

# Salin file package.json terlebih dahulu untuk memanfaatkan sistem cache Docker
COPY package.json ./

# Install dependensi (hanya untuk production, menghemat ruang)
RUN npm install --production

# Salin seluruh kode aplikasi (index.js) ke dalam container
COPY . .

# Eksekusi bot saat container berjalan
CMD ["node", "index.js"]
