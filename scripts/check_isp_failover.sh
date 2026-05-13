#!/bin/bash

cek_isp_failover(){
    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses data status Failover dari cache..."

    # 1. KONSUM DARI RAW_DATA
    # Ambil baris yang diawali dengan ISP_FAILOVER
    ISP_DATA=$(echo "$RAW_DATA" | grep "^ISP_FAILOVER|")
    
    # Ekstrak nilai berdasarkan pembatas '|' (Kolom 2 untuk IndiHome, Kolom 3 untuk XL)
    STATUS_INDIHOME=$(echo "$ISP_DATA" | awk -F'|' '{print $2}')
    STATUS_XL=$(echo "$ISP_DATA" | awk -F'|' '{print $3}')

    # Fallback ke 0 (Down) jika MikroTik baru reboot dan variabel global masih kosong
    [ -z "$STATUS_INDIHOME" ] && STATUS_INDIHOME=0
    [ -z "$STATUS_XL" ] && STATUS_XL=0

    # FUNGSI PROCESSOR (GRAFANA + REDIS + TELEGRAM)
    process_isp() {
        local NAMA_ISP=$1
        local STATUS_CODE=$2
        local METODE=$3

        # --- A. KIRIM KE GRAFANA (INFLUXDB) ---
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "isp_status,provider=$NAMA_ISP value=$STATUS_CODE" > /dev/null 2>&1

        # --- B. STATE MACHINE (REDIS) ---
        local REDIS_KEY="state_isp_$NAMA_ISP"
        local LAST_STATE=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY)

        if [ "$STATUS_CODE" -eq 0 ]; then
            # JIKA DOWN
            if [ "$LAST_STATE" != "0" ]; then
                MSG="🚨 *ALERT FAILOVER*%0A%0AISP: *$NAMA_ISP*%0AStatus: *DOWN*%0AMetode: $METODE"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                redis-cli -h ${REDIS_HOST} SET $REDIS_KEY "0" > /dev/null 2>&1
                echo "[$NAMA_ISP] DOWN! Alert terkirim."
            else
                echo "[$NAMA_ISP] Masih DOWN. (Silent Mode)"
            fi
        else
            # JIKA UP
            if [ "$LAST_STATE" == "0" ]; then
                MSG="✅ *RECOVERY SUCCESS*%0A%0AISP: *$NAMA_ISP*%0AStatus: *UP (Connected)*%0AMetode: $METODE"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                echo "[$NAMA_ISP] UP kembali! Alert Recovery terkirim."
            else
                echo "[$NAMA_ISP] Normal (UP)."
            fi
            redis-cli -h ${REDIS_HOST} SET $REDIS_KEY "1" > /dev/null 2>&1
        fi
    }

    # Eksekusi fungsi dengan parameter yang sudah disiapkan
    process_isp "IndiHome" "$STATUS_INDIHOME" "ICMP Ping (8.8.8.8)"
    process_isp "XL_Backup" "$STATUS_XL" "HTTP Fetch (detectportal.firefox.com)"

    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Selesai mengecek ISP."
}