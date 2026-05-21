#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "nextcloud-local-cloudflare-fix"
source "$ROOT_DIR/utils/remote.sh"
TMP="$(mktemp -d)"
cat > "$TMP/nextcloud-local-fix.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/nextcloud

show_nc_logs(){
  docker ps -a --filter name=hb-nextcloud || true
  docker logs hb-nextcloud --tail=120 || true
}

wait_nextcloud_ready(){
  echo "⏳ Nextcloud readiness kontrolü..."
  for i in $(seq 1 120); do
    state="$(docker inspect -f '{{.State.Status}} {{.State.Restarting}}' hb-nextcloud 2>/dev/null || true)"
    if echo "$state" | grep -q '^running false'; then
      if docker exec hb-nextcloud test -f /var/www/html/version.php >/dev/null 2>&1; then
        if docker exec hb-nextcloud php -v >/dev/null 2>&1; then
          echo "✅ hb-nextcloud running ve version.php mevcut."
          return 0
        fi
      fi
    fi
    if echo "$state" | grep -q 'restarting'; then
      echo "⚠️ hb-nextcloud restarting; bekleniyor... ($i/120)"
    fi
    sleep 3
  done
  echo "❌ Nextcloud hazır değil veya /var/www/html/version.php eksik."
  show_nc_logs
  return 1
}

occ(){ docker exec -u www-data hb-nextcloud php occ "$@"; }

wait_nextcloud_ready

if ! docker exec hb-nextcloud test -d /var/www/html/custom_apps >/dev/null 2>&1; then
  echo "❌ /var/www/html/custom_apps yok. Compose/volume mimarisini kontrol et."
  show_nc_logs
  exit 1
fi

echo "🔧 Nextcloud trusted domains / overwrite ayarları..."
occ config:system:set trusted_domains 0 --value='192.168.50.104' || true
occ config:system:set trusted_domains 1 --value='cloud.bacmastercloud.com' || true
occ config:system:set trusted_domains 2 --value='cloud-api.bacmastercloud.com' || true
occ config:system:delete overwritehost || true
occ config:system:delete overwriteprotocol || true
occ config:system:set overwrite.cli.url --value='http://192.168.50.104:8080' || true
occ maintenance:repair || true

echo "📦 Nextcloud data mount:"
docker exec hb-nextcloud df -h /var/www/html/data || true
REMOTE
chmod +x "$TMP/nextcloud-local-fix.sh"
rscp "$TMP/nextcloud-local-fix.sh" 104 /tmp/hv238-nextcloud-local-fix.sh
rssh 104 "sudo bash /tmp/hv238-nextcloud-local-fix.sh"
rm -rf "$TMP"
