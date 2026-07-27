#!/usr/bin/env pwsh
# Build the example app's Android APK and stage it into dist/ with release discipline.
#
# Usage:
#   scripts/build-apk.ps1                            # debug build (default)
#   scripts/build-apk.ps1 -Mode release              # release build
#   scripts/build-apk.ps1 -Mode profile
#   scripts/build-apk.ps1 -AllowSameVersion          # re-stage identical build, no version bump
#
# For each build it stages, into dist/:
#   - a stable name    : universal_camera_adapter-<mode>.apk           (overwritten each build)
#   - a versioned copy : universal_camera_adapter-<version>-<mode>.apk (from example/pubspec.yaml)
#   - a .sha256 sidecar for each of the above
#
# The version comes from example/pubspec.yaml's `version:` key (never hand-typed). The script
# REFUSES to overwrite an existing versioned file — that's the signal you forgot to bump the
# version. Pass -AllowSameVersion only to deliberately re-stage the identical already-built APK.
# See .claude/skills/release-packaging/SKILL.md.

param(
    [ValidateSet('debug', 'release', 'profile')]
    [string]$Mode = 'debug',

    [switch]$AllowSameVersion
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Parent $PSScriptRoot
$exampleDir = Join-Path $repoRoot 'example'
$distDir    = Join-Path $repoRoot 'dist'

# --- Read + validate the version from example/pubspec.yaml (anchored at line start) ---
$pubspecPath = Join-Path $exampleDir 'pubspec.yaml'
if (-not (Test-Path $pubspecPath)) { throw "pubspec.yaml not found: $pubspecPath" }

# Match in the current scope (not inside a Where-Object child scope) so $Matches is reliable.
$version = $null
foreach ($line in Get-Content $pubspecPath) {
    if ($line -match '^version:\s*(\S+)') { $version = $Matches[1]; break }
}
if (-not $version) { throw "No top-level 'version:' key in $pubspecPath — add one before building." }
if ($version -notmatch '^\d+\.\d+\.\d+(\+\d+)?$') {
    throw "Version '$version' in $pubspecPath is not a valid semver (expected e.g. 1.0.0 or 1.0.0+1)."
}

New-Item -ItemType Directory -Force -Path $distDir | Out-Null

# --- Build ---
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

# --- Stage: stable name (always overwritten) + versioned copy (guarded) ---
$stable    = Join-Path $distDir "universal_camera_adapter-$Mode.apk"
$versioned = Join-Path $distDir "universal_camera_adapter-$version-$Mode.apk"

if ((Test-Path $versioned) -and -not $AllowSameVersion) {
    throw "Versioned APK already exists: $versioned`nBump example/pubspec.yaml version or pass -AllowSameVersion."
}

Copy-Item $built $stable -Force
Copy-Item $built $versioned -Force

# --- SHA256 sidecars for each staged file ---
foreach ($file in @($stable, $versioned)) {
    $hash = (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower()
    "$hash  $(Split-Path -Leaf $file)" | Out-File -FilePath "$file.sha256" -Encoding utf8
}

$sizeMB = [math]::Round((Get-Item $stable).Length / 1MB, 1)
Write-Host "APK ready ($version, $sizeMB MB):"
Write-Host "  stable    -> $stable"
Write-Host "  versioned -> $versioned"
Write-Host "  sha256    -> $stable.sha256 / $versioned.sha256"
