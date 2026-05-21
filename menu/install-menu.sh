#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils/env-loader.sh"
source "$ROOT_DIR/utils/logging.sh"
start_log "install-menu"
run(){ echo; echo "▶️ $*"; if bash "$ROOT_DIR/$1"; then return 0; else local c=$?; echo "❌ Script hata verdi ($c): $1"; return "$c"; fi; }
confirm_truenas_ready(){ cat <<'CHECK'

TrueNAS API bootstrap için şu adımlar bitmiş olmalı:
  ✅ VM101 TrueNAS kurulmuş
  ✅ IP 192.168.50.101 olarak sabitlenmiş
  ✅ pool'lar oluşturulmuş: tank + private
  ✅ API key alınmış:
     midclt call api_key.create '{"name":"homelabv237","username":"truenas_admin"}'

CHECK
read -r -p "TrueNAS API bootstrap şimdi çalışsın mı? [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]]; }
while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.3.8 - Install Menu
=========================================
1) Bootstrap secrets/env
2) Create Proxmox users
3) Install TrueNAS VM 101
4) Bootstrap TrueNAS storage + install all VMs except TrueNAS
5) Prepare all Docker hosts
6) Install core services
7) Configure / repair basics
8) Phase 3 service configuration
9) Phase 4 Chia / SMTP
10) Maintenance menu
11) Additionals menu
12) Normalize Proxmox local storage
13) Exit
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) run bootstrap/00-bootstrap-secrets.sh ;;
    2) run bootstrap/01-create-proxmox-users.sh ;;
    3) run vm/101-truenas-vm-install.sh ;;
    4)
      if confirm_truenas_ready; then run services/truenas/01-truenas-api-bootstrap-storage.sh; else echo "ℹ️ TrueNAS API bootstrap atlandı."; fi
      run vm/102-docker-arr-vm-install.sh
      run vm/103-network-vm-install.sh
      run vm/104-nextcloud-vm-install.sh
      run vm/105-homeassistant-vm-install.sh
      run vm/106-media-ai-vm-install.sh
      run vm/107-chia-farmer-vm-install.sh ;;
    5) run services/common/01-prepare-all-docker-hosts.sh ;;
    6)
      run services/arr/01-arr-service-install.sh
      run services/seerr/01-seerr-service-install.sh
      run services/uptime-kuma/01-uptime-kuma-service-install.sh
      run services/nextcloud/01-nextcloud-service-install.sh
      run services/jellyfin/01-jellyfin-service-install.sh
      run services/immich/01-immich-service-install.sh
      run services/ollama/01-ollama-openwebui-service-install.sh
      run services/lidarr/01-lidarr-service-install.sh
      run services/homeassistant/01-homeassistant-service-install.sh
      run services/cloudflared/01-cloudflared-service-install.sh ;;
    7)
      run config/nextcloud/01-nextcloud-local-and-cloudflare-fix.sh
      run config/immich/01-immich-storage-verify.sh
      run services/cloudflared/02-generate-ingress-config-reference.sh ;;
    8) bash "$ROOT_DIR/menu/config-menu.sh" ;;
    9)
      run config/smtp/01-write-service-smtp-reference.sh
      run config/uptime-kuma/01-uptime-kuma-smtp-note.sh
      run services/chia/01-chia-farmer-service-install.sh ;;
    10) bash "$ROOT_DIR/menu/maintenance-menu.sh" ;;
    11) bash "$ROOT_DIR/menu/additionals-menu.sh" ;;
    12) run bootstrap/02-normalize-local-storage.sh ;;
    13) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
