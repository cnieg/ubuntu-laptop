# Ubuntu Laptop Factory USB (NVMe)

Factory autoinstall ISO for Ubuntu Server 25.10.

## Features
- NVMe only (/dev/nvme0n1)
- EFI + LUKS swap (32GB) + LUKS root
- Btrfs subvolumes (@, @home, @var, @snapshots)
- TPM auto-unlock
- Hibernation supported
- Recovery key generated
- Zero prompt factory mode (ARMED file required)

## Usage
1. Replace password hash in nocloud/user-data
2. Add ARMED file inside NOLOUD/ to enable wipe
3. Build ISO using Cubic or custom tooling
4. Boot and wait

Recovery key will be stored in:
/root/recovery/luks-root-recovery.key
