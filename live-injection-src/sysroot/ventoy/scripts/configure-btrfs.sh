#!/usr/bin/env bash
set -euxo pipefail

exec > /target/root/configure-btrfs.log 2>&1

TARGET="/target"

# créer subvolumes
for sv in @ @home @var_log @var_cache @snapshots; do
    if ! btrfs subvolume show "$TARGET/$sv" >/dev/null 2>&1; then
        btrfs subvolume create "$TARGET/$sv"
    fi
done

mkdir -p "$TARGET/.snapshots"

# migration root
rsync -aAXH --numeric-ids "$TARGET/" "$TARGET/@/" \
  --exclude=@ --exclude=@home --exclude=@var_log --exclude=@var_cache --exclude=@snapshots

# migration home
if [ -d "$TARGET/home" ]; then
    rsync -aAXH "$TARGET/home/" "$TARGET/@home/"
fi

# migration logs
if [ -d "$TARGET/var/log" ]; then
    rsync -aAXH "$TARGET/var/log/" "$TARGET/@var_log/"
fi

# migration cache
if [ -d "$TARGET/var/cache" ]; then
    rsync -aAXH "$TARGET/var/cache/" "$TARGET/@var_cache/"
fi

ROOT_UUID="$(findmnt -no UUID /target)"
BOOT_UUID="$(blkid -s UUID -o value /dev/nvme0n1p2)"
EFI_UUID="$(blkid -s UUID -o value /dev/nvme0n1p1)"
SWAP_UUID="$(blkid -s UUID -o value /dev/nvme0n1p3)"

cat > "$TARGET/etc/fstab" <<EOF
UUID=${BOOT_UUID} /boot ext4 defaults 0 1
UUID=${EFI_UUID} /boot/efi vfat umask=0077 0 1
UUID=${SWAP_UUID} none swap sw 0 0
UUID=${ROOT_UUID} / btrfs subvol=@,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /home btrfs subvol=@home,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /var/log btrfs subvol=@var_log,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /var/cache btrfs subvol=@var_cache,compress=zstd,noatime,ssd,space_cache=v2 0 0
UUID=${ROOT_UUID} /.snapshots btrfs subvol=@snapshots,compress=zstd,noatime,ssd,space_cache=v2 0 0
EOF
