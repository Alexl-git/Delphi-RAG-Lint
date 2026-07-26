<#
  run_doc_p3_decay.ps1 -- Auto-Document Phase 3, Task 3 (review follow-up,
  Concern 4): TDocumenter.BuildForSymbol's "existing comment decays to
  nothing -> delete" branch.

  v(ADP3 T3)'s omit-when-empty rule means MergeComment can return '' for a
  symbol that ALREADY has an existing doc comment -- every tag in it was
  engine-owned (marked), and whatever used to refill them (a harvested
  summary, a mined return case, index facts) is now empty too. Without a
  guard, BuildForSymbol would either write an empty comment or silently do
  nothing while leaving a now-meaningless stub on disk; the guard added in
  Task 3 detects Merged = '' and, when a prior comment existed, emits a
  single delete-only edit so the file ends up with NO comment there --
  cleanly, not a blank line, not an orphaned `///`. This was verified only
  by hand (an ad-hoc, uncommitted fixture) in the original Task 3 report;
  this is the committed regression test for that branch.

  Fixture fixtures\docp3\decay.pas, hand-authored with the marker ALREADY
  baked in (Task 2's static-fixture pattern -- no PRIOR `document` run
  needed to seed the marked state):
    * Noop2: a parameterless, callerless, return-less procedure whose ONLY
      existing doc-comment is a marked-and-empty <summary> (exactly the
      shape an OLDER drag-lint build would have written before Task 3, or
      that Task 3's own repair path would produce mid-decay). Nothing about
      Noop2 can ever refill it (no harvester, no return, no facts) --
      MergeComment returns '' for it, unconditionally.
    * Kept: a hand-written, UNMARKED <summary> on an otherwise-identical
      procedure (no params/return/facts either) -- proves the deletion is
      scoped to Noop2's own comment only: Kept has real (if minimal)
      content, so it is preserved untouched, not swept up by the same
      empty-merge guard.

  Drives `index` -> `document --unit --apply` and asserts, via an EXACT
  hand-computed expected-after text (byte-compare, Task 2 Scenario A style):
    1. Noop2's marked <summary> line is gone ENTIRELY -- no stray blank line
       left where it was, no orphaned `///` continuation.
    2. Kept's hand-written <summary> survives byte-identical, untouched.
    3. Every other line in the file (unit header, blank lines, declarations,
       implementation bodies) is unchanged.
    4. Idempotency: reindex + a second --apply reports edits=0/applied=false
       and leaves the file byte-identical (Noop2 stays undocumented; Kept
       stays documented -- a stable fixed point, not a repeating churn).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\decay.pas')).Path

# The exact hand-computed post-apply text: Noop2's marked <summary> line is
# gone (no stray blank line in its place -- the blank line that was ALREADY
# between 'interface' and the comment is the only one left); Kept's
# hand-written comment is untouched; everything else is unchanged. Written as
# an LF here-string then normalized to CRLF, matching every sibling fixture's
# own writing convention (e.g. run_doc_p3_strip_static.ps1's $ExpectedAfterA).
$ExpectedAfter = @'
unit decay;

interface

procedure Noop2;

/// <summary>Hand-written summary; must survive untouched.</summary>
procedure Kept;

implementation

procedure Noop2;
begin
end;

procedure Kept;
begin
end;

end.
'@
# PowerShell's @'...'@ here-string drops the FINAL newline immediately before
# the closing '@ delimiter -- re-add it so this matches the fixture's own
# trailing newline (TTextEditApplier.Apply preserves a trailing terminator
# when the original file had one, which this fixture does).
$ExpectedAfter = (($ExpectedAfter -replace "`r`n", "`n") -replace "`n", "`r`n") + "`r`n"

$scratch = Join-Path C:\TEMP 'draglint_docp3decay'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'decay.pas'
$db     = Join-Path $scratch 'docp3decay.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  $before = [IO.File]::ReadAllBytes($target)

  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $applyJson = (& $exePath document --unit $target --db $db --apply --json 2>$null) -join "`n"
  Check 'document --unit --apply exits 0' ($LASTEXITCODE -eq 0)
  Check 'apply: exactly one edit (Noop2''s delete-only span; Kept is unchanged)' `
    ($applyJson -match '"edits":1') $applyJson

  $afterApply = [IO.File]::ReadAllText($target)
  Check '1-3. whole-file result is byte-identical to the hand-computed expected text' `
    ($afterApply -ceq $ExpectedAfter) "actual length=$($afterApply.Length) expected length=$($ExpectedAfter.Length)"

  # Targeted checks in case the whole-file compare above ever needs updating --
  # these pin the SPECIFIC properties Concern 4 asked for, independent of the
  # exact surrounding text.
  $lines = [IO.File]::ReadAllLines($target)
  Check '1. Noop2''s marked <summary> line is completely gone' `
    (-not ($afterApply -match '<summary><!-- drag-lint:auto --></summary>'))
  Check '1. no orphaned bare ''///'' line anywhere' `
    (($lines | Where-Object { $_.Trim() -eq '///' }).Count -eq 0)
  Check '1. no stray double-blank-line introduced (Noop2 decl directly follows the interface blank line)' `
    ($afterApply -match "(?s)interface\r\n\r\nprocedure Noop2;")
  Check '2. Kept''s hand-written <summary> survives byte-identical' `
    (($lines | Where-Object { $_.Trim() -eq '/// <summary>Hand-written summary; must survive untouched.</summary>' }).Count -eq 1)

  # --- 4. Idempotency: reindex (Noop2 is now undocumented; Kept unchanged) ---
  $afterApplyBytes = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $reApplyJson = (& $exePath document --unit $target --db $db --apply --json 2>$null) -join "`n"
  Check '4. second apply reports edits=0' ($reApplyJson -match '"edits":0') $reApplyJson
  Check '4. second apply reports applied=false' ($reApplyJson -match '"applied":false') $reApplyJson
  $afterSecondBytes = [IO.File]::ReadAllBytes($target)
  Check '4. idempotent: file byte-identical after reindex + 2nd apply' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterSecondBytes,[byte[]]$afterApplyBytes))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
