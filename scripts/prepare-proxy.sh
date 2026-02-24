#!/usr/bin/env bash
set -euo pipefail

PROXY_URL="http://172.30.11.253:8080"
NO_PROXY_LIST="localhost,127.0.0.1,::1,.cnieg.fr,.iegp.edfgdf.fr"
MATCH_REGEX='^172\.(30|31)\.'

log(){ echo "[prepare-proxy] $*"; }

IPS=""
for i in $(seq 1 30); do
  IPS="$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ' || true)"
  [[ -n "$IPS" ]] && break
  sleep 1
done

need_proxy=0
for ip in $IPS; do
  if echo "$ip" | grep -Eq "$MATCH_REGEX"; then
    need_proxy=1
    break
  fi
done

if [[ "$need_proxy" -ne 1 ]]; then
  log "No proxy needed for installer. IPs=[$IPS]"
  exit 0
fi

log "Proxy enabled for installer (IPs=[$IPS]) PROXY=$PROXY_URL NO_PROXY=$NO_PROXY_LIST"

mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/95proxy <<EOF
Acquire::http::Proxy "$PROXY_URL";
Acquire::https::Proxy "$PROXY_URL";
EOF

export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export no_proxy="$NO_PROXY_LIST"
export NO_PROXY="$NO_PROXY_LIST"

log "Installer proxy configured."
