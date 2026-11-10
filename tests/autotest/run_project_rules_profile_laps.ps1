<#
  run_project_rules_profile_laps.ps1 -- PF2 (wave 150) item 2: the DRAGLINT_PROFILE
  'PROJECT-RULES BREAKDOWN' of lint-all lists EVERY rule of TProjectLintRules.Run that had no
  counter (147 PF: ~31 s of project-rules growth sat in work the breakdown did not list), and
  prints the untimed remainder of Run instead of leaving it to subtraction.
   * one row per lap: the 17 per-rule laps + the referenced-sets prelude + the three rules
     that used to be charged to 'global-only-uses-edge'
   * a '(untimed remainder)' row, >= 0 s
  The base build (1.49.0-alpha) has none of these rows -> RED. pwsh 7, neutral CWD.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-prlaps-$PID"
)
. (Join-Path $PSScriptRoot 'exe-hint.ps1')   # Get-ExeStartFailureHint (GUARD-0XC07B)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$WorkDir = Join-Path $WorkDir ([guid]::NewGuid().ToString('N'))
Push-Location C:\TEMP
try {
  $db = & (Join-Path $PSScriptRoot 'tools\new-missing-uses-fixture.ps1') -Exe $Exe -WorkDir $WorkDir -Fns 2 | Select-Object -Last 1
  if (-not (Test-Path $db)) { $hint = Get-ExeStartFailureHint $LASTEXITCODE; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: no fixture DB" -ForegroundColor Red; exit 2 }
  $errFile = Join-Path $WorkDir 'lint-all.err'
  $env:DRAGLINT_PROFILE = '1'
  try { & $Exe lint-all --db $db --json 2> $errFile | Out-Null } finally { $env:DRAGLINT_PROFILE = $null }
  $err = [IO.File]::ReadAllText($errFile)
  $i = $err.IndexOf('PROJECT-RULES BREAKDOWN')
  Check 'the profile prints the project-rules breakdown' ($i -ge 0)
  $blk = if ($i -ge 0) { $err.Substring($i) } else { '' }
  foreach ($row in '(referenced-id/name sets)', 'duplicate-unit-on-search-path', 'dfm-property-not-declared', 'dependent-project-not-recomp',
                   'enum-ordinal-persisted', 'unused-enum-value', 'unused-global', 'read-never-assigned', 'init-order-hazard',
                   'finalization-after-dependency', 'heavy-initialization', 'global-set-in-init-never-freed', 'datamodule-form-global',
                   'parameter-type-too-wide', 'ref-type rules (F1)', 'dfm-event-handler-missing', 'ancestor-not-in-project',
                   'opaque-to-analysis', 'dfm-password-edit-unmasked', 'uses-movable-to-implementation', 'virtual-never-overridden') {
    # positive-control: none of these rows exists on the base build
    Check "lap row '$row'" ($blk -match ('(?m)^\s+' + [regex]::Escape($row) + '\s+-?[\d.]+ s'))
  }
  $rem = [regex]::Match($blk, '(?m)^\s+\(untimed remainder\)\s+(-?[\d.]+) s')
  Check "'(untimed remainder)' row" $rem.Success
  if ($rem.Success) { Check 'remainder >= 0 (the laps do not overlap the old counters)' ([double]$rem.Groups[1].Value -ge 0) $rem.Groups[1].Value }
} finally { Pop-Location }
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
