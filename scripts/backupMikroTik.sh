#!/bin/bash

# --- Konfigurasi ---
DATE=$(date +%Y-%m-%d_%H-%M)
HOMELAB="/root/homelab-infrastructure"
BACKUP_DIR="${HOMELAB}/configs/mikrotik_config_backup"
RETENTION_DAYS=2  # Jumlah hari file disimpan
source ${HOMELAB}/scripts/vault.sh && vault

if [ ! -d ${BACKUP_DIR} ]; then
    mkdir -p $BACKUP_DIR
fi

# --- 1. Proses Backup di MikroTik ---
echo "[$(date)] Memulai proses backup di MikroTik..."
${HOMELAB}/scripts/terminate.sh -t 3 sshpass -p "$(echo ${MIKROTIK_PSSWD} | base64 -d)" ssh -t -oStrictHostKeyChecking=no ${MIKROTIK_HOST} "/system backup save name=backup_$DATE.backup; /export file=backup_$DATE.rsc"

# Jeda agar file selesai ditulis
sleep 5

# --- 2. Download File ke Homelab ---
echo "[$(date)] Mengunduh file ke Homelab..."
${HOMELAB}/scripts/terminate.sh -t 3 sshpass -p "$(echo ${MIKROTIK_PSSWD} | base64 -d)" scp ${MIKROTIK_HOST}:/backup_$DATE.backup $BACKUP_DIR/
${HOMELAB}/scripts/terminate.sh -t 3 sshpass -p "$(echo ${MIKROTIK_PSSWD} | base64 -d)" scp ${MIKROTIK_HOST}:/backup_$DATE.rsc $BACKUP_DIR/

# --- 3. Bersihkan File di MikroTik ---
echo "[$(date)] Membersihkan file sementara di MikroTik..."
${HOMELAB}/scripts/terminate.sh -t 3 sshpass -p "$(echo ${MIKROTIK_PSSWD} | base64 -d)" ssh -t -oStrictHostKeyChecking=no ${MIKROTIK_HOST} "/file remove [find name=backup_$DATE.backup]; /file remove [find name=backup_$DATE.rsc]"
echo "\n"

# --- 4. Auto-Cleanup di Homelab (Hapus file > 30 hari) ---
echo "[$(date)] Menjalankan pembersihan file lama di ${BACKUP_DIR}"
find ${BACKUP_DIR} -type f -mtime +$RETENTION_DAYS -name "backup_*" -exec rm {} \;
echo "[$(date)] File yang lebih lama dari $RETENTION_DAYS hari telah dihapus."

echo "[$(date)] Backup SELESAI!"
