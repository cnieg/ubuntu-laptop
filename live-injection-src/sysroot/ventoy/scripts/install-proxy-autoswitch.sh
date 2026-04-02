#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 /usr/local/bin
install -d -m 0755 /etc/NetworkManager/dispatcher.d

cat > /usr/local/bin/proxy-autoswitch.sh <<'AUTOSWITCH'
#!/usr/bin/env bash
set -euo pipefail

PROXY_URL="http://172.30.11.253:8080"
NO_PROXY_LIST="localhost,127.0.0.1,::1,.cnieg.fr,.iegp.edfgdf.fr"
APT_CONF="/etc/apt/apt.conf.d/90proxy"

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
  echo "[proxy] enabling proxy"

  mkdir -p /etc/apt/apt.conf.d
  cat > "$APT_CONF" <<APT_EOF
Acquire::http::Proxy "$PROXY_URL";
Acquire::https::Proxy "$PROXY_URL";
Acquire::Retries "2";
Acquire::http::Timeout "20";
Acquire::https::Timeout "20";
APT_EOF

  cat > /etc/environment <<ENV_EOF
http_proxy=$PROXY_URL
https_proxy=$PROXY_URL
HTTP_PROXY=$PROXY_URL
HTTPS_PROXY=$PROXY_URL
no_proxy=$NO_PROXY_LIST
NO_PROXY=$NO_PROXY_LIST
ENV_EOF
else
  echo "[proxy] disabling proxy"
  rm -f "$APT_CONF"

  cat > /etc/environment <<'ENV_EOF'
http_proxy=
https_proxy=
HTTP_PROXY=
HTTPS_PROXY=
no_proxy=
NO_PROXY=
ENV_EOF
fi
AUTOSWITCH

chmod 0755 /usr/local/bin/proxy-autoswitch.sh

cat > /etc/NetworkManager/dispatcher.d/90-proxy <<'DISPATCHER'
#!/usr/bin/env bash

INTERFACE="$1"
STATUS="$2"

case "$STATUS" in
  up|dhcp4-change|connectivity-change)
    /usr/local/bin/proxy-autoswitch.sh
    ;;
esac
DISPATCHER

chmod 0755 /etc/NetworkManager/dispatcher.d/90-proxy

/usr/local/bin/proxy-autoswitch.sh || true
