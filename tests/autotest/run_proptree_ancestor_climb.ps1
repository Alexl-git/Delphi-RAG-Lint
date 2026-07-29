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

    1. unit_uses.target_file_id is NULL for essentially every DOTTED unit -- in
       library-Win64, 38390 of the 38512 dotted rows (99.7%), inside 49527 NULL
       rows out of 85157. CLASSIFIER, because two earlier drafts of this header got
       the split wrong and both times it was a classifier error: replay the FIXED
       procedure's BOTH passes over the NULL rows (files filtered to .pas, stem =
       lowercased basename, tail = text after the stem's last dot, a tail claimed
       by two different stems is ambiguous). Pass 1 resolves 38022, pass 2 a
       further 4592, 6381 are correctly refused on an ambiguous tail, and 532 name
       nothing indexed. So 48995 of the 49527 name an indexed unit. Draft 1 charged
       all 49527 to the defect and called it "58%"; draft 2 classified by full-stem
       equality -- pass 1's criterion alone -- and so called all 11137 plain-name
       NULLs missing data, when 10790 of them match an indexed file TAIL, which is
       exactly what pass 2 exists for (`uses SysUtils` -> System.SysUtils.pas).
       The cause: UnitNameNorm stores the dotted TAIL
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
    Dfm.Kit.pas   + Dfm.Kit.dfm -- a form unit and the .dfm the indexer stores
                  beside it, sharing a stem. TDfmCtl [DfmMarker] is AMBIGUOUS
                  (Dup.Kit declares one too), so scope is the ONLY thing that can
                  resolve an edge onto it.
    Dup.Kit.pas   the TDfmCtl decoy [DupPoison]. Nothing that must reach Dfm.Kit
                  uses it.
    PlainKit.pas  + PlainKit.dfm -- the same pair with a PLAIN name, because the
                  mis-binding is a stem collision, not a dotted-name defect.
    Cli.Kit.pas   uses Dfm.Kit and PlainKit; TCliCtl descends from TDfmCtl.
    Prog.dpr      + Prog.pas -- a PROGRAM whose stem collides with a unit's.
                  `uses Prog` names the UNIT; the .dpr is not a candidate at all.
                  TProgCtl is AMBIGUOUS (Dup.Kit declares one), so scope decides.
    UseProg.pas   uses Prog; TUseProg descends from TProgCtl.
    Upper.Kit.PAS an UPPERCASE extension, as 554 of ORM3's 757 .pas paths really
                  are. TUpCtl is AMBIGUOUS (Dup.Kit declares one too).
    UseUp.Kit.pas uses Upper.Kit; TUseUp descends from TUpCtl.

  THE FIX-ROUND-1 CRITICAL, which groups A-D could not see: ResolveUnitUseTargets
  pulled `files` unfiltered, so a form's .dfm competed with its .pas for the stem
  and, where it sorted first, won. A .dfm declares no classes, so the resulting
  scope entry is an EMPTY scope and ResolveAncestry abandons the edge -- measured
  on tests\fixtures\formsmap as 15 of 30 uses rows bound to a .dfm, and on the
  real indexes (replaying the whole unfiltered procedure and counting DISTINCT
  LOWER(TRIM(unit_name)) whose WINNING file is not a .pas) 57 in ORM3, 608 in
  library-Win64, 197 in M2022, 25 in this repo's own index. Groups B, C and D all
  stayed green through it, because the query-time late resolver is TEXTUAL and
  never reads target_file_id. Group E is the only guard; E5-E14 pin this case and
  read the stored tables, never the engine's answer.

  Those four figures were published here as 62 / 613 / 205 / 25 before 2026-07-29
  and did NOT follow from the criterion stated in the same sentence. That set is
  the union of "the WINNING file is not a .pas" with "some non-.pas file claims
  the stem, won or not". The command is committed rather than described --
  tools\measure\uses_target_replay.py, measured at c4b78d0 -- so both numbers can
  be re-derived instead of trusted.

  AND THE FIX-ROUND-1 GUARD WAS WRITTEN TO THE IMPLEMENTATION. Round 1 whitelisted
  .pas/.dpr/.dpk, and E7 asserted "no row targets a non-.pas/.dpr/.dpk" -- the
  CODE's own set, so it could not fire on the code admitting the wrong extensions.
  A `uses` clause names a UNIT: a .dpr names a program and a .dpk names a package,
  and neither declares a unit (.dpk files carry 0 symbols in all four measured
  indexes). Executed: `uses Prog` bound to Prog.dpr on both b811097 and round 1,
  un-resolving an ancestor edge that pre-T4d 0e84cc6 got RIGHT. E9-E11 assert the
  REQUIREMENT -- the target is Prog.pas, named -- not membership of any allowed
  set. E12-E14 pin the one line that keeps ORM3's 554 uppercase .PAS paths in
  scope at all, LowerCase(ExtractFileExt(..)), which nothing asserted.

  WHY 'Prog.dpr WON' HERE AND WHY THAT IS NOT A GENERAL RULE. The earlier text
  said a colliding non-unit file "ALWAYS won" because the scan is path-ordered and
  '.dpk' < '.dpr' < '.pas'. False as stated. The scan is served from the UNIQUE
  index on files.path, so the order is by RAW PATH BYTES: the extension decides
  only when everything before it is byte-identical, which is exactly the shape
  THIS FIXTURE has (Prog.dpr beside Prog.pas, same directory, same case). Real
  corpora are not that tidy -- ORM3's DFCTLIST.PAS beats DFCTLIST.dfm inside the
  extension ('P' 0x50 < 'd' 0x64), ABC5's ABCDFTIP.PAS beats Abcdftip.dfm on
  basename case, and a directory name can decide before either. Distinct used
  names whose non-.pas competitor LOSES: 5 in library-Win64, 5 in ORM3, 8 in
  M2022, 0 in this repo. The fixture pins the byte-identical-path case, and that
  is the case it should be read as pinning.

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
                   HOW STRONG D ACTUALLY IS, measured rather than counted
                   (register K38): under the mutation that removes the mechanism
                   -- AStrict:=False at the climb's call site -- only D4 and D5
                   go red. Non-strict returns InScope[0], so exactly ONE
                   candidate is grafted; D2/D3 fire only if candidate ORDER
                   flips, which a fixture-file rename could do silently. So four
                   named-leaf checks carried two checks' worth of discrimination.
                   D6 is the order-independent form and is strictly stronger than
                   all four: the refusal means the top-level surface is declared
                   by TAmbiguous ALONE, which forbids a graft from any class at
                   all. D7 de-vacuates D6 against B's grafting tree.
    E ROOT CAUSE   the index-time guard, read off the STORED tables: a DOTTED uses
                   row resolves target_file_id (E1-E2); the ambiguous cross-unit
                   edge is stored RESOLVED and points at the Vcl.Kit class, not the
                   Fmx.Kit one (E3); the genuinely ambiguous one stays unresolved
                   (E4); a uses row binds to the unit's .pas and never to the .dfm
                   beside it (E5-E7, de-vacuated by E8); never to the .dpr either
                   (E9-E10, de-vacuated by E11); and an UPPERCASE .PAS is still a
                   candidate (E12-E13, de-vacuated by E14). Every one of E5-E13
                   names the file it expects, so none of them can pass by agreeing
                   with whatever set the implementation currently allows.
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

# --- The .pas/.dfm pair (fix round 1). ResolveUnitUseTargets pulls `files` for
# every indexed file, INCLUDING the .dfm the indexer stores beside a form unit.
# Both share the stem, so whichever accumulator policy wins decides whether
# `uses Dfm.Kit` points at Dfm.Kit.pas or Dfm.Kit.dfm -- and .dfm is walked
# first. A .dfm declares no classes, so a scope entry pointing at one is an
# empty scope: ResolveAncestry then cannot see Dfm.Kit.TDfmCtl and abandons the
# edge. TDfmCtl is deliberately AMBIGUOUS (Dup.Kit declares one too) so that the
# single-global fallback cannot rescue it -- scope is the only thing that can.
Write-Ascii (Join-Path $work 'Dfm.Kit.pas') @'
unit Dfm.Kit;

interface

uses
  Vcl.Kit;

type
  // AMBIGUOUS simple name: Dup.Kit declares a TDfmCtl too. This unit has a .dfm.
  TDfmCtl = class(TComponentBase)
  private
    FDfmMarker: Integer;
  published
    property DfmMarker: Integer read FDfmMarker write FDfmMarker;
  end;

implementation

{$R *.dfm}

end.
'@

Write-Ascii (Join-Path $work 'Dfm.Kit.dfm') @'
object DfmCtl: TDfmCtl
  Left = 0
  Top = 0
  Caption = 'Kit'
end
'@

Write-Ascii (Join-Path $work 'Dup.Kit.pas') @'
unit Dup.Kit;

interface

type
  // The DECOY that makes 'TDfmCtl' ambiguous. Nothing that must reach Dfm.Kit
  // ever uses this unit.
  TDfmCtl = class(TPersistent)
  private
    FDupPoison: Integer;
  published
    property DupPoison: Integer read FDupPoison write FDupPoison;
  end;

  // Same job for the .dpr pair: without this, Prog.TProgCtl is the single global
  // definition and PickCandidate takes it with no scope at all, so E10 would pass
  // even with `uses Prog` pointing at Prog.dpr.
  TProgCtl = class(TPersistent)
  private
    FDupProgPoison: Integer;
  published
    property DupProgPoison: Integer read FDupProgPoison write FDupProgPoison;
  end;

  // ...and for the uppercase-extension pair.
  TUpCtl = class(TPersistent)
  private
    FDupUpPoison: Integer;
  published
    property DupUpPoison: Integer read FDupUpPoison write FDupUpPoison;
  end;

implementation

end.
'@

# A PLAIN-named pair too: the mis-binding is not a dotted-name defect, it is a
# stem-collision defect, and the reviewer's evidence (tests\fixtures\formsmap)
# is entirely plain names.
Write-Ascii (Join-Path $work 'PlainKit.pas') @'
unit PlainKit;

interface

type
  TPlainCtl = class(TPersistent)
  private
    FPlainMarker: Integer;
  published
    property PlainMarker: Integer read FPlainMarker write FPlainMarker;
  end;

implementation

{$R *.dfm}

end.
'@

Write-Ascii (Join-Path $work 'PlainKit.dfm') @'
object PlainCtl: TPlainCtl
  Left = 0
  Top = 0
  Caption = 'Plain'
end
'@

Write-Ascii (Join-Path $work 'Cli.Kit.pas') @'
unit Cli.Kit;

interface

uses
  Dfm.Kit, PlainKit;

type
  // Descends from the AMBIGUOUS TDfmCtl. Only `uses Dfm.Kit` says which one --
  // and only if that uses row points at Dfm.Kit.pas rather than Dfm.Kit.dfm.
  TCliCtl = class(TDfmCtl)
  private
    FCliMarker: Integer;
  published
    property CliMarker: Integer read FCliMarker write FCliMarker;
  end;

implementation

end.
'@

# --- The .pas/.dpr pair (fix round 2). Round 1 whitelisted .pas/.dpr/.dpk, and
# because the `files` scan is path-ordered the .dpr sorts BEFORE the .pas and wins
# the stem. A program declares no unit, so `uses Prog` then names a file that
# declares nothing -- the same empty scope as the .dfm case, on a stem that
# pre-T4d 0e84cc6 bound correctly. Executed across the three exes:
#   0e84cc6 -> Prog.pas (edge resolved) | b811097 -> Prog.dpr (<UNRESOLVED>)
#   7192542 -> Prog.dpr (<UNRESOLVED>)  | round 2 -> Prog.pas (edge resolved)
Write-Ascii (Join-Path $work 'Prog.dpr') @'
program Prog;

uses
  UseProg in 'UseProg.pas';

begin
end.
'@

Write-Ascii (Join-Path $work 'Prog.pas') @'
unit Prog;

interface

type
  // AMBIGUOUS simple name: Dup.Kit declares a TProgCtl too, so the single-global
  // fallback cannot rescue this edge -- only `uses Prog` can, and only if it
  // points at Prog.pas rather than at the program beside it.
  TProgCtl = class(TPersistent)
  private
    FProgMarker: Integer;
  published
    property ProgMarker: Integer read FProgMarker write FProgMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'UseProg.pas') @'
unit UseProg;

interface

uses
  Prog;

type
  TUseProg = class(TProgCtl)
  private
    FUseMarker: Integer;
  published
    property UseMarker: Integer read FUseMarker write FUseMarker;
  end;

implementation

end.
'@

# --- The UPPERCASE-extension pair. ORM3 stores 554 paths ending '.PAS' against
# 203 ending '.pas' -- the majority of that project -- plus 25 in M2022 and 14 in
# library-Win64. The only thing keeping them eligible as `uses` targets is the
# LowerCase() around ExtractFileExt in ResolveUnitUseTargets, and nothing asserted
# it. TUpCtl is ambiguous for the same reason TProgCtl is.
Write-Ascii (Join-Path $work 'Upper.Kit.PAS') @'
unit Upper.Kit;

interface

type
  TUpCtl = class(TPersistent)
  private
    FUpMarker: Integer;
  published
    property UpMarker: Integer read FUpMarker write FUpMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'UseUp.Kit.pas') @'
unit UseUp.Kit;

interface

uses
  Upper.Kit;

type
  TUseUp = class(TUpCtl)
  private
    FUseUpMarker: Integer;
  published
    property UseUpMarker: Integer read FUseUpMarker write FUseUpMarker;
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
# K38 -- D2..D5 name FOUR leaves, but under the mutation that removes the very
# mechanism this group pins (AStrict:=False at the climb's call site) only TWO of
# them go red. Non-strict returns InScope[0], so exactly ONE candidate is grafted
# and the other pair stays green; WHICH pair is decided by candidate ORDER, which
# a fixture-file rename could silently flip. Measured by the T4d fix-round-1
# reviewer, not restated from the brief: D4/D5 red, D2/D3 green.
#
# D6 is the order-independent form of the same requirement, and it is STRICTLY
# STRONGER than D2..D5 together: a refusal means the top-level surface is
# declared by TAmbiguous and by NOTHING ELSE, so it forbids a graft from any
# class -- including one no D-check names. Whichever candidate a non-strict
# resolver picks, D6 reddens.
$dClimb = ClimbOf $dTop
Check 'D6 REFUSAL is order-independent: the whole top-level surface is declared by TAmbiguous ALONE' `
  ($dClimb -eq 'Ambig.Kit.TAmbiguous') ("climb=" + $dClimb)
# D7 de-vacuates D6 without needing a rebuilt exe: the SAME predicate applied to
# B's tree, which DOES graft, must be FALSE. Without it, "the climb names exactly
# one class" would also hold for a tree that grafted nothing because it was never
# built -- the shape D1 guards against for absence and nothing guarded for here.
$bClimbForD7 = ClimbOf $bTop
Check 'D7 D6 is not vacuous: the SAME predicate is FALSE for Std.Kit.TEdit, which does graft' `
  ($bClimbForD7 -ne 'Std.Kit.TEdit') ("B climb=" + $bClimbForD7)

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
# Rows, not a joined blob: `-match` over a newline-joined string anchors at the END
# of the whole string, so a two-row result whose LAST row happens to be the .pas
# would satisfy '\.pas$' with a .dfm row sitting right there. Every "binds to X"
# assertion below therefore checks the ROW COUNT as well as the path.
function SqlRows([string]$Q) {
  $out = @(python $pySql $db $Q)
  return @($out | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}
# $Expect is a regex for the FULL expected path tail, e.g. '[\\/]Dfm\.Kit\.pas$'.
# $CaseSensitive matters for the uppercase-extension case only.
function CheckSoleTarget([string]$Name, [string[]]$Rows, [string]$Expect, [switch]$CaseSensitive) {
  $one = ($Rows.Count -eq 1)
  $hit = if ($CaseSensitive) { $one -and ($Rows[0] -cmatch $Expect) } else { $one -and ($Rows[0] -match $Expect) }
  Check $Name $hit ("rows=" + $Rows.Count + " targets=[" + ($Rows -join '; ') + "] expected=" + $Expect)
}

$e1 = Sql "SELECT COUNT(*) FROM unit_uses WHERE unit_name='Vcl.Kit' AND target_file_id IS NOT NULL"
Check 'E1 dotted "uses Vcl.Kit" resolves target_file_id' ($e1 -eq '3') "rows with a target=$e1 (expected 3: Std.Kit + Ambig.Kit + Dfm.Kit)"

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

# --- E5..E14: a `uses` names a UNIT, and only a .pas declares one. These are the
# regression guard for the fix-round-1 Critical and for the round-1 guard's own
# defect: whichever accumulator ResolveUnitUseTargets uses, it must never let a
# form's .dfm -- or a program's .dpr -- win the stem over its .pas. E6/E10 are the
# ones that show the CONSEQUENCE (an empty scope un-resolves an ancestry edge that
# scope alone could resolve); the query-time late resolver is textual and would
# mask it in any proptree-level assertion, so every one of these reads the stored
# tables. Each names the file it expects, so none can pass by agreeing with the
# implementation's current allowed set -- which is exactly how round 1's E7 missed
# the .dpr.
Write-Host ''
Write-Host 'E5-E8. A uses row must bind to the .pas, never to the .dfm beside it' -ForegroundColor Cyan

$e5d = SqlRows "SELECT DISTINCT f.path FROM unit_uses u JOIN files f ON f.id=u.target_file_id WHERE u.unit_name='Dfm.Kit'"
CheckSoleTarget 'E5 dotted "uses Dfm.Kit" binds to Dfm.Kit.pas and nothing else' $e5d '(?i)[\\/]Dfm\.Kit\.pas$'

$e5p = SqlRows "SELECT DISTINCT f.path FROM unit_uses u JOIN files f ON f.id=u.target_file_id WHERE u.unit_name='PlainKit'"
CheckSoleTarget 'E5b plain "uses PlainKit" binds to PlainKit.pas and nothing else' $e5p '(?i)[\\/]PlainKit\.pas$'

# The consequence: scope is the ONLY thing that can resolve this edge (TDfmCtl is
# ambiguous, so the single-global fallback cannot), and an empty scope loses it.
$e6 = Sql @"
SELECT COALESCE(f.path,'<UNRESOLVED>') FROM symbols s
  JOIN type_ancestors ta ON ta.symbol_id = s.id
  LEFT JOIN symbols a ON a.id = ta.ancestor_symbol_id
  LEFT JOIN files   f ON f.id = a.file_id
 WHERE s.qualified_name = 'Cli.Kit.TCliCtl' AND ta.ancestor_name = 'TDfmCtl'
"@
Check 'E6 stored edge TCliCtl->TDfmCtl resolves to Dfm.Kit.pas (not Dup.Kit, not unresolved)' ($e6 -match '(?i)Dfm\.Kit\.pas$') "target=$e6"

# Whole-fixture sweep. NOTE what this is and is not: it restates the rule the code
# now applies, so it is a CONSISTENCY check across every row, not the requirement.
# Round 1's version of this line whitelisted exactly what the code whitelisted and
# was therefore unable to fail on the code allowing the wrong thing. The
# requirement is carried by E5/E5b/E9/E12, which name the file they expect.
$e7 = Sql "SELECT COUNT(*) FROM unit_uses u JOIN files f ON f.id=u.target_file_id WHERE LOWER(f.path) NOT LIKE '%.pas'"
Check 'E7 sweep: no uses row anywhere targets a non-.pas' ($e7 -eq '0') "rows targeting a non-.pas=$e7"

# De-vacuating E7: it only means something if non-.pas files are in `files` at
# all. If the indexer stopped storing them, E7 would pass for the wrong reason.
$e8 = Sql "SELECT COUNT(*) FROM files WHERE LOWER(path) LIKE '%.dfm'"
Check 'E8 de-vacuates E7: the .dfm files ARE indexed' ($e8 -eq '2') "dfm files in the index=$e8 (expected 2)"

# --- E9..E11: the same thing for a PROGRAM. A .dpr sorts before the .pas it shares
# a stem with, so round 1's whitelist handed `uses Prog` to the program.
Write-Host ''
Write-Host 'E9-E11. A uses row must bind to the .pas, never to the .dpr beside it' -ForegroundColor Cyan

$e9 = SqlRows "SELECT DISTINCT f.path FROM unit_uses u JOIN files f ON f.id=u.target_file_id WHERE u.unit_name='Prog'"
CheckSoleTarget 'E9 "uses Prog" binds to Prog.pas -- named, not "some allowed extension"' $e9 '(?i)[\\/]Prog\.pas$'

# The consequence, and the one that pre-T4d 0e84cc6 got RIGHT: TProgCtl is
# ambiguous (Dup.Kit), so only the uses-scope can resolve this edge, and a scope
# pointing at a program is empty.
$e10 = Sql @"
SELECT COALESCE(f.path,'<UNRESOLVED>') FROM symbols s
  JOIN type_ancestors ta ON ta.symbol_id = s.id
  LEFT JOIN symbols a ON a.id = ta.ancestor_symbol_id
  LEFT JOIN files   f ON f.id = a.file_id
 WHERE s.qualified_name = 'UseProg.TUseProg' AND ta.ancestor_name = 'TProgCtl'
"@
Check 'E10 stored edge TUseProg->TProgCtl resolves to Prog.pas (not Dup.Kit, not unresolved)' ($e10 -match '(?i)[\\/]Prog\.pas$') "target=$e10"

$e11 = Sql "SELECT COUNT(*) FROM files WHERE LOWER(path) LIKE '%.dpr'"
Check 'E11 de-vacuates E9/E10: the .dpr IS indexed and did compete' ($e11 -eq '1') "dpr files in the index=$e11 (expected 1)"

# --- E12..E14: an UPPERCASE .PAS is still a unit. LowerCase(ExtractFileExt(..)) is
# the whole of what keeps ORM3's 554 such paths eligible, and until now nothing
# asserted it. Mutation-proved rather than assumed: with that LowerCase removed and
# the exe rebuilt, E12, E13 and E2 go red and every other assertion in this file
# stays green.
Write-Host ''
Write-Host 'E12-E14. An UPPERCASE .PAS extension is still a unit' -ForegroundColor Cyan

$e12 = SqlRows "SELECT DISTINCT f.path FROM unit_uses u JOIN files f ON f.id=u.target_file_id WHERE u.unit_name='Upper.Kit'"
CheckSoleTarget 'E12 "uses Upper.Kit" binds to Upper.Kit.PAS' $e12 '[\\/]Upper\.Kit\.PAS$' -CaseSensitive

$e13 = Sql @"
SELECT COALESCE(f.path,'<UNRESOLVED>') FROM symbols s
  JOIN type_ancestors ta ON ta.symbol_id = s.id
  LEFT JOIN symbols a ON a.id = ta.ancestor_symbol_id
  LEFT JOIN files   f ON f.id = a.file_id
 WHERE s.qualified_name = 'UseUp.Kit.TUseUp' AND ta.ancestor_name = 'TUpCtl'
"@
Check 'E13 stored edge TUseUp->TUpCtl resolves to Upper.Kit.PAS (not Dup.Kit, not unresolved)' ($e13 -cmatch '[\\/]Upper\.Kit\.PAS$') "target=$e13"

# GLOB, not LIKE: SQLite's LIKE is case-insensitive over ASCII, so LIKE '%.PAS'
# would match every .pas file and this de-vacuator would assert nothing.
$e14 = Sql "SELECT COUNT(*) FROM files WHERE path GLOB '*.PAS'"
Check 'E14 de-vacuates E12/E13: the path really is stored with an uppercase extension' ($e14 -eq '1') "files matching GLOB '*.PAS'=$e14 (expected 1)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
