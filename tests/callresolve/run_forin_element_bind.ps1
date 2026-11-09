<#
  run_forin_element_bind.ps1 -- `for var X in A` types X as A's element type.

  RECV-UNDECIDABLE slice (1.43, lane recv2). A for-var with no written type had an
  empty signature, so every X.Bar stayed untyped. The element type is written in the
  collection's declaration when the collection is a bare identifier of an array type.

  DECIDED: `for var X in Ident do` where Ident is a local, parameter, outer-routine
  local, class-chain field or property, or the one visible unit-level var, and its
  declared type is `array of T`, `array[..] of T`, `TArray<T>` or a named alias of
  those. T must be a plain type name that names the same thing where the collection is
  declared and where the loop is, and that is not a generic parameter on either side.

  ALSO DECIDED (the same proof): `var X := Ident[i]`; a library list -- TList<T> or
  TObjectList<T> under System.Generics.Collections, IList<T> or IReadOnlyList<T> under
  Spring.Collections, no project type of the name; `var X := Y as T`, the cast being the
  last word of the expression; and a collection out of `F(x)`, `A.B(x)`, `A.Field` or
  `A.Prop`, read through `var U :=` or directly in the for-in, for one non-overloaded
  routine and one receiver of a declared non-generic type.

  A wrong receiver is far worse than a missing one, so each N case is a real trap:
  NF1, NF2, NF3 and NF11 bind to a WRONG method if the proof is dropped.

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_forin_element_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_forin_element_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

W (Join-Path $WorkDir 'uDefs.pas') @'
unit uDefs;

interface

type
  TInner = class
  public
    procedure Ping;
  end;

  TFoo = class
  public
    Inner: TInner;
    procedure Bar;
  end;

  TMsgs = TArray<TFoo>;
  TMsgs2 = TMsgs;
  TDynFoo = array of TFoo;
  TStaticFoo = array[0..3] of TFoo;

var
  GItems: TArray<TFoo>;
  GLibVar: TArray<TFoo>;
  GDup: TArray<TFoo>;
  GMeth: TArray<TFoo>;

implementation

procedure TInner.Ping; begin end;
procedure TFoo.Bar; begin end;

end.
'@
W (Join-Path $WorkDir 'uAmb1.pas') @'
unit uAmb1;

interface

uses uDefs;

type
  TAmb = class
  public
    procedure Bar;
  end;

function GDup: TArray<TInner>;

implementation

procedure TAmb.Bar; begin end;
function GDup: TArray<TInner>; begin Result := nil; end;

end.
'@
W (Join-Path $WorkDir 'uAmb2.pas') @'
unit uAmb2;

interface

type
  TAmb = class
  public
    procedure Bar;
  end;

implementation

procedure TAmb.Bar; begin end;

end.
'@
W (Join-Path $WorkDir 'uCells.pas') @'
unit uCells;

interface

type
  TCell = class
  public
    procedure Bar;
  end;

implementation

procedure TCell.Bar; begin end;

end.
'@
W (Join-Path $WorkDir 'uMid.pas') @'
unit uMid;

interface

uses uCells;

type
  TCells = TArray<TCell>;

implementation

end.
'@
W (Join-Path $WorkDir 'uUse.pas') @'
unit uUse;

interface

uses uDefs, uAmb1, uAmb2, uMid;

type
  { This unit's own TCell: a different type from the element of uMid.TCells. }
  TCell = class
  public
    procedure Bar;
  end;

  { Types named like the generic parameters below: the wrong answer has a target. }
  T = class
  public
    procedure Bar;
  end;

  K = class
  public
    procedure Bar;
  end;

  TBox<T> = class
  public
    FItems: TArray<T>;
    procedure Walk;
    procedure WalkOne<K>(const A: TArray<K>);
  end;

  TBoxKid = class(TBox<TFoo>)
  public
    procedure WalkKid;
  end;

  TOwn = class
  public
    FItems: TArray<TFoo>;
    FAmbs: TArray<TAmb>;
    property PItems: TArray<TFoo> read FItems;
    function GMeth: TArray<TInner>;
    procedure Use;
  end;

  TKidOwn = class(TOwn)
  public
    procedure UseKid;
  end;

  TLibKid = class(TLibBase)
  public
    procedure UseLib;
  end;

  TWithOwner = class
  public
    Items: TArray<TInner>;
  end;

implementation

procedure TCell.Bar; begin end;
procedure T.Bar; begin end;
procedure K.Bar; begin end;

procedure TBox<T>.Walk;
begin
  for var X in FItems do
    X.Bar; // NF1
end;

procedure TBox<T>.WalkOne<K>(const A: TArray<K>);
begin
  for var X in A do
    X.Bar; // NF2
end;

procedure TBoxKid.WalkKid;
begin
  for var X in FItems do
    X.Bar; // NF3
end;

function TOwn.GMeth: TArray<TInner>;
begin
  Result := nil;
end;

procedure TOwn.Use;
begin
  for var X in FItems do
    X.Bar; // F6
  for var X in PItems do
    X.Bar; // F14
  for var X in FAmbs do
    X.Bar; // NF10
  for var X in GMeth do
    X.Bar; // NF14
end;

procedure TKidOwn.UseKid;
begin
  for var X in FItems do
    X.Bar; // F7
end;

procedure TLibKid.UseLib;
begin
  for var X in GLibVar do
    X.Bar; // NF12
end;

procedure Locals(const P1: array of TFoo; const P2: TArray<TFoo>; const P3: array of const);
var
  D: TFoo;
  A: TArray<TFoo>;
  M: TMsgs;
  M2: TMsgs2;
  DF: TDynFoo;
  S4: array[0..3] of TFoo;
  ST: TStaticFoo;
  Grid: TArray<TArray<TFoo>>;
  Strs: TArray<string>;
  Lib: TArray<TNotHere>;
  AoA: array of array of TFoo;
  Multi: array[0..1, 0..1] of TFoo;
  Box: TBox<TFoo>;
  Str: string;
  Cells: TCells;
begin
  D.Bar; // C1
  for var X in A do
    X.Bar; // F1
  for var X in P1 do
    X.Bar; // F2
  for var X in P2 do begin
    X.Bar; // F3
  end;
  for var X in M do
    X.Bar; // F4
  for var X in M2 do
    X.Bar; // F4B
  for var X in DF do
    X.Bar; // F4C
  for var X in S4 do
    X.Bar; // F5
  for var X in ST do
    X.Bar; // F5B
  for var Row in Grid do
    for var C in Row do
      C.Bar; // F9
  for var X in A do
    X.Inner.Ping; // F12
  for var X in Strs do
    X.Foo; // F10
  for var X in Lib do
    X.Add; // F11
  for var X in A do
    X.Bar; // F15
  for var X in M do
    X.Inner.Ping; // F15B
  for var X in AoA do
    X.Bar; // NF5
  for var X in Multi do
    X.Bar; // NF6
  for var X in P3 do
    X.Bar; // NF7
  for var X in Box do
    X.Bar; // NF4
  for var X in Str do
    X.Bar; // NF19
  for var X in Cells do
    X.Bar; // NF11
  for var I := 0 to 3 do
    I.Bar; // NF16
  for var X in [D, D] do
    X.Bar; // NF16B
  for var X in A[0] do
    X.Bar; // NF16C
  var U := Locals2(1);
  for var X in U do
    X.Bar; // NF17
end;

procedure Globals;
begin
  for var X in GItems do
    X.Bar; // F8
  for var X in GLibVar do
    X.Bar; // F8B
  for var X in GDup do
    X.Bar; // NF15
end;

procedure Outer;
var
  A: TArray<TFoo>;

  procedure Nest;
  begin
    for var X in A do
      X.Bar; // F13
  end;

begin
  Nest;
end;

procedure SelfRef;
begin
  for var X in X do
    X.Bar; // NF9
end;

procedure WithScope(O: TWithOwner);
var
  Items: TArray<TFoo>;
begin
  with O do
    for var X in Items do
      X.Bar; // NF8
end;

procedure LocalConst;
const
  GItems = 5;
begin
  for var X in GItems do
    X.Bar; // NF13
end;

type
  TRows = class
  public
    FField: TArray<TFoo>;
    property Rows[I: Integer]: TArray<TFoo> read GetRows;
    procedure Use;
  end;

procedure TRows.Use;
begin
  begin
    var X := FField[0];
    X.Bar; // I2
  end;
  begin
    var X := Rows[0];
    X.Bar; // NI1
  end;
end;

procedure Indexed(const P1: array of TFoo; I: Integer);
var
  A: TArray<TFoo>;
  M: TMsgs;
  S4: array[0..3] of TFoo;
  Grid: TArray<TArray<TFoo>>;
  Strs: TArray<string>;
  Lib: TArray<TNotHere>;
  AoA: array of array of TFoo;
  Multi: array[0..1, 0..1] of TFoo;
  Box: TBox<TFoo>;
  Str: string;
begin
  begin
    var X := A[0];
    X.Bar; // I1
  end;
  begin
    var X := A[I + F(I, 2)];
    X.Bar; // I1B
  end;
  begin
    var X := P1[I];
    X.Bar; // I3
  end;
  begin
    var X := M[I];
    X.Inner.Ping; // I4
  end;
  begin
    var X := S4[I];
    X.Bar; // I5
  end;
  begin
    var X := GItems[I];
    X.Bar; // I6
  end;
  begin
    var Row := Grid[I];
    for var C in Row do
      C.Bar; // I7
  end;
  begin
    var X := Strs[I];
    X.Foo; // I8
  end;
  begin
    var X := Lib[I];
    X.Add; // I9
  end;
  begin
    var X := Str[1];
    X.Bar; // NI2
  end;
  begin
    var X := Box[0];
    X.Bar; // NI3
  end;
  begin
    var X := A[0].Inner;
    X.Bar; // NI4
  end;
  begin
    var X := Multi[0, 1];
    X.Bar; // NI5
  end;
  begin
    var X := AoA[0];
    X.Bar; // NI6
  end;
  begin
    var X := A[0]^;
    X.Bar; // NI7
  end;
  begin
    var X := A[0] + 1;
    X.Bar; // NI8
  end;
  begin
    var X := AoA[0][1];
    X.Bar; // NI9
  end;
  begin
    var X := X[0];
    X.Bar; // NI10
  end;
end;

end.
'@
W (Join-Path $WorkDir 'uOwnList.pas') @'
unit uOwnList;

interface

type
  { A project type named like a library list: nothing here is known about it. }
  IReadOnlyList<T> = interface
    function Next: Integer;
  end;

implementation

end.
'@
W (Join-Path $WorkDir 'uDup.pas') @'
unit uDup;

interface

uses uDefs;

function MkDup(I: Integer): TArray<TInner>;

implementation

function MkDup(I: Integer): TArray<TInner>; begin Result := nil; end;

end.
'@
W (Join-Path $WorkDir 'uCellFn.pas') @'
unit uCellFn;

interface

uses uCells;

function MkCellArr(I: Integer): TArray<TCell>;

implementation

function MkCellArr(I: Integer): TArray<TCell>; begin Result := nil; end;

end.
'@
W (Join-Path $WorkDir 'uNoGen.pas') @'
unit uNoGen;

interface

uses uDefs, uLibOther;

procedure NoUses(const L: TList<TFoo>);

implementation

procedure NoUses(const L: TList<TFoo>);
begin
  for var X in L do
    X.Bar; // NL5
end;

end.
'@
W (Join-Path $WorkDir 'uGen.pas') @'
unit uGen;

interface

uses System.Generics.Collections, Spring.Collections, uDefs, uAmb1, uAmb2, uDup, uCellFn, uOwnList;

type
  { This unit's own TCell: a different type from the element of MkCellArr. }
  TCell = class
  public
    procedure Bar;
  end;

  { A type named like the generic parameter below: the wrong answer has a target. }
  T = class
  public
    procedure Bar;
  end;

  TFooList = TList<TFoo>;

  TGenBox<T> = class
  public
    FL: TList<T>;
    function MkT(I: Integer): TArray<T>;
    procedure WalkT(O: TObject);
  end;

  TGenKid = class(TGenBox<TFoo>)
  public
    procedure WalkKid;
  end;

  TGenOwner = class
  public
    FList: TList<TFoo>;
    FArr: TArray<TFoo>;
    property PArr: TArray<TFoo> read FArr;
    function MkArr(I: Integer): TArray<TFoo>;
    function MkList(I: Integer): TList<TFoo>;
    function MkAlias(I: Integer): TMsgs;
    function MkStrs(I: Integer): TArray<string>;
    function MkOver: TArray<TFoo>; overload;
    function MkOver(I: Integer): TArray<TInner>; overload;
    procedure Own;
  end;

  { MkGArr here means something else than the unit routine of the name. }
  TShadow = class
  public
    function MkGArr(I: Integer): TArray<TInner>;
  end;

  TLibHeir = class(TLibBase)
  public
    procedure UseLib;
  end;

function MkGArr(I: Integer): TArray<TFoo>;
function MkDup(I: Integer): TArray<TFoo>;

implementation

procedure TCell.Bar; begin end;
procedure T.Bar; begin end;
function TGenBox<T>.MkT(I: Integer): TArray<T>; begin Result := nil; end;
function TGenOwner.MkArr(I: Integer): TArray<TFoo>; begin Result := nil; end;
function TGenOwner.MkList(I: Integer): TList<TFoo>; begin Result := nil; end;
function TGenOwner.MkAlias(I: Integer): TMsgs; begin Result := nil; end;
function TGenOwner.MkStrs(I: Integer): TArray<string>; begin Result := nil; end;
function TGenOwner.MkOver: TArray<TFoo>; begin Result := nil; end;
function TGenOwner.MkOver(I: Integer): TArray<TInner>; begin Result := nil; end;
function TShadow.MkGArr(I: Integer): TArray<TInner>; begin Result := nil; end;
function MkGArr(I: Integer): TArray<TFoo>; begin Result := nil; end;
function MkDup(I: Integer): TArray<TFoo>; begin Result := nil; end;

procedure TGenBox<T>.WalkT(O: TObject);
begin
  for var X in FL do
    X.Bar; // NL6
  begin
    var X := O as T;
    X.Bar; // NA4
  end;
  for var X in MkT(1) do
    X.Bar; // NR2B
end;

procedure TGenKid.WalkKid;
begin
  for var X in FL do
    X.Bar; // NL7
  for var X in MkT(1) do
    X.Bar; // NR3
end;

procedure TGenOwner.Own;
begin
  begin
    var U := MkArr(1);
    for var X in U do
      X.Bar; // R2
  end;
  for var X in MkArr(1) do
    X.Bar; // R2B
  for var X in FList do
    X.Bar; // L9
end;

procedure TLibHeir.UseLib;
begin
  for var X in MkGArr(1) do
    X.Bar; // NR8
end;

procedure Lists(const L: TList<TFoo>; const OL: TObjectList<TFoo>; const IL: IList<TFoo>;
  const RL: IReadOnlyList<TFoo>; const LL: TList<TList<TFoo>>; const AL: TFooList;
  const D: TDictionary<string, TFoo>; const Q: TQueue<TFoo>; I: Integer);
begin
  for var X in L do
    X.Bar; // L1
  for var X in OL do
    X.Bar; // L2
  for var X in IL do
    X.Bar; // L3
  for var Row in LL do
    for var X in Row do
      X.Bar; // L4
  for var X in AL do
    X.Bar; // L5
  begin
    var X := L[I];
    X.Bar; // L6
  end;
  begin
    var X := OL[I];
    X.Bar; // L7
  end;
  begin
    var X := IL[I];
    X.Bar; // L8
  end;
  for var X in RL do
    X.Bar; // NL1
  for var X in D do
    X.Bar; // NL2
  for var X in Q do
    X.Bar; // NL3
  begin
    var X := D['a'];
    X.Bar; // NL4
  end;
end;

procedure Casts(O, A, B: TObject; const L: TArray<TObject>);
begin
  begin
    var X := O as TFoo;
    X.Bar; // A1
  end;
  begin
    var X := MkGArr(1, 2) as TFoo;
    X.Bar; // A2
  end;
  begin
    var X := (O) as uDefs.TFoo;
    X.Bar; // A3
  end;
  begin
    var X := L[0] as TFoo;
    X.Bar; // A4
  end;
  begin
    var X := A + B as TFoo;
    X.Bar; // NA1
  end;
  begin
    var X := O as TInner as TFoo;
    X.Bar; // NA2
  end;
  begin
    var X := (O as TFoo).Inner;
    X.Bar; // NA3
  end;
  begin
    var X := O as TAmb;
    X.Bar; // NA5
  end;
  begin
    var X := O is TFoo;
    X.Bar; // NA6
  end;
  begin
    var X := not O as TFoo;
    X.Bar; // NA7
  end;
end;

procedure Results(Own: TGenOwner; const Box: TGenBox<TFoo>; const Kid: TGenKid; const Fn: TObject; W: TShadow);
begin
  begin
    var U := MkGArr(1);
    for var X in U do
      X.Bar; // R1
  end;
  begin
    var U := Own.MkArr(1);
    for var X in U do
      X.Bar; // R3
  end;
  for var X in MkGArr(1) do
    X.Bar; // R4
  for var X in Own.MkArr(1) do
    X.Bar; // R5
  begin
    var U := Own.MkList(1);
    for var X in U do
      X.Bar; // R6
    var V := U[0];
    V.Bar; // R6B
  end;
  begin
    var U := Own.MkAlias(1);
    for var X in U do
      X.Bar; // R7
  end;
  for var X in Own.FArr do
    X.Bar; // R8
  for var X in Own.PArr do
    X.Bar; // R9
  begin
    var U := Own.FArr;
    for var X in U do
      X.Bar; // R10
  end;
  for var X in Own.FList do
    X.Bar; // R11
  for var X in Own.MkStrs(1) do
    X.Foo; // R12
  for var X in Own.MkOver(1) do
    X.Bar; // NR1
  for var X in Box.MkT(1) do
    X.Bar; // NR2
  for var X in Kid.MkT(1) do
    X.Bar; // NR3B
  for var X in Kid.FL do
    X.Bar; // NR3C
  for var X in MkDup(1) do
    X.Bar; // NR4
  begin
    var U := MkCellArr(1);
    for var X in U do
      X.Bar; // NR5
  end;
  for var X in MkCellArr(1) do
    X.Bar; // NR5B
  for var X in Fn(1) do
    X.Bar; // NR6
  with W do
    for var X in MkGArr(1) do
      X.Bar; // NR7
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uDefs in 'uDefs.pas',
  uAmb1 in 'uAmb1.pas',
  uAmb2 in 'uAmb2.pas',
  uCells in 'uCells.pas',
  uMid in 'uMid.pas',
  uUse in 'uUse.pas',
  uOwnList in 'uOwnList.pas',
  uDup in 'uDup.pas',
  uCellFn in 'uCellFn.pas',
  uNoGen in 'uNoGen.pas',
  uGen in 'uGen.pas';

begin
end.
'@

$db = Join-Path $WorkDir 'App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Sql([string]$Q) {
  $j = & $Exe sql --db $db --json --limit 1000 --query $Q 2>$null | ConvertFrom-Json
  if ($null -eq $j) { return ,@() }
  $cols = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($row in $j.rows) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
    $out += [pscustomobject]$o
  }
  return ,$out
}
function LineOfMarker([string]$Marker) {
  $script:MarkerUnit = if ($Marker -match '^(L\d|NL\d|A\d|NA\d|R\d|NR\d)') { 'uGen' } else { 'uUse' }
  if ($Marker -eq 'NL5') { $script:MarkerUnit = 'uNoGen' }
  $ls = [IO.File]::ReadAllLines((Join-Path $WorkDir "$($script:MarkerUnit).pas"))
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match ('// ' + [regex]::Escape($Marker) + '$')) { return $i + 1 } }
  throw "no marker $Marker"
}
# The ref named AName on the marker line, with its edge target and receiver type text.
function CallAt([string]$Marker, [string]$Name) {
  $ln = LineOfMarker $Marker
  $q = "SELECT r.id, r.receiver_type_text AS rtt, (SELECT t.qualified_name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS tq " +
       "FROM refs r JOIN files f ON f.id = r.file_id " +
       "WHERE r.kind = 'call' AND r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\$($script:MarkerUnit).pas'"
  return ,(Sql $q)
}
function Binds($Marker, $Name, $Target) {
  $r = CallAt $Marker $Name
  Check ("{0}  {1} binds {2}" -f $Marker, $Name, $Target) `
    (($r.Count -eq 1) -and ($r[0].tq -eq $Target)) ("rows=$($r.Count) tq=$($r[0].tq) rtt=$($r[0].rtt)")
}
function TextOnly($Marker, $Name, $Text, $Why) {
  $r = CallAt $Marker $Name
  Check ("{0}  {1}: no edge, type text {2}: {3}" -f $Marker, $Name, $Text, $Why) `
    (($r.Count -eq 1) -and ($null -eq $r[0].tq) -and ($r[0].rtt -eq $Text)) ("rows=$($r.Count) tq=$($r[0].tq) rtt=$($r[0].rtt)")
}
function Declines($Marker, $Name, $Why) {
  $r = CallAt $Marker $Name
  Check ("{0}  {1} stays unbound: {2}" -f $Marker, $Name, $Why) `
    (($r.Count -eq 1) -and ($null -eq $r[0].tq) -and ([string]$r[0].rtt -eq '')) ("rows=$($r.Count) tq=$($r[0].tq) rtt=$($r[0].rtt)")
}

$Foo = 'uDefs.TFoo.Bar'
$Ping = 'uDefs.TInner.Ping'
Binds 'C1'   'Bar'  $Foo   # the written-type control
Binds 'F1'   'Bar'  $Foo   # local TArray<T>
Binds 'F2'   'Bar'  $Foo   # open array parameter
Binds 'F3'   'Bar'  $Foo   # parameter, begin..end body
Binds 'F4'   'Bar'  $Foo   # alias of TArray<T>
Binds 'F4B'  'Bar'  $Foo   # alias of an alias
Binds 'F4C'  'Bar'  $Foo   # alias of array of T
Binds 'F5'   'Bar'  $Foo   # static array
Binds 'F5B'  'Bar'  $Foo   # alias of a static array
Binds 'F6'   'Bar'  $Foo   # own field
Binds 'F7'   'Bar'  $Foo   # inherited field
Binds 'F8'   'Bar'  $Foo   # the one visible unit var
Binds 'F8B'  'Bar'  $Foo   # the NF12 var from a plain routine: NF12 is not a dead var
Binds 'F9'   'Bar'  $Foo   # TArray<TArray<T>>: the inner loop reads the outer's type
Binds 'F12'  'Ping' $Ping  # a chain through the element type
Binds 'F13'  'Bar'  $Foo   # an outer routine's local
Binds 'F14'  'Bar'  $Foo   # own non-indexed property
Binds 'F15'  'Bar'  $Foo   # sibling loops, each its own X
Binds 'F15B' 'Ping' $Ping
TextOnly 'F10' 'Foo' 'string' 'an element type outside the project'
TextOnly 'F11' 'Add' 'TNotHere' 'an element type outside the project'

Declines 'NF1'  'Bar' 'TArray<T> of the class''s generic T (uUse.T exists)'
Declines 'NF2'  'Bar' 'TArray<K> of the method''s generic K (uUse.K exists)'
Declines 'NF3'  'Bar' 'FItems: TArray<T> inherited from TBox<TFoo>, substitution not modelled'
Declines 'NF4'  'Bar' 'a generic class, not an array'
Declines 'NF5'  'Bar' 'array of array: the element is no plain type name'
Declines 'NF6'  'Bar' 'a multi-dimensional array'
Declines 'NF7'  'Bar' 'array of const'
Declines 'NF8'  'Bar' 'a with target declares the collection''s name'
Declines 'NF9'  'Bar' 'a self reference, which must also terminate'
# NF10 / NA5: two used units declare TAmb; since 1.47 (B5) Delphi's tie-break binds the last-used unit's type.
Binds 'NF10' 'Bar' 'uAmb2.TAmb.Bar'
Declines 'NF11' 'Bar' 'the element name means another type at the loop than at the alias'
Declines 'NF12' 'Bar' 'a library ancestor may declare the name'
Declines 'NF13' 'Bar' 'a local const shadows the unit var'
Declines 'NF14' 'Bar' 'a method of the class shadows the unit var'
Declines 'NF15' 'Bar' 'a used unit declares a routine of the name'
Declines 'NF16' 'Bar' 'for var I := 0 to n is no for-in'
Declines 'NF16B' 'Bar' 'an array constructor is not a bare identifier'
Declines 'NF16C' 'Bar' 'a selector is not a bare identifier'
Declines 'NF17' 'Bar' 'an untyped collection local'
Declines 'NF19' 'Bar' 'a string is no array'

# `var X := A[i]` over the same proof.
Binds 'I1'  'Bar'  $Foo    # a local
Binds 'I1B' 'Bar'  $Foo    # a subscript holding a call and a comma inside its parens
Binds 'I2'  'Bar'  $Foo    # a field
Binds 'I3'  'Bar'  $Foo    # an open array parameter
Binds 'I4'  'Ping' $Ping   # an alias, then a chain
Binds 'I5'  'Bar'  $Foo    # a static array
Binds 'I6'  'Bar'  $Foo    # the one visible unit var
Binds 'I7'  'Bar'  $Foo    # X is itself an array: a for-in over it reads on
TextOnly 'I8' 'Foo' 'string' 'an element type outside the project'
TextOnly 'I9' 'Add' 'TNotHere' 'an element type outside the project'
Declines 'NI1'  'Bar' 'an indexed property: its signature is the ELEMENT''s type, not an array'
Declines 'NI2'  'Bar' 'a string subscript'
Declines 'NI3'  'Bar' 'a default property of a generic class'
Declines 'NI4'  'Bar' 'a member after the subscript'
Declines 'NI5'  'Bar' 'two subscripts in one group'
Declines 'NI6'  'Bar' 'the element is itself array of T'
Declines 'NI7'  'Bar' 'a dereference after the subscript'
Declines 'NI8'  'Bar' 'an operator after the subscript'
Declines 'NI9'  'Bar' 'two subscript groups'
Declines 'NI10' 'Bar' 'a self reference'

# A library list: the name, the one type argument and the unit it comes from.
Binds 'L1'  'Bar'  $Foo    # TList<T>
Binds 'L2'  'Bar'  $Foo    # TObjectList<T>
Binds 'L3'  'Bar'  $Foo    # Spring's IList<T>
Binds 'L4'  'Bar'  $Foo    # TList<TList<T>>: the inner loop reads the outer's type
Binds 'L5'  'Bar'  $Foo    # an alias of TList<T>
Binds 'L6'  'Bar'  $Foo    # L[i] over TList<T>
Binds 'L7'  'Bar'  $Foo    # OL[i] over TObjectList<T>
Binds 'L8'  'Bar'  $Foo    # IL[i] over IList<T>
Binds 'L9'  'Bar'  $Foo    # a field
Declines 'NL1' 'Bar' 'a project type of a library list''s name'
Declines 'NL2' 'Bar' 'a dictionary enumerates pairs'
Declines 'NL3' 'Bar' 'a queue is not modelled'
Declines 'NL4' 'Bar' 'a dictionary subscript is not modelled'
Declines 'NL5' 'Bar' 'TList<T> in a unit that does not use the library unit'
Declines 'NL6' 'Bar' 'TList<T> of the class''s generic T (uGen.T exists)'
Declines 'NL7' 'Bar' 'TList<T> inherited from TGenBox<TFoo>, substitution not modelled'

# `var X := Y as T`: the cast names the type, when it is the whole expression's last word.
Binds 'A1'  'Bar'  $Foo    # an identifier
Binds 'A2'  'Bar'  $Foo    # a call with a comma in its arguments
Binds 'A3'  'Bar'  $Foo    # a parenthesised value, a unit-qualified type
Binds 'A4'  'Bar'  $Foo    # a subscripted value
Declines 'NA1' 'Bar' 'an operator before the cast: `as` binds to its right operand only'
Declines 'NA2' 'Bar' 'two casts'
Declines 'NA3' 'Bar' 'a member after the parenthesised cast'
Declines 'NA4' 'Bar' 'a cast to the class''s generic T (uGen.T exists)'
Binds 'NA5' 'Bar' 'uAmb2.TAmb.Bar'
Declines 'NA6' 'Bar' '`is` is no cast'
Declines 'NA7' 'Bar' 'a `not` before the cast'

# A collection out of a routine, a field or a property, written or read through a local.
Binds 'R1'  'Bar'  $Foo    # var U := F(x), then for-in over U
Binds 'R2'  'Bar'  $Foo    # var U := OwnMethod(x)
Binds 'R2B' 'Bar'  $Foo    # for-in over OwnMethod(x)
Binds 'R3'  'Bar'  $Foo    # var U := A.B(x)
Binds 'R4'  'Bar'  $Foo    # for-in over F(x)
Binds 'R5'  'Bar'  $Foo    # for-in over A.B(x)
Binds 'R6'  'Bar'  $Foo    # a TList<T> result
Binds 'R6B' 'Bar'  $Foo    # and its subscript
Binds 'R7'  'Bar'  $Foo    # a result of an alias type
Binds 'R8'  'Bar'  $Foo    # for-in over A.Field
Binds 'R9'  'Bar'  $Foo    # for-in over A.Property
Binds 'R10' 'Bar'  $Foo    # var U := A.Field
Binds 'R11' 'Bar'  $Foo    # for-in over A.ListField
TextOnly 'R12' 'Foo' 'string' 'an element type outside the project'
Declines 'NR1'  'Bar' 'an overloaded routine: the other overload is another element'
Declines 'NR2'  'Bar' 'TArray<T> of a generic class, substitution not modelled'
Declines 'NR2B' 'Bar' 'a bare call to the same, inside the generic class (uGen.T exists)'
Declines 'NR3'  'Bar' 'inherited from TGenBox<TFoo>, bare'
Declines 'NR3B' 'Bar' 'inherited from TGenBox<TFoo>, through a receiver'
Declines 'NR3C' 'Bar' 'a field inherited from TGenBox<TFoo>, through a receiver'
Declines 'NR4'  'Bar' 'two visible routines of the name'
Declines 'NR5'  'Bar' 'the element name means another type at the local than at the routine'
Declines 'NR5B' 'Bar' 'the same, read directly'
Declines 'NR6'  'Bar' 'a parameter of the name called as a value'
Declines 'NR7'  'Bar' 'a with target declares the routine''s name'
Declines 'NR8'  'Bar' 'a library ancestor may declare the routine''s name'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
