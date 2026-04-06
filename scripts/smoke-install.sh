#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET_ISO_NAME="${TARGET_ISO_NAME:-resolute-live-server-amd64.iso}"
TARGET_ISO_PATH="${TARGET_ISO_PATH:-${REPO_ROOT}/build/ventoy/${TARGET_ISO_NAME}}"
SMOKE_TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-420}"
SMOKE_LOG_PATH="${SMOKE_LOG_PATH:-${REPO_ROOT}/build/ventoy/smoke-install.log}"
SEED_ISO_PATH="${SEED_ISO_PATH:-${REPO_ROOT}/build/ventoy/nocloud-seed.iso}"
SMOKE_STRICT_CLOUD_INIT="${SMOKE_STRICT_CLOUD_INIT:-0}"

required_tools=(bash qemu-system-x86_64 xorriso timeout grep)
for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: missing required dependency for smoke install: ${tool}" >&2
    exit 1
  fi
done

if [[ ! -f "${TARGET_ISO_PATH}" ]]; then
  echo "ERROR: smoke install target ISO not found: ${TARGET_ISO_PATH}" >&2
  exit 1
fi

if [[ ! -f "${REPO_ROOT}/nocloud/user-data" || ! -f "${REPO_ROOT}/nocloud/meta-data" ]]; then
  echo "ERROR: NoCloud seed files are required for smoke install" >&2
  exit 1
fi

for script in \
  "${REPO_ROOT}/live-injection-src/sysroot/ventoy/scripts/prepare-proxy.sh" \
  "${REPO_ROOT}/live-injection-src/sysroot/ventoy/scripts/configure-networkmanager.sh" \
  "${REPO_ROOT}/live-injection-src/sysroot/ventoy/scripts/install-proxy-autoswitch.sh"; do
  bash -n "${script}"
done

xorriso -as mkisofs \
  -V CIDATA \
  -o "${SEED_ISO_PATH}" \
  "${REPO_ROOT}/nocloud/user-data" \
  "${REPO_ROOT}/nocloud/meta-data" >/dev/null 2>&1

mkdir -p "$(dirname "${SMOKE_LOG_PATH}")"
rm -f "${SMOKE_LOG_PATH}"

set +e
timeout "${SMOKE_TIMEOUT_SECONDS}" qemu-system-x86_64 \
  -m 4096 \
  -smp 2 \
  -nographic \
  -serial mon:stdio \
  -boot d \
  -cdrom "${TARGET_ISO_PATH}" \
  -drive file="${SEED_ISO_PATH}",media=cdrom,readonly=on \
  -no-reboot \
  -snapshot >"${SMOKE_LOG_PATH}" 2>&1
qemu_exit=$?
set -e

if [[ ${qemu_exit} -ne 0 && ${qemu_exit} -ne 124 ]]; then
  echo "ERROR: qemu exited unexpectedly with code ${qemu_exit}" >&2
  tail -n 80 "${SMOKE_LOG_PATH}" >&2 || true
  exit 1
fi

if ! grep -Eqi 'Ubuntu|Linux version|initramfs' "${SMOKE_LOG_PATH}"; then
  echo "ERROR: smoke log does not show expected early boot/init markers" >&2
  tail -n 120 "${SMOKE_LOG_PATH}" >&2 || true
  exit 1
fi

if ! grep -Eqi 'cloud-init|NoCloud|cidata' "${SMOKE_LOG_PATH}"; then
  if [[ "${SMOKE_STRICT_CLOUD_INIT}" == "1" ]]; then
    echo "ERROR: smoke log does not show NoCloud/cloud-init markers (strict mode enabled)" >&2
    tail -n 120 "${SMOKE_LOG_PATH}" >&2 || true
    exit 1
  fi

  if grep -Eqi 'GNU GRUB|Try or Install Ubuntu Server|The highlighted entry will be executed automatically' "${SMOKE_LOG_PATH}"; then
    echo "WARN: NoCloud/cloud-init markers were not observed on serial output; proceeding because GRUB/installer menu markers were observed" >&2
  else
    echo "ERROR: smoke log does not show NoCloud/cloud-init markers or GRUB/installer menu markers" >&2
    tail -n 120 "${SMOKE_LOG_PATH}" >&2 || true
    exit 1
  fi
fi

echo "SUCCESS: smoke install reached boot/init markers"
