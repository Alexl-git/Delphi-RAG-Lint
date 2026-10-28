<#
  run_anon_method_rhs_write_ref.ps1 -- lane EXT E3 (2026-10-28, item #3 of the
  1.37.0 gaps triage; gaps.log 2026-10-27 16:24 "usages --name FeedHarvest").
  A record-field write whose RHS is an anonymous method
  (`LHost.FeedHarvest := procedure(...) begin ... end;`) is a WRITE of the field:
  usages counts it like the scalar control `LHost.Plain := 1`. MEASURED on the
  stage2 engine (68b84870): the ref IS emitted (also on the real
  ConvRules.MainForm.pas:3765), so #3 was a stale worktree DB, not an extractor
  gap. This guard is a REGRESSION guard (it could not be RED on stage2).

  Fixture tests\autotest\fixtures\anonrhs\uAnonRhs.pas: procedure RHS, function
  RHS, the real-source shape (inline var host, TProc<TArray<string>> field, a var
  section inside the anonymous method, `:=` without a space) and the control.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-anonrhs-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Passed = 0; $script:FailedN = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailedN++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
function Writes([string]$db, [string]$name) {
  Push-Location $WorkDir
  try { $o = & $Exe usages --name $name --db $db 2>&1 | Out-String } finally { Pop-Location }
  if ($o -match 'writes:\s*(\d+)') { return [int]$Matches[1] }
  return -1
}
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  $fx = Join-Path $WorkDir 'anonrhs'
  Copy-Item (Resolve-Path "$PSScriptRoot\fixtures\anonrhs").Path $fx -Recurse
  $db = Join-Path $WorkDir 'a.sqlite'
  Push-Location $WorkDir
  try { $null = & $Exe index $fx --db $db --library-db none 2>&1 | Out-String } finally { Pop-Location }
  $w = Writes $db 'Plain'
  Check 'control: LHost.Plain := <int> counted as 2 writes' ($w -eq 2) "writes=$w"
  foreach ($n in 'FeedHarvest', 'Counter', 'FeedPaths') {
    $w = Writes $db $n
    Check ("anonymous-method RHS: LHost.{0} := ... counted as a write" -f $n) ($w -eq 1) "writes=$w"
  }
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("run_anon_method_rhs_write_ref: {0} passed, {1} failed" -f $script:Passed, $script:FailedN)
if ($script:FailedN -gt 0) { exit 1 } else { exit 0 }