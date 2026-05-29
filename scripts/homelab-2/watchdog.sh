#!/bin/bash
export HOMELAB="/root/homelab-infrastructure/scripts"
export HOST_LAB="${HOMELAB}/homelab-2"

# Import fungsi-fungsi Anda
source ${HOMELAB}/vault.sh
source ${HOST_LAB}/hardware_metrics.sh
source ${HOST_LAB}/need-reboot.sh
source ${HOMELAB}/housekeeping.sh
source ${HOMELAB}/check_remote.sh

main() {
    vault
    hardware_metrics
    need_reboot
    remote
    housekeeping
}

# Jalankan main dan catat log jika ada error
main #>> /var/log/homelab-minutely.log 2>&1
