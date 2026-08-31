<#
  run_lint_global_only_uses_edge.ps1 -- the approved di-globals shape.

  THE OWNER RULING THIS ENCODES (2026-08-30)
  ------------------------------------------
  The rule is NOT "flag global reads". That framing was REFUTED on measurement:
  1,987 global reads on ORM3 client, 745 on server -- a census, not a defect
  report. What the owner approved instead is a decoupling finding:

      a global variable is the ONLY reason unit A depends on unit B, so
      injecting or RELOCATING it DELETES the uses edge.

  Measured on that definition: 8 pairs ORM3 server, 29 client, 0 on the non-DI
  control, 24 of the 37 carried by a SINGLE global. The specification is
  docs\probe-di-globals-uses-edges.py; this guard pins its behaviour in the
  engine.

  "INJECTING OR RELOCATING", NOT "INJECT". The strongest measured case is
  SkipRefresh: twelve units depend on the 1,139-line uStyles for one Boolean.
  That is fixed by MOVING the variable to a small unit, not by wiring up a
  container -- so the message must not prescribe injection as the only cure.

  EACH CONTROL BELOW EXISTS BECAUSE ITS ABSENCE HIDES A SPECIFIC FAILURE:

    POSITIVE      A uses B and references exactly one interface global of B.
    SECOND LINK   A also references a TYPE of B -> SILENT. Without this the
                  rule can degrade back into "flag global reads" -- the refuted
                  shape wearing a new id -- and every other assertion here
                  still passes.
    SHADOW        A declares the same name itself -> SILENT. The ref is a name
                  join (reads carry symbol_id NULL), so a shadowing local would
                  otherwise manufacture a dependency that does not exist.
    AMBIGUITY     the name is declared in a third unit too -> SILENT. Same
                  reason: the join cannot say which declaration was meant, and
                  guessing is how a name join invents an edge.
    DFM DEMOTION  A's sibling .dfm references B's root object -> the finding
                  says so. Measured 2026-08-30: DFM cross-form component refs
                  are NOT in the index (DFM refs are event-binding only), so
                  this is a TEXT read of the .dfm. Without it the rule advises
                  breaking a dependency the DFM silently re-creates at design
                  time.
    CODE LINK     the reader touches a form MEMBER (dmFix.styThing) in code ->
                  SILENT. Distinct from SECOND LINK: the member is published, so
                  it exists in the .pas AND the .dfm, and counting distinct FILES
                  makes it look ambiguous and discards it. Cost eight false
                  positives on ORM3 client before it was caught.
    OFF SWITCH    the rule is ON by default (e989ce4, 2026-08-30), so an
                  explicit `"disabled"` entry must produce nothing AND an empty
                  config must still report. Both halves are needed: this section
                  asserted the OLD default for six hours after the flip and
                  nobody saw it, because the battery that would have caught it
                  never ran.

  POSITIVE CONTROL ON THE OFF SWITCH: the "off" run must still produce OTHER
  findings. A silent run because lint-all failed, the DB was empty, or the
  fixture did not index looks exactly like a correctly disabled rule.

  IT MUST RUN THROUGH lint-all, NOT `lint <file>`: this is a project-wide rule
  and the single-file path never reaches it. A fixture that cannot REACH the
  feature reads exactly like a feature that does not work.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-globaledge"
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
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $srcDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

# --- B: the declaring unit. Carries globals AND a type AND a routine, so the
#     SECOND-LINK control has something real to reference. -------------------
Emit 'uGlobalsB.pas' @'
unit uGlobalsB;
interface
type
  TBThing = class
  private
    FCount: Integer;
  public
    constructor Create;
    procedure Poke;
  end;
  IBService = interface
    procedure Ping;
  end;
var
  gOnlyLink : Boolean;
  gShadowed : Integer;
  gAmbig    : Integer;
  gService  : IBService;
procedure BHelper(Sender: TObject);
procedure RefreshView;
procedure ResetAll;
procedure SharedHelper;
implementation
constructor TBThing.Create;
begin
  FCount:= 0;
end;
procedure TBThing.Poke;
begin
end;
procedure BHelper(Sender: TObject);
begin
end;
procedure RefreshView;
begin
end;
procedure ResetAll;
begin
end;
procedure SharedHelper;
begin
end;
end.
'@

# A third unit declaring SharedHelper, so that name leaves the `uniq` set and
# the generator stops counting it as a link. That is what makes the E-KILL case
# a CANDIDATE at all -- without it the shipped query already kills the pair and
# the case would prove nothing about rule E.
Emit 'uOtherDecl.pas' @'
unit uOtherDecl;
interface
procedure SharedHelper;
implementation
procedure SharedHelper;
begin
end;
end.
'@

# POSITIVE: the only thing A takes from B is one global.
Emit 'uReaderA.pas' @'
unit uReaderA;
interface
uses uGlobalsB;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gOnlyLink then
    Exit;
end;
end.
'@

# SECOND LINK: a global AND a type -> not a global-only edge.
Emit 'uSecondLink.pas' @'
unit uSecondLink;
interface
uses uGlobalsB;
procedure DoWork;
implementation
procedure DoWork;
var
  T: TBThing;
begin
  if gOnlyLink then
    Exit;
  T:= TBThing.Create;
  try
    T.Poke;
  finally
    T.Free;
  end;
end;
end.
'@

# SHADOW: the reading unit declares the same name.
Emit 'uShadow.pas' @'
unit uShadow;
interface
uses uGlobalsB;
var
  gShadowed: Integer;
procedure DoWork;
implementation
procedure DoWork;
begin
  gShadowed:= gShadowed + 1;
end;
end.
'@

# AMBIGUITY: gAmbig is declared in a THIRD unit as well.
Emit 'uAmbigDecl.pas' @'
unit uAmbigDecl;
interface
var
  gAmbig: Integer;
implementation
end.
'@

Emit 'uAmbigReader.pas' @'
unit uAmbigReader;
interface
uses uGlobalsB;
procedure DoWork;
implementation
procedure DoWork;
begin
  gAmbig:= gAmbig + 1;
end;
end.
'@

# --- the DFM pair. uStyleB stands in for uStyles: one global that many forms
#     read, plus a datamodule those forms bind to at DESIGN time. ------------
Emit 'uStyleB.pas' @'
unit uStyleB;
interface
uses System.Classes;
type
  TFixStyle = class(TComponent)
  end;
  TdmFix = class(TDataModule)
    styThing: TFixStyle;
    procedure DoThing(Sender: TObject);
  end;
var
  dmFix       : TdmFix;
  gSkipRefresh: Boolean;
implementation
procedure TdmFix.DoThing(Sender: TObject);
begin
end;
end.
'@

Emit 'uStyleB.dfm' @'
object dmFix: TdmFix
  Height = 200
  Width = 300
  object styThing: TFixStyle
  end
end
'@

# The .dfm re-creates the dependency at design time -> DEMOTED (annotated).
Emit 'uDfmReader.pas' @'
unit uDfmReader;
interface
uses System.Classes, Vcl.Forms, uStyleB;
type
  TfrmDfmReader = class(TForm)
  end;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gSkipRefresh then
    Exit;
end;
end.
'@

Emit 'uDfmReader.dfm' @'
object frmDfmReader: TfrmDfmReader
  Caption = 'Reader'
  StyleRef = dmFix.styThing
end
'@

# The twin with NO design-time link -> plain finding, no annotation.
Emit 'uPlainReader.pas' @'
unit uPlainReader;
interface
uses System.Classes, Vcl.Forms, uStyleB;
type
  TfrmPlainReader = class(TForm)
  end;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gSkipRefresh then
    Exit;
end;
end.
'@

Emit 'uPlainReader.dfm' @'
object frmPlainReader: TfrmPlainReader
  Caption = 'Plain'
end
'@

# CODE LINK (regression control, 2026-08-30). This one is NOT about the .dfm:
# uCodeLinkReader touches dmFix.styThing in CODE, so a global is plainly not the
# only link and the pair must be SILENT.
#
# It goes RED the moment the declaration universe counts .dfm files. Every
# published component is indexed twice -- a `field` in the .pas, a `component`
# in the .dfm -- so counting distinct FILES marks styThing ambiguous, the
# ambiguity mitigation discards it, and the second link vanishes. That is not
# hypothetical: measured on ORM3 client, EIGHT forms executing
# `cxGrid1DBTableView1.Styles.Header:= dmStyles.styGridHeaderBold` were reported
# as depending on uStyles for nothing but SkipRefresh -- 29 findings where the
# truth is 21. The probe that SPECIFIES this rule has the same defect.
Emit 'uCodeLinkReader.pas' @'
unit uCodeLinkReader;
interface
uses System.Classes, Vcl.Forms, uStyleB;
type
  TfrmCodeLink = class(TForm)
  end;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gSkipRefresh then
    Exit;
  dmFix.styThing.Tag:= 1;
end;
end.
'@

Emit 'uCodeLinkReader.dfm' @'
object frmCodeLink: TfrmCodeLink
  Caption = 'CodeLink'
end
'@

# INTERFACE ARM (owner ruling 2026-08-30). The carrying global's declared TYPE
# is the discriminator: an interface CAN be registered and resolved, so here --
# and only here -- the advice is allowed to say "inject". Resolution is against
# the index (kind='interface'), never a name heuristic: ORM3's two real cases
# are ImcSTATIONS and ImcOPTRLIST, and "I followed by an upper-case letter"
# misses both.
Emit 'uIfaceReader.pas' @'
unit uIfaceReader;
interface
uses uGlobalsB;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gService = nil then
    Exit;
end;
end.
'@

# MIXED control. Injecting only the interface-typed half leaves the OTHER
# global carrying the edge, so the edge does not go away and the advice must
# not claim it does. Relocation is the only cure that works for the pair.
#
# 2026-08-31: THIS FIXTURE DID NOT EXIST. It was called uMixedReader.pas, and so
# is the DFM mixed-datamodule reader emitted ~110 lines below -- Emit does an
# unconditional WriteAllText, so the later one silently overwrote this one. Both
# assertion groups then read the same DFM pair, and `MIXED does NOT say inject`
# passed for the wrong reason: gMixOnly is a Boolean, so there was nothing to
# inject and nothing being tested. The AllInterfaceTyped "ALL, not ANY" control
# was dead. Renamed, with its own $ifmix, so both are live.
Emit 'uIfaceMixedReader.pas' @'
unit uIfaceMixedReader;
interface
uses uGlobalsB;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gOnlyLink then
    Exit;
  if gService = nil then
    Exit;
end;
end.
'@

# --- RULE E (owner ruling 2026-08-30) -------------------------------------
# Each reader below reads gOnlyLink, so the pair is a CANDIDATE; then it makes
# ONE more reference to uGlobalsB that rule E must judge. Every collision name
# is declared in TWO files on purpose: a name unique to uGlobalsB never leaves
# the generator's `uniq` set, so the pair would die for a reason unrelated to
# the thing under test.

# E-KILL. SharedHelper is genuinely importable from uGlobalsB, referenced BARE,
# and not declared here -- a real second link. uOtherDecl also declares it, so
# the generator cannot see it. THE ONLY CASE THAT IS RED AGAINST THE PRE-RULE-E
# BUILD, and therefore the only positive control the suite has.
Emit 'uEKillReader.pas' @'
unit uEKillReader;
interface
uses uGlobalsB;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gOnlyLink then
    Exit;
  SharedHelper;
end;
end.
'@

# CTOR: `Create` is TBThing's constructor -- a class member, so `uses uGlobalsB`
# cannot hand it to anyone. This Create belongs to TLocalThing.
Emit 'uCtorReader.pas' @'
unit uCtorReader;
interface
uses uGlobalsB;
type
  TLocalThing = class
  public
    constructor Create;
  end;
procedure DoWork;
implementation
constructor TLocalThing.Create;
begin
end;
procedure DoWork;
var
  L: TLocalThing;
begin
  if gOnlyLink then
    Exit;
  L:= TLocalThing.Create;
  L.Free;
end;
end.
'@

# FIELD: FCount is a private field of TBThing, and this unit's own class has one
# spelled the same.
Emit 'uFieldReader.pas' @'
unit uFieldReader;
interface
uses uGlobalsB;
type
  TLocalCounter = class
  private
    FCount: Integer;
  public
    procedure Bump;
  end;
procedure DoWork;
implementation
procedure TLocalCounter.Bump;
begin
  FCount:= FCount + 1;
end;
procedure DoWork;
begin
  if gOnlyLink then
    Exit;
end;
end.
'@

# MEMBER METHOD: Poke is a method of TBThing. Named uMemberMethodReader and NOT
# uMethodReader -- that name is already taken by the DFM event-binding case
# below, and reusing it would repeat the exact overwrite bug fixed above.
Emit 'uMemberMethodReader.pas' @'
unit uMemberMethodReader;
interface
uses uGlobalsB;
type
  TLocalPoker = class
  public
    procedure Poke;
  end;
procedure DoWork;
implementation
procedure TLocalPoker.Poke;
begin
end;
procedure DoWork;
var
  L: TLocalPoker;
begin
  if gOnlyLink then
    Exit;
  L:= TLocalPoker.Create;
  try
    L.Poke;
  finally
    L.Free;
  end;
end;
end.
'@

# PARAM: Sender is a PARAMETER of uGlobalsB.BHelper. A parameter of a routine
# inside B is not something `uses B` can bring into scope.
Emit 'uParamReader.pas' @'
unit uParamReader;
interface
uses uGlobalsB;
procedure Click(Sender: TObject);
implementation
procedure Click(Sender: TObject);
begin
  if gOnlyLink then
    Exit;
  if Sender = nil then
    Exit;
end;
end.
'@

# WRONG RECEIVER: RefreshView IS importable from uGlobalsB, but this reference
# is FGrid.RefreshView -- a member of TLocalGrid. Rule D, which matches the
# importable surface by NAME alone, kills this pair. E keeps it, and this is the
# case that goes red if anyone reduces E back to a name join.
Emit 'uRecvReader.pas' @'
unit uRecvReader;
interface
uses uGlobalsB;
type
  TLocalGrid = class
  public
    procedure RefreshView;
  end;
procedure DoWork;
implementation
procedure TLocalGrid.RefreshView;
begin
end;
procedure DoWork;
var
  FGrid: TLocalGrid;
begin
  if gOnlyLink then
    Exit;
  FGrid:= TLocalGrid.Create;
  try
    FGrid.RefreshView;
  finally
    FGrid.Free;
  end;
end;
end.
'@

# SELF-DECLARED: ResetAll is importable from uGlobalsB and called BARE -- but
# this unit declares its own. A name the reader declares cannot be an import.
Emit 'uSelfReader.pas' @'
unit uSelfReader;
interface
uses uGlobalsB;
procedure ResetAll;
procedure DoWork;
implementation
procedure ResetAll;
begin
end;
procedure DoWork;
begin
  if gOnlyLink then
    Exit;
  ResetAll;
end;
end.
'@

# --- CLASSIFIED DFM DEMOTION (owner ruling 2026-08-30) --------------------
# The demotion is a BLESSING -- it tells the reader "this design-time link is
# legitimate". A blessing needs positive evidence, so it is now conditional on
# WHAT the referenced datamodule member is, decided by ANCESTRY rather than by
# a list of type names. The four pairs below are the four ways that decision
# can go wrong, and every one of them DEMOTES under the pre-ruling build.
#
# Every fixture type roots at TDataSet / TComponent by NAME, neither of which
# this fixture index declares, so the classification is proved with no library
# store attached.

# DATA: the referenced member is a dataset -> the coupling IS the finding.
Emit 'uDataB.pas' @'
unit uDataB;
interface
uses System.Classes;
type
  TFixQueryB = class(TDataSet)
  end;
  TdmData = class(TDataModule)
    qryThing: TFixQueryB;
  end;
var
  dmData    : TdmData;
  gOnlyData : Boolean;
implementation
end.
'@

Emit 'uDataB.dfm' @'
object dmData: TdmData
  Height = 200
  Width = 300
  object qryThing: TFixQueryB
  end
end
'@

Emit 'uDataReader.pas' @'
unit uDataReader;
interface
uses System.Classes, Vcl.Forms, uDataB;
type
  TfrmDataReader = class(TForm)
  end;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gOnlyData then
    Exit;
end;
end.
'@

Emit 'uDataReader.dfm' @'
object frmDataReader: TfrmDataReader
  Caption = 'Data'
  DataSource = dmData.qryThing
end
'@

# MIXED: the reader touches only the STYLE, but the module also holds a
# dataset. Worst case wins -- binding to it at design time forces the whole
# module's construction order onto this form, whichever member was sampled.
Emit 'uMixedB.pas' @'
unit uMixedB;
interface
uses System.Classes;
type
  TFixStyleM = class(TComponent)
  end;
  TFixQueryM = class(TDataSet)
  end;
  TdmMixed = class(TDataModule)
    styOther: TFixStyleM;
    qryOther: TFixQueryM;
  end;
var
  dmMixed  : TdmMixed;
  gMixOnly : Boolean;
implementation
end.
'@

Emit 'uMixedB.dfm' @'
object dmMixed: TdmMixed
  Height = 200
  Width = 300
  object styOther: TFixStyleM
  end
  object qryOther: TFixQueryM
  end
end
'@

Emit 'uMixedReader.pas' @'
unit uMixedReader;
interface
uses System.Classes, Vcl.Forms, uMixedB;
type
  TfrmMixedReader = class(TForm)
  end;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gMixOnly then
    Exit;
end;
end.
'@

Emit 'uMixedReader.dfm' @'
object frmMixedReader: TfrmMixedReader
  Caption = 'Mixed'
  StyleRef = dmMixed.styOther
end
'@

# METHOD: a cross-form .dfm reference to a METHOD is an event binding, which is
# behaviour by definition. Its twin is the resource pair itself -- TdmFix now
# HAS a method and uDfmReader must go on demoting, or "a method makes the
# module behavioural" would have made the demotion arm dead code (measured: the
# canonical resource datamodule TdmStyles declares 7 methods).
Emit 'uMethodReader.pas' @'
unit uMethodReader;
interface
uses System.Classes, Vcl.Forms, uStyleB;
type
  TfrmMethodReader = class(TForm)
  end;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gSkipRefresh then
    Exit;
end;
end.
'@

Emit 'uMethodReader.dfm' @'
object frmMethodReader: TfrmMethodReader
  Caption = 'Method'
  OnFoo = dmFix.DoThing
end
'@

# UNRESOLVED: TVaporware is declared nowhere. Absence is not evidence, so it
# classifies as behavioural and the finding keeps its full strength -- the
# direction that also makes a missing or stale library store safe.
Emit 'uUnresB.pas' @'
unit uUnresB;
interface
uses System.Classes;
type
  TdmUnres = class(TDataModule)
    mystery: TVaporware;
  end;
var
  dmUnres    : TdmUnres;
  gUnresOnly : Boolean;
implementation
end.
'@

Emit 'uUnresB.dfm' @'
object dmUnres: TdmUnres
  Height = 200
  Width = 300
end
'@

Emit 'uUnresReader.pas' @'
unit uUnresReader;
interface
uses System.Classes, Vcl.Forms, uUnresB;
type
  TfrmUnresReader = class(TForm)
  end;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gUnresOnly then
    Exit;
end;
end.
'@

Emit 'uUnresReader.dfm' @'
object frmUnresReader: TfrmUnresReader
  Caption = 'Unres'
  Mystery = dmUnres.mystery
end
'@

# --- configs ---------------------------------------------------------------
# THE DEFAULT FLIPPED ON 2026-08-30 (e989ce4) AND THIS SECTION DID NOT FOLLOW.
# The rule used to ship DefaultEnabled=False, so "off" was an EMPTY config and
# the guard asserted silence from it. e989ce4 made global-only-uses-edge ON by
# default -- `ShouldKeep(id, False)` now means "keep unless explicitly disabled"
# -- without touching this file, so the assertion started failing at 19:05 that
# evening. It went unnoticed because the battery scheduled for that night never
# reached the runners: the AFTER-baseline capture died first.
#
# So "off" is now an explicit DISABLE, and the empty config becomes a THIRD run
# that pins the new default. Without that third run, flipping the default back
# by accident would leave this whole section green.
$cfgOn  = Join-Path $WorkDir 'on.json'
$cfgOff = Join-Path $WorkDir 'off.json'
$cfgDef = Join-Path $WorkDir 'default.json'
[System.IO.File]::WriteAllText($cfgOn,  '{ "enabled": [ "global-only-uses-edge" ] }',
                               [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($cfgOff, '{ "disabled": [ "global-only-uses-edge" ] }',
                               [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($cfgDef, '{ }', [System.Text.Encoding]::ASCII)

# --- index -----------------------------------------------------------------
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecEdge", "db": "edge.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\edge.sqlite'

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecEdge --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) {
    Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2
  }
  $onOut  = & $Exe lint-all --db $db --config $cfgOn  --quiet 2>&1 | Out-String
  $offOut = & $Exe lint-all --db $db --config $cfgOff --quiet 2>&1 | Out-String
  $defOut = & $Exe lint-all --db $db --config $cfgDef --quiet 2>&1 | Out-String
} finally { Pop-Location }

# One finding line per pair; anchored in the READING unit.
$lines = @($onOut -split "`r?`n" | Where-Object { $_ -match 'global-only-uses-edge' })
function EdgeFor([string]$reader) {
  @($lines | Where-Object { $_ -match [regex]::Escape($reader) })
}

Write-Host ''
Write-Host 'The finding' -ForegroundColor Cyan
$a = EdgeFor 'uReaderA.pas'
Check 'POSITIVE: uReaderA -> uGlobalsB is reported' ($a.Count -eq 1) `
  ("got " + $a.Count + " line(s)")
Check 'the finding names the declaring unit' `
  (($a -join ' ') -match 'uGlobalsB') ''
Check 'the finding names the carrying global' `
  (($a -join ' ') -match 'gOnlyLink') ''
Check 'the advice offers RELOCATING, not only injecting' `
  (($a -join ' ') -match 'relocat') `
  'SkipRefresh is fixed by moving the variable, not by a container'

Write-Host ''
Write-Host 'DI WORDING -- the carrying global TYPE decides it' -ForegroundColor Cyan
$ifc   = EdgeFor 'uIfaceReader.pas'
$ifmix = EdgeFor 'uIfaceMixedReader.pas'
Check 'a Boolean-carried edge NEVER says inject' `
  (-not (($a -join ' ') -match 'inject')) `
  'you cannot register a Boolean in a container; relocation is the only cure'
Check 'INTERFACE ARM: the interface-carried edge is reported' ($ifc.Count -eq 1) `
  ("got " + $ifc.Count + " line(s)")
Check 'and it names the type as the reason injection applies' `
  (($ifc -join ' ') -match 'interface-typed') `
  'RED means the arm is unconditional wording again, not a type decision'
Check 'and it does offer injecting' `
  (($ifc -join ' ') -match 'inject') ''
Check 'MIXED: one interface + one Boolean is reported' ($ifmix.Count -eq 1) `
  ("got " + $ifmix.Count + " line(s)")
Check 'and MIXED does NOT say inject' `
  (-not (($ifmix -join ' ') -match 'inject')) `
  'injecting only the interface half leaves the Boolean carrying the edge'

Write-Host ''
Write-Host 'CONTROLS -- each one is a way the rule can be wrong' -ForegroundColor Cyan
Check 'SECOND LINK: a type reference too -> SILENT' `
  ((EdgeFor 'uSecondLink.pas').Count -eq 0) `
  'RED here means the rule degraded into "flag global reads"'
Check 'SHADOW: the reader declares the name itself -> SILENT' `
  ((EdgeFor 'uShadow.pas').Count -eq 0) ''
Check 'AMBIGUITY: the name is declared in a third unit -> SILENT' `
  ((EdgeFor 'uAmbigReader.pas').Count -eq 0) ''
Check 'CODE LINK: a form MEMBER touched in code -> SILENT' `
  ((EdgeFor 'uCodeLinkReader.pas').Count -eq 0) `
  'RED means .dfm files are counted as declarations again'

Write-Host ''
Write-Host 'RULE E -- the second-link test asks WHICH symbol, not just the name' -ForegroundColor Cyan
# WHAT IS RED AGAINST WHAT, stated because the plan got this wrong and a reader
# who believes the plan will mis-diagnose a failure here.
#
# Rule E is a FILTER over the candidates the shipped query generates. It can
# only ever REMOVE a pair -- never resurrect one the generator already killed --
# so only a case where the OLD build reports and E must be silent can be red
# against the pre-E build. There is exactly one, and it is E-KILL.
#
# The other six are regression controls against the two REJECTED corrections:
#   * CTOR / FIELD / MEMBER METHOD / PARAM go red against option C, which
#     matched a reader's refs against EVERY symbol in the used unit. C deleted
#     varnames -> uStyles, the example the whole design was sold on.
#   * WRONG RECEIVER and SELF-DECLARED go red against option D, which narrowed
#     C's universe to the importable surface but still joined by NAME alone.
#
# Drop E-KILL and this entire section passes with rule E switched off. That is
# why it is here.
Check 'E-KILL: a real importable second link on an ambiguous name -> SILENT' `
  ((EdgeFor 'uEKillReader.pas').Count -eq 0) `
  'the ONLY positive control for rule E -- red here means the probe never ran'
Check 'CTOR: the used unit''s constructor is not an import -> reported' `
  ((EdgeFor 'uCtorReader.pas').Count -eq 1) `
  'uses B cannot hand you B''s constructor; this Create is TLocalThing''s'
Check 'FIELD: a class field of the used unit -> reported' `
  ((EdgeFor 'uFieldReader.pas').Count -eq 1) ''
Check 'MEMBER METHOD: a method of the used unit''s class -> reported' `
  ((EdgeFor 'uMemberMethodReader.pas').Count -eq 1) ''
Check 'PARAM: a parameter of a routine in the used unit -> reported' `
  ((EdgeFor 'uParamReader.pas').Count -eq 1) ''
Check 'WRONG RECEIVER: FGrid.RefreshView is TLocalGrid''s -> reported' `
  ((EdgeFor 'uRecvReader.pas').Count -eq 1) `
  'RED means E was reduced back to a bare name join over the importable surface'
Check 'SELF-DECLARED: the reader declares ResetAll itself -> reported' `
  ((EdgeFor 'uSelfReader.pas').Count -eq 1) `
  'a name the reader declares cannot be an import of the used unit'

Write-Host ''
Write-Host 'DFM DEMOTION -- the design-time dependency the index cannot see' -ForegroundColor Cyan
$dfm   = EdgeFor 'uDfmReader.pas'
$plain = EdgeFor 'uPlainReader.pas'
Check 'the .dfm-linked reader is still reported' ($dfm.Count -eq 1) `
  ("got " + $dfm.Count + " line(s)")
Check 'and it is annotated as re-created at design time' `
  (($dfm -join ' ') -match 'design time') `
  'RED here means the .dfm text scan was dropped'
Check 'the twin WITHOUT a .dfm link is reported' ($plain.Count -eq 1) `
  ("got " + $plain.Count + " line(s)")
Check 'and carries NO design-time annotation' `
  (-not (($plain -join ' ') -match 'design time')) `
  'otherwise the annotation is unconditional and proves nothing'

Write-Host ''
Write-Host 'DEMOTION IS CLASSIFIED -- resource blesses, behaviour does not' -ForegroundColor Cyan
$dat = EdgeFor 'uDataReader.pas'
$mix = EdgeFor 'uMixedReader.pas'
$mth = EdgeFor 'uMethodReader.pas'
$unr = EdgeFor 'uUnresReader.pas'
foreach ($case in @(
    @{ n = 'DATA       (member is a TDataSet descendant)'; v = $dat },
    @{ n = 'MIXED      (module also holds a dataset)'    ; v = $mix },
    @{ n = 'METHOD     (event binding, not a resource)'  ; v = $mth },
    @{ n = 'UNRESOLVED (type declared nowhere)'          ; v = $unr })) {
  # The presence half is the positive control: a bare "no annotation" check
  # also passes when the rule is switched off entirely.
  Check ($case.n + ' is still reported') ($case.v.Count -eq 1) `
    ('got ' + $case.v.Count + ' line(s)')
  Check ($case.n + ' is NOT demoted') `
    (-not ((($case.v) -join ' ') -match 'design time')) `
    'RED means the demotion went unconditional again -- it would bless a data coupling'
}
Check 'the behavioural note names the cure (a container), not deletion' `
  (($dat -join ' ') -match 'container') `
  'silence would hide that deleting the edge breaks the form in the IDE'
Check 'QUESTION 4 PIN: a datamodule that merely HAS a method still demotes' `
  (($dfm -join ' ') -match 'design time') `
  'TdmFix now declares DoThing; counting methods would make the demotion arm dead code'

Write-Host ''
Write-Host 'OFF SWITCH' -ForegroundColor Cyan
Check 'an explicit "disabled" entry reports nothing' `
  (-not ($offOut -match 'global-only-uses-edge')) ''
Check 'POSITIVE CONTROL: the off run still produced other findings' `
  ($offOut -match ':\d+:\d+') `
  'a silent run would pass the check above for the wrong reason'
Check 'ON BY DEFAULT: an EMPTY config still reports the rule' `
  ($defOut -match 'global-only-uses-edge') `
  'owner ruling 2026-08-30 (e989ce4). Without this the off-switch check above passes when the default silently flips back'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
