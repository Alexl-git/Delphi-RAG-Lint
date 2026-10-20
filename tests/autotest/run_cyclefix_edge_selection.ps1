<#
  run_cyclefix_edge_selection.ps1 -- E18 Task 7: edge selection R3 across the
  recipes, and the `mvBase` gate F5.

  R3: an implementation-only cycle evaluates EVERY edge; the candidates rank
  move-globals, then routine-call inversion (R1), then member hand-over (R2);
  ties within a recipe go to the fewest surface members, then the fewest refs.
  `### Recommended fix` lists every edge with its recipe or its reason.
  F5: a base-class extraction (Part A, `mvBase`) is allowed only when every
  switched site is a const / value parameter whose body uses it only to read
  a member or to compare it with nil; otherwise Part A refuses `base-class`
  naming the site.

  Asserts, on COPIES:
    (a) circular-demo with a COPY of the platform library: cycle 2's
        Recommended fix names `demouiconnect -> demogageport` with
        `recipe: member hand-over`; cycle 3 names
        `demoblueprint -> demoblueprint.viewmodel` with
        `recipe: routine-call inversion`; cycle 1 Part B still cuts
        `demoaudit -> democonfig` (move globals wins); cycle 1 (Part A) is NOT
        refused for `base-class` (plan dump).
    (b) tests\fixtures\cyclefix\basevar (the demo's 4 units, DemoLogSession
        takes `var pSession: TDemoSession`): Part A prints
        `refused: base-class` on a line naming `DemoLogger.pas:`, and the plan
        dump lists `base-class`.
    (c)-(e) basevar variants with a const parameter: a bare use in the body
        (basebody), a nil test inside a string beside a bare use on one line
        (basestring: each occurrence is classified by its own column), and an
        abstract method with no body to check (basenobody: fail closed).
    (f) tests\fixtures\cyclefix\tiebreak: three move-globals edges where
        members-then-refs, refs alone and cost alone each pick a different edge.
    (g) tests\fixtures\cyclefix\partbr1: Part B predicts the routine-call
        inversion cut and names its recipe.
  POSITIVE CONTROL: both copies index with 0 errors and the plain report finds
  the 4-unit group with interface coupling.

  THE PLATFORM LIBRARY: never opened in place. It is copied into the $PID
  scratch dir and passed with --library-db; size + mtime of the real library
  DBs are compared before and after. Without -LibraryDb on disk: SKIP, exit 0.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-edgesel-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Get-LibStamp {
  return (@(Get-ChildItem 'C:\Projects\.drag-lint' -Filter 'library-*.sqlite' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { '{0}={1}@{2:o}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc }) -join ' ')
}

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

# `cycles` (with pExtra) on pDb, stdout to a file; the plan dump (DRAGLINT_TEST_DUMP_PLAN) parsed per cycle.
function Get-Cycles([string]$Db, [string]$Tag, [string[]]$Extra) {
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $dump = Join-Path $WorkDir "dump-$Tag.txt"
  $env:DRAGLINT_TEST_DUMP_PLAN = $dump
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList (@('cycles', '--db', ('"' + $Db + '"')) + $Extra) `
      -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "cycles-$Tag.err")
  } finally {
    $env:DRAGLINT_TEST_DUMP_PLAN = $null
  }
  $byCycle = @{}
  if (Test-Path $dump) {
    foreach ($l in [IO.File]::ReadAllLines($dump)) {
      $h = @{}
      foreach ($kv in ($l -split "`t")) { $i = $kv.IndexOf('='); if ($i -gt 0) { $h[$kv.Substring(0, $i)] = $kv.Substring($i + 1) } }
      if ($h.ContainsKey('cycle')) { $byCycle[[int]$h['cycle']] = $h }
    }
  }
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Dump = $byCycle }
}

# The lines of `## Cycle <No>`, optionally only those under `### <Section>` (up to the next `### `).
function Get-Block([string]$Plan, [int]$No, [string]$Section = '') {
  $out = @(); $inCycle = $false; $inSect = ($Section -eq '')
  foreach ($l in @($Plan -split "`r?`n")) {
    if ($l -match '^## Cycle (\d+):') { $inCycle = ([int]$Matches[1] -eq $No); continue }
    if (-not $inCycle) { continue }
    if ($Section -ne '' -and $l.StartsWith('### ')) { $inSect = $l.StartsWith('### ' + $Section); continue }
    if ($inSect) { $out += $l }
  }
  return ($out -join "`n")
}

function Index-Copy([string]$Dir, [string]$Dproj, [string]$Tag, [int]$Units) {
  $db = Join-Path $Dir "$Tag.sqlite"
  $idx = & $Exe index --project (Join-Path $Dir $Dproj) --db $db 2>&1 | Out-String
  Check "${Tag}: SANITY the $Units units indexed with 0 errors" `
    (([regex]::Matches($idx, 'Demo[\w.]+\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')).Count -eq $Units) $idx
  $report = & $Exe cycles --db $db 2>&1 | Out-String
  Check "${Tag}: POSITIVE CONTROL plain report finds the 4-unit group with interface coupling" `
    ($report -match '\[4 units\].*has interface coupling') $report
  return $db
}

$stampBefore = Get-LibStamp
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Lib = Join-Path $WorkDir 'library-copy.sqlite'
Push-Location $WorkDir
try {
  Write-Host '== setup: library copy' -ForegroundColor Cyan
  Copy-Item $LibraryDb $Lib -Force

  Write-Host '== (a) circular-demo: R3 picks one edge per cycle, by recipe preference' -ForegroundColor Cyan
  $demoDir = Join-Path $WorkDir 'demo'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demoDir
  $demoDb = Index-Copy $demoDir 'CircularDemo.dproj' 'demo' 10
  $r = Get-Cycles $demoDb 'demo' @('--plan', '--library-db', ('"' + $Lib + '"'))
  Check 'demo: cycles --plan exit 0' ($r.Exit -eq 0) "exit $($r.Exit)"

  $fix2 = Get-Block $r.Out 2 'Recommended fix'
  Check 'cycle 2: cuts demouiconnect -> demogageport' `
    ($fix2.Contains('Cut the edge `demouiconnect -> demogageport`')) $fix2
  Check 'cycle 2: lists demouiconnect -> demogageport with recipe: member hand-over' `
    ($fix2 -match '(?m)^- `demouiconnect -> demogageport`: recipe: member hand-over') $fix2
  Check 'cycle 2: the other edge keeps its per-edge reason' `
    ($fix2 -match '(?m)^- `demogageport -> demouiconnect`: not mechanical: ') $fix2

  $fix3 = Get-Block $r.Out 3 'Recommended fix'
  Check 'cycle 3: cuts demoblueprint -> demoblueprint.viewmodel' `
    ($fix3.Contains('Cut the edge `demoblueprint -> demoblueprint.viewmodel`')) $fix3
  Check 'cycle 3: lists demoblueprint -> demoblueprint.viewmodel with recipe: routine-call inversion' `
    ($fix3 -match '(?m)^- `demoblueprint -> demoblueprint\.viewmodel`: recipe: routine-call inversion') $fix3
  Check 'cycle 3: lists all three edges' `
    (([regex]::Matches($fix3, '(?m)^- `demo[\w.]+ -> demo[\w.]+`: ')).Count -eq 3) $fix3

  $partB = Get-Block $r.Out 1 'Part B'
  Check 'cycle 1 Part B: move globals still wins (demoaudit -> democonfig)' `
    ($partB.Contains('The edge it will cut is `demoaudit -> democonfig`.')) $partB

  $c1 = $r.Dump[1]
  Check 'cycle 1 dump present' ($null -ne $c1) ($r.Dump.Keys -join ',')
  Check 'cycle 1 (Part A, mvBase on const parameters) is NOT refused for base-class' `
    (($null -ne $c1) -and -not (($c1['refusals'] -split ',') -contains 'base-class')) "[$($c1['verdict']) / $($c1['refusals'])]"
  Check 'cycle 1 still extracts the base class TDemoSessionBase' `
    ((Get-Block $r.Out 1 'Step 1').Contains('**extract a base class** and keep `TDemoSession` where it is')) ''

  Write-Host '== (b) basevar: a var parameter of the switched type refuses base-class' -ForegroundColor Cyan
  $bvDir = Join-Path $WorkDir 'basevar'
  Copy-Tree (Join-Path $Repo 'tests\fixtures\cyclefix\basevar') $bvDir
  $bvDb = Index-Copy $bvDir 'BaseVar.dproj' 'basevar' 4
  $b = Get-Cycles $bvDb 'basevar' @('--plan', '--library-db', ('"' + $Lib + '"'))
  Check 'basevar: cycles --plan exit 0' ($b.Exit -eq 0) "exit $($b.Exit)"
  $bv1 = Get-Block $b.Out 1
  Check 'basevar Part A prints refused: base-class naming DemoLogger.pas:<line>' `
    ($bv1 -match '(?m)^.*refused: base-class.*DemoLogger\.pas:\d+') $bv1
  Check 'basevar: the refusal names the var parameter' `
    ($bv1 -match '(?m)^.*refused: base-class.*pSession.*a `var` parameter') $bv1
  Check 'basevar: no base-class extraction is offered' `
    (-not $bv1.Contains('**extract a base class**')) ''
  $bvc = $b.Dump[1]
  Check 'basevar: plan dump refuses with base-class' `
    (($null -ne $bvc) -and ($bvc['verdict'] -eq 'refused') -and (($bvc['refusals'] -split ',') -contains 'base-class')) "[$($bvc['verdict']) / $($bvc['refusals'])]"

  Write-Host '== (c) basebody: a const parameter used other than for a member read / nil test refuses base-class' -ForegroundColor Cyan
  # the demo's 4 units; DemoLogger.pas line 62 passes pSession to Assigned (a bare read, not `= nil`)
  $bbDir = Join-Path $WorkDir 'basebody'
  Copy-Tree (Join-Path $Repo 'tests\fixtures\cyclefix\basevar') $bbDir
  $lg = Join-Path $bbDir 'DemoLogger.pas'
  $txt = [IO.File]::ReadAllText($lg).Replace('var pSession: TDemoSession;', 'const pSession: TDemoSession;')
  $txt = $txt.Replace('LId := if pSession = nil then 0 else pSession.Id;', 'LId := if Assigned(pSession) then pSession.Id else 0;')
  [IO.File]::WriteAllText($lg, $txt, [Text.Encoding]::ASCII)
  Check 'basebody: SANITY the variant edit applied' ($txt.Contains('Assigned(pSession)') -and -not $txt.Contains('var pSession')) ''
  $bbDb = Index-Copy $bbDir 'BaseVar.dproj' 'basebody' 4
  $c = Get-Cycles $bbDb 'basebody' @('--plan', '--library-db', ('"' + $Lib + '"'))
  $bb1 = Get-Block $c.Out 1
  Check 'basebody: refused: base-class naming DemoLogger.pas and body line 62' `
    ($bb1 -match '(?m)^.*refused: base-class -- `DemoLogger\.pas:\d+`: parameter `pSession` -- line 62 ') $bb1

  Write-Host '== (d) basestring: each occurrence is classified by its own column (a nil test inside a string does not excuse a bare use)' -ForegroundColor Cyan
  # one line holds `pSession = nil` in code, `pSession = nil` inside a string, and Assigned(pSession):
  # a per-line count (2 bare refs vs 2 nil matches) let it pass; the occurrence in Assigned( must refuse.
  $bsDir = Join-Path $WorkDir 'basestring'
  Copy-Tree (Join-Path $Repo 'tests\fixtures\cyclefix\basevar') $bsDir
  $lg = Join-Path $bsDir 'DemoLogger.pas'
  $txt = [IO.File]::ReadAllText($lg).Replace('var pSession: TDemoSession;', 'const pSession: TDemoSession;')
  $txt = $txt.Replace('LId := if pSession = nil then 0 else pSession.Id;',
    'LId := if pSession = nil then 0 else 1; Writeln(''pSession = nil: '', Ord(Assigned(pSession)));')
  [IO.File]::WriteAllText($lg, $txt, [Text.Encoding]::ASCII)
  Check 'basestring: SANITY the variant edit applied' ($txt.Contains('Ord(Assigned(pSession))') -and -not $txt.Contains('var pSession')) ''
  $bsDb = Index-Copy $bsDir 'BaseVar.dproj' 'basestring' 4
  $c = Get-Cycles $bsDb 'basestring' @('--plan', '--library-db', ('"' + $Lib + '"'))
  $bs1 = Get-Block $c.Out 1
  Check 'basestring: refused: base-class at line 62, column of Assigned(pSession)' `
    ($bs1 -match '(?m)^.*refused: base-class -- `DemoLogger\.pas:\d+`: parameter `pSession` -- line 62 \(column \d+\) uses') $bs1

  Write-Host '== (e) basenobody: a parameter with no routine body to check refuses (fail closed)' -ForegroundColor Cyan
  $bnDir = Join-Path $WorkDir 'basenobody'
  Copy-Tree (Join-Path $Repo 'tests\fixtures\cyclefix\basevar') $bnDir
  $lg = Join-Path $bnDir 'DemoLogger.pas'
  $txt = [IO.File]::ReadAllText($lg).Replace('var pSession: TDemoSession;', 'const pSession: TDemoSession;')
  $txt = $txt.Replace("  TDemoLogLevel = (llDebug, llInfo, llWarn, llError);`r`n",
    "  TDemoLogLevel = (llDebug, llInfo, llWarn, llError);`r`n`r`n  /// <summary>A sink nobody implements here.</summary>`r`n  TDemoSink = class`r`n    procedure Put(const pSession: TDemoSession); virtual; abstract;`r`n  end;`r`n")
  [IO.File]::WriteAllText($lg, $txt, [Text.Encoding]::ASCII)
  Check 'basenobody: SANITY the variant edit applied' ($txt.Contains('virtual; abstract;') -and -not $txt.Contains('var pSession')) ''
  $bnDb = Index-Copy $bnDir 'BaseVar.dproj' 'basenobody' 4
  $c = Get-Cycles $bnDb 'basenobody' @('--plan', '--library-db', ('"' + $Lib + '"'))
  $bn1 = Get-Block $c.Out 1
  Check 'basenobody: refused: base-class naming the abstract method site' `
    ($bn1 -match '(?m)^.*refused: base-class -- `DemoLogger\.pas:\d+`: parameter `pSession` -- .*belongs to no routine body') $bn1

  Write-Host '== (f) tiebreak: three move-globals edges; fewest members, then fewest refs decides' -ForegroundColor Cyan
  # tiea -> tieb: members 0, refs 5, cost 1; tieb -> tiec: members 0, refs 3, cost 2;
  # tiec -> tiea: members 1, refs 2, cost 2. Cost first would cut tiea -> tieb, refs first tiec -> tiea.
  $tbDir = Join-Path $WorkDir 'tiebreak'
  Copy-Tree (Join-Path $Repo 'tests\fixtures\cyclefix\tiebreak') $tbDir
  $tbDb = Join-Path $tbDir 'tiebreak.sqlite'
  $idx = & $Exe index --project (Join-Path $tbDir 'TieBreak.dproj') --db $tbDb 2>&1 | Out-String
  Check 'tiebreak: SANITY the 3 units indexed with 0 errors' (([regex]::Matches($idx, 'Tie\w\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')).Count -eq 3) $idx
  $c = Get-Cycles $tbDb 'tiebreak' @('--plan', '--library-db', ('"' + $Lib + '"'))
  $tbFix = Get-Block $c.Out 1 'Recommended fix'
  Check 'tiebreak: POSITIVE CONTROL all three edges can move globals' `
    (([regex]::Matches($tbFix, '(?m)^- `tie\w -> tie\w`: recipe: move globals')).Count -eq 3) $tbFix
  Check 'tiebreak: cuts tieb -> tiec (members, then refs)' ($tbFix.Contains('Cut the edge `tieb -> tiec`')) $tbFix

  Write-Host '== (g) partbr1: Part B predicts the R1 cut, naming its recipe' -ForegroundColor Cyan
  $pbDir = Join-Path $WorkDir 'partbr1'
  Copy-Tree (Join-Path $Repo 'tests\fixtures\cyclefix\partbr1') $pbDir
  $pbDb = Join-Path $pbDir 'partbr1.sqlite'
  $idx = & $Exe index --project (Join-Path $pbDir 'PartBR1.dproj') --db $pbDb 2>&1 | Out-String
  Check 'partbr1: SANITY the 2 units indexed with 0 errors' (([regex]::Matches($idx, 'PartB\w\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')).Count -eq 2) $idx
  $c = Get-Cycles $pbDb 'partbr1' @('--plan', '--library-db', ('"' + $Lib + '"'))
  $pb = Get-Block $c.Out 1 'Part B'
  Check 'partbr1: POSITIVE CONTROL Part B lists both predicted edges' `
    (([regex]::Matches($pb, '(?m)^- `partb\w -> partb\w`: ')).Count -eq 2) $pb
  Check 'partbr1: partbb -> partba is mechanical by routine-call inversion' `
    ($pb -match '(?m)^- `partbb -> partba`: .* -- mechanical: recipe: routine-call inversion') $pb
  Check 'partbr1: Part B names the edge and its recipe' `
    ($pb.Contains('The edge it will cut is `partbb -> partba`. Recipe: routine-call inversion.')) $pb
  Check 'partbr1: no "No edge above can be cut" verdict' (-not $pb.Contains('No edge above can be cut')) $pb
} finally {
  Pop-Location
  if (Test-Path $Lib) { [IO.File]::Delete($Lib) }
}
Check 'z1: the real library DBs are unchanged (size + mtime)' ((Get-LibStamp) -eq $stampBefore) ''

Write-Host ("{0} PASS" -f $script:Passed)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
