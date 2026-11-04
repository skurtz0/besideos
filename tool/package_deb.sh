#!/usr/bin/env bash
# Packs build/BesideOS (made by tool/build_linux.sh) into build/besideos-linux-amd64.deb.
# Installs to /opt/besideos with a /usr/bin/besideos link and a menu entry; the engine scripts stay next to the app.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
[ -x build/BesideOS/besideos ] || { echo "run tool/build_linux.sh first" >&2; exit 1; }
version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)

pkg=build/deb
rm -rf "$pkg" && mkdir -p "$pkg/DEBIAN" "$pkg/opt" "$pkg/usr/bin" "$pkg/usr/share/applications" "$pkg/usr/share/icons/hicolor/512x512/apps"
cp -a build/BesideOS "$pkg/opt/besideos"
ln -s /opt/besideos/besideos "$pkg/usr/bin/besideos"
cp web/icons/Icon-512.png "$pkg/usr/share/icons/hicolor/512x512/apps/besideos.png"
cat > "$pkg/usr/share/applications/besideos.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=BesideOS
Comment=Install a second operating system beside this one
Exec=/usr/bin/besideos
Icon=besideos
Terminal=false
Categories=System;Utility;
DESK
cat > "$pkg/DEBIAN/control" <<CTRL
Package: besideos
Version: $version
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, policykit-1 | pkexec
Maintainer: skurtz0 <areyouskurtz@gmail.com>
Homepage: https://besideos.com
Description: Install a second operating system beside this one
 BesideOS prepares and installs another operating system next to the one
 you are running, without a USB stick.
CTRL
chmod -R go-w "$pkg"
find "$pkg/opt" -type d -exec chmod 755 {} +
dpkg-deb --root-owner-group --build "$pkg" build/besideos-linux-amd64.deb
echo "OK: build/besideos-linux-amd64.deb ($(du -h build/besideos-linux-amd64.deb | cut -f1))"
