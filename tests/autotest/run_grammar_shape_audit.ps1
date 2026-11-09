<#
  run_grammar_shape_audit.ps1 -- lane 149-GA: the tree-walking rules read the grammar v1.4.4 / v1.4.5 shapes.

  Owner request 2026-11-09T03:00:51: a FULL grammar-shape audit of every rule / autofix that walks
  trees directly, for four shapes:
    (a) an if STATEMENT with an else is `ifElse` (v1.4.4; bare-call / Exit branches used to be
        statement(exprIf));
    (b) the right of `is` is a TYPE node (v1.4.5): `X is Unit.TFoo` is a typerefDot, and
        `X is T and F` groups as `(X is T) and F`;
    (c) `A + B < C` groups as `(A + B) < C` (the `_ref < _expr` rule is gone; generic `<` is
        kLtTpl aliased to kLt);
    (d) newly parsing constructs (char subrange, several hints, callconv chain on a field,
        code-page constant, headerless program, orphan asm body).
  Fixtures: tests\fixtures\grammar-shape-audit\. Classification table: lanes\149\GA\REPORT.md.

  Checks (each names the shape and the rule; a FAIL means a walker no longer reads the shape):
    B1  is-always-true fires on `pLeaf is TBase` (identifier) -- POSITIVE CONTROL, both grammars;
    B2  is-always-true fires on `pLeaf is GA_IsDotted.TBase` (typerefDot) -- the 149-GA fix in
        TRefTypeScan.WrittenType; FAILS on 1.48.0-alpha (v1.4.5 DLL): the dotted type went silent;
    B3  is-always-true fires on `pLeaf is TBase and pFlag` (grouping) -- v1.4.5 benefit;
    B4  is-always-true does NOT fire on `pLeaf is TOther` (unrelated class) -- negative control;
    A1  constant-condition fires on `if True then DoA else DoB` (ifElse) -- the 149-GA .scm fix;
        FAILS on 1.48.0-alpha;
    A2  else-after-exit / identical-then-else fire on the v1.4.4 ifElse forms -- benefit, guarded;
    C1  not-comparison-precedence fires on `not pA < pB`, and unsigned-compare-always-true does NOT
        fire on `pA + pW < 0` (Int64 sum) -- v1.4.5 grouping benefit, guarded;
    D1  GA_NewSyntax.pas has no syntax-error finding -- v1.4.5 parses every (d) construct.
  Negative control for the guard itself: run it with -Exe on a 1.48.0-alpha engine: B2 and A1 FAIL,
  the rest PASS.

  Usage: pwsh -File tests\autotest\run_grammar_shape_audit.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$fx = Join-Path $Repo 'tests\fixtures\grammar-shape-audit'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name $Detail" -ForegroundColor Red; $script:Failed = $true }
}
# Line of the first source line that contains $Text (1-based); a missing text is a broken fixture.
function Get-GaLine([string]$File, [string]$Text) {
  $hit = Select-String -Path $File -SimpleMatch -Pattern $Text | Select-Object -First 1
  if (-not $hit) { throw "fixture $File lost the line '$Text'" }
  return $hit.LineNumber
}
# lint --json is a bare array of findings (rule, start_line, ...); an empty run prints [] or nothing.
function Get-GaFindings([string[]]$LintArgs) {
  $raw = & $exePath @LintArgs 2>$null
  $txt = ($raw -join "`n").Trim()
  if ($txt -eq '') { return ,@() }
  return ,@($txt | ConvertFrom-Json)
}
function Test-GaHit($Findings, [string]$Rule, [int]$Line) {
  return [bool](@($Findings | Where-Object { $_.rule -eq $Rule -and $_.start_line -eq $Line }).Count -gt 0)
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ga-shape-" + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
try {
  # ---- (b) store-backed: is-always-true through TRefTypeScan.WrittenType ----
  $isDir = Join-Path $fx 'isdotted'
  $isPas = Join-Path $isDir 'GA_IsDotted.pas'
  $db = Join-Path $tmp 'isdotted.sqlite'
  & $exePath index $isDir --db $db 2>&1 | Out-Null
  $f = Get-GaFindings @('lint', $isPas, '--db', $db, '--rule', 'is-always-true', '--json')
  Check 'B1 is-always-true on `is TBase` (positive control)' (Test-GaHit $f 'is-always-true' (Get-GaLine $isPas 'pLeaf is TBase then'))
  Check 'B2 is-always-true on `is GA_IsDotted.TBase` (typerefDot)' (Test-GaHit $f 'is-always-true' (Get-GaLine $isPas 'pLeaf is GA_IsDotted.TBase then'))
  Check 'B3 is-always-true on `is TBase and pFlag` (grouping)' (Test-GaHit $f 'is-always-true' (Get-GaLine $isPas 'pLeaf is TBase and pFlag'))
  Check 'B4 no is-always-true on `is TOther` (negative control)' (-not (Test-GaHit $f 'is-always-true' (Get-GaLine $isPas 'pLeaf is TOther then')))

  # ---- (a) if..else is ifElse ----
  $ifPas = Join-Path $fx 'GA_IfElse.pas'
  $f = Get-GaFindings @('lint', $ifPas, '--rule', 'constant-condition,else-after-exit,identical-then-else', '--json')
  Check 'A1 constant-condition on `if True then .. else ..`' (Test-GaHit $f 'constant-condition' (Get-GaLine $ifPas 'if True then DoA else DoB'))
  Check 'A1 constant-condition on `if False then .. else ..`' (Test-GaHit $f 'constant-condition' (Get-GaLine $ifPas 'if False then DoA else DoB'))
  Check 'A2 else-after-exit on `if .. then Exit else DoB`' (Test-GaHit $f 'else-after-exit' (Get-GaLine $ifPas 'if pFlag then Exit else DoB'))
  Check 'A2 identical-then-else on `if .. then DoA else DoA`' (Test-GaHit $f 'identical-then-else' (Get-GaLine $ifPas 'if pFlag then DoA else DoA'))

  # ---- (c) comparison grouping ----
  $binPas = Join-Path $fx 'GA_Binary.pas'
  $f = Get-GaFindings @('lint', $binPas, '--rule', 'not-comparison-precedence,unsigned-compare-always-true', '--json')
  Check 'C1 not-comparison-precedence on `not pA < pB`' (Test-GaHit $f 'not-comparison-precedence' (Get-GaLine $binPas 'if not pA < pB then'))
  Check 'C1 unsigned-compare-always-true on `pW < 0` (positive control)' (Test-GaHit $f 'unsigned-compare-always-true' (Get-GaLine $binPas 'if pW < 0 then'))
  Check 'C1 no unsigned-compare-always-true on `pA + pW < 0`' (-not (Test-GaHit $f 'unsigned-compare-always-true' (Get-GaLine $binPas 'if pA + pW < 0 then')))

  # ---- (d) newly parsing constructs ----
  $newPas = Join-Path $fx 'GA_NewSyntax.pas'
  $f = Get-GaFindings @('lint', $newPas, '--json')
  $syn = @($f | Where-Object { $_.rule -eq 'syntax-error' -or $_.rule -eq 'parser-error' })
  Check 'D1 GA_NewSyntax.pas parses (no syntax-error / parser-error)' ($syn.Count -eq 0) ("lines: " + (($syn | ForEach-Object { $_.start_line }) -join ','))
  Check 'D1 positive control: the unit is linted (unprotected-object-free fires)' (@($f | Where-Object { $_.rule -eq 'unprotected-object-free' }).Count -gt 0)
}
finally {
  try { [IO.Directory]::Delete($tmp, $true) } catch { Write-Host "note: temp dir kept: $tmp" }
}
if ($script:Failed) { Write-Host 'run_grammar_shape_audit: FAIL'; exit 1 }
Write-Host 'run_grammar_shape_audit: PASS'
exit 0
