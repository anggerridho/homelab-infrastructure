#!/bin/bash

need_reboot() {
  # --- 1. Pengecekan /mnt/disk2 (File Pribadi) ---
  # Menggunakan ls untuk mendeteksi I/O error atau unmounted
  ls -rltha /mnt/disk2/ > /dev/null 2>&1
  if [ $? != 0 ]; then
    MSG_DISK2="[$(date +'%Y%m%d_%H:%M:%S')] - Warning: $(hostname) '/mnt/disk2/' Input/output error or failed to mount"
    TxT="$(echo "${MSG_DISK2}")" ${HOMELAB}/alertelegram.sh | tee -a need-reboot.log
  fi

  # --- 2. Pengecekan /mnt/disk1/docker (Krusial) ---
  # Menggunakan ls untuk memicu pembacaan disk. Jika gagal, $? tidak akan 0.
  ls -rltha /mnt/disk1/docker/ > /dev/null 2>&1
  if [ $? != 0 ]; then
    MSG_DISK1="[$(date +'%Y%m%d_%H:%M:%S')] - Critical: $(hostname) '/mnt/disk1/docker' Input/output error or not found. Triggering reboot."

    # Kirim alert Telegram untuk disk1
    TxT="$(echo "${MSG_DISK1}")" ${HOMELAB}/alertelegram.sh | tee -a need-reboot.log

    # Ekspor log dmesg dan eksekusi reboot
    dmesg -T > dmesg.log
    /root/homelab-infrastructure/scripts/homelab-1/reboot.sh
  else
    # Jika ls berhasil (exit code 0), tandai sistem sehat
    touch /tmp/healthy_system.temp
  fi
}
