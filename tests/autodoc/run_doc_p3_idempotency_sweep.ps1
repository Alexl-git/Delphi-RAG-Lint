<#
  run_doc_p3_idempotency_sweep.ps1 -- Auto-Document Phase 3, Task 3b review
  round 4: a GENERAL idempotency sweep over this task's fixtures.

  WHY THIS RUNNER EXISTS
  ----------------------
  Task 3b regressed three times. Every round's tests asserted CYCLE-1
  correctness, and three separate non-idempotent shapes shipped because
  nothing swept for a FIXED POINT: 215 internal checks passed in round 3
  while a comment whose only HasContent-bearing tag was an empty <remarks>
  grew without bound on every single `document --apply` (measured 364 ->
  517 -> 670 -> 823 bytes, "action":"created","edits":1 every cycle).

  The binding acceptance criterion for `document --apply` is that a SECOND
  apply produces a zero-byte diff. This runner asserts exactly that, for
  every symbol in both of Task 3b's fixtures, in both apply modes:

    SWEEP A  fixtures\docp3\preserve_tags.pas       whole-unit apply
    SWEEP B  fixtures\docp3\idempotency_shapes.pas  whole-unit apply
    SWEEP C  fixtures\docp3\idempotency_shapes.pas  --qname-scoped apply,
             one isolated scratch copy per symbol (the round-4 review's own
             measurement methodology, reproduced as a committed test)
    SWEEP D  the two shapes that were KNOWN-UNSTABLE until T3h. Their ACTUAL
             behaviour was pinned here (converges, but cycle 2 differs from
             cycle 1 and --strip cannot undo it) so a future fix would break
             the pin loudly rather than silently change behaviour nothing
             covered. v(ADP3 T3h) did fix it, and the pin is FLIPPED: both now
             settle on cycle 1 and round-trip through --strip byte-exactly.

  METHOD (all sweeps): apply -> reindex -> apply -> reindex -> apply, and
  assert an md5 FIXED POINT from cycle 2 onward (md5 of cycle 2 == md5 of
  cycle 3). Cycle 1 is expected to change the file -- that is the engine
  doing its job. Anything that keeps changing after cycle 1 is a defect.

  Per-symbol attribution: the whole-file md5 is the headline, but a failing
  whole-file md5 does not say WHICH symbol moved, so each symbol's own
  doc-comment block (the contiguous run of /// lines above its declaration,
  located by the symbol's FRESHLY REINDEXED start line, never by a regex that
  would go stale) is md5'd separately every cycle too.

  Symbols are ENUMERATED FROM THE INDEX, not hardcoded: a fixture row added
  by a later task is swept automatically instead of silently escaping
  coverage. Enumeration reads the index DB via Python's stdlib sqlite3
  (C:\Python314\python, read-only ?mode=ro open) -- there is no sqlite3 on
  PATH in this environment, and several runners in tests/autotest already
  read the index this way.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Py  = 'C:\Python314\python.exe'
)

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath  = (Resolve-Path $Exe).Path
$fxPreserve = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\preserve_tags.pas')).Path
$fxShapes   = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\idempotency_shapes.pas')).Path

if (-not (Test-Path $Py)) {
  Write-Host "[FAIL] python not found at $Py (needed to enumerate symbols from the index)" -ForegroundColor Red
  exit 1
}

# ---------------------------------------------------------------------------
# Helpers (standalone by convention -- every runner in this directory carries
# its own copies rather than dot-sourcing a shared module).
# ---------------------------------------------------------------------------

# v(ADP3 T3d2 N8): 8 hex chars = 32 bits -- deliberately short, and fine for
# this runner's purpose. Every comparison here is a handful of md5s checked
# against EACH OTHER within one run (cycle-to-cycle, symbol-to-symbol), never
# against an external/adversarial corpus, so a 32-bit space is far more than
# enough to catch a genuine content change; nothing here relies on it as a
# security or global-uniqueness guarantee.
function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash.Substring(0,8) }

function Get-StrMd5([string]$s) {
  $md5 = [Security.Cryptography.MD5]::Create()
  try { return (([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)))) -replace '-','').Substring(0,8) }
  finally { $md5.Dispose() }
}

# The contiguous run of ///-prefixed lines immediately above 1-based line
# $declLine1, per-line trimmed. Tolerates ONE leading blank line before the
# scan starts, mirroring FindDocRegionAbove's own AllowGap=1 default, so a
# GAPPED comment is found the same way an abutting one is. Anchored by line
# number (from a fresh reindex) rather than by a declaration regex: an apply
# rewrites the file and shifts every line below it, and a regex anchor would
# also silently match the wrong row if two declarations ever share a spelling.
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

# (qualified_name, start_line) for every symbol the index holds for $pasPath,
# ordered by start_line. Read-only open so a concurrently-held write lock can
# never block or corrupt.
$pyEnum = @'
import sqlite3, sys
db, suffix = sys.argv[1], sys.argv[2]
c = sqlite3.connect('file:' + db.replace('\\', '/') + '?mode=ro', uri=True)
sql = ("select s.qualified_name, min(s.start_line) as sl from symbols s "
       "join files f on f.id = s.file_id where f.path like ? "
       "group by s.qualified_name order by sl")
for qn, sl in c.execute(sql, ('%' + suffix,)):
    print('%s\t%d' % (qn, sl))
'@
# v(ADP3 T3d2 N8): PID-qualified filename -- a fixed shared path here would
# race if two runners (or two invocations of this one) executed concurrently,
# each overwriting the file the other is about to read. The battery driver
# runs runners sequentially today, so this was latent, not live; the PID
# suffix makes it non-racing unconditionally instead of resting on that
# convention. Content and every downstream reference are unchanged -- only
# the filename gained a suffix.
$pyEnumPath = Join-Path ([IO.Path]::GetTempPath()) ('draglint_sweep_enum_' + $PID + '.py')
[IO.File]::WriteAllText($pyEnumPath, $pyEnum)

function Get-Symbols([string]$db, [string]$suffix) {
  $out = & $Py $pyEnumPath $db $suffix 2>$null
  $res = New-Object System.Collections.Generic.List[object]
  foreach ($line in $out) {
    if ($line -match '^(.+)\t(\d+)$') { $res.Add([pscustomobject]@{ QName = $Matches[1]; Line = [int]$Matches[2] }) }
  }
  return $res
}

# 3 apply cycles over a whole unit, reindexing before each. Returns the
# per-cycle whole-file md5 and the per-cycle per-symbol block md5 map.
function Invoke-UnitSweep([string]$fixture, [string]$scratchName, [string]$suffix) {
  $scratch = Join-Path C:\TEMP $scratchName
  if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch | Out-Null
  $target = Join-Path $scratch (Split-Path $fixture -Leaf)
  $db     = Join-Path $scratch 'sweep.sqlite'
  Copy-Item $fixture $target -Force

  $fileMd5   = @( Get-FileMd5 $target )   # index 0 = cycle 0 (pristine)
  $actions   = @()
  $blockMd5  = @()                        # array of hashtables, index = cycle
  $symOrder  = $null

  for ($cycle = 1; $cycle -le 3; $cycle++) {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    $j = (& $exePath document --unit $target --db $db --apply --json 2>$null) -join ' '
    $actions += $j
    # Reindex so start lines reflect the file the apply just wrote, then
    # snapshot each symbol's own block.
    & $exePath index $scratch --db $db 2>$null | Out-Null
    $syms = Get-Symbols $db $suffix
    if ($null -eq $symOrder) { $symOrder = $syms }
    $lines = [IO.File]::ReadAllLines($target)
    $map = @{}
    foreach ($s in $syms) { $map[$s.QName] = Get-StrMd5 (Get-DocBlockAtLine $lines $s.Line) }
    $blockMd5 += $map
    $fileMd5  += Get-FileMd5 $target
  }
  return [pscustomobject]@{
    Scratch = $scratch; Target = $target; Db = $db
    FileMd5 = $fileMd5; Actions = $actions; BlockMd5 = $blockMd5; Symbols = $symOrder
  }
}

# 3 --qname-scoped apply cycles in an ISOLATED scratch copy (one per symbol),
# reindexing before each -- exactly the round-4 review's own measurement
# methodology. Returns per-cycle size and md5 of the whole file.
function Invoke-QNameSweep([string]$fixture, [string]$scratchRoot, [string]$qname, [string]$slug) {
  $scratch = Join-Path $scratchRoot $slug
  if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch -Force | Out-Null
  $target = Join-Path $scratch (Split-Path $fixture -Leaf)
  $db     = Join-Path $scratch 'q.sqlite'
  Copy-Item $fixture $target -Force
  $sizes = @( (Get-Item $target).Length )
  $md5s  = @( Get-FileMd5 $target )
  $acts  = @()
  for ($cycle = 1; $cycle -le 3; $cycle++) {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    $j = (& $exePath document --qname $qname --db $db --apply --json 2>$null) -join ' '
    if ($j -match '"action":"(\w+)"') { $a = $Matches[1] } else { $a = '?' }
    if ($j -match '"edits":(\d+)')    { $a = "$a/$($Matches[1])" }
    $acts  += $a
    $sizes += (Get-Item $target).Length
    $md5s  += Get-FileMd5 $target
  }
  return [pscustomobject]@{ Scratch = $scratch; Target = $target; Db = $db; Sizes = $sizes; Md5s = $md5s; Actions = $acts }
}

Push-Location C:\TEMP
try {

# ===========================================================================
# SWEEP A -- preserve_tags.pas, whole-unit apply, every symbol
# ===========================================================================
Write-Host ''
Write-Host '=== SWEEP A: preserve_tags.pas, document --unit --apply, 3 cycles ===' -ForegroundColor Cyan

$a = Invoke-UnitSweep $fxPreserve 'draglint_docp3sweep_preserve' 'preserve_tags.pas'
Check 'SWEEP A: symbols enumerated from the index' ($a.Symbols.Count -gt 0) "count=$($a.Symbols.Count)"
Write-Host ("  whole-file md5 by cycle: pristine={0} c1={1} c2={2} c3={3}" -f $a.FileMd5[0], $a.FileMd5[1], $a.FileMd5[2], $a.FileMd5[3])
Check 'SWEEP A: whole-file md5 is a FIXED POINT from cycle 2 (c2 == c3)' ($a.FileMd5[2] -eq $a.FileMd5[3]) `
  "c2=$($a.FileMd5[2]) c3=$($a.FileMd5[3])"
# v(ADP3 T3h): and now from cycle ONE -- the last two settle-at-cycle-2 shapes
# were the N2 defect, so the whole 61-symbol file is a fixed point after the
# first apply. Asserted separately from the c2==c3 check above so a regression
# that reintroduces a late-settling shape is distinguishable from one that never
# settles at all.
Check 'SWEEP A: whole-file md5 is a fixed point from cycle ONE (c1 == c2)' ($a.FileMd5[1] -eq $a.FileMd5[2]) `
  "c1=$($a.FileMd5[1]) c2=$($a.FileMd5[2])"
Check 'SWEEP A: cycle-3 apply reports no edits' ($a.Actions[2] -match '"edits":0') $a.Actions[2]

$aUnstable = @()
$aSettleAt2 = @()
foreach ($s in $a.Symbols) {
  $m1 = $a.BlockMd5[0][$s.QName]; $m2 = $a.BlockMd5[1][$s.QName]; $m3 = $a.BlockMd5[2][$s.QName]
  if ($m2 -ne $m3) { $aUnstable  += $s.QName }
  if ($m1 -ne $m2) { $aSettleAt2 += ($s.QName -replace '^preserve_tags\.','') }
}
Check 'SWEEP A: EVERY symbol block is a fixed point from cycle 2' ($aUnstable.Count -eq 0) `
  ("unstable=" + ($aUnstable -join ','))

# PINNED ACTUAL BEHAVIOUR -- the set of symbols in preserve_tags.pas that settle
# at CYCLE 2 rather than cycle 1. It is now EMPTY: every one of the 61 symbols
# reaches its fixed point on the FIRST apply, so the whole-file md5 above is a
# fixed point from cycle 1 too.
#
# HISTORY, because an empty pin explains nothing on its own:
#   * It held THREE names until T3c. TabSeparatedSeeAlso left then -- T3c widened
#     TParsedDoc.HasContent to include Length(SeeAlso) > 0, which routes that decl
#     through the REPAIR path from cycle 1 instead of needing the two-cycle
#     additive-then-merge dance (cycle 1 takes the FRESH path and inserts a facts
#     block ADJACENT to the hand-written comment; the next scan's
#     MergeAdjacentSameKind folds the two into one region, whose <remarks> now has
#     real content, which flips ExistingHasAnyTag).
#   * v(ADP3 T3h): the last two, DeprecatedWithNestedReturns and
#     ExampleWithNestedRemarks, left now. Their settle-at-cycle-2 delta was NOT a
#     clean merge -- it FABRICATED an unmarked tag that `--strip` could not remove
#     (register N2, the unkeyed-singular-match defect: content read from the
#     first occurrence ANYWHERE while presence came from a filtered view that had
#     removed the nested look-alike). T3h reads content from the located
#     standalone occurrence instead, so cycle 2 has nothing left to change. SWEEP
#     D below now asserts the fix, including the strip round-trip.
#
# Kept as an EXACT set, empty or not: a NEW name appearing here is a new
# non-idempotent shape and must be understood, never accommodated.
$aExpectedSettleAt2 = @()
$aSettleSorted = @($aSettleAt2 | Sort-Object)
Write-Host ("  settles at cycle 2 (not cycle 1): " + ($aSettleSorted -join ', '))
Check 'SWEEP A: the set of symbols that settle at cycle 2 is EXACTLY the pinned set' `
  ((($aSettleSorted -join '|') -eq (($aExpectedSettleAt2 | Sort-Object) -join '|'))) `
  ("actual=" + ($aSettleSorted -join ',') + "  pinned=" + (($aExpectedSettleAt2 | Sort-Object) -join ',') + `
   "  (a NEW name here is a new non-idempotent shape; a name DISAPPEARING is an improvement -- update the pin)")

# ===========================================================================
# SWEEP B -- idempotency_shapes.pas, whole-unit apply, every symbol
# ===========================================================================
Write-Host ''
Write-Host '=== SWEEP B: idempotency_shapes.pas, document --unit --apply, 3 cycles ===' -ForegroundColor Cyan

$b = Invoke-UnitSweep $fxShapes 'draglint_docp3sweep_shapes' 'idempotency_shapes.pas'
Check 'SWEEP B: symbols enumerated from the index' ($b.Symbols.Count -gt 0) "count=$($b.Symbols.Count)"
Write-Host ("  whole-file md5 by cycle: pristine={0} c1={1} c2={2} c3={3}" -f $b.FileMd5[0], $b.FileMd5[1], $b.FileMd5[2], $b.FileMd5[3])
Check 'SWEEP B: whole-file md5 is a FIXED POINT from cycle 2 (c2 == c3)' ($b.FileMd5[2] -eq $b.FileMd5[3]) `
  "c2=$($b.FileMd5[2]) c3=$($b.FileMd5[3])"
# idempotency_shapes.pas is held to the STRICTER standard the round-4 review
# states as binding -- a SECOND apply must be a zero-byte diff, i.e. every
# shape here settles at CYCLE 1, not merely "converges eventually". Pre-fix
# this reported edits:7 on cycle 2 AND cycle 3 and never stopped.
Check 'SWEEP B: cycle-2 apply reports no edits (the binding criterion: a 2nd apply is a zero-byte diff)' `
  ($b.Actions[1] -match '"edits":0') $b.Actions[1]
Check 'SWEEP B: cycle-3 apply reports no edits' ($b.Actions[2] -match '"edits":0') $b.Actions[2]

$bUnstable = @()
$bSettleAt2 = @()
foreach ($s in $b.Symbols) {
  $m1 = $b.BlockMd5[0][$s.QName]; $m2 = $b.BlockMd5[1][$s.QName]; $m3 = $b.BlockMd5[2][$s.QName]
  if ($m2 -ne $m3) { $bUnstable  += $s.QName }
  if ($m1 -ne $m2) { $bSettleAt2 += $s.QName }
}
Check 'SWEEP B: EVERY symbol block is a fixed point from cycle 2' ($bUnstable.Count -eq 0) `
  ("unstable=" + ($bUnstable -join ','))
Check 'SWEEP B: EVERY symbol block is a fixed point from cycle 1 (nothing settles late)' ($bSettleAt2.Count -eq 0) `
  ("settles-late=" + ($bSettleAt2 -join ','))

# ===========================================================================
# SWEEP C -- idempotency_shapes.pas, --qname-scoped, one scratch per symbol
#   This is the round-4 review's own measurement, reproduced verbatim as a
#   committed test: one symbol per file, applies with a reindex before each,
#   file size + md5 after every cycle.
# ===========================================================================
Write-Host ''
Write-Host '=== SWEEP C: idempotency_shapes.pas, document --qname --apply, isolated per symbol ===' -ForegroundColor Cyan

$cRoot = Join-Path C:\TEMP 'draglint_docp3sweep_qname'
if (Test-Path $cRoot) { Remove-Item $cRoot -Recurse -Force }
New-Item -ItemType Directory -Path $cRoot | Out-Null

# Enumerate from the index (never hardcoded) so a later fixture row is swept
# automatically. Callers are swept too: a caller is itself a documentable
# symbol, and one of this task's regressions was in the FRESH-insert path,
# which is exactly the path an undocumented caller takes.
$probeDb = Join-Path $cRoot 'probe.sqlite'
$probeDir = Join-Path $cRoot '_probe'
New-Item -ItemType Directory -Path $probeDir | Out-Null
Copy-Item $fxShapes $probeDir -Force
& $exePath index $probeDir --db $probeDb 2>$null | Out-Null
$shapeSyms = Get-Symbols $probeDb 'idempotency_shapes.pas'
Check 'SWEEP C: symbols enumerated from the index' ($shapeSyms.Count -gt 0) "count=$($shapeSyms.Count)"

Write-Host ('  {0,-46} {1,-7} {2,-7} {3,-7} {4,-7}  {5}' -f 'symbol','start','c1','c2','c3','actions')
$cUnstable = @()
$cResults  = @{}
$slug = 0
foreach ($s in $shapeSyms) {
  $slug++
  $r = Invoke-QNameSweep $fxShapes $cRoot $s.QName ('s{0:d2}' -f $slug)
  $cResults[$s.QName] = $r
  $stable = ($r.Md5s[2] -eq $r.Md5s[3])
  if (-not $stable) { $cUnstable += $s.QName }
  $tag = if ($stable) { '' } else { '   <== NOT A FIXED POINT' }
  Write-Host ('  {0,-46} {1,-7} {2,-7} {3,-7} {4,-7}  {5}{6}' -f `
    ($s.QName -replace '^idempotency_shapes\.',''), $r.Sizes[0], $r.Sizes[1], $r.Sizes[2], $r.Sizes[3], ($r.Actions -join ' '), $tag) `
    -ForegroundColor (@('Red','Gray')[[int]$stable])
}
Check 'SWEEP C: EVERY symbol reaches a fixed point from cycle 2 under --qname-scoped apply' ($cUnstable.Count -eq 0) `
  ("unstable=" + ($cUnstable -join ','))

# The six shapes the round-4 review measured as growing without bound, named
# explicitly so a regression names itself instead of hiding in a count.
#
# v(ADP3 T3c review): cycle-1 ACTION is now ALSO pinned per shape below, not
# just the later-cycle fixed point. Task 3c's own HasContent widening (adding
# Length(SeeAlso) > 0 / HasExampleTag / HasSinceTag) silently flipped
# SincePlusEmptyRemarks/ExamplePlusEmptyRemarks/SeeAlsoPlusEmptyRemarks from a
# cycle-1 "created" (fresh/additive-insert -- HasContent was False from the
# ORIGINAL parse pre-3c, since none of them had any OTHER content and their
# <remarks></remarks> is empty) to a cycle-1 "extended" (repair -- HasContent
# is now True immediately). This is the SAME safe, non-destructive,
# faster-convergence mechanism already documented for
# preserve_tags.TabSeparatedSeeAlso (see that fixture and
# docs/lint/URGENT-TODO-2026-07-26-index-doc-tag-coverage.md), confirmed by
# direct probe both ways -- but neither this sweep nor the original Task 3c
# report had actually PINNED it: every other assertion in this file is
# deliberately agnostic to which cycle does the work (so it would not have
# gone red), which is exactly why a genuine three-symbol branch flip went
# unnoticed. Pinning the cycle-1 action here makes a FUTURE flip of this kind
# visible instead of silent, for both directions (created<->extended).
# v(ADP3 T9): the LAST THREE 'created' pins FLIP to 'extended', and this is the
# re-pin the pin's own instruction above asks for -- "update the pin only after
# understanding why". The why, measured:
#
# T9 added Existing.HasRemarksTag to the repair-vs-fresh OR-chain in
# DRagLint.Doc.Document.pas, so a comment whose ONLY tag is an empty/whitespace
# <remarks> now routes to REPAIR on cycle 1 instead of stacking a second block
# for cycle 2 to reconcile. That is the SAME mechanism, in the SAME direction,
# that Task 3c's own widening applied to the three shapes below -- and it was
# recorded there as "safe, non-destructive, faster-convergence". T9 simply
# finishes the enumeration: HasRemarksTag was missing from a chain documented as
# "any tag at all".
#
# This flip is the FIX, not a regression, and the numbers say so. Cycle 2 used to
# be a DELETION -- it removed the author's own '/// <remarks></remarks>' line:
#   EmptyRemarksOnly    7502 -> 9481 -> 9456 -> 9456   (cycle 2 SHRANK by 25 = the line)
#   GappedEmptyRemarks  7502 -> 8204 -> 7687 -> 7687   (cycle 2 SHRANK by 517)
# and now settles on cycle 1 with nothing destroyed:
#   EmptyRemarksOnly    7502 -> 9456 -> 9456 -> 9456
#   GappedEmptyRemarks  7502 -> 8179 -> 8179 -> 8179
# Per the user ruling in docs/lint/TRIAGE-the-22-harvest-repair.md, repair must
# be non-destructive; routing here EARLIER is what makes it so, because repair
# ADOPTS the author's <remarks> as the container for its facts rather than
# emitting a rival one. A flip BACK to 'created' now means that fix regressed.
$expectedCycle1Action = @{
  'EmptyRemarksOnly'        = 'extended'  # v(ADP3 T9): was 'created' pre-T9 -- see comment above
  'WhitespaceRemarksOnly'   = 'extended'  # v(ADP3 T9): was 'created' pre-T9
  'TwoLineRemarksOnly'      = 'extended'  # v(ADP3 T9): was 'created' pre-T9
  'SincePlusEmptyRemarks'   = 'extended'  # v(ADP3 T3c): was 'created' pre-3c -- see comment above
  'ExamplePlusEmptyRemarks' = 'extended'  # v(ADP3 T3c): was 'created' pre-3c
  'SeeAlsoPlusEmptyRemarks' = 'extended'  # v(ADP3 T3c): was 'created' pre-3c
}
foreach ($nm in @('EmptyRemarksOnly','WhitespaceRemarksOnly','TwoLineRemarksOnly',
                  'SincePlusEmptyRemarks','ExamplePlusEmptyRemarks','SeeAlsoPlusEmptyRemarks')) {
  $qn = "idempotency_shapes.$nm"
  $r  = $cResults[$qn]
  if ($null -eq $r) { Check "SWEEP C: $nm present in the sweep" $false; continue }
  Check "SWEEP C CRITICAL: $nm reaches a fixed point (c2 == c3, no unbounded growth)" `
    ($r.Md5s[2] -eq $r.Md5s[3]) ("sizes=" + ($r.Sizes -join '->') + " actions=" + ($r.Actions -join ' '))
  Check "SWEEP C CRITICAL: $nm cycle-2 apply makes NO edit" ($r.Actions[1] -match '/0$') ($r.Actions -join ' ')
  Check "SWEEP C BRANCH: $nm cycle-1 action is pinned ($($expectedCycle1Action[$nm]))" `
    ($r.Actions[0] -match ('^' + [regex]::Escape($expectedCycle1Action[$nm]) + '/')) `
    ("actual=" + $r.Actions[0] + "  (a value here that DIFFERS from the pin is a branch flip -- update the pin only after understanding why, same rule as `$aExpectedSettleAt2 above)")
}

# The two convergent controls: already stable BEFORE the round-4 guard. If the
# guard perturbed a shape that was already fine, these go red. Also pins their
# cycle-1 action (both were ALREADY 'extended' pre-3c via Summary/Exception,
# which Task 3c's widening does not touch -- these must stay 'extended' and
# never flip to 'created', or the guard/routing has regressed for content that
# was already correctly routed before this task).
foreach ($nm in @('SummaryPlusEmptyRemarks','ExceptionPlusEmptyRemarks')) {
  $qn = "idempotency_shapes.$nm"
  $r  = $cResults[$qn]
  if ($null -eq $r) { Check "SWEEP C: $nm present in the sweep" $false; continue }
  Check "SWEEP C CONTROL: $nm still converges at cycle 1 (repair branch, unperturbed)" `
    (($r.Md5s[1] -eq $r.Md5s[2]) -and ($r.Md5s[2] -eq $r.Md5s[3])) ("sizes=" + ($r.Sizes -join '->'))
  Check "SWEEP C BRANCH: $nm cycle-1 action is pinned (extended)" `
    ($r.Actions[0] -match '^extended/') ("actual=" + $r.Actions[0])
}

# Non-destructiveness: the guard must suppress a duplicate INSERT, never
# convert the shape into a delete+reinsert that cannot represent <value>.
$rVal = $cResults['idempotency_shapes.ValuePlusEmptyRemarks']
if ($null -eq $rVal) { Check 'SWEEP C: ValuePlusEmptyRemarks present in the sweep' $false }
else {
  Check 'SWEEP C NON-DESTRUCTIVE: ValuePlusEmptyRemarks reaches a fixed point' ($rVal.Md5s[2] -eq $rVal.Md5s[3]) `
    ("sizes=" + ($rVal.Sizes -join '->'))
  $valTxt = [IO.File]::ReadAllText($rVal.Target)
  Check 'SWEEP C NON-DESTRUCTIVE: the unmodeled hand-written <value> tag SURVIVES all 3 cycles' `
    ($valTxt -match [regex]::Escape('<value>Hand-written value tag; unmodeled, must not be destroyed.</value>'))
  # Count the FULL tag text, not the bare '<value>' opener -- this fixture's
  # own header comment discusses <value> in prose, so a bare-opener count
  # would never be 1 and the check would be vacuously red.
  Check 'SWEEP C NON-DESTRUCTIVE: the <value> tag appears exactly once (not duplicated either)' `
    ((([regex]::Matches($valTxt, [regex]::Escape('<value>Hand-written value tag'))).Count) -eq 1) `
    ("count=" + ([regex]::Matches($valTxt, [regex]::Escape('<value>Hand-written value tag'))).Count)
}

# Load-bearing in the other direction: the guard must NOT suppress a genuine
# first insert. Without this check a guard that always returned daUnchanged
# would pass every stability assertion above.
$rNone = $cResults['idempotency_shapes.NoCommentAtAll']
if ($null -eq $rNone) { Check 'SWEEP C: NoCommentAtAll present in the sweep' $false }
else {
  Check 'SWEEP C GUARD NOT OVER-BROAD: NoCommentAtAll GAINS a comment on cycle 1' `
    (($rNone.Actions[0] -match '^created/1$') -and ($rNone.Md5s[1] -ne $rNone.Md5s[0])) ($rNone.Actions -join ' ')
  Check 'SWEEP C GUARD NOT OVER-BROAD: ...and is then a fixed point from cycle 2' `
    ($rNone.Md5s[2] -eq $rNone.Md5s[3]) ("sizes=" + ($rNone.Sizes -join '->'))
  $noneTxt = [IO.File]::ReadAllText($rNone.Target)
  Check 'SWEEP C GUARD NOT OVER-BROAD: a real facts block was written for NoCommentAtAll' `
    ($noneTxt -match 'Called from:.*CallsNoCommentAtAll')
  Check 'SWEEP C GUARD NOT OVER-BROAD: exactly ONE facts fence for NoCommentAtAll' `
    ((([regex]::Matches($noneTxt, [regex]::Escape('<!-- drag-lint:auto BEGIN -->'))).Count) -eq 1)
}

# Gapped twin of the CRITICAL shape.
$rGap = $cResults['idempotency_shapes.GappedEmptyRemarks']
if ($null -eq $rGap) { Check 'SWEEP C: GappedEmptyRemarks present in the sweep' $false }
else {
  Check 'SWEEP C GAPPED: GappedEmptyRemarks reaches a fixed point' ($rGap.Md5s[2] -eq $rGap.Md5s[3]) `
    ("sizes=" + ($rGap.Sizes -join '->'))
}

# Every /// line the sweep produced is 7-bit ASCII (both fixtures, final state).
foreach ($pair in @(@{n='SWEEP A'; p=$a.Target}, @{n='SWEEP B'; p=$b.Target})) {
  $bad = @()
  foreach ($l in [IO.File]::ReadAllLines($pair.p)) {
    if ($l -match '^\s*///') { foreach ($ch in $l.ToCharArray()) { if ([int]$ch -gt 126) { $bad += $l; break } } }
  }
  Check "$($pair.n): every emitted /// line is 7-bit ASCII" ($bad.Count -eq 0) ($bad -join ' | ')
}

# ===========================================================================
# SWEEP D -- the two formerly KNOWN-UNSTABLE shapes. PIN FLIPPED by T3h: these
# now assert the FIX, including the strip round-trip.
#
# What used to be true. <returns>/<summary>/<remarks> have no natural key
# (RxReturns/RxSummary/RxRemarks are singular .Match, not .Matches), so when
# MergeAdjacentSameKind folded a separately-inserted auto tag into a region that
# ALSO contained a nested look-alike, the singular CONTENT read picked the wrong
# occurrence from cycle 2 on while the PRESENCE gate correctly described the
# other one. These shapes still converged, so they passed the md5 fixed-point
# assertions above; what was not true was that the content was what the author
# wrote -- and the residue was UNMARKED, so `document --strip` could not remove
# it. This block pinned all three of those facts (converges / cycle 2 differs
# from cycle 1 / strip does not restore) so a fix would break the pin loudly.
#
# It did. v(ADP3 T3h) reads the content of the occurrence the presence gate is
# True ABOUT, located through a length-preserving mask, so:
#   1. cycle 2 is now byte-identical to cycle 1 -- there is no residue to carry;
#   2. `--strip` restores the pristine bytes EXACTLY, which is this task's
#      acceptance criterion and the reason it existed at all.
# Kept in its own sweep rather than folded into SWEEP A: the strip round-trip is
# measured per symbol here, on an isolated scratch copy, which SWEEP A does not do.
# ===========================================================================
Write-Host ''
Write-Host '=== SWEEP D: the two formerly-unstable shapes -- now asserting the FIX ===' -ForegroundColor Cyan
Write-Host '    DeprecatedWithNestedReturns / ExampleWithNestedRemarks: the unkeyed-singular-match'
Write-Host '    defect (register N2), closed by T3h. Each must now settle on cycle 1 and round-trip'
Write-Host '    through --strip back to the pristine bytes.'

$dRoot = Join-Path C:\TEMP 'draglint_docp3sweep_known'
if (Test-Path $dRoot) { Remove-Item $dRoot -Recurse -Force }
New-Item -ItemType Directory -Path $dRoot | Out-Null

foreach ($nm in @('DeprecatedWithNestedReturns','ExampleWithNestedRemarks')) {
  $r = Invoke-QNameSweep $fxPreserve $dRoot "preserve_tags.$nm" ('known_' + $nm)
  Write-Host ('  {0,-30} sizes={1}  actions={2}' -f $nm, ($r.Sizes -join '->'), ($r.Actions -join ' '))
  Check "SWEEP D: $nm CONVERGES (md5 c2 == c3)" `
    ($r.Md5s[2] -eq $r.Md5s[3]) ("md5=" + ($r.Md5s -join ' '))
  Check "SWEEP D FIXED (T3h): $nm cycle 2 is IDENTICAL to cycle 1 -- the disclosed residue is gone" `
    ($r.Md5s[1] -eq $r.Md5s[2]) ("md5=" + ($r.Md5s -join ' '))
  Check "SWEEP D FIXED (T3h): $nm cycle-2 apply makes NO edit" `
    ($r.Actions[1] -match '/0$') ($r.Actions -join ' ')
  # THE acceptance criterion: --strip recovers the pristine bytes.
  & $exePath index $r.Scratch --db $r.Db 2>$null | Out-Null
  & $exePath document --qname "preserve_tags.$nm" --db $r.Db --strip --apply 2>$null | Out-Null
  $afterStrip = Get-FileMd5 $r.Target
  Check "SWEEP D FIXED (T3h): $nm --strip RESTORES the pristine bytes -- the round-trip holds" `
    ($afterStrip -eq $r.Md5s[0]) ("pristine=$($r.Md5s[0]) afterStrip=$afterStrip")
}

Write-Host ''
Write-Host '--- SWEEP SUMMARY -----------------------------------------------------------'
Write-Host ("  SWEEP A  preserve_tags.pas      (unit)   symbols={0}  unstable={1}" -f $a.Symbols.Count, (@($aUnstable).Count))
Write-Host ("  SWEEP B  idempotency_shapes.pas (unit)   symbols={0}  unstable={1}" -f $b.Symbols.Count, (@($bUnstable).Count))
Write-Host ("  SWEEP C  idempotency_shapes.pas (qname)  symbols={0}  unstable={1}" -f $shapeSyms.Count, (@($cUnstable).Count))
Write-Host  '  SWEEP D  preserve_tags.DeprecatedWithNestedReturns, preserve_tags.ExampleWithNestedRemarks:'
Write-Host  '           the unkeyed singular-match defect (register N2), FIXED by T3h -- both now settle on'
Write-Host  '           cycle 1 and --strip restores the pristine bytes (see task-3h-report.md).'
Write-Host '-----------------------------------------------------------------------------'

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
