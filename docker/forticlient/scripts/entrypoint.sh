#!/bin/bash

# 1. Setup iptables Masquerade
iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE

# 2. Logika Dinamis Koneksi VPN
if [ "$REQUIRE_OTP" = "true" ]; then
    # Mode OTP Aktif
    if [ -z "$VPN_OTP" ]; then
        echo "Menunggu OTP... Update container dengan variabel VPN_OTP untuk memulai koneksi."
        # Tahan container agar tidak exit (idle mode)
        tail -f /dev/null
    fi
    echo "Menerima OTP, memulai openfortivpn dengan otentikasi OTP..."
    openfortivpn -c /etc/openfortivpn/config -p "$VPN_PASSWORD" -O "$VPN_OTP" &
    VPN_PID=$!
else
    # Mode Tanpa OTP
    echo "Mode Bypass OTP, memulai openfortivpn secara langsung..."
    openfortivpn -c /etc/openfortivpn/config -p "$VPN_PASSWORD" &
    VPN_PID=$!
fi

# 3. Tunggu ppp0 up
echo "Menunggu interface ppp0 up..."
while ! ip link show ppp0 > /dev/null 2>&1; do
    sleep 2
done
echo "Interface ppp0 aktif!"; sleep 15

# 4. Jalankan sinkronisasi Mikrotik
/scripts/enable_vpn_routes.sh

# 5. Tahan container dengan PID dari openfortivpn
wait $VPN_PID
