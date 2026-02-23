#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/nvme0n1"
EFI_SIZE_MIB=512
SWAP_SIZE_GIB=32

CRYPTROOT_NAME="cryptroot"
CRYPTSWAP_NAME="cryptswap"

ROOT_KEY="/run/crypt/root.key"
SWAP_KEY="/run/crypt/swap.key"

if [[ ! -f /cdrom/NOLOUD/ARMED ]]; then
  echo "USB not armed. Create NOLOUD/ARMED to enable wiping."
  exit 0
fi

P1="${DISK}p1"
P2="${DISK}p2"
P3="${DISK}p3"

wipefs -af "$DISK" || true
sgdisk --zap-all "$DISK" || true

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB "$((EFI_SIZE_MIB+1))"MiB
parted -s "$DISK" set 1 esp on

SWAP_END_MIB="$((EFI_SIZE_MIB + SWAP_SIZE_GIB*1024))"
parted -s "$DISK" mkpart primary "$((EFI_SIZE_MIB+1))"MiB "${SWAP_END_MIB}"MiB
parted -s "$DISK" mkpart primary "${SWAP_END_MIB}"MiB 100%

partprobe "$DISK" || true
udevadm settle

mkfs.vfat -F32 "$P1"

cryptsetup -q luksFormat --type luks2 "$P2" --batch-mode --key-file "$SWAP_KEY"
cryptsetup open "$P2" "$CRYPTSWAP_NAME" --key-file "$SWAP_KEY"
mkswap "/dev/mapper/${CRYPTSWAP_NAME}"
cryptsetup close "$CRYPTSWAP_NAME"

cryptsetup -q luksFormat --type luks2 "$P3" --batch-mode --key-file "$ROOT_KEY"
cryptsetup open "$P3" "$CRYPTROOT_NAME" --key-file "$ROOT_KEY"

mkfs.btrfs -f "/dev/mapper/${CRYPTROOT_NAME}"
mount "/dev/mapper/${CRYPTROOT_NAME}" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots

umount /mnt
cryptsetup close "$CRYPTROOT_NAME"
