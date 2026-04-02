#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[configure-recovery-and-tpm] $*"
}

ensure_line_in_file() {
  local file="$1"
  local key="$2"
  local line="$3"

  touch "$file"
  if grep -qE "^${key}[[:space:]]" "$file"; then
    sed -i "s|^${key}[[:space:]].*|${line}|" "$file"
  else
    echo "$line" >> "$file"
  fi
}

ROOT_MAPPER="$(findmnt -no SOURCE / || true)"
ROOT_NAME="${ROOT_MAPPER#/dev/mapper/}"
ROOT_PART=""

if [ -n "$ROOT_NAME" ] && [ "$ROOT_NAME" != "$ROOT_MAPPER" ] && command -v cryptsetup >/dev/null 2>&1; then
  ROOT_PART="$(cryptsetup status "$ROOT_NAME" 2>/dev/null | awk '/device:/ {print $2; exit}')"
fi

if [ -z "$ROOT_PART" ] || [ ! -b "$ROOT_PART" ]; then
  log "WARNING: unable to detect root LUKS device, fallback to /dev/nvme0n1p4"
  ROOT_PART="/dev/nvme0n1p4"
fi

ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART" 2>/dev/null || true)"

install -d -m 0700 /root/recovery
umask 077
if [ ! -f /root/recovery/luks-root-recovery.key ]; then
  openssl rand -out /root/recovery/luks-root-recovery.key 32
fi

if [ -b "$ROOT_PART" ]; then
  cryptsetup luksAddKey "$ROOT_PART" /root/recovery/luks-root-recovery.key || true
fi

if command -v systemd-cryptenroll >/dev/null 2>&1 && [ -b "$ROOT_PART" ]; then
  systemd-cryptenroll --tpm2-device=auto "$ROOT_PART" || true
fi

if [ -n "$ROOT_UUID" ]; then
  ensure_line_in_file /etc/crypttab cryptroot "cryptroot UUID=${ROOT_UUID} none luks,discard"
fi

install -d -m 0700 /etc/cryptsetup-keys.d
SWAP_KEYFILE="/etc/cryptsetup-keys.d/cryptswap.key"
if [ ! -f "$SWAP_KEYFILE" ]; then
  openssl rand -out "$SWAP_KEYFILE" 64
  chmod 0600 "$SWAP_KEYFILE"
fi

SWAP_PART="$(blkid -t TYPE=swap -o device | head -n1 || true)"
if [ -z "$SWAP_PART" ] || [ ! -b "$SWAP_PART" ]; then
  log "WARNING: no swap partition detected; encrypted hibernation will not be configured"
  exit 0
fi

if ! cryptsetup isLuks "$SWAP_PART" >/dev/null 2>&1; then
  swapoff -a || true
  cryptsetup luksFormat --batch-mode "$SWAP_PART" "$SWAP_KEYFILE"
fi

if [ ! -b /dev/mapper/cryptswap ]; then
  cryptsetup open "$SWAP_PART" cryptswap --key-file "$SWAP_KEYFILE"
fi

mkswap /dev/mapper/cryptswap
swapon /dev/mapper/cryptswap || true

SWAP_UUID="$(blkid -s UUID -o value "$SWAP_PART" 2>/dev/null || true)"
if [ -n "$SWAP_UUID" ]; then
  ensure_line_in_file /etc/crypttab cryptswap "cryptswap UUID=${SWAP_UUID} ${SWAP_KEYFILE} luks,discard"
fi

if grep -qE '^[^#].+[[:space:]]none[[:space:]]swap[[:space:]]' /etc/fstab; then
  sed -i 's|^[^#].*[[:space:]]none[[:space:]]swap[[:space:]].*|/dev/mapper/cryptswap none swap sw 0 0|' /etc/fstab
else
  echo '/dev/mapper/cryptswap none swap sw 0 0' >> /etc/fstab
fi

cat > /etc/cryptsetup-initramfs/conf-hook <<'HOOK'
KEYFILE_PATTERN="/etc/cryptsetup-keys.d/*.key"
HOOK

cat > /etc/initramfs-tools/conf.d/resume <<'RESUME'
RESUME=/dev/mapper/cryptswap
RESUME

log "Configured cryptroot/cryptswap, initramfs key inclusion and resume mapping"
