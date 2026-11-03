<#
  run_cognitive_else_if_chain.ps1 -- cognitive-complexity must score `else if`
  as +1 with NO nesting increment (SonarSource spec).
  INBOX-cognitive-else-if-chain: YADF ParseFlags, a flat 69-arm ladder, scored
  2444 = 1+2+..+69 because each `else <if>` was scored one level deeper.

    E1  flat 100-arm `else if` ladder     score must be linear (< 2*N), not ~N^2/2
    E2  same ladder inside a `while`       ditto
    P1  12 genuinely nested ifs            MUST still score exactly 1+2+..+12 = 78
    P2  deep nest inside an else-if arm    the inner ifs still cost their nesting
  Default threshold is 65, so every routine here fires and carries its score in
  the message ("complexity N"). Asserted on `lint --json` (bare array, start_line).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cogelseif-$PID"
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
  $arms = 100
  $ladder = "  if A = 0 then begin R:= 0; end`n"
  for ($k = 1; $k -lt $arms; $k++) { $ladder += "  else if A = $k then begin R:= $k; end`n" }
  $ladder += "  else begin R:= -1; end;`n"
  $fx = Join-Path $WorkDir 'CogElseIf.pas'
  $body = @"
unit CogElseIf;

interface

function E1(A: Integer): Integer;
function E2(A: Integer): Integer;
function P1(A, B: Integer): Integer;
function P2(A, B: Integer): Integer;

implementation

function E1(A: Integer): Integer;
var R: Integer;
begin
  R:= 0;
$ladder  Result:= R;
end;

function E2(A: Integer): Integer;
var R: Integer;
begin
  R:= 0;
  while R < 3 do
  begin
$ladder    Inc(R);
  end;
  Result:= R;
end;

function P1(A, B: Integer): Integer;
begin
  Result:= 0;
  if A > 0 then if A > 1 then if A > 2 then if A > 3 then if A > 4 then if A > 5 then if A > 6 then
  if A > 7 then if A > 8 then if A > 9 then if A > 10 then if A > 11 then
    Result:= 1;
end;

function P2(A, B: Integer): Integer;
var R: Integer;
begin
  R:= 0;
  if A = 0 then begin R:= 0; end
  else if A = 1 then
  begin
    if B > 0 then if B > 1 then if B > 2 then if B > 3 then if B > 4 then if B > 5 then
    if B > 6 then if B > 7 then if B > 8 then if B > 9 then if B > 10 then R:= 9;
  end
  else begin R:= -1; end;
  Result:= R;
end;

end.
"@
  $norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($fx, $norm, [System.Text.Encoding]::ASCII)

  $raw = (& $Exe lint $fx --rule cognitive-complexity --json 2>$null) -join "`n"
  $f = if ([string]::IsNullOrWhiteSpace($raw)) { @() } else { @($raw | ConvertFrom-Json) }
  $lines = [System.IO.File]::ReadAllLines($fx)
  function ScoreAt($name) {
    $ln = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match ('^function ' + $name + '\(')) { $ln = $i + 1; break } }
    $m = $f | Where-Object { $_.start_line -eq $ln } | Select-Object -First 1
    if (($null -ne $m) -and ($m.message -match 'complexity (\d+)')) { return [int]$Matches[1] }
    return $null
  }
  Check 'findings carry start_line (shape)' (($f.Count -gt 0) -and ($null -ne $f[0].start_line))
  $e1 = ScoreAt 'E1'; $e2 = ScoreAt 'E2'; $p1 = ScoreAt 'P1'; $p2 = ScoreAt 'P2'
  Check 'E1 flat ladder scores linearly' (($null -ne $e1) -and ($e1 -lt 2 * $arms)) "score=$e1 arms=$arms"
  Check 'E2 ladder inside while scores linearly' (($null -ne $e2) -and ($e2 -lt 2 * $arms)) "score=$e2"
  Check 'P1 twelve nested ifs score exactly 78 (positive control)' ($p1 -eq 78) "score=$p1"
  Check 'P2 nesting inside an else-if arm still costs (>= 66)' (($null -ne $p2) -and ($p2 -ge 66)) "score=$p2"
}
finally { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } }
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
