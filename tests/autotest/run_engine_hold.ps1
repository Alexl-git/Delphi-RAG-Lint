# dl:serial: manipulates the MACHINE-WIDE ide-release sentinel
#   (%LOCALAPPDATA%\drag-lint\engine-hold) -- one per-user file, not a per-test
#   one -- and asserts on `ide-release --status` around it, so a concurrent
#   sibling that takes or clears the hold flips this runner's answer. Its
#   staging-recovery case is also timing-windowed (hold the target, sleep 3,
#   release mid-retry, expect 'staging blocked' within 40s), which CPU
#   contention perturbs. FOUND BY THE -Jobs 8 A/B, not by the census: the
#   census asked only whether a runner writes the staged EXE (none does), and
#   this runner's shared state is a DIFFERENT global it never looked at.
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
# CHECK 4b -- WHAT THE VERB SAYS IT DOES
#
# Every surface that described `ide-release` claimed the plugin STOPS its
# drag-lint.exe children "on its next status tick". Both halves were wrong and
# both had been wrong since the verb shipped:
#   * the status strip (StatusBar.PollEngineHold) only ANNOUNCES the hold --
#     its own comment says "Announcing is not the same act as acting";
#   * the plugin acts LAZILY in EnsureLspClient, on the next request that wants
#     the client, and even then only stops a client that already exists. It
#     never kills anything -- build\stage-engine.ps1 does that.
#
# A reader who believed the old text would run the verb by hand and wait for a
# lock that, with nothing hovering, never clears.
#
# run_docs_sync_guard.ps1 cannot catch this: it checks verb PRESENCE, rule
# counts and dead DB paths, never prose, so it stayed green in both directions.
# Hence these checks, deliberately narrow -- two tokens, and only on the lines
# that name the verb. Matching English loosely is how a prose guard becomes
# noise that everyone learns to skim.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 4b: the wording matches the contract' -ForegroundColor Cyan

# The two predicates, factored out so the positive control (B5) can run the
# SAME code over planted text. A guard that cannot be made to fail is not a
# guard -- this repo has shipped three of those.
function Test-HoldProseOk([string]$Text, [string[]]$Banned, [string[]]$Required) {
  foreach ($b in $Banned)   { if ($Text -match [regex]::Escape($b)) { return $false } }
  foreach ($r in $Required) { if ($Text -notmatch [regex]::Escape($r)) { return $false } }
  $true
}

# B1 + B2 -- the runtime output of a real `ide-release`.
$r = Run @('ide-release','--seconds','60')
$runtime = $r.Out
Check 'runtime output does not claim a status tick' `
  (Test-HoldProseOk $runtime @('status tick') @()) `
  'the strip announces; EnsureLspClient acts'
Check 'runtime output names the refusal and the killer' `
  (Test-HoldProseOk $runtime @() @('respawn','stage-engine.ps1')) `
  'a caller needs both facts: what the plugin declines, and who actually kills'
Run @('ide-release','--resume') | Out-Null

# B3 -- the --help line for the verb.
$help     = (Run @('--help')).Out
$helpLine = ($help -split "`n" | Where-Object { $_ -match '^\s*drag-lint ide-release' }) -join "`n"
Check 'the --help line for ide-release exists' ($helpLine -ne '') 'regex: ^\s*drag-lint ide-release'
Check '--help does not claim a status tick' `
  (Test-HoldProseOk $helpLine @('status tick') @()) $helpLine
# RED-check finding, 2026-09-07: requiring only 'respawn' here is NOT
# discriminating -- the OLD help line already said "not respawn them", so that
# half passed against the defect it was written to catch. The token the old
# text genuinely lacked is the one naming who actually kills. Required tokens
# have to be chosen against the broken text, not against the fixed text.
Check '--help says the plugin will not respawn, and who does the killing' `
  (Test-HoldProseOk $helpLine @() @('respawn','stage-engine.ps1')) $helpLine

# B4 -- the three prose surfaces. Only the line(s) that NAME the verb.
$proseSurfaces = @(
  @{ File = 'README.md';                Select = { param($L) $L -match '^\|' -and $L -match 'ide-release' } },
  @{ File = 'docs\AI-USAGE.md';         Select = { param($L) $L -match '^\|' -and $L -match 'ide-release' } },
  # The wiki page's LEAD only: line 1 is the H1, and the body below the first
  # '## ' heading is already correct and says so at length.
  @{ File = 'docs\wiki\ide-release.md'; Select = $null }
)
foreach ($s in $proseSurfaces) {
  $path = Join-Path $Repo $s.File
  if (-not (Test-Path -LiteralPath $path)) { Check "$($s.File) exists" $false $path; continue }
  $lines = Get-Content -LiteralPath $path
  if ($null -eq $s.Select) {
    $stop  = ($lines | Select-String -Pattern '^## ' | Select-Object -First 1).LineNumber
    if (-not $stop) { $stop = $lines.Count + 1 }
    $text  = ($lines[1..($stop - 2)]) -join ' '
  } else {
    $text = ($lines | Where-Object { & $s.Select $_ }) -join ' '
  }
  Check "$($s.File): the ide-release description was found" ($text.Trim() -ne '') ''
  Check "$($s.File): does not overstate the verb as 'stop its/their children'" `
    (Test-HoldProseOk $text @('stop its','stop their') @()) $text
  Check "$($s.File): says the plugin will not respawn" `
    (Test-HoldProseOk $text @() @('respawn')) $text
}

# B5 -- POSITIVE CONTROL. The predicates above only prove something if they can
# still say FAIL. Plant the old wording and the removed token and require BOTH
# to be rejected; otherwise every PASS above is vacuous.
$planted = 'the plugin stops its drag-lint.exe children on its next status tick'
Check 'positive control: the OLD wording is rejected' `
  (-not (Test-HoldProseOk $planted @('status tick') @())) 'banned-token predicate is live'
Check 'positive control: text missing "respawn" is rejected' `
  (-not (Test-HoldProseOk $planted @() @('respawn'))) 'required-token predicate is live'
Check 'positive control: correct text still passes both' `
  (Test-HoldProseOk 'will not respawn drag-lint.exe; build\stage-engine.ps1 kills the holder' `
     @('status tick','stop its') @('respawn','stage-engine.ps1')) `
  'the predicates are not stuck on false'

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
