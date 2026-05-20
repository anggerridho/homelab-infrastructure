#!/bin/bash

check_disk_io_stb(){
    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses Disk I/O Performance STB..."

    # DAFTAR DISK (Format: "Device_Name|Label_Grafana")
    # Gunakan perintah 'lsblk' atau 'df -h' untuk memastikan sda/sdb mana yang merupakan disk2/disk3
    DISKS=(
        "sda|disk2"
        "sdb|disk3"
    )

    # Ambil data iostat (2x pengambilan dengan jeda 1 detik untuk mendapatkan rata-rata aktual)
    # Output iostat pertama adalah statistik sejak boot, yang kedua adalah yang kita butuhkan.
    IO_DATA=$(iostat -kd 1 2)

    for entry in "${DISKS[@]}"; do
        IFS='|' read -r DEV_NAME LABEL <<< "$entry"
        
        # Ekstrak baris spesifik perangkat dari output iostat yang kedua
        # Kolom 3: kB_read/s, Kolom 4: kB_wrtn/s
        DISK_STATS=$(echo "$IO_DATA" | grep "$DEV_NAME" | tail -n 1)

        if [ -n "$DISK_STATS" ]; then
            READ_KBS=$(echo "$DISK_STATS" | awk '{print $3}')
            WRITE_KBS=$(echo "$DISK_STATS" | awk '{print $4}')

            # Konversi KB ke MB agar lebih manusiawi di Grafana
            READ_MBS=$(awk -v kb="$READ_KBS" 'BEGIN { printf "%.2f", kb/1024 }')
            WRITE_MBS=$(awk -v kb="$WRITE_KBS" 'BEGIN { printf "%.2f", kb/1024 }')

            # --- KIRIM KE INFLUXDB ---
            curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
            --data-binary "disk_performance,mount=$LABEL read_mbps=$READ_MBS,write_mbps=$WRITE_MBS" > /dev/null 2>&1
            
            # echo "[$LABEL] Read: $READ_MBS MB/s | Write: $WRITE_MBS MB/s"
        else
            echo "Data untuk $DEV_NAME ($LABEL) tidak ditemukan di iostat!"
        fi
    done
}