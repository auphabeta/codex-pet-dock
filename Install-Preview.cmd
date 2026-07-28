@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0packaging\Install-CodexPetDock.ps1"
if errorlevel 1 (
  echo.
  echo Codex Pet Dock installation failed.
  pause
  exit /b 1
)
exit /b 0

