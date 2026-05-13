#!/bin/bash

check_hectic_isp(){
    # DAFTAR ISP (Format: "Nama_ISP|Interface_MikroTik|Batas_Alert_Mbps")
    ISPS=(
        "IndiHome|ISP-1|50"
        "XL_Backup|ISP-2|15"
    )

    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses trafik ISP Hectic dari cache..."

    for item in "${ISPS[@]}"; do
        # Memecah data dari array
        IFS='|' read -r ISP_NAME INTERFACE THRESHOLD_MBPS <<< "$item"
        
        # Konversi ambang batas ke bps untuk pencocokan raw data
        THRESHOLD_BPS=$((THRESHOLD_MBPS * 1000000))
        SAFE_NAME=$(echo "$ISP_NAME" | tr -cd 'A-Za-z0-9_-')
        REDIS_KEY="lock_hectic_${SAFE_NAME}"

        # 1. KONSUM DARI RAW_DATA (Pencarian berbasis Interface Name)
        # Kita ambil kolom ke-3 (RX) dari baris TRAFFIC yang sudah dipilah di Master Script
        TRAFFIC=$(echo "$RAW_DATA" | grep "^TRAFFIC|${INTERFACE}|" | awk -F'|' '{print $3}')

        if [[ -n "$TRAFFIC" && "$TRAFFIC" =~ ^[0-9]+$ ]]; then
            # Konversi bits ke Mbps untuk Grafana (Gunakan awk agar presisi desimal)
            RX_MBPS=$(echo "$TRAFFIC" | awk '{printf "%.2f", $1/1000000}')

            # --- A. INTEGRASI GRAFANA ---
            curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
            --data-binary "trafik_isp,interface=$INTERFACE,isp=$SAFE_NAME rx_mbps=$RX_MBPS" > /dev/null 2>&1

            # --- B. LOGIKA ALERT TELEGRAM DENGAN REDIS ---
            if [ "$TRAFFIC" -ge "$THRESHOLD_BPS" ]; then
                # Cek status lock di Redis
                IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET "$REDIS_KEY")

                if [ "$IS_LOCKED" != "1" ]; then
                    MSG="⚠️ *ALERT HECTIC ISP*%0A%0AISP: *$ISP_NAME*%0ATrafik: *$RX_MBPS Mbps*%0AStatus: *FULL / OVER THRESHOLD*"
                    echo "[$ISP_NAME] Hectic! Mengirim alert..."
                    
                    TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                    
                    # Set Lock di Redis (tanpa expiry, atau sesuaikan kebutuhan)
                    redis-cli -h ${REDIS_HOST} SET "$REDIS_KEY" "1" > /dev/null 2>&1
                else
                    echo "[$ISP_NAME] Masih Hectic. (Telegram skip via Redis)"
                fi
            else
                # Trafik normal, hapus lock di Redis
                redis-cli -h ${REDIS_HOST} DEL "$REDIS_KEY" > /dev/null 2>&1
                echo "[$ISP_NAME] Normal ($RX_MBPS Mbps). Lock Redis dihapus."
            fi
        else
            echo "[$ISP_NAME] Gagal mendapatkan data trafik untuk interface $INTERFACE"
        fi
    done
}