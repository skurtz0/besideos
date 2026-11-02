<#
.SYNOPSIS
  BesideOS host-facts collector (Stage 3b). Windows PowerShell 5.1.

.DESCRIPTION
  READ-ONLY GUARANTEE: only Get-* cmdlets, registry reads, CIM queries,
  `bcdedit /enum` and `manage-bde -status` are used. Nothing is created,
  changed, resized, formatted or removed on any disk. The only things written
  are the two output files below.

  Needs Administrator for BitLocker state and Get-PartitionSupportedSize.
  Without it those facts fall back to the fail-closed values
  (encrypted = null, min_size_bytes = size_bytes).

  Output (in -OutDir, default: this script's folder):
    probe.log   always written
    facts.json  written ONLY on success (UTF-8, no BOM)
  Schema: core/besideos_core/src/facts.rs (HostFacts).

  Heuristics (documented per request):
    uefi      registry Control\PEFirmwareType (2=UEFI, 1=BIOS); fallback:
              kernel32 GetFirmwareType (no admin needed); fallback: bcdedit
              winload.efi/.exe. Undeterminable -> abort (never guessed false).
    arch      PROCESSOR_ARCHITEW6432 (32-bit PS on 64-bit OS) else
              PROCESSOR_ARCHITECTURE; AMD64->x86_64, ARM64->arm64, else abort.
    dynamic   any Win32_DiskPartition on that disk whose Type contains
              "Logical Disk Manager" (covers MBR and GPT LDM partitions).
    is_system Partition.IsSystem -or Partition.IsBoot.
    used      size - Get-Volume.SizeRemaining; unknown -> size (fail closed).
    min_size  NTFS + drive letter -> Get-PartitionSupportedSize.SizeMin;
              anything else/failure -> size_bytes (= "cannot shrink").
    encrypted Get-BitLockerVolume (VolumeStatus != FullyDecrypted), else
              manage-bde percentage parse; no drive letter: MSR/EFI -> false,
              other -> null; undeterminable -> null.
    filesystem lowercase Get-Volume.FileSystem; MSR -> "msr"; none -> "".
#>
param([string]$OutDir = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = (Get-Location).Path }
$logPath   = Join-Path $OutDir 'probe.log'
$factsPath = Join-Path $OutDir 'facts.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:logLines = New-Object System.Collections.ArrayList

function Log([string]$m) {
    [void]$script:logLines.Add(('{0} {1}' -f (Get-Date -Format 's'), $m))
}
function Save-Log {
    # BOM so Windows PowerShell 5.1 / Notepad read the Turkish text as UTF-8 (facts.json stays BOM-less).
    try { [System.IO.File]::WriteAllText($logPath, (($script:logLines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true))) } catch { }
}
function Fail([string]$m) {
    Log "FATAL: $m"; Log 'facts.json NOT written.'
    Save-Log
    exit 1
}

try {
    # A stale facts.json from an earlier run must not survive a failed run.
    if (Test-Path -LiteralPath $factsPath) { Remove-Item -LiteralPath $factsPath -Force }
} catch { }

$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
Log "start; admin=$isAdmin; PS=$($PSVersionTable.PSVersion)"
if (-not $isAdmin) { Log 'WARN: not Administrator; BitLocker/SupportedSize will be fail-closed.' }

# ---- arch ----
$a = $env:PROCESSOR_ARCHITEW6432
if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
switch ($a) {
    'AMD64' { $arch = 'x86_64' }
    'ARM64' { $arch = 'arm64' }
    default { Fail "unsupported architecture '$a'" }
}
Log "arch=$arch"

# ---- uefi ----
$uefi = $null
try {
    $t = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType).PEFirmwareType
    if ($t -eq 2) { $uefi = $true } elseif ($t -eq 1) { $uefi = $false }
    Log "PEFirmwareType=$t"
} catch { Log "PEFirmwareType unreadable: $($_.Exception.Message)" }
if ($uefi -eq $null) {
    # GetFirmwareType (Windows 8+) needs no Administrator: 1=BIOS, 2=UEFI.
    try {
        Add-Type -Namespace BesideOS -Name Fw -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern bool GetFirmwareType(ref uint t);'
        [uint32]$ft = 0
        if ([BesideOS.Fw]::GetFirmwareType([ref]$ft)) {
            if ($ft -eq 2) { $uefi = $true } elseif ($ft -eq 1) { $uefi = $false }
            Log "GetFirmwareType=$ft"
        } else { Log 'GetFirmwareType returned false' }
    } catch { Log "GetFirmwareType failed: $($_.Exception.Message)" }
}
if ($uefi -eq $null) {
    # bcdedit fails without Administrator (access denied text, no exception), so only a positive match counts.
    try {
        $bcd = (& bcdedit /enum '{current}' 2>&1 | Out-String).ToLowerInvariant()
        if ($bcd -match 'winload\.efi') { $uefi = $true }
        elseif ($bcd -match 'winload\.exe') { $uefi = $false }
        Log "uefi via bcdedit: $uefi"
    } catch { Log "bcdedit failed: $($_.Exception.Message)" }
}
if ($uefi -eq $null) { Fail 'cannot determine UEFI/BIOS (run as Administrator)' }
Log "uefi=$uefi"

# ---- BitLocker helper: $true / $false / $null ----
$haveBl = [bool](Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)
function Get-Encrypted([string]$letter) {
    if ($haveBl) {
        try {
            $v = Get-BitLockerVolume -MountPoint "${letter}:" -ErrorAction Stop
            return ([string]$v.VolumeStatus -ne 'FullyDecrypted')
        } catch { Log "Get-BitLockerVolume ${letter}: failed: $($_.Exception.Message)" }
    }
    try {
        $o = (& manage-bde -status "${letter}:" 2>&1 | Out-String)
        # Locale-independent: first "NN%" figure is "Percentage Encrypted".
        if ($LASTEXITCODE -eq 0 -and $o -match '(\d+(?:[.,]\d+)?)\s*%') {
            return ([double]($Matches[1] -replace ',', '.') -gt 0)
        }
        Log "manage-bde ${letter}: unparseable (exit $LASTEXITCODE)"
    } catch { Log "manage-bde ${letter}: failed: $($_.Exception.Message)" }
    return $null
}

# ---- LDM (dynamic) partitions per disk ----
$ldm = @{}
try {
    foreach ($wp in @(Get-CimInstance Win32_DiskPartition)) {
        if ([string]$wp.Type -match 'Logical Disk Manager') { $ldm[[int]$wp.DiskIndex] = $true }
    }
} catch { Log "Win32_DiskPartition failed: $($_.Exception.Message) (dynamic=false assumed)" }

$MSR = 'e3c9e316-0b5c-4db8-817d-f92df00215ae'
$disks = @()
$drives = @()
try { $diskList = @(Get-Disk) } catch { Fail "Get-Disk failed: $($_.Exception.Message)" }

foreach ($d in $diskList) {
    $style = ([string]$d.PartitionStyle).ToLowerInvariant()
    if ($style -ne 'gpt' -and $style -ne 'mbr') { Log "disk $($d.Number): style '$style' skipped"; continue }
    $parts = @()
    try { $plist = @(Get-Partition -DiskNumber $d.Number -ErrorAction Stop) }
    catch { Log "disk $($d.Number): Get-Partition failed: $($_.Exception.Message)"; $plist = @() }
    foreach ($p in $plist) {
        $size = [uint64]$p.Size
        $letter = $null
        if ($p.DriveLetter -and [int]$p.DriveLetter -ne 0) { $letter = [string]$p.DriveLetter }
        $isMsr = ($style -eq 'gpt' -and ([string]$p.GptType).Trim('{}').ToLowerInvariant() -eq $MSR)
        $fs = ''; $used = $size; $min = $size; $enc = $null; $vol = $null
        if ($isMsr) { $fs = 'msr' }
        try {
            $vol = $p | Get-Volume -ErrorAction Stop
            if ($vol) {
                $fs = ([string]$vol.FileSystem).ToLowerInvariant()
                if ($vol.SizeRemaining -ne $null -and [uint64]$vol.SizeRemaining -le $size) { $used = $size - [uint64]$vol.SizeRemaining }
                else { Log "disk $($d.Number) part $($p.PartitionNumber): used unknown -> used=size" }
            }
        } catch { if (-not $isMsr) { Log "disk $($d.Number) part $($p.PartitionNumber): no volume info -> used=size" } }
        if ($letter -and $fs -eq 'ntfs') {
            try { $min = [uint64](Get-PartitionSupportedSize -DriveLetter $letter -ErrorAction Stop).SizeMin }
            catch { Log "disk $($d.Number) part $($p.PartitionNumber): SupportedSize failed: $($_.Exception.Message) -> min=size" }
            if ($min -gt $size) { $min = $size }
        }
        if ($letter) { $enc = Get-Encrypted $letter }
        elseif ($isMsr -or $p.IsSystem) { $enc = $false }
        if ($enc -eq $null) { Log "disk $($d.Number) part $($p.PartitionNumber): encrypted=null" }
        $parts += ,[ordered]@{
            number = [int]$p.PartitionNumber; size_bytes = $size; used_bytes = $used
            min_size_bytes = $min; filesystem = $fs
            is_system = [bool]($p.IsSystem -or $p.IsBoot); encrypted = $enc
        }
        # Candidates the UI may offer as the place to carve Linux space from (GUI only; the planner re-checks everything).
        if ($letter -and $fs -eq 'ntfs' -and $enc -eq $false -and $style -eq 'gpt' -and -not $ldm.ContainsKey([int]$d.Number)) {
            $lbl = ''; if ($vol -and $vol.FileSystemLabel) { $lbl = [string]$vol.FileSystemLabel }
            $drives += ,[ordered]@{
                disk = [int]$d.Number; partition = [int]$p.PartitionNumber; letter = $letter; label = $lbl
                disk_name = [string]$d.FriendlyName; disk_size_bytes = [uint64]$d.Size
                size_bytes = $size; free_bytes = ($size - $used); is_windows = $false
            }
        }
    }
    $disks += ,[ordered]@{
        number = [int]$d.Number; size_bytes = [uint64]$d.Size; style = $style
        dynamic = [bool]$ldm.ContainsKey([int]$d.Number); partitions = $parts
    }
}

# ---- windows partition ----
try {
    $sd = $env:SystemDrive.Substring(0, 1)
    $wp = Get-Partition -DriveLetter $sd -ErrorAction Stop
    $win = [ordered]@{ disk = [int]$wp.DiskNumber; partition = [int]$wp.PartitionNumber }
} catch { Fail "cannot locate Windows partition: $($_.Exception.Message)" }

$facts = [ordered]@{ uefi = $uefi; arch = $arch; windows_partition = $win; disks = $disks }
try {
    $json = ConvertTo-Json -InputObject $facts -Depth 6
    [System.IO.File]::WriteAllText($factsPath, $json, $utf8)
} catch { Fail "writing facts.json failed: $($_.Exception.Message)" }
try {
    foreach ($dr in $drives) { if ($dr.letter -eq $sd) { $dr.is_windows = $true } }
    $dj = ConvertTo-Json -InputObject @($drives) -Depth 4
    if (-not $dj) { $dj = '[]' }
    [System.IO.File]::WriteAllText((Join-Path (Split-Path -Parent $factsPath) 'drives.json'), $dj, $utf8)
} catch { Log "writing drives.json failed: $($_.Exception.Message) (non-fatal)" }
Log "OK: facts.json written ($($disks.Count) disks)"
Save-Log
exit 0
