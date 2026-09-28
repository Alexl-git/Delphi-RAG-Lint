<#
  run_unit_var_receiver_bind.ps1 -- a call on a VALUE the enclosing class does
  not declare itself is typed through Delphi's scope chain: an ancestor's field,
  then a unit-level var (own unit, then a used unit's interface). And a unit-
  level value spelled like a UNIT shadows the unit for a qualified call.
  Resolver 1.11.0-alpha.

  RB-1 (INBOX-charts-receiver-typed-calls-unbound, charts T5-R4, 2026-09-28).
  `GDatasetsDef.GetTable(...)`, `GBroadcastServer.PushTableChanged(...)`: a
  method call whose receiver is a unit-level `var` of a project class declared
  in ANOTHER unit was a `call` ref with symbol_id NULL and no call_edges row.
  TypeReceiver typed locals/params, the enclosing class's OWN fields and
  properties, casts and type names -- never a unit-level var, and never a field
  inherited from an ancestor. The last identifier rung now asks
  TypeOfOrdinaryName, the scope walk the `with` scope already used: the class
  chain, then exactly ONE visible unit-level var, then the name as a type.

  RB-4 (plan 2026-09-24 section 6). UnshadowedUnitFile gates a unit-qualified
  receiver (`uLib.Go`, rungs 3c/3d/4b) on a nearer value spelled like the unit:
  locals, the class chain, a `with` target -- but not a UNIT-LEVEL var/const.
  A var named like the unit whose TYPE the index cannot see answers TypeId 0,
  exactly what the unit rungs take, so `uLib.Go` bound to the unit's routine
  although the compiler reads the var.

  CASES (markers in the fixture; lines are read from it)
    R1 GDef.EnsureLoaded     cross-unit interface var            -> TDef.EnsureLoaded
    R2 N := GDef.GetTable    same, a function in an expression    -> TDef.GetTable
    R3 LImpl.Ping            own-unit IMPLEMENTATION var          -> TPinger.Ping
    R4 FHelper.Run           a field of the ANCESTOR class        -> THelper.Run
    N1 GDef.EnsureLoaded     a LOCAL GDef of an unindexed type    -> unbound
    N2 GAmb.Ping             two used units export GAmb           -> unbound
    N3 uLib.Go               a unit-level var uLib (unindexed type) shadows unit uLib -> unbound
    C3 uLib.Go               the same call where nothing shadows  -> uLib.Go (4b control)

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_unit_var_receiver_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_unit_var_receiver_$PID"
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

W (Join-Path $WorkDir 'uDef.pas') @'
unit uDef;

interface

type
  TDef = class
  public
    procedure EnsureLoaded;
    function GetTable(const AName: string): Integer;
  end;

  TPingA = class
  public
    procedure Ping;
  end;

var
  GDef: TDef;
  GAmb: TPingA;

implementation

procedure TDef.EnsureLoaded;
begin
end;

function TDef.GetTable(const AName: string): Integer;
begin
  Result := 0;
end;

procedure TPingA.Ping;
begin
end;

end.
'@
W (Join-Path $WorkDir 'uOther.pas') @'
unit uOther;

interface

type
  TPingB = class
  public
    procedure Ping;
  end;

var
  GAmb: TPingB;

implementation

procedure TPingB.Ping;
begin
end;

end.
'@
W (Join-Path $WorkDir 'uLib.pas') @'
unit uLib;

interface

procedure Go;

implementation

procedure Go;
begin
end;

end.
'@
W (Join-Path $WorkDir 'uBase.pas') @'
unit uBase;

interface

type
  THelper = class
  public
    procedure Run;
  end;

  TBase = class
  protected
    FHelper: THelper;
  end;

implementation

procedure THelper.Run;
begin
end;

end.
'@
W (Join-Path $WorkDir 'uUse.pas') @'
unit uUse;

interface

uses uBase;

type
  TPinger = class
  public
    procedure Ping;
  end;

  TChild = class(TBase)
  public
    procedure Work;
  end;

procedure Run;
procedure Shadowed;
procedure Amb;

implementation

uses uDef, uOther, uLib;

var
  LImpl: TPinger;

procedure TPinger.Ping;
begin
end;

procedure TChild.Work;
begin
  FHelper.Run; // R4
end;

procedure Run;
var
  N: Integer;
begin
  GDef.EnsureLoaded; // R1
  N := GDef.GetTable('x'); // R2
  if N > 0 then
    LImpl.Ping; // R3
end;

procedure Shadowed;
var
  GDef: TNotIndexed;
begin
  GDef.EnsureLoaded; // N1
end;

procedure Amb;
begin
  GAmb.Ping; // N2
end;

end.
'@
W (Join-Path $WorkDir 'uShadowUnit.pas') @'
unit uShadowUnit;

interface

procedure CallShadowed;

implementation

uses uLib;

var
  uLib: TNotIndexedEither;

procedure CallShadowed;
begin
  uLib.Go; // N3
end;

end.
'@
W (Join-Path $WorkDir 'uPlainUnit.pas') @'
unit uPlainUnit;

interface

procedure CallPlain;

implementation

uses uLib;

procedure CallPlain;
begin
  uLib.Go; // C3
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uDef in 'uDef.pas',
  uOther in 'uOther.pas',
  uLib in 'uLib.pas',
  uBase in 'uBase.pas',
  uUse in 'uUse.pas',
  uShadowUnit in 'uShadowUnit.pas',
  uPlainUnit in 'uPlainUnit.pas';

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
function LineOfMarker([string]$File, [string]$Marker) {
  $ls = [IO.File]::ReadAllLines((Join-Path $WorkDir $File))
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match ('// ' + [regex]::Escape($Marker) + '$')) { return $i + 1 } }
  return -1
}
# The CALL ref named ANAME on the marker line, with its bound target and edge target.
function CallAt([string]$File, [string]$Marker, [string]$Name) {
  $ln = LineOfMarker $File $Marker
  $q = "SELECT r.id, s.qualified_name AS sq, (SELECT t.qualified_name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS tq " +
       "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
       "WHERE r.kind = 'call' AND r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\$File'"
  return ,(Sql $q)
}

$cases = @(
  @{ M = 'R1'; F = 'uUse.pas';        N = 'EnsureLoaded'; Q = 'uDef.TDef.EnsureLoaded' },
  @{ M = 'R2'; F = 'uUse.pas';        N = 'GetTable';     Q = 'uDef.TDef.GetTable' },
  @{ M = 'R3'; F = 'uUse.pas';        N = 'Ping';         Q = 'uUse.TPinger.Ping' },
  @{ M = 'R4'; F = 'uUse.pas';        N = 'Run';          Q = 'uBase.THelper.Run' },
  @{ M = 'C3'; F = 'uPlainUnit.pas';  N = 'Go';           Q = 'uLib.Go' })
foreach ($c in $cases) {
  $r = CallAt $c.F $c.M $c.N
  Check ("{0}  {1} binds {2} with one call edge" -f $c.M, $c.N, $c.Q) `
    (($r.Count -eq 1) -and ($r[0].tq -eq $c.Q)) ("rows=$($r.Count) sq=$($r[0].sq) tq=$($r[0].tq)")
}
$negs = @(
  @{ M = 'N1'; F = 'uUse.pas';        N = 'EnsureLoaded'; Why = 'a LOCAL GDef of an unindexed type shadows the unit var' },
  @{ M = 'N2'; F = 'uUse.pas';        N = 'Ping';         Why = 'two used units export GAmb -- absence beats a guess' },
  @{ M = 'N3'; F = 'uShadowUnit.pas'; N = 'Go';           Why = 'a unit-level var uLib shadows unit uLib (RB-4)' })
foreach ($c in $negs) {
  $r = CallAt $c.F $c.M $c.N
  Check ("{0}  {1} stays unbound: {2}" -f $c.M, $c.N, $c.Why) `
    (($r.Count -eq 1) -and ($null -eq $r[0].tq) -and ($null -eq $r[0].sq)) ("rows=$($r.Count) sq=$($r[0].sq) tq=$($r[0].tq)")
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_unit_var_receiver_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
