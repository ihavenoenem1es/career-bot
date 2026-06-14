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

PUBLIC_NIC="${PUBLIC_NIC:-eth0}"
WG_PORT="${WG_PORT:-51820}"
WG_SERVER_ADDRESS="${WG_SERVER_ADDRESS:-10.44.0.1/24}"
WG_SERVER_IP="${WG_SERVER_ADDRESS%/*}"
WG_CLIENT_ADDRESS="${WG_CLIENT_ADDRESS:-10.44.0.2/32}"
CLIENT_NAME="${CLIENT_NAME:-asus-router}"
CLIENT_DNS="${CLIENT_DNS:-$WG_SERVER_IP}"
CLIENT_ALLOWED_IPS="${CLIENT_ALLOWED_IPS:-0.0.0.0/0,::/0}"
CLIENT_PERSISTENT_KEEPALIVE="${CLIENT_PERSISTENT_KEEPALIVE:-25}"
SSH_PORT="${SSH_PORT:-22}"
ENABLE_ADGUARD="${ENABLE_ADGUARD:-1}"
AGH_UPSTREAM_DNS="${AGH_UPSTREAM_DNS:-https://dns10.quad9.net/dns-query}"
AGH_BOOTSTRAP_DNS="${AGH_BOOTSTRAP_DNS:-1.1.1.1}"

mkdir -p client backups

VPS_IP="${VPS_IP:-}"
if [[ -z "$VPS_IP" ]]; then
  VPS_IP="$(curl -4fsS https://api.ipify.org || true)"
fi
if [[ -z "$VPS_IP" ]]; then
  echo "Не смог определить внешний IP сервера. Укажи VPS_IP=... в .env"
  exit 1
fi

echo "==> VPS IP: $VPS_IP"
echo "==> Публичный интерфейс: $PUBLIC_NIC"

apt update
DEBIAN_FRONTEND=noninteractive apt install -y wireguard iptables iptables-persistent curl wget qrencode dnsutils ufw ca-certificates

# Backup existing WireGuard config if present
if [[ -f /etc/wireguard/wg0.conf ]]; then
  cp /etc/wireguard/wg0.conf "backups/wg0.conf.$(date +%Y%m%d-%H%M%S)"
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
PostUp = iptables -t nat -A POSTROUTING -s ${WG_SERVER_ADDRESS%.*}.0/24 -o $PUBLIC_NIC -j MASQUERADE; iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -s ${WG_SERVER_ADDRESS%.*}.0/24 -j TCPMSS --clamp-mss-to-pmtu
PostDown = iptables -t nat -D POSTROUTING -s ${WG_SERVER_ADDRESS%.*}.0/24 -o $PUBLIC_NIC -j MASQUERADE; iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -s ${WG_SERVER_ADDRESS%.*}.0/24 -j TCPMSS --clamp-mss-to-pmtu

[Peer]
# $CLIENT_NAME
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $CLIENT_PSK
AllowedIPs = ${WG_CLIENT_ADDRESS}
EOF
chmod 600 /etc/wireguard/wg0.conf

# IPv4 forwarding and speed tuning
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

ufw allow "${SSH_PORT}/tcp" || true
ufw allow "${WG_PORT}/udp" || true
if [[ "$ENABLE_ADGUARD" == "1" ]]; then
  ufw allow from "${WG_SERVER_ADDRESS%.*}.0/24" to any port 53 proto tcp || true
  ufw allow from "${WG_SERVER_ADDRESS%.*}.0/24" to any port 53 proto udp || true
  ufw allow "3000/tcp" || true
fi
ufw --force enable || true

systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

# Install AdGuard Home best-effort
if [[ "$ENABLE_ADGUARD" == "1" ]]; then
  if ! command -v AdGuardHome >/dev/null 2>&1 && [[ ! -x /opt/AdGuardHome/AdGuardHome ]]; then
    curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | bash
  fi
  systemctl enable AdGuardHome || true
  systemctl restart AdGuardHome || true
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
