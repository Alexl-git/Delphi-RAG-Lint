<#
  run_reverse_calltree.ps1 -- reverse-calltree headless test (Batch C / Task 4):
  the N-deep REVERSE call tree (who calls X, who calls them) with call sites
  and cycle markers, across text/json/dot/mermaid renderers.

  FIXTURE (built fresh in a temp workdir, then indexed as a whole tree):
    chainc.pas -- unit chainc; procedure C; begin end;              <- root
    chainb.pas -- unit chainb; uses chainc; procedure B calls C at a known line
    chaina.pas -- unit chaina; uses chainb; procedure A calls B
    cyc.pas    -- unit cyc; procedure P (forward) / Q calling P / P calling Q
                   -- a self-sustaining cycle for the Cycle=True marker.

  Load-bearing assertions (per the task-4 brief):
    - reverse-calltree --qname C --json: root qname ends with '.C' (or ='C'),
      root.callers contains B, and B.callers contains A (UPWARD direction --
      B calls C, A calls B, so the tree climbs C <- B <- A).
    - a caller node's "site" matches <unit>:<line> with a numeric line
      (CallSiteLine surfaced via TResolvedCaller).
    - --depth 1 truncates: A is absent under C's tree; summary.truncated==true.
    - cycle fixture: --qname P --json has a node with cycle==true, and the
      process terminates (no infinite output/hang).
    - --format dot contains 'digraph'; --format mermaid contains 'graph'.
    - default/--format text is indented and mentions C then B (upward order).
    - two --json runs are byte-identical (determinism).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-reverse-calltree by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-reverse-calltree"
)
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# NOTE on fixture shape: drag-lint's call resolver (TCallResolver.ResolveOne,
# DRagLint.Index.CallResolver.pas) only resolves CROSS-UNIT calls that go
# through a TYPED RECEIVER (a class/interface/record instance) -- a bare
# cross-unit global-procedure call (e.g. chainb.B calling a bare chainc.C)
# NEVER produces a call_edges row, because TypeReceiver's kind-1 branch
# (bare M) resolves to the ENCLOSING routine's OWN class, and chainc.C is
# not on chainb.B's class. So this fixture uses one method per class,
# invoked via a typed local variable across units -- the resolver's
# documented, reliable path (kind 4: typed LOCAL var 'L.M').

$ChainCBody = @'
unit chainc;

interface

type
  TC = class
    procedure C;
  end;

implementation

procedure TC.C;
begin
end;

end.
'@

$ChainBBody = @'
unit chainb;

interface

uses
  chainc;

type
  TB = class
    procedure B;
  end;

implementation

procedure TB.B;
var
  V: TC;
begin
  V := TC.Create;
  try
    V.C;
  finally
    V.Free;
  end;
end;

end.
'@

$ChainABody = @'
unit chaina;

interface

uses
  chainb;

type
  TA = class
    procedure A;
  end;

implementation

procedure TA.A;
var
  V: TB;
begin
  V := TB.Create;
  try
    V.B;
  finally
    V.Free;
  end;
end;

end.
'@

# Cycle: TCyc.P <-> TCyc.Q via Self (kind-1 bare-call receiver = the
# enclosing method's OWN class -- the resolver's most reliable case).
$CycBody = @'
unit cyc;

interface

type
  TCyc = class
    procedure P;
    procedure Q;
  end;

implementation

procedure TCyc.Q;
begin
  P;
end;

procedure TCyc.P;
begin
  Q;
end;

end.
'@

Write-Ascii (Join-Path $work 'chainc.pas') $ChainCBody
Write-Ascii (Join-Path $work 'chainb.pas') $ChainBBody
Write-Ascii (Join-Path $work 'chaina.pas') $ChainABody
Write-Ascii (Join-Path $work 'cyc.pas')    $CycBody

$db = Join-Path $WorkDir 'rct.sqlite'

Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

Write-Host ''
Write-Host 'reverse-calltree --qname C --json (default depth)' -ForegroundColor Cyan
# Diagnostics go to stderr; stdout is captured WITHOUT a 2>&1 merge to keep it
# pure JSON (mirrors run_deps_report.ps1's convention).
Push-Location $WorkDir
try {
  $jsonRaw1 = (& $Exe reverse-calltree --qname C --db $db --json) -join "`n"
  $rctExit1 = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'reverse-calltree --qname C exits 0' ($rctExit1 -eq 0) "exit=$rctExit1"

$tree = $null
try {
  $tree = $jsonRaw1 | ConvertFrom-Json
} catch {
  Check 'reverse-calltree --json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$jsonRaw1"
}

if ($null -ne $tree) {
  Check 'reverse-calltree --json parses as JSON' $true

  # A single root (C is not overloaded) -> bare {schema, root, summary} object;
  # if the CLI array-wraps anyway (overload precedent), unwrap the first
  # element BEFORE drilling into .root.
  $treeObj = $tree
  if ($tree -is [System.Array]) { $treeObj = $tree[0] }
  $root = $treeObj.root

  Check 'root qname ends with C' ($root.qname -match '\.C$' -or $root.qname -eq 'C') "qname=$($root.qname)"

  $callersOfC = @($root.callers)
  $bNode = $callersOfC | Where-Object { $_.qname -match '\.B$' -or $_.qname -eq 'B' } | Select-Object -First 1
  Check 'root.callers contains B (C is called by B)' ($null -ne $bNode) ("callers=" + (($callersOfC | ForEach-Object { $_.qname }) -join ', '))

  if ($null -ne $bNode) {
    Check 'B site matches <unit>:<line> with numeric line' `
      ($bNode.site -match '^[^:]+:\d+$') "site=$($bNode.site)"

    $callersOfB = @($bNode.callers)
    $aNode = $callersOfB | Where-Object { $_.qname -match '\.A$' -or $_.qname -eq 'A' } | Select-Object -First 1
    Check 'B.callers contains A (B is called by A) -- UPWARD direction' ($null -ne $aNode) ("callers=" + (($callersOfB | ForEach-Object { $_.qname }) -join ', '))
  }
}

Write-Host ''
Write-Host 'reverse-calltree --qname C --depth 1 --json (truncation)' -ForegroundColor Cyan
$depth1Raw = (& $Exe reverse-calltree --qname C --db $db --depth 1 --json) -join "`n"
$depth1 = $null
try {
  $depth1 = $depth1Raw | ConvertFrom-Json
} catch {
  Check 'reverse-calltree --depth 1 --json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$depth1Raw"
}
if ($null -ne $depth1) {
  Check 'reverse-calltree --depth 1 --json parses as JSON' $true
  $depth1Obj = $depth1
  if ($depth1 -is [System.Array]) { $depth1Obj = $depth1[0] }
  $root1 = $depth1Obj.root

  $callersOfC1 = @($root1.callers)
  $bNode1 = $callersOfC1 | Where-Object { $_.qname -match '\.B$' -or $_.qname -eq 'B' } | Select-Object -First 1
  Check 'depth 1: root.callers still contains B' ($null -ne $bNode1) ("callers=" + (($callersOfC1 | ForEach-Object { $_.qname }) -join ', '))
  if ($null -ne $bNode1) {
    $callersOfB1 = @($bNode1.callers)
    Check 'depth 1: A is ABSENT under B (truncated before B''s own callers)' ($callersOfB1.Count -eq 0) ("callers=" + (($callersOfB1 | ForEach-Object { $_.qname }) -join ', '))
  }
  Check 'depth 1: summary.truncated == true' ($depth1Obj.summary.truncated -eq $true) `
    "summary=$($depth1Obj.summary | ConvertTo-Json -Compress)"
}

Write-Host ''
Write-Host 'reverse-calltree --qname P --json (cycle P<->Q)' -ForegroundColor Cyan
$cycRaw = (& $Exe reverse-calltree --qname P --db $db --json) -join "`n"
$cycExit = $LASTEXITCODE
Check 'reverse-calltree --qname P exits 0 (no hang/crash on cycle)' ($cycExit -eq 0) "exit=$cycExit"
$cycTree = $null
try {
  $cycTree = $cycRaw | ConvertFrom-Json
} catch {
  Check 'reverse-calltree --qname P --json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$cycRaw"
}
if ($null -ne $cycTree) {
  Check 'reverse-calltree --qname P --json parses as JSON' $true
  $cycTreeObj = $cycTree
  if ($cycTree -is [System.Array]) { $cycTreeObj = $cycTree[0] }
  $cycRoot = $cycTreeObj.root

  function Find-CycleNode($node) {
    if ($null -eq $node) { return $null }
    if ($node.cycle -eq $true) { return $node }
    foreach ($c in @($node.callers)) {
      $found = Find-CycleNode $c
      if ($null -ne $found) { return $found }
    }
    return $null
  }
  $cycleHit = Find-CycleNode $cycRoot
  Check 'cycle: some node has cycle==true' ($null -ne $cycleHit) "tree=$($cycRaw)"
}

Write-Host ''
Write-Host 'reverse-calltree --qname C --format dot' -ForegroundColor Cyan
$dotOut = (& $Exe reverse-calltree --qname C --db $db --format dot) -join "`n"
Check 'dot output contains digraph' ($dotOut -match 'digraph') "out=$dotOut"

Write-Host ''
Write-Host 'reverse-calltree --qname C --format mermaid' -ForegroundColor Cyan
$mermaidOut = (& $Exe reverse-calltree --qname C --db $db --format mermaid) -join "`n"
Check 'mermaid output contains graph' ($mermaidOut -match 'graph') "out=$mermaidOut"

Write-Host ''
Write-Host 'reverse-calltree --qname C (default text)' -ForegroundColor Cyan
$textOut = (& $Exe reverse-calltree --qname C --db $db) -join "`n"
$cIdx = $textOut.IndexOf('C')
$bIdx = $textOut.IndexOf('B')
Check 'text output contains C' ($cIdx -ge 0) "out=$textOut"
Check 'text output contains B after C (upward order)' ($bIdx -gt $cIdx) "cIdx=$cIdx bIdx=$bIdx out=$textOut"
Check 'text output is indented (contains a leading-space line)' ($textOut -match '(?m)^\s+\S') "out=$textOut"

Write-Host ''
Write-Host 'Determinism: --json run twice, byte-identical' -ForegroundColor Cyan
$jsonRaw2 = (& $Exe reverse-calltree --qname C --db $db --json) -join "`n"
Check 'two --json runs are byte-identical' ($jsonRaw1 -ceq $jsonRaw2) "len1=$($jsonRaw1.Length) len2=$($jsonRaw2.Length)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
