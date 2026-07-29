FROM debian:bookworm-slim

# Tambahkan tmux dan curl pada list apt-get
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    iproute2 \
    gawk \
    sshpass \
    openssh-client \
    openfortivpn \
    iptables \
    tmux \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
