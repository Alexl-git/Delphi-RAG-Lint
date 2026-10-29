<#
  run_charts_cycles_fixit.ps1 -- E18 Task 14: the chart page's "Fix it" cell (`ask cycles`, Emit-Cycles.ps1).

  The emitter asks the engine ONCE for `cycles --format json --edges --causes` and renders, per cycle, a
  "Fix it" row after the verdict row:
    available       -> the engine's dry-run command in a monospace cell (HREF draglint://copy?text=<dry-run>,
                       TITLE = the apply command: the page cannot run a command, it hands the exact one over)
                       plus a note row naming the chosen edge and recipe;
    not available   -> `fix-it: not available -- <reason>`;
    no `fix` object -> `fix-it: engine too old`.
  The row hrefs stay draglint://open (the Fix it rows never change Anchored / Edges / the verdict text).

  Asserts on a COPY of circular-demo and of tests\fixtures\cyclefix\nocut, indexed by -Exe (a COPY of an
  engine build; the real library DB is never opened: --library-db none):
    a) the demo page carries `cycles --fix --project` once per cycle that is available (cycles 1 and 3 here;
       cycle 2 needs the platform library for its member hand-over and reads `not available`), the chosen
       edge + `routine-call inversion` for cycle 3, `move globals` for the Part A follow-up of cycle 1;
    b) nocut: `not available -- construction`;
    c) a STUB engine (real engine for every verb but `cycles`) whose cycles JSON has NO `fix` objects: every
       cell reads `fix-it: engine too old` and no dry-run command is rendered (POSITIVE CONTROL: it proves
       (a) reads the engine's fix object, not a constant);
    d) a STUB whose cycle 2 fix is recipe `member-interface`: the cell reads `member hand-over` (the
       library-dependent case, without the 3 GB library);
    e) the verdict text, Anchored and Edges are unchanged by the new rows; -Playbook keeps the Status wording.
  Cleans its scratch in `finally`; -KeepScratch keeps it only on failure.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [switch]$KeepScratch,
  [string]$WorkDir = "$env:TEMP\drag-lint-charts-cycles-fixit-$PID"
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
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Emit = Join-Path $Repo 'charts\src\Emit-Cycles.ps1'

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
function Index-Copy([string]$Dir, [string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  $idx = & $Exe index --project (Join-Path $Dir $Dproj) --db $db 2>&1 | Out-String
  Check "${Tag}: SANITY the copy indexed with 0 errors" (($idx -match ', 0 errors') -and ($idx -notmatch '[1-9]\d* errors')) $idx
  return $db
}
# Builds the page; returns @{ Dot = <dot text>; Res = <emitter result> }
function Build-Page([string]$Db, [string]$Proj, [string]$Engine, [string]$Tag, [switch]$Playbook) {
  $out = Join-Path $WorkDir "out-$Tag"
  $a = @{ DbPath = $Db; OutDir = $out; Engine = $Engine; Project = $Proj; LibraryDb = 'none' }
  if ($Playbook) { $a.Playbook = $true }
  $res = & $Emit @a 6>$null
  return @{ Dot = [IO.File]::ReadAllText($res.Dot); Res = $res }
}
# Number of Fix it code cells (the monospace dry-run command), not counting the apply command in a TITLE
function Count-Code([string]$Dot) { return ([regex]::Matches($Dot, 'FACE="[^"]+" POINT-SIZE="11">drag-lint cycles --fix --project ')).Count }
# A stub engine: `cycles` prints the canned JSON file, every other verb goes to the real engine.
function New-Stub([string]$Tag, $Json) {
  $dir = Join-Path $WorkDir "stub-$Tag"
  New-Item -ItemType Directory -Force $dir | Out-Null
  [IO.File]::WriteAllText((Join-Path $dir 'cycles.json'), (ConvertTo-Json -InputObject @($Json) -Depth 30 -Compress), [Text.UTF8Encoding]::new($false))
  $ps = "if (`$args[0] -eq 'cycles') { [IO.File]::ReadAllText((Join-Path `$PSScriptRoot 'cycles.json')); exit 0 }`r`n& '$Exe' @args`r`nexit `$LASTEXITCODE`r`n"
  [IO.File]::WriteAllText((Join-Path $dir 'stub.ps1'), $ps, [Text.Encoding]::ASCII)
  return (Join-Path $dir 'stub.ps1')
}

$savedLive = $env:DRAGLINT_CHARTS_ALLOW_LIVE_DB
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $env:DRAGLINT_CHARTS_ALLOW_LIVE_DB = '1'   # the scratch DBs are not charts\scratch\db clones
  $demo = Join-Path $WorkDir 'demo'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demo
  $db = Index-Copy $demo 'CircularDemo.dproj' 'demo'
  $proj = Join-Path $demo 'CircularDemo.dproj'
  $nocut = Join-Path $WorkDir 'nocut'
  Copy-Tree (Join-Path $Repo 'tests\fixtures\cyclefix\nocut') $nocut
  $ndb = Index-Copy $nocut 'NoCut.dproj' 'nocut'
  $nproj = Join-Path $nocut 'NoCut.dproj'

  Write-Host '== (a) the demo page, real engine' -ForegroundColor Cyan
  $pg = Build-Page $db $proj $Exe 'demo'
  $t = $pg.Dot
  Check 'a0: SANITY three cycles drawn' ($pg.Res.Cycles -eq 3 -and $pg.Res.Shown -eq 3) "cycles=$($pg.Res.Cycles) shown=$($pg.Res.Shown)"
  Check 'a1: `cycles --fix --project` once per AVAILABLE cycle (2 of 3 without the library)' ((Count-Code $t) -eq 2) "count=$(Count-Code $t)"
  Check 'a2: the code cell names the cycle (--cycle 1, --cycle 3), the apply command is the TITLE' `
    (($t -match '>drag-lint cycles --fix --project [^<]*--cycle 1<') -and ($t -match '>drag-lint cycles --fix --project [^<]*--cycle 3<') -and
     ($t -match 'TITLE="drag-lint cycles --fix --project [^"]*--cycle 3 --apply"')) ''
  Check 'a3: no draglint://copy href anywhere (nothing handles it) and no [copy] hint' (($t -notmatch 'draglint://copy') -and ($t -notmatch '\[copy\]')) ''
  Check 'a4: cycle 3 names its chosen edge and `routine-call inversion`' `
    ($t -match 'fix-it: demoblueprint -&gt; demoblueprint\.viewmodel by routine-call inversion') ''
  Check 'a5: cycle 1 names the Part B follow-up `move globals`' ($t -match 'fix-it: Part A first, then demoaudit -&gt; democonfig by move globals') ''
  # since dbc28c1f (C1 is-guard) cycle 2's first refusal is cast-unseen (TComponent is undeclared without the
  # library); either reason is the library-missing case this check pins.
  Check 'a6: cycle 2 without the library reads `not available -- `' ($t -match 'fix-it: not available -- (receiver-unknown|cast-unseen: .*no index given declares)') ''

  Write-Host '== (b) nocut' -ForegroundColor Cyan
  $pn = Build-Page $ndb $nproj $Exe 'nocut'
  Check 'b1: `not available -- construction`' ($pn.Dot -match 'fix-it: not available -- construction') ''
  Check 'b2: no dry-run code cell for an unavailable fix' ((Count-Code $pn.Dot) -eq 0) ''

  Write-Host '== (c) POSITIVE CONTROL: a stub engine without `fix`' -ForegroundColor Cyan
  $raw = & $Exe cycles --db $db --project $proj --format json --edges --causes --library-db none 2>$null | Out-String
  $j = @($raw | ConvertFrom-Json)
  Check 'c0: SANITY the real JSON has a fix object on all 3 cycles' (@($j | Where-Object { $_.PSObject.Properties['fix'] }).Count -eq 3) ''
  $old = @($raw | ConvertFrom-Json | ForEach-Object { $_.PSObject.Properties.Remove('fix'); $_ })
  $stubOld = New-Stub 'old' $old
  $po = Build-Page $db $proj $stubOld 'old'
  Check 'c1: every cycle reads `fix-it: engine too old`' (([regex]::Matches($po.Dot, 'fix-it: engine too old')).Count -eq 3) ''
  Check 'c2: no dry-run command and no `not available` cell rendered' (((Count-Code $po.Dot) -eq 0) -and ($po.Dot -notmatch 'fix-it: not available')) ''

  Write-Host '== (d) a stub with recipe member-interface (the library case)' -ForegroundColor Cyan
  $j2 = @($raw | ConvertFrom-Json)
  $j2[1].fix.available = $true; $j2[1].fix.reason = ''
  $j2[1].fix.edges = @([pscustomobject]@{ from = 'demogageport'; to = 'demouiconnect'; recipe = 'member-interface'; chosen = $true })
  $stubMi = New-Stub 'mi' $j2
  $pm = Build-Page $db $proj $stubMi 'mi'
  Check 'd1: cycle 2 reads `by member hand-over`' ($pm.Dot -match 'fix-it: demogageport -&gt; demouiconnect by member hand-over') ''
  Check 'd2: `cycles --fix --project` once per cycle (3 of 3)' ((Count-Code $pm.Dot) -eq 3) "count=$(Count-Code $pm.Dot)"

  Write-Host '== (e) nothing else moved' -ForegroundColor Cyan
  Check 'e1: Anchored / Edges as before the Fix it rows (9 anchored, 9 edges)' (($pg.Res.Anchored -eq 9) -and ($pg.Res.Edges -eq 9)) "anchored=$($pg.Res.Anchored) edges=$($pg.Res.Edges)"
  Check 'e2: the verdict row text is unchanged' ($t -match '>interface coupling: \d+ of \d+ uses interface-section; every loop crosses an implementation use<' -and $t -match '>implementation-only<') ''
  $pp = Build-Page $db $proj $Exe 'playbook' -Playbook
  $statusImpl = 'legal in Delphi, low impact'   # the engine Status of an implementation-only cycle; the chart's own verdict never says it
  $statusIntf = '-- engine: interface coupling -- 3 of 4 uses between the units of this cycle are in INTERFACE uses clauses.'
  Check 'e3: WITH -Playbook the engine Status wording is on the page (cycle 1 after the counted clause, cycles 2 and 3 verbatim)' `
    (($pp.Dot.Contains($statusIntf)) -and (([regex]::Matches($pp.Dot, [regex]::Escape($statusImpl))).Count -eq 2)) ''
  Check 'e4: WITHOUT -Playbook neither Status wording is on the page' ((-not $t.Contains($statusImpl)) -and (-not $t.Contains($statusIntf))) ''
  Check 'e5: -Playbook still renders the Fix it cells' ((Count-Code $pp.Dot) -eq 2) ''

  Write-Host '== (f) through the Ask-Report path (-Plain)' -ForegroundColor Cyan
  # the wrapper adds --library-db none to `cycles` (Ask-Report has no -LibraryDb; the real library DB is never opened)
  $wdir = Join-Path $WorkDir 'wrap'; New-Item -ItemType Directory -Force $wdir | Out-Null
  $wps = "if (`$args[0] -eq 'cycles') { & '$Exe' @args --library-db none; exit `$LASTEXITCODE }`r`n& '$Exe' @args`r`nexit `$LASTEXITCODE`r`n"
  [IO.File]::WriteAllText((Join-Path $wdir 'wrap.ps1'), $wps, [Text.Encoding]::ASCII)
  $ask = Join-Path $Repo 'charts\src\Ask-Report.ps1'
  function Get-AskDot([bool]$WithProject, [string]$Tag) {
    $outRoot = Join-Path $WorkDir "ask-$Tag"
    $aa = @('-NoProfile', '-File', $ask, '-Question', 'cycles', '-Target', 'project', '-DbPath', $db, '-Engine', (Join-Path $wdir 'wrap.ps1'), '-OutRoot', $outRoot, '-Plain')
    if ($WithProject) { $aa += @('-Project', $proj) }
    $o = & pwsh @aa 2>&1 | Out-String
    $m = [regex]::Match($o, '(?m)^BUNDLE (.+?)\s*$')
    if (-not $m.Success) { return @{ Dot = ''; Out = $o } }
    return @{ Dot = [IO.File]::ReadAllText((Join-Path $m.Groups[1].Value 'graph.dot')); Out = $o }
  }
  $ak = Get-AskDot $true 'proj'
  Check 'f1: SANITY the Ask-Report run produced a bundle with a dot' ($ak.Dot.Length -gt 0) $ak.Out
  Check 'f2: with -Project the Fix it commands name the real .dproj' ($ak.Dot.Contains($proj) -and $ak.Dot -notmatch '<your\.dproj>|&lt;your\.dproj&gt;') ''
  $an = Get-AskDot $false 'noproj'
  Check 'f3: CONTROL without -Project the page prints <your.dproj> (the check can fail)' ($an.Dot -match '&lt;your\.dproj&gt;|<your\.dproj>') ''}
finally {
  $env:DRAGLINT_CHARTS_ALLOW_LIVE_DB = $savedLive
  if ($script:Failed -and $KeepScratch) { Write-Host "scratch kept: $WorkDir" -ForegroundColor Yellow }
  else { Set-Location -LiteralPath $env:TEMP; if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } }
}
Write-Host ("{0} passed" -f $script:Passed)
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
