<#
  run_proptree_scope_rule.ps1 -- direct regression coverage for
  PickAncestorCandidateByScope (src/storage/DRagLint.Storage.SQLite.pas),
  the shared same-unit -> uses -> framework-prefix -> decline scope rule
  used to disambiguate a same-named ancestor/type candidate.

  WHY THIS EXISTS: run_proptree_ancestry_bridge.ps1 (Task 1) exercises the
  rule only through a scenario where the DECISIVE PrefixHits=1 line (rule 3)
  cannot yet be observed end-to-end -- that scenario needs the query-time
  climb fallback (Task 3) and/or the index-time repair (Task 4), neither of
  which Task 2 implements. Without a test of its own, the one line that
  separates this rule from a guessing resolver -- and the Finding-1 fix that
  makes rule 2 equally strict -- would ship with zero committed coverage.

  TECHNIQUE: every case below routes an ambiguous name through a TYPE ALIAS
  ancestor ('TAliasSrcN = TThingN;') exactly like the CxKit/TcxBaseButton
  case in run_proptree_ancestry_bridge.ps1. ResolveAncestry's candidate set
  is class/interface only (src/storage/DRagLint.Storage.SQLite.pas ~3506),
  so it NEVER links a type-alias ancestor regardless of whether the alias's
  target name is unique or ambiguous -- the edge is unconditionally left
  unresolved. That forces proptree's bare-property-type resolution (' Marker'
  is redeclared with no type) through the LIVE path: PropTree.pas:520
  (ResolveViaBridgedAncestry.Climb) -> AStore.ResolveTypeNameToClass ->
  PickCandidate -> PickAncestorCandidateByScope. This is the ONLY production
  call site (confirmed: ResolveAncestry never calls ResolveTypeNameToClass),
  so a PASS here is evidence about the real code path, not a mock.

  Each case declares a DECOY with a DIFFERENTLY-TYPED same-named 'Marker'
  property so a wrong pick is DETECTABLE (shows up as the decoy's type, not
  merely absent), and a decline is DETECTABLE too (shows up as literal
  'unknown' -- see DRagLint.Convert.PropTree.pas:789-796 -- never one of the
  candidate types, which would mean the rule guessed by array order).

  CASES (design doc 2026-07-29-proptree-ancestor-scope-design.md section 3.3
  / task-2 review Finding 2):
    1. same-unit candidate wins ................................ rule 1
    2. a uses-named candidate wins WHEN UNIQUE .................. rule 2
    3. two uses-named candidates -> decline (Finding 1's fix) .... rule 2 -> 4
    4. two same-framework-prefix candidates -> decline ........... rule 3 -> 4
    5/6. undotted scope vs dotted candidates: no prefix match AND
         no wildcard fallback -- declines, never a substring-match guess
         (mirrors run_proptree_ancestry_bridge.ps1's 'VclKit must not count
         as sharing a prefix with Vcl.Controls' concern, one level up: here
         the SCOPE itself is undotted, not just a decoy candidate) . rule 3
    7. exactly ONE same-framework-prefix candidate wins -- the ACCEPT side
       of "PrefixHits = 1", uncovered by cases 4/5/6 (which only exercise
       its decline side) and the reason rule 3 exists at all .... rule 3
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-scope-rule"
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

# --- Case 1: same-unit candidate wins (rule 1). ------------------------------
Write-Ascii (Join-Path $work 'Scope1Kit.pas') @'
unit Scope1Kit;

interface

type
  TMark1Same = (m1sA, m1sB);

  // The REAL candidate: declared in THIS unit, same as TRoot1 -- rule 1
  // must win outright, before rule 2/3 are even consulted.
  TThing1 = class(TObject)
  private
    FMarker: TMark1Same;
  published
    property Marker: TMark1Same read FMarker write FMarker;
  end;

  TAliasSrc1 = TThing1;   // alias => ResolveAncestry never links this edge

  TRoot1 = class(TAliasSrc1)
  published
    property Marker;      // bare -- must bridge to TMark1Same
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Decoy1Kit.pas') @'
unit Decoy1Kit;

interface

type
  TMark1Decoy = (m1dA, m1dB);

  // DECOY: same simple name 'TThing1', different unit, unrelated type --
  // if rule 1 didn't win outright this would be picked (or declined into),
  // making a wrong pick or a false decline both detectable.
  TThing1 = class(TObject)
  private
    FMarker: TMark1Decoy;
  published
    property Marker: TMark1Decoy read FMarker write FMarker;
  end;

implementation

end.
'@

# --- Case 2: a uses-named candidate wins WHEN UNIQUE (rule 2). ---------------
Write-Ascii (Join-Path $work 'Real2Kit.pas') @'
unit Real2Kit;

interface

type
  TMark2Real = (m2rA, m2rB);

  TThing2 = class(TObject)
  private
    FMarker: TMark2Real;
  published
    property Marker: TMark2Real read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Decoy2Kit.pas') @'
unit Decoy2Kit;

interface

type
  TMark2Decoy = (m2dA, m2dB);

  // DECOY: same simple name, NOT in Scope2Kit's uses -- must lose to Real2Kit.
  TThing2 = class(TObject)
  private
    FMarker: TMark2Decoy;
  published
    property Marker: TMark2Decoy read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Scope2Kit.pas') @'
unit Scope2Kit;

interface

uses
  Real2Kit;

type
  TAliasSrc2 = TThing2;

  TRoot2 = class(TAliasSrc2)
  published
    property Marker;      // bare -- must bridge to TMark2Real (Real2Kit is used)
  end;

implementation

end.
'@

# --- Case 3 (Finding 1): two uses-named candidates -> DECLINE, never the -----
#     first one in array order (that is exactly how a Vcl-rooted class could
#     wrongly resolve into an FMX candidate when a unit uses both).
Write-Ascii (Join-Path $work 'UsesA3Kit.pas') @'
unit UsesA3Kit;

interface

type
  TMarkA3 = (a3X, a3Y);

  TThing3 = class(TObject)
  private
    FMarker: TMarkA3;
  published
    property Marker: TMarkA3 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'UsesB3Kit.pas') @'
unit UsesB3Kit;

interface

type
  TMarkB3 = (b3X, b3Y);

  // Same simple name as UsesA3Kit.TThing3 -- BOTH units are used by
  // Scope3Kit below, so rule 2 finds TWO hits and must decline rather than
  // pick whichever the store happens to enumerate first.
  TThing3 = class(TObject)
  private
    FMarker: TMarkB3;
  published
    property Marker: TMarkB3 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Scope3Kit.pas') @'
unit Scope3Kit;

interface

uses
  UsesA3Kit, UsesB3Kit;

type
  TAliasSrc3 = TThing3;

  TRoot3 = class(TAliasSrc3)
  published
    property Marker;      // bare -- must stay 'unknown' (genuine decline)
  end;

implementation

end.
'@

# --- Case 4: two same-framework-prefix candidates -> DECLINE (rule 3's -------
#     existing PrefixHits=1 constraint; not new, but had zero coverage).
Write-Ascii (Join-Path $work 'Vcl.CandA4.pas') @'
unit Vcl.CandA4;

interface

type
  TMarkA4 = (a4X, a4Y);

  TThing4 = class(TObject)
  private
    FMarker: TMarkA4;
  published
    property Marker: TMarkA4 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.CandB4.pas') @'
unit Vcl.CandB4;

interface

type
  TMarkB4 = (b4X, b4Y);

  // Same simple name, ALSO prefixed 'Vcl' -- two same-prefix candidates,
  // neither in Vcl.Scope4's uses (it has none) -- must decline, not pick
  // by array order.
  TThing4 = class(TObject)
  private
    FMarker: TMarkB4;
  published
    property Marker: TMarkB4 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.Scope4.pas') @'
unit Vcl.Scope4;

interface

// Deliberately no 'uses' clause -- only rule 3 (framework prefix) is even
// reachable here, and it must find TWO 'Vcl' candidates and decline.

type
  TAliasSrc4 = TThing4;

  TRoot4 = class(TAliasSrc4)
  published
    property Marker;      // bare -- must stay 'unknown'
  end;

implementation

end.
'@

# --- Case 5/6: undotted scope unit vs dotted candidates -- no prefix match ---
#     (an undotted name has NO framework prefix, so it can never match a
#     dotted one by substring) AND no wildcard fallback (declines rather
#     than grabbing either candidate).
Write-Ascii (Join-Path $work 'Vcl.Controls5.pas') @'
unit Vcl.Controls5;

interface

type
  TMarkVclDotted5 = (v5X, v5Y);

  // A DOTTED candidate whose prefix ('Vcl') textually looks like it could
  // match an undotted scope unit named 'VclKit5' under a naive
  // leading-substring implementation. It must NOT: UnitFrameworkPrefix
  // on an undotted name returns '', which never equals 'Vcl'.
  TThing5 = class(TObject)
  private
    FMarker: TMarkVclDotted5;
  published
    property Marker: TMarkVclDotted5 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Other5Kit.pas') @'
unit Other5Kit;

interface

type
  TMarkOther5 = (o5X, o5Y);

  // Second same-named candidate, ALSO not reachable by any rule from the
  // undotted scope below -- proves the decline isn't just "the dotted one
  // lost", it's "neither candidate is reachable, so nothing is guessed".
  TThing5 = class(TObject)
  private
    FMarker: TMarkOther5;
  published
    property Marker: TMarkOther5 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'VclKit5.pas') @'
unit VclKit5;

interface

// UNDOTTED scope unit name (no '.' at all) -- rule 3 must be skipped
// outright for this scope, not treated as carrying an empty-string
// "wildcard" prefix that matches anything.

type
  TAliasSrc5 = TThing5;

  TRoot5 = class(TAliasSrc5)
  published
    property Marker;      // bare -- must stay 'unknown'
  end;

implementation

end.
'@

# --- Case 7: exactly ONE same-framework-prefix candidate -> rule 3 WINS. -----
#     Cases 4 and 5/6 above only exercise the DECLINE side of "PrefixHits = 1"
#     (2+ hits, or no hits at all) -- none of them would catch rule 3 being
#     silently disabled (e.g. always falling through to decline). This is the
#     headline scenario the whole feature exists for (Vcl.StdCtrls.TCustomEdit
#     -> TWinControl in the real library), reduced to a hermetic fixture.
Write-Ascii (Join-Path $work 'Vcl.Cand7.pas') @'
unit Vcl.Cand7;

interface

type
  TMarkVcl7 = (v7X, v7Y);

  TThing7 = class(TObject)
  private
    FMarker: TMarkVcl7;
  published
    property Marker: TMarkVcl7 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FMX.Cand7.pas') @'
unit FMX.Cand7;

interface

type
  TMarkFmx7 = (f7X, f7Y);

  // DECOY: same simple name, DIFFERENT framework prefix ('FMX' vs the scope
  // unit's 'Vcl') -- must lose to Vcl.Cand7.TThing7.
  TThing7 = class(TObject)
  private
    FMarker: TMarkFmx7;
  published
    property Marker: TMarkFmx7 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.Scope7.pas') @'
unit Vcl.Scope7;

interface

// Deliberately no 'uses' clause (same shape as the measured real-library
// root cause) -- only rule 3 can resolve this, and exactly one candidate
// ('Vcl.Cand7') shares the 'Vcl' prefix, so it must win.

type
  TAliasSrc7 = TThing7;

  TRoot7 = class(TAliasSrc7)
  published
    property Marker;      // bare -- must bridge to TMarkVcl7
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'scoperule.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

function Get-MarkerType([string]$Database, [string]$QName) {
  Push-Location $WorkDir
  try {
    $raw = (& $Exe proptree --qname $QName --format json --db $Database --no-write-back 2>$null) -join "`n"
  } finally { Pop-Location }
  $tree = $raw | ConvertFrom-Json
  $prop = @($tree.properties) | Where-Object { $_.path -eq 'Marker' } | Select-Object -First 1
  if ($null -eq $prop) { return $null }
  return $prop.type
}

Write-Host ''
Write-Host 'Case 1: same-unit candidate wins (rule 1)' -ForegroundColor Cyan
$t1 = Get-MarkerType $db 'Scope1Kit.TRoot1'
Check "TRoot1.Marker resolves to same-unit 'TMark1Same'" ($t1 -eq 'TMark1Same') "type=$t1"
Check "TRoot1.Marker is NOT the decoy 'TMark1Decoy'" ($t1 -ne 'TMark1Decoy') "type=$t1"

Write-Host ''
Write-Host 'Case 2: a uses-named candidate wins when unique (rule 2)' -ForegroundColor Cyan
$t2 = Get-MarkerType $db 'Scope2Kit.TRoot2'
Check "TRoot2.Marker resolves to used-unit 'TMark2Real'" ($t2 -eq 'TMark2Real') "type=$t2"
Check "TRoot2.Marker is NOT the decoy 'TMark2Decoy'" ($t2 -ne 'TMark2Decoy') "type=$t2"

Write-Host ''
Write-Host 'Case 3 (Finding 1): two uses-named candidates -> decline, not array order' -ForegroundColor Cyan
$t3 = Get-MarkerType $db 'Scope3Kit.TRoot3'
Check "TRoot3.Marker is NOT 'TMarkA3' (would be an array-order guess)" ($t3 -ne 'TMarkA3') "type=$t3"
Check "TRoot3.Marker is NOT 'TMarkB3' (would be an array-order guess)" ($t3 -ne 'TMarkB3') "type=$t3"
Check "TRoot3.Marker stays 'unknown' (genuine decline)" ($t3 -eq 'unknown') "type=$t3"

Write-Host ''
Write-Host 'Case 4: two same-framework-prefix candidates -> decline' -ForegroundColor Cyan
$t4 = Get-MarkerType $db 'Vcl.Scope4.TRoot4'
Check "TRoot4.Marker is NOT 'TMarkA4'" ($t4 -ne 'TMarkA4') "type=$t4"
Check "TRoot4.Marker is NOT 'TMarkB4'" ($t4 -ne 'TMarkB4') "type=$t4"
Check "TRoot4.Marker stays 'unknown' (genuine decline)" ($t4 -eq 'unknown') "type=$t4"

Write-Host ''
Write-Host 'Case 5/6: undotted scope vs dotted candidates -- no prefix match, no wildcard' -ForegroundColor Cyan
$t5 = Get-MarkerType $db 'VclKit5.TRoot5'
Check "TRoot5.Marker is NOT 'TMarkVclDotted5' (undotted scope must not substring-match 'Vcl.Controls5')" ($t5 -ne 'TMarkVclDotted5') "type=$t5"
Check "TRoot5.Marker is NOT 'TMarkOther5' either (no wildcard fallback)" ($t5 -ne 'TMarkOther5') "type=$t5"
Check "TRoot5.Marker stays 'unknown' (genuine decline)" ($t5 -eq 'unknown') "type=$t5"

Write-Host ''
Write-Host 'Case 7: exactly one same-framework-prefix candidate -> rule 3 WINS' -ForegroundColor Cyan
$t7 = Get-MarkerType $db 'Vcl.Scope7.TRoot7'
Check "TRoot7.Marker resolves to the Vcl candidate 'TMarkVcl7'" ($t7 -eq 'TMarkVcl7') "type=$t7"
Check "TRoot7.Marker is NOT the FMX decoy 'TMarkFmx7'" ($t7 -ne 'TMarkFmx7') "type=$t7"
Check "TRoot7.Marker is NOT 'unknown' (rule 3 must actually decide, not just decline)" ($t7 -ne 'unknown') "type=$t7"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
