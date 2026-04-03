#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/device-discovery.sh"

exec > /target/root/configure-btrfs-root-at.log 2>&1


log() {
  echo "[configure-btrfs-root-at] $*"
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

TARGET="/target"
TOP="/mnt/btrfs-top"
CRYPTSWAP_NAME="cryptswap"
CRYPTSWAP_KEYFILE="/etc/cryptsetup-keys.d/cryptswap.key"

ROOT_DEV="$(detect_root_source /target)"
ROOT_UUID="$(detect_root_uuid /target)"
SWAP_PART="$(extract_swap_device_from_fstab /target/etc/fstab)"

BOOT_DEV="$(findmnt -no SOURCE /target/boot)"
EFI_DEV="$(findmnt -no SOURCE /target/boot/efi)"

BOOT_UUID="$(blkid -s UUID -o value "$BOOT_DEV")"
EFI_UUID="$(blkid -s UUID -o value "$EFI_DEV")"

if [ -z "$ROOT_DEV" ] || [ ! -e "$ROOT_DEV" ]; then
  fail_device_discovery "unable to resolve root device for /target"
  exit 1
fi

if [ -z "$ROOT_UUID" ]; then
  fail_device_discovery "unable to resolve root UUID for /target"
  exit 1
fi

if [ -z "$SWAP_PART" ] || [ ! -b "$SWAP_PART" ]; then
  fail_device_discovery "unable to resolve swap partition from /target/etc/fstab"
  exit 1
fi

mkdir -p "$TOP"
mount -o subvolid=5 "$ROOT_DEV" "$TOP"

install -d -m 0700 "$TOP/@/etc/cryptsetup-keys.d"
if [ ! -f "$TOP/@${CRYPTSWAP_KEYFILE}" ]; then
  umask 0077
  dd if=/dev/urandom of="$TOP/@${CRYPTSWAP_KEYFILE}" bs=64 count=1 status=none
fi

SWAP_TYPE="$(blkid -s TYPE -o value "$SWAP_PART" 2>/dev/null || true)"
if [ "$SWAP_TYPE" != "crypto_LUKS" ]; then
  log "Formatting swap partition with LUKS2: $SWAP_PART"
  cryptsetup luksFormat --type luks2 --batch-mode "$SWAP_PART" "$TOP/@${CRYPTSWAP_KEYFILE}"
fi

if [ ! -e "/dev/mapper/${CRYPTSWAP_NAME}" ]; then
  cryptsetup open "$SWAP_PART" "$CRYPTSWAP_NAME" --key-file "$TOP/@${CRYPTSWAP_KEYFILE}"
fi

mkswap "/dev/mapper/${CRYPTSWAP_NAME}" >/dev/null
SWAP_UUID="$(blkid -s UUID -o value "/dev/mapper/${CRYPTSWAP_NAME}")"
SWAP_LUKS_UUID="$(blkid -s UUID -o value "$SWAP_PART")"

if [ -z "$SWAP_UUID" ] || [ -z "$SWAP_LUKS_UUID" ]; then
  fail_device_discovery "unable to resolve encrypted swap identifiers"
  exit 1
fi

for sv in @ @home @var_log @var_cache @snapshots; do
  if ! btrfs subvolume show "$TOP/$sv" >/dev/null 2>&1; then
    btrfs subvolume create "$TOP/$sv"
  fi
done

mkdir -p \
  "$TOP/@/boot" \
  "$TOP/@/boot/efi" \
  "$TOP/@/home" \
  "$TOP/@/var" \
  "$TOP/@/var/log" \
  "$TOP/@/var/cache" \
  "$TOP/@/.snapshots"

rsync -aAXH --numeric-ids \
  --exclude='/@' \
  --exclude='/@home' \
  --exclude='/@var_log' \
  --exclude='/@var_cache' \
  --exclude='/@snapshots' \
  /target/ "$TOP/@/"

if [ -d /target/home ]; then
  rsync -aAXH --numeric-ids /target/home/ "$TOP/@home/" || true
fi

if [ -d /target/var/log ]; then
  rsync -aAXH --numeric-ids /target/var/log/ "$TOP/@var_log/" || true
fi

if [ -d /target/var/cache ]; then
  rsync -aAXH --numeric-ids /target/var/cache/ "$TOP/@var_cache/" || true
fi

cat > "$TOP/@/etc/fstab" <<EOF
UUID=${BOOT_UUID} /boot ext4 defaults 0 1
UUID=${EFI_UUID} /boot/efi vfat umask=0077 0 1
/dev/mapper/${CRYPTSWAP_NAME} none swap sw 0 0
UUID=${ROOT_UUID} / btrfs subvol=@,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /home btrfs subvol=@home,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /var/log btrfs subvol=@var_log,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /var/cache btrfs subvol=@var_cache,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /.snapshots btrfs subvol=@snapshots,compress=zstd,noatime,ssd,space_cache=v2 0 0
EOF

cat > "$TOP/@/etc/crypttab" <<EOF
cryptroot UUID=${ROOT_UUID} none luks,discard,tpm2-device=auto
${CRYPTSWAP_NAME} UUID=${SWAP_LUKS_UUID} ${CRYPTSWAP_KEYFILE} luks,discard
EOF

install -d -m 0755 "$TOP/@/etc/initramfs-tools/conf.d"
cat > "$TOP/@/etc/initramfs-tools/conf.d/resume" <<EOF
RESUME=/dev/mapper/${CRYPTSWAP_NAME}
EOF

install -d -m 0755 "$TOP/@/etc/cryptsetup-initramfs"
if [ -f "$TOP/@/etc/cryptsetup-initramfs/conf-hook" ]; then
  if grep -q '^KEYFILE_PATTERN=' "$TOP/@/etc/cryptsetup-initramfs/conf-hook"; then
    sed -i 's|^KEYFILE_PATTERN=.*|KEYFILE_PATTERN="/etc/cryptsetup-keys.d/*.key"|' \
      "$TOP/@/etc/cryptsetup-initramfs/conf-hook"
  else
    echo 'KEYFILE_PATTERN="/etc/cryptsetup-keys.d/*.key"' >> "$TOP/@/etc/cryptsetup-initramfs/conf-hook"
  fi
else
  cat > "$TOP/@/etc/cryptsetup-initramfs/conf-hook" <<EOF
KEYFILE_PATTERN="/etc/cryptsetup-keys.d/*.key"
EOF
fi

GRUB_LINUX_ARGS="rootflags=subvol=@ resume=/dev/mapper/${CRYPTSWAP_NAME}"
if grep -q '^GRUB_CMDLINE_LINUX=' "$TOP/@/etc/default/grub"; then
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${GRUB_LINUX_ARGS}\"|" \
    "$TOP/@/etc/default/grub"
else
  echo "GRUB_CMDLINE_LINUX=\"${GRUB_LINUX_ARGS}\"" >> "$TOP/@/etc/default/grub"
fi

mount --bind /dev  "$TOP/@/dev"
mount --bind /proc "$TOP/@/proc"
mount --bind /sys  "$TOP/@/sys"

run_critical_step "update-grub" chroot "$TOP/@" update-grub
run_critical_step "update-initramfs -u -k all" chroot "$TOP/@" update-initramfs -u -k all

umount "$TOP/@/dev" || true
umount "$TOP/@/proc" || true
umount "$TOP/@/sys" || true
cryptsetup close "${CRYPTSWAP_NAME}" || true
umount "$TOP"

sync
