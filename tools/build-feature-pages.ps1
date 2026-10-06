#Requires -Version 7.3
<#
  build-feature-pages.ps1 -- regenerate every page the feature registry owns:
    docs\wiki\Home.md, Features.md, Feature-Index.md, Quick-Help.md,
    the dl:registry blocks in README.md and docs\AI-USAGE.md,
    features\generated\manifest.json
  from features\** + the live engine (--help, rules --json) + the plugin sources.

  -Check      write nothing; exit 1 with a diff head per output that would change
              (the publish gate: tools\publish-wiki.ps1, build\pack-lint-release.ps1,
              tools\publish-release.ps1 and the battery guard call this)
  -OutDir     render into another directory (byte comparison by the guard)
  -Normalise  first rewrite every entry/data file into canonical form
  -Repo       repository root (default: the parent of this script's folder)
  Outputs are written only when the bytes differ, so mtimes stay honest for
  run_manual_freshness_guard.ps1. No date is written anywhere.
  Exit codes: 0 = nothing changed or everything written; 1 = -Check found a
  difference, or the generator failed.
#>
[CmdletBinding()]
param([switch]$Check, [string]$OutDir = '', [switch]$Normalise, [string]$Repo = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
  Import-Module (Join-Path $PSScriptRoot 'FeatureRegistry.psm1') -Force
  $paths = Get-RegistryPaths -Repo $Repo
  if ($Normalise) {
    $n = Invoke-RegistryNormalise -Paths $paths
    Write-Host "normalised $($n.Count) file(s)" -ForegroundColor Cyan
    foreach ($f in $n) { Write-Host "  $f" }
  }
  $res = Invoke-RegistryGenerate -Paths $paths -Check:$Check -OutDir $OutDir
  if ($Check) {
    if ($res.Changed.Count -eq 0) { Write-Host 'feature pages: current' -ForegroundColor Green; exit 0 }
    Write-Host "feature pages: $($res.Changed.Count) output(s) would change -- run tools\build-feature-pages.ps1 and commit:" -ForegroundColor Red
    foreach ($c in $res.Changed) { Write-Host "  $($c.Path)" -ForegroundColor Red; Write-Host ($c.Diff.TrimEnd() -replace '(?m)^', '    ') -ForegroundColor DarkGray }
    exit 1
  }
  Write-Host "feature pages: wrote $($res.Written.Count) of $($res.Outputs.Count) output(s)" -ForegroundColor Green
  foreach ($w in $res.Written) { Write-Host "  $w" }
  exit 0
} catch {
  Write-Host "feature pages: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
