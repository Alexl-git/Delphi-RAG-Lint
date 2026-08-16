# Guard: a STATIC array is managed iff its ELEMENT type is.
#
# docs\INBOX-used-before-assignment-array-local-never-counted-as-defined.md.
#
# IsManagedType tested for the substring 'array of', which matches a DYNAMIC
# array but not `array[0..2] of string` -- the range sits between the two words.
# So a static array of a managed element type was treated as unmanaged and
# reported by used-before-assignment, even though the compiler zero-initialises
# it exactly as it does a bare string local: reading an element before any write
# yields '', which is defined behaviour and not a defect the rule can describe.
#
# THE NOTE'S STATED MECHANISM WAS WRONG and is worth recording: it says an array
# local is "never counted as defined". It is -- definite-assignment uses
# AssignmentBaseIndex, so `A[i] := x` does define A. The real cause was the
# managed-type test, reached only by measuring which types the rule reports.
#
# THE CONTROL IS THE ELEMENT TYPE. `array[0..2] of Integer` is NOT
# zero-initialised on the stack and must STILL be reported -- otherwise this is
# indistinguishable from switching the rule off for all arrays.
#
# Usage: pwsh -File tests/autotest/run_used_before_assignment_arrays.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir = "$env:TEMP\drag-lint-uba-arrays"
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

# Every local is written only inside `if Flag`, then read unconditionally -- so
# every one of them HAS a may-path where it was never assigned. The rule's
# decision therefore turns purely on the declared type, which is what this pins.
$Fixture = @'
unit uUBA;
interface
procedure P(Flag: Boolean);
implementation
procedure P(Flag: Boolean);
var
  SManaged: string;
  IUnmanaged: Integer;
  ArrManaged: array[0..2] of string;
  ArrUnmanaged: array[0..2] of Integer;
begin
  if Flag then
  begin
    SManaged := 'x';
    IUnmanaged := 1;
    ArrManaged[0] := 'y';
    ArrUnmanaged[0] := 2;
  end;
  Writeln(SManaged, IUnmanaged, ArrManaged[1], ArrUnmanaged[1]);
end;
end.
'@
$file = Join-Path $WorkDir 'uUBA.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$named = @([regex]::Matches($out, 'used-before-assignment: Local "(\w+)"') | ForEach-Object { $_.Groups[1].Value })
Write-Host ("  reported: {0}" -f ($(if ($named) { $named -join ',' } else { '(none)' }))) -ForegroundColor DarkGray

# THE DEFECT -- a static array of a managed element type is zero-initialised.
Check 'array[0..2] of string is NOT reported' (-not ($named -contains 'arrmanaged'))

# THE CONTROL -- an unmanaged element type is NOT zero-initialised on the stack.
# Without this arm, skipping every array would pass the check above.
Check 'array[0..2] of Integer IS still reported' ($named -contains 'arrunmanaged') `
    ("reported: " + ($named -join ','))

# Pre-existing behaviour, pinned so a future change to IsManagedType is visible:
# the rule already declines the analogous SCALAR cases in this same fixture.
Check 'a bare string local is not reported (pre-existing)' (-not ($named -contains 'smanaged'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
