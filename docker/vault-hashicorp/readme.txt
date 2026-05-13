mkdir -p /mnt/disk1/vault-storage
chown -R 100:1000 /mnt/disk1/vault-storage
docker config create vault-v1 /root/vault-config.hcl
