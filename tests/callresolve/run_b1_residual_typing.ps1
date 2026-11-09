<#
  run_b1_residual_typing.ps1 -- receiver typing residuals from lane 146 b1
  (lane 149-RB1 item 6): a receiver in a PROGRAM's main block, and `inherited`
  inside a class helper.

  146 b1 REPORT, residual gaps: "a receiver in a .dpr main block has no static
  type: enclosing_symbol_id is 0, so TypeReceiverCore exits. COne.Alpha in
  NrProg.dpr refused [receiver-untyped]"; "inherited inside a class helper is
  not modelled separately".

  CASES (markers in the fixture; lines are read from it)
    P1 X := COne.Alpha      .dpr main block, program-level typed const   -> uP.TPoint2.Alpha (150-RS2 (4))
    P2 GRun.Go              .dpr main block, program-level var           -> uP.TRun.Go (150-RS2 (4))
    P3 X := GLib.Alpha      .dpr main block, a used unit's interface var -> uP.TPoint2.Alpha
    H1 inherited Go         class helper for TRun                        -> uP.TRun.Go (the helped type's method)
    N1 Application.Run      .dpr main block, nothing in the project names it -> unbound (oracle head, as before)

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_b1_residual_typing.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_b1_residual_$PID"
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

W (Join-Path $WorkDir 'uP.pas') @'
unit uP;

interface

type
  TPoint2 = record
    Alpha: Integer;
  end;

  TRun = class
  public
    procedure Go;
  end;

  TRunHelper = class helper for TRun
  public
    procedure Go;
  end;

var
  GLib: TPoint2;

implementation

procedure TRun.Go;
begin
end;

procedure TRunHelper.Go;
begin
  inherited Go; // H1
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uP in 'uP.pas';

const
  COne: TPoint2 = (Alpha: 1);

var
  GRun: TRun;
  X: Integer;

begin
  X := COne.Alpha; // P1
  GRun.Go; // P2
  X := GLib.Alpha; // P3
  Application.Run; // N1
  if X > 0 then
    Exit;
end.
'@

$db = Join-Path $WorkDir 'App.sqlite'
$idxOut = & $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-String
Check 'V the fixture index was built' (Test-Path $db) $db
# found-in-150 (RS2): COne's typed-const initializer `(Alpha: 1)` binds a record-field ref through rung 3c
# (ValueOnly). The store counted it as an enum value (Shape B) the resolver never counted -> a false
# 'enum-values: WARNING ... INCOMPLETE' on every index holding a typed record const.
$ev = @($idxOut -split "`r?`n" | Where-Object { $_ -match 'enum-values' })
Check 'W1  the enum-values reconciliation agrees (a record-field initializer is not an enum value)' ((@($ev | Where-Object { $_ -match 'WARNING' }).Count -eq 0) -and (@($ev | Where-Object { $_ -match 'resolver and store agree' }).Count -eq 1)) ($ev -join ' | ')

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
function RefAt([string]$File, [string]$Marker, [string]$Kind, [string]$Name) {
  $ln = LineOfMarker $File $Marker
  $q = "SELECT r.id, r.receiver_text AS rt, r.receiver_type_text AS rtt, s.qualified_name AS sq, " +
       "(SELECT t.qualified_name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS tq " +
       "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
       "WHERE r.kind = '$Kind' AND r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\$File'"
  return ,(Sql $q)
}

$r = RefAt 'App.dpr' 'P1' 'member-access' 'Alpha'
Check 'P1  .dpr COne.Alpha (program-level typed const) binds uP.TPoint2.Alpha (150-RS2 (4): GetUnitLevelValueDecls admits program-level values)' `
  (($r.Count -eq 1) -and ($r[0].sq -eq 'uP.TPoint2.Alpha')) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) sq=$($r[0].sq)")
$r = RefAt 'App.dpr' 'P2' 'call' 'Go'
Check 'P2  .dpr GRun.Go (program-level var) binds uP.TRun.Go (150-RS2 (4))' `
  (($r.Count -eq 1) -and ($r[0].tq -eq 'uP.TRun.Go')) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) tq=$($r[0].tq)")
$r = RefAt 'App.dpr' 'P3' 'member-access' 'Alpha'
Check 'P3  .dpr GLib.Alpha (used unit var) binds uP.TPoint2.Alpha' `
  (($r.Count -eq 1) -and ($r[0].sq -eq 'uP.TPoint2.Alpha')) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) sq=$($r[0].sq)")
$r = RefAt 'uP.pas' 'H1' 'call' 'Go'
Check 'H1  inherited Go in a class helper binds the helped uP.TRun.Go' `
  (($r.Count -eq 1) -and ($r[0].tq -eq 'uP.TRun.Go')) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) tq=$($r[0].tq)")
$r = RefAt 'App.dpr' 'N1' 'call' 'Run'
Check 'N1  .dpr Application.Run stays unbound in the project' `
  (($r.Count -eq 1) -and ($null -eq $r[0].tq) -and ($null -eq $r[0].sq)) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) tq=$($r[0].tq)")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (-not $env:RB1_KEEP) { foreach ($d23 in @("C:\TEMP\draglint_b1_residual_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } } }
}
