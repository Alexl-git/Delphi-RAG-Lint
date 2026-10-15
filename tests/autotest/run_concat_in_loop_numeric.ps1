<#
  run_concat_in_loop_numeric.ps1 -- concat-in-loop must not report a numeric
  sum whose type is declared (Gitea drag-lint#7).

  THE DEFECT. The rule is a tree-sitter query: `X := X + Y` in a loop, with
  syntactic exclusions only (numeric literal or `[` on the right, a reset in
  the same pass). With a VARIABLE on the right, `Total := Total + Qty` and
  `S := S + Word` are the same tree, so every numeric accumulation in a loop
  was reported as an O(n^2) string concatenation -- ~40% of the rule's
  findings on sampled production code (Currency, Integer, Int64, Double). The new
  `#not-declared-numeric?` predicate reads the declaration in the enclosing
  routine; unknown keeps the finding.

  WHAT THIS ASSERTS (lint without --db, rule concat-in-loop)
    1. Result: Integer, for var I := ... Result := Result + I       -> 0   <- THE FIX
    2. Result: Double (for-in), Total: Int64 (while), Cur: Currency -> 0   <- THE FIX
    3. inline `var Acc: Integer := 0` + `for var` sum                -> 0   <- THE FIX
    4. CONTROL: string accumulations keep firing -- section var, inline
       `var Acc: string := ''`, untyped inline `var Acc := ''`, Result: string
    5. CONTROL: a string built from Chars keeps firing
    6. CONTROL: a FIELD (not declared in the routine) keeps firing -- unknown
       is never treated as numeric

  RED-CHECK: against the pre-fix build 1, 2 and 3 FAIL; 4, 5 and 6 pass on both.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
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

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

$work = Join-Path C:\TEMP "draglint_concatnum_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

$unit = Join-Path $work 'Fx7.pas'
Write-Ascii $unit @'
unit Fx7;

interface

type
  TAcc = class
    FText: string;
    procedure Grow(const L: TArray<string>);
  end;

function SumI(const Names: TArray<string>): Integer;
function SumD(const V: TArray<Double>): Double;
function SumL(N: Integer): Int64;
function SumC(const V: TArray<Currency>): Currency;
function SumInline(N: Integer): Integer;
function JoinSec(const L: TArray<string>): string;
function JoinInl(const L: TArray<string>): string;
function JoinRes(const L: TArray<string>): string;
function JoinChr(const L: TArray<Char>): string;

implementation

function SumI(const Names: TArray<string>): Integer;
begin
  Result := 0;
  for var I := 0 to High(Names) do
    Result := Result + I; { NUM_SUMI }
end;

function SumD(const V: TArray<Double>): Double;
begin
  Result := 0;
  for var X in V do
    Result := Result + X; { NUM_SUMD }
end;

function SumL(N: Integer): Int64;
var
  Total, K: Int64;
begin
  Total := 0;
  K := N;
  while K > 0 do
  begin
    Total := Total + K; { NUM_SUML }
    Dec(K);
  end;
  Result := Total;
end;

function SumC(const V: TArray<Currency>): Currency;
var
  Cur: Currency;
begin
  Cur := 0;
  for var X in V do
    Cur := Cur + X; { NUM_SUMC }
  Result := Cur;
end;

function SumInline(N: Integer): Integer;
begin
  var Acc: Integer := 0;
  for var I := 1 to N do
    Acc := Acc + I; { NUM_INLINE }
  Result := Acc;
end;

function JoinSec(const L: TArray<string>): string;
var
  S: string;
begin
  S := '';
  for var X in L do
    S := S + X; { STR_SEC }
  Result := S;
end;

function JoinInl(const L: TArray<string>): string;
begin
  var Acc: string := '';
  for var X in L do
    Acc := Acc + X; { STR_INL }
  var Acc2 := '';
  for var X in L do
    Acc2 := Acc2 + X; { STR_UNTYPED }
  Result := Acc + Acc2;
end;

function JoinRes(const L: TArray<string>): string;
begin
  Result := '';
  for var X in L do
    Result := Result + X; { STR_RES }
end;

function JoinChr(const L: TArray<Char>): string;
var
  Line: string;
begin
  Line := '';
  for var X in L do
    Line := Line + X; { CHR }
  Result := Line;
end;

procedure TAcc.Grow(const L: TArray<string>);
begin
  for var X in L do
    FText := FText + X; { FIELD }
end;

end.
'@
$lines = Get-Content -LiteralPath $unit
function LineOf([string]$mark) { for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -cmatch ('\{ ' + [regex]::Escape($mark) + ' \}')) { return $i + 1 } }; return -1 }
$out = (& $Exe lint $unit --rule concat-in-loop 2>$null) -join "`n"
Write-Host $out -ForegroundColor DarkGray
$hits = @($out -split "`n" | Where-Object { $_ -match 'concat-in-loop' })
function Fires([string]$mark) { $l = LineOf $mark; return (@($hits | Where-Object { $_ -match ":${l}:" }).Count -ge 1) }

Check '1. Result: Integer sum is not reported' (-not (Fires 'NUM_SUMI')) ''
Check '2. Double / Int64 / Currency sums are not reported' `
  ((-not (Fires 'NUM_SUMD')) -and (-not (Fires 'NUM_SUML')) -and (-not (Fires 'NUM_SUMC'))) ''
Check '3. inline var Acc: Integer sum is not reported' (-not (Fires 'NUM_INLINE')) ''
Check '4. CONTROL: string accumulations still fire (section, inline typed, inline untyped, Result)' `
  ((Fires 'STR_SEC') -and (Fires 'STR_INL') -and (Fires 'STR_UNTYPED') -and (Fires 'STR_RES')) ''
Check '5. CONTROL: a string built from Chars still fires' (Fires 'CHR') ''
Check '6. CONTROL: a field (unknown here) still fires' (Fires 'FIELD') ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_concatnum_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
