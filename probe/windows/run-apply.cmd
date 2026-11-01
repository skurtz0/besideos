@echo off
rem Yonetici degilse kendini yonetici olarak yeniden baslatir. Mod, yanindaki bayrak dosyalarindan secilir.
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Yonetici izni isteniyor...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
set "ARGS="
set "MODE=KURU CALISTIRMA (hicbir sey degismez)"
if exist "%~dp0EXECUTE.flag" (set "ARGS=%ARGS% -Execute" & set "MODE=GERCEK UYGULAMA (-Execute)")
if exist "%~dp0REBOOT.flag" (set "ARGS=%ARGS% -Reboot" & set "MODE=%MODE% + yeniden baslatma")
if exist "%~dp0UNDO.flag" (set "ARGS=%ARGS% -Undo" & set "MODE=%MODE% + GERI ALMA (-Undo)")
echo Mod: %MODE%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-plan.ps1"%ARGS%
set RC=%errorlevel%
echo.
echo Cikis kodu: %RC%  (0 = tamam, 1 = hata/durduruldu). Ayrinti: apply.log
pause
