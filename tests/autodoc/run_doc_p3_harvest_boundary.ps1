<#
  run_doc_p3_harvest_boundary.ps1 -- PHASE A1: the harvest BOUNDARY rule, ruling
  D-5 (foreign-symbol demotion) and ruling D-1 (no duplicate on re-run).

  WHY THIS RUNNER EXISTS
  ----------------------
  Two defects were filed against the harvester from REAL corpora, and both are
  the same shape: prose that a human wrote about something ELSE became a
  declaration's <summary> -- the one line a Help Insight tooltip shows.

    docs\INBOX-harvest-swallows-preceding-banner-comment.md   (2026-08-03)
    docs\INBOX-datacopy-2026-08-06-...-doc-lint-defects.md, section 8

  THE BOUNDARY RULE. The upward scan used to cross blank lines without limit, so
  a comment block that ended one blank line above ANOTHER comment block was
  accumulated into it. HarvestText's leading-banner drop repaired the first
  filed instance -- but only because that particular upper block was a row of
  dashes. This fixture's upper block is ORDINARY PROSE, which is what makes the
  case discriminating: the banner drop cannot see it, so only the boundary rule
  keeps it out of the summary.

  RULING D-5 -- DEMOTE, NEVER DISCARD. A comment whose first sentence names a
  symbol declared in ANOTHER unit is prose about that symbol, not this one's
  contract. It moves to <remarks>, where it is still available to a reader. The
  filed instance documented a REMOVAL ("SourceStampString used to live here. It
  MOVED to uFileUtils...") and became a constructor's summary.

  ... AND THE CONSERVATISM IS HALF THE RULE. A false demotion loses a good
  summary, so two controls run against the same code path:

    LocalMention  names a symbol declared in ITS OWN unit -- the ordinary
                  "summary mentions the helper it calls" shape. Keeps it.
    PlainProse    opens on `Backup`, a single-cased English word that IS also a
                  symbol in the other unit. Single-cased words are not symbol
                  references; otherwise every comment opening with Register /
                  Create / Count would be demoted. Keeps it.

  Both controls are load-bearing: a demoter that simply resolved the first
  identifier would satisfy every D-5 assertion here and fail these two.

  RULING D-1 -- NO DUPLICATE ON RE-RUN. Ownership of an engine-written line
  passes to a human by DELETING its provenance marker, after which MergeComment
  preserves it as hand prose. But the harvest is recomputed from a source
  comment that is still in the file, so without a dedupe the engine re-emits its
  own copy underneath the human's and the paragraph is there twice, for good,
  with no marker on the first copy for --strip to find. The OwnershipHandover
  case performs exactly that human edit between two applies.

  NON-VACUITY. Before any D-5 verdict, the runner asserts against the INDEX that
  SourceStampString really is declared in the other file and LocalHelper really
  is declared in this one -- the two facts the rule is a function of. It also
  asserts each subject rendered a doc block at all, because "has no <summary>"
  is trivially true of a symbol that was never documented.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\harvest_boundary.pas')).Path
$fxOther = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\harvest_boundary_other.pas')).Path

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

# The file (leaf name) $name's interface declaration lives in, per the index.
# This is what "foreign" means, so the runner reads it rather than assuming it.
function Get-DeclFile([string]$db, [string]$name) {
  $j = (& $exePath query --name $name --db $db --json 2>$null) -join "`n"
  $o = $null; try { $o = ($j | ConvertFrom-Json) } catch { return '' }
  if ($null -eq $o) { return '' }
  foreach ($r in @($o)) { if ($r.section -eq 'interface') { return (Split-Path -Leaf $r.file) } }
  return ''
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

# The text content of the <summary>, marker stripped, or '' when the tag is
# absent. Spans lines: EmitTagged re-prefixes continuation lines with ///.
function Get-Summary([string]$block) {
  $flat = ($block -split "`n" | ForEach-Object { $_ -replace '^\s*///\s?','' }) -join ' '
  $m = [regex]::Match($flat, '<summary>(?:<!-- drag-lint:auto -->)?\s*(.*?)\s*</summary>')
  if ($m.Success) { return ($m.Groups[1].Value -replace '\s+',' ').Trim() } else { return '' }
}

# How many times $needle occurs in $block, compared on whitespace-collapsed
# text so a wrapped re-emission still counts as the same phrase.
function Count-Phrase([string]$block, [string]$needle) {
  $flat = (($block -split "`n" | ForEach-Object { $_ -replace '^\s*///\s?','' }) -join ' ') -replace '\s+',' '
  return ([regex]::Matches($flat, [regex]::Escape($needle))).Count
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== harvest_boundary.pas, document --unit --apply ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_harvestboundary'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'harvest_boundary.pas'
$db  = Join-Path $sc 'h.sqlite'
Copy-Item $fx      $tgt -Force
Copy-Item $fxOther (Join-Path $sc 'harvest_boundary_other.pas') -Force

& $exePath index $sc --db $db 2>$null | Out-Null

# --- PRECONDITIONS, from the pre-apply source. ------------------------------
$pre = [IO.File]::ReadAllLines($tgt)
Check 'PRECONDITION: the fixture carries NO /// line before the apply' `
  (@($pre | Where-Object { $_ -match '^\s*///' }).Count -eq 0) ''

# THE SHAPE UNDER TEST: two comment blocks, exactly one blank SOURCE line
# between them. If a fixture edit ever closes that gap the boundary rule is no
# longer being exercised and this assertion says so here, not three checks later.
$iUpper = -1; $iLower = -1
for ($i = 0; $i -lt $pre.Count; $i++) {
  if ($pre[$i] -match '^// This note belongs to the section ABOVE') { $iUpper = $i }
  if ($pre[$i] -match '^// Real prose that must become the summary\.$') { $iLower = $i }
}
Check 'PRECONDITION: both comment blocks are present' (($iUpper -ge 0) -and ($iLower -gt $iUpper)) `
  "upper=$iUpper lower=$iLower"
Check 'PRECONDITION: exactly ONE blank source line separates the two blocks' `
  (($iLower -gt 0) -and ($pre[$iLower - 1].Trim() -eq '') -and ($pre[$iLower - 2].Trim() -ne '')) `
  ("above=[" + $(if ($iLower -gt 1) { $pre[$iLower - 2] } else { '' }) + "]")

# --- NON-VACUITY: the two index facts ruling D-5 is a function of. ----------
Check 'CONTROL: SourceStampString is declared in the OTHER unit (so "foreign" is a fact)' `
  ((Get-DeclFile $db 'SourceStampString') -eq 'harvest_boundary_other.pas') `
  ("file=" + (Get-DeclFile $db 'SourceStampString'))
Check 'CONTROL: LocalHelper is declared in THIS unit (so "not foreign" is a fact)' `
  ((Get-DeclFile $db 'LocalHelper') -eq 'harvest_boundary.pas') `
  ("file=" + (Get-DeclFile $db 'LocalHelper'))
Check 'CONTROL: Backup -- the single-cased word -- really does resolve, in the other unit' `
  ((Get-DeclFile $db 'Backup') -eq 'harvest_boundary_other.pas') `
  ("file=" + (Get-DeclFile $db 'Backup'))

# ===========================================================================
# APPLY (cycle 1)
# ===========================================================================
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
$md5Cycle1 = Get-FileMd5 $tgt
& $exePath index $sc --db $db 2>$null | Out-Null

$lines = [IO.File]::ReadAllLines($tgt)

$subjects = @('BlockBoundary','ForeignNote','LocalMention','PlainProse','OwnershipHandover')
$blk = @{}
foreach ($s in $subjects) {
  $ln = Get-DeclLine $db $s
  Check "$s resolved to an interface declaration line" ($ln -gt 0) "line=$ln"
  $blk[$s] = Get-DocBlockAtLine $lines $ln
  # "has no <summary>" is trivially true of a symbol nothing was written for.
  Check "$s rendered a doc block at all (de-vacuator)" ($blk[$s] -match '///') `
    ($blk[$s] -replace "`n",' | ')
}

# --- (1) THE BOUNDARY RULE. -------------------------------------------------
Check 'BOUNDARY: the summary is the LOWER block''s prose' `
  ((Get-Summary $blk['BlockBoundary']) -eq 'Real prose that must become the summary.') `
  ("got=[" + (Get-Summary $blk['BlockBoundary']) + "]")
# Not merely "not the summary" -- the upper block must not have been harvested
# at all. Demoting it to <remarks> would just relocate someone else's words.
Check 'BOUNDARY: the upper block appears NOWHERE in the emitted doc block' `
  ((Count-Phrase $blk['BlockBoundary'] 'This note belongs to the section ABOVE') -eq 0) `
  ($blk['BlockBoundary'] -replace "`n",' | ')

# --- (2) RULING D-5: demoted, not discarded. --------------------------------
Check 'D-5: the foreign-symbol note is NOT the summary' `
  ((Get-Summary $blk['ForeignNote']) -eq '') ("got=[" + (Get-Summary $blk['ForeignNote']) + "]")
Check 'D-5: ... and it is NOT discarded -- it is in <remarks>' `
  (($blk['ForeignNote'] -match '<remarks>') -and `
   ((Count-Phrase $blk['ForeignNote'] 'SourceStampString used to live here.') -eq 1)) `
  ($blk['ForeignNote'] -replace "`n",' | ')

# --- (3) RULING D-5's conservatism, both arms. ------------------------------
Check 'D-5 (conservatism): a summary naming a symbol in ITS OWN unit keeps its summary' `
  ((Get-Summary $blk['LocalMention']) -match '^LocalHelper does the actual work') `
  ("got=[" + (Get-Summary $blk['LocalMention']) + "]")
Check 'D-5 (conservatism): a single-cased English word that is also a foreign symbol does NOT demote' `
  ((Get-Summary $blk['PlainProse']) -match '^Backup happens before the copy step') `
  ("got=[" + (Get-Summary $blk['PlainProse']) + "]")

# --- (4) COPY, NEVER MOVE. --------------------------------------------------
foreach ($orig in @(
    '^// This note belongs to the section ABOVE and is not BlockBoundary''s comment\.$',
    '^// Real prose that must become the summary\.$',
    '^// SourceStampString used to live here\. It MOVED to harvest_boundary_other so$',
    '^// Backup happens before the copy step\. The first word is an ordinary English$')) {
  Check "COPY: the original // line is still present, unchanged -- $orig" `
    (@($lines | Where-Object { $_ -match $orig }).Count -eq 1) ''
}

# ===========================================================================
# APPLY (cycle 2) -- byte-identical, no human edit in between.
# ===========================================================================
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
$md5Cycle2 = Get-FileMd5 $tgt
Check 'IDEMPOTENT: a second --apply is byte-identical' ($md5Cycle1 -eq $md5Cycle2) `
  "md5_1=$md5Cycle1 md5_2=$md5Cycle2"

# ===========================================================================
# RULING D-1 -- the ownership handover, then a third apply.
# ===========================================================================
# A human adopts the engine's second paragraph by deleting its marker. From
# that moment MergeComment preserves the line as hand prose -- and the harvest,
# recomputed from the // comment still sitting in the file, would re-emit its
# own copy underneath it.
$before = [IO.File]::ReadAllLines($tgt)
$hits   = @($before | Where-Object { $_ -match 'drag-lint:auto -->A second paragraph that a human adopts' })
Check 'D-1 (setup): the harvested paragraph is present ONCE and carries its marker' `
  ($hits.Count -eq 1) ("hits=" + $hits.Count)

$edited = $before | ForEach-Object { $_ -replace '<!-- drag-lint:auto -->(A second paragraph that a human adopts)','$1' }
$sw = New-Object System.IO.StreamWriter($tgt, $false, [Text.Encoding]::ASCII)
foreach ($l in $edited) { $sw.Write($l); $sw.Write("`r`n") }
$sw.Close()

& $exePath index $sc --db $db 2>$null | Out-Null
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
& $exePath index $sc --db $db 2>$null | Out-Null

$lines3 = [IO.File]::ReadAllLines($tgt)
$ln3    = Get-DeclLine $db 'OwnershipHandover'
$blk3   = Get-DocBlockAtLine $lines3 $ln3
Check 'D-1: after the ownership handover the paragraph appears EXACTLY ONCE' `
  ((Count-Phrase $blk3 'A second paragraph that a human adopts') -eq 1) `
  ("count=" + (Count-Phrase $blk3 'A second paragraph that a human adopts') + " blk=[" + ($blk3 -replace "`n",' | ') + "]")
Check 'D-1 (de-vacuator): the paragraph was not simply deleted -- the human''s copy survives' `
  ((Count-Phrase $blk3 'A second paragraph that a human adopts') -ge 1) `
  ($blk3 -replace "`n",' | ')
Check 'D-1: the surviving copy is the HUMAN''s -- unmarked' `
  (-not ($blk3 -match '<!-- drag-lint:auto -->A second paragraph')) `
  ($blk3 -replace "`n",' | ')

# --- ENCODING: the repo's invariant, asserted on the written file. ----------
$bytes = [IO.File]::ReadAllBytes($tgt)
Check 'ENCODING: the applied file is strict 7-bit ASCII' `
  (@($bytes | Where-Object { $_ -ge 128 }).Count -eq 0) ''
$raw = [IO.File]::ReadAllText($tgt)
Check 'ENCODING: the applied file has no bare LF (CRLF throughout)' `
  (([regex]::Matches($raw, "(?<!`r)`n")).Count -eq 0) ''
# The 5ebde68 corruption was an unprefixed interior line turning the rest of a
# doc block into code. Matched on spellings the FIXTURE's own prose does not
# carry -- it discusses <remarks> in its header, so that opener is not a usable
# signature for "this line was emitted by the engine".
Check 'PREFIX: every line of every emitted doc region begins with /// after its indentation' `
  (@($lines3 | Where-Object { $_ -match 'drag-lint:auto|</summary>|</remarks>' } |
     Where-Object { $_ -notmatch '^\s*///' }).Count -eq 0) `
  (($lines3 | Where-Object { $_ -match 'drag-lint:auto|</summary>|</remarks>' } |
     Where-Object { $_ -notmatch '^\s*///' }) -join ' | ')

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
