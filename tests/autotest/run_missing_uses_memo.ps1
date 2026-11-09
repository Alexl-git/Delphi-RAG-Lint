<#
  run_missing_uses_memo.ps1 -- PF2 (wave 150): lint-all shares ONE store-wide memo of the
  unit-missing-from-uses bound-ref check (symbol id -> declaring unit) across every file
  (TMissingUsesMemo), instead of re-reading the store per file (147 PF: 51.6 -> 284.8 s on
  CLIENT, cause ffc8cf878).

  Fixture: tests\autotest\tools\new-missing-uses-fixture.ps1 (60 units; 49 user units bind
  the same decl-unit symbols; 10 of them lose one uses entry from the text after the index).
   * findings: exactly the blanked units, each naming the unit taken out (Fns+4 names each)
   * DRAGLINT_PROFILE prints 'missing-uses memo: N bound-ref lookup(s), M store read(s)'
   * M <= the distinct bound symbol ids of the store (one read per symbol per RUN), and
     M < N (positive control: a per-file memo reads once per symbol per FILE, M = N)
  The base build (1.49.0-alpha) prints no memo line -> RED. Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-missingmemo-$PID",
  [int]$Fns = 40
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
  $db = & (Join-Path $PSScriptRoot 'tools\new-missing-uses-fixture.ps1') -Exe $Exe -WorkDir $WorkDir -Fns $Fns | Select-Object -Last 1
  if (-not (Test-Path $db)) { $hint = Get-ExeStartFailureHint $LASTEXITCODE; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: no fixture DB" -ForegroundColor Red; exit 2 }
  # sql --json rows are POSITIONAL arrays
  $q = "select count(distinct r.symbol_id) from refs r join symbols s on s.id=r.symbol_id where r.symbol_id>0"
  $distinct = [int](& $Exe sql --db $db --query $q --json 2>&1 | Out-String | ConvertFrom-Json).rows[0][0]
  Check 'PRECONDITION: the fixture binds refs' ($distinct -gt 100) "distinct bound symbols=$distinct"

  $env:DRAGLINT_PROFILE = '1'
  try {
    $errFile = Join-Path $WorkDir 'lint-all.err'
    $json = & $Exe lint-all --db $db --rule unit-missing-from-uses --json 2> $errFile | Out-String
    $raw = [IO.File]::ReadAllText($errFile)
  } finally { $env:DRAGLINT_PROFILE = $null }
  $memo = [regex]::Match($raw, 'missing-uses memo\s+(\d+) bound-ref lookup\(s\), (\d+) store read\(s\)')
  Check 'the profile prints the memo counters' $memo.Success
  if ($memo.Success) {
    $look = [int64]$memo.Groups[1].Value; $reads = [int64]$memo.Groups[2].Value
    Check 'lookups were made (the bound-ref path ran)' ($look -gt 0) "lookups=$look"
    # positive-control: a per-file memo (the base) reads once per symbol per FILE -> reads = lookups
    Check 'store reads < lookups (shared across files)' ($reads -lt $look) "reads=$reads lookups=$look"
    Check 'store reads <= distinct bound symbols (one per symbol per run)' ($reads -le $distinct) "reads=$reads distinct=$distinct"
  }

  $f = @($json | ConvertFrom-Json | Where-Object { $_.rule -eq 'unit-missing-from-uses' })
  $want = 10 * ($Fns + 4)
  Check "findings: 10 blanked units x $($Fns + 4) names" ($f.Count -eq $want) "got=$($f.Count) want=$want"
  $files = @($f | ForEach-Object { [IO.Path]::GetFileName($_.file_path) } | Sort-Object -Unique)
  $exp = @(0, 5, 10, 15, 20, 25, 30, 35, 40, 45 | ForEach-Object { 'uU{0:D2}.pas' -f $_ })
  Check 'NEG: only the blanked units fire' ((Compare-Object $files $exp).Count -eq 0) ($files -join ',')
  $u00 = @($f | Where-Object { $_.file_path -match 'uU00\.pas$' -and $_.message -match "'F3_0' is declared in unit uD03" })
  Check 'uU00 lost uD03 -> F3_0 names uD03' ($u00.Count -eq 1)
} finally { Pop-Location }
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
