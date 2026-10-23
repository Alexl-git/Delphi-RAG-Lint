<#
  run_lint_fp_sized_plus_one.ps1 -- N-14 (INBOX-lint-fp-active-field-and-sized-plus-one, item 2).

  off-by-one-count fired on `for i := 0 to Length(lA) do lD[i, 0] := i;` where
  `SetLength(lD, Length(lA) + 1, ...)` sits above the loop (a Levenshtein
  table): the table is sized one past Length(lA) on purpose, so the loop is in
  bounds. The rule now drops the match when an earlier SetLength in the same routine
  sizes something to `Length(<the same X>) + 1`.

  Positive controls: the same loop with no +1 sizing, and a +1 sizing of a
  DIFFERENT array's length, must still be reported.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fp-sized-$PID"
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
unit fpsized;

interface

function Lev(const pA, pB: string): Integer;
function Plain(const pA: TArray<Integer>): Integer;
function Other(const pA, pB: TArray<Integer>): Integer;

implementation

function Lev(const pA, pB: string): Integer;
var
  lD: array of array of Integer;
  i: Integer;
begin
  SetLength(lD, Length(pA) + 1, Length(pB) + 1);
  for i := 0 to Length(pA) do
    lD[i, 0] := i;
  Result := lD[Length(pA), 0];
end;

function Plain(const pA: TArray<Integer>): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Length(pA) do
    Result := Result + pA[i];
end;

function Other(const pA, pB: TArray<Integer>): Integer;
var
  lD: TArray<Integer>;
  i: Integer;
begin
  Result := 0;
  SetLength(lD, Length(pB) + 1);
  for i := 0 to Length(pA) do
    Result := Result + pA[i];
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$unit = Join-Path $WorkDir 'fpsized.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)

$out = (& $Exe lint $unit --rule off-by-one-count 2>$null | Out-String)

Write-Host 'False positive that must be GONE' -ForegroundColor Cyan
Check 'a loop to Length(pA) over a table sized Length(pA) + 1 is in bounds' `
  (-not ($out -match 'fpsized\.pas:17:'))
Write-Host 'True positives that must SURVIVE' -ForegroundColor Cyan
Check 'a loop to Length(pA) with no +1 sizing is still reported' `
  ($out -match 'fpsized\.pas:27:') 'else the fix just disabled the rule'
Check 'a +1 sizing of a DIFFERENT array does not excuse the loop' `
  ($out -match 'fpsized\.pas:38:') 'else the exemption ignores which array was sized'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
