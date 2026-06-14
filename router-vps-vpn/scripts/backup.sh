#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
OUT="/root/router-vps-vpn-backup-${TS}.tar.gz"

tar -czf "$OUT" \
  /etc/wireguard 2>/dev/null || true

if [[ -d /opt/AdGuardHome ]]; then
  tar -rzf "$OUT" /opt/AdGuardHome 2>/dev/null || true
fi

echo "Backup created: $OUT"
