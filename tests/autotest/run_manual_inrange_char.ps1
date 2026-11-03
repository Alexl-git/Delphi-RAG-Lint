<#
  run_manual_inrange_char.ps1 -- manual-inrange must not suggest System.Math.InRange
  for Char operands (InRange has no Char overload; E2250). INBOX-manual-inrange-char.

    G1  (C >= 'a') and (C <= 'z')                    Char var, literal bounds   MUST NOT fire
    G2  (S[i] >= 'a') and (S[i] <= 'z')              indexed string             MUST NOT fire
    G3  (C >= 'A') and (C <= 'Z') or-ed with another range                      MUST NOT fire
    G4  (C >= #32) and (C <= #126)                   control-char literals      MUST NOT fire
    P1  (I >= 1) and (I <= 9)                        Integer                    MUST fire
    P2  (B >= $C2) and (B <= $DF)                    Byte                       MUST fire
    P3  (D >= 0.5) and (D <= 2.5)                    Double                     MUST fire
  Asserted on `lint --json` (bare array), bucketed by start_line.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-inrange-char-$PID"
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
  $fx = Join-Path $WorkDir 'InRangeChar.pas'
  $body = @'
unit InRangeChar;

interface

function G1(C: Char): Boolean;
function G2(const S: string; I: Integer): Boolean;
function G3(C: Char): Boolean;
function G4(C: Char): Boolean;
function P1(I: Integer): Boolean;
function P2(B: Byte): Boolean;
function P3(D: Double): Boolean;

implementation

function G1(C: Char): Boolean;
begin
  Result:= (C >= 'a') and (C <= 'z');
end;

function G2(const S: string; I: Integer): Boolean;
begin
  Result:= (S[I] >= 'a') and (S[I] <= 'z');
end;

function G3(C: Char): Boolean;
begin
  Result:= ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

function G4(C: Char): Boolean;
begin
  Result:= (C >= #32) and (C <= #126);
end;

function P1(I: Integer): Boolean;
begin
  Result:= (I >= 1) and (I <= 9);
end;

function P2(B: Byte): Boolean;
begin
  Result:= (B >= $C2) and (B <= $DF);
end;

function P3(D: Double): Boolean;
begin
  Result:= (D >= 0.5) and (D <= 2.5);
end;

end.
'@
  $norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($fx, $norm, [System.Text.Encoding]::ASCII)
  $lines = [System.IO.File]::ReadAllLines($fx)
  $names = @('G1', 'G2', 'G3', 'G4', 'P1', 'P2', 'P3')
  $start = [ordered]@{}
  foreach ($n in $names) {
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      if ($lines[$i] -match ('^function ' + $n + '\(')) { $start[$n] = $i + 1; break }
    }
  }
  Check 'all routine headers located' ($start.Count -eq $names.Count)
  $raw = (& $Exe lint $fx --rule manual-inrange --json 2>$null) -join "`n"
  $f = if ([string]::IsNullOrWhiteSpace($raw)) { @() } else { @($raw | ConvertFrom-Json) }
  function CountIn($name) {
    $lo = $start[$name]
    $idx = [array]::IndexOf(@($names), $name)
    $hi = if ($idx -lt $names.Count - 1) { $start[$names[$idx + 1]] } else { $lines.Count + 1 }
    @($f | Where-Object { $_.start_line -ge $lo -and $_.start_line -lt $hi }).Count
  }
  Check 'P1 Integer range -> fires' ((CountIn 'P1') -ge 1)
  Check 'P2 Byte range -> fires' ((CountIn 'P2') -ge 1)
  Check 'P3 Double range -> fires' ((CountIn 'P3') -ge 1)
  Check 'G1 Char var, literal bounds' ((CountIn 'G1') -eq 0)
  Check 'G2 indexed string char' ((CountIn 'G2') -eq 0)
  Check 'G3 two Char ranges or-ed' ((CountIn 'G3') -eq 0)
  Check 'G4 #nn char literals' ((CountIn 'G4') -eq 0)
}
finally { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } }
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
