#!/bin/bash

hardware_metrics(){
# 1. MENDAPATKAN CPU LOAD STB LOKAL
# Kita ambil nilai %id (idle) dari perintah 'top', lalu kita kurangi 100
STB_CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/")
STB_CPU_LOAD=$(awk -v idle="$STB_CPU_IDLE" 'BEGIN { printf "%.2f", 100 - idle }')

# 2. MENDAPATKAN MEMORY USAGE STB LOKAL (%)
STB_MEM_USAGE=$(free | awk '/Mem/ {printf "%.2f", $3/$2 * 100.0}')

redis-cli SETEX dump_cpu_load 120 "$STB_CPU_LOAD" > /dev/null
redis-cli SETEX dump_mem_usage 120 "$STB_MEM_USAGE" > /dev/null

# MENDAPATKAN TOP PROCESS (PELAKU CPU TINGGI)
RAW_LINE=$(ps -eo comm,pcpu --sort=-pcpu | grep -Evi 'ps|grep|mega_cmd|bash' | grep -v "COMMAND" | head -n 1)

# Gunakan xargs untuk membuang spasi di awal/akhir agar awk tidak meleset
TOP_APP_NAME=$(echo "$RAW_LINE" | xargs | awk '{print $1}')
TOP_APP_CPU=$(echo "$RAW_LINE" | xargs | awk '{print $2}')

# Validasi: Jika karena suatu hal tetap kosong, beri nilai default agar Grafana tidak 'No Data'
if [[ -z "$TOP_APP_NAME" || -z "$TOP_APP_CPU" ]]; then
    TOP_APP_NAME="system-idle"
    TOP_APP_CPU="0.00"
fi

SAFE_APP_NAME=$(echo "$TOP_APP_NAME" | tr -cd 'A-Za-z0-9_-')

redis-cli SETEX dump_top_app_name 120 "$SAFE_APP_NAME" > /dev/null
redis-cli SETEX dump_top_app_cpu 120 "$TOP_APP_CPU" > /dev/null

# CPU Load by AdGuard
CPU_LOAD=$(awk '{print $1}' /proc/loadavg)
RAM_INFO=$(free -m)
RAM_USED=$(echo "$RAM_INFO" | awk '/Mem:/ {print $3}')
RAM_FREE=$(echo "$RAM_INFO" | awk '/Mem:/ {print $4}')

# Simpan ke Redis lokal (dengan kedaluwarsa 120 detik agar tidak basi)
redis-cli SETEX dump_cpu_loadavg 120 "$CPU_LOAD" > /dev/null
redis-cli SETEX dump_ram_used 120 "$RAM_USED" > /dev/null
redis-cli SETEX dump_ram_free 120 "$RAM_FREE" > /dev/null
}
