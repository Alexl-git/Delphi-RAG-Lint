<#
  run_shared_unit_staleness.ps1 -- Task 4 of
  docs\superpowers\plans\2026-08-13-shared-unit-docs-and-menu.md.

  THE DEFECT, measured on the real projects 2026-08-13 (engine e6d0b8b),
  read-only lint-all --project with no --fix:

      YADF       8 findings,  0 doc-drift
      YADFOT    64 findings, 31 doc-drift
      YADFSetup 58 findings, 34 doc-drift

  Every one of those 31/34 lands on a unit all three projects compile, while YADF
  reports zero on those same files. The concrete disagreement:
  YADF.Options.ParseEncoding stores

      Called from: YADF.Options.OptionTable (YADF.Options.pas), YadfMain.ParseFlags (YadfMain.pas)

  and renders, under YADFOT.sqlite, the same block without the YadfMain entry --
  every other line byte-identical, because YADFOT does not compile YadfMain.pas.

  WHY THE PLAN'S ORIGINAL TWO ASSERTIONS ARE NOT THE ONES BELOW. The plan asked
  for "A documents, B sees no drift" AND "B documents, A sees no drift". Those
  cannot both hold while an entry present in FRESH and absent from STORED is
  drift -- and it must stay drift, or a genuinely new caller is never recorded.
  Walk it: A documents, B regenerates, B's own caller is in FRESH and not in
  STORED, so B reports drift BY CONSTRUCTION. Forgiveness alone is
  one-directional; it silences the narrow project and does nothing about the wide
  one re-adding what the narrow one dropped.

  So the owner ruled for the MERGE (option 1): the writer unions the stored
  inbound entries it cannot see into what it renders, and the checker forgives
  the ones it cannot see. The property that actually holds -- and the one
  asserted here -- is CONVERGENCE:

      A documents  -> B still sees drift (B has a real new caller to record)
      B documents  -> the block is now the UNION of both projects' callers
      thereafter   -> NEITHER project sees drift, and neither writes again

  THE FIXTURE. Two projects with their own databases, sharing one directory of
  units. Each project's ownRoots declares the shared directory, or lint-all skips
  it and every count below is a silent zero (measured while building this).
  REINDEX AFTER EVERY WRITE: doc-drift reads the doc comment from the STORE, so a
  document --apply that is not followed by a reindex reports "no doc-comment on"
  and every assertion passes vacuously (also measured while building this).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-shared-staleness"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force -LiteralPath $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$shDir = Join-Path $WorkDir 'shared'
$aDir  = Join-Path $WorkDir 'a'
$bDir  = Join-Path $WorkDir 'b'
New-Item -ItemType Directory $shDir            | Out-Null
New-Item -ItemType Directory "$aDir\_D-RAG"    | Out-Null
New-Item -ItemType Directory "$bDir\_D-RAG"    | Out-Null

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- shared units -------------------------------------------------------------
# Marked: the unit under test. Unmarked: the control that must keep today's
# behaviour, because the marker is what opts in.
function New-SharedUnit([string]$Name, [string]$Routine, [bool]$Marked) {
  $mark = if ($Marked) { "   // dl:shared ProjA, ProjB" } else { "" }
  Write-Ascii (Join-Path $shDir "$Name.pas") @"
unit $Name;$mark

interface

procedure $Routine;

implementation

procedure $Routine;
begin
end;

end.
"@
}
New-SharedUnit 'Marked'  'MarkedRoutine'  $true    # the convergence case
New-SharedUnit 'Plain'   'PlainRoutine'   $false   # the unmarked control
New-SharedUnit 'MarkQ'   'MarkQRoutine'   $true    # a '?' entry is still drift
New-SharedUnit 'MarkDel' 'MarkDelRoutine' $true    # an in-closure deletion is still drift
New-SharedUnit 'MarkInt' 'MarkIntRoutine' $true    # intrinsic drift is unaffected
New-SharedUnit 'Busy'    'BusyRoutine'    $true    # a marked unit is never truncated
New-SharedUnit 'MarkTrunc' 'MarkTruncRoutine' $true # a truncated STORED line is still not forgiven
New-SharedUnit 'MarkFix' 'MarkFixRoutine' $true    # the SECOND writer entry point: --fix

# v(Q0, 2026-08-14) -- the 'Used in units:' label is a SECOND capped inbound site
# with the same defect, and it is capped by a DIFFERENT rule (DocDisplayCount,
# >15 total -> 10 shown) than 'Called from:'/'Used by:' (docs.max_callers). It
# needs its own fixture because it only exists for skClass/skInterface/skRecord,
# so none of the procedure-only units above can reach it.
Write-Ascii (Join-Path $shDir 'MarkType.pas') @'
unit MarkType;   // dl:shared ProjA, ProjB

interface

type
  TMarkType = class
  end;

implementation

end.
'@

# --- project A: calls everything, and calls Busy SEVEN times so its caller list
#     exceeds the display cap (max_callers is 5) and renders '(+N more)'.
$aBody = @'
unit AOnly;

interface

procedure CallFromA;

implementation

uses Marked, Plain, MarkQ, MarkDel, MarkInt, Busy, MarkTrunc, MarkFix;

procedure CallFromA;
begin
  MarkedRoutine;
  PlainRoutine;
  MarkQRoutine;
  MarkDelRoutine;
  MarkIntRoutine;
  MarkTruncRoutine;
  MarkFixRoutine;
end;

'@
foreach ($i in 1..7) {
  $aBody += "procedure BusyCaller$i;`nbegin`n  BusyRoutine;`nend;`n`n"
}
$aBody += "end.`n"
Write-Ascii (Join-Path $aDir 'AOnly.pas') $aBody

# 16 A-only units referencing TMarkType, so its 'Used in units:' total clears
# DocDisplayCount's >15 threshold. A-only because the convergence question is
# about entries the OTHER project cannot see.
foreach ($i in 1..16) {
  $nm = 'AUser{0:D2}' -f $i
  Write-Ascii (Join-Path $aDir "$nm.pas") @"
unit $nm;

interface

uses MarkType;

var
  G$nm : TMarkType;

implementation

end.
"@
}

Write-Ascii (Join-Path $bDir 'BOnly.pas') @'
unit BOnly;

interface

procedure CallFromB;

implementation

uses Marked, Plain, MarkFix, MarkTrunc;

procedure CallFromB;
begin
  MarkedRoutine;
  PlainRoutine;
  MarkFixRoutine;
  { B must CALL this one, or its fresh render is empty and the empty-render
    preservation rule (2026-08-14) decides before IsTruncated is ever reached --
    which is what the truncation case is supposed to be testing. Two rules
    tangled in one fixture is how the ORIGINAL truncation assertion came to pass
    for the wrong reason in the first place. }
  MarkTruncRoutine;
end;

end.
'@

# Without this the shared directory is OUTSIDE ownRoots and lint-all reports
# nothing on it -- every count below would be a silent zero.
Write-Ascii "$aDir\_D-RAG\drag-lint-project.json" '{ "ownRoots": [".", "../shared"] }'
Write-Ascii "$bDir\_D-RAG\drag-lint-project.json" '{ "ownRoots": [".", "../shared"] }'

$dbA = "$aDir\_D-RAG\A.sqlite"
$dbB = "$bDir\_D-RAG\B.sqlite"

function Reindex([string]$Db, [string[]]$Dirs) {
  foreach ($d in $Dirs) { & $Exe index $d --db $Db 2>&1 | Out-Null }
}
function DocApply([string]$Db, [string]$Unit) {
  & $Exe document --unit (Join-Path $shDir "$Unit.pas") --db $Db --apply --no-backup 2>$null
}
function DocEditCount([string]$Db, [string]$Unit) {
  $o = ((& $Exe document --unit (Join-Path $shDir "$Unit.pas") --db $Db 2>$null) -join "`n") -replace '</?para>',''
  if ($o -match 'decl\(s\)[^,]*,\s*(\d+)\s*edit\(s\)') { return [int]$Matches[1] }
  return 0
}
function DriftCount([string]$Db, [string]$Unit) {
  $o = & $Exe lint-all --db $Db --quiet 2>$null
  ($o | Select-String 'doc-drift' | Where-Object { $_.Line -match "\\$Unit\.pas:" }).Count
}
function BlockLine([string]$Unit, [string]$Label) {
  # P8 wraps each managed fact in <para>...</para>, so the label no longer
  # follows /// directly. The wrapper is tolerated in the pattern and removed
  # from the returned line, leaving every caller-list assertion below unchanged.
  $m = Select-String -Path (Join-Path $shDir "$Unit.pas") -Pattern "///\s*(<para>)?\s*$Label" | Select-Object -First 1
  if ($m) { return ($m.Line -replace '</?para>','').Trim() } else { return '' }
}

Reindex $dbA @($shDir, $aDir)
Reindex $dbB @($shDir, $bDir)
Check 'fixture indexed' ((Test-Path $dbA) -and (Test-Path $dbB))

Write-Host 'shared-unit staleness' -ForegroundColor Cyan

# ---------------------------------------------------------------- convergence --
# A documents everything it can see, then both stores are refreshed.
foreach ($u in 'Marked', 'Plain', 'MarkQ', 'MarkDel', 'MarkInt', 'Busy', 'MarkTrunc', 'MarkType', 'MarkFix') { DocApply $dbA $u | Out-Null }
Reindex $dbA @($shDir)
Reindex $dbB @($shDir)

Check 'A wrote a caller list naming its own unit' ((BlockLine 'Marked' 'Called from') -match 'AOnly') `
  "block says: $(BlockLine 'Marked' 'Called from')"

# B has a REAL new caller to record. This must stay drift -- it is rule 4, and
# dropping it means a genuinely new caller is never written down.
$driftB0 = DriftCount $dbB 'Marked'
Check 'a genuinely new caller is still drift' ($driftB0 -gt 0) `
  'B compiles BOnly, which A cannot see; that is not forgivable, it is work to do'

# B documents. With the merge, this must PRESERVE A's entry rather than replace it.
DocApply $dbB 'Marked' | Out-Null
Reindex $dbA @($shDir)
Reindex $dbB @($shDir)

$merged = BlockLine 'Marked' 'Called from'
Check 'the merged block keeps the other project''s caller' ($merged -match 'AOnly') `
  "block says: $merged"
Check 'the merged block gains this project''s caller' ($merged -match 'BOnly') `
  "block says: $merged"

Check 'B sees no drift on the merged block' ((DriftCount $dbB 'Marked') -eq 0) `
  'the assertion that would have caught all four incidents on this seam'
Check 'A sees no drift on the merged block' ((DriftCount $dbA 'Marked') -eq 0) `
  'A must not call the union stale just because it cannot see BOnly'

Check 'idempotent under A: no second edit' ((DocEditCount $dbA 'Marked') -eq 0)
Check 'idempotent under B: no second edit' ((DocEditCount $dbB 'Marked') -eq 0)

# ------------------------------------------------------------------- controls --
Check 'an UNMARKED shared unit keeps old behaviour' ((DriftCount $dbB 'Plain') -gt 0) `
  'the marker is what opts in -- nothing changes for anyone who has not marked'

# A '?' entry is KNOWN uncertain, so it is never forgiven. (The absence of '?'
# proves nothing -- JoinRefs emits the marker only on a MIXED list -- so this is
# sound in one direction only, which is why the other two conditions carry it.)
$qPath = Join-Path $shDir 'MarkQ.pas'
$qText = ([System.IO.File]::ReadAllText($qPath) -replace '</?para>','')
$qText = $qText -replace '(?m)(///\s*Called from:.*?)(\r?\n)', '$1, Ghost.Caller (Ghost.pas) ?$2'
[System.IO.File]::WriteAllText($qPath, $qText, [System.Text.Encoding]::ASCII)
Reindex $dbA @($shDir)
Check 'a ? entry is still drift' ((DriftCount $dbA 'MarkQ') -gt 0) `
  'uncertainty-derived entries must still be cleaned'

# An entry naming a unit that IS in this closure cannot be excused by "another
# project can see it" -- this project can see it, and it is gone.
$dPath = Join-Path $shDir 'MarkDel.pas'
$dText = ([System.IO.File]::ReadAllText($dPath) -replace '</?para>','')
$dText = $dText -replace '(?m)(///\s*Called from:.*?)(\r?\n)', '$1, AOnly.NoSuchProc (AOnly.pas)$2'
[System.IO.File]::WriteAllText($dPath, $dText, [System.Text.Encoding]::ASCII)
Reindex $dbA @($shDir)
Check 'an in-closure deletion is still drift' ((DriftCount $dbA 'MarkDel') -gt 0)

# Intrinsic facts keep byte-compare semantics: nothing about sharing makes a
# wrong Calls:/Pure line acceptable.
$iPath = Join-Path $shDir 'MarkInt.pas'
$iText = ([System.IO.File]::ReadAllText($iPath) -replace '</?para>','')
$iText = $iText -replace '(?m)(///\s*Called from:.*?\r?\n)', "`$1/// Calls: NoSuchCallee`r`n"
[System.IO.File]::WriteAllText($iPath, $iText, [System.Text.Encoding]::ASCII)
Reindex $dbA @($shDir)
Check 'intrinsic drift is unaffected' ((DriftCount $dbA 'MarkInt') -gt 0)

# v(Q0, 2026-08-14) -- A MARKED UNIT'S INBOUND LISTS ARE NEVER TRUNCATED, and
# that is the whole fix. Truncation was the ONE thing that stopped the union
# converging: a '(+N more)' window cannot be set-differenced soundly in either
# direction, so forgiveness had to be withheld, so a shared unit with more than
# `docs.max_callers` callers drifted forever. Uncapping the marked unit -- rather
# than raising the cap, which only moves the cliff -- lets the union that already
# ships do the rest.
#
# THE PRICE, stated because it is real: a line on a marked unit grows without
# bound, and marked units are marked precisely because many things call them.
#
# PAIRED GUARD: tests\autodoc\run_doc_cap.ps1 holds the cap in place for an
# UNMARKED unit (16 callers -> 5 shown, '(+11 more)'). Without it this change
# would "pass" by uncapping everything.
$busy = BlockLine 'Busy' 'Called from'
Check 'a marked unit''s inbound list is not truncated' (-not ($busy -match '\(\+\d+ more\)')) `
  "block says: $busy"
Check 'all 7 callers are shown, not the cap''s 5' ((([regex]::Matches($busy, 'BusyCaller\d')).Count) -eq 7) `
  "block says: $busy"
Check 'the uncapped block is stable under A' ((DriftCount $dbA 'Busy') -eq 0) `
  'a 7-entry line must be as idempotent as a 5-entry one'
Check 'no second edit under A on the uncapped block' ((DocEditCount $dbA 'Busy') -eq 0)

# THE EMPTY-RENDER CASE, fixed 2026-08-14. B compiles Busy and never calls
# BusyRoutine, so B's fresh render is EMPTY. Until today that was DESTRUCTIVE:
# TSharedFacts.BlockDrifted exited on `SRes <> FRes` ('Pure' vs '') before ever
# reaching the inbound labels, and TDocumenter then emitted a pure
# tekDeleteLines that stripped the wide project's documentation -- which A then
# rewrote on its next run, the unbounded loop dl:shared exists to end.
#
# Neither half of TSharedFacts could stop it alone: MergeInboundFacts merges
# INTO a rendered block and there was none. Both halves now ask
# HoldsForeignInboundEntries first.
Check 'the empty-render block is not deleted under B' ((DocEditCount $dbB 'Busy') -eq 0) `
  'B renders nothing; every stored entry names AOnly, which B cannot see'
Check 'and B reports no drift on it' ((DriftCount $dbB 'Busy') -eq 0) `
  'the checker half -- it used to decide on the residual compare'
Check 'A still sees no drift on the same block' ((DriftCount $dbA 'Busy') -eq 0) `
  'the wide project must not be provoked into rewriting it either'

# Note for the record: the OLD assertion here ('a truncated inbound list is not
# forgiven') was passing for the WRONG REASON -- it exited at that same residual
# compare and never reached IsTruncated, so that guard had NO coverage at all
# until the MarkTrunc fixture below.

# The SECOND capped inbound site, under a different rule (DocDisplayCount). One
# site fixed and the other left would converge 'Called from:' and leave every
# shared TYPE drifting, which is the same bug with a different label.
$ut = BlockLine 'MarkType' 'Used in units'
Check 'the Used-in-units fixture clears the cap' ((([regex]::Matches($ut, 'AUser\d\d')).Count) -eq 16) `
  "block says: $ut"
Check 'Used in units: is not truncated on a marked unit' (-not ($ut -match '\(\+\d+ more\)')) `
  "block says: $ut"

# The truncation guard in TSharedFacts is STILL LIVE and still needs a case:
# source written before this change, or by hand, can carry a '(+N more)' in the
# STORED line, and set difference over that window is unsound whatever produced
# it. Without the guard B forgives every entry here -- they all name AOnly,
# outside B's closure -- and reports no drift on a line it cannot reason about.
$tPath = Join-Path $shDir 'MarkTrunc.pas'
$tText = ([System.IO.File]::ReadAllText($tPath) -replace '</?para>','')
$tText = $tText -replace '(?m)(///\s*Called from:.*?)(\r?\n)', '$1 (+3 more)$2'
[System.IO.File]::WriteAllText($tPath, $tText, [System.Text.Encoding]::ASCII)
Reindex $dbA @($shDir)
Reindex $dbB @($shDir)
Check 'a truncated STORED line is still not forgiven' ((DriftCount $dbB 'MarkTrunc') -gt 0) `
  'a window onto the list is not the list; today''s byte compare stands'

# ------------------------------------------------- the OTHER writer entry point --
# `lint-all --fix` repairs through TDocLintRules.FixEditsForDocDrift, not through
# `document`. It is a SEPARATE path to TDocumenter.BuildFor and it has diverged
# from the checker twice: once by walking the whole store instead of the findings
# (aeeeee6, which planned 22 edits into a vendored repo), and once by calling
# BuildFor's two-argument overload, which hardcodes AIncludeSeeAlso := False while
# the checker defaults it True (9414826) -- the checker saw a block WITH seealso
# and called it stale, the repairer regenerated one WITHOUT and emitted nothing,
# so the finding was unrepairable by any command. Reading the source says this
# path inherits the merge; that is exactly what was believed both previous times.
# Assert it instead. Runs LAST because --fix repairs everything fixable in scope,
# including the controls asserted above.
# REGRESSION, YADF 2026-08-13. Every fixture above ends its block with 'Pure',
# which is a LABEL, so the stored-side slice always stopped in time and the bug
# below could not show. On YADF.Tokens the last fact in the block was the inbound
# line itself, so the slice ran past AUTO_END and swallowed the marker into an
# entry, writing this into the source:
#     /// Used in units: ..., YadfMain, YadfMain <!-- drag-lint:auto END -->
#     /// <!-- drag-lint:auto END -->
# -- a duplicated entry, a marker inside a fact line, and a doubled terminator.
$tokPath = Join-Path $shDir 'Marked.pas'
$tokText = ([System.IO.File]::ReadAllText($tokPath) -replace '</?para>','')
Check 'no marker text leaked into a fact line' (-not ($tokText -match '(?m)^\s*///\s*(Called from|Used by|Used in units):.*drag-lint:auto')) `
  'the stored-side parse must stop at AUTO_END, not at the next label'
Check 'exactly one END marker in the block' (([regex]::Matches($tokText, [regex]::Escape('drag-lint:auto END'))).Count -eq 1) `
  "found $((([regex]::Matches($tokText, [regex]::Escape('drag-lint:auto END')))).Count)"
Check 'no entry is duplicated in the merged list' (
  $(  $ln = (BlockLine 'Marked' 'Called from')
      $es = ($ln -replace '.*Called from:', '') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
      ($es | Sort-Object -Unique).Count -eq $es.Count )) `
  "list: $(BlockLine 'Marked' 'Called from')"

Check 'the --fix path starts from real drift' ((DriftCount $dbB 'MarkFix') -gt 0)

& $Exe lint-all --db $dbB --fix --apply --no-backup 2>$null | Out-Null
Reindex $dbA @($shDir)
Reindex $dbB @($shDir)

$fixed = BlockLine 'MarkFix' 'Called from'
Check '--fix keeps the other project''s caller' ($fixed -match 'AOnly') `
  "block says: $fixed"
Check '--fix gains this project''s caller' ($fixed -match 'BOnly') `
  "block says: $fixed"
Check '--fix converges under B' ((DriftCount $dbB 'MarkFix') -eq 0)
Check '--fix converges under A too' ((DriftCount $dbA 'MarkFix') -eq 0) `
  'the repairer must not write what the checker then calls stale -- incident five'

Write-Host ''
if ($script:Failed) { Write-Host 'run_shared_unit_staleness: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_shared_unit_staleness: OK' -ForegroundColor Green
exit 0
