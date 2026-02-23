#!/usr/bin/env bash
set -euo pipefail

ISO_IN="${1:-}"
ISO_OUT="${2:-build/ubuntu-server-25.10-factory.iso}"

if [[ -z "$ISO_IN" || ! -f "$ISO_IN" ]]; then
  echo "Usage: $0 /path/to/ubuntu-25.10-live-server-amd64.iso [output.iso]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${ROOT_DIR}/build/work"
OUTDIR="$(dirname "$ISO_OUT")"

mkdir -p "$WORKDIR" "$OUTDIR"

echo "=== Vérification et installation des dépendances ==="
REQUIRED_PACKAGES="squashfs-tools xorriso isolinux rsync wget"
MISSING_PACKAGES=""

for pkg in $REQUIRED_PACKAGES; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
    fi
done

if [ -n "$MISSING_PACKAGES" ]; then
    echo "Installation des packages manquants :$MISSING_PACKAGES"
    sudo apt update
    sudo apt install -y $MISSING_PACKAGES
else
    echo "Tous les packages requis sont déjà installés ✓"
fi

echo "[build-iso] Extract ISO..."
rm -rf "$WORKDIR/iso"
mkdir -p "$WORKDIR/iso"
xorriso -osirrox on -indev "$ISO_IN" -extract / "$WORKDIR/iso" >/dev/null 2>&1

chmod -R u+rwX "$WORKDIR/iso"

echo "[build-iso] Inject NOLOUD..."
rm -rf "$WORKDIR/iso/NOLOUD"
mkdir -p "$WORKDIR/iso/NOLOUD"
cp -a "$ROOT_DIR/nocloud/." "$WORKDIR/iso/NOLOUD/"
cp -a "$ROOT_DIR/scripts/prepare-disk.sh" "$WORKDIR/iso/NOLOUD/prepare-disk.sh"
chmod +x "$WORKDIR/iso/NOLOUD/prepare-disk.sh"

# Arm by default (remove if you want manual arming)
touch "$WORKDIR/iso/NOLOUD/ARMED"

echo "[build-iso] Patch boot parameters..."
if [[ -f "$WORKDIR/iso/boot/grub/grub.cfg" ]]; then
  sed -i 's/---/ autoinstall ds=nocloud;s=\/cdrom\/NOLOUD\/ ---/g' "$WORKDIR/iso/boot/grub/grub.cfg"
fi

if [[ -f "$WORKDIR/iso/isolinux/txt.cfg" ]]; then
  sed -i 's/---/ autoinstall ds=nocloud;s=\/cdrom\/NOLOUD\/ ---/g' "$WORKDIR/iso/isolinux/txt.cfg"
fi

echo "[build-iso] Repack ISO..."
rm -f "$ISO_OUT"

xorriso -as mkisofs   -r -V "UBUNTU_FACTORY"   -o "$ISO_OUT"   -J -l   -c isolinux/boot.cat   -b isolinux/isolinux.bin   -no-emul-boot -boot-load-size 4 -boot-info-table   -eltorito-alt-boot   -e boot/grub/efi.img   -no-emul-boot   "$WORKDIR/iso" >/dev/null 2>&1 || {
    echo "[build-iso] Repack failed. Your ISO layout may differ."
    exit 1
  }

echo "[build-iso] Done: $ISO_OUT"
