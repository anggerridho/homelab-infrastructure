#!/bin/bash
export HOMELAB="/root/homelab-infrastructure/scripts"
export HOST_LAB="${HOMELAB}/homelab-2"

# Import fungsi-fungsi Anda
source ${HOMELAB}/housekeeping.sh
source ${HOST_LAB}/hardware_metrics.sh

main() {
    hardware_metrics
    housekeeping
}

# Jalankan main dan catat log jika ada error
main #>> /var/log/homelab-minutely.log 2>&1
