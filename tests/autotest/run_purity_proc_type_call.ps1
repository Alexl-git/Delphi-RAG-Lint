<#
  run_purity_proc_type_call.ps1 -- a call THROUGH a procedural-type variable
  (`P := DoWrite; P();`) is an unknown callee, so the caller is NOT effect-free.

  THE DEFECT (BACKLOG-TRIAGE-2026-09-28 FIX-3, part 2). The call `P()` has no
  call_edges row (P is a variable, not a routine), and the purity stage scored
  it as a pure built-in / no-effect, so a routine that runs an arbitrary
  procedure through a TProc / TFunc / method pointer scored effect-free.

  CASES
    T1 CallTProc      var P: TProc;      P := DoWrite; P();   -> effect_free 0
    T2 CallTFunc      var F: TFunc<Integer>; F := GetOne; Result := F();  -> 0
    T3 CallMethodPtr  var M: TNotifyEvent;   M(nil);          -> 0
    T4 CallParam      pCb: TProc; pCb();                       -> 0
    C1 CallDirect     DoWrite;               -> effect_free 0 (control: real effect)
    C2 PureAdd        Result := A + B;       -> effect_free 1 (control: guard can pass)
    C3 AssignOnly     P := DoWrite; (no call) -> effect_free 1 (assigning is no effect)

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_purity_proctype_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
W (Join-Path $WorkDir 'uProcs.pas') @'
unit uProcs;

interface

uses System.SysUtils, System.Classes;

type
  TPlainProc = procedure;
  TPlainFunc = function: Integer;
  TObjProc = procedure of object;
  TObjFunc = function: Integer of object;
  THolder = class
    FOnGo: TObjProc;
    FGet: TObjFunc;
  end;

var
  GCount: Integer;
  GProc: TPlainProc;

procedure DoWrite;
function GetOne: Integer;
procedure CallTProc;
function CallTFunc: Integer;
procedure CallMethodPtr;
procedure CallParam(pCb: TProc);
procedure CallDirect;
function PureAdd(A, B: Integer): Integer;
procedure AssignOnly;
procedure BareProc;
function BareFunc: Integer;
procedure BareMethod(pHolder: THolder);
procedure BareGlobal;
function BareMember(pHolder: THolder): Integer;
procedure CompareOnly;

implementation

procedure DoWrite;
begin
  GCount := GCount + 1;
end;

function GetOne: Integer;
begin
  Result := 1;
end;

procedure CallTProc;
var
  P: TProc;
begin
  P := DoWrite;
  P();
end;

function CallTFunc: Integer;
var
  F: TFunc<Integer>;
begin
  F := GetOne;
  Result := F();
end;

procedure CallMethodPtr;
var
  M: TNotifyEvent;
begin
  M := nil;
  M(nil);
end;

procedure CallParam(pCb: TProc);
begin
  pCb();
end;

procedure CallDirect;
begin
  DoWrite;
end;

function PureAdd(A, B: Integer): Integer;
begin
  Result := A + B;
end;

procedure AssignOnly;
var
  P: TProc;
begin
  P := DoWrite;
end;

procedure BareProc;
var
  P: TPlainProc;
begin
  P := DoWrite;
  P;
end;

function BareFunc: Integer;
var
  F: TPlainFunc;
begin
  F := GetOne;
  Result := F;
end;

procedure BareMethod(pHolder: THolder);
begin
  pHolder.FOnGo;
end;

procedure BareGlobal;
begin
  GProc;
end;

function BareMember(pHolder: THolder): Integer;
begin
  Result := pHolder.FGet;
end;

procedure CompareOnly;
var
  P: TPlainProc;
begin
  P := DoWrite;
  if Assigned(P) or (@P <> nil) or (P <> nil) then Exit;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;
uses
  uProcs in 'uProcs.pas';
begin
end.
'@
$db = Join-Path $WorkDir 'App.sqlite'
& $exePath index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

$j = & $exePath sql --db $db --json --query "SELECT s.name, f.effect_free, f.effect_summary, f.effect_witness FROM symbols s JOIN symbol_facts f ON f.symbol_id = s.id WHERE s.name IN ('CallTProc','CallTFunc','CallMethodPtr','CallParam','CallDirect','PureAdd','AssignOnly','BareProc','BareFunc','BareMethod','BareGlobal','BareMember','CompareOnly')" 2>$null | ConvertFrom-Json
$rows = @{}
foreach ($r in $j.rows) { $rows[[string]$r[0]] = [pscustomobject]@{ Free = $r[1]; Sum = [string]$r[2]; Why = [string]$r[3] } }
Check 'V all thirteen routines carry a purity verdict' ($rows.Count -eq 13) ($rows.Keys -join ', ')

foreach ($t in @(@('T1','CallTProc'),@('T2','CallTFunc'),@('T3','CallMethodPtr'),@('T4','CallParam'),@('T5','BareProc'),@('T6','BareFunc'),@('T7','BareMethod'),@('T8','BareGlobal'),@('T9','BareMember'))) {
  $x = $rows[$t[1]]
  Check "$($t[0]) $($t[1]) is NOT effect-free (effect_free $($x.Free), summary '$($x.Sum)')" ($x.Free -eq 0) $x.Why

}
# The paren-less READ forms had no call ref (base scored them effect-free): the witness must name the procedural read.
foreach ($n in @('BareFunc','BareMember')) { Check "W $n witness names the procedural read" ($rows[$n].Why -match 'procedur') $rows[$n].Why }
Check "C1 CONTROL a direct call of a writing routine is not effect-free" ($rows['CallDirect'].Free -eq 0) $rows['CallDirect'].Why
Check "C2 CONTROL pure arithmetic stays effect-free" ($rows['PureAdd'].Free -eq 1) $rows['PureAdd'].Why
Check "C3 CONTROL assigning a routine to a proc var (no call) stays effect-free" ($rows['AssignOnly'].Free -eq 1) $rows['AssignOnly'].Why

Check "C4 CONTROL Assigned(P) (no call) stays effect-free" ($rows['CompareOnly'].Free -eq 1) $rows['CompareOnly'].Why

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_purity_proctype_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
