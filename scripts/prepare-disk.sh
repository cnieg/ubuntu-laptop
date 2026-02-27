#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/nvme0n1"

# Partitions layout (ESP will be created by Subiquity as p1)
# p2 = swap (LUKS2)
# p3 = root (LUKS2 + btrfs)
SWAP_SIZE_GIB=32

CRYPTROOT_NAME="cryptroot"
CRYPTSWAP_NAME="cryptswap"

ROOT_KEY="/run/crypt/root.key"
SWAP_KEY="/run/crypt/swap.key"

log(){ echo "[prepare-disk] $*"; }

if [[ ! -f /cdrom/NOLOUD/ARMED ]]; then
  log "Not armed: create /NOLOUD/ARMED inside the ISO to enable wiping."
  exit 0
fi

for bin in wipefs parted cryptsetup mkfs.btrfs partprobe udevadm dd mount umount btrfs mkswap; do
  command -v "$bin" >/dev/null 2>&1 || { echo "[prepare-disk] Missing tool: $bin" >&2; exit 1; }
done

[[ -b "$DISK" ]] || { echo "[prepare-disk] Disk not found: $DISK" >&2; exit 1; }
[[ -f "$ROOT_KEY" && -f "$SWAP_KEY" ]] || { echo "[prepare-disk] Missing keyfiles in /run/crypt" >&2; exit 1; }

P2="${DISK}p2"
P3="${DISK}p3"

log "Wipe signatures + new GPT..."
wipefs -af "$DISK" || true
dd if=/dev/zero of="$DISK" bs=1M count=16 conv=fsync 2>/dev/null || true

parted -s "$DISK" mklabel gpt

# IMPORTANT:
# - Leave p1 free for Subiquity ESP (512M).
# - Create swap as p2 starting after 513MiB.
parted -s "$DISK" unit MiB mkpart primary 513 $((513 + SWAP_SIZE_GIB*1024))
# Root uses the rest (p3)
parted -s "$DISK" unit MiB mkpart primary $((513 + SWAP_SIZE_GIB*1024)) 100%

partprobe "$DISK" || true
udevadm settle

log "LUKS2 swap on $P2..."
cryptsetup -q luksFormat --type luks2 "$P2" --batch-mode --key-file "$SWAP_KEY"
cryptsetup open "$P2" "$CRYPTSWAP_NAME" --key-file "$SWAP_KEY"
mkswap "/dev/mapper/${CRYPTSWAP_NAME}"
cryptsetup close "$CRYPTSWAP_NAME"

log "LUKS2 root on $P3..."
cryptsetup -q luksFormat --type luks2 "$P3" --batch-mode --key-file "$ROOT_KEY"
cryptsetup open "$P3" "$CRYPTROOT_NAME" --key-file "$ROOT_KEY"

log "Btrfs + subvolumes..."
mkfs.btrfs -f "/dev/mapper/${CRYPTROOT_NAME}"
mount "/dev/mapper/${CRYPTROOT_NAME}" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots

umount /mnt
cryptsetup close "$CRYPTROOT_NAME"

log "Done."
