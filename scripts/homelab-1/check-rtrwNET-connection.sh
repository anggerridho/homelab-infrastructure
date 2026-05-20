#!/bin/bash
PATH=/usr/bin

export HOMELAB="/root/homelab-infrastructure/scripts"
export HOST_LAB="${HOMELAB}/homelab-1"

source ${HOMELAB}/vault.sh
source ${HOST_LAB}/get_data_mikrotik.sh
source ${HOST_LAB}/check_cctv.sh
source ${HOST_LAB}/check_rtrwNet.sh
source ${HOST_LAB}/check_hectic_isp.sh
source ${HOST_LAB}/check_traffic_distribution.sh
source ${HOST_LAB}/check_top_user.sh
source ${HOST_LAB}/check_isp_failover.sh
source ${HOST_LAB}/check_critical_applications.sh
source ${HOST_LAB}/check_anomali_speedtest.sh
source ${HOST_LAB}/check_remote.sh
source ${HOST_LAB}/check_disk.sh
source ${HOST_LAB}/check_cpu_load_usage_mikrotik.sh
source ${HOST_LAB}/check_cpu_mem_usage_stb.sh
source ${HOST_LAB}/check_disk_io_stb.sh
source ${HOST_LAB}/check_vps_monitor.sh
source ${HOST_LAB}/telemetry_collector.sh
source ${HOMELAB}/housekeeping.sh

main(){
    vault
    get_data
    cctv
    rtrw
    check_hectic_isp
    traffic_distribution
    check_top_user
    cek_isp_failover
    cek_critical_applications
    cek_anomali_speedtest
    remote
    disk
    check_cpu_load_usage_mikrotik
    check_cpu_mem_usage_stb
    check_disk_io_stb
    vps_monitor
    telemetry_collector
    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Proses Bulk Fetch selesai!"
    housekeeping
}

sleep 5
main #| tee -ai ${LOG_FILE}

# Notes
# curl -s -G 'http://localhost:8086/query?db=${DB_NAME}" --data-urlencode "q=SHOW MEASUREMENTS"

# for x in $(curl -s -G 'http://localhost:8086/query?db=${DB_NAME}" --data-urlencode "q=SHOW MEASUREMENTS" | jq -r '.results[0].series[0].values[][0]'); do curl -i -XPOST 'http://localhost:8086/query?db=${DB_NAME}" --data-urlencode "q=DROP MEASUREMENT $x"; done

# curl -i -XPOST 'http://localhost:8086/query?db=${DB_NAME}" --data-urlencode "q=CREATE RETENTION POLICY \"auto_clean_2d\" ON \"db_rtrw\" DURATION 30d REPLICATION 1 DEFAULT"

# Hapus seluruh database
# curl -i -XPOST 'http://localhost:8086/query' --data-urlencode "q=DROP DATABASE db_rtrw"

# Buat lagi database-nya (kosong)
# curl -i -XPOST 'http://localhost:8086/query' --data-urlencode "q=CREATE DATABASE db_rtrw"

# Cek Redis
# redis-cli keys "*"

# Delete All Data Redis
# redis-cli flushall
