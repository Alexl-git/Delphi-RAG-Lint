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
      resolves it on the next run. The To-type tie too. A3. A name no --db
      declares is reported not-found, nothing added. (1.27.0: a cast link
      writes no .pas access site, so a cast template introduces nothing any
      more -- A1 pins the per-site refusal and the ABSENCE of those adds; the
      cast forms parse and fail only at the refused site, C3.)
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
# A7-7: TSolo is declared at UNIT level in LibSolo only; LibNest declares a
# class-level (nested) TSolo, which is no unit-level declarer.
W 'LibSolo.pas' ((Text 'LibTieA.pas') -replace 'unit LibTieA;', 'unit LibSolo;' -replace 'TTie', 'TSolo')
W 'LibNest.pas' @'
unit LibNest;

interface

uses
  Classes;

type
  TNestHost = class(TComponent)
  public
    type
      TSolo = class(TComponent)
      private
        FCaption: string;
      published
        property Caption: string read FCaption write FCaption;
      end;
  end;

implementation

end.
'@
# A7-8: a second unit whose string helper also provides OldUpper.
W 'LibHelp2.pas' @'
unit LibHelp2;

interface

type
  TOldStrHelper2 = record helper for string
    function OldUpper: string;
  end;

implementation

uses
  SysUtils;

function TOldStrHelper2.OldUpper: string;
begin
  Result:= UpperCase(Self);
end;

end.
'@
# A7-9: TShared is declared by the watched LibOldS AND by LibDupI.
W 'LibOldS.pas' @'
unit LibOldS;

interface

uses
  Classes;

type
  TOldS = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TShared = Integer;

implementation

end.
'@
# F3 (review): the same nested-vs-unit-level shape with the names and the
# .dpr order SWAPPED -- the chosen unit must not depend on hash order.
W 'LibZSolo2.pas' ((Text 'LibTieA.pas') -replace 'unit LibTieA;', 'unit LibZSolo2;' -replace 'TTie', 'TSolo2')
W 'LibANest2.pas' ((Text 'LibNest.pas') -replace 'unit LibNest;', 'unit LibANest2;' -replace 'TSolo', 'TSolo2')
W 'LibDupI.pas' @'
unit LibDupI;

interface

type
  TShared = Integer;

implementation

end.
'@

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
# A8-1: the To type TTie ties (LibTieA / LibTieB) and the book picks LibTieA with
# #use. The retyped field is in the INTERFACE, so LibTieA must land there --
# added (TieUForm) or MOVED from the implementation clause (TieMForm, A8-4).
Form 'TieUForm' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'TieMForm' 'Classes, LibOld' @('Old1: TOld;') 'LibTieA' @() '' @((Obj 'Old1' 'TOld'))
# A8-3: W2Form with a comment glued to the implementation keyword.
Form 'W2iForm' 'Classes, LibOld' @('Old1: TOld;') 'SysUtils' @('procedure Run;', 'procedure Run2;') @'
procedure TW2iForm.Run2;
begin
end;

procedure TW2iForm.Run;
begin
  try
    Run2;
  except
    on E: ELibOld do raise;
  end;
end;
'@ @((Obj 'Old1' 'TOld'))
W 'W2iForm.pas' ((Text 'W2iForm.pas') -replace "(?m)^implementation\r?$", 'implementation{ glued }')
# A7-6: --only Old0 leaves Old1..Old5 (five own TOld instances, the needed_by
# cap) AND X2: TOld2, a sixth keeper no --only explains.
Form 'O2Form' 'Classes, LibOld' @('Old0: TOld;', 'Old1: TOld;', 'Old2: TOld;', 'Old3: TOld;', 'Old4: TOld;', 'Old5: TOld;', 'X2: TOld2;') '' @() '' `
  @((Obj 'Old0' 'TOld'), (Obj 'Old1' 'TOld'), (Obj 'Old2' 'TOld'), (Obj 'Old3' 'TOld'), (Obj 'Old4' 'TOld'), (Obj 'Old5' 'TOld'), (Bare 'X2' 'TOld2'))
Form 'SoloForm' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'W5bForm' 'Classes, SysUtils, LibOld, LibHelp2' @('Old1: TOld;') '' @('function Up(const S: string): string;') @'
function TW5bForm.Up(const S: string): string;
begin
  Result:= S.OldUpper;
end;
'@ @((Obj 'Old1' 'TOld'))
Form 'SecForm' 'Classes, LibOldS' @('Old1: TOldS;', 'X: TShared;') 'LibDupI' @() '' @((Obj 'Old1' 'TOldS'))
# A7-9 control: the same TShared referenced only in the IMPLEMENTATION, where
# LibDupI is visible -- not dangling.
# F1 (review): a tie settled ONLY by a #convert block's trailing unit.
Form 'TieCForm' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
# F2 (review): the unit already uses LibTieB, which the same book #unuse's.
Form 'TieRForm' 'Classes, LibOld, LibTieB' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'TieR2Form' 'Classes, LibOld, LibTieB' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
# F-minor: a #useswap whose Old the unit does not use settles nothing.
Form 'TieSForm' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'Solo2Form' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
# F-minor: an escaped &implementation identifier above the real keyword.
Form 'AmpForm' 'Classes, LibOld' @('&implementation: Integer;', 'E1: ELibOld;', 'Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
# F4 (converter capture 1.27.0): a #convert header's trailing unit is WRITTEN
# into the uses clause -- it must be an add row, counted by uses_added.
Form 'CvForm' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'CvUForm' 'Classes, LibOld' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'CvPForm' 'Classes, LibOld, LibNew' @('Old1: TOld;') '' @() '' @((Obj 'Old1' 'TOld'))
Form 'SecIForm' 'Classes, LibOldS' @('Old1: TOldS;') 'LibDupI' @('procedure Run;') @'
procedure TSecIForm.Run;
var
  X: TShared;
begin
  X:= 0;
  if X = 0 then Exit;
end;
'@ @((Obj 'Old1' 'TOldS'))
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
  '  LibSolo, LibNest, LibHelp2, LibOldS, LibDupI,',
  '  TieForm, BaseForm, DescForm, CastForm, CastEForm, AmbForm, AmbUForm, EncForm, Enc2Form, NfForm, Base2Form, Desc2Form,',
  '  TieUForm, TieMForm, W2iForm, O2Form, SoloForm, W5bForm, SecForm, SecIForm,',
  '  LibANest2, LibZSolo2, TieCForm, TieRForm, TieR2Form, TieSForm, Solo2Form, AmpForm, CvForm, CvUForm, CvPForm;', '', 'begin', 'end.') -join "`n")

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
W 'tieu.rules'  "#convert TOld -> TTie`n#link Caption <- Caption`n#use LibTieA`n"
W 'solo.rules'  "#convert TOld -> TSolo`n#link Caption <- Caption`n"
W 'tiec.rules'  "#convert TOld -> TTie, LibTieA`n#link Caption <- Caption`n"
W 'tier.rules'  "#convert TOld -> TTie`n#link Caption <- Caption`n#unuse LibTieB`n"
W 'tier2.rules' "#convert TOld -> TTie`n#link Caption <- Caption`n#unuse LibTieB`n#use LibTieA`n"
W 'ties.rules'  "#convert TOld -> TTie`n#link Caption <- Caption`n#useswap LibAmbA -> LibTieA`n"
W 'solo2.rules' "#convert TOld -> TSolo2`n#link Caption <- Caption`n"
W 'cv.rules'    "#convert TOld -> TNew, LibNew`n#link Caption <- Caption`n"
W 'cvu.rules'   "#unuse LibOld`n#convert TOld -> TNew, LibNew`n#link Caption <- Caption`n"
W 'olds.rules'  "#convert TOldS -> TNew`n#link Caption <- Caption`n#unuse LibOldS`n"
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
Check 'A7-10 ... and the warning says how to fix it: pass the platform library --db (resolve-dbs --platform Win32|Win64)' `
  (@($r.J.warnings | Where-Object { $_ -match 'GoneU' -and $_ -match [regex]::Escape('pass the platform library --db (resolve-dbs --platform Win32|Win64)') }).Count -eq 1) ($r.J.warnings -join ' | ')

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
Check 'A8-2 ... the uses_unresolved row carries the line of the retyped field (10), not 0' `
  (($un.Count -eq 1) -and ($un[0].line -eq 10) -and ($un[0].section -eq 'interface')) ($un | ConvertTo-Json -Depth 5)

# ---- A8-1 / A8-4: a #use resolves the To-type tie, in the INTERFACE ----------
$r = J 'TieUForm.pas' 'tieu.rules'
$ad = @(Rows $r 'add' | Where-Object { $_.unit -eq 'LibTieA' })
Check 'A8-1 #use LibTieA resolves the TTie tie: no ambiguity warning, no uses_unresolved row' `
  (($r.Code -eq 0) -and -not ((Kinds $r) -contains 'uses-unit-ambiguous') -and (@($r.J.uses_unresolved).Count -eq 0)) $r.Out
Check 'A8-1 ... LibTieA is added ONCE, to the INTERFACE uses (the retyped field is declared there), rule #use LibTieA' `
  (($ad.Count -eq 1) -and ($ad[0].section -eq 'interface') -and ($ad[0].rule -eq '#use LibTieA')) ($r.J.uses | ConvertTo-Json -Depth 5)
$r = J 'TieMForm.pas' 'tieu.rules'
$mv = Rows $r 'moved'
Check 'A8-4 LibTieA used only in the implementation: MOVED to the interface (moved row), no ambiguity, no add' `
  (($r.Code -eq 0) -and ($mv.Count -eq 1) -and ($mv[0].unit -eq 'LibTieA') -and ($mv[0].section -eq 'interface') -and
   ((Rows $r 'add').Count -eq 0) -and -not ((Kinds $r) -contains 'uses-unit-ambiguous')) $r.Out

# ---- A8-3: 'implementation{comment}' is still the implementation keyword -----
$r = J 'W2iForm.pas' 'old.rules'
$rm = Rows $r 'remove'
Check 'A8-3 implementation{ glued }: the dangling ELibOld is in the IMPLEMENTATION section (line 31)' `
  (($rm.Count -eq 1) -and ((Need $rm[0]) -eq 'ELibOld') -and ($rm[0].needed_by[0].line -eq 31) -and ($rm[0].needed_by[0].section -eq 'implementation')) ($rm | ConvertTo-Json -Depth 5)

# ---- A7-6: a keeper past the needed_by cap still counts --------------------
$r = J 'O2Form.pas' 'old.rules' @('--only', 'Old0')
Check 'A7-6 --only Old0 with 5 own left-out TOld instances + X2: TOld2 (6th keeper): KEPT, not skipped' `
  (($r.Code -eq 0) -and ((Rows $r 'kept').Count -eq 1) -and ((Rows $r 'skipped').Count -eq 0)) $r.Out

# ---- A7-7: a class-level (nested) declaration is no unit-level declarer -----
$r = J 'SoloForm.pas' 'solo.rules'
Check 'A7-7 TSolo (unit level in LibSolo, nested in LibNest): not ambiguous, nothing unresolved' `
  (($r.Code -eq 0) -and -not ((Kinds $r) -contains 'uses-unit-ambiguous') -and (@($r.J.uses_unresolved).Count -eq 0)) $r.Out

# ---- A7-8: a helper member another kept unit provides is not dangling -------
$r = J 'W5bForm.pas' 'old.rules'
$rm = Rows $r 'remove'
Check 'A7-8 S.OldUpper also provided by LibHelp2 (kept): LibOld removed with NO needed_by, no unit-rule-dangling' `
  (($rm.Count -eq 1) -and (@($rm[0].needed_by).Count -eq 0) -and -not ((Kinds $r) -contains 'unit-rule-dangling')) $r.Out

# ---- review fix wave ---------------------------------------------------------
$r = J 'TieCForm.pas' 'tiec.rules'
Check 'F1 a tie settled only by the #convert block unit (LibTieA): no ambiguity, nothing unresolved (the write is checked in X F1 / C1 -- the #convert surface''s own add has no uses[] row)' `
  (($r.Code -eq 0) -and -not ((Kinds $r) -contains 'uses-unit-ambiguous') -and (@($r.J.uses_unresolved).Count -eq 0)) $r.Out
$r = J 'TieRForm.pas' 'tier.rules'
Check 'F2 #unuse LibTieB on a unit using LibTieB: LibTieB does not settle the tie (ambiguity reported) and its #unuse is not cancelled (a remove or kept row for it)' `
  (((Kinds $r) -contains 'uses-unit-ambiguous') -and (@($r.J.uses | Where-Object { $_.unit -eq 'LibTieB' -and $_.action -in @('remove','kept') }).Count -eq 1)) $r.Out
$r = J 'TieR2Form.pas' 'tier2.rules'
Check 'F2 ... + #use LibTieA: the tie goes to LibTieA (interface), LibTieB REMOVED, no ambiguity' `
  (-not ((Kinds $r) -contains 'uses-unit-ambiguous') -and (@(Rows $r 'remove' | Where-Object { $_.unit -eq 'LibTieB' }).Count -eq 1) -and
   (@(Rows $r 'add' | Where-Object { $_.unit -eq 'LibTieA' -and $_.section -eq 'interface' }).Count -eq 1)) $r.Out
$r = J 'TieSForm.pas' 'ties.rules'
Check 'F-minor #useswap LibAmbA -> LibTieA on a unit without LibAmbA settles nothing: the tie is reported, LibTieA not added' `
  (((Kinds $r) -contains 'uses-unit-ambiguous') -and (@(Rows $r 'add' | Where-Object { $_.unit -eq 'LibTieA' }).Count -eq 0)) $r.Out
$r = J 'Solo2Form.pas' 'solo2.rules'
Check 'F3 swapped names / order (LibANest2 nested, LibZSolo2 unit level): no ambiguity, the unit added is LibZSolo2' `
  (-not ((Kinds $r) -contains 'uses-unit-ambiguous') -and ($r.J.items | Where-Object { $_.kind -eq 'field-retyped' }) -and
   -not ($r.Out -match 'LibANest2')) $r.Out
$r = J 'AmpForm.pas' 'old.rules'
$rm = Rows $r 'remove'
Check 'F-minor &implementation (an escaped identifier) is not the keyword: E1: ELibOld dangles in the INTERFACE' `
  (($rm.Count -eq 1) -and ((Need $rm[0]) -eq 'ELibOld') -and ($rm[0].needed_by[0].section -eq 'interface')) $r.Out
function AddRows($r) { return @(Rows $r 'add') }
$r = J 'CvForm.pas' 'cv.rules'
$ad = AddRows $r
Check 'F4 #convert TOld -> TNew, LibNew (no unit rules): ONE add row -- LibNew, interface, line 6, rule #convert, source rule -- and uses_added 1' `
  (($r.Code -eq 0) -and ($ad.Count -eq 1) -and ($ad[0].unit -eq 'LibNew') -and ($ad[0].section -eq 'interface') -and ($ad[0].line -eq 6) -and
   ($ad[0].rule -eq '#convert') -and ($ad[0].source -eq 'rule') -and ($r.J.uses_added -eq 1)) ($r.J.uses | ConvertTo-Json -Depth 5)
$r = J 'CvUForm.pas' 'cvu.rules'
$ad = AddRows $r
Check 'F4 ... with #unuse LibOld (the capture shape): remove LibOld AND add LibNew (interface, #convert, rule), uses_added 1, uses_removed 1' `
  (($r.Code -eq 0) -and ($ad.Count -eq 1) -and ($ad[0].unit -eq 'LibNew') -and ($ad[0].section -eq 'interface') -and ($ad[0].rule -eq '#convert') -and
   ($ad[0].source -eq 'rule') -and ($r.J.uses_added -eq 1) -and ($r.J.uses_removed -eq 1)) ($r.J.uses | ConvertTo-Json -Depth 5)
$r = J 'CvPForm.pas' 'cv.rules'
Check 'F4 control: LibNew already in the uses -- no add row, uses_added 0' `
  (($r.Code -eq 0) -and ((AddRows $r).Count -eq 0) -and ($r.J.uses_added -eq 0)) ($r.J.uses | ConvertTo-Json -Depth 5)
# ---- A7-9: an interface name is not satisfied by an implementation-only unit -
$r = J 'SecForm.pas' 'olds.rules'
$rm = Rows $r 'remove'
Check 'A7-9 TShared (interface field) declared by LibOldS (removed) and LibDupI (implementation uses only): dangling, section interface' `
  (($rm.Count -eq 1) -and ($rm[0].unit -eq 'LibOldS') -and ((Need $rm[0]) -eq 'TShared') -and ($rm[0].needed_by[0].section -eq 'interface')) $r.Out
$r = J 'SecIForm.pas' 'olds.rules'
$rm = Rows $r 'remove'
Check 'A7-9 control: TShared referenced only in the implementation, LibDupI in the implementation uses: NOT dangling' `
  (($rm.Count -eq 1) -and ($rm[0].unit -eq 'LibOldS') -and (@($rm[0].needed_by).Count -eq 0) -and -not ((Kinds $r) -contains 'unit-rule-dangling')) $r.Out

# 1.27.0 (cast-link refusal, owner decision): a cast link writes NO .pas access
# site, so a cast template's routine (CastPic, CastPicMode + cmFancy, AmbPic,
# NoSuchPic) never reaches the converted .pas and the reconciliation has no
# introduced name to add, report ambiguous or report not-found. Until 1.26.x
# A1 / A1b / A2 / A4 asserted those adds and uses_unresolved rows; they now
# assert their ABSENCE deliberately, plus the per-site refusal that replaced
# the template. The reconcile-add path (PlanNewNames) has no convert-apply
# route left -- see the known gap in the 1.27.0 CHANGELOG; A3 below still pins
# the ambiguity reporting of the #convert surface's To type.
function CastRefused($r) { return @(if ($r.J) { $r.J.items | Where-Object { $_.kind -eq 'cast-not-applied' -and $_.instance -eq 'pic1' -and $_.line -eq 20 } }) }
foreach ($x in @(@('CastForm','cast.rules','CastA'), @('CastEForm','caste.rules','CastE'), @('AmbForm','amb.rules','CastAmb'),
                 @('AmbUForm','ambu.rules','CastAmb'), @('NfForm','nf.rules','CastNf'))) {
  $r = J "$($x[0]).pas" $x[1]
  $cr = CastRefused $r
  Check "A1 $($x[0]): the cast link's access site pic1.Picture (line 20) is REFUSED, one cast-not-applied naming $($x[2])" `
    (($r.Code -eq 0) -and ($cr.Count -eq 1) -and ($cr[0].value -eq $x[2]) -and ($cr[0].text -match "$($x[0])\.pas:20 pic1\.Picture") -and
     ($cr[0].text -match 'convert this access site by hand')) $r.Out
  Check "A1 ... $($x[0]): so no reconcile add and no uses_unresolved row (the template never reaches the .pas)" `
    ((@(Rows $r 'add' | Where-Object { $_.source -eq 'reconcile' }).Count -eq 0) -and (@($r.J.uses_unresolved).Count -eq 0) -and
     -not ((Kinds $r) -contains 'uses-unit-ambiguous') -and -not ((Kinds $r) -contains 'cast-applied')) $r.Out
}

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
                 @('CastForm','cast.rules'), @('CastEForm','caste.rules'),
                 @('TieUForm','tieu.rules'), @('TieMForm','tieu.rules'), @('SoloForm','solo.rules'), @('W5bForm','old.rules'), @('SecIForm','olds.rules'),
                 @('TieCForm','tiec.rules'), @('TieR2Form','tier2.rules'), @('Solo2Form','solo2.rules'), @('CvForm','cv.rules'))) {
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
Check 'X TieUForm LibTieA written into the INTERFACE uses' ((Text 'TieUForm.pas') -match "interface\s+uses\s+Classes, LibOld, LibTieA;") (Text 'TieUForm.pas')
Check 'X TieMForm LibTieA moved: in the interface uses, no longer in the implementation' `
  (((Text 'TieMForm.pas') -match "interface\s+uses\s+Classes, LibOld, LibTieA;") -and -not ((Text 'TieMForm.pas') -match "implementation\s+uses")) (Text 'TieMForm.pas')
Check 'X SoloForm LibSolo added, LibNest not' (((Text 'SoloForm.pas') -match '\bLibSolo\b') -and -not ((Text 'SoloForm.pas') -match 'LibNest')) (Text 'SoloForm.pas')
Check 'X F1 TieCForm LibTieA written into the INTERFACE uses' ((Text 'TieCForm.pas') -match "interface\s+uses\s+Classes, LibOld, LibTieA;") (Text 'TieCForm.pas')
Check 'X F2 TieR2Form LibTieB gone, LibTieA in the interface' (((Text 'TieR2Form.pas') -match "interface\s+uses\s+Classes, LibOld, LibTieA;") -and -not ((Text 'TieR2Form.pas') -match 'LibTieB')) (Text 'TieR2Form.pas')
Check 'X F3 Solo2Form LibZSolo2 added, LibANest2 not' (((Text 'Solo2Form.pas') -match '\bLibZSolo2\b') -and -not ((Text 'Solo2Form.pas') -match 'LibANest2')) (Text 'Solo2Form.pas')
# A8-1 / A8-4 / A7-7 / A7-8 / A7-9 control: these must COMPILE -- an interface field typed by a
# unit in the implementation uses (the A8-1 defect) is E2003.
$cl = Dcc 'CGood' @('W1Form', 'W4Form', 'W6Form', 'W6bForm', 'W7Form', 'D1Form', 'D2Form', 'BaseForm', 'DescForm', 'O1Form',
                    'TieUForm', 'TieMForm', 'SoloForm', 'W5bForm', 'SecIForm', 'TieCForm', 'TieR2Form', 'Solo2Form', 'CvForm')
Check 'C1 the reconciled units compile (dcc64)' (($cl -match 'BUILD_EXITCODE=0') -and -not ($cl -match '(?m)Error')) (@(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' }) -join ' | ')
# CastForm / CastEForm: until 1.26.x they were EXCLUDED here because the cast
# realisation spliced a statement over the member token (`pic1.pic1.Glyph.
# Assign(CastPic(pic1.Picture));.Data`) and the unit did not parse. 1.27.0
# refuses the site instead, so the converted unit PARSES and its one error is
# the refused access site itself -- pic1 is a TPicNew, which has no Picture --
# exactly the hand-conversion the cast-not-applied warning names (ruling 1:
# the compile error is the signal). Any other error, a syntax error above all,
# fails this check.
foreach ($cf in @('CastForm', 'CastEForm')) {
  $cl = Dcc ("CCast" + $cf) @($cf)
  $errs = @(($cl -split "`r?`n") | Where-Object { $_ -match '\b(Error|Fatal)\b' })
  Check "C3 (cast refusal) $cf parses; its only error is the refused site: E2003 Picture at $cf.pas(20)" `
    (($cl -match 'BUILD_EXITCODE=1') -and ($errs.Count -ge 1) -and
     (@($errs | Where-Object { $_ -notmatch ("$cf\.pas\(20\).*E2003.*\bPicture\b") -and $_ -notmatch 'F2063|Fatal: F2613|Could not compile used unit' }).Count -eq 0) -and
     (@($errs | Where-Object { $_ -match ("$cf\.pas\(20\).*E2003.*\bPicture\b") }).Count -eq 1)) ($errs -join ' | ')
}
foreach ($x in @(@('W2Form','ELibOld'), @('W3Form','TOld'), @('W5Form','OldUpper'))) {
  $cl = Dcc ("CBad" + $x[0]) @($x[0])
  Check "C2 (ruling 1) $($x[0]) does NOT compile, and the error names $($x[1])" (($cl -match 'BUILD_EXITCODE=1') -and ($cl -match ("E2003.*\b" + $x[1] + "\b"))) (@(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' }) -join ' | ')
}

# ---- I2: idempotence of the add / move / alias-removal paths -----------------
# CastForm / CastEForm took reconcile ADDs until 1.26.x (since 1.27.0 a cast link
# writes no .pas site, so they take none -- CastEForm still a #unuse removal),
# D2Form a MOVE, W6Form an
# alias REMOVAL; each was applied above (index refreshed). A second run plans no
# uses add / remove / moved row.
foreach ($x in @(@('CastForm','cast.rules'), @('CastEForm','caste.rules'), @('D2Form','old.rules'), @('W6Form','al.rules'),
                 @('TieUForm','tieu.rules'), @('TieMForm','tieu.rules'))) {
  $r = J "$($x[0]).pas" $x[1]
  Check "I2 second run on the converted $($x[0]): no uses add/remove/moved row, no ambiguity warning" `
    (($null -ne $r.J) -and (-not $r.J.refused) -and (@($r.J.uses | Where-Object { $_.action -in @('add','remove','moved') }).Count -eq 0) -and
     -not ((Kinds $r) -contains 'uses-unit-ambiguous')) $r.Out
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
