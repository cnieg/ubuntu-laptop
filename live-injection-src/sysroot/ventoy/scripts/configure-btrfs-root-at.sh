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

ROOT_DEV="$(detect_root_source /target)"
ROOT_UUID="$(detect_root_uuid /target)"

BOOT_DEV="$(findmnt -no SOURCE /target/boot)"
EFI_DEV="$(findmnt -no SOURCE /target/boot/efi)"

BOOT_UUID="$(blkid -s UUID -o value "$BOOT_DEV")"
EFI_UUID="$(blkid -s UUID -o value "$EFI_DEV")"
SWAP_UUID="$(detect_swap_uuid)"

if [ -z "$ROOT_DEV" ] || [ ! -e "$ROOT_DEV" ]; then
  fail_device_discovery "unable to resolve root device for /target"
  exit 1
fi

if [ -z "$ROOT_UUID" ]; then
  fail_device_discovery "unable to resolve root UUID for /target"
  exit 1
fi

if [ "$SWAP_UUID" = "none" ] || [ -z "$SWAP_UUID" ]; then
  fail_device_discovery "unable to resolve swap UUID; refusing to generate fstab"
  exit 1
fi

mkdir -p "$TOP"
mount -o subvolid=5 "$ROOT_DEV" "$TOP"

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
UUID=${SWAP_UUID} none swap sw 0 0
UUID=${ROOT_UUID} / btrfs subvol=@,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /home btrfs subvol=@home,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /var/log btrfs subvol=@var_log,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /var/cache btrfs subvol=@var_cache,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /.snapshots btrfs subvol=@snapshots,compress=zstd,noatime,ssd,space_cache=v2 0 0
EOF

if grep -q '^GRUB_CMDLINE_LINUX=' "$TOP/@/etc/default/grub"; then
  sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="rootflags=subvol=@"/' \
    "$TOP/@/etc/default/grub"
else
  echo 'GRUB_CMDLINE_LINUX="rootflags=subvol=@"' >> "$TOP/@/etc/default/grub"
fi

mount --bind /dev  "$TOP/@/dev"
mount --bind /proc "$TOP/@/proc"
mount --bind /sys  "$TOP/@/sys"

run_critical_step "update-grub" chroot "$TOP/@" update-grub
run_critical_step "update-initramfs -u -k all" chroot "$TOP/@" update-initramfs -u -k all

umount "$TOP/@/dev" || true
umount "$TOP/@/proc" || true
umount "$TOP/@/sys" || true
umount "$TOP"

sync
