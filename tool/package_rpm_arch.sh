#!/usr/bin/env bash
# Packs build/BesideOS (made by tool/build_linux.sh) into build/besideos-linux-x86_64.rpm and
# build/besideos-linux-x86_64.pkg.tar.zst (Arch). Same layout as the .deb. Needs: fpm (rpm output), zstd, tar.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
[ -x build/BesideOS/besideos ] || { echo "run tool/build_linux.sh first" >&2; exit 1; }
version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)

stage=build/pkgroot
rm -rf "$stage" && mkdir -p "$stage/opt" "$stage/usr/bin" "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/512x512/apps"
cp -a build/BesideOS "$stage/opt/besideos"
ln -s /opt/besideos/besideos "$stage/usr/bin/besideos"
cp web/icons/Icon-512.png "$stage/usr/share/icons/hicolor/512x512/apps/besideos.png"
cat > "$stage/usr/share/applications/besideos.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=BesideOS
Comment=Install a second operating system beside this one
Exec=/usr/bin/besideos
Icon=besideos
Terminal=false
Categories=System;Utility;
DESK
chmod -R go-w "$stage"
find "$stage/opt" -type d -exec chmod 755 {} +

fpm -s dir -t rpm -n besideos -v "$version" --architecture x86_64 --license MIT \
  --url https://besideos.com --maintainer "skurtz0 <areyouskurtz@gmail.com>" \
  --description "Install a second operating system beside this one" \
  --depends gtk3 --depends polkit --rpm-os linux \
  -p build/besideos-linux-x86_64.rpm -C "$stage" .

size=$(du -sb "$stage" | cut -f1)
cat > "$stage/.PKGINFO" <<INFO
pkgname = besideos
pkgbase = besideos
pkgver = $version-1
pkgdesc = Install a second operating system beside this one
url = https://besideos.com
builddate = $(date +%s)
packager = skurtz0 <areyouskurtz@gmail.com>
size = $size
arch = x86_64
license = MIT
depend = gtk3
depend = polkit
INFO
(cd "$stage" && tar --zstd --owner=0 --group=0 --numeric-owner -cf ../besideos-linux-x86_64.pkg.tar.zst .PKGINFO opt usr)
echo "OK: build/besideos-linux-x86_64.rpm, build/besideos-linux-x86_64.pkg.tar.zst"
