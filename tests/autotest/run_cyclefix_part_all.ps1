<#
  run_cyclefix_part_all.ps1 -- E18 Task 12: `cycles --fix --part all --apply` loops
  plan -> apply -> compile -> re-index until the selected circular group is gone.

  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing. Every project copy and DB copy lives under
  the work dir (default %TEMP%); the platform library is used through a scratch copy only; no real
  _D-RAG DB is touched.
  (a) the demo, default group (cycle 1): 2 iterations -- Part A, then Part B (edge
      demoaudit->democonfig) -- each compiled and verified, exit 0, `cycles` lists 2 groups after.
  (b) --unit demogageport --part all --apply: 1 iteration, exit 0.
  (c) --unit demoblueprint --part all --apply: 1 iteration, exit 0; `cycles` then prints
      "No circular unit dependencies found."; the edited demo program prints what the untouched one
      prints (scorer criterion 2, -RunExe).
  (d) score-cycle-playbook.ps1 -RunExe, original vs a copy edited by the
      cycle-1 Part A apply (--no-backup, so no .BCK files) against the report of `cycles --plan`
      (no platform library, so the report names cycle 1's Part A and nothing else to create): 4/4.
      Iteration 1 of (a) wrote the same files as this apply.
  (e) --part all without --apply -> exit 2 with the stale-line-numbers sentence, nothing written.
  (f) a failing iteration ends the loop: DRAGLINT_CYCLEFIX_BREAK=3 -> exit 1, cycles[] holds the
      failing iteration only, rolled back, tree byte-identical.
  (g) a refused group (no platform library, so no edge of demouiconnect/demogageport is cuttable):
      exit 1, cycles[0] refused, nothing written.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [switch]$KeepScratch,
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-part-all-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [string]$Rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
# E18 T13: removes this run's scratch (WorkDir) however the run ends; kept only on failure when
# -KeepScratch is passed (the path is printed).
function Remove-Scratch {
  if ($script:Failed -and $KeepScratch) { Write-Host "scratch kept: $WorkDir" -ForegroundColor Yellow; return }
  Set-Location -LiteralPath $env:TEMP
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
trap { $script:Failed = $true; Remove-Scratch; break }

$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars) -- --apply needs dcc" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library to copy ($LibraryDb)" -ForegroundColor Yellow; exit 0 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Demo = Join-Path $Repo 'circular-demo'
$Scorer = Join-Path $Repo 'tools\score-cycle-playbook.ps1'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Lib = Join-Path $WorkDir 'library-copy.sqlite'
Copy-Item $LibraryDb $Lib -Force

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
function Get-TreeHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File -Recurse | Where-Object {
      $_.FullName -notmatch '\\(Win32|Win64|__history|__recovery)\\' -and
      $_.Extension -notmatch '^\.(dcu|exe|res|identcache|local|stat|dsk|map|rsm|drc)$' } |
    Sort-Object FullName | ForEach-Object { '{0}={1}' -f $_.FullName.Substring($Dir.Length), (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function New-Demo([string]$Tag) {
  $proj = Join-Path $WorkDir "$Tag-proj"
  Copy-Tree $Demo $proj
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $proj 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir "$Tag-index.log")
  return @{ Proj = $proj; Dproj = (Join-Path $proj 'CircularDemo.dproj'); Db = $db }
}
function Run-Fix([hashtable]$D, [string[]]$Extra, [hashtable]$Env = @{}, [bool]$Json = $true, [string]$LibArg = $Lib) {
  $errf = Join-Path $WorkDir ("stderr-{0}.txt" -f [guid]::NewGuid().ToString('N'))
  $a = @('cycles', '--fix', '--project', $D.Dproj, '--db', $D.Db, '--library-db', $LibArg) + $Extra
  if ($Json) { $a += @('--format', 'json') }
  foreach ($k in $Env.Keys) { Set-Item "Env:$k" $Env[$k] }
  try {
    $out = (& $Exe @a 2>$errf | Out-String)
    $code = $LASTEXITCODE
  } finally { foreach ($k in $Env.Keys) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } }
  $err = if (Test-Path $errf) { [IO.File]::ReadAllText($errf) } else { '' }
  $j = $null
  if ($Json) { try { $j = $out | ConvertFrom-Json } catch { $j = $null } }
  return @{ Exit = $code; Out = $out; Err = $err; Json = $j; Log = '' }
}
function Cycles-Text($D) { return (& $Exe cycles --db $D.Db 2>$null | Out-String) }

# ---------------------------------------------------------------- (a) cycle 1: Part A then Part B
Write-Host '== (a) default group (cycle 1): Part A, Part B' -ForegroundColor Cyan
$A = New-Demo 'a'
Check 'setup: demo indexed' (Test-Path $A.Db) ''
$r = Run-Fix $A @('--part', 'all', '--apply')
$cys = @($r.Json.cycles)
$cysDoc = $r.Out.Trim()
Check 'a: exit 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out) $($r.Err)"
Check 'a: document is cycle-fix/1, mode apply, part all' (($r.Json.schema -eq 'cycle-fix/1') -and ($r.Json.mode -eq 'apply') -and ($r.Json.part -eq 'all')) $r.Out
Check 'a: cycles[] has 2 iterations' ($cys.Count -eq 2) "count=$($cys.Count) $($r.Out)"
Check 'a: iterations = 2' ($r.Json.iterations -eq 2) $r.Out
Check 'a: iteration 1 is Part A' ($cys[0].part -eq 'a') ($cys[0] | ConvertTo-Json -Compress -Depth 3)
Check 'a: iteration 2 is Part B' ($cys[1].part -eq 'b') ($cys[1] | ConvertTo-Json -Compress -Depth 3)
Check 'a: Part B cuts demoaudit->democonfig' ("$($cys[1].edge)" -match 'demoaudit\s*->\s*democonfig') "edge=$($cys[1].edge)"
Check 'a: every iteration wrote files, compiled ok and verified' (@($cys | Where-Object { (@($_.written).Count -gt 0) -and ($_.compile.status -eq 'ok') -and ($_.verified -eq $true) }).Count -eq 2) ($cys | ForEach-Object { "$($_.part):$($_.compile.status):$($_.verified)" })
Check 'a: ok = true, exit_code 0' (($r.Json.ok -eq $true) -and ($r.Json.exit_code -eq 0)) $r.Out
$cyc = Cycles-Text $A
Check 'a: cycles on the re-indexed DB: group 1 gone, 2 groups left' (($cyc -match '(?m)^2 circular unit group\(s\) found:') -and ($cyc -notmatch 'demologger')) $cyc

# ---------------------------------------------------------------- (b)/(c) the other two groups
Write-Host '== (b) --unit demogageport --part all' -ForegroundColor Cyan
$r = Run-Fix $A @('--unit', 'demogageport', '--part', 'all', '--apply')
Check 'b: exit 0, 1 iteration, verified' (($r.Exit -eq 0) -and (@($r.Json.cycles).Count -eq 1) -and (@($r.Json.cycles)[0].verified -eq $true)) "exit=$($r.Exit) $($r.Out) $($r.Err)"
Write-Host '== (c) --unit demoblueprint --part all' -ForegroundColor Cyan
$r = Run-Fix $A @('--unit', 'demoblueprint', '--part', 'all', '--apply')
Check 'c: exit 0, 1 iteration, verified' (($r.Exit -eq 0) -and (@($r.Json.cycles).Count -eq 1) -and (@($r.Json.cycles)[0].verified -eq $true)) "exit=$($r.Exit) $($r.Out) $($r.Err)"
$cyc = Cycles-Text $A
Check 'c: final cycles prints "No circular unit dependencies found."' ($cyc -match 'No circular unit dependencies found\.') $cyc

# ---------------------------------------------------------------- (d) the scorer
Write-Host '== (d) score-cycle-playbook.ps1 -RunExe (Part A report)' -ForegroundColor Cyan
$P = New-Demo 'p'
$planTxt = Join-Path $WorkDir 'part-a-report.md'
(& $Exe cycles --plan --db $P.Db --library-db none 2>$null | Out-String) | Set-Content $planTxt -Encoding ASCII
$O = Join-Path $WorkDir 'p-original'
Copy-Tree $Demo $O
$ra = Run-Fix $P @('--unit', 'demologger', '--apply', '--no-backup')
Check 'd: setup: the Part A apply (one iteration) exit 0' ($ra.Exit -eq 0) "exit=$($ra.Exit) $($ra.Out) $($ra.Err)"
$partAFiles = @(@($ra.Json.cycles)[0].written | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object)
$allFiles = @(@($cys[0].written) | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object)
Check 'd: iteration 1 of (a) wrote the same files as the single Part A apply' (($partAFiles -join ',') -eq ($allFiles -join ',')) "$($partAFiles -join ',') vs $($allFiles -join ',')"
$scoreOut = (& pwsh -NoProfile -File $Scorer -Original $O -Edited $P.Proj -Report $planTxt -Project 'CircularDemo.dproj' -RunExe -Exe $Exe 2>&1 | Out-String)
Check 'd: SCORE: PASS 4/4' ($scoreOut -match 'SCORE: PASS 4/4') $scoreOut

# ---------------------------------------------------------------- (e) --part all needs --apply
Write-Host '== (e) --part all without --apply' -ForegroundColor Cyan
$E = New-Demo 'e'
$hE = Get-TreeHash $E.Proj
$r = Run-Fix $E @('--part', 'all')
Check 'e: exit 2' ($r.Exit -eq 2) "exit=$($r.Exit) $($r.Out)"
Check 'e: names --apply and the stale line numbers' (("$($r.Json.error)" -match '--apply') -and ("$($r.Json.error)" -match 'stale line numbers')) $r.Out
Check 'e: nothing written' ((Get-TreeHash $E.Proj) -eq $hE) ''

# ---------------------------------------------------------------- (f) a failing iteration ends the loop
Write-Host '== (f) a failing iteration stops the loop' -ForegroundColor Cyan
$F = New-Demo 'f'
$hF = Get-TreeHash $F.Proj
$r = Run-Fix $F @('--part', 'all', '--apply') @{ DRAGLINT_CYCLEFIX_BREAK = '3' }
Check 'f: exit 1' ($r.Exit -eq 1) "exit=$($r.Exit) $($r.Out) $($r.Err)"
Check 'f: cycles[] holds the failing iteration only, rolled back' ((@($r.Json.cycles).Count -eq 1) -and (@($r.Json.cycles)[0].rolled_back -eq $true)) $r.Out
Check 'f: refusal compile-error' (@(@($r.Json.cycles)[0].refusals | Where-Object { $_.kind -eq 'compile-error' }).Count -eq 1) $r.Out
Check 'f: stopped says iteration 1 ended' ("$($r.Json.stopped)" -match 'iteration 1') $r.Out
Check 'f: tree byte-identical' ((Get-TreeHash $F.Proj) -eq $hF) ''

# ---------------------------------------------------------------- (g) a refused group
Write-Host '== (g) a refused group: nothing cuttable' -ForegroundColor Cyan
$G = New-Demo 'g'
$hG = Get-TreeHash $G.Proj
$r = Run-Fix $G @('--unit', 'demouiconnect', '--part', 'all', '--apply') @{} $true 'none'
Check 'g: exit 1' ($r.Exit -eq 1) "exit=$($r.Exit) $($r.Out) $($r.Err)"
Check 'g: cycles[0] verdict refused, nothing written' ((@($r.Json.cycles).Count -eq 1) -and (@($r.Json.cycles)[0].verdict -eq 'refused')) $r.Out
Check 'g: tree byte-identical' ((Get-TreeHash $G.Proj) -eq $hG) ''

# ---------------------------------------------------------------- (h)-(k) the child protocol (test seams, project under TEMP)
# DRAGLINT_CYCLEFIX_ALL_CHILD runs a stub in place of the engine for the iteration child; the stub forwards
# every other command (the group listing) to the real exe. DRAGLINT_CYCLEFIX_ALL_PLANT plants a stale output file.
Write-Host '== (h) a failed child launch never reads a stale file' -ForegroundColor Cyan
$H = New-Demo 'h'
$hH = Get-TreeHash $H.Proj
$stale = Join-Path $WorkDir 'stale-success.json'
[IO.File]::WriteAllText($stale, ($cysDoc + "`r`n"), [Text.Encoding]::ASCII)
$r = Run-Fix $H @('--part', 'all', '--apply') @{ DRAGLINT_CYCLEFIX_ALL_CHILD = 'C:\no-such-dir\drag-lint.exe'; DRAGLINT_CYCLEFIX_ALL_PLANT = $stale }
Check 'h: exit 2, not the planted success' (($r.Exit -eq 2) -and ($r.Json.ok -eq $false)) "exit=$($r.Exit) $($r.Out)"
Check 'h: no iteration was recorded from the stale file' (@($r.Json.cycles).Count -eq 0) $r.Out
Check 'h: error says the loop could not continue' ("$($r.Json.error)" -ne '') $r.Out
Check 'h: tree byte-identical' ((Get-TreeHash $H.Proj) -eq $hH) ''

$stub = Join-Path $WorkDir 'stub-child.bat'
$bat = @('@echo off',
  'if "%~3"=="--apply" goto it',
  '"%STUB_REAL%" %*',
  'exit /b %errorlevel%',
  ':it',
  'echo %* >> "%STUB_LOG%"',
  'if "%STUB_MODE%"=="empty" echo {"schema":"cycle-fix/1","cycles":[]}',
  'if "%STUB_MODE%"=="refused" echo {"schema":"cycle-fix/1","cycles":[],"refusals":[{"kind":"dirty-baseline","symbol":"","file":"","line":0,"reason":"stub"}],"ok":false,"exit_code":1}',
  'if "%STUB_MODE%"=="noop" echo {"schema":"cycle-fix/1","cycles":[{"n":1,"part":"a","edge":"stub->stub","written":["x.pas"],"verified":true,"rolled_back":false}],"ok":true,"exit_code":0}',
  'if "%STUB_MODE%"=="refused" exit /b 1',
  'exit /b 0')
[IO.File]::WriteAllText($stub, (($bat -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
function Run-Stub([string]$Tag, [string]$Mode, [string[]]$Extra = @()) {
  $D = New-Demo $Tag
  $log = Join-Path $WorkDir "$Tag-stub.log"
  $r = Run-Fix $D (@('--part', 'all', '--apply') + $Extra) @{ DRAGLINT_CYCLEFIX_ALL_CHILD = $stub; STUB_REAL = $Exe; STUB_MODE = $Mode; STUB_LOG = $log }
  $r.Log = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  return $r
}

Write-Host '== (i) a refused iteration is kept in cycles[]' -ForegroundColor Cyan
$r = Run-Stub 'i' 'refused'
Check 'i: exit 1 (the child''s code)' ($r.Exit -eq 1) "exit=$($r.Exit) $($r.Out)"
Check 'i: cycles[] holds a synthetic refused entry with the refusal' ((@($r.Json.cycles).Count -eq 1) -and (@($r.Json.cycles)[0].verdict -eq 'refused') -and (@(@($r.Json.cycles)[0].refusals)[0].kind -eq 'dirty-baseline')) $r.Out

Write-Host '== (j) a child that exits 0 with no cycles[] is a failure' -ForegroundColor Cyan
$r = Run-Stub 'j' 'empty'
Check 'j: exit 2' (($r.Exit -eq 2) -and ($r.Json.ok -eq $false)) "exit=$($r.Exit) $($r.Out)"
Check 'j: error names the empty child' ("$($r.Json.error)" -match 'planned no group') $r.Out

Write-Host '== (k) an iteration that leaves the group unchanged: no edge is cuttable; target flags are forwarded' -ForegroundColor Cyan
$r = Run-Stub 'k' 'noop' @('--library-db', $Lib, '--rules-dir', $WorkDir)
Check 'k: exit 1' ($r.Exit -eq 1) "exit=$($r.Exit) $($r.Out)"
Check 'k: stopped = no edge is cuttable, after 1 iteration' (("$($r.Json.stopped)" -match 'no edge is cuttable') -and ($r.Json.iterations -eq 1)) $r.Out
Check 'k: the child got both --library-db and --rules-dir' ((([regex]::Matches($r.Log, '--library-db')).Count -eq 2) -and $r.Log.Contains('--rules-dir')) $r.Log

Write-Host ''
Remove-Scratch
if ($script:Failed) { Write-Host "FAILED ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS ($script:Passed)" -ForegroundColor Green
exit 0
