#!/usr/bin/env bash
set -euo pipefail

echo "== WireGuard =="
systemctl --no-pager --full status wg-quick@wg0 || true
wg show || true

echo ""
echo "== AdGuard Home =="
systemctl --no-pager --full status AdGuardHome || true

echo ""
echo "== Firewall =="
ufw status verbose || true

echo ""
echo "== Public IP =="
curl -4fsS https://api.ipify.org || true
echo
