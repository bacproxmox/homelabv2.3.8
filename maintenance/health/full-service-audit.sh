#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "full-service-audit"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

check_vm(){
  local vm="$1" name="$2"
  echo
  echo "================ $vm $name ================"
  if rssh "$vm" "hostname && uptime && ip -br a" >/dev/null; then
    rssh "$vm" "hostname; uptime; echo; docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true; echo; df -h | grep -E '/mnt|Filesystem' || true"
  else
    echo "❌ VM $vm SSH erişilemiyor"
  fi
}
check_vm 102 "docker-arr"
check_vm 103 "docker-network"
check_vm 104 "nextcloud"
check_vm 105 "homeassistant"
check_vm 106 "media-ai"
check_vm 107 "chia-farmer"

echo
echo "================ LAN PORT CHECK ================"
for item in \
  "192.168.50.102 8080 qbittorrent" \
  "192.168.50.102 8989 sonarr" \
  "192.168.50.102 7878 radarr" \
  "192.168.50.102 9696 prowlarr" \
  "192.168.50.102 6767 bazarr" \
  "192.168.50.102 5055 seerr" \
  "192.168.50.103 3001 uptime-kuma" \
  "192.168.50.104 8080 nextcloud" \
  "192.168.50.106 8096 jellyfin" \
  "192.168.50.106 2283 immich" \
  "192.168.50.106 3000 openwebui" \
  "192.168.50.105 8123 homeassistant" \
  "192.168.50.106 8686 lidarr"; do
  set -- $item
  host="$1"; port="$2"; name="$3"
  if timeout 3 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
    echo "✅ $name $host:$port açık"
  else
    echo "❌ $name $host:$port kapalı/erişilemedi"
  fi
done
