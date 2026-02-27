#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/nvme0n1"
SWAP_SIZE_GIB=32

CRYPTROOT_NAME="cryptroot"
CRYPTSWAP_NAME="cryptswap"

ROOT_KEY="/run/crypt/root.key"
SWAP_KEY="/run/crypt/swap.key"

log(){ echo "[prepare-disk] $*"; }

die(){
  echo "[prepare-disk] ERROR: $*" >&2
  exit 4
}

need_bin(){
  command -v "$1" >/dev/null 2>&1 || die "Missing tool: $1"
}

# --- Safety gate ---
if [[ ! -f /cdrom/NOLOUD/ARMED ]]; then
  log "Not armed: create /NOLOUD/ARMED inside the ISO to enable wiping."
  exit 0
fi

# --- Requirements ---
for bin in wipefs parted cryptsetup mkfs.btrfs partprobe udevadm dd mount umount btrfs mkswap lsblk blkid; do
  need_bin "$bin"
done
# Optional but helpful
command -v vgchange >/dev/null 2>&1 || true
command -v dmsetup  >/dev/null 2>&1 || true

[[ -b "$DISK" ]] || die "Disk not found: $DISK"
[[ -f "$ROOT_KEY" && -f "$SWAP_KEY" ]] || die "Missing keyfiles in /run/crypt (root.key / swap.key)"

P2="${DISK}p2"
P3="${DISK}p3"

# --- Helpers ---
settle(){
  partprobe "$DISK" >/dev/null 2>&1 || true
  udevadm settle || true
  sleep 1
}

close_mapper_best_effort(){
  local name="$1"
  if [[ -e "/dev/mapper/$name" ]]; then
    log "Closing mapper $name (best-effort)..."
    cryptsetup close "$name" >/dev/null 2>&1 || true
    # If still there, try dmsetup remove (best-effort)
    if [[ -e "/dev/mapper/$name" ]] && command -v dmsetup >/dev/null 2>&1; then
      dmsetup remove -f "$name" >/dev/null 2>&1 || true
    fi
  fi
}

wait_for_part(){
  local part="$1"
  local tries="${2:-20}"
  local i
  for i in $(seq 1 "$tries"); do
    [[ -b "$part" ]] && return 0
    settle
  done
  return 1
}

# --- Cleanup anything the live installer might have opened ---
log "Pre-clean: close crypt mappings / unmount / deactivate LVM (best-effort)..."
umount -R /mnt    >/dev/null 2>&1 || true
umount -R /target >/dev/null 2>&1 || true

close_mapper_best_effort "$CRYPTROOT_NAME"
close_mapper_best_effort "$CRYPTSWAP_NAME"

# Deactivate any VG that could keep devices busy (best-effort)
if command -v vgchange >/dev/null 2>&1; then
  vgchange -an >/dev/null 2>&1 || true
fi

settle

# --- Wipe signatures and reset GPT ---
log "Wipe signatures + new GPT..."
wipefs -af "$DISK" || true
dd if=/dev/zero of="$DISK" bs=1M count=16 conv=fsync 2>/dev/null || true

# Recreate partition table
parted -s "$DISK" mklabel gpt
settle

# IMPORTANT:
# Leave p1 to Subiquity (ESP 512M). We start p2 at 513MiB.
# p2: swap, p3: root
SWAP_START_MIB=513
SWAP_END_MIB=$((SWAP_START_MIB + SWAP_SIZE_GIB*1024))

log "Create partitions: p2 swap [${SWAP_START_MIB}MiB..${SWAP_END_MIB}MiB], p3 root [${SWAP_END_MIB}MiB..end]"
parted -s "$DISK" unit MiB mkpart primary "${SWAP_START_MIB}" "${SWAP_END_MIB}"
parted -s "$DISK" unit MiB mkpart primary "${SWAP_END_MIB}" 100%

settle

# Wait for kernel to expose /dev/nvme0n1p2 and p3
wait_for_part "$P2" 30 || die "Partition not found after create: $P2"
wait_for_part "$P3" 30 || die "Partition not found after create: $P3"

log "Partitions present:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$DISK" || true

# --- Create LUKS swap ---
log "LUKS2 swap on $P2..."
cryptsetup -q luksFormat --type luks2 "$P2" --batch-mode --key-file "$SWAP_KEY"
cryptsetup open "$P2" "$CRYPTSWAP_NAME" --key-file "$SWAP_KEY"

# Ensure mapping exists before mkswap
[[ -b "/dev/mapper/${CRYPTSWAP_NAME}" ]] || die "Mapper not found: /dev/mapper/${CRYPTSWAP_NAME}"
mkswap "/dev/mapper/${CRYPTSWAP_NAME}"

# Close swap mapping (may be used later by curtin; but we close now)
cryptsetup close "$CRYPTSWAP_NAME" || true
settle

# --- Create LUKS root + btrfs ---
log "LUKS2 root on $P3..."
cryptsetup -q luksFormat --type luks2 "$P3" --batch-mode --key-file "$ROOT_KEY"
cryptsetup open "$P3" "$CRYPTROOT_NAME" --key-file "$ROOT_KEY"

[[ -b "/dev/mapper/${CRYPTROOT_NAME}" ]] || die "Mapper not found: /dev/mapper/${CRYPTROOT_NAME}"

log "Btrfs + subvolumes..."
mkfs.btrfs -f "/dev/mapper/${CRYPTROOT_NAME}"
mount "/dev/mapper/${CRYPTROOT_NAME}" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots

umount /mnt
cryptsetup close "$CRYPTROOT_NAME" || true
settle

log "Done."
