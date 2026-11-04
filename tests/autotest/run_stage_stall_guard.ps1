<#
  run_stage_stall_guard.ps1 -- a stage that stops moving says why; armed, it exits. A moving one is never stopped.

  WHY. A heartbeat proves only that its timer thread is alive, so a run can "beat" for hours at nothing. The
  test is the status record's Seq. The hold seam (DRAGLINT_TEST_RESOLVE_DELAY_MS) is a stalled stage;
  DRAGLINT_TEST_BEAT_MOVES turns it into a slow one with a moving counter.

    S1 standing counter, not armed: NO PROGRESS line, exit 0, same rows
    S2 standing counter, armed: STALLED line, exit 8; a --resolve-only re-run restores the same rows
    S3 NO FALSE KILL: moving counter, armed with a limit far under the hold: exit 0, no reason line, same rows
    S4 standing counter, armed, RAM critical: exit 9, and at a quarter of the limit
    S5 NO FALSE KILL: moving counter, armed, RAM critical: LOW MEMORY line, exit 0
    S6 the flag itself: --stall-exit-min 1 is accepted and a short hold is not stopped

  Scratch only (-WorkDir); never a real project DB. Needs python on PATH. pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-stall-guard-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name  $Detail" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Run-Exe([string[]]$ArgList, [hashtable]$EnvVars = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $WorkDir
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(120000)) { try { $p.Kill($true) } catch { } }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Text = $o.Result + $e.Result; Ms = $sw.ElapsedMilliseconds }
}
function Mix([hashtable]$A, [hashtable]$B) { $m = $A.Clone(); foreach ($k in $B.Keys) { $m[$k] = $B[$k] }; return $m }
function Counts([string]$Db) {
  return [string](& python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute('SELECT count(*) FROM refs WHERE symbol_id IS NOT NULL').fetchone()[0], c.execute('SELECT count(*) FROM call_edges').fetchone()[0], c.execute('PRAGMA integrity_check').fetchone()[0])" $Db)
}

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $src -Force | Out-Null
  for ($i = 1; $i -le 3; $i++) {
    $j = if ($i -lt 3) { $i + 1 } else { 1 }
    $t = "unit StallUnit$i;`r`n`r`ninterface`r`n`r`nprocedure Work$i(A: Integer);`r`n`r`nimplementation`r`n`r`nuses StallUnit$j;`r`n`r`nprocedure Work$i(A: Integer);`r`nbegin`r`n  if A > 0 then begin Work$i(A - 1); Work$j(A - 1); end;`r`nend;`r`n`r`nend.`r`n"
    [IO.File]::WriteAllText((Join-Path $src "StallUnit$i.pas"), $t, [Text.Encoding]::ASCII)
  }
  $db = Join-Path $WorkDir 'stall.sqlite'
  $first = Run-Exe @('index', $src, '--db', $db)
  if ($first.Code -ne 0) { Write-Host "FATAL: setup index failed: $($first.Text)" -ForegroundColor Red; exit 2 }
  $c0 = Counts $db
  $Idx = @('index', $src, '--db', $db, '--resolve-only')
  $Fast = @{ DRAGLINT_STAGE_HEARTBEAT_MS = 50; DRAGLINT_STAGE_STALL_WARN_MS = 300; DRAGLINT_TEST_RESOLVE_DELAY_MS = 1500 }

  $s1 = Run-Exe $Idx $Fast
  Check 'S1 a standing counter, not armed: reason line, exit 0, same rows' (($s1.Code -eq 0) -and ($s1.Text -match 'stage: calls -- NO PROGRESS for \d+ s at ') -and ((Counts $db) -eq $c0)) "exit=$($s1.Code) rows=$(Counts $db)"

  $s2 = Run-Exe $Idx (Mix $Fast @{ DRAGLINT_STAGE_STALL_EXIT_MS = 500; DRAGLINT_TEST_RESOLVE_DELAY_MS = 20000 })
  $after = Run-Exe $Idx
  Check 'S2 a standing counter, armed: STALLED, exit 8, and --resolve-only restores the rows' (($s2.Code -eq 8) -and ($s2.Text -match 'stage: calls -- STALLED: no progress') -and ($after.Code -eq 0) -and ((Counts $db) -eq $c0)) "exit=$($s2.Code) ms=$($s2.Ms) rerun=$($after.Code) rows=$(Counts $db)"

  $Moves = @{ DRAGLINT_TEST_BEAT_MOVES = '1' }
  $s3 = Run-Exe $Idx (Mix (Mix $Fast $Moves) @{ DRAGLINT_STAGE_STALL_EXIT_MS = 100 })
  Check 'S3 NO FALSE KILL: a moving counter over the limit runs to exit 0' (($s3.Code -eq 0) -and ($s3.Text -notmatch 'STALLED|stage: calls -- NO PROGRESS') -and ((Counts $db) -eq $c0)) "exit=$($s3.Code) rows=$(Counts $db)"

  $s4 = Run-Exe $Idx (Mix $Fast @{ DRAGLINT_STAGE_STALL_EXIT_MS = 4000; DRAGLINT_TEST_AVAIL_PHYS_MB = 100; DRAGLINT_TEST_RESOLVE_DELAY_MS = 20000 })
  $restore = Run-Exe $Idx
  Check 'S4 a standing counter, armed, RAM critical: LOW MEMORY, exit 9, at a quarter of the limit' (($s4.Code -eq 9) -and ($s4.Text -match 'stage: calls -- LOW MEMORY: 100 MB free') -and ($s4.Text -match 'STALLED: no progress for 1 s') -and ($restore.Code -eq 0)) "exit=$($s4.Code) ms=$($s4.Ms) line='$(([regex]::Match($s4.Text,'STALLED: no progress for \d+ s')).Value)'"

  $s5 = Run-Exe $Idx (Mix (Mix $Fast $Moves) @{ DRAGLINT_STAGE_STALL_EXIT_MS = 100; DRAGLINT_TEST_AVAIL_PHYS_MB = 100 })
  Check 'S5 NO FALSE KILL: a moving counter short of RAM says so and runs to exit 0' (($s5.Code -eq 0) -and ($s5.Text -match 'LOW MEMORY') -and ($s5.Text -notmatch 'STALLED') -and ((Counts $db) -eq $c0)) "exit=$($s5.Code) rows=$(Counts $db)"

  $s6 = Run-Exe ($Idx + @('--stall-exit-min', '1')) @{ DRAGLINT_TEST_RESOLVE_DELAY_MS = 500 }
  Check 'S6 the flag is accepted and a short hold is not stopped' ($s6.Code -eq 0) "exit=$($s6.Code)"
}
catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
finally {
  try { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
}
if ($script:Failed) { exit 1 }
Write-Host 'ALL PASS'
exit 0
