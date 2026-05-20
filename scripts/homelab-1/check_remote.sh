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
          # Flag -it diganti dengan -i agar aman dieksekusi via cronjob
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
  # Mengirimkan status 1 atau 0 ke tabel 'remote_access'
  curl -s -i -XPOST "http://${DB_HOST}/write?db=${DB_NAME}" \
  --data-binary "remote_access,app=${LOOP_REMOTE} status=${STATUS_CODE}" > /dev/null 2>&1

  # 3. LOGIKA REDIS & TELEGRAM ALERT
  REDIS_KEY="lock_remote_${LOOP_REMOTE}"
        
  if [ "$STATUS_CODE" -eq 0 ]; then
      # Jika Offline (0), cek apakah sudah ada lock
      IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY)
      
      if [ "$IS_LOCKED" != "1" ]; then
          # Jika belum dilock, kirim Telegram
          MSG="[$(date +'%Y%m%d_%H:%M:%S')] - 🚨 ALERT: ${ERROR_DETAIL}"
          TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
          
          # Lock Redis selama 1 Jam (3600 detik)
          redis-cli -h ${REDIS_HOST} SETEX $REDIS_KEY 3600 "1" > /dev/null 2>&1
          echo "[ALERT] ${LOOP_REMOTE} Down! Telegram terkirim & Redis Lock aktif."
      else
          # Silent mode jika masih di masa lock
          echo "[HECTIC] ${LOOP_REMOTE} Down. (Masa Lock Telegram)" > /dev/null 2>&1
      fi
  else
      # Jika Online (1), cek apakah sebelumnya ada lock (berarti baru saja recover dari down)
      IS_LOCKED=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY)
      
      if [ "$IS_LOCKED" == "1" ]; then
          # 1. Kirim Telegram Recovery
          MSG="[$(date +'%Y%m%d_%H:%M:%S')] - ✅ RECOVERY SUCCESS: ${LOOP_REMOTE} is back Online!"
          TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
          
          # 2. Hapus lock agar siap alert jika down lagi di masa depan
          redis-cli -h ${REDIS_HOST} DEL $REDIS_KEY > /dev/null 2>&1
          echo "[RECOVERY] ${LOOP_REMOTE} UP kembali! Telegram terkirim & Lock dihapus."
      else
          # Silent mode jika dari awal memang normal
          echo "[NORMAL] ${LOOP_REMOTE} is Online."
      fi
  fi
done
}