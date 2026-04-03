#!/usr/bin/env bash

log_device_discovery() {
  echo "[device-discovery] $*" >&2
}

fail_device_discovery() {
  log_device_discovery "ERROR: $*"
  return 1
}

resolve_device_spec() {
  local spec="$1"

  case "$spec" in
    UUID=*)
      blkid -U "${spec#UUID=}" 2>/dev/null || true
      ;;
    PARTUUID=*)
      blkid -t "PARTUUID=${spec#PARTUUID=}" -o device 2>/dev/null | head -n1 || true
      ;;
    /dev/*)
      readlink -f "$spec" 2>/dev/null || echo "$spec"
      ;;
    *)
      echo "$spec"
      ;;
  esac
}

extract_root_from_cmdline() {
  local root_spec
  root_spec="$(sed -n 's/.*\broot=\([^[:space:]]\+\).*/\1/p' /proc/cmdline | head -n1)"

  if [ -n "$root_spec" ]; then
    resolve_device_spec "$root_spec"
  fi
}

extract_root_from_fstab() {
  local fstab_path="${1:-/etc/fstab}"

  [ -f "$fstab_path" ] || return 0

  awk '$1 !~ /^#/ && $2 == "/" { print $1; exit }' "$fstab_path" | {
    read -r root_spec || true
    [ -n "$root_spec" ] && resolve_device_spec "$root_spec"
  }
}

detect_root_source() {
  local mountpoint="${1:-/}"
  local source=""

  if source="$(findmnt -no SOURCE "$mountpoint" 2>/dev/null)" && [ -n "$source" ]; then
    source="$(resolve_device_spec "$source")"
    log_device_discovery "root source from findmnt(${mountpoint}): ${source}"
    echo "$source"
    return 0
  fi

  if source="$(extract_root_from_cmdline)" && [ -n "$source" ]; then
    log_device_discovery "root source from /proc/cmdline: ${source}"
    echo "$source"
    return 0
  fi

  if source="$(extract_root_from_fstab)" && [ -n "$source" ]; then
    log_device_discovery "root source from /etc/fstab: ${source}"
    echo "$source"
    return 0
  fi

  fail_device_discovery "unable to determine root source for mountpoint ${mountpoint}"
}

detect_root_partition() {
  local mountpoint="${1:-/}"
  local source pkname

  source="$(detect_root_source "$mountpoint")" || return 1

  if [[ "$source" == /dev/mapper/* || "$source" == /dev/dm-* ]]; then
    pkname="$(lsblk -no PKNAME "$source" 2>/dev/null | head -n1)"
    if [ -n "$pkname" ]; then
      source="/dev/$pkname"
      log_device_discovery "root partition under mapper: ${source}"
      echo "$source"
      return 0
    fi
  fi

  log_device_discovery "root partition resolved directly: ${source}"
  echo "$source"
}

detect_root_uuid() {
  local mountpoint="${1:-/}"
  local source root_uuid

  source="$(detect_root_source "$mountpoint")" || return 1

  root_uuid="$(blkid -s UUID -o value "$source" 2>/dev/null | head -n1 || true)"
  if [ -n "$root_uuid" ]; then
    log_device_discovery "root UUID from blkid(${source}): ${root_uuid}"
    echo "$root_uuid"
    return 0
  fi

  source="$(detect_root_partition "$mountpoint")" || return 1
  root_uuid="$(blkid -s UUID -o value "$source" 2>/dev/null | head -n1 || true)"
  if [ -n "$root_uuid" ]; then
    log_device_discovery "root UUID from blkid(${source}): ${root_uuid}"
    echo "$root_uuid"
    return 0
  fi

  fail_device_discovery "unable to determine root UUID"
}

detect_swap_uuid() {
  local swap_spec=""
  local swap_dev=""
  local swap_uuid=""

  if [ -f /proc/swaps ]; then
    swap_dev="$(awk 'NR>1 { print $1; exit }' /proc/swaps)"
    if [ -n "$swap_dev" ]; then
      swap_dev="$(resolve_device_spec "$swap_dev")"
      swap_uuid="$(blkid -s UUID -o value "$swap_dev" 2>/dev/null | head -n1 || true)"
      if [ -n "$swap_uuid" ]; then
        log_device_discovery "swap UUID from /proc/swaps (${swap_dev}): ${swap_uuid}"
        echo "$swap_uuid"
        return 0
      fi
    fi
  fi

  if [ -f /etc/fstab ]; then
    swap_spec="$(awk '$1 !~ /^#/ && $3 == "swap" { print $1; exit }' /etc/fstab)"
    if [ -n "$swap_spec" ]; then
      swap_dev="$(resolve_device_spec "$swap_spec")"
      swap_uuid="$(blkid -s UUID -o value "$swap_dev" 2>/dev/null | head -n1 || true)"
      if [ -n "$swap_uuid" ]; then
        log_device_discovery "swap UUID from /etc/fstab (${swap_dev}): ${swap_uuid}"
        echo "$swap_uuid"
        return 0
      fi
    fi
  fi

  swap_dev="$(blkid -t TYPE=swap -o device 2>/dev/null | head -n1 || true)"
  if [ -n "$swap_dev" ]; then
    swap_uuid="$(blkid -s UUID -o value "$swap_dev" 2>/dev/null | head -n1 || true)"
    if [ -n "$swap_uuid" ]; then
      log_device_discovery "swap UUID from blkid scan (${swap_dev}): ${swap_uuid}"
      echo "$swap_uuid"
      return 0
    fi
  fi

  log_device_discovery "swap UUID not found; returning explicit none"
  echo "none"
}

extract_swap_device_from_fstab() {
  local fstab_path="${1:-/etc/fstab}"
  local swap_spec=""
  local swap_dev=""

  [ -f "$fstab_path" ] || return 0

  swap_spec="$(awk '$1 !~ /^#/ && $3 == "swap" { print $1; exit }' "$fstab_path")"
  if [ -z "$swap_spec" ]; then
    return 0
  fi

  swap_dev="$(resolve_device_spec "$swap_spec")"
  if [ -n "$swap_dev" ]; then
    log_device_discovery "swap device from ${fstab_path} (${swap_spec}): ${swap_dev}"
    echo "$swap_dev"
  fi
}
