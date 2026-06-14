#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Не найден $ENV_FILE. Скопируй .env.example в .env и заполни при необходимости."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запусти от root. В веб-консоли AEZA ты обычно уже root."
  exit 1
fi

WG_PORT="${WG_PORT:-51820}"
WG_SERVER_ADDRESS="${WG_SERVER_ADDRESS:-10.44.0.1/24}"
WG_SERVER_IP="${WG_SERVER_ADDRESS%/*}"
WG_CLIENT_ADDRESS="${WG_CLIENT_ADDRESS:-10.44.0.2/32}"
CLIENT_NAME="${CLIENT_NAME:-asus-router}"
CLIENT_DNS="${CLIENT_DNS:-$WG_SERVER_IP}"
CLIENT_ALLOWED_IPS="${CLIENT_ALLOWED_IPS:-0.0.0.0/0,::/0}"
CLIENT_PERSISTENT_KEEPALIVE="${CLIENT_PERSISTENT_KEEPALIVE:-25}"
ENABLE_ADGUARD="${ENABLE_ADGUARD:-1}"
INSTALL_ADGUARD="${INSTALL_ADGUARD:-1}"

mkdir -p client backups

VPS_IP="${VPS_IP:-}"
if [[ -z "$VPS_IP" ]]; then
  VPS_IP="$(curl -4fsS https://api.ipify.org || true)"
fi
if [[ -z "$VPS_IP" ]]; then
  echo "Не смог определить внешний IP сервера. Укажи VPS_IP=... в .env"
  exit 1
fi

# Auto-detect public interface by default route. This is safer than hardcoded eth0.
PUBLIC_NIC="${PUBLIC_NIC:-}"
if [[ -z "$PUBLIC_NIC" ]]; then
  PUBLIC_NIC="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
fi
if [[ -z "$PUBLIC_NIC" ]]; then
  echo "Не смог определить внешний сетевой интерфейс. Укажи PUBLIC_NIC=... в .env"
  exit 1
fi

WG_SUBNET="${WG_SERVER_ADDRESS%.*}.0/24"

echo "==> VPS IP: $VPS_IP"
echo "==> Публичный интерфейс: $PUBLIC_NIC"
echo "==> WireGuard subnet: $WG_SUBNET"
echo "==> OpenVPN/Tailscale не трогаем. UFW/iptables-persistent специально НЕ ставим."

apt update
# Do not install ufw, iptables-persistent or netfilter-persistent here.
# They conflict on some Ubuntu 24.04 servers with existing OpenVPN/Tailscale setups.
DEBIAN_FRONTEND=noninteractive apt install -y wireguard iptables curl wget qrencode dnsutils ca-certificates

if [[ -f /etc/wireguard/wg0.conf ]]; then
  cp /etc/wireguard/wg0.conf "backups/wg0.conf.$(date +%Y%m%d-%H%M%S)"
  echo "==> Найден старый /etc/wireguard/wg0.conf, сделал backup в ./backups"
fi

SERVER_PRIVATE_KEY="$(wg genkey)"
SERVER_PUBLIC_KEY="$(printf '%s' "$SERVER_PRIVATE_KEY" | wg pubkey)"
CLIENT_PRIVATE_KEY="$(wg genkey)"
CLIENT_PUBLIC_KEY="$(printf '%s' "$CLIENT_PRIVATE_KEY" | wg pubkey)"
CLIENT_PSK="$(wg genpsk)"

cat >/etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $WG_SERVER_ADDRESS
ListenPort = $WG_PORT
SaveConfig = false
PostUp = iptables -t nat -C POSTROUTING -s $WG_SUBNET -o $PUBLIC_NIC -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s $WG_SUBNET -o $PUBLIC_NIC -j MASQUERADE; iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i wg0 -j ACCEPT; iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -s $WG_SUBNET -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -s $WG_SUBNET -j TCPMSS --clamp-mss-to-pmtu
PostDown = iptables -t nat -D POSTROUTING -s $WG_SUBNET -o $PUBLIC_NIC -j MASQUERADE 2>/dev/null || true; iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true; iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true; iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -s $WG_SUBNET -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true

[Peer]
# $CLIENT_NAME
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $CLIENT_PSK
AllowedIPs = ${WG_CLIENT_ADDRESS}
EOF
chmod 600 /etc/wireguard/wg0.conf

cat >/etc/sysctl.d/99-router-vps-vpn.conf <<'EOF'
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
EOF
sysctl --system >/dev/null || true

systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

if [[ "$ENABLE_ADGUARD" == "1" && "$INSTALL_ADGUARD" == "1" ]]; then
  if ! command -v AdGuardHome >/dev/null 2>&1 && [[ ! -x /opt/AdGuardHome/AdGuardHome ]]; then
    echo "==> Ставлю AdGuard Home"
    curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | bash || echo "AdGuard Home не установился автоматически, VPN всё равно готов."
  fi
  systemctl enable AdGuardHome 2>/dev/null || true
  systemctl restart AdGuardHome 2>/dev/null || true
fi

cat >"client/${CLIENT_NAME}.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = ${WG_CLIENT_ADDRESS}
DNS = $CLIENT_DNS
MTU = 1420

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $CLIENT_PSK
Endpoint = $VPS_IP:$WG_PORT
AllowedIPs = $CLIENT_ALLOWED_IPS
PersistentKeepalive = $CLIENT_PERSISTENT_KEEPALIVE
EOF
cp "client/${CLIENT_NAME}.conf" client/asus-wireguard.conf

cat > client/README-client.txt <<EOF
Это конфиг для ASUS WireGuard Client / VPN Fusion.
Открой файл client/asus-wireguard.conf и вставь его в ASUS.
Endpoint уже заполнен: $VPS_IP:$WG_PORT
DNS внутри VPN: $CLIENT_DNS
EOF

qrencode -t ansiutf8 < client/asus-wireguard.conf || true

echo ""
echo "ГОТОВО. Конфиг ASUS:"
echo "----------------------------------------"
cat client/asus-wireguard.conf
echo "----------------------------------------"
echo "Проверка сервера: wg show"
wg show
