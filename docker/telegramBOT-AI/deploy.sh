docker build -t registry.localhostaddr.biz.id/bot-ai:latest .
echo "docker service rm homelab_bot-ai" | bash -v
echo "sleep 10" | bash -v
echo "docker stack deploy -c docker-compose.yaml homelab" | bash -v
echo "docker service logs homelab_bot-ai -f" | bash -v
