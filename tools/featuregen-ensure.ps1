#Requires -Version 7.3
<#
  featuregen-ensure.ps1 -- dot-sourced by featuregen-gate.ps1 and run_feature_registry_guard.ps1.
  Defines Get-FeatureGenExe: returns the path of an up-to-date featuregen.exe or THROWS.

  Rules (never a silent stale run):
    * FEATUREGEN_EXE set  -> that file must exist; its freshness is the caller's choice.
    * otherwise the exe is <Repo>\src\tools\featuregen\featuregen.exe. When it is missing or
      older than the newest *.pas / *.dpr in that folder, it is rebuilt with
      build\_build_featuregen_local.bat (BUILD_EXITCODE=0 and no [dcc] Error required).
    * -NoBuild (used by the positive control) turns the rebuild into the failure itself:
      "featuregen.exe is missing" / "older than its sources".
#>
function Get-FeatureGenExe {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Repo, [switch]$NoBuild)
  if ($env:FEATUREGEN_EXE) {
    if (-not (Test-Path -LiteralPath $env:FEATUREGEN_EXE)) { throw "featuregen.exe not found: $($env:FEATUREGEN_EXE)" }
    return $env:FEATUREGEN_EXE
  }
  $dir = Join-Path $Repo 'src\tools\featuregen'
  $exe = Join-Path $dir 'featuregen.exe'
  $newest = $null
  if (Test-Path -LiteralPath $dir) {
    $newest = Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -in '.pas', '.dpr' } |
      Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  }
  $reason = $null
  if (-not (Test-Path -LiteralPath $exe)) { $reason = "featuregen.exe is missing: $exe" }
  elseif ($newest -and ((Get-Item -LiteralPath $exe).LastWriteTimeUtc -lt $newest.LastWriteTimeUtc)) {
    $reason = "featuregen.exe is older than its sources ($($newest.Name)): $exe"
  }
  if (-not $reason) { return $exe }
  if ($NoBuild) { throw $reason }
  $bat = Join-Path $Repo 'build\_build_featuregen_local.bat'
  if (-not (Test-Path -LiteralPath $bat)) { throw "$reason; build script missing: $bat" }
  $log = Join-Path $env:TEMP "featuregen-build-$PID-$([guid]::NewGuid().ToString('N')).log"
  Write-Host "featuregen: $reason -- rebuilding" -ForegroundColor Yellow
  Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $log + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
  $bl = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
  if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error ')) { throw "$reason; the rebuild FAILED (log: $log)" }
  if (-not (Test-Path -LiteralPath $exe)) { throw "$reason; the rebuild produced no exe" }
  [IO.File]::Delete($log)
  return $exe
}
