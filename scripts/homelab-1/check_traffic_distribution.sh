#!/bin/bash

traffic_distribution(){
    LOCAL_PATHS=(
        "PELANGGAN|ether3|20"
        "PRIBADI|ether4|40"
    )

    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses traffic distribution (Lokal) dari cache..."

    for path in "${LOCAL_PATHS[@]}"; do
        IFS='|' read -r PATH_NAME INTERFACE THRESHOLD_MBPS <<< "$path"

        THRESHOLD_BPS=$((THRESHOLD_MBPS * 1000000))
        SAFE_NAME=$(echo "$PATH_NAME" | tr -cd 'A-Za-z0-9_-')
        REDIS_KEY="lock_hectic_local_${SAFE_NAME}"

        # 1. KONSUM DARI RAW_DATA (Pencarian berbasis Interface Name)
        # Perhatikan: Kita mengambil kolom ke-4 (TX) untuk trafik distribusi lokal
        TRAFFIC=$(echo "$RAW_DATA" | grep "^TRAFFIC|${INTERFACE}|" | awk -F'|' '{print $4}')

        if [[ -n "$TRAFFIC" && "$TRAFFIC" =~ ^[0-9]+$ ]]; then
            # Konversi bits ke Mbps untuk Grafana
            TX_MBPS=$(echo "$TRAFFIC" | awk '{printf "%.2f", $1/1000000}')

            # --- A. INTEGRASI GRAFANA ---
            curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
            --data-binary "trafik_lokal,interface=$INTERFACE,nama=$SAFE_NAME tx_mbps=$TX_MBPS" > /dev/null 2>&1

            # --- B. LOGIKA ALERT TELEGRAM DENGAN REDIS ---
            if [ "$TRAFFIC" -ge "$THRESHOLD_BPS" ]; then
                # Cek apakah sedang dalam kondisi 'lock' di Redis
                IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET "$REDIS_KEY")

                if [ "$IS_LOCKED" != "1" ]; then
                    # Kirim Alert Telegram
                    MSG="🔥 *HECTIC JALUR LOKAL*%0A%0AJalur: *$PATH_NAME*%0AInterface: *$INTERFACE*%0ATrafik: *$TX_MBPS Mbps*%0AStatus: *Jenuh / Full*"
                    TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh

                    # Pasang lock di Redis
                    redis-cli -h ${REDIS_HOST} SET "$REDIS_KEY" "1" > /dev/null 2>&1
                    echo "[$PATH_NAME] Hectic! Alert sent and Lock set in Redis."
                else
                    echo "[$PATH_NAME] Masih Hectic ($TX_MBPS Mbps). Data masuk DB. (Telegram skip via Redis)."
                fi
            else
                # Trafik normal, hapus lock di Redis
                redis-cli -h ${REDIS_HOST} DEL "$REDIS_KEY" > /dev/null 2>&1
                echo "[$PATH_NAME] Normal ($TX_MBPS Mbps). Lock Redis cleared."
            fi
        else
            echo "[$PATH_NAME] Gagal mengambil data. Raw: '$TRAFFIC'"
        fi
    done
}