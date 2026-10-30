<#
  run_rule_cache_warm_background.ps1 -- index warms the `lint <file>` rule cache
  in the run by default, or in a DETACHED background process on request
  (--rule-cache-warm background, or DRAGLINT_RULE_CACHE_WARM=background).

  WHY. The warm recomputes the whole-project rules (circular-uses,
  enum-helper-separate-units, duplicate-global-decl) and its key is the index's
  file stat, which every index run moves -- so it ran in full on every run,
  nothing changed included: 252 s on the 2,218-file ProjectA closure, against an
  index of 1 to 7 s (measured 2026-10-15, tools\perf\scenarios.ps1). In the
  background the run returns at once and the IDE still finds a warm cache.
  WHY NOT THE DEFAULT. The background process keeps the index open until it
  ends, and Windows will not delete an open file: tools\score-cycle-playbook.ps1
  indexes a scratch DB and deletes it, which failed under load
  (run_score_cycle_playbook_selftest).

  Checks:
    B0  default (no flag, no variable): warmed in the run, nothing in the background
    B1  --rule-cache-warm background: says it is warming in the background, with a pid
    B2  the background warm writes the cache entry and exits
    B3  the next lint is a HIT
    B4  --rule-cache-warm off: nothing warmed, said so
    B5  --rule-cache-warm wait: warmed in the run (the previous behaviour)
    B6  --rule-cache-warm with another value: exit 2
    B7  warm-rule-cache --db <db> by hand: exit 0, warmed
    B8  warm-rule-cache without --db: exit 2
    B9  a background warm stops the previous one of the SAME database (same engine image)
    B10 ... and never a process of another program that reuses the recorded pid
    B11 DRAGLINT_RULE_CACHE_WARM=background sets the default; the flag still wins
    B12 DRAGLINT_RULE_CACHE_WARM with another value: exit 2, naming the variable
    B13 index --all --jobs 2 passes --rule-cache-warm to each section child (--jobs 1 = control)
    B14 a warm started by the engine's 8.3 short path still stops the previous one

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_warm_bg_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$proj = Join-Path $WorkDir 'proj'; $libDir = Join-Path $WorkDir 'lib'; $cache = Join-Path $WorkDir 'cache'
New-Item -ItemType Directory -Path $proj, $libDir, $cache -Force | Out-Null
$env:DRAGLINT_RULE_CACHE_DIR = $cache
$env:DRAGLINT_RULE_CACHE     = $null
$env:DRAGLINT_RULE_CACHE_WARM = $null

# circular-uses gives the cache something to hold: uCycA <-> uCycB in the interface.
Write-Ascii (Join-Path $proj 'uCycA.pas') @'
unit uCycA;

interface

uses
  uCycB;

function FromA: Integer;

implementation

function FromA: Integer;
begin
  Result:= 1;
end;

end.
'@
Write-Ascii (Join-Path $proj 'uCycB.pas') @'
unit uCycB;

interface

uses
  uCycA;

function FromB: Integer;

implementation

function FromB: Integer;
begin
  Result:= FromA;
end;

end.
'@
Write-Ascii (Join-Path $proj 'Proj.dpr') @'
program Proj;

uses
  uCycA, uCycB;

begin
end.
'@
Write-Ascii (Join-Path $libDir 'uLibOnly.pas') @'
unit uLibOnly;

interface

function LibFn: Integer;

implementation

function LibFn: Integer;
begin
  Result:= 7;
end;

end.
'@
$lib = Join-Path $WorkDir 'lib.sqlite'
$idxL = & $exePath index $libDir --db $lib 2>&1 | Out-String
Check 'SANITY: library fixture indexed' ($LASTEXITCODE -eq 0) $idxL

$db  = Join-Path $WorkDir 'proj.sqlite'
$dpr = Join-Path $proj 'Proj.dpr'
function CacheFiles { @(Get-ChildItem $cache -Filter 'rules-*.json' -ErrorAction SilentlyContinue) }
function CacheState {
  $errF = Join-Path $WorkDir 'lint.err'
  $env:DRAGLINT_PROFILE = '1'
  $null = & $exePath lint (Join-Path $proj 'uCycA.pas') --db $db --library-db $lib --rules-dir $rules --json 2>$errF | Out-String
  $env:DRAGLINT_PROFILE = $null
  $prof = Get-Content $errF -Raw
  if ($prof -match 'rule-cache: (hit|miss|skipped)') { $Matches[1] } else { '(none)' }
}

# --- B0: the default warms in the run -------------------------------------------
$out0 = & $exePath index --project $dpr --db $db --library-db $lib 2>&1 | Out-String
Check 'SANITY: project fixture indexed' ($LASTEXITCODE -eq 0) $out0
Check 'B0 default: warmed in the run, nothing in the background' (($out0 -match 'rule-cache: warmed \d+ finding') -and ($out0 -notmatch 'warming in the background') -and ((CacheFiles).Count -eq 1)) (($out0 -split "`n" | Where-Object { $_ -match 'rule-cache' }) -join ' | ')

# --- B1..B3: background on request -----------------------------------------------
Get-ChildItem $cache -File | Remove-Item -Force
$out1 = & $exePath index --project $dpr --db $db --library-db $lib --rule-cache-warm background 2>&1 | Out-String
$warmPid = 0
if ($out1 -match 'rule-cache: warming in the background \(pid (\d+)\)') { $warmPid = [int]$Matches[1] }
Check 'B1 --rule-cache-warm background: says it is warming in the background, with a pid' ($warmPid -gt 0) (($out1 -split "`n" | Where-Object { $_ -match 'rule-cache' }) -join ' | ')

$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline -and ((CacheFiles).Count -eq 0 -or ($warmPid -gt 0 -and (Get-Process -Id $warmPid -ErrorAction SilentlyContinue)))) {
  Start-Sleep -Milliseconds 250
}
Check 'B2 the background warm wrote the cache entry and exited' (((CacheFiles).Count -eq 1) -and -not ($warmPid -gt 0 -and (Get-Process -Id $warmPid -ErrorAction SilentlyContinue))) "cache files: $((CacheFiles).Count)"
$state3 = CacheState
Check 'B3 the next lint is a HIT' ($state3 -eq 'hit') "state: $state3"

# --- B4: off --------------------------------------------------------------------
Get-ChildItem $cache -File | Remove-Item -Force
$out4 = & $exePath index --project $dpr --db $db --library-db $lib --rule-cache-warm off 2>&1 | Out-String
Check 'B4 --rule-cache-warm off: says it did not warm, starts nothing' (($LASTEXITCODE -eq 0) -and ($out4 -match 'rule-cache: not warmed \(--rule-cache-warm off\)') -and ($out4 -notmatch 'warming in the background')) (($out4 -split "`n" | Where-Object { $_ -match 'rule-cache' }) -join ' | ')
Start-Sleep -Seconds 2
Check 'B4 ... and no cache entry appears' ((CacheFiles).Count -eq 0) "cache files: $((CacheFiles).Count)"

# --- B5: wait ---------------------------------------------------------------------
$out5 = & $exePath index --project $dpr --db $db --library-db $lib --rule-cache-warm wait 2>&1 | Out-String
Check 'B5 --rule-cache-warm wait: warmed in the run' (($LASTEXITCODE -eq 0) -and ($out5 -match 'rule-cache: warmed \d+ finding') -and ((CacheFiles).Count -eq 1)) (($out5 -split "`n" | Where-Object { $_ -match 'rule-cache' }) -join ' | ')

# --- B6: a value that is not a mode --------------------------------------------
$out6 = & $exePath index --project $dpr --db $db --library-db $lib --rule-cache-warm later 2>&1 | Out-String
Check 'B6 --rule-cache-warm later: exit 2, naming the modes' (($LASTEXITCODE -eq 2) -and ($out6 -match 'background, wait or off')) $out6

# --- B7/B8: the verb by hand -----------------------------------------------------
Get-ChildItem $cache -File | Remove-Item -Force
$out7 = & $exePath warm-rule-cache --db $db --library-db $lib 2>&1 | Out-String
Check 'B7 warm-rule-cache --db: exit 0, warmed' (($LASTEXITCODE -eq 0) -and ($out7 -match 'rule-cache: warmed \d+ finding') -and ((CacheFiles).Count -eq 1)) $out7
$out8 = & $exePath warm-rule-cache 2>&1 | Out-String
Check 'B8 warm-rule-cache without --db: exit 2' ($LASTEXITCODE -eq 2) $out8

# --- B9/B10: one background warm per database ----------------------------------
# A stand-in for a running warm: the same engine image, alive until stopped
# (`index --watch` loops). Its pid goes in the marker a warm leaves beside the DB.
$marker  = "$db.rule-cache-warm.pid"
$watchDb = Join-Path $WorkDir 'watch.sqlite'
$stale   = Start-Process -FilePath $exePath -ArgumentList @('index', "`"$libDir`"", '--db', "`"$watchDb`"", '--watch', '--interval', '60') -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 2
[IO.File]::WriteAllText($marker, "$($stale.Id)")
$null = & $exePath warm-rule-cache --detached --db $db --library-db $lib 2>&1 | Out-String
$stale.Refresh()
Check 'B9 the previous warm of the same database (same engine image) is stopped' ($stale.HasExited) "pid $($stale.Id) still running"
Check 'B9 ... and the marker is gone once the warm finished' (-not (Test-Path $marker)) ''
if (-not $stale.HasExited) { Stop-Process -Id $stale.Id -Force -ErrorAction SilentlyContinue }

$foreign = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60') -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 1
[IO.File]::WriteAllText($marker, "$($foreign.Id)")
$null = & $exePath warm-rule-cache --detached --db $db --library-db $lib 2>&1 | Out-String
$foreign.Refresh()
Check 'B10 a process of another program under the recorded pid is left running' (-not $foreign.HasExited) ''
Stop-Process -Id $foreign.Id -Force -ErrorAction SilentlyContinue

# --- B11/B12: the variable sets the default --------------------------------------
$env:DRAGLINT_RULE_CACHE_WARM = 'Background'
$out11 = & $exePath index --project $dpr --db $db --library-db $lib 2>&1 | Out-String
$pid11 = 0
if ($out11 -match 'rule-cache: warming in the background \(pid (\d+)\)') { $pid11 = [int]$Matches[1] }
Check 'B11 DRAGLINT_RULE_CACHE_WARM=Background: the run warms in the background' (($LASTEXITCODE -eq 0) -and ($pid11 -gt 0)) (($out11 -split "`n" | Where-Object { $_ -match 'rule-cache' }) -join ' | ')
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline -and $pid11 -gt 0 -and (Get-Process -Id $pid11 -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 250 }
$out11b = & $exePath index --project $dpr --db $db --library-db $lib --rule-cache-warm off 2>&1 | Out-String
Check 'B11 ... and --rule-cache-warm off still wins over it' (($LASTEXITCODE -eq 0) -and ($out11b -match 'rule-cache: not warmed') -and ($out11b -notmatch 'warming in the background')) (($out11b -split "`n" | Where-Object { $_ -match 'rule-cache' }) -join ' | ')
$env:DRAGLINT_RULE_CACHE_WARM = 'later'
$out12 = & $exePath index --project $dpr --db $db --library-db $lib 2>&1 | Out-String
Check 'B12 DRAGLINT_RULE_CACHE_WARM=later: exit 2, naming the variable' (($LASTEXITCODE -eq 2) -and ($out12 -match 'DRAGLINT_RULE_CACHE_WARM takes background, wait or off')) $out12
$env:DRAGLINT_RULE_CACHE_WARM = $null

# --- B13: index --all --jobs N hands the mode to each section's child -----------
# The child re-parses its own arguments, so a flag left off its command line
# does not exist over there: without it a `--jobs 2` run warmed IN the run.
# --jobs 1 (the parent indexes the section itself) is the positive control.
$cfg = Join-Path $WorkDir 'manifest.drag-lint.json'
Write-Ascii $cfg @'
{
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "WarmSection", "db": "warm.sqlite", "include": ["proj\\Proj.dpr"] }
    ]
  }
}
'@
function WaitWarm($o) {
  if ($o -match 'rule-cache: warming in the background \(pid (\d+)\)') {
    $p = [int]$Matches[1]; $dl = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $dl -and (Get-Process -Id $p -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 250 }
  }
}
$out13a = & $exePath index --all --config $cfg --only WarmSection --jobs 1 --rule-cache-warm background 2>&1 | Out-String
Check 'B13 control: index --all --jobs 1 --rule-cache-warm background warms in the background' (($LASTEXITCODE -eq 0) -and ($out13a -match 'warming in the background \(pid \d+\)') -and ($out13a -notmatch 'rule-cache: warmed \d+ finding')) (($out13a -split "`n" | Where-Object { $_ -match 'rule-cache|ERROR' }) -join ' | ')
WaitWarm $out13a
$out13 = & $exePath index --all --config $cfg --only WarmSection --jobs 2 --rule-cache-warm background 2>&1 | Out-String
Check 'B13 index --all --jobs 2 --rule-cache-warm background: the section child warms in the background too' (($LASTEXITCODE -eq 0) -and ($out13 -match 'warming in the background \(pid \d+\)') -and ($out13 -notmatch 'rule-cache: warmed \d+ finding')) (($out13 -split "`n" | Where-Object { $_ -match 'rule-cache|ERROR' }) -join ' | ')
WaitWarm $out13

# --- B14: the same engine started under another SPELLING is still the same image --
# QueryFullProcessImageName reports the long path; a warm started by its 8.3
# short path has that short spelling in ParamStr(0). A text compare called its
# own previous warm "another program" and left it running.
$shortExe = (New-Object -ComObject Scripting.FileSystemObject).GetFile($exePath).ShortPath
if ($shortExe -ieq $exePath) {
  Write-Host '[SKIP] B14 no 8.3 short name for the engine path on this volume' -ForegroundColor Yellow
} else {
  $stale14 = Start-Process -FilePath $exePath -ArgumentList @('index', "`"$libDir`"", '--db', "`"$watchDb`"", '--watch', '--interval', '60') -WindowStyle Hidden -PassThru
  Start-Sleep -Seconds 2
  [IO.File]::WriteAllText($marker, "$($stale14.Id)")
  $null = & $shortExe warm-rule-cache --detached --db $db --library-db $lib 2>&1 | Out-String
  $stale14.Refresh()
  Check 'B14 a warm started by the 8.3 short path stops the previous warm (long-path image)' ($stale14.HasExited) "pid $($stale14.Id) still running; short=$shortExe"
  if (-not $stale14.HasExited) { Stop-Process -Id $stale14.Id -Force -ErrorAction SilentlyContinue }
}
}
finally {
  $env:DRAGLINT_RULE_CACHE_DIR = $null
  $env:DRAGLINT_RULE_CACHE_WARM = $null
  $env:DRAGLINT_PROFILE = $null
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
