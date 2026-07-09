<#
  run_butterfly.ps1 -- butterfly chart verb headless test (Batch H2 / Track 5.3
  slice): composes a symbol's callers (upward wing) + callees (downward wing)
  into one chart, reusing BuildReverseCallTree + BuildForwardCallTree.

  FIXTURE (built fresh in a temp workdir, then indexed as a whole tree):
    butterfly.pas -- unit Butterfly;
                       TRoot.Top calls TRoot.Middle       (Middle has a caller)
                       TRoot.Middle calls TRoot.Bottom    (Middle has a callee)
                     ROOT = Butterfly.TRoot.Middle -- both a caller (Top) and a
                     callee (Bottom) exist, so the butterfly has both wings.

  Load-bearing assertions (per the design spec's test plan):
    - --format json: schema butterfly/1, qname==root, callers.root present with
      >=1 caller node, callees.root present with >=1 callee node.
    - --format dot: contains 'digraph', contains the root qname, contains a
      caller->root edge AND a root->callee edge (BOTH orientations, proving
      composition).
    - --format mermaid: contains 'graph LR' and both edge orientations.
    - exit 0 on success; a bogus --qname exits 1.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-butterfly by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-butterfly"
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

$ButterflyBody = @'
unit Butterfly;

interface

type
  TRoot = class
    procedure Top;
    procedure Middle;
    procedure Bottom;
  end;

implementation

procedure TRoot.Bottom;
begin
end;

procedure TRoot.Middle;
begin
  Bottom;
end;

procedure TRoot.Top;
begin
  Middle;
end;

end.
'@

Write-Ascii (Join-Path $work 'butterfly.pas') $ButterflyBody

$db = Join-Path $WorkDir 'butterfly.sqlite'

Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

Write-Host ''
Write-Host 'butterfly --qname Butterfly.TRoot.Middle --format json' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $jsonRaw = (& $Exe butterfly --qname 'Butterfly.TRoot.Middle' --depth 3 --format json --db $db) -join "`n"
  $jsonExit = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'butterfly --format json exits 0' ($jsonExit -eq 0) "exit=$jsonExit"

$bf = $null
try {
  $bf = $jsonRaw | ConvertFrom-Json
} catch {
  Check 'butterfly --format json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$jsonRaw"
}

if ($null -ne $bf) {
  Check 'butterfly --format json parses as JSON' $true
  Check 'schema is butterfly/1' ($bf.schema -eq 'butterfly/1') "schema=$($bf.schema)"
  Check 'qname matches root' ($bf.qname -match '\.Middle$' -or $bf.qname -eq 'Middle') "qname=$($bf.qname)"
  Check 'has callers section' ($null -ne $bf.callers) ''
  Check 'has callees section' ($null -ne $bf.callees) ''

  if ($null -ne $bf.callers) {
    $callerRoot = $bf.callers.root
    Check 'callers.root present' ($null -ne $callerRoot) ''
    if ($null -ne $callerRoot) {
      $callerKids = @($callerRoot.callers)
      Check 'callers.root has >=1 caller node' ($callerKids.Count -ge 1) ("callers=" + (($callerKids | ForEach-Object { $_.qname }) -join ', '))
    }
  }

  if ($null -ne $bf.callees) {
    $calleeRoot = $bf.callees.root
    Check 'callees.root present' ($null -ne $calleeRoot) ''
    if ($null -ne $calleeRoot) {
      $calleeKids = @($calleeRoot.callers)
      Check 'callees.root has >=1 callee node' ($calleeKids.Count -ge 1) ("callers=" + (($calleeKids | ForEach-Object { $_.qname }) -join ', '))
    }
  }
}

Write-Host ''
Write-Host 'butterfly --qname Butterfly.TRoot.Middle --format dot' -ForegroundColor Cyan
$dotRaw = (& $Exe butterfly --qname 'Butterfly.TRoot.Middle' --depth 3 --format dot --db $db) -join "`n"
$dotExit = $LASTEXITCODE
Check 'butterfly --format dot exits 0' ($dotExit -eq 0) "exit=$dotExit"
Check 'dot contains digraph' ($dotRaw -match 'digraph') ''
Check 'dot contains root qname' ($dotRaw -match [regex]::Escape('Middle')) ''
Check 'dot contains caller->root edge (Top -> Middle)' ($dotRaw -match '"[^"]*Top"\s*->\s*"[^"]*Middle"') "dot=$dotRaw"
Check 'dot contains root->callee edge (Middle -> Bottom)' ($dotRaw -match '"[^"]*Middle"\s*->\s*"[^"]*Bottom"') "dot=$dotRaw"

Write-Host ''
Write-Host 'butterfly --qname Butterfly.TRoot.Middle --format mermaid' -ForegroundColor Cyan
$mmRaw = (& $Exe butterfly --qname 'Butterfly.TRoot.Middle' --depth 3 --format mermaid --db $db) -join "`n"
$mmExit = $LASTEXITCODE
Check 'butterfly --format mermaid exits 0' ($mmExit -eq 0) "exit=$mmExit"
Check 'mermaid contains graph LR' ($mmRaw -match 'graph LR') ''
Check 'mermaid contains caller->root edge (Top --> Middle)' ($mmRaw -match '(?i)Top\s*-->\s*.*Middle') "mermaid=$mmRaw"
Check 'mermaid contains root->callee edge (Middle --> Bottom)' ($mmRaw -match '(?i)Middle\s*-->\s*.*Bottom') "mermaid=$mmRaw"

Write-Host ''
Write-Host 'butterfly --qname NoSuchSym (bogus qname exits 1)' -ForegroundColor Cyan
$bogusOut = (& $Exe butterfly --qname 'NoSuchSym' --db $db 2>&1) -join "`n"
$bogusExit = $LASTEXITCODE
Check 'bogus --qname exits 1' ($bogusExit -eq 1) "exit=$bogusExit; out=$bogusOut"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
