@echo off
rem Doppelklick: holt den neuesten Stand von Bambu Studio Multi, baut die App und installiert sie.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows-installieren.ps1" %*
if errorlevel 1 (
  echo.
  echo Das Update ist fehlgeschlagen. Das Protokoll liegt als build-*.log im Ordner %~dp0
) else (
  echo.
  echo Fertig. Bambu Studio Multi wird gestartet.
  start "" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Bambu Studio Multi.lnk"
)
echo.
pause
