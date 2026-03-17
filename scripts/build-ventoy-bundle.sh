#!/usr/bin/env bash
set -e
mkdir -p build/ventoy/ubuntu-autoinstall
cp ventoy/ventoy.json build/ventoy/
cp nocloud/user-data build/ventoy/ubuntu-autoinstall/
cp nocloud/meta-data build/ventoy/ubuntu-autoinstall/
tar -czf build/ventoy/live_injection.tar.gz -C live-injection-src/sysroot .
cd build
zip -r ventoy-bundle.zip ventoy
