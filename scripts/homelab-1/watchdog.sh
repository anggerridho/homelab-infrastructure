#!/bin/bash
export HOMELAB="/root/homelab-infrastructure/scripts"
export HOST_LAB="${HOMELAB}/homelab-1"

# Import fungsi-fungsi Anda
source ${HOMELAB}/vault.sh
source ${HOST_LAB}/selfhealing-container.sh
source ${HOST_LAB}/need-reboot.sh
source ${HOST_LAB}/check_vpn_kantor.sh
source ${HOST_LAB}/check_traffic_vpn.sh

main() {
    vault
    need_reboot
    cek_vpn_kantor

    # Jalankan capture traffic hanya jika ppp0 aktif
    if [ -d "/sys/class/net/ppp0" ]; then
        cek_traffic_vpn
    fi

    selfhealing_swarm
}

# Jalankan main dan catat log jika ada error
main #>> /var/log/homelab-minutely.log 2>&1
