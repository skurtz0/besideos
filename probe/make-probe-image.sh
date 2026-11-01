#!/bin/bash
# Pack (default) or read back a 64 MB FAT32 raw probe image for the Windows VM.
#   make-probe-image.sh [--force] [out.img]        pack windows/* into new image
#   make-probe-image.sh --read <img> [dest.json]   print facts/log, copy facts.json
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
force=0; mode=pack; args=()
for a in "$@"; do
  case "$a" in --force) force=1;; --read) mode=read;; *) args+=("$a");; esac
done

attach() { # $1=img $2=hdiutil flag; sets globals dev, mnt (no subshell)
  local out
  out="$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nobrowse "$2" "$1" 2>/dev/null)"
  dev="$(echo "$out" | awk 'NR==1{print $1}')"
  mnt="$(echo "$out" | grep -o '/Volumes/.*' | head -1)"
  [ -n "$mnt" ] || { echo "attach failed: $out" >&2; exit 1; }
}

if [ "$mode" = pack ]; then
  img="${args[0]:-$here/besideprobe.img}"
  if [ -e "$img" ] && [ "$force" -ne 1 ]; then echo "exists: $img (use --force)" >&2; exit 1; fi
  rm -f "$img"
  dd if=/dev/zero of="$img" bs=1m count=64 2>/dev/null  # newfs_msdos formats the file directly
  newfs_msdos -F 32 -S 512 -s 131072 -v BESIDEPROBE "$img" >/dev/null
  attach "$img" -readwrite
  trap 'hdiutil detach "$dev" >/dev/null 2>&1 || true' EXIT
  cp "$here/windows/collect-host-facts.ps1" "$here/windows/run-probe.cmd" "$mnt/"
  sync; hdiutil detach "$dev" >/dev/null; trap - EXIT
  echo "$img"
else
  img="${args[0]:?usage: --read <img> [dest.json]}"; dest="${args[1]:-}"
  attach "$img" -readonly
  trap 'hdiutil detach "$dev" >/dev/null 2>&1 || true' EXIT
  for f in facts.json probe.log; do
    echo "== $mnt/$f"; [ -f "$mnt/$f" ] && cat "$mnt/$f" || echo "(missing)"
  done
  if [ -n "$dest" ]; then cp "$mnt/facts.json" "$dest" && echo "copied -> $dest"; fi
fi
