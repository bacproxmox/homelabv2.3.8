#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-gpu-passthrough"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/lib/vm-cloudinit-common.sh"

find_intel_igpu(){ lspci -Dnn | awk '/VGA compatible controller|Display controller|3D controller/ && /Intel/ && /UHD Graphics|Raptor Lake|Alder Lake|Integrated Graphics/ {print $1; exit}'; }
find_nvidia_gpu(){ lspci -Dnn | awk '/VGA compatible controller|3D controller/ && /NVIDIA/ {print $1; exit}'; }
find_nvidia_audio(){ local gpu="$1" base audio; base="${gpu%.*}"; audio="${base}.1"; lspci -Dnn -s "$audio" | grep -qi 'NVIDIA.*Audio' && echo "$audio" || true; }

stop_if_running(){ local vm="$1"; if qm status "$vm" 2>/dev/null | grep -q running; then qm shutdown "$vm" --timeout 60 || qm stop "$vm" || true; fi; }
start_and_wait(){ local vm="$1"; qm start "$vm" || true; wait_for_agent "$vm" 80; wait_ssh "$vm" || true; }

attach_vm106(){
  local pci short
  pci="$(find_intel_igpu || true)"
  [[ -n "$pci" ]] || { echo "❌ Intel iGPU bulunamadı."; return 1; }
  short="${pci#0000:}"
  echo "🎬 VM106 iGPU attach: $short"
  stop_if_running 106
  qm set 106 --hostpci0 "$short,pcie=1"
  start_and_wait 106
}

fix_vm106_driver(){
  echo "🔧 VM106 i915/linux modules kontrolü..."
  wait_ssh 106
  rssh 106 'sudo bash -lc "set -e; apt-get update; apt-get install -y linux-generic linux-firmware vainfo intel-media-va-driver-non-free intel-gpu-tools; apt-get install -y linux-modules-extra-$(uname -r) || true"'
  if ! rssh 106 'modinfo i915 >/dev/null 2>&1'; then
    echo "⚠️ Aktif kernelde i915 yok. VM106 reboot sonrası yeni kernel deneniyor..."
    rssh 106 'sudo reboot' || true
    sleep 10
    wait_ssh 106
  fi
  rssh 106 'sudo modprobe i915 || true; ls -lah /dev/dri || true; sudo lspci -nnk | grep -A3 -Ei "Raptor Lake-S UHD|UHD Graphics|i915" || true; vainfo --display drm --device /dev/dri/renderD128 || true'
}

attach_vm107(){
  local gpu audio short audio_short
  gpu="$(find_nvidia_gpu || true)"
  [[ -n "$gpu" ]] || { echo "❌ NVIDIA GPU bulunamadı."; return 1; }
  short="${gpu#0000:}"
  echo "🌱 VM107 NVIDIA attach: $short"
  stop_if_running 107
  qm set 107 --hostpci0 "$short,pcie=1"
  audio="$(find_nvidia_audio "$gpu" || true)"
  if [[ -n "$audio" ]]; then
    audio_short="${audio#0000:}"
    qm set 107 --hostpci1 "$audio_short,pcie=1" || echo "⚠️ NVIDIA audio attach atlandı/başarısız."
  fi
  start_and_wait 107
}

fix_vm107_driver(){
  echo "🔧 VM107 NVIDIA driver kontrolü..."
  wait_ssh 107
  rssh 107 'lspci -nn | grep -Ei "nvidia|vga|3d" || true'
  if ! rssh 107 'command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1'; then
    echo "⚠️ nvidia-smi çalışmıyor. ubuntu-drivers autoinstall deneniyor..."
    rssh 107 'sudo bash -lc "apt-get update; apt-get install -y ubuntu-drivers-common linux-headers-$(uname -r); ubuntu-drivers autoinstall || true"'
    echo "ℹ️ NVIDIA driver sonrası VM107 reboot gerekebilir."
  fi
  rssh 107 'nvidia-smi || true'
}

echo "🧪 GPU passthrough repair başlıyor..."
attach_vm106 || true
fix_vm106_driver || true
attach_vm107 || true
fix_vm107_driver || true

echo "✅ GPU passthrough repair tamamlandı."
