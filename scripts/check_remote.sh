#!/bin/bash

remote(){
LIST_REMOTE="tailscale cloudflare"

for LOOP_REMOTE in ${LIST_REMOTE}; do
  STATUS_CODE=0 # Default state: 0 (Offline/Down)
  ERROR_DETAIL=""

  # 1. CEK STATUS CONTAINER & APLIKASI
  CONTAINER_UP="$(docker ps | grep "${LOOP_REMOTE}" | grep 'Up' | grep -vi 'starting')"
        
  if [ -n "${CONTAINER_UP}" ]; then
      STATUS_CODE=1 # Asumsi awal: 1 (Online)
      
      # Pengecekan spesifik untuk Tailscale
      if [ "${LOOP_REMOTE}" == "tailscale" ]; then
          CONTAINER_ID="$(echo "${CONTAINER_UP}" | awk '{print $1}')"
          TAILSCALE_STATUS="$(docker exec -i ${CONTAINER_ID} tailscale status | grep "$(hostname)" | grep -i 'offline')"
          
          if [ -n "${TAILSCALE_STATUS}" ]; then
              STATUS_CODE=0 # Container jalan, tapi tunnel offline
              ERROR_DETAIL="Tailscale is offline on $(hostname)"
          fi
      fi
  else
      STATUS_CODE=0
      ERROR_DETAIL="${LOOP_REMOTE} container isn't running on $(hostname)"
  fi

  # 2. INTEGRASI GRAFANA (INFLUXDB)
  curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
  --data-binary "remote_access,host=$(hostname),app=${LOOP_REMOTE} status=${STATUS_CODE}" > /dev/null 2>&1

  # 3. LOGIKA REDIS & TELEGRAM ALERT
  REDIS_KEY="lock_remote_${LOOP_REMOTE}"
  STATE_KEY="state_${LOOP_REMOTE}"
        
  # Gunakan --raw agar ouput string bersih dari redis
  IS_LOCKED=$(redis-cli -h ${REDIS_HOST} --raw GET $REDIS_KEY)
  CURRENT_STATE=$(redis-cli -h ${REDIS_HOST} --raw GET $STATE_KEY)

  if [ "$STATUS_CODE" -eq 0 ]; then
      # JIKA OFFLINE (0)
      
      if [ "$IS_LOCKED" != "1" ]; then
          # Jika tidak dilock, cek apakah ini run pertama setelah Redis restart
          if [ -z "$CURRENT_STATE" ]; then
              # KONDISI 1: Redis habis restart (key state kosong)
              echo "[INIT] ${LOOP_REMOTE} Down saat boot. Alert di-skip."
              
              # Langsung set state dan lock agar run berikutnya tidak trigger alert
              redis-cli -h ${REDIS_HOST} SET $STATE_KEY "DOWN" > /dev/null 2>&1
              redis-cli -h ${REDIS_HOST} SET $REDIS_KEY "1" EX 3600 > /dev/null 2>&1
              
          else
              # KONDISI 2: Lock habis (expired) atau transisi dari UP ke DOWN
              
              # Khusus Tailscale, jangan re-alert berulang jika memang sengaja dimatikan
              if [ "${LOOP_REMOTE}" == "tailscale" ] && [ "$CURRENT_STATE" == "DOWN" ]; then
                  echo "[SILENT] Tailscale dibiarkan mati sesuai kebutuhan." > /dev/null 2>&1
                  redis-cli -h ${REDIS_HOST} SET $REDIS_KEY "1" EX 3600 > /dev/null 2>&1
              else
                  # Kirim Telegram Alert
                  MSG="[$(date +'%Y%m%d_%H:%M:%S')] - 🚨 ALERT: ${ERROR_DETAIL}"
                  TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
                  
                  # Lock Redis selama 1 Jam (3600 detik)
                  redis-cli -h ${REDIS_HOST} SET $REDIS_KEY "1" EX 3600 > /dev/null 2>&1
                  redis-cli -h ${REDIS_HOST} SET $STATE_KEY "DOWN" > /dev/null 2>&1
                  echo "[ALERT] ${LOOP_REMOTE} Down! Telegram terkirim & Redis Lock aktif."
              fi
          fi
      else
          # Silent mode jika masih di masa lock
          echo "[HECTIC] ${LOOP_REMOTE} Down. (Masa Lock Telegram)" > /dev/null 2>&1
      fi
  else
      # JIKA ONLINE (1)
      
      if [ "$CURRENT_STATE" == "DOWN" ]; then
          # 1. Kirim Telegram Recovery (karena sebelumnya DOWN)
          MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ✅ RECOVERY SUCCESS: ${LOOP_REMOTE} is back Online!"
          TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
          
          # 2. Update state dan hapus lock
          redis-cli -h ${REDIS_HOST} DEL $REDIS_KEY > /dev/null 2>&1
          redis-cli -h ${REDIS_HOST} SET $STATE_KEY "UP" > /dev/null 2>&1
          echo "[RECOVERY] ${LOOP_REMOTE} UP kembali! Telegram terkirim & Lock dihapus."
      else
          # Jika dari awal (atau habis restart) memang langsung UP
          if [ -z "$CURRENT_STATE" ]; then
              redis-cli -h ${REDIS_HOST} SET $STATE_KEY "UP" > /dev/null 2>&1
              echo "[NORMAL] ${LOOP_REMOTE} is Online sejak boot."
          else
              echo "[NORMAL] ${LOOP_REMOTE} is Online." > /dev/null 2>&1
          fi
      fi
  fi
done
}