<#
  run_doc_p3_guards.ps1 -- Auto-Document Phase 3, Task 3d, GROUP B: the
  fail-closed guard that protects hand-written source (register D5), the two
  T3f carry-through minors, and two shapes that STILL LOSE content and are
  pinned here so the loss is visible in the suite instead of silent (D12, D11).

  Fixture: fixtures\docp3\guards.pas -- see its own header for why each shape
  is contrived the way it is.

  D5 -- RegionFullyEngineOwned gates the empty-merge DELETE branch: it answers
    "is every line of this region engine-owned?" and, when it says yes, the
    whole comment span is removed. It has been rewritten in THREE consecutive
    review rounds, and until now NO committed test pinned either of its
    fail-closed arms; both were verified by a reviewer's scratch probe only. A
    refactor could silently restore fail-OPEN and every runner would stay
    green. The two arms:
      UnterminatedFenceHandProse -- an AUTO_BEGIN with no AUTO_END. The
        pre-round-3 code set an InFence flag it never reset, so every line
        from the BEGIN through end-of-region read as engine-owned; the
        author's <value>, which sits AFTER the BEGIN, went with the region.
      StrayFenceEndHandProse -- an AUTO_END with no AUTO_BEGIN, on a line that
        ALSO carries an AUTO_MARK. The marker is what makes this arm
        load-bearing: without it the ordinary per-line marker check would
        reject the line anyway and the test would prove nothing.

  T3f minor 1 -- UnfencedRemarksTail. A <remarks> with no fence and no marker,
    on a routine with no facts, is retractable: the engine will emit no
    <remarks> of its own, so there is no duplicate to avoid and no stale fact
    to trade against, and the tail beside it is carried through instead of
    dropped.

  T3f minor 3 -- AbortBlastRadius. The <returns> line legitimately loses its
    own carry-through (its span is engine-regenerated). The innocent <value>
    two lines above overlaps nothing non-retractable and now survives; it used
    to be deleted along with the whole region.

  D12 -- ValueBesideDecayedFence: STILL REPRODUCES, pinned as a known gap. An
    unmodeled tag beside a DECAYED fence is `unchanged, edits=0` forever, so
    the stale fact is never cleaned. Nothing is destroyed -- the guard is
    doing its job -- but the decay is not repaired either.

  D11 -- TwoSinceTags: STILL REPRODUCES, pinned as a known loss. The parser
    reads <since> with a singular .Match, so the second tag is dropped by the
    parse and then deleted from the file by the repair. Same unkeyed-singular
    class as register N2 (<summary>/<returns>/<remarks>), which task T3h owns.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\guards.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3guards'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'guards.pas'
$db     = Join-Path $scratch 'q.sqlite'
Copy-Item $fixture $target -Force

# The contiguous run of ///-prefixed lines immediately above the FIRST line
# matching $declPattern, RAW (never trimmed). $null when the decl is not found
# OR when it has no doc lines above it at all -- the two failures a caller
# needs to tell apart from "found a block" are "no decl" and "no block", and
# an EMPTY array is neither: returning one would let a "block was located"
# check pass for a doc block that had been deleted outright.
function Get-DocBlockLines([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i])
  }
  if ($acc.Count -eq 0) { return $null }
  return $acc.ToArray()
}
function Get-DocBlock([string[]]$lines, [string]$declPattern) {
  $a = Get-DocBlockLines $lines $declPattern
  if ($null -eq $a) { return $null }
  return [string]::Join("`n", $a)
}
function Get-Md5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash.Substring(0,8) }

$AUTO_MARK  = '<!-- drag-lint:auto -->'
$AUTO_BEGIN = '<!-- drag-lint:auto BEGIN -->'
$AUTO_END   = '<!-- drag-lint:auto END -->'

$patUnterm  = '^function UnterminatedFenceHandProse: Integer;'
$patStray   = '^function StrayFenceEndHandProse: Integer;'
$patDecayed = '^procedure ValueBesideDecayedFence;'
$patUnfence = '^procedure UnfencedRemarksTail;'
$patBlast   = '^function AbortBlastRadius: Integer;'
$patSince   = '^procedure TwoSinceTags;'

Push-Location C:\TEMP
try {
  $before = [IO.File]::ReadAllLines($target)

  # --- FIXTURE DISCRIMINATION ----------------------------------------------
  # Each D5 arm is only load-bearing while its fixture keeps the property that
  # forces THAT arm to decide. A later fixture tidy-up must break these checks
  # loudly rather than silently reduce the arm's test to a tautology.
  $untermBefore = Get-DocBlockLines $before $patUnterm
  $strayBefore  = Get-DocBlockLines $before $patStray
  Check 'FIXTURE: both D5 doc blocks were located' ($null -ne $untermBefore -and $null -ne $strayBefore)

  # Now that the two helpers answer $null for "no block", every dereference
  # below is written so a $null cannot raise a .NET null-argument exception --
  # an exception here would replace a readable FAIL with a stack trace about
  # the wrong thing.
  $untermJoin = if ($null -ne $untermBefore) { [string]::Join("`n", $untermBefore) } else { '' }
  $strayJoin  = if ($null -ne $strayBefore ) { [string]::Join("`n", $strayBefore ) } else { '' }
  Check 'FIXTURE D5/unterminated: the block has an AUTO_BEGIN and NO AUTO_END' `
    ($untermJoin.Contains($AUTO_BEGIN) -and -not $untermJoin.Contains($AUTO_END))
  $bIdx = if ($null -ne $untermBefore) { [array]::FindIndex($untermBefore, [Predicate[string]]{ param($s) $s.Contains($AUTO_BEGIN) }) } else { -1 }
  $vIdx = if ($null -ne $untermBefore) { [array]::FindIndex($untermBefore, [Predicate[string]]{ param($s) $s.Contains('<value>') })   } else { -1 }
  Check 'FIXTURE D5/unterminated: the hand-written line sits AFTER the AUTO_BEGIN (fail-OPEN would swallow it)' `
    ($bIdx -ge 0 -and $vIdx -gt $bIdx) "beginIdx=$bIdx valueIdx=$vIdx"

  $strayValueLine = @($strayBefore | Where-Object { $_.Contains('<value>') })
  Check 'FIXTURE D5/stray-END: exactly one hand-written <value> line' ($strayValueLine.Count -eq 1)
  Check 'FIXTURE D5/stray-END: that line carries BOTH an AUTO_END and an AUTO_MARK -- so only the stray-END arm can reject it' `
    ($strayValueLine.Count -eq 1 -and $strayValueLine[0].Contains($AUTO_END) -and $strayValueLine[0].Contains($AUTO_MARK))
  Check 'FIXTURE D5/stray-END: the block has NO AUTO_BEGIN, so the END really is stray' `
    (-not $strayJoin.Contains($AUTO_BEGIN))

  $decayedBefore = Get-DocBlock $before $patDecayed
  $unfenceBefore = Get-DocBlock $before $patUnfence
  $blastBefore   = Get-DocBlock $before $patBlast
  $sinceBefore   = Get-DocBlock $before $patSince
  Check 'FIXTURE: the other four doc blocks were located' `
    ($null -ne $decayedBefore -and $null -ne $unfenceBefore -and $null -ne $blastBefore -and $null -ne $sinceBefore)
  Check 'FIXTURE minor 1: the unfenced remarks block really has no fence and no marker' `
    ($null -ne $unfenceBefore -and -not $unfenceBefore.Contains($AUTO_BEGIN) -and -not $unfenceBefore.Contains($AUTO_MARK))

  # --- three apply cycles ---------------------------------------------------
  $md5s = @()
  for ($cycle = 1; $cycle -le 3; $cycle++) {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    & $exePath document --unit $target --db $db --stubs --apply --json 2>$null | Out-Null
    $md5s += (Get-Md5 $target)
  }
  Check 'converges: md5 identical across all 3 apply cycles' `
    ($md5s[0] -eq $md5s[1] -and $md5s[1] -eq $md5s[2]) ("md5s=" + ($md5s -join ' '))

  $after = [IO.File]::ReadAllLines($target)

  # --- D5: the guard held ---------------------------------------------------
  $untermAfter = Get-DocBlock $after $patUnterm
  Check 'D5 unterminated-fence arm: the hand-written <value> SURVIVES' `
    ($null -ne $untermAfter -and $untermAfter.Contains('<value>Hand-written after an unterminated fence; must survive.</value>'))
  Check 'D5 unterminated-fence arm: the whole doc block is byte-identical (nothing deleted, nothing rewritten)' `
    ($untermAfter -ceq $untermJoin)

  $strayAfter = Get-DocBlock $after $patStray
  Check 'D5 stray-END arm: the hand-written <value> SURVIVES' `
    ($null -ne $strayAfter -and $strayAfter.Contains('<value>Hand-written beside a stray END; must survive.</value>'))
  Check 'D5 stray-END arm: the whole doc block is byte-identical' `
    ($strayAfter -ceq $strayJoin)

  # --- T3f minor 1 ----------------------------------------------------------
  $unfenceAfter = Get-DocBlock $after $patUnfence
  Check 'T3f minor 1: the tail beside an unmarked, unfenced <remarks> SURVIVES' `
    ($null -ne $unfenceAfter -and $unfenceAfter.Contains('<value>tail value</value>'))
  Check 'T3f minor 1: the author''s remarks prose survives too, exactly once' `
    ($null -ne $unfenceAfter -and (([regex]::Matches($unfenceAfter, [regex]::Escape('Plain hand prose, no fence, no marker.'))).Count -eq 1))
  Check 'T3f minor 1: no <remarks> was fabricated beside the author''s (exactly one opening tag)' `
    ($null -ne $unfenceAfter -and (([regex]::Matches($unfenceAfter, '<remarks[ >]')).Count -eq 1))

  # --- T3f minor 3 ----------------------------------------------------------
  $blastAfter = Get-DocBlock $after $patBlast
  Check 'T3f minor 3: the INNOCENT <value> line survives another line''s abort' `
    ($null -ne $blastAfter -and $blastAfter.Contains("<value>Innocent unmodeled tag; must survive another line's abort.</value>"))
  Check 'T3f minor 3: the engine still regenerated the marked <returns> from the mined case (the span was NOT retracted)' `
    ($null -ne $blastAfter -and $blastAfter -match [regex]::Escape('<returns><!-- drag-lint:auto -->Observed: 42.</returns>'))
  Check 'T3f minor 3: exactly ONE <returns> -- the blocked line did not duplicate the tag' `
    ($null -ne $blastAfter -and (([regex]::Matches($blastAfter, '<returns>')).Count -eq 1))
  # DISCLOSED, DELIBERATE non-improvement: the offending line's OWN tail is
  # still dropped. Pinned so a future change that preserves it is a visible
  # improvement rather than an unnoticed behaviour drift.
  Check 'T3f minor 3 (disclosed): the offending line''s own hand tail is STILL dropped -- the narrow, deliberate loss' `
    ($null -ne $blastAfter -and -not $blastAfter.Contains('hand tail'))

  # --- D12: STILL REPRODUCES ------------------------------------------------
  $decayedAfter = Get-DocBlock $after $patDecayed
  Check 'D12 the hand-written <value> beside a decayed fence SURVIVES (the guard fails closed)' `
    ($null -ne $decayedAfter -and $decayedAfter.Contains('<value>Unmodeled tag beside a decayed fence; must survive.</value>'))
  Check 'D12 KNOWN GAP, pinned: the DECAYED fact is still on disk -- unchanged/0 forever, never cleaned' `
    ($null -ne $decayedAfter -and $decayedAfter.Contains('Called from: guards.NoSuchCallerAnyMore'))
  Check 'D12 the whole block is byte-identical (no edit is produced for this shape at all)' `
    ($decayedAfter -ceq $decayedBefore)

  # --- D11: STILL REPRODUCES ------------------------------------------------
  $sinceAfter = Get-DocBlock $after $patSince
  Check 'D11 the FIRST <since> survives' ($null -ne $sinceAfter -and $sinceAfter.Contains('<since>1.0</since>'))
  Check 'D11 KNOWN LOSS, pinned: the SECOND <since> is deleted (singular .Match parse; register N2 class, owned by T3h)' `
    ($null -ne $sinceAfter -and -not $sinceAfter.Contains('<since>2.0</since>'))

  # --- per-decl settled action ---------------------------------------------
  & $exePath index $scratch --db $db 2>$null | Out-Null
  foreach ($q in @('guards.UnterminatedFenceHandProse','guards.StrayFenceEndHandProse','guards.ValueBesideDecayedFence',
                   'guards.UnfencedRemarksTail','guards.AbortBlastRadius','guards.TwoSinceTags')) {
    $j = (& $exePath document --qname $q --db $db --json 2>$null) -join ' '
    Check "settled: $q reports unchanged with 0 edits" `
      ($j -match '"action":"unchanged"' -and $j -match '"edits":0[,}]') $j
  }

  # --- encoding -------------------------------------------------------------
  $bad = @([IO.File]::ReadAllBytes($target) | Where-Object { $_ -gt 127 }).Count
  Check 'every byte written back is 7-bit ASCII' ($bad -eq 0) "nonascii=$bad"
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
