@echo off
REM Drop a video file onto this .bat to compress it
REM Usage: just drag-and-drop a video file onto this .bat icon in Explorer,
REM then type your target size (and optionally frame rate) when asked.

if "%~1"=="" (
    echo Drag and drop a video file onto this .bat file to compress it.
    pause
    exit /b 1
)

set /p TargetMB="Target size in MB (press Enter for 10): "
if "%TargetMB%"=="" set TargetMB=10

set /p FPS="Frame rate / FPS (press Enter to keep original): "

if "%FPS%"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compressor.ps1" -InputFile "%~1" -TargetMB %TargetMB%
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compressor.ps1" -InputFile "%~1" -TargetMB %TargetMB% -FPS %FPS%
)
pause
