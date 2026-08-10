<#
  run_doc_p3_callerline.ps1 -- Auto-Document Phase 3, Task 4:
  the caller line's LABEL and its ' ?' UNCERTAINTY MARKER.

  TWO RULES, ONE LINE
  -------------------
  Both defects land on the single reference line RenderFactsBlock emits from
  TDocFacts.CalledFrom.

  (1) THE LABEL IS KIND-SELECTED.  "Called from:" is a claim that the symbol is
      CALLED. For a record, class, interface, constant or type alias that is
      simply false -- those references are USAGES. The YADF rollout rendered
      "Called from:" over what were plain type mentions. The verb now comes
      from the documented symbol's own kind: a callable reads "Called from:",
      everything else reads "Used by:". Contents, cap, "(+N more)" and the
      marker rule below are all unchanged; only the label differs.

  (2) THE ' ?' MARKER IS EMITTED ONLY WHEN THE LIST IS MIXED.  A marker present
      on EVERY entry distinguishes nothing. What survives is comparative: within
      one list, which entries are the weaker ones. So a uniformly-uncertain list
      now renders plain, exactly as a uniformly-certain one always has.

  WHAT THE SATURATION ACTUALLY IS -- MEASURED, NOT INHERITED
  ---------------------------------------------------------
  The plan justified rule (2) with "it fired 49 times out of 49" on the YADF
  rollout. That number is STALE: it predates T3i, which stopped counting
  'member-access' refs as unresolved call sites and so removed one of the causes
  of the saturation. Re-measured on the pre-T4 tree at 6bcc0a3 -- whose last
  engine-affecting commit is f5fc66e, the three after it being test-only, so the
  binary measured is f5fc66e's -- by running `document --unit` (dry) over every
  .pas file with the shipping Win64 exe and parsing every emitted reference line:

    YADF        (141 files, YADF.sqlite)        99 lines, 263 entries
                  lines: 28 all-certain / 65 all-uncertain / 6 MIXED
                  entries carrying ' ?': 186 = 70.7%
    drag-lint   (144 files, self-index)       1126 lines, 3039 entries
                  lines: 211 all-certain / 832 all-uncertain / 83 MIXED
                  entries carrying ' ?': 2594 = 85.4%

  So the marker is no longer on literally every entry -- but 66% (YADF) and 74%
  (drag-lint) of all reference LINES are still uniformly uncertain, and those
  are exactly the lines rule (2) strips. The rule is unchanged by the correction;
  what changes is that MIXED lines demonstrably EXIST in real indexes (6 and 83
  of them), so suppressing on uniformity does not erase the signal -- it
  concentrates it.

  SCENARIOS
  ---------
  A  fixtures\docp3\callerline.pas, indexed ALONE, document --unit --apply.
     TPoint2 is a record whose only reference arrives 'unverified', so it
     carries BOTH defects on one line and both fixes are visible on it.
     MakePoint/SumPoint are the controls: OriginSum calls each of them from
     inside the same unit, which resolves, so their lists are uniformly
     CERTAIN and must stay plain and must stay "Called from:".

     "Uniformly CERTAIN" is NOT observable in the rendered line: rule (2)
     strips the marker from a uniform list of EITHER kind, so a one-entry
     certain list and a one-entry uncertain list render the identical shape.
     A therefore derives the certainty FROM THE INDEX before it asserts
     anything about the line -- dump-call-edges must hold exactly one
     'certain' edge into each of MakePoint and SumPoint, and ambiguous-calls
     must report A's index with no unresolved call site at all. Review round
     1 measured what their absence cost: with OriginSum moved into a second
     unit (its calls become cross-unit, no call_edges row, both control lists
     uniformly UNCERTAIN) the applied file is shape-identical and ALL 27 of
     A's checks still passed -- including the one named "uniformly-CERTAIN
     list still renders plain", which was reading a uniformly-uncertain list.
     The preconditions are what make the control a control.

  B  fixtures\docp3\callerline_mixed.pas + callerline_mixedcross.pas, indexed
     TOGETHER. Ping's caller list holds one 'certain' entry (NearCaller, same
     unit, real call_edges row) and one 'unverified' entry (FarCaller, which
     calls Ping through a receiver of a type no unit declares, so the site has
     no target by construction). This scenario is NOT optional and not redundant with
     A: a suite built only from uniform lists passes identically whether the
     marker is correctly suppressed or never emitted at all. Only a mixed list
     tells those two apart.

     BOTH scenarios' preconditions are re-derived FROM THE INDEX
     (dump-call-edges and ambiguous-calls), never from the rendered line the
     scenario is about to assert on. If the resolver ever learns to resolve
     B's unresolved site, or stops resolving A's same-unit ones, the
     precondition fails and names the fixture, instead of leaving the
     scenario vacuous.

     THIS ALREADY HAPPENED, AND IT IS WHY B'S FIXTURE LOOKS THE WAY IT DOES.
     B's unverified half was originally a plain cross-unit BARE call. Option 4
     (the unit-level rung: a bare call now resolves across a uses edge) made it
     resolve, both entries turned 'certain', and these preconditions failed by
     name rather than letting the marker assertions pass over a list that was no
     longer mixed. The lesson taken: a fixture must not rest on a LIMITATION,
     because the next improvement dissolves it. FarCaller now calls through a
     receiver whose type is declared nowhere -- unresolvable by construction, and
     the shape most of the real remainder actually has.

  LOAD-BEARING PROOFS (see task-4-report.md for the transcripts). Each mutation
  leaves the mechanism reachable and changes only its answer, and each reddens a
  DIFFERENT group:
    M1  RefVerb forced to 'Called from: '  -> A LABEL reddens, A MARKER + B green
    M2  Mixed forced True  (pre-fix rule)  -> A MARKER reddens, A LABEL + B green
    M3  Mixed forced False (over-suppress) -> B reddens, all of A green
    M4  (fixture mutation, review round 1) OriginSum moved into a second unit,
        so A's control arm becomes uniformly UNCERTAIN -> 5 FAIL: the three
        A PRECONDITION checks and the two 'single entry is the
        callerline.OriginSum edge' checks. Every OTHER A check -- all 27 that
        existed before round 1, including 'uniformly-CERTAIN list still
        renders plain' -- stays GREEN on a uniformly-uncertain list. That is
        precisely the blindness these five exist to close.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fxA     = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\callerline.pas')).Path
$fxB1    = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\callerline_mixed.pas')).Path
$fxB2    = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\callerline_mixedcross.pas')).Path

# ---------------------------------------------------------------------------
# Helpers. Standalone by convention -- every runner in this directory carries
# its own copies rather than dot-sourcing a shared module.
# ---------------------------------------------------------------------------

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

# The contiguous run of ///-prefixed lines immediately above 1-based line
# $declLine1, per-line trimmed and newline-joined. Tolerates ONE leading blank
# line, mirroring FindDocRegionAbove's own AllowGap=1 default. Anchored by LINE
# NUMBER from a fresh reindex, never by a declaration regex: an apply rewrites
# the file and shifts every line below it, and this fixture spells
# `function MakePoint(AX, AY: Integer): TPoint2;` twice (interface and
# implementation), so a regex anchor would have to rely on "the first one wins".
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

# INTERFACE-section start line for $name, read back from the index via the
# engine's own query verb (index-first: no second parser, no python).
function Get-DeclLine([string]$db, [string]$name) {
  $j = (& $exePath query --name $name --db $db --json 2>$null) -join "`n"
  $o = $null; try { $o = ($j | ConvertFrom-Json) } catch { return 0 }
  if ($null -eq $o) { return 0 }
  foreach ($r in @($o)) { if ($r.section -eq 'interface') { return [int]$r.start_line } }
  return 0
}

# Split one rendered reference line into its entries. An entry is
# '<Display> (<Location>)' optionally followed by ' ?'. The trailing
# '(+N more)' suffix is removed FIRST so it is never mistaken for an entry.
# Returns objects with .Text and .Marked.
function Split-RefEntries([string]$line) {
  $body = $line -replace '\s*\(\+\d+ more\)\s*$',''
  $body = $body -replace '^.*?(Called from:|Used by:)\s*',''
  $res = New-Object System.Collections.Generic.List[object]
  foreach ($m in [regex]::Matches($body, '([^,()]+)\(([^()]*)\)(\s\?)?')) {
    $res.Add([pscustomobject]@{ Text = $m.Value.Trim(); Name = $m.Groups[1].Value.Trim(); Marked = $m.Groups[3].Success })
  }
  return $res
}

# Every ' ?' marker in $text, in its exact rendered shape: the close paren of an
# entry's location, a single space, a question mark. Counted over the WHOLE file
# rather than only over reference lines, so a marker leaking onto some other
# line would be caught too.
function Count-Markers([string]$text) { return ([regex]::Matches($text, '\)\s\?')).Count }

# --- dump-call-edges: LAYOUT and CONTENT are separate questions (register K19) -
# The preconditions below used to match a whole line,
# `^\s*\d+\|<qname>\|certain$`, against the raw dump. That conflates two
# unrelated failures: THE EDGE IS MISSING (what the check is named for) and THE
# DUMP GAINED A COLUMN (a change in a diagnostic verb's output, nothing to do
# with resolution). A fourth field would redden every one of them under a name
# that blames the resolver.
#
# So the layout is asserted ONCE, by its own name, and the edge preconditions
# read FIELDS. The verb's contract is `ref_id|target_qname|confidence`
# (DRagLint.CLI.pas DoDumpCallEdges), one row per resolved edge, no header.
function Parse-CallEdges([string]$raw) {
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($l in ($raw -split "`n")) {
    $t = $l.Trim()
    if ($t -eq '' -or $t -notlike '*|*') { continue }
    $f = $t -split '\|'
    $out.Add([pscustomobject]@{
      Fields     = $f
      RefId      = $f[0]
      QName      = $(if ($f.Count -gt 1) { $f[1] } else { '' })
      Confidence = $(if ($f.Count -gt 2) { $f[2] } else { '' })
    })
  }
  return $out
}

function Check-EdgeDumpLayout([string]$tag, $parsed, [string]$raw) {
  $widths = @(@($parsed | ForEach-Object { $_.Fields.Count }) | Sort-Object -Unique)
  Check "$tag FORMAT: dump-call-edges still emits exactly ref_id|target_qname|confidence (3 fields)" `
    ((@($parsed).Count -gt 0) -and ($widths.Count -eq 1) -and ($widths[0] -eq 3)) `
    ("field widths " + ($widths -join ',') + " over " + @($parsed).Count + " row(s); raw=" + ($raw -replace "`n",' / '))
}

# Edges into $qname at $confidence, read by FIELD so a layout change cannot be
# mistaken for a missing edge.
function Edges-Into($parsed, [string]$qname, [string]$confidence) {
  return @($parsed | Where-Object { $_.QName -eq $qname -and $_.Confidence -eq $confidence })
}

Push-Location C:\TEMP
try {

# ===========================================================================
# SCENARIO A -- callerline.pas alone: the record's label + the uniform list
# ===========================================================================
Write-Host ''
Write-Host '=== SCENARIO A: callerline.pas, document --unit --apply ===' -ForegroundColor Cyan

$sa = Join-Path C:\TEMP 'draglint_docp3_callerline_a'
if (Test-Path $sa) { Remove-Item $sa -Recurse -Force }
New-Item -ItemType Directory -Path $sa | Out-Null
$tgtA = Join-Path $sa 'callerline.pas'
$dbA  = Join-Path $sa 'a.sqlite'
Copy-Item $fxA $tgtA -Force

& $exePath index $sa --db $dbA 2>$null | Out-Null

# --- Preconditions, re-derived from the INDEX, not from the rendered line. ---
# A exists to hold BOTH arms of the marker rule in one file: TPoint2's
# uniformly-UNCERTAIN list and MakePoint/SumPoint's uniformly-CERTAIN ones. But
# the two arms RENDER IDENTICALLY -- rule (2) strips the marker from a uniform
# list of either kind -- so no check on the applied file can tell them apart.
# Review round 1 proved the cost: move OriginSum into a second unit, its calls
# become cross-unit with no call_edges row, both control lists turn uniformly
# UNCERTAIN, and all 27 of A's checks still passed, including the one named
# "uniformly-CERTAIN list still renders plain". The control had silently become
# a second copy of the uncertain case. So assert -- from the index, BEFORE
# asserting how anything renders -- that the certain arm IS certain and the
# uncertain arm IS uncertain. Neither arm's kind is observable in the output
# these checks read, so neither may be inherited from fixture prose.
$edgesA = (& $exePath dump-call-edges --db $dbA 2>$null) -join "`n"
$parsedA = Parse-CallEdges $edgesA
Check-EdgeDumpLayout 'A' $parsedA $edgesA
foreach ($nm in @('MakePoint','SumPoint')) {
  $eA = Edges-Into $parsedA "callerline.$nm" 'certain'
  Check "A PRECONDITION: the index holds exactly ONE certain call edge into $nm" ($eA.Count -eq 1) `
    ("edges=" + ($edgesA -replace "`n",' / '))
}
$ambA = (& $exePath ambiguous-calls --db $dbA 2>$null) -join "`n"
Check 'A PRECONDITION: A''s index holds NO unresolved call site (the control lists are uniformly CERTAIN, not merely unmarked)' `
  (($ambA -match '(?m)^0 ambiguous call\(s\)') -and (-not ($ambA -match '\[unverified\]'))) `
  ($ambA -replace "`n",' / ')
# The UNCERTAIN arm needs the mirror-image precondition, for the same reason:
# 'no marker' is equally true of a CERTAIN list, so without this the TPoint2
# check below would read its uncertainty off fixture prose rather than off the
# index -- the identical hole review round 1 found on the certain arm. A record
# is never a call target (CanBeCallTarget False, so Doc.Facts hardcodes
# 'unverified'), which is why this holds by construction today and is cheap to
# assert -- and why it is worth asserting against the day that stops being true.
$tpEdgesA = @($parsedA | Where-Object { $_.QName -eq 'callerline.TPoint2' })
Check 'A PRECONDITION: the index holds NO call edge into TPoint2 (its list is uniformly UNCERTAIN, not merely unmarked)' `
  ($tpEdgesA.Count -eq 0) ("edges=" + ($edgesA -replace "`n",' / '))

& $exePath document --unit $tgtA --db $dbA --apply 2>$null | Out-Null
$md5Cycle1 = Get-FileMd5 $tgtA
# Reindex so the start lines below describe the file the apply just wrote.
& $exePath index $sa --db $dbA 2>$null | Out-Null

$textA  = [IO.File]::ReadAllText($tgtA)
$linesA = [IO.File]::ReadAllLines($tgtA)

$blocks = @{}
foreach ($nm in @('TPoint2','MakePoint','SumPoint')) {
  $ln = Get-DeclLine $dbA $nm
  Check "A: $nm resolved to an interface declaration line" ($ln -gt 0) "line=$ln"
  $blocks[$nm] = Get-DocBlockAtLine $linesA $ln
}

# --- Rule (2)'s non-vacuity control, asserted BEFORE the marker count. -------
# 'no marker anywhere' is trivially true over a file with no reference lines at
# all. Pin the exact shape the file must have: ONE 'Used by:' line (TPoint2) and
# TWO 'Called from:' lines (MakePoint, SumPoint). If a future change stops
# emitting reference lines here, this fails instead of the marker check quietly
# passing over nothing.
#
# The '^\s*///' half of each filter is load-bearing, not decoration: the
# fixture's own header comment DISCUSSES both labels in prose, and without it
# this control read 7 'Called from:' lines where the engine emitted 2. A filter
# that matches the thing it is describing is the exact shape of a vacuous test.
$usedByLines     = @($linesA | Where-Object { $_ -match '^\s*///' -and $_ -match 'Used by:' })
$calledFromLines = @($linesA | Where-Object { $_ -match '^\s*///' -and $_ -match 'Called from:' })
Check 'A CONTROL: exactly ONE "Used by:" line in the applied file' ($usedByLines.Count -eq 1) `
  ("count=" + $usedByLines.Count)
Check 'A CONTROL: exactly TWO "Called from:" lines in the applied file' ($calledFromLines.Count -eq 2) `
  ("count=" + $calledFromLines.Count)

# --- Rule (1): the label is kind-selected. ----------------------------------
Check 'A LABEL: TPoint2 (a RECORD) renders "Used by:"' ($blocks['TPoint2'] -match 'Used by:') `
  ($blocks['TPoint2'] -replace "`n",' | ')
Check 'A LABEL: TPoint2 does NOT render "Called from:"' (-not ($blocks['TPoint2'] -match 'Called from:')) `
  ($blocks['TPoint2'] -replace "`n",' | ')
foreach ($nm in @('MakePoint','SumPoint')) {
  Check "A LABEL: $nm (a FUNCTION) renders `"Called from:`"" ($blocks[$nm] -match 'Called from:') `
    ($blocks[$nm] -replace "`n",' | ')
  Check "A LABEL: $nm does NOT render `"Used by:`"" (-not ($blocks[$nm] -match 'Used by:')) `
    ($blocks[$nm] -replace "`n",' | ')
}

# --- Rule (2): a uniform list carries no marker. ----------------------------
# TPoint2's single entry is 'unverified' (uniformly UNCERTAIN -- the case rule
# (2) newly suppresses); MakePoint's and SumPoint's are 'certain' (uniformly
# CERTAIN -- always rendered plain, and must stay that way).
Check 'A MARKER: the whole applied file carries ZERO " ?" markers' ((Count-Markers $textA) -eq 0) `
  ("markers=" + (Count-Markers $textA))
if ($usedByLines.Count -eq 1) {
  $tpEntries = Split-RefEntries $usedByLines[0]
  Check 'A MARKER: TPoint2 uniformly-UNCERTAIN list has 1 entry and no marker' `
    (($tpEntries.Count -eq 1) -and (-not $tpEntries[0].Marked)) ($usedByLines[0].Trim())
} else {
  Check 'A MARKER: TPoint2 uniformly-UNCERTAIN list has 1 entry and no marker' $false `
    'no single "Used by:" line to inspect -- see the CONTROL above'
}
# Located THROUGH each symbol's own block and NAMED for it. Iterating the two
# lines anonymously gave both checks the same name, so a failure could not say
# whether MakePoint or SumPoint had regressed. The second check ties the
# rendered entry back to the call edge the PRECONDITION above asserted certain,
# so 'plain' is read off a list that is known-certain rather than merely
# known-unmarked.
foreach ($nm in @('MakePoint','SumPoint')) {
  $l = @(($blocks[$nm] -split "`n") | Where-Object { $_ -match 'Called from:' })[0]
  $e = Split-RefEntries $l
  Check "A MARKER: $nm's uniformly-CERTAIN list still renders plain (unchanged)" `
    (($e.Count -eq 1) -and (-not $e[0].Marked)) (("" + $l).Trim())
  Check "A MARKER: $nm's single entry is the callerline.OriginSum edge the PRECONDITION asserted certain" `
    (($e.Count -eq 1) -and ($e[0].Name -eq 'callerline.OriginSum')) (("" + $l).Trim())
}

# --- Idempotency: reindex + a second --apply is byte-identical. --------------
& $exePath document --unit $tgtA --db $dbA --apply --json 2>$null | Out-Null
$md5Cycle2 = Get-FileMd5 $tgtA
Check 'A IDEMPOTENT: a second --apply after a reindex is byte-identical' ($md5Cycle1 -eq $md5Cycle2) `
  "c1=$md5Cycle1 c2=$md5Cycle2"

# Every emitted /// line stays 7-bit ASCII.
$badA = @()
foreach ($l in $linesA) { if ($l -match '^\s*///') { foreach ($ch in $l.ToCharArray()) { if ([int]$ch -gt 126) { $badA += $l; break } } } }
Check 'A: every emitted /// line is 7-bit ASCII' ($badA.Count -eq 0) ($badA -join ' | ')

# ===========================================================================
# SCENARIO B -- a genuinely MIXED list keeps the marker, on the weak entry only
# ===========================================================================
Write-Host ''
Write-Host '=== SCENARIO B: callerline_mixed.pas + callerline_mixedcross.pas ===' -ForegroundColor Cyan

$sb = Join-Path C:\TEMP 'draglint_docp3_callerline_b'
if (Test-Path $sb) { Remove-Item $sb -Recurse -Force }
New-Item -ItemType Directory -Path $sb | Out-Null
Copy-Item $fxB1 (Join-Path $sb 'callerline_mixed.pas') -Force
Copy-Item $fxB2 (Join-Path $sb 'callerline_mixedcross.pas') -Force
$dbB = Join-Path $sb 'b.sqlite'
& $exePath index $sb --db $dbB 2>$null | Out-Null

# --- Preconditions, re-derived from the INDEX, not from the rendered line. ---
$edges = (& $exePath dump-call-edges --db $dbB 2>$null) -join "`n"
$parsedB = Parse-CallEdges $edges
Check-EdgeDumpLayout 'B' $parsedB $edges
$pingEdges = Edges-Into $parsedB 'callerline_mixed.Ping' 'certain'
Check 'B PRECONDITION: the index holds exactly ONE certain call edge into Ping' ($pingEdges.Count -eq 1) `
  ("edges=" + ($edges -replace "`n",' / '))

$amb = (& $exePath ambiguous-calls --db $dbB 2>$null) -join "`n"
Check 'B PRECONDITION: the cross-unit site FarCaller is UNRESOLVED in the index' `
  ($amb -match 'callerline_mixedcross\.FarCaller\s+\(callerline_mixedcross\.pas\)\s+\[unverified\]') `
  ($amb -replace "`n",' / ')
Check 'B PRECONDITION: NearCaller is NOT in the unresolved set (so the two halves really differ)' `
  (-not ($amb -match 'callerline_mixed\.NearCaller')) ($amb -replace "`n",' / ')

# --- The rendered line. -----------------------------------------------------
$outB  = (& $exePath document --qname callerline_mixed.Ping --db $dbB 2>$null) -join "`n"
$lineB = ($outB -split "`r?`n" | Where-Object { $_ -match '(Called from:|Used by:)' } | Select-Object -First 1)
Check 'B: a reference line was rendered for Ping' ($null -ne $lineB -and $lineB -ne '') $outB
Check 'B LABEL: Ping (a PROCEDURE) renders "Called from:"' ($lineB -match 'Called from:') $lineB

$eB = Split-RefEntries $lineB
Check 'B: the mixed list renders exactly TWO entries' ($eB.Count -eq 2) `
  ("entries=" + $eB.Count + " :: " + $lineB.Trim())

if ($eB.Count -eq 2) {
  # THE assertion this whole scenario exists for: on a MIXED list the marker is
  # still emitted, and it is on the UNCERTAIN entry ONLY. Rule (2) suppresses on
  # uniformity, never on the presence of certainty.
  Check 'B MARKER: exactly ONE of the two entries carries " ?"' `
    ((@($eB | Where-Object { $_.Marked })).Count -eq 1) ($lineB.Trim())
  $near = $eB | Where-Object { $_.Name -match 'NearCaller' }
  $far  = $eB | Where-Object { $_.Name -match 'FarCaller'  }
  Check 'B MARKER: the UNVERIFIED entry (FarCaller) carries " ?"' `
    (($null -ne $far) -and $far.Marked) ($lineB.Trim())
  Check 'B MARKER: the CERTAIN entry (NearCaller) does NOT carry " ?"' `
    (($null -ne $near) -and (-not $near.Marked)) ($lineB.Trim())
  # Ordering is unchanged by Task 4: the Facts builder emits certain first.
  Check 'B ORDER: the certain entry is rendered FIRST (ordering unchanged)' `
    ($eB[0].Name -match 'NearCaller') ($lineB.Trim())
}

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
