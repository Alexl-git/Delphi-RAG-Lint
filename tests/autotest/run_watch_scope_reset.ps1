<#
  run_watch_scope_reset.ps1 -- every --watch tick resolves against ITS OWN
  change set, not the first tick's (1.31.6 lane E, item 1).

  THE DEFECT (lane 2 follow-up, 1.31.5): the resolve-scope state on
  TSQLiteSymbolStore -- FScopeWhole, the share counters, the scoped file/name
  sets -- is initialised once, in the constructor. `index --watch` keeps ONE
  store across ticks, so the whole-database latch that tick 1 sets (a new DB is
  always whole) stays set for the life of the process: every later tick that
  changes one file still runs the WHOLE-DB calls pass and names tick 1's reason.

  Found on the way, and pinned here because each one alone kept W2 red:
    * Checkpoint ran `PRAGMA wal_checkpoint` through FConn.ExecSQL, which left
      the statement in progress: every later tick failed its first file write
      with "cannot commit transaction - SQL statements in progress" (W0).
    * DoIndex read ResolverStale ONCE, before the loop: on a new DB every tick
      cleared every call edge and so could never scope.
    * Indexer.ParsedFiles is cumulative, so every idle tick ran the calls pass
      over the whole database (W4).

  THE CASES
    W0  no tick fails a file write with "SQL statements in progress".
    W1  tick 1 on a new DB runs the WHOLE-DB pass (sanity: the latch is set).
    W2  the tick that re-parses one changed file of nine runs the SCOPED pass
        over exactly 1 changed file -- RED before the fix.
    W3  and does not repeat tick 1's new-database reason.
    W4  an idle tick (nothing parsed) skips the calls pass.
    P1  POSITIVE CONTROL: the same one-file change, indexed by a one-shot run
        (a fresh store), is SCOPED -- the fixture CAN scope, so a W2 failure is
        the latch and not the fixture.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_watch_scope_reset_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $src $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
# Nine units in a chain: uU<i> calls uU<i-1>.P<i-1>. One edited file is 1 of 9,
# well under the one-in-three share latch (limit 3).
function Emit-Unit([int]$i, [string]$extra = '') {
  $uses = if ($i -gt 1) { "uses uU$($i-1);" } else { '' }
  $call = if ($i -gt 1) { "  P$($i-1);" } else { '' }
  Emit "uU$i.pas" @"
unit uU$i;
interface
$uses
procedure P$i;
implementation
procedure P$i;
begin
$call
$extra
end;
end.
"@
}
1..9 | ForEach-Object { Emit-Unit $_ }

$db     = Join-Path $WorkDir 'watch.sqlite'
$outLog = Join-Path $WorkDir 'watch.out'
$errLog = Join-Path $WorkDir 'watch.err'

# The engine still holds both logs open while it watches: read them shared.
function Read-Shared([string]$p) {
  if (-not (Test-Path $p)) { return '' }
  $fs = [System.IO.File]::Open($p, 'Open', 'Read', 'ReadWrite')
  try { (New-Object System.IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
function Read-Out { (Read-Shared $outLog) + "`n" + (Read-Shared $errLog) }
function Count-Done { ([regex]::Matches((Read-Out), '(?m)^Done\. Files:')).Count }
function Wait-Done([int]$n, [int]$seconds) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ((Count-Done) -lt $n -and $sw.Elapsed.TotalSeconds -lt $seconds) { Start-Sleep -Milliseconds 250 }
  return (Count-Done) -ge $n
}
# One block per tick, split on the tick banner.
function Get-Ticks { ((Read-Out) -split '(?m)^\[\d\d:\d\d:\d\d\] Indexing tick') | Select-Object -Skip 1 }

Push-Location C:\TEMP
$proc = $null
try {
  Write-Host ''
  Write-Host 'WATCH -- tick 1 indexes a new DB, a later tick re-parses ONE file' -ForegroundColor Cyan
  # ONE log for both streams, so the stderr resolve lines land inside their tick.
  [System.IO.File]::WriteAllText($errLog, '')
  $proc = Start-Process -FilePath $env:ComSpec -ArgumentList @('/c', "`"`"$Exe`" index `"$src`" --db `"$db`" --watch --interval 1 > `"$outLog`" 2>&1`"") `
            -PassThru -NoNewWindow
  $ok1 = Wait-Done 1 120
  Check 'the first tick finished' $ok1 ''
  Start-Sleep -Milliseconds 1100
  Emit-Unit 5 '  ;'
  # Wait until a tick has re-parsed uU5 AND finished.
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $hit = $null
  while (-not $hit -and $sw.Elapsed.TotalSeconds -lt 120) {
    Start-Sleep -Milliseconds 500
    $hit = Get-Ticks | Select-Object -Skip 1 | Where-Object { $_ -match 'uU5\.pas ->' -and $_ -match '(?m)^Done\. Files:' } | Select-Object -First 1
  }
}
finally {
  # Stop the watching engine (cmd's child) by PID, then cmd itself.
  if ($proc) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    $proc.WaitForExit(10000) | Out-Null
  }
}
try {
  $ticks = @(Get-Ticks)
  $t1 = if ($ticks.Count -gt 0) { $ticks[0] } else { '' }
  Check 'W1 tick 1 (new DB) runs the WHOLE-DB pass' ($t1 -match 'starting WHOLE-DB pass') ''
  $commitErr = (Read-Out) -split "`n" | Where-Object { $_ -match 'cannot commit transaction' } | Select-Object -First 1
  Check 'W0 no tick fails a file write with "cannot commit transaction - SQL statements in progress"' (-not $commitErr) "$commitErr"
  Check 'the edit was picked up by a later tick' ([bool]$hit) "ticks seen: $($ticks.Count)"
  $ann = if ($hit) { (($hit -split "`n") | Where-Object { $_ -match 'resolve: calls\s+(starting|\.\.\. whole database because)' }) -join ' / ' } else { '' }
  Check 'W2 that tick runs the SCOPED pass over 1 changed file' ($hit -and $hit -match 'starting SCOPED pass over 1 changed file') $ann
  Check 'W3 and does not repeat tick 1''s new-database reason' ($hit -and -not ($hit -match 'held no files before this run')) $ann
  $idle = @($ticks | Select-Object -Skip 1 | Where-Object { $_ -match '(?m)^Done\. Files:' -and -not ($_ -match '\.pas ->') })
  $idleRan = @($idle | Where-Object { $_ -match 'starting (WHOLE-DB|SCOPED) pass' })
  Check 'W4 an idle tick (nothing parsed) skips the calls pass' (($idle.Count -gt 0) -and ($idleRan.Count -eq 0)) `
    "idle ticks: $($idle.Count), of which ran the calls pass: $($idleRan.Count)"

  Write-Host ''
  Write-Host 'CONTROL -- the same one-file change through a one-shot run' -ForegroundColor Cyan
  Start-Sleep -Milliseconds 1100
  Emit-Unit 6 '  ;'
  $p = & $Exe index $src --db $db 2>&1 | Out-String
  $pann = (($p -split "`n") | Where-Object { $_ -match 'resolve: calls\s+(starting|\.\.\. whole database because)' }) -join ' / '
  Check 'P1 a one-shot run over one changed file is SCOPED' ($p -match 'starting SCOPED pass over 1 changed file') $pann
}
finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'run_watch_scope_reset: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_watch_scope_reset: PASS' -ForegroundColor Green
exit 0
}
catch {
  Write-Host "run_watch_scope_reset: ERROR $_" -ForegroundColor Red
  exit 2
}
