#!/bin/bash

set -e

ISO_SOURCE="ubuntu-25.10-live-server-amd64.iso"
ISO_OUTPUT="ubuntu-25.10-custom.iso"
WORK_DIR="$HOME/iso-build"

# Fonction pour afficher la progression et les ressources
show_progress() {
    echo ""
    echo "=== $1 ==="
    echo "Temps écoulé: $SECONDS secondes"
    echo "Mémoire disponible:"
    free -h | grep Mem
    echo "Espace disque:"
    df -h /home | tail -1
    echo ""
}

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

show_progress "Téléchargement de l'ISO Ubuntu 25.10"

if [ ! -f "$HOME/$ISO_SOURCE" ]; then
    echo "ISO non trouvée, téléchargement en cours..."
    cd "$HOME"
    # Utiliser wget avec progression et reprise
    wget --progress=dot:giga -c https://releases.ubuntu.com/25.10/ubuntu-25.10-live-server-amd64.iso
    
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

show_progress "Nettoyage et préparation"

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

show_progress "Extraction du contenu de l'ISO"

mkdir -p extract-cd
sudo rsync -a --info=progress2 --exclude="$(basename $SQUASHFS_PATH)" mnt/ extract-cd/

show_progress "Extraction du filesystem (peut prendre 10-15 min)"

# Limiter l'utilisation de la mémoire pour unsquashfs
sudo unsquashfs -processors 2 "$SQUASHFS_PATH"
sudo mv squashfs-root edit

sudo umount mnt

show_progress "Préparation du chroot"

sudo cp /etc/resolv.conf edit/etc/
sudo mount --bind /dev edit/dev
sudo mount --bind /run edit/run

sudo mount -t proc proc edit/proc
sudo mount -t sysfs sys edit/sys
sudo mount -t devpts devpts edit/dev/pts

show_progress "Personnalisation du système (peut prendre 20-30 min)"

sudo chroot edit /bin/bash << 'CHROOT_COMMANDS'
set -e

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export LANG=C

echo ">>> [$(date +%H:%M:%S)] Mise à jour des sources"
apt update

echo ">>> [$(date +%H:%M:%S)] Upgrade du système"
apt upgrade -y

echo ">>> [$(date +%H:%M:%S)] Installation NetworkManager et iwd"
apt install -y network-manager network-manager-openconnect network-manager-openconnect-gnome iwd

echo ">>> [$(date +%H:%M:%S)] Installation GNOME (étape la plus longue)"
apt install -y software-properties-common ubuntu-desktop-minimal gnome-session gnome-shell gdm3

echo ">>> [$(date +%H:%M:%S)] Installation applications GNOME essentielles"
apt install -y nautilus gnome-terminal gnome-text-editor gnome-system-monitor gnome-control-center

echo ">>> [$(date +%H:%M:%S)] Installation utilitaires GNOME"
apt install -y gnome-tweaks gnome-shell-extensions dconf-editor

echo ">>> [$(date +%H:%M:%S)] Installation outils de base"
apt install -y btop curl git wget net-tools

echo ">>> [$(date +%H:%M:%S)] Installation filesystem et chiffrement"
apt install -y btrfs-progs cryptsetup cryptsetup-initramfs

echo ">>> [$(date +%H:%M:%S)] Installation ansible"
apt install -y ansible

echo ">>> [$(date +%H:%M:%S)] Configuration des services"
# Désactiver wpa_supplicant (conflit avec iwd)
systemctl disable wpa_supplicant 2>/dev/null || true
systemctl mask wpa_supplicant 2>/dev/null || true

# Désactiver NetworkManager et iwd (seront activés par cloud-init après install)
systemctl disable NetworkManager 2>/dev/null || true
systemctl disable iwd 2>/dev/null || true
systemctl stop NetworkManager 2>/dev/null || true
systemctl stop iwd 2>/dev/null || true

echo ">>> [$(date +%H:%M:%S)] Configuration de NetworkManager pour utiliser iwd"
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-backend.conf << 'NMCONF'
[device]
wifi.backend=iwd
NMCONF

echo ">>> [$(date +%H:%M:%S)] Configuration de iwd"
mkdir -p /etc/iwd
cat > /etc/iwd/main.conf << 'IWDCONF'
[General]
EnableNetworkConfiguration=false

[Network]
NameResolvingService=systemd
IWDCONF

echo ">>> [$(date +%H:%M:%S)] Nettoyage"
apt clean
rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb

# Tuer tous les processus qui pourraient bloquer
echo "Arrêt des services qui pourraient bloquer..."
systemctl stop snapd 2>/dev/null || true
systemctl stop snapd.socket 2>/dev/null || true
killall -9 snapd 2>/dev/null || true

# Nettoyer les sockets et fichiers de lock
rm -f /run/snapd.socket 2>/dev/null || true
rm -f /run/lock/* 2>/dev/null || true
rm -f /etc/resolv.conf

echo ">>> [$(date +%H:%M:%S)] Personnalisation terminée"
exit
CHROOT_COMMANDS

show_progress "Nettoyage du chroot"

# Démontage robuste de tous les points de montage
# On démonte d'abord les sous-montages de /run
sudo umount -l edit/run/snapd/ns/*.mnt 2>/dev/null || true
sudo umount -l edit/run/snapd/ns 2>/dev/null || true
sudo umount -l edit/run/user/* 2>/dev/null || true
sudo umount -l edit/run/lock 2>/dev/null || true

# Démontage des points de montage principaux
sudo umount -l edit/dev/pts 2>/dev/null || true
sudo umount -l edit/proc 2>/dev/null || true
sudo umount -lR edit/sys 2>/dev/null || true
sudo umount -l edit/dev 2>/dev/null || true
sudo umount -l edit/run 2>/dev/null || true

# Vérification qu'il ne reste plus de montage
echo "Vérification des montages restants..."
if mount | grep -q "edit"; then
    echo "ATTENTION: Montages restants détectés:"
    mount | grep "edit"
    echo "Tentative de démontage forcé..."
    sudo umount -f $(mount | grep "edit" | awk '{print $3}') 2>/dev/null || true
    sleep 2
fi

show_progress "Recompression du filesystem (peut prendre 15-20 min)"

SQUASHFS_RELATIVE=$(echo "$SQUASHFS_PATH" | sed "s|mnt/||")
sudo rm -f "extract-cd/$SQUASHFS_RELATIVE"

# Limiter les processeurs pour éviter de saturer la mémoire
sudo mksquashfs edit "extract-cd/$SQUASHFS_RELATIVE" -comp xz -b 1M -processors 2 -progress

SQUASHFS_DIR=$(dirname "extract-cd/$SQUASHFS_RELATIVE")
if [ -f "$SQUASHFS_DIR/filesystem.size" ]; then
    echo "=== Mise à jour de la taille du filesystem ==="
    sudo du -sx --block-size=1 edit | cut -f1 | sudo tee "$SQUASHFS_DIR/filesystem.size"
fi

# Nettoyer pour libérer de l'espace
echo "Suppression du répertoire edit..."

# Utiliser un petit délai pour s'assurer que tous les processus sont terminés
sleep 2

# Tentative de suppression normale
if ! sudo rm -rf edit 2>/dev/null; then
    echo "Suppression simple échouée, tentative avec lazy unmount..."
    
    # Forcer le démontage de tout ce qui reste
    sudo find edit -type d -exec umount -l {} \; 2>/dev/null || true
    sleep 1
    
    # Nouvelle tentative de suppression
    if ! sudo rm -rf edit; then
        echo "ATTENTION: Impossible de supprimer complètement edit/"
        echo "Tentative de suppression du contenu uniquement..."
        sudo rm -rf edit/* 2>/dev/null || true
        sudo rm -rf edit/.* 2>/dev/null || true
    fi
fi

if [ -d edit ]; then
    echo "ATTENTION: Le répertoire edit existe toujours"
    ls -la edit/ 2>/dev/null || true
else
    echo "✓ Répertoire edit supprimé avec succès"
fi

show_progress "Filesystem nettoyé, espace libéré"

echo "=== Mise à jour des checksums ==="
cd extract-cd
sudo rm -f md5sum.txt SHA256SUMS
find -type f -print0 | sudo xargs -0 md5sum | grep -v "isolinux/boot.cat\|boot.catalog" | sudo tee md5sum.txt

show_progress "Recherche des fichiers de boot"

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

show_progress "Création de l'ISO finale"

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
    
    show_progress "BUILD TERMINÉ AVEC SUCCÈS !"
    
    echo ""
    echo "========================================="
    echo "✓ ISO CRÉÉE AVEC SUCCÈS"
    echo "========================================="
    echo ""
    echo "Fichier : $WORK_DIR/$ISO_OUTPUT"
    ls -lh "$ISO_OUTPUT"
    
    echo ""
    echo "Temps total de build: $SECONDS secondes ($((SECONDS/60)) minutes)"
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
