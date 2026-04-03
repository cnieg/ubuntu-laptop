# Ubuntu Laptop Factory USB (NVMe) — Autoinstall

- NVMe only: /dev/nvme0n1
- EFI 512MiB, Swap 32GiB (LUKS2), Root (LUKS2) + Btrfs subvolumes (@, @home, @var, @snapshots)
- Hibernation: swap LUKS (`cryptswap`) with persistent keyfile included in initramfs + `resume=/dev/mapper/cryptswap`
- TPM auto-unlock for root
- Proxy nomade: active/désactive proxy selon IP 172.30/172.31
- Factory mode: wipe only if /cdrom/NOLOUD/ARMED exists

## Build ISO
```bash
chmod +x scripts/*.sh
./scripts/build-iso.sh ubuntu-25.10-live-server-amd64.iso build/ubuntu-25.10-factory.iso
```

## Proxy nomade
Après install, un timer systemd applique ou retire le proxy automatiquement:
- /etc/proxy-autoswitch.conf
- /usr/local/sbin/proxy-autoswitch
- systemd: proxy-autoswitch.timer

## Chiffrement root/swap (parité sécurité)
- `/etc/crypttab` est régénéré pour inclure:
  - `cryptroot` (UUID root LUKS + option TPM2)
  - `cryptswap` (UUID swap LUKS + keyfile persistant)
- keyfile swap: `/etc/cryptsetup-keys.d/cryptswap.key` (copié dans initramfs via `KEYFILE_PATTERN`)
- reprise hibernation: `/etc/initramfs-tools/conf.d/resume` pointe vers `/dev/mapper/cryptswap`
