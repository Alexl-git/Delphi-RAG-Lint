<#
  run_with_call_head_bind.ps1 -- a member read or call off a CALL head that the
  with scope supplies: `with H do Names().FLeaf`.

  Lane 149-RB1 item 2a (145 gaps report, W17: "no row (receiver_type_text reads
  `Names`, not a type), so unknown. Safe, but a resolver gap for a bare call head
  through with"). Names is a method of H's class; the receiver `Names()` is a
  call chain whose head only the with scope can type.

  CASES (markers in the fixture; lines are read from it)
    W1 with H do X := Names().FLeaf     -> uW.TLeaf.FLeaf (member_accesses row)
    W2 with H do Names().Make(1)        -> uW.TLeaf.Make, one call edge
    C1 X := H.Names().FLeaf             no with: control                         -> uW.TLeaf.FLeaf
    N1 with U do X := Names().FLeaf     U of an UNINDEXED type: Names may be U's -> unbound (positive control)

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_with_call_head_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_with_call_head_$PID"
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
  TLeaf = class
  public
    FLeaf: Integer;
    procedure Make(A: Integer);
  end;

  THolder = class
  public
    function Names: TLeaf;
  end;

procedure Run(H: THolder; U: TNotIndexed);

implementation

procedure TLeaf.Make(A: Integer);
begin
end;

function THolder.Names: TLeaf;
begin
  Result := nil;
end;

procedure Run(H: THolder; U: TNotIndexed);
var
  X: Integer;
begin
  with H do
    X := Names().FLeaf; // W1
  with H do
    Names().Make(1); // W2
  X := H.Names().FLeaf; // C1
  with U do
    X := Names().FLeaf; // N1
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
function RefAt([string]$Marker, [string]$Kind, [string]$Name) {
  $ln = LineOfMarker 'uW.pas' $Marker
  $q = "SELECT r.id, r.receiver_text AS rt, r.receiver_type_text AS rtt, s.qualified_name AS sq, " +
       "(SELECT t.qualified_name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS tq " +
       "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
       "WHERE r.kind = '$Kind' AND r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\uW.pas'"
  return ,(Sql $q)
}

$r = RefAt 'W1' 'member-access' 'FLeaf'
Check 'W1  with H do Names().FLeaf binds uW.TLeaf.FLeaf' `
  (($r.Count -eq 1) -and ($r[0].sq -eq 'uW.TLeaf.FLeaf')) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) sq=$($r[0].sq)")
$r = RefAt 'W2' 'call' 'Make'
Check 'W2  with H do Names().Make(1) binds uW.TLeaf.Make with a call edge' `
  (($r.Count -eq 1) -and ($r[0].tq -eq 'uW.TLeaf.Make')) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) tq=$($r[0].tq)")
$r = RefAt 'C1' 'member-access' 'FLeaf'
Check 'C1  H.Names().FLeaf (no with) binds uW.TLeaf.FLeaf' `
  (($r.Count -eq 1) -and ($r[0].sq -eq 'uW.TLeaf.FLeaf')) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) sq=$($r[0].sq)")
$r = RefAt 'N1' 'member-access' 'FLeaf'
Check 'N1  with U (unindexed) do Names().FLeaf stays unbound' `
  (($r.Count -eq 1) -and ($null -eq $r[0].sq)) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) sq=$($r[0].sq)")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_with_call_head_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
