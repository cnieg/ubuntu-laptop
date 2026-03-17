#!/usr/bin/env bash
set -e

mkdir -p build/ventoy/ubuntu-autoinstall
cp ventoy/ventoy.json build/ventoy/
cp nocloud/user-data build/ventoy/ubuntu-autoinstall/
cp nocloud/meta-data build/ventoy/ubuntu-autoinstall/

(
  cd live-injection-src
  chmod +x pack.sh
  ./pack.sh
)

cp live-injection-src/live_injection.tar.gz build/ventoy/
