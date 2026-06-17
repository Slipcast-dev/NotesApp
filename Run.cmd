@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "LAUNCH_SCRIPT=%ROOT_DIR%Tools\LaunchPortable.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LAUNCH_SCRIPT%"
if errorlevel 1 (
    echo Portable launch failed.
    pause
    exit /b 1
)

endlocal
