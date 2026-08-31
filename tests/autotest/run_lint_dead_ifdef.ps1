<#
  run_lint_dead_ifdef.ps1 -- the lint walk must not report findings inside a
  branch the preprocessor blanks.

  THE DEFECT (docs/INBOX-lint-reports-in-dead-ifdef-branches.md)
  --------------------------------------------------------------------------------
  The lint walk NEVER preprocesses -- not "preprocesses with the wrong defines".
  `DRagLint.Preprocess.Preprocess` had exactly three production callers, all on
  the INDEX side; no lint-path caller existed. So `lint` and `lint-all` parse raw
  bytes and happily report code the compiler never sees.

  Measured blast radius: 592 findings, 3.7% of ORM3 SERVER's whole lint-all, from
  ONE file -- COMMON\BASICSF.pas, whose 7,074-line body sits inside a
  never-defined {$IFDEF LEGACY_BDE_FORM}. The indexer extracts 1 symbol from it.

  Why that matters more than the count: the owner's standard is that a linter
  message is worth looking into. Findings in code that cannot compile are the
  purest form of noise, and they train a reader to skim.

  EVERY ASSERTION IS LINE-ANCHORED, and that is not incidental. All three
  findings here are the SAME rule, so counting by rule id would locate nothing --
  a sibling runner in this repo already passed against an unfixed build for
  exactly that reason. The fixture carries markers and the runner resolves them
  to line numbers, so an assertion cannot be satisfied from the wrong place.

  THE DANGER THE CONTROL EXISTS FOR is the opposite failure: suppressing LIVE
  code. That is worse than the noise, because it is silent.

  AND THAT FAILURE ALREADY EXISTS, which the parent note did not know. The
  tree-sitter grammar handles {$IFDEF}/{$ELSE} itself and unconditionally keeps
  the FIRST branch -- this fixture has four procedures and the raw parse yields
  three defProc nodes with ZERO error nodes. So today the walk reports the DEAD
  {$IFDEF} half and never sees the LIVE {$ELSE} half at all. The fix corrects
  both directions, and the {$ELSE} case is a hazard here, not a control.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dead-ifdef"
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

$src = @'
unit uDeadIfdef;

interface

implementation

type
  TThing = class
    Alpha: Integer;
  end;

var
  P, Q: TThing;

procedure LiveOne;
begin
  with P, Q do   // MARK_LIVE
    Alpha:= 1;
end;

{$IFDEF NEVER_DEFINED_IN_THIS_FIXTURE}
procedure DeadOne;
begin
  with P, Q do   // MARK_DEAD
    Alpha:= 2;
end;
{$ENDIF}

{$IFDEF NEVER_DEFINED_IN_THIS_FIXTURE}
procedure NotTakenBranch;
begin
  with P, Q do   // MARK_NOTTAKEN
    Alpha:= 3;
end;
{$ELSE}
procedure TakenElseBranch;
begin
  with P, Q do   // MARK_ELSE
    Alpha:= 4;
end;
{$ENDIF}

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$mainPas = Join-Path $WorkDir 'uDeadIfdef.pas'
[System.IO.File]::WriteAllText($mainPas, $src, [System.Text.Encoding]::ASCII)

# (iv) a sibling with NO directives at all -- its output must be identical with
# and without the change, which is what proves the transform is inert where
# there is nothing to blank.
$plain = @'
unit uPlainSibling;

interface

implementation

type
  TOther = class
    Beta: Integer;
  end;

var
  R, S: TOther;

procedure PlainOne;
begin
  with R, S do
    Beta:= 1;
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$plainPas = Join-Path $WorkDir 'uPlainSibling.pas'
[System.IO.File]::WriteAllText($plainPas, $plain, [System.Text.Encoding]::ASCII)

# Resolve markers -> line numbers, so no assertion can be satisfied from the
# wrong site.
$lines = Get-Content $mainPas
function LineOf([string]$marker) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match [regex]::Escape($marker)) { return $i + 1 } }
  return -1
}
$lLive     = LineOf 'MARK_LIVE'
$lDead     = LineOf 'MARK_DEAD'
$lNotTaken = LineOf 'MARK_NOTTAKEN'
$lElse     = LineOf 'MARK_ELSE'
Write-Host ("fixture lines -- live={0} dead={1} notTaken={2} else={3}" -f $lLive, $lDead, $lNotTaken, $lElse)
if ($lLive -lt 0 -or $lDead -lt 0 -or $lNotTaken -lt 0 -or $lElse -lt 0) {
  Write-Host 'FATAL: a marker went missing from the fixture' -ForegroundColor Red; exit 2
}

$out    = (& $Exe lint $mainPas --quiet 2>&1 | Out-String)
$outRaw = (& $Exe lint $mainPas --no-preprocess --quiet 2>&1 | Out-String)
$plainA = (& $Exe lint $plainPas --quiet 2>&1 | Out-String)
$plainB = (& $Exe lint $plainPas --no-preprocess --quiet 2>&1 | Out-String)

function FiredAt([string]$text, [int]$line) {
  [bool]($text -split "`r?`n" | Where-Object { $_ -match ("uDeadIfdef\.pas:" + $line + ":") -and $_ -match 'with-multiple-items' })
}

Write-Host ''
Write-Host 'THE FIX -- dead branches are not linted' -ForegroundColor Cyan
Check 'HAZARD: a finding inside a never-taken {$IFDEF} is NOT reported' `
  (-not (FiredAt $out $lDead)) "line $lDead"
Check 'HAZARD: nor is one inside the not-taken half of an {$IFDEF}/{$ELSE}' `
  (-not (FiredAt $out $lNotTaken)) "line $lNotTaken"

Write-Host ''
Write-Host 'THE OTHER HALF OF THE DEFECT -- live code silently NOT linted' -ForegroundColor Cyan
# MEASURED 2026-08-30, and it is not what the parent note describes. The
# tree-sitter grammar handles {$IFDEF}/{$ELSE} ITSELF and unconditionally keeps
# the FIRST branch: this fixture has four procedures and the raw parse produced
# three defProc nodes with ZERO error nodes. So before the fix the walk reported
# the dead {$IFDEF} half (line 32) and never saw the live {$ELSE} half at all.
#
# That direction is the dangerous one. Noise is visible and annoying; live code
# that is never linted is invisible, and no count anywhere goes up to say so.
Check 'HAZARD: the TAKEN {$ELSE} branch IS linted' `
  (FiredAt $out $lElse) "line $lElse  -- red before the fix: the grammar kept the IFDEF half and dropped this one"

Write-Host ''
Write-Host 'THE CONTROL -- live code must still be linted' -ForegroundColor Cyan
Write-Host '  (without this, every assertion above also passes with linting switched off)' -ForegroundColor DarkGray
Check 'CONTROL: the same shape in ordinary LIVE code fires' `
  (FiredAt $out $lLive) "line $lLive"

Write-Host ''
Write-Host 'THE ESCAPE HATCH -- --no-preprocess gives the flag real semantics on lint' -ForegroundColor Cyan
Check '--no-preprocess brings the dead-branch finding BACK' `
  (FiredAt $outRaw $lDead) "line $lDead  -- pins that the mechanism is the preprocessor, not a coincidence"
Check 'and still reports the live one' `
  (FiredAt $outRaw $lLive) "line $lLive"

Write-Host ''
Write-Host 'INERT WHERE THERE IS NOTHING TO BLANK' -ForegroundColor Cyan
Check 'a directive-free file lints identically with and without --no-preprocess' `
  ($plainA -eq $plainB) 'any difference means the transform is doing something to files it should not touch'
Check 'POSITIVE CONTROL: that file did produce a finding' `
  ($plainA -match 'with-multiple-items') 'two empty outputs would satisfy the equality above for the wrong reason'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
