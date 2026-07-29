<#
  run_proptree_framework_anchor.ps1 -- Task 3c coverage for the two additions
  that let a LEGACY PRE-NAMESPACE unit stop declining on a framework-ambiguous
  type name, both in PickAncestorCandidateByScope
  (src/storage/DRagLint.Storage.SQLite.pas):

    (1) rule 2b, the WEAK last-dotted-segment 'uses' pass -- `uses Graphics`
        legitimately denotes the unit indexed as 'Vcl.Graphics', which the
        exact full-name pass (2a) can never match;
    (2) rule 3's ANCHOR -- TSQLiteSymbolStore.FrameworkAnchorForFile, the GUI
        framework ('Vcl' or 'FMX') the scope FILE's own classes demonstrably
        inherit from, climbed over ALREADY-RESOLVED type_ancestors edges only.
        It substitutes for the scope unit's missing first dotted segment, and
        for nothing else.

  MEASURED DEFECT THIS REPRODUCES (library-Win64.sqlite): 'Abcbtn' declares
  `uses Graphics, Menus, ImgList`; the candidates are indexed 'Vcl.Graphics.TFont'
  and 'FMX.Graphics.TFont' (likewise TPopupMenu, TCustomImageList). Rule 2a's
  exact compare never matches a bare name, and rule 3 was skipped outright
  because UnitFrameworkPrefix('Abcbtn') = '', so all three DECLINED and
  'Abcbtn.TabcToggleBtn' lost Font / Images / PopupMenu from class-typed to
  scalar -- 985 descendant leaves, on some of the most commonly mapped
  properties in the conversion editor proptree feeds.

  TECHNIQUE. Each case gives a legacy (undotted) unit a property whose declared
  TYPE is a globally AMBIGUOUS class name, with the two candidates in dotted
  'Vcl.*' / 'FMX.*' units carrying DIFFERENTLY-NAMED published members. That is
  the real defect's shape -- Walk's property-type classification
  (DRagLint.Convert.PropTree.pas, ResolveTypeInScope on the DECLARING class's
  file) -- and it makes all three outcomes distinguishable in the JSON:
    right pick  -> the child leaf '<Marker>.<Vcl-only member>' exists;
    wrong pick  -> '<Marker>.<FMX-only member>' exists instead (never merely
                   absent, so a wrong answer cannot masquerade as a decline);
    decline     -> the Marker leaf is is_class_typed=false with NO children,
                   exactly where an unresolvable type has always left it.

  CASES
    A  undotted unit, chain reaches Vcl.* ......... anchor 'Vcl' breaks the 2b tie
    B  undotted unit, NO anchor at all ............ 2b decides alone (its own RED case)
    C  undotted unit, chain reaches FMX.* ......... mirror of A (criterion 5 "nor the reverse")
    D  undotted unit, chain reaches Data.* only ... NO GUI hop -> must still DECLINE
    E  undotted unit, one Vcl-rooted AND one FMX-rooted class -> MIXED -> DECLINE
    F  undotted unit, explicit `uses FMX.GraphicsF` -> rule 2a WINS over a 'Vcl' anchor
       (the anchor is a last resort, never an override)
    G  DOTTED scope unit whose ancestry says FMX -> rule 3 still follows the unit's
       OWN 'Vcl' segment. Pins "a dotted scope unit never reads the anchor".

  RED PROOF -- each mechanism was disabled in turn, rebuilt, and re-run (full
  output in the Task 3c report):
    anchor never derived ................... A and C fail (4 checks); B D E F G pass
    rule 2b removed ........................ B fails (2 checks); the rest pass
    "both frameworks" detection removed .... E fails (2 checks): it picks the
                                             first-enumerated class's Vcl side
    anchor allowed to override a dotted unit's own segment, AND made to skip the
    starting class's own unit .............. G fails (2 checks)
  Note on G: with only the override mutation the anchor STILL came out 'Vcl',
  because the climb inspects the starting class's own unit first and
  'Vcl.ScopeG' is already a GUI unit -- a dotted GUI unit cannot be given a
  contradicting anchor. Both mutations together do flip the selection to FMX,
  at which point the proptree refuse side (CrossesGuiFramework, criterion 5)
  rejects it and the property declines instead: defence in depth, and the case
  goes red either way.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-framework-anchor"
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

# A candidate unit: one ambiguous class name, one uniquely-named published
# member so the pick is identifiable from the child leaf alone.
function Write-Candidate([string]$Unit, [string]$Cls, [string]$Member) {
  Write-Ascii (Join-Path $work "$Unit.pas") @"
unit $Unit;

interface

type
  $Cls = class(TPersistent)
  private
    F$Member : Integer;
  published
    property $Member : Integer read F$Member write F$Member;
  end;

implementation

end.
"@
}

# An ANCHOR unit: a single class with a GLOBALLY UNIQUE name, so ResolveAncestry
# resolves the inheriting class's edge at index time (a unique name resolves even
# with no 'uses' clause -- DRagLint.Storage.SQLite ResolveAncestry, the
# "InScopeCount = 0 and Cands.Count = 1" branch). That RESOLVED edge is the only
# thing FrameworkAnchorForFile is allowed to climb.
function Write-Anchor([string]$Unit, [string]$Cls) {
  Write-Ascii (Join-Path $work "$Unit.pas") @"
unit $Unit;

interface

type
  $Cls = class(TPersistent)
  end;

implementation

end.
"@
}

# --- Case A: undotted legacy unit, ancestry reaches Vcl.* --------------------
Write-Anchor    'Vcl.AnchorA'   'TVclAnchorA'
Write-Candidate 'Vcl.GraphicsA' 'TThingA' 'VclOnlyA'
Write-Candidate 'FMX.GraphicsA' 'TThingA' 'FmxOnlyA'

Write-Ascii (Join-Path $work 'LegacyVclKit.pas') @'
unit LegacyVclKit;

interface

uses
  GraphicsA;   // BARE pre-namespace name: matches NEITHER 'Vcl.GraphicsA' nor
               // 'FMX.GraphicsA' exactly, but is the LAST SEGMENT of both --
               // so rule 2b finds TWO hits and cannot decide. The ancestry
               // anchor ('Vcl', via TVclAnchorA) is what breaks that tie.

type
  TLegacyVclRoot = class(TVclAnchorA)
  private
    FMarkerA: TThingA;
  published
    property MarkerA: TThingA read FMarkerA write FMarkerA;
  end;

implementation

end.
'@

# --- Case B: no anchor anywhere -- the WEAK last-segment pass decides alone --
Write-Candidate 'Vcl.MenusB'   'TThingB' 'MenusOnlyB'
Write-Candidate 'Vcl.WidgetsB' 'TThingB' 'WidgetsOnlyB'

Write-Ascii (Join-Path $work 'LegacyMenusKit.pas') @'
unit LegacyMenusKit;

interface

uses
  MenusB;      // BARE name matching the LAST SEGMENT of exactly ONE candidate
               // unit ('Vcl.MenusB'), never of 'Vcl.WidgetsB'. Both candidates
               // carry the SAME 'Vcl' first segment, so rule 3 could not
               // separate them even with an anchor -- and there is none here:
               // TPersistent is not declared in this fixture, so this class's
               // ancestor edge never resolves and the climb finds nothing.

type
  TLegacyMenusRoot = class(TPersistent)
  private
    FMarkerB: TThingB;
  published
    property MarkerB: TThingB read FMarkerB write FMarkerB;
  end;

implementation

end.
'@

# --- Case C: the MIRROR -- ancestry reaches FMX.* ----------------------------
Write-Anchor    'FMX.AnchorC'   'TFmxAnchorC'
Write-Candidate 'Vcl.GraphicsC' 'TThingC' 'VclOnlyC'
Write-Candidate 'FMX.GraphicsC' 'TThingC' 'FmxOnlyC'

Write-Ascii (Join-Path $work 'LegacyFmxKit.pas') @'
unit LegacyFmxKit;

interface

uses
  GraphicsC;   // same bare-name tie as case A, mirrored: the anchor here is
               // 'FMX' (via TFmxAnchorC) and the FMX candidate must win.
               // Design criterion 5 reads "...nor the reverse".

type
  TLegacyFmxRoot = class(TFmxAnchorC)
  private
    FMarkerC: TThingC;
  published
    property MarkerC: TThingC read FMarkerC write FMarkerC;
  end;

implementation

end.
'@

# --- Case D: chain reaches a DOTTED but NON-GUI ancestor -> still DECLINE ----
Write-Anchor    'Data.NonGuiD'  'TDataAnchorD'
Write-Candidate 'Vcl.GraphicsD' 'TThingD' 'VclOnlyD'
Write-Candidate 'FMX.GraphicsD' 'TThingD' 'FmxOnlyD'

Write-Ascii (Join-Path $work 'LegacyDataKit.pas') @'
unit LegacyDataKit;

interface

uses
  GraphicsD;   // rule 2b ties (two 'GraphicsD' last segments) exactly as in
               // case A. The difference: this class's chain reaches
               // 'Data.NonGuiD' -- DOTTED, but NOT one of the two conflicting
               // GUI frameworks -- and then stops. 'Data' must NOT become an
               // anchor: the tie stays unbroken and the type must DECLINE.

type
  TLegacyDataRoot = class(TDataAnchorD)
  private
    FMarkerD: TThingD;
  published
    property MarkerD: TThingD read FMarkerD write FMarkerD;
  end;

implementation

end.
'@

# --- Case E: MIXED evidence in one file -> DECLINE, never first-found --------
Write-Anchor    'Vcl.AnchorE'   'TVclAnchorE'
Write-Anchor    'FMX.AnchorE'   'TFmxAnchorE'
Write-Candidate 'Vcl.GraphicsE' 'TThingE' 'VclOnlyE'
Write-Candidate 'FMX.GraphicsE' 'TThingE' 'FmxOnlyE'

Write-Ascii (Join-Path $work 'LegacyMixedKit.pas') @'
unit LegacyMixedKit;

interface

uses
  GraphicsE;   // This unit declares a Vcl-rooted AND an FMX-rooted class, so
               // the file-level anchor sees BOTH frameworks. Evidence of both
               // is evidence of neither: it must yield NO anchor and decline,
               // not settle on whichever class the store enumerates first
               // (TMixedVclSide, by id -- which would silently pick Vcl).

type
  TMixedVclSide = class(TVclAnchorE)
  end;

  TMixedFmxSide = class(TFmxAnchorE)
  end;

  TLegacyMixedRoot = class(TPersistent)
  private
    FMarkerE: TThingE;
  published
    property MarkerE: TThingE read FMarkerE write FMarkerE;
  end;

implementation

end.
'@

# --- Case F: an explicit full-name `uses` OUTRANKS the anchor ----------------
Write-Anchor    'Vcl.AnchorF'   'TVclAnchorF'
Write-Candidate 'Vcl.GraphicsF' 'TThingF' 'VclOnlyF'
Write-Candidate 'FMX.GraphicsF' 'TThingF' 'FmxOnlyF'

Write-Ascii (Join-Path $work 'LegacyOverrideKit.pas') @'
unit LegacyOverrideKit;

interface

uses
  FMX.GraphicsF;   // FULL dotted name -> rule 2a scores exactly one hit and
                   // decides there. This unit's ancestry anchor is 'Vcl' (via
                   // TVclAnchorF) and must be ignored: an anchor is inferred
                   // evidence, an explicit uses clause is a declaration, and
                   // inference must never override a declaration.

type
  TLegacyOverrideRoot = class(TVclAnchorF)
  private
    FMarkerF: TThingF;
  published
    property MarkerF: TThingF read FMarkerF write FMarkerF;
  end;

implementation

end.
'@

# --- Case G: a DOTTED scope unit never reads the anchor ----------------------
Write-Anchor    'FMX.AnchorG'   'TFmxAnchorG'
Write-Candidate 'Vcl.GraphicsG' 'TThingG' 'VclOnlyG'
Write-Candidate 'FMX.GraphicsG' 'TThingG' 'FmxOnlyG'

Write-Ascii (Join-Path $work 'Vcl.ScopeG.pas') @'
unit Vcl.ScopeG;

interface

// No 'uses' clause: rules 1, 2a and 2b are all unreachable, so rule 3 alone
// decides. This unit's OWN first segment is 'Vcl', while its ancestry would
// anchor on 'FMX' (TFmxAnchorG) -- deliberately contradictory. The unit's own
// segment must win: the anchor is only ever a substitute for a segment that is
// ABSENT, never a competitor to one that is present. If this flips to the FMX
// member, the anchor has started overriding dotted scope units.

type
  TDottedScopeRootG = class(TFmxAnchorG)
  private
    FMarkerG: TThingG;
  published
    property MarkerG: TThingG read FMarkerG write FMarkerG;
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'anchor.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

function Get-Tree([string]$Database, [string]$QName) {
  Push-Location $WorkDir
  try {
    $raw = (& $Exe proptree --qname $QName --format json --db $Database --no-write-back 2>$null) -join "`n"
  } finally { Pop-Location }
  return ($raw | ConvertFrom-Json)
}

# Assert one case: the Marker property must be class-typed and expand into the
# EXPECTED framework's member, never the other one.
function Test-Picks([string]$QName, [string]$Marker, [string]$WantChild, [string]$WrongChild, [string]$Why) {
  Write-Host ''
  Write-Host "$Why" -ForegroundColor Cyan
  $tree  = Get-Tree $db $QName
  $paths = @(@($tree.properties) | ForEach-Object { $_.path })
  $leaf  = @($tree.properties) | Where-Object { $_.path -eq $Marker } | Select-Object -First 1
  Check "$Marker is class-typed (the scope rule decided, not declined)" `
    ($null -ne $leaf -and $leaf.is_class_typed -eq $true) "type=$($leaf.type) class_typed=$($leaf.is_class_typed)"
  Check "$Marker expands into '$WantChild'" ($paths -contains "$Marker.$WantChild") `
    ("paths=" + (($paths | Where-Object { $_ -like "$Marker*" }) -join ', '))
  Check "$Marker does NOT expand into '$WrongChild' (wrong-framework pick)" `
    ($paths -notcontains "$Marker.$WrongChild") `
    ("paths=" + (($paths | Where-Object { $_ -like "$Marker*" }) -join ', '))
}

# Assert one case DECLINES: neither candidate may be picked, and the decline
# must be a genuine one (scalar leaf, no children), not a silent disappearance.
function Test-Declines([string]$QName, [string]$Marker, [string]$ChildA, [string]$ChildB, [string]$Why) {
  Write-Host ''
  Write-Host "$Why" -ForegroundColor Cyan
  $tree  = Get-Tree $db $QName
  $paths = @(@($tree.properties) | ForEach-Object { $_.path })
  $leaf  = @($tree.properties) | Where-Object { $_.path -eq $Marker } | Select-Object -First 1
  Check "$Marker is NOT class-typed (genuine decline)" `
    ($null -ne $leaf -and $leaf.is_class_typed -ne $true) "type=$($leaf.type) class_typed=$($leaf.is_class_typed)"
  Check "$Marker does NOT expand into '$ChildA'" ($paths -notcontains "$Marker.$ChildA") `
    ("paths=" + (($paths | Where-Object { $_ -like "$Marker*" }) -join ', '))
  Check "$Marker does NOT expand into '$ChildB'" ($paths -notcontains "$Marker.$ChildB") `
    ("paths=" + (($paths | Where-Object { $_ -like "$Marker*" }) -join ', '))
}

Test-Picks 'LegacyVclKit.TLegacyVclRoot'           'MarkerA' 'VclOnlyA' 'FmxOnlyA' `
  "Case A: undotted legacy unit, ancestry reaches Vcl.* -> anchor 'Vcl' breaks the bare-uses tie"
Test-Picks 'LegacyMenusKit.TLegacyMenusRoot'       'MarkerB' 'MenusOnlyB' 'WidgetsOnlyB' `
  'Case B: no anchor at all -- the weak last-segment uses pass decides alone'
Test-Picks 'LegacyFmxKit.TLegacyFmxRoot'           'MarkerC' 'FmxOnlyC' 'VclOnlyC' `
  "Case C: mirror -- ancestry reaches FMX.* -> anchor 'FMX' (criterion 5, reverse direction)"
Test-Declines 'LegacyDataKit.TLegacyDataRoot'      'MarkerD' 'VclOnlyD' 'FmxOnlyD' `
  "Case D: chain reaches 'Data.*' only -- no GUI hop, so no anchor and no guess"
Test-Declines 'LegacyMixedKit.TLegacyMixedRoot'    'MarkerE' 'VclOnlyE' 'FmxOnlyE' `
  'Case E: file shows BOTH frameworks -- evidence of both is evidence of neither'
Test-Picks 'LegacyOverrideKit.TLegacyOverrideRoot' 'MarkerF' 'FmxOnlyF' 'VclOnlyF' `
  "Case F: an explicit 'uses FMX.GraphicsF' outranks the 'Vcl' anchor (never an override)"
Test-Picks 'Vcl.ScopeG.TDottedScopeRootG'          'MarkerG' 'VclOnlyG' 'FmxOnlyG' `
  "Case G: a DOTTED scope unit follows its OWN segment and never reads the anchor"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
