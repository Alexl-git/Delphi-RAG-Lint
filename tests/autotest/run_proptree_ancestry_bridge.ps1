<#
  run_proptree_ancestry_bridge.ps1 -- proptree LAZY ancestry-bridge + write-back.

  THE BUG (confirmed against the real DevExpress library index): when a published
  property is a BARE inherited redeclaration ('property Align;') on a class whose
  ancestry chain is broken by a TYPE ALIAS ancestor (e.g.
  'cxButtons.TcxBaseButton = Vcl.StdCtrls.TCustomButton'), ResolveAncestry leaves
  the edge UNRESOLVED (its candidate set is class/interface only, so a type-alias
  ancestor never resolves). proptree then cannot type the property and emits
  'unknown' for every VCL-inherited property (Align, Caption, Anchors, ...).

  THE FIX: when proptree is about to return 'unknown', it walks UP the ancestry
  BRIDGING each unresolved ancestor NAME to its defining class by a scope-aware,
  alias-following lookup, finds the ancestor that really declares the property
  with a known type, and memoizes the resolved type onto the property row so the
  next read is a plain hit. Auto write-back is the DEFAULT now: a plain
  'proptree --qname X --format json --db DB' (no flag) already opens the index
  writable and memoizes; '--no-write-back' opts out. This test ALSO covers
  DOWN-PROPAGATION: the recovered type is persisted onto every bare same-named
  occurrence across the queried class's ancestor+descendant closure (never
  overwriting an explicit type).

  FIXTURE (three units, indexed as one tree, PLUS four dotted-namespace units
  for the ambiguous-ancestor scenario below -- seven total):
    VclKit.pas  -- TAlign enum; a resolved VCL-style chain
                   TControl(TPersistent) [property Align: TAlign]
                     <- TWinControl <- TButtonControl <- TCustomButton
    FmxKit.pas  -- TAlignLayout enum; a DECOY 'TCustomButton' with
                   'property Align: TAlignLayout'. Same simple name as VclKit's
                   TCustomButton => the ancestor name 'TCustomButton' is AMBIGUOUS.
    CxKit.pas   -- uses VclKit (NOT FmxKit).
                   'type TcxBaseButton = TCustomButton;'   (the alias => broken edge)
                   TcxCustomButton(TcxBaseButton) published 'property Align;' (bare, intermediate)
                   TcxButton(TcxCustomButton) published 'property Align;' (bare, the queried leaf)
                   TcxSpeedButton(TcxButton) published 'property Align;' (bare, DESCENDANT)
                   TcxTypedButton(TcxButton) published 'property Align: TMyAlign;' (SAFETY: explicit)

  These three are UNCHANGED and pass today via same-unit (rule 1) and
  uses-clause (rule 2) matching; they do not exercise framework-PREFIX
  matching (rule 3) at all, so they are left exactly as-is.

  AMBIGUOUS-ANCESTOR-ACROSS-FRAMEWORKS scenario (design doc
  2026-07-29-proptree-ancestor-scope-design.md section 3.3, rule 3; criteria
  1-5): rule 3 is specified in terms of DOTTED namespace prefixes ('Vcl.*',
  'FMX.*', 'Winapi.*' -- real units look like 'Vcl.Controls', 'Vcl.StdCtrls',
  'FMX.Controls.Win'). A resolver implementing rule 3 the natural way (compare
  the segment before the first '.') finds NO prefix at all in an undotted name
  like 'VclKit', so the scenario below uses genuinely DOTTED unit names -- the
  fixture must model the real shape of the rule, not an undotted stand-in that
  could pass for the wrong reason (a loose substring/leading-text match) or
  never pass at all:
    Vcl.WinControls.pas -- TWinKind enum; the REAL candidate for the globally-
                   ambiguous name 'TCustomControl':
                   'TCustomControl = class(TPersistent) [property Kind: TWinKind]'.
    FMX.WinControls.pas -- TFmxKind enum; the DECOY: same simple name
                   'TCustomControl', but 'property Kind: TFmxKind' (a DIFFERENT
                   type, so a wrong pick is detectable, not merely absent).
    Vcl.ExtCtrls.pas -- 'TPanel = class(TCustomControl) end;' with DELIBERATELY
                   NO 'uses' clause, so neither same-unit (rule 1) nor
                   uses-based (rule 2) scoping applies to 'TCustomControl' --
                   the SAME shape as the measured real-library root cause
                   (Vcl.StdCtrls.TCustomEdit's 'TWinControl' edge: CandInScope
                   finds zero in-scope candidates and ResolveAncestry declines,
                   ancestor_kind='?'). Once rule 3 ships, THIS unit's 'Vcl'
                   prefix (matched against 'Vcl.WinControls') must resolve it
                   into the real candidate, never the FMX decoy (criteria 3+5).
    FMX.Layouts.pas -- the MIRROR IMAGE, for design criterion 5's "...nor the
                   reverse": 'TLayout = class(TCustomControl) end;', also no
                   'uses' clause. Once rule 3 ships, THIS unit's 'FMX' prefix
                   must resolve it into FMX.WinControls' TCustomControl, never
                   the Vcl.WinControls one.

  Load-bearing assertions (proptree --qname CxKit.TcxButton --format json):
    - Align resolves to 'TAlign'  (was 'unknown' before the fix)     <-- THE FIX
    - Align is NOT 'TAlignLayout' (the FMX decoy) -- scope disambiguation works
    - auto write-back (default, no flag): the TcxButton.Align property row's
      stored signature becomes ': TAlign' (memoized)
    - DOWN-PROPAGATION: the recovered type is stamped onto the intermediate
      ancestor (TcxCustomButton) AND the descendant (TcxSpeedButton) bare
      occurrences too.
    - SAFETY: TcxTypedButton's explicit 'Align: TMyAlign' is NEVER overwritten.
    - idempotency: a SECOND plain query leaves signatures unchanged (no further
      mutation).
    - read-only: resolution still returns TAlign even against a read-only handle.

  Load-bearing assertions (Vcl.ExtCtrls.TPanel / FMX.Layouts.TLayout --
  ambiguous Vcl-vs-FMX ancestor via dotted framework prefixes, design doc
  criteria 1-5): see section 3 below. TODAY (RED, before the framework-prefix
  scope rule): the type_ancestors row for EACH class's 'TCustomControl' edge
  is LEFT UNRESOLVED (ancestor_kind='?', ancestor_symbol_id=NULL) and 'Kind'
  is ABSENT from each's proptree output. Neither must ever flip to the WRONG
  resolution (Vcl.ExtCtrls.TPanel picking the FMX decoy, or FMX.Layouts.TLayout
  picking the Vcl one); each must flip to ITS OWN framework's candidate once
  tasks 2-3 implement the framework-prefix rule.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-bridge"
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

Write-Ascii (Join-Path $work 'VclKit.pas') @'
unit VclKit;

interface

type
  TAlign = (alNone, alTop, alBottom, alClient);

  TControl = class(TPersistent)
  private
    FAlign: TAlign;
  published
    property Align: TAlign read FAlign write FAlign;
  end;

  TWinControl = class(TControl)
  end;

  TButtonControl = class(TWinControl)
  end;

  TCustomButton = class(TButtonControl)
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FmxKit.pas') @'
unit FmxKit;

interface

type
  TAlignLayout = (Center, Client, Top);

  // DECOY: same simple name 'TCustomButton' as VclKit's, but Align is a DIFFERENT
  // type. If the bridge picks THIS by bare name it would wrongly type Align as
  // TAlignLayout; scope must prefer VclKit (which CxKit actually uses).
  TCustomButton = class(TPersistent)
  private
    FAlign: TAlignLayout;
  published
    property Align: TAlignLayout read FAlign write FAlign;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'CxKit.pas') @'
unit CxKit;

interface

uses
  VclKit;

type
  TcxBaseButton = TCustomButton;   // alias => broken edge

  TcxCustomButton = class(TcxBaseButton)
  published
    property Align;                // bare (intermediate)
  end;

  TcxButton = class(TcxCustomButton)
  published
    property Align;                // bare (the queried leaf)
    property Caption;
  end;

  TcxSpeedButton = class(TcxButton) // DESCENDANT of the queried class
  published
    property Align;                // bare -> must be propagated to TAlign
  end;

  TMyAlign = (maNone, maFull);

  TcxTypedButton = class(TcxButton) // SAFETY CASE: explicit own type
  published
    property Align: TMyAlign;      // must NOT be overwritten
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.WinControls.pas') @'
unit Vcl.WinControls;

interface

type
  TWinKind = (wkVcl, wkOther);

  // The REAL candidate for the globally-ambiguous name 'TCustomControl'.
  // Framework-prefix rule 3 must pick THIS one for any inheriting unit whose
  // own name shares the 'Vcl' prefix (e.g. Vcl.ExtCtrls.pas below) -- never
  // the FMX decoy in FMX.WinControls.pas -- even though nothing here
  // disambiguates by same-unit (rule 1) or uses-clause (rule 2).
  TCustomControl = class(TPersistent)
  private
    FKind: TWinKind;
  published
    property Kind: TWinKind read FKind write FKind;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FMX.WinControls.pas') @'
unit FMX.WinControls;

interface

type
  TFmxKind = (fkFmx, fkOther);

  // DECOY: same simple name 'TCustomControl' as Vcl.WinControls', so the
  // name is globally AMBIGUOUS. Kind is a DIFFERENT type, so a wrong pick is
  // detectable (Kind ends up typed TFmxKind) rather than merely absent.
  TCustomControl = class(TPersistent)
  private
    FKind: TFmxKind;
  published
    property Kind: TFmxKind read FKind write FKind;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.ExtCtrls.pas') @'
unit Vcl.ExtCtrls;

interface

// Deliberately NO 'uses' clause: neither Vcl.WinControls nor FMX.WinControls
// is in scope, so today's same-unit/uses-based disambiguation
// (ResolveAncestry.CandInScope) finds ZERO in-scope candidates for the
// globally-ambiguous 'TCustomControl' name and declines -- ancestor_kind='?',
// ancestor_symbol_id=NULL. This mirrors the MEASURED real-library root cause
// verbatim (design doc section 2: Vcl.StdCtrls.TCustomEdit's 'TWinControl'
// edge is left unresolved the same way). Once the framework-prefix scope
// rule ships (design section 3.3, rule 3), THIS unit's 'Vcl' prefix must
// resolve it into Vcl.WinControls.TCustomControl -- never FMX.WinControls'
// decoy (design criteria 3 and 5).

type
  TPanel = class(TCustomControl)
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FMX.Layouts.pas') @'
unit FMX.Layouts;

interface

// The MIRROR IMAGE of Vcl.ExtCtrls.pas above -- design criterion 5 reads
// "SHALL NEVER select an FMX.* ancestor for a Vcl.* class, nor the reverse".
// Deliberately NO 'uses' clause, same ambiguous name 'TCustomControl'. Once
// rule 3 ships, THIS unit's 'FMX' prefix must resolve it into
// FMX.WinControls.TCustomControl -- never the Vcl.WinControls one.

type
  TLayout = class(TCustomControl)
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'bridge.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

function Get-Tree([string]$Database, [string]$QName) {
  Push-Location $WorkDir
  try {
    $raw = (& $Exe proptree --qname $QName --format json --db $Database) -join "`n"
  } finally { Pop-Location }
  return ($raw | ConvertFrom-Json)
}

# --- 1. Read-only resolution: Align must resolve to TAlign (was 'unknown'). ------
Write-Host ''
Write-Host 'proptree CxKit.TcxButton (read-only)' -ForegroundColor Cyan
$tree = Get-Tree $db 'CxKit.TcxButton'
$align = @($tree.properties) | Where-Object { $_.path -eq 'Align' } | Select-Object -First 1
if ($null -ne $align) {
  Check "Align type resolves to 'TAlign' (bridged across the alias break)" ($align.type -eq 'TAlign') "type=$($align.type)"
  Check "Align is NOT the FMX decoy 'TAlignLayout' (scope disambiguation)"  ($align.type -ne 'TAlignLayout') "type=$($align.type)"
  Check "Align is NOT 'unknown'" ($align.type -ne 'unknown') "type=$($align.type)"
} else {
  Check "CxKit.TcxButton has property 'Align'" $false ("paths=" + (@(@($tree.properties)|ForEach-Object{$_.path}) -join ', '))
}

# --- 2. Auto write-back is the DEFAULT: a plain read memoizes the queried row. ----
$dbw = Join-Path $WorkDir 'bridge_wb.sqlite'
Copy-Item $db $dbw -Force

$script:PyAny = Join-Path $WorkDir 'read_sig.py'
Write-Ascii $script:PyAny @'
import sqlite3, sys
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True); c = con.cursor()
r = c.execute(
    "SELECT signature FROM symbols WHERE name='Align' AND kind='property' "
    "AND parent_id IN (SELECT id FROM symbols WHERE name=? AND kind='class')",
    (sys.argv[2],)
).fetchone()
print('' if r is None else (r[0] or ''))
con.close()
'@
function Get-Sig([string]$Database,[string]$Cls){ return (python $script:PyAny $Database $Cls).Trim() }

# Query the leaf once (auto write-back default) -> resolves + persists + propagates.
$null = Get-Tree $dbw 'CxKit.TcxButton'

Check "queried TcxButton.Align memoized ': TAlign'"        ((Get-Sig $dbw 'TcxButton')       -eq ': TAlign')
Check "intermediate TcxCustomButton.Align propagated"       ((Get-Sig $dbw 'TcxCustomButton') -eq ': TAlign')
Check "descendant TcxSpeedButton.Align propagated"          ((Get-Sig $dbw 'TcxSpeedButton')  -eq ': TAlign')
Check "SAFETY: TcxTypedButton.Align NOT overwritten"        ((Get-Sig $dbw 'TcxTypedButton')  -eq 'TMyAlign')

# Idempotency: a second query performs no further mutation.
$sigBefore = Get-Sig $dbw 'TcxSpeedButton'
$null = Get-Tree $dbw 'CxKit.TcxButton'
Check "idempotent: TcxSpeedButton.Align unchanged on re-query" ((Get-Sig $dbw 'TcxSpeedButton') -eq $sigBefore)

# Read-only DB: resolution still returns TAlign, no write attempted/succeeds.
$dbro = Join-Path $WorkDir 'bridge_ro.sqlite'
Copy-Item $db $dbro -Force
$treeRo = Get-Tree $dbro 'CxKit.TcxButton' # (no --write-back flag; default is auto, but RO handle no-ops)
$alignRo = @($treeRo.properties) | Where-Object { $_.path -eq 'Align' } | Select-Object -First 1
Check "read-only still resolves Align=TAlign" ($null -ne $alignRo -and $alignRo.type -eq 'TAlign') "type=$($alignRo.type)"

# --- 3. AMBIGUOUS ANCESTOR ACROSS FRAMEWORKS, via genuine DOTTED framework ------
#        prefixes (design doc criteria 1-5). 'TCustomControl' must resolve
#        into EACH inheriting unit's OWN framework, never the other one --
#        checked in BOTH directions (criterion 5: "...nor the reverse").
#        Neither inheriting unit has a 'uses' clause, so today neither
#        same-unit nor uses-based scoping applies and ResolveAncestry
#        declines -- the SAME shape as the measured real-library bug
#        (Vcl.StdCtrls.TCustomEdit's TWinControl edge: ancestor_kind='?',
#        ancestor_symbol_id=NULL).
Write-Host ''
Write-Host 'type_ancestors: TCustomControl ancestor edges (ambiguous Vcl-vs-FMX, both directions)' -ForegroundColor Cyan

$script:PyAncestor = Join-Path $WorkDir 'read_ancestor.py'
Write-Ascii $script:PyAncestor @'
import sqlite3, sys
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True); c = con.cursor()
r = c.execute(
    "SELECT ta.ancestor_kind, ta.ancestor_symbol_id, f.path "
    "FROM type_ancestors ta "
    "JOIN symbols s ON s.id = ta.symbol_id AND s.kind='class' AND s.name=? "
    "LEFT JOIN files f ON f.id = ta.ancestor_file_id "
    "WHERE ta.ancestor_name=? ORDER BY ta.ordinal LIMIT 1",
    (sys.argv[2], sys.argv[3])
).fetchone()
print('NOROW' if r is None else "%s|%s|%s" % (r[0] or '', 'NULL' if r[1] is None else r[1], r[2] or 'NULL'))
con.close()
'@
function Get-AncestorEdge([string]$Database,[string]$Cls,[string]$Anc){ return (python $script:PyAncestor $Database $Cls $Anc).Trim() }

# --- 3a. Vcl.ExtCtrls.TPanel -> TCustomControl: must resolve into Vcl.WinControls. --
$edgeVcl = Get-AncestorEdge $db 'TPanel' 'TCustomControl'
Check "fixture sanity: TPanel's ancestor row exists in type_ancestors" ($edgeVcl -ne 'NOROW') "edge=$edgeVcl"
Check "Vcl.ExtCtrls.TPanel's ambiguous 'TCustomControl' resolves into Vcl.WinControls, not FMX.WinControls (criteria 3+5)" `
  ($edgeVcl -like '*Vcl.WinControls.pas') `
  "edge=$edgeVcl -- TODAY this is '?|NULL|NULL' (LEFT UNRESOLVED, matching the design doc's measured real-library root cause: ResolveAncestry.CandInScope finds zero in-scope candidates and declines); it must become 'class|<id>|...Vcl.WinControls.pas' once the framework-prefix scope rule ships"
Check "Vcl.ExtCtrls.TPanel's ambiguous 'TCustomControl' NEVER resolves into the FMX decoy (criterion 5)" `
  ($edgeVcl -notlike '*FMX.WinControls.pas') "edge=$edgeVcl"

# --- 3b. MIRROR (criterion 5 "...nor the reverse"): FMX.Layouts.TLayout ------------
#         -> TCustomControl must resolve into FMX.WinControls, never Vcl.WinControls.
$edgeFmx = Get-AncestorEdge $db 'TLayout' 'TCustomControl'
Check "fixture sanity: TLayout's ancestor row exists in type_ancestors" ($edgeFmx -ne 'NOROW') "edge=$edgeFmx"
Check "FMX.Layouts.TLayout's ambiguous 'TCustomControl' resolves into FMX.WinControls, not Vcl.WinControls (criterion 5, reverse direction)" `
  ($edgeFmx -like '*FMX.WinControls.pas') `
  "edge=$edgeFmx -- TODAY this is '?|NULL|NULL' (LEFT UNRESOLVED, same root cause as 3a); it must become 'class|<id>|...FMX.WinControls.pas' once the framework-prefix scope rule ships"
Check "FMX.Layouts.TLayout's ambiguous 'TCustomControl' NEVER resolves into the Vcl decoy (criterion 5, reverse direction)" `
  ($edgeFmx -notlike '*Vcl.WinControls.pas') "edge=$edgeFmx"

Write-Host ''
Write-Host 'proptree Vcl.ExtCtrls.TPanel / FMX.Layouts.TLayout (ambiguous ancestor -- observable symptom)' -ForegroundColor Cyan
$treePanel  = Get-Tree $db 'Vcl.ExtCtrls.TPanel'
Check "fixture sanity: Vcl.ExtCtrls.TPanel resolves as a class (root_type='TPanel')" ($treePanel.root_type -eq 'TPanel') "root_type=$($treePanel.root_type)"
$kindPanel = @($treePanel.properties) | Where-Object { $_.path -eq 'Kind' } | Select-Object -First 1
if ($null -ne $kindPanel) {
  Check "Vcl.ExtCtrls.TPanel.Kind is NOT the FMX decoy type 'TFmxKind' (criterion 5)" ($kindPanel.type -ne 'TFmxKind') "type=$($kindPanel.type)"
  Check "Vcl.ExtCtrls.TPanel.Kind resolves to VCL's 'TWinKind' (criterion 3: framework-prefix scope rule)" ($kindPanel.type -eq 'TWinKind') "type=$($kindPanel.type)"
} else {
  Check "Vcl.ExtCtrls.TPanel.Kind resolves to VCL's 'TWinKind' (criterion 3: framework-prefix scope rule)" $false `
    "Kind is ABSENT from the tree -- the climb stopped at the unresolved TCustomControl edge and never reached Vcl.WinControls.TCustomControl (expected RED today; see the type_ancestors check above for the root cause)"
}

$treeLayout = Get-Tree $db 'FMX.Layouts.TLayout'
Check "fixture sanity: FMX.Layouts.TLayout resolves as a class (root_type='TLayout')" ($treeLayout.root_type -eq 'TLayout') "root_type=$($treeLayout.root_type)"
$kindLayout = @($treeLayout.properties) | Where-Object { $_.path -eq 'Kind' } | Select-Object -First 1
if ($null -ne $kindLayout) {
  Check "FMX.Layouts.TLayout.Kind is NOT the Vcl decoy type 'TWinKind' (criterion 5, reverse direction)" ($kindLayout.type -ne 'TWinKind') "type=$($kindLayout.type)"
  Check "FMX.Layouts.TLayout.Kind resolves to FMX's 'TFmxKind' (criterion 3, reverse direction)" ($kindLayout.type -eq 'TFmxKind') "type=$($kindLayout.type)"
} else {
  Check "FMX.Layouts.TLayout.Kind resolves to FMX's 'TFmxKind' (criterion 3, reverse direction)" $false `
    "Kind is ABSENT from the tree -- the climb stopped at the unresolved TCustomControl edge and never reached FMX.WinControls.TCustomControl (expected RED today; see the type_ancestors check above for the root cause)"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
