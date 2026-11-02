<#
.SYNOPSIS
  BesideOS ISO inspector. Windows PowerShell 5.1. ASCII-only on purpose
  (PS 5.1 reads BOM-less .ps1 files in the ANSI code page).

.DESCRIPTION
  READ-ONLY: mounts the ISO, measures its contents, dismounts it. The only thing
  written is -OutFile: the IsoFacts JSON that besideos-plan expects
  (arch, size_bytes, extracted_bytes, largest_file_bytes, largest_file_name).
  Needs no Administrator rights.

  Exit codes: 0 ok (OutFile written), 1 error (message on stderr, no OutFile).
#>
param(
    [Parameter(Mandatory = $true)][string]$IsoPath,
    [Parameter(Mandatory = $true)][ValidateSet('x86_64', 'arm64')][string]$Arch,
    [Parameter(Mandatory = $true)][string]$OutFile
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$mounted = $false
$code = 1
try {
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
    if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) { throw "ISO not found: $IsoPath" }
    $size = (Get-Item -LiteralPath $IsoPath).Length
    [void](Mount-DiskImage -ImagePath $IsoPath -PassThru)
    $mounted = $true
    $letter = $null
    for ($k = 0; $k -lt 15 -and -not $letter; $k++) {
        $v = Get-DiskImage -ImagePath $IsoPath | Get-Volume
        if ($v -and $v.DriveLetter) { $letter = [string]$v.DriveLetter } else { Start-Sleep -Seconds 1 }
    }
    if (-not $letter) { throw 'mounted ISO has no drive letter' }
    $root = "${letter}:\"
    $sum = [uint64]0; $max = [uint64]0; $maxName = ''
    foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction Stop)) {
        $sum += [uint64]$f.Length
        if ([uint64]$f.Length -gt $max) {
            $max = [uint64]$f.Length
            $maxName = $f.FullName.Substring($root.Length).Replace('\', '/')
        }
    }
    $o = [ordered]@{
        arch = $Arch; size_bytes = [uint64]$size; extracted_bytes = $sum
        largest_file_bytes = $max; largest_file_name = $maxName
    }
    [System.IO.File]::WriteAllText($OutFile, (ConvertTo-Json -InputObject $o), $utf8)
    $code = 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    $code = 1
} finally {
    if ($mounted) { try { [void](Dismount-DiskImage -ImagePath $IsoPath) } catch { } }
}
exit $code
