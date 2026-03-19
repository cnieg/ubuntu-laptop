#!/usr/bin/env bash
set -euo pipefail

PROXY_URL="http://172.30.11.253:8080"
NO_PROXY_LIST="localhost,127.0.0.1,::1,.cnieg.fr,.iegp.edfgdf.fr"

IPS="$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ' || true)"

need_proxy=0
for ip in $IPS; do
  case "$ip" in
    172.30.*|172.31.*)
      need_proxy=1
      break
      ;;
  esac
done

if [ "$need_proxy" -eq 1 ]; then
  mkdir -p /etc/apt/apt.conf.d
  cat > /etc/apt/apt.conf.d/90proxy <<EOF
Acquire::http::Proxy "$PROXY_URL";
Acquire::https::Proxy "$PROXY_URL";
Acquire::Retries "2";
Acquire::http::Timeout "20";
Acquire::https::Timeout "20";
EOF

  export http_proxy="$PROXY_URL"
  export https_proxy="$PROXY_URL"
  export HTTP_PROXY="$PROXY_URL"
  export HTTPS_PROXY="$PROXY_URL"
  export no_proxy="$NO_PROXY_LIST"
  export NO_PROXY="$NO_PROXY_LIST"
fi
