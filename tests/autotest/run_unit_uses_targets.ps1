<#
  run_unit_uses_targets.ps1 -- INDEX-TIME repair of unit_uses.target_file_id
  (design doc 2026-07-29-proptree-ancestor-scope-design.md section 3.2,
  acceptance criterion 12: "AFTER a re-index, unit_uses.target_file_id SHALL be
  populated for a unit whose `uses` name matches an indexed file").

  THE BUG. UnitNameNorm() stores a used unit's LAST DOTTED SEGMENT
  ('Vcl.Controls' -> 'controls'), and ResolveUnitUseTargets compared that
  against a file's FULL basename stem ('vcl.controls'). For a dotted unit name
  those two can never be equal, so every dotted `uses` row stayed NULL.
  Measured on library-Win64.sqlite before the fix: 122 of 38512 dotted rows
  resolved -- and those 122 were WRONG, dotted names that had landed on an
  unrelated file named after their last segment ('uses Fmx.Editor.MaskEdit'
  matching FMX.MaskEdit.pas). Overall 41.8% of rows resolved; after, 91.0%.

  THE RULES NOW, in order (first hit wins; no hit leaves the row NULL):
    A. EXACT -- the lowercased used-unit name equals a file's lowercased
       basename stem. A name equality, not an inference. Applies to dotted and
       bare names alike, and is NOT restricted by the GUI rule below.
    B. UNIT SCOPE NAMES -- a used name may match a DOTTED stem by that stem's
       last segment ('uses Beta' -> Ns.Beta.pas). An INFERENCE, so it carries
       three restrictions, each independently pinned below:
         * BARE NAMES ONLY   (case E)
         * exactly ONE distinct stem carries the segment   (case D)
         * the target stem is NOT in a GUI framework namespace   (case G)
       This is Delphi's own unit-scope-names resolution, in the only direction
       Delphi performs it.
  ONLY A .pas IS A CANDIDATE, filtered before a stem is computed. A `uses` clause
  names a UNIT, and in these corpora a unit is declared by a .pas and by nothing
  else (kind='unit' symbols: 5542 library-Win64 / 757 ORM3 / 278 M2022 / 521 here,
  all .pas, zero elsewhere; .dpk files carry no symbols at all). Every other
  indexed file competes for the same stem, and the shipped indexes already hold
  129 / 38 / 45 / 15 rows bound to a non-.pas. Cases I-N below, which pin the two
  shapes that actually produce those rows and say why the third does not.
  The pass RECOMPUTES rather than tops up -- it clears target_file_id and
  refills, in one transaction -- so it can REPAIR a wrong value rather than
  preserve it (the 'repair:' checks at the end).

  EACH CASE IS RED-ABLE against a specific line of the fix -- but read the
  note on D and E before trusting "delete the line and watch it fail":
    A  dotted exact      -- RED if the norm-vs-stem comparison comes back
    B  bare exact        -- RED if rule A is dropped (also the pre-fix regression guard)
    C  bare -> dotted    -- RED if rule B is dropped
    D  ambiguous segment -- RED if rule B stops requiring a UNIQUE stem   (see below)
    E  dotted -> other   -- RED if rule B stops being bare-only           (see below)
    F  no such unit      -- RED if anything resolves a name with no candidate
    G  bare -> GUI stem  -- RED if the IsGuiFrameworkPrefix refusal is dropped
    H  dotted -> GUI stem-- RED if that refusal is applied to rule A as well
    I  .PAS + .dfm       -- RED if the .pas filter is dropped: the lowercase .dfm
                            sorts AFTER the all-caps .PAS and last-wins takes it
    J  .inc sole holder  -- RED if the filter is dropped (an .inc declares nothing)
    K  .dpr sole holder  -- ditto for a program
    K2 .dpk sole holder  -- ditto for a package
    L  uppercase .PAS    -- RED if the extension test is not case-folded
    M  sweep             -- consistency over every row (restates the rule; the
                            REQUIREMENT is I/J/K/K2/L, which name what they expect)
    N  helper edge       -- RED if the .pas filter is dropped: the CONSEQUENCE, a
                            stored type_helpers row only the uses-scope can resolve
    repair (x2)          -- RED if the pass goes back to filling only NULL rows

  D AND E ARE NOT RED UNDER PLAIN DELETION, and saying otherwise overstates
  them. Their guard lines are EFFECT-DEAD if you simply remove them:
    * E guards Storage.SQLite.pas:3989 ('if Pos(''.'', Stem) > 0 then Continue',
      rule B is bare-only). Delete it and the very next line looks the dotted
      name up in SegToStem, whose keys are LAST SEGMENTS and therefore never
      contain a dot -- so a dotted key misses regardless and the row still
      stays NULL. The check passes either way.
    * D guards Storage.SQLite.pas:3991 ('if Seen = CStemAmbiguous then
      Continue'). Delete it and CStemAmbiguous ('?') is carried into Stem and
      then looked up in StemToFileId, where '?' is never a key -- so the
      TryGetValue on the next line misses and the row still stays NULL. The
      check passes either way.
  Both ARE red under the mutation that actually matters, which is the SHAPE OF
  THE ORIGINAL BUG rather than an absent line: make rule B accept a dotted name
  by matching on its last segment (E), or make it resolve an ambiguous segment
  to the first stem seen instead of declining (D). That is the better test --
  a deleted guard here is inert, a wrong guard is what ships damage -- so mutate
  toward the bug, not toward nothing, when re-proving these two.

  CASE E's RED-ABILITY IS FRAGILE, and was silently lost once: it needs its
  segment ('alpha') to stay UNIQUE across the fixture. A second file whose stem
  ends in '.alpha' makes rule B decline on AMBIGUITY instead, so case E then
  passes with or without the bare-only restriction and stops testing anything.
  That is exactly what adding a 'Vcl.Alpha.pas' for case H did. Case H uses the
  unshared segment 'delta' precisely so it cannot recur -- do not give any new
  fixture file a stem ending in '.alpha'.

  NOT covered here, deliberately: ancestor resolution. ResolveAncestry does not
  read this column at all (it scopes candidates textually), which is why an
  index built before this fix is not wrong about ancestry and needs no
  re-index. run_proptree_ancestry_bridge.ps1 is where that is pinned. That is
  also why case N reaches for a HELPER edge for its consequence: ResolveHelpers
  is a consumer that really does scope by this column, so it can see the defect,
  and ancestry cannot.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-unit-uses-targets"
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

# --- The indexed units the uses clause below will (or must not) resolve to. ------
Write-Ascii (Join-Path $work 'Ns.Alpha.pas') @'
unit Ns.Alpha;

// Stem 'ns.alpha', last segment 'alpha' -- and NO other indexed stem in this
// fixture ends in '.alpha', so 'alpha' is a UNIQUE segment. Target of case A
// (by its full name) and the thing case E must NOT be allowed to seize.
//
// THAT UNIQUENESS IS LOAD-BEARING FOR CASE E, and it is not obvious. Case E
// proves rule B refuses a DOTTED name. If some other file's stem also ended in
// '.alpha', rule B would decline on AMBIGUITY first and case E would pass even
// with the bare-only restriction removed -- green, and testing nothing. Do not
// add a second '.alpha' stem here; see the suite header.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Ns.Beta.pas') @'
unit Ns.Beta;

// Stem 'ns.beta'. No file is named 'Beta.pas', so a bare 'uses Beta' can only
// reach this unit through rule B (unit scope names). Target of case C.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Plain.pas') @'
unit Plain;

// An UNDOTTED unit, the shape that already resolved before the fix. Case B
// exists so the repair cannot quietly drop what used to work.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Ns.Gamma.pas') @'
unit Ns.Gamma;

// One of TWO stems whose last segment is 'gamma' (see Zed.Gamma.pas). A bare
// 'uses Gamma' is therefore ambiguous and rule B must DECLINE -- the same
// shape as the real 'controls'/'graphics'/'forms' names that both Vcl.* and
// FMX.* declare, which is exactly why the uniqueness requirement is what keeps
// rule B from crossing frameworks. Case D.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Zed.Gamma.pas') @'
unit Zed.Gamma;

// The second 'gamma' stem. See Ns.Gamma.pas.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.Widgets9.pas') @'
unit Vcl.Widgets9;

// The ONLY stem carrying the last segment 'widgets9', and it sits in a GUI
// framework namespace. Rule B's uniqueness test alone would therefore hand it
// to a bare `uses Widgets9` -- which is exactly the criterion-5 hazard that
// uniqueness CANNOT cover, because uniqueness is a property of what happens to
// be INDEXED, not a property of the rule. Case G pins the structural refusal.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.Delta.pas') @'
unit Vcl.Delta;

// Exists so that the GUI-namespace refusal is shown to apply to rule B ONLY:
// 'uses Vcl.Delta' NAMES this file outright and must resolve, GUI or not.
// Rule A is a name equality the unit itself stated; only the rule B INFERENCE
// is refused a GUI target. Case H -- without it, case G would also pass under
// a blanket "never resolve into Vcl.*" that broke criterion 12 for VCL units.
//
// THE SEGMENT 'delta' IS DELIBERATELY UNSHARED. The first cut of this case used
// 'Vcl.Alpha.pas', which collided with Ns.Alpha.pas on the segment 'alpha' and
// silently destroyed case E's RED-ability -- rule B then declined on ambiguity
// rather than on the bare-only restriction case E exists to pin. Any file added
// here must carry a segment no other fixture file carries.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Consumer.pas') @'
unit Consumer;

interface

uses
  Ns.Alpha,      // A: dotted, exact stem match      -> Ns.Alpha.pas
  Plain,         // B: bare, exact stem match        -> Plain.pas
  Beta,          // C: bare, unique last segment     -> Ns.Beta.pas
  Gamma,         // D: bare, TWO stems carry it      -> must stay NULL
  Zed.Alpha,     // E: dotted, no such stem          -> must stay NULL
  NoSuchUnit9,   // F: nothing of the sort indexed   -> must stay NULL
  Widgets9,      // G: bare, unique -- but GUI stem  -> must stay NULL
  Vcl.Delta;     // H: dotted exact, GUI stem        -> Vcl.Delta.pas (rule A)

implementation

end.
'@

# --- Cases I-N: ONLY A .pas DECLARES A UNIT. -------------------------------------
# ResolveUnitUseTargets pulls EVERY row of `files`, so the .dfm the indexer stores
# beside a form unit -- and a program's .dpr, a package's .dpk, an included .inc --
# competes for the same stem as a real unit. `SELECT id, path FROM files` is
# `SCAN files USING COVERING INDEX sqlite_autoindex_files_1` (path is UNIQUE), i.e.
# raw path-byte order, and the accumulator is AddOrSetValue -- LAST WINS.
#
# WHICH SHAPES THAT ACTUALLY BREAKS, because it is not every collision and saying
# so would overstate it. '.pas' sorts after '.dfm', '.dpk', '.dpr' and '.inc', so
# an IDENTICALLY-CASED pair ('Foo.dfm' vs 'Foo.pas') is won by the .pas anyway and
# is not RED-able here. The two shapes that do break, both measured live on the
# indexes shipped on this machine:
#   (1) SOLE HOLDER -- a non-.pas is the only file carrying the stem, so nothing
#       competes. 125 of library-Win64's 129 bad rows (Spring.inc 112, Events.dpr
#       8, TestRunner.dpr 4, ex.inc 1), 22 of ORM3's 38 (Interfaces.dpk), and all
#       15 of this repo's own (config.inc). Cases J, K, K2.
#   (2) MIXED-CASE COLLISION -- the legacy all-caps unit filename with a lowercase
#       sibling, where 'P' 0x50 < 'd' 0x64 puts the .dfm LAST and last-wins hands
#       it the stem. ORM3's DFCTLIST.PAS / DFCTLIST.dfm and four more like it =
#       16 rows; 45 rows over 8 stems in M2022; 4 in library-Win64. Case I, and
#       the fixture uses that exact shape.
#
# Each case NAMES THE FILE IT EXPECTS (or that no file is expected) rather than
# restating the extension set the code allows: a guard that whitelists whatever the
# implementation whitelists cannot fail on the implementation whitelisting the
# wrong thing.
Write-Ascii (Join-Path $work 'DFKIT.PAS') @'
unit DfKit;

// SHAPE 2, the ORM3 'DFCTLIST' shape: a legacy all-caps unit filename with a
// lowercase .dfm beside it. 'DFKIT.PAS' < 'DFKIT.dfm' in path bytes, so the .dfm
// is walked LAST and last-wins gives it the stem 'dfkit'. Case I.
//
// TDfmRec is deliberately AMBIGUOUS (Dup.Kit declares one too) so that case N's
// helper edge cannot be rescued by ResolveHelpers' single-global fallback -- only
// the uses-scope, i.e. this unit's uses row target_file_id, can resolve it.

interface

type
  TDfmRec = record
    DfmMarker: Integer;
  end;

implementation

{$R *.dfm}

end.
'@

Write-Ascii (Join-Path $work 'DFKIT.dfm') @'
object DfmForm: TDfmForm
  Left = 0
  Top = 0
  Caption = 'Kit'
end
'@

Write-Ascii (Join-Path $work 'Dup.Kit.pas') @'
unit Dup.Kit;

// The DECOY that makes the simple name 'TDfmRec' ambiguous. NOTHING uses this
// unit, so it is never in anyone's scope; it exists only so that case N's
// resolution depends on scope rather than on global uniqueness.

interface

type
  TDfmRec = record
    DupPoison: Integer;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Shared.inc') @'
{ SHAPE 1: an INCLUDE file, the sole holder of the stem 'shared'. An .inc
  declares no unit, so `uses Shared` names nothing indexed and must stay NULL.
  This is the single largest live instance: Spring.inc holds 112 unit_uses rows in
  library-Win64 and config.inc 15 in this repo's own index. Case J. }
const
  CSharedMarker = 1;
'@

Write-Ascii (Join-Path $work 'Prog.dpr') @'
program Prog;

// SHAPE 1 again, for a PROGRAM: sole holder of the stem 'prog'. A program
// declares no unit, so `uses Prog` must stay NULL. Live: Events.dpr holds 8
// unit_uses rows in library-Win64 and TestRunner.dpr 4. Case K.

begin
end.
'@

Write-Ascii (Join-Path $work 'Pkg.dpk') @'
package Pkg;

{ SHAPE 1 again, for a PACKAGE: sole holder of the stem 'pkg'. .dpk files carry
  ZERO symbols in all four measured indexes (305 files in library-Win64, 64 in
  M2022, 2 in ORM3, 1 here), so a scope entry pointing at one is empty by
  construction. Live: Interfaces.dpk holds 22 unit_uses rows in ORM3. Case K2. }

requires
  rtl;

end.
'@

Write-Ascii (Join-Path $work 'Upper.Kit.PAS') @'
unit Upper.Kit;

// The COUNTERWEIGHT to cases J/K/K2: an uppercase extension is still a unit and
// must still resolve. ORM3 stores 554 paths ending '.PAS' against 203 ending
// '.pas' -- the MAJORITY of that project -- plus 25 in M2022 and 14 in
// library-Win64, and the only thing keeping them eligible is the LowerCase()
// around ExtractFileExt. Case L. RED if the filter is written case-sensitively.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'HelpKit.pas') @'
unit HelpKit;

// CASE N -- the CONSEQUENCE, in stored data, through a consumer that really reads
// the column. ResolveHelpers scopes helper targets by unit_uses.target_file_id
// (its CandInScope IS the resolved uses graph), unlike ResolveAncestry which
// scopes textually and therefore cannot see this defect at all. TDfmRec is
// declared in BOTH DFKIT.PAS and Dup.Kit.pas, so ResolveHelpers' single-global
// fallback cannot fire and only the uses-scope can resolve this edge. A uses row
// pointing at DFKIT.dfm is an EMPTY scope, so the edge is stored NULL.

interface

uses
  DfKit;

type
  TKitHelper = record helper for TDfmRec
    function Twice: Integer;
  end;

implementation

function TKitHelper.Twice: Integer;
begin
  Result:= 2;
end;

end.
'@

Write-Ascii (Join-Path $work 'Consumer2.pas') @'
unit Consumer2;

interface

uses
  DfKit,         // I:  all-caps .PAS + lowercase .dfm -> DFKIT.PAS
  Shared,        // J:  only Shared.inc exists         -> must stay NULL
  Prog,          // K:  only Prog.dpr exists           -> must stay NULL
  Pkg,           // K2: only Pkg.dpk exists            -> must stay NULL
  Upper.Kit;     // L:  the file's extension is .PAS   -> Upper.Kit.PAS

implementation

end.
'@

$db = Join-Path $WorkDir 'uses.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

# --- Probe: for one used unit name, what file (if any) did the index resolve? ----
$script:PyUse = Join-Path $WorkDir 'read_use.py'
Write-Ascii $script:PyUse @'
import sqlite3, sys, os
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True); c = con.cursor()
r = c.execute(
    "SELECT u.unit_name, u.unit_name_norm, u.target_file_id, f.path "
    "FROM unit_uses u "
    "LEFT JOIN files f ON f.id = u.target_file_id "
    "WHERE LOWER(u.unit_name) = LOWER(?) LIMIT 1", (sys.argv[2],)).fetchone()
if r is None:
    print('NOROW')
else:
    print("%s|%s|%s|%s" % (r[0], r[1], 'NULL' if r[2] is None else 'SET',
                           os.path.basename(r[3]) if r[3] else 'NULL'))
con.close()
'@
function Get-Use([string]$Name) { return (python $script:PyUse $db $Name).Trim() }

# --- Raw SQL probe, for the cases that must read more than one row. ---------------
$script:PySql = Join-Path $WorkDir 'sql.py'
Write-Ascii $script:PySql @'
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1].replace("\\", "/"), uri=True)
print("\n".join("|".join("" if v is None else str(v) for v in r)
                for r in con.execute(sys.argv[2]).fetchall()))
con.close()
'@
function Sql([string]$Q) { return ((python $script:PySql $db $Q) -join "`n").Trim() }
# ROWS, not one joined blob: `-match` over a newline-joined string anchors at the
# END of the whole string, so a two-row result whose LAST row is the .pas would
# satisfy '\.pas$' with a .dfm row sitting right beside it. Every "binds to X"
# check below therefore asserts the ROW COUNT as well as the path.
function SqlRows([string]$Q) {
  $out = @(python $script:PySql $db $Q)
  return @($out | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}
# $Expect is a regex for the expected path TAIL, e.g. '[\\/]Dfm\.Kit\.pas$'.
# -CaseSensitive matters for the uppercase-extension case only.
function CheckSoleTarget([string]$N, [string[]]$Rows, [string]$Expect, [string]$D = '', [switch]$CaseSensitive) {
  $one = ($Rows.Count -eq 1)
  $hit = if ($CaseSensitive) { $one -and ($Rows[0] -cmatch $Expect) } else { $one -and ($Rows[0] -match $Expect) }
  Check $N $hit ("rows=" + $Rows.Count + " targets=[" + ($Rows -join '; ') + "] expected=" + $Expect + " " + $D)
}
function TargetsOf([string]$UnitName) {
  return SqlRows ("SELECT DISTINCT f.path FROM unit_uses u JOIN files f ON f.id=u.target_file_id " +
                  "WHERE LOWER(u.unit_name) = LOWER('" + $UnitName + "')")
}

Write-Host ''
Write-Host 'unit_uses.target_file_id after a fresh index' -ForegroundColor Cyan

$script:AllNames = @('Ns.Alpha','Plain','Beta','Gamma','Zed.Alpha','NoSuchUnit9','Widgets9','Vcl.Delta',
                     'DfKit','Shared','Prog','Pkg','Upper.Kit')

# Fixture sanity: every uses entry produced a row at all.
foreach ($n in $script:AllNames) {
  Check "fixture sanity: Consumer's 'uses $n' produced a unit_uses row" ((Get-Use $n) -ne 'NOROW') "row=$(Get-Use $n)"
}

# --- A. CRITERION 12 ITSELF: a DOTTED uses name resolves to the file it names. ---
$a = Get-Use 'Ns.Alpha'
Check "A: dotted 'uses Ns.Alpha' RESOLVES (criterion 12 -- was NULL for every dotted name)" `
  ($a -like '*|SET|Ns.Alpha.pas') `
  "row=$a -- unit_name_norm is 'alpha' while the file stem is 'ns.alpha'; comparing those two was the bug"

# --- B. Regression guard: a BARE name that exactly matches a stem still works. ---
$b = Get-Use 'Plain'
Check "B: bare 'uses Plain' still resolves to Plain.pas (nothing that worked was lost)" `
  ($b -like '*|SET|Plain.pas') "row=$b"

# --- C. Unit scope names, the only direction Delphi resolves them. ---------------
$c = Get-Use 'Beta'
Check "C: bare 'uses Beta' resolves to Ns.Beta.pas via its UNIQUE last segment" `
  ($c -like '*|SET|Ns.Beta.pas') "row=$c"

# --- D. Two stems share the segment -- decline, do not pick one. -----------------
$d = Get-Use 'Gamma'
Check "D: bare 'uses Gamma' stays NULL -- 'gamma' is carried by TWO stems (declining is the point)" `
  ($d -like '*|NULL|NULL') `
  "row=$d -- picking either Ns.Gamma or Zed.Gamma here is exactly the guess that would let a legacy unit cross into the wrong namespace"

# --- E. A DOTTED name must never fall back to another namespace's file. ----------
$e = Get-Use 'Zed.Alpha'
Check "E: dotted 'uses Zed.Alpha' stays NULL -- it must NOT seize Ns.Alpha.pas" `
  ($e -like '*|NULL|NULL') `
  "row=$e -- 'alpha' IS a unique segment, so only the bare-only restriction on rule B stops this; the pre-fix code made exactly this mistake on the real library"

# --- F. Nothing indexed by that name at all. -------------------------------------
$f = Get-Use 'NoSuchUnit9'
Check "F: 'uses NoSuchUnit9' stays NULL (no candidate file exists)" ($f -like '*|NULL|NULL') "row=$f"

# --- G. CRITERION 5, STRUCTURALLY: rule B must never infer a GUI-namespaced -------
#        target, even when it is the UNIQUE holder of the segment. Uniqueness is
#        a property of what happens to be indexed; this must be a property of the
#        rule. Here Vcl.Widgets9.pas is the only 'widgets9' stem in the tree, so
#        uniqueness alone WOULD hand it over.
$g = Get-Use 'Widgets9'
Check "G: bare 'uses Widgets9' stays NULL -- rule B never infers a GUI-namespace target (criterion 5)" `
  ($g -like '*|NULL|NULL') `
  "row=$g -- Vcl.Widgets9.pas is the UNIQUE 'widgets9' stem, so the uniqueness test passes and only the IsGuiFrameworkPrefix refusal stops it; without it, an index carrying FMX.Types.pas but not System.Types.pas would give a legacy VCL unit FireMonkey types"

# --- H. ...and that refusal applies to rule B ONLY. Rule A is a name equality -----
#        the unit stated outright, so a DOTTED uses naming a Vcl.* file must
#        still resolve -- otherwise criterion 12 would be broken for all of VCL.
$h = Get-Use 'Vcl.Delta'
Check "H: dotted 'uses Vcl.Delta' RESOLVES -- the GUI refusal binds rule B, never rule A" `
  ($h -like '*|SET|Vcl.Delta.pas') `
  "row=$h -- if this is NULL the guard was applied too broadly and criterion 12 is broken for every Vcl.*/FMX.* unit"

# --- I-N. A `uses` clause names a UNIT, and only a .pas declares one. -------------
Write-Host ''
Write-Host 'only a .pas can be a uses target (cases I-N)' -ForegroundColor Cyan

# SHAPE 2 -- the mixed-case collision. 'DFKIT.PAS' < 'DFKIT.dfm' in path bytes, so
# the .dfm is walked LAST and last-wins hands it the stem unless it is filtered out.
CheckSoleTarget "I: 'uses DfKit' binds to DFKIT.PAS, never the DFKIT.dfm that sorts after it" `
  (TargetsOf 'DfKit') '[\\/]DFKIT\.PAS$' `
  "-- the ORM3 DFCTLIST shape ('P' 0x50 < 'd' 0x64); 16 rows in ORM3, 45 in M2022, 4 in library-Win64 are bound this way today" -CaseSensitive

# SHAPE 1 -- a non-.pas as SOLE holder of the stem. Declining is the correct answer:
# nothing indexed declares a unit of that name.
$jRows = TargetsOf 'Shared'
Check "J: 'uses Shared' stays NULL -- only Shared.inc carries that stem, and an .inc declares no unit" `
  ($jRows.Count -eq 0) "targets=[$($jRows -join '; ')] -- Spring.inc holds 112 such rows in library-Win64, config.inc 15 here"
$kRows = TargetsOf 'Prog'
Check "K: 'uses Prog' stays NULL -- only Prog.dpr carries that stem, and a program declares no unit" `
  ($kRows.Count -eq 0) "targets=[$($kRows -join '; ')] -- Events.dpr holds 8 such rows in library-Win64, TestRunner.dpr 4"
$k2Rows = TargetsOf 'Pkg'
Check "K2: 'uses Pkg' stays NULL -- only Pkg.dpk carries that stem, and a package declares no unit" `
  ($k2Rows.Count -eq 0) "targets=[$($k2Rows -join '; ')] -- Interfaces.dpk holds 22 such rows in ORM3; .dpk files carry 0 symbols in all four indexes"

# The COUNTERWEIGHT: the filter must exclude by EXTENSION, case-folded, and must
# not take an uppercase .PAS with it.
CheckSoleTarget "L: 'uses Upper.Kit' binds to Upper.Kit.PAS -- an UPPERCASE extension is still a unit" `
  (TargetsOf 'Upper.Kit') '[\\/]Upper\.Kit\.PAS$' `
  "-- RED if the extension test is not case-folded: ORM3 stores 554 '.PAS' paths against 203 '.pas'" -CaseSensitive

# Whole-fixture sweep. NOTE what this is: it RESTATES the rule the code applies, so
# it is a consistency check over every row rather than the requirement itself. The
# requirement is carried by I/J/K/K2/L, which name the file they expect or expect
# no file at all.
$mSweep = Sql "SELECT COUNT(*) FROM unit_uses u JOIN files f ON f.id=u.target_file_id WHERE LOWER(f.path) NOT LIKE '%.pas'"
Check "M: sweep -- no uses row anywhere targets a non-.pas" ($mSweep -eq '0') "rows targeting a non-.pas=$mSweep"

# De-vacuators. I/J/K/K2/M only mean something if the non-.pas files are in `files`
# at all: if the indexer stopped storing them, every one of those checks would pass
# for the wrong reason. GLOB, not LIKE, for the .PAS case -- SQLite's LIKE is
# case-insensitive over ASCII, so LIKE '%.PAS' matches every .pas file.
$devNon = Sql ("SELECT COUNT(*) FROM files WHERE LOWER(path) LIKE '%.dfm' OR LOWER(path) LIKE '%.inc' " +
               "OR LOWER(path) LIKE '%.dpr' OR LOWER(path) LIKE '%.dpk'")
Check "I/J/K/K2 de-vacuator: the .dfm/.inc/.dpr/.dpk files ARE indexed and did compete" ($devNon -eq '4') `
  "non-.pas files in the index=$devNon (expected 4: DFKIT.dfm, Shared.inc, Prog.dpr, Pkg.dpk)"
$devUp = Sql "SELECT COUNT(*) FROM files WHERE path GLOB '*.PAS'"
Check "I/L de-vacuator: the two uppercase-extension paths really are stored uppercase" ($devUp -eq '2') `
  "files matching GLOB '*.PAS'=$devUp (expected 2: DFKIT.PAS, Upper.Kit.PAS)"

# --- N. THE CONSEQUENCE, in stored data, through a real consumer of the column. ---
#     ResolveHelpers scopes helper targets by the RESOLVED uses graph (its
#     CandInScope reads unit_uses.target_file_id), unlike ResolveAncestry which
#     scopes textually and therefore cannot see this defect at all. TDfmRec is
#     declared twice, so ResolveHelpers' single-global fallback cannot fire: a
#     scope entry pointing at DFKIT.dfm is EMPTY and the edge is stored NULL.
Write-Host ''
Write-Host 'consequence: a helper edge only the uses-scope can resolve' -ForegroundColor Cyan
$nDup = Sql "SELECT COUNT(*) FROM symbols WHERE name='TDfmRec'"
Check "N de-vacuator: TDfmRec is declared TWICE, so no global-uniqueness fallback can rescue the edge" `
  ($nDup -eq '2') "TDfmRec symbols=$nDup (expected 2: DfKit + Dup.Kit)"
$nEdge = Sql @"
SELECT COALESCE(f.path, '<UNRESOLVED>') FROM type_helpers th
  JOIN symbols h ON h.id = th.helper_symbol_id
  LEFT JOIN symbols t ON t.id = th.target_symbol_id
  LEFT JOIN files   f ON f.id = t.file_id
 WHERE h.name = 'TKitHelper'
"@
Check "N: stored helper edge TKitHelper -> TDfmRec resolves to DFKIT.PAS" ($nEdge -cmatch '[\\/]DFKIT\.PAS$') `
  "target=$nEdge -- '<UNRESOLVED>' is what a scope pointing at DFKIT.dfm produces; Dup.Kit.pas would mean scope was ignored"

# --- Idempotency: re-running the resolve pass must not change any answer. ---------
Write-Host ''
Write-Host 'idempotency: a second index pass over the same tree' -ForegroundColor Cyan
$before = @($script:AllNames | ForEach-Object { Get-Use $_ })
$null = & $Exe index $work --db $db 2>&1
$after  = @($script:AllNames | ForEach-Object { Get-Use $_ })
Check "re-indexing leaves every target_file_id unchanged" (($before -join ';') -eq ($after -join ';')) `
  "before=$($before -join ' ; ') after=$($after -join ' ; ')"

# --- Finding 4: the pass RECOMPUTES, so it can REPAIR a wrong value. A row -------
#     poisoned behind the indexer's back (simulating the 122 measured wrong
#     dotted targets left by the old rule in a file that is never re-parsed)
#     must be corrected by the next pass, not preserved because it is non-NULL.
Write-Host ''
Write-Host 'repair: a pre-existing WRONG target_file_id is corrected, not kept' -ForegroundColor Cyan
$script:PyPoison = Join-Path $WorkDir 'poison.py'
Write-Ascii $script:PyPoison @'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1]); c = con.cursor()
# point 'uses Ns.Alpha' at the WRONG file, and invent a target for a name that
# must have none -- exactly the two shapes the old fill-only pass could not fix.
wrong = c.execute("SELECT id FROM files WHERE path LIKE '%Plain.pas'").fetchone()[0]
c.execute("UPDATE unit_uses SET target_file_id=? WHERE LOWER(unit_name)='ns.alpha'", (wrong,))
c.execute("UPDATE unit_uses SET target_file_id=? WHERE LOWER(unit_name)='gamma'", (wrong,))
con.commit(); con.close()
print('poisoned')
'@
$null = python $script:PyPoison $db
Check "fixture sanity: the poison took (Ns.Alpha now points at Plain.pas)" ((Get-Use 'Ns.Alpha') -like '*|SET|Plain.pas') "row=$(Get-Use 'Ns.Alpha')"
Check "fixture sanity: the poison took (Gamma now has a target at all)"    ((Get-Use 'Gamma')    -like '*|SET|Plain.pas') "row=$(Get-Use 'Gamma')"
$null = & $Exe index $work --db $db 2>&1
$r1 = Get-Use 'Ns.Alpha'
$r2 = Get-Use 'Gamma'
Check "repair: a WRONG target is corrected by the next pass" ($r1 -like '*|SET|Ns.Alpha.pas') `
  "row=$r1 -- RED if the pass only fills NULL rows; the 122 measured wrong dotted targets would then survive this fix forever"
Check "repair: a target that should not exist is cleared back to NULL" ($r2 -like '*|NULL|NULL') "row=$r2"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
