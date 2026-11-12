<#
  run_named_arg_readers.ps1 -- lane 152b GF1 rows 2 + 3 (finisher F-GF1-R2R3).

  Row 2: grammar v1.4.9 wraps an Automation named argument `Foo(Name := V)` in exprArgNamed.
  unconditional-recursion (ControlFlowChecks.ExprCallsSelf) must see the call in the VALUE and
  must NOT treat the LABEL as a call/identifier. (EffectRules.Invariant, InlayHint.VisitCall and
  Fix.Stmt.ElementRead got the same unwrap; they are not reachable from a lint fixture.)
  Row 3: magic-literal must not flag the ordinal of `external Lib index N`.
  Positive controls: a real magic literal and a label-only function name still behave.
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-named-arg-readers-$PID"
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
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null

$src = @(
  'unit uNamedArgReaders;'
  ''
  'interface'
  ''
  'const'
  '  LibName = ''kernel32.dll'';'
  ''
  'function Rec(const S: OleVariant): Integer;'
  'function LabelOnly(const S: OleVariant): Integer;'
  'function TickB: Cardinal; stdcall; external LibName index 5;'
  ''
  'implementation'
  ''
  'function Rec(const S: OleVariant): Integer;'
  'begin'
  '  Result := S.Calc(N := Rec(S));'
  'end;'
  ''
  'function LabelOnly(const S: OleVariant): Integer;'
  'begin'
  '  Result := S.Calc(LabelOnly := 1);'
  'end;'
  ''
  'function Magic: Integer;'
  'begin'
  '  Result := Sqr(41) + Sqr(0);'
  'end;'
  ''
  'end.'
) -join "`r`n"
$pas = Join-Path $WorkDir 'uNamedArgReaders.pas'
[IO.File]::WriteAllText($pas, $src + "`r`n", [Text.Encoding]::ASCII)

Push-Location $WorkDir
try {
  $raw = (& $Exe lint $pas --enable magic-literal --json 2>$null) -join "`n"
  $rows = @($raw | ConvertFrom-Json)
  Check 'lint --json answered (non-empty array)' ($rows.Count -gt 0) "rows=$($rows.Count)"
  $rec = @($rows | Where-Object { $_.rule -eq 'unconditional-recursion' } | ForEach-Object { $_.start_line })
  $mag = @($rows | Where-Object { $_.rule -eq 'magic-literal' } | ForEach-Object { $_.start_line })
  Write-Host ("  unconditional-recursion lines [{0}]  magic-literal lines [{1}]" -f ($rec -join ','), ($mag -join ',')) -ForegroundColor DarkGray
  Write-Host 'row 2: named-argument VALUE is read' -ForegroundColor Cyan
  Check 'unconditional-recursion IS reported for S.Calc(N := Rec(S)) (line 16)' ($rec -contains 16)
  Check 'unconditional-recursion NOT reported for a label-only name (line 21)' (-not ($rec -contains 21))
  Write-Host 'row 3: external index ordinal' -ForegroundColor Cyan
  Check 'magic-literal NOT reported on `external LibName index 5` (line 10)' (-not ($mag -contains 10))
  Check 'magic-literal IS reported for Sqr(41) (line 26, positive control)' ($mag -contains 26)
} finally { Pop-Location }

[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
