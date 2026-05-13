#!/bin/bash
HOMELAB="/root/homelab-infrastructure/scripts"
source ${HOMELAB}/vault.sh && vault

# HDD 1TB
umount -l /dev/sda1
mount -t ntfs3 -o defaults,noatime,uid=1000,gid=1000,dmask=000,fmask=000,iocharset=utf8 /dev/sda1 /mnt/disk2/

# SSD 128GB
umount -l /dev/sdb1
mount /dev/sdb1 /mnt/disk1

# Restart Docker
service docker restart

IPADDR="$(ifconfig eth0 | grep "inet " | awk '{print $2}')"
MSG="[$(date +'%Y%m%d %H:%M:%S')] - IPAddr:${IPADDR} LABRADOR has just come back to life."
TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh #| tee -ai /root/startup.log

# 1. Beri jeda waktu (delay) 30-60 detik.
# Ini SANGAT PENTING untuk memastikan daemon Docker, container Tailscale,
# dan interface ppp0 sudah benar-benar hidup sebelum perintah dieksekusi.
sleep 45

# 2. Paksa container Tailscale untuk mengiklankan rute (State override)
#docker exec tailscale tailscale up --advertise-routes=10.56.0.0/16,192.168.88.0/24,192.168.10.0/24 --accept-dns=false

# 3. Dobrak aturan Iptables agar selalu menempati posisi VIP (Nomor 1)
# Menghapus aturan lama (jika ada) agar tidak terjadi duplikasi setiap reboot
iptables -D FORWARD -i tailscale0 -o ppp0 -j ACCEPT 2>/dev/null
iptables -D FORWARD -i ppp0 -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null

# Memasukkan aturan ke posisi teratas
iptables -I FORWARD 1 -i tailscale0 -o ppp0 -j ACCEPT
iptables -I FORWARD 1 -i ppp0 -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "[$(date)] Tailscale & VPN Routing Override Executed" #>> /var/log/homelab_startup.log

#${HOMELAB}/auto-unseal.sh
