<#
  run_doc_p3_harvest_text.ps1 -- Auto-Document Phase 3, Task 7:
  the harvested text itself, and its interface-side wiring.

  Task 6 decided WHETHER a comment may be harvested. This decides WHAT the
  harvested comment turns into and where it lands.

  THE TRANSFORMATION (plan 3.5), in order: strip comment markers and the common
  leading indentation; split into paragraphs on blank comment lines; first
  paragraph -> the managed <summary>, the rest -> <remarks> prose; XML-escape
  with EscXml semantics (ampersand FIRST, then the angle brackets, so the
  ampersand an entity introduces is not re-escaped); join a paragraph's wrapped
  lines with single spaces.

  COPY, NEVER MOVE (plan 3.2). The original // comment must still be in the file
  afterwards, unchanged. Harvesting that deleted the human's comment would be a
  destructive edit dressed as documentation, so the surviving // lines are
  asserted explicitly and not merely assumed.

  IDEMPOTENCY IS THE HARD PART, AND IT IS WHY THE SCAN SKIPS THE DOC REGION.
  MergeComment writes its /// block immediately above the declaration -- i.e.
  BETWEEN the harvested // comment and the declaration. A second run scanning up
  from the declaration would therefore meet /// first, get hrNone (Task 6's
  already-DocInsight rule), find HarvestedSummary empty, and DROP the summary the
  first run just wrote. The wiring skips the existing doc region so the candidate
  is the comment above it; assertion 7 is what holds that in place, and it fails
  loudly if the skip is ever removed.

  ESCAPING IS ASSERTED IN BOTH DIRECTIONS: the three characters are escaped, AND
  no double-escaped '&amp;lt;' appears. A one-directional check passes on an
  escaper that runs the ampersand pass last.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\harvest_text.pas')).Path

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

# The text content of the managed <summary>, marker stripped, or '' when the tag
# is absent. Spans lines: EmitTagged re-prefixes continuation lines with ///.
function Get-Summary([string]$block) {
  $flat = ($block -split "`n" | ForEach-Object { $_ -replace '^\s*///\s?','' }) -join ' '
  $m = [regex]::Match($flat, '<summary>(?:<!-- drag-lint:auto -->)?\s*(.*?)\s*</summary>')
  if ($m.Success) { return ($m.Groups[1].Value -replace '\s+',' ').Trim() } else { return '' }
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== harvest_text.pas, document --unit --apply ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_harvesttext'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'harvest_text.pas'
$db  = Join-Path $sc 'h.sqlite'
Copy-Item $fx $tgt -Force

& $exePath index $sc --db $db 2>$null | Out-Null

# --- PRECONDITIONS, from the pre-apply source. ------------------------------
# The whole suite is about promoting these two comments; if the fixture ever
# stops carrying them in the shape the transformation expects, every assertion
# below would be testing something else.
$pre = [IO.File]::ReadAllLines($tgt)
Check 'PRECONDITION: the fixture carries NO /// line before the apply' `
  (@($pre | Where-Object { $_ -match '^\s*///' }).Count -eq 0) ''
Check 'PRECONDITION: IsAsciiAlpha''s // comment is TWO wrapped lines (so "joined with single spaces" is testable)' `
  ((@($pre | Where-Object { $_ -match '^// (True for a 7-bit|shield and unshield)' }).Count) -eq 2) ''
Check 'PRECONDITION: TwoParagraphs'' // comment has a BLANK comment line separating two paragraphs' `
  (@($pre | Where-Object { $_.Trim() -eq '//' }).Count -eq 1) ''
Check 'PRECONDITION: the second paragraph really contains the three characters XML escaping must handle' `
  (@($pre | Where-Object { $_ -match 'A < B & C > D' }).Count -eq 1) ''

# ===========================================================================
# APPLY
# ===========================================================================
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
$md5Cycle1 = Get-FileMd5 $tgt
& $exePath index $sc --db $db 2>$null | Out-Null

$text  = [IO.File]::ReadAllText($tgt)
$lines = [IO.File]::ReadAllLines($tgt)

$lnAlpha = Get-DeclLine $db 'IsAsciiAlpha'
$lnTwo   = Get-DeclLine $db 'TwoParagraphs'
Check 'IsAsciiAlpha resolved to an interface declaration line'  ($lnAlpha -gt 0) "line=$lnAlpha"
Check 'TwoParagraphs resolved to an interface declaration line' ($lnTwo   -gt 0) "line=$lnTwo"
$blkAlpha = Get-DocBlockAtLine $lines $lnAlpha
$blkTwo   = Get-DocBlockAtLine $lines $lnTwo

# --- (1) One paragraph, wrapped lines joined with single spaces. ------------
$wantAlpha = 'True for a 7-bit ASCII letter (A-Z / a-z). Shared by the include-directive shield and unshield scans; deliberately ASCII-only.'
Check 'HARVEST: IsAsciiAlpha''s summary is the whole comment, wrapped lines joined with single spaces' `
  ((Get-Summary $blkAlpha) -eq $wantAlpha) ("got=[" + (Get-Summary $blkAlpha) + "]")
Check 'HARVEST: that summary carries the provenance marker (engine-owned, so --strip and drift can find it)' `
  ($blkAlpha -match '<summary><!-- drag-lint:auto -->') ($blkAlpha -replace "`n",' | ')

# --- (2) COPY, NEVER MOVE: the original // comment is still there. ----------
foreach ($orig in @(
    '^// True for a 7-bit ASCII letter \(A-Z / a-z\)\. Shared by the include-directive$',
    '^// shield and unshield scans; deliberately ASCII-only\.$',
    '^// First paragraph becomes the summary\.$',
    '^// Second paragraph becomes remarks prose\. It mentions A < B & C > D so the$',
    '^// XML escaping is exercised on real content\.$')) {
  Check "COPY: the original // line is still present, unchanged -- $orig" `
    (@($lines | Where-Object { $_ -match $orig }).Count -eq 1) ''
}

# --- (3) TwoParagraphs: paragraph 1 is the summary, paragraph 2 is remarks. -
Check 'SPLIT: TwoParagraphs'' summary is EXACTLY the first paragraph' `
  ((Get-Summary $blkTwo) -eq 'First paragraph becomes the summary.') ("got=[" + (Get-Summary $blkTwo) + "]")
Check 'SPLIT: the summary does NOT swallow the second paragraph' `
  (-not ((Get-Summary $blkTwo) -match 'Second paragraph')) ("got=[" + (Get-Summary $blkTwo) + "]")

$blkTwoFlat = ($blkTwo -split "`n") -join ' '
Check 'SPLIT: the second paragraph is emitted inside <remarks>' `
  (($blkTwo -match '<remarks>') -and ($blkTwoFlat -match 'Second paragraph becomes remarks prose')) `
  ($blkTwo -replace "`n",' | ')

# ... and ABOVE the facts fence, so a later run's regenerated fence never
# swallows it. Compare line INDEXES inside the block, not mere presence.
$twoLines = @($blkTwo -split "`n")
$idxProse = -1; $idxBegin = -1
for ($i = 0; $i -lt $twoLines.Count; $i++) {
  if (($idxProse -lt 0) -and ($twoLines[$i] -match 'Second paragraph becomes remarks prose')) { $idxProse = $i }
  if (($idxBegin -lt 0) -and ($twoLines[$i] -match 'drag-lint:auto BEGIN')) { $idxBegin = $i }
}
# The fence must EXIST for the ordering claim to mean anything -- which is why
# the fixture makes TwoParagraphs call IsAsciiAlpha, so it renders a fact at all.
Check 'SPLIT (de-vacuator): TwoParagraphs really does render an AUTO_BEGIN fence' `
  ($idxBegin -ge 0) ($blkTwo -replace "`n",' | ')
Check 'SPLIT: the harvested remarks prose sits ABOVE the AUTO_BEGIN fence' `
  (($idxProse -ge 0) -and ($idxBegin -ge 0) -and ($idxProse -lt $idxBegin)) `
  ("prose=$idxProse begin=$idxBegin")

# --- (4) XML escaping, in BOTH directions. ---------------------------------
Check 'ESCAPE: < and > and & in the harvested prose are escaped' `
  (($blkTwoFlat -match '&lt;') -and ($blkTwoFlat -match '&gt;') -and ($blkTwoFlat -match '&amp;')) `
  ($blkTwoFlat)
Check 'ESCAPE: the raw characters do NOT survive into the /// prose' `
  (-not ($blkTwoFlat -match 'A < B')) ($blkTwoFlat)
# The ampersand pass must run FIRST. If it ran last it would re-escape the
# ampersand '&lt;' introduced, producing '&amp;lt;'. Absence-only, but the
# positive '&lt;' check above is its de-vacuator.
Check 'ESCAPE: nothing is double-escaped (no &amp;lt; / &amp;gt; / &amp;amp;)' `
  (-not ($text -match '&amp;(lt|gt|amp);')) ''

# --- (5) Every emitted line is /// -prefixed after its indentation. ---------
# The 5ebde68 corruption: an interior newline reaching the file unprefixed turns
# the rest of the doc block into code. Scan BOTH doc regions, whole.
$bad = @()
foreach ($blk in @($blkAlpha, $blkTwo)) {
  foreach ($l in ($blk -split "`n")) { if (($l.Trim() -ne '') -and ($l -notmatch '^\s*///')) { $bad += $l } }
}
Check 'PREFIX: every line of every emitted doc region begins with /// after its indentation' `
  ($bad.Count -eq 0) ($bad -join ' | ')

# --- (6) Strict 7-bit ASCII and CRLF. --------------------------------------
$bytes = [IO.File]::ReadAllBytes($tgt)
Check 'ENCODING: the applied file is strict 7-bit ASCII' `
  (@($bytes | Where-Object { $_ -ge 128 }).Count -eq 0) ''
$raw = [IO.File]::ReadAllText($tgt)
Check 'ENCODING: the applied file has no bare LF (CRLF throughout)' `
  (([regex]::Matches($raw, "(?<!`r)`n")).Count -eq 0) ''

# --- (7) Idempotency. -------------------------------------------------------
# THE assertion that holds the doc-region skip in place: without it the second
# run scans up from the declaration, meets its own /// block, harvests nothing,
# and drops the summary the first run wrote.
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
$md5Cycle2 = Get-FileMd5 $tgt
Check 'IDEMPOTENT: a second --apply after a reindex is byte-identical' ($md5Cycle1 -eq $md5Cycle2) `
  "c1=$md5Cycle1 c2=$md5Cycle2"
# ... and specifically, the summary SURVIVED it. A file that lost both summaries
# identically would also be byte-identical on a third run.
$lines2 = [IO.File]::ReadAllLines($tgt)
Check 'IDEMPOTENT: the harvested summary is still present after the second apply' `
  ((Get-Summary (Get-DocBlockAtLine $lines2 (Get-DeclLine $db 'IsAsciiAlpha'))) -eq $wantAlpha) ''

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
