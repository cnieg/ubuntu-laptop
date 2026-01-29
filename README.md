# Ubuntu Laptop - Custom ISO

ISO Ubuntu Desktop 25.10 personnalisée pour laptops avec :
- **GNOME Desktop** (ubuntu-desktop-minimal)
- **Wayland** activé par défaut
- NetworkManager + iwd (backend Wi-Fi moderne)
- OpenConnect VPN
- Packages de base : btop, curl, git, wget, net-tools
- Support btrfs + cryptsetup (LUKS)
- Ansible pré-installé
- Configuration automatique via cloud-init

## 🚀 Installation rapide sur Ventoy

### Méthode 1 : Package complet (recommandé)

1. Télécharger le **package Ventoy** depuis [Actions](https://github.com/cnieg/ubuntu-laptop/actions) ou les [Releases](https://github.com/cnieg/ubuntu-laptop/releases)
2. Extraire l'archive : `tar xzf ventoy-package.tar.gz`
3. Copier le contenu sur votre clé Ventoy :
```bash
   # Monter votre clé Ventoy
   # Puis copier les fichiers
   cp ventoy-package/ubuntu-25.10-custom.iso /media/$USER/Ventoy/
   cp -r ventoy-package/ventoy/* /media/$USER/Ventoy/ventoy/
```
4. Démonter et booter !

Le package contient :
- ✅ L'ISO
- ✅ Le fichier ventoy.json configuré
- ✅ Les fichiers cloud-init (user-data, meta-data)
- ✅ Le logo Oasis
- ✅ Un README avec les instructions

### Méthode 2 : Script de déploiement (développement local)
```bash
# Builder l'ISO localement
./scripts/build-iso.sh

# Déployer sur Ventoy
./scripts/deploy-to-ventoy.sh
```

## 📦 Télécharger depuis GitHub

### Via GitHub Actions (builds automatiques)

1. Aller dans l'onglet **[Actions](https://github.com/cnieg/ubuntu-laptop/actions)**
2. Sélectionner le dernier workflow réussi
3. Télécharger :
   - `ventoy-package` : Archive complète prête pour Ventoy
   - `ubuntu-25.10-custom-iso` : ISO seule (si besoin)

### Via Releases (versions stables)

Pour les versions taguées, télécharger depuis les [Releases](https://github.com/cnieg/ubuntu-laptop/releases) :
- `ubuntu-25.10-custom.iso` : ISO
- `ubuntu-25.10-custom.iso.sha256` : Checksum
- `ventoy-package.tar.gz` : Package Ventoy complet

## 🛠️ Build local

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

## ⚙️ Configuration cloud-init

La configuration par défaut (dans `ventoy/ubuntu-autoinstall/user-data`) :
- **Hostname**: ubuntu-laptop
- **Username**: ubuntu-admin
- **Password**: (hashé dans le fichier)
- **Password LUKS**: LUKS-cnieg
- **Clavier**: FR
- **Locale**: fr_FR.UTF-8
- **Stockage**: LUKS + btrfs avec compression zstd
- **Réseau**: NetworkManager + iwd

### Personnaliser

Pour modifier la configuration :

1. **Pour les builds GitHub** : Éditer les fichiers dans le repo
```bash
   vim ventoy/ubuntu-autoinstall/user-data
   git commit -m "feat: update configuration"
   git push
```

2. **Pour un déploiement local** : Le script copie les fichiers du repo

3. **Sur une clé Ventoy existante** : Éditer directement
```bash
   vim /media/$USER/Ventoy/ventoy/ubuntu-autoinstall/user-data
```

### Générer un nouveau hash de mot de passe
```bash
openssl passwd -6
# Entre ton mot de passe
# Remplace le hash dans user-data
```

## 📂 Structure du repository

ubuntu-laptop/
├── .github/
│   └── workflows/
│       └── build-iso.yml          # CI/CD
├── ventoy/
│   ├── ubuntu-autoinstall/
│   │   ├── user-data              # Configuration cloud-init
│   │   └── meta-data              # Métadonnées
│   └── ventoy.json                # Config Ventoy
├── scripts/
│   ├── build-iso.sh               # Build ISO
│   └── deploy-to-ventoy.sh        # Déploiement Ventoy (optionnel)
├── assets/
│   └── oasis-logo.png             # Logo copié dans /usr/share/pixmaps
└── README.md

## 🏷️ Créer une release

Pour créer une release avec l'ISO et le package Ventoy :
```bash
git tag v1.0.0
git push origin v1.0.0
```

L'ISO et le package Ventoy seront automatiquement attachés à la release GitHub.

## Packages installés

### Desktop
- ubuntu-desktop-minimal (GNOME)
- GDM avec Wayland activé

### Réseau
- network-manager
- network-manager-openconnect (VPN)
- network-manager-openconnect-gnome
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

