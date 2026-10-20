#Requires -Version 7.3
<#
  featuregen-gate.ps1 -- the one place the publish / pack / battery scripts call
  featuregen.exe from. Exit 0 = every generated output is current (and, with -Full,
  the registry check A-E passes); exit 1 = it is not, OR the tool or the engine it
  needs is missing. A missing tool is NEVER a pass: the message names the path.

    pwsh -NoProfile -File tools\featuregen-gate.ps1 [-Repo <root>] [-Full]

  -Repo  repository root (default: the parent of this script's folder)
  -Full  also run "featuregen check --level full" (live surface, checks A-E)

  The exe is the tool's build output, src\tools\featuregen\featuregen.exe (gitignored).
  It is REBUILT here (build\_build_featuregen_local.bat) when missing or older than its
  sources (tools\featuregen-ensure.ps1); a failed build is GATE BROKEN. Or the file named by
  the environment variable FEATUREGEN_EXE (used as is). The engine is <root>\third_party\dll-win64\drag-lint.exe.
  The tool never ships: nothing here, and nothing in build\pack-lint-release.ps1,
  copies it into a payload.
#>
[CmdletBinding()]
param([string]$Repo = (Split-Path -Parent $PSScriptRoot), [switch]$Full)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path -LiteralPath $Repo).Path
. (Join-Path $PSScriptRoot 'featuregen-ensure.ps1')
$engine = Join-Path $Repo 'third_party\dll-win64\drag-lint.exe'
try { $exe = Get-FeatureGenExe -Repo $Repo }
catch {
  Write-Host "feature pages: GATE BROKEN -- $($_.Exception.Message) (build\_build_featuregen_local.bat builds it, or set FEATUREGEN_EXE)" -ForegroundColor Red
  exit 1
}
if (-not (Test-Path -LiteralPath $engine)) {
  Write-Host "feature pages: GATE BROKEN -- engine not found: $engine" -ForegroundColor Red
  exit 1
}
& $exe build --all --check --repo $Repo --engine $engine
if ($LASTEXITCODE -ne 0) {
  Write-Host 'feature pages: output(s) would change -- run featuregen build --all and commit (see the list above)' -ForegroundColor Red
  exit 1
}
if ($Full) {
  & $exe check --level full --repo $Repo --engine $engine
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'feature registry: check --level full failed (see the findings above)' -ForegroundColor Red
    exit 1
  }
}
Write-Host 'feature pages: current' -ForegroundColor Green
exit 0
