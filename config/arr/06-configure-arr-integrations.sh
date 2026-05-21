#!/usr/bin/env bash
set -euo pipefail

export TERM=xterm

USERS_ENV="/root/homelab-secrets/users.env"

VM102="192.168.50.102"
VM106="192.168.50.106"

SERVICE_USER=""
SERVICE_PASS=""

QBIT_URL="http://192.168.50.102:8080"
SONARR_URL="http://192.168.50.102:8989"
RADARR_URL="http://192.168.50.102:7878"
PROWLARR_URL="http://192.168.50.102:9696"
LIDARR_URL="http://192.168.50.106:8686"

FLARESOLVERR_URL="http://flaresolverr:8191/"

echo
echo "🔗 Homelab v2.3.8 - ARR Integration Configurator"
echo

if [ ! -f "$USERS_ENV" ]; then
  echo "❌ $USERS_ENV bulunamadı."
  exit 1
fi

set -a
source "$USERS_ENV"
set +a

SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:-}"

SERVICE_USER="${BACMASTER_USER:-bacmaster}"
SERVICE_PASS="${BACMASTER_PASS:-}"

if [ -z "$SSH_PASS" ] || [ -z "$SERVICE_PASS" ]; then
  echo "❌ BACMASTER_PASS users.env içinde bulunamadı."
  exit 1
fi

apt update
apt install -y sshpass curl jq

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=8
)

run_ssh() {
  local ip="$1"
  local tmp_local
  tmp_local="$(mktemp)"

  cat > "$tmp_local"

  sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" \
    "$tmp_local" "$SSH_USER@$ip:/tmp/homelab-arr-run.sh" >/dev/null

  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" \
    "$SSH_USER@$ip" \
    "echo '$SSH_PASS' | sudo -S -p '' bash /tmp/homelab-arr-run.sh"

  rm -f "$tmp_local"
}

remote_api_key() {
  local ip="$1"
  local config="$2"

  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" \
    "echo '$SSH_PASS' | sudo -S -p '' sh -c \"sed -n 's:.*<ApiKey>\\(.*\\)</ApiKey>.*:\\1:p' '$config' | head -n1\"" \
    2>/dev/null | tr -d '\r' || true
}

wait_api() {
  local name="$1"
  local url="$2"
  local key="$3"

  echo "⏳ $name API bekleniyor..."

  for i in {1..60}; do
    if curl -fsS -H "X-Api-Key: $key" "$url/api/v3/system/status" >/dev/null 2>&1; then
      echo "✅ $name API hazır."
      return 0
    fi

    if curl -fsS -H "X-Api-Key: $key" "$url/api/v1/system/status" >/dev/null 2>&1; then
      echo "✅ $name API hazır."
      return 0
    fi

    sleep 2
  done

  echo "⚠️ $name API erişilemedi: $url"
  return 1
}

api_get_v3() {
  local url="$1"
  local key="$2"
  local path="$3"

  curl -fsS -H "X-Api-Key: $key" "$url/api/v3$path"
}

api_post_v3() {
  local url="$1"
  local key="$2"
  local path="$3"
  local payload="$4"

  curl -sS \
    -H "X-Api-Key: $key" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "$payload" \
    "$url/api/v3$path"
}

api_delete_v3() {
  local url="$1"
  local key="$2"
  local path="$3"

  curl -fsS \
    -H "X-Api-Key: $key" \
    -X DELETE \
    "$url/api/v3$path" >/dev/null || true
}

api_get_v1() {
  local url="$1"
  local key="$2"
  local path="$3"

  curl -fsS -H "X-Api-Key: $key" "$url/api/v1$path"
}

api_post_v1() {
  local url="$1"
  local key="$2"
  local path="$3"
  local payload="$4"

  curl -sS \
    -H "X-Api-Key: $key" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "$payload" \
    "$url/api/v1$path"
}

api_delete_v1() {
  local url="$1"
  local key="$2"
  local path="$3"

  curl -fsS \
    -H "X-Api-Key: $key" \
    -X DELETE \
    "$url/api/v1$path" >/dev/null || true
}

check_mount_vm102() {
  echo
  echo "🧪 VM102 /mnt/media mount ve yazma testi..."

  run_ssh "$VM102" <<'EOF'
set -euo pipefail

if ! mountpoint -q /mnt/media; then
  echo "⚠️ /mnt/media mount değil. mount -a deneniyor..."
  mount -a || true
fi

if ! mountpoint -q /mnt/media; then
  echo "❌ /mnt/media hâlâ mount değil."
  exit 1
fi

for dir in /mnt/media/downloads /mnt/media/movies /mnt/media/series; do
  mkdir -p "$dir"

  testfile="$dir/.homelab-write-test"
  echo "test" > "$testfile"
  rm -f "$testfile"

  if id bacmaster >/dev/null 2>&1; then
    sudo -u bacmaster bash -c "echo test > '$testfile'"
    rm -f "$testfile"
  fi

  echo "✅ Yazma testi başarılı: $dir"
done

echo "✅ VM102 mount testleri tamam."
EOF
}

check_mount_vm106() {
  echo
  echo "🧪 VM106 /mnt/media mount ve yazma testi..."

  run_ssh "$VM106" <<'EOF'
set -euo pipefail

if ! mountpoint -q /mnt/media; then
  echo "⚠️ /mnt/media mount değil. mount -a deneniyor..."
  mount -a || true
fi

if ! mountpoint -q /mnt/media; then
  echo "❌ /mnt/media hâlâ mount değil."
  exit 1
fi

for dir in /mnt/media/music /mnt/media/downloads; do
  mkdir -p "$dir"

  testfile="$dir/.homelab-write-test"
  echo "test" > "$testfile"
  rm -f "$testfile"

  if id bacmaster >/dev/null 2>&1; then
    sudo -u bacmaster bash -c "echo test > '$testfile'"
    rm -f "$testfile"
  fi

  echo "✅ Yazma testi başarılı: $dir"
done

echo "✅ VM106 mount testleri tamam."
EOF
}

qb_login() {
  local user="$1"
  local pass="$2"

  rm -f /tmp/qbit.cookies

  local result
  result="$(curl -fsS -i -c /tmp/qbit.cookies \
    --data-urlencode "username=$user" \
    --data-urlencode "password=$pass" \
    "$QBIT_URL/api/v2/auth/login" || true)"

  echo "$result" | grep -qi "Ok"
}

configure_qbittorrent() {
  echo
  echo "🧲 qBittorrent kategori ve tercih ayarları..."

  if ! qb_login "$SERVICE_USER" "$SERVICE_PASS"; then
    echo "⚠️ qBittorrent login başarısız: $SERVICE_USER"
    return 0
  fi

  curl -fsS -b /tmp/qbit.cookies \
    --data-urlencode "json={\"save_path\":\"/downloads/\",\"temp_path_enabled\":false,\"create_subfolder_enabled\":true}" \
    "$QBIT_URL/api/v2/app/setPreferences" >/dev/null || true

  curl -fsS -b /tmp/qbit.cookies \
    --data-urlencode "category=sonarr" \
    --data-urlencode "savePath=/downloads/sonarr" \
    "$QBIT_URL/api/v2/torrents/createCategory" >/dev/null || true

  curl -fsS -b /tmp/qbit.cookies \
    --data-urlencode "category=radarr" \
    --data-urlencode "savePath=/downloads/radarr" \
    "$QBIT_URL/api/v2/torrents/createCategory" >/dev/null || true

  curl -fsS -b /tmp/qbit.cookies \
    --data-urlencode "category=lidarr" \
    --data-urlencode "savePath=/downloads/lidarr" \
    "$QBIT_URL/api/v2/torrents/createCategory" >/dev/null || true

  echo "✅ qBittorrent kategorileri hazır: sonarr, radarr, lidarr"
}

add_root_folder() {
  local app="$1"
  local url="$2"
  local key="$3"
  local path="$4"

  echo
  echo "📁 $app root folder kontrolü: $path"

  local existing
  existing="$(api_get_v3 "$url" "$key" "/rootfolder" || echo "[]")"

  if echo "$existing" | jq -e --arg path "$path" '.[] | select(.path==$path)' >/dev/null 2>&1; then
    echo "✅ $app root folder zaten var."
    return 0
  fi

  local payload
  payload="$(jq -n --arg path "$path" '{path:$path}')"

  local response
  response="$(api_post_v3 "$url" "$key" "/rootfolder" "$payload" || true)"

  if echo "$response" | grep -qi "error\|exception\|validation"; then
    echo "⚠️ $app root folder ekleme cevabı:"
    echo "$response"
  else
    echo "✅ $app root folder eklendi/denendi."
  fi
}

delete_download_client_by_name() {
  local app="$1"
  local url="$2"
  local key="$3"
  local name="$4"

  local existing ids
  existing="$(api_get_v3 "$url" "$key" "/downloadclient" || echo "[]")"
  ids="$(echo "$existing" | jq -r --arg name "$name" '.[] | select(.name==$name) | .id' || true)"

  while read -r id; do
    [ -z "$id" ] && continue
    [ "$id" = "null" ] && continue
    echo "🧹 $app eski download client siliniyor: $name ID $id"
    api_delete_v3 "$url" "$key" "/downloadclient/$id"
  done <<< "$ids"
}

add_qbit_client_sonarr() {
  echo
  echo "📺 Sonarr → qBittorrent bağlantısı..."

  delete_download_client_by_name "Sonarr" "$SONARR_URL" "$SONARR_KEY" "qBittorrent"

  local payload
  payload="$(jq -n \
    --arg user "$SERVICE_USER" \
    --arg pass "$SERVICE_PASS" \
    '{
      enable: true,
      protocol: "torrent",
      priority: 1,
      removeCompletedDownloads: true,
      removeFailedDownloads: true,
      name: "qBittorrent",
      implementation: "QBittorrent",
      configContract: "QBittorrentSettings",
      fields: [
        {name:"host", value:"192.168.50.102"},
        {name:"port", value:8080},
        {name:"useSsl", value:false},
        {name:"urlBase", value:""},
        {name:"username", value:$user},
        {name:"password", value:$pass},
        {name:"category", value:"sonarr"},
        {name:"recentTvPriority", value:0},
        {name:"olderTvPriority", value:0},
        {name:"initialState", value:0}
      ]
    }')"

  api_post_v3 "$SONARR_URL" "$SONARR_KEY" "/downloadclient" "$payload" >/tmp/sonarr-qbit.json || true

  if grep -qi "error\|exception\|validation" /tmp/sonarr-qbit.json 2>/dev/null; then
    echo "⚠️ Sonarr qBittorrent ekleme cevabı:"
    cat /tmp/sonarr-qbit.json
  else
    echo "✅ Sonarr qBittorrent bağlantısı eklendi."
  fi
}

add_qbit_client_radarr() {
  echo
  echo "🎬 Radarr → qBittorrent bağlantısı..."

  delete_download_client_by_name "Radarr" "$RADARR_URL" "$RADARR_KEY" "qBittorrent"

  local payload
  payload="$(jq -n \
    --arg user "$SERVICE_USER" \
    --arg pass "$SERVICE_PASS" \
    '{
      enable: true,
      protocol: "torrent",
      priority: 1,
      removeCompletedDownloads: true,
      removeFailedDownloads: true,
      name: "qBittorrent",
      implementation: "QBittorrent",
      configContract: "QBittorrentSettings",
      fields: [
        {name:"host", value:"192.168.50.102"},
        {name:"port", value:8080},
        {name:"useSsl", value:false},
        {name:"urlBase", value:""},
        {name:"username", value:$user},
        {name:"password", value:$pass},
        {name:"category", value:"radarr"},
        {name:"recentMoviePriority", value:0},
        {name:"olderMoviePriority", value:0},
        {name:"initialState", value:0}
      ]
    }')"

  api_post_v3 "$RADARR_URL" "$RADARR_KEY" "/downloadclient" "$payload" >/tmp/radarr-qbit.json || true

  if grep -qi "error\|exception\|validation" /tmp/radarr-qbit.json 2>/dev/null; then
    echo "⚠️ Radarr qBittorrent ekleme cevabı:"
    cat /tmp/radarr-qbit.json
  else
    echo "✅ Radarr qBittorrent bağlantısı eklendi."
  fi
}

add_qbit_client_lidarr() {
  echo
  echo "🎵 Lidarr → qBittorrent bağlantısı..."

  delete_download_client_by_name "Lidarr" "$LIDARR_URL" "$LIDARR_KEY" "qBittorrent"

  local payload
  payload="$(jq -n \
    --arg user "$SERVICE_USER" \
    --arg pass "$SERVICE_PASS" \
    '{
      enable: true,
      protocol: "torrent",
      priority: 1,
      removeCompletedDownloads: true,
      removeFailedDownloads: true,
      name: "qBittorrent",
      implementation: "QBittorrent",
      configContract: "QBittorrentSettings",
      fields: [
        {name:"host", value:"192.168.50.102"},
        {name:"port", value:8080},
        {name:"useSsl", value:false},
        {name:"urlBase", value:""},
        {name:"username", value:$user},
        {name:"password", value:$pass},
        {name:"category", value:"lidarr"},
        {name:"recentAlbumPriority", value:0},
        {name:"olderAlbumPriority", value:0},
        {name:"initialState", value:0}
      ]
    }')"

  api_post_v3 "$LIDARR_URL" "$LIDARR_KEY" "/downloadclient" "$payload" >/tmp/lidarr-qbit.json || true

  if grep -qi "error\|exception\|validation" /tmp/lidarr-qbit.json 2>/dev/null; then
    echo "⚠️ Lidarr qBittorrent ekleme cevabı:"
    cat /tmp/lidarr-qbit.json
  else
    echo "✅ Lidarr qBittorrent bağlantısı eklendi."
  fi
}

prowlarr_delete_app() {
  local name="$1"

  local apps ids
  apps="$(api_get_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/applications" || echo "[]")"
  ids="$(echo "$apps" | jq -r --arg name "$name" '.[] | select(.name==$name) | .id' || true)"

  while read -r id; do
    [ -z "$id" ] && continue
    [ "$id" = "null" ] && continue
    echo "🧹 Prowlarr eski app siliniyor: $name ID $id"
    api_delete_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/applications/$id"
  done <<< "$ids"
}

prowlarr_get_or_create_tag() {
  local label="$1"

  local tag_id
  tag_id="$(api_get_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/tag" | jq -r --arg label "$label" '.[] | select(.label==$label) | .id' | head -n1 || true)"

  if [ -n "$tag_id" ] && [ "$tag_id" != "null" ]; then
    echo "$tag_id"
    return 0
  fi

  api_post_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/tag" "$(jq -n --arg label "$label" '{label:$label}')" \
    | jq -r '.id // empty'
}

configure_flaresolverr() {
  echo
  echo "🔥 Prowlarr → FlareSolverr proxy ayarlanıyor..."

  local tag_id tag_json existing ids payload
  tag_id="$(prowlarr_get_or_create_tag "cl" || true)"

  if [ -n "$tag_id" ] && [ "$tag_id" != "null" ]; then
    tag_json="[$tag_id]"
  else
    tag_json="[]"
  fi

  existing="$(api_get_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/indexerproxy" || echo "[]")"
  ids="$(echo "$existing" | jq -r '.[] | select(.name=="FlareSolverr" or .implementation=="FlareSolverr") | .id' || true)"

  while read -r id; do
    [ -z "$id" ] && continue
    [ "$id" = "null" ] && continue
    echo "🧹 Eski FlareSolverr proxy siliniyor: ID $id"
    api_delete_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/indexerproxy/$id"
  done <<< "$ids"

  payload="$(jq -n \
    --arg host "$FLARESOLVERR_URL" \
    --argjson tags "$tag_json" \
    '{
      name:"FlareSolverr",
      implementation:"FlareSolverr",
      configContract:"FlareSolverrSettings",
      tags:$tags,
      fields:[
        {name:"host", value:$host}
      ]
    }')"

  api_post_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/indexerproxy" "$payload" >/tmp/prowlarr-flaresolverr.json || true

  if grep -qi "error\|exception\|validation" /tmp/prowlarr-flaresolverr.json 2>/dev/null; then
    echo "⚠️ FlareSolverr proxy ekleme cevabı:"
    cat /tmp/prowlarr-flaresolverr.json
  else
    echo "✅ FlareSolverr proxy eklendi."
  fi
}

add_prowlarr_sonarr_app() {
  echo
  echo "📺 Prowlarr → Sonarr app sync..."

  prowlarr_delete_app "Sonarr"

  local payload
  payload="$(jq -n \
    --arg prowlarrUrl "$PROWLARR_URL" \
    --arg baseUrl "$SONARR_URL" \
    --arg apiKey "$SONARR_KEY" \
    '{
      name:"Sonarr",
      syncLevel:"fullSync",
      implementation:"Sonarr",
      configContract:"SonarrSettings",
      fields:[
        {name:"prowlarrUrl", value:$prowlarrUrl},
        {name:"baseUrl", value:$baseUrl},
        {name:"apiKey", value:$apiKey},
        {name:"syncCategories", value:[5000,5010,5020,5030,5040,5045,5050,5060,5070,5080]},
        {name:"animeSyncCategories", value:[5070]}
      ]
    }')"

  api_post_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/applications" "$payload" >/tmp/prowlarr-sonarr.json || true

  if grep -qi "error\|exception\|validation" /tmp/prowlarr-sonarr.json 2>/dev/null; then
    echo "⚠️ Prowlarr Sonarr app cevabı:"
    cat /tmp/prowlarr-sonarr.json
  else
    echo "✅ Prowlarr Sonarr app sync eklendi."
  fi
}

add_prowlarr_radarr_app() {
  echo
  echo "🎬 Prowlarr → Radarr app sync..."

  prowlarr_delete_app "Radarr"

  local payload
  payload="$(jq -n \
    --arg prowlarrUrl "$PROWLARR_URL" \
    --arg baseUrl "$RADARR_URL" \
    --arg apiKey "$RADARR_KEY" \
    '{
      name:"Radarr",
      syncLevel:"fullSync",
      implementation:"Radarr",
      configContract:"RadarrSettings",
      fields:[
        {name:"prowlarrUrl", value:$prowlarrUrl},
        {name:"baseUrl", value:$baseUrl},
        {name:"apiKey", value:$apiKey},
        {name:"syncCategories", value:[2000,2010,2020,2030,2040,2045,2050,2060,2070,2080]}
      ]
    }')"

  api_post_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/applications" "$payload" >/tmp/prowlarr-radarr.json || true

  if grep -qi "error\|exception\|validation" /tmp/prowlarr-radarr.json 2>/dev/null; then
    echo "⚠️ Prowlarr Radarr app cevabı:"
    cat /tmp/prowlarr-radarr.json
  else
    echo "✅ Prowlarr Radarr app sync eklendi."
  fi
}

add_prowlarr_lidarr_app() {
  echo
  echo "🎵 Prowlarr → Lidarr app sync..."

  prowlarr_delete_app "Lidarr"

  local payload
  payload="$(jq -n \
    --arg prowlarrUrl "$PROWLARR_URL" \
    --arg baseUrl "$LIDARR_URL" \
    --arg apiKey "$LIDARR_KEY" \
    '{
      name:"Lidarr",
      syncLevel:"fullSync",
      implementation:"Lidarr",
      configContract:"LidarrSettings",
      fields:[
        {name:"prowlarrUrl", value:$prowlarrUrl},
        {name:"baseUrl", value:$baseUrl},
        {name:"apiKey", value:$apiKey},
        {name:"syncCategories", value:[3000,3010,3020,3030,3040,3050,3060]}
      ]
    }')"

  api_post_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/applications" "$payload" >/tmp/prowlarr-lidarr.json || true

  if grep -qi "error\|exception\|validation" /tmp/prowlarr-lidarr.json 2>/dev/null; then
    echo "⚠️ Prowlarr Lidarr app cevabı:"
    cat /tmp/prowlarr-lidarr.json
  else
    echo "✅ Prowlarr Lidarr app sync eklendi."
  fi
}

trigger_prowlarr_sync() {
  echo
  echo "🔄 Prowlarr indexer sync tetikleniyor..."

  api_post_v1 "$PROWLARR_URL" "$PROWLARR_KEY" "/command" '{"name":"ApplicationIndexerSync"}' >/tmp/prowlarr-sync.json || true

  echo "✅ Sync komutu gönderildi."
}

print_summary() {
  echo
  echo "✅ 06-configure-arr-integrations.sh tamamlandı."
  echo
  echo "Kontrol edilecek yerler:"
  echo "  - Sonarr → Settings → Download Clients"
  echo "  - Radarr → Settings → Download Clients"
  echo "  - Lidarr → Settings → Download Clients"
  echo "  - Prowlarr → Settings → Apps"
  echo "  - Prowlarr → Settings → Indexer Proxies"
}

check_mount_vm102
check_mount_vm106

echo
echo "🔑 API keyler okunuyor..."

SONARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/sonarr/config.xml")"
RADARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/radarr/config.xml")"
PROWLARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/prowlarr/config.xml")"
LIDARR_KEY="$(remote_api_key "$VM106" "/opt/homelab/lidarr/config/lidarr/config.xml")"

[ -n "$SONARR_KEY" ] && echo "✅ Sonarr API key bulundu." || echo "❌ Sonarr API key yok."
[ -n "$RADARR_KEY" ] && echo "✅ Radarr API key bulundu." || echo "❌ Radarr API key yok."
[ -n "$PROWLARR_KEY" ] && echo "✅ Prowlarr API key bulundu." || echo "❌ Prowlarr API key yok."
[ -n "$LIDARR_KEY" ] && echo "✅ Lidarr API key bulundu." || echo "❌ Lidarr API key yok."

if [ -z "$SONARR_KEY" ] || [ -z "$RADARR_KEY" ] || [ -z "$PROWLARR_KEY" ] || [ -z "$LIDARR_KEY" ]; then
  echo "❌ Eksik API key var. Önce 05-configure-service-auth.sh ve containerların sağlıklı çalıştığını kontrol et."
  exit 1
fi

wait_api "Sonarr" "$SONARR_URL" "$SONARR_KEY" || true
wait_api "Radarr" "$RADARR_URL" "$RADARR_KEY" || true
wait_api "Prowlarr" "$PROWLARR_URL" "$PROWLARR_KEY" || true
wait_api "Lidarr" "$LIDARR_URL" "$LIDARR_KEY" || true

configure_qbittorrent

add_root_folder "Sonarr" "$SONARR_URL" "$SONARR_KEY" "/media/series"
add_root_folder "Radarr" "$RADARR_URL" "$RADARR_KEY" "/media/movies"
add_root_folder "Lidarr" "$LIDARR_URL" "$LIDARR_KEY" "/media/music"

add_qbit_client_sonarr
add_qbit_client_radarr
add_qbit_client_lidarr

configure_flaresolverr
add_prowlarr_sonarr_app
add_prowlarr_radarr_app
add_prowlarr_lidarr_app
trigger_prowlarr_sync

print_summary