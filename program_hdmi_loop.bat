@echo off
setlocal
set "CHECK_PATHS="
set "PROBE="
set "NO_PAUSE="
:args
if "%~1"=="" goto run
if /i "%~1"=="--check" (
    set "CHECK_PATHS=-CheckPaths"
) else if /i "%~1"=="--no-pause" (
    set "NO_PAUSE=1"
) else if /i "%~1"=="--probe" (
    set "PROBE=-Probe"
) else (
    echo Usage: program_hdmi_loop.bat [--check] [--probe] [--no-pause]
    exit /b 2
)
shift /1
goto args
:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0program_hdmi_loop.ps1" %CHECK_PATHS% %PROBE%
set "RC=%ERRORLEVEL%"
if not defined NO_PAUSE pause
exit /b %RC%
