# Usage: .\scripts\build.ps1 [-Mode debug|release] [-Clean]
# Wraps DevEco CLI build, setting DEVECO_SDK_HOME to the HarmonyOS SDK ROOT
# (the parent of the "default" SDK tree), required by hvigor CLI.
param(
  [string]$Mode = "debug",
  [switch]$Clean
)
$ErrorActionPreference = "Stop"
$studio = "C:\Program Files\Huawei\DevEco Studio"
$hvigorw = Join-Path $studio "tools\hvigor\bin\hvigorw.bat"
$env:DEVECO_SDK_HOME = Join-Path $studio "sdk"
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