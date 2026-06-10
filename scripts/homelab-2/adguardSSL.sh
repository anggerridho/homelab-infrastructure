#!/bin/bash
HOMELAB="/root/homelab-infrastructure/scripts"
source ${HOMELAB}/vault.sh && vault

docker run --rm -v /mnt/disk1/adguard/acme:/acme.sh -v /mnt/disk1/adguard/ssl:/ssl -e CF_Token="${CF_TOKEN}" neilpang/acme.sh --cron
docker service update --force homelab_adguardhome
