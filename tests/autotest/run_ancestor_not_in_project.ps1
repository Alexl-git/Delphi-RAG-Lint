# Guard: ancestor-not-in-project (1.42 lane enum, project-wide, ERROR; owner ruling 2026-11-03,
# docs\INBOX-2026-11-03-converter-to-engine-ancestor-not-in-project-rule.md).
#
# Fixture tests\lint-project\ancestor-not-in-project:
#   lib\Vcl.Forms.pas   stand-in platform library: TForm, TFrame, TDataModule
#   proj\uBase.pas      TBaseForm = class(TForm), root of uBase.dfm     -> silent (library ancestor exempt)
#   proj\uChild.pas     TChildForm = class(TBaseForm), inherited dfm    -> silent (ancestor IS in the project)
#   proj\uOrphan.pas:9  TOrphanForm = class(TMissingBaseForm)           -> FIRES (bare ancestor, unit hint uMissingBase)
#   proj\uDM.pas:9      TOrphanDM = class(uMissingDM.TMissingBaseDM)    -> FIRES (qualified ancestor, unit uMissingDM)
#   proj\uPlain.pas     TPlainThing = class(TMissingHelperBase), no dfm -> silent (not a form / frame / data module)
#   proj\uFrame.pas     TMyFrame = class(TFrame) root of uFrame.dfm     -> silent;
#                       THelperOrphan = class(TMissingOther) in the same unit, NOT the dfm root -> silent
# The library goes in as a SECOND --db: lint-all takes its library store from the db list,
# not from --library-db.
# Positive control: an engine without the rule reports 0 findings and fails the "fires" checks.
# Usage: pwsh -File tests/autotest/run_ancestor_not_in_project.ps1 [-Exe <path>]
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-anip-$PID")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok) {
  if ($Ok) { Write-Host "  [PASS] $Name" -ForegroundColor Green } else { Write-Host "  [FAIL] $Name" -ForegroundColor Red; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$src = Join-Path $PSScriptRoot '..\lint-project\ancestor-not-in-project'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  foreach ($d in 'proj', 'lib') {
    New-Item -ItemType Directory -Force (Join-Path $WorkDir $d) | Out-Null
    Get-ChildItem (Join-Path $src $d) -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $WorkDir $d) -Force }
  }
  $db  = Join-Path $WorkDir 'fx.sqlite'
  $lib = Join-Path $WorkDir 'lib.sqlite'
  & $Exe index (Join-Path $WorkDir 'lib') --db $lib 2>&1 | Out-Null
  Check 'library index exits 0' ($LASTEXITCODE -eq 0)
  & $Exe index (Join-Path $WorkDir 'proj') --db $db 2>&1 | Out-Null
  Check 'project index exits 0' ($LASTEXITCODE -eq 0)
  $raw = & $Exe lint-all --db $db --db $lib --rule ancestor-not-in-project --format json 2>$null
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $f = @(); if ($b -ge 0) { try { $f = @($txt.Substring($b) | ConvertFrom-Json) } catch { $f = @() } }
  $f = @($f | Where-Object { $_.rule -eq 'ancestor-not-in-project' })
  $f | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) -ForegroundColor DarkGray }
  function At([string]$Leaf) { @($f | Where-Object { $_.file_path -match "\\$Leaf$" }) }
  Check 'positive: TOrphanForm (bare missing ancestor) fires at uOrphan.pas:9' ((At 'uOrphan\.pas' | Where-Object { [int]$_.start_line -eq 9 }).Count -eq 1)
  Check 'positive: TOrphanDM (qualified missing ancestor) fires at uDM.pas:9' ((At 'uDM\.pas' | Where-Object { [int]$_.start_line -eq 9 }).Count -eq 1)
  Check 'negative: library ancestor TForm exempt (uBase.pas)' ((At 'uBase\.pas').Count -eq 0)
  Check 'negative: ancestor declared in the project (uChild.pas)' ((At 'uChild\.pas').Count -eq 0)
  Check 'negative: class without a .dfm (uPlain.pas)' ((At 'uPlain\.pas').Count -eq 0)
  Check 'negative: non-root class beside a dfm root (uFrame.pas)' ((At 'uFrame\.pas').Count -eq 0)
  Check 'exactly two findings' ($f.Count -eq 2)
  Check 'severity is error' (($f.Count -gt 0) -and (@($f | Where-Object { $_.severity -ne 'error' }).Count -eq 0))
  Check 'message names ancestor and unit hint (uOrphan)' ((At 'uOrphan\.pas' | Where-Object { $_.message -match 'TMissingBaseForm' -and $_.message -match 'uMissingBase' }).Count -eq 1)
  Check 'message names the qualifying unit (uDM)' ((At 'uDM\.pas' | Where-Object { $_.message -match 'TMissingBaseDM' -and $_.message -match 'uMissingDM' }).Count -eq 1)
} finally { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }