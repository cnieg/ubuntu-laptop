#!/usr/bin/env bash
set -euxo pipefail

TARGET="/target"

if ! btrfs subvolume show "$TARGET/@snapshots" >/dev/null 2>&1; then
  btrfs subvolume create "$TARGET/@snapshots"
fi

ROOT_UUID="$(findmnt -no UUID /target)"
BOOT_UUID="$(blkid -s UUID -o value /dev/nvme0n1p2)"
EFI_UUID="$(blkid -s UUID -o value /dev/nvme0n1p1)"
SWAP_UUID="$(blkid -s UUID -o value /dev/nvme0n1p3)"

cat > "$TARGET/etc/fstab" <<EOF
UUID=${BOOT_UUID} /boot ext4 defaults 0 1
UUID=${EFI_UUID} /boot/efi vfat umask=0077 0 1
UUID=${SWAP_UUID} none swap sw 0 0
UUID=${ROOT_UUID} / btrfs defaults,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /.snapshots btrfs subvol=@snapshots,compress=zstd,noatime,ssd,space_cache=v2 0 0
EOF
