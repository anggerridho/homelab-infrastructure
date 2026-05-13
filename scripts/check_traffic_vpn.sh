#!/bin/bash

cek_traffic_vpn() {
    if [ ! -d "/sys/class/net/$INTERFACE" ]; then
        # Jika VPN offline, laporkan ke InfluxDB dengan nilai 0 agar Grafana tidak "No Data"
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "vpn_traffic,interface=${INTERFACE} rx_mbps=0,tx_mbps=0" > /dev/null 2>&1
        return
    fi

    # 1. AMBIL DATA BYTES SAAT INI
    RX_NOW=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    TX_NOW=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    TIME_NOW=$(date +%s)

    # 2. AMBIL DATA SEBELUMNYA DARI REDIS
    RX_PREV=$(redis-cli -h ${REDIS_HOST} get vpn_rx_prev)
    TX_PREV=$(redis-cli -h ${REDIS_HOST} get vpn_tx_prev)
    TIME_PREV=$(redis-cli -h ${REDIS_HOST} get vpn_time_prev)

    # Simpan data sekarang ke Redis untuk pengecekan berikutnya
    redis-cli -h ${REDIS_HOST} set vpn_rx_prev "$RX_NOW"
    redis-cli -h ${REDIS_HOST} set vpn_tx_prev "$TX_NOW"
    redis-cli -h ${REDIS_HOST} set vpn_time_prev "$TIME_NOW"

    # Jika data sebelumnya kosong (baru nyala), berhenti di sini
    if [ -z "$RX_PREV" ]; then return; fi

    # 3. HITUNG SELISIH & CONVERT KE Mbps
    INTERVAL=$((TIME_NOW - TIME_PREV))
    if [ "$INTERVAL" -le 0 ]; then INTERVAL=1; fi

    RX_DIFF=$((RX_NOW - RX_PREV))
    TX_DIFF=$((TX_NOW - TX_PREV))

    # Rumus: (Bytes * 8) / (1024 * 1024) / Detik = Mbps
    RX_MBPS=$(echo "scale=2; ($RX_DIFF * 8) / (1024 * 1024) / $INTERVAL" | bc)
    TX_MBPS=$(echo "scale=2; ($TX_DIFF * 8) / (1024 * 1024) / $INTERVAL" | bc)

    # 4. KIRIM KE INFLUXDB (Measurement terpisah: vpn_traffic)
    # Menggunakan tag interface=ppp0 agar lebih rapi jika nanti ada interface lain
    curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
    --data-binary "vpn_traffic,interface=${INTERFACE} rx_mbps=$RX_MBPS,tx_mbps=$TX_MBPS" > /dev/null 2>&1

    # 5. LOGIKA ALERT TELEGRAM
    # Jika RX lebih besar dari threshold, kirim alert (Gunakan Redis lock agar tidak spam)
    IS_HIGH=$(echo "$RX_MBPS > $THRESHOLD_MBPS" | bc)
    if [ "$IS_HIGH" -eq 1 ]; then
        REDIS_KEY_TRAFFIC="lock_traffic_vpn"
        IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY_TRAFFIC)

        if [ "$IS_LOCKED" != "1" ]; then
            MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ⚠️ WARNING: Traffic VPN Tinggi! RX: ${RX_MBPS} Mbps"
            TxT="$(echo "${MSG}")" ${HOMELAB_SCRIPT}/alertelegram.sh
            # redis-cli SETEX $REDIS_KEY_TRAFFIC 1800 "1" # Lock selama 30 menit
            redis-cli -h ${REDIS_HOST} SET $REDIS_KEY "1" > /dev/null 2>&1 # Permanent Lock
        fi
    fi
}