export $(grep -v '^#' .env | xargs) && docker stack deploy -c tailscale-stack.yaml homelab
