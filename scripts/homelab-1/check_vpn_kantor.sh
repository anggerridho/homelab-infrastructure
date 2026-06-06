#!/bin/bash

cek_vpn_kantor() {
    APP_NAME="openfortivpn"
    REDIS_KEY="lock_remote_${APP_NAME}"
    STATE_KEY="state_${APP_NAME}"
    STATUS_CODE=0
    ERROR_DETAIL=""
    REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
    
    # Gunakan --raw agar output bersih dari Redis tanpa perlu memotong newline manual
    LAST_INFLUX_STATUS=$(redis-cli -h ${REDIS_HOST} --raw GET "influx_last_status_${APP_NAME}")
    MINUTE_NOW=$(date +%M)

    # 1. CEK STATUS INTERFACE PPP0
    # Menggunakan ip addr show, jika exit status 0 (sukses), berarti interface ada
    if ip addr show ppp0 > /dev/null 2>&1; then
        STATUS_CODE=1
    else
        HOUR_NOW=$(date +%H)
        if [ "$HOUR_NOW" -eq 18 ]; then
            ERROR_DETAIL="VPN Offline (Terjadwal)"
        else
            ERROR_DETAIL="VPN Offline (Gangguan/Unscheduled)"
        fi
        ${HOMELAB}/homelab-1/disconnect_vpn.sh
    fi

    # 2. INTEGRASI GRAFANA (INFLUXDB)
    # Tulis ke Influx HANYA JIKA:
    # 1. Statusnya BERUBAH (Online -> Offline atau sebaliknya)
    # 2. ATAU setiap kelipatan 5 menit (Heartbeat agar Grafana fill(previous) tidak error)
    if [ "$STATUS_CODE" != "$LAST_INFLUX_STATUS" ] || [ $((10#$MINUTE_NOW % 5)) -eq 0 ]; then

        # Tembak ke InfluxDB (Sudah menggunakan tag host)
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "remote_access,host=$(hostname),app=${APP_NAME} status=${STATUS_CODE}" > /dev/null 2>&1

        # Update memori Redis dengan status terbaru
        redis-cli -h ${REDIS_HOST} SET "influx_last_status_${APP_NAME}" "$STATUS_CODE" > /dev/null 2>&1
    fi

    # 3. LOGIKA REDIS & TELEGRAM ALERT (STATE MACHINE)
    IS_LOCKED=$(redis-cli -h ${REDIS_HOST} --raw GET $REDIS_KEY)
    CURRENT_STATE=$(redis-cli -h ${REDIS_HOST} --raw GET $STATE_KEY)

    if [ "$STATUS_CODE" -eq 0 ]; then
        # JIKA OFFLINE (0)
        
        if [ "$IS_LOCKED" != "1" ]; then
            if [ -z "$CURRENT_STATE" ]; then
                # KONDISI 1: Redis baru restart / STB habis reboot (state kosong)
                echo "[INIT] ${APP_NAME} Down saat boot. Alert di-skip."
                
                # Langsung lock dan set state DOWN tanpa kirim Telegram
                redis-cli -h ${REDIS_HOST} SET $STATE_KEY "DOWN" > /dev/null 2>&1
                redis-cli -h ${REDIS_HOST} SET $REDIS_KEY "1" > /dev/null 2>&1
            else
                # KONDISI 2: Transisi murni (sebelumnya UP, sekarang DOWN)
                # LOCK DULU SEBELUM KIRIM TELEGRAM (Menghindari hang)
                redis-cli -h ${REDIS_HOST} SET $REDIS_KEY "1" > /dev/null 2>&1
                redis-cli -h ${REDIS_HOST} SET $STATE_KEY "DOWN" > /dev/null 2>&1
                echo "[ALERT] ${APP_NAME} Down! Redis Lock aktif."
                
                # Eksekusi Telegram
                MSG="[$(date +'%Y%m%d_%H:%M:%S')] - 🚨 ALERT: ${ERROR_DETAIL} | STB"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
            fi
        else
            # Silent mode
            echo "[HECTIC] ${APP_NAME} Down. (Masa Lock Telegram)" > /dev/null 2>&1
        fi
    
    else
        # JIKA ONLINE (1)
        
        if [ "$CURRENT_STATE" == "DOWN" ]; then
            # KONDISI: Recovery (sebelumnya DOWN, sekarang UP)
            # HAPUS LOCK DULU
            redis-cli -h ${REDIS_HOST} DEL $REDIS_KEY > /dev/null 2>&1
            redis-cli -h ${REDIS_HOST} SET $STATE_KEY "UP" > /dev/null 2>&1
            echo "[RECOVERY] ${APP_NAME} UP kembali! Lock dihapus."
            
            # Baru kirim Telegram
            MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ✅ RECOVERY SUCCESS: ${APP_NAME} is back Online! | STB"
            TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
        else
            if [ -z "$CURRENT_STATE" ]; then
                # KONDISI: STB baru boot dan VPN langsung sukses terhubung
                redis-cli -h ${REDIS_HOST} SET $STATE_KEY "UP" > /dev/null 2>&1
                echo "[NORMAL] ${APP_NAME} is Online sejak boot."
            else
                echo "[NORMAL] ${APP_NAME} is Online." > /dev/null 2>&1
            fi
        fi
    fi
}