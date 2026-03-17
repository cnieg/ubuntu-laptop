#!/usr/bin/env bash
set -euxo pipefail

exec > /target/root/configure-btrfs.log 2>&1

TARGET="/target"

ROOT_UUID="$(findmnt -no UUID /target)"
BOOT_UUID="$(blkid -s UUID -o value /dev/nvme0n1p2)"
EFI_UUID="$(blkid -s UUID -o value /dev/nvme0n1p1)"
SWAP_UUID="$(blkid -s UUID -o value /dev/nvme0n1p3)"

echo "ROOT_UUID=$ROOT_UUID"

echo "=== before ==="
mount | grep target || true
btrfs subvolume list "$TARGET" || true
ls -la "$TARGET" || true

for sv in @home @var_log @var_cache @snapshots; do
  if ! btrfs subvolume show "$TARGET/$sv" >/dev/null 2>&1; then
    btrfs subvolume create "$TARGET/$sv"
  fi
done

mkdir -p "$TARGET/.snapshots"

if [ -d "$TARGET/home" ]; then
  rsync -aAXH --numeric-ids "$TARGET/home/" "$TARGET/@home/" || true
fi

if [ -d "$TARGET/var/log" ]; then
  rsync -aAXH --numeric-ids "$TARGET/var/log/" "$TARGET/@var_log/" || true
fi

if [ -d "$TARGET/var/cache" ]; then
  rsync -aAXH --numeric-ids "$TARGET/var/cache/" "$TARGET/@var_cache/" || true
fi

cat > "$TARGET/etc/fstab" <<EOF
UUID=${BOOT_UUID} /boot ext4 defaults 0 1
UUID=${EFI_UUID} /boot/efi vfat umask=0077 0 1
UUID=${SWAP_UUID} none swap sw 0 0
UUID=${ROOT_UUID} / btrfs subvolid=5,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /home btrfs subvol=@home,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /var/log btrfs subvol=@var_log,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /var/cache btrfs subvol=@var_cache,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /.snapshots btrfs subvol=@snapshots,compress=zstd,noatime,ssd,space_cache=v2 0 0
EOF

echo "=== after ==="
btrfs subvolume list "$TARGET" || true
cat "$TARGET/etc/fstab" || true

sync
