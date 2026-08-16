# Session 23 implementation plan

Written at the end of session 22 (2026-08-16) for execution after a context
reset. **Planning was done first, deliberately, so the implementing session can
start coding immediately rather than re-deriving.**

## Resume state

| | |
|---|---|
| branch | `main`, HEAD **`f6d7c3f`** |
| unpushed | **85 commits, ON PURPOSE** -- Group A is finished, so the gate is the OWNER'S to lift. Owner intends to publish soon after Group B and parts of C close, then check it in the IDE. |
| working tree | clean |
| battery | **303/303** green at `f6d7c3f` |
| exe | `third_party\dll-win64\drag-lint.exe`, built 2026-08-16 13:55 |
| INBOX | 13 open, 96 retired |
| branches | Nothing of ours to merge -- all work went straight to `main`. NOTE: `salvage/lsp-codeaction-agent` carries 2 owner-authored commits from 2026-08-12 (LSP codeAction for `dl:ok` markers) never merged; left alone deliberately. |

**Consumer source edits are NOW PERMITTED** (owner, end of session 22). The
earlier "consumer files will wait" instruction is lifted. YADF / YADFOT /
YADFSetup / DataCopy may be modified.

## Working rules that keep being re-learned

Do not skip these; every one cost a wasted cycle in session 22.

1. **Re-measure before coding.** Seven notes across two sessions had the wrong
   stated mechanism. Reading the note is not measuring.
2. **Every guard needs a POSITIVE CONTROL, and must be run against the UNFIXED
   build.** Twice in session 22 a "the bad thing stopped" assertion passed with
   the fix disabled. For any rule NARROWING, the fixture must contain a true
   positive that still fires.
3. **Fixture size can silently defeat a test** -- `ScopedResolveIsSound` declines
   once the changed set reaches a third of the corpus.
4. **`document --qname X --json` never contains the block text**, only a summary.
5. **PowerShell `(...).Count` is `$null`, not 0**, when `Where-Object` matches
   nothing. Wrap in `@()`.
6. **Rebuild before the battery**; editing source after a build fails
   `run_exe_freshness`. Battery is ~16 min, 302 suites.
7. `.pas` / `.dpr` / `.ps1` are strict 7-bit ASCII + CRLF. The Write tool emits
   LF -- convert after writing.
8. **NEVER reindex a project DB with a folder scan** -- `index --all --only <Section>`.

---

## Order of work

Ordered by value per unit of risk. Items 1-3 are consumer-visible; 4-5 are engine.

1. **DataCopy `local-field-prefix`** -- mechanical renames, lowest risk. Warm-up.
2. **`unused-parameter` false-positive hardening** -- the owner's callback-signature
   hypothesis. Biggest consumer-visible win if it holds.
3. **`converter-editor-phase-g` 2.11** (strong type aliases never indexed) --
   HIGH, and the same defect class as the already-fixed 2.1.
4. **`used-before-assignment`** -- **shape A is DONE** (same-predicate suppression shipped, 39 -> 35). Shapes B/C/D remain; a
   "do not implement" recommendation is a legitimate outcome.
5. **Group B remainder** -- see below; already planned with anchors.

Sections 1-4 are filled in from three Fable investigations run at the end of
session 22 (see the sections below). Section 5 is carried over unchanged.

---

## 1. DataCopy `local-field-prefix` -- 5 mechanical renames

All sites verified; **no name collisions** (checked every local/param in each
routine, the class fields `Fconfig/Flogger/Ftrlogger/Fstatus`, and the dpr
globals). `L` matches the file's own convention (`LName` already at
`uZeissRoutines.pas:578, 887`).

**Do NOT strip the prefix to `Name` in the .dpr** -- a unit-level
`Name: Ansistring` (`DataCopy.dpr:42`) is live in that very routine. The
`fix-naming` refactor verb (`DRagLint.Refactor.NamingFix.pas:540-560`) DOES
handle this rule but proposes exactly that strip, so it would collide. Rename
manually.

| # | file | routine | rename | every line to change |
|---|---|---|---|---|
| 1 | `uZeissRoutines.pas` | `TZEISSTransfer.isValidZeissFileName` (696-707) | `FName` -> `LName` | **698** decl, **700**, **702**, **704**, **705** (commented CodeSite line -- update for consistency) |
| 2 | `uZeissRoutines.pas` | `TZEISSTransfer.BackupFile` (1742-1944) | `FName` -> `LName` | **1746** decl, **1862**, **1864**, **1866**, **1873**, **1877**, **1879**. Nested `DoBackupInternal` does not touch it. Sibling local `Fpath:1747` is NOT flagged (lowercase second letter) -- leave it. |
| 3 | `uZeissRoutines.pas` | `TZEISSTransfer.TransferFile` (1946+) | `FName` -> `LName` | **1953** decl, **2003**, **2005**, **2007**, **2014**, **2018**, **2020**. Routine already uses `LStem`/`LStripped`; no `LName` yet. |
| 4 | `DataCopy.dpr` | `MicroniteActive` | `FHandle` -> `LHandle` | **63** decl, **68**, **70** (TWO occurrences) |
| 5 | `DataCopy.dpr` | `MicroniteActive` | `FLastError` -> `LLastError` | **64** decl, **69** -- **note the existing casing typo `FLAstError`**, which a case-insensitive rename must catch and normalise -- **74** (two occurrences in `Format` args), **77** |

`ExtractAllTags(const FName: ...)` at `uZeissRoutines.pas:35/708` is a PARAMETER,
not a local. Correctly not flagged. Leave it.

---

## 2. `unused-parameter` -- the owner's hypothesis is CONFIRMED (4 of 5)

| # | site | routine | verdict |
|---|---|---|---|
| 1 | `EExtraExceptionInfo.pas:468` `ACustom` | `DescribeExceptionInfo` | callback -- passed bare at `:529` to `RegisterEventCustomDataRequest` |
| 2 | `EExtraExceptionInfo.pas:470` `ALogBuilder` | same | same |
| 3 | `EExtraExceptionInfo.pas:485` `ACustom` | `DescribeExceptionMessage` | callback -- registered at `:533`, **inside an INACTIVE `{$IFDEF E_ADD_CUSTOM_MESSAGE}`** |
| 4 | `uMainZeissCopy.pas:3838` `Path` | `TfrmZeissCopy.isValidZeissFileName` | `TFilterPredicate` -- passed at `:3303` to `TDirectory.GetFiles` |
| 5 | `uZeissRoutines.pas:696` `Path` | `TZEISSTransfer.isValidZeissFileName` | **TRUE POSITIVE** -- signature copied from the form's predicate but the method is referenced NOWHERE (zero refs, zero grep hits) |

**#5 must keep firing.** An evidence-based suppression correctly leaves it. The
owner should wire it, delete it, or `dl:ok` it -- that is a source decision, not
a rule one.

### Where the rule is

NOT a `.scm` rule. `TDeadCodeChecker.Check` ->  nested `CheckUnusedParams`
(`src\diagnostics\DRagLint.Diagnostics.DeadCodeChecks.pas:497`, emit at `:645`),
called from `DRagLint.CLI.pas:7417` (`DoLint`) and `:10458` (`DoLintAll`).

It already guards: `var`/`out` (`:604`), `Self`/`Sender` (`:633-641`), the
first-param-`Sender` handler skip (`:560+`), virtual/dynamic/override/message/
abstract via the `ContractMethods` two-pass (`CollectContractDecls:423`, checked
at `:532`), `IsVclFormEventName` (`:213`), asm bodies, external routines. The
doc block at `:148-151` already admits the interface-implementation gap.

### THE FIX -- a same-file syntactic addr-taken pass, NO database

Add a pass-1 collector beside `CollectContractDecls`, mirroring its design
(registered in `Check`, ~`:2394`). Walk the tree and record:

* bare `identifier` arguments inside any `exprCall` argument list;
* `@identifier` -- an `exprUnary` with `kAt`. **Keyword nodes are NAMED nodes**
  in this grammar; that has caused four separate bugs, so do not assume `kAt` is
  anonymous;
* RHS identifiers of assignments (`OnFoo := Handler`).

Then in `CheckUnusedParams`, after the `ContractMethods` check at `:532`, `Exit`
if the enclosing routine's bare name is in that set.

**Why syntactic and not store-backed:** this suppresses findings 1-4 **including
#3**, whose registration sits in an inactive `{$IFDEF}` -- the DB has no symbol
and no ref for it, but the linter's raw tree-sitter parse sees it. It also works
on the plain `lint <file>` path, which has no store at all.

Accepted imprecision: matching is by BARE NAME, so a method sharing a name with
an addr-taken free routine is also suppressed. That is the same trade-off
`ContractMethods` already makes -- document it, do not fix it.

### Follow-ups, in order, NOT part of this change

1. **Store-backed addr-taken** for CROSS-unit passing. The data exists today --
   `refs.kind='read'` rows for a bare routine argument were verified
   (`uMainZeissCopy.pas:3303 read isValidZeissFileName`). Needs `Store` + file id
   plumbed into `TDeadCodeChecker.Check`, exactly as `TNamingChecker.Check`
   already receives them (`DRagLint.CLI.pas:10456`).
2. **DFM event bindings** -- `refs.kind='event-binding'` rows exist from `.dfm`
   indexing. Would let the hardcoded `IsVclFormEventName` list retire. Note
   `symbol_facts.dfm_event` exists but is **0 for every DataCopy symbol**, i.e.
   not populated -- use the refs, not that column.
3. **Interface implementations** -- needs heritage resolution via
   `type_ancestors`. Most work; keep as the documented gap.

### Fixture + POSITIVE CONTROL

One unit, template `tests\autotest\run_addr_of_is_a_definition.ps1`:

* **A1 -- POSITIVE CONTROL, MUST STILL FIRE.** `procedure Plain(A, B: Integer);`
  uses only `A`, called normally as `Plain(1, 2)`, never passed bare. Assert
  exactly ONE `unused-parameter`, on `B`. Without this the narrowing proves
  nothing.
* A2 -- predicate with an unused param passed bare to another routine -> silent.
* A3 -- routine registered via `@Handler` -> silent.
* A4 -- registration inside `{$IFDEF NEVER_DEFINED}` -> silent (pins finding #3).
* A5 -- method whose name matches an addr-taken free routine only by bare name
  -> silent, documenting the accepted collision.

**Caution:** `run_addr_of_is_a_definition.ps1` is about FLOW analysis (`@Buf[0]`
as a possible write, in `Analysis.Flow.Lattices.pas`). It is a harness template
here, NOT prior art for routine addr-taken -- different concept.

---

## 3. `converter-editor-phase-g` -- ALMOST ALL ALREADY FIXED. Verify and retire.

Re-measured against `main` @ `10902bd` and the live `library-Win64.sqlite`.
**2.4, 2.5 (engine half), 2.6, 2.9, 2.10 and 2.11 are already fixed, with
autotests.** This is a verify-and-close job, not an implementation job.

### 2.11 strong type aliases -- FIXED, verified live

`query --name TFileName --db ...library-Win64.sqlite` returns **1 row,
`kind=type`, `System.SysUtils.TFileName : string`, exit 0**. `TCaption` ->
`Vcl.Controls.TCaption : string`. `TDate`/`TTime` -> `System.TDate`/`System.TTime`
(declared in `System.pas`, not SysUtils -- the note's expectation was off only on
the unit).

Fix lives at `src\parser\DRagLint.Parser.Delphi13.pas:943-977`
(`TryWalkStrongAlias`), dispatched at `:1664`. Root cause, documented at
`:916-931`: the strong form carries **TWO `type:` fields** -- the `(kType)`
keyword first, the real target second. `TryWalkAlias` read the first via
`ChildByField`, found `kType`, and exited, so every strong alias fell through
unemitted. Exactly the 2.1 shape, fixed the same way: take the LAST `type:`
wrapper. Gated on the `kType` keyword, so it can only ADD rows, never alter
existing ones -- the note's "handler added, not extractor loosened" property
holds by construction.

Fixture + positive controls already exist: `tests\autotest\run_type_decl_shapes.ps1`.

**The converter consequence is resolved**: `Bde.DBTables.TTable.TableName` is
`TFileName`, `FireDAC...TFDTable.TableName` is `String`, and the declaration row
now states `TFileName` IS `string` -- the fact Auto-Match needed.

### The rest

| finding | state | action |
|---|---|---|
| 2.4 substring / no `--exact` / rejects qualified names | **FIXED.** Lookup is exact SQL (`name = :name`, `Storage.SQLite.pas:3253`); the old "substring" behaviour was the FUZZY FALLBACK. Rows now carry `match_kind: exact\|fuzzy`, and `--exact` suppresses the fallback so 0 rows means "no such symbol". | none |
| 2.5 tie order / FMX-over-VCL | **Engine half FIXED** -- name lookups `ORDER BY qualified_name`; qname lookups have a documented TOTAL ordering (real decl before forward stub, implemented before abstract, then file/line/id) at `Storage.SQLite.pas:3255-3307`, asserted by `run_qname_row_order.ps1`. **Product half OPEN**: a `--framework vcl\|fmx` hint is a small post-filter but needs an OWNER RULING. **Do not invent it silently.** | ask owner |
| 2.6 enum members unreachable | **FIXED.** `surface` accepts an enum (`Storage.SQLite.pas:3953`); verified `surface --qname System.Classes.TAlignment` prints members with ordinals. | none |
| 2.7 ad-hoc DB has no FTS tables | **UNCONFIRMED, likely stale.** Literal harvest is unconditional (`Core.Indexer.pas:952-960`) and the FTS5 DDL is in the ordinary migration every writable open runs (`Storage.Schema.pas:288-302`) -- both since v10, which PREDATES the finding. The 2026-08-02 measurement was probably against a pre-v10 DB kept alive by the (since-fixed) fingerprint-less skip. | **THE ONLY POSSIBLY-LIVE ITEM.** Write `run_text_query_adhoc_db.ps1` |
| 2.8 exit codes / stderr banner | **Banner half FIXED** (`--quiet`, `CLI.pas:373`). The exit-code contract (0 = hits, 1 = zero hits, 2 = usage) is still missing from the `query` row of `docs\AI-USAGE.md`, though sibling verbs document theirs at lines 149/155. | one docs line |
| 2.9 `--refs-as-leaves` not pruning | **FIXED.** Exact repro re-run: `proptree --qname FireDAC.Comp.Client.TFDUpdateSQL --min-visibility published --refs-as-leaves` now returns **10 properties** with component-typed ones as unexpanded leaves -- versus the reported 364 leaves / 354 phantoms. | none |
| 2.10 case-sensitive `--name` | **FIXED.** Exact-then-NOCASE retry with `--case-sensitive` opt-out. Verified `--name TFDRDBMSDataSet` finds `TFDRdbmsDataSet`, exit 0. | none |

2.4 / 2.5-engine / 2.10 all shipped together as one coherent commit -- the single
`--exact` + ordering change this note asked for already happened.

### Execution order for section 3

1. Re-run `run_type_decl_shapes.ps1`, `run_query_case_insensitive.ps1`,
   `run_qname_row_order.ps1` as regression evidence.
2. Write and run **`run_text_query_adhoc_db.ps1`** (2.7): fixture unit with one
   distinctive literal -> ad-hoc `index <dir> --db` -> assert
   `query --text --substring` finds it. **Negative control: a nonsense phrase
   must exit 1**, otherwise a match-everything bug reads as a pass. If it fails,
   start at `DoQueryText` (`CLI.pas:3527-3561`) and `SearchText`
   (`Storage.SQLite.pas:4878`).
3. Add the exit-code line to `docs\AI-USAGE.md` (2.8).
4. Update the INBOX banner with the measurements above, then retire the note to
   `INBOX-Done\` once 2.7's test is green. **2.5's framework hint stays open as
   an owner question** -- do not close the note over it silently.

---

## 4. `used-before-assignment` -- SHAPE A **IMPLEMENTED** (owner request); rest still DO NOT IMPLEMENT

> ### DONE 2026-08-16 (end of session 22): same-predicate suppression shipped
>
> Owner: *"Can we at least textually compare the predicate ... just to remove
> this very specific false positive?"* Yes -- shape A only, and it is in.
>
> `DRagLint.Diagnostics.FlowChecks.pas` -- `ThenGuardName` / `CollectThenGuards`
> / `AssignedInRange` / `AssignedUnderSameGuard`, hooked into the emit site in
> the **info arm only**. A `must` finding says the variable is unassigned on
> EVERY path, which no guard correlation can excuse, so the warning arm is
> untouched: this can downgrade noise, never hide a certain use-before-assignment.
>
> **Self-index 39 -> 35**, removing exactly the four `tmark` sites.
> Test: `testsutotestun_flow_same_predicate_guard.ps1`.
>
> Scope is deliberately tiny: only a BARE LOCAL IDENTIFIER predicate, only when
> the assignment sits under a textually identical one, and only when that
> predicate variable is not rewritten in between. A compound or call-bearing
> predicate is refused outright -- `if Ready(X) then` twice is no guarantee the
> second call returns what the first did.
>
> **A vacuous-fixture trap was caught here and is worth remembering.** The first
> fixture read the variable as `Other(V)`. A bare identifier passed as an
> argument is recorded as a **CallDef, not a read**, so the fixture produced NO
> findings at all and every assertion -- including the SILENT one -- passed
> vacuously. Reads in flow fixtures must be ARITHMETIC (`Sum := Sum + V`).
>
> RED verified: with the suppression neutralised and rebuilt, `SamePredicate`
> fails and all five controls still pass.
>
> **Shapes B, C and D remain, and the recommendation for them is UNCHANGED:
> do not implement.** The reasoning below still holds -- 12 of the remaining
> findings are arrays/records no predicate check can reach, and shape B needs a
> flag-pairing proof where any gap suppresses TRUE positives.

### Original analysis (still current for shapes B/C/D)


**My session-22 claim that all 39 are one shape was WRONG.** Every site was read.
They are FOUR shapes, and the flag-correlated one the note leads with is the
*smallest*. Correcting that is the most valuable part of this investigation.

| shape | count | what it is |
|---|---|---|
| **A** identical condition text | **4** | `if Profiled then TMark := ...` / `if Profiled then Inc(..., TMark)`. Only `tmark`, at `Storage.SQLite.pas:8509, 8540, 8571, 8578`. |
| **B** witness flag | **21** | Assignment of V paired with `F := True`; read guarded by F. Four sub-forms: (i) `if F then <read>` (13); (ii) right conjunct of `F and ...` (2); (iii) right disjunct of `(not F) or ...` (2); (iv) dominating early exit `if not F then Exit; ... <read>` (4). |
| **C** aggregate granularity | **12** | Arrays/records only ever element- or field-written, or filled via a `var` param element (`ReadFile(..., Buf[0], ...)`). **No predicate correlation can ever touch these.** |
| **D** other | **2** | `Lint.ProjectRules.pas:1181` -- finding sits ON an inline `var Lst:` declaration, a distinct and probably real walker bug. `Doc.Drift.pas:983` -- conditions genuinely uncorrelated; a defensible hedged finding. |

### Why the lattice cannot do this

`TDefAsgnVal` is `record Must, May: TArray<Boolean>`
(`Analysis.Flow.Lattices.pas:194-196`) -- **no predicate at all** -- and the CFG
encodes branching only as edges. So any correlation must be a SYNTACTIC AST check
at emission time, not a lattice extension; the latter would be path-sensitivity.
Hook is `FlowChecks.pas:1001`, **in the info arm only, never the warning arm**.
`TTSNode.Parent` exists (`TreeSitter.pas:942`), so walking up to the routine node
is available. Cost is negligible -- it runs once per emitted candidate.

### THE RECOMMENDATION

**Do not implement.** Reasons, in order:

1. **0 findings on all four consumer projects.** This buys nothing for YADF /
   YADFOT / YADFSetup / DataCopy.
2. All 39 are `info` and correctly hedged (*"may be used"*).
3. **14 of 39 (shapes C and D) are unreachable by ANY correlation check**, so the
   ceiling is 25, not 39.
4. The highest-yield part (shape B, 21) needs four guard forms plus an airtight
   flag-pairing proof, **and any gap in that proof SUPPRESSES TRUE POSITIVES** --
   the worst failure direction for this rule.

Accepting them as hedged info findings is the owner-sanctioned outcome and is
the right call today.

### IF the owner still wants the self-index noise gone

Bounded version, in this order:

1. **Write the fresh INBOX note first**, recording the 4 / 21 / 12 / 2 split so
   no future session re-derives it. The existing note explicitly asks for this.
2. Implement **shape B forms (i) and (iv) only** (~17 findings, the two simplest).
   Skip shape A -- 4 findings does not pay for the between-mutation scanner.
3. Separately, cost S and probably a REAL bug: the `ProjectRules.pas:1181`
   finding positioned on an inline `var` declaration.

Design detail, if it is built: from the read, walk parents to the routine node
recording normalized then-arm conditions; for a bare Boolean flag F, require F
initialised only `False`, every `F := True` to sit in a block that also assigns
V, and F never passed as a bare `var`/`@` argument. Guard-set containment is
**one-directional** (assignment-guard must be a SUBSET of read-guard); bail on
`case`, on else-arms, and on a loop boundary enclosing one site but not the
other.

### Fixture -- the SURVIVING-FIRE cases are the test

`tests\autotest\run_flow_flag_correlated_guard.ps1`, modelled on
`run_object_leak_padded_free.ps1`:

* `FlagGuarded` (shape A verbatim) -> SILENT
* `WitnessFlag` (`HaveX := False; if C then begin X := ...; HaveX := True end; if HaveX then Use(X)`) -> SILENT
* **`TrueUnassigned`** (`Y := X + 1`, X never assigned) -> **must still fire as a WARNING**
* **`FlagReassigned`** (`if P then V := 1; P := Q; if P then Use(V)`) -> **must still fire** -- proves the between-mutation scan
* **`NotFlag`** (assign under `if P`, read under `if not P`) -> **must still fire**
* **`WitnessUnpaired`** (`if C1 then HaveX := True; if C2 then X := ...; if HaveX then Use(X)`) -> **must still fire** -- this is the exact hole a lazy implementation opens

A test asserting only "39 became fewer" is worthless.

---

## 5. Group B -- what is left, already planned

Done in session 22: scoped-resolve A/B equivalence harness (closed
`indexer-livelock`), index-path size guard, fingerprint-commit correctness fix.

### 5a. Walk progress `n/total` + ETA (~90 min)

`TIndexer.ReportProgress` (`src\core\DRagLint.Core.Indexer.pas:535-538`, sole
call site :1018) prints one line per file with no counter, so an hours-long
library reindex is indistinguishable from a hang.

Add `FProgressTotal` / `FProgressDone`; run `WalkAndIndex` (decl :223) once in a
count-only mode using the SAME filters and ignore-stack, then index.

**Emit to ErrOutput, not stdout.** Several suites regex the existing stdout
per-file lines (`run_index_fingerprint_commit.ps1` among them); changing them
breaks the battery for no reason.

**Positive control:** with 3 units plus 1 file excluded by filter, the total must
be **3, not 4**. A pre-count that ignores the walk's admission rules is the one
way this silently lies, and asserting only "a progress line appeared" would miss it.

### 5b. Per-file resume: `files.indexed_at_fingerprint` (~120 min) -- HIGHEST RISK

Additive `TryExec('ALTER TABLE files ADD COLUMN indexed_at_fingerprint TEXT')`
in `Migrate` (pattern at `DRagLint.Storage.SQLite.pas:2888`, no schema bump).

**Stamp it INSIDE the per-file transaction that `CommitFileTx` closes
(`Indexer.pas:1017`), never outside it** -- otherwise a kill leaves rows stamped
but unparsed, which is precisely the silent-staleness bug fixed in session 22.

Test `run_index_resume_per_file.ps1`: index a folder; index ONE file with
`--no-preprocess` (new fingerprint -- simulates the completed prefix of an
interrupted run); index the folder with `--no-preprocess`. Assert step 3 parses
**exactly one** file and reports `skipped 1 up-to-date`.
**Positive control:** step 3 must STILL announce `Indexer changed since this DB
was built` and must reparse the untouched file. If per-file stamping were off
entirely, step 3 parses 2 and the count assertion fails; if the stamp wrongly
matches old fingerprints, the reparse assertion fails.
**Unproven and must be said so:** the real shape -- a process killed hours into a
library walk -- is only simulated.

### 5c. CodeLens LRU cap (~60 min)

`src\delphi-plugin\DragLint.Plugin.CodeLensCache.pas` -- `FByFile` (:26), only
`Clear` (:363) and `InvalidateFile` (:274) shrink it, no bound. Pure
`TDictionary` + `TCriticalSection`, no IDE dependencies, so the unit and a
console test (precedent: `tests\StorageHelperEdgesTests.dpr`) can land now.

**Positive control:** assert an entry is RETRIEVABLE before eviction, and that
the NEWEST entry survives cap+1 inserts. A cache that stores nothing passes any
`count <= cap` check.
**Blocked half:** the BPL rebuild needs the Delphi IDE CLOSED; in-IDE behaviour
stays unverified until then.

### 5d. Profile doc-drift on YADF (~40 min, measurement only)

`lint-all-project-wide-phase-dominates-runtime` should MOVE TO GROUP A: its
dominant phase (doc-drift, 454.9s of 732s on ORM3) reproduces on YADF in
~40-second runs, so it was never environment-blocked. Run `DRAGLINT_PROFILE=1`,
attribute the cost, append the finding to the note. The fix is then a normal item.

### 5e. Genuinely blocked -- do not attempt

* **Win32 library rebuild abort** -- root cause unknown. The old
  "crashed mid-DIAG-line" clue was a 128-byte stdout buffering artifact, since
  fixed by a per-file flush, so the NEXT failure is diagnosable. Launch the
  rebuild unattended and harvest; hours-long by nature.
* **Narrowing the added-type resolve fallback** -- a soundness redesign. The
  fallback is provably required by the indirect channel
  (`Storage.SQLite.pas:3796-3804`). Must not precede the equivalence harness,
  which is its only credible guard.
* **The 25x reindex figure** -- O(child-table rows); no small fixture can exhibit
  it. Stays a projection until a real large-DB run.
