#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "uptime-kuma-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
VM=103; WORK=/tmp/hv23-uptime-kuma; rm -rf "$WORK"; mkdir -p "$WORK"
source "$ROOT_DIR/utils/env-write.sh"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
} > "$WORK/.env"
cat > "$WORK/docker-compose.yml" <<'COMPOSE'
networks:
  homelab:
    external: true
services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: hb-uptime-kuma
    restart: unless-stopped
    networks: [homelab]
    environment:
      - TZ=${TZ}
    volumes:
      - ./data:/app/data
    ports:
      - "3001:3001"
COMPOSE
cat > "$WORK/install.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /opt/homelab/uptime-kuma/data
cp /tmp/hv23-uptime-kuma/docker-compose.yml /opt/homelab/uptime-kuma/docker-compose.yml
cp /tmp/hv23-uptime-kuma/.env /opt/homelab/uptime-kuma/.env
cd /opt/homelab/uptime-kuma
docker network create homelab >/dev/null 2>&1 || true
docker compose pull
docker compose up -d
REMOTE
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv23-uptime-kuma/install.sh"
