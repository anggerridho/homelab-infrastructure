#!/bin/bash

get_data(){
# A. Bangun perintah Ping CCTV secara dinamis dari file
LIST_CLIENT="$(cat ${HOMELAB}/listCheck.conf | grep -Evi 'E1|E2' | grep -vi '#')"
CCTV_CMD=""
for LOOP_CLIENT in ${LIST_CLIENT}; do
    HSTNAME="$(echo "${LOOP_CLIENT}" | awk -F'|' '{print $1}')"
    IPADDR="$(echo "${LOOP_CLIENT}" | awk -F'|' '{print $2}')"
    # Mengembalikan 1 jika UP, 0 jika DOWN
    CCTV_CMD+=":local p [/ping $IPADDR count=1]; :put (\"CCTV|$HSTNAME|$IPADDR|\$p\"); "
done

MEGA_CMD=":global statusIndiHome; :global statusXL; "
MEGA_CMD+=":put (\"ISP_FAILOVER|\" . \$statusIndiHome . \"|\" . \$statusXL); "
MEGA_CMD+="$CCTV_CMD"
MEGA_CMD+=":foreach i in=[/queue simple find] do={ :put (\"QUEUE|\" . [/queue simple get \$i name] . \"|\" . [/queue simple get \$i rate]) }; "
# Ambil trafik seluruh interface aktif agar fungsi distribution & hectic bisa memfilter namanya nanti
MEGA_CMD+=":foreach i in=[/interface find running=yes] do={ :do { :local rx ([/interface monitor-traffic \$i once as-value]->\"rx-bits-per-second\"); :local tx ([/interface monitor-traffic \$i once as-value]->\"tx-bits-per-second\"); :put (\"TRAFFIC|\" . [/interface get \$i name] . \"|\$rx|\$tx\"); } on-error={} }; "
# Khusus RTRW Net / Hotspot Active, beri pembatas karena outputnya multi-baris
MEGA_CMD+=":put \"---RTRW_START---\"; /ip hotspot active print terse; :put \"---RTRW_END---\"; "
# CPU/Mem-Load Mikrotik
MEGA_CMD+=":put (\"RESOURCE|\" . [/system resource get cpu-load] . \"|\" . [/system resource get free-memory] . \"|\" . [/system resource get total-memory]); "

# EKSEKUSI SSH DENGAN RETRY & REDIS LOCKING
MAX_RETRIES=3
ATTEMPT=1
IS_SUCCESS=0
RAW_DATA=""

while [ $ATTEMPT -le $MAX_RETRIES ]; do
    # Eksekusi 1x SSH
    RAW_DATA=$(${HOMELAB}/terminate.sh -t 10 sshpass -p "$(echo ${MIKROTIK_PSSWD} | base64 -d)" ssh -q -oStrictHostKeyChecking=no ${MIKROTIK_HOST} "$MEGA_CMD" | tr -d '\r')

    # Validasi output: Jika berhasil harusnya ada kata ISP_FAILOVER
    if [ -n "$RAW_DATA" ] && echo "$RAW_DATA" | grep -q "ISP_FAILOVER"; then
        IS_SUCCESS=1
        break
    fi
    sleep 5
    ATTEMPT=$((ATTEMPT + 1))
done

# --- CEK STATE REDIS ---
LAST_SSH_STATE=$(redis-cli -h ${REDIS_HOST} GET $REDIS_KEY_SSH)

if [ "$IS_SUCCESS" -eq 0 ]; then
    # Jika gagal total
    if [ "$LAST_SSH_STATE" != "0" ]; then
        MSG="🚨 *CRITICAL ERROR*%0A%0AStatus: *MikroTik SSH Unreachable*%0AInfo: Gagal mengambil Bulk Data setelah $MAX_RETRIESx percobaan. Monitoring dihentikan sementara."
        TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
        redis-cli -h ${REDIS_HOST} SET $REDIS_KEY_SSH "0" > /dev/null 2>&1
    fi
    # Berhenti disini agar tidak error saat membedah data kosong
    exit 1 
else
    # Jika berhasil dan sebelumnya mati
    if [ "$LAST_SSH_STATE" == "0" ]; then
        MSG="✅ *RECOVERY*%0A%0AStatus: *MikroTik SSH Connected*%0AInfo: Koneksi pulih, Monitoring berjalan kembali."
        TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh
    fi
    # Kunci state aktif
    redis-cli -h ${REDIS_HOST} SET $REDIS_KEY_SSH "1" > /dev/null 2>&1
fi
}