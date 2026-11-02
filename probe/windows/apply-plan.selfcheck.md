# apply-plan.ps1 self-check (nothing here was executed on Windows)

Line-by-line review done for PS 5.1: no ternary/`?.`/`&&`, no pwsh-only cmdlets, `[ordered]` ok (3.0+), file is pure ASCII
(PS 5.1 reads BOM-less files as ANSI), `{bootmgr}`/`{guid}` are always passed as quoted strings (bare `{}` is a scriptblock),
`${var}:` used where a colon follows a variable, native stderr handled via `Continue` inside `Invoke-Native`,
`$null -ne $x` used (array `-ne $null` filters). No pwsh/PSScriptAnalyzer available on the Mac, so syntax was not machine-parsed:
**first VM step: `powershell -Command "[void][scriptblock]::Create((gc -Raw apply-plan.ps1))"` or just the dry-run.**

## Must be verified in the VM
1. `bcdedit /copy {bootmgr} /d "..."` on Windows 11 ARM64 UEFI: succeeds, prints one `{guid}`; the copied entry can be given
   `device partition=X:` and `path \EFI\BOOT\BOOTAA64.EFI` and really boots. May need `bcdedit /set {guid} device partition=X:`
   vs `device partition=\Device\HarddiskVolumeN`; may need an extra `application`/`osdevice` value. Unverified.
2. `bcdedit /set {fwbootmgr} bootsequence {guid}` is accepted for a copied-bootmgr entry and is consumed once (one-shot) by
   the VM's UEFI (UTM/EDK2 may ignore BootNext-style entries). Undo uses `/deletevalue {fwbootmgr} bootsequence` and
   `bcdedit /delete {guid}`; confirm `/delete` also removes it from displayorder.
3. GUID parse regex works on the localized `bcdedit /copy` output (it is locale-independent by design).
4. `New-Partition -DiskNumber 0 -Size N -AssignDriveLetter` places the partition in the freed gap next to C: (not elsewhere),
   gets partition number 5, and a drive letter within ~15 s. Windows may pop up a "format disk?" dialog (ShellHWDetection).
5. `Format-Volume -FileSystem FAT32` works for ~4.4 GiB (limit is 32 GiB) and the label sticks.
6. `Resize-Partition -Size` accepts the exact computed size (granularity/rounding); actual shrunk size is logged. Undo grows to
   `SizeMax` of `Get-PartitionSupportedSize`; confirm it returns the full original size (original_size is logged).
7. Robocopy: exit codes 0-7 ok, >=8 fail; arguments `E:\` / `F:\` pass unquoted (no trailing-backslash quote bug);
   `/XD "System Volume Information" '$RECYCLE.BIN'` is accepted; all files < 4 GiB (preflight enforces on media roots; for
   `.iso` sources the check runs after mount).
8. `Mount-DiskImage` / `Get-DiskImage | Get-Volume` give a drive letter; `Dismount-DiskImage` afterwards.
9. `Get-BitLockerVolume` exists on this edition; otherwise `manage-bde` fallback parses first `NN%`; unknown => abort (by design).
10. `Get-Volume | Where FileSystemLabel` sees volumes without drive letters; `Get-Partition ... | Get-Volume` resolves for undo.
11. Locale: log/UI text is ASCII Turkish; bcdedit/robocopy/manage-bde output is only regex-matched on GUIDs and `NN%`.
12. `Restart-Computer -Force` with `-Reboot`; state is written before it.
13. Preflight expects the first-listed plan sequence exactly (shrink,create,extract,boot[,reboot]); delete_partition and
    remove_boot_entry as forward steps are rejected (they only appear as `undo`).
14. Undo removes any bootsequence value when it lists our GUID (would also drop other entries if the sequence had several).
15. `extract_iso` size estimates in `iso_ubuntu_arm64.json` (4154798080 / 3221225472) are placeholders, not measured.
16. (VM finding) Partition numbers are NOT stable: after New-Partition the reported number (5) became 4 on disk (Recovery became 5).
    Script now identifies partitions by Guid/UniqueId/offset/drive letter: Windows partition via `-DriveLetter` (plan numbers only
    cross-checked in preflight and at the shrink step), the created partition re-resolved by offset+size after creation, undo by
    recorded Guid (v1 state fallback: label + FAT32 + size within 1 MiB, exactly one non-system match, else refuse).
    Verify: `Get-Partition.Guid`/`UniqueId`/`Offset`/`GptType`/`Type` are populated; `Resize-Partition`/`Get-PartitionSupportedSize`
    accept `-DriveLetter`; GptType compares after stripping braces; `Remove-Partition` with freshly resolved numbers.
17. State file is version 2 (adds guid, unique_id, offset, letter); version 1 files are still read.
18. (VM finding) The one-shot bootsequence is consumed by the reboot, and `bcdedit /deletevalue` exits 1 for a missing element.
    Undo now parses `bcdedit /enum {fwbootmgr}` line by line and only deletes `bootsequence` if that element lists our GUID;
    a missing entry on `/delete` is a warning. Every undo step is idempotent and the summary lists done vs skipped.
    Verify: element-name parsing (`bootsequence`, `displayorder` at column 0, values on indented continuation lines) and that
    `bcdedit /delete` drops the GUID from displayorder (otherwise the explicit `/set {fwbootmgr} displayorder {guid} /remove` runs).
