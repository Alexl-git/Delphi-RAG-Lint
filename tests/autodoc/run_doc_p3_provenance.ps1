<#
  run_doc_p3_provenance.ps1 -- Auto-Document Phase 3, Task 1: uniform
  <!-- drag-lint:auto --> provenance marker; delete the Observed: content sniff.

  Fixture fixtures\docp3\provenance.pas:
    * Marked(const AText: string): Integer -- UNDOCUMENTED. A fresh managed
      comment is generated; its <returns> tag must carry the marker as the
      FIRST characters of its text content (immediately after the opening
      tag), exactly once.
    * HandWritten: Integer -- ALREADY carries a hand-written comment whose
      <returns> text happens to start with the word "Observed:" (prose, not
      engine output). Pre-T1, StartsText('Observed:', ...) misclassified this
      as MANAGED content and silently overwrote it on every `document --apply`.
      Post-T1, ownership is marker-keyed only: this tag carries no AUTO_MARK,
      so it must survive byte-identical.

  v(ADP3 T3) update -- marker-on-<param> can no longer be demonstrated here,
  by design: a fresh comment never carries a <param> skeleton at all (Rule 2:
  AText has no hand-written description, and no harvester for params exists
  or ever will -- see the T3 report), so a MARKED, CONTENT-BEARING <param> is
  now categorically impossible, in this fixture or any other. Marker coverage
  for a tag that DOES legitimately survive with content moves entirely to
  <returns> (assertion 2 below, unaffected by T3 since Marked has a real
  mined return case). Assertion 1 is rewritten to assert the T3 consequence
  directly: Marked gets NO <param name="AText"> tag at all.

  Drives `index` -> `document --unit --apply` and asserts:
    1. v(ADP3 T3): Marked has NO <param name="AText"> tag at all (nothing
       hand-written to carry -- see the update note above).
    2. Marked's <returns> line carries exactly one <!-- drag-lint:auto -->
       immediately after the opening tag.
    3. HandWritten's <summary> and <returns> lines are byte-identical to the
       fixture (no marker added; the hand-written Observed:-prefixed prose is
       neither adopted as managed nor rewritten; that same prose string is not
       duplicated into a separate Returns: fact line -- the real mined return
       case, "1", is a legitimately DIFFERENT fact and may appear on its own
       line, same as the existing Doubler precedent in run_doc_returns_merge).
    4. Idempotency: reindex + a second --apply leaves the file byte-identical.
    5. Every emitted /// line is 7-bit ASCII.

  Review-fix regression (the presentation-layer strip originally covered only
  1 of 5 display surfaces): 6. `context --task "modify provenance.Marked"
  --format md` never leaks the literal 'drag-lint:auto' ownership token, and
  its Remarks section shows the facts TEXT ("Calls: Length") with the
  AUTO_BEGIN/END fence markers stripped (finding 1b) -- Marked already
  carries both a managed tag AND a managed facts block, so this is a REAL
  assertion against a REAL engine-emitted symbol, not a fixture string.
  7. Same no-leak check on `provenance.HandWritten`'s context bundle.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\provenance.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3provenance'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'provenance.pas'
$db     = Join-Path $scratch 'docp3provenance.sqlite'
Copy-Item $fixture $target -Force

# Returns the contiguous run of ///-prefixed lines immediately above the FIRST
# line matching $declPattern (the interface declaration -- always the earlier
# of the two textually-identical free-function decl/impl signature lines,
# since interface precedes implementation in a well-formed unit). '' if the
# declaration is not found.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return ($blockLines -join "`n")
}

$MARK = '<!-- drag-lint:auto -->'

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # --- Marked: fresh managed comment; returns carries the marker ---
  $markedBlock = Get-DocBlockAbove $lines '^function Marked\(const AText: string\): Integer;'
  Check 'Marked decl found' ($null -ne $markedBlock)

  # v(ADP3 T3): AText has no hand-written description and no harvester exists
  # for params, so the fresh comment carries NO <param name="AText"> tag at
  # all -- see this file's own update note above.
  $paramLine = $lines | Where-Object { $_ -match [regex]::Escape('<param name="AText">') } | Select-Object -First 1
  # v(PHASE A3, ruling D-3) reverses v(ADP3 T3) here: STRUCTURE ALWAYS, MEANING
  # ONLY WHERE THE SOURCE CARRIES IT. The old rule -- no <param> unless a human
  # wrote a description -- was itself the defect: doc-drift reported those tags as
  # missing while `document` refused to write them, so the two halves could never
  # converge. The tag is now emitted, engine-marked, with an EMPTY body.
  Check 'v(PHASE A3, D-3): Marked HAS a <param name="AText"> tag, engine-marked and empty' `
    (($null -ne $paramLine) -and ($paramLine -match [regex]::Escape('<param name="AText"><!-- drag-lint:auto --></param>'))) $paramLine

  $returnsLineMarked = $null
  if ($null -ne $markedBlock) {
    $returnsLineMarked = ($markedBlock -split "`n") | Where-Object { $_ -match '<returns>' } | Select-Object -First 1
  }
  Check 'Marked <returns> line found' ($null -ne $returnsLineMarked)
  if ($null -ne $returnsLineMarked) {
    $returnsMarkCount = ([regex]::Matches($returnsLineMarked, [regex]::Escape($MARK))).Count
    Check 'Marked <returns> carries exactly one marker' ($returnsMarkCount -eq 1)
    Check 'Marked <returns> marker sits immediately after the opening tag' `
      ($returnsLineMarked -match [regex]::Escape('<returns>' + $MARK))
  }

  # --- HandWritten: hand-written prose that merely starts with "Observed:" ---
  $handBlock = Get-DocBlockAbove $lines '^function HandWritten: Integer;'
  Check 'HandWritten decl found' ($null -ne $handBlock)

  Check 'HandWritten <summary> byte-identical to fixture (no marker added)' `
    (($lines | Where-Object { $_ -eq '/// <summary>Hand-written and must survive verbatim.</summary>' }).Count -eq 1)
  Check 'HandWritten <returns> byte-identical to fixture (NOT adopted/rewritten by the deleted sniff)' `
    (($lines | Where-Object { $_ -eq '/// <returns>Observed: this is hand-written prose that merely starts with the word.</returns>' }).Count -eq 1)
  Check 'HandWritten doc block carries no marker anywhere' `
    ($null -eq $handBlock -or (-not ($handBlock -match [regex]::Escape($MARK))))
  Check 'HandWritten hand-written prose is not duplicated into a Returns: fact line' `
    ($null -eq $handBlock -or (-not ($handBlock -match 'Returns:\s*Observed: this is hand-written')))

  # --- Phase 3 T1 REVIEW-FIX regression: the presentation-layer strip must --
  # --- also cover `context --format markdown` (finding 1), and must strip --
  # --- the AUTO_BEGIN/AUTO_END facts-fence, not just the leading marker    --
  # --- (finding 1b). Marked is the ideal host: it carries a managed        --
  # --- <summary>/<param>/<returns> (marker-only) AND a managed facts block --
  # --- ("Calls: Length" between a REAL AUTO_BEGIN/END fence in Remarks),   --
  # --- so ONE context call on a REAL, already-documented symbol exercises --
  # --- both fixes at once. Reindex first -- context reads the doc comment --
  # --- via the store, same staleness trap as hover/document (see          --
  # --- run_doc_idempotent.ps1's own header comment).
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $ctxMarked = (& $exePath context --task 'modify provenance.Marked' --db $db --format md 2>&1) -join "`n"
  Check 'context (Marked) exits 0' ($LASTEXITCODE -eq 0)
  Check 'T1 review fix: context markdown never leaks the AUTO_MARK ownership token' `
    ($ctxMarked -notmatch 'drag-lint:auto') $ctxMarked
  # Positive checks: a real assertion against real output, not a vacuous
  # absence check -- the cleaned Returns text is present, AND (1b) the
  # facts-FENCE is gone while the facts TEXT it wrapped survived.
  Check 'T1 review fix: context markdown shows the cleaned Returns line' `
    ($ctxMarked -match '\*\*Returns:\*\* Observed: Length\(AText\)\.') $ctxMarked
  Check 'T1 review fix (1b): context markdown Remarks keeps the facts TEXT with the fence markers stripped' `
    ($ctxMarked -match '\*\*Remarks:\*\* Calls: Length') $ctxMarked

  $ctxHandWritten = (& $exePath context --task 'modify provenance.HandWritten' --db $db --format md 2>&1) -join "`n"
  Check 'context (HandWritten) exits 0' ($LASTEXITCODE -eq 0)
  Check 'T1 review fix: context markdown never leaks the marker for hand-written content either' `
    ($ctxHandWritten -notmatch 'drag-lint:auto') $ctxHandWritten

  # --- Idempotency: reindex (facts are index-time) + re-apply -> no change ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical after reindex + 2nd apply' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  # --- Every emitted /// line is 7-bit ASCII ---
  $docLines = [IO.File]::ReadAllLines($target) | Where-Object { $_.TrimStart() -match '^///' }
  $nonAscii = $docLines | Where-Object { $_ -match '[^\x00-\x7F]' }
  Check 'every /// line is 7-bit ASCII' ($nonAscii.Count -eq 0)
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
