#!/bin/bash

cek_critical_applications(){
    THRESHOLD_MBPS=15
    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses Aplikasi Kritis dari cache..."

    # Saring hanya baris yang berawalan QUEUE| dari RAW_DATA
    QUEUE_DATA=$(echo "$RAW_DATA" | grep "^QUEUE|")

    # Gunakan <<< agar loop berjalan di shell utama
    while IFS='|' read -r PREFIX NAME RATE; do
        
        # Abaikan baris kosong
        [ -z "$NAME" ] && continue

        # Filter HANYA antrean aplikasi kritis yang Anda miliki
        if [[ "$NAME" == "0-Traffic-WhatsApp" || "$NAME" == "0-Traffic-Zoom" || "$NAME" == "0-Traffic-MsTeams" ]]; then
            
            # Bersihkan nama untuk label di Grafana
            APP_NAME=$(echo "$NAME" | sed 's/0-Traffic-//g')
            DOWNLOAD_RAW=$(echo "$RATE" | cut -d'/' -f2)

            # AWK Parser: Ubah format ke desimal (Mbps) murni
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
            --data-binary "app_kritis,app=$APP_NAME value=$TX_MBPS" > /dev/null 2>&1

            # --- B. CEK REDIS & TELEGRAM ALERT ---
            IS_OVER=$(awk -v tx="$TX_MBPS" -v th="$THRESHOLD_MBPS" 'BEGIN { if (tx >= th) print 1; else print 0 }')

            if [ "$IS_OVER" -eq "1" ]; then
                REDIS_KEY="lock_app_${APP_NAME}"
                # Pastikan menggunakan 127.0.0.1 agar konsisten
                IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY)

                if [ "$IS_LOCKED" != "1" ]; then
                    MSG="📊 *TRAFIK APLIKASI KRITIS TINGGI*%0A%0AAplikasi: *$APP_NAME*%0APemakaian: *${TX_MBPS} Mbps*%0AStatus: *Warning (>= ${THRESHOLD_MBPS} Mbps)*"
                    TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh

                    # Pasang Lock di Redis (1800 detik / 30 menit)
                    redis-cli -h ${REDIS_HOST} SETEX $REDIS_KEY 1800 "1" > /dev/null 2>&1
                    echo "[ALERT] $APP_NAME tembus $TX_MBPS Mbps! (Lock 30 Menit)"
                else
                    echo "[HECTIC] $APP_NAME masih $TX_MBPS Mbps. (Masa Lock)"
                fi
            else
                redis-cli -h ${REDIS_HOST} DEL "lock_app_${APP_NAME}" > /dev/null 2>&1
                # echo "[NORMAL] $APP_NAME -> $TX_MBPS Mbps"
            fi
        fi
    done <<< "$QUEUE_DATA"
}