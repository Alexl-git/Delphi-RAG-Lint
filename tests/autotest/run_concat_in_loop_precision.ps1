<#
  run_concat_in_loop_precision.ps1 -- `concat-in-loop` must flag STRING
  concatenation, not every self-referential assignment in a loop.

  THE BUG (found 2026-08-13 while triaging YADF; 2 of 6 sampled were false)
  ------------------------------------------------------------------------
  The query matched any `X := X <binop> Y`:

      rhs: (exprBinary lhs: (identifier) @lhs_id)

  with no constraint on the operator and none on the operand. So a plain loop
  counter was reported as quadratic string building:

      i := i + 1;      -- YADF.Layout.pas:445
      k := k + 2;      -- YADF.Layout.pas:2568

  and `i := i - 1` would have been too, since (kSub) is an exprBinary like any
  other. The message names `+` explicitly, so the pattern and the message
  disagreed.

  THE FIX, and what it does NOT fix
  ---------------------------------
  Two constraints, both derived from a dumped AST rather than guessed:
    * `operator: (kAdd)` -- nothing else concatenates.
    * the right operand may not start with a digit or `$`. A numeric literal on
      the right cannot be string concatenation -- `S := S + 1` does not compile
      in Delphi -- so this is type-safe reasoning without a type.

  It remains type-blind for a VARIABLE operand: `i := i + Count` still fires.
  Case 5 below asserts that honestly rather than pretending otherwise, so the
  day a store-backed built-in supersedes this query (the
  string-equality-comparison precedent), the test says exactly what changed.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-concat-precision"
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

$fixture = Join-Path $WorkDir 'ConcatPrecision.pas'
$body = @"
unit ConcatPrecision;

interface

procedure P;

implementation

procedure P;
var
  i, k, Count: Integer;
  S: string;
  C: Char;
  Arr: TArray<Integer>;
begin
  i := 0; k := 0; Count := 2; S := ''; C := 'x';
  Arr := nil;
  while i < 10 do
  begin
    S := S + C;
    S := S + 'x';
    i := i + 1;
    k := k - 1;
    k := k + 2;
    i := i + Count;
    Arr := Arr + [i];
  end;
  Writeln(S, i, k, Length(Arr));
end;

end.
"@
$norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

# Resolve the statement lines from the fixture, so edits cannot decouple them.
$lines = [System.IO.File]::ReadAllLines($fixture)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$lnConcatVar = LineOf 'S := S + C;'
$lnConcatLit = LineOf "S := S + 'x';"
$lnIncOne    = LineOf 'i := i + 1;'
$lnDecOne    = LineOf 'k := k - 1;'
$lnIncTwo    = LineOf 'k := k + 2;'
$lnAddVar    = LineOf 'i := i + Count;'
$lnArrAppend = LineOf 'Arr := Arr + [i];'
Check 'all seven fixture statements located' (
  @($lnConcatVar,$lnConcatLit,$lnIncOne,$lnDecOne,$lnIncTwo,$lnAddVar,$lnArrAppend) -notcontains -1)

# `lint --rule` cannot be used: its validator rejects external .scm ids.
$fired = @()
foreach ($line in (& $Exe lint $fixture 2>$null)) {
  if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+concat-in-loop:') { $fired += [int]$Matches[1] }
}
$fired = @($fired | Sort-Object -Unique)
Write-Host ("  fired on lines: {0}" -f ($fired -join ', ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'String concatenation in a loop MUST fire' -ForegroundColor Cyan
Check "S := S + C   (line $lnConcatVar)"   ($fired -contains $lnConcatVar)
Check "S := S + 'x' (line $lnConcatLit)"   ($fired -contains $lnConcatLit)

Write-Host ''
Write-Host 'Integer arithmetic in a loop MUST NOT fire' -ForegroundColor Cyan
Check "i := i + 1   (line $lnIncOne)  -- numeric literal operand" (-not ($fired -contains $lnIncOne))
Check "k := k + 2   (line $lnIncTwo)  -- numeric literal operand" (-not ($fired -contains $lnIncTwo))
Check "k := k - 1   (line $lnDecOne)  -- not even an addition"    (-not ($fired -contains $lnDecOne))

Write-Host ''
Write-Host 'Dynamic-array append in a loop MUST NOT fire' -ForegroundColor Cyan
# 2026-08-14. `Arr := Arr + [i]` is array append, not string concatenation, and
# `S := S + ['x']` does not compile -- so a right operand opening with `[` is
# type-safe to exclude WITHOUT a type, exactly like the numeric-literal rule
# above. Found by sampling 14 findings on drag-lint's own source: 5 were false
# positives and 4 of them were this shape (Doc.Facts, Doc.Strip, Lint.Baseline,
# Diagnostics.AstChecks). Removed 22 findings on drag-lint.
Check "Arr := Arr + [i] (line $lnArrAppend) -- array constructor operand" `
  (-not ($fired -contains $lnArrAppend)) `
  'the message advises TStringList/string.Join, which is nonsense for an array'

Write-Host ''
Write-Host 'KNOWN LIMITATION, asserted so a future fix is visible' -ForegroundColor Cyan
Check "i := i + Count (line $lnAddVar) still fires -- type-blind for a variable operand" `
  ($fired -contains $lnAddVar) 'flip this when a store-backed built-in supersedes the .scm rule'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
