#!/bin/bash

cek_vpn_kantor() {
    APP_NAME="openfortivpn"
    REDIS_KEY="lock_remote_${APP_NAME}"
    STATUS_CODE=0
    ERROR_DETAIL=""
    REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
    LAST_INFLUX_STATUS=$(redis-cli -h ${REDIS_HOST} GET "influx_last_status_${APP_NAME}" | tr -d '\r\n')
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
    fi

    # 2. INTEGRASI GRAFANA (INFLUXDB)
    # Tulis ke Influx HANYA JIKA:
    # 1. Statusnya BERUBAH (Online -> Offline atau sebaliknya)
    # 2. ATAU setiap kelipatan 5 menit (Heartbeat agar Grafana fill(previous) tidak error)
    if [ "$STATUS_CODE" != "$LAST_INFLUX_STATUS" ] || [ $((10#$MINUTE_NOW % 5)) -eq 0 ]; then

        # Tembak ke InfluxDB
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "remote_access,app=${APP_NAME} status=${STATUS_CODE}" > /dev/null 2>&1

        # Update memori Redis dengan status terbaru
        redis-cli -h ${REDIS_HOST} SET "influx_last_status_${APP_NAME}" "$STATUS_CODE" > /dev/null 2>&1
    fi
    # (Catatan: 10#$MINUTE_NOW digunakan agar bash tidak menganggap angka seperti 08 atau 09 sebagai bilangan oktal yang salah)

    # 3. LOGIKA REDIS & TELEGRAM ALERT (STATE MACHINE)
    if [ "$STATUS_CODE" -eq 0 ]; then
        # Jika Offline (0), cek lock. Gunakan tr untuk membuang spasi/newline tersembunyi
        IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY | tr -d '\r\n')
    
        if [ "$IS_LOCKED" != "1" ]; then
            # LOCK DULU SEBELUM KIRIM TELEGRAM (Menghindari hang)
            redis-cli -h ${REDIS_HOST} SET $REDIS_KEY "1" > /dev/null 2>&1
            echo "[ALERT] ${APP_NAME} Down! Redis Lock aktif."
            
            # Eksekusi Telegram (Jika ini hang/gagal, Redis sudah terlanjur di-lock, sehingga aman dari spam)
            MSG="[$(date +'%Y%m%d_%H:%M:%S')] - 🚨 ALERT: ${ERROR_DETAIL} | STB"
            TxT="$(echo "${MSG}")" ${HOMELAB_SCRIPT}/alertelegram.sh
        else
            # Silent mode
            echo "[HECTIC] ${APP_NAME} Down. (Masa Lock Telegram)" > /dev/null 2>&1
        fi
    
    else
        # Jika Online (1)
        IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY | tr -d '\r\n')
    
        if [ "$IS_LOCKED" == "1" ]; then
            # HAPUS LOCK DULU
            redis-cli -h ${REDIS_HOST} DEL $REDIS_KEY > /dev/null 2>&1
            echo "[RECOVERY] ${APP_NAME} UP kembali! Lock dihapus."
            
            # Baru kirim Telegram
            MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ✅ RECOVERY SUCCESS: ${APP_NAME} is back Online! | STB"
            TxT="$(echo "${MSG}")" ${HOMELAB_SCRIPT}/alertelegram.sh
        else
            echo "[NORMAL] ${APP_NAME} is Online."
        fi
    fi
}