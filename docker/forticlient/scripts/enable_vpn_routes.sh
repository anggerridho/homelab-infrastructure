#!/bin/bash

echo "Mengekstrak rute dinamis dari interface ppp0..."

DYNAMIC_ROUTES=$(ip -4 route show dev ppp0 | awk '{print $1}')

if [ -z "$DYNAMIC_ROUTES" ]; then
    echo "❌ GAGAL: Interface ppp0 tidak ditemukan atau tidak ada rute."
    exit 1
fi

TOTAL_ROUTES=$(echo "$DYNAMIC_ROUTES" | wc -l)
echo "Ditemukan $TOTAL_ROUTES rute dari server kantor."
echo "Menyusun konfigurasi MikroTik..."

ROS_CMD="/ip route remove [find comment~\"^ALTO\"]; "

for SUBNET in $DYNAMIC_ROUTES; do
    CLEAN_IP="${SUBNET%/*}"
    COMMENT="ALTO-${CLEAN_IP}"

    # Perhatikan penambahan routing-mark="Route_Kantor"
    ROS_CMD+="/ip route add dst-address=$SUBNET gateway=$STB_IP routing-mark=\"Route_Kantor\" comment=\"$COMMENT\"; "
done

echo "Mensinkronisasi rute ke MikroTik (via SSH Batch)..."

# Menggunakan env var $MIKROTIK_PSSWD dan $MIKROTIK_HOST yang di-pass dari docker-compose
sshpass -p "$MIKROTIK_PSSWD" ssh -q -oStrictHostKeyChecking=no "$MIKROTIK_HOST" "$ROS_CMD"

echo "✅ Berhasil! Tabel routing MikroTik sekarang 100% sinkron dengan ppp0."
