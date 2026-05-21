#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "config-menu"
run(){ echo; echo "▶️ $*"; if bash "$ROOT_DIR/$1"; then return 0; else local c=$?; echo "❌ Script hata verdi ($c): $1"; return "$c"; fi; }
run_jellyfin_with_wizard_gate(){
  echo; echo "▶️ config/jellyfin/01-jellyfin-libraries-and-users.sh"
  if bash "$ROOT_DIR/config/jellyfin/01-jellyfin-libraries-and-users.sh"; then return 0; fi
  local c=$?
  if [[ "$c" == "20" ]]; then
    cat <<'MSG'

⚠️ Jellyfin wizard tamamlanmamış.
Tarayıcıdan aç: http://192.168.50.106:8096
Admin kullanıcı: bacmaster
Şifre: /root/homelab-secrets/users.env içindeki BACMASTER_PASS

Wizard bitince Enter'a bas. Aynı script otomatik tekrar çalışacak.
MSG
    read -r -p "Jellyfin wizard tamamlandıysa Enter..." _
    bash "$ROOT_DIR/config/jellyfin/01-jellyfin-libraries-and-users.sh"
    return $?
  fi
  return "$c"
}
run_all_core(){
  run config/arr/05-configure-service-auth.sh
  run config/arr/06-configure-arr-integrations.sh
  run config/prowlarr/01-add-canonical-indexers.sh
  run config/bazarr/07-bazarr-languages-and-media-management.sh
  run_jellyfin_with_wizard_gate
  run config/seerr/02-seerr-full-auto-config.sh
  run config/nextcloud/02-nextcloud-smtp-google-and-users.sh
  run config/immich/02-immich-users-smtp-external-library-note.sh
  run config/ollama/02-fix-openwebui-admin.sh
}
while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.3.8 - Config Menu
=========================================
1) Configure service auth (qBittorrent / Sonarr / Radarr / Prowlarr / Lidarr)
2) Configure ARR integrations (qBit clients / Prowlarr apps / FlareSolverr)
3) Add Prowlarr canonical indexers
4) Configure Bazarr languages + media management
5) Configure Jellyfin users/libraries/HW acceleration
6) Configure Seerr full-auto
7) Configure Nextcloud SMTP/Google/users/local fix
8) Configure Immich users/storage/external libraries
9) Reset + final configure Immich
10) Fix OpenWebUI admin
11) Google OAuth manager
12) SMTP reference + tests helper
13) Uptime Kuma SMTP note
14) Run all core config scripts
15) Additionals menu
16) Exit
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) run config/arr/05-configure-service-auth.sh ;;
    2) run config/arr/06-configure-arr-integrations.sh ;;
    3) run config/prowlarr/01-add-canonical-indexers.sh ;;
    4) run config/bazarr/07-bazarr-languages-and-media-management.sh ;;
    5) run_jellyfin_with_wizard_gate ;;
    6) run config/seerr/02-seerr-full-auto-config.sh ;;
    7) run config/nextcloud/02-nextcloud-smtp-google-and-users.sh ;;
    8) run config/immich/02-immich-users-smtp-external-library-note.sh ;;
    9) run config/immich/03-immich-reset-final-config.sh ;;
    10) run config/ollama/02-fix-openwebui-admin.sh ;;
    11) run config/google-oauth/14c-configure-google-oauth-all.sh ;;
    12) run config/smtp/01-write-service-smtp-reference.sh ;;
    13) run config/uptime-kuma/01-uptime-kuma-smtp-note.sh ;;
    14) run_all_core ;;
    15) bash "$ROOT_DIR/menu/additionals-menu.sh" ;;
    16) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
