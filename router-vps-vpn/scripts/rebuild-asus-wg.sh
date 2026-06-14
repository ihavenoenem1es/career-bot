#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p client backups

VPS_IP="${VPS_IP:-$(curl -4fsS https://api.ipify.org || true)}"
if [[ -z "${VPS_IP}" ]]; then
  echo "Не смог определить внешний IP. Укажи VPS_IP=... перед запуском."
  exit 1
fi

PUBLIC_NIC="${PUBLIC_NIC:-$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')}"
if [[ -z "${PUBLIC_NIC}" ]]; then
  echo "Не смог определить внешний интерфейс. Укажи PUBLIC_NIC=ens3 перед запуском."
  exit 1
fi

PORT="${WG_PORT:-443}"
SERVER_ADDR="10.44.0.1/24"
CLIENT_ADDR="10.44.0.2/32"
SUBNET="10.44.0.0/24"

if [[ -f /etc/wireguard/wg0.conf ]]; then
  cp /etc/wireguard/wg0.conf "backups/wg0.conf.$(date +%Y%m%d-%H%M%S)"
  # keep existing server private key if present
  SERVER_PRIVATE="$(awk -F'= ' '/^PrivateKey/ {print $2; exit}' /etc/wireguard/wg0.conf || true)"
else
  SERVER_PRIVATE=""
fi

if [[ -z "${SERVER_PRIVATE}" ]]; then
  SERVER_PRIVATE="$(wg genkey)"
fi

SERVER_PUBLIC="$(printf '%s' "$SERVER_PRIVATE" | wg pubkey)"
CLIENT_PRIVATE="$(wg genkey)"
CLIENT_PUBLIC="$(printf '%s' "$CLIENT_PRIVATE" | wg pubkey)"

cat >/etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE
Address = $SERVER_ADDR
ListenPort = $PORT
SaveConfig = false
PostUp = iptables -t nat -C POSTROUTING -s $SUBNET -o $PUBLIC_NIC -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s $SUBNET -o $PUBLIC_NIC -j MASQUERADE; iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i wg0 -j ACCEPT; iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $SUBNET -o $PUBLIC_NIC -j MASQUERADE 2>/dev/null || true; iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true; iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true

[Peer]
PublicKey = $CLIENT_PUBLIC
AllowedIPs = $CLIENT_ADDR
EOF
chmod 600 /etc/wireguard/wg0.conf

cat >/etc/sysctl.d/99-router-vps-vpn.conf <<'EOF'
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
EOF
sysctl --system >/dev/null || true

cat >client/asus-wireguard.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = $CLIENT_ADDR
DNS = 1.1.1.1
MTU = 1380

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = $VPS_IP:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
systemctl restart wg-quick@wg0

echo ""
echo "ГОТОВО: создан новый чистый файл client/asus-wireguard.conf"
echo "Сервер слушает: $VPS_IP:$PORT UDP"
echo "Внешний интерфейс: $PUBLIC_NIC"
echo ""
echo "Содержимое файла:"
echo "----------------------------------------"
cat client/asus-wireguard.conf
echo "----------------------------------------"
echo ""
echo "Чтобы скачать файл без Блокнота, запусти:"
echo "bash scripts/serve-config.sh"
echo ""
wg show
