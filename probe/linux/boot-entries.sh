#!/usr/bin/env bash
# Lists the UEFI boot entries (efibootmgr) and chooses which system starts next (once) or by default.
# Same options and JSON as probe/windows/boot-entries.ps1, so the app's boot page works on both.
#
#   boot-entries.sh -Action list [-OutFile FILE]
#   boot-entries.sh -Action next|default -Id 0001 [-Execute]     (without -Execute nothing is changed)
# Exit codes: 0 done, 1 error, 2 bad argument, 3 not root.

set -euo pipefail
ACTION=list; ID=; OUT=; EXECUTE=0
while [ $# -gt 0 ]; do
  case $1 in
    -Action) ACTION=${2:-}; shift 2 ;;
    -Id) ID=${2:-}; shift 2 ;;
    -OutFile) OUT=${2:-}; shift 2 ;;
    -Execute) EXECUTE=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case $ACTION in list|next|default) ;; *) echo "bad -Action: $ACTION" >&2; exit 2 ;; esac
[ "${BESIDEOS_TEST:-0}" = 1 ] || [ "$(id -u)" -eq 0 ] || { echo "Must run as root." >&2; exit 3; }
EFI=${BESIDEOS_EFIBOOTMGR:-efibootmgr}
command -v "$EFI" >/dev/null 2>&1 || { echo "efibootmgr is not installed." >&2; exit 1; }
RAW=$("$EFI" -v 2>&1) || { echo "efibootmgr failed (is this a UEFI computer?)." >&2; exit 1; }

jstr() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g'; }
csv_json() { # "0005,2002" -> "0005","2002"
  local out= x; IFS=, read -ra a <<<"$1"
  for x in "${a[@]}"; do [ -n "$x" ] && out+="${out:+,}\"$x\""; done; printf '%s' "$out"
}

ORDER=$(sed -n 's/^BootOrder: *//p' <<<"$RAW" | head -n1)
NEXT=$(sed -n 's/^BootNext: *//p' <<<"$RAW" | head -n1)
IDS=(); ENTRIES=
while IFS= read -r line; do
  [[ $line =~ ^Boot([0-9A-Fa-f]{4})\*?[[:space:]]+(.*)$ ]] || continue
  id=${BASH_REMATCH[1]}; rest=${BASH_REMATCH[2]}
  desc=${rest%%$'\t'*}; desc=${desc%"${desc##*[![:space:]]}"}
  dev=; [[ $rest == *$'\t'* ]] && dev=${rest#*$'\t'}
  path=
  if [[ $dev =~ File\(([^\)]*)\) ]]; then path=${BASH_REMATCH[1]}
  elif [[ $dev =~ (\\[^[:space:]]*\.[eE][fF][iI]) ]]; then path=${BASH_REMATCH[1]}; fi
  IDS+=("$id")
  ENTRIES+="${ENTRIES:+,}{\"id\":\"$id\",\"title\":\"$(jstr "$desc")\",\"description\":\"$(jstr "$desc")\",\"path\":\"$(jstr "$path")\"}"
done <<<"$RAW"

if [ "$ACTION" = list ]; then
  json="{\"order\":[$(csv_json "$ORDER")],\"sequence\":[$(csv_json "$NEXT")],\"timeout\":null,\"entries\":[$ENTRIES]}"
  if [ -n "$OUT" ]; then printf '%s' "$json" >"$OUT"; else printf '%s\n' "$json"; fi
  exit 0
fi

# next / default: only an entry the list above contains, never a free-form value handed to efibootmgr
[[ $ID =~ ^[0-9A-Fa-f]{4}$ ]] || { echo "Bad or missing -Id: $ID" >&2; exit 2; }
found=0; for x in "${IDS[@]}"; do [ "${x^^}" = "${ID^^}" ] && found=1; done
[ "$found" = 1 ] || { echo "Entry $ID is not a firmware boot entry of this computer." >&2; exit 2; }

if [ "$ACTION" = next ]; then args=(-n "$ID"); what="start $ID once at the next boot"
else
  neworder=$ID; IFS=, read -ra cur <<<"$ORDER"
  for x in "${cur[@]}"; do [ -n "$x" ] && [ "${x^^}" != "${ID^^}" ] && neworder+=",$x"; done
  args=(-o "$neworder"); what="make $ID the first (default) boot entry"
fi
if [ "$EXECUTE" -eq 0 ]; then echo "DRY-RUN: would run efibootmgr ${args[*]}  ($what)"; exit 0; fi
"$EFI" "${args[@]}" >/dev/null || { echo "efibootmgr ${args[*]} failed." >&2; exit 1; }
echo "DONE: $what"
