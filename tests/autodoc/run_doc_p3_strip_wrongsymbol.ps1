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

  every line number below is also asserted by the runner itself (see FIXTURE
  PREMISES), so editing the fixture cannot silently retarget a check:

    Alpha  (line 33) -- documented: a marked <summary> plus an
                        AUTO_BEGIN..AUTO_END facts fence inside <remarks>
                        (lines 27-32).
    Beta   (line 34) -- UNdocumented, on the line directly after Alpha.
                        SHAPE 1, the defect: window [32, 33], Alpha's block
                        ends at 32, intervening line 33 is Alpha's own
                        DECLARATION.
    Gamma  (line 38) -- SHAPE 2, the legitimate gap: its marked <summary> is on
                        line 36 with exactly ONE BLANK line (37) between. Must
                        STILL be stripped -- a fix that rejects this is worse
                        than the defect it closes.
    Epsilon(line 43) -- SHAPE 3: its block is on line 40, TWO blank lines above
                        the declaration. Already outside the window; must stay
                        outside.
    Zeta   (line 47) -- SHAPE 4: its block is on line 45 with ONE intervening
                        line (46) that is an ordinary '//' comment -- non-blank,
                        but not a declaration either. The disclosed narrowing;
                        see SCENARIO E.

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

  SCENARIO E -- SHAPE 4: the NARROWING this fix introduces, pinned rather than
  merely described. The blank test refuses a non-blank NON-declaration gap that
  `document --apply` still claims; the whole-file path remains the escape hatch,
  so the round-trip is narrowed for --qname, not lost. See the block comment at
  that scenario for why this was accepted rather than widened.

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

Check 'PREMISE: all four interface declarations are found' `
  ($alphaLine -gt 0 -and $betaLine -gt 0 -and $gammaLine -gt 0 -and $epsLine -gt 0) `
  "alpha=$alphaLine beta=$betaLine gamma=$gammaLine epsilon=$epsLine"
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
$pristineB = [IO.File]::ReadAllBytes($B.Target)

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
# SCENARIO E -- SHAPE 4: the DISCLOSED NARROWING this fix introduces, pinned
# rather than described.
#
# The blank test asks "is the intervening line blank?". FindDocRegionAbove --
# the write path's equivalent, which has index access -- instead asks "does
# another DECLARATION start in the gap?". Those two questions differ for exactly
# one shape: a single intervening line that is non-blank but is NOT a
# declaration, e.g. an ordinary '//' comment. There, `--qname X --strip` now
# REFUSES a region that `document --apply` still claims and repairs.
#
# Recorded honestly as a NARROWING relative to the pre-fix behaviour, not as an
# improvement: before this fix `--qname Zeta --strip` did remove Zeta's block.
# Accepted deliberately -- the brief for this task rules out adding new
# tolerances, the declaration-based test is unavailable in this index-free unit,
# and refusing to delete is the safe direction on a path that removes lines from
# a user's source. It is NOT a lost round-trip: the whole-file path (Scenario D,
# and again below) still removes the block, so the marker is always recoverable.
# Pinned so a future widening (or a decision to accept comment lines) is a
# deliberate, visible change rather than a silent one.
# ===========================================================================
Write-Host ''
Write-Host '=== SCENARIO E: SHAPE 4 -- disclosed narrowing: a non-blank, NON-declaration gap ===' -ForegroundColor Cyan

$E = New-Case 'e'
$pristineE = [IO.File]::ReadAllBytes($E.Target)

$outZeta = (& $exePath document --qname strip_wrongsymbol.Zeta --db $E.Db --strip --apply --json 2>$null) -join ' '
Check 'E: document --qname Zeta --strip --apply exits 0' ($LASTEXITCODE -eq 0)
Check 'E (disclosed narrowing): a non-blank NON-declaration intervening line is REFUSED by the blank test -- zero removals' `
  ($outZeta -match '"tagsRemoved":0[,}]' -and $outZeta -match '"blocksRemoved":0[,}]' -and $outZeta -match '"edits":0[,}]') $outZeta
$afterZetaBytes = [IO.File]::ReadAllBytes($E.Target)
Check 'E: the file is BYTE-IDENTICAL to pristine (refusing to delete is the safe direction)' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$pristineE, [byte[]]$afterZetaBytes))
Check 'E: Zeta''s block is still present, marker and all' `
  ([IO.File]::ReadAllText($E.Target).Contains('Engine summary for Zeta.'))

# The ESCAPE HATCH, proven on the same file: the windowless whole-file path
# still removes Zeta's block, so the round-trip is narrowed for --qname, never
# lost outright.
$outZetaUnit = (& $exePath document --unit $E.Target --db $E.Db --strip --apply --json 2>$null) -join ' '
Check 'E: document --unit --strip --apply exits 0' ($LASTEXITCODE -eq 0)
Check 'E ESCAPE HATCH: the whole-file path DOES remove Zeta''s block -- the marker is always recoverable' `
  ($outZetaUnit -match '"tagsRemoved":4[,}]') $outZetaUnit
Check 'E ESCAPE HATCH: no drag-lint:auto marker survives after the whole-file strip' `
  (-not ([IO.File]::ReadAllText($E.Target) -match 'drag-lint:auto'))

# ===========================================================================
# ENCODING -- every file this runner wrote must still be strict 7-bit ASCII
# with CRLF endings and no BOM (the project rule for .pas, and the property a
# line-oriented delete could plausibly break).
# ===========================================================================
Write-Host ''
Write-Host '=== ENCODING ===' -ForegroundColor Cyan
foreach ($case in @($A, $B, $C, $D, $E)) {
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
