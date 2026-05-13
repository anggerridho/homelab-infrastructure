#!/bin/bash

housekeeping(){
for x in {1..3}; do echo "echo ${x} >  /proc/sys/vm/drop_caches" | bash -v; done

if [ "$(date +%H:%M)" == "07:00" ]; then
docker system prune -f
apt-get clean
apt-get autoremove
rm -rf /var/cache/apt/archives/*
rm -rf /var/lib/apt/lists/*
journalctl --vacuum-size=50M
rm -f /tmp/telegram.log
fi
}
