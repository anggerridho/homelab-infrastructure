#!/bin/bash

need_reboot() {
  # --- 1. Pengecekan /mnt/disk2 (File Pribadi) ---
  # Menggunakan ls untuk mendeteksi I/O error atau unmounted
  ls -rltha /mnt/disk2/ > /dev/null 2>&1
  if [ $? != 0 ]; then
    MSG_DISK2="[$(date +'%Y%m%d_%H:%M:%S')] - Warning: $(hostname) '/mnt/disk2/' Input/output error or failed to mount"
    TxT="$(echo "${MSG_DISK2}")" ${HOMELAB}/alertelegram.sh | tee -a need-reboot.log

    # Self-healing
    echo "umount -l /mnt/disk2" | bash -v
    echo "sleep 5" | bash -v
    echo "mount $(lsblk -p -l -n -o NAME,SIZE,TYPE | awk '$3=="part" && $2 ~ /^931/ {print $1}' | head -n 1) /mnt/disk2" | bash -v

    if [ "$(docker service ls | grep homelab_samba | awk '{print $2}')" == "homelab_samba" ]; then
      echo "docker service update --force homelab_samba" | bash -v
    else
      echo "Stack homelab_samba not found"
    fi

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
