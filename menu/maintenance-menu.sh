#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"
start_log "maintenance-menu"
run() { echo; echo "▶️ $*"; bash "$ROOT_DIR/$1"; }
while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.3.8 - Maintenance Menu
=========================================
1) Full health check
2) Full service audit
3) Collect support bundle
4) Docker cleanup on all Docker VMs
5) Fix Docker permissions
6) Repair NFS mounts
7) Recreate Cloudflared
8) Reinstall selected VM
9) VM resource audit
10) Resize VM106/VM107 resources
11) Bootstrap TrueNAS storage/users/NFS/SMB
12) Test SMTP
13) Repair Nextcloud data storage to TrueNAS tank
14) Repair GPU passthrough / drivers
15) Rollback everything except TrueNAS
16) Rollback / Checkpoints
17) Show state
18) Back
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) run maintenance/health/full-health-check.sh ;;
    2) run maintenance/health/full-service-audit.sh ;;
    3) run maintenance/logs/collect-support-bundle.sh ;;
    4) run maintenance/cleanup/docker-cleanup.sh ;;
    5) run maintenance/repair/fix-docker-permissions.sh ;;
    6) run maintenance/repair/repair-nfs-mounts.sh ;;
    7) run maintenance/repair/recreate-cloudflared.sh ;;
    8) run maintenance/vm/reinstall-selected-vm.sh ;;
    9) run maintenance/health/vm-resource-audit.sh ;;
    10) run maintenance/repair/vm/resize-vm106-vm107.sh ;;
    11) run services/truenas/01-truenas-api-bootstrap-storage.sh ;;
    12)
      read -r -p "Profile [nextcloud|immich|seerr|uptime-kuma|truenas|all]: " profile
      bash "$ROOT_DIR/maintenance/alerts/test-smtp-send.sh" "$profile"
      ;;
    13) run maintenance/repair/repair-nextcloud-data-storage.sh ;;
    14) run maintenance/repair/repair-gpu-passthrough.sh ;;
    15) run maintenance/reset/rollback-everything-except-truenas.sh ;;
    16) run maintenance/checkpoints/rollback-checkpoints-menu.sh ;;
    17) run maintenance/state/show-state.sh ;;
    18) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
