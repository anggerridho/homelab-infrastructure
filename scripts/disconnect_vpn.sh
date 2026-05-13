#!/bin/bash
HOMELAB="/root/homelab-infrastructure/scripts"
source ${HOMELAB}/vault.sh && vault

# 1. Matikan VPN
/usr/bin/pkill openfortivpn
/usr/bin/pkill screen

# 2. Hapus semua rute yang memiliki awalan comment "ALTO"
# Ini jauh lebih aman dan bersih daripada menghapus satu per satu
${HOMELAB}/terminate.sh -t 10 sshpass -p "$(echo ${MIKROTIK_PSSWD} | base64 -d)" ssh -q -oStrictHostKeyChecking=no ${MIKROTIK_HOST} '/ip route remove [find comment~"ALTO"]'

echo "[$(date)] VPN Offline dan rute ALTO telah dibersihkan dari MikroTik." >> /var/log/vpn_status.log

${HOMELAB}/check_vpn_kantor.sh
