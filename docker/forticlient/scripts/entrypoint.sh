#!/bin/bash

iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE

# Fungsi Helper Notifikasi langsung ke Telegram via Alert-Service
send_alert() {
    curl -s -X POST "http://127.0.0.1:3001/api/alert?api_key=$API_KEY" \
         -H "Content-Type: application/json" \
         -d "{\"text\":\"$1\",\"type\":\"$2\"}" || true
}

if [ "$REQUIRE_OTP" = "true" ]; then
    send_alert "⏳ FortiClient berjalan.\nMenunggu input OTP dalam 1 menit!\n\nKetik di Telegram:\n/otp <kode>\nAtau Postman:\n/api/forticlient/otp?code=<kode>" "INFO"

    # Jalankan openfortivpn di background menggunakan sesi tmux
    tmux new-session -d -s vpn_session "openfortivpn -c /etc/openfortivpn/config -p '$VPN_PASSWORD'"
    ELAPSED=0
    # Tunggu maksimal 60 detik (30 x 2 detik)
    while ! ip link show ppp0 > /dev/null 2>&1; do
        sleep 2
        ELAPSED=$((ELAPSED + 2))

        if [ $ELAPSED -ge 60 ]; then
            send_alert "❌ Waktu habis (60 Detik). OTP tidak diterima.\nMembatalkan koneksi VPN." "ERROR"
            tmux kill-session -t vpn_session 2>/dev/null
            exit 1
        fi
    done

    send_alert "✅ OTP Berhasil! Interface ppp0 aktif." "INFO"
    sleep 5
    /scripts/enable_vpn_routes.sh

    # Tahan container agar tidak exit
    sleep infinity
else
    # Jika REQUIRE_OTP=false, berjalan normal tanpa notifikasi tunggu
    echo "Mode Bypass OTP aktif, memulai openfortivpn secara langsung..."
    openfortivpn -c /etc/openfortivpn/config -p "$VPN_PASSWORD" &
    VPN_PID=$!

    while ! ip link show ppp0 > /dev/null 2>&1; do sleep 2; done
    echo "Interface ppp0 aktif!"; sleep 15

    /scripts/enable_vpn_routes.sh
    wait $VPN_PID
fi
