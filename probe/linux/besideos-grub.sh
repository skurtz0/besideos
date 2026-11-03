#!/usr/bin/env bash
# BesideOS Linux engine: boots an installer ISO straight from a file on an existing disk
# through a GRUB loopback entry. No partition is shrunk, created or formatted.
#
#   besideos-grub.sh check   --iso FILE            read-only report, no root needed (grub.cfg check needs root)
#   besideos-grub.sh prepare --iso FILE [--name ID] [--execute] [--allow-experimental]
#   besideos-grub.sh undo    [--name ID | --all] [--execute]
#   besideos-grub.sh status
#   besideos-grub.sh disks [--out FILE]            partitions that can give up room, as JSON (root)
#   prepare ... --title "Ubuntu"                       name shown in the GRUB menu: "BesideOS: 5 saniye içinde kurulacak: Ubuntu"
#   prepare ... --shrink-dev /dev/sdXN --shrink-gb N   also shrinks that partition by N GiB (leaves it unallocated)
#
# Several systems can be prepared at once: each --name ID (default "default") gets its own menu entry
# "besideos-ID" and its own state file; preparing the same ID again replaces that entry only.
#
# prepare and undo only print what they would do unless --execute is given (like apply-plan.ps1).
# What --execute changes: one marked block per name in <grub dir>/custom.cfg, one state file per name in
# /var/lib/besideos, and the GRUB one-time "next boot" entry. The ISO file itself is never touched.
# Exit codes: 0 done, 1 error, 2 refused (nothing changed).

set -euo pipefail

STATE_DIR=${BESIDEOS_STATE_DIR:-/var/lib/besideos}
CFG_MARK=$STATE_DIR/cfg_existed   # whether custom.cfg existed before BesideOS first wrote to it
LEGACY_STATE=$STATE_DIR/state     # written by the first, single-entry version

say()    { printf '%s\n' "$*"; }
ok()     { say "OK: $*"; }
warn()   { say "WARN: $*"; }
refuse() { say "REFUSED: $*"; exit 2; }
fail()   { say "ERROR: $*" >&2; exit 1; }

cmd=${1:-}; [ $# -gt 0 ] && shift
ISO=; EXECUTE=0; EXPERIMENTAL=0; NAME=default; ALL=0; SHRINK_DEV=; SHRINK_GB=0; OUT=; TITLE=
while [ $# -gt 0 ]; do
  case $1 in
    --iso) ISO=${2:-}; shift 2 ;;
    --name) NAME=${2:-}; shift 2 ;;
    --all) ALL=1; shift ;;
    --title) TITLE=${2:-}; shift 2 ;;
    --shrink-dev) SHRINK_DEV=${2:-}; shift 2 ;;
    --shrink-gb) SHRINK_GB=${2:-0}; shift 2 ;;
    --out) OUT=${2:-}; shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    --allow-experimental) EXPERIMENTAL=1; shift ;;
    *) fail "unknown option: $1" ;;
  esac
done

# BESIDEOS_TEST=1 lets the automated test run without root against a scratch GRUB directory.
TEST=${BESIDEOS_TEST:-0}
[[ $NAME =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || { say "REFUSED: --name must be lower case letters, digits and dashes" ; exit 2; }
set_name() { # $1 = name, or "" for the entry the first version wrote
  if [ -n "$1" ]; then
    STATE_FILE=$STATE_DIR/$1.state; ENTRY_ID=besideos-$1; BEGIN="# BEGIN BESIDEOS $1"; END="# END BESIDEOS $1"
  else
    STATE_FILE=$LEGACY_STATE; ENTRY_ID=besideos; BEGIN='# BEGIN BESIDEOS'; END='# END BESIDEOS'
  fi
}
set_name "$NAME"

need_root() { [ "$TEST" = 1 ] || [ "$(id -u)" -eq 0 ] || refuse "this needs root (run with sudo or pkexec)"; }

# ---------------------------------------------------------------- GRUB

find_grub() {
  GRUB_REBOOT=; GRUB_EDITENV=; GRUBDIR=
  for p in grub2 grub; do
    command -v "$p-reboot" >/dev/null 2>&1 && { GRUB_REBOOT=$p-reboot; GRUB_EDITENV=$p-editenv; break; }
  done
  # The automated test must never touch the real grubenv, even when it runs as root.
  [ "$TEST" = 1 ] && { GRUB_REBOOT=true; GRUB_EDITENV=true; }
  [ -n "$GRUB_REBOOT" ] || refuse "GRUB was not found on this system (systemd-boot and others are not supported yet)"
  for d in ${BESIDEOS_GRUBDIR:-} /boot/grub2 /boot/grub; do
    [ -n "$d" ] && [ -d "$d" ] && { GRUBDIR=$d; break; }
    [ "$TEST" = 1 ] || true
  done
  [ -n "$GRUBDIR" ] || refuse "no GRUB directory under /boot"
}

[ -d /sys/firmware/efi ] && UEFI=1 || UEFI=0

check_grub_cfg() {
  # The generated menu must read custom.cfg, otherwise our entry would never show up.
  local cfg=
  for c in "$GRUBDIR/grub.cfg" /boot/efi/EFI/*/grub.cfg; do
    [ -r "$c" ] && grep -q 'custom.cfg' "$c" 2>/dev/null && { cfg=$c; break; }
  done
  if [ -n "$cfg" ]; then ok "GRUB menu reads custom.cfg ($cfg)"; return; fi
  if [ ! -r "$GRUBDIR/grub.cfg" ]; then warn "cannot read $GRUBDIR/grub.cfg without root, custom.cfg support not verified"; return; fi
  refuse "this GRUB menu does not read custom.cfg (no 41_custom in grub.cfg)"
}

# ---------------------------------------------------------------- ISO

ISO_LIST=; ISO_LABEL=
iso_has() { grep -qxF "'$1'" <<<"$ISO_LIST"; }

inspect_iso() {
  [ -n "$ISO" ] || fail "--iso FILE is required"
  [ -f "$ISO" ] || refuse "ISO file not found: $ISO"
  ISO=$(readlink -f "$ISO")
  case $ISO in *[\"\$\`\\]*|*$'\n'*) refuse "the ISO path contains a character GRUB cannot take safely (\" \$ \` \\): rename it";; esac
  command -v xorriso >/dev/null 2>&1 || refuse "xorriso is needed to look inside the ISO (dnf/apt install xorriso)"
  ISO_LIST=$(xorriso -indev "$ISO" -find / -maxdepth 4 -type f 2>/dev/null) || refuse "not a readable ISO image: $ISO"
  ISO_LABEL=$(xorriso -indev "$ISO" -toc 2>&1 | sed -n "s/^Volume id *: '\(.*\)'.*/\1/p" | head -n1)
  ok "ISO label: ${ISO_LABEL:-unknown}"
  iso_has /EFI/BOOT/BOOTX64.EFI || iso_has /efi/boot/bootx64.efi || warn "no UEFI boot file in the ISO (fine for loopback, GRUB loads the kernel itself)"
}

# Sets METHOD to the recipe for this ISO and says whether it is verified.
detect_method() {
  METHOD=; VERIFIED=0
  if iso_has /boot/grub/loopback.cfg; then
    METHOD=loopbackcfg; VERIFIED=1
    ok "the ISO ships its own loopback.cfg (Ubuntu, Mint, Debian live family)"
  elif iso_has /images/pxeboot/vmlinuz && iso_has /images/pxeboot/initrd.img; then
    METHOD=dracut
    warn "Fedora style ISO: boots with iso-scan, not verified on real hardware yet"
  elif iso_has /arch/boot/x86_64/vmlinuz-linux; then
    METHOD=archiso
    warn "Arch style ISO: boots with img_loop, not verified on real hardware yet"
  else
    refuse "this ISO has no known loopback boot recipe yet"
  fi
  if [ "$VERIFIED" -eq 0 ] && [ "$EXPERIMENTAL" -eq 0 ]; then
    refuse "recipe '$METHOD' is experimental: add --allow-experimental to try it"
  fi
}

# ---------------------------------------------------------------- where the ISO lives

locate_iso() {
  local line
  line=$(findmnt -T "$ISO" -n -o FSTYPE,UUID,FSROOT,TARGET,SOURCE --raw 2>/dev/null) || fail "cannot find the file system of $ISO"
  read -r FSTYPE FSUUID FSROOT FSTARGET FSSOURCE <<<"$line"
  FSROOT=${FSROOT//\\x20/ }; FSTARGET=${FSTARGET//\\x20/ }
  case $FSTYPE in
    ext2|ext3|ext4|xfs|btrfs|vfat|exfat|ntfs|ntfs3|fuseblk) ok "ISO is on a $FSTYPE file system GRUB can read" ;;
    *) refuse "GRUB cannot read the file system the ISO is on ($FSTYPE): copy it to an ext4, xfs, btrfs or FAT32 disk" ;;
  esac
  [ -n "$FSUUID" ] || refuse "the file system of the ISO has no UUID"
  if lsblk -rno TYPE -s "$FSSOURCE" 2>/dev/null | grep -qx crypt; then
    refuse "the ISO is on an encrypted disk, GRUB cannot read it: copy it to an unencrypted disk"
  fi
  # Path as GRUB sees it: btrfs subvolumes appear as directories of the top level.
  local rel=${ISO#"$FSTARGET"}; rel=${rel#/}
  local root=${FSROOT%/}
  GRUB_ISO_PATH="$root/$rel"
  FSLABEL=$(lsblk -rno LABEL "$FSSOURCE" 2>/dev/null | head -n1 || true)
  ok "GRUB path: $GRUB_ISO_PATH on UUID $FSUUID ${FSLABEL:+($FSLABEL)}"
  if [ "$FSTARGET" = / ] || [ "$FSTARGET" = /home ]; then
    warn "the ISO is on a disk you may want to install onto; the installer cannot erase the partition holding its own ISO, so keep free space on another partition"
  fi
}

# ---------------------------------------------------------------- the menu entry

menu_entry() {
  local name=${TITLE:-$(basename "$ISO" .iso)}
  name=${name//[\"\$\`\\]/}
  local title="BesideOS: 5 saniye içinde kurulacak: $name"
  # The next start shows the whole GRUB menu for 5 seconds with this entry selected; every system that is already
  # installed stays in the list below it. GRUB itself forgets the one-shot choice (besideos_next) by saving it empty.
  cat <<ENTRY
$BEGIN
if [ "\$besideos_next" = "$ENTRY_ID" ]; then
  set default="$ENTRY_ID"
  set timeout=5
  set timeout_style=menu
  set besideos_next=
  save_env besideos_next
fi
menuentry "$title" --id $ENTRY_ID {
  insmod part_gpt
  insmod part_msdos
  insmod loopback
  insmod iso9660
  search --no-floppy --fs-uuid --set=isoroot $FSUUID
  set isofile="$GRUB_ISO_PATH"
  loopback loop (\$isoroot)\$isofile
ENTRY
  case $METHOD in
    loopbackcfg)
      cat <<'B'
  set iso_path="$isofile"
  export iso_path
  set root=(loop)
  configfile /boot/grub/loopback.cfg
B
      ;;
    dracut)
      cat <<B
  linux (loop)/images/pxeboot/vmlinuz root=live:CDLABEL=$ISO_LABEL rd.live.image iso-scan/filename=\$isofile quiet
  initrd (loop)/images/pxeboot/initrd.img
B
      ;;
    archiso)
      cat <<B
  linux (loop)/arch/boot/x86_64/vmlinuz-linux archisobasedir=arch img_dev=/dev/disk/by-uuid/$FSUUID img_loop=\$isofile
  initrd (loop)/arch/boot/x86_64/initramfs-linux.img
B
      ;;
  esac
  printf '}\n%s\n' "$END"
}

strip_block() { # file -> stdout without our block
  sed "/^$BEGIN\$/,/^$END\$/d" "$1"
}

# ---------------------------------------------------------------- making room (shrinking a partition)

GIB=$((1<<30)); MIB=$((1<<20)); MARGIN=$((2*GIB))   # a shrunk file system keeps its used space plus this much
SYSTEM_MOUNTS='^(/|/boot|/boot/efi|/usr|/var|/etc|/opt|/home)$'

lsfld() { sed -n "s/.*\b$1=\"\([^\"]*\)\".*/\1/p" <<<"$2"; }   # lsblk -P field

# How many bytes of partition $1 (fs $2, size $3, mount $4) can be given up; 0 when it cannot be shrunk safely.
shrinkable_bytes() {
  local dev=$1 fs=$2 size=$3 mnt=$4 used=0 free=0
  case $fs in
    ext4)
      if [ -n "$mnt" ]; then used=$(df -B1 --output=used "$mnt" | tail -n1 | tr -d ' ')
      else
        local bc fb bs
        bc=$(dumpe2fs -h "$dev" 2>/dev/null | sed -n 's/^Block count: *//p'); fb=$(dumpe2fs -h "$dev" 2>/dev/null | sed -n 's/^Free blocks: *//p')
        bs=$(dumpe2fs -h "$dev" 2>/dev/null | sed -n 's/^Block size: *//p')
        [ -n "$bc" ] && [ -n "$fb" ] && [ -n "$bs" ] || { echo 0; return; }
        used=$(( (bc - fb) * bs ))
      fi ;;
    btrfs)
      [ -n "$mnt" ] || { echo 0; return; }
      used=$(df -B1 --output=used "$mnt" 2>/dev/null | tail -n1 | tr -d ' ')
      [[ $used =~ ^[0-9]+$ ]] || { echo 0; return; } ;;
    ntfs)
      [ -z "$mnt" ] || { echo 0; return; }
      local minb; minb=$(ntfsresize -i -f -b "$dev" 2>/dev/null | sed -n 's/.*might resize at \([0-9]*\) bytes.*/\1/p')
      [ -n "$minb" ] || { echo 0; return; }
      used=$minb ;;
    *) echo 0; return ;;
  esac
  free=$(( size - used - MARGIN ))
  [ "$free" -gt 0 ] && echo "$free" || echo 0
}

do_disks() {
  need_root
  local disks=() line out= first=1 n=0 p dev fs size lbl mnt pk partn model
  while IFS= read -r line; do
    [ "$(lsfld TYPE "$line")" = disk ] && disks+=("$(lsfld PATH "$line")")
  done < <(lsblk -b -P -o PATH,TYPE 2>/dev/null)
  while IFS= read -r line; do
    [ "$(lsfld TYPE "$line")" = part ] || continue
    dev=$(lsfld PATH "$line"); fs=$(lsfld FSTYPE "$line"); size=$(lsfld SIZE "$line"); lbl=$(lsfld LABEL "$line")
    mnt=$(lsfld MOUNTPOINT "$line"); pk=$(lsfld PKNAME "$line"); partn=$(lsfld PARTN "$line")
    case $fs in ext4|btrfs|ntfs) ;; *) continue ;; esac
    [ -n "$pk" ] && [ -n "$partn" ] || continue
    local can; can=$(shrinkable_bytes "$dev" "$fs" "$size" "$mnt")
    [ "$can" -gt 0 ] || continue
    local disk=/dev/$pk dsize dname idx=0 i sys=false win=false
    dsize=$(lsblk -bdno SIZE "$disk"); dname=$(lsblk -dno MODEL "$disk" | sed 's/ *$//')
    for i in "${!disks[@]}"; do [ "${disks[$i]}" = "$disk" ] && idx=$i; done
    [[ $mnt =~ $SYSTEM_MOUNTS ]] && sys=true
    # ext4 cannot be shrunk while it is a mounted system directory; btrfs can (online).
    [ "$sys" = true ] && [ "$fs" != btrfs ] && continue
    out+="${out:+,}{\"disk\":$idx,\"partition\":$partn,\"letter\":\"$(printf '%s' "$dev" | sed 's/["\\]//g')\",\"device\":\"$dev\",\"label\":\"$(printf '%s' "$lbl" | sed 's/["\\]/ /g')\",\"fstype\":\"$fs\",\"mountpoint\":\"$(printf '%s' "$mnt" | sed 's/["\\]//g')\",\"system\":$sys,\"disk_name\":\"$(printf '%s' "$dname" | sed 's/["\\]/ /g')\",\"disk_size_bytes\":$dsize,\"size_bytes\":$size,\"free_bytes\":$can,\"is_windows\":$win}"
  done < <(lsblk -b -P -o PATH,TYPE,FSTYPE,SIZE,LABEL,MOUNTPOINT,PKNAME,PARTN 2>/dev/null)
  if [ -n "$OUT" ]; then printf '[%s]' "$out" >"$OUT"; else printf '[%s]\n' "$out"; fi
}

# Partition table facts via parted (bytes): sets P_START, P_END (inclusive) of partition $2 on disk $1.
part_geometry() {
  local line
  line=$(parted -m -s "$1" unit B print 2>/dev/null | grep "^$2:") || return 1
  P_START=$(cut -d: -f2 <<<"$line"); P_START=${P_START%B}
  P_END=$(cut -d: -f3 <<<"$line"); P_END=${P_END%B}
}

# Validates a shrink request (never touches anything). Sets S_DEV S_DISK S_PARTN S_FS S_SIZE S_MNT S_NEWSIZE.
shrink_plan() {
  local dev=$1 gb=$2
  [[ $dev =~ ^/dev/[A-Za-z0-9/_-]+$ ]] || refuse "bad partition name: $dev"
  [[ $gb =~ ^[0-9]+$ ]] && [ "$gb" -ge 8 ] || refuse "the room to make must be at least 8 GiB"
  local line; line=$(lsblk -b -P -o PATH,TYPE,FSTYPE,SIZE,MOUNTPOINT,PKNAME,PARTN "$dev" 2>/dev/null | head -n1)
  [ -n "$line" ] && [ "$(lsfld TYPE "$line")" = part ] || refuse "$dev is not a partition"
  S_DEV=$dev; S_FS=$(lsfld FSTYPE "$line"); S_SIZE=$(lsfld SIZE "$line"); S_MNT=$(lsfld MOUNTPOINT "$line")
  S_DISK=/dev/$(lsfld PKNAME "$line"); S_PARTN=$(lsfld PARTN "$line")
  case $S_FS in ext4|btrfs|ntfs) ;; *) refuse "cannot shrink a $S_FS partition" ;; esac
  if [ "$S_FS" = ext4 ] && [[ $S_MNT =~ $SYSTEM_MOUNTS ]]; then refuse "$dev holds a running system directory ($S_MNT) and ext4 cannot be shrunk while mounted"; fi
  [ "$(parted -m -s "$S_DISK" print 2>/dev/null | sed -n 2p | cut -d: -f6)" = gpt ] || refuse "only GPT disks are supported"
  local can; can=$(shrinkable_bytes "$dev" "$S_FS" "$S_SIZE" "$S_MNT")
  [ $(( gb * GIB )) -le "$can" ] || refuse "$dev can give up at most $(( can / GIB )) GiB, not $gb GiB (its files and ${MARGIN} bytes of margin stay)"
  S_NEWSIZE=$(( (S_SIZE - gb * GIB) / MIB * MIB ))
  say "PLAN: shrink $dev ($S_FS) from $(( S_SIZE / GIB )) GiB to $(( S_NEWSIZE / GIB )) GiB; $gb GiB stay unallocated behind it"
}

shrink_exec() { # needs shrink_plan to have run; echoes progress; leaves SHRINK_* for the state file
  part_geometry "$S_DISK" "$S_PARTN" || fail "cannot read the partition table of $S_DISK"
  SHRINK_ORIG_END=$P_END
  local new_end=$(( P_START + S_NEWSIZE - 1 )) tmpmnt=
  case $S_FS in
    ext4)
      if [ -n "$S_MNT" ]; then umount "$S_DEV" || fail "could not unmount $S_DEV (is something using it?)"; fi
      e2fsck -f -y "$S_DEV" >/dev/null || [ $? -le 1 ] || fail "e2fsck found problems on $S_DEV; nothing was shrunk"
      resize2fs "$S_DEV" "$(( S_NEWSIZE / 1024 ))K" >/dev/null || fail "resize2fs failed; the partition table was not changed" ;;
    btrfs)
      local mnt=$S_MNT
      if [ -z "$mnt" ]; then tmpmnt=$(mktemp -d /run/besideos-mnt.XXXXXX); mount "$S_DEV" "$tmpmnt" || fail "cannot mount $S_DEV"; mnt=$tmpmnt; fi
      btrfs filesystem resize "1:$S_NEWSIZE" "$mnt" >/dev/null || { [ -z "$tmpmnt" ] || umount "$tmpmnt"; fail "btrfs resize failed; the partition table was not changed"; }
      [ -z "$tmpmnt" ] || { umount "$tmpmnt"; rmdir "$tmpmnt"; } ;;
    ntfs)
      ntfsresize -f -s "$S_NEWSIZE" "$S_DEV" >/dev/null <<<y || fail "ntfsresize failed; the partition table was not changed" ;;
  esac
  # parted asks before shrinking a partition; the file system inside is already smaller, so the answer is yes.
  echo Yes | parted ---pretend-input-tty "$S_DISK" resizepart "$S_PARTN" "${new_end}B" >/dev/null 2>&1 \
    || fail "the file system was shrunk but the partition table could not be changed: run undo to grow it back"
  partprobe "$S_DISK" >/dev/null 2>&1 || true
  ok "$S_DEV shrunk; $SHRINK_GB GiB are free (unallocated) on $S_DISK"
}

shrink_undo() { # uses SHRINK_* from the state file
  [ -n "${SHRINK_DEV:-}" ] || return 0
  local disk=$SHRINK_DISK partn=$SHRINK_PARTN
  part_geometry "$disk" "$partn" || fail "cannot read the partition table of $disk"
  local line next
  # Anything that now starts inside the room we gave up means the room was used: growing back would destroy it.
  while IFS= read -r line; do
    next=$(cut -d: -f2 <<<"$line"); next=${next%B}
    [ "$(cut -d: -f1 <<<"$line")" = "$partn" ] && continue
    [ "$next" -gt "$P_END" ] && [ "$next" -le "$SHRINK_ORIG_END" ] && refuse "the room behind $SHRINK_DEV is in use (a new partition exists); it was not grown back"
  done < <(parted -m -s "$disk" unit B print 2>/dev/null | grep -E '^[0-9]+:')
  echo Yes | parted ---pretend-input-tty "$disk" resizepart "$partn" "${SHRINK_ORIG_END}B" >/dev/null 2>&1 || fail "could not grow $SHRINK_DEV back"
  partprobe "$disk" >/dev/null 2>&1 || true
  case $SHRINK_FS in
    ext4) e2fsck -f -y "$SHRINK_DEV" >/dev/null || [ $? -le 1 ]; resize2fs "$SHRINK_DEV" >/dev/null || fail "resize2fs could not grow $SHRINK_DEV" ;;
    btrfs)
      local mnt; mnt=$(findmnt -n -o TARGET "$SHRINK_DEV" | head -n1)
      if [ -n "$mnt" ]; then btrfs filesystem resize 1:max "$mnt" >/dev/null || fail "btrfs could not grow back"
      else local t; t=$(mktemp -d /run/besideos-mnt.XXXXXX); mount "$SHRINK_DEV" "$t" && btrfs filesystem resize 1:max "$t" >/dev/null; umount "$t"; rmdir "$t"; fi ;;
    ntfs) ntfsresize -f "$SHRINK_DEV" >/dev/null <<<y || fail "ntfsresize could not grow back" ;;
  esac
  ok "$SHRINK_DEV grown back to its original size"
}

# ---------------------------------------------------------------- commands

do_check() {
  inspect_iso; detect_method; locate_iso
  find_grub; ok "GRUB tools: $GRUB_REBOOT, config dir $GRUBDIR"
  [ "$UEFI" -eq 1 ] && ok "UEFI boot" || warn "BIOS boot: loopback also works, but read the notes for Secure Boot/Legacy"
  check_grub_cfg
  if [ -f /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c ]; then
    [ "$(od -An -t u1 -j4 -N1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c | tr -d ' ')" = 1 ] \
      && warn "Secure Boot is on: ISOs with unsigned kernels may refuse to start; turn it off in the firmware if the entry fails"
  fi
  return 0
}

do_prepare() {
  do_check
  need_root
  [ -z "$SHRINK_DEV" ] || shrink_plan "$SHRINK_DEV" "$SHRINK_GB"
  say "--- entry that will be added to $GRUBDIR/custom.cfg"
  menu_entry
  say "---"
  if [ "$EXECUTE" -eq 0 ]; then say "DRY RUN: nothing was changed (add --execute)"; return; fi
  mkdir -p "$STATE_DIR"
  # A shrink is recorded first: if anything below fails, undo can still grow the partition back.
  local shrink_state=
  if [ -n "$SHRINK_DEV" ]; then
    SHRINK_DISK=$S_DISK; SHRINK_PARTN=$S_PARTN; SHRINK_FS=$S_FS
    shrink_exec
    shrink_state="SHRINK_DEV=$S_DEV\nSHRINK_DISK=$S_DISK\nSHRINK_PARTN=$S_PARTN\nSHRINK_FS=$S_FS\nSHRINK_ORIG_END=$SHRINK_ORIG_END\n"
    # Remember the shrink at once so "undo" can grow the partition back even if a later step fails.
    { echo "GRUBDIR=$GRUBDIR"; echo "GRUB_REBOOT=$GRUB_REBOOT"; echo "GRUB_EDITENV=$GRUB_EDITENV"; printf '%b' "$shrink_state"; } >"$STATE_FILE"
  fi
  local cfg=$GRUBDIR/custom.cfg tmp
  if [ ! -f "$CFG_MARK" ]; then
    if [ -f "$LEGACY_STATE" ]; then sed -n 's/^CFG_EXISTED=//p' "$LEGACY_STATE" >"$CFG_MARK"
    elif [ -f "$cfg" ]; then echo 1 >"$CFG_MARK"; else echo 0 >"$CFG_MARK"; fi
  fi
  [ ! -f "$STATE_FILE" ] || ok "replacing the earlier '$NAME' entry"
  tmp=$(mktemp)
  { [ -f "$cfg" ] && strip_block "$cfg" || true; menu_entry; } >"$tmp"
  cat "$tmp" >"$cfg"; rm -f "$tmp"
  { echo "GRUBDIR=$GRUBDIR"; echo "ISO=$ISO"; echo "METHOD=$METHOD"
    echo "GRUB_REBOOT=$GRUB_REBOOT"; echo "GRUB_EDITENV=$GRUB_EDITENV"; printf '%b' "$shrink_state"; } >"$STATE_FILE"
  ok "entry written"
  if "$GRUB_EDITENV" - set "besideos_next=$ENTRY_ID" 2>/dev/null; then
    ok "next start shows the GRUB menu for 5 seconds with this BesideOS entry selected; restart when you are ready (nothing restarts by itself)"
  else
    warn "could not prepare the next start; pick \"BesideOS\" in the GRUB menu (hold Shift or press Esc at start)"
  fi
}

do_undo() {
  need_root
  if [ "$ALL" -eq 1 ]; then
    local f n
    for f in "$STATE_DIR"/*.state; do
      [ -f "$f" ] || continue
      n=$(basename "$f" .state)
      BESIDEOS_STATE_DIR=$STATE_DIR bash "$0" undo --name "$n" $([ "$EXECUTE" -eq 1 ] && echo --execute)
    done
    [ -f "$LEGACY_STATE" ] && { BESIDEOS_STATE_DIR=$STATE_DIR bash "$0" undo --name legacy-entry $([ "$EXECUTE" -eq 1 ] && echo --execute); }
    return 0
  fi
  # The first version wrote a single unnamed entry: a name without its own state file takes it over.
  if [ ! -f "$STATE_FILE" ] && [ -f "$LEGACY_STATE" ]; then set_name ""; fi
  [ -f "$STATE_FILE" ] || { ok "nothing to undo"; return; }
  # shellcheck disable=SC1090
  . "$STATE_FILE"
  say "will remove the BesideOS block '$ENTRY_ID' from $GRUBDIR/custom.cfg and clear the next-boot entry"
  if [ "$EXECUTE" -eq 0 ]; then say "DRY RUN: nothing was changed (add --execute)"; return; fi
  local cfg=$GRUBDIR/custom.cfg existed
  existed=$(cat "$CFG_MARK" 2>/dev/null || echo "${CFG_EXISTED:-1}")
  if [ -f "$cfg" ]; then
    local tmp; tmp=$(mktemp)
    strip_block "$cfg" >"$tmp"
    if [ "$existed" = 0 ] && ! grep -q '[^[:space:]]' "$tmp"; then rm -f "$cfg"; else cat "$tmp" >"$cfg"; fi
    rm -f "$tmp"
  fi
  if "$GRUB_EDITENV" - list 2>/dev/null | grep -qx "besideos_next=$ENTRY_ID"; then "$GRUB_EDITENV" - unset besideos_next || true; fi
  shrink_undo
  rm -f "$STATE_FILE"
  # forget the "custom.cfg did not exist" note once no entry of ours is left
  compgen -G "$STATE_DIR/*.state" >/dev/null || [ -f "$LEGACY_STATE" ] || rm -f "$CFG_MARK"
  ok "undone (your ISO file was not touched)"
}

do_status() {
  local any=0 f
  for f in "$STATE_DIR"/*.state "$LEGACY_STATE"; do
    [ -f "$f" ] || continue
    any=1; say "ENTRY: $(basename "$f" .state)"; cat "$f"
  done
  [ "$any" -eq 1 ] || ok "nothing prepared"
}

case $cmd in
  check) do_check ;;
  prepare) do_prepare ;;
  undo) do_undo ;;
  status) do_status ;;
  disks) do_disks ;;
  *) say "usage: besideos-grub.sh check|prepare|undo|status --iso FILE [--execute] [--allow-experimental]"; exit 1 ;;
esac
