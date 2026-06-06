#!/bin/bash

systemctl stop docker docker.socket containerd; sleep 3

# SSD 500GB
umount -l /mnt/disk1

# HDD 1TB
umount -l /mnt/disk2

/usr/sbin/reboot
