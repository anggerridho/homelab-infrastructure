ID=$(docker ps | grep homelab_registry | grep 'homelab_registry\.' | awk '{print $1}')

docker exec -it ${ID} bin/registry garbage-collect /etc/docker/registry/config.yml

# Menghapus Nama Repositori yang Kosong di UI
# cd /mnt/disk1/registry/data/docker/registry/v2/repositories/
# rm -rf tailscale/
