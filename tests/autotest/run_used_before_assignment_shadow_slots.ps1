# Guard: one flow slot per DECLARATION, not per name (B-14, 1.31.6 lane D).
#
# docs\INBOX-used-before-assignment-record-and-shadow-residual.md section 2.
#
# TRoutineVarTable keyed its slots by lower-case name and ignored a second
# declaration of the same name, and a bare inline `var X: T;` (varDef) was not
# registered at all. So an inner-block `var Why := 1` and a later outer
# `var Why: string;` shared ONE slot, carrying the FIRST declaration's type and
# the inner block's assigned-ness. Two wrong answers followed:
#   M2: the outer `string` is managed (auto-initialised), but the rule asked
#       IsManagedType about the inner var's inferred type and reported it;
#   M3: the outer Integer is NEVER assigned, but the slot was MAY-assigned by
#       the inner block, so the rule said "may be used" instead of "is used".
#
# CONTROLS keep the rule alive on the same shapes: M4 (an inner varDef with no
# assignment is still an ERROR), M5 (a genuine may-path still says "may"), M1
# (a plain managed local stays silent -- the exemption M2 relies on).
#
# Usage: pwsh -File tests/autotest/run_used_before_assignment_shadow_slots.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir = "$env:TEMP\drag-lint-uba-shadow-$PID"
)
try {
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

$Fixture = @'
unit uUbaShadow;

interface

implementation

function M1(AFlag: Boolean): string;
var
  Plain: string;
begin
  Result := Plain;
end;

function M2(AFlag: Boolean): string;
begin
  Result := '';
  if AFlag then
  begin
    var Why := 1;
    if Why = 0 then Exit;
  end;
  var Why: string;
  Result := Why;
end;

function M3(AFlag: Boolean): Integer;
begin
  Result := 0;
  if AFlag then
  begin
    var Why := 1;
    if Why = 0 then Exit;
  end;
  var Why: Integer;
  Result := Why;
end;

function M4(AFlag: Boolean): Integer;
begin
  Result := 0;
  if AFlag then
  begin
    var Why: Integer;
    Result := Why;
  end
  else
  begin
    var Why: Integer := 5;
    Result := Why;
  end;
end;

function M5(AFlag: Boolean): Integer;
var
  X: Integer;
begin
  if AFlag then X := 1;
  Result := X;
end;

end.
'@
$file = Join-Path $WorkDir 'uUbaShadow.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$uba = @($out -split "`r?`n" | Where-Object { $_ -match 'used-before-assignment:' })
function At([int]$Line) { @($uba | Where-Object { $_ -match (':{0}:\d+\s' -f $Line) }) }

Check 'M1 control: plain managed local silent'  ((At 11).Count -eq 0) ((At 11) -join ' | ')
Check 'M2: outer string after inner inferred var not reported' ((At 23).Count -eq 0) ((At 23) -join ' | ')
Check 'M3: outer never-assigned Integer is reported' ((At 35).Count -eq 1) ((At 35) -join ' | ')
Check 'M3: ... as IS used (error), not MAY' (((At 35) -join '') -match 'is used before') ((At 35) -join ' | ')
Check 'M4 control: inner varDef with no assignment is an error' (((At 44) -join '') -match 'is used before') ((At 44) -join ' | ')
Check 'M4: sibling-block declaration with initialiser silent' ((At 49).Count -eq 0) ((At 49) -join ' | ')
Check 'M5 control: genuine may-path still says MAY' (((At 58) -join '') -match 'may be used before') ((At 58) -join ' | ')

if ($script:Failed) { Write-Host 'FAIL run_used_before_assignment_shadow_slots' -ForegroundColor Red; exit 1 }
Write-Host 'PASS run_used_before_assignment_shadow_slots' -ForegroundColor Green
exit 0
}
finally {
    if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
}
