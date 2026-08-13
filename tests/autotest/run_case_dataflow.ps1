<#
  run_case_dataflow.ps1 -- the CFG must model a `case` statement's SELECTOR and
  its ELSE ARM.

  THE TWO DEFECTS (2026-08-12, docs\PLAN-2026-08-12-case-dataflow-fix-and-datacopy-cycle.md
  Tasks 1 and 2). Both lived in the `if K = 'case'` block of
  src\analysis\DRagLint.Analysis.Cfg.pas, and both came from reading the parse
  tree's shape wrongly. The real shape, dumped rather than assumed:

      (case (kCase) <selector> (kOf) (caseCase ...)* (kElse) <stmt>* (kEnd))

  1. THE ELSE BODY WAS NEVER EMITTED. The handler added a bare
     `ACur -> JoinIdx` fall-through edge and stopped. So assignments inside
     `case..else` were invisible, and the CFG carried a path through the case
     that assigns nothing. Real casualty, tracked: YADF.Options.pas:593
     EncodingOf sets Result in every arm including the else, and
     function-result-not-set fired on it anyway.

  2. THE SELECTOR WAS NEVER ADDED. The handler took "the first named child that
     is not a caseCase" -- but KEYWORDS ARE NAMED NODES in this grammar, so that
     is the `case` keyword itself, and the loop then Break'd. Every read
     occurring in a case selector was invisible. Real casualty, tracked:
     write-only-local called CurLineLast "assigned but never read" at
     YADF.Layout.pas:3325, while YADF.Layout.pas:3512 reads it as
     `case CurLineLast of`.

  WHAT THIS TEST GUARDS, AND WHY HALF OF IT ASSERTS THE OPPOSITE
  --------------------------------------------------------------
  The cheap "fix" for defect 1 is to delete the fall-through edge, and the cheap
  "fix" for defect 2 is to stop reporting write-only-local near a case. Both
  would go green on the positive cases alone while silencing two real rules.
  So cases 2 and 5 below assert the findings STILL FIRE. They matter as much as
  the ones that assert silence -- more, if anything: a linter that has quietly
  stopped checking looks exactly like a clean codebase.

  Case 4 is the sharpest of the five. A local read ONLY inside the `case..else`
  body distinguishes "the else EDGE reaches the join" (which the old code did
  have) from "the else BODY is in the graph" (which it did not). An edge-only
  fix passes cases 1-3 and fails case 4.

  These are mock fixtures by explicit owner ruling -- a whole-YADF run is not
  needed to prove either fix.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-case-dataflow"
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# One fixture per case, so "the rule fired at all" IS the assertion -- no
# line-number bookkeeping to drift.
function New-Fixture([string]$Name, [string]$Body) {
  $p = Join-Path $WorkDir "$Name.pas"
  Write-Ascii $p $Body
  return $p
}

# Returns the findings of one rule on one file, as objects.
# The leading comma is load-bearing: PowerShell unrolls a returned empty array
# into $null, and "no findings" is the EXPECTED answer for three of the five
# cases here -- without it, a correct silent run looks like a broken one.
function Get-Findings([string]$Path, [string]$Rule) {
  $raw = (& $Exe lint $Path --rule $Rule --json 2>$null) -join "`n"
  if (-not $raw.Trim()) { return ,@() }
  try { return ,@($raw | ConvertFrom-Json) } catch { return $null }
}

# ---------------------------------------------------------------------------
# 1) case..else where EVERY arm assigns Result -> silence.
#    Shape copied from the tracked reproducer, YADF.Options.pas:593 EncodingOf.
#    Result is Integer on purpose: a managed return type (string) opts out of
#    this rule entirely via IsManagedType, which would make the case vacuous.
# ---------------------------------------------------------------------------
$f1 = New-Fixture 'CaseElseAllArms' @"
unit CaseElseAllArms;

interface

type
  TKind = (kA, kB, kC);

function ValueOf(const AKind: TKind): Integer;

implementation

function ValueOf(const AKind: TKind): Integer;
begin
  case AKind of
    kA: Result := 1;
    kB: Result := 2;
  else
    Result := 3;
  end;
end;

end.
"@

Write-Host 'Case 1: case..else assigning Result in every arm' -ForegroundColor Cyan
$r1 = Get-Findings $f1 'function-result-not-set'
Check 'lint emitted parseable JSON' ($null -ne $r1)
# Filtered by message, not by count: `lint --rule X` also lets some other rules
# through (magic-literal fires on the case labels here), so a bare count would
# be asserting something this test does not own.
Check 'no function-result-not-set when the else arm assigns Result' (
  ($r1 | Where-Object { $_.message -match 'Function Result' }).Count -eq 0) `
  (($r1 | ForEach-Object { $_.message }) -join ' | ')

# ---------------------------------------------------------------------------
# 2) REGRESSION GUARD -- a case with NO else really does leave a path unset.
#    A fix that simply deletes the fall-through edge would silence this.
# ---------------------------------------------------------------------------
$f2 = New-Fixture 'CaseNoElseGap' @"
unit CaseNoElseGap;

interface

type
  TKind = (kA, kB, kC);

function ValueOf(const AKind: TKind): Integer;

implementation

function ValueOf(const AKind: TKind): Integer;
begin
  case AKind of
    kA: Result := 1;
    kB: Result := 2;
  end;
end;

end.
"@

Write-Host ''
Write-Host 'Case 2: case with NO else leaves Result unset on the no-match path' -ForegroundColor Cyan
$r2 = Get-Findings $f2 'function-result-not-set'
Check 'function-result-not-set STILL fires without an else arm' (
  ($r2 | Where-Object { $_.message -match 'Function Result' }).Count -ge 1) `
  (($r2 | ForEach-Object { $_.message }) -join ' | ')

# ---------------------------------------------------------------------------
# 3) A local whose ONLY read is the case selector -> silence.
# ---------------------------------------------------------------------------
$f3 = New-Fixture 'CaseSelectorRead' @"
unit CaseSelectorRead;

interface

procedure Classify(const AInput: Integer);

implementation

procedure Classify(const AInput: Integer);
var
  LKind: Integer;
begin
  LKind := AInput;
  case LKind of
    0: Writeln('zero');
    1: Writeln('one');
  end;
end;

end.
"@

Write-Host ''
Write-Host 'Case 3: local read ONLY in the case selector' -ForegroundColor Cyan
$r3 = Get-Findings $f3 'write-only-local'
Check 'no write-only-local for a variable read by the selector' (
  ($r3 | Where-Object { $_.message -match 'LKind' }).Count -eq 0) `
  (($r3 | ForEach-Object { $_.message }) -join ' | ')

# ---------------------------------------------------------------------------
# 4) THE SHARP ONE -- a local read ONLY inside the case..else BODY.
#    Passes only if the else body is emitted into the graph. An edge-only fix
#    (delete the fall-through, add nothing) fails right here.
# ---------------------------------------------------------------------------
$f4 = New-Fixture 'CaseElseBodyRead' @"
unit CaseElseBodyRead;

interface

procedure Report(const AInput: Integer);

implementation

procedure Report(const AInput: Integer);
var
  LOnlyInElse: Integer;
begin
  LOnlyInElse := AInput * 2;
  case AInput of
    0: Writeln('zero');
  else
    Writeln(LOnlyInElse);
  end;
end;

end.
"@

Write-Host ''
Write-Host 'Case 4: local read ONLY inside the case..else BODY' -ForegroundColor Cyan
$r4 = Get-Findings $f4 'write-only-local'
Check 'no write-only-local for a variable read only in the else body' (
  ($r4 | Where-Object { $_.message -match 'LOnlyInElse' }).Count -eq 0) `
  (($r4 | ForEach-Object { $_.message }) -join ' | ')

# ---------------------------------------------------------------------------
# 5) REGRESSION GUARD -- a local that genuinely is never read.
#    Proves cases 3 and 4 were not won by switching the rule off near a case.
# ---------------------------------------------------------------------------
$f5 = New-Fixture 'CaseNeverRead' @"
unit CaseNeverRead;

interface

procedure Ignore(const AInput: Integer);

implementation

procedure Ignore(const AInput: Integer);
var
  LNeverRead: Integer;
begin
  LNeverRead := AInput;
  case AInput of
    0: Writeln('zero');
  else
    Writeln('other');
  end;
end;

end.
"@

Write-Host ''
Write-Host 'Case 5: local assigned and genuinely never read, beside a case..else' -ForegroundColor Cyan
$r5 = Get-Findings $f5 'write-only-local'
Check 'write-only-local STILL fires for a truly unread local' (
  ($r5 | Where-Object { $_.message -match 'LNeverRead' }).Count -ge 1) `
  (($r5 | ForEach-Object { $_.message }) -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
