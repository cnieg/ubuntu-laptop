# Ubuntu Laptop - Custom ISO

ISO Ubuntu Server 25.10 personnalisée pour laptops avec :
- NetworkManager + iwd (backend Wi-Fi moderne)
- Packages de base : btop, curl, git, wget, net-tools
- Support btrfs + cryptsetup (LUKS)
- Ansible pré-installé
- Configuration automatique via cloud-init

## Build automatique

L'ISO est buildée automatiquement via GitHub Actions à chaque push sur `main`.

### Télécharger l'ISO

1. Aller dans l'onglet **Actions**
2. Sélectionner le dernier workflow réussi
3. Télécharger l'artifact `ubuntu-25.10-custom-iso`

## Build local

### Prérequis
```bash
sudo apt install squashfs-tools xorriso isolinux rsync wget
```

### Builder l'ISO
```bash
chmod +x scripts/build-iso.sh
./scripts/build-iso.sh
```

L'ISO sera créée dans `~/iso-build/ubuntu-25.10-custom.iso`

## Déployer sur Ventoy

### Prérequis
- Une clé USB avec Ventoy installé
- Le fichier `oasis-logo.png` (optionnel)

### Déploiement
```bash
chmod +x scripts/deploy-to-ventoy.sh
./scripts/deploy-to-ventoy.sh
```

Le script va :
1. Détecter automatiquement la clé Ventoy
2. Copier l'ISO
3. Créer la structure cloud-init avec user-data et meta-data
4. Copier le logo (si présent)

## Configuration cloud-init

La configuration par défaut :
- **Hostname**: ubuntu-laptop
- **Username**: ubuntu-admin
- **Clavier**: FR
- **Locale**: fr_FR.UTF-8
- **Stockage**: LUKS + btrfs avec compression zstd
- **Réseau**: NetworkManager + iwd

### Personnaliser

Éditez `/ventoy/ubuntu-autoinstall/user-data` sur la clé Ventoy pour modifier :
- Les mots de passe
- Les clés SSH
- Le layout du disque
- Les packages supplémentaires

## Créer une release

Pour créer une release avec l'ISO :
```bash
git tag v1.0.0
git push origin v1.0.0
```

L'ISO sera automatiquement attachée à la release GitHub.

## Packages installés

### Réseau
- network-manager
- network-manager-openvpn
- iwd (backend Wi-Fi)

### Outils
- btop (monitoring système)
- curl, wget
- git
- net-tools

### Filesystem et sécurité
- btrfs-progs
- cryptsetup
- cryptsetup-initramfs

### Automatisation
- ansible

## License

MIT

