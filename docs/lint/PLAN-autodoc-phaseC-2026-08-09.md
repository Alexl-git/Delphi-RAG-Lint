# PLAN: autodoc PHASE C -- fixes for the YADF doc-quality review

- **Created:** 2026-08-09
- **Source review:** `docs/INBOX-autodoc-2026-08-07-yadf-doc-quality-review.md` (filed by YADF, 2026-08-07)
- **Status:** follow-up verification COMPLETE. **No code has been changed yet.** Nothing in
  `src\` was touched for this plan.
- **Related:** `docs/lint/PLAN-autodoc-and-backlog-2026-08-06.md` (Phase A/B),
  `docs/INBOX-autodoc-returns-section-incomplete.md`,
  `docs/INBOX-harvest-swallows-preceding-banner-comment.md`

---

## >>> RESUME POINT -- updated 2026-08-09 (SECOND execution session)

**B10, B3 and B8 are now DONE.** The user's instruction this session was explicit: *"Lets do YADF
and DataCopy test only after all planned autodoc are done. Otherwise there is no use to do these
tests. Lets finish B8, B10 and B3 first."* So the live runs below are still the next action, but
they now come AFTER this work, not instead of it.

Baseline before the work: full battery **232/234** at `88a5d9a`. Both failures
(`run_doc_p3_idempotency_sweep`, `run_doc_p3_preserve_tags`) were proven ENVIRONMENTAL -- each
passes in isolation (228 and 54 assertions, exit 0). Both hard-fail when the start-of-run
`Remove-Item` cannot delete a lingering `.sqlite-wal`; they have no retry. That fragility is worth
fixing but is not a product defect.

### B10 -- DONE (fixed)

`IsTestRoutine` (`src\doc\DRagLint.Doc.SymbolFacts.pas`) accepted any routine whose DECLARING FILE
matched `*Test`/`Test*`. YADF's `CodeChars` is a plain helper in `Test\GuardTest.dpr`, so it was
rendered as a coverer of three `YADF.LineScan` symbols. The file rule is now NECESSARY BUT NOT
SUFFICIENT: it must be corroborated by (a1) the routine's own name starting with `Test`, or (a2)
the routine being a method of a fixture-named class. Rule (b), `TTestCase` ancestry, is unchanged
and still fires independently.

**The resume note said this needed "a per-hop file id the coverage walk lacks". It did not** --
`Walk` already carries `RC.Location`. The fix is entirely inside `IsTestRoutine`.

(a1) covers every shape in the corpora in play: YADF's tests are free `Test*` procedures in a
`.dpr`, drag-lint's own `StorageHelperEdgesTests.dpr` is the same, and
`DRagLint.Refactor.TestStub` GENERATES `Test_<Method>_HappyPath`. Verified on the live YADF index
(render only): `Covered by` is now exactly the genuine `Test*` procedures, and `CodeChars` still
appears under `Called from`, which is true.

### B3 -- DONE (no code defect; the recorded diagnosis was WRONG)

The previous resume point said *"a masking gap on that body remains and now shows up as silence."*
**That is not why `FormatSource` is silent.** Its own body -- everything after its `begin` at
`YADF.Layout.pas:5441` -- runs ~22 lines of `Result:= SomeStage(Result)`. `Result` on the RHS is
exactly what `HasResultMutation` detects, and it is asked of the DOCUMENTED routine's own code, so
it fires no matter how perfectly nested scopes are masked. Under the miner's "absence over wrong"
policy that routine can never carry a `<returns>`. **Do not re-open this as a masking bug.**

The mask itself was PROVEN complete on the one shape no fixture covered: a nested routine that
MUTATES `Result` (`Result := Result + S[i]`, the real `CurrentLineLeadingWS` shape at
`YADF.Layout.pas:5089`). Every pre-existing nested fixture did a whole-`Result` ASSIGNMENT, which
never reaches `HasResultMutation` at all. That shape now lives in
`run_doc_returns_nested_scope.ps1` as `InnerAccum`. **It passed on first run** -- it is a
regression pin, not a TDD-driven fix, and it is recorded as such.

Why it mattered enough to test: a leak there is DESTRUCTIVE, not cosmetic. It would delete the
outer routine's `<returns>` outright, and the result is silence -- indistinguishable from "nothing
to say" without the control assertion.

### B8 -- DONE (implemented, this time it stuck)

New `WrapEngineProse` + `DOC_WRAP_COLS = 100` in `src\doc\DRagLint.Doc.Regions.pas`, applied on
THREE emit paths: `EmitTagged` (tag values), `AppendFact` (the facts block), and
`EmitHarvestedRemarks` (harvested prose -- the 759-column worst case).

**Why this attempt survived where the first was reverted: OWNERSHIP.** `EmitTagged` wraps only when
`AUTO_MARK` is in the OPEN TAG. That reuses the existing invariant by which the emitter already
tells its two arms apart -- the engine arm stamps the marker, the preserve arm carrying a human's
text does not. The reverted attempt reflowed hand-written values too, which changed the text the
merge re-parses. Facts-block lines need no such test: they live between `AUTO_BEGIN`/`AUTO_END` and
are regenerated wholesale.

Idempotency is structural: wrapping is PER LINE and lines already within budget pass through, so
`Wrap(Wrap(x)) = Wrap(x)`. The join-then-reflow alternative is not a fixed point once the value
round-trips through the parser, which is the instability that killed attempt one.

`run_doc_p3_decayrouting` DID go red, exactly as predicted -- but only its N7 DISCRIMINATION
guard, an assertion about the TEST'S OWN setup, with all 43 behavioural pins still green. The
engine block grew 7 -> 9 lines, so the fixture's quoted region no longer exercised the containment
loop. Re-derived from real output per the rule the fixture itself states. Now `existing=9
engineBlock=9`.

New runner: `tests\autodoc\run_doc_p3_wrap.ps1` -- width, word-preservation, AUTHOR-preservation
(the assertion that separates this implementation from the reverted one), and idempotency.

#### B8 SCOPE RULING by the user, 2026-08-09 -- fact lists are NOT wrapped

Wrapping was first applied to the facts block too, and the full battery answered with 5 failures:
`run_doc_cap`, `run_doc_p3_callerline`, `run_doc_returns_and_callers`, `run_calledfrom_resolved`,
`run_callsite_kind_universe`. **None was broken output** -- the content was complete, it had simply
moved onto a continuation line, and each of those runners reads one fact as one line.

Asked, and the user ruled: *"If it is easier, keep these as a single line with a future option to
break into individual lines."* So:

- **Wrapped:** `<summary>`, `<remarks>`, harvested prose -- i.e. PROSE, which is what produced the
  759- and 659-column lines.
- **NOT wrapped:** `Called from:` / `Calls:` / `Used in units:` / `Raises:` / `Overridden by:` /
  `Returns:`. These can still exceed 120 columns (262 measured on YADF.LineScan) and that is
  accepted for now.
- **The agreed future fix is ONE ENTRY PER LINE, not word-wrap** -- entries stay atomic, greppable,
  and a diff shows exactly the caller that changed. The six call sites already route through a
  single `AppendFact` procedure whose body is currently a passthrough, so that change is one place.

Do not "finish" this later by turning word-wrap back on for fact lines; that is the option that was
considered and declined.

### Not a defect -- checked and dismissed

`document --unit`/`--project` emit NOTHING for a routine with a harvestable `//` comment but no
facts, while `--qname` emits a full block. That is the DOCUMENTED facts-only gate for batch modes
("add `--stubs` to keep a fresh comment that has no facts block"), confirmed by giving the fixture
a `Calls:` fact and watching batch mode insert. It is also why YADF's earlier run documented only
28 of 52 declarations.

---

## NESTED-ROUTINE EXTRACTION -- design, investigated 2026-08-09 (NOT yet implemented)

The user's instruction: *"Implement: indexer should extract nested routines as symbols... After
that we'll see if unknown is still remaining... Lets wait with YADF and DataCopy until we resolve
as many indexer problems and unknowns as possible."*

### The parser already walks them; it deliberately does not EMIT them

`src\parser\DRagLint.Parser.Delphi13.pas`, the `defProc` arm (~line 1762). Nested routines are
walked at `RoutineDepth > 0` (~line 1853) purely to collect their REFERENCES -- that was a
deliberate earlier fix, and its comment says so: *"the nested routine still does not emit a SYMBOL
of its own (its decl is not a unit-level API...)"*. Symbol emission is gated by
`if AState.RoutineDepth = 0`. So the change is localised, not a new traversal.

### What to change

1. In the nested-walk loop, emit a symbol for the nested routine BEFORE recursing, parented to the
   ENCLOSING ROUTINE's symbol index (today the loop passes `AParentSymbolIdx` -- the enclosing
   class/unit -- straight through, which would give a wrong parent).
2. `QualifiedName` becomes `Unit.Outer.Nested`. This is the whole point: `YADF.Layout.pas` declares
   `StartsWordCI` THREE times (lines 1925, 2351, 2900), each local to a different routine, and
   only a qualified name tells them apart.
3. Pass the new symbol's index down so deeper nesting chains correctly.

### Why this is SAFE for `document` -- verified, do not re-derive

`DRagLint.Doc.Batch.pas:252` gates the public surface on `SameText(Sym.Section, 'interface')`.
Nested routines are implementation-section, so `--unit` / `--project` / `document-all` skip them
automatically. `document --qname` bypasses that loop, so a nested routine can still be documented
ON PURPOSE. Nothing else needs a guard.

### The real cost is symbol-count churn, not the emission

Emitting nested routines also emits their PARAMS (`EmitRoutineLocals` / the `declProc` path), and
many runners assert symbol counts. Budget the reconciliation, not the parser edit.

### Expected yield -- measured, so it can be checked afterwards

On YADF, 4,005 unresolved call refs name NO symbol anywhere. `StartsWordCI` (93 refs) and
`EndsWordCI` (62) are in that bucket and ARE nested routines, so they should move. Most of the rest
will NOT: the top names are `Exit` (532), `Inc` (491), `Free` (222), `Append` (200), `Add` (165),
`Continue` (145) -- compiler intrinsics and RTL/VCL methods.

### Two follow-ups this exposes, both bigger than they look

- **Intrinsics are counted as unresolved calls and should not be.** `Exit`/`Inc`/`Break`/
  `Continue`/`SetLength`/`High`/`Assigned` are `System.pas` intrinsics the compiler recognises by
  name and compiles inline; several have signatures no Pascal declaration can express. They will
  never be project symbols. A known-intrinsic classification would stop them polluting the
  denominator -- which is what made "35.1% coverage" read far worse than reality. Against a
  denominator of calls to project-declared routines, coverage is already **69.7%**.
- **RTL/VCL calls cannot resolve from a project DB AT ALL.** `Free`/`Add`/`Format` live in the
  SEPARATE library index (`library-Win32.sqlite` / `library-Win64.sqlite`), and
  `call_edges.target_symbol_id` is a rowid in ONE database. Cross-DB edges are not representable
  today. This is architectural and needs a design decision, not a parser fix.

### Also measured: option 4 (bare cross-unit calls), for when it is picked up

167 resolvable / 23 ambiguous / 18 name-coincidences. Coverage 35.1% -> 37.1% raw, 69.7% -> 73.8%
on project calls; 38 target and 82 caller doc blocks improve. **The recorded "208" was computed
WITHOUT a visibility check** -- resolving all 208 would create 41 WRONG edges.
**TRAP, verified:** join on `unit_uses.unit_name` (146/379 rows resolve), NOT `unit_name_norm`,
which is only the last dotted segment lowercased (`DelphiAST.Classes` -> `classes`, 46/379).

---

### Still open after this session

- **Break fact lists into logical lines -- ONE ENTRY PER LINE.** The user's words when ruling on
  B8: *"Add this as a future todo item to break facts into logical lines, but it might come much
  later to implement."* LOW PRIORITY, explicitly not now. The seam is ready: all six fact call
  sites already go through `AppendFact` in `src\doc\DRagLint.Doc.Regions.pas`, whose body is a
  one-line passthrough. Whoever picks it up must also update the five runners that read one fact
  as one line -- `run_doc_cap`, `run_doc_p3_callerline`, `run_doc_returns_and_callers`,
  `run_calledfrom_resolved`, `run_callsite_kind_universe` -- which is exactly the set that went red
  when word-wrap was tried there.
- **Indexer does not extract NESTED routines as symbols.** `query --name EmitTagged` returns 0
  exact matches for a real function at `src\doc\DRagLint.Doc.Regions.pas:1882`. Logged in
  `stats\draglint-gaps.log` as class `unsupported`. The user asked for this as its own todo.
- The ` ?` uncertainty marker on all-uncertain lists -- STILL UNANSWERED, one line in `JoinRefs`.
- Call-edge coverage 35.1% on YADF (bare calls to free functions in other units never resolve).
- B9, and YADF suggestions 2-10 (`<exception cref="">` first).

---

## >>> EARLIER RESUME POINT -- 2026-08-09 (first execution session)

`main` = **`b28518d`, pushed, in sync**. Autodoc suite **69/69**; last FULL battery **233/233**
at `0c47bc2` (B5 landed after it -- **re-run the full battery once** before the runs below).

### THE NEXT ACTION IS THE USER'S ASK, not more fixes

They instructed, verbatim: *"You can run YADF and DataCopy on live projects, just branch out. If
results will be good, we do need these autodoc comments and reindex there. These documentations
are very useful."* So:

1. **YADF** (`C:\Projects\YADF`, git): `git checkout -b autodoc-phaseC` -> `drag-lint index` ->
   `document --project YADF.dproj --apply` -> `index` again -> `lint-all` -> **read the findings
   and judge false positives / gaps.** Keep the commits on the branch.
2. **DataCopy** (`C:\Projects\DataCopy`, **Mercurial**, `DataCopy.dproj`, 16 units): same
   sequence; branch with `hg branch` / bookmark first. NOTE the standing caution in
   PLAN-autodoc-and-backlog-2026-08-06 C1 -- DataCopy shipped to a tester on 2026-08-07; the
   user has since explicitly asked for this run, which supersedes it, but branch anyway.
3. Report back: false positives, missing findings, and whether the docs are worth keeping.

Everything already measured on COPIES is in
`C:\Projects\YADF\INBOX-drag-lint-phaseC-response-2026-08-09.md` (filed, untracked).

### Shipped this session

B6 (files.path case + repair migration), B1 (arity-aware overloads), B2 (arity tags on rendered
edges), B11 (no fabricated caller), B3 **partial** (nested-mask pending stack), B4 (labelled
complexity scopes), B7 (empty PROSE omitted; `<param>` structural; severities), B5 (honour
`.gitignore` by DEFAULT).

### OUTSTANDING -- B8 and B10

**B8 was implemented and then DELIBERATELY REVERTED. The tree is clean; nothing is half-applied.**
Wrapping `EmitHarvestedRemarks` works in isolation and fixes the 759-character worst case. The
long `<summary>`/`<returns>` lines come from `EmitTagged`, and wrapping THAT is entangled: it
emits its first line UNTRIMMED, `tests/autodoc/run_doc_p3_decayrouting.ps1`'s fixture QUOTES its
exact output back to the engine to test containment routing, and its empty-value path feeds
`<remarks>`. The measured effect was doc blocks DISAPPEARING from that fixture -- a routing
change, not a cosmetic one. Retrying B8 means re-deriving those fixtures in the same pass; budget
it as its own task, not a tail-end cleanup.

**B10 not started.** `ComputeCoveredBy` needs a per-hop file id its `Walk` does not carry.

### Rulings given 2026-08-09 -- implemented, do not re-litigate

- "Empty sections are omitted" applies to PROSE elements (`<summary>`, `<returns>`) only.
- "Autodocument has to produce the param section ... Warnings and errors is what Linter
  produces": `<param>` is STRUCTURAL (D-3 stands); undocumented param ->
  `doc-param-no-description` at **warning**; a `<param>` for a parameter that does not exist ->
  `doc-param-not-in-signature` at **error** (new rule).

### One question asked and not yet answered

The ` ?` uncertainty marker renders only on MIXED lists, so an all-guessed caller list is
indistinguishable from an all-resolved one. One line in `JoinRefs`
(`src\doc\DRagLint.Doc.Regions.pas`). Needs a ruling.

---

## Earlier resume point (execution pass, kept for the corrections it records)

**B6, B1, B2, B3(partial), B4, B11 are DONE.** Three commits:
`e261cba` (B6), `0a8fcd6` (B1+B2+B11), `0a67b5f` (B3+B4). Response to YADF filed at
`C:\Projects\YADF\INBOX-drag-lint-phaseC-response-2026-08-09.md`.

**REMAINING: B5, B7, B8, B10**, plus two NEW items this pass discovered (below).
Each is scoped in the response doc's "Not done, and why" section; none is blocked.

### Two corrections to THIS plan, established by execution

1. **B2's premise is FALSE.** The docs have never bypassed `call_edges`.
   `Called from` = `FindResolvedCallers` + a name bucket for refs with no edge;
   `Calls` = `GetCallEdgesFromSymbol` + a body-scan fallback. The reviewer's
   "9 rendered vs 2 resolved" is the union of the two buckets. So this plan's
   "B1 and B2 are ONE defect, landing either alone makes the docs worse" was
   wrong -- B1 landed alone and made them strictly better. What B2 needed was
   RENDERING: an overload set shares one qualified name, so a correct edge still
   read as self-recursion. Rendered edges now carry `/N` when the name is shared.
2. **B3's root cause was NOT "the indexer emits no symbols for nested routines".**
   `MaskNestedRoutines` already existed and already masked all three mined views.
   The real bug was that its pending-header state was a SINGLE SLOT, so a routine
   declared inside another nested routine's declaration part overwrote it. That is
   fixed. The plan's "must be derived at parse time" estimate was too pessimistic
   -- no parser work was needed.

### New, found while executing -- neither is in the original review

- **Call-edge coverage is 35.1%** on YADF (2,828 of 8,062 call refs). 208 of the
  unresolved name a unit-level routine that IS in the index: a bare call to a free
  function in ANOTHER unit is never resolved, because `TypeReceiver` types a
  receiver and a bare call has none. This bounds what any `call_edges`-based fact
  can say and is the highest-value next fix in this area.
- **An unmarked doc element is frozen.** YADF's bad `<returns>` carries no
  `<!-- drag-lint:auto -->`, so the merge treats it as hand-written and preserves
  it forever. Regenerating cannot clear it -- it needs `--strip`. Any "re-run and
  the docs improve" claim is false for elements emitted before the marker existed.

### Open DECISION for the user (not a bug)

The ` ?` uncertainty marker is emitted ONLY on MIXED lists, so an all-guessed
caller list renders exactly like an all-resolved one. That was a deliberate,
re-measured T4 decision and it was NOT changed. It is, however, why the YADF
reviewer read the caller lists as confident. Changing it is one line in `JoinRefs`
(`DRagLint.Doc.Regions.pas`). Needs a ruling.

---

## Verification status (re-checked 2026-08-09)

The review's evidence base was YADF `ee08894` / index built 2026-08-03. YADF has since moved
one commit to **`14ab163`** ("release: 1.0.14.0 -- uses-clause + Unsafe-casing fixes, docs
extended to the whole codebase") and the index was rebuilt **2026-08-07 17:22**.

**All 11 findings still reproduce at `14ab163`.** Only counts drifted, because `14ab163`
extended autodoc to more files.

| Id | Finding | Reported | Verified at 14ab163 |
|---|---|---|---|
| B1 | Call edges arity-blind | self-recursion | CONFIRMED: `7133->7133`, `19720->19720`; the real 603-line impls (`7136`, `19723`) record 0 callers |
| B2 | Docs bypass `call_edges` | 9 rendered vs 2 resolved | CONFIRMED: 9 distinct (name, basename) vs **0-1** resolved |
| B3 | `<returns>` aggregates nested | 15 nested routines | CONFIRMED: 15 nested decls in source 4984-5587 |
| B4 | Complexity scope mismatch | 24 vs 603 | CONFIRMED: `cyclomatic=24`, `body_loc=603` in `symbol_facts` |
| B5 | `.private` indexed | 5 files | CONFIRMED: 5 rows; **4 of the 9 rendered callers are archive rows** |
| B6 | Duplicate `files` row | 929/5,870 (15.8%) | CONFIRMED: **929/5,920 (15.7%)**, and it SURVIVED the 08-07 rebuild |
| B7 | Empty doc elements | 39 / 40 / 2 | CONFIRMED exactly |
| B8 | Unterminated singleton | 3 | CONFIRMED: 3, plus 68 `///` lines over 120 chars |
| B9 | Impl banner on interface decl | 1 case | Not re-probed (source-level, unchanged region) |
| B10 | `Covered by` counts non-tests | `CodeChars` | Not re-probed (source-level, unchanged) |
| B11 | Fabricated "X caller" | 15 | CONFIRMED, now **16** (grew with 14ab163) |

Marker balance re-checked: **89 BEGIN / 89 END**. The marker text is
`<!-- drag-lint:auto BEGIN -->` (a SPACE, not a colon) -- a grep for `drag-lint:auto:BEGIN`
returns 0 and will fool you.

## Two corrections to the review

1. **B3's root cause is deeper than the review states.** It asks for "a scope boundary at
   nested routine declarations." But the indexer emits **zero symbols** for those 15 nested
   routines -- they exist in source and not in `symbols`. There is no boundary to look up; it
   must be derived during parsing. This is a bigger fix than the review implies.
2. **B4's fields live in `symbol_facts`, not `symbols`.** Columns: `cyclomatic`, `body_loc`,
   plus `returns_owner` (which suggestion 6 correctly notes is populated but never rendered).

## Why B6 first

`YADF.Layout.pas` is indexed twice (`files.id` 7 = `C:\...`, 161 = `c:\...`). A query for
`FormatSource` therefore returns **five** symbol rows where the source has three overloads.
Any arity-resolution work validated against this DB is being tested on doubled candidates.
Fix B6, rebuild, reindex, THEN verify B1. Note also that SQLite `LIKE` is case-insensitive
while the `files.path` UNIQUE is case-sensitive -- that asymmetry is the whole bug.

## Fix sites (located, not modified)

| Id | Unit | Note |
|---|---|---|
| B6 | `src\storage\DRagLint.Storage.SQLite.pas` | **`NormalizeStoredPath` already exists** and normalizes `/`->`\` but NOT drive-letter case. `files.path` carries a case-sensitive `UNIQUE`. Upsert pair is `FQUpsertFile` / `FQInsertFile` (~line 906). Needs: upper-case the drive letter in the canonical form, + a one-off dedupe migration (double-indexed corpora already exist in the wild). |
| B1 | `src\index\DRagLint.Index.CallResolver.pas` (22 KB) | Resolve overloads by argument count before writing `call_edges.target_symbol_id`. Arity alone fixes every case in this corpus. |
| B2 | `src\doc\DRagLint.Doc.Facts.pas` (90 KB), `src\doc\DRagLint.Doc.SymbolFacts.pas` (147 KB) | `Called from` / `Calls` are derived from `refs.name_text` grouped by `enclosing_symbol_id`, deduped by (routine, basename). Switch to `call_edges` -- but ONLY together with B1. |
| B3 | `src\doc\DRagLint.Doc.SymbolFacts.pas` | `Result` collector; needs a parse-time nested-routine boundary (see correction 1). |
| B5 | `src\index\DRagLint.Index.IgnoreFiles.pas` | A full `.gitignore`/`.hgignore` engine **already exists**. Ask (a) may reduce to wiring `.private` in rather than building anything. Ask (b) -- repo-relative paths on basename collision -- is separate, in the doc renderer. |
| B10 | `src\index\DRagLint.Index.Coverage.pas` | `covered_by`; restrict to routines the test runner actually invokes. |

## Reproduction (all re-verified working)

```powershell
# B6 -- duplicate file rows and their symbol share
python -c "import sqlite3,collections; con=sqlite3.connect(r'file:C:\Projects\YADF\YADF.sqlite?mode=ro',uri=True); rows=con.execute('SELECT id,path FROM files').fetchall(); d=collections.defaultdict(list); [d[p.lower()].append((i,p)) for i,p in rows]; print([v for v in d.values() if len(v)>1])"

# B7 / B11 -- note the <param> regex must NOT require name="..."
Set-Location C:\Projects\YADF
(Select-String -Path *.pas -Pattern '///\s*<summary></summary>').Count   # 39
(Select-String -Path *.pas -Pattern '<param[^>]*></param>').Count        # 40
(Select-String -Path *.pas -Pattern '\w+ caller \(').Count               # 16
(Select-String -Path *.pas -Pattern 'drag-lint:auto BEGIN').Count        # 89
```

## Gotchas for a cold start

- Battery needs `pwsh`, ~12 min. Never rebuild the exe mid-battery; never edit `src\*.pas`
  mid-battery (several suites compile from source). `DRagLint.CLI.pas` is the one exception.
- The battery log is BUFFERED under `*>` and lags minutes, looking stalled. Read
  `C:\TEMP\draglint_battery_<stamp>\` live, or wait for `results.csv`.
- Build loop: 3-line wrapper `.bat` (rsvars -> cd -> msbuild), run via PowerShell
  `Start-Process -Wait`, check `BUILD_EXITCODE=0`, then copy
  `src\cli\Win64\Debug\drag-lint.exe` over `third_party\dll-win64\drag-lint.exe`.
- Never grep a Delphi msbuild log loosely -- filter to `\[dcc\] (Error|Fatal)|BUILD_EXITCODE`.
- `FEATURES.txt` is another workstream's -- do NOT commit it.
- Deliverable when done: re-run autodoc on YADF and file a report back into `C:\Projects\YADF`
  so it can re-review. YADF is a good corpus for this: the autodoc pass is committed
  (`95170f9`, `ee08894`, `14ab163`) and the tree is under git, so regenerate-and-diff shows
  exactly what changed.
