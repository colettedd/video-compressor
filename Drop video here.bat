@echo off
REM Drop a video file onto this .bat to compress it for Discord (default: 10 MB limit)
REM Usage: just drag-and-drop a video file onto this .bat icon in Explorer

if "%~1"=="" (
    echo Drag and drop a video file onto this .bat file to compress it.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compress_for_discord.ps1" -InputFile "%~1" -TargetMB 10
pause
