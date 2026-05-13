#!/bin/bash

cek_anomali_speedtest(){
    THRESHOLD_MBPS=10
    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses Anomali Speedtest dari cache..."

    # Tembak langsung spesifik ke nama Bypass-Speedtest di memori
    SPEEDTEST_DATA=$(echo "$RAW_DATA" | grep "^QUEUE|Bypass-Speedtest|")

    # Jika baris data ditemukan
    if [ -n "$SPEEDTEST_DATA" ]; then
        # Pecah variabel tanpa perlu looping
        IFS='|' read -r PREFIX NAME RATE <<< "$SPEEDTEST_DATA"

        DOWNLOAD_RAW=$(echo "$RATE" | cut -d'/' -f2)

        # Parser Satuan ke Mbps
        TX_MBPS=$(echo "$DOWNLOAD_RAW" | awk '{
            val = tolower($0);
            mult = 1;
            if (val ~ /k/) mult = 1000;
            if (val ~ /m/) mult = 1000000;
            gsub(/[^0-9.]/, "", val);
            if (val == "") val = 0;
            bps = val * mult;
            printf "%.2f", bps / 1000000;
        }')

        # --- A. KIRIM KE INFLUXDB (GRAFANA) ---
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "app_anomali,app=Speedtest value=$TX_MBPS" > /dev/null 2>&1

        # --- B. CEK REDIS & TELEGRAM ALERT ---
        IS_OVER=$(awk -v tx="$TX_MBPS" -v th="$THRESHOLD_MBPS" 'BEGIN { if (tx >= th) print 1; else print 0 }')

        if [ "$IS_OVER" -eq "1" ]; then
            REDIS_KEY="lock_anomali_speedtest"
            IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY)

            if [ "$IS_LOCKED" != "1" ]; then
                MSG="🚀 *ANOMALI SPEEDTEST TERDETEKSI*%0A%0AQueue: *$NAME*%0ASpeed: *${TX_MBPS} Mbps*%0AStatus: *High Load Terdeteksi!*"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh

                # Lock Redis selama 10 menit (600 detik)
                redis-cli -h ${REDIS_HOST} SETEX $REDIS_KEY 600 "1" > /dev/null 2>&1
                echo "[ALERT] Anomali Speedtest! ($TX_MBPS Mbps). Telegram terkirim."
            else
                echo "[HECTIC] Speedtest masih $TX_MBPS Mbps. (Masa Lock)"
            fi
        else
            redis-cli -h ${REDIS_HOST} DEL "lock_anomali_speedtest" > /dev/null 2>&1
            # echo "[NORMAL] Speedtest -> $TX_MBPS Mbps"
        fi
    else
        echo "Data antrean Bypass-Speedtest tidak ditemukan."
    fi
}