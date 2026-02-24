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

# rendre l'arborescence modifiable (CI)
chmod -R u+rwX "$WORKDIR/iso"

echo "[build-iso] Inject NOLOUD..."
rm -rf "$WORKDIR/iso/NOLOUD"
mkdir -p "$WORKDIR/iso/NOLOUD"
cp -a "$ROOT_DIR/nocloud/." "$WORKDIR/iso/NOLOUD/"
cp -a "$ROOT_DIR/scripts/prepare-disk.sh" "$WORKDIR/iso/NOLOUD/prepare-disk.sh"
chmod +x "$WORKDIR/iso/NOLOUD/prepare-disk.sh"
cp -a "$ROOT_DIR/scripts/prepare-proxy.sh" "$WORKDIR/iso/NOLOUD/prepare-proxy.sh"
chmod +x "$WORKDIR/iso/NOLOUD/prepare-proxy.sh"
cp -a "$ROOT_DIR/scripts/install-proxy-autoswitch.sh" "$WORKDIR/iso/NOLOUD/install-proxy-autoswitch.sh"
chmod +x "$WORKDIR/iso/NOLOUD/install-proxy-autoswitch.sh"

# Arm by default (remove if you want manual arming)
touch "$WORKDIR/iso/NOLOUD/ARMED"

echo "[build-iso] Patch boot parameters..."

echo "[build-iso] Patch boot parameters..."
for f in   "$WORKDIR/iso/boot/grub/grub.cfg"   "$WORKDIR/iso/boot/grub/loopback.cfg"   "$WORKDIR/iso/EFI/boot/grub.cfg"   "$WORKDIR/iso/isolinux/txt.cfg"
do
  [[ -f "$f" ]] && sed -i 's/---/ autoinstall ds=nocloud\\;s=\/cdrom\/NOLOUD\/ ---/g' "$f"
done

echo "[build-iso] Repack ISO (boot replay, robust)..."
rm -f "$ISO_OUT"

echo "[build-iso] xorriso version:"
xorriso -version || true

echo "[build-iso] ISO boot report (source):"
xorriso -indev "$ISO_IN" -report_el_torito as_mkisofs || true

# IMPORTANT: ne pas rediriger vers /dev/null => on veut l'erreur exacte
if ! xorriso \
  -indev "$ISO_IN" \
  -outdev "$ISO_OUT" \
  -volid "UBUNTU_FACTORY" \
  -map "$WORKDIR/iso" / \
  -boot_image any replay \
  -compliance no_emul_toc \
  -padding 0
then
  echo "[build-iso] Replay failed; trying fallback mkisofs mode (auto-detect boot images)..."

  # Auto-détection BIOS/UEFI boot images (selon l'ISO)
  BIOS_BIN="$(find "$WORKDIR/iso" -type f \( -path "*/isolinux/isolinux.bin" -o -path "*/boot/grub/i386-pc/eltorito.img" \) | head -n1 || true)"
  EFI_IMG="$(find "$WORKDIR/iso" -type f \( -path "*/boot/grub/efi.img" -o -path "*/efi.img" -o -path "*/boot/grub/efi*.img" \) | head -n1 || true)"

  echo "[build-iso] Detected BIOS boot image: ${BIOS_BIN:-<none>}"
  echo "[build-iso] Detected EFI image: ${EFI_IMG:-<none>}"

  # Construit les arguments boot de façon conditionnelle
  MKISO_ARGS=(-r -V "UBUNTU_FACTORY" -o "$ISO_OUT" -J -l)

  if [[ -n "$BIOS_BIN" ]]; then
    # boot.cat doit être dans le même dossier que isolinux.bin dans la plupart des ISOs
    BOOT_CAT_DIR="$(dirname "$BIOS_BIN")"
    # chemin relatif dans l'ISO
    BIOS_BIN_REL="${BIOS_BIN#$WORKDIR/iso/}"
    BOOT_CAT_REL="${BOOT_CAT_DIR#$WORKDIR/iso/}/boot.cat"
    MKISO_ARGS+=(-c "$BOOT_CAT_REL" -b "$BIOS_BIN_REL" -no-emul-boot -boot-load-size 4 -boot-info-table)
  fi

  if [[ -n "$EFI_IMG" ]]; then
    EFI_REL="${EFI_IMG#$WORKDIR/iso/}"
    MKISO_ARGS+=(-eltorito-alt-boot -e "$EFI_REL" -no-emul-boot)
  fi

  # Si aucun des deux n'est trouvé, on échoue avec un message clair
  if [[ -z "$BIOS_BIN" && -z "$EFI_IMG" ]]; then
    echo "[build-iso] ERROR: cannot find BIOS or EFI boot image in extracted ISO tree."
    echo "[build-iso] DEBUG: listing candidate boot files:"
    find "$WORKDIR/iso" -maxdepth 4 -type f \( -name "isolinux.bin" -o -name "eltorito.img" -o -name "efi.img" -o -name "*.efi" -o -name "*.img" \) | head -n 200
    exit 1
  fi

  # Lance mkisofs via xorriso
  xorriso -as mkisofs "${MKISO_ARGS[@]}" "$WORKDIR/iso"
fi

echo "[build-iso] Done: $ISO_OUT"
