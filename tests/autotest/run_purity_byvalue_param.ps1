<#
  run_purity_byvalue_param.ps1 -- a write to a parameter passed BY VALUE with a scalar or string
  type changes the routine's own copy: the caller never sees it, so effect_summary has no p<n>.

  THE DEFECT (wave 146, t5\REPORT.md): YADF.Layout.CollectParensItems stored 'p1,?' for
  Inc(AIdx) on `AIdx: Integer`. side-effect-in-short-circuit was tuned on the rule side (t5);
  this fixes the stored fact, so every other reader of effect_summary agrees.

  CASES
    T1 IncValue      Inc(AIdx), by value             -> effect_free 1, ''
    T2 IncSecond     second param by value           -> effect_free 1 (ordinal is right)
    T3 MultiName     (A, B: Integer; var C) Inc(B)   -> effect_free 1 (a shared group is right)
    T4 IncDefault    AIdx: Integer = 0               -> effect_free 1
    T5 CallsIncVar   IncVar(X) where X is by value   -> effect_free 1 (translated through a call)
    T6 TMeth.M       a method's by-value parameter   -> effect_free 1
    C1 IncVar        var AIdx                        -> p0 (CONTROL: positive, still reported)
    C2 IncOut        out                             -> p0
    C3 IncSecondVar  (S: string; var AIdx)           -> p1 (CONTROL: ordinal)
    C4 MultiVar      (A, B: Integer; var C) Inc(C)   -> p2
    C5 IncAlias      TMyInt, a type not on the list  -> p0 (not judged: stays reported)
    C6 CallsIncVarV  IncVar(X) where X is var        -> p0

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_purity_byvalue_$PID"
)
try {
$ErrorActionPreference = 'Continue'   # engine stderr banner under PS5 is not an error (GD 148, per R3); every step below checks its own result
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
W (Join-Path $WorkDir 'uP.pas') @'
unit uP;

interface

type
  TMyInt = Integer;
  TMeth = class
  public
    procedure M(A: Integer);
  end;

procedure IncValue(AIdx: Integer);
procedure IncSecond(var S: string; AIdx: Integer);
procedure MultiName(A, B: Integer; var C: Integer);
procedure IncDefault(AIdx: Integer = 0);
procedure IncVar(var AIdx: Integer);
procedure IncOut(out AIdx: Integer);
procedure IncSecondVar(S: string; var AIdx: Integer);
procedure MultiVar(A, B: Integer; var C: Integer);
procedure IncAlias(AIdx: TMyInt);
procedure CallsIncVar(X: Integer);
procedure CallsIncVarV(var X: Integer);

implementation

procedure TMeth.M(A: Integer);
begin
  Inc(A);
end;

procedure IncValue(AIdx: Integer);
begin
  Inc(AIdx);
end;

procedure IncSecond(var S: string; AIdx: Integer);
begin
  Inc(AIdx);
end;

procedure MultiName(A, B: Integer; var C: Integer);
begin
  Inc(B);
end;

procedure IncDefault(AIdx: Integer = 0);
begin
  Inc(AIdx);
end;

procedure IncVar(var AIdx: Integer);
begin
  Inc(AIdx);
end;

procedure IncOut(out AIdx: Integer);
begin
  Inc(AIdx);
end;

procedure IncSecondVar(S: string; var AIdx: Integer);
begin
  Inc(AIdx);
end;

procedure MultiVar(A, B: Integer; var C: Integer);
begin
  Inc(C);
end;

procedure IncAlias(AIdx: TMyInt);
begin
  Inc(AIdx);
end;

procedure CallsIncVar(X: Integer);
begin
  IncVar(X);
end;

procedure CallsIncVarV(var X: Integer);
begin
  IncVar(X);
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uP in 'uP.pas';

begin
end.
'@
$db = Join-Path $WorkDir 'App.sqlite'
Push-Location C:\TEMP
& $exePath index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

$j = & $exePath sql --db $db --json --query "SELECT s.name, f.effect_free, f.effect_summary, f.effect_witness FROM symbols s JOIN symbol_facts f ON f.symbol_id = s.id WHERE s.kind IN ('procedure','method') AND f.effect_free IS NOT NULL" | Out-String | ConvertFrom-Json
Pop-Location
$rows = @{}
foreach ($r in $j.rows) { $rows[[string]$r[0]] = [pscustomobject]@{ Free = $r[1]; Sum = [string]$r[2]; Why = [string]$r[3] } }
Check "V the routines carry a verdict ($($rows.Count))" ($rows.Count -eq 12) ($rows.Keys -join ', ')

foreach ($c in @(@('T1','IncValue'),@('T2','IncSecond'),@('T3','MultiName'),@('T4','IncDefault'),@('T5','CallsIncVar'),@('T6','M'))) {
  $r = $rows[$c[1]]
  Check "$($c[0]) $($c[1]): a by-value write is no effect (free=$($r.Free) summary='$($r.Sum)')" (($r.Free -eq 1) -and ($r.Sum -eq '')) $r.Why
}
foreach ($c in @(@('C1','IncVar','p0'),@('C2','IncOut','p0'),@('C3','IncSecondVar','p1'),@('C4','MultiVar','p2'),@('C5','IncAlias','p0'),@('C6','CallsIncVarV','p0'))) {
  $r = $rows[$c[1]]
  Check "$($c[0]) CONTROL $($c[1]): stays reported as $($c[2]) (free=$($r.Free) summary='$($r.Sum)')" (($r.Free -eq 0) -and ($r.Sum -eq $c[2])) $r.Why
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath "C:\TEMP\draglint_purity_byvalue_$PID") { [IO.Directory]::Delete("C:\TEMP\draglint_purity_byvalue_$PID", $true) }
}
