<#
  run_forward_decl_shadow.ps1 -- a FORWARD-DECLARATION stub must never shadow
  the real declaration of the same class in a BY-NAME lookup.

  REPORTED BY THE CONVERTER TEAM, 2026-09-14
  (docs\INBOX-forward-decl-shadows-real-class-declaration.md). DevExpress units
  forward-declare their classes in one block and declare them for real further
  down:

      TcxCustomButton = class;                       // line 53  -- stub
      TcxCustomButton = class(TcxBaseButton, ...)    // line 531 -- the body

  Both land in `symbols` as kind='class' rows. The stub has NULL heritage, a
  single-line span, no children and NO type_ancestors rows; it also has the
  LOWER id. FindSymbolsByQualifiedName already orders a body before a stub
  (run_qname_row_order.ps1), but FindSymbolsByExactName -- the BY-NAME lookup --
  ordered by qualified_name alone, and the two rows share one qualified name, so
  the stub came first. Every consumer that takes the first class-kind row by
  NAME therefore started its walk at a symbol with no ancestors and no members.
  Measured on library-Win64.sqlite before the fix:

      query ancestors --name TcxCustomButton        -> (none)
      query ancestors --name TcxButtonImageOptions  -> (none)
      query ancestors --name TcxButton --of TControl -> True   (iterates ALL
                                                        candidates, so it was
                                                        never affected)

  The two verbs DISAGREED about the same class -- one said it had no ancestors,
  the other that it descended from TControl. That disagreement is the assertion
  here, because it cannot be satisfied by an implementation that is broken in a
  new way.

  WHAT THE NOTE GOT WRONG, recorded so nobody re-derives it: neither of its two
  headline symptoms is caused by this shadow. `query descendants` walks
  type_ancestors by NAME and the stub owns no rows there, so it is invisible to
  that verb (its real cause is the type-alias hop -- run_descendants_alias_hop.ps1);
  and proptree already routes every class pick through BodyOf. The shadow is
  real, and this guard pins the consumers it DOES reach.

  CASES
    precondition  FwdShadow.TShadowMid owns exactly 2 class rows, exactly 1 of
                  them a stub by the engine's own predicate. ASSERTED, not
                  assumed -- if the parser stops emitting a stub symbol this
                  whole shape is gone and CASE A is vacuously green.
    de-vacuator   under `ORDER BY qualified_name, id` ALONE (the pre-fix order)
                  the STUB sorts first, so the leading term is doing the work.
    A (the defect) `query ancestors --name TShadowMid` lists TShadowRoot. RED
                  against the pre-fix engine: `(none)`.
    A2            the list verb and the Boolean verb AGREE: `--of TShadowRoot`
                  is True (already true pre-fix) AND the list names TShadowRoot.
    P1            POSITIVE CONTROL, the chain THROUGH a forward-declared class:
                  `query ancestors --name TShadowLeaf` reaches TShadowMid and
                  TShadowRoot. Passes pre-fix -- index-time ResolveAncestry
                  already drops stubs (step 1b) -- so it proves the fixture's
                  ancestry is sound and the stub is the only variable.
    P2            POSITIVE CONTROL, the TSizeConstraints shape: TShadowTwin is
                  declared for REAL in two units, no stub anywhere. Its
                  ancestors resolve pre-fix and must still resolve. So
                  "duplicate rows" is not the defect and the fix must not treat
                  it as one.
    N1            NEGATIVE CONTROL: TShadowOnly's ONLY row is a stub. It must
                  still resolve to a class with NO ancestors -- exit 0, `(none)`
                  -- and never to some other class's chain. (A real analogue: a
                  class whose body sits in an inactive {$IFDEF} branch.)
    N2            the not-found case stays distinguishable: exit 1.

  RED SIGNATURE, observed against the pre-fix engine (drag-lint 1.12.0-alpha,
  third_party\dll-win64, 2026-09-14): CASE A and the list half of A2 FAIL;
  every precondition, de-vacuator, P and N line PASSES. Anything else means the
  FIXTURE is being measured, not the engine.

  Usage: pwsh -File tests/autotest/run_forward_decl_shadow.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-forward-decl-shadow"
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

Write-Ascii (Join-Path $work 'FwdShadow.pas') @'
unit FwdShadow;

interface

type
  // The DevExpress shape: a block of forward declarations, then the bodies.
  TShadowMid  = class;
  // NEGATIVE CONTROL: a stub whose body is NOWHERE in the index (think: the
  // body lives in an inactive {$IFDEF} branch). Must resolve to a class with
  // no ancestors -- never to another class's chain.
  TShadowOnly = class;

  TShadowRoot = class(TPersistent)
  private
    FRootMark: Integer;
  published
    property RootMark: Integer read FRootMark write FRootMark;
  end;

  // The real declaration. Same name, same qualified name, HIGHER id than the
  // stub above -- so under any id-ordered pick the stub wins.
  TShadowMid = class(TShadowRoot)
  private
    FMidMark: Integer;
    FLink   : TShadowOnly;
  published
    property MidMark: Integer read FMidMark write FMidMark;
  end;

  // Inherits THROUGH the forward-declared class. Its own row is unambiguous, so
  // this is the positive control for the chain itself.
  TShadowLeaf = class(TShadowMid)
  end;

implementation

end.
'@

# P2: the TSizeConstraints shape -- one name, TWO REAL declarations in two
# units, no stub anywhere. Duplicate rows are not the defect.
Write-Ascii (Join-Path $work 'TwinA.pas') @'
unit TwinA;

interface

uses
  FwdShadow;

type
  TShadowTwin = class(TShadowRoot)
  private
    FTwinA: Integer;
  published
    property TwinA: Integer read FTwinA write FTwinA;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'TwinB.pas') @'
unit TwinB;

interface

uses
  FwdShadow;

type
  TShadowTwin = class(TShadowRoot)
  private
    FTwinB: Integer;
  published
    property TwinB: Integer read FTwinB write FTwinB;
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'shadow.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

# --- Probes. ----------------------------------------------------------------------
$script:PySql = Join-Path $WorkDir 'sql.py'
Write-Ascii $script:PySql @'
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1].replace("\\", "/"), uri=True)
print("\n".join("|".join("" if v is None else str(v) for v in r)
                for r in con.execute(sys.argv[2]).fetchall()))
con.close()
'@
function Sql([string]$Q) { return ((python $script:PySql $db $Q) -join "`n").Trim() }

# stdout and stderr captured SEPARATELY (the engine writes '(loaded defaults
# from ...)' to stderr), and NEVER through a pipe that could break early --
# exit codes are only trustworthy when captured into a variable first.
# The engine pretty-prints its JSON over many lines, so take everything from
# the first line that opens an object to the end -- not just that one line.
function JsonFrom([string[]]$Lines) {
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i].TrimStart().StartsWith('{')) { return ($Lines[$i..($Lines.Count - 1)] -join "`n") }
  }
  return ''
}
function Ancestors([string]$Name) {
  $raw = @(& $Exe query ancestors --name $Name --json --db $db 2>$null) | ForEach-Object { "$_" }
  $code = $LASTEXITCODE
  $json = JsonFrom $raw
  $names = @()
  if ($json) {
    $o = $json | ConvertFrom-Json
    $names = @(@($o.ancestors) | ForEach-Object { $_.name })
  }
  return @{ Code = $code; Names = $names; Raw = ($raw -join ' | ') }
}
function AncestorsText([string]$Name) {
  $raw = @(& $Exe query ancestors --name $Name --db $db 2>$null) | ForEach-Object { "$_" }
  return @{ Code = $LASTEXITCODE; Text = ($raw -join "`n") }
}
function Descends([string]$Name, [string]$Of) {
  $raw = @(& $Exe query ancestors --name $Name --of $Of --json --db $db 2>$null) | ForEach-Object { "$_" }
  $json = JsonFrom $raw
  if (-not $json) { return $null }
  return [bool](($json | ConvertFrom-Json).is_descendant)
}

# The engine's own stub predicate, transcribed (IsStub / IsForwardDeclClass).
$stubTerm = "kind IN ('class','interface') AND COALESCE(TRIM(heritage),'')='' AND end_line<=start_line"

# --- preconditions --------------------------------------------------------------
Write-Host ''
Write-Host 'preconditions -- the fixture really has the DevExpress shape' -ForegroundColor Cyan
$midRows = Sql "SELECT COUNT(*) FROM symbols WHERE name='TShadowMid' AND kind='class'"
Check 'precondition: TShadowMid owns exactly 2 class rows' ($midRows -eq '2') "rows=$midRows"
$midStubs = Sql "SELECT COUNT(*) FROM symbols WHERE name='TShadowMid' AND $stubTerm"
Check "precondition: exactly ONE of them is a stub by the engine's own predicate" ($midStubs -eq '1') `
  "stub rows=$midStubs -- if 0 the parser stopped emitting a symbol for a forward declaration and this shape is gone"
$stubTa = Sql "SELECT COUNT(*) FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id WHERE s.name='TShadowMid' AND $stubTerm"
Check 'precondition: the stub owns NO type_ancestors rows (so a walk started there is empty)' ($stubTa -eq '0') "rows=$stubTa"
$tieFirst = Sql "SELECT CASE WHEN $stubTerm THEN 'STUB' ELSE 'BODY' END FROM symbols WHERE name='TShadowMid' ORDER BY qualified_name, id LIMIT 1"
Check 'de-vacuator: under (qualified_name, id) ALONE the STUB would be first' ($tieFirst -eq 'STUB') `
  "pre-fix-order first row=$tieFirst -- if this says BODY, CASE A passes for free"
$onlyRows = Sql "SELECT COUNT(*) FROM symbols WHERE name='TShadowOnly' AND kind='class'"
Check 'precondition: TShadowOnly owns exactly 1 row, and it is a stub' (($onlyRows -eq '1') -and ((Sql "SELECT COUNT(*) FROM symbols WHERE name='TShadowOnly' AND $stubTerm") -eq '1')) "rows=$onlyRows"
$twinRows  = Sql "SELECT COUNT(*) FROM symbols WHERE name='TShadowTwin' AND kind='class'"
$twinStubs = Sql "SELECT COUNT(*) FROM symbols WHERE name='TShadowTwin' AND $stubTerm"
Check 'precondition: TShadowTwin owns 2 class rows and NEITHER is a stub (the TSizeConstraints shape)' (($twinRows -eq '2') -and ($twinStubs -eq '0')) "rows=$twinRows stubs=$twinStubs"

# --- CASE A: the defect ----------------------------------------------------------
Write-Host ''
Write-Host 'CASE A: query ancestors --name <forward-declared class> starts at the BODY' -ForegroundColor Cyan
$a = Ancestors 'TShadowMid'
Check 'CASE A: exit 0' ($a.Code -eq 0) "exit=$($a.Code)"
Check "CASE A: `query ancestors --name TShadowMid` lists TShadowRoot" ($a.Names -contains 'TShadowRoot') `
  ("got: [" + ($a.Names -join ', ') + "] -- EMPTY means the stub row won the by-name pick and the walk started at a symbol with no ancestor rows")
$aText = AncestorsText 'TShadowMid'
Check 'CASE A: the text form is not (none)' ($aText.Text -notmatch '\(none\)') "text=$($aText.Text -replace "`n",' | ')"

# --- CASE A2: the list verb and the Boolean verb must AGREE ----------------------
Write-Host ''
Write-Host 'CASE A2: `--of` (iterates every candidate) and the list (first pick) agree' -ForegroundColor Cyan
$desc = Descends 'TShadowMid' 'TShadowRoot'
Check 'A2: TShadowMid --of TShadowRoot is True (unaffected pre-fix; iterates ALL candidates)' ($desc -eq $true) "is_descendant=$desc"
Check 'A2: ...and the list verb names the same ancestor (this is the half that was RED)' (($desc -eq $true) -and ($a.Names -contains 'TShadowRoot')) `
  "is_descendant=$desc list=[$($a.Names -join ', ')]"

# --- P1: the chain THROUGH the forward-declared class ---------------------------
Write-Host ''
Write-Host 'P1 (positive control): a class inheriting THROUGH the forward-declared one' -ForegroundColor Cyan
$p1 = Ancestors 'TShadowLeaf'
Check 'P1: TShadowLeaf reaches TShadowMid' ($p1.Names -contains 'TShadowMid') "got: [$($p1.Names -join ', ')]"
Check 'P1: TShadowLeaf reaches TShadowRoot (index-time step 1b already drops stubs)' ($p1.Names -contains 'TShadowRoot') "got: [$($p1.Names -join ', ')]"

# --- P2: two REAL declarations, no stub --------------------------------------------
Write-Host ''
Write-Host 'P2 (positive control): the TSizeConstraints shape still resolves' -ForegroundColor Cyan
$p2 = Ancestors 'TShadowTwin'
Check 'P2: exit 0' ($p2.Code -eq 0) "exit=$($p2.Code)"
Check 'P2: TShadowTwin lists TShadowRoot (duplicate REAL rows are not the defect)' ($p2.Names -contains 'TShadowRoot') "got: [$($p2.Names -join ', ')]"

# --- N1: a lone stub resolves to NOTHING, not to garbage ---------------------------
Write-Host ''
Write-Host 'N1 (negative control): a class whose ONLY row is a stub' -ForegroundColor Cyan
$n1 = AncestorsText 'TShadowOnly'
Check 'N1: exit 0 (the stub IS still a class-kind symbol; the name is found)' ($n1.Code -eq 0) "exit=$($n1.Code) text=$($n1.Text -replace "`n",' | ')"
Check 'N1: (none) -- no ancestors invented from some other class' ($n1.Text -match '\(none\)') "text=$($n1.Text -replace "`n",' | ')"
$n1j = Ancestors 'TShadowOnly'
Check 'N1: json ancestors list is empty' ($n1j.Names.Count -eq 0) "got: [$($n1j.Names -join ', ')]"

# --- N2: not-found stays distinguishable -------------------------------------------
$n2 = AncestorsText 'TNoSuchShadowClass'
Check 'N2: an unknown name still exits 1 (type not found)' ($n2.Code -eq 1) "exit=$($n2.Code)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
