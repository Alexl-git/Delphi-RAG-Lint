<#
  run_forward_calltree.ps1 -- reverse-calltree --direction callees headless test
  (Task 2 of the reverse-calltree direction flag): the N-deep FORWARD call tree
  (what X calls, what those call) emitted via the SAME reverse-calltree/1 JSON
  schema as the (upward) callers tree, selected with --direction callees.

  FIXTURE (built fresh in a temp workdir, then indexed as a whole tree):
    forward.pas -- unit Forward; TRoot.Drive calls StepA and StepB;
                    TRoot.StepB also calls StepA.
                    Drive is the ROOT: --direction callees walks DOWNWARD
                    (Drive -> {StepA, StepB}), the mirror of the reverse
                    (callers) tree tested by run_reverse_calltree.ps1.

  Load-bearing assertions:
    - reverse-calltree --qname Forward.TRoot.Drive --direction callees --json:
      schema == reverse-calltree/1, root present, root.callers (used as the
      generic child-node array for both directions) has >=1 node, and the
      first callee node has a non-empty qname + file and line >= 1.
    - Back-compat: the SAME qname with the DEFAULT direction (no --direction
      flag, i.e. historic 'callers') still returns schema reverse-calltree/1
      and does NOT silently switch to callees (root.callers empty, since
      nothing in the fixture calls Drive).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-forward-calltree by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-forward-calltree"
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

$ForwardBody = @'
unit Forward;

interface

type
  TRoot = class
    procedure Drive;
    procedure StepA;
    procedure StepB;
  end;

implementation

procedure TRoot.StepA;
begin
end;

procedure TRoot.StepB;
begin
  StepA;
end;

procedure TRoot.Drive;
begin
  StepA;
  StepB;
end;

end.
'@

Write-Ascii (Join-Path $work 'forward.pas') $ForwardBody

$db = Join-Path $WorkDir 'forward.sqlite'

Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

Write-Host ''
Write-Host 'reverse-calltree --qname Forward.TRoot.Drive --direction callees --json' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $jsonRaw = (& $Exe reverse-calltree --qname 'Forward.TRoot.Drive' --direction callees --depth 3 --db $db --json) -join "`n"
  $rctExit = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'reverse-calltree --direction callees exits 0' ($rctExit -eq 0) "exit=$rctExit"

$tree = $null
try {
  $tree = $jsonRaw | ConvertFrom-Json
} catch {
  Check 'reverse-calltree --direction callees --json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$jsonRaw"
}

if ($null -ne $tree) {
  Check 'reverse-calltree --direction callees --json parses as JSON' $true

  $treeObj = $tree
  if ($tree -is [System.Array]) { $treeObj = $tree[0] }

  Check 'schema is reverse-calltree/1' ($treeObj.schema -eq 'reverse-calltree/1') "schema=$($treeObj.schema)"
  Check 'has root' ($null -ne $treeObj.root) ''

  $root = $treeObj.root
  $callees = @($root.callers)
  Check 'root has >=1 callee node' ($callees.Count -ge 1) ("callers=" + (($callees | ForEach-Object { $_.qname }) -join ', '))

  if ($callees.Count -ge 1) {
    $first = $callees[0]
    Check 'callee node has non-empty qname' (-not [string]::IsNullOrEmpty($first.qname)) "qname=$($first.qname)"
    Check 'callee node has non-empty file (navigable)' (-not [string]::IsNullOrEmpty($first.file)) "file=$($first.file)"
    Check 'callee node has line >= 1' ($first.line -ge 1) "line=$($first.line)"
  }

  # StepB itself calls StepA -- confirm the DOWNWARD walk descends a second level.
  $bNode = $callees | Where-Object { $_.qname -match '\.StepB$' -or $_.qname -eq 'StepB' } | Select-Object -First 1
  Check 'Drive callees include StepB' ($null -ne $bNode) ("callers=" + (($callees | ForEach-Object { $_.qname }) -join ', '))
  if ($null -ne $bNode) {
    $bCallees = @($bNode.callers)
    $aUnderB = $bCallees | Where-Object { $_.qname -match '\.StepA$' -or $_.qname -eq 'StepA' } | Select-Object -First 1
    Check 'StepB callees include StepA (2nd-level downward)' ($null -ne $aUnderB) ("callers=" + (($bCallees | ForEach-Object { $_.qname }) -join ', '))
  }
}

Write-Host ''
Write-Host 'Back-compat: default direction (no --direction flag) still reverse-calltree/1' -ForegroundColor Cyan
$defRaw = (& $Exe reverse-calltree --qname 'Forward.TRoot.Drive' --depth 2 --db $db --json) -join "`n"
$defExit = $LASTEXITCODE
Check 'default direction exits 0' ($defExit -eq 0) "exit=$defExit"

$defTree = $null
try {
  $defTree = $defRaw | ConvertFrom-Json
} catch {
  Check 'default direction --json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$defRaw"
}
if ($null -ne $defTree) {
  Check 'default direction --json parses as JSON' $true
  $defObj = $defTree
  if ($defTree -is [System.Array]) { $defObj = $defTree[0] }
  Check 'default (callers) still reverse-calltree/1' ($defObj.schema -eq 'reverse-calltree/1') "schema=$($defObj.schema)"

  # Nothing in the fixture calls Drive, so the UPWARD (callers) tree from
  # Drive must have ZERO callers -- proves the default did NOT silently
  # flip to 'callees' (which would show StepA/StepB here).
  $defRoot = $defObj.root
  $defCallers = @($defRoot.callers)
  Check 'default direction root.callers is EMPTY (proves default stayed callers, not callees)' `
    ($defCallers.Count -eq 0) ("callers=" + (($defCallers | ForEach-Object { $_.qname }) -join ', '))
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
