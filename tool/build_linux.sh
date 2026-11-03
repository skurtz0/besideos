#!/usr/bin/env bash
# Builds the Linux app and packs it, with its engine scripts, into build/BesideOS-linux.tar.gz.
# Needs: Flutter with Linux desktop support (clang, cmake, ninja, GTK 3 headers).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
flutter build linux --release

bundle=build/linux/x64/release/bundle
[ -x "$bundle/besideos" ] || { echo "besideos missing in $bundle" >&2; exit 1; }
rm -rf build/BesideOS && mkdir -p build/BesideOS/engine
cp -a "$bundle"/. build/BesideOS/
cp probe/linux/besideos-grub.sh probe/linux/boot-entries.sh build/BesideOS/engine/
chmod +x build/BesideOS/engine/*.sh
tar -C build -czf build/BesideOS-linux.tar.gz BesideOS
echo "OK: build/BesideOS-linux.tar.gz ($(du -h build/BesideOS-linux.tar.gz | cut -f1))"
