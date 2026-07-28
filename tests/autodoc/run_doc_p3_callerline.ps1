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

  B  fixtures\docp3\callerline_mixed.pas + callerline_mixedcross.pas, indexed
     TOGETHER. Ping's caller list holds one 'certain' entry (NearCaller, same
     unit, real call_edges row) and one 'unverified' entry (FarCaller, cross
     unit, no row). This scenario is NOT optional and it is not redundant with
     A: a suite built only from uniform lists passes identically whether the
     marker is correctly suppressed or never emitted at all. Only a mixed list
     tells those two apart.

     B's preconditions are re-derived FROM THE INDEX (dump-call-edges and
     ambiguous-calls), never from the rendered line the scenario is about to
     assert on. If the resolver ever learns to resolve the cross-unit site the
     precondition fails and names the fixture, instead of leaving B vacuous.

  LOAD-BEARING PROOFS (see task-4-report.md for the transcripts). Each mutation
  leaves the mechanism reachable and changes only its answer, and each reddens a
  DIFFERENT group:
    M1  RefVerb forced to 'Called from: '  -> A LABEL reddens, A MARKER + B green
    M2  Mixed forced True  (pre-fix rule)  -> A MARKER reddens, A LABEL + B green
    M3  Mixed forced False (over-suppress) -> B reddens, all of A green

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
foreach ($l in $calledFromLines) {
  $e = Split-RefEntries $l
  Check 'A MARKER: uniformly-CERTAIN list still renders plain (unchanged)' `
    (($e.Count -eq 1) -and (-not $e[0].Marked)) ($l.Trim())
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
$pingEdges = @([regex]::Matches($edges, '(?m)^\s*\d+\|callerline_mixed\.Ping\|certain\s*$'))
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
