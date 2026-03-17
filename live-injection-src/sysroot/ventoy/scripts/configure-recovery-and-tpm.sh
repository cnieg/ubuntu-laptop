#!/usr/bin/env bash
set -euo pipefail
ROOT_PART="/dev/nvme0n1p4"
install -d -m 0700 /root/recovery
umask 077
openssl rand -out /root/recovery/luks-root-recovery.key 32
cryptsetup luksAddKey "$ROOT_PART" /root/recovery/luks-root-recovery.key || true
