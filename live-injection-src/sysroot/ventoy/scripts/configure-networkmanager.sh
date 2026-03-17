#!/usr/bin/env bash
set -euo pipefail

rm -f /etc/netplan/*.yaml

cat > /etc/netplan/01-nm.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF

chmod 600 /etc/netplan/01-nm.yaml

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-backend.conf <<EOF
[device]
wifi.backend=iwd
EOF

systemctl enable NetworkManager
systemctl enable iwd

systemctl disable systemd-networkd || true
systemctl mask systemd-networkd || true
systemctl disable wpa_supplicant || true
systemctl mask wpa_supplicant || true

# Eviter les boots lents
systemctl disable NetworkManager-wait-online.service || true
systemctl mask NetworkManager-wait-online.service || true
