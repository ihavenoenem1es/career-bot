#!/usr/bin/env bash
set -euo pipefail

echo "Останавливаю только WireGuard wg0. OpenVPN родителей не трогаю."
systemctl stop wg-quick@wg0 || true
systemctl disable wg-quick@wg0 || true

echo "Конфиг /etc/wireguard/wg0.conf НЕ удаляю автоматически."
echo "Если нужно удалить вручную: rm /etc/wireguard/wg0.conf"
echo "AdGuard Home тоже не удаляю автоматически, чтобы не потерять настройки DNS."
