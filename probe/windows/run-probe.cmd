@echo off
rem Yonetici degilse kendini yonetici olarak yeniden baslatir (yalnizca bu probu yukseltir).
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Yonetici izni isteniyor...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect-host-facts.ps1" -OutDir "%~dp0"
echo.
if exist "%~dp0facts.json" (
  echo Tamam: facts.json bu dosyanin yanina yazildi: %~dp0facts.json
) else (
  echo HATA: facts.json olusmadi. Nedeni icin probe.log dosyasina bakin.
)
pause
