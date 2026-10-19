#!/bin/bash

monitor_stb(){
# ==========================================
# KONFIGURASI TARGET & LOKAL
# ==========================================
TARGET_IP="192.168.10.3"
TARGET_NAME="STB-1"
STB_ASAL="STB-2"                  # Nama STB tempat script ini berjalan
LOG_FILE="/var/log/stb_monitor.log"
STATE_FILE="/tmp/state_stb_monitor_${TARGET_NAME}.txt"
CURRENT_TIME=$(date +'%Y-%m-%d %H:%M:%S')

# ==========================================
# PING & CEK STATUS LOKAL
# ==========================================
if ping -c 4 -i 0.5 -W 1 "${TARGET_IP}" > /dev/null 2>&1; then
    STATUS_CODE=1
else
    STATUS_CODE=0
fi

if [ -f "$STATE_FILE" ]; then
    CURRENT_STATE=$(cat "$STATE_FILE")
else
    CURRENT_STATE=""
fi

# ==========================================
# LOGIKA STATE MACHINE (Hanya untuk Log & Telegram)
# ==========================================
if [ "$STATUS_CODE" -eq 1 ]; then
    
    # JIKA ONLINE
    if [ "$CURRENT_STATE" != "1" ]; then
        if [ -z "$CURRENT_STATE" ]; then
            # INIT
            echo "[${CURRENT_TIME}] ℹ️ [INIT] Monitoring dimulai. ${TARGET_NAME} (${TARGET_IP}) ONLINE." >> "${LOG_FILE}"
        else
            # RECOVERY
            MSG="✅ [RECOVERY] ${TARGET_NAME} (${TARGET_IP}) kembali ONLINE dan dapat di-ping."
            echo "[${CURRENT_TIME}] ${MSG}" >> "${LOG_FILE}"
            TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
        fi
        
        echo "1" > "$STATE_FILE"
    fi

else
    
    # JIKA OFFLINE
    if [ "$CURRENT_STATE" != "0" ]; then
        MSG="🚨 [ALERT] ${TARGET_NAME} (${TARGET_IP}) DOWN! Tidak merespon PING."
        echo "[${CURRENT_TIME}] ${MSG}" >> "${LOG_FILE}"
        TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
        
        echo "0" > "$STATE_FILE"
    fi

fi

# ==========================================
# HEARTBEAT METRIK KE INFLUXDB
# ==========================================
# Kirim ke DB setiap kali script dieksekusi agar Grafana selalu memiliki data poin terbaru
curl -s -i -m 5 -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
--data-binary "stb_monitor,asal=${STB_ASAL},target=${TARGET_NAME} status=${STATUS_CODE}" > /dev/null 2>&1

}
