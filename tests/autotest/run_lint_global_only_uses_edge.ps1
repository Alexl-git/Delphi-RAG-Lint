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
    OFF SWITCH    the rule is DefaultEnabled=False; an un-enabling config must
                  produce nothing.

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
  public
    procedure Poke;
  end;
var
  gOnlyLink : Boolean;
  gShadowed : Integer;
  gAmbig    : Integer;
procedure BHelper;
implementation
procedure TBThing.Poke;
begin
end;
procedure BHelper;
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
  TdmFix = class(TDataModule)
    styThing: TComponent;
  end;
var
  dmFix       : TdmFix;
  gSkipRefresh: Boolean;
implementation
end.
'@

Emit 'uStyleB.dfm' @'
object dmFix: TdmFix
  Height = 200
  Width = 300
  object styThing: TComponent
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

# --- configs ---------------------------------------------------------------
# The rule ships DefaultEnabled=False, so "on" means an explicit opt-in.
$cfgOn  = Join-Path $WorkDir 'on.json'
$cfgOff = Join-Path $WorkDir 'off.json'
[System.IO.File]::WriteAllText($cfgOn,  '{ "enabled": [ "global-only-uses-edge" ] }',
                               [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($cfgOff, '{ }', [System.Text.Encoding]::ASCII)

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
Write-Host 'OFF SWITCH' -ForegroundColor Cyan
Check 'DefaultEnabled=False: an un-enabling config reports nothing' `
  (-not ($offOut -match 'global-only-uses-edge')) ''
Check 'POSITIVE CONTROL: the off run still produced other findings' `
  ($offOut -match ':\d+:\d+') `
  'a silent run would pass the check above for the wrong reason'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
