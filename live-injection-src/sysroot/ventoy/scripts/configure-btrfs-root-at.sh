#!/usr/bin/env bash
set -euxo pipefail

exec > /target/root/configure-btrfs-root-at.log 2>&1

TARGET="/target"
TOP="/mnt/btrfs-top"

ROOT_DEV="$(findmnt -no SOURCE /target)"
ROOT_UUID="$(findmnt -no UUID /target)"

BOOT_DEV="$(findmnt -no SOURCE /target/boot)"
EFI_DEV="$(findmnt -no SOURCE /target/boot/efi)"

BOOT_UUID="$(blkid -s UUID -o value "$BOOT_DEV")"
EFI_UUID="$(blkid -s UUID -o value "$EFI_DEV")"
SWAP_UUID="$(blkid -s UUID -o value /dev/nvme0n1p3)"

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

chroot "$TOP/@" update-grub || true
chroot "$TOP/@" update-initramfs -u -k all || true

umount "$TOP/@/dev" || true
umount "$TOP/@/proc" || true
umount "$TOP/@/sys" || true
umount "$TOP"

sync
