<#
  run_engine_hold.ps1 -- `drag-lint ide-release` and the staging recovery.

  WHAT THIS IS FOR
  ----------------
  A running Windows process holds an EXECUTE LOCK on its own image, and the
  Delphi plugin spawns drag-lint.exe as a long-lived LSP child. So an IDE that
  is merely OPEN blocks build_draglint_win64.bat from staging the engine it
  just compiled -- the compile succeeds and the deploy fails one line later,
  naming the FILE and not the HOLDER.

  The fix has two halves that only work together:
    * `ide-release` writes a sentinel carrying a DEADLINE, which the plugin
      observes lazily in EnsureLspClient and refuses to respawn while it lasts;
    * build\stage-engine.ps1 names the holder, writes that sentinel, kills the
      holder and retries.
  Killing alone loses the race -- both clients respawn within about a second.

  THE ASSERTION THAT MATTERS MOST IS THE FILE'S LOCATION
  -----------------------------------------------------
  The first implementation put the sentinel in TPath.GetTempPath. That is
  PER-PROCESS: this machine's shell has TEMP=C:\TEMP while the IDE resolves it
  to %LOCALAPPDATA%\Temp, so the writer and the reader looked in two different
  directories and the hold silently never arrived -- no error, no symptom,
  just a feature that did nothing. Caught by running it. Check 2 pins the
  stable location so it cannot come back.

  AND THE ONE AFTER IT IS FAIL-OPEN
  ---------------------------------
  A corrupt, empty or expired sentinel must report NOT HELD. The two failure
  directions are not symmetric: failing open costs a blocked build, which is
  visible and retryable; failing closed leaves the IDE silently without hovers,
  completion or diagnostics, with no error anywhere and no obvious way back.
  `--status` exists so this is checkable from outside at all.

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_engine_hold.ps1
#>
[CmdletBinding()]
param(
  [string] $Exe  = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string] $Repo = "$PSScriptRoot\..\.."
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== engine hold: ide-release + staging recovery ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path $Repo).Path
$errFile = Join-Path ([IO.Path]::GetTempPath()) ("draglint-hold-" + [Guid]::NewGuid().ToString('N') + ".txt")

function Run([string[]]$A) {
  $out = & $Exe @A 2>$errFile
  $rc  = $LASTEXITCODE
  [pscustomobject]@{ Out = ($out -join "`n"); Code = $rc }
}
function Status {
  $r = Run @('ide-release','--status','--json')
  if ($r.Code -ne 0) { return $null }
  try { return $r.Out | ConvertFrom-Json } catch { return $null }
}

# Whatever state a previous run or a real build left behind.
Run @('ide-release','--resume') | Out-Null

# ---------------------------------------------------------------------------
# CHECK 1 -- POSITIVE CONTROL: the hold can be set, seen and cleared
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 1: set / observe / clear' -ForegroundColor Cyan

$s = Status
Check 'with nothing set, --status reports NOT held' (($null -ne $s) -and ($s.held -eq $false)) "held=$($s.held)"

$r = Run @('ide-release','--seconds','300','--json')
Check 'ide-release exits 0' ($r.Code -eq 0) "exit $($r.Code)"
$s = Status
Check 'the hold is then observable' (($null -ne $s) -and ($s.held -eq $true)) "held=$($s.held)"
Check 'and it reports a plausible remaining time' `
  (($null -ne $s) -and ($s.seconds_left -gt 280) -and ($s.seconds_left -le 300)) "seconds_left=$($s.seconds_left)"

$sentinel = $s.sentinel

# ---------------------------------------------------------------------------
# CHECK 2 -- THE LOCATION. This is the bug that shipped and did nothing.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 2: the sentinel lives where BOTH processes will look' -ForegroundColor Cyan

Check 'the sentinel actually exists on disk' (Test-Path -LiteralPath $sentinel) $sentinel
Check 'it is under %LOCALAPPDATA%, not %TEMP%' `
  ($sentinel -like (Join-Path $env:LOCALAPPDATA 'drag-lint*')) `
  "TEMP is per-process: a shell and the IDE resolve it differently, so a TEMP sentinel never arrives. got: $sentinel"

$r = Run @('ide-release','--resume')
Check '--resume exits 0' ($r.Code -eq 0) "exit $($r.Code)"
$s = Status
Check 'and the hold is gone' (($null -ne $s) -and ($s.held -eq $false)) "held=$($s.held)"
Check 'the sentinel file is removed too' (-not (Test-Path -LiteralPath $sentinel)) $sentinel

# Clearing when there is nothing to clear is the desired end state, not an error.
$r = Run @('ide-release','--resume')
Check 'clearing a hold that does not exist is a success' ($r.Code -eq 0) "exit $($r.Code)"

# ---------------------------------------------------------------------------
# CHECK 3 -- FAIL OPEN. A corrupt sentinel must never mute the IDE.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 3: fail-open' -ForegroundColor Cyan

Set-Content -LiteralPath $sentinel -Value 'not-a-number' -Encoding Ascii
$s = Status
Check 'an UNPARSEABLE sentinel reports NOT held' (($null -ne $s) -and ($s.held -eq $false)) "held=$($s.held)"

Set-Content -LiteralPath $sentinel -Value '' -Encoding Ascii
$s = Status
Check 'an EMPTY sentinel reports NOT held' (($null -ne $s) -and ($s.held -eq $false)) "held=$($s.held)"

# A deadline in the past. Epoch seconds, UTC.
$past = [int][double]::Parse((Get-Date -Date ([datetime]::UtcNow.AddMinutes(-5)) -UFormat %s))
Set-Content -LiteralPath $sentinel -Value $past -Encoding Ascii
$s = Status
Check 'an EXPIRED sentinel reports NOT held' (($null -ne $s) -and ($s.held -eq $false)) "held=$($s.held)"
Check 'and the expired sentinel is tidied away' (-not (Test-Path -LiteralPath $sentinel)) ''

# NEGATIVE CONTROL: after three "not held" results in a row, a --status that
# ALWAYS said false would have passed every one of them.
Run @('ide-release','--seconds','60') | Out-Null
$s = Status
Check 'negative control: --status can still report TRUE' (($null -ne $s) -and ($s.held -eq $true)) `
  'three false results in a row would otherwise be satisfied by a stuck false'
Run @('ide-release','--resume') | Out-Null

# ---------------------------------------------------------------------------
# CHECK 4 -- the clamp
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 4: the hold length is clamped' -ForegroundColor Cyan

Run @('ide-release','--seconds','999999') | Out-Null
$s = Status
Check 'an absurd --seconds is clamped to an hour, not honoured' `
  (($null -ne $s) -and ($s.seconds_left -le 3600) -and ($s.seconds_left -gt 3500)) `
  "seconds_left=$($s.seconds_left) -- a typo must not silence the IDE for a week"
Run @('ide-release','--resume') | Out-Null

# ---------------------------------------------------------------------------
# CHECK 5 -- the staging recovery retries a genuinely locked target
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 5: stage-engine.ps1 recovery' -ForegroundColor Cyan

$stager = Join-Path $Repo 'build\stage-engine.ps1'
Check 'the recovery script is present' (Test-Path -LiteralPath $stager) $stager

if (Test-Path -LiteralPath $stager) {
  $tmp    = Join-Path ([IO.Path]::GetTempPath()) ("draglint-stage-" + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null
  $fresh  = Join-Path $tmp 'fresh.exe'
  $target = Join-Path $tmp 'target.exe'
  Set-Content -LiteralPath $fresh  -Value 'NEW' -Encoding Ascii
  Set-Content -LiteralPath $target -Value 'OLD' -Encoding Ascii

  # Hold the target open with NO sharing -- the same shape of lock a running
  # image has, without needing a real process to run it. The holder is not a
  # drag-lint.exe, which also exercises the "the lock is something else" path.
  $stream = [IO.File]::Open($target, 'Open', 'ReadWrite', 'None')
  $job = Start-Job -ScriptBlock {
    param($p, $s)
    pwsh -NoProfile -File $p -FreshExe $s.fresh -Target $s.target -TimeoutSec 20 2>&1
    $LASTEXITCODE
  } -ArgumentList $stager, @{ fresh = $fresh; target = $target }

  Start-Sleep -Seconds 3
  # Release mid-retry: the recovery must notice and finish the copy.
  $stream.Close(); $stream.Dispose()

  $done = Wait-Job $job -Timeout 40
  $out  = Receive-Job $job
  Remove-Job $job -Force -ErrorAction SilentlyContinue

  Check 'the recovery finished rather than hanging' ($null -ne $done) ''
  $staged = ''
  if (Test-Path -LiteralPath $target) { $staged = (Get-Content -LiteralPath $target -Raw).Trim() }
  Check 'it staged the file once the lock was released' ($staged -eq 'NEW') "target content: '$staged'"
  Check 'and it said the target was locked rather than failing silently' `
    (($out -join "`n") -match 'staging blocked') (($out -join ' ') -replace '\s+',' ')

  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
Run @('ide-release','--resume') | Out-Null

Write-Host ''
if ($script:Failed) { Write-Host 'ENGINE HOLD GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ENGINE HOLD GUARD: PASS' -ForegroundColor Green
exit 0
