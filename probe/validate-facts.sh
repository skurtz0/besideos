#!/bin/bash
# validate-facts.sh <facts.json>: run besideos-plan on facts with a sample iso/request.
# Exit: 0 plan, 2 refusal, 1 error.
set -u
f="$(cd "$(dirname "${1:?usage: validate-facts.sh <facts.json>}")" && pwd)/$(basename "$1")"
root="$(cd "$(dirname "$0")/.." && pwd)"
d="$root/core/besideos_core/tests/data"
export PATH=/opt/homebrew/opt/rustup/bin:$PATH
case "$(grep -o '"arch": *"[a-z0-9_]*"' "$f" | head -1)" in
  *arm64*) iso="$d/iso_arm64.json";; *x86_64*) iso="$d/iso.json";;
  *) echo "cannot read arch from $f" >&2; exit 1;;
esac
cd "$root/core" && cargo run -q --bin besideos-plan -- --host "$(cd - >/dev/null; realpath "$f")" --iso "$iso" --request "$d/request.json" --iso-path /tmp/sample.iso
rc=$?; echo "exit code: $rc"; exit $rc
