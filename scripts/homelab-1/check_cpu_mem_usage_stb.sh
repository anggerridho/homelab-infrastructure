#!/bin/bash

check_cpu_mem_usage_stb(){    
    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses Resource STB Linux..."
    
    # 1. MENDAPATKAN CPU LOAD STB LOKAL
    # Kita ambil nilai %id (idle) dari perintah 'top', lalu kita kurangi 100
    STB_CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/")
    STB_CPU_LOAD=$(awk -v idle="$STB_CPU_IDLE" 'BEGIN { printf "%.2f", 100 - idle }')
    
    # 2. MENDAPATKAN MEMORY USAGE STB LOKAL (%)
    STB_MEM_USAGE=$(free | awk '/Mem/ {printf "%.2f", $3/$2 * 100.0}')
    
    # --- KIRIM KE INFLUXDB ---
    curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
    --data-binary "stb_resource,device=homelab-1 cpu_load=$STB_CPU_LOAD,mem_usage=$STB_MEM_USAGE" > /dev/null 2>&1
    
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
    
    # KIRIM KE INFLUXDB (Gunakan 127.0.0.1 agar pasti lokal)
    curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
    --data-binary "stb_top_process,device=homelab-1,app_name=$SAFE_APP_NAME cpu_usage=$TOP_APP_CPU" > /dev/null 2>&1

    # =========================================================
    # 2. METRIK HOMELAB-2 (DARI REDIS)
    # =========================================================
    # Tarik data dari Redis Homelab-2
    HL2_CPU_LOAD=$(redis-cli -h "$REDIS_HOST" GET dump_cpu_load)
    HL2_MEM_USAGE=$(redis-cli -h "$REDIS_HOST" GET dump_mem_usage)

    # Validasi fallback: Jika Redis mati, unreachable, atau data expired (kosong)
    if [[ -z "$HL2_CPU_LOAD" ]]; then HL2_CPU_LOAD="0.00"; fi
    if [[ -z "$HL2_MEM_USAGE" ]]; then HL2_MEM_USAGE="0.00"; fi

    # Kirim metrik Homelab-2 ke InfluxDB (Gunakan tag device=homelab_2)
    curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
    --data-binary "stb_resource,device=homelab_2 cpu_load=$HL2_CPU_LOAD,mem_usage=$HL2_MEM_USAGE" > /dev/null 2>&1

    # Tarik data Top Process dari Redis Homelab-2
    HL2_TOP_APP_NAME=$(redis-cli -h "$REDIS_HOST" GET dump_top_app_name)
    HL2_TOP_APP_CPU=$(redis-cli -h "$REDIS_HOST" GET dump_top_app_cpu)

    # Validasi fallback
    if [[ -z "$HL2_TOP_APP_NAME" ]]; then HL2_TOP_APP_NAME="system-idle"; fi
    if [[ -z "$HL2_TOP_APP_CPU" ]]; then HL2_TOP_APP_CPU="0.00"; fi

    # Kirim Top Process Homelab-2 ke InfluxDB
    curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
    --data-binary "stb_top_process,device=homelab_2,app_name=$HL2_TOP_APP_NAME cpu_usage=$HL2_TOP_APP_CPU" > /dev/null 2>&1
}