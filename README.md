# Ubuntu Laptop Factory USB (NVMe) — Autoinstall

- NVMe only: /dev/nvme0n1
- EFI 512MiB, Swap 32GiB (LUKS2), Root (LUKS2) + Btrfs subvolumes (@, @home, @var, @snapshots)
- Hibernation: **supported with encrypted swap** (`cryptswap`) + initramfs resume mapping
- TPM auto-unlock for root
- Proxy nomade: active/désactive proxy selon IP 172.30/172.31
- Factory mode: wipe only if /cdrom/NOLOUD/ARMED exists

## Build ISO
```bash
chmod +x scripts/*.sh
./scripts/build-iso.sh ubuntu-25.10-live-server-amd64.iso build/ubuntu-25.10-factory.iso
```

## Chiffrement root/swap + reprise (resume)
Le flux post-install configure explicitement:
- `/etc/crypttab` pour `cryptroot` (UUID root LUKS détecté) et `cryptswap`.
- keyfile persistant swap: `/etc/cryptsetup-keys.d/cryptswap.key`.
- inclusion des keyfiles dans l'initramfs via `/etc/cryptsetup-initramfs/conf-hook`.
- reprise hibernation via `/etc/initramfs-tools/conf.d/resume` (`RESUME=/dev/mapper/cryptswap`).
- ligne swap `fstab` pointant vers `/dev/mapper/cryptswap`.

Mode supporté: **hibernation chiffrée supportée** (swap LUKS dédié + resume initramfs).

## Proxy nomade
Après install, un timer systemd applique ou retire le proxy automatiquement:
- /etc/proxy-autoswitch.conf
- /usr/local/sbin/proxy-autoswitch
- systemd: proxy-autoswitch.timer
