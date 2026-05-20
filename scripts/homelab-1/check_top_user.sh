#!/bin/bash

check_top_user(){
    # Ambang batas alert individu
    THRESHOLD_MBPS=15
    # Kita ubah Mbps ke BPS untuk perbandingan Bash murni (7 x 1.000.000)
    THRESHOLD_BPS=$((THRESHOLD_MBPS * 1000000))

    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses Top User (Queue) dari cache..."

    # 1. KONSUM DARI RAW_DATA (Saring baris yang diawali dengan 'QUEUE|')
    QUEUE_DATA=$(echo "$RAW_DATA" | grep "^QUEUE|")

    # Gunakan <<< agar loop berjalan di shell utama, bukan subshell
    # Kita tambah variabel PREFIX untuk menyerap kata "QUEUE"
    while IFS='|' read -r PREFIX NAME RATE; do
        
        # Abaikan baris kosong
        [ -z "$NAME" ] && continue

        if [[ -n "$NAME" && -n "$RATE" ]]; then
            
            # Ambil sisi Download (Contoh: "104bps/32.2kbps" -> "32.2kbps")
            DOWNLOAD_RAW=$(echo "$RATE" | cut -d'/' -f2)

            # AWK MAGIC: Parser satuan (bps/kbps/mbps) menjadi desimal Mbps murni
            TX_MBPS=$(echo "$DOWNLOAD_RAW" | awk '{
                val = tolower($0);
                mult = 1;
                if (val ~ /k/) mult = 1000;
                if (val ~ /m/) mult = 1000000;

                gsub(/[^0-9.]/, "", val); # Buang semua huruf, sisakan angka & titik
                if (val == "") val = 0;

                bps = val * mult;
                printf "%.2f", bps / 1000000;
            }')

            SAFE_NAME=$(echo "$NAME" | tr -cd 'A-Za-z0-9_-')

            # --- KIRIM KE INFLUXDB ---
            curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
            --data-binary "top_users,user=$SAFE_NAME value=$TX_MBPS" > /dev/null 2>&1

            # --- CEK REDIS & TELEGRAM ALERT ---
            if [[ "$NAME" == *"hotspot"* ]]; then
                
                # AWK NATIVE PERBANDINGAN: Awk kembalikan nilai 1 jika Over Threshold, 0 jika Aman.
                # Ini mengatasi kelemahan Bash yang tidak bisa menghitung angka desimal (float).
                IS_OVER=$(awk -v tx="$TX_MBPS" -v th="$THRESHOLD_MBPS" 'BEGIN { if (tx >= th) print 1; else print 0 }')

                if [ "$IS_OVER" -eq "1" ]; then
                    
                    REDIS_KEY="lock_sedot_$SAFE_NAME"
                    IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET "$REDIS_KEY")

                    if [ "$IS_LOCKED" != "1" ]; then
                        MSG="🚨 *DETEKSI TUKANG SEDOT*%0A%0AUser: *$NAME*%0ASpeed: *${TX_MBPS} Mbps*%0AStatus: *Melebihi Limit!*"
                        TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh

                        redis-cli -h ${REDIS_HOST} SETEX "$REDIS_KEY" 3600 "1" > /dev/null 2>&1
                        echo "[ALERT] $NAME menyedot $TX_MBPS Mbps! (Telegram & Lock Aktif)"
                    else
                        echo "[HECTIC] $NAME masih di $TX_MBPS Mbps. (Masa Lock)"
                    fi
                else
                    redis-cli -h ${REDIS_HOST} DEL "lock_sedot_$SAFE_NAME" > /dev/null 2>&1
                    # Boleh di-comment agar log terminal tidak terlalu penuh
                    # echo "[HOTSPOT] $NAME -> $TX_MBPS Mbps" 
                fi
            else
                # Boleh di-comment agar log terminal tidak terlalu penuh
                # echo "[SISTEM] $NAME -> $TX_MBPS Mbps"
                : # Do nothing
            fi
        fi
    done <<< "$QUEUE_DATA"
}