<#
  run_doc_p3_decayrouting.ps1 -- Auto-Document Phase 3, Task 3d, GROUP C: the
  decay/routing class. Five register items, ALL of them pinned as CURRENT
  BEHAVIOUR rather than fixed. Read that as a deliberate verdict, not an
  omission: every one traces to the same property -- these shapes route to the
  FRESH-INSERT branch, which can only ADD a block, having neither a repair nor
  a delete -- and the alternative routing was measured, tried and reverted in
  an earlier round because the repair path DELETES the region and re-emits only
  what it models, destroying the hand-written tags these shapes carry.

  Pinning them here is the deliverable: each behaviour is now visible in the
  suite, so the day one of them is fixed the change announces itself, and the
  day one of them silently gets WORSE a runner goes red.

  N5 -- QuotedBlockExact. The fresh branch's guard refuses to insert a block
    whose lines already sit above the declaration. An author who quotes that
    block verbatim therefore suppresses the real insert, and the symbol
    silently never receives its own. Contrived; silent; uncovered until now.

  N7 -- QuotedBlockNearMiss. The guard's containment scan had never been
    exercised on its LOOP's negative path -- every committed shape answered
    False through the "inner is longer than outer" early-out. This shape has a
    SIX-line existing region and a FIVE-line block to insert, so the loop
    really runs and really compares, failing on one character (.pos vs .pas).
    It doubles as N5's control: change that one character back and the insert
    is suppressed again.

  N6 -- EmptyRemarksSibling. The converged output carries TWO sibling
    <remarks> elements, the author's empty one first. Stable and reversible,
    but not well-formed DocInsight, and the consequence is the same one T3f
    minor 4 has: a consumer that reads "the <remarks> element" gets the EMPTY
    one and never sees the facts.

  T3f minor 4 -- AttributedRemarksOrder. Same consequence, sharper: an
    attributed <remarks xml:lang="en"> is VALID XML doc that the parser's
    strict pattern cannot represent, so it is carried through verbatim as a
    residual line, which the emitter places BEFORE the facts block. Delphi
    Help Insight renders the author's element and silently ignores the facts.
    The existing pin (in run_doc_p3_residual_lines.ps1) records the element
    COUNT; this one records the ORDER, which is where the consequence lives.

  N4 -- DecayAddThenRemove, driven by this runner across four applies: add a
    caller, apply (a SECOND block is inserted, the first stays), remove that
    caller, apply. The engine now matches the FIRST block, reports the symbol
    up to date, and leaves the second on disk asserting a caller that no
    longer exists anywhere in the file. `document --strip --apply` recovers.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\decayrouting.pas')).Path

function Get-DocBlock([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i])
  }
  return [string]::Join("`n", $acc.ToArray())
}
function Get-Md5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash.Substring(0,8) }
function New-Scratch([string]$slug) {
  $d = Join-Path C:\TEMP $slug
  if (Test-Path $d) { Remove-Item $d -Recurse -Force }
  New-Item -ItemType Directory -Path $d | Out-Null
  Copy-Item $fixture (Join-Path $d 'decayrouting.pas') -Force
  return $d
}

$patExact  = '^procedure QuotedBlockExact;'
$patNear   = '^procedure QuotedBlockNearMiss;'
$patSib    = '^procedure EmptyRemarksSibling;'
$patAttr   = '^procedure AttributedRemarksOrder;'
$patDecay  = '^procedure DecayAddThenRemove;'

Push-Location C:\TEMP
try {
  # ======================= PART 1: N5 / N7 / N6 / minor 4 ===================
  $scratch = New-Scratch 'draglint_docp3decayrouting'
  $target  = Join-Path $scratch 'decayrouting.pas'
  $db      = Join-Path $scratch 'q.sqlite'

  $before      = [IO.File]::ReadAllLines($target)
  $exactBefore = Get-DocBlock $before $patExact
  $nearBefore  = Get-DocBlock $before $patNear
  Check 'FIXTURE: the N5 and N7 doc blocks were located' ($null -ne $exactBefore -and $null -ne $nearBefore)
  # The two quoted blocks must differ in EXACTLY the file extension, or N7 is
  # not the control for N5 and either check could pass for its own reasons.
  Check 'FIXTURE: N5 quotes .pas and N7 quotes .pos -- the near miss is ONE character' `
    ($exactBefore -match [regex]::Escape('(decayrouting.pas)') -and $nearBefore -match [regex]::Escape('(decayrouting.pos)'))

  $md5s = @()
  for ($cycle = 1; $cycle -le 3; $cycle++) {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    & $exePath document --unit $target --db $db --stubs --apply --json 2>$null | Out-Null
    $md5s += (Get-Md5 $target)
  }
  Check 'converges: md5 identical across all 3 apply cycles' `
    ($md5s[0] -eq $md5s[1] -and $md5s[1] -eq $md5s[2]) ("md5s=" + ($md5s -join ' '))

  $after = [IO.File]::ReadAllLines($target)

  # --- N5 -------------------------------------------------------------------
  $exactAfter = Get-DocBlock $after $patExact
  Check 'N5 KNOWN GAP, pinned: an exact verbatim quote of the engine block SUPPRESSES the real insert' `
    ($exactAfter -ceq $exactBefore)
  Check 'N5 consequence: the symbol carries exactly ONE facts fence -- the author''s quote, never its own' `
    ($null -ne $exactAfter -and (([regex]::Matches($exactAfter, [regex]::Escape('drag-lint:auto BEGIN'))).Count -eq 1))

  # --- N7 -- the control, and the guard's loop negative path ----------------
  $nearAfter = Get-DocBlock $after $patNear
  Check 'N7 control: changing ONE character of the quote restores the insert' `
    ($null -ne $nearAfter -and $nearAfter -ne $nearBefore)
  Check 'N7 the near-miss quote itself is untouched (nothing was rewritten, only added)' `
    ($null -ne $nearAfter -and $nearAfter.Contains('(decayrouting.pos)'))
  Check 'N7 the engine''s OWN block was added beside it, with the real file name' `
    ($null -ne $nearAfter -and $nearAfter.Contains('Called from: decayrouting.CallsQuotedBlockNearMiss (decayrouting.pas)'))
  Check 'N7 exactly TWO fences on this symbol -- the quote plus the engine''s, not an unbounded stack' `
    ($null -ne $nearAfter -and (([regex]::Matches($nearAfter, [regex]::Escape('drag-lint:auto BEGIN'))).Count -eq 2))

  # --- N6 -------------------------------------------------------------------
  $sibAfter = Get-DocBlock $after $patSib
  # N7's claim is specifically that the guard answers False through its SCAN
  # LOOP, not through the "inner is longer than outer" early-out. That is only
  # true while the existing region is at least as long as the block being
  # inserted, so derive both lengths and assert it, rather than asserting the
  # outcome and hoping. The engine's own block length is read off the N6 shape,
  # whose whole doc block is the author's ONE line plus exactly that block.
  $engineBlockLines = ($sibAfter -split "`n").Count - 1
  $nearBeforeLines  = ($nearBefore -split "`n").Count
  Check 'N7 DISCRIMINATION: the existing region is at least as long as the block to insert, so the early-out CANNOT be what answers' `
    ($engineBlockLines -ge 1 -and $nearBeforeLines -ge $engineBlockLines) `
    "existing=$nearBeforeLines engineBlock=$engineBlockLines"
  Check 'N6 KNOWN GAP, pinned: the converged output has TWO sibling <remarks> elements' `
    ($null -ne $sibAfter -and (([regex]::Matches($sibAfter, '<remarks[ >]')).Count -eq 2))
  Check 'N6 consequence: the FIRST <remarks> is the author''s EMPTY one, so a consumer reading "the remarks" sees nothing' `
    ($null -ne $sibAfter -and (($sibAfter -split "`n")[0].Trim() -ceq '/// <remarks></remarks>'))

  # --- T3f minor 4 ----------------------------------------------------------
  $attrAfter = Get-DocBlock $after $patAttr
  Check 'T3f minor 4: the attributed <remarks> SURVIVES (T3f''s own guarantee, unchanged)' `
    ($null -ne $attrAfter -and $attrAfter.Contains('<remarks xml:lang="en">Attributed remarks prose must survive.</remarks>'))
  Check 'T3f minor 4: a facts block WAS written, so there really are two elements to order' `
    ($null -ne $attrAfter -and $attrAfter.Contains('drag-lint:auto BEGIN'))
  # THE CONSEQUENCE, which the existing element-count pin does not record: the
  # author's element comes FIRST, so a spec-conforming consumer renders it and
  # silently ignores the facts block below.
  $attrIdx  = $attrAfter.IndexOf('<remarks xml:lang="en">')
  $factsIdx = $attrAfter.IndexOf('drag-lint:auto BEGIN')
  Check 'T3f minor 4 KNOWN GAP, pinned: the AUTHOR''s <remarks> is emitted BEFORE the facts block, so Help Insight never shows the facts' `
    ($attrIdx -ge 0 -and $factsIdx -gt $attrIdx) "authorAt=$attrIdx factsAt=$factsIdx"

  # ======================= PART 2: N4, the decay sequence ===================
  $s2 = New-Scratch 'draglint_docp3decayrouting_n4'
  $t2 = Join-Path $s2 'decayrouting.pas'
  $d2 = Join-Path $s2 'q.sqlite'

  # (a) one caller
  & $exePath index $s2 --db $d2 2>$null | Out-Null
  & $exePath document --unit $t2 --db $d2 --stubs --apply --json 2>$null | Out-Null
  $decayA = Get-DocBlock ([IO.File]::ReadAllLines($t2)) $patDecay
  Check 'N4 (a) one caller: a facts block is written naming it' `
    ($null -ne $decayA -and $decayA.Contains('Called from: decayrouting.CallsDecayAddThenRemove'))
  Check 'N4 (a) exactly one fence so far' `
    ($null -ne $decayA -and (([regex]::Matches($decayA, [regex]::Escape('drag-lint:auto BEGIN'))).Count -eq 1))

  # (b) ADD a second caller through the fixture's own markers, then apply
  $txt = [IO.File]::ReadAllText($t2)
  Check 'N4 FIXTURE: both extra-caller markers are present' `
    ($txt.Contains('// N4-EXTRA-CALLER-DECL') -and $txt.Contains('// N4-EXTRA-CALLER-IMPL'))
  $txt = $txt.Replace('// N4-EXTRA-CALLER-DECL', "procedure ExtraCallerOfDecay;")
  $txt = $txt.Replace('// N4-EXTRA-CALLER-IMPL', "procedure ExtraCallerOfDecay;`r`nbegin`r`n  DecayAddThenRemove;`r`nend;")
  [IO.File]::WriteAllText($t2, $txt)
  & $exePath index $s2 --db $d2 2>$null | Out-Null
  & $exePath document --unit $t2 --db $d2 --stubs --apply --json 2>$null | Out-Null
  $decayB = Get-DocBlock ([IO.File]::ReadAllLines($t2)) $patDecay
  Check 'N4 (b) second caller added: a SECOND block appears, naming both' `
    ($null -ne $decayB -and $decayB.Contains('ExtraCallerOfDecay') -and
     (([regex]::Matches($decayB, [regex]::Escape('drag-lint:auto BEGIN'))).Count -eq 2))
  # LINE-EXACT, not Contains: the two-caller line the second block carries has
  # the one-caller line as a literal PREFIX, so a substring test would pass
  # even if the first block had been repaired away.
  # @() forces an array: a single-match pipeline returns a bare STRING, whose
  # [0] is its first CHARACTER, which would compare against nothing.
  $oneCallerLine = @($decayA -split "`n" | Where-Object { $_ -match 'Called from:' })
  Check 'N4 (b) FIXTURE: block (a) had exactly one Called-from line to look for' ($oneCallerLine.Count -eq 1)
  Check 'N4 (b) the FIRST block is still on disk VERBATIM, unrepaired -- the fresh branch only ever adds' `
    ($oneCallerLine.Count -eq 1 -and (@($decayB -split "`n" | Where-Object { $_ -ceq $oneCallerLine[0] }).Count -eq 1))

  # (c) REMOVE that caller and apply again
  $txt = [IO.File]::ReadAllText($t2)
  $txt = $txt.Replace("procedure ExtraCallerOfDecay;`r`nbegin`r`n  DecayAddThenRemove;`r`nend;", '')
  $txt = $txt.Replace("procedure ExtraCallerOfDecay;`r`n", '')
  [IO.File]::WriteAllText($t2, $txt)
  Check 'N4 (c) FIXTURE: the extra caller is really gone from the source' `
    (-not ([IO.File]::ReadAllText($t2)).Contains('procedure ExtraCallerOfDecay'))
  & $exePath index $s2 --db $d2 2>$null | Out-Null
  $j = (& $exePath document --qname 'decayrouting.DecayAddThenRemove' --db $d2 --json 2>$null) -join ' '
  Check 'N4 KNOWN GAP, pinned: the engine reports the symbol UP TO DATE after the caller is removed' `
    ($j -match '"action":"unchanged"' -and $j -match '"edits":0[,}]') $j
  $decayC = Get-DocBlock ([IO.File]::ReadAllLines($t2)) $patDecay
  Check 'N4 KNOWN GAP, pinned: ...while an engine-MARKED block below still names a caller that no longer exists' `
    ($null -ne $decayC -and $decayC.Contains('ExtraCallerOfDecay'))

  # (d) the documented recovery
  & $exePath document --unit $t2 --db $d2 --strip --apply 2>$null | Out-Null
  $decayD = Get-DocBlock ([IO.File]::ReadAllLines($t2)) $patDecay
  Check 'N4 recovery: --strip --apply removes the stale fact' `
    ($null -ne $decayD -and -not $decayD.Contains('ExtraCallerOfDecay'))
  Check 'N4 recovery: --strip --apply removes EVERY engine block on the symbol' `
    ($null -ne $decayD -and -not $decayD.Contains('drag-lint:auto BEGIN'))
  Check 'N4 recovery: the author''s own line is restored exactly' `
    ($decayD -ceq '/// <remarks></remarks>')

  # --- encoding -------------------------------------------------------------
  $bad = @([IO.File]::ReadAllBytes($target) | Where-Object { $_ -gt 127 }).Count
  Check 'every byte written back is 7-bit ASCII' ($bad -eq 0) "nonascii=$bad"
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
