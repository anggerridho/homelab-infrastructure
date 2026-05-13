#!/bin/bash
export HOMELAB="/root/homelab-infrastructure/scripts"

# Import fungsi-fungsi Anda
source ${HOMELAB}/vault.sh
source ${HOMELAB}/need-reboot-homelab-1.sh
source ${HOMELAB}/check_vpn_kantor.sh
source ${HOMELAB}/check_traffic_vpn.sh

export HOMELAB_SCRIPT="${HOMELAB}"

main() {
    vault
    need_reboot
    cek_vpn_kantor

    # Jalankan capture traffic hanya jika ppp0 aktif
    if [ -d "/sys/class/net/ppp0" ]; then
        cek_traffic_vpn
    fi
}

# Jalankan main dan catat log jika ada error
main #>> /var/log/homelab-minutely.log 2>&1