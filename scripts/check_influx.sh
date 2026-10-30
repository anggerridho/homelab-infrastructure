#!/bin/bash

# --- KONFIGURASI DEFAULT (BISA OVERRIDE LEWAT ENV) ---
# TTL Anti-Spam Redis (dalam detik), default: 1 jam (3600 detik)
REDIS_TTL=${REDIS_TTL:-3600}
DB_DOWN_FLAG="flag_db_influx_down"

# Pengecekan argumen/environment variable DB_HOST
if [ -z "${DB_HOST}" ]; then
    echo "[$(date +'%Y%m%d_%H:%M:%S')] - [ERROR] DB_HOST belum didefinisikan!"
    exit 1
fi

# --- 1. TEST KONEKSI INFLUXDB VIA HTTP/HTTPS ---
if ! curl -s -f --connect-timeout 2 -m 3 "${DB_HOST}/ping" > /dev/null 2>&1; then
    echo "[$(date +'%Y%m%d_%H:%M:%S')] - [WARNING] (${DB_HOST}) Offline/Tidak Dapat Diakses."

    # --- 2. ANTI-SPAM LOGIC (REDIS) ---
    HAS_ALERTED=""
    if [ -n "${REDIS_HOST}" ]; then
        HAS_ALERTED=$(redis-cli -h "${REDIS_HOST}" GET "$DB_DOWN_FLAG" 2>/dev/null)
    fi

    if [ "$HAS_ALERTED" != "1" ]; then
        MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ⚠️ WARNING: InfluxDB (${DB_HOST}) Offline/Tidak Dapat Diakses! Penulisan log Grafana di-skip, pengecekan pelanggan tetap berjalan."

        # Kirim alert Telegram jika script alertelegram.sh ada
        if [ -x "${HOMELAB}/alertelegram.sh" ]; then
            TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
        else
            echo "${MSG}"
        fi

        # Catat flag di Redis dengan TTL agar tidak spam
        if [ -n "${REDIS_HOST}" ]; then
            redis-cli -h "${REDIS_HOST}" SET "$DB_DOWN_FLAG" "1" EX ${REDIS_TTL} > /dev/null 2>&1
        fi
    fi

    # Kembalikan exit code 1 (Gagal)
    exit 1
else
    # --- 3. JIKA KONEKSI DB NORMAL ---
    # Hapus flag error di Redis agar jika terjadi downtime di kemudian hari, alert langsung terkirim
    if [ -n "${REDIS_HOST}" ]; then
        redis-cli -h "${REDIS_HOST}" DEL "$DB_DOWN_FLAG" > /dev/null 2>&1
    fi

    # Kembalikan exit code 0 (Sukses)
    exit 0
fi
