#!/bin/bash

check_top_user(){
    THRESHOLD_MBPS=15
    THRESHOLD_BPS=$((THRESHOLD_MBPS * 1000000))

    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses Top User (Queue) dari cache..."

    # 1. KONSUM DARI RAW_DATA
    QUEUE_DATA=$(echo "$RAW_DATA" | grep -i "^QUEUE|.*hotspot")
    ALL_ACTIVE_CLIENTS=$(echo "$RAW_DATA" | awk '/---RTRW_START---/{flag=1; next} /---RTRW_END---/{flag=0} flag')
    LIST_CLIENT_CONF="$(cat ${HOMELAB}/listCheck.conf | grep -E 'E1|E2' | grep -vi '#')"

    while IFS='|' read -r PREFIX NAME RATE; do
        
        [ -z "$NAME" ] && continue

        if [[ -n "$NAME" && -n "$RATE" ]]; then
            
            DOWNLOAD_RAW=$(echo "$RATE" | cut -d'/' -f2)

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

            # --- CORRELATION: MAC TO CLIENT NAME ---
            # Extract MAC murni tanpa < > hotspot- dan titik dua
            RAW_MAC=$(echo "$NAME" | tr -d '<>' | sed 's/hotspot-//gI' | tr -d ':')
            
            # Format ke 8E:26:CA:24:96:65 (Huruf Besar)
            CLEAN_MAC=$(echo "$RAW_MAC" | sed 's/\(..\)/\1:/g;s/:$//' | tr '[:lower:]' '[:upper:]')

            FINAL_NAME=""

            # A. Cari IP di ALL_ACTIVE_CLIENTS berdasarkan MAC Address
            CLIENT_IP=$(echo "$ALL_ACTIVE_CLIENTS" | grep -i "$CLEAN_MAC" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)

            # B. Jika IP ketemu, cocokkan IP ke listCheck.conf untuk ambil SSID/Nama Klien
            if [ -n "$CLIENT_IP" ]; then
                MATCHED_ROW=$(echo "$LIST_CLIENT_CONF" | grep "$CLIENT_IP")
                if [ -n "$MATCHED_ROW" ]; then
                    SSID="$(echo "$MATCHED_ROW" | awk -F'|' '{print $1}')"
                    FINAL_NAME=$(echo "${SSID}" | tr -cd 'A-Za-z0-9_-')
                fi
            fi

            # C. Fallback: Jika tidak ketemu via IP, bersihkan nama asli dari MikroTik
            if [ -z "$FINAL_NAME" ]; then
                FINAL_NAME=$(echo "$NAME" | tr -d '<>' | tr -cd 'A-Za-z0-9_-')
            fi

            # --- KIRIM KE INFLUXDB (Hanya Klien yang Terdaftar di Config) ---
            if [[ "$FINAL_NAME" != *"hotspot"* && "$FINAL_NAME" != *"<"* ]]; then
                curl -s -i -XPOST "${DB_HOST}/write?db=${DB_NAME}" \
                --data-binary "top_users,user=$FINAL_NAME value=$TX_MBPS" > /dev/null 2>&1
            fi

            # --- CEK REDIS & TELEGRAM ALERT ---
            if [[ "$NAME" == *"hotspot"* ]]; then
                IS_OVER=$(awk -v tx="$TX_MBPS" -v th="$THRESHOLD_MBPS" 'BEGIN { if (tx >= th) print 1; else print 0 }')

                if [ "$IS_OVER" -eq "1" ]; then
                    REDIS_KEY="lock_sedot_$FINAL_NAME"
                    IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET "$REDIS_KEY")

                    if [ "$IS_LOCKED" != "1" ]; then
                        MSG="🚨 *DETEKSI TUKANG SEDOT*%0A%0AUser: *$FINAL_NAME*%0ASpeed: *${TX_MBPS} Mbps*%0AStatus: *Melebihi Limit!*"
                        TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh

                        redis-cli -h ${REDIS_HOST} SETEX "$REDIS_KEY" 3600 "1" > /dev/null 2>&1
                        echo "[ALERT] $FINAL_NAME menyedot $TX_MBPS Mbps! (Telegram & Lock Aktif)"
                    else
                        echo "[HECTIC] $FINAL_NAME masih di $TX_MBPS Mbps. (Masa Lock)"
                    fi
                else
                    redis-cli -h ${REDIS_HOST} DEL "lock_sedot_$FINAL_NAME" > /dev/null 2>&1
                fi
            fi
        fi
    done <<< "$QUEUE_DATA"
}