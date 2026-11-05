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
  uUse in 'uUse.pas';

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
  $ls = [IO.File]::ReadAllLines((Join-Path $WorkDir 'uUse.pas'))
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match ('// ' + [regex]::Escape($Marker) + '$')) { return $i + 1 } }
  throw "no marker $Marker"
}
# The ref named AName on the marker line, with its edge target and receiver type text.
function CallAt([string]$Marker, [string]$Name) {
  $ln = LineOfMarker $Marker
  $q = "SELECT r.id, r.receiver_type_text AS rtt, (SELECT t.qualified_name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS tq " +
       "FROM refs r JOIN files f ON f.id = r.file_id " +
       "WHERE r.kind = 'call' AND r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\uUse.pas'"
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
Declines 'NF10' 'Bar' 'the element name is ambiguous'
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

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
