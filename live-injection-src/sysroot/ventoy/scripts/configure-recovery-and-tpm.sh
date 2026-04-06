#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/device-discovery.sh"

ROOT_PART="$(detect_root_partition /)"
if [ -z "$ROOT_PART" ] || [ ! -b "$ROOT_PART" ]; then
  fail_device_discovery "detected root partition is invalid: ${ROOT_PART:-<empty>}"
  exit 1
fi

install -d -m 0700 /root/recovery
umask 077
openssl rand -out /root/recovery/luks-root-recovery.key 32

cryptsetup luksAddKey "$ROOT_PART" /root/recovery/luks-root-recovery.key || true

if command -v systemd-cryptenroll >/dev/null 2>&1; then
  systemd-cryptenroll --tpm2-device=auto "$ROOT_PART" || true
fi
