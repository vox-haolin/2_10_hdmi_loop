@echo off
setlocal
set "CHECK_PATHS="
set "NO_PAUSE="
:args
if "%~1"=="" goto run
if /i "%~1"=="--check" (
    set "CHECK_PATHS=-CheckPaths"
) else if /i "%~1"=="--no-pause" (
    set "NO_PAUSE=1"
) else (
    echo Usage: build_hdmi_loop.bat [--check] [--no-pause]
    exit /b 2
)
shift /1
goto args
:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_contest.ps1" %CHECK_PATHS%
set "RC=%ERRORLEVEL%"
if not defined NO_PAUSE pause
exit /b %RC%
