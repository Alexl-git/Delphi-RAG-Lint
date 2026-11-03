<#
  run_function_result_while_true_exit.ps1 -- function-result-not-set must treat
  `while True do` / `repeat ... until False` with no Break as never falling
  through. INBOX-function-result-while-true-exit (YADF HasLineCommentOrOpenBlock:
  `while True do case ... Exit(x) ... end;` flagged "Result not assigned").

    G1  while True do case with Exit(x) arms (the INBOX shape)   MUST NOT fire
    G2  repeat ... until False, Exit(x) inside                   MUST NOT fire
    G3  while True do begin ... Exit(x) end                      MUST NOT fire
    P1  while True with a Break, nothing set after               MUST fire (control)
    P2  while A < 9 (real condition), Exit(x) inside, no tail    MUST fire (control)
    P3  repeat ... until A > 3 with only Exit(x)                 MUST fire (control)
  Asserted on `lint --json` (bare array), bucketed by start_line.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fres-whiletrue-$PID"
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
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
try {
  $fx = Join-Path $WorkDir 'WhileTrue.pas'
  $body = @'
unit WhileTrue;

interface

type
  TStep = (seEnd, seLine, seCode);

function G1(A: Integer): Boolean;
function G2(A: Integer): Integer;
function G3(A: Integer): Integer;
function P1(A: Integer): Integer;
function P2(A: Integer): Integer;
function P3(A: Integer): Integer;

implementation

function Next(A: Integer): TStep;
begin
  Result:= TStep(A mod 3);
end;

function G1(A: Integer): Boolean;
var i: Integer;
begin
  i:= 1;
  while True do
  case Next(i) of
    seEnd : Exit(False);
    seLine: Exit(True);
    seCode: Inc(i);
  end;
end;

function G2(A: Integer): Integer;
begin
  repeat
    Inc(A);
    if A > 10 then Exit(A);
  until False;
end;

function G3(A: Integer): Integer;
begin
  while True do
  begin
    Inc(A);
    if A > 10 then Exit(A);
  end;
end;

function P1(A: Integer): Integer;
begin
  while True do
  begin
    Inc(A);
    if A > 10 then Break;
  end;
end;

function P2(A: Integer): Integer;
begin
  while A < 9 do
  begin
    Inc(A);
    if A > 5 then Exit(A);
  end;
end;

function P3(A: Integer): Integer;
begin
  repeat
    Inc(A);
    if A > 5 then Exit(A);
  until A > 3;
end;

end.
'@
  $norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($fx, $norm, [System.Text.Encoding]::ASCII)
  $lines = [System.IO.File]::ReadAllLines($fx)
  $names = @('G1', 'G2', 'G3', 'P1', 'P2', 'P3')
  $start = [ordered]@{}
  foreach ($n in $names) {
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      if ($lines[$i] -match ('^function ' + $n + '\(')) { $start[$n] = $i + 1; break }
    }
  }
  Check 'all routine headers located' ($start.Count -eq $names.Count)
  $raw = (& $Exe lint $fx --rule function-result-not-set --json 2>$null) -join "`n"
  $f = if ([string]::IsNullOrWhiteSpace($raw)) { @() } else { @($raw | ConvertFrom-Json) }
  function CountIn($name) {
    $lo = $start[$name]
    $idx = [array]::IndexOf(@($names), $name)
    $hi = if ($idx -lt $names.Count - 1) { $start[$names[$idx + 1]] } else { $lines.Count + 1 }
    @($f | Where-Object { $_.start_line -ge $lo -and $_.start_line -lt $hi }).Count
  }
  Check 'P1 while True + Break, no Result -> fires' ((CountIn 'P1') -ge 1)
  Check 'P2 while A < 9, Exit inside, no tail -> fires' ((CountIn 'P2') -ge 1)
  Check 'P3 repeat until A > 3, Exit inside -> fires' ((CountIn 'P3') -ge 1)
  Check 'G1 while True do case ... Exit(x) (INBOX shape)' ((CountIn 'G1') -eq 0)
  Check 'G2 repeat ... until False, Exit inside' ((CountIn 'G2') -eq 0)
  Check 'G3 while True do begin ... Exit(x) end' ((CountIn 'G3') -eq 0)
}
finally { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } }
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
