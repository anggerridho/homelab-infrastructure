#!/bin/bash
HOMELAB="/home/ubuntu/homelab-infrastructure/scripts"
source ${HOMELAB}/vault.sh && vault

# 1. Jalankan renew/cron
docker run --rm \
  -v /opt/adguard/acme:/acme.sh \
  -v /opt/adguard/ssl:/ssl \
  -e CF_Token="${CF_TOKEN}" \
  neilpang/acme.sh --cron --force --server zerossl

# 2. Salin sertifikat terbaru ke folder /opt/adguard/ssl/
docker run --rm \
  -v /opt/adguard/acme:/acme.sh \
  -v /opt/adguard/ssl:/ssl \
  neilpang/acme.sh --install-cert -d ytta.localhostaddr.biz.id --ecc \
  --key-file /ssl/yttacloudhostaddr.biz.id.key \
  --fullchain-file /ssl/fullchain.cer

# 3. Restart AdGuard untuk menerapkan sertifikat baru
docker restart adguard
