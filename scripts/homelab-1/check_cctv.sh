#!/bin/bash

cctv(){
    critical_down=0 # Inisialisasi flag untuk status WEST/EAST
    # Saring hanya baris yang mengandung data CCTV dari MEGA_CMD
    n=0; CCTV_DATA=$(echo "$RAW_DATA" | grep "^CCTV|")
    while IFS='|' read -r PREFIX HSTNAME IPADDR PING_RESULT; do
        
        # Lewati jika baris kosong (pengaman)
        [ -z "$HSTNAME" ] && continue
        
        # Karena PING_RESULT dari MikroTik sudah pasti 1 (Up) atau 0 (Down)
        CCTV_STATUS=$PING_RESULT
        
        if [ "$CCTV_STATUS" -eq 1 ]; then
            ((n+=1))
            echo "[$(date +'%Y%m%d_%H:%M:%S')] - ${n}. Ok ${HSTNAME} ${IPADDR}"
        else
            echo "[$(date +'%Y%m%d_%H:%M:%S')] - RTO ${HSTNAME} ${IPADDR}"
            
            # LOGIKA BARU: Cek apakah yang mati adalah WEST atau EAST
            if [[ "$HSTNAME" == "CCTV_WEST" || "$HSTNAME" == "CCTV_EAST" ]]; then
                critical_down=1
                DOWN_DEVICE_NAME=$HSTNAME # Untuk keperluan pesan alert
            fi
        fi

        # --------------------------------------------------
        # A. GRAFANA: KIRIM STATUS INDIVIDU (Per Kamera)
        # --------------------------------------------------
        SAFE_HSTNAME=$(echo "$HSTNAME" | tr -cd 'A-Za-z0-9_-')
        
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "cctv_individu,nama=$SAFE_HSTNAME status=$CCTV_STATUS" > /dev/null 2>&1

    done <<< "$CCTV_DATA"

    # GRAFANA: KIRIM STATUS TOTAL
    curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
    --data-binary "cctv_total,kategori=semua_cctv online_count=${n}" > /dev/null 2>&1

    # REDIS LOCKING & TELEGRAM ALERT
    REDIS_KEY="lock_cctv_down"

    if [ "$critical_down" -eq 1 ]; then
        # Jika salah satu WEST atau EAST mati
        IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY)

        if [ "$IS_LOCKED" != "1" ]; then
            # Buat pesan yang lebih spesifik
            MSG="[$(date +'%Y%m%d_%H:%M:%S')] - 🚨 ALERT: Critical CCTV is DOWN (${DOWN_DEVICE_NAME})!"
            echo "$MSG"

            # Kirim ke Telegram
            TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh

            # Pasang lock selama 2 Jam
            redis-cli -h ${REDIS_HOST} SETEX $REDIS_KEY 7200 "1" > /dev/null 2>&1
        else
            echo "[HECTIC] CCTV masih mati. (Masa Lock Telegram Aktif)"
        fi
    else
        # Jika kedua CCTV (WEST & EAST) sudah UP kembali, hapus kunci Redis
        redis-cli -h ${REDIS_HOST} DEL $REDIS_KEY > /dev/null 2>&1
        echo "[$(date +'%Y%m%d_%H:%M:%S')] - CCTV net is GOOD with ${n} devices connected."
    fi
}