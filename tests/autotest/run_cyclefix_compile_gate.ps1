<#
  run_cyclefix_compile_gate.ps1 -- E18 Task 10: the compile gate of `cycles --fix`.

  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing. Every project copy lives under %TEMP%.
  (a) clean demo copy, `--fix --unit demogageport` dry run WITHOUT --no-compile -> exit 0,
      baseline.status = "ok" (top level and in the cycle), baseline.seconds > 0; the text run
      prints `compile: baseline N.N s`.
  (b) DemoConfig.pas line 1 -> `unit DemoConfigX;` -> exit 1, refusals[0].kind = "dirty-baseline",
      an `error E` line in baseline.errors[0], no source file written, no shadow staged.
  (c) --no-compile: accepted by the dry run (baseline "skipped"), refused with --apply (exit 2).
  (d) R4 repairs on canned dcc lines (test seam DRAGLINT_CYCLEFIX_REPAIR_PROBE=<tree>|<errors file>,
      dry run only, tree under %TEMP%): E2015 -> cast through the plan's ancestor; E2003 -> the leaf
      added to the uses of the section holding the line; E2010 -> the pointer type re-emitted from
      the plan. CONTROLS: E2066 alone and E2003 on a name the plan does not provide -> no repair,
      the tree byte-identical.
  (e) DRAGLINT_CYCLEFIX_BREAK=1|2 (test seam, project under %TEMP% only): the staged shadow holds
      the broken line; the REAL build of that tree through the probe (CompileAfter) fails with the
      R4 code, repairs once and builds clean. CONTROL: a break no repair covers -> status "error",
      one build, no repair. The seam is ignored for a project outside %TEMP% / C:\TEMP.
  The platform library is used through a scratch copy only.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [switch]$KeepScratch,
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-gate-$PID",
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
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars) -- the compile gate needs dcc" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library to copy ($LibraryDb)" -ForegroundColor Yellow; exit 0 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Demo = Join-Path $Repo 'circular-demo'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Lib = Join-Path $WorkDir 'library-copy.sqlite'
Copy-Item $LibraryDb $Lib -Force

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
# source files only: a build writes .dcu / .exe / .res next to the project, a refusal must write no SOURCE
function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File -Recurse | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    Sort-Object FullName | ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function Replace-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, [Text.Encoding]::ASCII)
  if (-not $t.Contains($From)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($From, $To), [Text.Encoding]::ASCII)
}
function Line-Of([string]$Path, [int]$No) { return @([IO.File]::ReadAllLines($Path))[$No - 1] }
# A demo copy, indexed; returns @{ Proj; Dproj; Db }
function New-Demo([string]$Tag, [string]$Root = $WorkDir, [scriptblock]$Patch = $null) {
  $proj = Join-Path $Root "$Tag-proj"
  Copy-Tree $Demo $proj
  if ($Patch) { & $Patch $proj }
  $db = Join-Path $Root "$Tag.sqlite"
  & $Exe index --project (Join-Path $proj 'CircularDemo.dproj') --db $db *> (Join-Path $Root "$Tag-index.log")
  return @{ Proj = $proj; Dproj = (Join-Path $proj 'CircularDemo.dproj'); Db = $db }
}
# `cycles --fix` with env vars set for the call only; returns Exit/Out/Err/Json
function Run-Fix([hashtable]$D, [string[]]$Extra, [hashtable]$Env = @{}, [bool]$Json = $true) {
  $errf = Join-Path $WorkDir ("stderr-{0}.txt" -f [guid]::NewGuid().ToString('N'))
  $a = @('cycles', '--fix', '--build-timeout', '1800', '--project', $D.Dproj, '--db', $D.Db, '--library-db', $Lib) + $Extra
  if ($Json) { $a += @('--format', 'json') }
  foreach ($k in $Env.Keys) { Set-Item "Env:$k" $Env[$k] }
  try {
    $out = (& $Exe @a 2>$errf | Out-String)
    $code = $LASTEXITCODE
  } finally { foreach ($k in $Env.Keys) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } }
  $err = if (Test-Path $errf) { [IO.File]::ReadAllText($errf) } else { '' }
  $j = $null
  if ($Json) { try { $j = $out | ConvertFrom-Json } catch { $j = $null } }
  return @{ Exit = $code; Out = $out; Err = $err; Json = $j }
}
# a build tree: the project copy with the shadow laid over it
function New-Tree([string]$Tag, [string]$Proj, [string]$Shadow) {
  $t = Join-Path $WorkDir "$Tag-tree"
  Copy-Tree $Proj $t
  Copy-Item (Join-Path $Shadow '*') $t -Force
  return $t
}
function Write-Canned([string]$Tag, [string[]]$Lines) {
  $f = Join-Path $WorkDir "$Tag-errors.txt"
  [IO.File]::WriteAllText($f, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  return $f
}

$D = New-Demo 'base'
Check 'setup: demo indexed' (Test-Path $D.Db) ''

# ---------------------------------------------------------------- (a) clean baseline
Write-Host '== (a) clean baseline' -ForegroundColor Cyan
$r = Run-Fix $D @('--unit', 'demogageport', '--shadow-out', (Join-Path $WorkDir 'a-shadow'))
Check 'a: exit 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out)"
Check 'a: baseline.status = ok (top level)' ($r.Json.baseline.status -eq 'ok') $r.Out
Check 'a: baseline.seconds > 0' ($r.Json.baseline.seconds -gt 0) $r.Out
Check 'a: the cycle carries baseline.status = ok' (@($r.Json.cycles)[0].baseline.status -eq 'ok') $r.Out
Check 'a: verdict mechanical' (@($r.Json.cycles)[0].verdict -eq 'mechanical') $r.Out
$t = Run-Fix $D @('--unit', 'demogageport', '--shadow-out', (Join-Path $WorkDir 'a-shadow-txt')) -Json $false
Check 'a: text run prints the baseline timing' ($t.Out -match '(?m)^compile: baseline \d+\.\d s') $t.Out

# ---------------------------------------------------------------- (b) dirty baseline
Write-Host '== (b) dirty baseline' -ForegroundColor Cyan
$B = New-Demo 'dirty' -Patch { param($p) Replace-Text (Join-Path $p 'DemoConfig.pas') 'unit DemoConfig;' 'unit DemoConfigX;' }
$before = Get-SrcHash $B.Proj
$shB = Join-Path $WorkDir 'b-shadow'
$r = Run-Fix $B @('--unit', 'demogageport', '--shadow-out', $shB)
Check 'b: exit 1' ($r.Exit -eq 1) "exit=$($r.Exit) $($r.Out)"
Check 'b: refusals[0].kind = dirty-baseline' (@($r.Json.refusals)[0].kind -eq 'dirty-baseline') $r.Out
Check 'b: baseline.status = error' ($r.Json.baseline.status -eq 'error') $r.Out
Check 'b: baseline.errors[0] is a dcc error line' ("$(@($r.Json.baseline.errors)[0])" -match 'error E\d{4}') $r.Out
Check 'b: no source file written' ((Get-SrcHash $B.Proj) -eq $before) ''
Check 'b: nothing staged' (-not (Test-Path $shB) -or @(Get-ChildItem $shB -Recurse -File).Count -eq 0) ''
$t = Run-Fix $B @('--unit', 'demogageport', '--shadow-out', (Join-Path $WorkDir 'b-shadow-txt')) -Json $false
Check 'b: text run: exit 1, names dirty-baseline and the dcc line' (($t.Exit -eq 1) -and $t.Out.Contains('dirty-baseline') -and ($t.Out -match 'error E\d{4}')) $t.Out

# ---------------------------------------------------------------- (c) --no-compile
Write-Host '== (c) --no-compile' -ForegroundColor Cyan
$r = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--shadow-out', (Join-Path $WorkDir 'c-shadow'))
Check 'c: dry run accepts --no-compile (exit 0)' ($r.Exit -eq 0) "exit=$($r.Exit)"
Check 'c: baseline.status = skipped' ($r.Json.baseline.status -eq 'skipped') $r.Out
$r = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--apply')
Check 'c: --apply --no-compile -> exit 2' ($r.Exit -eq 2) "exit=$($r.Exit)"
Check 'c: --apply --no-compile names the rule' ("$($r.Json.error)" -match 'no-compile') $r.Out

# ---------------------------------------------------------------- (e1) BREAK=1 stages the broken cast
Write-Host '== (d/e) BREAK seams and R4 repairs' -ForegroundColor Cyan
$sh1 = Join-Path $WorkDir 'e1-shadow'
$r = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--shadow-out', $sh1) @{ DRAGLINT_CYCLEFIX_BREAK = '1' }
Check 'e1: BREAK=1 dry run exit 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Err)"
Check 'e1: stderr announces TEST BREAK active' ($r.Err.Contains('TEST BREAK active')) $r.Err
$l57 = if (Test-Path (Join-Path $sh1 'DemoUIConnect.pas')) { Line-Of (Join-Path $sh1 'DemoUIConnect.pas') 57 } else { '' }
Check 'e1: the staged line 57 lost its cast' ($l57 -eq '  with Sender as IDemoGagePortSurface do') "[$l57]"

# (d1) canned E2015 (plus the cascade dcc printed for it, measured) -> one cast repair
$tr = New-Tree 'd1' $D.Proj $sh1
$canned = Write-Canned 'd1' @(
  'DemoUIConnect.pas(57): error E2015: Operator not applicable to this operand type [C:\x\CircularDemo.dproj]',
  "DemoUIConnect.pas(60): error E2003: Undeclared identifier: 'Log' [C:\x\CircularDemo.dproj]",
  'DemoUIConnect.pas(61): error E2066: Missing operator or semicolon [C:\x\CircularDemo.dproj]',
  "DemoGagePort.pas(61): error F2063: Could not compile used unit 'DemoUIConnect.pas' [C:\x\CircularDemo.dproj]")
$r = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--shadow-out', (Join-Path $WorkDir 'd1-shadow')) @{
  DRAGLINT_CYCLEFIX_REPAIR_PROBE = "$tr|$canned"; DRAGLINT_CYCLEFIX_BREAK = '1' }
$rep = @(@($r.Json.cycles)[0].repairs)
Check 'd1: stderr announces the probe' ($r.Err.Contains('TEST REPAIR PROBE active')) $r.Err
Check 'd1: exactly one repair' ($rep.Count -eq 1) $r.Out
Check 'd1: repairs[0] = {E2015, DemoUIConnect.pas, 57, cast}' (($rep[0].code -eq 'E2015') -and ("$($rep[0].file)" -like '*DemoUIConnect.pas') -and
  ($rep[0].line -eq 57) -and ("$($rep[0].action)" -match 'TComponent')) ($rep | ConvertTo-Json -Compress)
Check 'd1: line 57 rewritten through TComponent' ((Line-Of (Join-Path $tr 'DemoUIConnect.pas') 57) -eq '  with TComponent(Sender) as IDemoGagePortSurface do') (Line-Of (Join-Path $tr 'DemoUIConnect.pas') 57)

# (d2) canned E2003 on the new interface -> the leaf joins the implementation uses
$sh0 = Join-Path $WorkDir 'd0-shadow'
$null = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--shadow-out', $sh0)
$tr = New-Tree 'd2' $D.Proj $sh0
Replace-Text (Join-Path $tr 'DemoUIConnect.pas') '  DemoGagePort.Untangle; // <-- the edge' '  System.Classes; // <-- the edge'
$canned = Write-Canned 'd2' @("DemoUIConnect.pas(49): error E2003: Undeclared identifier: 'IDemoGagePortSurface' [C:\x\CircularDemo.dproj]")
$r = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--shadow-out', (Join-Path $WorkDir 'd2-shadow')) @{ DRAGLINT_CYCLEFIX_REPAIR_PROBE = "$tr|$canned" }
$rep = @(@($r.Json.cycles)[0].repairs)
Check 'd2: repairs[0] = {E2003, DemoUIConnect.pas, 49, uses}' (($rep.Count -eq 1) -and ($rep[0].code -eq 'E2003') -and ($rep[0].line -eq 49) -and
  ("$($rep[0].action)" -match 'DemoGagePort\.Untangle')) ($rep | ConvertTo-Json -Compress)
$txt = [IO.File]::ReadAllText((Join-Path $tr 'DemoUIConnect.pas'))
$impl = $txt.Substring($txt.IndexOf("`r`nimplementation`r`n"))
Check 'd2: DemoGagePort.Untangle is in the IMPLEMENTATION uses' ($impl -match '(?s)^\r\nimplementation\r\n\r\nuses\r\n  DemoGagePort\.Untangle,\r\n  System\.Classes;') $impl.Substring(0, [Math]::Min(120, $impl.Length))

# (d3) canned E2010 on the pointer assignment -> the pointer type re-emitted
$sh2 = Join-Path $WorkDir 'e2-shadow'
$r = Run-Fix $D @('--unit', 'demoblueprint', '--no-compile', '--shadow-out', $sh2) @{ DRAGLINT_CYCLEFIX_BREAK = '2' }
$intf = Join-Path $sh2 'DemoBlueprint.Interfaces.pas'
$l28 = if (Test-Path $intf) { Line-Of $intf 28 } else { '' }
Check 'e2: BREAK=2 stages the pointer type as a TFunc-style reference' ($l28 -eq '  TDemoBlueprintViewModelCreatePtr = reference to function(pFolderId: Integer): IDemoBlueprintViewModel;') "[$l28]"
$tr = New-Tree 'd3' $D.Proj $sh2
$canned = Write-Canned 'd3' @("DemoBlueprint.ViewModel.pas(81): error E2010: Incompatible types: 'DemoBlueprint.Interfaces.TDemoBlueprintViewModelCreatePtr' and 'Procedure' [C:\x\CircularDemo.dproj]",
  "CircularDemo.dpr(36): error F2063: Could not compile used unit 'DemoBlueprint.ViewModel.pas' [C:\x\CircularDemo.dproj]")
$r = Run-Fix $D @('--unit', 'demoblueprint', '--no-compile', '--shadow-out', (Join-Path $WorkDir 'd3-shadow')) @{ DRAGLINT_CYCLEFIX_REPAIR_PROBE = "$tr|$canned" }
$rep = @(@($r.Json.cycles)[0].repairs)
Check 'd3: repairs[0] = {E2010, DemoBlueprint.ViewModel.pas, 81, pointer type}' (($rep.Count -eq 1) -and ($rep[0].code -eq 'E2010') -and ($rep[0].line -eq 81) -and
  ("$($rep[0].file)" -like '*DemoBlueprint.ViewModel.pas') -and ("$($rep[0].action)" -match 'TDemoBlueprintViewModelCreatePtr')) ($rep | ConvertTo-Json -Compress)
Check 'd3: line 28 re-emitted from the signature' ((Line-Of (Join-Path $tr 'DemoBlueprint.Interfaces.pas') 28) -eq '  TDemoBlueprintViewModelCreatePtr = function(const pFolderId: Integer): IDemoBlueprintViewModel;') (Line-Of (Join-Path $tr 'DemoBlueprint.Interfaces.pas') 28)

# (d4) CONTROLS: another code, or E2003 on a name the plan does not provide -> no repair, no write
$tr = New-Tree 'd4' $D.Proj $sh1
$h4 = Get-SrcHash $tr
foreach ($c in @(
    @('d4a', 'DemoUIConnect.pas(61): error E2066: Missing operator or semicolon [C:\x\CircularDemo.dproj]'),
    @('d4b', "DemoUIConnect.pas(60): error E2003: Undeclared identifier: 'Log' [C:\x\CircularDemo.dproj]"),
    @('d4c', "DemoUIConnect.pas(57): error E2029: ')' expected but identifier 'X' found [C:\x\CircularDemo.dproj]"))) {
  $canned = Write-Canned $c[0] @($c[1])
  $r = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--shadow-out', (Join-Path $WorkDir "$($c[0])-shadow")) @{ DRAGLINT_CYCLEFIX_REPAIR_PROBE = "$tr|$canned" }
  Check "$($c[0]): no repair for [$($c[1].Substring(0, 45))...]" (($r.Exit -eq 0) -and (@(@($r.Json.cycles)[0].repairs).Count -eq 0)) $r.Out
}
Check 'd4: the tree is byte-identical (no retry, no write)' ((Get-SrcHash $tr) -eq $h4) ''

# (e) the REAL build through CompileAfter: break -> R4 repair -> clean build
foreach ($c in @(@('e1b', 'demogageport', '1', 'E2015'), @('e2b', 'demoblueprint', '2', 'E2010'))) {
  $sh = Join-Path $WorkDir "$($c[0])-stage"
  $null = Run-Fix $D @('--unit', $c[1], '--no-compile', '--shadow-out', $sh) @{ DRAGLINT_CYCLEFIX_BREAK = $c[2] }
  $tr = New-Tree $c[0] $D.Proj $sh
  $r = Run-Fix $D @('--unit', $c[1], '--no-compile', '--shadow-out', (Join-Path $WorkDir "$($c[0])-shadow")) @{
    DRAGLINT_CYCLEFIX_REPAIR_PROBE = $tr; DRAGLINT_CYCLEFIX_BREAK = $c[2] }
  $cy = @($r.Json.cycles)[0]
  Check "$($c[0]): real dcc: compile.status = ok after the repair" ($cy.compile.status -eq 'ok') ($cy.compile | ConvertTo-Json -Compress -Depth 4)
  Check "$($c[0]): repairs[0].code = $($c[3]), two builds" ((@($cy.repairs).Count -ge 1) -and (@($cy.repairs)[0].code -eq $c[3]) -and ($cy.compile.builds -eq 2)) ($cy | ConvertTo-Json -Compress -Depth 4)
  Check "$($c[0]): the after build is timed" ($cy.compile.seconds -gt 0) ''
}
# CONTROL: a break no repair covers -> one build, error, no repair
$sh = Join-Path $WorkDir 'e3-stage'
$null = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--shadow-out', $sh)
$tr = New-Tree 'e3' $D.Proj $sh
Replace-Text (Join-Path $tr 'DemoUIConnect.pas') '  if not Supports(Sender, IDemoGagePortSurface) then' '  if not Supports(Sender, IDemoGagePortSurface) the'
$r = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--shadow-out', (Join-Path $WorkDir 'e3-shadow')) @{ DRAGLINT_CYCLEFIX_REPAIR_PROBE = $tr }
$cy = @($r.Json.cycles)[0]
Check 'e3 control: status error, one build, no repair' (($cy.compile.status -eq 'error') -and ($cy.compile.builds -eq 1) -and (@($cy.repairs).Count -eq 0)) ($cy | ConvertTo-Json -Compress -Depth 4)
Check 'e3 control: compile.errors carry {file,line,code,message}' ((@($cy.compile.errors).Count -ge 1) -and (@($cy.compile.errors)[0].code -match '^[EF]\d{4}$') -and (@($cy.compile.errors)[0].line -gt 0)) ($cy.compile | ConvertTo-Json -Compress -Depth 4)

# (f) the BREAK seam is ignored outside %TEMP% / C:\TEMP
$outRoot = Join-Path $env:LOCALAPPDATA "drag-lint-cyclefix-gate-$PID"
try {
  $O = New-Demo 'outside' -Root $outRoot
  $shO = Join-Path $WorkDir 'f-shadow'
  $r = Run-Fix $O @('--unit', 'demogageport', '--no-compile', '--shadow-out', $shO) @{ DRAGLINT_CYCLEFIX_BREAK = '1' }
  Check 'f: outside TEMP: exit 0, no TEST BREAK notice' (($r.Exit -eq 0) -and -not $r.Err.Contains('TEST BREAK')) $r.Err
  $lo = if (Test-Path (Join-Path $shO 'DemoUIConnect.pas')) { Line-Of (Join-Path $shO 'DemoUIConnect.pas') 57 } else { '' }
  Check 'f: outside TEMP: the staged line keeps its cast' ($lo -eq '  with TComponent(Sender) as IDemoGagePortSurface do') "[$lo]"
  # the probe is ignored for a tree outside TEMP (its POSITIVE control is d1: same lines, tree under TEMP)
  Copy-Item (Join-Path $sh1 'DemoUIConnect.pas') (Join-Path $O.Proj 'DemoUIConnect.pas') -Force
  $hO = Get-SrcHash $O.Proj
  $canned = Write-Canned 'f' @('DemoUIConnect.pas(57): error E2015: Operator not applicable to this operand type')
  $r = Run-Fix $D @('--unit', 'demogageport', '--no-compile', '--shadow-out', (Join-Path $WorkDir 'f-shadow2')) @{ DRAGLINT_CYCLEFIX_REPAIR_PROBE = "$($O.Proj)|$canned" }
  Check 'f: probe tree outside TEMP: no notice, no repair, no write' ((-not $r.Err.Contains('TEST REPAIR PROBE')) -and
    (@(@($r.Json.cycles)[0].repairs).Count -eq 0) -and ((Get-SrcHash $O.Proj) -eq $hO)) $r.Err
} finally {
  if (Test-Path $outRoot) { [IO.Directory]::Delete($outRoot, $true) }
}

Write-Host ''
Remove-Scratch
if ($script:Failed) { Write-Host "FAILED ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS ($script:Passed)" -ForegroundColor Green
exit 0
