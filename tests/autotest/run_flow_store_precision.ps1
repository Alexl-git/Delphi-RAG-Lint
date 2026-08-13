<#
  run_flow_store_precision.ps1 -- the two flow checks that need a SYMBOL STORE to
  be right: object-leak's ownership transfer, and used-before-assignment's
  treatment of an `out` argument.

  WHY THIS IS ONE TEST: both defects have the same shape. The analysis had the
  syntax in front of it and was missing a fact only a lookup could supply, so
  each reported a defect on code that is correct by construction.

  A. object-leak: ownership needs the LIBRARY store (~14 findings)
  ---------------------------------------------------------------
  ConstructorTransfersOwnership asked `IsDescendantOf(T, 'TComponent')` of the
  PROJECT store only. TTimer, TButton and the rest of the VCL live in the
  LIBRARY index, so the answer was always False, ownership was never detected,
  and `T := TTimer.Create(Self)` -- freed by its owner, by definition -- was
  reported as a leak.

  The fixture builds its OWN two-database world rather than leaning on the real
  ~2.2 GB library index: FakeVcl.pas (TComponent + TTimer) is indexed into
  library-Test.sqlite, and the code under test into proj.sqlite. That is the
  exact split the bug lived in -- the type is absent from the project store and
  present in the library store -- and it makes the test hermetic and fast.

  The controls are the point. `TTimer.Create(nil)` has NO owner, so it is a real
  leak and must still fire; it differs from the owned case in one argument, so a
  fix that simply stopped reporting TComponent descendants would fail here.

  B. used-before-assignment: a KNOWN, still-open false positive
  -------------------------------------------------------------
  The backlog note claimed the bug was "an `out` argument is put in Reads as
  well as CallDefs". MEASURED, that is false: CollectReadsAndCallDefs adds a
  bare identifier argument to CallDefs ONLY (Flow.Lattices.pas, the exprCall
  branch -- `if Arg.NodeType <> 'identifier' then Walk(Arg, False)`). Passing an
  unassigned local as a bare argument has never produced this finding, for `out`
  or `var`, so resolving the callee's parameter modifiers would have fixed
  nothing. That mechanism was written, measured at zero, and removed.

  The REAL shape, from DataCopy uAlertGrouper.pas:384, is an ordering problem
  WITHIN one CFG item:

      if FGroups.TryGetValue(LOldest, LGroup) and (LGroup.Count > 1) then

  `LGroup.Count` is a dot-expression, so LGroup is a genuine READ. The call that
  defines LGroup sits in the same item, and an item's CallDefs are applied only
  after all its reads are checked -- so the read is judged against the state
  BEFORE the call. Delphi's `and` short-circuits, so LGroup.Count is evaluated
  only when TryGetValue returned True and therefore assigned it. False positive.

  Case B below reproduces it hermetically and asserts that it STILL FIRES, the
  way run_concat_in_loop_precision asserts its remaining limitation: the day
  intra-item evaluation order is modelled, this test says exactly what changed.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-flow-store-precision"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WritePas([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$libSrc  = Join-Path $WorkDir 'lib'
$projSrc = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory $libSrc  | Out-Null
New-Item -ItemType Directory $projSrc | Out-Null

# --- the "library": the only place TComponent/TTimer are declared -------------
WritePas (Join-Path $libSrc 'FakeVcl.pas') @"
unit FakeVcl;

interface

type
  TComponent = class
  public
    constructor Create(AOwner: TComponent);
  end;

  TTimer = class(TComponent)
  end;

implementation

constructor TComponent.Create(AOwner: TComponent);
begin
end;

end.
"@

# --- the project under test ---------------------------------------------------
WritePas (Join-Path $projSrc 'FlowCases.pas') @"
unit FlowCases;

interface

uses
  FakeVcl;

type
  TWirer = class(TComponent)
  public
    Tag: Integer;
    procedure Owned;
    procedure Orphan;
  end;

procedure ShortCircuitRead;

implementation

function TryFetch(const AKey: string; out AValue: TWirer): Boolean;
begin
  AValue := nil;
  Result := True;
end;

procedure TWirer.Owned;
var
  T: TTimer;
begin
  T := TTimer.Create(Self);
end;

procedure TWirer.Orphan;
var
  T: TTimer;
begin
  T := TTimer.Create(nil);
end;

procedure ShortCircuitRead;
var
  G: TWirer;
begin
  if TryFetch('k', G) and (G.Tag > 1) then Writeln('hit');
end;

end.
"@

$cases = Join-Path $projSrc 'FlowCases.pas'
$lines = [System.IO.File]::ReadAllLines($cases)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$lnOwned  = LineOf 'T := TTimer.Create(Self);'
$lnOrphan = LineOf 'T := TTimer.Create(nil);'
$lnShort  = LineOf "if TryFetch('k', G) and (G.Tag > 1) then Writeln('hit');"
Check 'all three fixture statements located' (
  @($lnOwned,$lnOrphan,$lnShort) -notcontains -1) `
  ("lines {0}" -f (@($lnOwned,$lnOrphan,$lnShort) -join ', '))

# --- index both, as two separate databases -----------------------------------
$libDb  = Join-Path $WorkDir 'library-Test.sqlite'
$projDb = Join-Path $WorkDir 'proj.sqlite'
& $Exe index $libSrc  --db $libDb  2>&1 | Out-Null
& $Exe index $projSrc --db $projDb 2>&1 | Out-Null
Check 'both indexes built' ((Test-Path $libDb) -and (Test-Path $projDb))

# lint-all takes the FIRST --db as the project index and the `library-*` one as
# the library slot, which is exactly the pairing the fix depends on.
$raw = & $Exe lint-all --db $projDb --db $libDb 2>&1
$fired = @{}
foreach ($line in $raw) {
  if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+([a-z0-9-]+):') {
    $fired["$($Matches[2])@$($Matches[1])"] = $true
  }
}
Write-Host ("  findings: {0}" -f (($fired.Keys | Sort-Object) -join ', ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'A. object-leak: ownership resolved through the LIBRARY store' -ForegroundColor Cyan
Check "TTimer.Create(Self) is OWNED, not a leak (line $lnOwned)" `
  (-not $fired.ContainsKey("object-leak@$lnOwned")) `
  'TTimer is absent from the project index and present in the library index'
Check "TTimer.Create(nil) IS a leak (line $lnOrphan)" `
  ($fired.ContainsKey("object-leak@$lnOrphan")) `
  'one argument apart from the case above -- keeps the fix honest'

Write-Host ''
Write-Host 'B. KNOWN LIMITATION, asserted so a future fix is visible' -ForegroundColor Cyan
Check "short-circuited read after an out-def still fires (line $lnShort)" `
  ($fired.ContainsKey("used-before-assignment@$lnShort")) `
  'flip this when intra-item evaluation order is modelled'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
