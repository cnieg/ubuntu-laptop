#!/usr/bin/env bash
set -euo pipefail


log() {
  echo "[configure-system-optimizations] $*"
}

run_critical_step() {
  local step_name="$1"
  shift

  log "START critical step: ${step_name}"
  if "$@"; then
    log "DONE critical step: ${step_name}"
  else
    local exit_code=$?
    log "ERROR critical step failed: ${step_name} (exit=${exit_code})"
    exit "$exit_code"
  fi
}

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

run_critical_step "update-grub" update-grub

touch /etc/cloud/cloud-init.disabled

if dpkg -s unattended-upgrades >/dev/null 2>&1; then
  systemctl enable unattended-upgrades.service || true
fi

if dpkg -s locales >/dev/null 2>&1; then
  locale-gen fr_FR.UTF-8 || true
  update-locale LANG=fr_FR.UTF-8 || true
fi

if command -v snap >/dev/null 2>&1; then
  snap set system refresh.timer=02:00-04:00 || true
fi
