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
    [string]$PlanFile = (Join-Path $PSScriptRoot 'plan.json'),
    [switch]$Execute,
    [switch]$Undo,
    [switch]$Reboot,
    [string]$OutDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = (Get-Location).Path }
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
function Get-LetterOf([int]$disk, [int]$pn) {
    for ($i = 0; $i -lt 15; $i++) {
        $l = (Get-Partition -DiskNumber $disk -PartitionNumber $pn).DriveLetter
        if ($l) { return [string]$l }
        Start-Sleep -Seconds 1
    }
    return $null
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

    # 1. boot entry
    if ($st.boot_entry -and $st.boot_entry.guid) {
        $g = [string]$st.boot_entry.guid
        if ($g -notmatch "^$GUID_RE`$") { Abort 'Durum dosyasindaki GUID gecersiz.' "Bad GUID in state: $g" }
        Log "UNDO 1: boot entry $g"
        if (-not $Execute) {
            Log "DRY-RUN: would run bcdedit /deletevalue {fwbootmgr} bootsequence (only if it lists $g), then bcdedit /delete $g"
        } else {
            $fw = Invoke-Native 'bcdedit' @('/enum', '{fwbootmgr}')
            if ($fw.Out -match [regex]::Escape($g)) {
                $r = Invoke-Native 'bcdedit' @('/deletevalue', '{fwbootmgr}', 'bootsequence')
                if ($r.Code -ne 0) { Abort 'bootsequence silinemedi.' 'bcdedit /deletevalue bootsequence failed.' }
            }
            $e = Invoke-Native 'bcdedit' @('/enum', $g)
            if ($e.Code -eq 0) {
                $r = Invoke-Native 'bcdedit' @('/delete', $g)
                if ($r.Code -ne 0) { Abort 'Onyukleme girdisi silinemedi.' 'bcdedit /delete failed.' }
            } else { Log 'boot entry already gone.' }
        }
    }

    # 2. staging partition (only the one we created)
    if ($st.created -and $st.created.partition) {
        $cd = [int]$st.created.disk; $cp = [int]$st.created.partition
        Log "UNDO 2: remove staging partition disk $cd partition $cp label $($st.created.label)"
        $p = $null
        try { $p = Get-Partition -DiskNumber $cd -PartitionNumber $cp -ErrorAction Stop } catch { }
        if (-not $p) { Log 'staging partition not present; skipping.' 'WARN' }
        else {
            $v = $null
            try { $v = $p | Get-Volume -ErrorAction Stop } catch { }
            $okLabel = ($v -and ([string]$v.FileSystemLabel -eq [string]$st.created.label))
            $okSize = ([int64]$p.Size -eq [int64]$st.created.size_bytes)
            if (-not ($okLabel -and $okSize)) {
                Abort "Bolum $cd/$cp etiketi/boyutu durum dosyasiyla uyusmuyor; silinmedi." "Partition $cd/$cp label/size do not match state; refusing to remove."
            }
            $cmd = "Remove-Partition -DiskNumber $cd -PartitionNumber $cp -Confirm:`$false"
            if (-not $Execute) { Log "DRY-RUN: would run $cmd" }
            else { Log "RUN: $cmd"; Remove-Partition -DiskNumber $cd -PartitionNumber $cp -Confirm:$false -ErrorAction Stop }
        }
    }

    # 3. grow Windows partition back
    if ($st.windows -and $st.windows.partition -ne $null) {
        $wd = [int]$st.windows.disk; $wn = [int]$st.windows.partition
        Log "UNDO 3: grow Windows partition disk $wd partition $wn to SizeMax (original size $($st.original_size))"
        $wp = Get-Partition -DiskNumber $wd -PartitionNumber $wn -ErrorAction Stop
        if ([string]$wp.DriveLetter -ne $sd) { Abort 'Durum dosyasindaki bolum Windows bolumu degil.' 'State partition is not the Windows partition.' }
        $sup = Get-PartitionSupportedSize -DiskNumber $wd -PartitionNumber $wn
        Log "current=$($wp.Size) SizeMax=$($sup.SizeMax) original=$($st.original_size)"
        if ([int64]$sup.SizeMax -le [int64]$wp.Size) { Log 'already at SizeMax; nothing to grow.' }
        else {
            $cmd = "Resize-Partition -DiskNumber $wd -PartitionNumber $wn -Size $($sup.SizeMax)"
            if (-not $Execute) { Log "DRY-RUN: would run $cmd" }
            else { Log "RUN: $cmd"; Resize-Partition -DiskNumber $wd -PartitionNumber $wn -Size ([uint64]$sup.SizeMax) -ErrorAction Stop }
        }
    }
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
Req ($label -match '^[A-Za-z0-9_]{1,11}$') 'Etiket gecersiz (1-11 harf/rakam).' "Invalid FAT32 label '$label'"
Req ([string]$ex.target_label -ceq $label) 'extract_iso hedef etiketi uyusmuyor.' 'extract_iso target_label differs from created label'
$desc = [string]$bo.description; $loader = [string]$bo.loader_path
Req ($desc -match '^[\x20-\x7E]+$' -and $desc -notmatch '["{}]') 'Onyukleme aciklamasi yalniz ASCII, tirnaksiz olmali.' 'Boot entry description must be printable ASCII without quotes/braces'
$a = $env:PROCESSOR_ARCHITEW6432; if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
$leaf = Split-Path -Leaf $loader
$wantLeaf = $null
if ($a -eq 'ARM64') { $wantLeaf = 'BOOTAA64.EFI' } elseif ($a -eq 'AMD64') { $wantLeaf = 'BOOTX64.EFI' }
Req ($wantLeaf -and $leaf -ieq $wantLeaf -and $loader -imatch '^\\EFI\\BOOT\\[^\\]+$') "Yukleyici yolu bu mimariyle ($a) uyusmuyor: $loader" "loader_path '$loader' does not match architecture '$a'"
Stop-IfFailed

# --- firmware ---
# Mirrors collect-host-facts.ps1: registry PEFirmwareType first, then bcdedit fallback (boot manager path ends in .efi).
# Unknown => $false => abort (fail-closed).
$uefi = $false
try {
    $t = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType).PEFirmwareType
    if ($t -eq 2) { $uefi = $true }
    Log "PEFirmwareType=$t" 'DEBUG' -NoConsole
} catch {
    Log "PEFirmwareType unreadable: $($_.Exception.Message)" 'DEBUG' -NoConsole
    try {
        $bcd = (& bcdedit /enum '{current}' 2>&1 | Out-String)
        if ($bcd -match '(?i)\.efi') { $uefi = $true }
        Log 'uefi decided via bcdedit'
    } catch { Log "bcdedit failed: $($_.Exception.Message)" 'WARN' }
}
Req $uefi 'UEFI degil (veya belirlenemedi).' 'UEFI boot required (undetermined counts as not UEFI)'

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
$sdl = $env:SystemDrive.Substring(0, 1)
try { $winPart = Get-Partition -DriveLetter $sdl -ErrorAction Stop } catch { }
Req ($winPart -and $winPart.DiskNumber -eq $dn -and $winPart.PartitionNumber -eq $pn) "Hedef bolum ${sdl}: surucusunu icermiyor." "Target partition must be the one holding ${sdl}:"
try { $vol = Get-Volume -DriveLetter $sdl -ErrorAction Stop } catch { }
Req ($vol -and [string]$vol.FileSystem -eq 'NTFS') 'Windows bolumu NTFS degil.' 'Windows volume must be NTFS'
Stop-IfFailed
$enc = Get-Encrypted $sdl
Req ($enc -eq $false) 'BitLocker acik ya da durumu belirlenemedi.' "BitLocker must be verifiably off (result: $enc)"

# --- shrink feasibility ---
$cur = [int64]$part.Size; $newSize = $cur - $shrink
$sup = $null
try { $sup = Get-PartitionSupportedSize -DiskNumber $dn -PartitionNumber $pn -ErrorAction Stop } catch { }
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
$srcIsRoot = ($srcPath -match '^[A-Za-z]:\\?$')
$srcIsIso = ($srcPath -imatch '\.iso$')
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
    version = 1; started = (Get-Date -Format 's'); plan_file = $PlanFile
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
                $p = Get-Partition -DiskNumber $dn -PartitionNumber $pn -ErrorAction Stop
                $cur = [int64]$p.Size; $newSize = $cur - $shrink
                $sup = Get-PartitionSupportedSize -DiskNumber $dn -PartitionNumber $pn -ErrorAction Stop
                if ($newSize -lt [int64]$sup.SizeMin) { throw "new size $newSize < SizeMin $($sup.SizeMin)" }
                $cmd = "Resize-Partition -DiskNumber $dn -PartitionNumber $pn -Size $newSize"
                if (-not $Execute) { Log "DRY-RUN: would run $cmd  (current $cur, SizeMin $($sup.SizeMin))" }
                else {
                    $script:State.windows = [ordered]@{ disk = $dn; partition = $pn }
                    $script:State.original_size = $cur
                    Save-State   # recorded BEFORE the change so a half-done resize is still undoable
                    Log "RUN: $cmd"
                    Resize-Partition -DiskNumber $dn -PartitionNumber $pn -Size ([uint64]$newSize) -ErrorAction Stop
                    $script:State.shrunk_size = [int64](Get-Partition -DiskNumber $dn -PartitionNumber $pn).Size
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
                    $npn = [int]$np.PartitionNumber
                    $script:State.created = [ordered]@{ disk = $dn; partition = $npn; label = $label; size_bytes = [int64]$np.Size; letter = $null }
                    Save-State
                    $stageLetter = Get-LetterOf $dn $npn
                    if (-not $stageLetter) { throw 'new partition got no drive letter' }
                    $script:State.created.letter = $stageLetter; Save-State
                    Log "RUN: Format-Volume -DriveLetter $stageLetter -FileSystem FAT32 -NewFileSystemLabel $label -Confirm:`$false"
                    [void](Format-Volume -DriveLetter $stageLetter -FileSystem FAT32 -NewFileSystemLabel $label -Confirm:$false -ErrorAction Stop)
                    $fv = Get-Volume -DriveLetter $stageLetter -ErrorAction Stop
                    if ([string]$fv.FileSystem -ne 'FAT32' -or [string]$fv.FileSystemLabel -ne $label) { throw "format verify failed ($($fv.FileSystem)/$($fv.FileSystemLabel))" }
                    $script:State.created.size_bytes = [int64](Get-Partition -DiskNumber $dn -PartitionNumber $npn).Size
                    Log "created partition $npn, letter ${stageLetter}:"
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
