#!/bin/bash

telemetry_collector(){
LOG_FILE="/var/log/telemetry_adguard.log"

# ==========================================
# 1. TARIK METRIK ADGUARD API
# ==========================================
AGH_STATS=$(curl -s -u "$AGH_USER:$AGH_PASS" "$AGH_URL/control/stats")

# Ekstrak nilai menggunakan jq
DNS_QUERIES=$(echo "$AGH_STATS" | jq '.num_dns_queries')
BLOCKED=$(echo "$AGH_STATS" | jq '.num_blocked_filtering')

# Waktu proses AdGuard biasanya dalam format detik (0.063), kita ubah ke milidetik (ms)
AVG_TIME_MS=$(echo "$AGH_STATS" | jq '.avg_processing_time * 1000' | awk '{printf "%.0f", $1}')

# =========================================================
# 2. TARIK METRIK HARDWARE STB
# =========================================================

# --- A. METRIK HOMELAB-2 (Tarik dari Redis Node-2) ---
HL2_RAM_USED=$(redis-cli -h "$REDIS_HOST" GET dump_ram_used | tr -d '\r\n')
HL2_RAM_FREE=$(redis-cli -h "$REDIS_HOST" GET dump_ram_free | tr -d '\r\n')
HL2_CPU_LOAD=$(redis-cli -h "$REDIS_HOST" GET dump_cpu_loadavg | tr -d '\r\n')

# Validasi jika Node-2 mati
HL2_RAM_USED=${HL2_RAM_USED:-0}
HL2_RAM_FREE=${HL2_RAM_FREE:-0}
HL2_CPU_LOAD=${HL2_CPU_LOAD:-0}

# --- B. METRIK HOMELAB-1 (Ambil Lokal) ---
HL1_CPU_LOAD=$(awk '{print $1}' /proc/loadavg)
HL1_RAM_INFO=$(free -m)
HL1_RAM_USED=$(echo "$HL1_RAM_INFO" | awk '/Mem:/ {print $3}')
HL1_RAM_FREE=$(echo "$HL1_RAM_INFO" | awk '/Mem:/ {print $4}')

# Validasi Homelab-1 (Sebagai pengaman)
HL1_RAM_USED=${HL1_RAM_USED:-0}
HL1_RAM_FREE=${HL1_RAM_FREE:-0}
HL1_CPU_LOAD=${HL1_CPU_LOAD:-0}


# =========================================================
# 3. FORMAT INFLUXDB LINE PROTOCOL & KIRIM
# =========================================================
# Kita gunakan tag host=homelab-1 dan host=homelab-2 agar terbaca terpisah di Grafana
# Pastikan tidak ada spasi di sekitar tanda sama dengan (=) pada tag dan field

PAYLOAD="adguard_dns,host=homelab-1 total_queries=$DNS_QUERIES,blocked_queries=$BLOCKED,processing_time_ms=$AVG_TIME_MS
stb_system,host=homelab-2 ram_used_mb=$HL2_RAM_USED,ram_free_mb=$HL2_RAM_FREE,cpu_load=$HL2_CPU_LOAD
stb_system,host=homelab-1 ram_used_mb=$HL1_RAM_USED,ram_free_mb=$HL1_RAM_FREE,cpu_load=$HL1_CPU_LOAD"

# Tembak data ke InfluxDB
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -XPOST "$DB_HOST/write?db=$DB_NAME" --data-binary "$PAYLOAD")

# Pencatatan log
if [ "$HTTP_CODE" -eq 204 ]; then
    echo "[$(date)] Metrik berhasil dikirim ke InfluxDB." #>> "$LOG_FILE"
else
    echo "[$(date)] GAGAL! HTTP Code: $HTTP_CODE" #>> "$LOG_FILE"
fi

# Cek apakah latensi melebihi threshold
if [ "$AVG_TIME_MS" -ge "$LATENCY_THRESHOLD" ]; then
    # Ambil status lock dari Redis
    IS_LOCKED=$(redis-cli -h "$REDIS_HOST" GET $REDIS_KEY_LATENCY | tr -d '\r\n')

    if [ "$IS_LOCKED" != "1" ]; then
        # Pasang lock agar tidak spam
        redis-cli -h "$REDIS_HOST" SET $REDIS_KEY_LATENCY "1" > /dev/null 2>&1
        
        # Kirim Alert Telegram
        MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ⚠️ WARNING: AdGuard Latency High! (${AVG_TIME_MS} ms)"
        TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
        
        echo "[ALERT] Latensi AdGuard Tinggi: ${AVG_TIME_MS}ms. Lock aktif." #>> "$LOG_FILE"
    else
        echo "[HECTIC] Latensi masih tinggi (${AVG_TIME_MS}ms). (Masa Lock)" #>> "$LOG_FILE"
    fi
else
    # Jika latensi sudah kembali normal (di bawah 100ms)
    IS_LOCKED=$(redis-cli -h "$REDIS_HOST" GET $REDIS_KEY_LATENCY | tr -d '\r\n')

    if [ "$IS_LOCKED" == "1" ]; then
        # Hapus lock
        redis-cli -h "$REDIS_HOST" DEL $REDIS_KEY_LATENCY > /dev/null 2>&1
        
        # Kirim Alert Recovery
        MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ✅ RECOVERY: AdGuard Latency Normal (${AVG_TIME_MS} ms)"
        TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
        
        echo "[RECOVERY] Latensi AdGuard Normal: ${AVG_TIME_MS}ms. Lock dihapus." #>> "$LOG_FILE"
    fi
fi
}
