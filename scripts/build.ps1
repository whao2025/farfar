# Usage: .\scripts\build.ps1 [-Mode debug|release] [-Clean] [-DevEcoHome <path>]
# Wraps DevEco CLI build, setting DEVECO_SDK_HOME to the HarmonyOS SDK ROOT
# (the parent of the "default" SDK tree), required by hvigor CLI.
# Auto-detects DevEco Studio installation: API 26 needs DevEco Studio 26 (Hvigor 6.26.8 + SDK 26.0.0).
param(
  [string]$Mode = "debug",
  [switch]$Clean,
  [string]$DevEcoHome = ""
)
$ErrorActionPreference = "Stop"

$candidates = @()
if ($DevEcoHome) { $candidates += $DevEcoHome }
if ($env:DEVECO_HOME) { $candidates += $env:DEVECO_HOME }
$candidates += @(
  "D:\DevEcoStudio26",
  "C:\Program Files\Huawei\DevEco Studio"
)

$studio = $null
foreach ($c in $candidates) {
  if ($c -and (Test-Path (Join-Path $c "tools\hvigor\bin\hvigorw.bat"))) { $studio = $c; break }
}
if (-not $studio) {
  throw "DevEco Studio not found. Tried: $($candidates -join ', ')"
}

$hvigorw = Join-Path $studio "tools\hvigor\bin\hvigorw.bat"
$env:DEVECO_SDK_HOME = Join-Path $studio "sdk"
$sdkPkg = Join-Path $env:DEVECO_SDK_HOME "default\sdk-pkg.json"
$sdkInfo = "unknown"
if (Test-Path $sdkPkg) {
  try { $sdkInfo = (Get-Content $sdkPkg -Raw | ConvertFrom-Json).data.displayName } catch { }
}
Write-Host "DevEco: $studio (SDK: $sdkInfo)" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
  if ($Clean) {
    & $hvigorw clean --no-daemon
  }
  & $hvigorw --mode module -p product=default -p buildMode=$Mode --no-daemon assembleHap
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}
Write-Host "BUILD $Mode SUCCESS" -ForegroundColor Green
