#!/bin/bash
PATH=/usr/bin

HOMELAB="/root/homelab-infrastructure/scripts"
source ${HOMELAB}/vault.sh && vault

HOST_LAB="${HOMELAB}/homelab-2"

# Flashdisk 32GB
umount -l /dev/sda1
mount /dev/sda1 /mnt/disk1

# Restart Docker
service docker restart

IPADDR="$(ifconfig eth0 | grep "inet " | awk '{print $2}')"
MSG="[$(date +'%Y%m%d %H:%M:%S')] - IPAddr:${IPADDR} LABRADOR has just come back to life."
TxT="$(echo "${MSG}")" ${HOST_LAB}/alertelegram.sh #| tee -ai /root/startup.log
