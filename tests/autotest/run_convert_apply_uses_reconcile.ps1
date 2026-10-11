<#
  run_convert_apply_uses_reconcile.ps1 -- C9 (1.27.0-alpha): convert-apply
  RECONCILES the unit's uses clauses instead of applying #unuse blindly.

  THE CONTRACT (spec docs\superpowers\specs\2026-10-07-c9-uses-reconciliation-design.md,
  as superseded by its OWNER RULINGS 2026-10-06):
    * #unuse / #useswap Old are a WATCH LIST. A watched unit is KEPT while a
      component the CONVERTED .dfm still streams has a class declared in it
      (an unconverted instance, a second component type of that unit, an
      inherited instance the ancestor has not converted) -- a `kept` row and a
      `line N: warning:` naming the components. W4 / W4c / W6b / DESC / W7.
    * A need from .pas code ONLY (an exception class, a local variable, a type
      helper member) does NOT keep it: the unit is REMOVED and the remove row
      names the dangling references (needed_by) with a unit-rule-dangling
      warning. The converted unit then FAILS to compile -- the intended
      signal (ruling 1). W2 / W3 / W5.
    * A watched unit no --db knows is KEPT with unit-rule-unverified. U1.
    * Presence is scope-alias aware: `#unuse LibAl` matches `Scope.LibAl`,
      `#use DB` is satisfied by `Fx.DB`. W6 / W6b / D1.
    * Names the conversion INTRODUCES (a cast template's routine or enum value)
      get their declaring unit added; a name two units declare is REPORTED in
      uses_unresolved (ambiguous) and never picked; a #use of one candidate
      resolves it on the next run. A1 / A1b / A2. The To-type tie too. A3.
      A name no --db declares is reported not-found, nothing added. A4.
    * Tree-sitter byte columns are read as characters: non-ASCII text before
      a reference does not index past the line (ERangeError). ENC2.
    * The C13 move is a `moved` row. D2.
    * --only keeps its C13 N4 `skipped` row byte-identical. O1.
    * --no-reconcile-uses is 1.26.6 exactly. N1.
    * The decision runs on an IN-MEMORY re-index of the converted output (dry
      run = --apply plan); --apply then refreshes ONLY the unit's own project
      DB. R1 / R2.
    * A second --apply plans no uses add/remove/moved row. I1; and for the
      reconcile adds, the move and the alias removal. I2.
    * A batch --apply equals single runs although the project DB is
      re-indexed between its units; --no-reindex is the positive control. B2.
    * The converted units compile (dcc64), W2/W3/W5 fail to (ruling 1), and
      every written .dfm loads (DfmLoadCheck).

  Fixture written fresh under a $PID scratch folder and indexed into a scratch
  PROJECT --db there (index --project P.dpr). Nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_uses_reconcile_$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
. (Join-Path $PSScriptRoot 'lib\DfmLoadCheck.ps1')

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
$CRLF = "`r`n"
function P([string]$n) { return (Join-Path $WorkDir $n) }
function W([string]$n, [string]$t) { [IO.File]::WriteAllText((P $n), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
function Text([string]$n) { return [IO.File]::ReadAllText((P $n)) }

# ---- library units ----------------------------------------------------------
W 'LibOld.pas' @'
unit LibOld;

interface

uses
  Classes, SysUtils;

type
  TOld = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TOld2 = class(TComponent)
  end;

  ELibOld = class(Exception);

  TOldStrHelper = record helper for string
    function OldUpper: string;
  end;

implementation

function TOldStrHelper.OldUpper: string;
begin
  Result:= UpperCase(Self);
end;

end.
'@
W 'LibNew.pas' @'
unit LibNew;

interface

uses
  Classes;

type
  TNew = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@
W 'Scope.LibAl.pas' @'
unit Scope.LibAl;

interface

uses
  Classes;

type
  TAl = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TAl2 = class(TComponent)
  end;

implementation

end.
'@
W 'Fx.DB.pas' @'
unit Fx.DB;

interface

implementation

end.
'@
W 'LibTieA.pas' @'
unit LibTieA;

interface

uses
  Classes;

type
  TTie = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@
W 'LibTieB.pas' ((Text 'LibTieA.pas') -replace 'unit LibTieA;', 'unit LibTieB;')
W 'LibPicOld.pas' @'
unit LibPicOld;

interface

uses
  Classes;

type
  TSrcPic = class(TPersistent)
  private
    FData: string;
  published
    property Data: string read FData write FData;
  end;

  TPicOld = class(TComponent)
  private
    FPicture: TSrcPic;
  published
    property Picture: TSrcPic read FPicture write FPicture;
  end;

implementation

end.
'@
W 'LibPicNew.pas' @'
unit LibPicNew;

interface

uses
  Classes;

type
  TDstGlyph = class(TPersistent)
  private
    FData: string;
  published
    property Data: string read FData write FData;
  end;

  TPicNew = class(TComponent)
  private
    FGlyph: TDstGlyph;
  published
    property Glyph: TDstGlyph read FGlyph write FGlyph;
  end;

implementation

end.
'@
W 'LibEnum.pas' @'
unit LibEnum;

interface

type
  TCastMode = (cmPlain, cmFancy);

implementation

end.
'@
W 'LibCast.pas' @'
unit LibCast;

interface

uses
  Classes, LibEnum;

function CastPic(A: TPersistent): TPersistent;
function CastPicMode(A: TPersistent; M: TCastMode): TPersistent;

implementation

function CastPic(A: TPersistent): TPersistent;
begin
  Result:= A;
end;

function CastPicMode(A: TPersistent; M: TCastMode): TPersistent;
begin
  Result:= A;
end;

end.
'@
W 'LibAmbA.pas' @'
unit LibAmbA;

interface

uses
  Classes;

function AmbPic(A: TPersistent): TPersistent;

implementation

function AmbPic(A: TPersistent): TPersistent;
begin
  Result:= A;
end;

end.
'@
W 'LibAmbB.pas' ((Text 'LibAmbA.pas') -replace 'unit LibAmbA;', 'unit LibAmbB;')

# ---- form units -------------------------------------------------------------
# Form(Name, IntfUses, Fields, ImplUses, Methods-decl, Methods-body, DfmObjects)
function Form([string]$Name, [string]$IntfUses, [string[]]$Fields, [string]$ImplUses, [string[]]$Decls, [string]$Body, [string[]]$Objs, [string]$Base = 'TComponent') {
  $f = @("unit $Name;", '', 'interface', '', 'uses', "  $IntfUses;", '', 'type', "  T$Name = class($Base)")
  foreach ($x in $Fields) { $f += "    $x" }
  foreach ($x in $Decls)  { $f += "    $x" }
  $f += '  end;'; $f += ''; $f += 'implementation'; $f += ''
  if ($ImplUses) { $f += 'uses'; $f += "  $ImplUses;"; $f += '' }
  $f += '{$R *.dfm}'; $f += ''
  if ($Body) { $f += $Body; $f += '' }
  $f += 'end.'
  W "$Name.pas" (($f -join "`n") + "`n")
  $kw = if ($Base -eq 'TComponent') { 'object' } else { 'inherited' }
  $d = @("$kw ${Name}: T$Name")
  foreach ($o in $Objs) { $d += $o }
  $d += 'end'
  W "$Name.dfm" (($d -join "`n") + "`n")
}
function Obj([string]$N, [string]$T, [string]$Kw = 'object') { return "  $Kw ${N}: $T`n    Caption = '$N'`n  end" }
function Bare([string]$N, [string]$T, [string]$Kw = 'object') { return "  $Kw ${N}: $T`n  end" }

Form 'W1Form' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
# ENC: a CP1252 byte (0xA9, a copyright sign) in a comment -- valid ANSI, invalid
# UTF-8. Real data (ORM3 JobLayout) had one; the in-memory re-index must
# transcode it, not degrade. Written as raw bytes so this script stays ASCII.
Form 'EncForm' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
$encBytes = [Text.Encoding]::ASCII.GetBytes((Text 'EncForm.pas').Replace('implementation', "implementation`r`n`r`n{ COPYRIGHT_MARK 2026 }"))
$encList = [Collections.Generic.List[byte]]::new($encBytes)
$at = [Text.Encoding]::ASCII.GetString($encBytes).IndexOf('COPYRIGHT_MARK')
$encList.RemoveRange($at, 'COPYRIGHT_MARK'.Length); $encList.Insert($at, [byte]0xA9)
[IO.File]::WriteAllBytes((P 'EncForm.pas'), $encList.ToArray())
Form 'W2Form' 'Classes, LibOld' @('Old1: TOld;') 'SysUtils' @('procedure Run;', 'procedure Run2;') @'
procedure TW2Form.Run2;
begin
end;

procedure TW2Form.Run;
begin
  try
    Run2;
  except
    on E: ELibOld do raise;
  end;
end;
'@ @((Obj 'Old1' 'TOld'))
Form 'W3Form' 'Classes, LibOld' @('Old1: TOld;') '' @('procedure Run;') @'
procedure TW3Form.Run;
var
  T: TOld;
begin
  T:= nil;
  if T = nil then Exit;
end;
'@ @((Obj 'Old1' 'TOld'))
Form 'W4Form' 'Classes, LibOld' @('Old1: TOld;', 'Old2: TOld2;') '' @() '' @((Obj 'Old1' 'TOld'), (Bare 'Old2' 'TOld2'))
Form 'W5Form' 'Classes, SysUtils, LibOld' @('Old1: TOld;') '' @('function Up(const S: string): string;') @'
function TW5Form.Up(const S: string): string;
begin
  Result:= S.OldUpper;
end;
'@ @((Obj 'Old1' 'TOld'))
Form 'W6Form'  'Classes, Scope.LibAl' @('Al1: TAl;') '' @() '' @((Obj 'Al1' 'TAl'))
Form 'W6bForm' 'Classes, LibAl' @('Al1: TAl;', 'Al2: TAl2;') '' @() '' @((Obj 'Al1' 'TAl'), (Bare 'Al2' 'TAl2'))
Form 'W7Form' 'Classes {$IFNDEF NEVERDEF}, LibOld{$ENDIF}' @('Old1: TOld;', 'Old2: TOld2;') '' @() '' @((Obj 'Old1' 'TOld'), (Bare 'Old2' 'TOld2'))
Form 'W8Form' 'Classes {$IFNDEF NEVERDEF}, LibOld{$ENDIF}' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'U1Form' 'Classes, LibOld, GoneU' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'D1Form' 'Classes, LibOld, Fx.DB' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'D2Form' 'Classes, LibOld' @('Old1: TOld;') 'LibNew' @() '' @((Obj 'Old1' 'TOld'))
Form 'O1Form' 'Classes, LibOld' @('Old1: TOld;', 'Old2: TOld;') '' @() '' @((Obj 'Old1' 'TOld'), (Obj 'Old2' 'TOld'))
Form 'TieForm' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'BaseForm' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'DescForm' 'Classes, LibOld, BaseForm' @('Old3: TOld;') '' @() '' @((Obj 'Old1' 'TOld' 'inherited'), (Obj 'Old3' 'TOld')) 'TBaseForm'
# ENC2: tree-sitter columns are UTF-8 BYTES. Eight CP1252 0xA9 bytes (16 UTF-8
# bytes) before `Run2;` put the byte column 8 past the character column -- past
# the end of the line, so indexing the line with it raised ERangeError.
Form 'Enc2Form' 'Classes, LibOld' @('Old1: TOld;') '' @('procedure Run;', 'procedure Run2;') @'
procedure TEnc2Form.Run2;
begin
end;

procedure TEnc2Form.Run;
var
  S: string;
begin
  S:= 'EIGHT_MARKS'; Run2;
end;
'@ @((Obj 'Old1' 'TOld'))
$encBytes = [Text.Encoding]::ASCII.GetBytes((Text 'Enc2Form.pas'))
$encList = [Collections.Generic.List[byte]]::new($encBytes)
$at = [Text.Encoding]::ASCII.GetString($encBytes).IndexOf('EIGHT_MARKS')
$encList.RemoveRange($at, 'EIGHT_MARKS'.Length); $encList.InsertRange($at, [byte[]](@(0xA9) * 8))
[IO.File]::WriteAllBytes((P 'Enc2Form.pas'), $encList.ToArray())
# B2: Desc2Form uses its ancestor's Old2 in CODE only -- what convert-apply makes
# of that is read from the project DB (the field's declared type), so it is what
# a stale view of Base2Form would change.
Form 'Base2Form' 'Classes, LibOld' @('Old1: TOld;', 'Old2: TOld;') '' @() '' @((Obj 'Old1' 'TOld'), (Obj 'Old2' 'TOld'))
Form 'Desc2Form' 'Classes, LibOld, Base2Form' @('Old3: TOld;') '' @('procedure Run;') @'
procedure TDesc2Form.Run;
begin
  Old2.Caption:= 'x';
end;
'@ @((Obj 'Old1' 'TOld' 'inherited'), (Obj 'Old3' 'TOld')) 'TBase2Form'
foreach ($cf in @('CastForm', 'CastEForm', 'AmbForm', 'AmbUForm', 'NfForm')) {
  Form $cf 'Classes, LibPicOld' @('pic1: TPicOld;') '' @('procedure Setup;') @"
procedure T$cf.Setup;
begin
  pic1.Picture.Data := 'seed';
end;
"@ @("  object pic1: TPicOld`n    Picture.Data = 'seed'`n  end")
}

W 'P.dpr' (@('program P;', '', 'uses',
  '  LibOld, LibNew, Scope.LibAl, Fx.DB, LibTieA, LibTieB, LibPicOld, LibPicNew, LibEnum, LibCast, LibAmbA, LibAmbB,',
  '  W1Form, W2Form, W3Form, W4Form, W5Form, W6Form, W6bForm, W7Form, W8Form, U1Form, D1Form, D2Form, O1Form,',
  '  TieForm, BaseForm, DescForm, CastForm, CastEForm, AmbForm, AmbUForm, EncForm, Enc2Form, NfForm, Base2Form, Desc2Form;', '', 'begin', 'end.') -join "`n")

# ---- books ------------------------------------------------------------------
W 'old.rules'   "#convert TOld -> TNew`n#link Caption <- Caption`n#unuse LibOld`n"
W 'al.rules'    "#convert TAl -> TNew`n#link Caption <- Caption`n#unuse LibAl`n"
W 'gone.rules'  "#convert TOld -> TNew`n#link Caption <- Caption`n#unuse GoneU`n"
W 'db.rules'    "#convert TOld -> TNew`n#link Caption <- Caption`n#unuse LibOld`n#use DB`n"
W 'tie.rules'   "#convert TOld -> TTie`n#link Caption <- Caption`n"
W 'cast.rules'  "#convert TPicOld -> TPicNew`n#link Glyph <- Picture : CastA`n"
W 'caste.rules' "#convert TPicOld -> TPicNew`n#link Glyph <- Picture : CastE`n#unuse LibPicOld`n"
W 'amb.rules'   "#convert TPicOld -> TPicNew`n#link Glyph <- Picture : CastAmb`n"
W 'ambu.rules'  "#convert TPicOld -> TPicNew`n#link Glyph <- Picture : CastAmb`n#use LibAmbA`n"
W 'nf.rules'    "#convert TPicOld -> TPicNew`n#link Glyph <- Picture : CastNf`n"
W 'fx.castlib' @'
cast CastA
  accepts TSrcPic
  yields  TDstGlyph
  pas     '{dst}.Assign(CastPic({src}));'
end

cast CastE
  accepts TSrcPic
  yields  TDstGlyph
  pas     '{dst}.Assign(CastPicMode({src}, cmFancy));'
end

cast CastAmb
  accepts TSrcPic
  yields  TDstGlyph
  pas     '{dst}.Assign(AmbPic({src}));'
end

cast CastNf
  accepts TSrcPic
  yields  TDstGlyph
  pas     '{dst}.Assign(NoSuchPic({src}));'
end
'@

# B2: three untouched copies of the fixture, taken before anything is applied,
# each indexed into its own project DB below.
$b2 = @{}
foreach ($k in @('batch', 'single', 'ctl')) {
  $b2[$k] = P "b2$k"
  New-Item -ItemType Directory $b2[$k] -Force | Out-Null
  Get-ChildItem -LiteralPath $WorkDir -File | Copy-Item -Destination $b2[$k]
}

$db = P 'fx.sqlite'
& $Exe index --project (P 'P.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture PROJECT index was built' (Test-Path $db)

function Run([string]$Unit, [string]$Rules, [string[]]$Extra = @()) {
  $a = @('convert-apply', '--unit', (P $Unit), '--rules', (P $Rules), '--db', $db, '--castlib', (P 'fx.castlib')) + $Extra
  $o = (& $Exe @a 2>$null) -join "`n"
  $code = $LASTEXITCODE
  $j = $null
  if ($Extra -contains 'json') { try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {} }
  return [pscustomobject]@{ Code = $code; Out = $o; J = $j }
}
function J([string]$Unit, [string]$Rules, [string[]]$Extra = @()) { return Run $Unit $Rules (@('--format', 'json') + $Extra) }
function Rows($r, [string]$Action) { if ($null -eq $r.J) { return @() }; return @($r.J.uses | Where-Object { $_.action -eq $Action }) }
function Kinds($r) { if ($null -eq $r.J) { return @() }; return @($r.J.items | ForEach-Object { $_.kind }) }
function Need($row) { return (@($row.needed_by | ForEach-Object { $_.name }) -join ',') }

# ============================ dry-run contract ===============================
$r = J 'W1Form.pas' 'old.rules'
$rm = Rows $r 'remove'
Check 'W1 every TOld converts: LibOld REMOVED (remove row, source rule)' `
  (($r.Code -eq 0) -and ($rm.Count -eq 1) -and ($rm[0].unit -eq 'LibOld') -and ($rm[0].source -eq 'rule') -and ($r.J.uses_reconcile -eq 'on')) $r.Out
Check 'W1 ... apply/1 carries uses_kept / uses_moved / uses_unresolved, always' `
  (($null -ne $r.J) -and ($r.J.uses_kept -eq 0) -and ($r.J.uses_moved -eq 0) -and ($null -ne $r.J.uses_unresolved) -and (@($r.J.uses_unresolved).Count -eq 0)) $r.Out

$r = J 'EncForm.pas' 'old.rules'
Check 'ENC a CP1252 byte in the unit: re-index stays on (not degraded), LibOld removed' `
  (($r.Code -eq 0) -and ($r.J.uses_reconcile -eq 'on') -and ((Rows $r 'remove').Count -eq 1)) $r.Out
$r = J 'Enc2Form.pas' 'old.rules'
Check 'ENC2 eight CP1252 bytes before a reference: byte columns read as characters, not past the line end (on, LibOld removed)' `
  (($r.Code -eq 0) -and ($r.J.uses_reconcile -eq 'on') -and ((Rows $r 'remove').Count -eq 1)) $r.Out

$r = J 'W2Form.pas' 'old.rules'
$rm = Rows $r 'remove'
Check 'W2 (ruling 1/2) only .pas code (on E: ELibOld) needs LibOld: REMOVED anyway' (($r.Code -eq 0) -and ($rm.Count -eq 1) -and ($rm[0].unit -eq 'LibOld')) $r.Out
Check 'W2 ... the remove row names the dangling reference: needed_by ELibOld with its line' `
  (($rm.Count -eq 1) -and ((Need $rm[0]) -eq 'ELibOld') -and ($rm[0].needed_by[0].line -eq 31) -and ($rm[0].needed_by[0].section -eq 'implementation')) ($rm | ConvertTo-Json -Depth 5)
Check 'W2 ... and warns unit-rule-dangling' ((Kinds $r) -contains 'unit-rule-dangling') ((Kinds $r) -join ',')

$r = J 'W3Form.pas' 'old.rules'
$rm = Rows $r 'remove'
Check 'W3 a `var T: TOld` local alone: REMOVED, needed_by TOld' (($rm.Count -eq 1) -and ((Need $rm[0]) -eq 'TOld')) ($r.Out)

$r = J 'W4Form.pas' 'old.rules'
$kp = Rows $r 'kept'
Check 'W4 a second component type of LibOld (Old2: TOld2) still streams: LibOld KEPT' `
  (($r.Code -eq 0) -and ($kp.Count -eq 1) -and ($kp[0].unit -eq 'LibOld') -and ((Rows $r 'remove').Count -eq 0) -and ($r.J.uses_kept -eq 1)) $r.Out
Check 'W4 ... needed_by names the component, with its .dfm line' (($kp.Count -eq 1) -and ((Need $kp[0]) -eq 'Old2: TOld2') -and ($kp[0].needed_by[0].line -eq 5)) ($kp | ConvertTo-Json -Depth 5)
Check 'W4 ... `kept` is a WARNING (Q5): items[] unit-rule-kept + a line N: warning' `
  (((Kinds $r) -contains 'unit-rule-kept') -and (@($r.J.warnings | Where-Object { $_ -match '^line 3: warning: #unuse LibOld kept LibOld -- still needed by \.dfm component\(s\) Old2: TOld2' }).Count -eq 1)) ($r.J.warnings -join ' | ')

$r = J 'W5Form.pas' 'old.rules'
$rm = Rows $r 'remove'
Check 'W5 only a type-helper member (S.OldUpper) needs LibOld: REMOVED, needed_by OldUpper' (($rm.Count -eq 1) -and ((Need $rm[0]) -match 'OldUpper')) $r.Out

$r = J 'W6Form.pas' 'al.rules'
$rm = Rows $r 'remove'
Check 'W6 alias: `#unuse LibAl` removes the entry Scope.LibAl' (($rm.Count -eq 1) -and ($rm[0].unit -eq 'Scope.LibAl') -and ($rm[0].rule -eq '#unuse LibAl')) $r.Out
$r = J 'W6bForm.pas' 'al.rules'
$kp = Rows $r 'kept'
Check 'W6b alias: entry LibAl, keeper TAl2 declared in Scope.LibAl: KEPT' (($kp.Count -eq 1) -and ($kp[0].unit -eq 'LibAl') -and ((Need $kp[0]) -eq 'Al2: TAl2')) $r.Out

$r = J 'W7Form.pas' 'old.rules'
Check 'W7 a KEPT unit inside {$IFNDEF}: no refusal (R12), kept row' (($r.Code -eq 0) -and (-not $r.J.refused) -and ((Rows $r 'kept').Count -eq 1)) $r.Out
$r = Run 'W8Form.pas' 'old.rules'
Check 'W8 a REMOVED unit inside {$IFNDEF}: refused, message unchanged' `
  (($r.Code -eq 1) -and ($r.Out -match [regex]::Escape('REFUSED: W8Form.pas: "LibOld" sits inside a conditional ({$IF...}) region of the interface uses clause -- unit rules not applied to this unit'))) $r.Out

$r = J 'U1Form.pas' 'gone.rules'
$kp = Rows $r 'kept'
Check 'U1 (Q3) a watched unit no --db knows: KEPT with unit-rule-unverified' `
  (($kp.Count -eq 1) -and ($kp[0].unit -eq 'GoneU') -and ((Kinds $r) -contains 'unit-rule-unverified')) $r.Out

$r = J 'D1Form.pas' 'db.rules'
Check 'D1 `#use DB` on a unit using Fx.DB: no add (alias-aware presence)' (($r.Code -eq 0) -and (@($r.J.uses | Where-Object { $_.unit -eq 'DB' }).Count -eq 0)) $r.Out

$r = J 'D2Form.pas' 'old.rules'
$mv = Rows $r 'moved'
Check 'D2 the C13 move is now a uses[] row: moved LibNew to the interface' `
  (($mv.Count -eq 1) -and ($mv[0].unit -eq 'LibNew') -and ($mv[0].section -eq 'interface') -and ($r.J.uses_moved -eq 1)) $r.Out

$r = J 'DescForm.pas' 'old.rules'
$kp = Rows $r 'kept'
Check 'DESC inherited Old1 (ancestor unconverted) still streams TOld: LibOld KEPT -- no R26 refusal' `
  (($r.Code -eq 0) -and (-not $r.J.refused) -and ($kp.Count -eq 1) -and ((Need $kp[0]) -eq 'Old1: TOld')) $r.Out

$r = J 'O1Form.pas' 'old.rules' @('--only', 'Old1')
$sk = Rows $r 'skipped'
Check 'O1 --only Old1: the C13 N4 skipped row, byte-identical to 1.26.6' `
  (($sk.Count -eq 1) -and ($sk[0].unit -eq 'LibOld') -and ($sk[0].reason -eq 'would leave 1 unconverted instance(s) of TOld') -and ($sk[0].rule -eq '#unuse LibOld') -and ((Rows $r 'kept').Count -eq 0)) $r.Out
Check 'O1 ... and its unit-rule-skipped warning text unchanged' `
  (@($r.J.warnings | Where-Object { $_ -eq 'line 3: warning: #unuse LibOld skipped -- it would leave 1 unconverted instance(s) of TOld left out by --only; LibOld kept in uses' }).Count -eq 1) ($r.J.warnings -join ' | ')

$r = J 'TieForm.pas' 'tie.rules'
$un = @($r.J.uses_unresolved)
Check 'A3 (R8a) the To type TTie is declared in two units: none added, reported ambiguous with both' `
  (($un.Count -eq 1) -and ($un[0].name -eq 'TTie') -and ($un[0].reason -eq 'ambiguous') -and ((@($un[0].candidates | ForEach-Object { $_.unit }) | Sort-Object) -join ',') -eq 'LibTieA,LibTieB' -and
   ((Kinds $r) -contains 'uses-unit-ambiguous') -and -not ((Text 'TieForm.pas') -match 'LibTie')) $r.Out

$r = J 'CastForm.pas' 'cast.rules'
$ad = @(Rows $r 'add' | Where-Object { $_.unit -eq 'LibCast' })
Check 'A1 a cast template introduces CastPic: LibCast added (implementation, source reconcile, needed_by CastPic)' `
  (($ad.Count -eq 1) -and ($ad[0].section -eq 'implementation') -and ($ad[0].source -eq 'reconcile') -and ((Need $ad[0]) -eq 'CastPic')) $r.Out
$r = J 'CastEForm.pas' 'caste.rules'
$ad = @(Rows $r 'add' | ForEach-Object { $_.unit })
Check 'A1b ... CastPicMode + the enum value cmFancy: LibCast AND LibEnum added' (($ad -contains 'LibCast') -and ($ad -contains 'LibEnum')) $r.Out
$r = J 'AmbForm.pas' 'amb.rules'
$un = @($r.J.uses_unresolved)
Check 'A2 AmbPic is declared in LibAmbA and LibAmbB: no add, uses_unresolved ambiguous with both' `
  (($un.Count -eq 1) -and ($un[0].name -eq 'AmbPic') -and ($un[0].reason -eq 'ambiguous') -and (@($un[0].candidates).Count -eq 2) -and
   (@(Rows $r 'add' | Where-Object { $_.unit -like 'LibAmb*' }).Count -eq 0) -and ((Kinds $r) -contains 'uses-unit-ambiguous')) $r.Out
$r = J 'AmbUForm.pas' 'ambu.rules'
Check 'A2 ... with `#use LibAmbA` in the book: resolved, no warning, LibAmbA added once' `
  ((@($r.J.uses_unresolved).Count -eq 0) -and -not ((Kinds $r) -contains 'uses-unit-ambiguous') -and (@(Rows $r 'add' | Where-Object { $_.unit -eq 'LibAmbA' }).Count -eq 1)) $r.Out
$r = J 'NfForm.pas' 'nf.rules'
$un = @($r.J.uses_unresolved)
Check 'A4 NoSuchPic is declared by no --db: no add, uses_unresolved not-found with no candidates, no ambiguity warning' `
  (($r.Code -eq 0) -and ($un.Count -eq 1) -and ($un[0].name -eq 'NoSuchPic') -and ($un[0].reason -eq 'not-found') -and (@($un[0].candidates).Count -eq 0) -and
   ($un[0].section -eq 'implementation') -and (@(Rows $r 'add' | Where-Object { $_.source -eq 'reconcile' }).Count -eq 0) -and -not ((Kinds $r) -contains 'uses-unit-ambiguous')) $r.Out

# ---- N1: --no-reconcile-uses is 1.26.6 --------------------------------------
$r = J 'W2Form.pas' 'old.rules' @('--no-reconcile-uses')
Check 'N1 --no-reconcile-uses: uses_reconcile off, plain remove row, no needed_by, no dangling warning' `
  (($r.Code -eq 0) -and ($r.J.uses_reconcile -eq 'off') -and ((Rows $r 'remove').Count -eq 1) -and (@((Rows $r 'remove')[0].needed_by).Count -eq 0) -and -not ((Kinds $r) -contains 'unit-rule-dangling')) $r.Out
$r = J 'W4Form.pas' 'old.rules' @('--no-reconcile-uses')
Check 'N1 ... W4: 1.26.6 REMOVES LibOld although Old2: TOld2 still streams (R26 only counts #convert types) -- the defect W4 pins' `
  (($r.Code -eq 0) -and ((Rows $r 'remove').Count -eq 1) -and ((Rows $r 'kept').Count -eq 0)) $r.Out
$r = Run 'DescForm.pas' 'old.rules' @('--no-reconcile-uses')
Check 'N1 ... DESC refused by R26 exactly as 1.26.6' `
  (($r.Code -eq 1) -and ($r.Out -match [regex]::Escape('REFUSED: #unuse LibOld would leave 1 unconverted instance(s) of TOld -- unit not changed'))) $r.Out
$r = J 'D2Form.pas' 'old.rules' @('--no-reconcile-uses')
Check 'N1 ... D2 move has no uses[] row (1.26.6)' (($r.Code -eq 0) -and (@($r.J.uses).Count -eq 1) -and ((Rows $r 'moved').Count -eq 0)) $r.Out

# ---- R: the re-index step ---------------------------------------------------
$r = J 'W1Form.pas' 'old.rules'
Check 'R1 dry run: uses_reindex dry-run naming the project DB it would refresh' `
  (($null -ne $r.J.uses_reindex) -and ($r.J.uses_reindex.status -eq 'dry-run') -and ($r.J.uses_reindex.db -eq $db) -and ($r.J.uses_reindex.project -eq (P 'P.dpr'))) ($r.J.uses_reindex | ConvertTo-Json)
$other = P 'other.sqlite'
Copy-Item $db $other
$hOther = (Get-FileHash $other).Hash
$r = J 'W1Form.pas' 'old.rules' @('--apply', '--no-backup')
Check 'R2 --apply W1: exit 0, uses_reindex done on fx.sqlite' (($r.Code -eq 0) -and ($r.J.uses_reindex.status -eq 'done') -and ($r.J.uses_reindex.db -eq $db)) $r.Out
Check 'R2 ... a DB not passed to the run is untouched' ((Get-FileHash $other).Hash -eq $hOther)
$r = J 'W1Form.pas' 'old.rules'
Check 'I1 second run on the converted W1 (index refreshed by R2): no uses add/remove/moved/kept row, no refusal' `
  (($r.Code -eq 0) -and (@($r.J.uses | Where-Object { $_.action -in @('add','remove','moved','kept') }).Count -eq 0)) $r.Out
$r = J 'W4Form.pas' 'old.rules' @('--apply', '--no-backup', '--no-reindex')
Check 'R3 --no-reindex: uses_reindex off' (($r.Code -eq 0) -and ($r.J.uses_reindex.status -eq 'off')) ($r.J.uses_reindex | ConvertTo-Json)

# ---- B1: batch entries equal single runs ------------------------------------
$singles = @{}
foreach ($u in @('W2Form', 'W6Form')) { $singles[$u] = (J "$u.pas" (@{W2Form='old.rules'; W6Form='al.rules'}[$u])).J }
$b = (& $Exe convert-apply --unit (P 'W2Form.pas') --unit (P 'W3Form.pas') --rules (P 'old.rules') --db $db --format json 2>$null) -join "`n"
$bj = $null; try { $bj = $b.Substring($b.IndexOf('{')) | ConvertFrom-Json } catch {}
$s2 = (J 'W3Form.pas' 'old.rules').J
Check 'B1 batch W2+W3: each units[] uses[] equals its single run' `
  (($null -ne $bj) -and (($bj.units[0].uses | ConvertTo-Json -Depth 6) -eq ($singles['W2Form'].uses | ConvertTo-Json -Depth 6)) -and
   (($bj.units[1].uses | ConvertTo-Json -Depth 6) -eq ($s2.uses | ConvertTo-Json -Depth 6))) $b

# ---- B2: a batch --apply equals single runs (the refresh between units) -----
# Unit 1 (Base2Form) is written and its project DB re-indexed by a child process
# while this run keeps its stores and caches open; unit 2 (Desc2Form) inherits
# from it, so its entry depends on what the run sees of the CONVERTED ancestor.
# Compared without uses_reindex (ms differs; status asserted on its own) and
# classes_built (a per-unit cost counter: a batch reuses the classes unit 1
# already resolved). Paths are normalised to the copy's folder.
function ApplyJ([string]$Dir, [string[]]$Units, [string[]]$Extra = @()) {
  $a = @('convert-apply')
  foreach ($u in $Units) { $a += @('--unit', (Join-Path $Dir "$u.pas")) }
  $a += @('--rules', (Join-Path $Dir 'old.rules'), '--db', (Join-Path $Dir 'fx.sqlite'), '--apply', '--no-backup', '--format', 'json') + $Extra
  $o = (& $Exe @a 2>$null) -join "`n"
  try { return ($o.Substring($o.IndexOf('{')) | ConvertFrom-Json) } catch { return $null }
}
function Norm($Entry, [string]$Dir) {
  if ($null -eq $Entry) { return '<null>' }
  $c = $Entry | ConvertTo-Json -Depth 10 | ConvertFrom-Json
  $c.PSObject.Properties.Remove('uses_reindex')
  $c.PSObject.Properties.Remove('classes_built')
  return (($c | ConvertTo-Json -Depth 10 -Compress).Replace(($Dir -replace '\\', '\\'), '<D>'))
}
foreach ($k in $b2.Keys) { & $Exe index --project (Join-Path $b2[$k] 'P.dpr') --db (Join-Path $b2[$k] 'fx.sqlite') 2>&1 | Out-Null }
$bb = ApplyJ $b2['batch'] @('Base2Form', 'Desc2Form')
$sb = ApplyJ $b2['single'] @('Base2Form')
$sd = ApplyJ $b2['single'] @('Desc2Form')
$nb = if ($null -ne $bb) { Norm $bb.units[1] $b2['batch'] } else { '<null>' }
$ns = Norm $sd $b2['single']
Check 'B2 batch --apply Base2Form+Desc2Form: both units refreshed their project DB (uses_reindex done), single runs too' `
  (($null -ne $bb) -and ($bb.units[0].uses_reindex.status -eq 'done') -and ($bb.units[1].uses_reindex.status -eq 'done') -and
   ($sb.uses_reindex.status -eq 'done') -and ($sd.uses_reindex.status -eq 'done')) "batch: $($bb.units.uses_reindex | ConvertTo-Json -Compress) single: $($sd.uses_reindex | ConvertTo-Json -Compress)"
Check 'B2 ... Desc2Form''s batch entry equals its single run made after BaseForm was applied' ($nb -eq $ns) "batch : $nb`n      single: $ns"
Check 'B2 ... and the written Desc2Form.pas / .dfm are byte-identical' `
  (([IO.File]::ReadAllText((Join-Path $b2['batch'] 'Desc2Form.pas')) -eq [IO.File]::ReadAllText((Join-Path $b2['single'] 'Desc2Form.pas'))) -and
   ([IO.File]::ReadAllText((Join-Path $b2['batch'] 'Desc2Form.dfm')) -eq [IO.File]::ReadAllText((Join-Path $b2['single'] 'Desc2Form.dfm'))))
$cb = ApplyJ $b2['ctl'] @('Base2Form', 'Desc2Form') @('--no-reindex')
$nc = if ($null -ne $cb) { Norm $cb.units[1] $b2['ctl'] } else { '<null>' }
Check 'B2 positive control: the same batch with --no-reindex gives a DIFFERENT Desc2Form entry (the comparison can fail)' `
  (($null -ne $cb) -and ($cb.units[1].uses_reindex.status -eq 'off') -and ($nc -ne $ns)) "control: $nc"

# ---- --apply the rest, then compile and load --------------------------------
$written = @('W1Form.dfm', 'W4Form.dfm')
foreach ($x in @(@('W2Form','old.rules'), @('W3Form','old.rules'), @('W5Form','old.rules'), @('W6Form','al.rules'), @('W6bForm','al.rules'),
                 @('W7Form','old.rules'), @('D1Form','db.rules'), @('D2Form','old.rules'), @('DescForm','old.rules'),
                 @('CastForm','cast.rules'), @('CastEForm','caste.rules'))) {
  $r = Run "$($x[0]).pas" $x[1] @('--apply', '--no-backup')
  Check "X $($x[0]) --apply exits 0" ($r.Code -eq 0) $r.Out
  $written += "$($x[0]).dfm"
}
$r = Run 'O1Form.pas' 'old.rules' @('--apply', '--no-backup', '--only', 'Old1'); $written += 'O1Form.dfm'
Check 'X O1Form --apply --only Old1 exits 0' ($r.Code -eq 0) $r.Out
Check 'X W7 uses bytes unchanged around the kept conditional entry' ((Text 'W7Form.pas').Contains('{$IFNDEF NEVERDEF}, LibOld{$ENDIF}')) (Text 'W7Form.pas')
Check 'X W6 Scope.LibAl gone, LibNew in' (-not ((Text 'W6Form.pas') -match 'LibAl') -and ((Text 'W6Form.pas') -match 'LibNew')) (Text 'W6Form.pas')
Check 'X D1 no second DB unit' (-not ((Text 'D1Form.pas') -match '\bDB\b(?<!Fx\.DB)')) (Text 'D1Form.pas')

$bad = @(Test-DfmLoads @($written | ForEach-Object { P $_ }))
Check 'L every written .dfm loads (DfmLoadCheck)' ($bad.Count -eq 0) ($bad -join ' | ')

New-Item -ItemType Directory (P 'bin'), (P 'dcu') -Force | Out-Null
function Dcc([string]$Dpr, [string[]]$Units) {
  W "$Dpr.dpr" (@("program $Dpr;", '', 'uses', ('  ' + ($Units -join ', ') + ';'), '', 'begin', 'end.') -join "`n")
  $bat = P "$Dpr.bat"; $log = P "$Dpr.log"
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$WorkDir`"",
    "dcc64 -Q -B -NSSystem;Scope -E`"$WorkDir\bin`" -NU`"$WorkDir\dcu`" $Dpr.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join $CRLF), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  return (Get-Content $log -Raw -ErrorAction SilentlyContinue)
}
# CastForm / CastEForm are NOT in this set: the cast access-site rewrite
# replaces only the member token (`pic1.Picture` -> `pic1.<statement>.Data`),
# so their converted Setup body does not parse -- a defect of the cast
# realisation (Apply.pas Outcome 1), not of the uses reconciliation.
$cl = Dcc 'CGood' @('W1Form', 'W4Form', 'W6Form', 'W6bForm', 'W7Form', 'D1Form', 'D2Form', 'BaseForm', 'DescForm', 'O1Form')
Check 'C1 the reconciled units compile (dcc64)' (($cl -match 'BUILD_EXITCODE=0') -and -not ($cl -match '(?m)Error')) (@(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' }) -join ' | ')
foreach ($x in @(@('W2Form','ELibOld'), @('W3Form','TOld'), @('W5Form','OldUpper'))) {
  $cl = Dcc ("CBad" + $x[0]) @($x[0])
  Check "C2 (ruling 1) $($x[0]) does NOT compile, and the error names $($x[1])" (($cl -match 'BUILD_EXITCODE=1') -and ($cl -match ("E2003.*\b" + $x[1] + "\b"))) (@(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' }) -join ' | ')
}

# ---- I2: idempotence of the add / move / alias-removal paths -----------------
# CastForm / CastEForm took reconcile ADDs (A1 / A1b), D2Form a MOVE, W6Form an
# alias REMOVAL; each was applied above (index refreshed). A second run plans no
# uses add / remove / moved row.
foreach ($x in @(@('CastForm','cast.rules'), @('CastEForm','caste.rules'), @('D2Form','old.rules'), @('W6Form','al.rules'))) {
  $r = J "$($x[0]).pas" $x[1]
  Check "I2 second run on the converted $($x[0]): no uses add/remove/moved row" `
    (($null -ne $r.J) -and (-not $r.J.refused) -and (@($r.J.uses | Where-Object { $_.action -in @('add','remove','moved') }).Count -eq 0)) $r.Out
}

# ---- capability -------------------------------------------------------------
$info = (& $Exe info --json 2>$null) -join "`n"
$ij = $null; try { $ij = $info.Substring($info.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'K info --json: capabilities.uses_reconcile is true' (($null -ne $ij) -and ($ij.capabilities.uses_reconcile -eq $true)) ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
