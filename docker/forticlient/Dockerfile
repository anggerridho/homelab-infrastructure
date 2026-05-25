FROM debian:bookworm-slim

# Update repository dan install dependensi
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    iproute2 \
    gawk \
    sshpass \
    openssh-client \
    openfortivpn \
    iptables \
    && rm -rf /var/lib/apt/lists/* # Membersihkan cache apt agar image tetap kecil

# Set direktori kerja
WORKDIR /app

# Copy skrip ke dalam image
COPY scripts/ /scripts/

# Beri akses eksekusi
RUN chmod +x /scripts/*.sh

# Jadikan entrypoint.sh sebagai perintah utama saat container start
ENTRYPOINT ["/scripts/entrypoint.sh"]
