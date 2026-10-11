<#
  run_function_result_noreturn_paths.ps1 -- `function-result-not-set` (and
  `out-param-not-set`) must not count a path that NEVER RETURNS as a path that
  returns an unassigned Result.

  THE BUG (C14, filed 2026-09-30 / 2026-10-05 by the converter stream)
  -------------------------------------------------------------------
  DRagLint.Analysis.Cfg wires a `raise` statement to the synthetic Exit block,
  so the definite-assignment state AT EXIT was the meet over the raise path
  too. A leading argument guard (`if A > 99 then raise ...;`) followed by full
  assignment therefore reported "Function Result is not assigned on every
  path." Halt and Abort were not terminators at all: control fell through them.

  Cases (each routine owns the lines from its header to the next header)
    G1  guard raise (CreateFmt) + both arms assign       MUST NOT fire
    G2  guard raise Exception.Create + both arms assign  MUST NOT fire
    G3  raise inside nested begin/end in the else arm    MUST NOT fire
    G4  try..except whose handler re-raises (`raise;`)   MUST NOT fire
    G5  then-arm Halt(1), else-arm assigns               MUST NOT fire
    G6  then-arm Abort, else-arm assigns                 MUST NOT fire
    G7  guard Exit(0) then assign                        MUST NOT fire
    G8  out param: guard raise, then assign              MUST NOT fire (out-param-not-set)
    P1  guard plain `Exit;` then assign                  MUST fire (positive control)
    P2  raise arm + an arm that falls through unassigned MUST fire (positive control)
    P3  guard raise, then only a partial assignment      MUST fire (positive control)
    P4  out param: plain Exit before assignment          MUST fire (out-param-not-set)
  Asserted on `lint --json` (a bare array), filtered by `rule` and bucketed by
  `start_line` into the routine spans.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fres-noreturn-$PID"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
try {
  $fixture = Join-Path $WorkDir 'NoReturnPaths.pas'
  $body = @'
unit NoReturnPaths;

interface

uses System.SysUtils;

function G1(A: Integer): Integer;
function G2(A: Integer): Integer;
function G3(A: Integer): Integer;
function G4(A: Integer): Integer;
function G5(A: Integer): Integer;
function G6(A: Integer): Integer;
function G7(A: Integer): Integer;
procedure G8(A: Integer; out B: Integer);
function P1(A: Integer): Integer;
function P2(A: Integer): Integer;
function P3(A: Integer): Integer;
procedure P4(A: Integer; out B: Integer);

implementation

function G1(A: Integer): Integer;
begin
  if A > 99 then
    raise EArgumentOutOfRangeException.CreateFmt('x %d', [A]);
  if A > 0 then
  begin
    Result := 1;
  end
  else
  begin
    Result := 2;
  end;
end;

function G2(A: Integer): Integer;
begin
  if A > 99 then
    raise Exception.Create('x');
  if A > 0 then
    Result := 1
  else
    Result := 2;
end;

function G3(A: Integer): Integer;
begin
  if A > 0 then
    Result := 1
  else
  begin
    if A < -5 then
    begin
      Writeln('bad');
      raise Exception.Create('x');
    end;
    Result := 2;
  end;
end;

function G4(A: Integer): Integer;
begin
  try
    Result := 100 div A;
  except
    Writeln('failed');
    raise;
  end;
end;

function G5(A: Integer): Integer;
begin
  if A > 99 then
  begin
    Writeln('fatal');
    Halt(1);
  end
  else
    Result := 2;
end;

function G6(A: Integer): Integer;
begin
  if A > 99 then
  begin
    Writeln('silent');
    Abort;
  end
  else
    Result := 2;
end;

function G7(A: Integer): Integer;
begin
  if A > 99 then
    Exit(0);
  Result := 2;
end;

procedure G8(A: Integer; out B: Integer);
begin
  if A > 99 then
    raise Exception.Create('x');
  B := A;
end;

function P1(A: Integer): Integer;
begin
  if A > 99 then
    Exit;
  Result := 2;
end;

function P2(A: Integer): Integer;
begin
  if A > 99 then
    raise Exception.Create('x')
  else if A > 0 then
    Result := 1;
end;

function P3(A: Integer): Integer;
begin
  if A > 99 then
  begin
    raise Exception.Create('x');
  end;
  if A > 0 then
    Result := 1;
end;

procedure P4(A: Integer; out B: Integer);
begin
  if A > 99 then
    Exit;
  B := A;
end;

end.
'@
  $norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

  # Routine spans from the IMPLEMENTATION headers (the last occurrence of each).
  $lines = [System.IO.File]::ReadAllLines($fixture)
  $names = @('G1', 'G2', 'G3', 'G4', 'G5', 'G6', 'G7', 'G8', 'P1', 'P2', 'P3', 'P4')
  $start = [ordered]@{}
  foreach ($n in $names) {
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      if ($lines[$i] -match ('^(function|procedure) ' + $n + '\(')) { $start[$n] = $i + 1; break }
    }
  }
  Check 'all twelve routine headers located' ($start.Count -eq $names.Count)
  $spans = @{}
  for ($k = 0; $k -lt $names.Count; $k++) {
    $hi = if ($k -lt $names.Count - 1) { $start[$names[$k + 1]] - 1 } else { $lines.Count }
    $spans[$names[$k]] = @($start[$names[$k]], $hi)
  }

  # One rule per run: a repeated --rule keeps only the last one.
  $all = @()
  foreach ($r in @('function-result-not-set', 'out-param-not-set')) {
    $raw = (& $Exe lint $fixture --rule $r --json 2>$null) -join "`n"
    if ($raw.Trim()) { $all += @($raw | ConvertFrom-Json) }
  }
  $hits = @($all | Where-Object { $_.rule -eq 'function-result-not-set' -or $_.rule -eq 'out-param-not-set' })
  Write-Host ("  findings: {0}" -f (($hits | ForEach-Object { '{0}@{1}' -f $_.rule, $_.start_line }) -join ', ')) -ForegroundColor DarkGray
  function CountIn([string]$Routine, [string]$Rule) {
    $sp = $spans[$Routine]
    return @($hits | Where-Object { $_.rule -eq $Rule -and [int]$_.start_line -ge $sp[0] -and [int]$_.start_line -le $sp[1] }).Count
  }
  $fr = 'function-result-not-set'
  $op = 'out-param-not-set'

  Write-Host ''
  Write-Host 'Positive controls (a real returning path leaves it unassigned)' -ForegroundColor Cyan
  Check 'P1 plain Exit before assignment -> fires' ((CountIn 'P1' $fr) -ge 1)
  Check 'P2 raise arm + fall-through arm unassigned -> fires' ((CountIn 'P2' $fr) -ge 1)
  Check 'P3 guard raise then partial assignment -> fires' ((CountIn 'P3' $fr) -ge 1)
  Check 'P4 out param, plain Exit before assignment -> fires' ((CountIn 'P4' $op) -ge 1)
  Check 'every finding carries a start_line (shape check)' (
    @($hits | Where-Object { $null -eq $_.start_line }).Count -eq 0)

  Write-Host ''
  Write-Host 'A path that never returns is satisfied -> MUST NOT fire' -ForegroundColor Cyan
  Check 'G1 guard raise CreateFmt' ((CountIn 'G1' $fr) -eq 0)
  Check 'G2 guard raise Exception.Create' ((CountIn 'G2' $fr) -eq 0)
  Check 'G3 raise in nested begin/end' ((CountIn 'G3' $fr) -eq 0)
  Check 'G4 except handler re-raises' ((CountIn 'G4' $fr) -eq 0)
  Check 'G5 Halt(1) arm' ((CountIn 'G5' $fr) -eq 0)
  Check 'G6 Abort arm' ((CountIn 'G6' $fr) -eq 0)
  Check 'G7 Exit(0) guard' ((CountIn 'G7' $fr) -eq 0)
  Check 'G8 out param guard raise' ((CountIn 'G8' $op) -eq 0)
}
finally {
  if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
