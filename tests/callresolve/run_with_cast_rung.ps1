<#
  run_with_cast_rung.ps1 -- the cast rung of RefStaticType (an UNBOUND call ref
  spelled like a type -> ref_types via 'cast') asks the with scope first.

  Lane 149-RB1 item 2b (145 gaps report, "CallResolver 9834 cast rung does not
  consult WithScopeAt, so the row is wrong-able"). Inside `with U do TBox(1)`
  where U's type is NOT indexed, TBox may be a member of U (a method call) as
  well as a cast to the type TBox: the compiler reads U's member first. The
  rung wrote `cast` regardless, and RefStaticTypeAt / the TRefTypeScan rules
  trust that row.

  CASES (markers in the fixture; lines are read from it)
    W1 with U do X := TBox(1)        U untypable: with scope UNDECIDED -> no ref_types row
    C1 X := TBox(O).V                no with: a real cast               -> ref_types via cast TBox (positive control)
    C2 with H do X := TBox(O).V      H typed, no member TBox: verdict none -> via cast (with scope does not hide it)

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_with_cast_rung.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_with_cast_$PID"
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

W (Join-Path $WorkDir 'uW.pas') @'
unit uW;

interface

type
  TBox = class
  public
    V: Integer;
  end;

  THost = class
  public
    N: Integer;
  end;

procedure Run(H: THost; U: TNotIndexed; O: TObject);

implementation

procedure Run(H: THost; U: TNotIndexed; O: TObject);
var
  X: Integer;
begin
  with U do
    X := TBox(1); // W1
  X := TBox(O).V; // C1
  with H do
    X := TBox(O).V; // C2
  if X > 0 then
    Exit;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uW in 'uW.pas';

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
# The CALL ref TBox on the marker line with its ref_types row (via, type_qname) if any.
function CastAt([string]$Marker) {
  $ln = LineOfMarker 'uW.pas' $Marker
  $q = "SELECT r.id, r.symbol_id AS sid, t.via, t.type_qname AS tq FROM refs r JOIN files f ON f.id = r.file_id " +
       "LEFT JOIN ref_types t ON t.ref_id = r.id " +
       "WHERE r.kind = 'call' AND r.name_text = 'TBox' AND r.start_line = $ln AND f.path LIKE '%\uW.pas'"
  return ,(Sql $q)
}

$r = CastAt 'W1'
Check 'W1  with U (untypable) do TBox(1): no cast row -- TBox may be a member of U' `
  (($r.Count -eq 1) -and ($null -eq $r[0].via)) ("rows=$($r.Count) sid=$($r[0].sid) via=$($r[0].via) tq=$($r[0].tq)")
$r = CastAt 'C1'
Check 'C1  TBox(O).V outside any with: ref_types via cast uW.TBox (positive control)' `
  (($r.Count -eq 1) -and ($r[0].via -eq 'cast') -and ($r[0].tq -eq 'uW.TBox')) ("rows=$($r.Count) sid=$($r[0].sid) via=$($r[0].via) tq=$($r[0].tq)")
$r = CastAt 'C2'
Check 'C2  with H (typed, no member TBox) do TBox(O).V: still via cast uW.TBox' `
  (($r.Count -eq 1) -and ($r[0].via -eq 'cast') -and ($r[0].tq -eq 'uW.TBox')) ("rows=$($r.Count) sid=$($r[0].sid) via=$($r[0].via) tq=$($r[0].tq)")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_with_cast_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
