#!/bin/bash
# Pack (default) or read back a 64 MB FAT32 raw probe image for the Windows VM.
#   make-probe-image.sh [--force] [out.img]        pack windows/* into new image
#   pack options: --plan <plan.json> (copied as plan.json), --execute/--reboot/--undo (empty EXECUTE.flag/REBOOT.flag/UNDO.flag;
#   no flags = pure dry-run). apply-plan.ps1 + run-apply.cmd are always packed.
#   make-probe-image.sh --read <img> [dest.json]   print facts/log, copy facts.json; also apply.log, apply-state.json
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
force=0; mode=pack; args=(); plan=""; flags=()
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1;; --read) mode=read;;
    --plan) plan="${2:?--plan needs a file}"; shift;;
    --execute) flags+=(EXECUTE.flag);; --reboot) flags+=(REBOOT.flag);; --undo) flags+=(UNDO.flag);;
    *) args+=("$1");;
  esac; shift
done
[ -z "$plan" ] || [ -f "$plan" ] || { echo "plan not found: $plan" >&2; exit 1; }

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
  dd if=/dev/zero of="$img" bs=1m count=64 2>/dev/null
  # MBR partition table is required: Windows will not mount an unpartitioned (superfloppy) USB disk.
  dev="$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "$img" 2>/dev/null | awk 'NR==1{print $1}')"
  trap 'hdiutil detach "$dev" >/dev/null 2>&1 || true' EXIT
  diskutil partitionDisk "$dev" MBR MS-DOS BESIDEPROBE R >/dev/null
  mnt="/Volumes/BESIDEPROBE"; [ -d "$mnt" ] || { echo "mount failed" >&2; exit 1; }
  cp "$here/windows/collect-host-facts.ps1" "$here/windows/run-probe.cmd" "$here/windows/apply-plan.ps1" "$here/windows/run-apply.cmd" "$mnt/"
  [ -z "$plan" ] || cp "$plan" "$mnt/plan.json"
  for f in ${flags[@]+"${flags[@]}"}; do : > "$mnt/$f"; done
  sync; hdiutil detach "$dev" >/dev/null; trap - EXIT
  echo "$img"
else
  img="${args[0]:?usage: --read <img> [dest.json]}"; dest="${args[1]:-}"
  attach "$img" -readonly
  trap 'hdiutil detach "$dev" >/dev/null 2>&1 || true' EXIT
  for f in facts.json probe.log apply.log apply-state.json; do
    echo "== $mnt/$f"; [ -f "$mnt/$f" ] && cat "$mnt/$f" || echo "(missing)"
  done
  if [ -n "$dest" ]; then cp "$mnt/facts.json" "$dest" && echo "copied -> $dest"; fi
fi
