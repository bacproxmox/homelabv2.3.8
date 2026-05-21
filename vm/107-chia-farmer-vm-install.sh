#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/utils/logging.sh"
start_log "vm-107-chia-farmer"
source "$REPO_ROOT/lib/vm-cloudinit-common.sh"

find_nvidia_gpu() {
  lspci -Dnn | awk '/VGA compatible controller|3D controller/ && /NVIDIA/ {print $1; exit}'
}
find_nvidia_audio_for_gpu() {
  local gpu="$1" base audio
  base="${gpu%.*}"
  audio="${base}.1"
  if lspci -Dnn | awk '{print $1}' | grep -Fxq "$audio" && lspci -Dnn -s "$audio" | grep -qi 'NVIDIA.*Audio'; then
    echo "$audio"
  fi
}
attach_nvidia_to_vm107() {
  local gpu audio short audio_short
  gpu="$(find_nvidia_gpu || true)"
  if [[ -z "$gpu" ]]; then
    echo "⚠️ NVIDIA GPU detect edilemedi. VM107 GPU passthrough atlandı."
    return 0
  fi
  short="${gpu#0000:}"
  echo "🌱 VM107 NVIDIA GPU passthrough ekleniyor: $short"
  qm set 107 --hostpci0 "$short,pcie=1" || {
    echo "⚠️ VM107 NVIDIA GPU passthrough eklenemedi. Sonradan repair script kullan: maintenance/repair/repair-gpu-passthrough.sh"
    return 0
  }
  audio="$(find_nvidia_audio_for_gpu "$gpu" || true)"
  if [[ -n "$audio" ]]; then
    audio_short="${audio#0000:}"
    echo "🔊 VM107 NVIDIA audio function passthrough deneniyor: $audio_short"
    qm set 107 --hostpci1 "$audio_short,pcie=1" || echo "⚠️ NVIDIA audio eklenemedi; CUDA için çoğu senaryoda kritik değil."
  fi
}

AUTO_START=0
create_ubuntu_vm 107 "chia-farmer" "192.168.50.107/24" 16384 6 320G "yes" "none"
attach_nvidia_to_vm107

if [[ "${AUTO_START_AFTER_GPU:-1}" == "1" ]]; then
  qm start 107 || true
  wait_for_agent 107 80
fi

echo "✅ VM107 hazır. NVIDIA driver/CUDA validation Phase 4 veya GPU repair ile yapılacak."
