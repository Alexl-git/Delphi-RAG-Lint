<#
  run_lint_fp_parens_generic_call.ps1 -- N-16 (INBOX-redundant-parentheses-generic-call).

  redundant-parentheses fired on the argument list of a generic method call
  `pO.GetValue<string>('title')` when the call sits inside a larger expression
  (a `+` concatenation, an `or` chain): there the parser reads
  `GetValue < string > ('title')` as two comparisons, so the call's argument
  list becomes an exprParens around a single literal. Real case:
  FeatureGenTests.dpr 638:67. The rule now skips an exprParens whose source is
  immediately preceded by a generic argument list `Ident<T, ...>`.

  Positive controls: `(pL) = ''` and `lA > (lB)` (a real comparison against a
  parenthesised single term) must still be reported.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fp-parens-generic-$PID"
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
unit fpparen;

interface

function A(const pO: TObject; const pL: string; lA, lB: Integer): Boolean;

implementation

function A(const pO: TObject; const pL: string; lA, lB: Integer): Boolean;
begin
  Result := (Pos('t' + pO.GetValue<string>('title') + 'x', pL) = 0);
  Result := Pos('t' + pO.GetValue<string>('title'), pL) = 0;
  Result := Pos(pO.GetValue<string>('title') + 'x', pL) = 0;
  Result := 'a' + pO.GetValue<string>('title') = pL;
  Result := 'a' + pO.GetValue<TArray<string>>('title') = pL;
  Result := 'a' + pO.Get<string, Integer>(lA) = pL;
  Result := (pL) = '';
  Result := lA > (lB);
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$unit = Join-Path $WorkDir 'fpparen.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)

$out = (& $Exe lint $unit --rule redundant-parentheses 2>$null | Out-String)
$generic = @([regex]::Matches($out, 'fpparen\.pas:1[1-6]:')).Count

Write-Host 'False positives that must be GONE' -ForegroundColor Cyan
Check 'the argument list of a generic call inside an expression is not reported' `
  ($generic -eq 0) "(found $generic on lines 11-16)"
Write-Host 'True positives that must SURVIVE' -ForegroundColor Cyan
Check '(pL) = '''' is still reported' `
  ($out -match 'fpparen\.pas:17:') 'else the fix just disabled the rule'
Check 'lA > (lB), a real comparison, is still reported' `
  ($out -match 'fpparen\.pas:18:') 'else every paren after > is exempt'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
