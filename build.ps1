<#
    Retro Pi 2.0 - image builder (Windows entrypoint)

    Produces a flashable .img for a Raspberry Pi 4 / 400 that boots
    straight into Kodi, with RetroArch behind it for games.

    Usage:
        .\build.ps1              # build the image
        .\build.ps1 -Clean       # discard the workspace and start fresh
#>
[CmdletBinding()]
param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$Project   = $PSScriptRoot
$SrcDir    = Join-Path $Project 'src'

# Everything big lives on D:. The base image is ~3 GB, the workspace
# another ~6 GB, and C: is nearly full with Docker's own VM disk on it.
$BuildRoot = 'D:\RetroPi2-build'
$Workspace = Join-Path $BuildRoot 'workspace'
$ImageDir  = Join-Path $BuildRoot 'image'
$DistDir   = Join-Path $BuildRoot 'dist'

$BaseName = '2026-06-18-raspios-trixie-arm64-lite'
$BaseUrl  = "https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-06-19/$BaseName.img.xz"
$BaseXz   = Join-Path $ImageDir "$BaseName.img.xz"
$BaseImg  = Join-Path $ImageDir "$BaseName.img"

$DistVersionTag = '0.2.0'   # keep in step with DIST_VERSION in src/config

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!!  $m"   -ForegroundColor Yellow }

# ---- preflight ---------------------------------------------------
Step 'Checking Docker'
try { docker info --format '{{.ServerVersion}}' | Out-Null }
catch { throw 'Docker is not running. Start Docker Desktop and try again.' }

New-Item -ItemType Directory -Force -Path $BuildRoot,$Workspace,$ImageDir,$DistDir | Out-Null

if ($Clean) {
    Step 'Clearing workspace'
    Remove-Item -Recurse -Force (Join-Path $Workspace '*') -ErrorAction SilentlyContinue
}

# ---- preflight: package names ------------------------------------
# A bad package name otherwise fails ~20 minutes into the build, inside
# the emulated chroot. This catches it in about 30 seconds.
Step 'Checking package names against the Debian index'
bash "$Project/scripts/check-packages.sh"
if ($LASTEXITCODE -ne 0) {
    throw 'One or more packages do not exist. Fix src/modules/retropi2/{config,start_chroot_script} and re-run.'
}

# ---- base image --------------------------------------------------
# CustomPiOS unpacks the .xz itself (with 7za), so we only need to make
# sure the compressed file is there.
if (-not (Test-Path $BaseXz)) {
    Step 'Downloading Raspberry Pi OS Trixie arm64 Lite (~525 MB, one time)'
    curl.exe -L --fail --progress-bar -o $BaseXz $BaseUrl
    if ($LASTEXITCODE -ne 0) { throw 'Base image download failed.' }
}
Step "Base image ready: $BaseName.img.xz"

# ---- the image ---------------------------------------------------
Step 'Building the image with CustomPiOS (this takes a while)'
# CustomPiOS sets DIST_PATH=/distro and reads $DIST_PATH/config, /modules,
# /image and /workspace from it - so /distro is the project's src
# directory, NOT the repo root.
docker run --rm --privileged `
    -v "${SrcDir}:/distro" `
    -v "${Workspace}:/distro/workspace" `
    -v "${ImageDir}:/distro/image" `
    ghcr.io/guysoft/custompios:devel build
$buildExit = $LASTEXITCODE

# CustomPiOS finishes with a `chmod 777` across the workspace, which
# fails on a Windows bind mount even when the image was written fine.
# So trust the artifact, not the exit code - but say so.
if ($buildExit -ne 0) {
    Warn "Builder exited $buildExit; checking whether the image was still produced..."
}

# ---- collect -----------------------------------------------------
$built = Get-ChildItem -Path $Workspace -Filter '*.img' -Recurse -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like "*$DistVersionTag*" } |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($null -eq $built) {
    throw "Image build failed: no output .img in $Workspace (builder exit $buildExit)."
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$out   = Join-Path $DistDir "RetroPi2-$stamp.img"
Copy-Item $built.FullName $out -Force

Step 'Done'
Write-Host "  Image:  $out"
Write-Host ("  Size:   {0:N1} GB" -f ($built.Length / 1GB))
Write-Host ""
Write-Host "  Flash it with Raspberry Pi Imager or balenaEtcher." -ForegroundColor Green
Write-Host "  Use a spare SD card if you can - flashing erases everything on it." -ForegroundColor Green
