#!/usr/bin/env bash
set -Eeuo pipefail
OUT="/root/homelab-support-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
chmod 700 "$OUT"

echo "📦 Support bundle hazırlanıyor: $OUT"
{
  echo "date=$(date -Is)"
  uname -a
  ip a
  ip r
  df -h
  lsblk -f
  command -v qm >/dev/null && qm list || true
  command -v pvesm >/dev/null && pvesm status || true
} > "$OUT/system.txt" 2>&1

journalctl -n 500 --no-pager > "$OUT/journal-last500.txt" 2>&1 || true
cp -a /root/homelab-logs "$OUT/homelab-logs" 2>/dev/null || true
cp -a /root/homelab-state "$OUT/homelab-state" 2>/dev/null || true
find /opt/homelab -maxdepth 3 \( -name 'docker-compose.yml' -o -name '.env' \) -print -exec cp --parents {} "$OUT" \; 2>/dev/null || true

tar -czf "$OUT.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo "✅ Oluşturuldu: $OUT.tar.gz"
