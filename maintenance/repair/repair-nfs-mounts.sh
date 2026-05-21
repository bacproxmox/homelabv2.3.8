#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-nfs-mounts"
source "$ROOT_DIR/utils/remote.sh"
for vm in 102 104 106; do
  echo "▶️ VM$vm mount repair"
  rssh "$vm" "sudo systemctl daemon-reload; sudo mount -a || true; df -h | egrep 'mnt|Filesystem' || true"
done
