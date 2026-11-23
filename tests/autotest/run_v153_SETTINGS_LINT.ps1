<#
  run_v153_SETTINGS_LINT.ps1 -- 1.53.0 SETTINGS-CORE lint read side: `lint.config`, `lint.profile`
  and `taint.envSource` from <anchor>\_D-RAG\drag-lint-project.json reach `lint <file>`
  (spec docs\superpowers\specs\2026-11-20-settings-store-design.md section 7, criteria L1-L5).

  Fixture tests\autotest\fixtures\v153-SETTINGS\proj is copied to a temp folder per run:
    uMagic.pas  one magic literal (rule magic-literal)
    uEnv.pas    GetEnvironmentVariable('MY_CACHE') -> DeleteFile (taint-path-traversal @40,
                the positive control for L3) and ParamStr -> CreateProcess (taint-command-injection @20,
                which no settings key may switch off)
    drag-lint-lint.json  enables magic-literal (sits beside the .dproj: the discovery default)
    alt-lint.json        disables it; prof-lint.json  enables it, with profiles quiet / loud
  The library types come from tests\lint-project\taint-lib\lib (indexed into a throwaway DB).

  Against an engine without the read side L1-L3 fail (RED); L4/L5 pass there by design (no-op guarantee).

  Usage: pwsh -File tests\autotest\run_v153_SETTINGS_LINT.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }
$Exe = (Resolve-Path $Exe).Path

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v153-settingslint-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$Proj = Join-Path $Work 'proj'
[void](New-Item -ItemType Directory -Force $Work)
Copy-Item (Join-Path $Root 'tests\autotest\fixtures\v153-SETTINGS\proj') $Proj -Recurse
[void](New-Item -ItemType Directory -Force (Join-Path $Proj '_D-RAG'))
$Dproj = Join-Path $Proj 'App.dproj'
$Db = Join-Path $Proj '_D-RAG\fx.sqlite'
$Lib = Join-Path $Work 'lib.sqlite'
$ProjFile = Join-Path $Proj '_D-RAG\drag-lint-project.json'
$UMagic = Join-Path $Proj 'uMagic.pas'
$UEnv = Join-Path $Proj 'uEnv.pas'

$Pass = 0; $Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
function Quiet([scriptblock]$B) { & { $ErrorActionPreference = 'Continue'; & $B } }
# settings verb, merged output + exit code
function Settings([string[]]$A) {
  $Out = Quiet { & { $ErrorActionPreference = 'Continue'; & $Exe settings @A --project $Dproj 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" } }
  return $LASTEXITCODE
}
# Sorted "rule:line" list of one unit's findings; stderr goes to $script:LastErr.
function Findings([string]$Unit, [string[]]$Extra = @()) {
  $ErrFile = Join-Path $Work 'err.txt'
  [IO.File]::WriteAllText($ErrFile, '')
  $Out = Quiet { & { $ErrorActionPreference = 'Continue'; & $Exe lint $Unit --db $Db --library-db $Lib --json --quiet @Extra 2>$ErrFile } }
  $script:LastErr = [IO.File]::ReadAllText($ErrFile)
  $Txt = ($Out -join "`n"); $B = $Txt.IndexOf('[')
  if ($B -lt 0) { return ,@() }
  $All = @(($Txt.Substring($B) | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ })
  return ,@($All | ForEach-Object { "$($_.rule):$($_.start_line)" } | Sort-Object)
}
function Has($List, [string]$Rule) { return (@($List | Where-Object { $_ -like "$Rule`:*" }).Count -gt 0) }
function ResetSettings { if (Test-Path $ProjFile) { [IO.File]::Delete($ProjFile) } }

try {
  Quiet { & { $ErrorActionPreference = 'Continue'; & $Exe index $Proj --db $Db --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null }
  Quiet { & { $ErrorActionPreference = 'Continue'; & $Exe index (Join-Path $Root 'tests\lint-project\taint-lib\lib') --db $Lib --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null }

  # baseline, taken before any settings file exists (L4 reference + positive controls)
  $BaseMagic = Findings $UMagic
  $BaseEnv = Findings $UEnv
  Check 'baseline POSITIVE CONTROL: magic-literal fires in uMagic (drag-lint-lint.json beside the .dproj)' (Has $BaseMagic 'magic-literal') ($BaseMagic -join ' ')
  Check 'baseline POSITIVE CONTROL: taint-path-traversal fires in uEnv' (Has $BaseEnv 'taint-path-traversal') ($BaseEnv -join ' ')
  Check 'baseline POSITIVE CONTROL: taint-command-injection fires in uEnv' (Has $BaseEnv 'taint-command-injection') ($BaseEnv -join ' ')

  # L1 lint.config beats the discovered config; --config beats lint.config
  [void](Settings @('set', 'lint.config', 'alt-lint.json'))
  $F = Findings $UMagic
  Check 'L1 lint.config alt-lint.json: no magic-literal despite drag-lint-lint.json beside the .dproj' (-not (Has $F 'magic-literal')) ($F -join ' ')
  $F = Findings $UMagic @('--config', (Join-Path $Proj 'drag-lint-lint.json'))
  Check 'L1 POSITIVE CONTROL: --config wins over lint.config (magic-literal fires)' (Has $F 'magic-literal') ($F -join ' ')

  # L2 lint.profile; --profile wins
  [void](Settings @('set', 'lint.config', 'prof-lint.json'))
  $F = Findings $UMagic
  Check 'L2 prof-lint.json without a profile: magic-literal fires' (Has $F 'magic-literal') ($F -join ' ')
  [void](Settings @('set', 'lint.profile', 'quiet'))
  $F = Findings $UMagic
  Check 'L2 lint.profile quiet: no magic-literal' (-not (Has $F 'magic-literal')) ($F -join ' ')
  $F = Findings $UMagic @('--profile', 'loud')
  Check 'L2 POSITIVE CONTROL: --profile loud wins over lint.profile' (Has $F 'magic-literal') ($F -join ' ')
  ResetSettings

  # L3 taint.envSource
  [void](Settings @('set', 'taint.envSource', 'false'))
  $F = Findings $UEnv
  Check 'L3 taint.envSource false: the GetEnvironmentVariable finding is gone' (-not (Has $F 'taint-path-traversal')) ($F -join ' ')
  Check 'L3 ParamStr -> CreateProcess still fires' (Has $F 'taint-command-injection') ($F -join ' ')
  [void](Settings @('unset', 'taint.envSource'))
  $F = Findings $UEnv
  Check 'L3 POSITIVE CONTROL: unset -> the finding is back' (Has $F 'taint-path-traversal') ($F -join ' ')
  ResetSettings

  # L4 no settings files: identical to the baseline (and to a run on the same inputs after a set/unset round trip)
  $M = Findings $UMagic; $E = Findings $UEnv
  Check 'L4 no settings file: uMagic findings equal the baseline' (($M -join '|') -eq ($BaseMagic -join '|')) ''
  Check 'L4 no settings file: uEnv findings equal the baseline' (($E -join '|') -eq ($BaseEnv -join '|')) ''

  # L5 malformed settings file: one warning line naming it, findings as L4
  [IO.File]::WriteAllText($ProjFile, "{`r`n", [Text.Encoding]::ASCII)
  $M = Findings $UMagic
  $Warn = @($script:LastErr -split "`r?`n" | Where-Object { $_ -match 'drag-lint-project\.json' })
  Check 'L5 malformed file: exactly one stderr line names it' ($Warn.Count -eq 1) "lines=$($Warn.Count) err=[$($script:LastErr)]"
  Check 'L5 malformed file: findings equal the baseline' (($M -join '|') -eq ($BaseMagic -join '|')) ($M -join ' ')
  ResetSettings
}
catch { $Fail++; Write-Host "  FAIL  exception: $($_.Exception.Message)" }
finally { try { [IO.Directory]::Delete($Work, $true) } catch { } }

Write-Host "$Pass passed, $Fail failed"
if ($Fail -gt 0) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
