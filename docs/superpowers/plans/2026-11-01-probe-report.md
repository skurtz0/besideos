# Stage 3b probe report

## Built
- `probe/windows/collect-host-facts.ps1` (PS 5.1, read-only; facts.json UTF-8 no BOM only on success; probe.log always)
- `probe/windows/run-probe.cmd` (self-elevates via `net session` check + Start-Process -Verb RunAs)
- `probe/make-probe-image.sh` (pack / `--read`, `--force`), `probe/validate-facts.sh`, `probe/README.md` (TR)

## Mac tests
- Pack: `dd` 64 MB zero file, `newfs_msdos -F 32 -S 512 -s 131072 -v BESIDEPROBE img` (no mount privileges needed; `mount_msdos` fails unprivileged), `hdiutil attach -imagekey diskimage-class=CRawDiskImage`, copy, detach. Prints image path. Second run without `--force` -> "exists", exit 1.
- Round trip: attached image, wrote host_ok.json as facts.json + probe.log, detached; `--read img /tmp/out-facts.json` printed both, copied; `cmp` identical. No images left attached.
- validate-facts.sh: host_ok -> exit 0 (plan); host_bitlocker -> exit 2 (encrypted_target); host_arm64 -> 0; `{}` -> exit 1.
- Image is a "superfloppy" (FAT32 without partition table); UTM/Windows should mount it, unverified.
- PowerShell script NOT executed anywhere (no Windows here); reviewed by eye only.

## Assumptions to verify in the Windows VM
1. `ConvertTo-Json` emits uint64 as plain integers and keeps `partitions: []` / single-element arrays as arrays; `encrypted: null` is emitted as null.
2. `$parts += ,[ordered]@{}` appends the dictionary as a single element.
3. Registry `PEFirmwareType` exists on VM (2=UEFI); bcdedit fallback.
4. `Get-Partition` GptType/IsSystem/IsBoot values on ARM64/UTM; EFI partition gets `is_system=true`, `filesystem` from `Get-Volume` (may be "" if no volume object -> planner treats as unknown).
5. `Get-Volume` via `$p | Get-Volume` works for letterless partitions; otherwise used=size (fail closed).
6. manage-bde fallback: first `NN%` in output is "Percentage Encrypted" (locale-independent guess; Turkish uses `%`-forms possibly like `%0,0` — regex `(\d+)\s*%` would NOT match leading `%`; then null, fail closed).
7. Dynamic-disk detection via Win32_DiskPartition.Type "Logical Disk Manager" (English strings; localized Windows may differ -> false, unsafe direction!).
8. Partition without drive letter and not MSR/system gets `encrypted=null`.
9. Script folder on removable FAT volume: running `.ps1` with `-ExecutionPolicy Bypass` from there is allowed (Mark-of-the-Web not applicable).

## Concerns
- #7 fails open (dynamic=false) on localized Windows; consider checking `Get-Partition` MbrType 66 / GPT LDM GUIDs later.
- #6 is likewise weak on Turkish Windows; only used when Get-BitLockerVolume is absent.
