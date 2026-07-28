<#
  run_doc_p3_strip_wrongsymbol.ps1 -- Auto-Document Phase 3 Task 3j, register
  item S1: `document --qname Y --strip` must never delete a DIFFERENT symbol's
  doc block.

  THE DEFECT. TDocStripper.StripSymbolRegion accepted a /// region whose 1-based
  end line fell anywhere in [ADeclLine-2, ADeclLine-1]. The ADeclLine-2 half
  exists to tolerate a single BLANK-line gap -- but the code never checked that
  the intervening line was blank. So for a DOCUMENTED declaration X immediately
  followed by an UNDOCUMENTED declaration Y, evaluating Y produced the window
  [XLine-1, XLine] and X's block ends at XLine-1: it matched, and
  `--qname Y --strip --apply` DELETED X's block. The "gap" it tolerated was
  declaration X itself.

  This is the SIBLING of the collision T3d2 fixed (see
  run_doc_p3_strip_collision.ps1). That one is about deleting ONE region TWICE
  and was fixed by de-duplicating on the resolved region; de-duplication does
  nothing about deleting the WRONG symbol's region ONCE, which is this runner.

  Fixture fixtures\docp3\strip_wrongsymbol.pas -- every /// block is
  engine-owned by construction (marker baked in by hand, as strip_static.pas
  does it), so no `document --apply` run is needed and no assertion here depends
  on what the miner happens to produce for these trivial routines:

  the RELATIVE geometry of each shape is asserted by the runner itself (see
  FIXTURE PREMISES), so editing the fixture cannot silently retarget a check.
  v(ADP3 T3j review round 2, folded 3): the absolute line numbers below are
  ORIENTATION ONLY and are NOT asserted -- every check resolves its declaration
  through Get-LineNo at run time. They were 3 low for one commit after the
  fixture's header comment grew, which is exactly why they must not be presented
  as though something verifies them. Trust the premises, not these:

    Alpha  (~line 36) -- documented: a marked <summary> plus an
                         AUTO_BEGIN..AUTO_END facts fence inside <remarks>
                         (~lines 30-35).
    Beta   (~line 37) -- UNdocumented, on the line DIRECTLY AFTER Alpha.
                         SHAPE 1, the defect: Alpha's block ends at
                         BetaLine-2, so the intervening line is Alpha's own
                         DECLARATION.
    Gamma  (~line 41) -- SHAPE 2, the legitimate gap: its marked <summary> sits
                         with exactly ONE BLANK line between it and the
                         declaration. Must STILL be stripped -- a fix that
                         rejects this is worse than the defect it closes.
    Epsilon(~line 46) -- SHAPE 3: TWO blank lines above the declaration.
                         Already outside the window; must stay outside.
    Zeta   (~line 50) -- SHAPE 4: ONE intervening line that is an ordinary '//'
                         comment -- non-blank, but not a declaration either. The
                         shape that separates "the gap is blank" from "no other
                         DECLARATION is in the gap"; see SCENARIO E.

  SCENARIO A -- SHAPE 1 + the anti-vacuity control. `--qname Beta --strip
  --apply` must report ZERO and leave the file byte-identical. Then, on that
  SAME file, `--qname Alpha --strip --apply` must report 1 tag / 1 block and
  remove the block -- which is what makes Scenario A's zeros a genuine
  REJECTION rather than a vacuous pass on an unstrippable block.

  SCENARIO B -- SHAPE 2: `--qname Gamma --strip --apply` still strips, the
  blank line that formed the gap survives, and the neighbouring blocks are
  untouched.

  SCENARIO C -- SHAPE 3: `--qname Epsilon --strip --apply` reports zero and
  leaves the file byte-identical.

  SCENARIO D -- premise: the whole-file path (`--unit --strip --apply`, which
  has NO window at all) removes all four blocks -- 4 tags, 1 block. This is
  the independent proof that every block in this fixture is genuinely
  engine-owned, so the zeros in A, C and E cannot be an artifact of a fixture
  nothing could strip.

  SCENARIO E -- SHAPE 4: an ordinary-comment gap IS stripped, because
  `document --apply` claims it. The author's comment line itself must survive.

  SCENARIO F -- THE APPLY/STRIP AGREEMENT TABLE, and the reason this runner
  exists in its current form. For all FIVE gap shapes it dry-runs BOTH paths and
  asserts they reach the same verdict, plus what that verdict must be. This is
  the invariant stated directly: a region `--apply` claims must be one `--strip`
  removes, or the engine can write a block the user cannot take back.

  HISTORY, because it explains the shape of this file. T3j's first fix required
  the gap line to be BLANK. That closed the wrong-symbol defect but made --strip
  NARROWER than --apply, which is a worse defect of the same family. The shipped
  fix instead has all three attribution sites -- index capture, apply, strip --
  read ONE shared predicate (DRagLint.Core.Model.DocRegionFitsDecl), so they
  cannot disagree, and SCENARIO F is what proves it at the behaviour level.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\strip_wrongsymbol.pas')).Path

# Contiguous run of ///-prefixed lines immediately above the FIRST line matching
# $declPattern; $null when the declaration is absent, '' when it has no ///
# block. Same scan-upward idiom run_doc_p3_strip.ps1 uses -- scoped to ONE
# declaration so an assertion can never be satisfied by a DIFFERENT
# declaration's block earlier in the file, which is precisely the confusion
# this runner exists to detect.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return ($blockLines -join "`n")
}

# 1-based line number of the FIRST line matching $pattern, or 0.
function Get-LineNo([string[]]$lines, [string]$pattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i + 1 } }
  return 0
}

# Fresh scratch dir holding its own copy of the fixture plus its own index, so
# no scenario can observe another's writes.
function New-Case([string]$name) {
  $dir = Join-Path C:\TEMP "draglint_docp3stripwrong_$name"
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
  New-Item -ItemType Directory -Path $dir | Out-Null
  $target = Join-Path $dir 'strip_wrongsymbol.pas'
  Copy-Item $fixture $target -Force
  $db = Join-Path $dir "$name.sqlite"
  & $exePath index $dir --db $db 2>$null | Out-Null
  Check "${name}: index exits 0" ($LASTEXITCODE -eq 0)
  return @{ Dir = $dir; Target = $target; Db = $db }
}

Push-Location C:\TEMP
try {

# ===========================================================================
# FIXTURE PREMISES -- asserted, not assumed. Every window assertion below is
# arithmetic on these line numbers, so if the fixture is ever edited without
# updating this runner these fire instead of the checks silently testing a
# different shape.
# ===========================================================================
Write-Host ''
Write-Host '=== FIXTURE PREMISES ===' -ForegroundColor Cyan

$fx        = [IO.File]::ReadAllLines($fixture)
$alphaLine = Get-LineNo $fx '^function Alpha\(AValue: Integer\): Integer;'
$betaLine  = Get-LineNo $fx '^function Beta\(AValue: Integer\): Integer;'
$gammaLine = Get-LineNo $fx '^function Gamma\(AValue: Integer\): Integer;'
$epsLine   = Get-LineNo $fx '^function Epsilon\(AValue: Integer\): Integer;'
$zetaLine  = Get-LineNo $fx '^function Zeta\(AValue: Integer\): Integer;'

Check 'PREMISE: all five interface declarations are found' `
  ($alphaLine -gt 0 -and $betaLine -gt 0 -and $gammaLine -gt 0 -and $epsLine -gt 0 -and $zetaLine -gt 0) `
  "alpha=$alphaLine beta=$betaLine gamma=$gammaLine epsilon=$epsLine zeta=$zetaLine"
# SHAPE 1's whole point: Beta is on the line DIRECTLY after Alpha, so the line
# intervening between Alpha's block and Beta is Alpha's own declaration.
Check 'PREMISE SHAPE 1: Beta is declared on the line DIRECTLY after Alpha' `
  ($betaLine -eq $alphaLine + 1) "alpha=$alphaLine beta=$betaLine"
Check 'PREMISE SHAPE 1: Alpha carries a /// block; Beta carries NONE' `
  (($fx[$alphaLine - 2].TrimStart().StartsWith('///')) -and (-not $fx[$betaLine - 2].TrimStart().StartsWith('///'))) `
  "aboveAlpha=$($fx[$alphaLine-2]) aboveBeta=$($fx[$betaLine-2])"
# The window Beta tolerates is [BetaLine-2, BetaLine-1]; Alpha's block ends at
# BetaLine-2. State that explicitly -- this is the collision itself.
Check 'PREMISE SHAPE 1: Alpha''s block ENDS on line BetaLine-2, i.e. inside Beta''s tolerated window' `
  ($fx[$betaLine - 3].TrimStart().StartsWith('///')) "line$($betaLine-2)=$($fx[$betaLine-3])"
Check 'PREMISE SHAPE 1: the intervening line (BetaLine-1) is NOT blank -- it is Alpha''s declaration' `
  ($fx[$betaLine - 2].Trim() -ne '') "line$($betaLine-1)=$($fx[$betaLine-2])"

# SHAPE 2: exactly ONE blank line between Gamma's block and its declaration.
Check 'PREMISE SHAPE 2: exactly ONE blank line sits between Gamma''s /// block and its declaration' `
  (($fx[$gammaLine - 2].Trim() -eq '') -and ($fx[$gammaLine - 3].TrimStart().StartsWith('///'))) `
  "line$($gammaLine-1)='$($fx[$gammaLine-2])' line$($gammaLine-2)='$($fx[$gammaLine-3])'"

# SHAPE 3: TWO blank lines -- the block ends at EpsilonLine-3, outside the window.
Check 'PREMISE SHAPE 3: TWO blank lines sit between Epsilon''s /// block and its declaration' `
  (($fx[$epsLine - 2].Trim() -eq '') -and ($fx[$epsLine - 3].Trim() -eq '') -and ($fx[$epsLine - 4].TrimStart().StartsWith('///'))) `
  "line$($epsLine-1)='$($fx[$epsLine-2])' line$($epsLine-2)='$($fx[$epsLine-3])' line$($epsLine-3)='$($fx[$epsLine-4])'"

# SHAPE 4: exactly ONE intervening line that is NEITHER blank NOR a declaration.
# Both halves matter and both are asserted: non-blank is what makes the blank
# test refuse it (SCENARIO E), and "not a declaration" is what makes it the ONE
# shape where this unit's blank test and FindDocRegionAbove's declaration test
# disagree. Without these, SCENARIO E could silently degenerate into a duplicate
# of SHAPE 1 (non-blank, but a declaration) and stop testing the narrowing.
Check 'PREMISE SHAPE 4: exactly ONE intervening line sits between Zeta''s /// block and its declaration' `
  (($zetaLine -ge 3) -and ($fx[$zetaLine - 3].TrimStart().StartsWith('///'))) `
  "line$($zetaLine-2)='$($fx[$zetaLine-3])'"
Check 'PREMISE SHAPE 4: that intervening line is NOT blank' `
  ($fx[$zetaLine - 2].Trim() -ne '') "line$($zetaLine-1)='$($fx[$zetaLine-2])'"
Check 'PREMISE SHAPE 4: that intervening line is NOT a declaration -- it is an ordinary // comment' `
  ($fx[$zetaLine - 2].TrimStart().StartsWith('//') -and (-not $fx[$zetaLine - 2].TrimStart().StartsWith('///'))) `
  "line$($zetaLine-1)='$($fx[$zetaLine-2])'"

# ===========================================================================
# SCENARIO A -- SHAPE 1: the defect, plus the anti-vacuity control.
# ===========================================================================
Write-Host ''
Write-Host '=== SCENARIO A: SHAPE 1 -- --qname Beta --strip must not touch Alpha''s block ===' -ForegroundColor Cyan

$A = New-Case 'a'
$pristine = [IO.File]::ReadAllBytes($A.Target)

# Premise: each qname resolves to exactly ONE row, so nothing below can be
# explained by a second row of the same name landing elsewhere in the file.
$betaRows = (& $exePath query --name Beta --db $A.Db --json 2>$null) -join "`n"
Check 'A: query --name Beta exits 0' ($LASTEXITCODE -eq 0)
Check 'A PREMISE: strip_wrongsymbol.Beta resolves to exactly ONE row' `
  ((([regex]::Matches($betaRows, '"qualified_name"\s*:\s*"strip_wrongsymbol\.Beta"')).Count) -eq 1) $betaRows

$outBeta = (& $exePath document --qname strip_wrongsymbol.Beta --db $A.Db --strip --apply --json 2>$null) -join ' '
Check 'A: document --qname Beta --strip --apply exits 0' ($LASTEXITCODE -eq 0)

# THE DEFECT ASSERTION. Anchored with [,}] -- the unanchored-substring shape
# removed from run_pipeline_tests.ps1:67 would let "tagsRemoved":10 satisfy a
# naive match for 0.
Check 'A CRITICAL: --qname Beta --strip reports ZERO removals (Beta has no doc block of its own)' `
  ($outBeta -match '"tagsRemoved":0[,}]' -and $outBeta -match '"blocksRemoved":0[,}]' -and $outBeta -match '"edits":0[,}]') $outBeta
Check 'A CRITICAL: --qname Beta --strip reports applied:false (nothing was written)' `
  ($outBeta -match '"applied":false[,}]') $outBeta

$afterBetaBytes = [IO.File]::ReadAllBytes($A.Target)
Check 'A CRITICAL: the file is BYTE-IDENTICAL to the pristine fixture -- Alpha''s block was NOT deleted' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$pristine, [byte[]]$afterBetaBytes))

# Content-level restatement of the same fact, so a failure names WHAT was lost
# rather than only that some bytes differ.
$afterBetaLines = [IO.File]::ReadAllLines($A.Target)
$alphaBlockAfterBeta = Get-DocBlockAbove $afterBetaLines '^function Alpha\(AValue: Integer\): Integer;'
Check 'A CRITICAL: Alpha''s marked <summary> survives' `
  ($null -ne $alphaBlockAfterBeta -and $alphaBlockAfterBeta -match [regex]::Escape('<summary><!-- drag-lint:auto -->Engine summary for Alpha.</summary>')) $alphaBlockAfterBeta
Check 'A CRITICAL: Alpha''s AUTO_BEGIN..AUTO_END facts fence survives' `
  ($null -ne $alphaBlockAfterBeta -and $alphaBlockAfterBeta -match [regex]::Escape('drag-lint:auto BEGIN') -and $alphaBlockAfterBeta -match [regex]::Escape('drag-lint:auto END')) $alphaBlockAfterBeta
Check 'A CRITICAL: both declarations survive intact' `
  (($afterBetaLines -contains 'function Alpha(AValue: Integer): Integer;') -and ($afterBetaLines -contains 'function Beta(AValue: Integer): Integer;'))

# --- ANTI-VACUITY CONTROL, on the SAME file --------------------------------
# Without this, "0 tags, 0 blocks" above would also be reported by a build that
# could not strip Alpha's block at all -- the assertion would pass for entirely
# the wrong reason. Stripping Alpha BY NAME must work, and must report the
# counts Beta's run refused to claim.
Write-Host '--- A control: the very same block IS strippable when its OWN symbol asks ---' -ForegroundColor DarkCyan
$outAlpha = (& $exePath document --qname strip_wrongsymbol.Alpha --db $A.Db --strip --apply --json 2>$null) -join ' '
Check 'A CONTROL: document --qname Alpha --strip --apply exits 0' ($LASTEXITCODE -eq 0)
Check 'A CONTROL: --qname Alpha --strip reports 1 tag, 1 block, 1 edit -- so Beta''s zeros were a REJECTION, not an unstrippable block' `
  ($outAlpha -match '"tagsRemoved":1[,}]' -and $outAlpha -match '"blocksRemoved":1[,}]' -and $outAlpha -match '"edits":1[,}]') $outAlpha
Check 'A CONTROL: --qname Alpha --strip reports applied:true' ($outAlpha -match '"applied":true[,}]') $outAlpha

$afterAlphaLines = [IO.File]::ReadAllLines($A.Target)
Check 'A CONTROL: Alpha''s block is now GONE' `
  ('' -eq (Get-DocBlockAbove $afterAlphaLines '^function Alpha\(AValue: Integer\): Integer;'))
Check 'A CONTROL: both declarations still survive after the real strip' `
  (($afterAlphaLines -contains 'function Alpha(AValue: Integer): Integer;') -and ($afterAlphaLines -contains 'function Beta(AValue: Integer): Integer;'))
# Rule 5: the emptied region collapses completely -- no stray blank line left
# where the block was, so `interface` is still followed by ONE blank line.
$ifaceNo = Get-LineNo $afterAlphaLines '^interface$'
Check 'A CONTROL: rule 5 leaves no stray blank -- exactly one blank line between `interface` and Alpha''s declaration' `
  ($ifaceNo -gt 0 -and $afterAlphaLines[$ifaceNo].Trim() -eq '' -and $afterAlphaLines[$ifaceNo + 1] -eq 'function Alpha(AValue: Integer): Integer;') `
  "after-interface='$($afterAlphaLines[$ifaceNo])' next='$($afterAlphaLines[$ifaceNo+1])'"

# ===========================================================================
# SCENARIO B -- SHAPE 2: the LEGITIMATE one-blank-line gap must keep working.
# ===========================================================================
Write-Host ''
Write-Host '=== SCENARIO B: SHAPE 2 -- the one-blank-line gap the window exists for ===' -ForegroundColor Cyan

$B = New-Case 'b'

$outGamma = (& $exePath document --qname strip_wrongsymbol.Gamma --db $B.Db --strip --apply --json 2>$null) -join ' '
Check 'B: document --qname Gamma --strip --apply exits 0' ($LASTEXITCODE -eq 0)
Check 'B CRITICAL: the one-blank-line gap is STILL stripped (1 tag, 0 blocks, 1 edit)' `
  ($outGamma -match '"tagsRemoved":1[,}]' -and $outGamma -match '"blocksRemoved":0[,}]' -and $outGamma -match '"edits":1[,}]') $outGamma
Check 'B CRITICAL: applied:true -- the gapped block was actually written away' `
  ($outGamma -match '"applied":true[,}]') $outGamma

$afterB = [IO.File]::ReadAllText($B.Target)
Check 'B CRITICAL: Gamma''s marked <summary> is GONE' `
  (-not $afterB.Contains('Engine summary for Gamma.'))
Check 'B: Gamma''s declaration survives' ($afterB.Contains('function Gamma(AValue: Integer): Integer;'))

# The gap's blank line is not part of the doc region, so rule 5 must not eat it
# and the strip must not merge Gamma's declaration into the preceding block.
$afterBLines = [IO.File]::ReadAllLines($B.Target)
$gammaAfter  = Get-LineNo $afterBLines '^function Gamma\(AValue: Integer\): Integer;'
Check 'B: the blank line that formed the gap still sits directly above Gamma''s declaration' `
  ($gammaAfter -gt 1 -and $afterBLines[$gammaAfter - 2].Trim() -eq '') "line$($gammaAfter-1)='$($afterBLines[$gammaAfter-2])'"
# v(ADP3 T3j): PINNING PRE-EXISTING BEHAVIOUR, not asserting a guarantee. This
# gapped block sat BETWEEN two blank lines -- the separator after Beta's
# declaration and the gap line itself -- so removing the block necessarily
# leaves those two blanks adjacent. Rule 5 removes exactly the /// lines and
# never a surrounding blank, by design ("no stray blank line is introduced"
# means none is ADDED, not that adjacent pre-existing blanks are coalesced).
# Measured identical before and after T3j's window fix -- this shape is
# ACCEPTED by the window in both builds, so the fix cannot have caused it. It is
# an independent second data point for the register's standing T17 note ("confirm
# on the YADF dry-run that --strip rule 5's blank remainder leaves no
# double-blank"), which had only ever been byte-proved for one fixture shape.
# Pinned so a future change to rule 5's blank handling is visible here rather
# than silent.
Check 'B (pinned, pre-existing): a gapped block between two blanks leaves the two blanks adjacent -- rule 5 removes /// lines only, it does not coalesce blanks' `
  ($gammaAfter -gt 2 -and $afterBLines[$gammaAfter - 3].Trim() -eq '') "line$($gammaAfter-2)='$($afterBLines[$gammaAfter-3])'"

# Scoping: stripping Gamma must not reach into either neighbour's block.
Check 'B: Alpha''s block is UNTOUCHED (scoped strip does not leak backwards)' `
  ($afterB.Contains('Engine summary for Alpha.') -and $afterB.Contains('drag-lint:auto BEGIN'))
Check 'B: Epsilon''s block is UNTOUCHED (scoped strip does not leak forwards)' `
  ($afterB.Contains('Engine summary for Epsilon.'))

# Idempotency: a second run over the already-stripped file changes nothing, and
# BOTH calls are exit-checked -- a crash on either would otherwise be
# indistinguishable from a genuine no-op to a byte comparison alone.
& $exePath index $B.Dir --db $B.Db 2>$null | Out-Null
Check 'B IDEMPOTENT: re-index before the second strip exits 0' ($LASTEXITCODE -eq 0)
$afterB1 = [IO.File]::ReadAllBytes($B.Target)
& $exePath document --qname strip_wrongsymbol.Gamma --db $B.Db --strip --apply --json 2>$null | Out-Null
Check 'B IDEMPOTENT: the second strip --apply itself exits 0' ($LASTEXITCODE -eq 0)
$afterB2 = [IO.File]::ReadAllBytes($B.Target)
Check 'B IDEMPOTENT: a second --qname Gamma --strip --apply is byte-identical' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterB1, [byte[]]$afterB2))

# ===========================================================================
# SCENARIO C -- SHAPE 3: a TWO-blank-line gap stays outside the window.
# ===========================================================================
Write-Host ''
Write-Host '=== SCENARIO C: SHAPE 3 -- a two-blank-line gap is still rejected ===' -ForegroundColor Cyan

$C = New-Case 'c'
$pristineC = [IO.File]::ReadAllBytes($C.Target)

$outEps = (& $exePath document --qname strip_wrongsymbol.Epsilon --db $C.Db --strip --apply --json 2>$null) -join ' '
Check 'C: document --qname Epsilon --strip --apply exits 0' ($LASTEXITCODE -eq 0)
Check 'C: a TWO-blank-line gap is rejected -- zero removals (the window is one line, and stays one line)' `
  ($outEps -match '"tagsRemoved":0[,}]' -and $outEps -match '"blocksRemoved":0[,}]' -and $outEps -match '"edits":0[,}]') $outEps
$afterC = [IO.File]::ReadAllBytes($C.Target)
Check 'C: the file is BYTE-IDENTICAL to pristine' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$pristineC, [byte[]]$afterC))
Check 'C: Epsilon''s block is still present' `
  ([IO.File]::ReadAllText($C.Target).Contains('Engine summary for Epsilon.'))

# ===========================================================================
# SCENARIO D -- premise: the WINDOWLESS whole-file path strips all three.
# This is what makes A's and C's zeros meaningful.
# ===========================================================================
Write-Host ''
Write-Host '=== SCENARIO D: premise -- the whole-file (windowless) path strips ALL FOUR blocks ===' -ForegroundColor Cyan

$D = New-Case 'd'
$outUnit = (& $exePath document --unit $D.Target --db $D.Db --strip --apply --json 2>$null) -join ' '
Check 'D: document --unit --strip --apply exits 0' ($LASTEXITCODE -eq 0)
Check 'D PREMISE: all four blocks ARE engine-owned -- the windowless path removes 4 tags and 1 block' `
  ($outUnit -match '"tagsRemoved":4[,}]' -and $outUnit -match '"blocksRemoved":1[,}]') $outUnit
$afterD = [IO.File]::ReadAllText($D.Target)
Check 'D PREMISE: no drag-lint:auto marker survives anywhere in the file' `
  (-not ($afterD -match 'drag-lint:auto'))
Check 'D PREMISE: all five declarations survive the whole-file strip' `
  ($afterD.Contains('function Alpha(AValue: Integer): Integer;') -and $afterD.Contains('function Beta(AValue: Integer): Integer;') -and `
   $afterD.Contains('function Gamma(AValue: Integer): Integer;') -and $afterD.Contains('function Epsilon(AValue: Integer): Integer;') -and `
   $afterD.Contains('function Zeta(AValue: Integer): Integer;'))

# ===========================================================================
# SCENARIO E -- SHAPE 4: a non-blank, NON-declaration gap must be STRIPPED,
# because the apply path claims it.
#
# This is the shape that distinguishes the two candidate predicates. "Is the gap
# blank?" refuses it; "is there another DECLARATION in the gap?" -- which is what
# FindDocRegionAbove actually asks, and therefore what `document --apply` does --
# tolerates it. An ordinary comment between a doc block and its declaration does
# not transfer ownership of that block to anything.
#
# T3j's FIRST attempt required blankness. It closed the wrong-symbol defect but
# created a worse one: `--apply` would claim and rewrite this block while
# `--strip` refused to remove it, so the engine could write a block the user
# could never take back through the same verb -- an apply/strip asymmetry, which
# is the invariant --strip exists to uphold. Fixed by reading the SAME shared
# predicate the apply path reads (DRagLint.Core.Model.DocRegionFitsDecl) and
# supplying the file's symbol StartLines so its declaration guard is live.
# SCENARIO F below asserts the resulting symmetry across every gap shape.
# ===========================================================================
Write-Host ''
Write-Host '=== SCENARIO E: SHAPE 4 -- a non-blank, NON-declaration gap is stripped (apply claims it) ===' -ForegroundColor Cyan

$E = New-Case 'e'

$outZeta = (& $exePath document --qname strip_wrongsymbol.Zeta --db $E.Db --strip --apply --json 2>$null) -join ' '
Check 'E: document --qname Zeta --strip --apply exits 0' ($LASTEXITCODE -eq 0)
Check 'E CRITICAL: an ordinary-comment gap IS stripped (1 tag, 0 blocks, 1 edit) -- matching what --apply claims' `
  ($outZeta -match '"tagsRemoved":1[,}]' -and $outZeta -match '"blocksRemoved":0[,}]' -and $outZeta -match '"edits":1[,}]') $outZeta
Check 'E CRITICAL: applied:true' ($outZeta -match '"applied":true[,}]') $outZeta

$afterE = [IO.File]::ReadAllText($E.Target)
Check 'E CRITICAL: Zeta''s marked <summary> is GONE' (-not $afterE.Contains('Engine summary for Zeta.'))
Check 'E: Zeta''s declaration survives' ($afterE.Contains('function Zeta(AValue: Integer): Integer;'))
# The gap line is NOT part of the doc region -- it is hand-written source and
# must survive untouched. A strip that swallowed it would be destroying author
# content, which is the one thing this verb must never do.
Check 'E CRITICAL: the ordinary // comment in the gap SURVIVES untouched (it is author content, not part of the region)' `
  ($afterE.Contains('// an ordinary comment line -- not blank, and not a declaration'))
# Scoping: the neighbours keep their blocks.
Check 'E: Alpha''s block is UNTOUCHED' `
  ($afterE.Contains('Engine summary for Alpha.') -and $afterE.Contains('drag-lint:auto BEGIN'))
Check 'E: Gamma''s and Epsilon''s blocks are UNTOUCHED' `
  ($afterE.Contains('Engine summary for Gamma.') -and $afterE.Contains('Engine summary for Epsilon.'))

# ===========================================================================
# SCENARIO F -- THE APPLY/STRIP AGREEMENT TABLE.
#
# The invariant, stated directly instead of inferred: for EVERY gap shape, the
# write path and the remove path must reach the SAME verdict about whether a doc
# region belongs to a declaration. If apply claims a region strip will not
# remove, the engine can write a block the user cannot take back; if strip
# removes a region apply never claimed, it is deleting somebody else's comment --
# which is exactly the T3j defect.
#
# Both probes are DRY RUNS (no --apply), so all ten run against one pristine
# copy and cannot perturb each other.
#
# Discriminator, established by measurement rather than assumption (see
# task-3j-report.md): on the apply path `action:"extended"` means it FOUND and
# repaired an existing region, `action:"created"` means it found none and wrote a
# fresh block. No shape in this fixture reports `unchanged`, and the assertions
# below require one of exactly those two values, so a future `unchanged` would
# fail loudly rather than being silently bucketed.
#
# Each row asserts BOTH the agreement AND the expected direction -- agreement
# alone would be satisfied by both paths being uniformly wrong (e.g. refusing
# everything).
# ===========================================================================
Write-Host ''
Write-Host '=== SCENARIO F: apply/strip agreement across every gap shape ===' -ForegroundColor Cyan

$F = New-Case 'f'

# symbol, human description of the gap, expected verdict (claimed = both act)
$shapes = @(
  @{ Sym = 'Alpha';   Gap = 'no gap (block ends directly above the decl)'; Claimed = $true  },
  @{ Sym = 'Beta';    Gap = 'another DECLARATION in the gap';              Claimed = $false },
  @{ Sym = 'Gamma';   Gap = 'ONE BLANK line in the gap';                   Claimed = $true  },
  @{ Sym = 'Epsilon'; Gap = 'TWO blank lines (outside the window)';        Claimed = $false },
  @{ Sym = 'Zeta';    Gap = 'an ordinary // COMMENT in the gap';           Claimed = $true  }
)

foreach ($sh in $shapes) {
  $applyOut = (& $exePath document --qname "strip_wrongsymbol.$($sh.Sym)" --db $F.Db --json 2>$null) -join ' '
  $applyOk  = $LASTEXITCODE -eq 0
  $stripOut = (& $exePath document --qname "strip_wrongsymbol.$($sh.Sym)" --db $F.Db --strip --json 2>$null) -join ' '
  $stripOk  = $LASTEXITCODE -eq 0
  Check "F: both dry runs for $($sh.Sym) exit 0" ($applyOk -and $stripOk)

  $isExtended = $applyOut -match '"action":"extended"'
  $isCreated  = $applyOut -match '"action":"created"'
  Check "F: $($sh.Sym) -- apply reports either extended or created (not a third state)" `
    ($isExtended -xor $isCreated) $applyOut

  $applyClaims = $isExtended
  # v(ADP3 T3j review round 2, folded 6): the field must be PRESENT and its value
  # read positively. The previous form was `-not ($stripOut -match
  # '"tagsRemoved":0[,}]')`, which treats any output MISSING the field -- a
  # rename, a crash, an empty string -- as "strip removed something", i.e. it
  # fails OPEN into the success direction. Assert presence first, then compare
  # the captured number.
  $hasTags = $stripOut -match '"tagsRemoved":(\d+)[,}]'
  $tagsVal = if ($hasTags) { [int]$Matches[1] } else { -1 }
  Check "F: $($sh.Sym) -- strip output actually CARRIES a tagsRemoved field (not read by absence)" `
    $hasTags $stripOut
  $stripRemoves = $hasTags -and ($tagsVal -gt 0)

  Check "F AGREEMENT [$($sh.Sym), $($sh.Gap)]: apply and strip reach the SAME verdict" `
    ($applyClaims -eq $stripRemoves) "applyClaims=$applyClaims stripRemoves=$stripRemoves apply=$applyOut strip=$stripOut"
  Check "F DIRECTION [$($sh.Sym), $($sh.Gap)]: that shared verdict is '$(if($sh.Claimed){'attributed'}else{'NOT attributed'})'" `
    ($applyClaims -eq $sh.Claimed) "applyClaims=$applyClaims expected=$($sh.Claimed) apply=$applyOut"
}

# Nothing above passed --apply, so the file must be untouched -- proof the whole
# table was a dry run and no row's write leaked into a later row's probe.
Check 'F: all ten probes were dry runs -- the fixture copy is byte-identical to the original' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($fixture), [byte[]][IO.File]::ReadAllBytes($F.Target)))

# ===========================================================================
# ENCODING -- every file this runner wrote must still be strict 7-bit ASCII
# with CRLF endings and no BOM (the project rule for .pas, and the property a
# line-oriented delete could plausibly break).
# ===========================================================================
Write-Host ''
Write-Host '=== ENCODING ===' -ForegroundColor Cyan
foreach ($case in @($A, $B, $C, $D, $E, $F)) {
  $bytes  = [IO.File]::ReadAllBytes($case.Target)
  $nonAsc = 0; $loneLf = 0
  for ($i = 0; $i -lt $bytes.Count; $i++) {
    if ($bytes[$i] -gt 126) { $nonAsc++ }
    if ($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i - 1] -ne 13)) { $loneLf++ }
  }
  $hasBom = ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  Check "ENCODING: $(Split-Path $case.Dir -Leaf) stays 7-bit ASCII, CRLF, no BOM" `
    (($nonAsc -eq 0) -and ($loneLf -eq 0) -and (-not $hasBom)) "nonAscii=$nonAsc loneLF=$loneLf bom=$hasBom"
}

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
