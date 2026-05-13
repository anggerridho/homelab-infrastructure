#!/bin/bash

# ==========================================
# GRAFANA AUTO-BACKUP & GITOPS SCRIPT
# ==========================================

# Konfigurasi
HOMELAB="/root/homelab-infrastructure"
source ${HOMELAB}/scripts/vault.sh && vault
DATE_NOW=$(date +'%Y-%m-%d_%H:%M:%S')

echo "[$DATE_NOW] Memulai backup Grafana Dashboards..."

# 1. Ambil semua UID Dashboard yang ada di Grafana
DASHBOARD_UIDS=$(curl -s "$GRAFANA_URL/api/search?type=dash-db" | jq -r '.[] | .uid')

if [ -z "$DASHBOARD_UIDS" ]; then
    echo "Tidak ada dashboard ditemukan atau Grafana tidak merespons."
    exit 1
fi

# 2. Loop setiap DASH_UID
for DASH_UID in $DASHBOARD_UIDS; do
    RAW_JSON=$(curl -s "$GRAFANA_URL/api/dashboards/uid/$DASH_UID")
    
    # Perbaikan: Hapus karakter ilegal termasuk slash (/)
    DASH_TITLE=$(echo "$RAW_JSON" | jq -r '.dashboard.title' | sed 's/[^a-zA-Z0-9._-]/_/g')
    
    # Simpan ke folder provisioning
    echo "$RAW_JSON" | jq '.dashboard | .id = null' > "$PROVISION_DIR/${DASH_TITLE}.json"
    
    echo "  -> Berhasil membackup: ${DASH_TITLE}.json"
done

# 3. Sinkronisasi ke GitHub
echo "Sinkronisasi ke GitHub..."
cd "$GIT_REPO_DIR" || exit

# Salin file dari /mnt/disk3 ke dalam folder repo sebelum Git operasional
# Misal repo Anda punya folder khusus bernama 'grafana-dashboards'
mkdir -p "$GIT_REPO_DIR/grafana-dashboards"
cp "$PROVISION_DIR"/*.json "$GIT_REPO_DIR/grafana-dashboards/"

# Jalankan Git dari dalam folder repo
if [[ -n $(git status -s) ]]; then
    #git add .
    #git commit -m "chore: auto-backup grafana dashboards [$DATE_NOW]"
    #git push origin main
    echo "✅ Backup berhasil, siap kapanpun di-push ke GitHub."
else
    echo "✅ Tidak ada perubahan dashboard. Skip Git Push."
fi
