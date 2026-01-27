#!/bin/bash

set -e

ISO_FILE="$HOME/iso-build/ubuntu-25.10-custom.iso"

echo "=== Déploiement sur clé Ventoy ==="
echo ""

# Détecter les clés Ventoy montées (sda1 seulement, pas sda2)
echo "Recherche des clés Ventoy..."
VENTOY_PATHS=$(mount | grep -E 'sda1|sdb1|sdc1' | grep -i ventoy | awk '{print $3}' || true)

if [ -z "$VENTOY_PATHS" ]; then
    echo "❌ Aucune clé Ventoy détectée."
    echo ""
    echo "Montez votre clé Ventoy et relancez le script."
    echo "Ou spécifiez le chemin manuellement:"
    echo "  $0 /chemin/vers/ventoy"
    exit 1
fi

# Si un chemin est fourni en argument, l'utiliser
if [ -n "$1" ]; then
    VENTOY_PATH="$1"
else
    # Afficher les chemins trouvés
    echo "Clés Ventoy détectées:"
    echo "$VENTOY_PATHS" | nl
    echo ""
    
    # Si une seule clé, l'utiliser automatiquement
    COUNT=$(echo "$VENTOY_PATHS" | wc -l)
    if [ "$COUNT" -eq 1 ]; then
        VENTOY_PATH="$VENTOY_PATHS"
        echo "Utilisation de: $VENTOY_PATH"
    else
        echo "Plusieurs clés détectées. Spécifiez laquelle utiliser:"
        read -p "Numéro (1-$COUNT): " CHOICE
        VENTOY_PATH=$(echo "$VENTOY_PATHS" | sed -n "${CHOICE}p")
    fi
fi

echo ""
echo "Clé Ventoy: $VENTOY_PATH"

# Vérifier que l'ISO existe
if [ ! -f "$ISO_FILE" ]; then
    echo "❌ ISO non trouvée: $ISO_FILE"
    echo "Lancez d'abord le script de build: ./build-iso.sh"
    exit 1
fi

echo ""
echo "=== Copie de l'ISO ==="
echo "Source: $ISO_FILE"
echo "Destination: $VENTOY_PATH/"

cp -v "$ISO_FILE" "$VENTOY_PATH/"

echo ""
echo "=== Création de la structure cloud-init ==="

# Créer les dossiers
mkdir -p "$VENTOY_PATH/ventoy/ubuntu-autoinstall"

# Copier le logo si présent
if [ -f "oasis-logo.png" ]; then
    echo "Copie du oasis-logo.png..."
    cp oasis-logo.png "$VENTOY_PATH/ventoy/ubuntu-autoinstall/"
elif [ -f "$HOME/oasis-logo.png" ]; then
    echo "Copie du oasis-logo.png..."
    cp "$HOME/oasis-logo.png" "$VENTOY_PATH/ventoy/ubuntu-autoinstall/"
elif [ -f "assets/oasis-logo.png" ]; then
    echo "Copie du oasis-logo.png depuis assets/..."
    cp assets/oasis-logo.png "$VENTOY_PATH/ventoy/ubuntu-autoinstall/"
else
    echo "⚠️  oasis-logo.png non trouvé (optionnel)"
fi

# Créer ventoy.json
echo "Création de ventoy.json..."
cat > "$VENTOY_PATH/ventoy/ventoy.json" << 'JSONEOF'
{
    "auto_install": [
        {
            "image": "/ubuntu-25.10-custom.iso",
            "template": "/ventoy/ubuntu-autoinstall/user-data",
            "autosel": 1,
            "timeout": 1
        }
    ]
}
JSONEOF

# Vérifier que le fichier a bien été créé
if [ ! -s "$VENTOY_PATH/ventoy/ventoy.json" ]; then
    echo "❌ Erreur: ventoy.json est vide ou n'a pas été créé"
    echo "Tentative avec sudo..."
    sudo tee "$VENTOY_PATH/ventoy/ventoy.json" > /dev/null << 'JSONEOF2'
{
    "auto_install": [
        {
            "image": "/ubuntu-25.10-custom.iso",
            "template": "/ventoy/ubuntu-autoinstall/"
        }
    ]
}
JSONEOF2
fi

# Afficher le contenu pour vérification
echo "Contenu de ventoy.json:"
cat "$VENTOY_PATH/ventoy/ventoy.json"

# Créer meta-data
echo "Création de meta-data..."
cat > "$VENTOY_PATH/ventoy/ubuntu-autoinstall/meta-data" << 'EOF'
instance-id: ubuntu-laptop-autoinstall
local-hostname: ubuntu-laptop
EOF

# Créer user-data template
echo "Création de user-data..."
cat > "$VENTOY_PATH/ventoy/ubuntu-autoinstall/user-data" << 'EOF'
#cloud-config
autoinstall:
  version: 1
  
  # Configuration locale et clavier
  locale: fr_FR.UTF-8
  keyboard:
    layout: fr
  
  # Utilisateur
  identity:
    hostname: ubuntu-laptop
    username: ubuntu-admin
    password: "$6$/yanqE2Vz2S8vxoc$9AijXrulDxDWtdbzSRcFUGvQgoccp7jn3HYYx3l4n3MHeZZnrpgQuMuibotuTLc87L2/l0jTpEicShq5bvLOE0"
  
  # SSH
  ssh:
    install-server: yes
    allow-pw: yes
    # Décommente et ajoute ta clé publique
    # authorized-keys:
    #   - ssh-rsa AAAAB3... ton_email@domain.com
  
  # Stockage: LUKS + btrfs
  storage:
    layout:
      name: direct
    config:
      # Disque principal
      - type: disk
        id: disk0
        ptable: gpt
        wipe: superblock-recursive
        preserve: false
        grub_device: true
      
      # Partition EFI (non chiffrée)
      - type: partition
        id: partition-efi
        device: disk0
        size: 512M
        flag: boot
      
      # Partition /boot (non chiffrée)
      - type: partition
        id: partition-boot
        device: disk0
        size: 1G
      
      # Partition racine (sera chiffrée)
      - type: partition
        id: partition-root
        device: disk0
        size: -1
      
      # Format EFI
      - type: format
        id: format-efi
        volume: partition-efi
        fstype: fat32
        label: EFI
      
      # Format /boot
      - type: format
        id: format-boot
        volume: partition-boot
        fstype: ext4
        label: boot
      
      # Chiffrement LUKS
      - type: dm_crypt
        id: dmcrypt-root
        volume: partition-root
        key: "LUKS-cnieg"
      
      # Format btrfs sur LUKS
      - type: format
        id: format-root
        volume: dmcrypt-root
        fstype: btrfs
        label: rootfs
      
      # Mount /boot/efi
      - type: mount
        id: mount-efi
        device: format-efi
        path: /boot/efi
      
      # Mount /boot
      - type: mount
        id: mount-boot
        device: format-boot
        path: /boot
      
      # Sous-volume racine
      - type: btrfs_subvolume
        id: subvol-root
        volume: format-root
        name: "@"
      
      - type: mount
        id: mount-root
        device: subvol-root
        path: /
        options: "subvol=@,compress=zstd"
      
      # Sous-volume /home
      - type: btrfs_subvolume
        id: subvol-home
        volume: format-root
        name: "@home"
      
      - type: mount
        id: mount-home
        device: subvol-home
        path: /home
        options: "subvol=@home,compress=zstd"
      
      # Sous-volume /var
      - type: btrfs_subvolume
        id: subvol-var
        volume: format-root
        name: "@var"
      
      - type: mount
        id: mount-var
        device: subvol-var
        path: /var
        options: "subvol=@var,compress=zstd"
  
  # Packages supplémentaires (optionnel si réseau disponible)
  # packages:
  #   - package1
  #   - package2
  
  # Configuration post-installation
  late-commands:
    # Copier le logo depuis le CDROM vers la machine
    - cp /cdrom/logo_oasis.png /target/usr/share/pixmaps/logo_oasis.png || true
    
    # Nettoyer les fichiers netplan créés par l'installeur
    - rm -f /target/etc/netplan/*.yaml
    
    # Créer le fichier netplan pour NetworkManager avec bonnes permissions
    - |
      cat > /target/etc/netplan/01-network-manager.yaml << 'NETPLAN'
      network:
        version: 2
        renderer: NetworkManager
      NETPLAN
    
    # Corriger les permissions du fichier netplan
    - chmod 600 /target/etc/netplan/01-network-manager.yaml
    - chown root:root /target/etc/netplan/01-network-manager.yaml
    
    # Désactiver systemd-networkd
    - curtin in-target -- systemctl stop systemd-networkd
    - curtin in-target -- systemctl disable systemd-networkd
    - curtin in-target -- systemctl mask systemd-networkd
    
    # Activer NetworkManager et iwd
    - curtin in-target -- systemctl enable NetworkManager
    - curtin in-target -- systemctl enable iwd
    
    # Message de fin
    - echo 'Installation terminée avec LUKS + btrfs + NetworkManager !' > /target/root/install-complete.txt
EOF

echo ""
echo "========================================="
echo "✓ DÉPLOIEMENT TERMINÉ"
echo "========================================="
echo ""
echo "Structure créée sur Ventoy:"
echo "  $VENTOY_PATH/"
echo "  ├── ubuntu-25.10-custom.iso"
echo "  └── ventoy/"
echo "      ├── ventoy.json (avec autosel=1, timeout=1)"
echo "      └── ubuntu-autoinstall/"
echo "          ├── user-data"
echo "          ├── meta-data"
echo "          └── logo_oasis.png (si présent)"
echo ""
echo "⚠️  IMPORTANT - user-data configuré avec:"
echo "  • Hostname: ubuntu-laptop"
echo "  • Username: ubuntu-admin"
echo "  • Password LUKS: LUKS-cnieg"
echo "  • Clavier: FR"
echo "  • Locale: fr_FR.UTF-8"
echo ""
echo "Pour modifier, éditez: $VENTOY_PATH/ventoy/ubuntu-autoinstall/user-data"
echo ""
echo "Options ventoy.json:"
echo "  • autosel: 1 = Sélection automatique du template"
echo "  • timeout: 1 = 1 seconde avant démarrage auto"
echo ""
echo "Ensuite, démontez la clé et bootez dessus !"

