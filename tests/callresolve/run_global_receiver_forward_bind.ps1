<#
  run_global_receiver_forward_bind.ps1 -- member access and calls through a
  unit-level (global) var whose class is FORWARD-declared in its own unit.

  Lane 149-RB1 item 1 (hub-scc P5, docs\superpowers\specs\2026-11-08-hub-scc-phased.md).
  On the Loader2025 index all 1826 refs whose receiver is the hub global
  `frmLoader2019_Main: TfrmLoader2019_Main` were UNRESOLVED although
  receiver_type_text named the class: Loader2019.Main.pas declares
  `TfrmLoader2019_Main = class;` (a forward declaration) before the full class,
  so the type name had TWO class symbols in one unit and ResolveTypeNameToSymbol
  declined it as ambiguous.

  CASES (markers in the fixture; lines are read from it)
    R1 X := GH.F1        spoke, field through the global            -> uHub.TH.F1, member_accesses row
    R2 GH.M              spoke, method call through the global      -> uHub.TH.M, one call edge
    R3 GH.F1 := 1        hub unit itself, same-unit access          -> uHub.TH.F1
    C1 X := GK.F1        control: class WITHOUT a forward decl      -> uHub.TK.F1 (green on the base too)
    N1 X := GU.F1        global of an UNINDEXED type                -> unbound (positive control: no guess)
    N2 X := GD.F1        two FULL declarations of one name (a real ambiguity, not a forward) -> unbound

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_global_receiver_forward_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_global_fwd_$PID"
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

W (Join-Path $WorkDir 'uHub.pas') @'
unit uHub;

interface

type
  TH = class;

  TK = class
  public
    F1: Integer;
  end;

  TH = class
  public
    F1: Integer;
    F2: string;
    procedure M;
  end;

var
  GH: TH;
  GK: TK;
  GU: TNotIndexed;

procedure Touch;

implementation

procedure TH.M;
begin
end;

procedure Touch;
begin
  GH.F1 := 1; // R3
end;

end.
'@
W (Join-Path $WorkDir 'uDupA.pas') @'
unit uDupA;

interface

type
  TD = class
  public
    F1: Integer;
  end;

  TD = class
  public
    F1: Integer;
  end;

var
  GD: TD;

implementation

end.
'@
W (Join-Path $WorkDir 'uSpoke.pas') @'
unit uSpoke;

interface

procedure Run;

implementation

uses uHub, uDupA;

procedure Run;
var
  X: Integer;
begin
  X := GH.F1; // R1
  GH.M; // R2
  X := GK.F1; // C1
  X := GU.F1; // N1
  X := GD.F1; // N2
  if X > 0 then
    Exit;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uHub in 'uHub.pas',
  uDupA in 'uDupA.pas',
  uSpoke in 'uSpoke.pas';

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
# The ref named ANAME (member-access or call) on the marker line: bound symbol,
# member_accesses target and call edge target.
function RefAt([string]$File, [string]$Marker, [string]$Name) {
  $ln = LineOfMarker $File $Marker
  $q = "SELECT r.id, r.kind, s.qualified_name AS sq, " +
       "(SELECT m.qualified_name FROM member_accesses ma JOIN symbols m ON m.id = ma.member_symbol_id WHERE ma.ref_id = r.id) AS mq, " +
       "(SELECT t.qualified_name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS tq " +
       "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
       "WHERE r.kind IN ('member-access','call') AND r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\$File'"
  return ,(Sql $q)
}

$r = RefAt 'uSpoke.pas' 'R1' 'F1'
Check 'R1  spoke X := GH.F1 binds uHub.TH.F1 with a member_accesses row' `
  (($r.Count -eq 1) -and ($r[0].sq -eq 'uHub.TH.F1') -and ($r[0].mq -eq 'uHub.TH.F1')) ("rows=$($r.Count) kind=$($r[0].kind) sq=$($r[0].sq) mq=$($r[0].mq)")
$r = @((RefAt 'uSpoke.pas' 'R2' 'M') | Where-Object { $_.kind -eq 'call' })
Check 'R2  spoke GH.M binds uHub.TH.M with one call edge' `
  (($r.Count -eq 1) -and ($r[0].tq -eq 'uHub.TH.M')) ("rows=$($r.Count) kind=$($r[0].kind) sq=$($r[0].sq) tq=$($r[0].tq)")
$r = RefAt 'uHub.pas' 'R3' 'F1'
Check 'R3  hub unit GH.F1 := 1 binds uHub.TH.F1' `
  (($r.Count -eq 1) -and ($r[0].sq -eq 'uHub.TH.F1')) ("rows=$($r.Count) kind=$($r[0].kind) sq=$($r[0].sq) mq=$($r[0].mq)")
$r = RefAt 'uSpoke.pas' 'C1' 'F1'
Check 'C1  control GK.F1 (no forward decl) binds uHub.TK.F1' `
  (($r.Count -eq 1) -and ($r[0].sq -eq 'uHub.TK.F1')) ("rows=$($r.Count) sq=$($r[0].sq) mq=$($r[0].mq)")
foreach ($n in @(@{ M = 'N1'; Why = 'GU has an unindexed type' }, @{ M = 'N2'; Why = 'TD has two FULL declarations' })) {
  $r = RefAt 'uSpoke.pas' $n.M 'F1'
  Check ("{0}  F1 stays unbound: {1}" -f $n.M, $n.Why) `
    (($r.Count -eq 1) -and ($null -eq $r[0].sq) -and ($null -eq $r[0].mq)) ("rows=$($r.Count) sq=$($r[0].sq) mq=$($r[0].mq)")
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_global_fwd_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
