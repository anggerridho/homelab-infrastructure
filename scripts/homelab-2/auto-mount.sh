#!/bin/bash

# Pastikan script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "Tolong jalankan script ini menggunakan sudo"
  exit 1
fi

echo "Memulai pencarian disk berdasarkan ukuran..."

# Menambahkan flag -l (list) agar karakter tree (└─) hilang
PART_28G=$(lsblk -p -l -n -o NAME,SIZE,TYPE | awk '$3=="part" && $2 ~ /^28/ {print $1}' | head -n 1)

# ==========================================
# 1. Mount size ~28G ke /mnt/disk1
# ==========================================
if [ -n "$PART_28G" ]; then
    echo "[OK] Ditemukan partisi ~28G di: $PART_28G"
    mkdir -p /mnt/disk1
    
    if grep -qs '/mnt/disk1 ' /proc/mounts; then
        echo " -> /mnt/disk1 sudah ter-mount sebelumnya. Melewati..."
    else
        mount "$PART_28G" /mnt/disk1
        # Pengecekan apakah mount benar-benar sukses
        if [ $? -eq 0 ]; then
            echo " -> Berhasil mount $PART_28G ke /mnt/disk1"
        else
            echo " -> [ERROR] Gagal mount $PART_28G ke /mnt/disk1"
        fi
    fi
else
    echo "[FAIL] Partisi dengan ukuran ~28G tidak ditemukan!"
fi

echo "Selesai!"