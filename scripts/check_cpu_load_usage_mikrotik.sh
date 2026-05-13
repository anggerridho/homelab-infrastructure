#!/bin/bash

check_cpu_load_usage_mikrotik(){
    echo "[$(date +'%Y%m%d_%H:%M:%S')] - Memproses Resource MikroTik dari cache..."
    
    # 1. KONSUM DARI RAW_DATA
    RESOURCE_DATA=$(echo "$RAW_DATA" | grep "^RESOURCE|")
    
    if [ -n "$RESOURCE_DATA" ]; then
        IFS='|' read -r PREFIX CPU_LOAD FREE_MEM TOTAL_MEM <<< "$RESOURCE_DATA"
        
        # Kalkulasi Memory Usage (%) menggunakan AWK agar presisi desimal
        # Rumus: ((Total - Free) / Total) * 100
        if [ "$TOTAL_MEM" -gt 0 ]; then
            MEM_USED=$((TOTAL_MEM - FREE_MEM))
            MEM_USAGE_PCT=$(awk -v used="$MEM_USED" -v total="$TOTAL_MEM" 'BEGIN { printf "%.2f", (used/total)*100 }')
        else
            MEM_USAGE_PCT=0
        fi
        
        # --- KIRIM KE INFLUXDB ---
        curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
        --data-binary "router_resource,device=mikrotik cpu_load=$CPU_LOAD,mem_usage=$MEM_USAGE_PCT" > /dev/null 2>&1
        
        # Silakan uncomment baris di bawah ini jika ingin memantau angkanya di terminal
        # echo "[MIKROTIK] CPU: $CPU_LOAD%, RAM: $MEM_USAGE_PCT%"
    else
        echo "[MIKROTIK] Data Resource gagal diambil dari cache!"
    fi
}