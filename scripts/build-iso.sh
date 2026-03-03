#!/usr/bin/env bash
set -euo pipefail

ISO_IN="${1:-}"
ISO_OUT="${2:-build/ubuntu-custom.iso}"

if [[ -z "$ISO_IN" || ! -f "$ISO_IN" ]]; then
  echo "Usage: $0 /path/to/ubuntu-live-server-amd64.iso [output.iso]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${ROOT_DIR}/build/work"
OUTDIR="$(dirname "$ISO_OUT")"

mkdir -p "$WORKDIR" "$OUTDIR"

echo "=== Vérification et installation des dépendances ==="
REQUIRED_PACKAGES="squashfs-tools xorriso rsync wget"
MISSING_PACKAGES=""

for pkg in $REQUIRED_PACKAGES; do
  if ! dpkg -l | grep -q "^ii  $pkg"; then
    MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
  fi
done

if [[ -n "$MISSING_PACKAGES" ]]; then
  echo "Installation des packages manquants :$MISSING_PACKAGES"
  sudo apt-get update
  sudo apt-get install -y $MISSING_PACKAGES
else
  echo "Tous les packages requis sont déjà installés ✓"
fi

echo "[build-iso] Extract ISO..."
rm -rf "$WORKDIR/iso"
mkdir -p "$WORKDIR/iso"
xorriso -osirrox on -indev "$ISO_IN" -extract / "$WORKDIR/iso" >/dev/null

# rendre l'arborescence modifiable (CI)
chmod -R u+rwX "$WORKDIR/iso"

echo "[build-iso] Inject NOLOUD..."
rm -rf "$WORKDIR/iso/NOLOUD"
mkdir -p "$WORKDIR/iso/NOLOUD"
cp -a "$ROOT_DIR/nocloud/." "$WORKDIR/iso/NOLOUD/"
cp -a "$ROOT_DIR/scripts/prepare-proxy.sh" "$WORKDIR/iso/NOLOUD/prepare-proxy.sh"
chmod +x "$WORKDIR/iso/NOLOUD/prepare-proxy.sh"
cp -a "$ROOT_DIR/scripts/install-proxy-autoswitch.sh" "$WORKDIR/iso/NOLOUD/install-proxy-autoswitch.sh"
chmod +x "$WORKDIR/iso/NOLOUD/install-proxy-autoswitch.sh"
touch "$WORKDIR/iso/NOLOUD/ARMED"

# Paramètres à injecter (Ventoy/GRUB2-friendly)
KPARAMS='autoinstall ds=nocloud\\;s=/cdrom/NOLOUD/'

echo "[build-iso] Patch boot parameters (safe append)..."
patch_one() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  # Si déjà présent, ne rien faire
  if grep -q 'ds=nocloud\\;s=/cdrom/NOLOUD/' "$f" || grep -q 'ds=nocloud;s=/cdrom/NOLOUD/' "$f"; then
    echo "[build-iso] already patched: $f"
    return 0
  fi

  # GRUB cfg: lignes commençant par 'linux' (ou 'linuxefi') -> append avant '---' si présent, sinon en fin
  if grep -Eq '^[[:space:]]*(linux|linuxefi)[[:space:]]+' "$f"; then
    # 1) cas avec ' ---' : injecter avant les trois tirets
    if grep -q ' ---' "$f"; then
      sed -i -E "s@^([[:space:]]*(linux|linuxefi)[[:space:]].*) ---@\\1 ${KPARAMS} ---@g" "$f"
    else
      # 2) sinon, append en fin de ligne linux/linuxefi
      sed -i -E "s@^([[:space:]]*(linux|linuxefi)[[:space:]].*)\$@\\1 ${KPARAMS}@g" "$f"
    fi
    echo "[build-iso] patched linux cmdline: $f"
    return 0
  fi

  # ISOLINUX txt.cfg : lignes append/initrd avec '---' souvent
  if grep -Eq '^[[:space:]]*append[[:space:]]+' "$f"; then
    if grep -q ' ---' "$f"; then
      sed -i -E "s@^([[:space:]]*append[[:space:]].*) ---@\\1 ${KPARAMS} ---@g" "$f"
    else
      sed -i -E "s@^([[:space:]]*append[[:space:]].*)\$@\\1 ${KPARAMS}@g" "$f"
    fi
    echo "[build-iso] patched isolinux append: $f"
    return 0
  fi

  echo "[build-iso] no known patch pattern for: $f"
}

# Patch les endroits “classiques” + quelques variantes
CANDIDATES=(
  "$WORKDIR/iso/boot/grub/grub.cfg"
  "$WORKDIR/iso/boot/grub/loopback.cfg"
  "$WORKDIR/iso/EFI/boot/grub.cfg"
  "$WORKDIR/iso/boot/grub/x86_64-efi/grub.cfg"
  "$WORKDIR/iso/isolinux/txt.cfg"
)
for f in "${CANDIDATES[@]}"; do
  patch_one "$f"
done

echo "[build-iso] Update md5sum.txt if present (avoid md5check surprises)..."
if [[ -f "$WORKDIR/iso/md5sum.txt" ]]; then
  (cd "$WORKDIR/iso" && \
    find . -type f -print0 \
      | grep -zvE '^\./md5sum\.txt$' \
      | xargs -0 md5sum > md5sum.txt)
fi

echo "[build-iso] Repack ISO (boot replay, robust)..."
rm -f "$ISO_OUT"

echo "[build-iso] xorriso version:"
xorriso -version || true

echo "[build-iso] ISO boot report (source):"
xorriso -indev "$ISO_IN" -report_el_torito as_mkisofs || true

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

  BIOS_BIN="$(find "$WORKDIR/iso" -type f \( -path "*/isolinux/isolinux.bin" -o -path "*/boot/grub/i386-pc/eltorito.img" \) | head -n1 || true)"
  EFI_IMG="$(find "$WORKDIR/iso" -type f \( -path "*/boot/grub/efi.img" -o -path "*/efi.img" -o -path "*/boot/grub/efi*.img" \) | head -n1 || true)"

  echo "[build-iso] Detected BIOS boot image: ${BIOS_BIN:-<none>}"
  echo "[build-iso] Detected EFI image: ${EFI_IMG:-<none>}"

  MKISO_ARGS=(-r -V "UBUNTU_FACTORY" -o "$ISO_OUT" -J -l)

  if [[ -n "$BIOS_BIN" ]]; then
    BIOS_BIN_REL="${BIOS_BIN#$WORKDIR/iso/}"
    BOOT_CAT_REL="$(dirname "${BIOS_BIN_REL}")/boot.cat"
    MKISO_ARGS+=(-c "$BOOT_CAT_REL" -b "$BIOS_BIN_REL" -no-emul-boot -boot-load-size 4 -boot-info-table)
  fi

  if [[ -n "$EFI_IMG" ]]; then
    EFI_REL="${EFI_IMG#$WORKDIR/iso/}"
    MKISO_ARGS+=(-eltorito-alt-boot -e "$EFI_REL" -no-emul-boot)
  fi

  if [[ -z "$BIOS_BIN" && -z "$EFI_IMG" ]]; then
    echo "[build-iso] ERROR: cannot find BIOS or EFI boot image in extracted ISO tree."
    find "$WORKDIR/iso" -maxdepth 5 -type f \( -name "isolinux.bin" -o -name "eltorito.img" -o -name "efi.img" -o -name "*.efi" -o -name "*.img" \) | head -n 200
    exit 1
  fi

  xorriso -as mkisofs "${MKISO_ARGS[@]}" "$WORKDIR/iso"
fi

echo "[build-iso] Done: $ISO_OUT"
