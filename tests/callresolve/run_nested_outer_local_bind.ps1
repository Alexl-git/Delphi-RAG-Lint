<#
  run_nested_outer_local_bind.ps1 -- a nested routine sees its outer routine's
  parameters and var-section locals, and a receiver typed by one binds.

  RECV-UNDECIDABLE slice (1.43, lane recv). LocalInScopeAt read only the routine
  enclosing the site, so `AStore.Find` inside a nested helper was untyped: the largest
  project-typed shape left on the engine (2993 refs, 1076 of them calls). Delphi's
  order: the nested routine's own declarations, then each outer routine's, then the
  class chain and the units.

  An outer var section declared AFTER the nested routine, and an outer inline var (its
  body follows every nested routine), are NOT visible and must not shadow anything.

  CASES (markers in the fixture; lines are read from it)
    R1 A.Bar     outer parameter                         -> TFoo.Bar
    R2 L.Bar     outer var-section local                 -> TFoo.Bar
    R3 A.Bar     two levels of nesting                   -> TFoo.Bar
    R4 A.Ping    the nested routine's own A shadows      -> TOther.Ping
    R5 F.Bar     an outer parameter beats a class field  -> TFoo.Bar
    R6 G.Ping    outer `G` declared after the nested routine: the unit var -> TOther.Ping
    C1 A.Bar     the outer routine's own use, control    -> TFoo.Bar
    N1 K.Bar     an outer inline var                     -> unbound
    N2 Z.Bar     a sibling nested routine's local        -> unbound
    N3 G.Bar     R6's site again: never TFoo.Bar         -> unbound

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_nested_outer_local_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_nested_outer_$PID"
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

W (Join-Path $WorkDir 'uUse.pas') @'
unit uUse;

interface

type
  TFoo = class
  public
    procedure Bar;
  end;

  TOther = class
  public
    procedure Ping;
  end;

  TOwner = class
  public
    F: TOther;
    procedure Work(F: TFoo);
  end;

var
  G: TOther;

procedure Outer(A: TFoo);
procedure Late;
procedure Siblings;
procedure InlineOuter;

implementation

procedure TFoo.Bar; begin end;
procedure TOther.Ping; begin end;

procedure TOwner.Work(F: TFoo);

  procedure Nested;
  begin
    F.Bar; // R5
  end;

begin
  Nested;
end;

procedure Outer(A: TFoo);
var
  L: TFoo;

  procedure Near;
  begin
    A.Bar; // R1
    L.Bar; // R2
  end;

  procedure Mid;

    procedure Deep;
    begin
      A.Bar; // R3
    end;

  begin
    Deep;
  end;

  procedure Shadows;
  var
    A: TOther;
  begin
    A.Ping; // R4
  end;

begin
  A.Bar; // C1
  Near;
  Mid;
  Shadows;
end;

procedure Late;

  procedure Early;
  begin
    G.Ping; // R6
    G.Bar; // N3
  end;

var
  G: TFoo;
begin
  G := nil;
  Early;
end;

procedure Siblings;

  procedure One;
  var
    Z: TFoo;
  begin
    Z := nil;
  end;

  procedure Two;
  begin
    Z.Bar; // N2
  end;

begin
  One;
  Two;
end;

procedure InlineOuter;

  procedure Before;
  begin
    K.Bar; // N1
  end;

begin
  var K: TFoo := nil;
  Before;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
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
function CallAt([string]$Marker, [string]$Name) {
  $ln = LineOfMarker $Marker
  $q = "SELECT r.id, (SELECT t.qualified_name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS tq " +
       "FROM refs r WHERE r.kind = 'call' AND r.name_text = '$Name' AND r.start_line = $ln"
  return ,(Sql $q)
}

$cases = @(
  @{ M = 'C1'; N = 'Bar';  Q = 'uUse.TFoo.Bar' },
  @{ M = 'R1'; N = 'Bar';  Q = 'uUse.TFoo.Bar' },
  @{ M = 'R2'; N = 'Bar';  Q = 'uUse.TFoo.Bar' },
  @{ M = 'R3'; N = 'Bar';  Q = 'uUse.TFoo.Bar' },
  @{ M = 'R4'; N = 'Ping'; Q = 'uUse.TOther.Ping' },
  @{ M = 'R5'; N = 'Bar';  Q = 'uUse.TFoo.Bar' },
  @{ M = 'R6'; N = 'Ping'; Q = 'uUse.TOther.Ping' })
foreach ($c in $cases) {
  $r = CallAt $c.M $c.N
  Check ("{0}  {1} binds {2}" -f $c.M, $c.N, $c.Q) (($r.Count -eq 1) -and ($r[0].tq -eq $c.Q)) ("rows=$($r.Count) tq=$($r[0].tq)")
}
$negs = @(
  @{ M = 'N1'; N = 'Bar'; Why = 'an outer inline var is declared after the nested routine' },
  @{ M = 'N2'; N = 'Bar'; Why = 'a sibling routine''s local is not in scope' },
  @{ M = 'N3'; N = 'Bar'; Why = 'an outer var section after the nested routine is not in scope' })
foreach ($c in $negs) {
  $r = CallAt $c.M $c.N
  Check ("{0}  {1} stays unbound: {2}" -f $c.M, $c.N, $c.Why) (($r.Count -eq 1) -and ($null -eq $r[0].tq)) ("rows=$($r.Count) tq=$($r[0].tq)")
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
