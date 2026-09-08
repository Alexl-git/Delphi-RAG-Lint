<#
  run_battery_heartbeat_guard.ps1 -- the battery announces itself, and keeps
  announcing itself while a slow runner blocks the loop.

  WHY THIS EXISTS
  ---------------
  Owner report, 2026-09-08: "When battery runs, we need a more prominent message
  that will be better visible with 10 minute status update, so I won't get
  confused and think the run is over and ready for the next command."

  The failure mode is a property of the driver's SERIAL loop. It writes
  '[ 12/486] tests/... ... ' with -NoNewline and then blocks inside WaitForExit
  until that runner finishes. tests\lint\run_lint_tests is ~261 s, so the console
  can sit on a half-written line for four and a half minutes with no cursor
  movement -- indistinguishable from a finished run sitting at a prompt.

  WHAT IS ASSERTED, AND WHY EACH ONE IS HERE
  ------------------------------------------
  1-2. The START and FINISHED banners exist and say which they are. These print
       unconditionally, so on their own they are weak checks -- they would pass
       against a driver whose heartbeat was deleted. They are here because the
       banners are half of what the owner asked for, not as the load-bearing
       check.
  3.   A heartbeat FIRES while a runner is still blocking, and names the runner.
       This is the load-bearing one.
  4.   THE POSITIVE CONTROL FOR 3: the same run with -HeartbeatMin 0 must
       produce NO heartbeat. Without this, check 3 would also pass against a
       driver that printed the beat unconditionally on every poll, which is a
       different (and much noisier) feature than the one that was asked for.
  5.   THE TIMEOUT BUDGET SURVIVED. This is the check that exists because of the
       CHANGE, not because of the feature: the beat was made possible by
       replacing one blocking WaitForExit($TimeoutSec * 1000) with a polled wait
       in 500 ms slices. A polled wait is exactly where a per-runner budget goes
       wrong -- slices accumulating drift, or a loop that never breaks. So the
       guard drives a runner known to outlive a deliberately tiny -TimeoutSec
       and asserts it is still reported TIMEOUT, and that the run still exits 1.

  WHY IT KILLS A RUNNER ON PURPOSE
  --------------------------------
  Check 5 selects tests\run_doctests_v021.ps1 (~188 s) with -TimeoutSec 3, so it
  is killed at three seconds. That is not collateral damage -- killing an
  over-budget runner WITH ITS WHOLE PROCESS TREE is the production path this
  guard is verifying, and the driver does it precisely because an orphaned
  drag-lint.exe holds a .sqlite lock that would fail the NEXT runner too.

  COST: about 10 seconds. Both runs are -Include-narrowed to a single runner and
  both are capped at a few seconds by -TimeoutSec.
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = "$PSScriptRoot\..\..",

  # The runner used as the "slow" subject. It must (a) be enumerated by the
  # driver and (b) reliably outlive -TimeoutSec 3. Parameterised so that a
  # future retirement of this runner is a one-line fix rather than a mystery.
  [string]$SlowRunner = 'run_doctests_v021'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
$driver   = Join-Path $RepoRoot 'tests\run_battery.ps1'
if (-not (Test-Path $driver)) { Write-Host "FATAL: no driver at $driver" -ForegroundColor Red; exit 2 }

$driverText = Get-Content -LiteralPath $driver -Raw

Write-Host ''
Write-Host 'The driver declares the heartbeat parameter' -ForegroundColor Cyan
Check 'run_battery.ps1 declares [double]$HeartbeatMin and defaults it to 10' `
  ($driverText -match '\[double\]\$HeartbeatMin\s*=\s*10') `
  '10 is the owner''s number; [double] is what makes a sub-minute interval testable'

# --- Drive the real driver, twice ------------------------------------------
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("hb_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Invoke-Battery([string]$Tag, [string]$Beat) {
  $out = Join-Path $tmp "$Tag.log"
  $p = Start-Process pwsh -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-File', $driver,
        '-Include', $SlowRunner,
        '-TimeoutSec', '3',
        '-HeartbeatMin', $Beat,
        '-LogDir', (Join-Path $tmp "logs_$Tag")
      ) -WorkingDirectory $RepoRoot -PassThru -Wait `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err" -WindowStyle Hidden
  return [pscustomobject]@{
    Text = (Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue)
    Exit = $p.ExitCode
  }
}

Write-Host ''
Write-Host "Driving the driver: -Include $SlowRunner -TimeoutSec 3" -ForegroundColor Cyan
$beat = Invoke-Battery 'beat' '0.01'   # 0.6 s -- several beats inside a 3 s budget
$none = Invoke-Battery 'none' '0'      # the control: beats disabled

# Guard against a vacuous pass: if the -Include selected nothing the driver
# exits 2 and every text assertion below would be checking an empty run.
Check 'the narrowed run actually selected the slow runner' `
  ($beat.Exit -ne 2 -and $beat.Text -match [regex]::Escape($SlowRunner)) `
  "exit=$($beat.Exit) -- exit 2 means the -Include matched ZERO runners and this guard proved nothing"

Write-Host ''
Write-Host 'Banners' -ForegroundColor Cyan
Check 'a START banner names the run as started' `
  ($beat.Text -match 'BATTERY STARTED') ''
Check 'the START banner states the heartbeat interval' `
  ($beat.Text -match '(?m)heartbeat\s*:') ''
Check 'a FINISHED banner names the run as over' `
  ($beat.Text -match 'BATTERY FINISHED') ''
Check 'the FINISHED banner states the verdict in a word (RED here -- the runner is killed)' `
  ($beat.Text -match 'BATTERY FINISHED -- RED') ''
Check 'the FINISHED banner tells the reader it is safe to type again' `
  ($beat.Text -match 'safe to type the next command') ''

Write-Host ''
Write-Host 'The heartbeat itself' -ForegroundColor Cyan
$beats = [regex]::Matches($beat.Text, 'BATTERY STILL RUNNING -- heartbeat #\d+').Count
Check 'at least one heartbeat fired while the runner was still blocking' `
  ($beats -ge 1) "beats=$beats"
Check 'the heartbeat names the runner currently blocking' `
  ($beat.Text -match '(?m)running\s*:\s*\S*' + [regex]::Escape($SlowRunner)) ''
Check 'the heartbeat says the run is NOT finished' `
  ($beat.Text -match 'This run is NOT finished') ''
Check 'the heartbeat does not fabricate an ETA before anything has completed' `
  ($beat.Text -match 'no runner has completed yet') `
  'with a single -Include''d runner nothing has finished, so an ETA would be extrapolated from zero samples'

Write-Host ''
Write-Host 'POSITIVE CONTROL -- the beat is driven by the parameter, not printed unconditionally' -ForegroundColor Cyan
$noneBeats = [regex]::Matches($none.Text, 'BATTERY STILL RUNNING -- heartbeat').Count
Check '-HeartbeatMin 0 produces NO heartbeat at all' `
  ($noneBeats -eq 0) "beats=$noneBeats -- if this is non-zero, the check above passes vacuously"
Check '-HeartbeatMin 0 still prints both banners' `
  ($none.Text -match 'BATTERY STARTED' -and $none.Text -match 'BATTERY FINISHED') `
  'disabling the beat must not disable the start/end banners'
Check '-HeartbeatMin 0 says so in the START banner' `
  ($none.Text -match 'DISABLED') ''

Write-Host ''
Write-Host 'THE TIMEOUT BUDGET SURVIVED THE POLLED WAIT' -ForegroundColor Cyan
Check 'the driver still polls in bounded slices rather than one blocking wait' `
  ($driverText -match 'WaitForExit\(\[Math\]::Min\(\$remainMs,\s*500\)\)') `
  'the beat is only possible because the wait is sliced'
Check 'the deadline is computed ONCE, so slices cannot accumulate into a longer budget' `
  ($driverText -match '\$deadline\s*=\s*\[DateTime\]::UtcNow\.AddSeconds\(\$TimeoutSec\)') ''
Check 'a runner that outlives -TimeoutSec is still reported TIMEOUT' `
  ($beat.Text -match '(?m)TIMEOUT') `
  'this is the check that exists because of the CHANGE: a polled wait is where a budget goes wrong'
Check 'a timed-out run still exits 1' `
  ($beat.Exit -eq 1) "exit=$($beat.Exit)"
Check 'the control run timed out too (so the two runs differ ONLY in the beat)' `
  ($none.Text -match '(?m)TIMEOUT' -and $none.Exit -eq 1) "exit=$($none.Exit)"

Write-Host ''
Write-Host 'The heartbeat does not corrupt the runner result line' -ForegroundColor Cyan
# The beat interrupts a '[  1/1] rel ... ' prefix written with -NoNewline, so the
# driver re-draws that prefix afterwards. Without the re-draw the runner's own
# TIMEOUT would land at the end of the heartbeat block instead of after its name.
Check 'the runner name and its result appear on one line' `
  ($beat.Text -match '(?m)^\[\s*\d+/\d+\]\s+\S*' + [regex]::Escape($SlowRunner) + '.*(TIMEOUT|PASS|FAIL)') `
  'if the -NoNewline prefix is not re-drawn after a beat, the result is orphaned from its runner'

try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
