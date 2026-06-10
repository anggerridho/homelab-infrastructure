#!/bin/bash
HOMELAB="/root/homelab-infrastructure/scripts"
source ${HOMELAB}/vault.sh && vault

systemctl stop docker docker.socket containerd; sleep 3

${HOMELAB}/homelab-2/auto-mount.sh

# Restart Docker
if [ -d "/mnt/disk1/adguard" ]; then
  systemctl restart docker docker.socket containerd
fi

#IPADDR="$(ifconfig eth0 | grep "inet " | awk '{print $2}')"
IPADDR="192.168.10.4"
MSG="[$(date +'%Y%m%d %H:%M:%S')] - IPAddr:${IPADDR} LABRADOR has just come back to life."
TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh #| tee -ai /root/startup.log
