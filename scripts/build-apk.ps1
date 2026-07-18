#!/usr/bin/env pwsh
# Build the example app's Android APK and copy it into dist/ for fast access.
#
# Usage:
#   scripts/build-apk.ps1                 # debug build (default)
#   scripts/build-apk.ps1 -Mode release   # release build
#   scripts/build-apk.ps1 -Mode profile
#
# Output: dist/universal_camera_adapter-<mode>.apk (overwrites the previous one
# for the same mode, so the path is stable/predictable).

param(
    [ValidateSet('debug', 'release', 'profile')]
    [string]$Mode = 'debug'
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Parent $PSScriptRoot
$exampleDir = Join-Path $repoRoot 'example'
$distDir    = Join-Path $repoRoot 'dist'

New-Item -ItemType Directory -Force -Path $distDir | Out-Null

Push-Location $exampleDir
try {
    flutter build apk "--$Mode"
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk --$Mode failed (exit $LASTEXITCODE)" }
}
finally {
    Pop-Location
}

$built = Join-Path $exampleDir "build\app\outputs\flutter-apk\app-$Mode.apk"
if (-not (Test-Path $built)) { throw "Expected APK not found: $built" }

$dest = Join-Path $distDir "universal_camera_adapter-$Mode.apk"
Copy-Item $built $dest -Force

$sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
Write-Host "APK ready -> $dest ($sizeMB MB)"
