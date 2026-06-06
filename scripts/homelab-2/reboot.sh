#!/bin/bash

systemctl stop docker docker.socket containerd; sleep 3

umount -l /mnt/disk1

/usr/sbin/reboot
