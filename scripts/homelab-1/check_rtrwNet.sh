#!/bin/bash

rtrw(){
    LIST_CLIENT="$(cat ${HOMELAB}/listCheck.conf | grep -E 'E1|E2' | grep -vi '#')"
    TOO_MUCH="10"

    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses status klien RTRW dari cache memori..."

    # 1. Ekstrak data RTRW dari RAW_DATA (Pindahkan baris ini ke sini!)
    ALL_ACTIVE_CLIENTS=$(echo "$RAW_DATA" | awk '/---RTRW_START---/{flag=1; next} /---RTRW_END---/{flag=0} flag')

    # Menggunakan <<< agar loop berjalan di shell utama
    while read -r LOOP_CLIENT; do
        # Abaikan baris kosong
        [ -z "$LOOP_CLIENT" ] && continue
        
        READ_CLIENT="$(echo "${LOOP_CLIENT}" | sed 's/|/ /g')"
        SSID="$(echo "${LOOP_CLIENT}" | awk -F'|' '{print $1}')"
        SAFE_CLIENT=$(echo "${SSID}" | tr -cd 'A-Za-z0-9_-')
        
        # Ekstrak IP Address dari LOOP_CLIENT (Tambahkan ini agar pencarian lebih akurat)
        TARGET_IP="$(echo "${LOOP_CLIENT}" | awk -F'|' '{print $2}')"
            
        # 2. Pengecekan HANYA mencari IP (Lebih aman daripada mencari nama)
        CHECK_ACTIVE=$(echo "$ALL_ACTIVE_CLIENTS" | grep -E "${TARGET_IP}")
            
        STATUS_CODE=0
        if [ -n "${CHECK_ACTIVE}" ]; then
            STATUS_CODE=1 # Online
        fi

        # --- A. INTEGRASI GRAFANA (INFLUXDB) ---
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "client_hotspot,nama=${SAFE_CLIENT} status=${STATUS_CODE}" > /dev/null 2>&1

        # --- B. LOGIKA REDIS (ANTI-SPAM & STATE MACHINE) ---
        REDIS_KEY="count_rtrw_${SAFE_CLIENT}"
        REBOOT_FLAG="reboot_flag_${SAFE_CLIENT}"

        if [ "$STATUS_CODE" -eq 1 ]; then
            # JIKA ONLINE
            COUNT_INACTIVE=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY)
                
            if [[ -n "$COUNT_INACTIVE" && "$COUNT_INACTIVE" -gt 0 ]]; then
                MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ${READ_CLIENT} Connected"
                echo "${MSG}"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                
                # Reset Redis
                redis-cli -h ${REDIS_HOST} DEL $REDIS_KEY > /dev/null 2>&1
                redis-cli -h ${REDIS_HOST} DEL $REBOOT_FLAG > /dev/null 2>&1
            else
                echo "[$(date +'%Y%m%d_%H:%M:%S')] - ${READ_CLIENT} Connected"
            fi
                
        else
            # JIKA OFFLINE
            COUNT_INACTIVE=$(redis-cli -h ${REDIS_HOST} INCR $REDIS_KEY)
            redis-cli -h ${REDIS_HOST} EXPIRE $REDIS_KEY 86400 > /dev/null 2>&1
            
            if [ "$COUNT_INACTIVE" -eq 1 ]; then
                MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ${READ_CLIENT} Inactive"
                echo "${MSG}"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                
            elif [ "$COUNT_INACTIVE" -eq 5 ]; then
                MSG="A customer has received ${COUNT_INACTIVE} alerts indicating a failed connection to (${SSID_WISP}). I recommend that you try restarting the MikroTik as a troubleshooting step before contacting the customer regarding the issue they are experiencing."
                echo "${MSG}"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                
            elif [ "$COUNT_INACTIVE" -gt "$TOO_MUCH" ]; then
                HAS_REBOOTED=$(redis-cli -h ${REDIS_HOST} GET $REBOOT_FLAG)
                
                if [ "$HAS_REBOOTED" != "1" ]; then
                    MSG="A customer has received ${COUNT_INACTIVE} alerts indicating a failed connection to (${SSID_WISP}). I will help you restart MikroTik."
                    echo "${MSG}"
                    TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                    
                    redis-cli -h ${REDIS_HOST} SET $REBOOT_FLAG "1" > /dev/null 2>&1
                    
                    # Eksekusi Reboot (Ini tetap pakai SSH karena berupa perintah eksekusi/aksi)
                    ${HOMELAB}/terminate.sh -t 3 sshpass -p "$(echo ${MIKROTIK_PSSWD} | base64 -d)" ssh -t -oStrictHostKeyChecking=no ${MIKROTIK_HOST} ":execute {/system reboot}"
                else
                    MSG="A customer has received ${COUNT_INACTIVE} alerts indicating a failed connection to (${SSID_WISP}). Please go on-site immediately to conduct a thorough and serious investigation."
                    echo "${MSG}"
                    TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                fi
            else
                echo "[HECTIC] ${READ_CLIENT} Inactive (Hitungan ke-${COUNT_INACTIVE}). Silent mode." > /dev/null 2>&1
            fi
        fi
    done <<< "$LIST_CLIENT"
}