#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"
start_log "reinstall-selected-vm"
require_root
cat <<'MENU'
Reinstall selected VM
---------------------
101 TrueNAS
102 Docker ARR
103 Network / Cloudflared / Uptime Kuma
104 Nextcloud
105 Home Assistant
106 Media + AI
107 Chia Farmer
MENU
read -r -p "VMID: " vmid
case "$vmid" in
  101) bash "$ROOT_DIR/vm/101-truenas-vm-install.sh" ;;
  102) bash "$ROOT_DIR/vm/102-docker-arr-vm-install.sh" ;;
  103) bash "$ROOT_DIR/vm/103-network-vm-install.sh" ;;
  104) bash "$ROOT_DIR/vm/104-nextcloud-vm-install.sh" ;;
  105) bash "$ROOT_DIR/vm/105-homeassistant-vm-install.sh" ;;
  106) bash "$ROOT_DIR/vm/106-media-ai-vm-install.sh" ;;
  107) bash "$ROOT_DIR/vm/107-chia-farmer-vm-install.sh" ;;
  *) echo "❌ Geçersiz VMID: $vmid"; exit 1 ;;
esac
