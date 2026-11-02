<#
.SYNOPSIS
  Lists the UEFI boot entries of this computer and chooses which system starts next (once) or by default.
  ASCII only on purpose: Windows PowerShell 5.1 reads BOM-less files as ANSI.

.PARAMETER Action   list (default), next, default
.PARAMETER Id       list: unused. next/default: the identifier ({guid} or {bootmgr}) of an entry from the list.
.PARAMETER OutFile  list: where the JSON result is written (UTF-8).
.PARAMETER Execute  next/default: really change the firmware boot settings. Without it nothing is changed (dry-run).
#>
[CmdletBinding()]
param(
    [ValidateSet('list', 'next', 'default')][string]$Action = 'list',
    [string]$Id,
    [string]$OutFile,
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
$GUID_RE = '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}'

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) { Write-Error 'Must run as Administrator.'; exit 3 }

# bcdedit element names (identifier, description, displayorder, ...) are not localized; values may continue on indented lines.
function Read-Blocks([string]$text) {
    $blocks = @()
    foreach ($chunk in ($text -split "(?:\r?\n){2,}")) {
        $lines = @($chunk -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
        if ($lines.Count -lt 2) { continue }
        $b = [ordered]@{ title = $lines[0].Trim(); props = [ordered]@{} }
        $last = $null
        foreach ($ln in ($lines | Select-Object -Skip 1)) {
            if ($ln -match '^-{3,}\s*$') { continue }
            if ($ln -match '^(\S+)\s{2,}(.*)$') { $last = $Matches[1]; $b.props[$last] = @($Matches[2].Trim()) }
            elseif ($last -and $ln -match '^\s+(\S.*)$') { $b.props[$last] += $Matches[1].Trim() }
        }
        $blocks += , $b
    }
    return $blocks
}

$raw = (& bcdedit.exe /enum firmware | Out-String)
if ($LASTEXITCODE -ne 0) { Write-Error 'bcdedit /enum firmware failed (is this a UEFI computer?).'; exit 1 }
$blocks = Read-Blocks $raw

$mgr = $blocks | Where-Object { $_.props['identifier'] -and $_.props['identifier'][0] -eq '{fwbootmgr}' } | Select-Object -First 1
$order = @(); $seq = @(); $timeout = $null
if ($mgr) {
    if ($mgr.props['displayorder']) { $order = @($mgr.props['displayorder'] | ForEach-Object { [regex]::Matches($_, '\{[^}]+\}') | ForEach-Object { $_.Value } }) }
    if ($mgr.props['bootsequence']) { $seq = @($mgr.props['bootsequence'] | ForEach-Object { [regex]::Matches($_, '\{[^}]+\}') | ForEach-Object { $_.Value } }) }
    if ($mgr.props['timeout']) { $timeout = [int]($mgr.props['timeout'][0] -replace '\D', '') }
}
$entries = @()
foreach ($b in $blocks) {
    if (-not $b.props['identifier']) { continue }
    $eid = $b.props['identifier'][0]   # not $id: PowerShell variable names are case-insensitive and $Id is the parameter
    if ($eid -eq '{fwbootmgr}') { continue }
    $entries += [ordered]@{
        id          = $eid
        title       = $b.title
        description = $(if ($b.props['description']) { $b.props['description'][0] } else { '' })
        path        = $(if ($b.props['path']) { $b.props['path'][0] } else { '' })
    }
}

if ($Action -eq 'list') {
    $result = [ordered]@{ order = $order; sequence = $seq; timeout = $timeout; entries = $entries }
    $json = $result | ConvertTo-Json -Depth 5
    if ($OutFile) { [System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding $false)) } else { $json }
    exit 0
}

# next / default: the identifier must be one of the listed entries (never a free-form value handed to bcdedit)
if (-not $Id -or ($Id -notmatch "^$GUID_RE`$" -and $Id -ne '{bootmgr}')) { Write-Error "Bad or missing -Id: $Id"; exit 2 }
if (-not ($entries | Where-Object { $_.id -ieq $Id })) { Write-Error "Entry $Id is not a firmware boot entry of this computer."; exit 2 }

if ($Action -eq 'next') { $bcd = @('/set', '{fwbootmgr}', 'bootsequence', $Id); $what = "start $Id once at the next boot" }
else { $bcd = @('/set', '{fwbootmgr}', 'displayorder', $Id, '/addfirst'); $what = "make $Id the first (default) boot entry" }
if (-not $Execute) { Write-Output "DRY-RUN: would run bcdedit $($bcd -join ' ')  ($what)"; exit 0 }
& bcdedit.exe @bcd | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "bcdedit $($bcd -join ' ') failed (exit $LASTEXITCODE)."; exit 1 }
Write-Output "DONE: $what"
exit 0
