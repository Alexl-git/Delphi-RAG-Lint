# PLAN: autodoc PHASE C -- fixes for the YADF doc-quality review

- **Created:** 2026-08-09
- **Source review:** `docs/INBOX-autodoc-2026-08-07-yadf-doc-quality-review.md` (filed by YADF, 2026-08-07)
- **Status:** follow-up verification COMPLETE. **No code has been changed yet.** Nothing in
  `src\` was touched for this plan.
- **Related:** `docs/lint/PLAN-autodoc-and-backlog-2026-08-06.md` (Phase A/B),
  `docs/INBOX-autodoc-returns-section-incomplete.md`,
  `docs/INBOX-harvest-swallows-preceding-banner-comment.md`

---

## >>> RESUME POINT -- updated 2026-08-09 (end of the execution session)

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
