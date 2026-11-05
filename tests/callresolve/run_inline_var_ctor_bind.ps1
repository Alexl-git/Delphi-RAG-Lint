<#
  run_inline_var_ctor_bind.ps1 -- `var X := TFoo.Create` types X as TFoo.

  INLINE-VAR-CTOR-UNTYPED (1.43, lane recv). An inline var with no written type
  has an empty symbols.signature, so TypeReceiver answered 0 for every X.Bar: the
  largest single source of opaque-to-analysis on the engine. The resolver now reads
  the initializer of such a local and, for the one shape it can decide, behaves
  exactly as if `var X: TFoo` had been written.

  DECIDED: <type>[<generic args>].<name>[(args)] where <type> names no value in
  scope, and <name> is a constructor on the type's chain, the one class function of
  the name (its declared return type), or `Create` that the chain does not declare
  (TObject's, or a library ancestor's).

  An unresolved receiver is better than a wrong one, so each N case is a real trap.

  CASES (markers in the fixture; lines are read from it)
    R1 X.Bar            TFoo.Create;                 -> TFoo.Bar
    R2 X.Bar            TFoo.Create(1, 'a;b');       -> TFoo.Bar (a `;` in a string)
    R3 X.Bar            TKid.Create (declared nowhere in the chain) -> TKid.Bar
    R4 X.Bar            TFoo.Make('a') named ctor    -> TFoo.Bar
    R5 X.Inner.Ping     chain through the inferred type -> TInner.Ping
    R6 X.Bar            uDefs.TFoo.Create unit-qualified -> TFoo.Bar
    R7 X.Put            TBox<Integer>.Create         -> TBox.Put
    R8 X.Ping           TFac.Create class function   -> TInner.Ping (its return type)
    R9 X.Bar            initializer over three lines -> TFoo.Bar
    R10 X.Bar / X.Ping  two sibling blocks, each its own X -> each own type
    R11 X.Add           TNotHere.Create, no project type -> no edge, type text TNotHere
    N1 X.Bar            TAmb.Create, two used units declare TAmb -> unbound
    N2 X.Bar            TFoo.Create as IThing: the cast's type, never the chain's -> no edge, type text IThing
    N3 X.Bar            F(TFoo.Create) (a call around it) -> unbound
    N4 X.Bar            for var X in ...              -> unbound
    N5 X.Bar            var X := X.Create (self reference) -> unbound
    N6 X.Bar            TFoo is a LOCAL value here    -> unbound
    N7 X.Bar            TFac.Other (no such member)   -> unbound
    N8 X.Add            FList.Create, not a type name -> no edge, no type text
    C1 D.Bar            `var D: TFoo` control         -> TFoo.Bar

  FUNCTION RESULTS (RECV-UNDECIDABLE slice): an initializer ending in a call is typed
  by the receiver ladder, when that names a type of this index the local's own file
  resolves to the same symbol.
    S1 X.Bar            GetFoo(1)                     -> TFoo.Bar
    S2 X.Ping           D.Mk('a') (a method)          -> TInner.Ping
    S3 X.Bar            TFoo(D) (a cast)              -> TFoo.Bar
    S4 Y.Ping           X := GetFoo(1); Y := X.Mk('a') -> TInner.Ping
    N9  X.Bar           Over(1), overloads disagree   -> unbound
    N10 X.Mk            X := X.Mk('a') self reference -> unbound, and it ends
    N11 X.Bar           Box.Get(0), returns the generic T -> unbound
    N12 X.Bar           NoRet(1), a procedure         -> unbound
    N13 X.Bar           MkAmb(1), TAmb is ambiguous at the local -> unbound
    N14 X.Bar           GetFoo(1) where a LOCAL GetFoo shadows the routine -> unbound

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_inline_var_ctor_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_inline_var_ctor_$PID"
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
    constructor Create; overload;
    constructor Create(N: Integer; const S: string); overload;
    constructor Make(const S: string);
    function Mk(const S: string): TInner;
    procedure Bar;
  end;

  TBase = class
  public
    procedure Base;
  end;

  TKid = class(TBase)
  public
    procedure Bar;
  end;

  TBox<T> = class
  public
    procedure Put;
    function Get(I: Integer): T;
  end;

  TFac = class
  public
    class function Create: TInner;
    procedure Bar;
  end;

function F(O: TObject): TObject;
function GetFoo(N: Integer): TFoo;
function Over(N: Integer): TFoo; overload;
function Over(const S: string): TInner; overload;
procedure NoRet(N: Integer);

implementation

procedure TInner.Ping; begin end;
constructor TFoo.Create; begin end;
constructor TFoo.Create(N: Integer; const S: string); begin end;
constructor TFoo.Make(const S: string); begin end;
procedure TFoo.Bar; begin end;
procedure TBase.Base; begin end;
procedure TKid.Bar; begin end;
procedure TBox<T>.Put; begin end;
class function TFac.Create: TInner; begin Result := nil; end;
procedure TFac.Bar; begin end;
function F(O: TObject): TObject; begin Result := O; end;
function GetFoo(N: Integer): TFoo; begin Result := nil; end;
function Over(N: Integer): TFoo; begin Result := nil; end;
function Over(const S: string): TInner; begin Result := nil; end;
procedure NoRet(N: Integer); begin end;
function TFoo.Mk(const S: string): TInner; begin Result := nil; end;
function TBox<T>.Get(I: Integer): T; begin end;

end.
'@
W (Join-Path $WorkDir 'uAmb1.pas') @'
unit uAmb1;

interface

type
  TAmb = class
  public
    procedure Bar;
  end;

function MkAmb(N: Integer): TAmb;

implementation

procedure TAmb.Bar; begin end;
function MkAmb(N: Integer): TAmb; begin Result := nil; end;

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
W (Join-Path $WorkDir 'uUse.pas') @'
unit uUse;

interface

uses uDefs, uAmb1, uAmb2;

type
  TOwner = class
  public
    FList: TObject;
    procedure FieldHead;
  end;

procedure Run;
procedure Traps;
procedure Results;
procedure Shadow;

implementation

procedure TOwner.FieldHead;
begin
  var L := GList.Create;
  L.Add(1); // N8
end;

procedure Run;
var
  D: TFoo;
begin
  D := nil;
  D.Bar; // C1
  begin
    var X := TFoo.Create;
    X.Bar; // R1
  end;
  begin
    var X := TFoo.Create(1, 'a;b');
    X.Bar; // R2
  end;
  begin
    var X := TKid.Create;
    X.Bar; // R3
  end;
  begin
    var X := TFoo.Make('a');
    X.Bar; // R4
  end;
  begin
    var X := TFoo.Create;
    X.Inner.Ping; // R5
  end;
  begin
    var X := uDefs.TFoo.Create;
    X.Bar; // R6
  end;
  begin
    var X := TBox<Integer>.Create;
    X.Put; // R7
  end;
  begin
    var X := TFac.Create;
    X.Ping; // R8
    X.Bar; // R8N
  end;
  begin
    var X :=
      TFoo.
        Create;
    X.Bar; // R9
  end;
  begin
    var X := TKid.Create;
    X.Base; // R10
  end;
  begin
    var X := TNotHere.Create;
    X.Add; // R11
  end;
end;

procedure Traps;
begin
  begin
    var X := TAmb.Create;
    X.Bar; // N1
  end;
  begin
    var X := TFoo.Create as IThing;
    X.Bar; // N2
  end;
  begin
    var X := F(TFoo.Create);
    X.Bar; // N3
  end;
  for var X in GItems do
    X.Bar; // N4
  begin
    var Y := Y.Create;
    Y.Bar; // N5
  end;
  begin
    var TKid := GKid;
    var X := TKid.Create;
    X.Bar; // N6
  end;
  begin
    var X := TFac.Other;
    X.Bar; // N7
  end;
end;

procedure Results;
var
  D: TFoo;
  Box: TBox<TFoo>;
begin
  D := nil;
  Box := nil;
  begin
    var X := GetFoo(1);
    X.Bar; // S1
  end;
  begin
    var X := D.Mk('a');
    X.Ping; // S2
  end;
  begin
    var X := TFoo(D);
    X.Bar; // S3
  end;
  begin
    var X := GetFoo(1);
    var Y := X.Mk('a');
    Y.Ping; // S4
  end;
  begin
    var X := Over(1);
    X.Bar; // N9
  end;
  begin
    var X := X.Mk('a');
    X.Mk('b'); // N10
  end;
  begin
    var X := Box.Get(0);
    X.Bar; // N11
  end;
  begin
    var X := NoRet(1);
    X.Bar; // N12
  end;
  begin
    var X := MkAmb(1);
    X.Bar; // N13
  end;
end;

procedure Shadow;
var
  GetFoo: TFn;
begin
  var X := GetFoo(1);
  X.Bar; // N14
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uDefs in 'uDefs.pas',
  uAmb1 in 'uAmb1.pas',
  uAmb2 in 'uAmb2.pas',
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
# The CALL ref named AName on the marker line, with its edge target and receiver type text.
function CallAt([string]$Marker, [string]$Name) {
  $ln = LineOfMarker $Marker
  $q = "SELECT r.id, r.receiver_type_text AS rtt, (SELECT t.qualified_name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS tq " +
       "FROM refs r JOIN files f ON f.id = r.file_id " +
       "WHERE r.kind = 'call' AND r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\uUse.pas'"
  return ,(Sql $q)
}

$cases = @(
  @{ M = 'C1';  N = 'Bar';  Q = 'uDefs.TFoo.Bar' },
  @{ M = 'R1';  N = 'Bar';  Q = 'uDefs.TFoo.Bar' },
  @{ M = 'R2';  N = 'Bar';  Q = 'uDefs.TFoo.Bar' },
  @{ M = 'R3';  N = 'Bar';  Q = 'uDefs.TKid.Bar' },
  @{ M = 'R4';  N = 'Bar';  Q = 'uDefs.TFoo.Bar' },
  @{ M = 'R5';  N = 'Ping'; Q = 'uDefs.TInner.Ping' },
  @{ M = 'R6';  N = 'Bar';  Q = 'uDefs.TFoo.Bar' },
  @{ M = 'R7';  N = 'Put';  Q = 'uDefs.TBox.Put' },
  @{ M = 'R8';  N = 'Ping'; Q = 'uDefs.TInner.Ping' },
  @{ M = 'R9';  N = 'Bar';  Q = 'uDefs.TFoo.Bar' },
  @{ M = 'R10'; N = 'Base'; Q = 'uDefs.TBase.Base' },
  @{ M = 'S1';  N = 'Bar';  Q = 'uDefs.TFoo.Bar' },
  @{ M = 'S2';  N = 'Ping'; Q = 'uDefs.TInner.Ping' },
  @{ M = 'S3';  N = 'Bar';  Q = 'uDefs.TFoo.Bar' },
  @{ M = 'S4';  N = 'Ping'; Q = 'uDefs.TInner.Ping' })
foreach ($c in $cases) {
  $r = CallAt $c.M $c.N
  Check ("{0}  {1} binds {2}" -f $c.M, $c.N, $c.Q) `
    (($r.Count -eq 1) -and ($r[0].tq -eq $c.Q)) ("rows=$($r.Count) tq=$($r[0].tq)")
}
$r = CallAt 'N2' 'Bar'
Check 'N2 a cast after the chain types X as the cast, not as the chain (1.43 recv2): no edge to TFoo.Bar' `
  (($r.Count -eq 1) -and ($null -eq $r[0].tq) -and ($r[0].rtt -eq 'IThing')) ("rows=$($r.Count) tq=$($r[0].tq) rtt=$($r[0].rtt)")
$r = CallAt 'R11' 'Add'
Check 'R11 a type the project does not declare: no edge, its NAME is recorded' `
  (($r.Count -eq 1) -and ($null -eq $r[0].tq) -and ($r[0].rtt -eq 'TNotHere')) ("rows=$($r.Count) tq=$($r[0].tq) rtt=$($r[0].rtt)")

$r = CallAt 'R8N' 'Bar'
Check 'R8N TFac.Create is a class FUNCTION: X is a TInner, never a TFac' `
  (($r.Count -eq 1) -and ($null -eq $r[0].tq) -and ($r[0].rtt -eq 'TInner')) ("rows=$($r.Count) tq=$($r[0].tq) rtt=$($r[0].rtt)")

$negs = @(
  @{ M = 'N1';  N = 'Bar'; Why = 'two used units declare TAmb -- absence beats a guess' },
  @{ M = 'N3';  N = 'Bar'; Why = 'a call around the constructor' },
  @{ M = 'N4';  N = 'Bar'; Why = 'a for-in var is the element type, not an initializer' },
  @{ M = 'N5';  N = 'Bar'; Why = 'a self reference is not a type' },
  @{ M = 'N6';  N = 'Bar'; Why = 'a local value shadows the type of the name' },
  @{ M = 'N7';  N = 'Bar'; Why = 'a member the chain does not declare' },
  @{ M = 'N8';  N = 'Add'; Why = 'an unknown head that does not read as a type name' },
  @{ M = 'N9';  N = 'Bar'; Why = 'overloads that disagree on the return type' },
  @{ M = 'N10'; N = 'Mk';  Why = 'a self reference, which must also terminate' },
  @{ M = 'N11'; N = 'Bar'; Why = 'a generic parameter is not a type name' },
  @{ M = 'N12'; N = 'Bar'; Why = 'a procedure yields nothing' },
  @{ M = 'N13'; N = 'Bar'; Why = 'the return type is ambiguous where the local reads it' },
  @{ M = 'N14'; N = 'Bar'; Why = 'a local value shadows the routine of the name' })
foreach ($c in $negs) {
  $r = CallAt $c.M $c.N
  Check ("{0}  {1} stays unbound: {2}" -f $c.M, $c.N, $c.Why) `
    (($r.Count -eq 1) -and ($null -eq $r[0].tq) -and ([string]$r[0].rtt -eq '')) ("rows=$($r.Count) tq=$($r[0].tq) rtt=$($r[0].rtt)")
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
