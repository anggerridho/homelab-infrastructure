#!/bin/bash

# Konfigurasi Path dan Ambang Batas
CERT_FILE="/opt/adguard/ssl/fullchain.cer"
ALERT_SCRIPT="/home/ubuntu/homelab-infrastructure/scripts/homelab-2/alertelegram.sh"
DOMAIN="ytta.localhostaddr.biz.id"
DAYS_THRESHOLD=7

# Pastikan file sertifikat tersedia
if [ ! -f "$CERT_FILE" ]; then
    MSG="[$(date +'%Y-%m-%d %H:%M:%S')] ❌ Error: File sertifikat $CERT_FILE tidak ditemukan!"
    TxT="$MSG" bash "$ALERT_SCRIPT"
    exit 1
fi

# Ekstrak tanggal kedaluwarsa dan konversi ke detik (Epoch)
EXP_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
EXP_EPOCH=$(date -d "$EXP_DATE" +%s)
CURRENT_EPOCH=$(date +%s)

# Hitung sisa hari
REMAINING_DAYS=$(( (EXP_EPOCH - CURRENT_EPOCH) / 86400 ))

# Kirim alert jika sisa hari kurang dari atau sama dengan threshold
if [ "$REMAINING_DAYS" -le "$DAYS_THRESHOLD" ]; then
    MSG="[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ SSL Alert: Sertifikat $DOMAIN tersisa $REMAINING_DAYS hari (Expired: $EXP_DATE). Segera jalankan adguardSSL.sh!"

    # Eksekusi script Telegram alert
    TxT="$MSG" bash "$ALERT_SCRIPT"

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] - Alert terkirim: $REMAINING_DAYS hari tersisa."
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] - Sertifikat aman. Sisa waktu: $REMAINING_DAYS hari."
fi
