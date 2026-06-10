#!/bin/bash

CF_TOKEN="cfut_nHcxN2s0Bs6UJUtcDYZfuypPD2QLg8MJTB41WrQI23397f05"

docker run --rm -v /mnt/disk1/adguard/acme:/acme.sh -v /mnt/disk1/adguard/ssl:/ssl -e CF_Token="${CF_TOKEN}" neilpang/acme.sh --cron
docker service update --force adguard_adguardhome
