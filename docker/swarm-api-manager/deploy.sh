export $(grep -v '^#' .env | xargs) && docker stack deploy -c swarm-stack.yml homelab
