#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/utils/env-loader.sh"
source "$REPO_ROOT/utils/logging.sh"
source "$REPO_ROOT/utils/remote.sh"
source "$REPO_ROOT/utils/state.sh"
source "$REPO_ROOT/utils/env-write.sh"
start_log "chia-farmer-install"
load_all_env

CHIA_ENV="$SECRETS_DIR/chia.env"
ask_visible_once() { local var="$1" prompt="$2" value=""; read -r -p "$prompt: " value; printf -v "$var" "%s" "$value"; }
ask_text_default() { local var="$1" prompt="$2" def="$3" value=""; read -r -p "$prompt [$def]: " value; printf -v "$var" "%s" "${value:-$def}"; }

if [[ ! -f "$CHIA_ENV" ]]; then
  echo "🌱 Chia farmer için geçici secret dosyası oluşturulacak. Script sonunda shred ile silinecek."
  ask_visible_once CHIA_MNEMONIC "Chia 24-word mnemonic"
  ask_text_default CHIA_DB_DOWNLOAD_URL "Opsiyonel Chia DB download URL, boş bırakılabilir" ""
  {
    write_env_header
    write_env_line CHIA_MNEMONIC "$CHIA_MNEMONIC"
    write_env_line CHIA_DB_DOWNLOAD_URL "$CHIA_DB_DOWNLOAD_URL"
  } > "$CHIA_ENV"
  chmod 600 "$CHIA_ENV"
fi

# shellcheck disable=SC1090
source "$CHIA_ENV"

wait_ssh 107
TMP_REMOTE="/tmp/homelab-chia-install.sh"
MNEMONIC_REMOTE="/tmp/chia-mnemonic.txt"

printf '%s\n' "$CHIA_MNEMONIC" > /tmp/chia-mnemonic.txt
scp "${SSH_OPTS[@]}" /tmp/chia-mnemonic.txt "$SSH_USER@192.168.50.107:$MNEMONIC_REMOTE"
shred -u /tmp/chia-mnemonic.txt || rm -f /tmp/chia-mnemonic.txt

cat > /tmp/homelab-chia-install.sh <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
CHIA_HOME="/home/bacmaster/.chia/mainnet"
CHIA_SRC="/opt/chia-blockchain"
MNEMONIC_FILE="/tmp/chia-mnemonic.txt"
DB_URL="${CHIA_DB_DOWNLOAD_URL:-}"

sudo apt update
sudo apt install -y git curl ca-certificates build-essential python3 python3-venv python3-pip python3-dev lsb-release jq tmux unzip rsync

if [[ ! -d "$CHIA_SRC/.git" ]]; then
  sudo git clone https://github.com/Chia-Network/chia-blockchain.git -b latest --recurse-submodules "$CHIA_SRC"
else
  cd "$CHIA_SRC"
  sudo git fetch --all --tags
  sudo git checkout latest || true
  sudo git pull --recurse-submodules || true
  sudo git submodule update --init --recursive
fi

sudo chown -R bacmaster:bacmaster "$CHIA_SRC"
cd "$CHIA_SRC"
sudo -u bacmaster bash -lc 'sh install.sh'
sudo -u bacmaster bash -lc 'cd /opt/chia-blockchain && . ./activate && chia init'

if [[ -s "$MNEMONIC_FILE" ]]; then
  sudo -u bacmaster bash -lc "cd /opt/chia-blockchain && . ./activate && chia keys add -f '$MNEMONIC_FILE' || true"
  shred -u "$MNEMONIC_FILE" || sudo rm -f "$MNEMONIC_FILE"
fi

if [[ -n "$DB_URL" ]]; then
  sudo -u bacmaster mkdir -p "$CHIA_HOME/db"
  echo "📦 Opsiyonel DB indiriliyor..."
  tmp="/tmp/chia-db-download"
  curl -fL "$DB_URL" -o "$tmp"
  case "$tmp" in
    *.gz) gzip -dc "$tmp" > "$CHIA_HOME/db/blockchain_v2_mainnet.sqlite" ;;
    *) cp "$tmp" "$CHIA_HOME/db/blockchain_v2_mainnet.sqlite" ;;
  esac
  sudo chown -R bacmaster:bacmaster "$CHIA_HOME"
  rm -f "$tmp"
else
  echo "ℹ️ CHIA_DB_DOWNLOAD_URL boş; DB bootstrap atlandı."
fi

sudo tee /etc/systemd/system/chia-farmer.service >/dev/null <<'UNIT'
[Unit]
Description=Chia Farmer
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=bacmaster
WorkingDirectory=/opt/chia-blockchain
Environment=CHIA_ROOT=/home/bacmaster/.chia/mainnet
ExecStart=/bin/bash -lc 'cd /opt/chia-blockchain && . ./activate && chia start farmer -r'
ExecStop=/bin/bash -lc 'cd /opt/chia-blockchain && . ./activate && chia stop all -d'
Restart=on-failure
RestartSec=20
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable chia-farmer.service
sudo systemctl restart chia-farmer.service || true
sudo -u bacmaster bash -lc 'cd /opt/chia-blockchain && . ./activate && chia show -s || true'
REMOTE

scp "${SSH_OPTS[@]}" /tmp/homelab-chia-install.sh "$SSH_USER@192.168.50.107:$TMP_REMOTE"
printf 'CHIA_DB_DOWNLOAD_URL=%q\n' "${CHIA_DB_DOWNLOAD_URL:-}" > /tmp/chia-remote.env
scp "${SSH_OPTS[@]}" /tmp/chia-remote.env "$SSH_USER@192.168.50.107:/tmp/chia-remote.env"
rm -f /tmp/chia-remote.env
ssh "${SSH_OPTS[@]}" "$SSH_USER@192.168.50.107" "chmod +x $TMP_REMOTE && sudo bash -c 'set -a; source /tmp/chia-remote.env; set +a; $TMP_REMOTE; rm -f /tmp/chia-remote.env'"
rm -f /tmp/homelab-chia-install.sh

if [[ -f "$CHIA_ENV" ]]; then
  echo "🧹 Chia secret dosyası siliniyor: $CHIA_ENV"
  shred -u "$CHIA_ENV" || rm -f "$CHIA_ENV"
fi

state_set chia_farmer_installed true
state_set chia_farmer_installed_at "$(date -Is)"
echo "✅ Chia farmer kurulumu tamamlandı."
