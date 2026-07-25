# !!!VIBECODED!!!

# Video Compressor

A PowerShell script that compresses a video to fit under a target file size
(10 MB by default, matching Discord's free upload limit) using ffmpeg
two-pass encoding.

## Features

- Targets an exact file size (e.g. "make this fit under 10 MB")
- Automatically retries with a lower bitrate if the first attempt comes out
  slightly over the limit — output is guaranteed to fit
- Automatically downscales resolution (e.g. 1080p → 720p) when the bitrate
  budget is too low for the original resolution, to avoid a blocky mess
- Drag-and-drop support via the included `.bat` wrapper, which prompts for
  target size and (optionally) frame rate
- Optional frame rate cap (e.g. force 30 fps) via `-FPS`
- Saves next to the original file by default, with `(Reencoded)` added to
  the filename

## Requirements

- Windows with PowerShell
- [ffmpeg](https://www.gyan.dev/ffmpeg/builds/) (the "release essentials"
  build works fine) — both `ffmpeg.exe` and `ffprobe.exe` need to be
  available, either in your `PATH` or in the same folder together

## Usage

### Option 1: Drag and drop (easiest)

Drag a video file onto `Drop video here.bat`. It will ask for a target
size (press Enter for the 10 MB default) and a frame rate (press Enter to
keep the original), then save the result next to the original file.

### Option 2: PowerShell

```powershell
# Default: 10 MB, saves as "video (Reencoded).mp4" next to the original
.\compressor.ps1 -InputFile "video.mp4"

# Custom size limit
.\compressor.ps1 -InputFile "video.mp4" -TargetMB 50

# Custom output path
.\compressor.ps1 -InputFile "video.mp4" -OutputFile "result.mp4" -TargetMB 10

# Cap the frame rate (e.g. force 30 fps)
.\compressor.ps1 -InputFile "video.mp4" -TargetMB 10 -FPS 30
```

If PowerShell blocks the script from running, allow it for the current
session first:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## How it works

1. Reads the video's duration and resolution via `ffprobe`
2. Calculates the video bitrate needed to hit the target size, minus a
   safety margin
3. Downscales resolution automatically if the bitrate budget is too low
   for the source resolution
4. Encodes with `ffmpeg` using two-pass H.264 encoding for accurate sizing
5. Checks the actual output size; if it's still over the limit, lowers the
   bitrate and re-encodes (up to 3 attempts)
