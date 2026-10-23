<#
  run_lint_fp_magic_defaults_table.ps1 -- N-12 FP item (INBOX-yadf-fp-options, item 1).

  magic-literal fired on every line of a defaults table:
      Result.MaxLen := 180;  Result.Indent := 2; ...
  The literal is the WHOLE right-hand side of an assignment to a named field,
  so the field name states its meaning exactly as a `const MaxLen = 180` would.
  The rule now exempts a literal that is the entire rhs of an assignment whose
  target is a dotted field access.

  Positive controls: the same literal assigned to a plain local, and a literal
  that is only PART of the rhs (`Result.MaxLen := lW * 180`), must still be
  reported.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fp-magic-defaults-$PID"
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
unit fpmagic;

interface

type
  TOpts = record
    MaxLen, Indent, TabWidth: Integer;
  end;

function DefaultOptions: TOpts;
function Plain(lW: Integer): Integer;

implementation

function DefaultOptions: TOpts;
begin
  Result.MaxLen   := 180;
  Result.Indent   := 3;
  Result.TabWidth := 4;
end;

function Plain(lW: Integer): Integer;
var
  lX: Integer;
  lO: TOpts;
begin
  lX := 180;
  lO.MaxLen := lW * 140;
  Result := lX + lO.MaxLen;
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$unit = Join-Path $WorkDir 'fpmagic.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)

$out = (& $Exe lint $unit --rule magic-literal --enable magic-literal 2>$null | Out-String)
$table = @([regex]::Matches($out, 'fpmagic\.pas:(17|18|19):')).Count

Write-Host 'False positives that must be GONE' -ForegroundColor Cyan
Check 'a literal that is the whole rhs of a named-field assignment (defaults table)' `
  ($table -eq 0) "(found $table on lines 17-19)"
Write-Host 'True positives that must SURVIVE' -ForegroundColor Cyan
Check 'the same literal assigned to a plain local is still reported' `
  ($out -match 'fpmagic\.pas:27:') 'else the fix just disabled the rule'
Check 'a literal that is only PART of a field assignment rhs is still reported' `
  ($out -match 'fpmagic\.pas:28:') 'else every literal on a field line is exempt'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
