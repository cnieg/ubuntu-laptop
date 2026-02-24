# Ubuntu Laptop Factory USB (NVMe) — Autoinstall

- NVMe only: /dev/nvme0n1
- EFI 512MiB, Swap 32GiB (LUKS2), Root (LUKS2) + Btrfs subvolumes (@, @home, @var, @snapshots)
- Hibernation: swap LUKS with persistent keyfile in initramfs
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
