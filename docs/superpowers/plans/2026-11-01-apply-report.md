# Stage 3c apply report

Built: `probe/windows/apply-plan.ps1` (dry-run default, preflight, ordered execute with state file, `-Undo`), `run-apply.cmd`
(self-elevating, EXECUTE/REBOOT/UNDO flag files), `make-probe-image.sh` (`--plan`, `--execute`, `--reboot`, `--undo`, `--read` also lists
apply.log/apply-state.json), README section (Turkish), `apply-plan.selfcheck.md` (assumption list), Rust fixtures
`iso_ubuntu_arm64.json`, `plan_vm_apply.json` + golden test `vm_apply_plan_matches_golden`.

Tested on the Mac: cargo test (62 + 10 pass), clippy -D warnings clean; pack + `--read` round trip with a dummy plan for
no flags, `--execute`, `--execute --reboot`, `--undo --execute`, `--undo --reboot --execute`, and no plan (files/flags verified
by mounting the image). The PowerShell was NOT run or machine-parsed (no pwsh here); only a manual line-by-line review.

Estimates to replace: `iso_ubuntu_arm64.json` size_bytes/extracted_bytes 4154798080 and largest_file_bytes 3221225472
are estimates; `plan_vm_apply.json` (staging 4691668992 B, shrink 26166505472 B) and its golden must be regenerated afterwards.

Assumptions/risks: see `probe/windows/apply-plan.selfcheck.md`. Top: bcdedit /copy {bootmgr} + one-shot bootsequence on ARM64/UTM
firmware; New-Partition placement; Resize-Partition rounding; first-run PS syntax errors.
Concerns: only the exact sequence shrink,create,extract,boot[,reboot] is accepted; macOS creates `._*` AppleDouble files on the
image (harmless); undo removes whole bootsequence if it lists our GUID.

## Fix after first VM dry-run
UEFI check now mirrors collect-host-facts.ps1 (registry PEFirmwareType, then bcdedit `.efi` fallback; unknown = abort).
The odd "PASS: Unknown field ..." lines were passing checks printed with their failure text; passing checks are now logged
as DEBUG "check ok" (file only, console only with -Verbose). Summary lines "PREFLIGHT TAMAM / PREFLIGHT OK" and
"PREFLIGHT BASARISIZ / PREFLIGHT FAILED (n)"; dry-run prints a header before the per-step "DRY-RUN: would run ..." action list.
Still unrun on Windows after this edit.
