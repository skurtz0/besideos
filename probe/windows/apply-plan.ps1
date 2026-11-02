<#
.SYNOPSIS
  BesideOS plan applier (Stage 3c). Windows PowerShell 5.1. ASCII-only on purpose
  (PS 5.1 reads BOM-less .ps1 files in the ANSI code page).

.DESCRIPTION
  Applies the JSON plan produced by `besideos-plan` (core/besideos_core, plan.rs):
  shrink the Windows partition, create a FAT32 staging partition, copy the
  installer media onto it, add a ONE-SHOT UEFI boot entry, optionally reboot.
  Intended for a throwaway test VM with a clean snapshot. Written so that it
  could not easily hurt a real disk either.

  SAFETY RAILS
    * DEFAULT IS DRY-RUN. Nothing changes unless -Execute is given. The preflight
      runs in both modes and aborts (exit 1) with a Turkish + English message.
    * Preflight: Administrator; plan parses, all step types/fields known, step
      sequence is exactly shrink,create,extract,boot-entry[,reboot]; target
      partition exists NOW, is NTFS, holds %SystemDrive%, is not BitLocker
      protected (undeterminable = abort), disk is GPT, firmware is UEFI;
      live Get-PartitionSupportedSize.SizeMin <= current size - shrink;
      shrink == plan.total_shrink_bytes; no volume labelled BESIDEOS exists;
      media source exists; Windows volume keeps >= 10 GiB free after shrink;
      loader leaf matches the machine architecture; no leftover apply-state.json
      (with -Execute).
    * Only the disk/partition named in the plan is resized. The only partition
      ever removed is the one THIS script created (recorded in apply-state.json,
      re-verified by number + label + size before removal). No Clear-Disk,
      Initialize-Disk, or file deletion anywhere.
    * Any step failure stops at once, writes apply-state.json, tells you to run -Undo.

.PARAMETER PlanFile  Plan JSON. Default: plan.json next to this script.
.PARAMETER Execute   Really do it. Without it: dry-run (print + log only).
.PARAMETER Undo      Reverse what apply-state.json records (dry-run unless -Execute).
.PARAMETER Reboot    With -Execute: restart after the last step. Otherwise "reboot skipped".
.PARAMETER OutDir    Where apply.log and apply-state.json go. Default: script folder.

.NOTES
  Exit codes: 0 ok, 1 error/abort.
  Assumptions: see apply-plan.selfcheck.md (untested on real Windows when written).
  Outputs (OutDir): apply.log (UTF-8, no BOM, appended), apply-state.json.
#>
[CmdletBinding()]
param(
    [string]$PlanFile,
    [switch]$Execute,
    [switch]$Undo,
    [switch]$Reboot,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
# Defaults are set here, not in param(): with [CmdletBinding()] Windows PowerShell 5.1 leaves $PSScriptRoot empty
# inside param() defaults, which made `-Undo -OutDir <dir>` (no -PlanFile) die before any code ran.
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $PlanFile) { $PlanFile = Join-Path $here 'plan.json' }
if (-not $OutDir) { $OutDir = $here }
$logPath   = Join-Path $OutDir 'apply.log'
$statePath = Join-Path $OutDir 'apply-state.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$GUID_RE = '\{[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\}'
$MinFreeAfter = 10GB   # PowerShell GB suffix is 1024^3 = GiB

function Log([string]$m, [string]$lvl = 'INFO', [switch]$NoConsole) {
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 's'), $lvl, $m
    try { [System.IO.File]::AppendAllText($logPath, $line + "`r`n", $utf8) } catch { }
    if (-not $NoConsole) { Write-Host $line }
}
function Abort([string]$tr, [string]$en) {
    Log "DURDURULDU / ABORT: $tr / $en" 'ERROR'
    Log 'Hicbir sey degistirilmedi (preflight) veya durum apply-state.json icinde. / See state file.' 'ERROR'
    exit 1
}
$script:fails = 0
function Req([bool]$ok, [string]$tr, [string]$en) {
    if ($ok) { Log "check ok: $en" 'DEBUG' -NoConsole:($VerbosePreference -ne 'Continue') } else { Log "FAIL: $tr / $en" 'ERROR'; $script:fails++ }
}
function Stop-IfFailed {
    if ($script:fails -gt 0) {
        Log "PREFLIGHT BASARISIZ / PREFLIGHT FAILED ($($script:fails))" 'ERROR'
        Abort "Preflight basarisiz ($($script:fails) hata)." "Preflight failed ($($script:fails) problem(s))."
    }
}
function Invoke-Native([string]$exe, [string[]]$a) {
    # 2>&1 on a native exe yields ErrorRecords that would throw under 'Stop'.
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & $exe @a 2>&1 | Out-String; $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    Log ("> $exe " + ($a -join ' ') + " [exit $rc]")
    Log $o 'OUT' -NoConsole
    return [pscustomobject]@{ Code = $rc; Out = $o }
}
function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}
# $true = encrypted/protected, $false = clearly not, $null = unknown (=> abort)
function Get-Encrypted([string]$letter) {
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        try {
            $v = Get-BitLockerVolume -MountPoint "${letter}:" -ErrorAction Stop
            return ([string]$v.VolumeStatus -ne 'FullyDecrypted' -or [string]$v.ProtectionStatus -ne 'Off')
        } catch { Log "Get-BitLockerVolume failed: $($_.Exception.Message)" 'WARN' }
    }
    try {
        $r = Invoke-Native 'manage-bde' @('-status', "${letter}:")
        # Locale-independent: first "NN%" figure is "Percentage Encrypted".
        if ($r.Code -eq 0 -and $r.Out -match '(\d+(?:[.,]\d+)?)\s*%') {
            return ([double]($Matches[1] -replace ',', '.') -gt 0)
        }
    } catch { Log "manage-bde failed: $($_.Exception.Message)" 'WARN' }
    return $null
}
function Save-State {
    if (-not $Execute) { return }
    [System.IO.File]::WriteAllText($statePath, (ConvertTo-Json -InputObject $script:State -Depth 8), $utf8)
}
# Partition NUMBERS are not stable (Windows renumbers by disk order after create). Identify by Guid / letter / offset.
function NormGuid($g) { return (([string]$g) -replace '[{}]', '').ToLowerInvariant() }
$PROTECTED_GPT = @('c12a7328-f81f-11d2-ba4b-00a0c93ec93b', 'e3c9e316-0b5c-4db8-817d-f92df00215ae', 'de94bba4-06d1-4d40-a16a-bfd50179d6ac')
function Get-VolOf($p) { try { return ($p | Get-Volume -ErrorAction Stop) } catch { return $null } }
function Test-Protected($p) {
    return ([bool]$p.IsSystem -or [bool]$p.IsBoot -or ($PROTECTED_GPT -contains (NormGuid $p.GptType)) -or (@('System', 'Reserved', 'Recovery') -contains [string]$p.Type))
}
function Describe-Part($p) {
    $v = Get-VolOf $p
    $lbl = ''; $fs = ''
    if ($v) { $lbl = [string]$v.FileSystemLabel; $fs = [string]$v.FileSystem }
    return "disk=$($p.DiskNumber) number=$($p.PartitionNumber) guid=$($p.Guid) letter=$($p.DriveLetter) label='$lbl' fs=$fs size=$($p.Size) offset=$($p.Offset)"
}
# After New-Partition the reported number is stale: find the new partition by offset+size and wait for its letter.
function Find-Created([int]$disk, $np) {
    for ($i = 0; $i -lt 15; $i++) {
        $hit = @(Get-Partition -DiskNumber $disk -ErrorAction Stop | Where-Object { [int64]$_.Offset -eq [int64]$np.Offset -and [int64]$_.Size -eq [int64]$np.Size -and $_.DriveLetter })
        if ($hit.Count -eq 1) { return $hit[0] }
        if ($hit.Count -gt 1) { throw 'ambiguous new partition' }
        Start-Sleep -Seconds 1
    }
    return $null
}
# Undo: locate the staging partition we created. Guid first; v1 state (no guid): label+FAT32+size(+-1MiB), exactly one.
function Resolve-Staging($c) {
    $all = @(Get-Partition -DiskNumber ([int]$c.disk) -ErrorAction Stop)
    $want = [int64]$c.size_bytes; $tol = 1MB
    if ($c.guid) {
        $hit = @($all | Where-Object { (NormGuid $_.Guid) -eq (NormGuid $c.guid) })
        if ($hit.Count -eq 0) { return $null }
    } else {
        Log 'state has no partition Guid (v1); using label+FAT32+size fallback.' 'WARN'
        $hit = @($all | Where-Object {
                $v = Get-VolOf $_
                $v -and [string]$v.FileSystemLabel -eq [string]$c.label -and [string]$v.FileSystem -eq 'FAT32' -and [math]::Abs([int64]$_.Size - $want) -le $tol -and -not (Test-Protected $_)
            })
        if ($hit.Count -ne 1) { Abort "Tam olarak 1 aday bulunamadi ($($hit.Count)); silinmedi." "Fallback matched $($hit.Count) partitions (need exactly 1); refusing." }
    }
    if ($hit.Count -ne 1) { Abort 'Birden fazla eslesme; silinmedi.' 'Multiple matches; refusing.' }
    $p = $hit[0]; $v = Get-VolOf $p
    if (Test-Protected $p) { Abort 'Aday bolum sistem/kurtarma/EFI/MSR; silinmedi.' 'Candidate is a system/recovery/EFI/MSR partition; refusing.' }
    if (-not ($v -and [string]$v.FileSystemLabel -eq [string]$c.label)) { Abort 'Aday bolumun etiketi uyusmuyor; silinmedi.' 'Candidate label mismatch; refusing.' }
    if ([math]::Abs([int64]$p.Size - $want) -gt $tol) { Abort 'Aday bolumun boyutu uyusmuyor; silinmedi.' 'Candidate size mismatch; refusing.' }
    return $p
}

$mode = 'DRY-RUN'; if ($Execute) { $mode = 'EXECUTE' }
$verb = 'APPLY'; if ($Undo) { $verb = 'UNDO' }
Log "start; $verb mode=$mode; PS=$($PSVersionTable.PSVersion); plan=$PlanFile; Reboot=$($Reboot.IsPresent)"
if ($Undo -and $Reboot) { Log '-Reboot ignored with -Undo.' 'WARN' }

Req (Test-Admin) 'Yonetici olarak calistirilmali.' 'Must run as Administrator.'
Stop-IfFailed

# =====================================================================
# UNDO
# =====================================================================
if ($Undo) {
    if (-not (Test-Path -LiteralPath $statePath)) { Abort 'apply-state.json yok; geri alinacak bir sey yok.' "No state file at $statePath." }
    try { $st = [System.IO.File]::ReadAllText($statePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
    catch { Abort "apply-state.json okunamadi: $($_.Exception.Message)" "Cannot parse state file: $($_.Exception.Message)" }
    $sd = $env:SystemDrive.Substring(0, 1)

    $undoDone = New-Object System.Collections.ArrayList
    $undoSkipped = New-Object System.Collections.ArrayList
    # Which {guid}s does a bcdedit element (e.g. bootsequence, displayorder) list? Element names are not localized;
    # values may continue on following indented lines.
    function Get-BcdElementGuids([string]$text, [string]$name) {
        $found = @(); $inEl = $false
        foreach ($ln in ($text -split "`r?`n")) {
            if ($ln -match "^\s*$name(\s|$)" -and $ln -match '^\S') { $inEl = $true; $found += [regex]::Matches($ln, $GUID_RE) | ForEach-Object { $_.Value }; continue }
            if ($inEl -and $ln -match '^\s+\S') { $found += [regex]::Matches($ln, $GUID_RE) | ForEach-Object { $_.Value }; continue }
            $inEl = $false
        }
        return @($found)
    }
    # 1. boot entry (idempotent: consumed bootsequence / already-deleted entry are skips, not errors)
    if ($st.boot_entry -and $st.boot_entry.guid) {
        $g = [string]$st.boot_entry.guid
        if ($g -notmatch "^$GUID_RE`$") { Abort 'Durum dosyasindaki GUID gecersiz.' "Bad GUID in state: $g" }
        Log "UNDO 1: boot entry $g"
        $fw = Invoke-Native 'bcdedit' @('/enum', '{fwbootmgr}')   # read-only
        if ($fw.Code -ne 0) { Abort 'fwbootmgr okunamadi.' 'bcdedit /enum {fwbootmgr} failed.' }
        $inSeq = @(Get-BcdElementGuids $fw.Out 'bootsequence' | Where-Object { $_ -ieq $g }).Count -gt 0
        if (-not $inSeq) {
            Log 'bootsequence already consumed (or does not list our entry), nothing to remove.'
            [void]$undoSkipped.Add('1a bootsequence')
        } elseif (-not $Execute) {
            Log 'DRY-RUN: would run bcdedit /deletevalue {fwbootmgr} bootsequence'
        } else {
            $r = Invoke-Native 'bcdedit' @('/deletevalue', '{fwbootmgr}', 'bootsequence')
            if ($r.Code -ne 0) { Abort 'bootsequence silinemedi.' 'bcdedit /deletevalue bootsequence failed although it lists our entry.' }
            [void]$undoDone.Add('1a bootsequence')
        }
        # bcdedit /enum <missing guid> prints "no matching objects" but still exits 0, so exit code alone proves nothing.
        # The entry exists only if the output names its GUID (locale independent).
        function Test-BcdEntry([string]$guid) {
            $x = Invoke-Native 'bcdedit' @('/enum', $guid)   # read-only existence check
            return ($x.Code -eq 0 -and ([string]$x.Out) -match [regex]::Escape($guid))
        }
        if (-not (Test-BcdEntry $g)) {
            Log 'boot entry already gone.' 'WARN'
            [void]$undoSkipped.Add('1b boot entry')
        } elseif (-not $Execute) {
            Log "DRY-RUN: would run bcdedit /delete $g"
        } else {
            $r = Invoke-Native 'bcdedit' @('/delete', $g)
            if ($r.Code -ne 0) {
                if (-not (Test-BcdEntry $g)) { Log 'bcdedit /delete reported an error but the entry is gone.' 'WARN'; [void]$undoSkipped.Add('1b boot entry') }
                else { Abort 'Onyukleme girdisi silinemedi.' 'bcdedit /delete failed and the entry still exists.' }
            } else { [void]$undoDone.Add('1b boot entry') }
            # bcdedit /delete also removes the entry from displayorder (unless /nocleanup); verify, remove explicitly if not.
            $fw2 = Invoke-Native 'bcdedit' @('/enum', '{fwbootmgr}')
            if (@(Get-BcdElementGuids $fw2.Out 'displayorder' | Where-Object { $_ -ieq $g }).Count -gt 0) {
                $r = Invoke-Native 'bcdedit' @('/set', '{fwbootmgr}', 'displayorder', $g, '/remove')
                if ($r.Code -ne 0) { Log 'could not remove entry from displayorder (non-fatal).' 'WARN' }
            }
        }
    } else { [void]$undoSkipped.Add('1 boot entry (none recorded)') }

    # 2. staging partition (only the one we created; resolved by Guid, never by number)
    if ($st.created -and ($st.created.guid -or $st.created.partition)) {
        Log "UNDO 2: remove staging partition (state: disk $($st.created.disk), number $($st.created.partition), guid $($st.created.guid), label $($st.created.label), size $($st.created.size_bytes))"
        $p = Resolve-Staging $st.created
        if (-not $p) { Log 'staging partition not present (Guid not found); skipping.' 'WARN'; [void]$undoSkipped.Add('2 staging partition') }
        else {
            Log ('TARGET to remove: ' + (Describe-Part $p))
            $cmd = "Remove-Partition -DiskNumber $($p.DiskNumber) -PartitionNumber $($p.PartitionNumber) -Confirm:`$false"
            if (-not $Execute) { Log "DRY-RUN: would run $cmd" }
            else { Log "RUN: $cmd"; Remove-Partition -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber -Confirm:$false -ErrorAction Stop; [void]$undoDone.Add('2 staging partition') }
        }
    }

    # 3. grow Windows partition back
    if ($st.windows -and $st.windows.disk -ne $null) {
        $wd = [int]$st.windows.disk
        # the shrunk drive is the one recorded in state (may be a data drive, not the Windows drive); Guid is verified below
        if ($st.windows.letter -and ([string]$st.windows.letter) -cmatch '^[A-Za-z]$') { $sd = [string]$st.windows.letter }
        $wp = Get-Partition -DriveLetter $sd -ErrorAction Stop
        Log ('UNDO 3: grow Windows partition to SizeMax: ' + (Describe-Part $wp) + " (original size $($st.original_size))")
        if ($wp.DiskNumber -ne $wd) { Abort 'Windows bolumu durum dosyasindaki diskte degil.' 'Windows partition is not on the disk recorded in state.' }
        if ($st.windows.guid -and (NormGuid $st.windows.guid) -ne (NormGuid $wp.Guid)) { Abort 'Windows bolumunun Guid degeri uyusmuyor.' 'Windows partition Guid differs from state.' }
        $sup = Get-PartitionSupportedSize -DriveLetter $sd
        Log "current=$($wp.Size) SizeMax=$($sup.SizeMax) original=$($st.original_size)"
        if ([int64]$sup.SizeMax -le [int64]$wp.Size) { Log 'already at SizeMax; nothing to grow.'; [void]$undoSkipped.Add('3 grow Windows') }
        else {
            $cmd = "Resize-Partition -DriveLetter $sd -Size $($sup.SizeMax)"
            if (-not $Execute) { Log "DRY-RUN: would run $cmd (SizeMax shown is before the staging partition is removed)" }
            else { Log "RUN: $cmd"; Resize-Partition -DriveLetter $sd -Size ([uint64]$sup.SizeMax) -ErrorAction Stop; [void]$undoDone.Add('3 grow Windows') }
        }
    }
    Log ("UNDO ozet / summary: done=[" + ($undoDone -join ', ') + "] skipped(already undone)=[" + ($undoSkipped -join ', ') + ']')
    if ($Execute) {
        $done = Join-Path $OutDir ('apply-state.undone-' + (Get-Date -Format 'yyyyMMddHHmmss') + '.json')
        Move-Item -LiteralPath $statePath -Destination $done
        Log "UNDO complete; state moved to $done"
    } else { Log 'DRY-RUN: UNDO would be complete. Use -Execute to really undo.' }
    exit 0
}

# =====================================================================
# PREFLIGHT (apply)
# =====================================================================
try {
    $plan = [System.IO.File]::ReadAllText($PlanFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
} catch { Abort "Plan okunamadi/ayrisamadi: $($_.Exception.Message)" "Cannot read/parse plan: $($_.Exception.Message)" }

$fields = @{
    shrink_partition        = @('type', 'disk', 'partition', 'shrink_bytes')
    create_partition        = @('type', 'disk', 'size_bytes', 'filesystem', 'label')
    extract_iso             = @('type', 'iso_path', 'target_label')
    add_one_shot_boot_entry = @('type', 'loader_path', 'description')
    reboot                  = @('type')
    delete_partition        = @('type', 'disk', 'label')
    remove_boot_entry       = @('type', 'description')
}
function Test-Fields($o, [string[]]$allowed, [string]$where) {
    $names = @($o.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($n in $names) { Req ($allowed -contains $n) "Bilinmeyen alan '$n' ($where)." "Unknown field '$n' in $where" }
    foreach ($a in $allowed) { Req ($names -contains $a) "Eksik alan '$a' ($where)." "Missing field '$a' in $where" }
}
function Test-StepShape($s, [string]$where) {
    $t = [string]$s.type
    if (-not $fields.ContainsKey($t)) { Req $false "Bilinmeyen adim turu '$t' ($where)." "Unknown step type '$t' in $where"; return }
    Test-Fields $s $fields[$t] $where
}

Test-Fields $plan @('steps', 'risks', 'total_shrink_bytes') 'plan'
Req (@($plan.steps).Count -gt 0) 'Plan bos.' 'Plan has no steps.'
Stop-IfFailed
$i = 0
foreach ($ps in @($plan.steps)) {
    $i++
    Test-Fields $ps @('description', 'step', 'undo') "steps[$i]"
    if ($ps.step) { Test-StepShape $ps.step "steps[$i].step" } else { Req $false "steps[$i].step yok." "steps[$i].step missing" }
    if ($ps.undo) { Test-StepShape $ps.undo "steps[$i].undo" }
}
Stop-IfFailed
$seq = (@($plan.steps) | ForEach-Object { [string]$_.step.type }) -join ','
$base = 'shrink_partition,create_partition,extract_iso,add_one_shot_boot_entry'
Req (($seq -eq $base) -or ($seq -eq "$base,reboot")) "Adim sirasi desteklenmiyor: $seq" "Unsupported step sequence: $seq (expected $base[,reboot])"
Stop-IfFailed

$sh = @($plan.steps)[0].step; $cr = @($plan.steps)[1].step
$ex = @($plan.steps)[2].step; $bo = @($plan.steps)[3].step
try {
    $dn = [int]$sh.disk; $pn = [int]$sh.partition
    $shrink = [int64]$sh.shrink_bytes; $total = [int64]$plan.total_shrink_bytes
    $stageSize = [int64]$cr.size_bytes
} catch { Abort 'Plandaki sayilar gecersiz.' "Bad numeric fields in plan: $($_.Exception.Message)" }
$label = [string]$cr.label
Req ($shrink -gt 0 -and $stageSize -gt 0) 'Boyutlar pozitif olmali.' 'Sizes must be positive.'
Req ($shrink -eq $total) 'shrink_bytes ile total_shrink_bytes esit degil.' "shrink_bytes ($shrink) must equal total_shrink_bytes ($total)"
Req ($stageSize -le $shrink) 'Hazirlik bolumu kucultulen alandan buyuk.' 'Staging size must fit in the shrunk space.'
Req ($cr.filesystem -eq 'fat32') 'Dosya sistemi fat32 olmali.' 'create_partition filesystem must be fat32'
Req ([int]$cr.disk -eq $dn) 'create_partition baska bir diski gosteriyor.' 'create_partition disk differs from shrink disk'
# -cmatch, not -match: under tr-TR a case-insensitive [A-Za-z] rejects the capital I (BESIDEOS would fail).
Req ($label -cmatch '^[A-Za-z0-9_]{1,11}$') 'Etiket gecersiz (1-11 harf/rakam).' "Invalid FAT32 label '$label'"
Req ([string]$ex.target_label -ceq $label) 'extract_iso hedef etiketi uyusmuyor.' 'extract_iso target_label differs from created label'
$desc = [string]$bo.description; $loader = [string]$bo.loader_path
Req ($desc -match '^[\x20-\x7E]+$' -and $desc -notmatch '["{}]') 'Onyukleme aciklamasi yalniz ASCII, tirnaksiz olmali.' 'Boot entry description must be printable ASCII without quotes/braces'
$a = $env:PROCESSOR_ARCHITEW6432; if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
$leaf = Split-Path -Leaf $loader
$wantLeaf = $null
if ($a -eq 'ARM64') { $wantLeaf = 'BOOTAA64.EFI' } elseif ($a -eq 'AMD64') { $wantLeaf = 'BOOTX64.EFI' }
Req ($wantLeaf -and $leaf -ieq $wantLeaf -and $loader.ToLowerInvariant() -match '^\\efi\\boot\\[^\\]+$') "Yukleyici yolu bu mimariyle ($a) uyusmuyor: $loader" "loader_path '$loader' does not match architecture '$a'"
Stop-IfFailed

# --- firmware ---
# Mirrors collect-host-facts.ps1: registry PEFirmwareType, then kernel32 GetFirmwareType, then bcdedit winload.efi/.exe.
# Unknown => $null => abort (fail-closed).
$uefi = $null
try {
    $t = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType).PEFirmwareType
    if ($t -eq 2) { $uefi = $true } elseif ($t -eq 1) { $uefi = $false }
    Log "PEFirmwareType=$t" 'DEBUG' -NoConsole
} catch { Log "PEFirmwareType unreadable: $($_.Exception.Message)" 'DEBUG' -NoConsole }
if ($uefi -eq $null) {
    try {
        Add-Type -Namespace BesideOS -Name Fw -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern bool GetFirmwareType(ref uint t);'
        [uint32]$ft = 0
        if ([BesideOS.Fw]::GetFirmwareType([ref]$ft)) {
            if ($ft -eq 2) { $uefi = $true } elseif ($ft -eq 1) { $uefi = $false }
            Log "GetFirmwareType=$ft" 'DEBUG' -NoConsole
        }
    } catch { Log "GetFirmwareType failed: $($_.Exception.Message)" 'WARN' }
}
if ($uefi -eq $null) {
    try {
        $bcd = (& bcdedit /enum '{current}' 2>&1 | Out-String).ToLowerInvariant()
        if ($bcd -match 'winload\.efi') { $uefi = $true } elseif ($bcd -match 'winload\.exe') { $uefi = $false }
        Log "uefi via bcdedit: $uefi"
    } catch { Log "bcdedit failed: $($_.Exception.Message)" 'WARN' }
}
Req ($uefi -eq $true) 'UEFI degil (veya belirlenemedi).' 'UEFI boot required (undetermined counts as not UEFI)'

# --- target disk/partition ---
$part = $null; $winPart = $null; $vol = $null; $disk = $null
try { $disk = Get-Disk -Number $dn -ErrorAction Stop } catch { }
Req ($null -ne $disk) "Disk $dn bulunamadi." "Disk $dn not found"
Stop-IfFailed
Req ([string]$disk.PartitionStyle -eq 'GPT') 'Disk GPT degil.' "Disk $dn must be GPT (is $($disk.PartitionStyle))"
Req (-not $disk.IsReadOnly -and -not $disk.IsOffline) 'Disk salt okunur ya da cevrimdisi.' 'Disk is read-only or offline'
try { $part = Get-Partition -DiskNumber $dn -PartitionNumber $pn -ErrorAction Stop } catch { }
Req ($null -ne $part) "Bolum $dn/$pn bulunamadi." "Partition $dn/$pn not found"
Stop-IfFailed
# $sdl = drive letter of the partition that gets shrunk. Usually the Windows drive, but the user may pick
# another NTFS data drive (e.g. a second disk). It must be an ordinary lettered NTFS data volume.
$winLetter = $env:SystemDrive.Substring(0, 1)
$sdl = $null
if ($part.DriveLetter -and [int]$part.DriveLetter -ne 0) { $sdl = [string]$part.DriveLetter }
Req ($null -ne $sdl) "Hedef bolumun surucu harfi yok ($dn/$pn)." "Target partition $dn/$pn has no drive letter"
Stop-IfFailed
try { $winPart = Get-Partition -DriveLetter $sdl -ErrorAction Stop } catch { }
Req ($winPart -and $winPart.DiskNumber -eq $dn -and $winPart.PartitionNumber -eq $pn) "Hedef bolum ${sdl}: surucusunu icermiyor." "Target partition must be the one holding ${sdl}:"
if ($sdl -ne $winLetter) {
    Req (-not $part.IsSystem -and -not $part.IsBoot -and -not $part.IsHidden) 'Hedef bolum sistem/onyukleme/gizli bolum olamaz.' "Target ${sdl}: must not be a system/boot/hidden partition"
    Log "Target drive ${sdl}: is not the Windows drive ($winLetter`:); shrinking a data drive on disk $dn."
}
try { $vol = Get-Volume -DriveLetter $sdl -ErrorAction Stop } catch { }
Req ($vol -and [string]$vol.FileSystem -eq 'NTFS') 'Windows bolumu NTFS degil.' 'Windows volume must be NTFS'
Stop-IfFailed
$enc = Get-Encrypted $sdl
Req ($enc -eq $false) 'BitLocker acik ya da durumu belirlenemedi.' "BitLocker must be verifiably off (result: $enc)"

# --- shrink feasibility ---
$cur = [int64]$part.Size; $newSize = $cur - $shrink
$sup = $null
try { $sup = Get-PartitionSupportedSize -DriveLetter $sdl -ErrorAction Stop } catch { }
Req ($null -ne $sup) 'Desteklenen boyut okunamadi.' 'Get-PartitionSupportedSize failed'
Stop-IfFailed
Req ($newSize -gt 0 -and $newSize -ge [int64]$sup.SizeMin) 'Kucultme mumkun degil (SizeMin asiliyor).' "Shrink impossible: new size $newSize < SizeMin $($sup.SizeMin)"
Req (([int64]$vol.SizeRemaining - $shrink) -ge $MinFreeAfter) 'Kucultmeden sonra Windows bolumunde 10 GiB bos yer kalmiyor.' "Free after shrink $([int64]$vol.SizeRemaining - $shrink) < 10 GiB"

# --- no existing BESIDEOS volume ---
$existing = $null
try { $existing = @(Get-Volume -ErrorAction Stop | Where-Object { $_.FileSystemLabel -eq $label }) } catch { }
Req ($null -ne $existing -and $existing.Count -eq 0) "'$label' etiketli bir birim zaten var (ya da liste alinamadi)." "A volume labelled '$label' already exists (or volumes unreadable)"

# --- media source ---
$srcPath = [string]$ex.iso_path
$srcIsRoot = ($srcPath -cmatch '^[A-Za-z]:\\?$')
$srcIsIso = ($srcPath.ToLowerInvariant() -match '\.iso$')
if ($srcIsRoot) { $srcPath = $srcPath.TrimEnd('\') + '\' }
if ($srcIsRoot) { Req (Test-Path -LiteralPath $srcPath -PathType Container) "Ortam yok: $srcPath" "Media root not found: $srcPath" }
elseif ($srcIsIso) { Req (Test-Path -LiteralPath $srcPath -PathType Leaf) "ISO yok: $srcPath" "ISO file not found: $srcPath" }
else { Req $false "iso_path ne .iso ne surucu koku: $srcPath" "iso_path is neither a .iso file nor a drive root: $srcPath" }
function Test-SourceTree([string]$root, [int64]$cap) {
    $sum = 0L
    foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction Stop)) {
        if ($f.Length -ge 4GB) { throw "File too large for FAT32: $($f.FullName)" }
        $sum += $f.Length
    }
    if ($sum -gt $cap) { throw "Media ($sum bytes) does not fit staging partition ($cap bytes)" }
    Log "source tree OK: $sum bytes"
}
if ($srcIsRoot) {
    $ok = $true; try { Test-SourceTree $srcPath $stageSize } catch { $ok = $false; Log $_.Exception.Message 'ERROR' }
    Req $ok 'Ortam icerigi FAT32 bolumune sigmiyor.' 'Media tree does not fit FAT32 staging partition'
}

$stateExists = Test-Path -LiteralPath $statePath
if ($Execute) { Req (-not $stateExists) 'apply-state.json zaten var; once -Undo calistirin.' 'apply-state.json exists; run -Undo first (or move it away).' }
elseif ($stateExists) { Log 'apply-state.json exists; -Execute would refuse.' 'WARN' }
Stop-IfFailed
Log "PREFLIGHT TAMAM / PREFLIGHT OK (disk $dn part $pn, size $cur -> $newSize, SizeMin $($sup.SizeMin))"

# =====================================================================
# EXECUTE / DRY-RUN
# =====================================================================
if ($Execute) { Log 'Adimlar uygulanacak / Executing steps:' } else { Log 'KURU CALISTIRMA: asagidaki eylemler yapilacakti (hicbiri yapilmiyor) / DRY-RUN: the actions below WOULD be taken (none are):' }
$script:State = [ordered]@{
    version = 2; started = (Get-Date -Format 's'); plan_file = $PlanFile
    windows = $null; original_size = $null; shrunk_size = $null
    created = $null; boot_entry = $null; iso = $null
    steps_done = @(); failed_step = $null
}
$stageLetter = $null
$n = 0
foreach ($ps in @($plan.steps)) {
    $n++; $s = $ps.step; $t = [string]$s.type
    Log "STEP $n/$(@($plan.steps).Count) [$t] $($ps.description)"
    try {
        switch ($t) {
            'shrink_partition' {
                # resolve by drive letter; plan numbers are only cross-checked
                $p = Get-Partition -DriveLetter $sdl -ErrorAction Stop
                if ($p.DiskNumber -ne $dn -or $p.PartitionNumber -ne $pn) { throw "Windows partition ($($p.DiskNumber)/$($p.PartitionNumber)) differs from plan ($dn/$pn)" }
                $cur = [int64]$p.Size; $newSize = $cur - $shrink
                $sup = Get-PartitionSupportedSize -DriveLetter $sdl -ErrorAction Stop
                if ($newSize -lt [int64]$sup.SizeMin) { throw "new size $newSize < SizeMin $($sup.SizeMin)" }
                $cmd = "Resize-Partition -DriveLetter $sdl -Size $newSize"
                if (-not $Execute) { Log "DRY-RUN: would run $cmd  (current $cur, SizeMin $($sup.SizeMin))" }
                else {
                    $script:State.windows = [ordered]@{ disk = $dn; partition = $pn; letter = $sdl; guid = [string]$p.Guid; unique_id = [string]$p.UniqueId }
                    $script:State.original_size = $cur
                    Save-State   # recorded BEFORE the change so a half-done resize is still undoable
                    Log "RUN: $cmd"
                    Resize-Partition -DriveLetter $sdl -Size ([uint64]$newSize) -ErrorAction Stop
                    $script:State.shrunk_size = [int64](Get-Partition -DriveLetter $sdl).Size
                    Log "shrunk: $cur -> $($script:State.shrunk_size)"
                }
            }
            'create_partition' {
                $cmd1 = "New-Partition -DiskNumber $dn -Size $stageSize -AssignDriveLetter"
                $cmd2 = "Format-Volume -DriveLetter <new> -FileSystem FAT32 -NewFileSystemLabel $label -Confirm:`$false"
                if (-not $Execute) { Log "DRY-RUN: would run $cmd1"; Log "DRY-RUN: then $cmd2" }
                else {
                    Log "RUN: $cmd1"
                    $np = New-Partition -DiskNumber $dn -Size ([uint64]$stageSize) -AssignDriveLetter -ErrorAction Stop
                    # np.PartitionNumber is stale (Windows renumbers); record offset/size first, then resolve the real object
                    $script:State.created = [ordered]@{ disk = $dn; partition = $null; label = $label; size_bytes = [int64]$np.Size; offset = [int64]$np.Offset; letter = $null; guid = [string]$np.Guid; unique_id = [string]$np.UniqueId }
                    Save-State
                    $cp = Find-Created $dn $np
                    if (-not $cp) { throw 'new partition not found by offset/size or got no drive letter' }
                    if (Test-Protected $cp) { throw 'new partition unexpectedly looks like a system partition' }
                    $stageLetter = [string]$cp.DriveLetter
                    $script:State.created.partition = [int]$cp.PartitionNumber
                    $script:State.created.letter = $stageLetter
                    $script:State.created.guid = [string]$cp.Guid
                    $script:State.created.unique_id = [string]$cp.UniqueId
                    $script:State.created.size_bytes = [int64]$cp.Size
                    Save-State
                    Log "RUN: Format-Volume -DriveLetter $stageLetter -FileSystem FAT32 -NewFileSystemLabel $label -Confirm:`$false"
                    [void](Format-Volume -DriveLetter $stageLetter -FileSystem FAT32 -NewFileSystemLabel $label -Confirm:$false -ErrorAction Stop)
                    $fv = Get-Volume -DriveLetter $stageLetter -ErrorAction Stop
                    if ([string]$fv.FileSystem -ne 'FAT32' -or [string]$fv.FileSystemLabel -ne $label) { throw "format verify failed ($($fv.FileSystem)/$($fv.FileSystemLabel))" }
                    $cp = Get-Partition -DriveLetter $stageLetter -ErrorAction Stop
                    $script:State.created.partition = [int]$cp.PartitionNumber
                    $script:State.created.size_bytes = [int64]$cp.Size
                    Log ('created: ' + (Describe-Part $cp))
                }
            }
            'extract_iso' {
                if (-not $Execute) {
                    if ($srcIsIso) { Log "DRY-RUN: would run Mount-DiskImage -ImagePath '$srcPath' -PassThru ; read its drive letter" ; $srcRoot = '<iso-letter>:\' }
                    else { $srcRoot = $srcPath }
                    Log "DRY-RUN: would run robocopy $srcRoot <staging-letter>:\ /E /R:1 /W:1 /NFL /NDL /NP /XD 'System Volume Information' '`$RECYCLE.BIN'  (exit < 8 = ok)"
                    Log "DRY-RUN: then verify <staging-letter>:$loader exists$(if ($srcIsIso) { '; Dismount-DiskImage' })"
                } else {
                    $fv = Get-Volume -DriveLetter $stageLetter -ErrorAction Stop
                    if ([string]$fv.FileSystemLabel -ne [string]$ex.target_label) { throw "staging volume label mismatch ($($fv.FileSystemLabel))" }
                    $mounted = $false; $srcRoot = $srcPath
                    try {
                        if ($srcIsIso) {
                            Log "RUN: Mount-DiskImage -ImagePath '$srcPath' -PassThru"
                            [void](Mount-DiskImage -ImagePath $srcPath -PassThru -ErrorAction Stop)
                            $mounted = $true
                            $script:State.iso = [ordered]@{ path = $srcPath; mounted_by_script = $true }; Save-State
                            $il = $null
                            for ($k = 0; $k -lt 15 -and -not $il; $k++) {
                                $iv = Get-DiskImage -ImagePath $srcPath | Get-Volume
                                if ($iv -and $iv.DriveLetter) { $il = [string]$iv.DriveLetter } else { Start-Sleep -Seconds 1 }
                            }
                            if (-not $il) { throw 'mounted ISO has no drive letter' }
                            if ($il -eq $stageLetter) { throw 'ISO mounted on staging letter (refusing)' }
                            $srcRoot = "${il}:\"
                            Test-SourceTree $srcRoot ([int64]$script:State.created.size_bytes)
                        }
                        $dst = "${stageLetter}:\"
                        # drive roots have no spaces, so PS 5.1 passes them unquoted (no trailing-backslash quote bug)
                        $r = Invoke-Native 'robocopy' @($srcRoot, $dst, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/XD', 'System Volume Information', '$RECYCLE.BIN')
                        if ($r.Code -ge 8) { throw "robocopy failed (exit $($r.Code))" }
                        $lp = Join-Path $dst $loader.TrimStart('\')
                        if (-not (Test-Path -LiteralPath $lp -PathType Leaf)) { throw "loader missing after copy: $lp" }
                        Log "copy verified: $lp"
                    } finally {
                        if ($mounted) {
                            try { Dismount-DiskImage -ImagePath $srcPath | Out-Null; Log 'ISO dismounted.' }
                            catch { Log "Dismount-DiskImage failed: $($_.Exception.Message)" 'WARN' }
                        }
                    }
                }
            }
            'add_one_shot_boot_entry' {
                if (-not $Execute) {
                    Log "DRY-RUN: would run bcdedit /copy {bootmgr} /d `"$desc`"   (parse new {guid} from output)"
                    Log "DRY-RUN: then bcdedit /set {guid} device partition=<staging-letter>:"
                    Log "DRY-RUN: then bcdedit /set {guid} path $loader"
                    Log "DRY-RUN: then bcdedit /set {fwbootmgr} bootsequence {guid}   (one-shot)"
                } else {
                    $r = Invoke-Native 'bcdedit' @('/copy', '{bootmgr}', '/d', $desc)
                    $m = [regex]::Matches($r.Out, $GUID_RE)
                    if ($r.Code -ne 0 -or $m.Count -ne 1) { throw "bcdedit /copy failed or GUID not found (exit $($r.Code), matches $($m.Count))" }
                    $g = $m[0].Value
                    $script:State.boot_entry = [ordered]@{ guid = $g; description = $desc }; Save-State
                    foreach ($args2 in @(
                            @('/set', $g, 'device', "partition=${stageLetter}:"),
                            @('/set', $g, 'path', $loader),
                            @('/set', '{fwbootmgr}', 'bootsequence', $g))) {
                        $r = Invoke-Native 'bcdedit' $args2
                        if ($r.Code -ne 0) { throw "bcdedit $($args2 -join ' ') failed (exit $($r.Code))" }
                    }
                    [void](Invoke-Native 'bcdedit' @('/enum', $g))
                }
            }
            'reboot' {
                if ($Execute -and $Reboot) {
                    $script:State.steps_done += $t; Save-State
                    Log 'RUN: Restart-Computer -Force'
                    Restart-Computer -Force
                } else { Log 'reboot skipped (needs -Execute and -Reboot).' }
            }
        }
        if ($Execute -and $t -ne 'reboot') { $script:State.steps_done += $t; Save-State }
    } catch {
        Log "STEP $n [$t] FAILED: $($_.Exception.Message)" 'ERROR'
        if ($Execute) {
            $script:State.failed_step = "$n/$t"
            try { Save-State } catch { Log "state save failed: $($_.Exception.Message)" 'ERROR' }
            Log "DURDURULDU. Geri almak icin -Undo ile tekrar calistirin (UNDO.flag). / STOPPED. Run again with -Undo (and -Execute) to roll back." 'ERROR'
        }
        exit 1
    }
}
if ($Execute) { Log 'DONE: all steps executed. State in apply-state.json.' }
else { Log 'DRY-RUN complete: nothing was changed. Add -Execute to apply.' }
exit 0
