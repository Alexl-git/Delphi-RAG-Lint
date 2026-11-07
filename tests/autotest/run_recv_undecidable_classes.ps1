<#
  run_recv_undecidable_classes.ps1 -- spec 2026-11-06-recv-undecidable, classes D02, D03, D04, D12:
  dotted calls the library oracle declined although Delphi's own lookup decides them.

    D02 a library global hidden by a same-named type in a unit the file does not use:
        `Application` also names typelib interfaces in units nobody uses.
    D04 a library routine named through its unit: `System.SysUtils.DeleteFile`.
    D03 the implicit TObject root: `sb.Free` on a class with no written parent, a project class
        with a complete chain, a library class behind a generic ancestor, and a type name with
        several class candidates that all give the same member.
    D12 a class-level `var` section: `FVM.LoadSettings`.

  A wrong binding is worse than none, so each class carries controls that must stay unbound.
  Reads refs.external_target and call_edges from a fixture DB. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_recv_undec_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($dir,$name,$t){ [IO.File]::WriteAllText((Join-Path $dir $name), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$lib = Join-Path $WorkDir 'lib'; $app = Join-Path $WorkDir 'app'
New-Item -ItemType Directory -Path $lib,$app | Out-Null

W $lib 'System.pas' @'
unit System;
interface
type
  TObject = class
  public
    procedure Free;
    function ClassName: string;
  end;
function Pos(const A, B: string): Integer;
implementation
procedure TObject.Free; begin end;
function TObject.ClassName: string; begin Result := ''; end;
function Pos(const A, B: string): Integer; begin Result := 0; end;
end.
'@
W $lib 'System.SysUtils.pas' @'
unit System.SysUtils;
interface
function DeleteFile(const A: string): Boolean;
function OnlyInSysUtils: Integer;
implementation
function DeleteFile(const A: string): Boolean; begin Result := False; end;
function OnlyInSysUtils: Integer; begin Result := 0; end;
end.
'@
W $lib 'Winapi.Windows.pas' @'
unit Winapi.Windows;
interface
function CloseHandle(H: Integer): Boolean;
implementation
function CloseHandle(H: Integer): Boolean; begin Result := False; end;
end.
'@
W $lib 'Word2000.pas' @'
unit Word2000;
interface
type
  System = interface
    procedure WordOnly;
  end;
implementation
end.
'@
W $lib 'WordXP.pas' @'
unit WordXP;
interface
type
  System = interface
    procedure WordOnly;
  end;
implementation
end.
'@
W $lib 'NotUsedUnit.pas' @'
unit NotUsedUnit;
interface
function HiddenRoutine: Integer;
implementation
function HiddenRoutine: Integer; begin Result := 0; end;
end.
'@
W $lib 'Vcl.Forms.pas' @'
unit Vcl.Forms;
interface
type
  TApplication = class
  public
    procedure ProcessMessages;
  end;
  TScreen = class
  public
    procedure Refresh;
  end;
var
  Application: TApplication;
  Screen: TScreen;
implementation
procedure TApplication.ProcessMessages; begin end;
procedure TScreen.Refresh; begin end;
end.
'@
W $lib 'FMX.Forms.pas' @'
unit FMX.Forms;
interface
type
  TApplication = class
  public
    procedure ProcessMessages;
  end;
var
  Application: TApplication;
implementation
procedure TApplication.ProcessMessages; begin end;
end.
'@
W $lib 'Graph2010.pas' @'
unit Graph2010;
interface
type
  Application = interface
    procedure Quit;
  end;
implementation
end.
'@
W $lib 'VBIDE2000.pas' @'
unit VBIDE2000;
interface
type
  Application = interface
    procedure Quit;
  end;
implementation
end.
'@
W $lib 'Access2000.pas' @'
unit Access2000;
interface
type
  Screen = interface
    procedure Refresh;
  end;
implementation
end.
'@
W $lib 'Gen.Coll.pas' @'
unit Gen.Coll;
interface
type
  TEnumerable<T> = class abstract
  public
    function ToArray: Integer;
  end;
  TList<T> = class(TEnumerable<T>)
  public
    procedure Add(const V: T);
  end;
  TDictionary<K, V> = class(TEnumerable<K>)
  public
    procedure AddPair(const AK: K);
  end;
  TObjDict<K, V> = class(TDictionary<K, V>)
  end;
implementation
function TEnumerable<T>.ToArray: Integer; begin Result := 0; end;
procedure TList<T>.Add(const V: T); begin end;
procedure TDictionary<K, V>.AddPair(const AK: K); begin end;
end.
'@
W $lib 'Old.Classes.pas' @'
unit Old.Classes;
interface
type
  TList = class
  public
    procedure Add(P: Pointer);
  end;
  TStrB = class
  public
    function Append(const S: string): TStrB;
  end;
  TBehindUnknown = class(TNotIndexedAnywhere)
  end;
  TRecNoFree = record
    X: Integer;
  end;
  ITalk = interface
    procedure Say;
  end;
  TTwice = class
  end;
  TMixed = class
  end;
implementation
procedure TList.Add(P: Pointer); begin end;
function TStrB.Append(const S: string): TStrB; begin Result := Self; end;
end.
'@
W $lib 'Other.Classes.pas' @'
unit Other.Classes;
interface
type
  TTwice = class
  public
    procedure Free;
  end;
  TMixed = record
    X: Integer;
  end;
implementation
procedure TTwice.Free; begin end;
end.
'@

W $app 'uProj.pas' @'
unit uProj;
interface
type
  TNoParent = class
  public
    procedure Own;
  end;
  TChild = class(TNoParent)
  end;
  TProjRec = record
    X: Integer;
  end;
  IProj = interface
    procedure Say;
  end;
  TGenChild = class(TList<Integer>)
  end;
  TBehind = class(TNotIndexedAnywhere)
  end;
  TVm = class
  public
    procedure LoadSettings;
  end;
  THolder = class
  var
    FVM: TVm;
    FList: TNoParent;
  public
    procedure Go;
  end;
implementation
procedure TNoParent.Own; begin end;
procedure TVm.LoadSettings; begin end;
procedure THolder.Go;
begin
  FVM.LoadSettings;
  FList.Free;
end;
end.
'@
W $app 'uD02Vcl.pas' @'
unit uD02Vcl;
interface
uses Vcl.Forms;
procedure Go;
implementation
procedure Go;
begin
  Application.ProcessMessages;
  Screen.Refresh;
end;
end.
'@
W $app 'uD02Both.pas' @'
unit uD02Both;
interface
uses Vcl.Forms, FMX.Forms;
procedure GoBoth;
implementation
procedure GoBoth;
begin
  Application.ProcessMessages;
end;
end.
'@
W $app 'uD02None.pas' @'
unit uD02None;
interface
procedure GoNone;
implementation
procedure GoNone;
begin
  Application.ProcessMessages;
end;
end.
'@
W $app 'uD02Seen.pas' @'
unit uD02Seen;
interface
uses Vcl.Forms, Graph2010;
procedure GoSeen;
implementation
procedure GoSeen;
begin
  Application.ProcessMessages;
end;
end.
'@
W $app 'uD04.pas' @'
unit uD04;
interface
uses System.SysUtils, Winapi.Windows;
procedure GoUnit;
implementation
procedure GoUnit;
begin
  System.SysUtils.DeleteFile('x');
  SysUtils.OnlyInSysUtils;
  Winapi.Windows.CloseHandle(0);
  Windows.CloseHandle(0);
  System.Pos('a', 'b');
  System.SysUtils.NoSuchRoutine;
  NotUsedUnit.HiddenRoutine;
end;
end.
'@
W $app 'uD03.pas' @'
unit uD03;
interface
uses Gen.Coll, Old.Classes, Other.Classes, uProj;
procedure GoFree;
implementation
procedure GoFree;
var
  N: TNoParent;
  C: TChild;
  R: TProjRec;
  I: IProj;
  G: TGenChild;
  B: TBehind;
  S: TStrB;
  LU: TBehindUnknown;
  LR: TRecNoFree;
  LI: ITalk;
  D: TDictionary<Integer, Integer>;
  OD: TObjDict<Integer, Integer>;
  E: TObjDict<Integer, Integer>;
  L: TList;
  L2: TList;
  W: TTwice;
  M: TMixed;
begin
  N.Free;
  C.Free;
  N.NoSuchMember;
  R.Free;
  I.Free;
  G.Free;
  B.Free;
  S.Free;
  LU.Free;
  LR.Free;
  LI.Free;
  D.Free;
  OD.Free;
  E.ToArray;
  L.Free;
  L2.Add(nil);
  W.Free;
  M.Free;
end;
end.
'@
W $app 'App.dpr' @'
program App;
uses
  uProj in 'uProj.pas',
  uD02Vcl in 'uD02Vcl.pas',
  uD02Both in 'uD02Both.pas',
  uD02None in 'uD02None.pas',
  uD02Seen in 'uD02Seen.pas',
  uD04 in 'uD04.pas',
  uD03 in 'uD03.pas';
begin
end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'; $appDb = Join-Path $WorkDir 'app.sqlite'
Push-Location C:\TEMP
& $exePath index $lib --db $libDb 2>&1 | Out-Null
Check 'V library index built' (Test-Path $libDb) $libDb
& $exePath index --project (Join-Path $app 'App.dpr') --db $appDb --library-db $libDb 2>&1 | Out-Null
Check 'V app index built' (Test-Path $appDb) $appDb
$j = & $exePath sql --db $appDb --json --limit 2000 --query "SELECT '' p, r.start_line, r.receiver_text, r.name_text, coalesce(r.external_target,''), coalesce(t.qualified_name,'') , f.path FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN call_edges c ON c.ref_id = r.id LEFT JOIN symbols t ON t.id = c.target_symbol_id WHERE r.kind = 'call' AND r.receiver_text <> ''" | Out-String | ConvertFrom-Json
Pop-Location

$rows = foreach ($r in $j.rows) { [pscustomobject]@{ File=[IO.Path]::GetFileNameWithoutExtension([string]$r[6]); Rcv=[string]$r[2]; Name=[string]$r[3]; Ext=[string]$r[4]; Edge=[string]$r[5] } }
Check "V the sites were read ($(@($rows).Count))" (@($rows).Count -ge 30)
function Site($file,$rcv,$name){ @($rows | Where-Object { $_.File -eq $file -and $_.Rcv -eq $rcv -and $_.Name -eq $name }) | Select-Object -First 1 }
function Ext($id,$file,$rcv,$name,$want){
  $s = Site $file $rcv $name
  Check "$id $file $rcv.$name -> $want (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -ceq $want -and $s.Edge -eq '') "edge='$($s.Edge)'"
}
function None($id,$file,$rcv,$name){
  $s = Site $file $rcv $name
  Check "$id CONTROL $file $rcv.$name stays unbound (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -eq '' -and $s.Edge -eq '') "edge='$($s.Edge)'"
}

# ---- D02 ----
Ext  'D02a' 'uD02Vcl'  'Application' 'ProcessMessages' 'Vcl.Forms.TApplication.ProcessMessages'
Ext  'D02b' 'uD02Vcl'  'Screen'      'Refresh'         'Vcl.Forms.TScreen.Refresh'
None 'D02c' 'uD02Both' 'Application' 'ProcessMessages'
None 'D02d' 'uD02None' 'Application' 'ProcessMessages'
None 'D02e' 'uD02Seen' 'Application' 'ProcessMessages'

# ---- D04 ----
Ext  'D04a' 'uD04' 'System.SysUtils' 'DeleteFile'     'System.SysUtils.DeleteFile'
Ext  'D04b' 'uD04' 'SysUtils'        'OnlyInSysUtils' 'System.SysUtils.OnlyInSysUtils'
Ext  'D04c' 'uD04' 'Winapi.Windows'  'CloseHandle'    'Winapi.Windows.CloseHandle'
Ext  'D04d' 'uD04' 'Windows'         'CloseHandle'    'Winapi.Windows.CloseHandle'
Ext  'D04e' 'uD04' 'System'          'Pos'            'System.Pos'
None 'D04f' 'uD04' 'System.SysUtils' 'NoSuchRoutine'
None 'D04g' 'uD04' 'NotUsedUnit'     'HiddenRoutine'

# ---- D03 ----
Ext  'D03a' 'uD03' 'N'  'Free'    'System.TObject.Free'
Ext  'D03b' 'uD03' 'C'  'Free'    'System.TObject.Free'
Ext  'D03c' 'uD03' 'G'  'Free'    'System.TObject.Free'
Ext  'D03d' 'uD03' 'S'  'Free'    'System.TObject.Free'
Ext  'D03e' 'uD03' 'D'  'Free'    'System.TObject.Free'
Ext  'D03f' 'uD03' 'OD' 'Free'    'System.TObject.Free'
Ext  'D03g' 'uD03' 'E'  'ToArray' 'Gen.Coll.TEnumerable.ToArray'
Ext  'D03h' 'uD03' 'L'  'Free'    'System.TObject.Free'
None 'D03i' 'uD03' 'N'  'NoSuchMember'
None 'D03j' 'uD03' 'R'  'Free'
None 'D03k' 'uD03' 'I'  'Free'
None 'D03l' 'uD03' 'B'  'Free'
None 'D03m' 'uD03' 'LU' 'Free'
None 'D03n' 'uD03' 'LR' 'Free'
None 'D03o' 'uD03' 'LI' 'Free'
None 'D03p' 'uD03' 'L2' 'Add'
None 'D03q' 'uD03' 'W'  'Free'
None 'D03r' 'uD03' 'M'  'Free'

# ---- D12 ----
$s = Site 'uProj' 'FVM' 'LoadSettings'
Check "D12a uProj FVM.LoadSettings -> a local edge to uProj.TVm.LoadSettings (got '$($s.Edge)')" ($null -ne $s -and $s.Edge -ceq 'uProj.TVm.LoadSettings')
Ext  'D12b' 'uProj' 'FList' 'Free' 'System.TObject.Free'

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath "C:\TEMP\draglint_recv_undec_$PID") { [IO.Directory]::Delete("C:\TEMP\draglint_recv_undec_$PID", $true) }
}
