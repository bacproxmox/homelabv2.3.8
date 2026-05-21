#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "cloudflared-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

VM=103
DOMAIN="${DOMAIN:-bacmastercloud.com}"
TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME:-homelab-v238}"
WORK="/tmp/hv238-cloudflared"
rm -rf "$WORK"; mkdir -p "$WORK"

cp "$ROOT_DIR/services/cloudflared/routes.env" "$WORK/routes.env"
cp "$ROOT_DIR/services/cloudflared/api-routes.env" "$WORK/api-routes.env"

cat > "$WORK/install-cloudflared-native.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
set +H

DOMAIN="${DOMAIN:-bacmastercloud.com}"
TUNNEL_NAME="${TUNNEL_NAME:-homelab-v238}"
ROUTES_FILE="/tmp/hv238-cloudflared/routes.env"
API_ROUTES_FILE="/tmp/hv238-cloudflared/api-routes.env"

export DEBIAN_FRONTEND=noninteractive

say() { echo -e "$*"; }

install_packages() {
  say "📦 Paketler kontrol ediliyor..."
  apt update >/dev/null
  apt install -y curl jq python3 ca-certificates >/dev/null

  if ! command -v cloudflared >/dev/null 2>&1; then
    say "📥 cloudflared kuruluyor..."
    curl -fsSL -o /tmp/cloudflared.deb \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cloudflared.deb
  fi
}

ensure_login_cert() {
  mkdir -p /root/.cloudflared /etc/cloudflared
  chmod 700 /root/.cloudflared /etc/cloudflared || true

  local root_cert="/root/.cloudflared/cert.pem"
  local home_cert="${HOME}/.cloudflared/cert.pem"

  if [[ ! -f "$root_cert" && ! -f "$home_cert" ]]; then
    cat <<LOGIN

🔑 Cloudflare login gerekiyor.
Açılan URL'yi Windows tarayıcıda açıp ${DOMAIN} domainini authorize et.
Token istenmez; browser login + cert.pem yöntemi kullanılır.

LOGIN
    cloudflared tunnel login
  fi

  if [[ -f "$home_cert" && ! -f "$root_cert" ]]; then
    cp "$home_cert" "$root_cert"
  fi

  if [[ ! -f "$root_cert" ]]; then
    say "❌ Cloudflare cert.pem bulunamadı: $root_cert"
    say "Tekrar dene: cloudflared tunnel login"
    exit 1
  fi
}

get_tunnel_id_by_name() {
  local name="$1"
  cloudflared tunnel list --output json 2>/dev/null \
    | jq -r --arg name "$name" '.[] | select(.name==$name) | .id' \
    | head -n1 || true
}

copy_credentials_if_present() {
  local id="$1"
  local src1="/root/.cloudflared/${id}.json"
  local src2="${HOME}/.cloudflared/${id}.json"
  local dst="/etc/cloudflared/${id}.json"

  if [[ -f "$src1" ]]; then
    cp "$src1" "$dst"
  elif [[ -f "$src2" ]]; then
    cp "$src2" "$dst"
  fi

  [[ -f "$dst" ]]
}

create_tunnel() {
  local name="$1"
  say "🕳️ Tunnel oluşturuluyor: $name"
  cloudflared tunnel create "$name"
  get_tunnel_id_by_name "$name"
}

ensure_tunnel_with_credentials() {
  say
  say "🕳️ Tunnel kontrol/oluşturma..."

  local existing_id
  existing_id="$(get_tunnel_id_by_name "$TUNNEL_NAME")"

  if [[ -z "$existing_id" || "$existing_id" == "null" ]]; then
    TUNNEL_ID="$(create_tunnel "$TUNNEL_NAME")"
    [[ -n "$TUNNEL_ID" && "$TUNNEL_ID" != "null" ]] || { say "❌ Tunnel ID bulunamadı."; exit 1; }
    copy_credentials_if_present "$TUNNEL_ID" || { say "❌ Yeni tunnel credentials JSON oluşmadı."; ls -la /root/.cloudflared /etc/cloudflared || true; exit 1; }
    return 0
  fi

  say "✅ Remote tunnel bulundu: $TUNNEL_NAME / $existing_id"

  if copy_credentials_if_present "$existing_id"; then
    TUNNEL_ID="$existing_id"
    return 0
  fi

  cat <<WARN
⚠️ Remote tunnel var ama local credentials JSON yok:
  Tunnel: $TUNNEL_NAME / $existing_id
  Beklenen: /etc/cloudflared/${existing_id}.json

Bu genelde fresh install/rollback sonrası olur. cloudflared tunnel login sadece cert.pem oluşturur;
mevcut remote tunnel'ın JSON credentials dosyasını geri üretmez.
WARN

  local choice=""
  if [[ -t 0 ]]; then
    echo
    echo "Ne yapılsın?"
    echo "  1) Yeni versioned tunnel oluştur ve DNS route'ları buna bağla (önerilen)"
    echo "  2) Eski tunnel'ı silip aynı isimle yeniden oluştur"
    echo "  3) İptal et; credentials JSON dosyasını manuel import edeceğim"
    read -r -p "Seçim [1]: " choice
  fi
  choice="${choice:-1}"

  case "$choice" in
    2)
      say "⚠️ Eski tunnel silinecek: $TUNNEL_NAME / $existing_id"
      if [[ -t 0 ]]; then
        read -r -p "Devam için DELETE yaz: " confirm
        [[ "$confirm" == "DELETE" ]] || { say "İptal edildi."; exit 1; }
      fi
      cloudflared tunnel delete -f "$existing_id" || true
      TUNNEL_ID="$(create_tunnel "$TUNNEL_NAME")"
      ;;
    3)
      say "İptal edildi. Credentials dosyasını import ettikten sonra scripti tekrar çalıştır."
      exit 1
      ;;
    *)
      local base="${TUNNEL_NAME%-*}"
      [[ "$base" == "$TUNNEL_NAME" ]] && base="$TUNNEL_NAME"
      TUNNEL_NAME="${base}-$(date +%Y%m%d%H%M%S)"
      say "🆕 Yeni tunnel adı: $TUNNEL_NAME"
      TUNNEL_ID="$(create_tunnel "$TUNNEL_NAME")"
      ;;
  esac

  [[ -n "$TUNNEL_ID" && "$TUNNEL_ID" != "null" ]] || { say "❌ Tunnel ID bulunamadı."; exit 1; }
  copy_credentials_if_present "$TUNNEL_ID" || { say "❌ Credentials dosyası bulunamadı: /etc/cloudflared/${TUNNEL_ID}.json"; ls -la /root/.cloudflared /etc/cloudflared || true; exit 1; }
}

write_config() {
  CONFIG="/etc/cloudflared/config.yml"
  [[ -f "$CONFIG" ]] && cp "$CONFIG" "${CONFIG}.bak.$(date +%Y%m%d-%H%M%S)" || true

  write_ingress_entry() {
    local name="$1" service="$2" host="$3"
    [[ -z "$host" || "$host" =~ ^# ]] && return 0
    cat >> "$CONFIG" <<YAML
  - hostname: ${host}
    service: ${service}
YAML
    if [[ "$service" == https://192.168.50.100:8006* ]]; then
      cat >> "$CONFIG" <<'YAML'
    originRequest:
      noTLSVerify: true
YAML
    fi
  }

  say
  say "📝 config.yml yazılıyor: $CONFIG"
  cat > "$CONFIG" <<YAML
# Generated by Homelab v2.3.8 hotfix
tunnel: ${TUNNEL_ID}
credentials-file: /etc/cloudflared/${TUNNEL_ID}.json

protocol: quic
loglevel: info

ingress:
YAML

  while IFS='|' read -r name service host; do
    [[ -z "${name:-}" || "$name" =~ ^# ]] && continue
    write_ingress_entry "$name" "$service" "$host"
  done < "$ROUTES_FILE"

  while IFS='|' read -r name service host; do
    [[ -z "${name:-}" || "$name" =~ ^# ]] && continue
    write_ingress_entry "$name" "$service" "$host"
  done < "$API_ROUTES_FILE"

  cat >> "$CONFIG" <<'YAML'
  - service: http_status:404
YAML

  say
  say "🔎 Ingress validate..."
  cloudflared tunnel ingress validate --config "$CONFIG"
}

route_dns_records() {
  say
  say "🌐 DNS route kayıtları oluşturuluyor/güncelleniyor..."
  route_dns() {
    local host="$1"
    [[ -z "$host" || "$host" =~ ^# ]] && return 0
    say "➡️ $host"
    cloudflared tunnel route dns "$TUNNEL_NAME" "$host" || true
  }

  while IFS='|' read -r name service host; do
    [[ -z "${name:-}" || "$name" =~ ^# ]] && continue
    route_dns "$host"
  done < "$ROUTES_FILE"

  while IFS='|' read -r name service host; do
    [[ -z "${name:-}" || "$name" =~ ^# ]] && continue
    route_dns "$host"
  done < "$API_ROUTES_FILE"
}

install_service() {
  say
  say "🔧 cloudflared servisi kuruluyor/güncelleniyor..."
  if systemctl list-unit-files | grep -q '^cloudflared.service'; then
    systemctl restart cloudflared
  else
    cloudflared service install || true
    systemctl enable --now cloudflared || true
  fi

  sleep 4

  say
  say "📋 cloudflared status:"
  systemctl --no-pager --full status cloudflared | sed -n '1,22p' || true
}

echo
echo "🌩️ Homelab v2.3.8 hotfix - Cloudflared interactive login + resilient tunnel credentials"
echo "Tunnel : $TUNNEL_NAME"
echo "Domain : $DOMAIN"
echo

install_packages
ensure_login_cert
ensure_tunnel_with_credentials
write_config
route_dns_records
install_service

echo
echo "✅ Cloudflared tamamlandı."
echo "Config: /etc/cloudflared/config.yml"
echo "Tunnel: $TUNNEL_NAME / $TUNNEL_ID"
REMOTE

chmod +x "$WORK/install-cloudflared-native.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo DOMAIN='$DOMAIN' TUNNEL_NAME='$TUNNEL_NAME' bash /tmp/hv238-cloudflared/install-cloudflared-native.sh"
