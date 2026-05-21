#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/env-loader.sh"
source "$SCRIPT_DIR/../../utils/logging.sh"
start_log "vm-resource-audit"
load_all_env

check_vm() {
  local vmid="$1" name="$2" expected_mem="$3" expected_cores="$4"
  echo
  echo "🖥️ VM $vmid / $name"
  if ! qm status "$vmid" >/dev/null 2>&1; then echo "❌ VM yok"; return 1; fi
  qm config "$vmid" | sed 's/^/  /'
  mem="$(qm config "$vmid" | awk '/^memory:/ {print $2}')"
  cores="$(qm config "$vmid" | awk '/^cores:/ {print $2}')"
  [[ "$mem" == "$expected_mem" ]] && echo "✅ RAM doğru: $mem MB" || echo "⚠️ RAM beklenen $expected_mem MB, mevcut $mem MB"
  [[ "$cores" == "$expected_cores" ]] && echo "✅ Core doğru: $cores" || echo "⚠️ Core beklenen $expected_cores, mevcut $cores"
}

check_vm 101 truenas 16384 4 || true
check_vm 102 docker-arr 16384 6 || true
check_vm 103 docker-network 4096 2 || true
check_vm 104 nextcloud 8192 4 || true
check_vm 105 homeassistant 4096 2 || true
check_vm 106 docker-media 32768 8 || true
check_vm 107 chia-farmer 16384 6 || true

echo
if qm config 106 | grep -qE '^hostpci'; then
  echo "✅ VM106 PCI passthrough satırı var:"
  qm config 106 | grep -E '^hostpci' | sed 's/^/  /'
else
  echo "⚠️ VM106 hostpci satırı yok. iGPU passthrough için: bash gpu/attach-igpu-to-vm106.sh"
fi
