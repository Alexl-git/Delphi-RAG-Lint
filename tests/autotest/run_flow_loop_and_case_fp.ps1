<#
  run_flow_loop_and_case_fp.ps1 -- two false positives reported from a real
  review of C:\Projects\DataCopy\uFileUtils.pas, plus the true positives they
  must NOT take with them.

  1) write-only-local on a for-loop's counter AND its bound
     ------------------------------------------------------
     Reported for `J` and `LCount` in

         for J:= 1 to LCount do ...

     The CFG's `for` lowering emitted only the 'start' assignment and the 'body'.
     The BOUND expression was never emitted at all, so `LCount` -- which the loop
     plainly consumes -- recorded no read; and the loop's implicit read of its
     own control variable was not modelled, so a counter whose body never
     mentions it looked assigned-and-never-read. ExtractMethod already had the
     right rule ("the remaining non-start, non-body named children are the bound
     expressions"); the CFG now applies it, and emits the control variable into
     the loop header where the test/increment reads it.

  2) empty-case-branch on a branch that HAS a comment
     ------------------------------------------------
     The rule's own message offers "or add a comment if intentional", but the
     .scm only anchored on the caseLabel being the branch's last child, so the
     documented escape hatch did not exist and a deliberate no-op could not be
     silenced. The comment usually sits on the STATEMENT line, not the label
     line:

         #$00B0, #$2300:
           ; // Skip/Eliminate

  Both halves assert the NEGATIVE and the POSITIVE: a fix that simply stopped
  the rules firing would pass half of this file and fail the other half.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-flow-fp"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir -Force | Out-Null

$src = @'
unit flowfp;

interface

procedure Demo(AKind: Integer);

implementation

procedure Demo(AKind: Integer);
var
  Counter : Integer;
  Bound   : Integer;
  DeadOne : Integer;
begin
  Bound  := 5;
  DeadOne:= 7;
  for Counter:= 1 to Bound do
    Writeln('tick');
  case AKind of
    1: Writeln('one');
    2:
      ;
    3:
      ; // deliberate no-op
  end;
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$unit = Join-Path $WorkDir 'flowfp.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)

$out = (& $Exe lint $unit 2>$null | Out-String)

Write-Host 'False positives that must be GONE' -ForegroundColor Cyan
Check 'loop COUNTER is not write-only (the loop reads it every test)' `
  (-not ($out -match 'write-only-local: Local "counter"'))
Check 'loop BOUND is not write-only (the loop reads it)' `
  (-not ($out -match 'write-only-local: Local "bound"'))
Check 'a commented empty case branch is not reported' `
  (-not ($out -match '(?m)^.*:24:.*empty-case-branch'))

Write-Host ''
Write-Host 'True positives that must SURVIVE' -ForegroundColor Cyan
Check 'a genuinely write-only local is still reported' `
  ($out -match 'write-only-local: Local "deadone"') 'else the fix just disabled the rule'
Check 'an UNcommented empty case branch is still reported' `
  ($out -match 'empty-case-branch') 'else the fix just disabled the rule'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
