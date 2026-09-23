<#
  run_enum_value_refs_bind.ps1 -- ENUM-VALUE references bind
  (docs\INBOX-enum-value-refs-never-bound.md; spec
  docs\superpowers\specs\2026-09-23-enum-value-ref-binding.md).

  ############################################################################
  # THIS GUARD IS COMMITTED **RED**, ON PURPOSE.                             #
  #                                                                          #
  # It was written and committed BEFORE any engine code existed (plan task   #
  # 2 of 9), so that tasks 3-8 are graded against checks nobody could tune   #
  # to the implementation after the fact. On the engine it was committed     #
  # against -- drag-lint 1.16.0-alpha, extractor 1.17.0-alpha, resolver      #
  # **1.5.1-alpha** -- the measured result is:                               #
  #                                                                          #
  #     PASS  1, 2, 6, 7, 8          FAIL  3, 4, 5, 9, 10, 11, 12, 13        #
  #                                                                          #
  # Any OTHER pattern on 1.5.1-alpha means THIS FIXTURE is broken, not the   #
  # engine. Fix the fixture; never relax a check to match what you saw.      #
  ############################################################################

  THE DEFECT. An enum value is referenced bare (`cmdDelta`) or qualified
  (`TCmd.cmdDelta` / `uEnumDecl.cmdDelta`). The bare form is indexed as a
  `read` ref; the qualified form as a `member-access` ref. Neither ever
  acquires a `refs.symbol_id`:

    * the resolve pass streams exactly `kind = 'call' OR kind = 'member-access'`
      (Storage.SQLite.pas:11737-11740), so a `read` ref never reaches
      ResolveOne at all;
    * a `member-access` ref that DOES reach it types its receiver to the enum,
      finds no routine and no property/field (MEMBER_KINDS = [skProperty,
      skField], CallResolver.pas:1743) and falls out unbound.

  So `find-callers --name cmdDelta --resolved` answers 0, FindReferencesTo is
  empty for every enum value, and the charts workstream's cross-process edge
  has to be recovered by a `name_text` string match -- the mechanism
  C:\Projects\CLAUDE.md names as the cause of the 2026-08-13 YADF incident.

  THE OWNER'S RULINGS (2026-09-23), both binding on this guard:
    R-A  **YES** -- `find-callers --resolved` reports an enum-value READ as a
         caller, with `mode = read`, exactly as the 2026-09-16 property ruling
         made a property read a reported caller. Check 9 asserts it.
    R-B  **ACCEPTED** -- the one-time autodoc `Called from:` churn on enum
         values that follows from R-A. Bound sites render PLAIN, never with
         ` ?`. Check 10 asserts the outcome (no double listing); this guard
         never runs `document --apply`, so it triggers none of that churn.
  (Also ruled: rule-0 duplicate collapse ships NOW -- check 13.)

  CHECK -> TASK MAP. Which task is expected to turn each check green:

    check  1  index health ................................. green already
    check  2  ROUTINE CONTROL ............................... green already
    check  3  A1-A5 bare reads bind ........................ task 4
    check  4  B1/B2 qualified (Shape B) bind ............... task 4
    check  5  pvHidden: own-file implementation enum ....... task 4
    check  6  N1-N4 stay NULL (POSITIVE CONTROL) ........... green already
    check  7  invariants: no enum in call_edges/member_accesses . green already
    check  8  E1 fence: complement universe untouched ...... green already
    check  9  R-A: find-callers --resolved reports reads ... task 6
    check 10  doc: "Used by:" driven by BOUND refs, deduped .. task 6
    check 11  lint-tree: stale-interface-reference ......... **task 8 (LAST)**
    check 12  E5: scoped pass NULLs its own universe ....... task 4
    check 13  rule 0: duplicate declarations collapse ...... task 4

  **Task 8 is the last check to go green** -- it wires `enum_value` into
  LintTree.IsRoutineKind, which the prior art (INBOX-property-refs-never-
  resolve) requires be done LAST, after the resolver binding is proven.

  THE POSITIVE CONTROLS -- do not weaken these, they are what makes the rest
  of the guard mean anything:

    * **Check 6 is the control AGAINST A HARD-WIRED NAME JOIN.** N1-N4 must
      stay NULL forever. If someone "fixes" the binding by joining on
      `name_text` alone, then N2 (a LOCAL spelled like an enum value), N3 (a
      unit CONST spelled like one) and N4 (TWO visible candidates) all bind
      wrongly and check 6 turns red. That is the entire reason those four
      sites exist in the fixture.
    * **Check 2 is the control on the FIXTURE.** The routine `DoWork` resolves
      today and must resolve in every later task. If check 2 ever reddens, the
      fixture broke, not the engine -- stop and fix the fixture.
    * **Check 13's MECHANISM assertion is REQUIRED, not optional.** Fixture B
      holds two content-identical copies of `uEnumDecl.pas`, so `cmdLoad` has
      two `enum_value` rows with the SAME qualified_name and the SAME
      (start_line, end_line) -- the library-twin shape. The OUTCOME assertion
      (A1 binds) would be green even with rule 0 absent, if `unit_uses`
      happened to resolve to exactly one copy. So check 13 ALSO asserts the
      `index` output's `enum-values:` line reports `collapsed >= 1`. That log
      line does not exist on 1.5.1-alpha -- it lands in task 4 -- and its
      absence is part of what makes check 13 red today. That is intended.
    * **Check 7 is the invariant fence.** `call_edges` stays ROUTINE-ONLY and
      `member_accesses` stays property/field-only; an enum binding is
      `refs.symbol_id` and NOTHING else (spec U3).

  EXECUTION ORDER -- **owner ruling R2, 2026-09-23, binding on this file.**
  The 1-13 numbering above is a LISTING order, not an execution order. This
  guard runs:

      1, 2, 7, 8, 3, 4, 5, 6, 9, 10, 11, 13, **12 LAST**

  because **check 12 deliberately MUTATES fixture A** (it rewrites
  uEnumDecl2.pas to add `const cmdLoad = 9;` to its interface, then
  re-indexes), and that mutation changes A5's expected state from BOUND to
  NULL. Every check that asserts the UNMUTATED state -- 3, 4, 5, 6, 9, 10 and
  11 -- must therefore run before it. Check 13 uses fixture B, a separate
  project and a separate database, so it is unaffected and sits wherever is
  convenient. The mutation point carries this note again in situ, and the
  guard prints its summary IN THE ORDER IT RAN, not in numeric order, so a
  reader can see the ordering was honoured. If this is ever reordered so that
  12 is not last, the guard reports a false GREEN or a false RED on A5 -- the
  "guard incapable of failing" class this repository has a recorded history
  of (tests\autotest, feedback_a_guard_can_be_incapable_of_failing).

  CHECK 12 GOT A SCOPED RUN -- no fallback was needed. Measured 2026-09-23 on
  1.5.1-alpha: the incremental re-index of the 4-file fixture A after the
  uEnumDecl2 edit printed `resolve: calls  starting SCOPED pass over 1 changed
  file(s)`. (The FIRST index of a database is always WHOLE-DB -- "this run
  rewrote more than one file in three" -- which is why check 12 re-indexes an
  already-built DB rather than building one.) The brief's documented fallback
  (assert the NULL-universe statement in ResolveEnumValueRefs' source, a
  WEAKER control) was therefore NOT taken, and must not be substituted while
  the scoped run keeps working.

  NO FIXTURE LINE NUMBER IS HARD-CODED. Every site is located at run time by
  the `{ A1 bind }`-style comment anchor in the fixture text this script just
  wrote (see `LineOf`, which FAILS LOUD if an anchor is not unique). A guard
  pinned to a literal line number silently stops testing what it names the
  moment the fixture is edited.

  CHECK 10 AND THE LABEL -- OWNER RULING R6, 2026-09-23, which CORRECTS the
  spec's surface table and the task brief. Both said `Called from:`. They are
  wrong, and a check asserting it could never go green:

    Doc.Facts.pas:561-568 -- TDocFacts.SymbolKind's single consumer is
    RenderFactsBlock, which picks the verb via CanBeCallTarget: a callable
    reads "Called from:", everything else reads "Used by:".

  `CanBeCallTarget(enum_value)` is False and spec U3 forbids touching it, so
  an enum value's bound references render under **`Used by:`**. A check that
  can never go green corrupts the grading contract exactly as badly as one
  that can never go red -- it would push task 6 toward the forbidden fix.

  BUT RELABELLING ALONE WOULD MAKE CHECK 10 GREEN TODAY, which is why this
  check does not stop at the relabel. Doc.Facts.pas:1451-1459 records that for
  a NON-ROUTINE symbol the reference list is not call-site-restricted at all:
  "the unresolved bucket has never held call sites ... it holds plain
  references to the symbol's NAME". So today's `Used by:` line is ALREADY
  produced by a name match. Measured on 1.5.1-alpha, 2026-09-23:

    --qname uEnumDecl.TCmd.cmdLoad   -> Used by: uEnumBoth.Both, uEnumUse.UseIt
    --qname uEnumDecl.TCmd.cmdShadow -> Used by: uEnumUse.UseIt
    --qname uEnumDecl.TCmd.cmdDelta  -> Used by: uEnumBoth.Both, uEnumUse.UseIt

  The first line already lists UseIt exactly once, plain, with no ` ?`, so the
  dedupe assertions alone pass today. Check 10 therefore carries TWO
  DISCRIMINATING assertions, each the doc-layer twin of a control this guard
  already has elsewhere, and each RED today for a reason task 6 can clear:

    * **cmdShadow must list NO usages** (doc-layer twin of check 6's
      name-join control). Today the name bucket lists `uEnumUse.UseIt` via the
      LOCAL `cmdShadow`; once the list is driven by BOUND refs, `cmdShadow`
      has zero bound references and the line disappears.
    * **cmdDelta must list uEnumUse.UseIt and NEVER uEnumBoth.Both**
      (doc-layer twin of check 9's cmdDelta assertion). Today the name bucket
      lists both; after binding, N4 declines under R2 (two visible candidates)
      and Both must go.

  The "the line exists at all" assertion is kept so the check still fails on
  empty output rather than passing on nothing.

  FIXTURE A (four units, one scratch project):
    uEnumDecl.pas   TCmd = (cmdLoad, cmdDelta, cmdShadow, cmdClash)
                    {$SCOPEDENUMS ON} TScoped = (scOne, scTwo)
                    procedure DoWork                    -- the routine CONTROL
                    implementation: TPriv = (pvHidden)  -- impl-only enum
    uEnumDecl2.pas  TOther = (cmdDelta, cmdOther)       -- a SECOND cmdDelta
    uEnumUse.pas    uses uEnumDecl; const cmdClash = 5; local cmdShadow
                    A1 A2 A3 (bind) N1 N2 N3 (must not) B1 B2 (Shape B)
    uEnumBoth.pas   uses uEnumDecl, uEnumDecl2
                    N4 (two candidates, must not) A4 A5 (bind)
  FIXTURE B (second scratch project, rule 0): uEnumDecl.pas, an IDENTICAL
    copy at dup\uEnumDecl.pas, and uEnumUse.pas.

  Scratch: C:\TEMP\draglint_enum_value_refs_bind (created and owned here).
  Both fixtures are indexed into THIS GUARD'S OWN databases only. Nothing
  here reads or writes the worktree self-index or any corpus database.
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}

# Per-CHECK roll-up, recorded in the order the checks actually RAN (owner
# ruling R2 above). A check is GREEN only if every assertion under it passed.
$script:checkOrder = @()
$script:checkState = @{}
$script:checkName  = @{}
function CheckN([int]$num, [string]$n, [bool]$ok, [string]$d = '') {
  if (-not $script:checkState.ContainsKey($num)) {
    $script:checkOrder += $num; $script:checkState[$num] = $true; $script:checkName[$num] = $n
  }
  if (-not $ok) { $script:checkState[$num] = $false }
  Check ("check {0}: {1}" -f $num, $n) $ok $d
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_enum_value_refs_bind'
if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
New-Item -ItemType Directory $scratch | Out-Null
$dirA = Join-Path $scratch 'A'
$dirB = Join-Path $scratch 'B'
New-Item -ItemType Directory $dirA | Out-Null
New-Item -ItemType Directory $dirB | Out-Null
New-Item -ItemType Directory (Join-Path $dirB 'dup') | Out-Null

# `W` as in run_property_refs_resolve.ps1 (ASCII + CRLF), with the target
# directory as a parameter because this guard writes TWO fixture projects.
function W([string]$dir, [string]$name, [string]$body) {
  [IO.File]::WriteAllText((Join-Path $dir $name), ($body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

# `Sql` as in run_property_refs_resolve.ps1 lines 249-262 -- `sql --json`
# returns columns[] + POSITIONAL rows[][], so each row is mapped onto its
# column names. A failed query (empty stdout) is an EMPTY array. The only
# change is the leading $db parameter: this guard queries two databases.
function Sql([string]$db, [string]$q) {
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($j)) { return ,@() }
  try { $o = $j | ConvertFrom-Json } catch { return ,@() }
  $cols = @($o.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($o.rows)) {
    $h = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $h[$cols[$i]] = @($r)[$i] }
    $out += [pscustomobject]$h
  }
  return ,$out
}

# ---------------------------------------------------------------------------
# Run-time site location. NEVER hard-code a fixture line number: locate every
# site by the comment anchor the fixture itself carries. A non-unique anchor
# is a FIXTURE defect and aborts with exit 2, which is deliberately distinct
# from a RED (exit 1) -- a broken anchor makes every downstream check
# meaningless rather than merely failing.
# ---------------------------------------------------------------------------
function LineOf([string]$path, [string]$anchor) {
  $lines = [IO.File]::ReadAllText($path) -split "`r`n"
  $hits = @()
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($anchor)) { $hits += ($i + 1) } }
  if ($hits.Count -ne 1) {
    Write-Host ("FATAL: fixture anchor '{0}' matched {1} line(s) in {2} -- the FIXTURE is broken, not the engine" -f $anchor, $hits.Count, $path) -ForegroundColor Red
    exit 2
  }
  return $hits[0]
}
# The single ref at (file, line, kind, name), with the qualified_name its
# symbol_id joins to. Returns 0 or 1 rows; the checks assert the count too.
function RefRow([string]$db, [string]$file, [int]$line, [string]$kind, [string]$name) {
  $q = "SELECT r.id AS rid, r.symbol_id AS sid, r.receiver_text AS rcv, s.qualified_name AS qn " +
       "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
       "WHERE f.path = '$file' AND r.start_line = $line AND r.kind = '$kind' AND r.name_text = '$name'"
  return ,(Sql $db $q)
}
function IsBoundTo($rows, [string]$qname) {
  return (@($rows).Count -eq 1 -and $rows[0].qn -eq $qname)
}
function IsNull($rows) {
  return (@($rows).Count -eq 1 -and [string]::IsNullOrEmpty([string]$rows[0].sid))
}
function Resolved([string]$db, [string]$name) {
  $raw = & $exePath query find-callers --name $name --resolved --json --db $db 2>$null | Out-String
  if ($raw.Trim() -eq '') { return @() }
  try { return @(($raw | ConvertFrom-Json)) } catch { return @() }
}

# ===========================================================================
# FIXTURE A
# ===========================================================================
W $dirA 'uEnumDecl.pas' @'
unit uEnumDecl;
interface
type
  TCmd = (cmdLoad, cmdDelta, cmdShadow, cmdClash);
  {$SCOPEDENUMS ON}
  TScoped = (scOne, scTwo);
  {$SCOPEDENUMS OFF}
procedure DoWork;
implementation
type
  TPriv = (pvHidden);
procedure DoWork;
begin
  if Ord(pvHidden) = 0 then ;
end;
end.
'@

W $dirA 'uEnumDecl2.pas' @'
unit uEnumDecl2;
interface
type
  TOther = (cmdDelta, cmdOther);
implementation
end.
'@

W $dirA 'uEnumUse.pas' @'
unit uEnumUse;
interface
uses uEnumDecl;
const
  cmdClash = 5;
procedure UseIt;
implementation
procedure UseIt;
var
  C: TCmd;
  S: TScoped;
  cmdShadow: Integer;
begin
  C := cmdLoad;                       { A1 bind }
  if C = cmdDelta then DoWork;        { A2 bind + routine CONTROL }
  case C of cmdLoad: ; end;           { A3 bind, case label (HANDLER shape) }
  cmdShadow := 1;                     { N1 write: must NOT bind }
  if cmdShadow > 0 then ;             { N2 read of a LOCAL: R3a }
  if cmdClash > 0 then ;              { N3 read of a unit CONST: R3c }
  S := TScoped.scOne;                 { B1 bind, Shape B type receiver }
  C := uEnumDecl.cmdLoad;             { B2 bind, Shape B UNIT receiver }
end;
end.
'@

W $dirA 'uEnumBoth.pas' @'
unit uEnumBoth;
interface
uses uEnumDecl, uEnumDecl2;
procedure Both;
implementation
procedure Both;
var
  C: TCmd;
  O: TOther;
begin
  if C = cmdDelta then ;              { N4 two visible candidates: R2 }
  O := cmdOther;                      { A4 bind through the second uses }
  C := cmdLoad;                       { A5 bind }
end;
end.
'@

$fDecl = Join-Path $dirA 'uEnumDecl.pas'
$fUse  = Join-Path $dirA 'uEnumUse.pas'
$fBoth = Join-Path $dirA 'uEnumBoth.pas'
$dbA   = Join-Path $scratch 'a.sqlite'

# Every site, located from the fixture text written above. The A/B/N labels
# are the spec's; `exp` is the qualified_name the site must bind to, or $null
# for a site that must stay NULL.
$L = @{
  A1 = @{ f = $fUse;  l = (LineOf $fUse  '{ A1 bind }');                      k = 'read';          n = 'cmdLoad';   exp = 'uEnumDecl.TCmd.cmdLoad' }
  A2 = @{ f = $fUse;  l = (LineOf $fUse  '{ A2 bind + routine CONTROL }');    k = 'read';          n = 'cmdDelta';  exp = 'uEnumDecl.TCmd.cmdDelta' }
  A3 = @{ f = $fUse;  l = (LineOf $fUse  '{ A3 bind, case label');            k = 'read';          n = 'cmdLoad';   exp = 'uEnumDecl.TCmd.cmdLoad' }
  A4 = @{ f = $fBoth; l = (LineOf $fBoth '{ A4 bind through the second uses }'); k = 'read';       n = 'cmdOther';  exp = 'uEnumDecl2.TOther.cmdOther' }
  A5 = @{ f = $fBoth; l = (LineOf $fBoth '{ A5 bind }');                      k = 'read';          n = 'cmdLoad';   exp = 'uEnumDecl.TCmd.cmdLoad' }
  B1 = @{ f = $fUse;  l = (LineOf $fUse  '{ B1 bind, Shape B type receiver }'); k = 'member-access'; n = 'scOne';   exp = 'uEnumDecl.TScoped.scOne' }
  B2 = @{ f = $fUse;  l = (LineOf $fUse  '{ B2 bind, Shape B UNIT receiver }'); k = 'member-access'; n = 'cmdLoad'; exp = 'uEnumDecl.TCmd.cmdLoad' }
  N1 = @{ f = $fUse;  l = (LineOf $fUse  '{ N1 write: must NOT bind }');      k = 'write';         n = 'cmdShadow'; exp = $null }
  N2 = @{ f = $fUse;  l = (LineOf $fUse  '{ N2 read of a LOCAL: R3a }');      k = 'read';          n = 'cmdShadow'; exp = $null }
  N3 = @{ f = $fUse;  l = (LineOf $fUse  '{ N3 read of a unit CONST: R3c }'); k = 'read';          n = 'cmdClash';  exp = $null }
  N4 = @{ f = $fBoth; l = (LineOf $fBoth '{ N4 two visible candidates: R2 }'); k = 'read';         n = 'cmdDelta';  exp = $null }
  PV = @{ f = $fDecl; l = (LineOf $fDecl 'Ord(pvHidden)');                    k = 'read';          n = 'pvHidden';  exp = 'uEnumDecl.TPriv.pvHidden' }
}

Write-Host ''
Write-Host ('== fixture A: sites located from the fixture text (no line number is hard-coded) ==') -ForegroundColor DarkGray
foreach ($k in @('A1','A2','A3','A4','A5','B1','B2','N1','N2','N3','N4','PV')) {
  Write-Host ("   {0,-3} {1}:{2,-3} {3,-13} {4}" -f $k, (Split-Path $L[$k].f -Leaf), $L[$k].l, $L[$k].k, $L[$k].n) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '== check 1: fixture A indexes clean ==' -ForegroundColor Cyan
$idxOut = & $exePath index $dirA --db $dbA 2>&1 | Out-String
$idxExit = $LASTEXITCODE
CheckN 1 'index exits 0' ($idxExit -eq 0) "exit=$idxExit"
CheckN 1 'index reported no parse errors' ($idxOut -match '0 errors') ''

Write-Host ''
Write-Host '== check 2: ROUTINE CONTROL -- green today and in EVERY later task ==' -ForegroundColor Cyan
$dw = @((Resolved $dbA 'DoWork') | Where-Object { $_.target_qname -eq 'uEnumDecl.DoWork' })
CheckN 2 'DoWork: exactly 1 resolved caller' ($dw.Count -eq 1) ($dw | ConvertTo-Json -Compress)
CheckN 2 'DoWork: the caller is uEnumUse.UseIt' ($dw.Count -eq 1 -and $dw[0].caller_qname -eq 'uEnumUse.UseIt') ($dw | ConvertTo-Json -Compress)
CheckN 2 'DoWork: certain' ($dw.Count -eq 1 -and $dw[0].confidence -eq 'certain') ($dw | ConvertTo-Json -Compress)

Write-Host ''
Write-Host '== check 7: INVARIANTS -- call_edges stays routine-only, member_accesses property/field-only ==' -ForegroundColor Cyan
$ceEnum = Sql $dbA "SELECT COUNT(*) AS n FROM call_edges ce JOIN symbols s ON s.id = ce.target_symbol_id WHERE s.kind = 'enum_value'"
CheckN 7 '0 enum values in call_edges.target_symbol_id' (@($ceEnum).Count -eq 1 -and [int]$ceEnum[0].n -eq 0) ($ceEnum | ConvertTo-Json -Compress)
$maEnum = Sql $dbA "SELECT COUNT(*) AS n FROM member_accesses ma JOIN symbols s ON s.id = ma.member_symbol_id WHERE s.kind = 'enum_value'"
CheckN 7 '0 enum values in member_accesses.member_symbol_id' (@($maEnum).Count -eq 1 -and [int]$maEnum[0].n -eq 0) ($maEnum | ConvertTo-Json -Compress)

Write-Host ''
Write-Host '== check 8: E1 fence -- the unresolved-call COMPLEMENT universe is untouched ==' -ForegroundColor Cyan
# The enum names come from the DB, not a literal list, so a fixture edit
# cannot quietly narrow what this fence looks for.
$enumNames = @((Sql $dbA "SELECT DISTINCT name FROM symbols WHERE kind = 'enum_value' ORDER BY name") | ForEach-Object { $_.name })
CheckN 8 'fixture health: the DB carries the expected enum values (fence has something to look for)' ($enumNames.Count -ge 8) ($enumNames -join ',')
$acRaw  = (& $exePath ambiguous-calls --db $dbA --json 2>$null) -join "`n"
$acExit = $LASTEXITCODE
# The fence is "no enum value is named", which an EMPTY $acRaw satisfies
# trivially -- so a failed, renamed or refused `ambiguous-calls` would report
# GREEN with the E1 fence never evaluated. Prove the verb actually ran before
# reading anything into its silence. A clean fixture legitimately emits `[]`,
# so the test is that it PARSES as JSON, not that it is non-empty (verified
# 2026-09-23: good DB -> exit 0, `[]`; missing DB -> exit 2, 63 bytes of
# non-JSON error text).
CheckN 8 'ambiguous-calls actually ran (exit 0) -- an empty result must not pass by default' ($acExit -eq 0) "exit=$acExit raw=$acRaw"
$acParsed = $false
try { $null = $acRaw | ConvertFrom-Json; $acParsed = $true } catch { $acParsed = $false }
CheckN 8 'ambiguous-calls returned parseable JSON' $acParsed "raw=$acRaw"
$acHit = @($enumNames | Where-Object { $acRaw -match ("\b" + [regex]::Escape($_) + "\b") })
CheckN 8 'ambiguous-calls names NO fixture enum value' ($acHit.Count -eq 0) ("hits=" + ($acHit -join ',') + " raw=" + $acRaw)
$uniPath = Join-Path $PSScriptRoot 'run_callsite_kind_universe.ps1'
$uniOut  = Join-Path $scratch 'universe.out.log'
$uniErr  = Join-Path $scratch 'universe.err.log'
$uniProc = Start-Process pwsh -ArgumentList '-NoProfile', '-File', $uniPath, '-Exe', $exePath `
             -Wait -PassThru -NoNewWindow -RedirectStandardOutput $uniOut -RedirectStandardError $uniErr
CheckN 8 'run_callsite_kind_universe.ps1 PASS when invoked from this guard' ($uniProc.ExitCode -eq 0) "exit=$($uniProc.ExitCode) log=$uniOut"

Write-Host ''
Write-Host '== check 3: A1-A5, bare reads bind (Shape A) ==' -ForegroundColor Cyan
foreach ($k in @('A1','A2','A3','A4','A5')) {
  $s = $L[$k]
  $r = RefRow $dbA $s.f $s.l $s.k $s.n
  CheckN 3 ("{0} ({1}:{2}) is one {3} ref of '{4}'" -f $k, (Split-Path $s.f -Leaf), $s.l, $s.k, $s.n) (@($r).Count -eq 1) ($r | ConvertTo-Json -Compress)
  CheckN 3 ("{0} binds to {1}" -f $k, $s.exp) (IsBoundTo $r $s.exp) ($r | ConvertTo-Json -Compress)
}

Write-Host ''
Write-Host '== check 4: B1/B2, qualified reads bind (Shape B) ==' -ForegroundColor Cyan
$rB1 = RefRow $dbA $L.B1.f $L.B1.l 'member-access' 'scOne'
CheckN 4 'B1: scOne is one member-access ref' (@($rB1).Count -eq 1) ($rB1 | ConvertTo-Json -Compress)
CheckN 4 'B1: receiver_text is the TYPE TScoped' (@($rB1).Count -eq 1 -and $rB1[0].rcv -eq 'TScoped') ($rB1 | ConvertTo-Json -Compress)
CheckN 4 'B1: binds to uEnumDecl.TScoped.scOne' (IsBoundTo $rB1 'uEnumDecl.TScoped.scOne') ($rB1 | ConvertTo-Json -Compress)
$rB2 = RefRow $dbA $L.B2.f $L.B2.l 'member-access' 'cmdLoad'
CheckN 4 'B2: cmdLoad is one member-access ref' (@($rB2).Count -eq 1) ($rB2 | ConvertTo-Json -Compress)
CheckN 4 'B2: receiver_text is the UNIT uEnumDecl' (@($rB2).Count -eq 1 -and $rB2[0].rcv -eq 'uEnumDecl') ($rB2 | ConvertTo-Json -Compress)
CheckN 4 'B2: binds to uEnumDecl.TCmd.cmdLoad' (IsBoundTo $rB2 'uEnumDecl.TCmd.cmdLoad') ($rB2 | ConvertTo-Json -Compress)

Write-Host ''
Write-Host '== check 5: pvHidden -- own file, IMPLEMENTATION section (R1) ==' -ForegroundColor Cyan
$rPV = RefRow $dbA $L.PV.f $L.PV.l 'read' 'pvHidden'
CheckN 5 'pvHidden: one read ref inside uEnumDecl DoWork' (@($rPV).Count -eq 1) ($rPV | ConvertTo-Json -Compress)
CheckN 5 'pvHidden: binds to uEnumDecl.TPriv.pvHidden' (IsBoundTo $rPV 'uEnumDecl.TPriv.pvHidden') ($rPV | ConvertTo-Json -Compress)

Write-Host ''
Write-Host '== check 6: N1-N4 stay NULL -- POSITIVE CONTROL against a hard-wired name join ==' -ForegroundColor Cyan
Write-Host '   (a name-only binding turns N2 (local), N3 (unit const) and N4 (two candidates) RED)' -ForegroundColor DarkGray
foreach ($k in @('N1','N2','N3','N4')) {
  $s = $L[$k]
  $r = RefRow $dbA $s.f $s.l $s.k $s.n
  CheckN 6 ("{0} ({1}:{2}) is one {3} ref of '{4}'" -f $k, (Split-Path $s.f -Leaf), $s.l, $s.k, $s.n) (@($r).Count -eq 1) ($r | ConvertTo-Json -Compress)
  CheckN 6 ("{0} symbol_id IS NULL" -f $k) (IsNull $r) ($r | ConvertTo-Json -Compress)
}
$wBound = Sql $dbA "SELECT COUNT(*) AS n FROM refs WHERE kind = 'write' AND symbol_id IS NOT NULL"
CheckN 6 'no write ref anywhere carries a symbol_id (spec N1: write is never a candidate)' (@($wBound).Count -eq 1 -and [int]$wBound[0].n -eq 0) ($wBound | ConvertTo-Json -Compress)

Write-Host ''
Write-Host '== check 9: R-A -- find-callers --resolved reports an enum-value READ as a caller ==' -ForegroundColor Cyan
# ONE ROW PER SITE, not per caller. MEASURED on run_property_refs_resolve.ps1's
# `Count` case (2026-09-23, engine 1.16.0-alpha): Count returns 3 rows across
# 2 callers because CountIt holds two accesses on one line. So UseIt owns
# A1 + A3 + B2 = 3 rows and Both owns A5 = 1 row. Both counts are DERIVED from
# the site table above, never written as a literal.
$cmdLoadSites  = @($L.Keys | Where-Object { $L[$_].exp -eq 'uEnumDecl.TCmd.cmdLoad' })
$useItSites    = @($cmdLoadSites | Where-Object { $L[$_].f -eq $fUse })
$bothSites     = @($cmdLoadSites | Where-Object { $L[$_].f -eq $fBoth })
$cl = @((Resolved $dbA 'cmdLoad') | Where-Object { $_.target_qname -eq 'uEnumDecl.TCmd.cmdLoad' })
CheckN 9 ("cmdLoad: {0} resolved rows, one per bound site" -f $cmdLoadSites.Count) ($cl.Count -eq $cmdLoadSites.Count) ("n=$($cl.Count) expected=$($cmdLoadSites.Count) " + ($cl | ConvertTo-Json -Compress))
CheckN 9 'cmdLoad: caller set is exactly {uEnumUse.UseIt, uEnumBoth.Both}' ((@($cl | ForEach-Object { $_.caller_qname } | Sort-Object -Unique) -join ',') -eq 'uEnumBoth.Both,uEnumUse.UseIt') (@($cl | ForEach-Object { $_.caller_qname } | Sort-Object -Unique) -join ',')
CheckN 9 ("cmdLoad: uEnumUse.UseIt owns {0} rows (A1, A3, B2)" -f $useItSites.Count) (@($cl | Where-Object { $_.caller_qname -eq 'uEnumUse.UseIt' }).Count -eq $useItSites.Count) ($cl | ConvertTo-Json -Compress)
CheckN 9 ("cmdLoad: uEnumBoth.Both owns {0} row (A5)" -f $bothSites.Count) (@($cl | Where-Object { $_.caller_qname -eq 'uEnumBoth.Both' }).Count -eq $bothSites.Count) ($cl | ConvertTo-Json -Compress)
CheckN 9 'cmdLoad: every row confidence=certain' ($cl.Count -gt 0 -and @($cl | Where-Object { $_.confidence -eq 'certain' }).Count -eq $cl.Count) ($cl | ConvertTo-Json -Compress)
CheckN 9 'cmdLoad: every row mode=read (R-A)' ($cl.Count -gt 0 -and @($cl | Where-Object { $_.mode -eq 'read' }).Count -eq $cl.Count) ($cl | ConvertTo-Json -Compress)
$cd = @(Resolved $dbA 'cmdDelta')
CheckN 9 'cmdDelta: exactly 1 resolved row (A2 only -- N4 declined under R2)' ($cd.Count -eq 1) ($cd | ConvertTo-Json -Compress)
CheckN 9 'cmdDelta: that row is uEnumUse.UseIt -> uEnumDecl.TCmd.cmdDelta' ($cd.Count -eq 1 -and $cd[0].caller_qname -eq 'uEnumUse.UseIt' -and $cd[0].target_qname -eq 'uEnumDecl.TCmd.cmdDelta') ($cd | ConvertTo-Json -Compress)
CheckN 9 'cmdDelta: uEnumBoth.Both is NEVER reported' (@($cd | Where-Object { $_.caller_qname -eq 'uEnumBoth.Both' }).Count -eq 0) ($cd | ConvertTo-Json -Compress)
$co = @(Resolved $dbA 'cmdOther')
CheckN 9 'cmdOther: exactly 1 resolved row, uEnumBoth.Both -> uEnumDecl2.TOther.cmdOther' ($co.Count -eq 1 -and $co[0].caller_qname -eq 'uEnumBoth.Both' -and $co[0].target_qname -eq 'uEnumDecl2.TOther.cmdOther') ($co | ConvertTo-Json -Compress)

Write-Host ''
Write-Host '== check 10: doc -- UseIt listed ONCE plain, and the list driven by BOUND refs not NAMES ==' -ForegroundColor Cyan
# DRY RUN ONLY -- no --apply. R-B accepts the corpus churn, but this guard
# must never cause any of it. --qname targets the VALUE, not its parent type
# (verified 2026-09-23: --qname on a sibling value, cmdShadow, renders a
# DIFFERENT usage set). The verb is "Used by:", not "Called from:" -- owner
# ruling R6, see the header.
function UsedByLine([string]$qname) {
  $o = (& $exePath document --qname $qname --db $dbA 2>$null) -join "`n"
  $lines = @(($o -split "`r?`n") | Where-Object { $_ -match 'Used by:' })
  return [pscustomobject]@{ Raw = $o; Lines = $lines; Text = ($lines -join ' ') }
}
# (a) DEDUPE, on the symbol with THREE bound sites in one routine.
$dLoad = UsedByLine 'uEnumDecl.TCmd.cmdLoad'
CheckN 10 'cmdLoad has a "Used by:" line at all' ($dLoad.Lines.Count -ge 1) $dLoad.Raw
$useItHits = @([regex]::Matches($dLoad.Text, [regex]::Escape('uEnumUse.UseIt'))).Count
CheckN 10 'cmdLoad "Used by:" lists uEnumUse.UseIt EXACTLY once (3 bound sites, one entry)' ($useItHits -eq 1) "hits=$useItHits line=$($dLoad.Text)"
CheckN 10 'cmdLoad "Used by:" carries no " ?" unverified marker' ($dLoad.Lines.Count -ge 1 -and $dLoad.Text -notmatch '\s\?') "line=$($dLoad.Text)"
# (b) DISCRIMINATOR 1 -- the doc-layer twin of check 6's name-join control.
# cmdShadow's only same-named references are the LOCAL in UseIt, which binds
# to nothing. A name-driven list shows UseIt; a BOUND-ref-driven list is empty.
$dShadow = UsedByLine 'uEnumDecl.TCmd.cmdShadow'
CheckN 10 'cmdShadow lists NO usages -- the list is driven by BOUND refs, not by NAME' ($dShadow.Lines.Count -eq 0) "lines=$($dShadow.Lines.Count) raw=$($dShadow.Raw)"
# (c) DISCRIMINATOR 2 -- the doc-layer twin of check 9's cmdDelta assertion.
# N4 in uEnumBoth.Both declines under R2 (two visible cmdDelta), so Both must
# never appear on uEnumDecl.TCmd.cmdDelta's line; only UseIt's A2 may.
$dDelta = UsedByLine 'uEnumDecl.TCmd.cmdDelta'
CheckN 10 'cmdDelta has a "Used by:" line at all' ($dDelta.Lines.Count -ge 1) $dDelta.Raw
CheckN 10 'cmdDelta "Used by:" names uEnumUse.UseIt (A2 bound)' ($dDelta.Text -match [regex]::Escape('uEnumUse.UseIt')) "line=$($dDelta.Text)"
CheckN 10 'cmdDelta "Used by:" NEVER names uEnumBoth.Both (N4 declined under R2)' ($dDelta.Lines.Count -ge 1 -and $dDelta.Text -notmatch [regex]::Escape('uEnumBoth.Both')) "line=$($dDelta.Text)"

Write-Host ''
Write-Host '== check 11: lint-tree sees a removed ENUM MEMBER (TASK 8, the LAST to go green) ==' -ForegroundColor Cyan
$base = Join-Path $scratch 'base.json'
& $exePath lint-tree --unit $fDecl --db $dbA --write-baseline $base --format json *> $null
CheckN 11 'baseline written' (Test-Path $base) ''
$buf = Join-Path $scratch 'uEnumDecl.buf.pas'
$srcDecl = [IO.File]::ReadAllText($fDecl)
[IO.File]::WriteAllText($buf, ($srcDecl -replace 'cmdLoad, ', ''), [Text.Encoding]::ASCII)
CheckN 11 'buffer really dropped cmdLoad from TCmd' ([IO.File]::ReadAllText($buf) -match '(?m)^\s*TCmd = \(cmdDelta, cmdShadow, cmdClash\);') (([IO.File]::ReadAllText($buf) -split "`r`n" | Where-Object { $_ -match 'TCmd' }) -join ' ')
$lt = & $exePath lint-tree --unit $fDecl --db $dbA --buffer $buf --baseline $base --format json 2>$null | Out-String
$lj = $null; try { $lj = $lt | ConvertFrom-Json } catch { }
CheckN 11 'lint-tree returned JSON' ($null -ne $lj) $lt
if ($null -ne $lj) {
  $stale = @($lj.findings | Where-Object { $_.rule -eq 'stale-interface-reference' -or $_.message -match 'no longer declares' })
  CheckN 11 ("removing cmdLoad reports {0} stale references, one per BOUND site (A1, A3, B2, A5)" -f $cmdLoadSites.Count) ($stale.Count -eq $cmdLoadSites.Count) ("n=$($stale.Count) expected=$($cmdLoadSites.Count) " + ($lj.findings | ConvertTo-Json -Compress -Depth 4))
  CheckN 11 'enum_value is no longer in not_reportable' (-not (@($lj.not_reportable) -contains 'enum_value')) (@($lj.not_reportable) -join ',')
}

# ===========================================================================
# FIXTURE B -- rule 0, content-identical duplicate declarations.
# A SEPARATE project and a SEPARATE database, so it is unaffected by the
# fixture-A mutation that check 12 is about to make, and may run here.
# ===========================================================================
Write-Host ''
Write-Host '== check 13: rule 0 -- two identical uEnumDecl copies collapse to ONE candidate ==' -ForegroundColor Cyan
Copy-Item $fDecl (Join-Path $dirB 'uEnumDecl.pas')
Copy-Item $fDecl (Join-Path $dirB 'dup\uEnumDecl.pas')
Copy-Item $fUse  (Join-Path $dirB 'uEnumUse.pas')
$dbB = Join-Path $scratch 'b.sqlite'
$idxB = & $exePath index $dirB --db $dbB 2>&1 | Out-String
CheckN 13 'fixture B indexes clean' (($LASTEXITCODE -eq 0) -and ($idxB -match '0 errors')) "exit=$LASTEXITCODE"
# FIXTURE HEALTH FIRST: without two identical twins, rule 0 has nothing to
# collapse and the outcome assertion below would be vacuous.
$twins = Sql $dbB "SELECT s.id, s.qualified_name AS qn, s.start_line AS sl, s.end_line AS el, f.path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = 'enum_value' AND s.name = 'cmdLoad' ORDER BY f.path"
CheckN 13 'fixture B really holds TWO cmdLoad enum_value rows (the library-twin shape)' (@($twins).Count -eq 2) ($twins | ConvertTo-Json -Compress)
CheckN 13 'the twins share qualified_name AND (start_line, end_line)' (@($twins).Count -eq 2 -and $twins[0].qn -eq $twins[1].qn -and $twins[0].sl -eq $twins[1].sl -and $twins[0].el -eq $twins[1].el) ($twins | ConvertTo-Json -Compress)
# THE MECHANISM ASSERTION -- required, see the header. Without it the outcome
# below is green even with rule 0 absent, whenever unit_uses happens to pick
# exactly one copy.
$evLine = @(($idxB -split "`r?`n") | Where-Object { $_ -match 'enum-values:' })
CheckN 13 'MECHANISM: the index output carries an "enum-values:" stage line' ($evLine.Count -ge 1) (($idxB -split "`r?`n" | Where-Object { $_ -match 'resolve:' }) -join ' | ')
$collapsed = -1
if ($evLine.Count -ge 1 -and (($evLine -join ' ') -match 'collapsed\D{0,20}(\d+)')) { $collapsed = [int]$Matches[1] }
CheckN 13 'MECHANISM: "enum-values:" reports collapsed >= 1' ($collapsed -ge 1) ("collapsed=$collapsed line=" + ($evLine -join ' '))
# THE OUTCOME.
$bUseFile = Join-Path $dirB 'uEnumUse.pas'
$bA1Line  = LineOf $bUseFile '{ A1 bind }'
$rBA1 = RefRow $dbB $bUseFile $bA1Line 'read' 'cmdLoad'
CheckN 13 'OUTCOME: A1 in project B binds to uEnumDecl.TCmd.cmdLoad despite the duplicate' (IsBoundTo $rBA1 'uEnumDecl.TCmd.cmdLoad') ($rBA1 | ConvertTo-Json -Compress)

# ===========================================================================
# ###   CHECK 12 RUNS LAST -- OWNER RULING R2, 2026-09-23.                ###
# ###                                                                     ###
# ###   It MUTATES fixture A: uEnumDecl2.pas gains `const cmdLoad = 9;`   ###
# ###   in its INTERFACE, which makes A5 (in uEnumBoth.Both, which uses   ###
# ###   uEnumDecl2) shadowed under R3c and therefore NULL. Checks 3, 4,   ###
# ###   5, 6, 9, 10 and 11 all assert the UNMUTATED state of fixture A    ###
# ###   and have run above. DO NOT MOVE THIS BLOCK EARLIER: doing so      ###
# ###   makes A5 report a false GREEN or a false RED depending on where   ###
# ###   it lands, which is the "guard incapable of failing" failure mode. ###
# ###                                                                     ###
# ###   The edit adds a NAME, not a TYPE, precisely so the re-index stays ###
# ###   SCOPED (a WHOLE-DB pass would mask the trap via ClearCallEdges,   ###
# ###   which NULLs every refs.symbol_id anyway). Measured SCOPED on      ###
# ###   1.5.1-alpha, so the brief's weaker source-inspection fallback was ###
# ###   not needed and must not be substituted.                           ###
# ===========================================================================
Write-Host ''
Write-Host '== check 12: E5 -- a SCOPED re-resolve NULLs its own universe (MUTATES fixture A; runs LAST) ==' -ForegroundColor Cyan
W $dirA 'uEnumDecl2.pas' @'
unit uEnumDecl2;
interface
type
  TOther = (cmdDelta, cmdOther);
const
  cmdLoad = 9;
implementation
end.
'@
$incOut = & $exePath index $dirA --db $dbA 2>&1 | Out-String
CheckN 12 'incremental index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
CheckN 12 'the calls stage ran SCOPED (a WHOLE-DB pass would mask the trap)' ($incOut -match 'starting SCOPED pass') (($incOut -split "`r?`n" | Where-Object { $_ -match 'resolve: calls' }) -join ' | ')
$rA5b = RefRow $dbA $L.A5.f $L.A5.l 'read' 'cmdLoad'
CheckN 12 'A5 is now NULL: uEnumDecl2 interface const cmdLoad shadows it (R3c)' (IsNull $rA5b) ($rA5b | ConvertTo-Json -Compress)
$rA1b = RefRow $dbA $L.A1.f $L.A1.l 'read' 'cmdLoad'
CheckN 12 'A1 is STILL bound: it is nulled by the scoped universe and re-binds (uEnumUse cannot see uEnumDecl2)' (IsBoundTo $rA1b 'uEnumDecl.TCmd.cmdLoad') ($rA1b | ConvertTo-Json -Compress)
$rA4b = RefRow $dbA $L.A4.f $L.A4.l 'read' 'cmdOther'
CheckN 12 'A4 is STILL bound: cmdOther is untouched by the edit' (IsBoundTo $rA4b 'uEnumDecl2.TOther.cmdOther') ($rA4b | ConvertTo-Json -Compress)

# ===========================================================================
Write-Host ''
Write-Host '== SUMMARY, in the order the checks RAN (owner ruling R2: 12 is last) ==' -ForegroundColor Cyan
foreach ($num in $script:checkOrder) {
  $ok = $script:checkState[$num]
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  check {0,2}  {1}" -f $num, $s) -ForegroundColor $c
}
$passed = @($script:checkOrder | Where-Object { $script:checkState[$_] } | Sort-Object)
$failed = @($script:checkOrder | Where-Object { -not $script:checkState[$_] } | Sort-Object)
Write-Host ("  PASS: " + ($passed -join ', ')) -ForegroundColor Green
Write-Host ("  FAIL: " + ($failed -join ', ')) -ForegroundColor Red
Write-Host '  On resolver 1.5.1-alpha the EXPECTED result is PASS 1,2,6,7,8 / FAIL 3,4,5,9,10,11,12,13.' -ForegroundColor DarkGray
Write-Host '  Any other pattern there means the FIXTURE is broken, not the engine.' -ForegroundColor DarkGray

Write-Host ''
if ($script:fail) { Write-Host 'ENUM-VALUE-REFS-BIND: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ENUM-VALUE-REFS-BIND: PASS' -ForegroundColor Green
exit 0
