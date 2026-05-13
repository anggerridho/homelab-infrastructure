#!/bin/bash

disk(){
DISK_INFO="$(df -h | grep -vE '^Filesystem|tmpfs|cdrom|boot|docker|google_drive' | tr -d '\r' | awk '{ print $5 " " $6 }')"

echo "${DISK_INFO}" | while read output
    do
        # Ekstrak persentase (angka saja) dan nama mount point / partisi
        usep=$(echo $output | awk '{ print $1}' | cut -d'%' -f1)
        partition=$(echo $output | awk '{ print $2 }')
        
        # 1. PARSING NAMA PARTISI UNTUK TAG DATABASE & REDIS
        # Ubah "/" menjadi "root" dan "/mnt/disk2" menjadi "mnt_disk2" agar aman dari error string
        SAFE_PARTITION=$(echo "$partition" | sed 's/^\///; s/\//_/g')
        [ -z "$SAFE_PARTITION" ] && SAFE_PARTITION="root"

        # 2. INTEGRASI GRAFANA (INFLUXDB)
        # Kirim persentase disk ke tabel 'disk_usage'
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "disk_usage,partition=$SAFE_PARTITION value=$usep" > /dev/null 2>&1

        # 3. LOGIKA THRESHOLD, REDIS, DAN TELEGRAM
        if [ "$usep" -ge "${THRESHOLD}" ]; then
            
            REDIS_KEY="lock_disk_$SAFE_PARTITION"
            IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY)

            if [ "$IS_LOCKED" != "1" ]; then
                # Jika belum ada lock, kirim pesan ke Telegram menggunakan alertelegram.sh bawaan Anda
                MSG="[$(date +'%Y%m%d_%H:%M:%S')] - LABRADOR Running out of space ${partition} ${usep}%"
                TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                
                # Pasang lock di Redis selama 6 jam (21600 detik)
                # (Disk penuh biasanya tidak bisa diselesaikan dalam 5 menit, jadi 6 jam sangat ideal agar tidak spam)
                redis-cli -h ${REDIS_HOST} SETEX $REDIS_KEY 21600 "1" > /dev/null 2>&1
                
                echo "Alert sent & Redis Lock (6h) activated for $partition"
            else
                # Silent mode (sedang masa lock Redis)
                # Anda bisa biarkan kosong atau dump ke /dev/null agar log terminal tetap bersih
                echo "[HECTIC] $partition penuh, tapi masa Lock Telegram masih aktif." > /dev/null 2>&1
            fi
        else
            # Jika disk sudah di bawah threshold (Anda sudah hapus file), hapus lock Redis
            REDIS_KEY="lock_disk_$SAFE_PARTITION"
            redis-cli -h ${REDIS_HOST} DEL $REDIS_KEY > /dev/null 2>&1
            
            # Print log normal Anda
            echo "[$(date +'%Y%m%d_%H:%M:%S')] - LABRADOR Space is still spacious ${partition} ${usep}%"
        fi
    done
}