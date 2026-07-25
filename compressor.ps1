# compress_for_discord.ps1
# Szhimaet video do zadannogo razmera (po umolchaniyu 10 MB) dlya otpravki v Discord
# Ispolzovanie:
#   .\compressor.ps1 -InputFile "video.mp4"
#     -> saves as "video (Reencoded).mp4" in the same folder
#   .\compressor.ps1 -InputFile "video.mp4" -OutputFile "result.mp4" -TargetMB 10
#   .\compressor.ps1 -InputFile "video.mp4" -TargetMB 10 -FPS 30
#     -> also caps the frame rate at 30 fps (omit -FPS to keep original)

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputFile,

    [string]$OutputFile,

    [double]$TargetMB = 10,

    [double]$FPS = 0
)

# Strip stray surrounding quotes in case they ended up in the path
$InputFile = $InputFile.Trim('"')
if ($OutputFile) { $OutputFile = $OutputFile.Trim('"') }

function Fail {
    Read-Host "Press Enter to close this window"
    exit 1
}

# If -OutputFile is not given, save next to the input file with "(Reencoded)"
# added to the filename, keeping the same extension.
if (-not $OutputFile) {
    $inputDir = Split-Path $InputFile -Parent
    $inputName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $inputExt = [System.IO.Path]::GetExtension($InputFile)
    if (-not $inputExt) { $inputExt = ".mp4" }
    $OutputFile = Join-Path $inputDir "$inputName (Reencoded)$inputExt"
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "Error: ffmpeg not found in PATH." -ForegroundColor Red
    Write-Host "Download: https://www.gyan.dev/ffmpeg/builds/ (release essentials build)"
    Write-Host "Unpack and add the 'bin' folder to your PATH environment variable."
    Fail
}

# ffprobe usually sits next to ffmpeg.exe. Try PATH first, then fall back
# to looking in the same folder as ffmpeg.exe.
$ffprobeCmd = "ffprobe"
if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    $ffmpegPath = (Get-Command ffmpeg).Source
    $ffmpegDir = Split-Path $ffmpegPath -Parent
    $candidate = Join-Path $ffmpegDir "ffprobe.exe"
    if (Test-Path $candidate) {
        $ffprobeCmd = $candidate
    } else {
        Write-Host "Error: ffprobe.exe not found (checked PATH and $ffmpegDir)." -ForegroundColor Red
        Write-Host "ffmpeg and ffprobe normally ship together in the same 'bin' folder of the download."
        Write-Host "Re-download the full build from https://www.gyan.dev/ffmpeg/builds/ and make sure ffprobe.exe is in that folder."
        Fail
    }
}

if (-not (Test-Path $InputFile)) {
    Write-Host "Error: file '$InputFile' not found" -ForegroundColor Red
    Fail
}

$durationStr = & $ffprobeCmd -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$InputFile"
$duration = [double]$durationStr

if ($duration -le 0) {
    Write-Host "Error: could not determine video duration" -ForegroundColor Red
    Fail
}

$resolutionStr = & $ffprobeCmd -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$InputFile"
$origWidth = 0
$origHeight = 0
if ($resolutionStr -match "^(\d+)x(\d+)$") {
    $origWidth = [int]$matches[1]
    $origHeight = [int]$matches[2]
}

$targetKbits = $TargetMB * 8000 * 0.90
$totalBitrate = [math]::Floor($targetKbits / $duration)

$audioBitrate = 96
if ($totalBitrate -lt 200) {
    $audioBitrate = 64
}

$videoBitrate = $totalBitrate - $audioBitrate

if ($videoBitrate -le 0) {
    Write-Host "Error: video too long for target size ($TargetMB MB)." -ForegroundColor Red
    Write-Host "Duration: $([math]::Round($duration,1)) sec. Increase target size or trim the video."
    Fail
}

# Pick a target height based on how little bitrate we have to work with.
# Low bitrate + high resolution = blocky mess, so downscale in that case.
$targetHeight = $origHeight
if ($origHeight -gt 0) {
    if ($videoBitrate -lt 800 -and $origHeight -gt 480) {
        $targetHeight = 480
    } elseif ($videoBitrate -lt 1500 -and $origHeight -gt 720) {
        $targetHeight = 720
    } elseif ($videoBitrate -lt 3000 -and $origHeight -gt 1080) {
        $targetHeight = 1080
    }
}

$scaleFilter = $null
if ($targetHeight -gt 0 -and $targetHeight -lt $origHeight) {
    # -2 keeps width divisible by 2 (required by libx264) while preserving aspect ratio
    $scaleFilter = "scale=-2:$targetHeight"
}

# Combine scale and fps into a single -vf filter chain if either is set
$vfParts = @()
if ($scaleFilter) { $vfParts += $scaleFilter }
if ($FPS -gt 0) { $vfParts += "fps=$FPS" }
$vfFilter = $null
if ($vfParts.Count -gt 0) { $vfFilter = ($vfParts -join ",") }

$targetBytes = $TargetMB * 1MB
$maxAttempts = 3
$attempt = 1
$success = $false

while ($attempt -le $maxAttempts -and -not $success) {
    Write-Host "==================================="
    Write-Host "Attempt $attempt of $maxAttempts"
    Write-Host "Video duration: $([math]::Round($duration,1)) sec"
    Write-Host "Target size: $TargetMB MB"
    Write-Host "Video bitrate: $videoBitrate kbps"
    Write-Host "Audio bitrate: $audioBitrate kbps"
    if ($scaleFilter) {
        Write-Host "Downscaling to: $targetHeight p (source was ${origWidth}x${origHeight})"
    }
    if ($FPS -gt 0) {
        Write-Host "Frame rate: $FPS fps"
    }
    Write-Host "==================================="

    $pass1Args = @("-y", "-i", "$InputFile", "-c:v", "libx264", "-b:v", "${videoBitrate}k", "-pass", "1", "-an", "-f", "mp4")
    $pass2Args = @("-y", "-i", "$InputFile", "-c:v", "libx264", "-b:v", "${videoBitrate}k", "-pass", "2", "-c:a", "aac", "-b:a", "${audioBitrate}k", "-movflags", "+faststart")
    if ($vfFilter) {
        $pass1Args += @("-vf", $vfFilter)
        $pass2Args += @("-vf", $vfFilter)
    }
    $pass1Args += "NUL"
    $pass2Args += "$OutputFile"

    & ffmpeg @pass1Args
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: ffmpeg pass 1 failed (exit code $LASTEXITCODE)" -ForegroundColor Red
        Fail
    }

    & ffmpeg @pass2Args
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: ffmpeg pass 2 failed (exit code $LASTEXITCODE)" -ForegroundColor Red
        Fail
    }

    Remove-Item -Path "ffmpeg2pass-0.log" -ErrorAction SilentlyContinue
    Remove-Item -Path "ffmpeg2pass-0.log.mbtree" -ErrorAction SilentlyContinue

    if (-not (Test-Path $OutputFile)) {
        Write-Host "Something went wrong - output file was not created." -ForegroundColor Red
        Fail
    }

    $actualBytes = (Get-Item $OutputFile).Length
    if ($actualBytes -le $targetBytes) {
        $success = $true
    } else {
        $overshootRatio = $actualBytes / $targetBytes
        Write-Host "Output came out $([math]::Round($actualBytes / 1MB, 2)) MB - over the $TargetMB MB limit. Retrying with a lower bitrate..." -ForegroundColor Yellow
        # Shrink bitrate proportionally to how much we overshot, plus a small extra margin
        $videoBitrate = [math]::Floor($videoBitrate / ($overshootRatio * 1.05))
        if ($videoBitrate -le 0) {
            Write-Host "Error: cannot fit this video under $TargetMB MB even at minimal bitrate." -ForegroundColor Red
            Fail
        }
        $attempt++
    }
}

if (-not $success) {
    Write-Host "Error: could not get under $TargetMB MB after $maxAttempts attempts." -ForegroundColor Red
    Write-Host "Consider trimming the video or increasing the target size."
    Fail
}

$finalSizeMB = [math]::Round((Get-Item $OutputFile).Length / 1MB, 2)
Write-Host "==================================="
Write-Host "Done! Output file: $OutputFile" -ForegroundColor Green
Write-Host "Size: ~$finalSizeMB MB (limit was $TargetMB MB)"
Write-Host "==================================="
Read-Host "Press Enter to close this window"
