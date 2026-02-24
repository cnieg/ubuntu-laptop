#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 /usr/local/sbin
cat > /usr/local/sbin/proxy-autoswitch <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONF="/etc/proxy-autoswitch.conf"
[[ -f "$CONF" ]] && source "$CONF"

: "${PROXY_URL:?Missing PROXY_URL in $CONF}"
: "${NO_PROXY_LIST:?Missing NO_PROXY_LIST in $CONF}"
: "${MATCH_REGEX:=^172\.(30|31)\.}"

has_matching_ip() {
  ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | grep -Eq "$MATCH_REGEX"
}

apply_proxy() {
  mkdir -p /etc/apt/apt.conf.d
  cat > /etc/apt/apt.conf.d/95proxy <<EOF
Acquire::http::Proxy "$PROXY_URL";
Acquire::https::Proxy "$PROXY_URL";
EOF

  mkdir -p /etc/environment.d
  cat > /etc/environment.d/95proxy.conf <<EOF
http_proxy=$PROXY_URL
https_proxy=$PROXY_URL
HTTP_PROXY=$PROXY_URL
HTTPS_PROXY=$PROXY_URL
no_proxy=$NO_PROXY_LIST
NO_PROXY=$NO_PROXY_LIST
EOF

  mkdir -p /etc/profile.d
  cat > /etc/profile.d/proxy.sh <<EOF
export http_proxy=$PROXY_URL
export https_proxy=$PROXY_URL
export HTTP_PROXY=$PROXY_URL
export HTTPS_PROXY=$PROXY_URL
export no_proxy=$NO_PROXY_LIST
export NO_PROXY=$NO_PROXY_LIST
EOF
  chmod +x /etc/profile.d/proxy.sh

  if command -v snap >/dev/null 2>&1; then
    snap set system proxy.http="$PROXY_URL" 2>/dev/null || true
    snap set system proxy.https="$PROXY_URL" 2>/dev/null || true
  fi
}

remove_proxy() {
  rm -f /etc/apt/apt.conf.d/95proxy || true
  rm -f /etc/environment.d/95proxy.conf || true
  rm -f /etc/profile.d/proxy.sh || true

  if command -v snap >/dev/null 2>&1; then
    snap unset system proxy.http 2>/dev/null || true
    snap unset system proxy.https 2>/dev/null || true
  fi
}

state_file="/run/proxy-autoswitch.state"
current="off"
has_matching_ip && current="on"
previous="$(cat "$state_file" 2>/dev/null || true)"

[[ "$current" == "$previous" ]] && exit 0

if [[ "$current" == "on" ]]; then
  apply_proxy
else
  remove_proxy
fi

echo "$current" > "$state_file"

EOF
chmod 0755 /usr/local/sbin/proxy-autoswitch

cat > /etc/proxy-autoswitch.conf <<'EOF'
PROXY_URL="http://172.30.11.253:8080"
NO_PROXY_LIST="localhost,127.0.0.1,::1,.cnieg.fr,.iegp.edfgdf.fr"
MATCH_REGEX='^172\.(30|31)\.'

EOF
chmod 0644 /etc/proxy-autoswitch.conf

cat > /etc/systemd/system/proxy-autoswitch.service <<'EOF'
[Unit]
Description=Auto enable/disable proxy depending on IP range (172.30/172.31)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/proxy-autoswitch

EOF

cat > /etc/systemd/system/proxy-autoswitch.timer <<'EOF'
[Unit]
Description=Run proxy autoswitch periodically

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s

[Install]
WantedBy=timers.target

EOF

systemctl daemon-reload
systemctl enable --now proxy-autoswitch.timer
/usr/local/sbin/proxy-autoswitch || true
