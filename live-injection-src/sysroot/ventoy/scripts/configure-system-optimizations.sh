#!/usr/bin/env bash
set -euo pipefail

# Réduire le timeout GRUB
if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
else
  echo 'GRUB_TIMEOUT=1' >> /etc/default/grub
fi

if grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub; then
  sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
else
  echo 'GRUB_TIMEOUT_STYLE=hidden' >> /etc/default/grub
fi

update-grub || true

# Désactiver cloud-init après installation
touch /etc/cloud/cloud-init.disabled

# Garder les mises à jour de sécurité automatiques
if dpkg -s unattended-upgrades >/dev/null 2>&1; then
  systemctl enable unattended-upgrades.service || true
fi

# Limiter les refresh snap à midi si snap est présent
if command -v snap >/dev/null 2>&1; then
  snap set system refresh.timer=12:00-14:00 || true
fi
