# Guard: `for G := Low(T) to High(T)` over an ordinal TYPE runs at least once.
#
# used-before-assignment reported a local that is written only inside such a
# loop, because ForLoopAlwaysExecutes (src\analysis\DRagLint.Analysis.Cfg.pas)
# accepted only INTEGER LITERAL bounds. Every other for-loop got the zero-trip
# shape, so the body's writes were may-defs and a following read was "may be
# used before assigned".
#
# For an ordinal TYPE this is not a heuristic, it is a theorem: Low(T) <= High(T)
# holds for every ordinal type in the language, so the range is never empty and
# the body executes at least once. Seven warnings in
# src\report\DRagLint.Report.Deps.pas are this one shape
# (`for G:= Low(TDepsGroup) to High(TDepsGroup) do ProjUnitsPerGroup[G]:= nil`).
#
# THE SOUNDNESS CONTROL, and it is the whole reason this file exists.
# Widening the rule SUPPRESSES findings, so a mistake here loses true positives
# -- the failure direction FlowChecks.pas refuses in writing. The unsound
# neighbour is `Low(V) to High(V)` where V is a dynamic array or string
# VARIABLE: High(V) is -1 when V is empty, so that loop CAN run zero times.
# PDyn pins exactly that: it must keep warning. Without it, "the ordinal case is
# silent now" is indistinguishable from having widened the rule to every
# Low/High loop, which would be a silent correctness regression.
#
# The gate implemented is deliberately narrow and syntactic: the SAME identifier
# in both bounds, AND that identifier is the DECLARED TYPE of the loop control
# variable. That last clause is what makes it sound without a symbol table --
# `Low(TFoo)`/`High(TFoo)` where TFoo is the control variable's type only
# compiles when TFoo is ordinal (Low/High of a dynamic-array or string TYPE is
# not legal Delphi; those need an instance).
#
# Usage: pwsh -File tests/autotest/run_for_over_ordinal_type_executes.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir  = "$env:TEMP\drag-lint-for-ordinal"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# Every local below is an UNMANAGED static array or a plain Integer, so none of
# them is zero-initialised and each is genuinely reportable on a may-path. The
# decision therefore turns purely on whether the loop body is on a guaranteed
# path, which is what this pins. Local names are unique per routine because the
# assertions match on the reported name.
$Fixture = @'
unit uForOrd;

interface

type
  TGrade = (gA, gB, gC);

procedure PType;
procedure PDyn(const ADyn: array of Integer);
procedure PStraight;
procedure PUnassigned(Flag: Boolean);

implementation

procedure PType;
var
  G     : TGrade;
  TallyT: array[TGrade] of Integer;
  NT    : Integer;
begin
  for G := Low(TGrade) to High(TGrade) do TallyT[G] := 0;
  NT := TallyT[gA];
  Writeln(NT);
end;

procedure PDyn(const ADyn: array of Integer);
var
  I    : Integer;
  SumsD: array[0..2] of Integer;
  MD   : Integer;
begin
  for I := Low(ADyn) to High(ADyn) do SumsD[0] := ADyn[I];
  MD := SumsD[0];
  Writeln(MD);
end;

procedure PStraight;
var
  TallyS: array[TGrade] of Integer;
  NS    : Integer;
begin
  TallyS[gA] := 0;
  NS := TallyS[gA];
  Writeln(NS);
end;

procedure PUnassigned(Flag: Boolean);
var
  QCtl: Integer;
  NQ  : Integer;
begin
  if Flag then QCtl := 1;
  NQ := QCtl;
  Writeln(NQ);
end;

end.
'@
$file = Join-Path $WorkDir 'uForOrd.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$named = @([regex]::Matches($out, 'used-before-assignment: Local "(\w+)"') | ForEach-Object { $_.Groups[1].Value })
Write-Host ("  reported: {0}" -f ($(if ($named) { $named -join ',' } else { '(none)' }))) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'CONTROLS -- these fix the meaning of the two assertions below' -ForegroundColor Cyan
# Proves the rule is ON and reporting in this fixture at all. Without it, a
# build with used-before-assignment disabled passes every "is NOT reported" arm.
Check 'a plainly may-unassigned local IS reported (rule is on)' ($named -contains 'qctl') `
    ("reported: " + ($named -join ','))
# Pre-existing: an element write on a STRAIGHT LINE already must-defs the base,
# so the loop is the only variable between this and PType.
Check 'a straight-line element write is not reported (pre-existing)' (-not ($named -contains 'tallys'))

Write-Host ''
Write-Host 'THE FIX -- a for over an ordinal TYPE is a guaranteed path' -ForegroundColor Cyan
Check 'array written only in for G := Low(TGrade) to High(TGrade) is NOT reported' `
    (-not ($named -contains 'tallyt')) ("reported: " + ($named -join ','))

Write-Host ''
Write-Host 'THE SOUNDNESS CONTROL -- an open/dynamic array VARIABLE can be empty' -ForegroundColor Cyan
Check 'array written only in for I := Low(ADyn) to High(ADyn) IS still reported' `
    ($named -contains 'sumsd') ("reported: " + ($named -join ','))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
