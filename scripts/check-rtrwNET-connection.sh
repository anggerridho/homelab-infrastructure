#!/bin/bash
PATH=/usr/bin

export HOMELAB="/root/homelab-infrastructure/scripts"
source ${HOMELAB}/vault.sh
source ${HOMELAB}/get_data_mikrotik.sh
source ${HOMELAB}/check_cctv.sh
source ${HOMELAB}/check_rtrwNet.sh
source ${HOMELAB}/check_hectic_isp.sh
source ${HOMELAB}/check_traffic_distribution.sh
source ${HOMELAB}/check_top_user.sh
source ${HOMELAB}/check_isp_failover.sh
source ${HOMELAB}/check_critical_applications.sh
source ${HOMELAB}/check_anomali_speedtest.sh
source ${HOMELAB}/check_remote.sh
source ${HOMELAB}/check_disk.sh
source ${HOMELAB}/check_cpu_load_usage_mikrotik.sh
source ${HOMELAB}/check_cpu_mem_usage_stb.sh
source ${HOMELAB}/check_disk_io_stb.sh
source ${HOMELAB}/check_vps_monitor.sh
source ${HOMELAB}/telemetry_collector.sh
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
