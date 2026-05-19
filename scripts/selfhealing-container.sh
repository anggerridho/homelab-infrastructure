#!/bin/bash

selfhealing_swarm(){
# Menggunakan --format agar output mudah di-parsing dengan pemisah '|'
docker service ls --format '{{.Name}}|{{.Replicas}}' | while IFS='|' read -r name replicas; do
    
    # Memisahkan angka running dan desired dari format 'Running/Desired' (contoh: 0/1)
    running=$(echo "${replicas}" | cut -d'/' -f1)
    desired=$(echo "${replicas}" | cut -d'/' -f2)

    # Cek jika service seharusnya berjalan (desired > 0) tapi mati (running == 0)
    if [[ "$running" -eq 0 && "$desired" -gt 0 ]]; then
        echo "-> Terdeteksi: Service '${name}' memiliki replicas ${replicas}."

        # Ambil status dari task terakhir (head -n 1 mengambil riwayat teratas)
        state=$(docker service ps "${name}" --format '{{.CurrentState}}' | head -n 1)

        # Mengecek apakah statusnya mengandung kata Shutdown, Failed, atau Rejected
        if [[ "${state}" == *"Shutdown"* || "${state}" == *"Failed"* || "${state}" == *"Rejected"* ]]; then
            MSG="[$(date +'%Y%m%d %H:%M:%S')] - Status task terakhir: ${state}. ${name} try self-healing"; echo "${MSG}"
            TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
            
            # 1. Scale down ke 0
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] - Scaling ${name} ke 0..."
            docker service scale "${name}=0" > /dev/null
            
            # Beri jeda sebentar agar Docker Swarm punya waktu mematikan task dan membersihkan state
            sleep 3 
            
            # 2. Scale up kembali ke jumlah desired semula
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] - Scaling ${name} kembali ke ${desired}..."
            docker service scale "${name}=${desired}" > /dev/null
            
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] - [SELESAI] Self-healing untuk ${name} berhasil."
        else
            # Jika statusnya "Starting" atau "Preparing", jangan diganggu
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] - Status task saat ini: ${state}. Bukan Shutdown/Failed, melewati..."
        fi
    fi
done
}
