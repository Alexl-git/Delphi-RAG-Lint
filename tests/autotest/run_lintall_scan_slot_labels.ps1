<#
  run_lintall_scan_slot_labels.ps1 -- PF2 (wave 150) item 3: the lint-all DRAGLINT_PROFILE
  per-file breakdown names each of the five checkers that used to share ONE window labelled
  'NamingChecker.Check' (147 PF: the +100 s there was unit-missing-from-uses, not naming).
   * five separate slot rows: AstChecker.CheckWithHiding, AstChecker.CheckEnumBareReadScoped,
     MissingUsesChecker.Check, EnumOrdinalCastChecker.Check, NamingChecker.Check
   * each row reports the fixture's file count (the window ran once per file)
  The base build (1.49.0-alpha) prints only 'NamingChecker.Check' -> RED. pwsh 7, neutral CWD.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-slotlabels-$PID"
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
  $m = [regex]::Match($err, 'PER-FILE SCAN BREAKDOWN \((\d+) file')
  Check 'the profile prints the per-file breakdown' $m.Success
  $files = if ($m.Success) { [int]$m.Groups[1].Value } else { -1 }
  foreach ($slot in 'AstChecker.CheckWithHiding', 'AstChecker.CheckEnumBareReadScoped', 'MissingUsesChecker.Check',
                    'EnumOrdinalCastChecker.Check', 'NamingChecker.Check') {
    $row = [regex]::Match($err, '(?m)^\s+' + [regex]::Escape($slot) + '\s+[\d.]+ s\s+\((\d+) file')
    # positive-control: the base build has ONE 'NamingChecker.Check' row for the whole window and none of the other four
    Check "slot row '$slot'" $row.Success
    if ($row.Success) { Check "  '$slot' ran once per file" ([int]$row.Groups[1].Value -eq $files) "rows=$($row.Groups[1].Value) files=$files" }
  }
} finally { Pop-Location }
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
