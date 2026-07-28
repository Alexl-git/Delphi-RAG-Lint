<#
  run_proptree_ancestor_climb.ps1 -- the ancestor CLIMB must not stop at an edge
  the INDEX left unresolved.

  THE BUG (INBOX-proptree-ancestor-climb-stops-early.md, 2026-07-28, reproduced on
  1.2.1-alpha against library-Win64.sqlite): ResolveAncestry resolves an ancestor
  NAME to a symbol id only when it is unambiguous -- exactly one candidate in the
  declaring file's uses-scope, or a single global definition. Everything else is
  stored with ancestor_symbol_id = NULL, and GetTransitiveAncestors treats a NULL
  edge as a name-only LEAF and stops climbing. Two independent causes make that
  fire constantly on real code:

    1. unit_uses.target_file_id is NULL for every DOTTED unit (58% of all rows in
       library-Win64: 49527 / 85157), because UnitNameNorm stores the dotted TAIL
       ('Vcl.Controls' -> 'controls') while ResolveUnitUseTargets keys on the FULL
       file stem ('vcl.controls'). They can never match. ResolveAncestry's
       uses-scope disambiguation therefore degenerates to same-file-only, so every
       CROSS-UNIT hop onto an ambiguous name (TWinControl exists in both
       Vcl.Controls and FMX.Controls.Win) is abandoned -- losing the whole
       TWinControl/TControl/TComponent surface for nearly all of VCL.
    2. A TYPE ALIAS ancestor ('TcxBaseButton = TCustomButton;') is never resolved
       at all: ResolveAncestry's candidate query is kind IN ('class','interface'),
       and an alias is kind='type'.

  WHY EVERY UNIT NAME IN THIS FIXTURE IS DOTTED, AND WHY THAT IS THE POINT: an
  earlier draft of this fixture used plain names (VclKit, StdKit) and group B
  PASSED on the broken exe. For a plain unit the tail IS the full stem, so
  target_file_id resolves, the uses-scope is intact, and the ambiguous hop is
  disambiguated correctly. Dotted-ness is the entire difference between the
  reporter's working rows and his failing ones, so the fixture must be dotted or
  it asserts nothing. Group E pins that mechanism directly.

  THE FIX, in two places:
    QUERY-TIME (works on indexes that already exist -- no reindex, which matters
      because the library DBs may not be rebuilt yet): GetTransitiveAncestors
      LATE-RESOLVES an unresolved edge through the scope-aware, alias-following
      resolver in STRICT mode -- resolve only when exactly ONE candidate survives,
      REFUSE when more than one does. That resolver scopes by TEXTUAL unit name
      from unit_uses.unit_name, so it is immune to cause 1 above, and it follows
      type aliases, so it also covers cause 2.
    INDEX-TIME (correct at rest, but only after a rebuild): ResolveUnitUseTargets
      now matches a dotted unit name against the full dotted file stem, and falls
      back to tail-matching only when that tail is unambiguous.

  FIXTURE (five units, indexed as one tree, ALL DOTTED):
    Vcl.Kit.pas   TComponentBase(TPersistent) [Tag]  <- TWinControl [Left]
                  'TWinControl' is deliberately AMBIGUOUS (Fmx.Kit declares one
                  too); 'TComponentBase' is deliberately UNIQUE (the control hop).
    Fmx.Kit.pas   TFmxBase(TPersistent) [FmxPoison] <- TWinControl [FmxLeft]
                  the DECOY. No unit that must climb into Vcl.Kit ever uses it.
    Std.Kit.pas   uses Vcl.Kit (NOT Fmx.Kit).
                  TCustomEdit(TWinControl) [Text] <- TEdit [EditMarker]
                  == the Vcl.StdCtrls.TEdit case: a CROSS-UNIT hop on an ambiguous
                     name, disambiguated only by the uses clause.
    Cx.Kit.pas    uses Std.Kit. 'TcxBaseButton = TCustomEdit;' (alias, same unit)
                  TcxCustomButton(TcxBaseButton, ICxSkin, ICxHint) -- a MULTI-LINE
                  header with interfaces == the cxButtons.TcxCustomButton case.
    Ambig.Kit.pas uses Vcl.Kit AND Fmx.Kit, then descends from 'TWinControl'.
                  BOTH candidates are in scope: the resolver must resolve NOTHING.

  Load-bearing assertions (proptree --no-write-back --format json):
    A CONTROL      Vcl.Kit.TWinControl already climbs to TComponentBase (Tag).
                   This hop is UNIQUE-named, passes before AND after the fix, and
                   is what proves the fixture and the walk are capable at all --
                   without it, B failing would not distinguish "climb broken" from
                   "fixture never had the property".
    B DEFECT 1     Std.Kit.TEdit reaches Left (Vcl.Kit.TWinControl) and Tag
                   (Vcl.Kit.TComponentBase), and NEVER the Fmx.Kit decoy's FmxLeft
                   / FmxPoison. declared_in is asserted, not just the leaf name --
                   the whole bug is the right name arriving from the wrong unit.
    C DEFECT 2     Cx.Kit.TcxCustomButton climbs THROUGH the type alias and the
                   multi-line interface header to Text, Left and Tag.
    D REFUSAL      Ambig.Kit.TAmbiguous emits its OWN AmbMarker (de-vacuating: the
                   tree really was built) but NEITHER ancestor surface. Absence
                   over wrong.
    E ROOT CAUSE   the index-time guard: a DOTTED uses row resolves target_file_id,
                   and the ambiguous cross-unit edge is stored RESOLVED and points
                   at the Vcl.Kit class, not the Fmx.Kit one.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-climb"
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

Write-Ascii (Join-Path $work 'Vcl.Kit.pas') @'
unit Vcl.Kit;

interface

type
  // UNIQUE simple name -> this hop resolves even before the fix (control A).
  TComponentBase = class(TPersistent)
  private
    FTag: Integer;
  published
    property Tag: Integer read FTag write FTag;
  end;

  // AMBIGUOUS simple name: Fmx.Kit declares a TWinControl too.
  TWinControl = class(TComponentBase)
  private
    FLeft: Integer;
  published
    property Left: Integer read FLeft write FLeft;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Fmx.Kit.pas') @'
unit Fmx.Kit;

interface

type
  TFmxBase = class(TPersistent)
  private
    FFmxPoison: Integer;
  published
    property FmxPoison: Integer read FFmxPoison write FFmxPoison;
  end;

  // The DECOY. Same simple name as Vcl.Kit's, completely different surface.
  // If the climb ever grafts THIS onto a Vcl.Kit descendant the test fails.
  TWinControl = class(TFmxBase)
  private
    FFmxLeft: Integer;
  published
    property FmxLeft: Integer read FFmxLeft write FFmxLeft;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Std.Kit.pas') @'
unit Std.Kit;

interface

uses
  Vcl.Kit;

type
  // The Vcl.StdCtrls.TCustomEdit case: cross-unit hop onto the AMBIGUOUS name
  // 'TWinControl'. Only the uses clause says which one is meant.
  TCustomEdit = class(TWinControl)
  private
    FText: string;
  published
    property Text: string read FText write FText;
  end;

  TEdit = class(TCustomEdit)
  private
    FEditMarker: Integer;
  published
    property EditMarker: Integer read FEditMarker write FEditMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Cx.Kit.pas') @'
unit Cx.Kit;

interface

uses
  Std.Kit;

type
  ICxSkin = interface
    ['{1B7F0C2A-0001-4A00-9000-000000000001}']
    procedure Skin;
  end;

  ICxHint = interface
    ['{1B7F0C2A-0002-4A00-9000-000000000002}']
    procedure Hint;
  end;

  // The cxButtons.TcxBaseButton case: a TYPE ALIAS, unique name, same unit.
  // ResolveAncestry never resolves it (kind='type', not 'class').
  TcxBaseButton = TCustomEdit;

  // Multi-line header carrying interfaces, exactly like cxButtons.TcxCustomButton.
  TcxCustomButton = class(TcxBaseButton,
    ICxSkin,
    ICxHint)
  private
    FCxMarker: Integer;
  published
    property CxMarker: Integer read FCxMarker write FCxMarker;
  end;

implementation

procedure TcxCustomButton.Skin;
begin
end;

procedure TcxCustomButton.Hint;
begin
end;

end.
'@

Write-Ascii (Join-Path $work 'Ambig.Kit.pas') @'
unit Ambig.Kit;

interface

uses
  Vcl.Kit, Fmx.Kit;

type
  // BOTH Vcl.Kit.TWinControl and Fmx.Kit.TWinControl are in scope here. Nothing
  // in the index can say which is meant, so the resolver must resolve NEITHER.
  TAmbiguous = class(TWinControl)
  private
    FAmbMarker: Integer;
  published
    property AmbMarker: Integer read FAmbMarker write FAmbMarker;
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'climb.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

# Read-only (--no-write-back) so no query can mutate the index between assertions.
function Get-Tree([string]$QName) {
  $raw = (& $Exe proptree --qname $QName --no-write-back --format json --db $db) -join "`n"
  return ($raw | ConvertFrom-Json)
}
# Top-level leaves only (dotted paths are recursions into class-typed properties,
# not the root's own inherited surface -- the report measures the same way).
function Top([object]$Tree) { return @(@($Tree.properties) | Where-Object { $_.path -notmatch '\.' }) }
function HasLeaf([object[]]$Top, [string]$Name) { return (@($Top | Where-Object { $_.path -eq $Name }).Count -gt 0) }
function LeafUnit([object[]]$Top, [string]$Name) {
  $n = @($Top | Where-Object { $_.path -eq $Name }) | Select-Object -First 1
  if ($null -eq $n) { return '<absent>' } else { return $n.declared_in }
}
function ClimbOf([object[]]$Top) { return (($Top | Select-Object -ExpandProperty declared_in -Unique) -join ' -> ') }

# --- A. CONTROL: a UNIQUE-named ancestor hop already climbs (before AND after). ---
Write-Host ''
Write-Host 'A. CONTROL -- Vcl.Kit.TWinControl -> TComponentBase (unique name)' -ForegroundColor Cyan
$aTop = Top (Get-Tree 'Vcl.Kit.TWinControl')
Check 'A1 control: TWinControl emits its own Left'           (HasLeaf $aTop 'Left') ("climb=" + (ClimbOf $aTop))
Check 'A2 control: climb reaches TComponentBase (Tag)'       (HasLeaf $aTop 'Tag')  ("climb=" + (ClimbOf $aTop))
Check 'A3 control: Tag is declared_in Vcl.Kit.TComponentBase' ((LeafUnit $aTop 'Tag') -eq 'Vcl.Kit.TComponentBase') ("declared_in=" + (LeafUnit $aTop 'Tag'))

# --- B. DEFECT 1: cross-unit hop onto an AMBIGUOUS name, uses-disambiguated. ------
Write-Host ''
Write-Host 'B. DEFECT 1 -- Std.Kit.TEdit must climb through the ambiguous TWinControl' -ForegroundColor Cyan
$bTop = Top (Get-Tree 'Std.Kit.TEdit')
Check 'B1 own EditMarker present (de-vacuating: tree really built)' (HasLeaf $bTop 'EditMarker') ("climb=" + (ClimbOf $bTop))
Check 'B2 reaches Std.Kit.TCustomEdit (Text)'                (HasLeaf $bTop 'Text') ("climb=" + (ClimbOf $bTop))
Check 'B3 reaches Vcl.Kit.TWinControl (Left)'                (HasLeaf $bTop 'Left') ("climb=" + (ClimbOf $bTop))
Check 'B4 Left comes from Vcl.Kit.TWinControl, not Fmx.Kit'  ((LeafUnit $bTop 'Left') -eq 'Vcl.Kit.TWinControl') ("declared_in=" + (LeafUnit $bTop 'Left'))
Check 'B5 reaches Vcl.Kit.TComponentBase (Tag)'              (HasLeaf $bTop 'Tag')  ("climb=" + (ClimbOf $bTop))
Check 'B6 Tag comes from Vcl.Kit.TComponentBase'             ((LeafUnit $bTop 'Tag') -eq 'Vcl.Kit.TComponentBase') ("declared_in=" + (LeafUnit $bTop 'Tag'))
Check 'B7 NEVER the FMX decoy FmxLeft'                       (-not (HasLeaf $bTop 'FmxLeft'))   ("declared_in=" + (LeafUnit $bTop 'FmxLeft'))
Check 'B8 NEVER the FMX decoy FmxPoison'                     (-not (HasLeaf $bTop 'FmxPoison')) ("declared_in=" + (LeafUnit $bTop 'FmxPoison'))

# --- C. DEFECT 2: type-alias ancestor + multi-line interface header. --------------
Write-Host ''
Write-Host 'C. DEFECT 2 -- Cx.Kit.TcxCustomButton must climb through the type alias' -ForegroundColor Cyan
$cTop = Top (Get-Tree 'Cx.Kit.TcxCustomButton')
Check 'C1 own CxMarker present (de-vacuating)'               (HasLeaf $cTop 'CxMarker') ("climb=" + (ClimbOf $cTop))
Check 'C2 climbs the alias into Std.Kit.TCustomEdit (Text)'  (HasLeaf $cTop 'Text') ("climb=" + (ClimbOf $cTop))
Check 'C3 Text is declared_in Std.Kit.TCustomEdit'           ((LeafUnit $cTop 'Text') -eq 'Std.Kit.TCustomEdit') ("declared_in=" + (LeafUnit $cTop 'Text'))
Check 'C4 continues to Vcl.Kit.TWinControl (Left)'           (HasLeaf $cTop 'Left') ("climb=" + (ClimbOf $cTop))
Check 'C5 continues to Vcl.Kit.TComponentBase (Tag)'         (HasLeaf $cTop 'Tag')  ("climb=" + (ClimbOf $cTop))
Check 'C6 NEVER the FMX decoy FmxLeft'                       (-not (HasLeaf $cTop 'FmxLeft')) ("declared_in=" + (LeafUnit $cTop 'FmxLeft'))

# --- D. REFUSAL: two in-scope candidates -> resolve NOTHING (absence over wrong). --
Write-Host ''
Write-Host 'D. REFUSAL -- Ambig.Kit.TAmbiguous has BOTH TWinControls in scope' -ForegroundColor Cyan
$dTop = Top (Get-Tree 'Ambig.Kit.TAmbiguous')
Check 'D1 own AmbMarker present (de-vacuating: absence is a REFUSAL, not an empty tree)' (HasLeaf $dTop 'AmbMarker') ("climb=" + (ClimbOf $dTop))
Check 'D2 does NOT graft Vcl.Kit.TWinControl (Left)'         (-not (HasLeaf $dTop 'Left'))      ("declared_in=" + (LeafUnit $dTop 'Left'))
Check 'D3 does NOT graft Vcl.Kit.TComponentBase (Tag)'       (-not (HasLeaf $dTop 'Tag'))       ("declared_in=" + (LeafUnit $dTop 'Tag'))
Check 'D4 does NOT graft Fmx.Kit.TWinControl (FmxLeft)'      (-not (HasLeaf $dTop 'FmxLeft'))   ("declared_in=" + (LeafUnit $dTop 'FmxLeft'))
Check 'D5 does NOT graft Fmx.Kit.TFmxBase (FmxPoison)'       (-not (HasLeaf $dTop 'FmxPoison')) ("declared_in=" + (LeafUnit $dTop 'FmxPoison'))

# --- E. ROOT CAUSE, at rest: the INDEX-TIME half of the fix. ----------------------
# Query the stored tables directly rather than the engine's own answer, so this
# group cannot pass merely because the query-time late resolution papered over it.
Write-Host ''
Write-Host 'E. ROOT CAUSE -- dotted uses rows must resolve target_file_id at index time' -ForegroundColor Cyan
$pySql = Join-Path $WorkDir 'sql.py'
Write-Ascii $pySql @'
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1].replace("\\", "/"), uri=True)
print("\n".join("|".join("" if v is None else str(v) for v in r)
                for r in con.execute(sys.argv[2]).fetchall()))
con.close()
'@
function Sql([string]$Q) { return ((python $pySql $db $Q) -join "`n").Trim() }

$e1 = Sql "SELECT COUNT(*) FROM unit_uses WHERE unit_name='Vcl.Kit' AND target_file_id IS NOT NULL"
Check 'E1 dotted "uses Vcl.Kit" resolves target_file_id' ($e1 -eq '2') "rows with a target=$e1 (expected 2: Std.Kit + Ambig.Kit)"

$e2 = Sql "SELECT COUNT(*) FROM unit_uses WHERE target_file_id IS NULL"
Check 'E2 no dotted uses row is left unresolved' ($e2 -eq '0') "unresolved rows=$e2"

# The ambiguous cross-unit edge must be stored RESOLVED, and pointed at Vcl.Kit.
$e3 = Sql @"
SELECT f.path FROM symbols s
  JOIN type_ancestors ta ON ta.symbol_id = s.id
  JOIN symbols a ON a.id = ta.ancestor_symbol_id
  JOIN files   f ON f.id = a.file_id
 WHERE s.qualified_name = 'Std.Kit.TCustomEdit' AND ta.ancestor_name = 'TWinControl'
"@
Check 'E3 stored edge TCustomEdit->TWinControl resolves to the Vcl.Kit file' ($e3 -match 'Vcl\.Kit\.pas$') "target=$e3"

# ...and the genuinely ambiguous one must still be stored UNRESOLVED.
$e4 = Sql "SELECT COUNT(*) FROM symbols s JOIN type_ancestors ta ON ta.symbol_id=s.id WHERE s.qualified_name='Ambig.Kit.TAmbiguous' AND ta.ancestor_name='TWinControl' AND ta.ancestor_symbol_id IS NULL"
Check 'E4 genuinely ambiguous edge stays UNRESOLVED at index time' ($e4 -eq '1') "unresolved-count=$e4"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
