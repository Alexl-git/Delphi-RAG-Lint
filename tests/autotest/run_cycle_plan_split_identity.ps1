<#
  run_cycle_plan_split_identity.ps1 -- `cycles --plan` output must stay
  byte-identical across the E18 Task 1 planner / renderer split.

  WHY (2026-10-19, E18 T1): TCyclePlanner computed and printed each cycle in one
  pass. `cycles --fix` needs the plan as DATA (TCycleFixPlan), so the per-cycle
  computation moved into BuildPlan and the printing into RenderPlan. That is a
  behaviour-preserving refactor: the playbook a user (or a cheap model) follows
  must not change by one byte. This runner pins it against oracles captured
  from the engine BEFORE the split.

  HOW. Copies circular-demo to a scratch root, indexes it, runs
      cycles --db <db> --edges --causes --plan --format text
  capturing stdout as BYTES, replaces the scratch root with @@ROOT@@ and the db
  path with @@DB@@, and compares byte-for-byte with
  tests\fixtures\cyclefix\oracle\demo-plan.txt (CRLF, ASCII; stdout only -- the
  stderr note `(loaded defaults from ...)` is not part of it). Optional: the same
  for an index of drag-lint itself (-SelfDb + -SelfOracle; skipped when absent),
  where the root is the repo and the oracle is a raw (untokenised) capture.

  POSITIVE CONTROL: one byte of the oracle is flipped in memory and the compare
  must then FAIL -- a compare that cannot fail proves nothing.
#>
[CmdletBinding()]
param(
  [string]$Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir    = "$env:TEMP\drag-lint-cycle-split-$PID",
  [string]$SelfDb     = '',
  [string]$SelfOracle = '',
  [string]$SelfRoot   = ''
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($SelfRoot -eq '') { $SelfRoot = $Repo }
$Ascii = [Text.Encoding]::ASCII

# Runs the plan and returns stdout exactly as written (no PowerShell line splitting).
function Get-PlanText([string]$Db, [string]$RunDir) {
  $outFile = Join-Path $WorkDir ('plan-' + [Guid]::NewGuid().ToString('N') + '.txt')
  $p = Start-Process -FilePath $Exe -WorkingDirectory $RunDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $Db + '"'), '--edges', '--causes', '--plan', '--format', 'text') `
    -RedirectStandardOutput $outFile -RedirectStandardError (Join-Path $WorkDir 'plan-stderr.txt')
  return @{ Exit = $p.ExitCode; Text = $Ascii.GetString([IO.File]::ReadAllBytes($outFile)) }
}

# Reports the first differing line so a drift is readable.
function Compare-Text([string]$Name, [string]$Actual, [string]$Expected) {
  if ($Actual -ceq $Expected) { Check "$Name byte-identical to the oracle" $true ("({0} bytes)" -f $Expected.Length); return }
  $a = $Actual -split "`n"; $e = $Expected -split "`n"
  $n = [Math]::Min($a.Count, $e.Count); $at = $n
  for ($i = 0; $i -lt $n; $i++) { if ($a[$i] -cne $e[$i]) { $at = $i; break } }
  $got = if ($at -lt $a.Count) { $a[$at].TrimEnd("`r") } else { '<eof>' }
  $exp = if ($at -lt $e.Count) { $e[$at].TrimEnd("`r") } else { '<eof>' }
  Check "$Name byte-identical to the oracle" $false ("first diff at line {0}: got [{1}] expected [{2}] (bytes {3} vs {4})" -f ($at + 1), $got, $exp, $Actual.Length, $Expected.Length)
}

if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- demo ---------------------------------------------------------------------
Write-Host ''
Write-Host '== circular-demo' -ForegroundColor Cyan
$oraclePath = Join-Path $Repo 'tests\fixtures\cyclefix\oracle\demo-plan.txt'
Check 'demo oracle exists' (Test-Path $oraclePath) $oraclePath
if (Test-Path $oraclePath) {
  $root = Join-Path $WorkDir 'circular-demo'
  New-Item -ItemType Directory $root | Out-Null
  Get-ChildItem (Join-Path $Repo 'circular-demo') -File |
    Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj', '.inc', '.dfm' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  $db = Join-Path $WorkDir 'demo.sqlite'
  & $Exe index --project (Join-Path $root 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir 'index-demo.log')
  Check 'demo indexed' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $run = Get-PlanText $db $WorkDir
  Check 'demo cycles --plan ran' ($run.Exit -eq 0 -or $run.Exit -eq 1) "exit=$($run.Exit)"
  $actual   = $run.Text.Replace($root, '@@ROOT@@').Replace($db, '@@DB@@')
  $expected = $Ascii.GetString([IO.File]::ReadAllBytes($oraclePath))
  Check 'demo oracle is CRLF ASCII and non-empty' (($expected.Length -gt 0) -and ($expected -notmatch "[^`r]`n") -and ($expected -notmatch '[^\x00-\x7F]')) ''
  Compare-Text 'demo' $actual $expected

  # POSITIVE CONTROL: a one-byte change in the oracle must make the compare fail.
  $mid = [int]($expected.Length / 2)
  $flip = if ($expected[$mid] -eq 'x') { 'y' } else { 'x' }
  $broken = $expected.Substring(0, $mid) + $flip + $expected.Substring($mid + 1)
  Check 'positive control: a one-byte oracle change is detected' (-not ($actual -ceq $broken)) "(byte $mid)"
}

# --- self (optional) --------------------------------------------------------------
Write-Host ''
if ($SelfDb -ne '' -and $SelfOracle -ne '' -and (Test-Path $SelfDb) -and (Test-Path $SelfOracle)) {
  Write-Host '== self (drag-lint)' -ForegroundColor Cyan
  $run = Get-PlanText $SelfDb $WorkDir
  Check 'self cycles --plan ran' ($run.Exit -eq 0 -or $run.Exit -eq 1) "exit=$($run.Exit)"
  $actual   = $run.Text.Replace($SelfRoot, '@@ROOT@@').Replace($SelfDb, '@@DB@@')
  # A raw capture may hold the stderr note `(loaded defaults from ...)` (2>&1); it is not plan text.
  $expected = $Ascii.GetString([IO.File]::ReadAllBytes($SelfOracle)).Replace($SelfRoot, '@@ROOT@@').Replace($SelfDb, '@@DB@@')
  $expected = [regex]::Replace($expected, '(?m)^\(loaded defaults from [^\r\n]*\r\n', '')
  Compare-Text 'self' $actual $expected
} else {
  Write-Host '== self: SKIPPED (pass -SelfDb and -SelfOracle)' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
