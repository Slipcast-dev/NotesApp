@echo off
setlocal

set "APP_DIR=%~dp0"
set "APP_EXE=%APP_DIR%NotesApp.exe"

if not exist "%APP_EXE%" (
    echo NotesApp.exe not found in:
    echo %APP_DIR%
    echo.
    echo Run this launcher from the portable package folder.
    pause
    exit /b 1
)

pushd "%APP_DIR%"
start "" "%APP_EXE%"
popd

endlocal
