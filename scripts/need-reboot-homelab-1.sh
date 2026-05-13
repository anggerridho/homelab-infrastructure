#!/bin/bash

need_reboot(){
listDisk="disk1 disk2"
for loopDisk in ${listDisk}; do
  CHECK_DISK="$(ls -rltha /mnt/${loopDisk}/ 2>&-)"
  if [ $? != 0 ]; then
    MSG="[$(date +'%Y%m%d_%H:%M:%S')] - Reading directory '/mnt/${loopDisk}/': Input/output error"
    # telegram_send | tee -ai need-reboot.log
    TxT="$(echo "${MSG}")" ${HOMELAB}/alertelegram.sh #| tee -ai need-reboot.log
    dmesg -T > dmesg.log
    /usr/sbin/reboot
  else
    touch /tmp/healthy_system.temp
  fi
done
}
