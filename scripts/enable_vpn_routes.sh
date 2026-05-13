#!/bin/bash
HOMELAB="/root/homelab-infrastructure/scripts"
source ${HOMELAB}/vault.sh && vault

echo "Mengekstrak rute dinamis dari interface ppp0..."

# Ambil hanya kolom pertama (IP/Subnet) dari tabel routing ppp0
# Outputnya berupa array text: 2.16.0.0/13 10.0.10.0/24 dst.
DYNAMIC_ROUTES=$(ip -4 route show dev ppp0 | awk '{print $1}')

# Validasi: Jika kosong, berarti VPN belum aktif
if [ -z "$DYNAMIC_ROUTES" ]; then
    echo "❌ GAGAL: Interface ppp0 tidak ditemukan atau tidak ada rute."
    echo "Pastikan openfortivpn sudah terhubung."
    exit 1
fi

TOTAL_ROUTES=$(echo "$DYNAMIC_ROUTES" | wc -l)
echo "Ditemukan $TOTAL_ROUTES rute dari server kantor."
echo "Menyusun konfigurasi MikroTik..."

# 1. PERSIAPAN: Selalu bersihkan rute ALTO lama agar tidak ada rute hantu / duplikat
ROS_CMD="/ip route remove [find comment~\"ALTO\"]; "

# 2. PERULANGAN: Susun perintah penambahan rute baru
for SUBNET in $DYNAMIC_ROUTES; do
    # Buang angka slash dan mask (misal /24) untuk mempercantik nama Comment
    # 10.35.0.0/16 akan menjadi 10.35.0.0
    CLEAN_IP="${SUBNET%/*}" 
    COMMENT="ALTO-${CLEAN_IP}"

    # Tambahkan perintah ini ke ujung string ROS_CMD
    ROS_CMD+="/ip route add dst-address=$SUBNET gateway=$STB_IP comment=\"$COMMENT\"; "
done

echo "Mensinkronisasi rute ke MikroTik (via SSH Batch)..."

# 3. EKSEKUSI BATCH: Tembak seluruh perintah dalam 1x koneksi SSH
${HOMELAB}/terminate.sh -t 10 sshpass -p "$(echo ${MIKROTIK_PSSWD} | base64 -d)" ssh -q -oStrictHostKeyChecking=no ${MIKROTIK_HOST} "$ROS_CMD"

echo "✅ Berhasil! Tabel routing MikroTik sekarang 100% sinkron dengan ppp0."
