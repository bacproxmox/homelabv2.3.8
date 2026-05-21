#!/usr/bin/env bash
set -Eeuo pipefail
set +H

echo "🔐 Homelab v2.3.8 - Google OAuth Manager"

SECRETS_DIR="/root/homelab-secrets"
USERS_ENV="$SECRETS_DIR/users.env"
GOOGLE_ENV="$SECRETS_DIR/google.env"
LEGACY_OAUTH_ENV="$SECRETS_DIR/oauth.env"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

[[ -f "$USERS_ENV" ]] || { echo "❌ users.env yok: $USERS_ENV"; exit 1; }
source "$USERS_ENV"
[[ -f "$GOOGLE_ENV" ]] && source "$GOOGLE_ENV"
[[ -f "$LEGACY_OAUTH_ENV" ]] && source "$LEGACY_OAUTH_ENV"

ask_visible_if_missing(){
  local var="$1" prompt="$2" current="${!var:-}"
  if [[ -n "$current" ]]; then
    echo "✅ $var mevcut, tekrar sorulmayacak."
    return 0
  fi
  local value=""
  while [[ -z "$value" ]]; do read -r -p "$prompt: " value; done
  printf -v "$var" '%s' "$value"
}

ask_visible_if_missing GOOGLE_CLIENT_ID "Google Client ID"
ask_visible_if_missing GOOGLE_CLIENT_SECRET "Google Client Secret"
if [[ -z "${GOOGLE_AUTO_REGISTER:-}" ]]; then
  read -r -p "Google ile otomatik kayıt açılsın mı? [y/N]: " AUTO_REGISTER
  if [[ "${AUTO_REGISTER:-N}" =~ ^[Yy]$ ]]; then GOOGLE_AUTO_REGISTER="true"; else GOOGLE_AUTO_REGISTER="false"; fi
fi

cat > "$GOOGLE_ENV" <<ENV
GOOGLE_CLIENT_ID='${GOOGLE_CLIENT_ID}'
GOOGLE_CLIENT_SECRET='${GOOGLE_CLIENT_SECRET}'
GOOGLE_ISSUER_URL='https://accounts.google.com'
GOOGLE_SCOPE='openid email profile'
GOOGLE_AUTO_REGISTER='${GOOGLE_AUTO_REGISTER}'
ENV
chmod 600 "$GOOGLE_ENV"
ln -sf "$GOOGLE_ENV" "$LEGACY_OAUTH_ENV" 2>/dev/null || true
echo "✅ Google OAuth secret kaydedildi: $GOOGLE_ENV"

VM106_IP="192.168.50.106"
VM104_IP="192.168.50.104"
SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:?BACMASTER_PASS yok}"
IMMICH_AUTO_REGISTER="$GOOGLE_AUTO_REGISTER"
OPENWEBUI_SIGNUP="$GOOGLE_AUTO_REGISTER"

apt update
apt install -y sshpass curl jq
shell_quote(){ printf "%q" "$1"; }
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

run_remote(){
  local ip="$1" envs="$2" body="$3" tmp
  tmp="$(mktemp)"; printf '%s\n' "$body" > "$tmp"
  sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" "$tmp" "$SSH_USER@$ip:/tmp/homelab-oauth.sh" >/dev/null
  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" "printf '%s\n' $(shell_quote "$SSH_PASS") | sudo -S -p '' env $envs bash /tmp/homelab-oauth.sh"
  rm -f "$tmp"
}

echo
echo "📸 Immich OAuth ayarlanıyor..."
run_remote "$VM106_IP" "BACMASTER_PASS=$(shell_quote "$SSH_PASS") GOOGLE_CLIENT_ID=$(shell_quote "$GOOGLE_CLIENT_ID") GOOGLE_CLIENT_SECRET=$(shell_quote "$GOOGLE_CLIENT_SECRET") IMMICH_AUTO_REGISTER=$(shell_quote "$IMMICH_AUTO_REGISTER")" '#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/immich
LOGIN_JSON="$(curl -sS -X POST http://127.0.0.1:2283/api/auth/login -H "Content-Type: application/json" -d "{\"email\":\"admin@bacmastercloud.com\",\"password\":\"$BACMASTER_PASS\"}")"
TOKEN="$(echo "$LOGIN_JSON" | jq -r ".accessToken // empty")"
[[ -n "$TOKEN" ]] || { echo "❌ Immich admin token alınamadı."; echo "$LOGIN_JSON"; exit 1; }
CONFIG="$(curl -sS http://127.0.0.1:2283/api/system-config -H "Authorization: Bearer $TOKEN")"
NEW_CONFIG="$(echo "$CONFIG" | jq --arg clientId "$GOOGLE_CLIENT_ID" --arg clientSecret "$GOOGLE_CLIENT_SECRET" --argjson autoRegister "$IMMICH_AUTO_REGISTER" '\''.oauth.enabled=true | .oauth.issuerUrl="https://accounts.google.com" | .oauth.clientId=$clientId | .oauth.clientSecret=$clientSecret | .oauth.scope="openid email profile" | .oauth.signingAlgorithm="RS256" | .oauth.profileSigningAlgorithm="none" | .oauth.storageLabelClaim="email" | .oauth.buttonText="Google ile giriş yap" | .oauth.autoRegister=$autoRegister | .oauth.autoLaunch=false'\'')"
curl -sS -X PUT http://127.0.0.1:2283/api/system-config -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$NEW_CONFIG" >/dev/null
docker compose restart immich-server >/dev/null
echo "✅ Immich OAuth tamam."'

echo
echo "🤖 Open WebUI OAuth ayarlanıyor..."
run_remote "$VM106_IP" "GOOGLE_CLIENT_ID=$(shell_quote "$GOOGLE_CLIENT_ID") GOOGLE_CLIENT_SECRET=$(shell_quote "$GOOGLE_CLIENT_SECRET") OPENWEBUI_SIGNUP=$(shell_quote "$OPENWEBUI_SIGNUP")" '#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/ollama
cp docker-compose.yml docker-compose.yml.bak.oauth.$(date +%Y%m%d-%H%M%S)
python3 - <<PY
from pathlib import Path
p=Path("docker-compose.yml")
text=p.read_text()
remove=["OAUTH_CLIENT_ID=","OAUTH_CLIENT_SECRET=","OPENID_PROVIDER_URL=","ENABLE_OAUTH_SIGNUP=","OAUTH_PROVIDER_NAME=","OAUTH_SCOPES=","OPENID_REDIRECT_URI=","WEBUI_URL="]
lines=[l for l in text.splitlines() if not any(k in l for k in remove)]
text="\n".join(lines)+"\n"
insert=f"""      - OAUTH_CLIENT_ID=${{GOOGLE_CLIENT_ID}}
      - OAUTH_CLIENT_SECRET=${{GOOGLE_CLIENT_SECRET}}
      - OPENID_PROVIDER_URL=https://accounts.google.com/.well-known/openid-configuration
      - ENABLE_OAUTH_SIGNUP=${{OPENWEBUI_SIGNUP}}
      - OAUTH_PROVIDER_NAME=Google
      - OAUTH_SCOPES=openid email profile
      - OPENID_REDIRECT_URI=https://ai.bacmastercloud.com/oauth/oidc/callback
      - WEBUI_URL=https://ai.bacmastercloud.com
"""
marker="      - OLLAMA_BASE_URL=http://ollama:11434"
if marker in text: text=text.replace(marker, insert+marker)
else: text=text.replace("    environment:\n", "    environment:\n"+insert, 1)
p.write_text(text)
PY
docker compose config >/dev/null
docker compose up -d open-webui >/dev/null
echo "✅ Open WebUI OAuth tamam."'

echo
echo "☁️ Nextcloud Social Login hazırlanıyor..."
run_remote "$VM104_IP" "GOOGLE_CLIENT_ID=$(shell_quote "$GOOGLE_CLIENT_ID") GOOGLE_CLIENT_SECRET=$(shell_quote "$GOOGLE_CLIENT_SECRET")" '#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/nextcloud
NC_CONTAINER="$(docker ps --format "{{.Names}}" | grep -E "^(hb-nextcloud|nextcloud)$" | head -n1 || true)"
[[ -n "$NC_CONTAINER" ]] || { echo "❌ Nextcloud container bulunamadı."; docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"; exit 1; }
occ(){ docker exec -u www-data "$NC_CONTAINER" php occ "$@"; }
occ app:install sociallogin || true
occ app:enable sociallogin || true
apt update >/dev/null
apt install -y jq >/dev/null
occ config:system:set overwrite.cli.url --value="https://cloud.bacmastercloud.com" >/dev/null
occ config:system:set overwritehost --value="cloud.bacmastercloud.com" >/dev/null
occ config:system:set overwriteprotocol --value="https" >/dev/null
occ config:system:set trusted_domains 0 --value="192.168.50.104" >/dev/null
occ config:system:set trusted_domains 1 --value="192.168.50.104:8080" >/dev/null
occ config:system:set trusted_domains 2 --value="cloud.bacmastercloud.com" >/dev/null
occ config:system:set trusted_domains 3 --value="nextcloud.bacmastercloud.com" >/dev/null
occ config:system:set trusted_domains 4 --value="cloud-api.bacmastercloud.com" >/dev/null
PROVIDERS="$(jq -n --arg clientId "$GOOGLE_CLIENT_ID" --arg clientSecret "$GOOGLE_CLIENT_SECRET" '\''{custom_oidc:[{name:"google",title:"Google ile giriş yap",authorizeUrl:"https://accounts.google.com/o/oauth2/v2/auth",tokenUrl:"https://oauth2.googleapis.com/token",userInfoUrl:"https://openidconnect.googleapis.com/v1/userinfo",logoutUrl:"",clientId:$clientId,clientSecret:$clientSecret,scope:"openid email profile",groupsClaim:"",style:"google",defaultGroup:""}]}'\'')"
occ config:app:set sociallogin prevent_create_email_exists --value="0" >/dev/null || true
occ config:app:set sociallogin update_profile_on_login --value="1" >/dev/null || true
occ config:app:set sociallogin hide_default_login --value="0" >/dev/null || true
occ config:app:set sociallogin disable_registration --value="0" >/dev/null || true
occ config:app:set sociallogin custom_providers --value="$PROVIDERS" >/dev/null
docker compose restart app >/dev/null || docker restart "$NC_CONTAINER" >/dev/null
echo "✅ Nextcloud Google Social Login provider otomatik yazıldı."'

echo
echo "✅ Google OAuth Manager tamamlandı."
