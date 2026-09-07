<#
  run_doc_p3_marked_prose_survives.ps1 -- session 74, owner ruling: D-4 wins.

  THE DEFECT. `document --apply` DELETED a <summary> that carried the bare
  AUTO_MARK but held a human's prose. The engine read the marker as "mine",
  found nothing harvested to refill the tag with, and applied v(ADP3 T3)'s
  omit-when-empty rule to words it had never written. Measured: 53 of the 54
  authored words the 91-file sweep still destroyed after session 73's
  stacked-region fix, all in DRagLint.Lint.Linter.pas (HarvestExceptions).

  THIS REVERSES A RECORDED ADJUDICATION, DELIBERATELY. run_doc_p3_markededit's
  assertion 1 pins the OPPOSITE for <summary> ("marked means engine-owned, full
  stop, regardless of what follows the marker"), and that ruling was itself the
  product of a coordinator reversal. The owner decided against it on 2026-09-06:
  ruling D-4 says a non-blank AUTO_MARK body is a HUMAN's text, and the engine
  must never silently delete a human's paragraph. markededit's assertion 1 is
  re-pinned to the new rule in the same change -- not weakened, not deleted.

  WHAT THE FIX IS NOT, AND WHY THIS FIXTURE HAS TWO SYMBOLS. The rule is NOT
  "marked + non-blank means the human's". The engine writes its own harvested
  summaries under that same bare marker -- 102 of them in src\ when this was
  written, and NOT ONE with a blank body -- so a blanket reading would freeze
  every engine summary in the corpus and make the refill arm unreachable. The
  actual rule is narrower:

      the engine may delete a marked <summary> only when there is nothing
      AUTHORED in it. Words the engine cannot replace are the human's: keep
      them, drop the marker (exactly D-4's "keep the words, drop the marker").

  So `Refreshable` is not decoration. It is the regression guard proving the fix
  stayed narrow: a marked summary the engine CAN refill still refreshes, marker
  intact.

  ASSERTION 3 IS THE POSITIVE CONTROL AND IS NOT OPTIONAL. An engine that
  stopped writing documentation altogether would satisfy "the prose survived".
  The control asserts the engine still wrote its facts for that SAME
  declaration in the SAME run. An edit-count assertion would be worthless here
  for the same reason -- see the INBOX note this closes.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\markedprose.pas')).Path

# The contiguous run of ///-prefixed lines immediately above the FIRST line
# matching $declPattern. $null when the declaration is not found. Same
# scan-upward idiom every sibling p3 runner uses.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return (($blockLines -join "`n") -replace '</?para>', '')
}

$MARK = '<!-- drag-lint:auto -->'
$SUM  = '<!-- drag-lint:auto sum -->'

$scratch = Join-Path C:\TEMP 'draglint_docp3markedprose'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'markedprose.pas'
$db     = Join-Path $scratch 'docp3markedprose.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --stubs --apply 2>$null | Out-Null
  Check 'document --unit --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)
  $whole = ($lines -join "`n")
  $nthBlock = Get-DocBlockAbove $lines '^function NothingToHarvest\(const AName: string\): Boolean;'
  Check 'NothingToHarvest decl found' ($null -ne $nthBlock)

  # --- 1. THE DEFECT: the authored prose survives -------------------------
  Check '1. authored prose SURVIVES --apply (the 53-word deletion is fixed)' `
    ($whole.Contains('that is the STATIC PREFIX, which is what a class name can'))
  Check '1. the whole authored sentence survives, not just a fragment' `
    ($whole.Contains('Ruling 2 is still open and gates stage 3, not this.'))
  Check '1. it survives as this declaration''s own <summary>' `
    ($null -ne $nthBlock -and $nthBlock -match '<summary>' -and $nthBlock -match 'STATIC PREFIX')

  # --- 2. ownership changed hands: the marker is dropped ------------------
  # D-4's second half. Leaving the marker would re-arm the same deletion on the
  # next run, so this is load-bearing, not cosmetic.
  #
  # THE `-match '<summary>'` CLAUSE IS WHAT MAKES THIS ASSERTION ABLE TO FAIL.
  # Written first as the bare "no marked summary in the block", it PASSED
  # against the unfixed engine -- which deletes the tag outright, so there is
  # no marked summary to find and the check is vacuously true. Caught by
  # red-checking the finished fixture against the unfixed build; a guard that
  # cannot fail for the right reason is not a guard.
  Check '2. the summary is PRESENT and its AUTO_MARK is DROPPED (ownership moved to the human)' `
    ($null -ne $nthBlock -and ($nthBlock -match '<summary>') `
      -and (-not ($nthBlock -match [regex]::Escape('<summary>' + $MARK))))

  # --- 3. POSITIVE CONTROL ------------------------------------------------
  # Without this, an engine that documented NOTHING would pass 1 and 2.
  Check '3. POSITIVE CONTROL: the engine still wrote its facts for the SAME decl in the SAME run' `
    ($null -ne $nthBlock -and $nthBlock -match [regex]::Escape('<!-- drag-lint:auto BEGIN -->'))
  Check '3. POSITIVE CONTROL: those facts are real (Calls: names Helper)' `
    ($null -ne $nthBlock -and $nthBlock -match 'Calls:[^<]*Helper')

  # --- 4. REGRESSION GUARD: the fix stayed narrow -------------------------
  # A marked summary the engine CAN refill must still be refreshed, marker
  # intact. This is what a blanket "marked+non-blank = the human's" would break,
  # across all 102 marked summaries in src\.
  $refBlock = Get-DocBlockAbove $lines '^function Refreshable\(const AName: string\): Boolean;'
  Check 'Refreshable decl found' ($null -ne $refBlock)
  # FLATTENED before matching. A harvested summary is engine PROSE, so it goes
  # through WrapEngineProse and can break across /// lines mid-sentence -- a
  # raw single-line regex then fails on output that is entirely correct, which
  # is how this assertion first read as "the refresh stopped working".
  $refFlat = (($refBlock -split "`n" | ForEach-Object { $_ -replace '^\s*///\s?','' }) -join ' ') -replace '\s+',' '
  Check '4. a REFILLABLE marked summary is refreshed from the harvest' `
    ($null -ne $refBlock -and $refFlat -match 'Real prose that the engine harvests into the summary')
  # THIS ASSERTION IS ALSO THE MIGRATION TEST, and that is why the fixture
  # still writes the LEGACY bare AUTO_MARK. Reaching the refill arm proves the
  # source comment still yields prose, so the tag is the engine's -- and it
  # comes back re-marked AUTO_SUM without anything having compared strings to
  # work that out. That is how all 102 legacy bare-marked summaries in src\
  # stay engine-owned instead of freezing. See AUTO_SUM's header.
  Check '4. ...and comes back marked AUTO_SUM -- the legacy bare marker MIGRATES, not freezes' `
    ($null -ne $refBlock -and $refBlock -match [regex]::Escape('<summary>' + $SUM))
  Check '4. ...and is no longer under the ambiguous bare AUTO_MARK' `
    ($null -ne $refBlock -and (-not ($refBlock -match [regex]::Escape('<summary>' + $MARK))))
  Check '4. ...and the stale engine text is GONE (the refill really happened)' `
    (-not $whole.Contains('Stale engine text from an earlier run.'))

  # --- 5. idempotency -----------------------------------------------------
  # The preserved summary is now unmarked, so run 2 must take the ordinary
  # preserve arm and change nothing. If ownership did not really transfer, this
  # is where it shows up.
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --stubs --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check '5. idempotent: byte-identical after reindex + 2nd apply' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  $linesAfter = [IO.File]::ReadAllLines($target)
  Check '5. the authored prose is still there after the SECOND apply' `
    (($linesAfter -join "`n").Contains('Ruling 2 is still open and gates stage 3, not this.'))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
