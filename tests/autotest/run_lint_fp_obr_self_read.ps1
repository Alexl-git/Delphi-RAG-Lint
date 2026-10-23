<#
  run_lint_fp_obr_self_read.ps1 -- overwrite-before-read on `X := Stamp; ...;
  X := Now - X;` (e3d W5 item 1, reported by lane W3-7 on the T-04 timing code
  in DRagLint.Lint.ClassMetrics.pas: `var TInv := TStopwatch.GetTimeStamp; ..;
  TInv := TStopwatch.GetTimeStamp - TInv`).

  The second store READS X on its rhs, so the first store is live. On main
  4e3f8077 this did NOT reproduce in any of the shapes below (the backward
  transfer kills X, then the rhs read re-gens it) -- this guard pins that.

  Positive control: a genuine dead store (`X := 1; X := 2;`) must still be
  reported, else the guard passes with the rule switched off.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fp-obr-self-$PID"
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
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir -Force | Out-Null

$src = @'
unit fpobrself;

interface

procedure InlineVar;
procedure VarSection;
procedure Conditional(const pOn: Boolean);
procedure DeadStore;

implementation

uses System.SysUtils, System.Diagnostics;

procedure Work;
begin
  Sleep(1);
end;

procedure InlineVar;
begin
  var lT: Int64 := TStopwatch.GetTimeStamp;
  Work;
  lT := TStopwatch.GetTimeStamp - lT;
  if GetEnvironmentVariable('X') <> '' then
    Writeln(Format('%8.2f', [lT / TStopwatch.Frequency]));
end;

procedure VarSection;
var
  lX: TDateTime;
begin
  lX := Now;
  Work;
  lX := Now - lX;
  Writeln(FloatToStr(lX));
end;

procedure Conditional(const pOn: Boolean);
var
  lX: TDateTime;
begin
  lX := Now;
  if pOn then
    lX := Now - lX;
  Writeln(FloatToStr(lX));
end;

procedure DeadStore;
var
  lX: Integer;
begin
  lX := 1;
  lX := 2;
  Writeln(lX);
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$unit = Join-Path $WorkDir 'fpobrself.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)

$out = (& $Exe lint $unit --rule overwrite-before-read 2>$null | Out-String)
$fp = @([regex]::Matches($out, 'fpobrself\.pas:(2[0-9]|3[0-9]|4[0-7]):')).Count

Write-Host 'False positives that must stay GONE' -ForegroundColor Cyan
Check 'a store whose value the next store reads on its rhs is not a dead store' `
  ($fp -eq 0) "(found $fp in lines 20-47)"
Write-Host 'True positives that must SURVIVE' -ForegroundColor Cyan
Check 'a store overwritten without being read is still reported' `
  ($out -match 'fpobrself\.pas:52:') 'else the rule is off'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
