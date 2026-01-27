#!/bin/bash

set -e

ISO_SOURCE="ubuntu-25.10-live-server-amd64.iso"
ISO_OUTPUT="ubuntu-25.10-custom.iso"
WORK_DIR="$HOME/iso-build"

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

echo ""
echo "=== Téléchargement de l'ISO Ubuntu 25.10 ==="
if [ ! -f "$HOME/$ISO_SOURCE" ]; then
    echo "ISO non trouvée, téléchargement en cours..."
    cd "$HOME"
    wget -c https://releases.ubuntu.com/25.10/ubuntu-25.10-live-server-amd64.iso
    
    echo "Vérification du checksum..."
    wget -q https://releases.ubuntu.com/25.10/SHA256SUMS
    if sha256sum -c SHA256SUMS 2>&1 | grep -q "$ISO_SOURCE: OK"; then
        echo "✓ Checksum vérifié avec succès"
        rm SHA256SUMS
    else
        echo "✗ ERREUR : Checksum invalide !"
        exit 1
    fi
else
    echo "ISO déjà présente : $HOME/$ISO_SOURCE ✓"
fi

echo ""
echo "=== Nettoyage et préparation ==="
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "=== Montage de l'ISO source ==="
sudo mkdir -p mnt
sudo mount -o loop "$HOME/$ISO_SOURCE" mnt

echo "=== Structure de l'ISO source ==="
ls -la mnt/

SQUASHFS_PATH=$(find mnt -name "*.squashfs" | head -n 1)

if [ -z "$SQUASHFS_PATH" ]; then
    echo "ERREUR : Aucun fichier squashfs trouvé !"
    sudo umount mnt
    exit 1
fi

echo "Fichier squashfs trouvé : $SQUASHFS_PATH"

echo "=== Extraction du contenu de l'ISO ==="
mkdir -p extract-cd
sudo rsync -a --exclude="$(basename $SQUASHFS_PATH)" mnt/ extract-cd/

echo "=== Extraction du filesystem ==="
sudo unsquashfs "$SQUASHFS_PATH"
sudo mv squashfs-root edit

sudo umount mnt

echo "=== Préparation du chroot ==="
sudo cp /etc/resolv.conf edit/etc/
sudo mount --bind /dev edit/dev
sudo mount --bind /run edit/run

echo "=== Personnalisation du système ==="
sudo chroot edit /bin/bash << 'CHROOT_COMMANDS'
set -e

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export LANG=C

echo ">>> Mise à jour et installation des packages"
apt update

# NetworkManager et backend Wi-Fi moderne
apt install -y network-manager network-manager-openconnect network-manager-openconnect-gnome iwd

# GNOME Desktop Environment
apt install -y gnome-shell

# Configurer GDM pour démarrer en Wayland par défaut
mkdir -p /etc/gdm3
cat > /etc/gdm3/custom.conf << 'GDMCONF'
[daemon]
WaylandEnable=true
# Décommenter la ligne suivante pour désactiver X11 complètement
# XorgEnable=false

[security]

[xdmcp]

[chooser]

[debug]
GDMCONF

# Outils de base
apt install -y btop curl git wget net-tools

# Filesystem et chiffrement
apt install -y btrfs-progs cryptsetup cryptsetup-initramfs

# Automatisation
apt install -y ansible

# Désactiver wpa_supplicant (conflit avec iwd)
systemctl disable wpa_supplicant 2>/dev/null || true
systemctl mask wpa_supplicant 2>/dev/null || true

# Désactiver NetworkManager et iwd (seront activés par cloud-init après install)
systemctl disable NetworkManager 2>/dev/null || true
systemctl disable iwd 2>/dev/null || true
systemctl stop NetworkManager 2>/dev/null || true
systemctl stop iwd 2>/dev/null || true

echo ">>> Configuration de NetworkManager pour utiliser iwd"
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-backend.conf << 'NMCONF'
[device]
wifi.backend=iwd
NMCONF

echo ">>> Configuration de iwd"
mkdir -p /etc/iwd
cat > /etc/iwd/main.conf << 'IWDCONF'
[General]
EnableNetworkConfiguration=false

[Network]
NameResolvingService=systemd
IWDCONF

echo ">>> Nettoyage"
apt clean
rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb
rm -f /etc/resolv.conf

umount /proc
umount /sys  
umount /dev/pts
exit
CHROOT_COMMANDS

echo "=== Nettoyage du chroot ==="
sudo umount edit/dev
sudo umount edit/run

echo "=== Recompression du filesystem ==="
SQUASHFS_RELATIVE=$(echo "$SQUASHFS_PATH" | sed "s|mnt/||")
sudo rm -f "extract-cd/$SQUASHFS_RELATIVE"
sudo mksquashfs edit "extract-cd/$SQUASHFS_RELATIVE" -comp xz -b 1M

SQUASHFS_DIR=$(dirname "extract-cd/$SQUASHFS_RELATIVE")
if [ -f "$SQUASHFS_DIR/filesystem.size" ]; then
    echo "=== Mise à jour de la taille du filesystem ==="
    sudo du -sx --block-size=1 edit | cut -f1 | sudo tee "$SQUASHFS_DIR/filesystem.size"
fi

sudo rm -rf edit

echo "=== Mise à jour des checksums ==="
cd extract-cd
sudo rm -f md5sum.txt SHA256SUMS
find -type f -print0 | sudo xargs -0 md5sum | grep -v "isolinux/boot.cat\|boot.catalog" | sudo tee md5sum.txt

echo ""
echo "=== Recherche des fichiers de boot ==="

if [ -f "./isolinux/isolinux.bin" ]; then
    BOOT_TYPE="legacy_isolinux"
    BIOS_BOOT="isolinux/isolinux.bin"
    BOOT_CAT="isolinux/boot.cat"
elif [ -f "./boot/grub/i386-pc/eltorito.img" ]; then
    BOOT_TYPE="grub_pc"
    BIOS_BOOT="boot/grub/i386-pc/eltorito.img"
    BOOT_CAT="boot.catalog"
else
    echo "ERREUR : Type de boot non reconnu !"
    exit 1
fi

if [ -f "./boot/grub/efi.img" ]; then
    EFI_BOOT="boot/grub/efi.img"
elif [ -f "./EFI/boot/bootx64.efi" ]; then
    EFI_BOOT="EFI/boot/bootx64.efi"
else
    echo "ATTENTION : Image EFI non trouvée"
    EFI_BOOT=""
fi

echo "Type de boot : $BOOT_TYPE"
echo "Boot BIOS : $BIOS_BOOT"
echo "Boot EFI : $EFI_BOOT"

echo ""
echo "=== Création de l'ISO ==="

ISOHDPFX=$(find /usr -name "isohdpfx.bin" 2>/dev/null | head -n 1)
if [ -n "$ISOHDPFX" ]; then
    HYBRID_OPTS="-isohybrid-mbr $ISOHDPFX"
else
    HYBRID_OPTS=""
fi

if [ -n "$EFI_BOOT" ]; then
    sudo xorriso -as mkisofs \
        -r -V "Ubuntu 25.10 Custom" \
        -o "$WORK_DIR/$ISO_OUTPUT" \
        -J -joliet-long \
        $HYBRID_OPTS \
        -c "$BOOT_CAT" \
        -b "$BIOS_BOOT" \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e "$EFI_BOOT" \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        .
else
    sudo xorriso -as mkisofs \
        -r -V "Ubuntu 25.10 Custom" \
        -o "$WORK_DIR/$ISO_OUTPUT" \
        -J -joliet-long \
        $HYBRID_OPTS \
        -c "$BOOT_CAT" \
        -b "$BIOS_BOOT" \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        .
fi

if [ $? -eq 0 ]; then
    cd "$WORK_DIR"
    
    echo ""
    echo "========================================="
    echo "✓ ISO CRÉÉE AVEC SUCCÈS"
    echo "========================================="
    echo ""
    echo "Fichier : $WORK_DIR/$ISO_OUTPUT"
    ls -lh "$ISO_OUTPUT"
    
    echo ""
    echo "=== Packages installés ==="
    echo "  • NetworkManager + OpenConnect + iwd (désactivés)"
    echo "  • GNOME Shell"
    echo "  • btop, curl, git, wget, net-tools"
    echo "  • btrfs-progs, cryptsetup"
    echo "  • ansible"
    echo ""
    echo "=== Configuration ==="
    echo "  • wpa_supplicant désactivé"
    echo "  • iwd configuré comme backend Wi-Fi"
    echo "  • Services NetworkManager/iwd seront activés par cloud-init"
    echo ""
    echo "=== Prochaines étapes ==="
    echo "  1. Utilisez le script deploy-to-ventoy.sh pour copier l'ISO"
    echo "  2. Configurez user-data et meta-data sur Ventoy"
    echo ""
else
    echo ""
    echo "✗ ERREUR lors de la création de l'ISO"
    exit 1
fi

