#!/bin/bash

# Pastikan script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "Tolong jalankan script ini menggunakan sudo"
  exit 1
fi

echo "Memulai pencarian disk berdasarkan ukuran..."

# Menambahkan flag -l (list) agar karakter tree (└─) hilang
PART_1TB=$(lsblk -p -l -n -o NAME,SIZE,TYPE | awk '$3=="part" && $2 ~ /^931/ {print $1}' | head -n 1)
PART_14GB=$(lsblk -p -l -n -o NAME,SIZE,TYPE | awk '$3=="part" && $2 ~ /^14/ {print $1}' | head -n 1)

# ==========================================
# 1. Mount size ~931G ke /mnt/disk2
# ==========================================
if [ -n "$PART_1TB" ]; then
    echo "[OK] Ditemukan partisi ~931G di: $PART_1TB"
    mkdir -p /mnt/disk2

    if grep -qs '/mnt/disk2 ' /proc/mounts; then
        echo " -> /mnt/disk2 sudah ter-mount sebelumnya. Melewati..."
    else
        mount "$PART_1TB" /mnt/disk2
        # Pengecekan apakah mount benar-benar sukses
        if [ $? -eq 0 ]; then
            echo " -> Berhasil mount $PART_1TB ke /mnt/disk2"
        else
            echo " -> [ERROR] Gagal mount $PART_1TB ke /mnt/disk2"
        fi
    fi
else
    echo "[FAIL] Partisi dengan ukuran ~931G tidak ditemukan!"
fi

echo "------------------------------------------"

# ==========================================
# 2. Mount size ~14.3G ke /mnt/disk1
# ==========================================
if [ -n "$PART_14GB" ]; then
    echo "[OK] Ditemukan partisi ~14G di: $PART_14GB"
    mkdir -p /mnt/disk1

    if grep -qs '/mnt/disk1 ' /proc/mounts; then
        echo " -> /mnt/disk1 sudah ter-mount sebelumnya. Melewati..."
    else
        mount "$PART_14GB" /mnt/disk1
        if [ $? -eq 0 ]; then
            echo " -> Berhasil mount $PART_14GB ke /mnt/disk1"
        else
            echo " -> [ERROR] Gagal mount $PART_14GB ke /mnt/disk1"
        fi
    fi
else
    echo "[FAIL] Partisi dengan ukuran ~14G tidak ditemukan!"
fi

echo "Selesai!"
