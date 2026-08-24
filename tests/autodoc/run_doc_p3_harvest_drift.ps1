<#
  run_doc_p3_harvest_drift.ps1 -- Auto-Document Phase 3, Task 9 (part 2):
  the harvest refresh/removal rules, their drift report, and the strip round-trip.

  Task 7 decided WHAT a harvested comment turns into. Task 8 decided WHERE it may
  be harvested from. This decides what happens on the SECOND and later runs, once
  the source comment underneath a marked summary has MOVED ON.

  THE FOUR-WAY RULE (plan Task 9 / spec 3.3), decided per symbol by comparing the
  existing <summary> against a freshly-computed harvest:

    existing marked, StripMark(existing) = harvest   -> no change (idempotent)
    existing marked, they differ                     -> REFRESH to the harvest
    existing NOT marked                              -> hand-written: never touch,
                                                        and never report
    existing marked non-empty, harvest is now ''     -> REMOVE the managed summary,
                                                        and report the drift

  WHY "A HUMAN EDITED INSIDE THE MARKERS" ALSO LANDS ON REFRESH. It is not
  distinguishable from "the source comment changed" by string comparison, and the
  spec's own detection mechanism IS that string comparison. Text inside a marked
  tag is engine-owned; a human who wants to own it removes the marker (step 5
  proves that escape hatch works). The drift REPORT is what makes the overwrite
  visible instead of silent -- so the report is asserted, not just the rewrite.

  THE FIXTURE NEEDS A Driver. A symbol with NO FACTS gets no doc block at all
  ("nothing to document"), so a harvested summary would have nowhere to land and
  every assertion here would be vacuous. The plan's fixture as written could not
  demonstrate its own scenario for that reason; Driver calls both routines so each
  one has a caller fact. Same device as harvest_text.pas / harvest_impl.pas.

  EVERY doc-drift READ IS TAKEN BEFORE ITS apply, and re-taken after. A finding
  that is never observed to CLEAR proves nothing about the rewrite that cleared
  it, and a finding asserted only after the fix would always be absent.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\harvest_drift.pas')).Path

# ---------------------------------------------------------------------------
# Helpers. Standalone by convention -- every runner in this directory carries
# its own copies rather than dot-sourcing a shared module.
# ---------------------------------------------------------------------------

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

# INTERFACE-section start line for $name, read back from the index via the
# engine's own query verb (index-first: no second parser).
function Get-DeclLine([string]$db, [string]$name) {
  $j = (& $exePath query --name $name --db $db --json 2>$null) -join "`n"
  $o = $null; try { $o = ($j | ConvertFrom-Json) } catch { return 0 }
  if ($null -eq $o) { return 0 }
  foreach ($r in @($o)) { if ($r.section -eq 'interface') { return [int]$r.start_line } }
  return 0
}

# The contiguous run of ///-prefixed lines immediately above 1-based
# $declLine1, per-line trimmed and newline-joined. Tolerates ONE leading blank
# line, mirroring FindDocRegionAbove's AllowGap=1 default.
function Get-DocBlockAtLine([string[]]$lines, [int]$declLine1) {
  $i = $declLine1 - 2
  if ($i -lt 0) { return '' }
  if ($lines[$i].Trim() -eq '') { $i-- }
  $acc = New-Object System.Collections.Generic.List[string]
  for (; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i].Trim())
  }
  return [string]::Join("`n", $acc.ToArray())
}

# The doc block for $name, re-resolved from the CURRENT file + index.
function Get-Block([string]$db, [string]$path, [string]$name) {
  return (Get-DocBlockAtLine ([IO.File]::ReadAllLines($path)) (Get-DeclLine $db $name))
}

# The text content of the <summary>, marker stripped, or '' when the tag is
# absent. Spans lines: EmitTagged re-prefixes continuation lines with ///.
function Get-Summary([string]$block) {
  $flat = ($block -split "`n" | ForEach-Object { $_ -replace '^\s*///\s?','' -replace '</?para>','' }) -join ' '
  $m = [regex]::Match($flat, '<summary>(?:<!-- drag-lint:auto -->)?\s*(.*?)\s*</summary>')
  if ($m.Success) { return ($m.Groups[1].Value -replace '\s+',' ').Trim() } else { return '' }
}

# True when the block carries a <summary> tag AT ALL (open form), marked or not.
# Deliberately NOT derived from Get-Summary: an EMPTY summary tag is present but
# has no text, and step 4 is about the tag's total ABSENCE.
function Has-SummaryTag([string]$block) {
  return ([bool]([regex]::IsMatch((($block -split "`n") -join ' '), '<summary[ >]')))
}

# True when the block's <summary> -- and nothing else in the block -- carries the
# provenance marker. Scoped to the tag on purpose: a documented block also marks
# its <returns> and its facts fence, so a whole-block search answers a different
# question than the one being asked (Task 8, finding 2).
function Test-SummaryMarked([string]$block) {
  return ([bool](((($block -split "`n") -join ' ') -match '<summary><!-- drag-lint:auto -->')))
}

# doc-drift for one qname, as raw JSON lines joined.
function Get-Drift([string]$db, [string]$qname) {
  return ((& $exePath doc-drift --qname $qname --db $db --json 2>$null) -join "`n")
}

function Set-Text([string]$p, [string]$s) {
  [IO.File]::WriteAllText($p, $s, [Text.Encoding]::ASCII)
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== harvest_drift.pas -- refresh / removal / hand-written / strip ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_harvestdrift'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'harvest_drift.pas'
$db  = Join-Path $sc 'h.sqlite'
Copy-Item $fx $tgt -Force

$pristine = [IO.File]::ReadAllBytes($tgt)

& $exePath index $sc --db $db 2>$null | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)

# --- PRECONDITIONS. --------------------------------------------------------
$pre = [IO.File]::ReadAllLines($tgt)
Check 'PRECONDITION: the fixture carries NO /// line before the apply' `
  (@($pre | Where-Object { $_ -match '^\s*///' }).Count -eq 0) ''
Check 'PRECONDITION: Drifting''s source comment is the first-version prose' `
  (@($pre | Where-Object { $_ -eq '// Original prose, first version.' }).Count -eq 1) ''
Check 'PRECONDITION: Vanishing''s source comment is present' `
  (@($pre | Where-Object { $_ -eq '// Prose that will be deleted.' }).Count -eq 1) ''

# ===========================================================================
# STEP 1 -- first apply: both summaries are marked and carry their prose.
# ===========================================================================
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
Check 'STEP 1: apply exits 0' ($LASTEXITCODE -eq 0)
& $exePath index $sc --db $db 2>$null | Out-Null

$blkD = Get-Block $db $tgt 'Drifting'
$blkV = Get-Block $db $tgt 'Vanishing'
Check 'STEP 1: Drifting''s summary is the harvested first-version prose' `
  ((Get-Summary $blkD) -eq 'Original prose, first version.') ("got=[" + (Get-Summary $blkD) + "]")
Check 'STEP 1: Drifting''s summary is MARKED (engine-owned, so refresh/strip can find it)' `
  (Test-SummaryMarked $blkD) ($blkD -replace "`n",' | ')
Check 'STEP 1: Vanishing''s summary is the harvested prose' `
  ((Get-Summary $blkV) -eq 'Prose that will be deleted.') ("got=[" + (Get-Summary $blkV) + "]")
Check 'STEP 1: Vanishing''s summary is MARKED' (Test-SummaryMarked $blkV) ($blkV -replace "`n",' | ')

# De-vacuator for step 4: the block exists because there is a FACT in it, not
# because of the summary. Step 4 asserts the summary goes and the block stays.
Check 'STEP 1 (de-vacuator): Vanishing''s block carries a facts fence (Driver''s caller fact)' `
  ($blkV -match 'drag-lint:auto BEGIN') ($blkV -replace "`n",' | ')

$md5Step1 = Get-FileMd5 $tgt

# ===========================================================================
# STEP 2 -- idempotency with a harvested summary already present.
# ===========================================================================
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
& $exePath index $sc --db $db 2>$null | Out-Null
Check 'STEP 2: a second apply after a reindex is byte-identical' `
  ((Get-FileMd5 $tgt) -eq $md5Step1) ("c1=$md5Step1 c2=" + (Get-FileMd5 $tgt))
# A file that lost BOTH summaries identically would also be byte-identical on a
# third run, so assert the summary specifically survived.
Check 'STEP 2: the harvested summary survived the second apply' `
  ((Get-Summary (Get-Block $db $tgt 'Drifting')) -eq 'Original prose, first version.') ''

# ===========================================================================
# STEP 3 -- the source comment CHANGED: refresh, and report it.
# ===========================================================================
# The '\r?' before '$' is load-bearing: the file is CRLF and .NET's multiline
# '$' matches BEFORE the '\n', so the CR is still part of the line and a plain
# '\.$' never matches. Getting this wrong makes the edit a silent no-op and the
# whole step tests the UNCHANGED file -- which is why the assertion below
# re-checks that the edited comment is actually on disk.
Set-Text $tgt (([IO.File]::ReadAllText($tgt)) -replace `
  '(?m)^// Original prose, first version\.\r?$', '// Original prose, SECOND version.')
& $exePath index $sc --db $db 2>$null | Out-Null

$drift3 = Get-Drift $db 'harvest_drift.Drifting'
Check 'STEP 3: doc-drift reports ddHarvestDrift BEFORE the apply' `
  ($drift3 -match '"kind":"ddHarvestDrift"') $drift3
Check 'STEP 3: the finding names the text now in the doc' `
  ($drift3 -match 'Original prose, first version\.') $drift3
Check 'STEP 3: the finding names the text the source comment now yields' `
  ($drift3 -match 'Original prose, SECOND version\.') $drift3
Check 'STEP 3: the finding names the symbol' ($drift3 -match 'Drifting') $drift3

& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
& $exePath index $sc --db $db 2>$null | Out-Null
$blkD3 = Get-Block $db $tgt 'Drifting'
Check 'STEP 3: the marked summary was REFRESHED to the new prose' `
  ((Get-Summary $blkD3) -eq 'Original prose, SECOND version.') ("got=[" + (Get-Summary $blkD3) + "]")
Check 'STEP 3: it is still marked after the refresh' (Test-SummaryMarked $blkD3) ($blkD3 -replace "`n",' | ')
Check 'STEP 3: the drift CLEARS once the refresh is applied' `
  (-not ((Get-Drift $db 'harvest_drift.Drifting') -match '"kind":"ddHarvestDrift"')) `
  (Get-Drift $db 'harvest_drift.Drifting')
# COPY, NEVER MOVE still holds after a refresh.
Check 'STEP 3: the edited source // comment is still in the file' `
  (@([IO.File]::ReadAllLines($tgt) | Where-Object { $_ -eq '// Original prose, SECOND version.' }).Count -eq 1) ''

# ===========================================================================
# STEP 4 -- the source comment was DELETED: remove the managed summary, report.
# ===========================================================================
Set-Text $tgt (([IO.File]::ReadAllText($tgt)) -replace '(?m)^// Prose that will be deleted\.\r?\n', '')
& $exePath index $sc --db $db 2>$null | Out-Null

$drift4 = Get-Drift $db 'harvest_drift.Vanishing'
Check 'STEP 4: doc-drift reports ddHarvestDrift for the vanished source comment' `
  ($drift4 -match '"kind":"ddHarvestDrift"') $drift4
Check 'STEP 4: the finding names the summary about to be removed' `
  ($drift4 -match 'Prose that will be deleted\.') $drift4

& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
& $exePath index $sc --db $db 2>$null | Out-Null
$blkV4 = Get-Block $db $tgt 'Vanishing'
Check 'STEP 4: Vanishing has NO <summary> tag at all' (-not (Has-SummaryTag $blkV4)) ($blkV4 -replace "`n",' | ')
Check 'STEP 4 (de-vacuator): the rest of Vanishing''s block is still there' `
  ($blkV4 -match 'drag-lint:auto BEGIN') ($blkV4 -replace "`n",' | ')
Check 'STEP 4: the drift CLEARS once the removal is applied' `
  (-not ((Get-Drift $db 'harvest_drift.Vanishing') -match '"kind":"ddHarvestDrift"')) `
  (Get-Drift $db 'harvest_drift.Vanishing')
# The removal must not spread: Drifting keeps the summary it refreshed to.
Check 'STEP 4: Drifting is untouched by Vanishing''s removal' `
  ((Get-Summary (Get-Block $db $tgt 'Drifting')) -eq 'Original prose, SECOND version.') ''

# ===========================================================================
# STEP 5 -- the human takes ownership: unmark the summary. Never touch, never
# report -- even though the source // comment still yields a DIFFERENT harvest.
# ===========================================================================
Set-Text $tgt (([IO.File]::ReadAllText($tgt)) -replace `
  '<summary><!-- drag-lint:auto -->Original prose, SECOND version\.</summary>', `
  '<summary>Human owns this now.</summary>')
& $exePath index $sc --db $db 2>$null | Out-Null

$blkD5pre = Get-Block $db $tgt 'Drifting'
Check 'STEP 5 (precondition): the summary is now UNMARKED and reads the human text' `
  (((Get-Summary $blkD5pre) -eq 'Human owns this now.') -and (-not (Test-SummaryMarked $blkD5pre))) `
  ($blkD5pre -replace "`n",' | ')
Check 'STEP 5 (de-vacuator): the source // comment still yields a DIFFERENT harvest' `
  (@([IO.File]::ReadAllLines($tgt) | Where-Object { $_ -eq '// Original prose, SECOND version.' }).Count -eq 1) ''

Check 'STEP 5: doc-drift does NOT report harvest drift on a hand-written summary' `
  (-not ((Get-Drift $db 'harvest_drift.Drifting') -match '"kind":"ddHarvestDrift"')) `
  (Get-Drift $db 'harvest_drift.Drifting')

& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
& $exePath index $sc --db $db 2>$null | Out-Null
$blkD5 = Get-Block $db $tgt 'Drifting'
Check 'STEP 5: the hand-written summary is UNTOUCHED by the apply' `
  ((Get-Summary $blkD5) -eq 'Human owns this now.') ("got=[" + (Get-Summary $blkD5) + "]")
Check 'STEP 5: and it is still UNMARKED (ownership did not silently return to the engine)' `
  (-not (Test-SummaryMarked $blkD5)) ($blkD5 -replace "`n",' | ')

# ===========================================================================
# STEP 6 -- strip round trip, on a SEPARATE scratch from the pristine fixture.
# The sequence above mutates the file deliberately; the round trip has to start
# from the state after step 1, so it gets its own copy.
# ===========================================================================
$sc2 = Join-Path C:\TEMP 'draglint_docp3_harvestdrift_strip'
if (Test-Path $sc2) { Remove-Item $sc2 -Recurse -Force }
New-Item -ItemType Directory -Path $sc2 | Out-Null
$tgt2 = Join-Path $sc2 'harvest_drift.pas'
$db2  = Join-Path $sc2 'h.sqlite'
[IO.File]::WriteAllBytes($tgt2, $pristine)

& $exePath index $sc2 --db $db2 2>$null | Out-Null
$md5Pre = Get-FileMd5 $tgt2
& $exePath document --unit $tgt2 --db $db2 --apply 2>$null | Out-Null
& $exePath index $sc2 --db $db2 2>$null | Out-Null
Check 'STEP 6 (de-vacuator): the apply really changed the file' `
  ((Get-FileMd5 $tgt2) -ne $md5Pre) ''
& $exePath document --unit $tgt2 --db $db2 --strip --apply 2>$null | Out-Null
Check 'STEP 6: --strip restores the file byte-for-byte, harvested summaries and all' `
  ((Get-FileMd5 $tgt2) -eq $md5Pre) ("pre=$md5Pre post=" + (Get-FileMd5 $tgt2))
$after = [IO.File]::ReadAllLines($tgt2)
foreach ($orig in @('// Original prose, first version.', '// Prose that will be deleted.')) {
  Check "STEP 6: the original source comment survived the round trip -- $orig" `
    (@($after | Where-Object { $_ -eq $orig }).Count -eq 1) ''
}

# --- ENCODING, on the mutated copy. ----------------------------------------
$bytes = [IO.File]::ReadAllBytes($tgt)
Check 'ENCODING: the applied file is strict 7-bit ASCII' `
  (@($bytes | Where-Object { $_ -ge 128 }).Count -eq 0) ''
Check 'ENCODING: the applied file has no bare LF (CRLF throughout)' `
  (([regex]::Matches([IO.File]::ReadAllText($tgt), "(?<!`r)`n")).Count -eq 0) ''

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
