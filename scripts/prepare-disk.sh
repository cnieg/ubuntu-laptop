#!/usr/bin/env bash
set -euo pipefail
set -x   # IMPORTANT: debug output

log(){ echo "[prepare-disk] $*"; }
die(){ echo "[prepare-disk] ERROR: $*" >&2; exit 4; }

# -----------------------------------------------------------------------------
# Select largest NVMe disk automatically
# -----------------------------------------------------------------------------
DISK="$(lsblk -dn -o NAME,TYPE,SIZE | awk '$2=="disk" && $1 ~ /^nvme/ {print $1, $3}' \
  | sort -hr -k2 | head -n1 | awk '{print "/dev/"$1}')"

[[ -n "${DISK:-}" ]] || die "No NVMe disk found"

log "Selected disk: $DISK"
lsblk -o NAME,SIZE,TYPE,MODEL "$DISK"

# -----------------------------------------------------------------------------
# Safety gate
# -----------------------------------------------------------------------------
if [[ ! -f /cdrom/NOLOUD/ARMED ]]; then
  log "Not armed. Create /NOLOUD/ARMED in ISO to enable wiping."
  exit 0
fi

ROOT_KEY="/run/crypt/root.key"
SWAP_KEY="/run/crypt/swap.key"

[[ -f "$ROOT_KEY" ]] || die "Missing $ROOT_KEY"
[[ -f "$SWAP_KEY" ]] || die "Missing $SWAP_KEY"

SWAP_SIZE_GIB=32
CRYPTROOT_NAME="cryptroot"
CRYPTSWAP_NAME="cryptswap"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
settle(){
  partprobe "$DISK" || true
  udevadm settle || true
  sleep 2
}

wait_for_part(){
  local p="$1"
  for i in {1..30}; do
    [[ -b "$p" ]] && return 0
    settle
  done
  return 1
}

close_mapper(){
  local name="$1"
  if [[ -e "/dev/mapper/$name" ]]; then
    cryptsetup close "$name" || true
  fi
}

# -----------------------------------------------------------------------------
# Clean previous state (important in installer environment)
# -----------------------------------------------------------------------------
log "Pre-clean..."
umount -R /mnt 2>/dev/null || true
umount -R /target 2>/dev/null || true

close_mapper "$CRYPTROOT_NAME"
close_mapper "$CRYPTSWAP_NAME"

wipefs -af "$DISK" || true
dd if=/dev/zero of="$DISK" bs=1M count=16 conv=fsync 2>/dev/null || true

settle

# -----------------------------------------------------------------------------
# Partitioning
# Leave first 512MiB for ESP (created later by Subiquity)
# -----------------------------------------------------------------------------
log "Create GPT"
parted -s "$DISK" mklabel gpt

SWAP_START_MIB=513
SWAP_END_MIB=$((SWAP_START_MIB + SWAP_SIZE_GIB*1024))

log "Create partitions"
parted -s "$DISK" mkpart primary "${SWAP_START_MIB}MiB" "${SWAP_END_MIB}MiB"
parted -s "$DISK" mkpart primary "${SWAP_END_MIB}MiB" 100%

settle

log "Partition table:"
parted -s "$DISK" print

P2="${DISK}p2"
P3="${DISK}p3"

wait_for_part "$P2" || die "Partition not found: $P2"
wait_for_part "$P3" || die "Partition not found: $P3"

lsblk "$DISK"

# -----------------------------------------------------------------------------
# LUKS SWAP
# -----------------------------------------------------------------------------
log "Create LUKS swap"
cryptsetup -q luksFormat --type luks2 "$P2" --batch-mode --key-file "$SWAP_KEY"
cryptsetup open "$P2" "$CRYPTSWAP_NAME" --key-file "$SWAP_KEY"

mkswap "/dev/mapper/$CRYPTSWAP_NAME"

cryptsetup close "$CRYPTSWAP_NAME" || true
settle

# -----------------------------------------------------------------------------
# LUKS ROOT + BTRFS
# -----------------------------------------------------------------------------
log "Create LUKS root"
cryptsetup -q luksFormat --type luks2 "$P3" --batch-mode --key-file "$ROOT_KEY"
cryptsetup open "$P3" "$CRYPTROOT_NAME" --key-file "$ROOT_KEY"

mkfs.btrfs -f "/dev/mapper/$CRYPTROOT_NAME"

mount "/dev/mapper/$CRYPTROOT_NAME" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots

umount /mnt
cryptsetup close "$CRYPTROOT_NAME" || true

settle

log "Disk preparation complete."
