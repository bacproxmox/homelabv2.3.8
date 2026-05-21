#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "nextcloud-smtp-google-users"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"

load_env_file "$SECRETS_DIR/smtp.env"
load_env_file "$SECRETS_DIR/google.env"

TMP="$(mktemp -d)"
{
  write_env_header
  write_env_line SMTP_HOST "${SMTP_HOST:-smtp.zoho.com}"
  write_env_line SMTP_PORT "${SMTP_PORT:-587}"
  write_env_line SMTP_SECURE "${SMTP_SECURE:-tls}"
  write_env_line SMTP_FROM_LOCAL "admin"
  write_env_line SMTP_DOMAIN "bacmastercloud.com"
  write_env_line NEXTCLOUD_SMTP_USER "admin@bacmastercloud.com"
  write_env_line NEXTCLOUD_SMTP_PASS "${ZOHO_NEXTCLOUD_APP_PASS:-}"
  write_env_line GOOGLE_CLIENT_ID "${GOOGLE_CLIENT_ID:-}"
  write_env_line GOOGLE_CLIENT_SECRET "${GOOGLE_CLIENT_SECRET:-}"
  write_env_line BACMASTER_USER "${BACMASTER_USER:-bacmaster}"
  write_env_line BACMASTER_PASS "${BACMASTER_PASS:-}"
} > "$TMP/nextcloud-post.env"

cat > "$TMP/nextcloud-post-config.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/nextcloud
occ(){ docker exec -u www-data hb-nextcloud php occ "$@"; }

for _ in $(seq 1 80); do docker exec hb-nextcloud php -v >/dev/null 2>&1 && break; sleep 3; done

# Trusted domains: local IP + Cloudflare domains, without forcing local redirect.
occ config:system:set trusted_domains 0 --value="192.168.50.104" || true
occ config:system:set trusted_domains 1 --value="cloud.bacmastercloud.com" || true
occ config:system:set trusted_domains 2 --value="cloud-api.bacmastercloud.com" || true
occ config:system:set overwrite.cli.url --value="http://192.168.50.104:8080" || true
occ config:system:delete overwritehost || true
occ config:system:delete overwriteprotocol || true

if [[ -n "${NEXTCLOUD_SMTP_PASS:-}" ]]; then
  occ config:system:set mail_smtpmode --value="smtp"
  occ config:system:set mail_smtphost --value="${SMTP_HOST:-smtp.zoho.com}"
  occ config:system:set mail_smtpport --value="${SMTP_PORT:-587}"
  occ config:system:set mail_smtpsecure --value="${SMTP_SECURE:-tls}"
  occ config:system:set mail_smtpauth --value="1"
  occ config:system:set mail_smtpname --value="${NEXTCLOUD_SMTP_USER:-admin@bacmastercloud.com}"
  occ config:system:set mail_smtppassword --value="${NEXTCLOUD_SMTP_PASS}"
  occ config:system:set mail_from_address --value="${SMTP_FROM_LOCAL:-admin}"
  occ config:system:set mail_domain --value="${SMTP_DOMAIN:-bacmastercloud.com}"
  echo "✅ Nextcloud SMTP ayarlandı"
else
  echo "⚠️ ZOHO_NEXTCLOUD_APP_PASS boş, Nextcloud SMTP atlandı"
fi

if [[ -n "${GOOGLE_CLIENT_ID:-}" && -n "${GOOGLE_CLIENT_SECRET:-}" ]]; then
  occ app:install sociallogin || true
  occ app:enable sociallogin || true
  echo "ℹ️ Google OAuth env mevcut. sociallogin app kuruldu/aktif edildi; provider UI/API doğrulaması gerekebilir."
fi

create_user(){
  local u="$1" p="$2"
  [[ -n "$u" && -n "$p" ]] || return 0
  if occ user:info "$u" >/dev/null 2>&1; then
    echo "✅ Nextcloud user zaten var: $u"
  else
    OC_PASS="$p" occ user:add --password-from-env "$u"
    echo "✅ Nextcloud user oluşturuldu: $u"
  fi
}
create_user "${BACMASTER_USER:-bacmaster}" "${BACMASTER_PASS:-}"
occ maintenance:repair || true
EOS
chmod +x "$TMP/nextcloud-post-config.sh"
rscp "$TMP/nextcloud-post-config.sh" 104 /tmp/hv23-nextcloud-post-config.sh
rscp "$TMP/nextcloud-post.env" 104 /tmp/hv23-nextcloud-post.env
rssh 104 "sudo bash -c 'set -a; source /tmp/hv23-nextcloud-post.env; set +a; bash /tmp/hv23-nextcloud-post-config.sh; rm -f /tmp/hv23-nextcloud-post.env'"
rm -rf "$TMP"
