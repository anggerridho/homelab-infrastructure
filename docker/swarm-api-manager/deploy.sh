# ./build.sh

echo "docker service rm homelab_alert-service" | bash -v
echo "sleep 5" | bash -v

echo "docker service rm homelab_api-manager" | bash -v
echo "sleep 5" | bash -v

export $(grep -v '^#' .env | xargs) && docker stack deploy -c swarm-stack.yml homelab
