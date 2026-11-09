<#
  run_ref_receivers_call_chain.ps1 -- 150-RS2 (1) / 149 RB1 2c: ref_receivers for a
  CALL-CHAIN receiver whose call head is DOTTED.

  Storage TSQLiteSymbolStore.ResolveRefReceivers links a ref to the ref that is its
  receiver by position. A receiver text ending in ')' was looked up by the START of
  the whole text, which is the call ref's own start only for a BARE head
  (`MakeB().Count`); `A.GetB(1).Count` starts at `A`, so the GetB call ref was never
  offered and no row was written. Nested argument parens (`GetB(F(3))`) also cut the
  head at the FIRST '('.

  CASES (markers in uUse.pas; lines are read from the fixture)
    C1 A.GetB(1).Count             -> receiver ref = the GetB call on that line
    C2 MakeA().GetB(2).Count       -> GetB (two calls in the chain)
    C3 A.GetB(Twice(3)).Count      -> GetB (nested call in the arguments)
    B1 MakeB().Count               -> MakeB  (bare head; green on the base = positive control of the query)
    N1 A.GetB(4)                   -> the GetB ref's own receiver is A (plain dotted, unchanged)

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_ref_receivers_call_chain.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_rr_chain_$PID"
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
  TB = class
  public
    function Count: Integer;
  end;

  TA = class
  public
    function GetB(X: Integer): TB;
  end;

function MakeA: TA;
function MakeB: TB;
function Twice(X: Integer): Integer;

implementation

function TB.Count: Integer;
begin
  Result:= 1;
end;

function TA.GetB(X: Integer): TB;
begin
  Result:= nil;
end;

function MakeA: TA;
begin
  Result:= nil;
end;

function MakeB: TB;
begin
  Result:= nil;
end;

function Twice(X: Integer): Integer;
begin
  Result:= X * 2;
end;

procedure Work(A: TA);
var
  N: Integer;
begin
  N:= A.GetB(1).Count; // C1
  N:= MakeA().GetB(2).Count; // C2
  N:= A.GetB(Twice(3)).Count; // C3
  N:= MakeB().Count; // B1
  A.GetB(4); // N1
  if N > 0 then
    Exit;
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
  return -1
}
function ReceiverOf([string]$Marker, [string]$Name) {
  $ln = LineOfMarker $Marker
  return ,(Sql ("SELECT r.id, r.receiver_text AS rt, v.name_text AS vn, v.start_col AS vc FROM refs r " +
                "JOIN files f ON f.id = r.file_id LEFT JOIN ref_receivers rr ON rr.ref_id = r.id " +
                "LEFT JOIN refs v ON v.id = rr.receiver_ref_id " +
                "WHERE r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\uUse.pas' " +
                "AND r.kind IN ('call','member-access','read','write') ORDER BY r.kind"))
}
function Has($rows, [string]$Want) { return (@($rows | Where-Object { $_.vn -eq $Want }).Count -ge 1) }
function D($rows) { return (($rows | ForEach-Object { "rt=$($_.rt) vn=$($_.vn)@$($_.vc)" }) -join '; ') }

$r = ReceiverOf 'C1' 'Count'
Check 'C1  A.GetB(1).Count -> receiver ref GetB' ((@($r).Count -ge 1) -and (Has $r 'GetB')) (D $r)
$r = ReceiverOf 'C2' 'Count'
Check 'C2  MakeA().GetB(2).Count -> receiver ref GetB' ((@($r).Count -ge 1) -and (Has $r 'GetB')) (D $r)
$r = ReceiverOf 'C3' 'Count'
Check 'C3  A.GetB(Twice(3)).Count -> receiver ref GetB (nested parens)' ((@($r).Count -ge 1) -and (Has $r 'GetB')) (D $r)
$r = ReceiverOf 'B1' 'Count'
Check 'B1  CONTROL MakeB().Count -> receiver ref MakeB (bare head)' ((@($r).Count -ge 1) -and (Has $r 'MakeB')) (D $r)
$r = ReceiverOf 'N1' 'GetB'
Check 'N1  CONTROL A.GetB(4) -> receiver ref A (plain dotted)' ((@($r).Count -ge 1) -and (Has $r 'A')) (D $r)

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
