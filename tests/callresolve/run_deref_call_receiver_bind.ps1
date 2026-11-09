<#
  run_deref_call_receiver_bind.ps1 -- a member read through a postfix
  dereference of a CALL or a HARD CAST receiver is typed and bound.

  Wave 150 RS1 item (1) (149 EX1 "150 row": EX1 wrote the member-access refs
  for `F()^.M`, `G(1, 2)^.N`, `PRec(P)^.K`; their symbol_id stayed NULL --
  the receiver text `F()^` / `PRec(P)^` was not typed by TypeReceiver).

  CASES (markers in the fixture; lines are read from it)
    D1 X := F()^.M          function result PRec, deref -> TRec.M
    D2 X := G(1, 2)^.N      function with args, deref    -> TRec.N
    D3 X := PRec(P)^.K      hard cast to a pointer type  -> TRec.K
    C1 X := F().L           no deref (implicit)          -> TRec.L (positive control, bound on the base)
    N1 X := Q()^.M          Q returns Pointer (untyped)  -> stays UNBOUND (negative control)

  RED on 1.49.0-alpha (150 base): D1-D3 unbound. POSITIVE CONTROL: C1 bound.
  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_deref_call_receiver_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_deref_bind_$PID"
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

W (Join-Path $WorkDir 'uD.pas') @'
unit uD;

interface

type
  PRec = ^TRec;
  TRec = record
    M: Integer;
    N: Integer;
    K: Integer;
    L: Integer;
  end;

function F: PRec;
function G(A, B: Integer): PRec;
function Q: Pointer;
procedure Run(P: Pointer);

implementation

var
  R: TRec;

function F: PRec;
begin
  Result := @R;
end;

function G(A, B: Integer): PRec;
begin
  Result := @R;
end;

function Q: Pointer;
begin
  Result := @R;
end;

procedure Run(P: Pointer);
var
  X: Integer;
begin
  X := F()^.M; // D1
  X := G(1, 2)^.N; // D2
  X := PRec(P)^.K; // D3
  X := F().L; // C1
  X := Q()^.M; // N1
  if X > 0 then
    Exit;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uD in 'uD.pas';

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
# The ref named AName on the marker line with the qualified name of its bound symbol (if any).
function RefAt([string]$Marker, [string]$AName) {
  $ln = LineOfMarker 'uD.pas' $Marker
  $q = "SELECT r.id, r.kind, r.symbol_id AS sid, s.qualified_name AS qn, r.receiver_type_text AS rt FROM refs r JOIN files f ON f.id = r.file_id " +
       "LEFT JOIN symbols s ON s.id = r.symbol_id " +
       "WHERE r.name_text = '$AName' AND r.start_line = $ln AND f.path LIKE '%\uD.pas'"
  return ,(Sql $q)
}
function Bound([string]$Marker, [string]$AName, [string]$Qn) {
  $r = RefAt $Marker $AName
  $ok = ($r.Count -ge 1) -and (@($r | Where-Object { $_.qn -eq $Qn }).Count -ge 1)
  return @($ok, ("rows=$($r.Count) " + (($r | ForEach-Object { "[$($_.kind) sid=$($_.sid) qn=$($_.qn) rt=$($_.rt)]" }) -join ' ')))
}

$b = Bound 'C1' 'L' 'uD.TRec.L'
Check 'C1  F().L (implicit deref): bound to uD.TRec.L (positive control)' $b[0] $b[1]
$b = Bound 'D1' 'M' 'uD.TRec.M'
Check 'D1  F()^.M: bound to uD.TRec.M' $b[0] $b[1]
$b = Bound 'D2' 'N' 'uD.TRec.N'
Check 'D2  G(1, 2)^.N: bound to uD.TRec.N' $b[0] $b[1]
$b = Bound 'D3' 'K' 'uD.TRec.K'
Check 'D3  PRec(P)^.K: bound to uD.TRec.K' $b[0] $b[1]
$r = RefAt 'N1' 'M'
Check 'N1  Q()^.M (Q: Pointer): stays unbound (negative control)' `
  (($r.Count -ge 1) -and (@($r | Where-Object { $null -ne $_.sid }).Count -eq 0)) ("rows=$($r.Count) " + (($r | ForEach-Object { "[sid=$($_.sid) qn=$($_.qn)]" }) -join ' '))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_deref_bind_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
