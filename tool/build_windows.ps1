# Builds the Windows app together with its installer engine (the Rust planner).
# Needs: Flutter, Rust (cargo), Visual Studio "Desktop development with C++".
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Push-Location (Join-Path $root 'core')
try { cargo build --release --bin besideos-plan; if ($LASTEXITCODE -ne 0) { throw 'cargo build failed' } } finally { Pop-Location }

Push-Location $root
try { flutter build windows --release; if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' } } finally { Pop-Location }

$out = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $out 'engine\besideos-plan.exe'))) { throw "engine\besideos-plan.exe missing in $out" }
Write-Host "OK: $out\besideos_site.exe"
