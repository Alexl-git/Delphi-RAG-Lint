<#
  run_doc_p3_strip_collision.ps1 -- Auto-Document Phase 3 T3d2, D8 review:
  pins the fixes for CRITICAL 1 (region-collision corruption) and IMPORTANT 2
  (writes to files the report never names), review round 2's IMPORTANT (the
  cross-file skip must be reported, not silent), and review round 3's
  IMPORTANT (the skip must be reported in --json too, always present,
  including when zero -- not just in the human-readable text-mode note).

  PART A -- CRITICAL 1: two declarations sharing one qualified name (Delphi
  `overload;`) on CONSECUTIVE source lines, with an engine-owned doc comment
  above only the FIRST of the pair (exactly what `document --qname X --apply`
  produces for an overloaded routine, since it always targets Syms[0] --
  verified directly against this fixture below, not assumed). Doc.Strip.pas's
  gap window ([ADeclLine-2, ADeclLine-1]) does not check that the intervening
  line is blank, so BOTH declaration lines resolve to the SAME physical doc
  region -- confirmed live in fixtures\docp3\strip_collision.pas, not a
  contrived shape: reachable in 311 measured same-file adjacent-overload pairs
  in the real ORM3 index (see task-3d2-report.md). Before the fix,
  DoDocumentStripQName unioned both symbols' delete edits with no
  de-duplication; TTextEditApplier.Apply has no overlap detection, so applying
  the identical delete twice removed whatever shifted up into the freed range
  on the second pass -- the declaration lines themselves. This runner proves
  the fixed de-duplication (on the RESOLVED REGION, not the symbol) reports
  the correct, non-doubled counts and leaves both declarations intact, with a
  byte-identical round-trip back to the pre-apply source.

  PART B -- IMPORTANT 2 + review round 2's IMPORTANT: a qualified name that
  resolves across TWO DIFFERENT FILES (two units sharing a name, e.g. the same
  unit duplicated per project tree -- 34 such cases measured in the real ORM3
  index). Proves --qname --strip touches ONLY Syms[0]'s own file and reports
  exactly that file in its summary, AND that the file it does NOT touch is
  named in a note -- silently leaving a match unstripped is exactly the
  broken-round-trip class D8 was raised to close, only relocated from
  same-file overloads to cross-file matches.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\strip_collision.pas')).Path

Push-Location C:\TEMP
try {

# ===========================================================================
# PART A -- CRITICAL 1: same-file, consecutive-line overload collision
# ===========================================================================
Write-Host ''
Write-Host '=== PART A: CRITICAL 1 -- consecutive-line overloads sharing one doc region ===' -ForegroundColor Cyan

$scratchA = Join-Path C:\TEMP 'draglint_docp3stripcollision_a'
if (Test-Path $scratchA) { Remove-Item $scratchA -Recurse -Force }
New-Item -ItemType Directory -Path $scratchA | Out-Null
$targetA = Join-Path $scratchA 'strip_collision.pas'
$dbA     = Join-Path $scratchA 'a.sqlite'
Copy-Item $fixture $targetA -Force
$pristineBytes = [IO.File]::ReadAllBytes($targetA)

& $exePath index $scratchA --db $dbA 2>$null | Out-Null
Check 'A: index exits 0' ($LASTEXITCODE -eq 0)

# v(ADP3 T3d2 D8 review round 2, minor 3): the collision this runner exists to
# exercise depends on strip_collision.Combine resolving to exactly TWO rows.
# If an indexer change ever collapsed the two overloads into one row, every
# check below would still pass while no longer testing the collision at all
# -- assert the premise the same way PART B already asserts its own
# ("dup.Widget resolves across exactly TWO files").
$combineRowsOut = (& $exePath query --name Combine --db $dbA --json 2>$null) -join "`n"
Check 'A: query --name Combine exits 0' ($LASTEXITCODE -eq 0)
Check 'A FIXTURE: strip_collision.Combine resolves to exactly TWO rows' `
  ((([regex]::Matches($combineRowsOut, '"qualified_name"\s*:\s*"strip_collision\.Combine"')).Count) -eq 2) $combineRowsOut

# document --qname always targets Syms[0] only (TDocumenter.BuildFor takes a
# bare qualified name, not a resolved row -- see TDocBatch.DocumentUnit's own
# "Bug A" comment for why the BATCH path had to change this). For an
# overloaded routine that means only the FIRST overload's declaration ever
# gets an engine-written comment through --qname -- which, for two
# declarations on consecutive lines, is exactly the shape that collides.
& $exePath document --qname strip_collision.Combine --db $dbA --apply --json 2>$null | Out-Null
Check 'A: document --qname --apply exits 0' ($LASTEXITCODE -eq 0)

$afterApplyLines = [IO.File]::ReadAllLines($targetA)
$declAIx = -1; $declBIx = -1
for ($i = 0; $i -lt $afterApplyLines.Count; $i++) {
  if ($afterApplyLines[$i] -match '^function Combine\(A: Integer\): Integer; overload;') { $declAIx = $i }
  if ($afterApplyLines[$i] -match '^function Combine\(A, B: Integer\): Integer; overload;') { $declBIx = $i }
}
Check 'A FIXTURE: both overload declarations are present after --apply' ($declAIx -ge 0 -and $declBIx -ge 0) "declAIx=$declAIx declBIx=$declBIx"
Check 'A FIXTURE: the two declarations are on CONSECUTIVE lines (no blank/comment between them)' `
  ($declAIx -ge 0 -and $declBIx -eq $declAIx + 1) "declAIx=$declAIx declBIx=$declBIx"
# The collision precondition, proven rather than assumed: an engine comment
# sits directly above the FIRST overload, and NOTHING sits directly above
# the second.
Check 'A FIXTURE: an engine-owned comment sits directly above the FIRST overload' `
  ($declAIx -ge 1 -and $afterApplyLines[$declAIx - 1].TrimStart().StartsWith('///'))
Check 'A FIXTURE: the SECOND overload has NO comment line directly above it (its own declaration line is what sits there)' `
  ($declBIx -ge 1 -and (-not $afterApplyLines[$declBIx - 1].TrimStart().StartsWith('///')))

# v(ADP3 T3d2 D8 review round 2, minor 4): this must run NOW, while the file
# actually carries the engine-written /// lines -- run after the round-trip
# restore below, it inspects a file with no /// lines left at all and can
# never fire regardless of what the engine emits.
foreach ($l in $afterApplyLines) {
  if ($l -match '^\s*///') { foreach ($ch in $l.ToCharArray()) { if ([int]$ch -gt 126) { Check 'A: every emitted /// line is 7-bit ASCII' $false $l; break } } }
}

# --- The fix under test: --qname --strip --apply must not corrupt either decl ---
& $exePath index $scratchA --db $dbA 2>$null | Out-Null
Check 'A: re-index before strip exits 0' ($LASTEXITCODE -eq 0)

$stripOut = (& $exePath document --qname strip_collision.Combine --db $dbA --strip --apply --json 2>$null) -join ' '
Check 'A: document --qname --strip --apply exits 0' ($LASTEXITCODE -eq 0)

# CRITICAL: the exact counts must be 1/1/1 -- NOT doubled. A regression back
# to the union-with-no-dedup shape would report tagsRemoved:2, blocksRemoved:2.
# v(ADP3 T3d2 D8 review round 2, minor 5): anchored with [,}] -- the same
# unanchored-substring shape removed from run_pipeline_tests.ps1:67 earlier in
# this task would let "tagsRemoved":12 etc. false-pass a 1-vs-doubled check.
# v(PHASE A3): tagsRemoved is now 2, not 1 -- ruling D-3 makes the engine emit a
# structural <param> for the signature parameter alongside the managed tag this
# fixture already had, so there is one more engine-owned tag to remove. What the
# check is FOR is unchanged and is what makes the numbers meaningful: a
# regression back to the union-with-no-dedup shape DOUBLES them, so the pinned
# values stay exact rather than becoming a >= test.
Check 'A CRITICAL: reports the NON-DOUBLED counts (tagsRemoved:2, blocksRemoved:1, edits:1)' `
  ($stripOut -match '"tagsRemoved":2[,}]' -and $stripOut -match '"blocksRemoved":1[,}]' -and $stripOut -match '"edits":1[,}]') $stripOut

# v(ADP3 T3d2 D8 review round 3, IMPORTANT): skippedCount/skippedFiles are now
# ALWAYS in --json output (see ReportStrip), including when nothing was
# skipped -- PART A has no cross-file match at all, so this is the "zero"
# half of that proof (PART B below proves the "populated" half). Anchored the
# same way as the tagsRemoved/blocksRemoved/edits check immediately above.
Check 'A: skippedCount/skippedFiles are ALWAYS present in --json, even when 0/empty' `
  ($stripOut -match '"skippedCount":0[,}]' -and $stripOut -match '"skippedFiles":\[\]') $stripOut

$afterStripText = [IO.File]::ReadAllText($targetA)
Check 'A CRITICAL: the FIRST overload declaration SURVIVES intact' `
  ($afterStripText.Contains('function Combine(A: Integer): Integer; overload;'))
Check 'A CRITICAL: the SECOND overload declaration SURVIVES intact (this is what the un-deduplicated union deleted)' `
  ($afterStripText.Contains('function Combine(A, B: Integer): Integer; overload;'))
Check 'A CRITICAL: the implementation keyword SURVIVES (the doubled delete ate past it in the unfixed code)' `
  ($afterStripText.Contains('implementation'))
Check 'A CRITICAL: both implementation bodies SURVIVE' `
  ($afterStripText.Contains('Result := A;') -and $afterStripText.Contains('Result := A + B;'))

# The strongest statement available: byte-identical round-trip back to the
# pristine, pre-apply source.
$afterStripBytes = [IO.File]::ReadAllBytes($targetA)
Check 'A ROUND-TRIP: file is BYTE-IDENTICAL to the pre-apply pristine fixture' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$pristineBytes, [byte[]]$afterStripBytes))

# --- Idempotency: a second strip --apply is a no-op ---
# v(ADP3 T3d2 D8 review round 2, minor 2): both calls now checked. Before this
# fix, an engine crash on EITHER line would leave the file untouched, and the
# "byte-identical" check right below would pass regardless -- a crash and a
# genuine no-op look identical to a check that only compares file bytes. The
# exact pattern this same task's item 5 removed from four other runners.
& $exePath index $scratchA --db $dbA 2>$null | Out-Null
Check 'A IDEMPOTENT: re-index before the second strip exits 0' ($LASTEXITCODE -eq 0)
& $exePath document --qname strip_collision.Combine --db $dbA --strip --apply --json 2>$null | Out-Null
Check 'A IDEMPOTENT: the second strip --apply itself exits 0' ($LASTEXITCODE -eq 0)
$afterStrip2Bytes = [IO.File]::ReadAllBytes($targetA)
Check 'A IDEMPOTENT: a second strip --apply is byte-identical (no further change)' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterStripBytes, [byte[]]$afterStrip2Bytes))

# ===========================================================================
# PART B -- IMPORTANT 2 + review round 2's IMPORTANT: a qname spanning two
# DIFFERENT files, and the skip must be reported, not silent.
# ===========================================================================
Write-Host ''
Write-Host '=== PART B: IMPORTANT 2 -- a qname that resolves across two files ===' -ForegroundColor Cyan

$scratchB = Join-Path C:\TEMP 'draglint_docp3stripcollision_b'
if (Test-Path $scratchB) { Remove-Item $scratchB -Recurse -Force }
$dirX = Join-Path $scratchB 'projX'
$dirY = Join-Path $scratchB 'projY'
New-Item -ItemType Directory -Path $dirX -Force | Out-Null
New-Item -ItemType Directory -Path $dirY -Force | Out-Null

# Two DIFFERENT files, same unit name, same routine name -- the real-world
# shape (a shared unit duplicated per project tree, e.g. the ORM3 index's
# EExtraExceptionInfo.pas under CLIENT/SERVER/TESTER).
$dupUnit = @'
unit dup;

interface

function Widget: Integer;

implementation

function Widget: Integer;
begin
  Result := 1;
end;

end.
'@
# v(ADP3 T3k, register K1): NORMALIZE TO LF FIRST. This was a bare
# `-replace "`n", "`r`n"`, which is correct only if $dupUnit's here-string is
# already LF. It was, in one working tree -- and .gitattributes says `*.ps1 text
# eol=crlf`, so A FRESH CLONE GIVES THIS FILE CRLF, the replace then produces
# `\r\r\n`, and the doubled CR breaks the parser: declCount 1, docCount 0, no
# engine marker, and 'B FIXTURE: BOTH files independently gained an engine
# marker' goes RED. So this runner has been passing on an accident of one
# checkout and would have failed for anyone else. Surfaced by T3k's
# renormalization; the fix makes it correct in both worlds.
# A repo-wide sweep found 42 sites doing this conversion and this was the ONLY
# one missing the normalize step -- the safe idiom below is already the
# convention everywhere else.
$dupUnitCrlf = ($dupUnit -replace "`r`n", "`n") -replace "`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $dirX 'dup.pas'), $dupUnitCrlf, (New-Object Text.ASCIIEncoding))
[IO.File]::WriteAllText((Join-Path $dirY 'dup.pas'), $dupUnitCrlf, (New-Object Text.ASCIIEncoding))
$pristineX = [IO.File]::ReadAllBytes((Join-Path $dirX 'dup.pas'))
$pristineY = [IO.File]::ReadAllBytes((Join-Path $dirY 'dup.pas'))

$dbB = Join-Path $scratchB 'b.sqlite'
& $exePath index $scratchB --db $dbB 2>$null | Out-Null
Check 'B: index exits 0' ($LASTEXITCODE -eq 0)

$queryOut = (& $exePath query --name Widget --db $dbB --json 2>$null) -join "`n"
Check 'B FIXTURE: dup.Widget resolves across exactly TWO files' `
  ((([regex]::Matches($queryOut, '"qualified_name"\s*:\s*"dup\.Widget"')).Count) -eq 2) $queryOut

# Write an engine comment on EACH file's copy independently (--unit is scoped
# to one file, so this cannot itself cross files).
& $exePath document --unit (Join-Path $dirX 'dup.pas') --db $dbB --stubs --apply --json 2>$null | Out-Null
Check 'B: document --unit (X) --apply exits 0' ($LASTEXITCODE -eq 0)
& $exePath document --unit (Join-Path $dirY 'dup.pas') --db $dbB --stubs --apply --json 2>$null | Out-Null
Check 'B: document --unit (Y) --apply exits 0' ($LASTEXITCODE -eq 0)

$xAfterApply = [IO.File]::ReadAllText((Join-Path $dirX 'dup.pas'))
$yAfterApply = [IO.File]::ReadAllText((Join-Path $dirY 'dup.pas'))
Check 'B FIXTURE: BOTH files independently gained an engine marker' `
  ($xAfterApply.Contains('drag-lint:auto') -and $yAfterApply.Contains('drag-lint:auto'))

& $exePath index $scratchB --db $dbB 2>$null | Out-Null
Check 'B: re-index before strip exits 0' ($LASTEXITCODE -eq 0)

# v(ADP3 T3d2 D8 review round 3, FOLDED A): this query decides which branch
# of the final X/Y pristine-state assertions runs below -- it had NO
# exit-code or content check at all, unlike the sibling `query --name Widget`
# whose result feeds the 'B FIXTURE: dup.Widget resolves across exactly TWO
# files' check earlier in this scenario, so a crash or empty result would
# silently route this runner into asserting the wrong file. Checked the same way
# now. (v(ADP3 T3k, Group 3): that sibling used to be cited as ':199-201'. The
# same diff that added this comment inserted ten lines above it, so the citation
# was already off by ten when it was written. Cite the assertion by its own text
# instead -- it cannot rot.)
$whichFirstOut = (& $exePath query --name Widget --db $dbB --json 2>$null) -join "`n"
Check 'B: query --name Widget (pre-strip ordering probe) exits 0' ($LASTEXITCODE -eq 0)
$whichFirst = @($whichFirstOut | ConvertFrom-Json)
Check 'B FIXTURE: the ordering probe returned at least one row with a non-empty file property' `
  (($whichFirst.Count -ge 1) -and (-not [string]::IsNullOrEmpty($whichFirst[0].file))) $whichFirstOut
$firstFile = $whichFirst[0].file
$strippedIsX = $firstFile -like '*projX*'

# v(ADP3 T3d2 D8 review round 2, IMPORTANT): TEXT mode, not --json -- needed
# to observe the human-readable `note:` sentence, which stays text-only (see
# CLI.pas's DoDocumentStripQName). This is the ONE invocation that must both
# report the strip correctly AND surface the note; splitting it into a
# separate JSON call for file-content checks and a separate text call for the
# note would test two different runs instead of proving THIS run does both.
# v(ADP3 T3d2 D8 review round 3): this comment used to justify text-only by
# citing DoDocumentUnit's AccessorsSkipped as "never mixed into --json" --
# that citation was FACTUALLY WRONG (see CLI.pas's ReportStrip and
# DoDocumentStripQName comments for the full correction); only the human
# SENTENCE is text-mode-only, the underlying skip DATA is now always in JSON
# too. The extra JSON-mode call below (after the pristine-state checks)
# proves --json also carries skippedCount/skippedFiles for this same
# cross-file case.
$stripOutB = (& $exePath document --qname dup.Widget --db $dbB --strip --apply 2>$null) -join "`n"
Check 'B: document --qname --strip --apply exits 0' ($LASTEXITCODE -eq 0)
Check 'B: the summary line names exactly ONE file path (Syms[0]''s own)' `
  ((([regex]::Matches($stripOutB, [regex]::Escape('dup.pas')))).Count -eq 1) $stripOutB
# v(ADP3 T3d2 D8 review round 2, IMPORTANT): this is the check that used to be
# missing -- PART B previously asserted only that the other file was silently
# untouched, which PINNED the silence as correct rather than proving it was
# reported. Restricting to Syms[0]'s file (IMPORTANT 2) still stands; the
# silence about the one skipped elsewhere does not.
Check 'B IMPORTANT: a note names how many OTHER matches in how many OTHER files were skipped' `
  ($stripOutB -match 'note:\s*1\s*other match\(es\)\s*for\s*dup\.Widget\s*in\s*1\s*other file\(s\)\s*were NOT touched') $stripOutB

$xAfterStrip = [IO.File]::ReadAllBytes((Join-Path $dirX 'dup.pas'))
$yAfterStrip = [IO.File]::ReadAllBytes((Join-Path $dirY 'dup.pas'))
if ($strippedIsX) {
  Check 'B IMPORTANT 2: the NAMED file (X) was stripped back to pristine' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$pristineX, [byte[]]$xAfterStrip))
  Check 'B IMPORTANT 2: the OTHER file (Y) was NOT touched -- still carries its own marker, byte-identical to right after its own --apply' `
    ([System.Linq.Enumerable]::SequenceEqual([Text.Encoding]::ASCII.GetBytes($yAfterApply), [byte[]]$yAfterStrip))
} else {
  Check 'B IMPORTANT 2: the NAMED file (Y) was stripped back to pristine' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$pristineY, [byte[]]$yAfterStrip))
  Check 'B IMPORTANT 2: the OTHER file (X) was NOT touched -- still carries its own marker, byte-identical to right after its own --apply' `
    ([System.Linq.Enumerable]::SequenceEqual([Text.Encoding]::ASCII.GetBytes($xAfterApply), [byte[]]$xAfterStrip))
}

# v(ADP3 T3d2 D8 review round 3, IMPORTANT): the skip DATA (as opposed to the
# human `note:` sentence proven above) is now ALSO always in --json output
# (see ReportStrip) -- this proves the "populated" half of that (PART A above
# already proved the "zero" half). Safe to call again here: Syms[0]'s own
# file is already stripped by the text-mode call above, so this --apply finds
# nothing left to apply (Applied:false, no file write) -- it cannot perturb
# the $xAfterStrip/$yAfterStrip byte snapshots already checked above; the
# cross-file skip is independent of whether Syms[0] itself had anything left
# to strip, so SkippedCount/SkippedFiles are computed the same either way.
$stripOutBJson = (& $exePath document --qname dup.Widget --db $dbB --strip --apply --json 2>$null) -join "`n"
Check 'B: the JSON-mode re-check of the same strip exits 0' ($LASTEXITCODE -eq 0)
$stripJsonB = $stripOutBJson | ConvertFrom-Json
Check 'B IMPORTANT: --json also reports skippedCount:1' ($stripJsonB.skippedCount -eq 1) $stripOutBJson
if ($strippedIsX) {
  Check 'B IMPORTANT: --json skippedFiles names the OTHER file (Y)' `
    (@($stripJsonB.skippedFiles).Count -eq 1 -and (@($stripJsonB.skippedFiles)[0] -like '*projY*')) $stripOutBJson
} else {
  Check 'B IMPORTANT: --json skippedFiles names the OTHER file (X)' `
    (@($stripJsonB.skippedFiles).Count -eq 1 -and (@($stripJsonB.skippedFiles)[0] -like '*projX*')) $stripOutBJson
}

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
