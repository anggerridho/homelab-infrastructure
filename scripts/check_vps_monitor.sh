#!/bin/bash

vps_monitor(){
INFLUX_URL="http://${DB_HOST}/write?db=${DB_NAME}" # Pastikan nama DB-nya db_rtrw

# Hit API VPS dengan timeout 10 detik agar script tidak hang
RESPONSE=$(curl -s -m 10 -H "X-API-Key: $API_KEY" "$API_URL")

# Ekstrak value "state" dari JSON tanpa perlu install jq
STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*' | grep -o '[^"]*$')

# Terjemahkan ke angka untuk database time-series
# 1 = ONLINE, 0 = OFFLINE atau Gagal Hit API
if [ "$STATE" == "ONLINE" ]; then
    STATUS_VAL=1
else
    STATUS_VAL=0
fi

# Tembak data ke InfluxDB STB (Measurement: remote_access, Tag: app=vps_api)
curl -s -i -XPOST "$INFLUX_URL" \
--data-binary "remote_access,app=vps_api status=${STATUS_VAL}" > /dev/null 2>&1
}