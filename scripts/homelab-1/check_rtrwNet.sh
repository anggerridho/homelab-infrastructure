#!/bin/bash

rtrw(){
    # =========================================================================
    # --- OPTION: CHECK STATUS PLN VIA MULTIPLE CCTV ---
    # Set 'true' untuk mengaktifkan deteksi PLN padam, 'false' jika sudah pakai UPS.
    # =========================================================================
    ENABLE_PLN_CHECK=true
    CCTV_IPS=("192.168.88.201" "192.168.10.11" "192.168.88.203")
    PLN_FLAG="pln_outage_flag"

    if [ "$ENABLE_PLN_CHECK" = true ]; then
        DEAD_CCTV_COUNT=0

        # Cek ping ke setiap CCTV
        for IP in "${CCTV_IPS[@]}"; do
            if ! ping -c 2 -i 0.2 -W 1 "${IP}" > /dev/null 2>&1; then
                ((DEAD_CCTV_COUNT++))
            fi
        done

        # Jika minimal 2 CCTV mati -> PLN Terkonfirmasi Padam
        if [ "$DEAD_CCTV_COUNT" -ge 2 ]; then
            HAS_PLN_ALERT=$(redis-cli -h ${REDIS_HOST} GET $PLN_FLAG)

            if [ "$HAS_PLN_ALERT" != "1" ]; then
                MSG="[$(date +'%Y%m%d_%H:%M:%S')] - 🔌 WARNING: PLN Padam / Listrik Mati! (${DEAD_CCTV_COUNT}/3 CCTV Offline). Pengecekan pelanggan di-skip."
                echo "${MSG}"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                
                # Set flag di Redis agar tidak spam alert
                redis-cli -h ${REDIS_HOST} SET $PLN_FLAG "1" > /dev/null 2>&1
            else
                echo "[$(date +'%Y%m%d_%H:%M:%S')] - PLN masih padam (${DEAD_CCTV_COUNT}/3 CCTV Offline). Pengecekan di-skip."
            fi

            # Skip seluruh pengecekan pelanggan & InfluxDB
            return 0
        else
            # PLN Normal / Menyala (Kurang dari 2 CCTV yang mati)
            HAS_PLN_ALERT=$(redis-cli -h ${REDIS_HOST} GET $PLN_FLAG)

            if [ "$HAS_PLN_ALERT" == "1" ]; then
                MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ⚡ RECOVERY: PLN Kembali Menyala! Pengecekan pelanggan dilanjutkan."
                echo "${MSG}"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                
                # Hapus flag PLN Padam dari Redis
                redis-cli -h ${REDIS_HOST} DEL $PLN_FLAG > /dev/null 2>&1
            fi
        fi
    fi

    # --- 0. EXEC HEALTH CHECK INFLUXDB TERPISAH ---
    INFLUX_ONLINE=true
    if ! ${HOMELAB}/check_influx.sh; then
        echo "[WARNING] InfluxDB Down/Unreachable! Penulisan log ke InfluxDB di-skip sementara."
        INFLUX_ONLINE=false
    fi

    LIST_CLIENT="$(cat ${HOMELAB}/listCheck.conf | grep -E 'E1|E2' | grep -vi '#')"
    TOO_MUCH="10"

    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses status klien RTRW dari cache memori..."

    # 1. Ekstrak data RTRW dari RAW_DATA
    ALL_ACTIVE_CLIENTS=$(echo "$RAW_DATA" | awk '/---RTRW_START---/{flag=1; next} /---RTRW_END---/{flag=0} flag')

    # Menggunakan <<< agar loop berjalan di shell utama
    while read -r LOOP_CLIENT; do
        # Abaikan baris kosong
        [ -z "$LOOP_CLIENT" ] && continue
        
        READ_CLIENT="$(echo "${LOOP_CLIENT}" | sed 's/|/ /g')"
        SSID="$(echo "${LOOP_CLIENT}" | awk -F'|' '{print $1}')"
        SAFE_CLIENT=$(echo "${SSID}" | tr -cd 'A-Za-z0-9_-')
        
        # Ekstrak IP Address dari LOOP_CLIENT
        TARGET_IP="$(echo "${LOOP_CLIENT}" | awk -F'|' '{print $2}')"
            
        # --- DEKLARASIKAN KUNCI REDIS DI SINI (AGAR SELALU TERSEDIA) ---
        INACTIVE_FLAG="inactive_flag_${SAFE_CLIENT}"
        SLOW_FLAG="slow_flag_${SAFE_CLIENT}"
        REDIS_KEY="count_rtrw_${SAFE_CLIENT}"
        REBOOT_FLAG="reboot_flag_${SAFE_CLIENT}"
        FAKE_FLAG="fake_connect_flag_${SAFE_CLIENT}"

        # 2. Pengecekan awal IP di list active MikroTik
        CHECK_ACTIVE=$(echo "$ALL_ACTIVE_CLIENTS" | grep -E "${TARGET_IP}")
            
        STATUS_CODE=0
        FAKE_CONNECT=0
        PACKET_LOSS=0
        AVG_LATENCY=0

        # --- VALIDASI PING (FITUR FAKE CONNECT & KUALITAS JARINGAN) ---
        if [ -n "${CHECK_ACTIVE}" ]; then
            # 1. Cek Ketersediaan (Ping Standar)
            if ping -c 8 -i 0.5 -W 1 "${TARGET_IP}" > /dev/null 2>&1; then
                STATUS_CODE=1 # Benar-benar online
                
                # 2. Cek KUALITAS (Ping Payload Besar 1472 bytes)
                PING_RESULT=$(ping -c 10 -s 1472 -i 0.2 -W 1 "${TARGET_IP}")
                PACKET_LOSS=$(echo "$PING_RESULT" | grep -oP '\d+(?=% packet loss)')
                AVG_LATENCY=$(echo "$PING_RESULT" | tail -1 | awk -F '/' '{print $5}' | cut -d '.' -f 1)
                
                # Fallback nilai jika output kosong
                [ -z "$PACKET_LOSS" ] && PACKET_LOSS=100
                [ -z "$AVG_LATENCY" ] && AVG_LATENCY=0
                
                HAS_SLOW_ALERT=$(redis-cli -h ${REDIS_HOST} GET $SLOW_FLAG)
                
                if [[ "$PACKET_LOSS" -gt 100 ]] || [[ "$AVG_LATENCY" -gt 500 ]]; then
                    if [ "$HAS_SLOW_ALERT" != "1" ]; then
                        MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ⚠️ WARNING: Koneksi ${READ_CLIENT} (${TARGET_IP}) terindikasi lambat/buruk! Loss: ${PACKET_LOSS}% | Latency: ${AVG_LATENCY}ms"
                        echo "${MSG}"
                        TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                        
                        # Set delay alert 1 jam (3600s) agar tidak spam
                        redis-cli -h ${REDIS_HOST} SET $SLOW_FLAG "1" EX 3600 > /dev/null 2>&1
                    fi
                else
                    redis-cli -h ${REDIS_HOST} DEL $SLOW_FLAG > /dev/null 2>&1
                fi
            else
                STATUS_CODE=0 # Fake Connect (Offline)
                FAKE_CONNECT=1
                PACKET_LOSS=100
                AVG_LATENCY=0
            fi
        fi

        # --- A. INTEGRASI GRAFANA (INFLUXDB) ---
        # Hanya kirim ke InfluxDB jika DB dapat diakses
        if [ "$INFLUX_ONLINE" = true ]; then
            curl -s -i -XPOST "${DB_HOST}/write?db=${DB_NAME}" \
            --data-binary "client_hotspot,nama=${SAFE_CLIENT} status=${STATUS_CODE},loss=${PACKET_LOSS},latency=${AVG_LATENCY}" > /dev/null 2>&1
        fi

        # --- B. LOGIKA REDIS (ANTI-SPAM & STATE MACHINE) ---
        if [ "$STATUS_CODE" -eq 1 ]; then
            # JIKA ONLINE SUNGGUHAN
            HAS_INACTIVE_ALERT=$(redis-cli -h ${REDIS_HOST} GET $INACTIVE_FLAG)
            HAS_FAKE_ALERT=$(redis-cli -h ${REDIS_HOST} GET $FAKE_FLAG)
                
            # Cek apakah sebelumnya pelanggan sempat Inactive ATAU Fake Connect
            if [ "$HAS_INACTIVE_ALERT" == "1" ] || [ "$HAS_FAKE_ALERT" == "1" ]; then
                MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ${READ_CLIENT} Connected"
                echo "${MSG}"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                
                # Reset Flag Inactive & Fake Connect di Redis
                redis-cli -h ${REDIS_HOST} DEL $INACTIVE_FLAG > /dev/null 2>&1
                redis-cli -h ${REDIS_HOST} DEL $FAKE_FLAG > /dev/null 2>&1
            else
                echo "[$(date +'%Y%m%d_%H:%M:%S')] - ${READ_CLIENT} Connected"
            fi
                
        else
            # JIKA OFFLINE ATAU FAKE CONNECT
            
            # 1. Kirim Alert segera untuk Fake Connect (Hotspot active tapi RTO)
            if [ "$FAKE_CONNECT" -eq 1 ]; then
                HAS_FAKE_ALERT=$(redis-cli -h ${REDIS_HOST} GET $FAKE_FLAG)
                if [ "$HAS_FAKE_ALERT" != "1" ]; then
                    MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ⚠️ ALERT: ${READ_CLIENT} (${TARGET_IP}) is FAKE CONNECT (Timeout)!"
                    echo "${MSG}"
                    TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                    
                    # Flag agar tidak spam alert Fake Connect
                    redis-cli -h ${REDIS_HOST} SET $FAKE_FLAG "1" > /dev/null 2>&1
                else
                    echo "[$(date +'%Y%m%d_%H:%M:%S')] - ${READ_CLIENT} Fake Connect (Tertahan Anti-Spam)"
                fi
                
            # 2. Kirim Alert untuk Inactive biasa (Benar-benar tidak ada di list MikroTik)
            else
                HAS_INACTIVE_ALERT=$(redis-cli -h ${REDIS_HOST} GET $INACTIVE_FLAG)
                if [ "$HAS_INACTIVE_ALERT" != "1" ]; then
                    MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ${READ_CLIENT} Inactive"
                    echo "${MSG}"
                    TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                    
                    # Flag di Redis agar tidak dikirim berulang kali selama masih offline
                    redis-cli -h ${REDIS_HOST} SET $INACTIVE_FLAG "1" > /dev/null 2>&1
                else
                    MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ${READ_CLIENT} Inactive (Tertahan Anti-Spam)"
                    echo "${MSG}"
                fi
            fi
        fi
    done <<< "$LIST_CLIENT"
}