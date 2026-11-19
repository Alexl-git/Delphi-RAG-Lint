<#
  run_v152_BK-OWNGATED.ps1 -- lane BK-OWNGATED (1.52, owner ruling 2026-11-18 03:46: U5 IN).

  GA-1. cyclomatic-complexity, cognitive-complexity and the autodoc Complexity fact (all three read
  TAstChecker.CyclomaticOf / the cognitive Score) did not count an if-EXPRESSION
  (`X := if C then A else B`, grammar node exprIf) as a decision point. Since grammar v1.4.4 exprIf is
  ONLY the expression form, so counting it is exact. Cyclomatic: +1 per exprIf. Cognitive: 1 + nesting,
  and an `else if` arm of an if-expression is the hybrid +1 (no nesting), as for the statement form.

  EX1. by-value-arg-before-assignment (OFF since 1.46) is folded into the ON rule
  used-before-assignment: `G.Take(X)` with X unassigned now reports under used-before-assignment
  (error when no path assigned it, warning when some path did) in a default run, and the old id is
  gone from the catalogue.

  Every negative has a positive control beside it, so a dead rule cannot pass.

  Usage: pwsh -File tests\autotest\run_v152_BK-OWNGATED.ps1 [-Exe <drag-lint.exe>] [-RulesDir <dir>]
#>
[CmdletBinding()]
param(
  [string]$Exe      = '',
  [string]$RulesDir = '',
  [string]$WorkDir  = "C:\TEMP\draglint_bk_owngated_$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $RulesDir) { $RulesDir = "$PSScriptRoot\..\..\rules" }
$ErrorActionPreference = 'Stop'; $script:fail = $false; $script:pass = 0; $script:failed = 0
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if ($ok) { $script:pass++ } else { $script:failed++; if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }
function Findings([string]$Json) {
  $i = $Json.IndexOf('['); if ($i -lt 0) { return ,@() }
  $a = @($Json.Substring($i) | ConvertFrom-Json)
  $o = @()
  foreach ($f in $a) {
    $m = [regex]::Match([string]$f.message, '"([^"]+)"')
    $o += [pscustomobject]@{ rule = [string]$f.rule; name = $m.Groups[1].Value; line = [int]$f.start_line;
                             sev = [string]$f.severity; msg = [string]$f.message }
  }
  return ,$o
}

$GaUnit = @'
unit uGaExpr;
interface
function TwoExprIf(A, B: Boolean): Integer;
function StmtIf(A: Boolean): Integer;
function NoBranch: Integer;
function ExprElseIf(A, B: Boolean): Integer;
function NestedExprIf(A, B: Boolean): Integer;
implementation
function TwoExprIf(A, B: Boolean): Integer;
begin
  Result := (if A then 1 else 2) + (if B then 3 else 4);
end;
function StmtIf(A: Boolean): Integer;
begin
  if A then Result := 1 else Result := 2;
end;
function NoBranch: Integer;
begin
  Result := 7;
end;
function ExprElseIf(A, B: Boolean): Integer;
begin
  Result := if A then 1 else if B then 2 else 3;
end;
function NestedExprIf(A, B: Boolean): Integer;
begin
  if A then
    Result := if B then 1 else 2
  else
    Result := 0;
end;
end.
'@

$ExTypes = @'
unit uBvTypes;
interface
type
  TGetter = class
  public
    procedure Take(V: Integer);
    procedure TakeC(const V: Integer);
    procedure GetOut(out V: Integer);
  end;
implementation
procedure TGetter.Take(V: Integer); begin end;
procedure TGetter.TakeC(const V: Integer); begin end;
procedure TGetter.GetOut(out V: Integer); begin V := 1; end;
end.
'@

$ExUse = @'
unit uBvUse;
interface
uses uBvTypes;
procedure Use(const V: Integer);
procedure Cases(G: TGetter; B: Boolean);
implementation
procedure Use(const V: Integer); begin end;
procedure Cases(G: TGetter; B: Boolean);
var
  tbvDefinite, tbvConst, tbvMay: Integer;
  cbvAssigned, cbvOut, cbvBare: Integer;
begin
  G.Take(tbvDefinite);
  G.TakeC(tbvConst);
  if B then tbvMay := 1;
  G.Take(tbvMay);
  cbvAssigned := 1;
  G.Take(cbvAssigned);
  G.GetOut(cbvOut);
  G.Take(cbvOut);
  Use(cbvBare);
end;
end.
'@

try {
  $exePath = (Resolve-Path $Exe).Path
  $rules   = (Resolve-Path $RulesDir).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $ga = Join-Path $WorkDir 'ga'; $ex = Join-Path $WorkDir 'ex'
  [void](New-Item -ItemType Directory -Path $ga, $ex -Force)

  # ---------------- GA-1 ----------------
  $gaPas = Join-Path $ga 'uGaExpr.pas'
  Write-Ascii $gaPas $GaUnit
  $cfg = Join-Path $ga 'cfg.json'
  Write-Ascii $cfg '{ "thresholds": { "cyclomatic-complexity": 0, "cognitive-complexity": 0 } }'
  $gaLines = [IO.File]::ReadAllLines($gaPas)
  Push-Location $ga
  try { $gf = Findings (& { $ErrorActionPreference = 'Continue'; & $exePath lint $gaPas --config $cfg --rules-dir $rules --rule 'cyclomatic-complexity,cognitive-complexity' --json 2>$null } | Out-String) }
  finally { Pop-Location }
  function Score([string]$Rule, [string]$Routine) {
    foreach ($f in $gf) {
      if ($f.rule -ne $Rule) { continue }
      if ($gaLines[$f.line - 1] -notmatch ("\b{0}\b" -f $Routine)) { continue }
      $m = [regex]::Match($f.msg, 'complexity (\d+)')
      if ($m.Success) { return [int]$m.Groups[1].Value }
    }
    return 0
  }
  $CY = 'cyclomatic-complexity'; $CG = 'cognitive-complexity'
  foreach ($r in 'TwoExprIf', 'StmtIf', 'NoBranch', 'ExprElseIf', 'NestedExprIf') {
    Write-Host ("  {0}: cyclomatic={1} cognitive={2}" -f $r, (Score $CY $r), (Score $CG $r))
  }
  # positive controls: the statement forms were always counted
  Check 'GA control: statement if is cyclomatic 2'      ((Score $CY 'StmtIf') -eq 2) ''
  Check 'GA control: no branch is cyclomatic 1'         ((Score $CY 'NoBranch') -eq 1) ''
  Check 'GA control: statement if is cognitive 1'       ((Score $CG 'StmtIf') -eq 1) ''
  # the fix
  Check 'GA cyclomatic counts each if-expression (2 -> 3)'        ((Score $CY 'TwoExprIf') -eq 3) ''
  Check 'GA cyclomatic counts an else-if expression chain (3)'    ((Score $CY 'ExprElseIf') -eq 3) ''
  Check 'GA cyclomatic counts if-expression under an if (3)'      ((Score $CY 'NestedExprIf') -eq 3) ''
  Check 'GA cognitive: two flat if-expressions = 2'               ((Score $CG 'TwoExprIf') -eq 2) ''
  Check 'GA cognitive: else-if expression arm is hybrid (+1) = 2' ((Score $CG 'ExprElseIf') -eq 2) ''
  Check 'GA cognitive: if-expression nested in an if pays nesting = 3' ((Score $CG 'NestedExprIf') -eq 3) ''

  # ---------------- EX1 ----------------
  Write-Ascii (Join-Path $ex 'uBvTypes.pas') $ExTypes
  $use = Join-Path $ex 'uBvUse.pas'
  Write-Ascii $use $ExUse
  $db = Join-Path $WorkDir 'bv.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $ex --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  Check 'EX index built' (Test-Path $db) $db
  $UBA = 'used-before-assignment'; $OLD = 'by-value-arg-before-assignment'
  Push-Location $WorkDir
  try {
    $dflt = Findings (& { $ErrorActionPreference = 'Continue'; & $exePath lint $use --db $db --rules-dir $rules --json 2>$null } | Out-String)
    $only = Findings (& { $ErrorActionPreference = 'Continue'; & $exePath lint $use --db $db --rules-dir $rules --rule $UBA --json 2>$null } | Out-String)
    $allT = (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --rules-dir $rules --library-db none --output (Join-Path $WorkDir 'la.txt') 2>&1 | ForEach-Object { "$_" } } | Out-String)
    $allR = if (Test-Path (Join-Path $WorkDir 'la.txt')) { [IO.File]::ReadAllText((Join-Path $WorkDir 'la.txt')) } else { '' }
    $cat  = (& { $ErrorActionPreference = 'Continue'; & $exePath rules --json --rules-dir $rules 2>$null } | Out-String)
  }
  finally { Pop-Location }
  function Has($F, [string]$Rule, [string]$Name, [string]$Sev = '') {
    @($F | Where-Object { $_.rule -eq $Rule -and $_.name -eq $Name -and ($Sev -eq '' -or $_.sev -eq $Sev) }).Count -gt 0
  }
  Write-Host ("  default {0}: {1}" -f $UBA, ((@($dflt | Where-Object { $_.rule -eq $UBA } | ForEach-Object { "$($_.name)/$($_.sev)" })) -join ','))
  Check 'EX control: bare Use(cbvBare) reports under used-before-assignment' (Has $dflt $UBA 'cbvBare') ''
  Check 'EX default run: G.Take(tbvDefinite) reports under used-before-assignment, error' (Has $dflt $UBA 'tbvDefinite' 'error') ''
  Check 'EX default run: G.TakeC(tbvConst) reports (const counts as by value)' (Has $dflt $UBA 'tbvConst') ''
  Check 'EX default run: possible path is a warning' (Has $dflt $UBA 'tbvMay' 'warning') ''
  $tbv = @($dflt | Where-Object { $_.rule -eq $UBA -and $_.name -eq 'tbvDefinite' })
  $exLines = [IO.File]::ReadAllLines($use)
  Check 'EX reports once, on the call line' (($tbv.Count -eq 1) -and ($exLines[$tbv[0].line - 1] -match 'G\.Take\(tbvDefinite\)')) ($tbv | Out-String)
  foreach ($n in 'cbvAssigned', 'cbvOut') { Check "EX negative: $n silent" (-not (Has $dflt $UBA $n)) '' }
  Check 'EX the old id never appears in a finding' (@($dflt | Where-Object { $_.rule -eq $OLD }).Count -eq 0) ''
  Check 'EX --rule used-before-assignment runs the by-value pass' (Has $only $UBA 'tbvDefinite') ''
  Check 'EX lint-all default reports the by-value site' (($allT + $allR) -match 'used-before-assignment: Local "tbvDefinite"') $allR; Check 'EX control: lint-all default reports the bare site' (($allT + $allR) -match 'used-before-assignment: Local "cbvbare"') ''
  Check 'EX catalogue: old id removed'           ($cat -notmatch [regex]::Escape('"' + $OLD + '"')) ''
  Check 'EX catalogue: used-before-assignment listed' ($cat -match [regex]::Escape('"' + $UBA + '"')) ''
}
catch { Write-Host "[FAIL] exception: $($_.Exception.Message)"; $script:fail = $true; $script:failed++ }
finally { if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (work dir left: $WorkDir)" } } }

Write-Host ("run_v152_BK-OWNGATED: {0} pass, {1} fail" -f $script:pass, $script:failed)
if ($script:fail) { Write-Host 'run_v152_BK-OWNGATED: FAIL'; exit 1 }
Write-Host 'run_v152_BK-OWNGATED: PASS'; exit 0
