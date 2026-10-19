#!/bin/bash

check_internet(){
# ==========================================
# KONFIGURASI
# ==========================================
STB_NAME="STB-2"                  # Ubah menjadi STB-2 jika dipasang di STB kedua
TARGET_PING="cloudflare.com"
REDIS_KEY="internet_down_state"

# ==========================================
# PING & CEK STATUS
# ==========================================
if ping -c 4 -i 0.5 -W 1 "${TARGET_PING}" > /dev/null 2>&1; then
    STATUS_CODE=1 # Internet OK
else
    STATUS_CODE=0 # Internet Putus
fi

# Cek apakah key Redis ada (untuk mendeteksi apakah ini state baru / pasca-reboot)
REDIS_EXISTS=$(redis-cli -h ${REDIS_HOST} EXISTS ${REDIS_KEY})
IS_OFFLINE=$(redis-cli -h ${REDIS_HOST} GET ${REDIS_KEY})

# ==========================================
# LOGIKA INITIAL & ANTI-SPAM
# ==========================================

# 1. JIKA KONDISI ONLINE (STATUS = 1)
if [ "$STATUS_CODE" -eq 1 ]; then

    # Kirim ke DB jika:
    # - Terjadi pemulihan (sebelumnya offline) ATAU
    # - Key Redis belum ada sama sekali (Inisialisasi awal / pasca reboot)
    if [ "$IS_OFFLINE" == "1" ] || [ "$REDIS_EXISTS" -eq 0 ]; then

        # Kirim alert pemulihan hanya jika sebelumnya memang tercatat offline
        if [ "$IS_OFFLINE" == "1" ]; then
            MSG="✅ [RECOVERY] ${STB_NAME} berhasil konek ke internet (${TARGET_PING})."
            TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
        fi

        # Selalu kirim data status=1 ke InfluxDB saat inisialisasi/recovery agar grafik Grafana terisi
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "internet_monitor,host=${STB_NAME} status=${STATUS_CODE}" > /dev/null 2>&1

        # Bersihkan / pastikan Redis bersih dari flag offline
        redis-cli -h ${REDIS_HOST} DEL ${REDIS_KEY} > /dev/null 2>&1
    fi

# 2. JIKA KONDISI OFFLINE (STATUS = 0)
else

    # Kirim alert & catat DB hanya jika belum tercatat offline
    if [ "$IS_OFFLINE" != "1" ]; then
        MSG="🚨 [ALERT] ${STB_NAME} gagal konek ke internet (RTO ke ${TARGET_PING})."

        TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh

        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "internet_monitor,host=${STB_NAME} status=${STATUS_CODE}" > /dev/null 2>&1

        # Set flag di Redis agar masuk mode silent
        redis-cli -h ${REDIS_HOST} SET ${REDIS_KEY} "1" > /dev/null 2>&1
    fi

fi
}
