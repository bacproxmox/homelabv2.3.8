#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-nextcloud-data-storage"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
cat <<'INFO'
Bu repair mevcut Nextcloud data klasörünü VM104 local diskten TrueNAS tank NFS mount'una taşır.
Adımlar: maintenance mode, stop, rsync, compose mount düzeltme, start, occ check/files:scan.
INFO
read -r -p "Devam edilsin mi? [y/N]: " ans
[[ "$ans" =~ ^[Yy]$ ]] || exit 0
rssh 104 'sudo bash -s' <<'REMOTE'
set -Eeuo pipefail
apt update >/dev/null
apt install -y nfs-common rsync jq >/dev/null
NC_DIR=/opt/homelab/nextcloud
COMPOSE="$NC_DIR/docker-compose.yml"
cd "$NC_DIR"
NC_CONTAINER="$(docker ps --format '{{.Names}}' | grep -E '^(hb-nextcloud|nextcloud)$' | head -n1 || true)"
if [[ -n "$NC_CONTAINER" ]]; then docker exec -u www-data "$NC_CONTAINER" php occ maintenance:mode --on || true; fi
mkdir -p /mnt/nextcloud
if ! grep -qsE '^192\.168\.50\.101:/mnt/tank/nextcloud\s+/mnt/nextcloud\s+' /etc/fstab; then
  echo '192.168.50.101:/mnt/tank/nextcloud /mnt/nextcloud nfs defaults,_netdev,x-systemd.automount,nofail 0 0' >> /etc/fstab
fi
systemctl daemon-reload
mount /mnt/nextcloud 2>/dev/null || mount -a || true
mountpoint -q /mnt/nextcloud || { echo '❌ /mnt/nextcloud mount olmadı.'; exit 1; }
mkdir -p /mnt/nextcloud/data
if [[ -d "$NC_DIR/nextcloud/data" ]]; then
  echo '📦 Data rsync başlıyor...'
  rsync -aHAX --numeric-ids "$NC_DIR/nextcloud/data/" /mnt/nextcloud/data/
fi
cp "$COMPOSE" "$COMPOSE.bak.$(date +%Y%m%d-%H%M%S)"
python3 - <<'PYINNER'
from pathlib import Path
p=Path('/opt/homelab/nextcloud/docker-compose.yml')
text=p.read_text()
mount='      - /mnt/nextcloud/data:/var/www/html/data'
if mount not in text:
    text=text.replace('      - ./nextcloud:/var/www/html\n', '      - ./nextcloud:/var/www/html\n'+mount+'\n')
p.write_text(text)
PYINNER
docker compose up -d
sleep 10
NC_CONTAINER="$(docker ps --format '{{.Names}}' | grep -E '^(hb-nextcloud|nextcloud)$' | head -n1)"
docker exec -u www-data "$NC_CONTAINER" php occ maintenance:mode --off || true
docker exec -u www-data "$NC_CONTAINER" php occ files:scan --all || true
docker exec "$NC_CONTAINER" df -h /var/www/html/data
REMOTE
