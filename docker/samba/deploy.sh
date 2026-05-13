export $(grep -v '^#' .env | xargs) && docker stack deploy -c samba-stack.yaml homelab
