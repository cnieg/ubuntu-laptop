#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET_ISO_NAME="${TARGET_ISO_NAME:-resolute-live-server-amd64.iso}"
TARGET_ISO_PATH="${TARGET_ISO_PATH:-${REPO_ROOT}/${TARGET_ISO_NAME}}"

required_tools=(bash cp mkdir tar chmod sed dos2unix)
for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: missing required dependency: ${tool}" >&2
    exit 1
  fi
done

required_assets=(
  "${REPO_ROOT}/ventoy/ventoy.json"
  "${REPO_ROOT}/nocloud/user-data"
  "${REPO_ROOT}/nocloud/meta-data"
)
for asset in "${required_assets[@]}"; do
  if [[ ! -f "${asset}" ]]; then
    echo "ERROR: required asset not found: ${asset}" >&2
    exit 1
  fi
done

if [[ ! -f "${TARGET_ISO_PATH}" ]]; then
  echo "ERROR: target ISO not found: ${TARGET_ISO_PATH}" >&2
  echo "Hint: set TARGET_ISO_PATH=/absolute/path/to/your.iso or TARGET_ISO_NAME=file.iso" >&2
  exit 1
fi

mkdir -p "${REPO_ROOT}/build/ventoy/ubuntu-autoinstall"
cp "${REPO_ROOT}/nocloud/user-data" "${REPO_ROOT}/build/ventoy/ubuntu-autoinstall/"
cp "${REPO_ROOT}/nocloud/meta-data" "${REPO_ROOT}/build/ventoy/ubuntu-autoinstall/"
cp "${TARGET_ISO_PATH}" "${REPO_ROOT}/build/ventoy/${TARGET_ISO_NAME}"

(
  cd "${REPO_ROOT}/live-injection-src"
  chmod +x pack.sh
  ./pack.sh
)

if [[ ! -f "${REPO_ROOT}/live-injection-src/live_injection.tar.gz" ]]; then
  echo "ERROR: expected live injection archive was not generated" >&2
  exit 1
fi

cp "${REPO_ROOT}/live-injection-src/live_injection.tar.gz" "${REPO_ROOT}/build/ventoy/"

sed "s|/resolute-live-server-amd64.iso|/${TARGET_ISO_NAME}|g" \
  "${REPO_ROOT}/ventoy/ventoy.json" > "${REPO_ROOT}/build/ventoy/ventoy.json"

expected_runtime_paths=(
  "${REPO_ROOT}/build/ventoy/ventoy.json"
  "${REPO_ROOT}/build/ventoy/ubuntu-autoinstall/user-data"
  "${REPO_ROOT}/build/ventoy/ubuntu-autoinstall/meta-data"
  "${REPO_ROOT}/build/ventoy/live_injection.tar.gz"
  "${REPO_ROOT}/build/ventoy/${TARGET_ISO_NAME}"
)
for runtime_path in "${expected_runtime_paths[@]}"; do
  if [[ ! -f "${runtime_path}" ]]; then
    echo "ERROR: runtime bundle path is missing: ${runtime_path}" >&2
    exit 1
  fi
done

if ! grep -q "\"image\": \"/${TARGET_ISO_NAME}\"" "${REPO_ROOT}/build/ventoy/ventoy.json"; then
  echo "ERROR: ventoy.json was not rendered with the target ISO path" >&2
  exit 1
fi
if ! grep -q '"template": "/ventoy/ubuntu-autoinstall/user-data"' "${REPO_ROOT}/build/ventoy/ventoy.json"; then
  echo "ERROR: ventoy.json template path is inconsistent" >&2
  exit 1
fi
if ! grep -q '"archive": "/ventoy/live_injection.tar.gz"' "${REPO_ROOT}/build/ventoy/ventoy.json"; then
  echo "ERROR: ventoy.json injection archive path is inconsistent" >&2
  exit 1
fi

echo "SUCCESS: Ventoy bundle generated at ${REPO_ROOT}/build/ventoy"
