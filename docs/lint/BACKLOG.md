# drag-lint Linter -- Backlog & Resume Point

> ## RESUME 2026-08-02 (LATEST-78) -- **`main` IS MERGED IN. 2.9 + 2.10 FIXED. A merge-induced regression was found and fixed. ONE USER RULING IS BLOCKING. Read this before LATEST-77.**
>
> ### Git
>
> `feat/autodoc-phase3` = **`4438c06`** (+ uncommitted docs), was 110 behind `main` and is now
> current. `main` = `3b4a877`, unchanged -- **nothing was merged INTO main.** NOTHING PUSHED.
> Shared exe `third_party\dll-win64\drag-lint.exe` rebuilt + staged **17:06**, verified in the
> STAGED binary. Completion report for the converter team:
> `docs/INBOX-REPLY-2026-08-02-engine-completion-report.md`.
>
> ### >>> NEXT ACTION: get the ruling in `docs/lint/TRIAGE-the-22-harvest-repair.md`
>
> The 22 red autodoc checks were triaged as LATEST-75 asked. **The obvious fix is worse than
> leaving them red, and the triage now proves why with numbers.** `EmptyRemarksOnly` goes
> `7502 -> 9481 -> 9456 -> 9456` bytes: **cycle 2 SHRINKS the file**, because the repair branch
> deletes the author's empty `<remarks>`. Widening the repair-vs-fresh term (the reverted
> one-liner at `Doc.Document.pas:764-770`) does NOT prevent that deletion -- it moves it to cycle 1.
> The suites would go green and the author's tag would still be gone, sooner, on the user's first
> run. **Recommendation: make the REPAIR branch non-destructive instead** -- the engine already
> has a guard that preserves an unmodeled `<value>` tag on the fresh path (`run_doc_p3_unhandledtags`
> check 3 passes); repair does not use it. Two questions for the user are at the end of the triage.
> **No engine change was made.** T8 remains unstarted.
>
> ### Fixed this session
>
> * **2.9 `--refs-as-leaves` phantom leaves (converter HIGH) -- FIXED BY THE MERGE ITSELF.**
>   `TFDUpdateSQL` published surface: **364 leaves / 354 phantom on `main` -> 10 / 0 now**
>   (5630 -> 500 without `--min-visibility`). `IsComponentType` asks the ancestor climb whether the
>   type descends from `TComponent`; for `TFDAdaptedDataSet` that climb could not reach it on `main`,
>   so the flag descended. The branch's late-ancestor resolution supplies the missing half -- so the
>   fix needed BOTH sides and neither branch alone could show it.
> * **2.10 case sensitivity -- FIXED, and the DESIGN IN LATEST-76 WAS WRONG.** Plain `COLLATE NOCASE`
>   on the lookups is correct and catastrophically slow: SQLite cannot serve NOCASE from a BINARY
>   index and **no existing consumer DB has a NOCASE one** (Migrate creates it; read verbs never call
>   Migrate). Measured: proptree climb 2s -> **300s+**. Now **EXACT first, NOCASE only as a retry on
>   zero rows**. Climb 55.2s un-migrated / **1.2s migrated**; wrong-case query 2.37s -> 0.23s.
>   Consumers need ONE writable `drag-lint index` per DB (35.6s, +80MB on 1.87GB); the engine prints
>   a one-time **stderr** note if they have not. Exact-case callers get byte-identical row sets.
> * **THE THIRD LOOKUP PATH IS FOUND** -- there isn't one. `ANotifyEvent` matching `TNotifyEvent` is
>   `FindSymbolsFuzzy` (trigram + Levenshtein, distance 3 allowed at 13 chars), which fires on ANY
>   zero-row exact lookup. The `(no exact match...)` banner prints **only without `--json`**, so JSON
>   consumers got guesses shaped like hits. Every `query` JSON row now carries
>   **`"match_kind": "exact"|"fuzzy"`**.
> * **REGRESSION THIS MERGE CAUSED, found and fixed.** `run_proptree_ancestor_climb` and
>   `run_proptree_prop_type_scope` pass on `main` and went RED on the merge: PropTree guarded its own
>   walk with a local `CrossesGuiFramework`, but the branch's late-ancestor resolution answers names
>   that walk never asks about, so criterion 5 was enforced on one path and not the other -- a Vcl
>   class inherited an FMX-only ancestor. `CrossesGuiFramework` **promoted to `Core.Model`**; both
>   sites read the one declaration.
> * **Four type-declaration shapes were never indexed** (NEW, nobody filed it): a plain alias to a
>   KEYWORD target (`= string`), a subrange, an array type, a set type. `query --name TRange` denied
>   a type in the file it had just indexed. The tell: `= type string` indexed while `= string` did
>   not -- 2.11 closed the strong form only. **This corrects LATEST-77**, which said "plain aliases,
>   subranges and enums were all fine": enums are, subranges are not.
> * Encoding guard: `*.rules` (arrived with main's converter work) was declared `eol=crlf` but never
>   scanned, so the guard's accounting assertion went red the moment the branches met -- which is what
>   it is for. Plus 3 files left lone-LF on disk, one by this session's own `sed -i`.
>
> ### Traps confirmed the hard way
>
> 1. **Git Bash `grep -c $'\r$'` LIES about line endings** -- it reported CRLF on files that were
>    pure LF. Use a byte-level check; the encoding guard caught what my grep missed.
> 2. **Do not rebuild the exe while a battery runs.** 51 of 79 `autotest` runners resolve
>    `src\cli\Win64\Debug\drag-lint.exe`; rebuilding mid-run contaminated a whole battery (4 phantom
>    timeouts). The first battery of the session was also worthless for a different reason: the
>    autodoc suites default to the STAGED exe, which was built from `main` and has no Phase 3.
> 3. **PowerShell `-ne` / `-eq` are CASE-INSENSITIVE.** A check in the case-sensitivity suite
>    asserted the exact opposite of its name until it used `-cne`.
>
> ## RESUME 2026-08-02 (LATEST-77) -- **THE SHARED EXE NOW CARRIES ALL FOUR CONVERTER FIXES. 2.11 found + fixed. Read this before LATEST-76.**
>
> ### The exe other teams rely on is CURRENT
>
> `third_party\dll-win64\drag-lint.exe` rebuilt **2026-08-02 15:16** from `main` + **2.1, 2.2,
> 2.3, 2.11**. `main` = `3b4a877`. Verified IN THE STAGED BINARY, not just the build output:
> `--refs-as-leaves` accepted, `--force-reparse` works, `context` emits `impl-method`,
> `TNotifyEvent` and `TFileName` both index. The exe is gitignored, so git will never tell you
> this -- check its timestamp.
>
> **Strategy used, and why:** the four engine fixes are branch-INDEPENDENT, so they were
> cherry-picked onto `main` and the exe built there. Phase 3 was NOT merged into main (still
> ~7/17 tasks, 22 red suites). That gives other teams every fix without shipping half a feature.
>
> ### 2.11 -- strong type aliases, FIXED (`ec579a0`, on main as `3b4a877`)
>
> `TFileName = type string;` produced NO declaration row. The strong form carries **TWO `type:`
> fields** and `ChildByField` returns the FIRST -- which is the `kType` KEYWORD, not a typeref --
> so `TryWalkAlias` exited. That is exactly why plain aliases, subranges and enums were all fine
> and only this shape was blind. `type string`'s target is `(declString (kString))`, not a typeref
> at all. New `TryWalkStrongAlias` takes the LAST `type:` wrapper, **gated on the `type` keyword so
> it can only ADD rows, never alter one**. Verified: `System.SysUtils.TFileName` -> `kind=type`,
> target `string`. (`TDate`/`TTime` live in `System.pas`, not SysUtils -- their absence there is
> expected, not a miss.) Unblocks the converter's TableName Auto-Match.
>
> ### >>> NEXT ACTIONS
>
> 1. **Merge `main` INTO `feat/autodoc-phase3`.** Now doubly worth it: it also brings back the four
>    fixes so the branch and the shipped exe stop diverging. Expect a proptree conflict from
>    `feat/proptree-ancestor-scope`.
> 2. **Case-insensitive lookups by default** -- see LATEST-76 for the agreed design. **Find the
>    THIRD substring lookup path first** (it matched `ANotifyEvent` for `TNotifyEvent`); the two
>    known paths do not explain it, and `--name` is on every consumer's hot path.
> 3. **2.9** `--refs-as-leaves` phantom leaves (HIGH) -- reproducible once main is merged in.
> 4. Then the deferred: INVESTIGATE-ONLY the 22 T7 failures, then T8.
>
> ### The INBOX file keeps GROWING while it is being worked
>
> `docs/INBOX-converter-editor-phase-g-engine-findings.md` grew TWICE today -- 2.9/2.10 at 13:53,
> then 2.11 at 15:05 -- and its title still says "8 findings" when there are 11. **Always re-check
> its mtime before trusting an earlier reading.** The reply now carries an UPDATE section covering
> 2.1/2.9/2.10/2.11 and asks them to ping on append.



> ## RESUME 2026-08-02 (LATEST-76) -- **SUPERSEDES LATEST-75's next-action.** Converter 2.1 FIXED + verified on real RTL/VCL. The INBOX file GREW two new findings (2.9 HIGH, 2.10) after it was first read. Three decisions taken with the user: do NOT merge the branch into main, DO merge main into the branch, and make the indexer CASE-INSENSITIVE by default.
>
> ### >>> NEXT ACTIONS, in order
>
> 1. **Cherry-pick `41973bd` (2.1) onto `main`, rebuild, restage the shared exe.** Same pattern as
>    `0c24f1a` -> `13e7fb0`. The conversion team cannot use 2.1 until this happens.
> 2. **Merge `main` INTO `feat/autodoc-phase3`** (NOT the other way -- see the ruling below).
> 3. **Case-insensitive lookups by default** (design below).
> 4. **2.9** `--refs-as-leaves` phantom leaves (HIGH). Only reproducible from `main` until step 2.
> 5. Then the deferred LATEST-75 work: INVESTIGATE-ONLY the 22 T7 failures, then plan T8.
>
> ### Fixed since LATEST-75
>
> **`41973bd` -- converter INBOX 2.1: method-pointer / procedural types were never indexed.**
> `TNotifyEvent = procedure(Sender: TObject) of object;` produced ZERO rows. Confirmed with
> tree-sitter's own CLI that the grammar parses it perfectly --
> `(declType name: (identifier) (kEq) type: (type (declProcRef ...)))` -- so it is an EMITTER gap:
> `WalkDeclType`'s dispatch had handlers only for interface / helper / class-or-record / enum /
> alias, nothing claimed `declProcRef`, and `TryWalkAlias` accepts only a direct `typeref`. New
> `TryWalkProcType`, ordered **before** `TryWalkAlias` (a declProcRef's ARGUMENTS contain typerefs
> the alias handler would otherwise grab as the target). Emitted as `skTypeAlias` (kind `type`)
> with the whole signature as target text, interior whitespace collapsed.
> **Verified on real sources, not fixtures:** `System.Classes.pas` -> TNotifyEvent / TThreadMethod /
> TGetStrProc; `Vcl.Controls.pas` -> TMouseEvent (declared across TWO lines, returns one collapsed
> signature) / TKeyPressEvent. Autodoc battery unchanged, 56 suites / 1702 pass / the same 22 fail.
>
> ### The INBOX file GREW while it was being worked
>
> `docs/INBOX-converter-editor-phase-g-engine-findings.md` was modified at 13:53 -- AFTER it was
> first read -- gaining **2.9** and **2.10**. Its own title still says "8 findings"; there are 10.
> **Re-check that file's mtime before trusting a previous reading of it.**
>
> * **2.9 `--refs-as-leaves` does not prune component-reference roots -- HIGH, NOT STARTED.**
>   `proptree --min-visibility published --refs-as-leaves` on
>   `FireDAC.Comp.Client.TFDUpdateSQL` returns 364 leaves of which **354 are phantom**; 7 reference
>   roots are not pruned. Inflates the editor's Auto-Match target surface ~36x. Code is
>   `src/report/DRagLint.Convert.PropTree.pas`, which **exists only on `main`** -- it cannot be
>   reproduced from this branch until main is merged in (next action 2).
> * **2.10 `query --name` is case-sensitive, silently -- ROOT-CAUSED, NOT FIXED.** The two lookup
>   paths disagree: `FindSymbolsByExactName` uses `WHERE name = :name` (SQLite `=` is
>   case-SENSITIVE) while `FindSymbolsByPrefix` uses `LIKE 'x%'` (case-INSENSITIVE for ASCII). That
>   is why the reporter saw the matching SEMANTICS shift with case (`TEdit` 2 rows, `tEdit` 2
>   DIFFERENT rows, `tedit` 10 rows). **LOOSE END: neither path explains `ANotifyEvent` matching
>   `TNotifyEvent`, which is a SUBSTRING -- a third lookup path exists and has NOT been located.
>   Find it before changing `--name`; it is on every consumer's hot path.**
>
> ### USER RULING -- case-insensitive by DEFAULT
>
> **Delphi identifiers are case-insensitive, so a case-sensitive index is WRONG FOR THE LANGUAGE,**
> not merely inconvenient. This reframes 2.10 from MEDIUM to a correctness bug and subsumes part of
> 2.4. Agreed design, NOT yet implemented:
>
> * `WHERE name = :name COLLATE NOCASE` on the exact-name and qualified-name lookups.
> * **`CREATE INDEX IF NOT EXISTS idx_symbols_name_nocase ON symbols(name COLLATE NOCASE)` is
>   REQUIRED, not optional** -- the existing `name` index is BINARY and a NOCASE comparison cannot
>   use it, so without this every lookup becomes a full scan of ~1.5M rows.
> * Opt back in with a new `--case-sensitive` flag.
> * `NOCASE` folds only ASCII A-Z, which is exactly right: this codebase is strict 7-bit ASCII.
>
> ### USER RULING -- branch merge direction
>
> Almost everything is already merged: of 20 branches only **`feat/autodoc-phase3` (117 ahead /
> 108 behind)** and **`merge/converter-into-main` (2 ahead, the converter team's own)** carry
> unmerged work.
>
> **DO NOT merge `feat/autodoc-phase3` into `main`.** Phase 3 is ~7 of 17 tasks done (T8/T9 and
> T10-T14 not started) and carries 22 known-red suites whose fix is blocked on a deferred product
> decision. That would put a half-built feature plus 22 failing tests on the branch everyone builds
> from.
>
> **DO merge `main` INTO the branch.** It is 108 behind and the gap is still growing (82 yesterday).
> That gap is exactly what caused today's near-miss -- the branch lacks `--refs-as-leaves`, so any
> exe built from it is FATAL to the converter editor. Merging main in kills that hazard for good,
> and makes 2.9 reproducible here. **Expect a conflict:** `feat/proptree-ancestor-scope` fixed the
> same proptree defect we did and is already in main, so it will surface during this merge.
>
> ### Git
>
> `feat/autodoc-phase3` = `41973bd`, 117 ahead / 108 behind `main`. `main` = `13e7fb0`, 126 ahead of
> `origin/main`. **NOTHING PUSHED -- user holds push.** Tree clean; the two INBOX markdown files are
> untracked by convention. The staged `third_party\dll-win64\drag-lint.exe` is main+2.2+2.3 and does
> **NOT** yet carry 2.1.

> ## RESUME 2026-08-02 (LATEST-75) -- **T7's red suites CLOSED, but the real story is that T7 was 9 suites red, not 2. One genuine engine defect found + fixed. Converter INBOX 2.2 + 2.3 fixed, cherry-picked to `main`, and the SHARED exe is refreshed. Tree CLEAN, nothing pushed.**
>
> ### >>> NEXT ACTION
>
> **Investigate the 22 remaining Phase 3 failures (5 suites) -- INVESTIGATE ONLY, the user has
> explicitly NOT approved an engine change.** They all share one mechanism, described under
> "The 22" below. Then plan **T8** (harvester implementation-side fallback + precedence).
>
> ### What this session found that the ledger did not know
>
> **T7 shipped with NINE red suites, not the two its own commit recorded.** Baselining the T6
> commit (`03dafb7`) with a purpose-built worktree + Delphi build proved `decayrouting`,
> `guards`, `idempotency_sweep`, `indent`, `residual_lines`, `tagoccurrence` and `unhandledtags`
> were ALL green at T6 and red at T7. They were never run. Do not trust "N suites red" in a
> commit message again without running the family.
>
> ### Fixed this session
>
> | commit | what |
> |---|---|
> | `6425a58` | **T7 unbounded growth.** `EmitHarvestedRemarks` marks only the FIRST line of harvested prose, but MergeComment's preserved-prose filter tested the marker PER LINE -- so paragraphs 2..N looked hand-written, were preserved AND regenerated, and the block grew by its own length every cycle. Measured **+1501 bytes/cycle, constant, never converging** on `tagoccurrence`. `TDocStripper` rule 1b already had the right model (delete from the marked line through the run); MergeComment now matches it. Emitted output is unchanged. |
> | `0c24f1a` | **Converter INBOX 2.2 + 2.3** (see below). |
> | `c0cc93a` | **Restored the 351 deleted fixture case-note lines**, harvest-proof. |
>
> Phase 3 family went **41 -> 22 failures, 7 -> 5 red suites**; `indent` and `residual_lines`
> fully green. Whole autodoc battery: **56 suites, 1702 pass, 22 fail.**
>
> ### The 22 -- ONE mechanism, and it needs a PRODUCT DECISION, not a bug fix
>
> Harvest writes a `<summary>` on cycle 1. Cycle 2 therefore sees a summary in the region, which
> flips the symbol from the fresh-insert branch to the **repair** branch -- and the repair path
> "re-emits only what it models", so it DELETES hand-written tags it does not model. Watched it
> delete the author's own `<remarks></remarks>` at `fixtures/docp3/decayrouting.pas:31`. Output
> does stabilise, but one cycle late, so idempotency fails.
>
> The obvious fix is to widen the repair-vs-fresh term so harvested content routes to repair on
> cycle 1. **DO NOT just do it:** `src/doc/DRagLint.Doc.Document.pas:764-770` records that this
> exact widening was already considered and **deliberately REVERTED**, because it destroys
> hand-written tags in real user source. The user was asked and chose *"investigate, don't change
> yet"* -- so produce a per-case triage (genuine defect vs known-gap fixture that should be
> re-pinned) with a recommendation, and get a ruling before touching the engine.
>
> ### Converter-editor INBOX -- 2.2 and 2.3 FIXED, reply written
>
> Incoming: `docs/INBOX-converter-editor-phase-g-engine-findings.md` (8 findings).
> Reply: `docs/INBOX-REPLY-converter-editor-phase-g-engine-findings.md` (untracked, per convention).
>
> * **2.2 `context --task` omitted the target's own body.** Their "renderer bug, not extractor gap"
>   read was exactly right. `GetSymbolSlice` assumed its argument resolves to a CLASS (emit
>   `class-decl`, then bodies for `FindChildSymbols`). v0.41 switched the bundler to pass the
>   TARGET's own qname; nothing here was updated. A method has no child symbols -> body loop
>   emitted NOTHING. A routine now emits its own recorded `impl_start_line..impl_end_line` from
>   the index (not `FindImplLine`'s heuristic, which cannot separate overloads). Class path
>   untouched. 931 -> 1968 tokens on a real symbol.
> * **2.3 stale incremental skip. THEIR HYPOTHESIS WAS WRONG** -- not mtime granularity;
>   `FileIsUpToDate` compares path AND mtime AND sha256 and the write path really upserts. The gap
>   is that the test keys on FILE identity and knows nothing about **what the current build would
>   extract** (no engine version / schema / preprocess profile / platform). So after any engine
>   upgrade an unchanged file was skipped FOREVER on its older parse. Fixed with a per-DB
>   **indexer fingerprint** in `schema_meta` (no table migration), checked on BOTH index paths,
>   plus a new **`--force-reparse`** (alias `--no-skip`) so consumers stop needing `touch`.
> * **GRANDFATHERED, by the user's explicit choice:** a DB with no stored fingerprint adopts the
>   current one silently. Treating "unknown" as stale would force a one-time full reparse of every
>   index incl. the ~1.8 GB `library-Win64`. **Consequence: existing DBs are NOT retroactively
>   repaired -- run one `--force-reparse` per DB that matters.**
> * Queued, not started: 2.1 procedural types (highest-value extractor gap), 2.4 `--exact`,
>   2.5 tie order / bare names resolving to FMX, 2.6 enum members, 2.7 FTS5 on ad-hoc DBs,
>   2.8 `--quiet`. `#mapping`/`#apply` is deliberately NOT filed as a bug.
>
> ### HAZARD -- how the shared exe must be built (nearly shipped a broken engine)
>
> `third_party\dll-win64\drag-lint.exe` is **gitignored**, hand-staged, and shared with the
> converter group. **This branch is 115 commits ahead of `main` but does NOT have
> `--refs-as-leaves`**, which their editor passes and an older engine treats as FATAL. Verified:
>
> ```
> branch build : FATAL: Exception: Unknown argument: --refs-as-leaves
> main + fixes : accepted
> ```
>
> So **never stage a build from `feat/autodoc-phase3`.** The two engine fixes were cherry-picked
> onto `main` (now `13e7fb0`) and the staged exe was built from there (2026-08-02 13:50) and
> smoke-tested. This is the LATEST-71 incident's exact shape -- it recurs because the shared exe
> is untracked, so git never warns.
>
> ### Also worth knowing
>
> * **Two Claude sessions ran in this repo at once earlier today.** The other one owned these
>   fixtures, corrupted `returns.pas` with literal unexpanded `` `r`n `` , and its runs collided with
>   mine on the shared scratch dir `C:\TEMP\draglint_docp3preservetags` (`EInOutError`, plus a
>   bogus 22-failure run). If suite results look wildly wrong, check for a second session before
>   believing them.
> * **Blank lines do NOT stop the harvester.** `HarvestScan` accumulates blank AND comment lines
>   and stops only at CODE or `///`. The other session's 8 double-blank insertions could not work.
>   The restored case notes sit between `unit X;` and `interface` -- harvest-proof BY CONSTRUCTION,
>   because `interface` is a code line.
> * The `.pas` LF endings seen mid-session were a **working-tree artifact only** -- `.gitattributes`
>   normalizes `*.pas` and a fresh checkout gives CRLF. Nothing was committed wrong.
>
> ### Git
>
> `feat/autodoc-phase3` = `c0cc93a`, **115 ahead of `main`**. `main` = `13e7fb0`, **126 ahead of
> `origin/main`**. **NOTHING PUSHED -- user holds push.** Tree clean; only the two INBOX markdown
> files are untracked, which is the convention.

> ## RESUME 2026-08-02 (LATEST-75) -- **T7 fixture rework IN PROGRESS. `run_doc_p3_preserve_tags.ps1` comment adjacency issue identified and partially addressed; `run_doc_p3_returns.ps1` expects 20 (TWENTY) not 19. See docs/lint/FIXTURE-UPDATE-T7-HARVEST-2026-08-02.md.**
> 
> ### Status Update
> 
> T7 legitimately harvests `//` comments directly above declarations. Test fixtures with such comments now see those harvested into `<summary>` tags. Two paths forward:
> 
> 1. **preserve_tags.pas**: Added 2+ blank lines before `///` tags to break adjacency (prevents comment-above-declaration harvesting since `HarvestInterfaceComment` uses `FindDocRegionAbove` with `AllowGap=1`). Fixture comments explain what each test isolates; separation preserves both the test intent AND the fixture's self-documenting nature without weakening the guards.
> 
> 2. **returns.ps1**: Updated count expectation from NINETEEN to TWENTY (line ~477). With T7 harvesting, one routine that previously had no summary (T3's omit-when-empty suppressed its blocks) now emits one, making its `<returns>` visible. The 20th line is legitimate and should be re-derived, not just counted.
> 
> ### NEXT IMMEDIATE ACTIONS
> 
> 1. **Verify preserve_tags fixture fix** -- run `run_doc_p3_preserve_tags.ps1` to confirm the blank-line separation breaks harvesting (assertions should now pass).
> 2. **Identify and list the 20th routine** in `run_doc_p3_returns.ps1` control list (which routine now renders Observed: when it didn't before).
> 3. **Debug returns.pas indexing issue** -- test currently shows all spans as 0..0 (empty index), despite the test creating and populating a database. May be fixture-format or runner-initialization issue.

> ## RESUME 2026-08-01 (LATEST-74) -- **T7 CODE COMPLETE and green on its own suite + 6 regressions + a byte-identical apply/strip round-trip. NOT FINISHED: two suites are RED on expectation churn the plan predicted. Committed anyway, deliberately, with the churn named.**
>
> ### What T7 shipped
>
> `HarvestText` in `DRagLint.Doc.Harvest.pas`; `EscXml` PROMOTED to
> `DRagLint.Doc.Regions`' interface (one escaper, one behaviour); `TDocFacts.HarvestedRemarks`;
> `HarvestInterfaceComment` called from `TDocFactsBuilder.Build`; `EmitHarvestedRemarks` shared by
> **both** of `MergeComment`'s paths (fresh and repair). Suite
> `tests/autodoc/run_doc_p3_harvest_text.ps1` + fixture `fixtures/docp3/harvest_text.pas`.
>
> **Three defects found and fixed while wiring it, each measured, not reasoned:**
>
> 1. **The scan must skip the existing doc region.** `MergeComment` writes its `///` block BETWEEN
>    the harvested `//` comment and the declaration, so a second run scanning up from the
>    declaration met `///` first, got `hrNone`, and DROPPED the summary the first run wrote.
>    `HarvestInterfaceComment` walks up over the region (blank-line tolerance = `FindDocRegionAbove`'s
>    `AllowGap=1`) so the candidate is the comment above it.
> 2. **The harvested paragraph DOUBLED on every apply cycle.** `StripManagedBlock` removes only the
>    `AUTO_BEGIN..AUTO_END` fence, so harvested prose (which sits above the fence) arrived in the
>    repair path's preserved-prose slot looking hand-written -- re-emitted as prose AND regenerated.
>    Fixed by dropping `AUTO_MARK`-carrying lines from that slot: marker-keyed ownership, the same
>    rule the rest of the unit uses. Same defect SHAPE as the nested-`<remarks>` duplication T3h fixed.
> 3. **`--strip` could not undo what `--apply` wrote.** Harvested remarks match neither strip rule 1
>    (no recognized opening tag before the marker) nor rule 2 (no fence), so apply-then-strip left the
>    marked line AND an orphaned `<remarks>` pair, with a `drag-lint:auto` marker surviving a verb
>    whose entire contract is that none do. Added **rule 1b** to `TDocStripper`. Verified:
>    apply -> strip is now **byte-identical to the pre-apply fixture** (MD5 `DDC392A8...` both sides).
>
> ### >>> NEXT ACTION -- the two RED suites. This is a FIXTURE decision, not a code fix.
>
> | suite | FAIL | cause |
> |---|---|---|
> | `run_doc_p3_preserve_tags.ps1` | 6 | its fixtures carry descriptive `//` comments above the declarations; those are now legitimately harvested into `<summary>`, and assertions written as "NOT wrapped in a fabricated `<summary>`" cannot tell a real harvest from the fabrication they were written to catch |
> | `run_doc_p3_returns.ps1` | 1 | `CONTROL: exactly NINETEEN Observed: lines` now counts **20** -- a routine that had nothing to say emitted no block at all under T3's omit-when-empty, and now emits one because the harvest gave it a summary, so its `<returns>` renders too |
>
> **VERIFIED legitimate, not a regression:** the new summaries are verbatim the fixtures' own `//`
> comments (transcript: `ClassLag`, `TAlpha/TBeta.Same`, `PlainSum`, `PrevIdx` ... all carry their
> own fixture prose). Nothing is fabricated.
>
> **Recommended fix -- do NOT weaken the assertions.** `preserve_tags`' checks are load-bearing
> against a real prior defect. Prefer moving those fixtures' descriptive comments so they are not
> adjacent-above a declaration (e.g. below the declaration, or separated by a line of code), which
> keeps every assertion's original intent intact. Only `returns`' NINETEEN -> TWENTY is a genuine
> count update, and it should be re-derived from the control list, not just incremented.
>
> ### Git
>
> `feat/autodoc-phase3`: `03dafb7` (T6) then T7. **T7 is committed with these two suites RED and
> said so in its commit message** -- the alternative was leaving three measured fixes uncommitted.
> Push still held by the user.
>
> ### Index gap filed this session
>
> `docs/INBOX-parser-var-named-dynamic.md` -- a var entry named `Dynamic` (or `Virtual`) fails to
> parse unless it is FIRST in its `var` block. Class **unsupported**; hits our own
> `src/doc/DRagLint.Doc.SymbolFacts.pas:1407` on every self-index run. Bisected to a 6-line repro;
> logged in `stats/draglint-gaps.log`.

> ## RESUME 2026-08-01 (LATEST-73) -- **T6 COMPLETE + committed (`03dafb7`). NEXT = T7. One measured hazard: the STAGED exe is main's build, so the whole autodoc battery is RED on its own default `-Exe` and only green with `-Exe` pointed at the linked build.**
>
> **Incoming messages: NONE.** Every `docs/INBOX-*.md` has a matching REPLY; nothing has
> arrived since `INBOX-REPLY-exe-default-0xC000007B-2026-07-29.md` (Jul 29 19:26). The
> `wt-merge-converter` worktree's INBOX files are Jul 30 08:39 **checkout** timestamps, not new mail.
>
> ### T6 -- harvester boundary scan + acceptance guards. DONE.
>
> New unit `src/doc/DRagLint.Doc.Harvest.pas` (`HarvestScan`, `THarvestReason`, `THarvestResult`,
> `HarvestReasonToString`), reached from the CLI as `selftest harvest --file <p> --line <n>`.
> Fixture `tests/autodoc/fixtures/docp3/harvest_scan.pas`, runner
> `tests/autodoc/run_doc_p3_harvest_scan.ps1` -- **33 checks, all PASS**, all eight verdicts observed.
>
> **Three decisions the plan left open, fixed and documented in the unit's header:**
> guard precedence is stated explicitly (hrEmpty before hrBanner -- an empty string satisfies the
> banner pattern too; hrTrailer on LAYOUT before any content is read); a **compiler directive is
> CODE, not a comment** (`{$IFDEF X}` read as a comment is harvestable -- `$R *.res` passes every
> content guard -- so the scan stops at one); and **blank lines are trimmed from BOTH ends** of the
> accumulated block, not only the top, so T7 is not handed a trailing empty paragraph.
>
> **Engine-verified, not asserted:** mutation M1 (reject on ANY `end;` stop) reddens **CaseAfterEnd
> alone**, CaseTrailer still green -- so the tie-breaker's *accepting* direction is load-bearing.
> Restored and re-verified green.
>
> A note for whoever writes the next brace comment: the unit's own header had to be rewritten as
> `//` lines because it spells the brace delimiters, and a brace comment ends at the first close
> brace inside it. The first draft did not compile -- it demonstrated the exact defect
> `hrNestedBrace` exists to catch.
>
> ### HAZARD (measured, pre-existing, NOT introduced by T6)
>
> `third_party\dll-win64\drag-lint.exe` is **main's** build (staged Jul 29 19:22 by LATEST-71 for the
> converter/proptree group). It has no `document --strip` -- a Phase 3 **T2** feature -- and no
> `selftest harvest`. All ~41 `tests/autodoc/` runners default `-Exe` at that staged copy, so **the
> autodoc battery is RED on its own default today**. Measured, not inferred:
>
> | suite | default `-Exe` (staged/main) | `-Exe` linked branch build |
> |---|---|---|
> | `run_doc_p3_strip.ps1` | 11 FAIL lines, verdict FAIL | 0 FAIL, **PASS** |
> | `run_doc_p3_provenance.ps1` | 6 FAIL lines, verdict FAIL | 0 FAIL, **PASS** |
> | `run_doc_p3_harvest_scan.ps1` (new) | would FAIL (no subverb) | 0 FAIL, **PASS** |
>
> **T6's runner deliberately keeps the suite convention** (default = the staged copy) rather than
> forking it: this is ONE cause with ONE fix -- restage when the branch merges -- and forty-one
> suites disagreeing about their default would hide it. **Until then, run the autodoc battery with
> `-Exe c:\Projects\Delphi-RAG-lint\src\cli\Win64\Debug\drag-lint.exe`.** Any "battery green" claim
> that does not name the exe is meaningless right now.
>
> This session built with a scratchpad wrapper that **does NOT stage** into `third_party\dll-win64`,
> deliberately: overwriting main's staged build with a `feat/autodoc-phase3` one would reintroduce
> exactly the defect LATEST-71 fixed for the other group.
>
> ### Git
>
> `feat/autodoc-phase3` @ **`03dafb7`** (T6). Push still held by the user. Tracked files dirty from
> earlier sessions are unchanged (`build/build_draglint_win64.bat`, the two Win32 BPL/DCP binaries,
> `third_party/dll-win64/drag-lint.json`, two docs).
>
> ### >>> NEXT ACTION
>
> **T7** -- harvester text transformation and interface-side wiring. Plan section "Task 7", line ~861
> of `docs/superpowers/plans/2026-07-24-autodocument-phase3-harvest-and-facts.md`.
> Then T8, T9, then the four facts T10-T14, then T15-T17.

> ## QUEUED FEATURE 2026-08-01 -- **`Assigned` section in the hover popup + auto-document. Implement SOON, after Phase 3 reaches a committable point. NOT one of Phase 3's 17 tasks.**
>
> User request: for objects (and maybe any variable), show the source lines that **create or
> assign** them -- exactly as `<returns>` already shows the `Result := ...` sites. Section name is
> literally **`Assigned`**. Cap at **5**, configurable.
>
> The cap has a precedent to copy rather than reinvent: `docs.max_callers` (default 5,
> `LoadDocMaxCallers` at `src/cli/DRagLint.CLI.pas:1071`, manifest read/validate/write at
> `src/index/DRagLint.Index.Manifest.pas:437/649/737`, capped at render in
> `src/doc/DRagLint.Doc.Facts.pas:783-790`). The new key is **`docs.max_assigned`, default 5**.
>
> Full request of record, with anchors and the four open design questions:
> **`docs/lint/FEATURE-assigned-section-autodoc-hover.md`**. Not started -- no branch, no spec.

> ## RESUME 2026-07-29 (LATEST-71) -- **INTERRUPT HANDLED: the shared binaries were built from the WRONG BRANCH, and the default `-Exe` could not start. Both fixed + staged. Plan NOT advanced: T5 is still NEXT.**
>
> This session did **no plan work**. The user redirected to incoming messages first. Read this block,
> then jump straight to LATEST-69/70 below and start **T5** (`task-5-brief.md`).
>
> ### What came in
>
> The converter/proptree group reported: their final review told the fix wave to align eleven suites'
> `-Exe` default to `src\cli\Win64\Debug\drag-lint.exe`, but that exe dies **0xC000007B**
> (27 PASS / 111 FAIL). They deliberately did not fix it -- main was merged and green and it would
> have been an unreviewed commit on main.
>
> ### Two defects found, both fixed
>
> **1. The `-Exe` default cannot start -- and the cause is one link deeper than reported.**
> Absent companions alone would be `0xC0000135` (DLL not found). `0xC000007B` is
> `STATUS_INVALID_IMAGE_FORMAT` = a **bitness** error. Measured: `third_party\dll` **is on `PATH`** and
> its three `tree-sitter*.dll` are **x86** (PE machine `0x014C`; `dll-win64` copies are `0x8664`). Chain:
> companions absent beside the exe -> loader falls through to `PATH` -> loads the x86 copies -> mismatch.
> On a machine without that `PATH` entry the same defect appears as `0xC0000135`, so **never assert
> "not 0xC000007B" -- assert "the default `-Exe` starts."**
>
> **Fix (in `build/build_draglint_win64.bat`, UNCOMMITTED):** stage the three companions next to the
> **linked** exe as well as outward. One `copy`. Fixes all **45** files under `tests\autotest\` that
> default to the linked exe (not eleven), needs zero test edits, and preserves
> `run_exe_freshness.ps1`'s teeth. **We rejected the prescribed fix** (repoint the suites at
> `third_party\dll-win64\drag-lint.exe`): that is a *staged copy* written by any branch at any time, so
> defaulting the battery at it institutionalises exactly what the freshness guard exists to catch.
>
> **2. The shared binaries other groups consume were built from THIS feature branch.**
> `third_party\dll-win64\drag-lint.exe` (Jul 29 09:54) came from `feat/autodoc-phase3`, which is
> **54 commits behind main** -- it contained none of main's merged proptree ancestor-scope work.
> Anyone testing the converter against the shared exe was testing without that fix.
>
> **Rebuilt from `main` (`34a96e2`) in a throwaway worktree and staged:**
>
> | artifact | path | size |
> |---|---|---|
> | `drag-lint.exe` Win64 (x64) | `third_party\dll-win64\drag-lint.exe` | 30,623,340 |
> | `dclDragLintWizard.bpl` **Win32** (x86 -- the IDE is 32-bit) | `third_party\dll-win32\dclDragLintWizard.bpl` | 7,061,115 |
> | `dclDragLintWizard.dcp` | `third_party\dll-win32\dclDragLintWizard.dcp` | 2,356,620 |
>
> Previous exe preserved as `third_party\dll-win64\drag-lint.exe.prev-autodoc-phase3`.
>
> ### Verification (classifiers named)
>
> | check | result |
> |---|---|
> | fresh `main` Win64 + Win32-BPL build | `CLI64_EXITCODE=0`, `BPL32_EXITCODE=0`, hints only (H2077/H2164) |
> | linked exe, 0 companions (RED) | `exit 0xC000007B` |
> | same exe, same dir, 3 companions (GREEN) | `drag-lint 1.2.1-alpha`, `exit 0` |
> | patched script, companions deleted first | script `exit 0`, `3 file(s) copied`, exe starts |
> | `run_proptree_ancestor_climb.ps1` on **default `-Exe`** | `exit 0`, final verdict `PASS` |
> | `run_proptree_prop_type_scope.ps1` on **default `-Exe`** | `exit 0`, final verdict `PASS` |
>
> Classifier for the suite rows is the **runner's exit code + its final verdict line**. A grep for
> line-start `PASS` under-counts (the suites indent `[PASS]`) -- it reported `PASS=1` for
> multi-assertion suites. Fifth instance of "green while measuring nothing": **name the command, the
> unit, AND the classifier.**
>
> ### Why our own battery never caught this
>
> `src\cli\Win64\Debug\tree-sitter*.dll` existed in this working tree, **hand-copied, untracked, and
> `.gitignore`d** (`.gitignore:14 Win64/`). Every "green on the default `-Exe`" we have ever claimed
> held because of three files present on one machine and in no commit. Same defect class as `b365197`.
> The fix removes the machine dependency instead of re-hiding it.
>
> ### Flagged, NOT touched -- decisions owed
>
> 1. **`build/build_draglint.bat` reproduces the defect by construction:** it builds **Win64** and
>    stages into `third_party\dll`, whose tree-sitter DLLs are **x86** and which is on `PATH`. A live
>    landmine for whoever runs that older script next.
> 2. **`third_party\dll\drag-lint.exe` is a stale x86 build (Jul 5)** and is on `PATH`, so a bare
>    `drag-lint` resolves to it -- the Win32 exe that `CLAUDE.md` warns OOMs on the 1.4 GB index.
> 3. **The build-script fix must land on main under the converter group's review**, not via this
>    branch's 103-commit merge. Their reason for stopping was correct; we did not commit either.
>
> ### Notification sent
>
> `docs/INBOX-REPLY-exe-default-0xC000007B-2026-07-29.md`, delivered to **both** checkouts
> (`Delphi-RAG-lint` and `Delphi-RAG-lint-converter`).
>
> ### Git / tree state
>
> `feat/autodoc-phase3` @ `b365197`, **103 ahead of / 54 behind `main`**; `main` is **72 ahead of
> `origin/main`**; **nothing pushed**; branch has no upstream. **USER HOLDS COMMIT+PUSH.**
> Tracked files dirty from THIS session: `build/build_draglint_win64.bat` (the fix),
> `third_party/dll-win32/dclDragLintWizard.bpl` + `.dcp` (**tracked binaries**, replaced by the
> main-built ones -- deliberate and flagged). Pre-existing dirty: `docs/lint/BACKLOG.md`,
> `docs/superpowers/specs/2026-06-29-grep-elimination-indexer-wishlist.md`,
> `third_party/dll-win64/drag-lint.json`. The temp `main` worktree was **removed** -- leaving it would
> have blocked the converter group from checking out `main` themselves.
>
> ### >>> NEXT ACTION
>
> **T5** -- ownership-yield investigation, TIMEBOXED. Brief:
> `.superpowers/sdd/2026-07-24-autodocument-phase3-harvest-and-facts/task-5-brief.md`.
> Then T6-T9 (harvester) and T10-T14 (four facts), both NOT STARTED.
>
> **Careful:** the battery's default `-Exe` is `src\cli\Win64\Debug\drag-lint.exe`, which in this
> working tree is still a **`feat/autodoc-phase3`** build (companions present, verified starting).
> The *staged* `third_party\dll-win64\drag-lint.exe` is now **main's** build and does NOT contain this
> branch's autodoc work -- do not use it to validate T5+.

> ## RESUME 2026-07-29 (LATEST-72) -- **T5 COMPLETE: ownership-yield investigation concluded. FINDING: correct conservative behaviour, no bug. No-bug path (finding document only). COMMIT DONE: `0c78b06`.**
>
> **T5 result:** No bug found. The dispose-gate (`AnalyzeReturnsOwner` line 1882) is working correctly by design. When a function disposes of Result anywhere (including in except blocks), `returns_owner` is conservatively omitted (empty). This prevents false `new` claims for functions with conditional ownership (freed on exception path, transferred on normal path).
>
> - **Fixture verification:** `owner_alias.MakeAliased` (aliased generic, no dispose) correctly yields `returns_owner = 'new'`
> - **Real YADF case:** `YADF.Tokens.LoadTokensFromString` has `Result.Free` in except block -> correctly yields `returns_owner = ''` (empty)
> - **Evidence:** Test `run_doc_p2_owner.ps1` PASS; disposition gate assertion `DisposedResult has NO Owns returned: line (Result.Free seen -- does not cleanly escape)` confirms correct behaviour
> - **Finding document:** `docs/lint/2026-07-29-ownership-yield-finding.md` records the gate, the rationale, and why the fix (conditional-ownership tracking) is out-of-scope for Phase 3
> - **Commit:** `docs/lint/2026-07-29-ownership-yield-finding.md` added; no code changes; no regression test needed
>
> **>>> NEXT ACTION: T6** -- harvester, boundary scan and acceptance guards. Brief: `.superpowers/sdd/2026-07-24-autodocument-phase3-harvest-and-facts/task-6-brief.md`.

> ## RESUME 2026-07-28 (LATEST-69) -- **AUTO-DOCUMENT PHASE 3: T4, T4b, T4c CLOSED. Two NEW INBOX tasks inserted. Branch `feat/autodoc-phase3`, ~90 commits, NEVER PUSHED. USER HOLDS COMMIT+PUSH.**
>
> **Read `.superpowers/sdd/2026-07-24-autodocument-phase3-harvest-and-facts/progress.md` (ledger) and
> `deferred-defects-register.md` (live defects + standing policies) FIRST.** Every task has a
> `task-<N>-brief.md` in that directory; the inserted ones are hand-written.
>
> ### Closed this session
>
> | task | commits | rounds |
> |---|---|---|
> | **T4** caller-line render fixes | `447e812`, `4b35452`, `fb37b37` | 2 review rounds, clean |
> | **T4b** INBOX `<returns>` correctness | `2fbb20d`, `55bcdaf`, `75a4be6`, `b14fbd7`, `2cd6edc` | **4** review rounds, clean |
> | **T4c** INBOX tree-sitter DLL | `0e84cc6` | verdict: **already fixed, no rebuild** |
> | **T4d** INBOX `proptree` ancestor climb | `b811097`, `7192542`, `c4b78d0` | 2 rounds, clean. **Unblocked the converter editor** |
> | **T4f** SECOND MINOR SWEEP (user-inserted) | `8fbdaf8`..`dc4cc70`, `59fff21` | 1 round, clean. 29 items, every one with a named verdict |
> | **T4e** INBOX Win32 index abort | `c9dea59`, `a687aca`, `b365197` | 1 round. **drag-lint was never crashing** |
>
> ### T4e's answer, because it invalidates a shared assumption
>
> `index --all` was **terminated externally** by a caller passing exit `-1` (`Process.Kill` family =
> `TerminateProcess(h,-1)`), which is why stderr was empty and no Windows event was logged. The
> `DIAG:` line the report called the crash site was a **128-byte `TTextBuf` boundary**: all three
> surviving logs are exact multiples of 128 (941/3229/187 x 128) where a normal exit lands off-boundary.
> Attribution nailed to the second: run 4 died **20:03:41** and `build_r1.log.err` truncates at
> **20:03:41**; run 5 died **23:59:46.69**, `build_M3b.log.err` at **23:59:47** -- both from scripts
> whose FIRST statement is `Get-Process drag-lint | Stop-Process -Force`, inside a poll-until-writable
> loop that only iterates because something holds the exe. **Verdict: proven in its class,
> consistent-but-not-conclusive in attribution.**
>
> ### >>> TWO USER DECISIONS ARE BLOCKING NOTHING BUT ARE OWED
>
> 1. **K52 -- our own docs tell agents to kill drag-lint BY IMAGE NAME.** `Stop-Process [-Name]
>    drag-lint` appears in **28 `.md` files (41 occurrences)**, `Get-Process ... | Stop-Process -Force`
>    in **4 more (6)**, `taskkill /F /IM` in **3**. This destroyed a 1.9 GB index rebuild at least twice
>    and misdirected a multi-day investigation. Recommended: kill by **PID**, or scope to the holder of
>    the staging path. NOT DONE -- it is the user's documented procedure.
> 2. **The 9.5 MB `library-Win32.sqlite` fragment (HAZARD H2).** Recommended: rename to
>    `.broken-20260728` so consumers fail loudly instead of answering thinly. NOT DONE -- user's data.
>
> ### Ordered remaining work
>
> 1. **T5** ownership-yield investigation, TIMEBOXED (`task-5-brief.md`, written). **NEXT.**
> 2. **T6-T9 harvester (NOT STARTED)**, **T10-T14 four facts (NOT STARTED)**, T15, T16, THIRD minor
>    sweep, T17, T3m, final whole-branch review.
>
> **T10 gained an incoming ask -- K59, a `framework_type` record** (`docs/TODO-URGENT-framework-type-record.md`,
> filed at the user's explicit instruction by the proptree session, whose branch is barred from adding a
> schema column). T10 is the v19 bump, so a fifth additive column is cheap **if the design is right --
> and their own TODO shows the obvious column does not solve their case**: `.dproj` `<FrameworkType>` is
> project-scoped, the library index has no project concept, and `Abcbtn.pas` (the unit actually
> degrading -- `PopupMenu` 757 leaves, `Images` 214, `Font` 14) is shared library source with no
> `.dproj`. The `.dfm`/`.fmx` signal is one-sided: **743 `.dfm`, 0 `.fmx`**. **Two questions asked back
> before it lands:** is attribution per-FILE or per-PROJECT (declining may be correct, not a gap), and
> does their un-built uses-graph anchor subsume it as a query-time fix needing no reindex? See register
> K59 and `docs/INBOX-REPLY-proptree-branch-collision-2026-07-29.md` §6.
>
> ### MINORS -- the standing policy and the live state
>
> **User instruction (2026-07-29): collect minors, then clear them in a DEDICATED STEP.** They inserted
> **T4f** before T5 for exactly that and said to do it again -- so the **THIRD sweep** is a real
> scheduled task, not a footnote. T3k was the first, T4f the second.
>
> - **Register K-series high-water = `K58`. Allocate from K59, and CHECK THE REGISTER FIRST.** Two
>   agents once numbered from K21 independently and it had to be untangled by hand; separately, a
>   controller inventory built from headings **missed K26 and K27** because they were recorded in prose.
>   Enumerate with `bash grep -n` over the whole file, not by reading section titles.
> - **Open for the third sweep:** K15 (needs a Win32 BPL rebuild + a live IDE check -- outside this
>   build path and outside the battery), K20, K26, K27, K28 (needs the span validated against source --
>   indexer work), K30-K33, K36, K44-K58, plus the **fourth `--db` defect** (ancestor resolution does
>   not span every supplied `--db`; needs a multi-store id space through
>   `BuildPropTree`/`ClassChain`/`BodyOf`).
> - **A sweep's discipline, which worked twice:** every item leaves with a **named verdict** -- fixed /
>   confirmed already done / owned elsewhere untouched / declined with the reason -- including the
>   out-of-scope ones. T3k proved items vanish silently without it. **Batch the builds:** a `.pas`
>   comment edit re-times the source ahead of the staged exe and turns `run_exe_freshness.ps1` red.
> - **A sweep is where scope creep lives.** If an item needs design, a schema change, a library reindex
>   or a plugin rebuild, that is a *verdict*, not a licence to expand.
>
> ### HAZARD H3 -- BRANCH COLLISION, unresolved and owned by the user
>
> A parallel session fixed the **same** proptree defect on `feat/proptree-ancestor-scope` (11 commits,
> from `main@674706a`), announced in `docs/INBOX-REPLY-proptree-ancestor-scope-2026-07-29.md`.
> **Both branches created `tests/autotest/run_proptree_ancestor_climb.ps1` with different content, and
> both rewrote the same storage procedures -- whichever merges second will not merge cleanly.**
> Their branch is the better base for proptree (it also fixes scope-aware property TYPES:
> `Vcl.Controls.TControl.Parent` was resolving to `FMX.Controls.Win.TWinControl`), **but their
> `ResolveUnitUseTargets` has no extension filter and uses last-wins -- the Critical T4d fixed -- and on
> their branch it is NOT latent, because they populate that column for the first time.** Measurements
> and the four other findings they will want are in
> `docs/INBOX-REPLY-proptree-branch-collision-2026-07-29.md`. **Nothing on their branch was touched.**
> 4. **T6-T9 harvester (NOT STARTED)**, **T10-T14 four facts (NOT STARTED)**, T15 docs, T16 converter +
>    Obsidian, **THIRD minor sweep** (T3k was the first, T4f the second), **T17 rollout**, T3m, final
>    whole-branch review.
>
> ### T17 now has FIVE one-time-rewrite causes, not two
>
> Consolidated in the register under "T17 -- FIVE ONE-TIME REWRITES TO EXPECT". (1) T3g's re-indent,
> (2) T4's relabel + marker suppression, (3) **K21's pre-marker `<returns>` -- the ONLY one that does
> NOT self-converge**, (4) T4d's deeper ancestor chains changing doc facts on an UNCHANGED index,
> (5) **K44** -- `document --unit` omits a comment `document --qname` writes, because `HasManagedBlock`
> uses the `AUTO_BEGIN` fence as a proxy for "has facts" and T4b broke that proxy. Only (3) needs a
> decision; the rest converge on a second apply.
>
> ### Standing constraints that bite
>
> - **Only ONE agent may build+stage `drag-lint.exe` at a time** -- concurrent builds clobber each
>   other's staged binary. T4d/T4e/T5 all build. Serialize them.
> - **HAZARD H2: `library-Win32.sqlite` is a 9.5 MB fragment that answers queries WRONGLY.** It is
>   authoritative for NOTHING; a miss is not evidence of absence. Use `library-Win64.sqlite`. T4e is the
>   fix. Do not delete/rename the fragment -- user's data.
> - **Libraries stay un-reindexed until the schema is final** (user). This is a DESIGN constraint, not
>   just process: an index-time-only fix does not reach a consumer until a rebuild.
> - **Minors: collect, act later** (user, reaffirmed 2026-07-28). Register K-series high-water mark:
>   **K32**. Allocate from K33 and CHECK FIRST -- two agents independently numbered from K21 and it had
>   to be untangled.
> - **More INBOX messages are expected** (user). Two arrived mid-session. Each becomes a task WITH a
>   `docs/INBOX-REPLY-*.md`. Note `docs/INBOX-*.md` and `.superpowers/` are **untracked by convention**,
>   so those deliverables live only in the working tree.
> - Battery at `0e84cc6`: **`193 pass / 0 fail / 0 timeout out of 193 executed (of 194 found)`**, 10.8 min.
>
> ### The three ways this phase has been green while measuring nothing
>
> 1. **A mutation must leave the mechanism reachable and change only its answer.**
> 2. **A coverage claim must be an assertion or it must not be written.**
> 3. **NEW: a measurement must classify by a criterion INDEPENDENT of the mechanism it measures.** T4b
>    shipped a Critical behind a green table because the table used the engine's own predicate.
>
> Corollaries earned this session: **every count must name its command AND its unit** (a two-round
> dispute where both numbers were right at different resolutions); **a figure is only as findable as the
> digits you think to look for**, and spelled-out numbers are invisible to a digit sweep.
>
> ### Controller errors (mine), for whoever dispatches next
>
> Five now, all the same shape: **reasoning about code from a summary instead of from the code, then
> stating the conclusion as an instruction.** The worst would have destroyed 111 `<returns>` sections in
> our own source. Every one was caught by an implementer who measured. **Keep "push back with evidence"
> in every brief** -- it is the only reason these were recoverable.
>
> ---

> ## RESUME 2026-07-28 (LATEST-68) -- **AUTO-DOCUMENT PHASE 3: 15 of 27 TASKS DONE. Branch `feat/autodoc-phase3` @ `6bcc0a3`, 81 commits, NEVER PUSHED (no upstream). `main` is 56 ahead of `origin/main`. USER HOLDS COMMIT+PUSH.**
>
> ### 0. READ THIS FIRST -- T4's STATE
>
> **[UPDATED at handoff time -- see the T4 STATUS line at the end of this block for what actually
> happened.]** T4 was dispatched and got a long way before the reset: measured at 08:43, the runner
> `tests/autodoc/run_doc_p3_callerline.ps1` (16 KB, all five assertions) and the fixture
> `tests/autodoc/fixtures/docp3/callerline.pas` both existed, `src/doc/DRagLint.Doc.Facts.pas` and
> `DRagLint.Doc.Regions.pas` carried **+98/-10**, and the exe had **already been rebuilt after the last
> source edit** -- i.e. it was in the verification phase, not the beginning.
>
> **So do NOT reflexively discard those edits.** If T4 committed before the reset, `git log` shows it
> and there is nothing to decide. If the working tree still holds uncommitted `src/doc/*.pas` changes
> with no T4 commit, you have a nearly-complete implementation whose agent is gone: **run
> `pwsh -File tests\autodoc\run_doc_p3_callerline.ps1` and the full battery first** -- if they pass,
> review and commit it as T4; if they fail in a way you cannot quickly attribute, then revert
> (`git checkout -- src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas`, delete the two
> new test files) and re-dispatch from
> `.superpowers/sdd/2026-07-24-autodocument-phase3-harvest-and-facts/task-4-brief.md`, which is complete.
> **T4 has NOT been reviewed either way -- the task review still owes.**
>
> Also dirty and SAFE TO KEEP (controller's, not T4's): `docs/lint/BACKLOG.md`,
> `docs/superpowers/specs/2026-06-29-grep-elimination-indexer-wishlist.md`.
> `third_party/dll-win64/drag-lint.json` -- provenance unclear, inspect before keeping.
>
> **T4 STATUS AT HANDOFF -- RESOLVED, no decision needed.** T4 completed and **committed `447e812`**
> before the reset, so there are no orphaned edits and nothing to revert. Battery
> **`191 pass / 0 fail / 0 timeout out of 191 executed (of 192 found)`** at `447e812`; sweep zero
> differing lines. **T4 has NOT been reviewed -- reviewing it is the next session's FIRST ACTION.**
> Base for the review package is `6bcc0a3`.
>
> Three things T4 established that later tasks need:
> 1. **The plan's "49 of 49 saturation" is STALE** (it predates T3i). Measured on the pre-T4 tree:
>    YADF **186/263 entries = 70.7%** (28 lines all-certain / 65 all-uncertain / **6 mixed**);
>    drag-lint `src` **2594/3039 = 85.4%** (211 / 832 / **83 mixed**). The mixed-only rule still holds
>    -- two thirds of lines are uniformly uncertain, so suppression concentrates the signal rather than
>    erasing it -- but **mixed lines demonstrably exist**, which is what makes the rule meaningful.
> 2. **`CanBeCallTarget` was reused; the five-kind set appears nowhere in the diff.** The plan would
>    have had T4 write a third copy -- carrying that cross-task interface into the dispatch is what
>    prevented it, and future dispatches must keep doing so.
> 3. **The brief's `--json` fallback for the mixed assertion was ILLUSORY** -- `document --json`
>    exposes no facts, so it could never have worked. T4 achieved the STRONG form instead (same-unit
>    caller resolves, cross-unit does not), with preconditions re-derived from the index via
>    `dump-call-edges` / `ambiguous-calls`, both proven to discriminate.
>
> **T4's open concerns, for the reviewer and for T17:**
> - Two runners pinned the old `Called from:` label; one had been pinned **by T3i specifically for T4
>   to flip**. Both were updated as expectations, never the engine, and both gained checks.
>   `CalledFromLine` needed widening because two callers assert *absence* and would have read a
>   relabelled line as no line.
> - **NEW, filed for the second minor sweep:** the IDE plugin's hover column caption still reads
>   "Called from" for every kind (`src/delphi-plugin/.../HoverForm.pas:1211`), so hover and the written
>   doc now disagree for types. Out of T4's scope and build path.
> - **T17 must expect a one-time non-empty first-apply diff** on already-documented code (the relabel
>   plus marker suppression). Verify with `git diff -w`, as T3g's re-indent already required.
>
> ### 1. Where to read, in order
>
> 1. `.superpowers/sdd/2026-07-24-autodocument-phase3-harvest-and-facts/progress.md` -- the LEDGER.
> 2. `.../deferred-defects-register.md` -- the LIVE defect list, with standing policies at the top.
> 3. `.../task-<N>-brief.md` -- every task has one; inserted tasks' briefs are hand-written.
>
> ### 2. Status
>
> **DONE (15):** T1, T2, T3, T3b, T3c, T3f (before this session) + **T3e, T3g, T3d, T3d2, T3h, T3j,
> T3i, T3k** (this session). All review-clean.
> **ORDERED REMAINING WORK (updated 2026-07-28 per the user):**
> 1. **REVIEW T4** -- complete and committed (`447e812`) but ungated. Base `6bcc0a3`. **First action.**
> 2. **T4b -- INBOX: autodoc `<returns>` is incomplete and can be actively misleading.**
>    `docs/INBOX-autodoc-returns-section-incomplete.md` (2026-07-27). A correctness defect **in this
>    phase's own feature** -- it names a value the function provably does not return, and that text is
>    read daily through Help Insight and LSP hover. Fix **and write a REPLY doc reporting what was
>    done.** Register has the full brief.
> 3. **T4c -- INBOX: rebuild the production tree-sitter DLL + reindex.**
>    `docs/INBOX-tree-sitter-jedi-jvcl-grammar-fixes.md` (2026-07-17). Three grammar gaps fixed
>    upstream (`e531000`); drag-lint cannot see them until the DLL is rebuilt. **CAUTION:** the message
>    asks for a reindex, but the standing user decision is *libraries stay un-reindexed until the
>    schema is final* -- so self-index only, and say so in the reply. Also write a REPLY doc.
> 4. Then **T5**, **T6-T9 harvester (NOT STARTED)**, **T10-T14 four facts (NOT STARTED)**, T15 docs,
>    T16 converter+Obsidian, **second minor sweep** (K5-K15), **T17 rollout**, **T3m**, final
>    whole-branch review.
>
> **Both INBOX tasks must end with a written reply** (`docs/INBOX-REPLY-*.md`), following
> `INBOX-REPLY-converter-v18-ack.md` as the format precedent: what shipped, what was measured, and
> anything deliberately not done with the reason.
>
> **The battery is `190 pass / 0 fail / 0 timeout out of 190 executed (of 191 found)` at `6bcc0a3` --
> zero exemptions, no caveats. The phase's first fully honest green.** Run it with
> `pwsh -File tests\run_battery.ps1` and quote the denominator IT prints.
>
> ### 3. Two rules this phase paid for -- put them in every future brief
>
> 1. **A mutation must leave the mechanism reachable and change only its answer.** Six proofs went
>    green while measuring nothing (one counted *extracted* items while the regression was in
>    *resolution*; one renamed a target so the site left the enumeration instead of becoming the
>    failure case; two were suppressed by an earlier gate; one used case-insensitive `-match` and
>    measured a neighbouring `//` line; one examined ZERO blocks because Python's universal-newline
>    translation defeated a `\r\n` split -- **and the re-reviewer hit that identical failure on its own
>    first attempt**). Practical form: disable the fix, confirm RED, **and confirm the RED names the
>    assertion you intended.** If a proof passes first try, be suspicious.
> 2. **A coverage claim must be an assertion or it must not be written.** "Prose broader than what
>    ships" recurred in **six consecutive rounds**, twice inside the guard files built to prevent it.
>
> ### 4. IMPROVEMENT SUGGESTIONS -- do not lose these
>
> **Indexer (all filed in `docs/superpowers/specs/2026-06-29-grep-elimination-indexer-wishlist.md`):**
> - **E4, highest value: nested routines are NOT INDEXED AT ALL** -- no symbol, no refs. Verified:
>   `local_var` = 13,993 rows (so the walker DOES enter routine bodies) but routine-in-routine symbols
>   = **0**. Consequence: `find-callers` can report "no callers" **wrongly**, and the failure mode is a
>   confident EMPTY RESULT, not an error. It already caused a real miss (a 4-consumer enumeration
>   returned 3; Grep found the 4th). **Rule until fixed: the index is authoritative for a POSITIVE
>   answer, not a NEGATIVE one.**
> - **E5:** a paren-less dotted call in expression position (`T := TThing.Create;` -- the dominant
>   Delphi constructor idiom, 1215 orphan `Create` member-accesses in the self-index) emits **no `call`
>   ref**, so it is invisible to `Calls:`, `call-path`, `call-tree`, `Covered by:`. Fixing it changes
>   what is INDEXED and needs every index rebuilt.
> - **Text index does not cover `.ps1` / `.bat` / `.md`** (`--source` accepts `pas|dfm|sql` only). The
>   `.ps1` gap is the costly one: `tests/` holds ~190 runners and "which runner asserts X?" is a
>   constant question. Proposed minimal shape: extend the existing FTS5 table with a `source` value per
>   family so `--source ps1` works like `--source pas`. Exclude generated output.
>
> **Tooling / harness:**
> - **The `Grep` TOOL silently skips hidden directories on recursive sweeps.** A repo-wide search
>   returned 2 files while `bash grep -rl` returned those plus 5 under `.superpowers/`. Since the
>   ledger, register, briefs and reports ALL live in that dot-directory, **any completeness-critical
>   sweep must use `bash grep -rn` or an explicit path.**
> - Consider a CI/battery check that the two guards themselves stay green on a FRESH CLONE, since both
>   were built around fresh-clone-vs-working-tree divergence.
>
> **Process (from controller errors this session -- all mine):**
> - **Run the task review BEFORE sending a fix round.** I once analysed an implementer's concerns and
>   dispatched fixes myself, skipping the independent review; two of my rulings in that dispatch were
>   wrong and only the implementer's pushback caught them.
> - **Do not inherit framing from the register without checking the code it describes.** Three of my
>   rulings were wrong for exactly this reason (a "require blank" rule that would have broken
>   apply/strip symmetry; a line-source that would have made a guard vacuous; a kind-set widening that
>   would have fabricated a new fact line). **Implementers caught all three with measurements.**
> - **Plan premises go stale mid-execution.** T4's justification cites a "49-of-49 saturation" that T3i
>   partly fixed eight tasks later. Briefs for remaining tasks must say **measure the current state,
>   do not assume the plan's numbers.**
> - **Every count must state the command that produced it.** Three separate count disputes this phase.
> - **Carry accumulated constraints into every dispatch** -- the plan text cannot know about predicates
>   and guards added by inserted tasks. T4 would have written a THIRD copy of `CanBeCallTarget`.
>
> ### 5. Open USER decisions
>
> - **E3: is the Win32 CLI still a supported artifact?** `third_party\dll-win32\drag-lint.exe` is from
>   2026-07-05 (`0.86.0-alpha` vs the CLI's `1.2.1-alpha`). Nothing in the battery targets Win32 any
>   more; `run_exe_freshness.ps1` deliberately does not decide it and now fails a Win32 exe for the
>   TRUE reason (staleness), so answering "supported" just needs a build step added.
> - **Commit + push:** 81 branch commits, no upstream; `main` 56 ahead of `origin/main`.
>
> ### 6. Gotchas for a cold start
>
> 1. **HAZARD H1:** a scripted edit can silently convert CRLF->LF and **the diff, the build AND a green
>    battery all miss it** -- git commits a correct blob while the on-disk file `dcc64` reads stays
>    wrong. `run_encoding_guard.ps1` now catches it repo-wide; still check bytes on files you touch.
> 2. `Doc.Document.pas`'s `RegionFullyEngineOwned`, `IsFenceOnlyRemarksSpan`, `CommentLinesContain` and
>    the delete-branch gating are **OFF-LIMITS** as executable code -- that file regressed in three
>    consecutive rounds.
> 3. A **background task started inside a subagent's turn does not survive that turn ending** -- one
>    implementer lost a battery run at 114/185 this way. Keep long verifications in the foreground.
> 4. The self-index lags the working tree; reindex `src/` (~30s incremental) before querying, or a
>    stale query sends you back to Grep.
> 5. `.pas`/`.dfm`/`.dpr`/`.dpk`/`.inc` are strict CRLF + 7-bit ASCII + no BOM, enforced by
>    `.gitattributes` AND now by the encoding guard.
>
> ---

> ## RESUME 2026-07-27 (LATEST-67) -- **AUTO-DOCUMENT PHASE 3 IS IN EXECUTION. 6 of 25 tasks done, all review-clean. Branch `feat/autodoc-phase3` @ `97d9f53`, 27 commits, NEVER PUSHED (no upstream). `main` @ `18bbbc8` is 18 ahead of `origin/main`. Working tree CLEAN. USER HOLDS COMMIT+PUSH.**
>
> **>>> NEXT ACTION:** continue with `superpowers:subagent-driven-development`. Read this entry, then
> the SDD ledger `.superpowers/sdd/2026-07-24-autodocument-phase3-harvest-and-facts/progress.md`
> and the live defect list `deferred-defects-register.md` in the same directory. Task briefs and
> per-task reports for every completed task are there too.
>
> ### 1. Status -- what shipped
>
> | Task | State |
> | --- | --- |
> | T1 uniform `<!-- drag-lint:auto -->` provenance marker; `Observed:` sniff deleted | DONE, review clean (1 fix round) |
> | T2 `document --strip` | DONE, review clean (1 fix round) |
> | T3 omit empty summary/param/returns tags | DONE, review clean (**3** fix rounds) |
> | T3b preserve hand-written `<exception>`/`<example>`/`<since>`/`<deprecated>`/`<seealso>` | DONE, review clean (**4** fix rounds; escalated to a fresh implementer at round 4) |
> | T3c index doc-tag coverage (`HasContent` widened) | DONE, review clean (1 fix round) |
> | T3f repair path preserves what it cannot model | DONE, review clean (1 fix round) |
>
> **The plan grew from 17 to 25 tasks.** Seven were inserted mid-execution -- T3b, T3c, T3d, T3e,
> T3f, T3g, T3h -- each after a review found a real defect, most of them **pre-existing and older
> than Phase 3**. Nine such bugs have surfaced so far, including `MergeComment` silently dropping
> five hand-written tag types since `24efbb9` and class-member doc de-indentation since `26b986c`.
>
> ### 2. Resume point -- the ordered remaining work
>
> 1. **T3e -- battery health.** Scope expanded 2026-07-27. `tests/` holds 185 `.ps1`, but every
>    "full battery" run in this phase covered only `autodoc` + `autotest`. A controller sweep of the
>    other **68 runners** gave **60 pass, 8 RED**:
>    - `tests/autofix/run_missing_doc_fix.ps1` -- **almost certainly OUR churn.** T3 stopped emitting
>      description-less `<param>` and empty `<summary>`, so the missing-doc autofix no longer inserts
>      what this suite asserts. T3's churn pass covered only autodoc/autotest, because that was the
>      only definition of "the battery" anyone had.
>    - `tests/refactor/run_textedit_tests.ps1` -- **not ours**:
>      `BUILD FAILED: F2613 Unit 'DRagLint.Preprocess.Types' not found` at `Core.Interfaces.pas(8)`.
>    - Undiagnosed: `callresolve/run_ambiguous_calls`, `callresolve/run_calledfrom_resolved`
>      (caller-resolution -- T1/T3/T4 all touch it, **must** be diagnosed), `refactor/run_buildlocal_tests`,
>      `refactor/run_extractmethod_unit_tests`, `ergonomics/run_pipeline_tests`,
>      `lintconfig/run_lintconfig_tests`.
>    - Also: `run_smoke.ps1` (stale **Win32** exe -- needs a Win32 build) and the two FLAKY runners.
>    - **Durable deliverable: fix the coverage DEFINITION** so no future task can report green against
>      61% of the suite. Classify every failure as (a) our churn -- fix the expectation, never the
>      engine; (b) a regression we caused -- fix the engine; (c) pre-existing/harness -- fix or record
>      why it cannot pass. No silent skips.
> 2. **T3g -- the ONLY hard blocker for T17.** `document --apply` de-indents every class member's doc
>    comment to column 0. Root cause: `src/doc/DRagLint.Doc.Document.pas` hardcodes `Prefix:= '/// '`,
>    introduced in `26b986c`. Fix `Prefix` to inherit the declaration's leading whitespace and add a
>    fixture with an indented class member asserting the indent survives.
> 3. **T3d** -- 16 deferred code defects (D1-D12 plus N4-N9 and T3f's four minors), listed in the register.
> 4. **T3h** -- unkeyed singular-match picks the wrong occurrence from cycle 2; its residue is
>    **unmarked, so `--strip` cannot remove it**. Needs parser position-tracking.
> 5. **T4-T17, the untouched original plan** -- caller-line fixes, the TIMEBOXED ownership investigation,
>    **the harvester (T6-T9) and the four new facts (T10-T14) have NOT started**, then docs, the
>    converter INBOX + Obsidian schema page, and the rollout.
>
> ### 3. Commands
>
> - Build: `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` with a log; confirm
>   `BUILD_EXITCODE=0`, no `[dcc] Error`, and that the deployed
>   `third_party\dll-win64\drag-lint.exe` timestamp actually moved. Kill orphan `drag-lint.exe` /
>   `bds.exe` first -- a lock makes the deploy copy fail SILENTLY and you then test a stale exe.
> - Battery: **a runner is `run_*.ps1`.** On-disk **112** = 45 `tests/autodoc/` + 67 `tests/autotest/`.
>   `tests/autotest/_manifest_common.ps1` is a dot-sourced HELPER, not a runner -- miscounting it caused
>   three separate disagreements. Plus the 68 runners in the other `tests/` subdirectories.
> - Safety net: `pwsh -File tests\autodoc\run_doc_p3_idempotency_sweep.ps1` -- enumerates symbols from
>   the index and asserts an md5 fixed point over 3 apply+reindex cycles plus the cycle-1 branch action.
>   **Run it before and after any change to the doc engine and diff the results.**
> - DBs: no `sqlite3` on PATH -- use `C:\Python314\python` (`?mode=ro`).
>
> ### 4. User decisions that OVERRIDE the plan as written
>
> 1. **Do NOT reindex the libraries** until the schema structure is final. Further inserted tasks may
>    push the schema to v20/v21 and that is accepted. Keep only the drag-lint self-index
>    (`C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite`) fresh, so index queries can replace Grep.
>    **This supersedes T17 steps 3 and 4** ("reindex all 9 manifest DBs" / "both YADF DBs").
> 2. **"Fix all the problems and then continue."** Nothing is parked for the final review; the
>    register is the live list and items leave it only when actually fixed.
> 3. **Standing policy for a newly found problem:** if it interferes with the task in hand, fix it
>    INLINE in that task's fix round; otherwise finish the task and insert it as the NEXT step while
>    the context is fresh. Never append it silently to the end.
> 4. **More review passes are pre-authorized.** Do not trade review depth for speed.
> 5. **Index-first over Grep**, including for this repo's own `.pas` files; log each replaced Grep to
>    `stats/draglint-usage.log`. (That log's `est_tokens_saved` column is a hand-entered ESTIMATE; the
>    genuinely measured figure is `bench-context` on ORM3, 556 vs 33,762 tokens.)
>
> ### 5. Gotchas for a cold start
>
> 1. **`MergeComment` has absorbed 12 fix rounds across 5 tasks.** Its invariants: the presence/content
>    split (each gate reads its own `BuildStandaloneFor` view for PRESENCE; content ALWAYS from
>    `AExisting`); `PRESERVED_VERBATIM_CONTAINERS` + `PRESERVED_CONTAINER_PATTERNS` must stay
>    load-bearing and must match the parser's patterns character-for-character; a marked tag is
>    engine-owned regardless of content **except `<param>`** (nothing will ever refill one), and
>    `--strip` mirrors that exception.
> 2. **`RegionFullyEngineOwned`, `IsFenceOnlyRemarksSpan`, `CommentLinesContain` and the delete-branch
>    gating in `Doc.Document.pas` are OFF-LIMITS** unless a fix provably requires them. That file
>    regressed in three consecutive fix rounds.
> 3. A test that passes with the fix disabled is the most common defect the reviews caught here --
>    **verify every new assertion by reverting the fix and confirming RED.** Swap the deployed binary;
>    `-Exe <path>` is not a usable revert mechanism (the binary needs its siblings, so every check
>    degrades to a false RED).
> 4. `.pas`/`.dfm` = strict 7-bit ASCII + CRLF, no BOM; DocInsight on new public declarations; a
>    `{ }` comment must not contain `{`, `}` or `...`.
> 5. The tree-sitter self-lint PostToolUse hook reports FALSE errors on generic-heavy `.pas` -- trust
>    `dcc64`, not the hook.
> 6. `YADF.sqlite` (v18) and `YADFOT.sqlite` (**v17**) are not in the manifest, so `resolve-dbs` never
>    selects them; pass `--db` explicitly.
> 7. Two untracked runners (`tests/autotest/run_hover_callsite.ps1`, `run_typeat_generic_member.ps1`)
>    are real prior-session regression tests, both passing, deliberately left uncommitted.
>
> ---

> ## RESUME 2026-07-26 (LATEST-66) -- **AUTO-DOCUMENT PHASE 3 PLAN WRITTEN (17 tasks; the plan FILE is named `2026-07-24-...`, pairing with the spec). No code changed this session -- plan-writing only. NEXT = `superpowers:subagent-driven-development` on the plan. Git UNCHANGED from LATEST-65: `main`=`7c551f1`, origin=`f434769`, 17 UNPUSHED + 17 dirty tracked files (LATEST-63 hover work) + the untracked spec + the new untracked plan. USER HOLDS COMMIT+PUSH.**
>
> **>>> NEXT ACTION:** run `superpowers:subagent-driven-development` against
> `docs/superpowers/plans/2026-07-24-autodocument-phase3-harvest-and-facts.md`.
> Read the plan's **Global Constraints** and **Notes for the executor** sections before dispatching
> task 1. The spec (`docs/superpowers/specs/2026-07-24-autodocument-phase3-harvest-and-facts-design.md`)
> is still accurate and is the source for *why*; the plan is the source for *what to type*.
>
> ### 1. Task map (17 tasks)
>
> | # | Task | Notes |
> | --- | --- | --- |
> | T1 | Uniform `<!-- drag-lint:auto -->` provenance marker; delete the `StartsText('Observed:')` sniff | **FOUNDATIONAL** |
> | T2 | `document --strip` (new unit `DRagLint.Doc.Strip.pas`) | needs T1 |
> | T3 | Omit empty `<summary>`/`<param>`/`<returns>`; drop marked stubs, keep human slots | needs T1 |
> | T4 | Caller-line fixes: ` ?` only when the list is MIXED + `Used by:` for non-callables | independent after T1 |
> | T5 | Ownership-yield investigation -- **TIMEBOXED**, `systematic-debugging` | independent after T1 |
> | T6 | Harvester: boundary scan + acceptance guards (new unit + `selftest harvest` probe verb) | needs T1-T3 |
> | T7 | Harvester: text transform + interface-side wiring | needs T6 |
> | T8 | Harvester: implementation-side fallback, precedence, hand-written-wins | needs T7 |
> | T9 | Harvester: drift/refresh rules, idempotency, strip round-trip | needs T8 |
> | T10 | Schema **v19** -- four additive `symbol_facts` columns + storage plumbing | independent of T1-T9 |
> | T11 | `mutates_params` fact (`Mutates:`) | needs T10 |
> | T12 | `ui_affinity` fact | needs T10 |
> | T13 | `touches` fact **+ the derived `Pure` line** | needs T11 (Pure's inputs) |
> | T14 | `wiring` fact (pure JOIN, no AST) + the doc/hover consistency assertion | needs T10 |
> | T15 | Docs refresh (INDEX-SCHEMA v19, CHANGELOG, AI-USAGE, `--help`, unit banners) | after T1-T14 |
> | T16 | Converter INBOX + **new** Obsidian `DragLint_Index_Schema.md` | after T15 |
> | T17 | Rollout: build, battery, reindex 9+2 DBs, YADF strip+re-apply, version bump | last |
>
> **T1-T3 are foundational and must not be reordered** -- the marker is what makes strip, empty-tag
> suppression, harvesting and the drift rule *exact* rather than heuristic.
>
> ### 2. Three plan decisions that deviate from the spec (flagged; overrule freely)
>
> 1. **The harvester lives in a NEW unit** `src/doc/DRagLint.Doc.Harvest.pas`, not inside
>    `DRagLint.Doc.Facts` as spec §3.6 says. That file is already 59 KB / ~1600 lines and the
>    harvester is a self-contained text scanner with a large test surface.
> 2. **Spec §3.3's "summary edited by a human, markers still present -> do not overwrite" is not
>    implementable** by the string comparison the spec itself specifies -- it is indistinguishable
>    from "source comment changed". Both therefore land on **refresh**. The plan states this in code
>    comments and in `AI-USAGE.md` rather than pretending the two rows separate: text inside a marked
>    tag is engine-owned, and a human takes ownership by **removing the marker**.
> 3. **`EscXml` moves** from `DRagLint.Doc.Regions`' implementation section to its interface so
>    `Doc.Harvest` reuses it. One escaper, never a copy.
>
> ### 3. Expect test-expectation churn in T1 and T3
>
> Several existing runners pin the exact emitted text (`<summary></summary>`, the trailing
> `AUTO_PARAM`): `run_doc_idempotent.ps1`, `run_doc_generate.ps1`, `run_doc_extend.ps1`,
> `run_doc_stale_param.ps1`, `run_doc_returns_merge.ps1`, `run_doc_multiline.ps1`. **Update the
> expectation, never the engine**, and list every runner touched in the commit message.
>
> ### 4. Source anchors quoted in the plan (verified 2026-07-24; re-verify before relying on them)
>
> - `SCHEMA_VERSION = 18` -- `src/storage/DRagLint.Storage.Schema.pas:6`; `symbol_facts` DDL at `:237`.
>   **`SCHEMA_DDL_FTS5_FIRST = 54` is UNCHANGED by v19** -- a column is appended to an existing
>   statement, no statement is inserted.
> - `Migrate` ALTER block -- `src/storage/DRagLint.Storage.SQLite.pas:598-626`; `FQPutSymbolFacts` at `:766`;
>   `PutSymbolFacts` body at `:2195`.
> - `AnalyzeReturnsOwner` -- `src/doc/DRagLint.Doc.SymbolFacts.pas:1842`; `TSymbolFactsAnalyzer.Analyze` at
>   `:1932`; **`AnalyzeReadsWrites` at `:574` is the template for every new AST analysis** (T11/T12/T13).
> - `JoinRefs` + the `?` rule -- `src/doc/DRagLint.Doc.Regions.pas:331-347`; the `Observed:` sniff at
>   `:488` and `:564`; `FormatPhase2FactLines` at `:230`; `MergeComment` at `:446`.
> - `TSymbolFacts` -- `src/core/DRagLint.Core.Model.pas:98`; `TDocFacts` -- `src/doc/DRagLint.Doc.Facts.pas:34`;
>   `TDocFactsBuilder.Build` at `:245`.
> - `VERSION = '1.2.1-alpha'` -- `src/cli/DRagLint.CLI.pas:6`. `selftest` subverbs at `:12716-12990`.
> - `TDocBatchOptions` -- `src/doc/DRagLint.Doc.Batch.pas:39`.
>
> ### 5. Gotchas for a cold start (unchanged from LATEST-65, still all live)
>
> 1. Nothing was committed this session -- `git status` first; 17 unpushed + 17 dirty + 2 untracked docs.
> 2. The 8 YADF `.pas` files carry BOTH autodoc and self-format changes -- never attribute that diff to the engine.
> 3. `YADFOT.sqlite` is v17; `YADF.sqlite` is v18. Neither is in the manifest `third_party/dll-win64/drag-lint.json`.
> 4. Reindexing to v19 must wire `--jobs` **together with `--config`** -- LATEST-62 ran ~3h/platform sequentially because `--jobs` needs `--config`. Parallelising it is a rollout step (T17), not a follow-up.
> 5. `.pas`/`.dfm` = strict 7-bit ASCII + CRLF, no BOM; DocInsight on new public decls; a `{ }` comment must not contain `{`, `}` or `...`.
> 6. The tree-sitter self-lint PostToolUse hook reports FALSE errors on generic-heavy `.pas` -- trust dcc64.
> 7. Kill orphan `drag-lint.exe` / `bds.exe` before any build (a lock makes the deploy copy fail SILENTLY and you test a stale exe).
> 8. Tasks 11-14 assert **index-time** facts -- the runner must `index` AFTER the new exe is deployed, or it asserts against stale rows.
>
> ---

> ## RESUME 2026-07-24 (LATEST-65) -- **(SUPERSEDED by LATEST-66 -- the plan is now written. This entry is the WHY: the approved spec + the YADF evidence behind it.)** AUTO-DOCUMENT PHASE 3 SPEC WRITTEN + APPROVED. No code changed this session. NEXT = `superpowers:writing-plans` on the spec, then `superpowers:subagent-driven-development` (~14-16 tasks, same shape as Phase 2). Git UNCHANGED: `main`=`7c551f1`, origin=`f434769`, 17 UNPUSHED + 17 dirty tracked files (LATEST-63 hover work) + the new UNTRACKED spec. USER HOLDS COMMIT+PUSH.**
>
> **>>> NEXT ACTION:** run `superpowers:writing-plans` against
> `docs/superpowers/specs/2026-07-24-autodocument-phase3-harvest-and-facts-design.md` (APPROVED),
> then execute the plan with `superpowers:subagent-driven-development`.
>
> ### 1. The LATEST-64 YADF autodoc run was ALREADY DONE -- and it is CLEAN
>
> It ran at **14:43 on 2026-07-24** on branch `experiment/drag-lint-autodoc` in `C:\Projects\YADF`
> (before this session started). Verified this session:
>
> - `YADF.sqlite` = **schema v18**, 176 files / 5,587 symbols / **1,089 `symbol_facts` rows**.
> - **50 managed blocks** written across 8 `.pas` files.
> - **NO CORRUPTION.** Declaration counts are byte-identical `HEAD` vs worktree in all 8 files, and
>   every file is still strict 7-bit ASCII. **The `7c551f1` `FindDocRegionAbove` fix holds on real
>   code -- the doc-block-collapse bug class is CLOSED.**
> - **TRAP:** the YADF worktree ALSO contains a **separate YADF self-format run** (14:54-14:55 --
>   aligned semicolons, split `var` lines, reindented implementation comments in `YADF.Options.pas` /
>   `YADF.Tokens.pas` / `YadfMain.pas`) plus `.res`, `YADF.Version.inc` and `build_all.bat` edits.
>   **The YADF diff is MIXED, not autodoc-only.** Do not read it as engine output.
> - `YADFOT.sqlite` is **STILL schema v17** (never reindexed, no `symbol_facts`).
>
> ### 2. What the real run exposed (the evidence Phase 3 is built on)
>
> | Fact line | Count in the 50 blocks |
> | --- | --- |
> | `Called from:` | 49 -- **every single entry marked ` ?`** |
> | `<summary></summary>` | **39 EMPTY stubs** (blank DocInsight tooltips) |
> | `Calls:` / `Covered by:` / `Observed:`+`Returns:` | 32 / 27 / 25 |
> | `Used in units:` / `Complexity:` | 6 / 5 |
> | `Reads:` `Writes:` `Handles:` `SQL:` `Owns returned:` | **0** |
>
> - **Harvestable legacy prose:** YADF **121** routines have a preceding non-DocInsight `//` comment --
>   but **120 of them are IMPLEMENTATION-side, only 1 is interface-side**. M2022/ORM3: **273**.
>   Authors comment the body; DocInsight renders the declaration. That gap is the headline feature.
> - **Ownership yield:** `returns_owner` is set on only **7 of 1,089** rows, all 7 in the DelphiAST
>   dependency, none in YADF's own code -- and `YADF.Tokens.LoadTokensFromString` abstained despite a
>   mined `Result := TTokenList.Create`. (So `Owns returned:` rendering 0 times is CORRECT, not a
>   render bug.)
>
> ### 3. Phase 3 scope -- 4 workstreams, ONE increment, ONE schema bump (v18 -> v19), ONE reindex
>
> - **WS0 (foundational) -- uniform provenance marking + `document --strip`.** Today the engine tracks
>   its own output THREE different ways and for one tag not at all: facts = `BEGIN`/`END` region
>   markers, `<param>` = a trailing marker, `<returns>` = **content sniffing**
>   (`StartsText('Observed:')`), `<summary>` = **nothing**. Phase 3 puts ONE `<!-- drag-lint:auto -->`
>   marker immediately after every emitted opening tag and **DELETES the sniff outright** -- only
>   **12 `.pas` files repo-wide** contain engine output (drag-lint 4, YADF 8), so a clean cutover beats
>   a compatibility window. New **`document --strip`** removes exactly the marked tags + facts regions
>   and nothing else; it replaces any heuristic "remove what we think drag-lint wrote" cleanup and
>   enables the `strip -> apply -> strip` round-trip test.
> - **WS1 -- comment harvesting.** Promote existing human prose into a MANAGED `<summary>` on the
>   interface declaration. **COPY, never move.** Drift-protected: a human-edited summary is never
>   overwritten, only reported. **Boundary scan (§3.4.1)** -- scan upward over comments *and blank
>   lines* until the previous real code (`end;` / `begin` / section keyword / another declaration /
>   `implementation`); blank lines do NOT break the scan. Plus banner / commented-out-code / trailer /
>   non-ASCII rejection, and an `end;` whitespace tie-breaker.
> - **WS2 -- 4 render fixes.** Omit and remove empty tags; emit the `?` marker **only when the caller
>   list is MIXED**; `Called from:` -> **`Used by:`** for types/records/consts; and a **TIMEBOXED**
>   ownership-yield investigation -- **if it is not a bug or has no immediate fix, document it and
>   defer to the next cycle. Do not hold Phase 3 open. Do NOT loosen the unanimity gate.**
> - **WS3 -- 4 new facts, schema v19.** Four ADDITIVE columns on `symbol_facts` (user chose
>   **keep-wide** over a narrow kv table, accepting that a future fact repeats the migration):
>   `mutates_params` (var/out writes -- closes the Phase-2 T4 deferred gap) with a render-time-derived
>   `Pure`; `ui_affinity`; `touches`; and `wiring` -- **a JOIN over the already-indexed
>   `di_bindings` / `orm_links` / `fb_relations`, no new analysis**.
> - **WS4 -- AFTER implementation (explicit user request, deliverables not follow-ups).** Docs refresh
>   (`INDEX-SCHEMA.md` -> v19, `CHANGELOG.md`, `AI-USAGE.md`, CLI `--help`, unit banners); a
>   converter-team message `docs/INBOX-index-schema-v19-reindex-for-converter.md` (template = the acked
>   v18 one; must state 19 = 18 + 4 additive columns, `SELECT *` now returns 4 more, **`symbols.id` is
>   REASSIGNED -> re-resolve by `qualified_name`**, which DBs were rebuilt incl. YADFOT, that `wiring`
>   is directly useful to them, and that `--strip` exists); and a **NEW** Obsidian page
>   `wiki/entities/DragLint_Index_Schema.md` (full v19 table inventory -- none exists today; the repo
>   `docs/INDEX-SCHEMA.md` stays authoritative).
>
> ### 4. One decision made against the user's literal words -- overrule if wanted
>
> The user said to remove "all autogenerated **and other** documentation" from YADF before re-running.
> **The spec KEEPS YADF's hand-written DocInsight** (especially `YADF.Guard.pas`) because it is the only
> CONTROL GROUP that exercises hand-written-wins, merge-into-existing-`<remarks>`, and drift detection --
> deleting it would leave the riskiest paths untested. The reset is `document --strip` (exact, marker-keyed)
> plus a `HEAD` comparison, **not** heuristic deletion. If a truly blank-slate run is wanted, do it as a
> SECOND pass on a throwaway branch.
>
> ### 5. Gotchas for a cold start
>
> 1. Nothing was committed this session -- `git status` first; 17 unpushed + 17 dirty + the untracked spec.
> 2. The 8 YADF `.pas` files carry BOTH autodoc and self-format changes -- never attribute that diff to the engine.
> 3. `YADFOT.sqlite` is v17; `YADF.sqlite` is v18. Neither is in the manifest `third_party/dll-win64/drag-lint.json`.
> 4. Reindexing to v19 must wire `--jobs` **together with `--config`** -- LATEST-62 ran ~3h/platform sequentially because `--jobs` needs `--config`. Parallelising it is a rollout step, not a follow-up.
> 5. `.pas`/`.dfm` = strict 7-bit ASCII + CRLF, no BOM; DocInsight on new public decls; a `{ }` comment must not contain `{`, `}` or `...`.
> 6. The tree-sitter self-lint PostToolUse hook reports FALSE errors on generic-heavy `.pas` -- trust dcc64.
> 7. Kill orphan `drag-lint.exe` / `bds.exe` before any build (a lock makes the deploy copy fail SILENTLY and you test a stale exe).
>
> ---
>
> ## RESUME 2026-07-24 (LATEST-64) -- **HANDOFF for a session RESTART (user is restarting to pick up the new Opus 5 model). No new code this session -- a short planning/checkpoint turn. NEXT SESSION does the two things below. Git UNCHANGED from LATEST-63: `main`=`7c551f1`, origin=`f434769`, 17 UNPUSHED + the LATEST-63 hover work (9 .pas + 1 test + docs) still UNCOMMITTED (survives the restart on disk). USER HOLDS COMMIT+PUSH.**
>
> **>>> NEXT SESSION -- do these in order:**
> 1. **RUN AUTO-DOCUMENT ON YADF** (the user-visible payoff + a real-world engine test). `document --project C:\Projects\YADF\YADF.dproj --apply` writes managed `<!-- drag-lint:auto -->` DocInsight + the Phase-2 analysis facts (Complexity / Reads-Writes / Covered-by / Handles / SQL / Owns-returned) into every public decl of YADF's compile closure.
>    - **BRANCH FIRST** -- YADF is a git repo; use the `experiment/autodoc-format` branch convention so the whole run is reversible, then review the diff before merging.
>    - **REINDEX YADF + YADFOT to v18 FIRST** -- neither `C:\Projects\YADF\YADF.dproj` nor `YADFOT.dproj` is in the drag-lint manifest (`third_party/dll-win64/drag-lint.json`), so their DBs must be (re)built with the v18 exe before `document` will find facts. The exe is already v18-built + deployed at `third_party/dll-win64/drag-lint.exe`.
>    - **Easiest path = the IDE menu** `drag-lint -> Generate & Export -> "Auto-Document Whole Project..."` which already runs reindex -> `document --apply` -> reindex in one LSP-safe job (LATEST-59). CLI recipe + all gotchas: LATEST-60 (the YADF rollout plan) and LATEST-59 below.
>    - **Known trap (now fixed):** the *previous* YADF autodoc run corrupted 8 `.pas` (doc-comment block collapse). Root cause was the `FindDocRegionAbove` adjacent-decl bug, **FIXED in `7c551f1`** (this branch). Still branch + eyeball the diff to confirm the fix holds on real code.
> 2. **THEN brainstorm autodoc enhancements** (`superpowers:brainstorming`). The user wants to "think about what we can add" -- there is **no Phase-3 spec yet**. Phase 1 + Phase 2 are FEATURE-COMPLETE; the only other open autodoc items are SHIP steps: version bump off `1.2.1-alpha` (`src/cli/DRagLint.CLI.pas:6`) + pack-release.
>
> **This session also (LATEST-64):** user CONFIRMED the popup-click AV is GONE in the live IDE (the LATEST-63 `TThread.ForceQueue` fix holds) -- that verify item is now closed. And moved the **"drag-lint FIRST, Grep second" GLOBAL RULE to the TOP of `c:\Projects\CLAUDE.md`** (was section 7, now section 1, tagged READ FIRST) so it is not forgotten. No drag-lint repo code changed.
>
> **Reindex status:** all 9 project/library DBs were reindexed to schema v18 in LATEST-62 -- so that autodoc prerequisite is done for the *manifest* DBs (YADF/YADFOT are the exception, handled in step 1 above).
>
> ---
>
> ## RESUME 2026-07-24 (LATEST-63) -- **BIG IDE-HOVER SESSION: shipped generic/alias member resolution (item #2, full spec+plan+SDD) + ~15 hover-polish/feature items across many rounds of live feedback. ALL built + DEPLOYED (exe `third_party/dll-win64/drag-lint.exe` 13:19; plugin BPL `third_party/dll-win32/dclDragLintWizard.bpl` 13:43). ALL UNCOMMITTED on `main`=`7c551f1` (9 .pas + new tests + 2 new docs + deployed BPL/DCP); 17 prior commits still unpushed. USER HOLDS COMMIT+PUSH. Context ran full -> handoff.**
>
> **>>> READ FIRST next session: this block. Everything below SHIPPED (built+deployed) but is UNCOMMITTED -- `git status`, then commit as labeled commits + push when the user says. Deep reasoning: wiki `entities/DragLint_Linter-reasoning-2026-07-24b.md`.**
>
> **WHAT SHIPPED THIS SESSION (all deployed, uncommitted):**
> - **Item #2 -- generic/alias instance-member resolution (spec `docs/superpowers/specs/2026-07-24-generic-inherited-member-resolution-design.md` + plan `.../plans/2026-07-24-generic-inherited-member-resolution.md`, TDD).** `TTypeAtResolver` is now MULTI-STORE (`Resolve(AStores: TArray<ISymbolStore>; ...)`; single-store overload is a wrapper). New: value->type re-resolution (LHS `ATokens` local -> its type via signature), same-store ANCESTRY walk (`ResolveMemberOnType`), cross-store GENERIC-BASE match (`ParseGenericBase`/`GenericArityOfName`/`FindGenericBaseAnywhere`; base-name+arity, RTL-preferred), and an `OwnerTypeFallback` floor (never a wrong `Symbols[0]`). `TTypeAtResult` gained `OwnerTypeFallback`+`ResolvedStoreIndex`. `typeat` now takes multi-`--db`. `HandleHover` passes `FStores` + honors the floor. REAL RESULT: `ATokens.Count` -> `System.Generics.Collections.TList<T>.Count : NativeInt` (matches IDE). Lock: `tests/autotest/run_typeat_generic_member.ps1` (all green). Files: `src/resolver/DRagLint.Resolver.TypeAt.pas`, `src/cli/DRagLint.CLI.pas`, `src/lsp/DRagLint.LSP.Server.pas`.
> - **Hover popup polish (many rounds):** (FB1) single-caller row now shown (grid sized from font+chrome). (FB2/R1) CONTENT-FIT sizing: measure body at FINAL width via `EM_GETLINECOUNT` + font-measured `LineH`, no artificial H cap -> `PlaceAndShow` screen-clamps; `BodyH = VisualLines*LineH + 12` (last "Used in" line never triggers the vertical scrollbar). (R2) reserve `SM_CYHSCROLL` on the callers grid. (R4) min width floors to SUM of caller columns (260+55+620) + vscroll -> no horizontal scrollbar. (FB3-header) `FACTS` section header renamed `DETAILS`. All in `src/delphi-plugin/DragLint.Plugin.HoverForm.pas` (structured `ShowAt(AModel,...)`).
> - **FB3 -- clickable Returns:** each `Result := <expr>` line jumps to its source line. Miner `MineReturnExpressionsEx` captures first-seen line offset (+ wrapper); `TReturnFact.Line`; `BuildHoverModel(... AReturnLines)`; `RenderHoverJson` emits parallel `returns_lines`; plugin parses + `ReturnLineForBodyLine` + nav. Lock: `run_hover_returns.ps1` (asserts `returns_lines`). Files: `src/cli/DRagLint.Hover.Returns.pas` + `.Hover.Renderer.pas` + plugin.
> - **R3 -- kind qualifier in header:** hover header now leads with `function`/`local var`/`parameter`/`property`/... via `KindQualifier(TSymbolKind)` (Renderer) -> `"kind"` in hover JSON -> plugin `BuildHoverSignature` prepends it.
> - **FB4 -- Code Elements `[?]` fixed:** the D5 index emits `local_var`/`param` symbols the outline parser mapped to `skUnknown` -> `[?]`; now EXCLUDED from the outline (`src/delphi-plugin/DragLint.Plugin.StructureCache.pas` ParseOutlineJson).
> - **AV CRASH FIX (critical, last thing done):** clicking a nav line in the popup crashed (AV in `System.GetDynaMethod` via DevExpress `cxContainerGetMessageHook`) -- `Close`+navigate INSIDE the `WM_LBUTTONUP` handler frees controls the VCL/DX hooks still dispatch on. FIX: all 3 nav sites in `HandleMemoClick` (structured header/returns, add-unit lightbulb, definition-row) now `TThread.ForceQueue` the close+navigate so it runs AFTER the mouse message unwinds. Values captured by-copy.
> - **#1 (ptObject) -- COVERAGE, not a bug:** `TptTokenKind`/`ptObject` live in `SimpleParser.Lexer.Types` (DelphiAST) which is on YADF.dproj's `DCC_UnitSearchPath` (a PROJECT unit, not external). YADF.sqlite was built by DIR-SCAN (folder only) so it missed it. Indexed `C:\Projects\DelphiAST\Source` into YADF.sqlite -> `ptObject` resolves + usages. (Dir-scan reindex is ADDITIVE -- verified out-of-dir symbols survive.)
> - **#2-enum -- ENUM ORDINAL stored + shown (`= 128` like the IDE):** parser (`src/parser/DRagLint.Parser.Delphi13.pas` TryWalkEnum) computes each enum value's ordinal by position, RESET by explicit `= N` (verified `fA=1/fB=5/fC=6`), stored in the enum_value SIGNATURE (no schema change). Hover JSON now emits `"signature"`; plugin appends `= N` for enum-value kind. `ptObject`=128 verified. NOTE: index-time -> existing symbols need a RE-PARSE to backfill (incremental skips unchanged; I force-repopulated SimpleParser via `touch`).
> - **#3 -- "Reindex Project" menu now TWO-PASS (`src/delphi-plugin/DragLint.Plugin.Editor.pas` InvokeReindexProject):** (a) `index <ProjDir>` (all local files incl. loose Demo/Test) + (b) `index --project <dproj>` (compile-closure -> search-path deps like DelphiAST/Spring4D). Both additive+incremental. Temp .bat, timeout 600s. So `Demo\Sample.pas` is NOT ignored (folder pass still covers it).
>
> **BUILD/DEPLOY recipe (proven all session):** exe = `build/build_draglint_win64.bat` (PowerShell `Start-Process -Wait` + log; copies to `third_party/dll-win64/drag-lint.exe`). Plugin BPL = `build_plugin_win32.bat` via `Start-Process -Wait -WorkingDirectory <repo>` (ABSOLUTE bat path -- a bare name isn't found); `.dproj` `DCC_BplOutput` deploys straight to `third_party/dll-win32`. **KILL `bds`/`drag-lint` before every build** (an orphan LOCKS the exe -> the copy SILENTLY fails and you test a stale exe -- bit me once, wasted a cycle). Both build in <2s, 0 errors.
>
> **>>> NOT DONE / NEXT SESSION:**
> 1. **User LIVE-VERIFY** (reopen RAD Studio -> new BPL + exe): item#2 (`ATokens.Count`->TList<T>.Count), popup sizing (R1/R2/R4 -- no scrollbars, snug callers), `DETAILS` header, kind qualifier, clickable returns, `ptObject`=128 + usages, Code Elements no `[?]`, **and confirm the AV crash on popup-click is GONE**.
> 2. **COMMIT** the session as labeled commits + **PUSH** (17 prior + this session). User holds both.
> 3. **tree-sitter Delphi-13 grammar gap:** `Demo\Sample.pas(1,1)` parse error -- the grammar chokes on Florence syntax (`is not`, `?:` ternary, inline `const`/`var` + inference, inline anon methods). Belongs to the tree-sitter-delphi13 workstream. Low impact (one demo file).
> 4. **Enum-ordinal backfill:** existing indexed enum values have empty signature until re-parsed; a clean/forced reindex backfills. New/changed files get it automatically. (No `--force` flag exists; incremental skips unchanged.)
> 5. **Perf:** hover is "sometimes slow" -- 2-3 exe spawns/hover + covered-by BFS (ParseGroups ~626ms in-proc). Not an item-#2 regression. Real fix = caching / in-process serving (follow-up).
> 6. Optional: plugin ON-OPEN reindex (ProjectNotifier) still dir-scan only; the two-pass is only the explicit "Reindex Project" menu. Consider whether on-open should also cover deps (heavy).
>
> **GOTCHAS (cold start):** (1) IDE CLOSED + kill orphan `drag-lint.exe`/`bds` before any build (lock -> silent stale deploy). (2) `Winapi.Windows` declares a `TBitmap` RECORD that SHADOWS `Vcl.Graphics.TBitmap` -- qualify `Vcl.Graphics.TBitmap` in HoverForm (bit me: E2003 Create/Canvas/Free). (3) the self-lint PostToolUse hook reports FALSE "2 errors" on `DragLint.Plugin.Editor.pas` (an array-list comment rule + generics) -- TRUST dcc32/dcc64. (4) `.pas` strict 7-bit ASCII + CRLF + DocInsight on new public decls. (5) `TThread.ForceQueue` is the AV-safe way to close/navigate a popup from its own mouse handler. (6) enum ordinal lives in the enum_value SIGNATURE (reused field, no schema bump). (7) `--project` closure is LARGE (DelphiAST/AsyncPro/Orpheus/Spring4D/ABC5) -- first two-pass reindex is slow, incremental after.
>
> ---
>
> ## RESUME 2026-07-24 (LATEST-62) -- **IDE HOVER: fixed call-site mis-resolution + dark-theme + structured facts + caller pollution/freeze; reindexed ALL DBs to v18; INDEX-SCHEMA.md->v18. NEXT = 5 hover-polish items (below). main=`7c551f1`, ALL this-session work UNCOMMITTED (5 .pas + 2 docs + new test + INBOX + deployed BPL/exe); 17 prior commits still unpushed. USER HOLDS PUSH/COMMIT.**
>
> **>>> READ FIRST next session: this block, then the "NOT DONE" list. Everything below SHIPPED (built + DEPLOYED to `third_party/`) but is UNCOMMITTED on disk -- verify with `git status` and offer to commit as ONE labeled commit.**
>
> **WHAT SHIPPED THIS SESSION (deployed, uncommitted):**
> - **Reindexed all 9 DBs to schema v18** (7 projects + `library-Win64` 6909f/2.17M sym + `library-Win32` 7143f/2.24M sym). Sequential (~3h/platform -- `--jobs` needs `--config`; wire that up to parallelize next time). All verified `schema_version=18`.
> - **Hover BUG 1 -- call-site mis-resolution (`src/lsp/DRagLint.LSP.Server.pas` HandleHover ~line 952):** hovering a QUALIFIED call `TGroup.Create(...)` resolved to an arbitrary same-named symbol (alphabetically-first library hit, e.g. `Abccompf.*`). FIX: when the cursor is NOT on a decl/impl, anchor to the store that OWNS the hovered file (`FindFileIdByPath`) + resolve via `TTypeAtResolver` (qualifier `TGroup.` -> the `Create` member), only overriding when `Resolved.Name = Ident`. Lock: `tests/autotest/run_hover_callsite.ps1` (RED->GREEN, 6/6 battery green).
> - **Hover BUG 2 -- callers pollution + ~20s FREEZE (`src/delphi-plugin/DragLint.Plugin.Editor.pas` FetchHoverCallers):** `find-callers --name Create` over the 2.2M-sym library scanned by name -> 200+ callers of UNRELATED Creates AND a multi-second main-thread freeze. Resolved call_edges (`reverse-calltree`) are TOO LOSSY here (miss qualified-ctor sites; mis-resolve generic `TObjectList<T>.Create`). FIX: stay on the NAME index but (a) DROP library DBs from the caller search (path contains `library-`) -> 0.5s not 20s; (b) keep only rows whose source line is qualified by the target's own class (`ClassQual` = last-two qname segments, e.g. `TGroup.Create`) + dedupe by (file,line); (c) fall back to unfiltered project rows if the class-qualified filter is empty (free fn / instance-var calls). Result for TGroup.Create: exactly the 7 real ParseGroups sites (96/102/108/114/116/123/131), no other Creates.
> - **Hover BUG 3 -- structured popup showed NO analysis facts:** `hover --format json` (what the colored popup consumes) never emitted facts (only `--format md` did). FIX: `DRagLint.Hover.Renderer.RenderHoverJson(AModel, AFactLines)` now emits a `"facts":[...]` array; `DoHover` (CLI.pas) computes FactLines ONCE (shared FormatPhase2FactLines) for both json+md; plugin `FetchHoverModel` parses `facts` into new `TDragLintHoverModel.Facts`; `RenderModel` (HoverForm.pas) renders a section. Verified json carries facts.
> - **Hover BUG 4 -- popup ignored the DARK IDE theme (attempt v2, WORKS):** v1 used process-global `TStyleManager` which the RAD Studio theming engine does NOT touch. FIX (`HoverForm.pas` `ThemedColor`): pull the IDE's OWN active StyleServices via `IOTAIDEThemingServices.GetIDEStyleServices` + `GetSystemColor(clWindow/clWindowText)`; applied to the form + the two `StyleElements:=[]` children (FBody/FCallers). User CONFIRMED dark popup now renders.
> - **Docs:** `docs/INDEX-SCHEMA.md` -> v18 (new section 2.15 `symbol_facts`, refreshed ORM3 counts); `docs/INBOX-index-schema-v18-reindex-for-converter.md` (message to the component-converter workstream: accept schema 18, re-resolve by qname since symbol_ids were reassigned, prop_access now populated).
>
> **BUILD/DEPLOY recipe (proven this session):** CLI exe = `build/build_draglint_win64.bat` (compiles src/cli + copies to `third_party/dll-win64/drag-lint.exe`). Plugin BPL = `build_plugin_win32.bat` (dclDragLintWizard.dproj -> `third_party/dll-win32/*.bpl`). Both via PowerShell `Start-Process -Wait` + log; require `0 Error(s)`. **IDE must be CLOSED to deploy** (LSP `drag-lint.exe` + `bds.exe` lock the exe/BPL). The tree-sitter self-lint PostToolUse hook reports FALSE "parser-error" on generic method calls (`GetValue<T>`, `TryGetValue<T>`) -- TRUST dcc32/dcc64. **TRAP HIT TWICE this session: a `{ }` block comment containing `{`, `}`, or `...` breaks the parser (comments don't nest) -- use `//` for any comment mentioning JSON shapes/braces.**
>
> **>>> NOT DONE -- 5 hover-polish items (user-requested 2026-07-24; implement after /clear):**
> 1. **Popup SIZING (`HoverForm.pas`, the structured `ShowAt(AModel,...)` overload -- the SECOND ShowAt).** (a) TOP body must be TALLER (it scrolls for normal content -- inconvenient); raise the body min/max height. (b) BOTTOM callers grid can also be taller (current CallersH clamp 60..200 -> raise max ~300). (c) WIDTH: the callers grid has 3 wide columns (Unit 260 / Line 55 / Code 620) -- enforce a MINIMUM popup width (~640px) for the structured/menu popup so a NARROW signature does not shrink it below the grid's needs. (Dwell popups size-to-content by design; keep that, but floor the width when callers are shown.)
> 2. **Instance-member resolution on GENERIC/ALIAS types (HARD -- the deep one).** Hovering `ATokens.Count` (ATokens: `TTokenList` = `TList<TToken>`) mis-resolves to `YadfMain.BatchFormat.Count` (an arbitrary local). Root: `TTypeAtResolver` resolves LHS type = TTokenList but `Count` is INHERITED from the generic base `TList<T>` (not a direct child of the alias) -> returns the owner TYPE -> HandleHover's guard `Resolved.Name=Ident` rejects it -> falls back to `Symbols[0]` (wrong). Also why "our info is much less" than the IDE (IDE shows `property TList<YADF.Tokens.TToken>.Count: Int64`). FIX DIRECTION: when TTypeAtResolver lands on the owner type (member inherited/generic), walk the type's ancestry + generic base to find the member (reuse the `proptree` ancestry-bridge in `DRagLint.Convert.PropTree`), resolving `Count` -> `System.Generics.Collections.TList<T>.Count` in `library-Win64`; then render its real signature. NOTE: the caller filter for instance-member access (`x.Count`) also can't use the class-qualified heuristic -- it correctly falls back today (showed 142 legit `.Count` uses); proper scoping needs the D5 resolved-reference milestone. This item overlaps the D5 indexer work -- consider brainstorming/spec before coding.
> 3. **Rename the popup "FACTS" section header** (`HoverForm.pas` RenderModel, the `Emit('FACTS', ...)` line). User suggested `USAGE`; but the content is complexity/reads/writes/sql/handles/ownership/covered-by -- `ANALYSIS` or `DETAILS` may fit better. CONFIRM the label with the user, then it's a 1-word change.
> 4. **[DONE -- data gathered] Rich-facts screenshot examples.** YADF has ONLY complexity facts (free-fn formatter; no SQL/DFM/class-fields) -- best is `YADF.Layout.ReindentByDepth` (Complexity 98 cyclomatic, 465 lines). For MULTI-fact richness use ORM3: `uPipeSessionBuilder.TPipeSessionBuilder.HandleComputeSchedule` (SQL reads FOLDERS/GINSP/IINSP/...; writes GINSP/IINSP/INSPRSLT/...; cyc 41) or `VARINSP.TVarInspDlg.sgr_ReadingsDoneEdit` (cyc 174 + many Reads + many Writes + Handles: sgr_Readings.OnDoneEdit).
> 5. **Then:** user wanted to /clear before implementing 1-3 (this handoff). After clear, brainstorm item 2 (hard), knock out 1+3 (mechanical), rebuild BPL (+CLI only if item 2 touches it), deploy with IDE CLOSED, user verifies live.
>
> **GOTCHAS for a cold start:** (1) IDE must be CLOSED before any deploy (exe/BPL locked by LSP/bds). (2) `{ }` comments can't contain `{`/`}`/`...` -- use `//`. (3) self-lint hook lies about `GetValue<T>` generics -- trust dcc. (4) YADF.sqlite is NOT in the manifest (`third_party/dll-win64/drag-lint.json`) -- it's a separate index (call_edges quality is limited; qualified-ctor calls + generic members under-resolve = the D5 gap). (5) `.pas`/`.dfm` strict 7-bit ASCII + CRLF + DocInsight on new public decls. (6) full deep reasoning for this session (why reverse-calltree was rejected, the heuristic trade-offs) -> wiki `entities/DragLint_Linter-reasoning-2026-07-24.md`.
>
> ---
>
> ## RESUME 2026-07-22 (LATEST-61) -- **AUTO-DOCUMENT PHASE 2 (analysis facts) COMPLETE.** All 10 tasks + 4 fix waves + final opus whole-branch review, every review clean. Feature is DONE. THEN the recurring pre-existing `FindDocRegionAbove` doc-corruption bug (below) was FIXED (`7c551f1`, systematic-debugging + TDD, reviewed clean). main=`7c551f1`, origin=`f434769`, 17 UNPUSHED (2 pre-existing docs + 14 Phase-2 feat/fix + 1 doc-corruption fix; USER HOLDS PUSH).
>
> **WHAT SHIPPED:** six *analysis* facts rendered in BOTH the `document` managed block AND `hover`:
> - **Complexity** `Complexity: N (cyclomatic), M lines` -- shared `TAstChecker.CyclomaticOf`; render-time threshold `docs.complexity_min` (default 10, in the manifest `docs` section; applied at RENDER so changing it needs NO reindex).
> - **Reads/Writes** `Reads: a   Writes: b` -- own-class instance fields (assignment-LHS + Inc/Dec = write). Limitation: var/out-param writes NOT detected; own-class only (not inherited).
> - **Covered by** `Covered by: A, B (+N more)` -- test methods (unit `*Test`/`Test*` OR `TTestCase` ancestry) that transitively call the routine; computed LAZILY at doc/hover time (always fresh).
> - **Handles** `Handles: Button1.OnClick` -- the paired `.dfm` event a published method is wired to.
> - **SQL** `SQL: reads A; writes B` -- tables from SQL string literals (FROM/JOIN read; INSERT/UPDATE/DELETE write); best-effort, dynamic/subquery/CTE skipped (absence over a wrong table).
> - **Owns returned** `Owns returned: new (caller owns)|borrowed|self` -- conservative escape analysis; emitted only when all return sites unanimously agree (else omitted).
>
> **ARCHITECTURE:** new `symbol_facts` table (SQLite schema **v17->v18**, `ON DELETE CASCADE` invalidation, gated by a `>=` version check so old DBs degrade gracefully = facts absent/lines omitted). 5 facts materialized at INDEX time by `TSymbolFactsAnalyzer.Analyze` (AST via `TAstParseCache.Get(AFilePath)` -- a memoized 2nd parse per file); covered-by computed LAZILY. `TDocFactsBuilder.Build` assembles a `TDocFacts`; ONE shared `TDocRegions.FormatPhase2FactLines` renders the lines for BOTH `document` (`RenderFactsBlock`) and `hover` (`RenderHoverMarkdown` via `DoHover`/`HandleHover`) -> they cannot drift.
>
> **COMMITS:** T1 `608753f` (symbol_facts + Get/Put) / T2 `cd3d061` (index-time hook + cascade invalidation) / T3 `43e8a05` (Complexity) / T4 `73e66bd` + fix `25a821f` (Reads/Writes + root-cause identity resolution) / T5 `e665cdb` (Covered-by, lazy) / T6 `23e94b6` (DFM) / T7 `db1f7c2` + fix `aa986c2` (SQL + conservative extraction) / T8 `d76fcb6` + fix `781263a` (Ownership + false-`new`/record gate) / T9 `5b5144f` (hover + shared formatter) / T10 `1449b47` (benchmark + docs) / final-review fix `ac3b661` (SQL prose gate + ownership RTL-record exclusion).
>
> **VERIFICATION:** full autodoc+hover battery **31/31 GREEN** @ `ac3b661`; index-cost benchmark **1.47x** (this repo's src/, before/after) -> always-on decision VALIDATED, no opt-in gate filed. Final opus whole-branch review = "merge with fixes"; both Important wrong-fact findings (SQL prose false-positives like `'Update complete...'`->writes COMPLETE; ownership `borrowed` on unindexed RTL records like TRect) were FIXED in `ac3b661` + re-reviewed clean. NO Critical anywhere.
>
> **CONTROLLER DEVIATIONS from the plan (all sound; full rationale in the SDD ledger `.superpowers/sdd/progress.md`):** (a) covered-by is LAZY not index-time (a reverse test->target edge is non-deterministic if computed per-file at index -- code file indexed before its test file yields empty); (b) `DRagLint.Parser.Sql` is a DDL parser for MS*.SQL schema files and CANNOT extract DML tables -> a net-new conservative DML extractor was built; (c) var/out-param field WRITES deferred + the `?` uncertainty marker dropped (needs cross-file callee param-mode resolution vs the bounded always-on mandate; under-reports, never wrong; within the plan's own tested contract); (d) ownership renders `Owns returned:` not the spec's illustrative `Returns:` (avoids colliding with the Phase-1 mined `Returns:` line); (e) `TSymbolFacts` record lives in `Core.Model` + `Analyze` takes `AFilePath` (avoids a circular unit dependency + reaches the AST cache).
>
> **NEXT (USER steps -- the feature is complete):** (1) **PUSH** the 16 commits when ready (includes the 2 pre-existing doc commits). (2) **VERIFY hover facts in a LIVE IDE** -- the LSP `HandleHover` path is autotest-uncovered (the battery only drives the CLI `hover --qname --format md`); restart the LSP so the plugin spawns the new exe, then hover a documented symbol. (3) **REINDEX live indexes** so `symbol_facts` populates for real code (facts are index-time -> a routine shows no fact lines until its file is reindexed with the v18 exe; this is absent-not-wrong). (4) **VERSION bump + release** -- still `1.2.1-alpha` (`src/cli/DRagLint.CLI.pas:6`); the bump + pack-release is a separate step as in Phase 1.
>
> **FAST-FOLLOWS (non-blocking; candidates for a follow-up session/tickets):**
> - **[FIXED `7c551f1`] RECURRING PRE-EXISTING BUG -- `FindDocRegionAbove` doc-block collapse** (both copies: `Core.Indexer.pas` + `Doc.Document.pas`). Surfaced INDEPENDENTLY by T6 and T7: its gap-tolerance (`AAllowGap=1`) checked only line-number distance, NOT whether an intervening line is another declaration -- so two back-to-back declarations with no blank line, where only the FIRST has a managed doc block, made the SECOND misattribute and the first's block collapse on the next `document --apply` (the RED repro showed it deleted ProcA's actual DECLARATION LINE, not just its comment). FIX (systematic-debugging + TDD, reviewed clean): added a sorted `ASymStartLines` param to both copies; a candidate region is REJECTED when any symbol start-line lies strictly between the region's EndLine and the target's StartLine (an intervening declaration). Callers pass start-lines (indexer from `ParseRes.Symbols`; `Doc.Document` via `AStore.FindSymbolsByFile(Path)`). Legit blank-gap docs still attribute (blank lines aren't symbol start-lines) -> no duplicate blocks. Lock: `tests/autodoc/run_doc_adjacent_decls.ps1` (14 checks, RED->GREEN); full doc battery 29/29. MINOR follow-up: the intervening scan restarts per symbol (O(N^2) worst-case, early-exit bounded; harmless in practice) + a comment slightly overstates "bounded".
> - `docs/INDEX-SCHEMA.md` is STALE (still documents schema v17, no `symbol_facts`) -- refresh to v18.
> - DRY: extract a shared `BuildOwnFieldSet(store, parentId)` (dup'd in `AnalyzeReadsWrites`/`AnalyzeReturnsOwner`) and build the routine var-table once per `Analyze` (currently twice).
> - Add a hover/doc consistency fixture covering all 6 facts (currently 2 of 6 are consistency-asserted; the other 4 rely on the structural single-formatter guarantee).
> - Optional T4 hardening: detect var/out-param field writes (deferred deviation (c)).
>
> **GOTCHAS for a cold start:** (1) facts are INDEX-TIME (except covered-by) -- reindex after any `document --apply` (line shifts) or source edit, else stale/absent. (2) `--jobs` spawns SEPARATE CHILD PROCESSES (not threads) -- verified this session -- so the module-level memo caches (`TAstParseCache`, the DFM cache) can't race. (3) `.pas`/`.dfm` strict 7-bit ASCII + CRLF + no BOM; build `build/build_draglint_win64.bat` (PowerShell `Start-Process -Wait`, `BUILD_EXITCODE=0`); no sqlite3 -> `C:\Python314\python` (`?mode=ro`); autotests take `-Exe`, stderr-banner-sensitive. (4) the tree-sitter self-lint PostToolUse hook reports FALSE errors on generic-heavy `.pas` -- trust dcc64/the build. (5) USE THE INDEXER (drag-lint query on the self-index), NOT Grep, for Delphi symbol lookups (user re-flagged mid-session). (6) SDD ledger with the full per-task record (every deviation, every minor, every review verdict) is `.superpowers/sdd/progress.md` (git-ignored scratch).
>
> ---
>
> ## RESUME 2026-07-22 (LATEST-60) -- **HANDOFF for /clear. Fixed a source-corrupting `document --apply` bug + 4 autodoc/hover items, shipped v1.2.0-alpha AND v1.2.1-alpha, repaired YADF, then DESIGNED + PLANNED Auto-Document Phase 2 (analysis facts). NEXT = IMPLEMENT Phase 2 per the committed plan. main=`2556cc3`, origin=`f434769`, 2 UNPUSHED (spec+plan docs; user holds push).**
>
> **>>> NEXT ACTION (post-clear): IMPLEMENT Auto-Document Phase 2 via superpowers:subagent-driven-development.** READ FIRST: spec `docs/superpowers/specs/2026-07-22-autodocument-phase2-analysis-facts-design.md` (APPROVED) + plan `docs/superpowers/plans/2026-07-22-autodocument-phase2-analysis-facts.md` (10 tasks). Build the index-time `symbol_facts` layer + 6 analysis facts (cheap->hard): T1 table+Get/PutSymbolFacts plumbing / T2 index-time analyzer hook+invalidation / T3 Complexity (cyclomatic+LOC, reuse `Analysis.Cfg`) / T4 Reads/Writes fields (reuse `Analysis.DataFlow`) / T5 Covered-by-tests (reuse `Report.RCallTree`) / T6 DFM event wiring (reuse `PairDfmSiblings`+`Parser.DFM`) / T7 SQL tables touched (reuse `Parser.Sql`) / T8 returned-object ownership (conservative escape; absence-over-wrong) / T9 hover surfaces the facts + shared `TSymbolFacts->TArray<string>` formatter (doc+hover single source) / T10 library-reindex benchmark + docs + CHANGELOG. Each fact task is TDD (fixture -> index -> `document --unit --apply` -> assert the rendered line; REINDEX after build because facts are INDEX-TIME).
>
> **DECISIONS (from the 2026-07-22 brainstorm, in the spec):** (1) ALL 6 facts this increment, cheap->hard, ownership LAST. (2) ALWAYS-ON at index time (no opt-in flag) -- even library corpora; analyses must be bounded/single-pass; T10 benchmarks the cost, opt-in gate is a future fallback only. (3) Ownership CONSERVATIVE: emit only unanimous `new`/`borrowed`/`self`, else omit. Architecture: new `symbol_facts` table keyed by symbol_id, materialized in the indexer, read by BOTH `TDocFactsBuilder` (doc) and `BuildHoverModel` (hover) via a cheap SELECT so hover stays fast.
>
> **WHAT SHIPPED THIS SESSION (all on main; the 6 code commits are PUSHED via the v1.2.1 release, the 2 doc commits are unpushed):**
> - **THE headline bug: `document --apply` corrupted source with multi-line comments** (`5ebde68`). A hand-written multi-line `<summary>`/`<param>`/`<returns>` was emitted on one line with interior `\n` intact -> continuation lines lost their `///` -> broke the `///`-block -> a re-run injected/duplicated managed blocks (the YADF mess the user reported). Root cause: the parser keeps interior newlines (`CollapseWhitespace` collapses spaces/tabs, NOT `\n`) and `MergeComment` emitted them via a single `AppendLine`. Fix = new nested `EmitTagged` in `MergeComment` (src/doc/DRagLint.Doc.Regions.pas) re-prefixes every continuation line, at all 4 hand-typed emit sites (summary/param/stale-param/returns). Lock: `tests/autodoc/run_doc_multiline.ps1`.
> - **Item A** (`66022bb`): `Overload k of n` now covers FREE (unit-level) function overloads, not just methods (guard at `Facts.pas` cheap-fact block was `skMethod`-only -> added `skFunction`/`skProcedure`; method-facts resolve empty for free routines). Also dropped spurious self-`Calls:` from the routine's own `Name(` header line.
> - **Item B+merge** (`66022bb`): mined `Result:=` cases now show even alongside a HAND-WRITTEN `<returns>` -- as a managed `Returns:` fact line (tag preserved). Managed/empty `<returns>` still gets `Observed:` IN the tag; a generated `Observed:` tag is recognized as MANAGED on re-parse (StartsText 'Observed:') so it stays idempotent; the drift engine's Fresh render (Drift.pas:~532) mirrors the same `IncludeReturns` logic so a hand-returns block is not perpetually stale. Lock: `run_doc_returns_merge.ps1`.
> - **Items C+D** (`978dcd9`): hover markdown now shows `Returns (observed): ...` from the live-mined cases (`RenderHoverMarkdown` gained an `AReturnRhs` param; DoHover md path + LSP both pass it), AND `textDocument/hover` (`HandleHover` in LSP.Server.pas) disambiguates an overloaded name by CURSOR POSITION (decl line or impl span containing the cursor) instead of always `Symbols[0]`. Lock: md assertions added to `tests/autotest/run_hover_returns.ps1`. **D is LSP-only -> user must verify in a live IDE (restart the LSP so the plugin spawns the new exe).**
> - **Two releases:** `v1.2.0-alpha` (the earlier Phase-1/proptree/escaping bundle) AND `v1.2.1-alpha` (this session's corruption fix + A/B/C/D). Both PUSHED with GitHub releases + win32/win64 zips (pack-lint-release.ps1). VERSION const bumped to `1.2.1-alpha`; CHANGELOG dated. autodoc 19/19 + hover tests green on the Release exe.
> - **YADF REPAIRED:** the 8 corrupted `.pas` files in `C:\Projects\YADF` (branch `experiment/autodoc-format`) were `git restore`d to clean originals (verified the diffs were 100% doc-comment corruption, zero code changes). **User is re-working YADF; will re-run autodoc with v1.2.1 + check when it frees up.** Optional future: re-document YADF cleanly with the fixed engine.
>
> **GOTCHAS:** (1) 2 UNPUSHED doc commits (spec `75d567f` + plan `2556cc3`); user holds push -- they are LOCAL so the fresh session can read them without a push. (2) Phase 2 facts are INDEX-TIME: every fact test must REINDEX after building the exe (else no `symbol_facts` rows). (3) `document --apply` shifts lines -> reindex after (recurring stale-index trap). (4) `.pas` strict 7-bit ASCII + CRLF + DocInsight; build `build/build_draglint_win64.bat` (Start-Process -Wait, EXIT:0); no sqlite3 -> `C:\Python314\python` (`?mode=ro`); autotests take `-Exe`, stderr-banner-sensitive. (5) The tree-sitter self-lint (PostToolUse hook) reports FALSE "2 errors" on generic-heavy `CLI.pas` -- TRUST dcc64/the build, not the hook. (6) Plugin BPL version bumps SEPARATELY from the CLI (convention); item D reaches the IDE via the spawned CLI exe, no BPL rebuild needed. (7) SDD ledger location for the Phase 2 work: create under `.superpowers/sdd/` (git-ignored). Read the spec + plan FIRST.
>
> ---
> ## RESUME 2026-07-21 #2 (LATEST-59) -- **HANDOFF for /clear. WHOLE-PROJECT AUTO-DOCUMENT Phase 1 IMPLEMENTED + HARDENED (4 engine bugs) + 2 backlog bugs fixed + full reindex + YADF experiment + TODO removed + the IDE menu now SELF-FRESHENS the index. main=`660c092`, origin=`faedcc6`, 18 UNPUSHED, user holds push.**
>
> **>>> NEXT ACTION (post-clear): user is TESTING the enhanced "Auto-Document Whole Project" IDE menu.** They reopen RAD Studio (new Win32 BPL loaded), run it on YADF (project `C:\Projects\YADF\YADF.dproj`, on branch `experiment/autodoc-format`), and confirm: the report shows reindex->document->reindex, and HOVER is correct immediately after (no manual reindex). Optional follow-ups the user floated: (1) a CLI equivalent `document --project ... --apply --reindex` so the self-freshening flow works outside the IDE; (2) push the 18 commits; (3) `run_smoke.ps1` is RED but it is NOT a bug -- it targets the STALE Win32 `third_party/dll-win32/drag-lint.exe` (v0.46 vs 0.86, predates the session) with FTS5-unavailable + LSP-timeout (rebuild that exe or bump the test's version expectation).
>
> **WHAT SHIPPED THIS SESSION (all on `main`, unpushed; every code change TDD'd + independently reviewed via subagent-driven-development):**
> - **Auto-Document Phase 1 (6 tasks):** T1 `d828d7f` manifest `docs` config {max_return_cases:6, max_callers:5} -> real `<returns>Observed:` + caller cap; T2 `04ef4f2` skip trivial Get*/Set* accessors (<=2-line) in BATCH modes (`--include-accessors` opt-out; `--qname` never filtered); T3 `741aa2f` cheap-fact group in the managed block (Overrides / Overridden by / Implements[name-based] / Overload k of n / abstract+virtual, via a DetectDeprecated-style source probe); T4 `4787ac2` Platform fact DEFERRED to Phase 2 (no per-symbol {IFDEF} guard in the index -- decision-gate); T5 `07cf0d4` IDE menu item; T6 `25dd867` docs+CHANGELOG. Config lives in `third_party/dll-win64/drag-lint.json` (GLOBAL beside the exe -> travels with it; the top-level `C:\Projects\.drag-lint.json` has no docs section so the per-field merge keeps 6/5/2). Engine: `src/doc/DRagLint.Doc.Facts.pas` (TDocFacts + TDocFactsBuilder.Build), `src/doc/DRagLint.Doc.Regions.pas` (RenderFactsBlock/MergeComment), `src/cli/DRagLint.CLI.pas` (DoDocumentUnit/Project/All), `src/doc/DRagLint.Doc.Batch.pas`.
> - **Fix wave 1** `b55a3ac`: the T5 menu omitted `--db` (would fail "Database not found"); fixed to `document --project ... --apply --db <GetActiveProjectDb>`; also corrected a stale abstract/virtual comment.
> - **Fix wave 2 (4 PRE-EXISTING engine bugs the final opus review surfaced; user authorized):** A=`130de3b` overload doc-block STACKING on `--apply` (BuildFor resolved overloads by qname->Syms[0]; fix = new `TDocumenter.BuildForSymbol(ASym)`, batch loop passes the row's symbol). C=`e164f46` spurious self-referential `Called from:` on EVERY class (FindUnresolvedNameCallers matched a class's own method-header type_use ref) -- **plus its CRITICAL NULL regression** `4152a23` (my SQL `NOT (x IN(..))` dropped legitimate unit-scope callers when enclosing IS NULL; the reviewer CAUGHT it; fix = `AND (s.parent_id IS NULL OR s.parent_id NOT IN(..))`). D=`aba46bf` the SAME self-ref leaking into `Used in units:` via the SHARED FindCallersByName (rename/lint/LSP need its self-refs) -> LOCAL post-filter in the "Used in units" gather (NOT the shared fn). B=`a1641d2` overloads got the WRONG impl body's `<returns>` (SetRoutineImplRange attached by name+source-order) -> signature-match (ProcSignatureOf) with byte-identical fallback. `tests/autodoc/run_document_unit.ps1` + `run_document_project.ps1` are now GREEN.
> - **2 backlog bugs:** rename double-rename `5317bbd` (`t.DoIt;` emits TWO refs at the same pos [call + member-access, ref-gap G]; both applied -> DoItNowNow; fix = dedupe TRenameEdit by (path,line,col) in Build); config F2613 `77358e1` (drag-lint-config.dproj missing `..\preprocess` search path).
> - **TODO removal** `395fe19`: generated DocInsight no longer emits `TODO:` text (it tripped drag-lint's own TODO lint rule). Empty placeholders + `<returns>Observed:` only; `IsManagedDesc` sentinel still recognizes empty AND legacy `TODO: describe.` so re-runs SELF-HEAL old TODO docs. NON-VOLATILE-DESCRIPTION model CONFIRMED working: hand-written `<summary>`/`<param>` descs + `<remarks>` prose OUTSIDE the `<!-- drag-lint:auto -->` fence are preserved; only the fenced facts regenerate.
> - **Auto-Document IDE menu SELF-FRESHENING** `660c092` (`src/delphi-plugin/DragLint.Plugin.Editor.pas` `InvokeAutoDocumentProject`): now runs, through the LSP-safe JOB QUEUE (OnPreRun STOPS the LSP so the reindex can take the DB WAL lock -- a live LSP would corrupt it), a temp-.bat 3-step: `index` (INCREMENTAL: mtime/sha auto-detects stale/absent, re-parses only those, creates DB if missing) -> `document --apply` (shifts lines) -> `index` again (re-freshen so hover/lint/LSP stay correct). Uses `GetActiveProjectPlatform`. Win32 BPL REBUILT (0 err, deployed `third_party/dll-win32`).
>
> **REINDEX:** full `index --all` of all 9 manifest sections done (~2.5h; Library[Win32] 2.24M + Library[Win64] 2.17M dominate; the only "errors" were the repo's intentional broken-syntax test fixtures). All corpora now reflect the fixed parser (Bug B). YADF+YADFOT indexed ad-hoc: `C:\Projects\YADF\YADF.sqlite` (Win64), `YADFOT.sqlite` (Win64), `YADFOT-Win32.sqlite` (Win32) -- all v17.
>
> **GOTCHAS:** (1) **STALE INDEX AFTER DOCUMENT** is the recurring trap -- `document --apply` inserts comments and SHIFTS line numbers, so the index goes stale (hover/refs point at wrong lines) until reindexed; the new menu self-brackets with reindex, but a CLI `document` does NOT -- always reindex after a CLI doc run. (2) 18 UNPUSHED on `main` (user holds push). (3) tracked-dirty build artifacts (`dclDragLintWizard.bpl`/`.dcp` Win32+Win64) + 2 PRE-EXISTING dirty reconcile docs (`docs/superpowers/.../2026-07-19-project-coherence-reconcile-*`) NOT mine. (4) SDD ledger for this session = `.superpowers/sdd/progress.md` (git-ignored; briefs/reports prefixed `adp1-*`/`adp1-bug*`). (5) YADF work is on branch `experiment/autodoc-format` in the SEPARATE `C:\Projects\YADF` repo (YADF+YADFOT share it); its pre-existing WIP `YADFSetup.dproj`+`build_all.bat` were preserved. (6) `.pas` strict 7-bit ASCII + CRLF; console build `build/build_draglint_win64.bat`, plugin build `build_plugin_win32.bat` (IDE CLOSED for the BPL lock).
>
> ---
> ## RESUME 2026-07-21 (LATEST-58) -- **HANDOFF for /clear. The PROPTREE ASSIGNABILITY ENGINE (V17 / proptree/2) SHIPPED + PUSHED + the corpus is LIVE. Then WHOLE-PROJECT AUTO-DOCUMENT Phase 1 was brainstormed -> spec'd -> planned. NEXT SESSION = IMPLEMENT Phase 1. main=`03be2dd`, origin=`faedcc6`, 2 UNPUSHED (spec+plan docs; user drives push).**
>
> **>>> NEXT ACTION (post-clear): IMPLEMENT the whole-project auto-document Phase 1 plan via superpowers:subagent-driven-development.** Plan: `docs/superpowers/plans/2026-07-21-whole-project-autodocument-phase1.md` (6 tasks + an operational YADF/YADFOT follow-on). Spec: `docs/superpowers/specs/2026-07-21-whole-project-autodocument-phase1-design.md`. Tasks: (1) enable real `Result:=` returns + cap "used in" callers@5 via a manifest `docs` section [CONFIG, no new engine code -- the return-miner ALREADY exists, just gated off]; (2) skip trivial <=2-line property accessors in BATCH modes only (`--include-accessors` opt-out; `document --qname` NEVER filtered); (3) cheap fact group in the managed block -- overrides/overridden-by, implements, overload set, virtual/abstract; (4) platform fact BEST-EFFORT (decision-gate: implement only if cheaply index-derivable, else defer to Phase 2); (5) IDE menu item "Auto-Document Whole Project..." under drag-lint->Generate&&Export (spawns `document --project --apply`, apply-DIRECTLY-with-backup per user); (6) docs+CHANGELOG.
>
> **WHAT AUTO-DOCUMENT IS (user clarified):** 100% Delphi, NO AI, facts-only. `document --project <X.dproj> --apply` writes managed `<!-- drag-lint:auto -->` DocInsight (params/returns/`Called from:`/`Calls:`/`Raises:`/seealso) into every public decl of the project's compile closure -- ALREADY EXISTS as a CLI verb; the gaps were (a) not in the IDE menu, (b) `<returns>` showed TODO (miner gated off) + trivial accessors add noise. Engine facts layer: `src/doc/DRagLint.Doc.Facts.pas` (TDocFacts + TDocFactsBuilder.Build) gathers, `src/doc/DRagLint.Doc.Regions.pas` (RenderFactsBlock ~line 137) renders. Return-miner = `MineReturnExpressions` in `src/cli/DRagLint.Hover.Returns.pas` (SAME one the HOVER POPUP uses); `TDocFacts.ReturnCases` capped by `Opts.MaxReturnCases` <- `LoadDocMaxReturnCases` (manifest `docs.max_return_cases`; 0 when no docs section -> today's bare TODO). Document modes: `DoDocumentUnit`/`DoDocumentProject`/`DoDocumentAll`/`DoDocument` in `src/cli/DRagLint.CLI.pas` (~6578/6666/6693/6715). Menu build: `src/delphi-plugin/DragLint.Plugin.Editor.pas` SubGen (~4546, next to InvokeGenerateDocs).
>
> **PHASE 2 (DEFERRED, own spec next time): ANALYSIS facts** -- reads/writes fields (dataflow lattices), returned-object ownership (escape analysis), complexity (CFG cyclomatic + LOC), DFM event wiring, SQL tables touched, covered-by-tests -- via an INDEX-TIME facts layer (compute at index, persist, cheap SELECT) consumed by BOTH autodoc AND the HOVER popup (so hover stays fast -- the key architectural decision from the user's "would hover slow down?" question). User LIKED ALL of these.
>
> **PROPTREE ASSIGNABILITY ENGINE (V17) -- SHIPPED THIS SESSION (13 commits `0f187ab..faedcc6`, PUSHED to origin):** 8-task subagent-driven-development, opus final review READY-TO-MERGE (no Critical/Important). Per-leaf `is_writable`/`visibility`/`member_kind`/class-accurate concrete `type`; new `prop_access` col (`ro`/`rw`/`wo`, schema v16->17, migration-safe); `--min-visibility published|public`; convert-scaffold `--surface dfm|pas`; back-compat defaults (is_writable TRUE / visibility "" / member_kind property when absent). CORPUS: `library-Win32/Win64.sqlite` REBUILT v17 + SWAPPED LIVE (2.35M sym each; prop_access ro~88.7k/rw~79.5k/wo 365); OLD kept as `*.sqlite.bak` (rollback = reverse the rename). Verified end-to-end on real DevExpress (TcxCheckBox/TcxButton). Deployed exe `third_party/dll-win64/drag-lint.exe` = v17 (md5 6c1f72e0). Full SDD ledger: `.superpowers/sdd/progress.md` (git-ignored). Converter-team report LEFT at `C:\Projects\Delphi-RAG-lint-converter\docs\converter\2026-07-21-proptree-assignability-engine-v17-SHIPPED.md` (UNCOMMITTED on their `feat/converter-editor` branch).
>
> **GOTCHAS:** (1) 2 UNPUSHED doc commits (spec `4acf199` + plan `03be2dd`); user drives push. (2) The `document` verb REQUIRES schema v17 (guards on it) -- project DBs (ORM3 etc.) are still v16 -> reindex before documenting them; self-index already reindexed v17 this session. (3) The BATCH-mode accessor filter must NOT touch `document --qname` (explicit request always documents). (4) Menu = apply-DIRECTLY-with-backup (user chose; git branch is the safety net) -- do NOT add a preview/confirm step, do NOT pass `--no-backup`. (5) YADF+YADFOT (`C:\Projects\YADF\YADF.dproj` + `C:\Projects\YADF\YADFOT.dproj`) are NOT in the manifest index -> reindex v17 before documenting; the rollout is a git-branch experiment in the YADF repo (branch->autodoc->review->merge->ship YADF + drag-lint next versions). (6) Pre-existing DIRTY (NOT mine this session): `docs/lint/BACKLOG.md` (this file), `docs/superpowers/plans/2026-07-19-project-coherence-reconcile-plan.md` + `.../specs/...reconcile-design.md`, `third_party/dll-win64/dclDragLintWizard.dcp`. (7) `.pas` strict 7-bit ASCII + CRLF + DocInsight; build via `build/build_draglint_win64.bat` (PS Start-Process -Wait, EXIT:0); no sqlite3 -> `C:\Python314\python` (`?mode=ro`); autotests take `-Exe` + are stderr-banner-sensitive. (8) Deterministic NO-AI is a hard rule for ALL doc facts. (9) Engine BACKLOG (non-blocking) in `.superpowers/sdd/progress.md`: wo-vs-rw merge (for a future source-direction consumer), `(A.Kind='class')` helper consolidation, a couple test-fixture gaps.
>
> ---
>
> ## RESUME 2026-07-20 (LATEST-57) -- **HANDOFF before implementing the PROPTREE ASSIGNABILITY ENGINE. Three engine features SHIPPED this session (lint rule, unknown-type down-propagation, convert-apply cross-db fix -> engine NOW READY for the first component conversion). Next = IMPLEMENT the assignability engine per the committed spec+plan. main=`0f187ab`, origin=`dabd499`, 34 UNPUSHED (user holds push).**
>
> **>>> NEXT ACTION (post-clear): IMPLEMENT the proptree assignability engine.** Plan: `docs/superpowers/plans/2026-07-20-proptree-assignability-engine.md` (8 tasks, subagent-driven-development, no-re-index tasks 1-5 first, R1 extract+re-index tasks 6-7 last, doc-update task 8). Spec: `docs/superpowers/specs/2026-07-20-proptree-assignability-engine-design.md`. Editor-team handoff (evidence + consumer contract): `docs/lint/2026-07-20-proptree-assignability-engine-handoff.md`. **User steer:** all 4 work items (R1-R4) in ONE increment INCLUDING the re-index; R3 must be CLASS-ACCURATE (a `TcxButton` pool must NEVER contain `TcxCheckBoxProperties.*` leaves -- each class resolves its OWN most-derived concrete `Properties` type). **After implementation: update the index documentation (Task 8 -- user asked explicitly).**
>
> **WHAT THIS FEATURE IS:** make `proptree` (+ `convert-scaffold`) emit per-leaf ASSIGNABILITY so the ConvRulesEditor + scaffold only offer VALID assignment targets. Additive `proptree/1 -> proptree/2` JSON (back-compat: `is_writable` defaults TRUE, `visibility` `""`, `member_kind` `"property"` when absent). 4 items: R2 visibility (`--min-visibility published|public`; DFM=published, PAS=public), R3 concrete per-class type, R4 public fields as PAS targets, R1 writability (`prop_access` `ro`/`rw`/`wo` column -> needs re-index). VERIFIED via index this session: writability ABSENT (needs re-index); visibility + concrete-type + **71,047 public library fields** all PRESENT (R2/R3/R4 need NO re-index -- resolved the handoff's open R4 question). new col = `prop_access TEXT`; `is_writable = prop_access<>'ro'`.
>
> **PROJECT PURPOSE (load-bearing -- user clarified):** component replacement (Orpheus/BDE -> DevExpress/FireDAC) is ENGINE-DRIVEN and DETERMINISTIC -- the ConvRulesEditor (parallel team, `C:\Projects\Delphi-RAG-lint-converter`, `feat/converter-editor`) RECORDS rules; `convert-apply` APPLIES them; **NO AI in the conversion itself**. First target = `TabcToggleBtn -> TcxButton`. Preliminary rules: `C:\Projects\Delphi-RAG-lint-converter\docs\examples\convrules\sample.rules`.
>
> **SHIPPED THIS SESSION (all on main, unpushed):**
> 1. **`used-unit-not-resolvable` lint rule** (`20a6155` pure `ResolveUsedUnit`+alias/RTL tables / `4c5c6a1` walker reframe / `b125a40` RuleCatalog+CLI wiring / `cc1cfbf` fix). REFRAMED the old `unit-not-in-project` rule: flags `uses X` where X resolves to no known unit (project member / platform library / standard alias / RTL namespace), finding on the `uses` line, neutral message (comment/replace/add), no `.dproj` needed, `*_SERVER` skip kept, M2022 NOT a source. Subagent-driven; review caught+fixed a CRITICAL (dotted-namespace member normalization) + IMPORTANT (`_server` skip). Spec `docs/superpowers/specs/2026-07-20-used-unit-not-resolvable-lint-rule-design.md`.
> 2. **Lazy unknown-property-type DOWN-propagation** (`3b14e0d` test / `55cfe19` impl / `bff9bc1` cleanup). Completes `cddf48f`/`d6a1ab8`: on a query returning an unknown property type, resolve up-tree then PROPAGATE the recovered type DOWN across the queried class's ancestor+descendant closure onto every BARE occurrence (safety rule: never overwrite an explicit type), persist (both paths, not just bridge), return the real type. Fixed the stale `run_proptree_ancestry_bridge.ps1` (auto-write-back is the DEFAULT now; `--write-back` is NOT a valid flag). Reviewed READY-TO-MERGE; documented a bounded scope-ambiguity limitation. Spec `docs/superpowers/specs/2026-07-20-lazy-unknown-property-type-resolution-design.md`.
> 3. **convert-apply CROSS-DB + BARE-TAIL fix** (`3453fb4` test / `f4c6469` fix) -- **THE engine-readiness unblock.** Root-caused (systematic-debugging): (Bug2) `DoConvertApply` opened only the FIRST readable `--db` for the freshness guard + apply plan (CLI.pas `Break`), so a conversion whose From/To/instances live in different dbs (TabcToggleBtn=libWin64, TcxButton=libWin32, instances=ORM3) failed "not indexed" + "no instances". (Bug1) qualified `#convert` names matched no bare `.dfm` instances. FIX (Approach B = per-db iteration, first-resolve-wins, like the existing validation `TreeFor`; NOT a composite -- avoids cross-db symbol-id collisions) + bare-tail matching + a companion fix in `DfmReemit.pas`. VERIFIED on real VARINSP: qualified header now clean plan. Reviewed PASS. `AI-CONVERT-RUNBOOK.md` step 0 updated for cross-db.
>
> **PARALLEL SESSION (not me):** `9d54488`+`8e8c8f3` shipped post-resume-plan **item 1** (M2022 auto-resolve as a reference DB for ORM3 files, plugin-side + BPL rebuild). No overlap with my files.
>
> **THE convert-apply INVOCATION for TabcToggleBtn->TcxButton (needs THREE --db):** `drag-lint convert-apply --unit C:\Projects\DB\ORM3\CLIENT\VARINSP.PAS --rules <editor.rules> --db C:\Projects\DB\ORM3\drag-lint.sqlite --db C:\Projects\.drag-lint\library-Win64.sqlite --db C:\Projects\.drag-lint\library-Win32.sqlite [--only <name>] [--apply]`. Dry-run first; instances matched by bare type tail (bare or qualified `#convert` both work now).
>
> **GOTCHAS:** (1) 34 UNPUSHED, user holds push -- do NOT push. (2) **USE drag-lint INDEXER not Grep for Delphi symbols** (user feedback this session; self-index `C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite` was reindexed -- 580 files, current). (3) Deployed exe `third_party/dll-win64/drag-lint.exe` is CURRENT (md5 0d5b8c9, carries all 3 features) but is GITIGNORED (`*.exe`) -> deploy = copy only, no exe commit. (4) Pre-existing DIRTY (NOT mine this session): `docs/lint/BACKLOG.md` (this file), `docs/superpowers/plans/2026-07-19-project-coherence-reconcile-plan.md` + `.../specs/...reconcile-design.md` (prior session, offer to commit), `third_party/dll-win64/dclDragLintWizard.dcp` (parallel BPL rebuild artifact). (5) Full task-by-task history of this session's SDD work: `.superpowers/sdd/progress.md` (git-ignored scratch) + `task-*-report.md`. (6) `.pas` strict 7-bit ASCII + CRLF + DocInsight; build via `build/build_draglint_win64.bat` (Start-Process -Wait + log, EXIT:0, no `[dcc] Error`); no sqlite3 on PATH -> `python` (3.14). (7) OPEN follow-ups (non-blocking): lint-rule lib-DB-pick/IsLib test coverage; unknown-type non-bridged-persist + dead-end + descendant-idempotency asserts; convert-apply multi-#convert-pair type-selection test; platform name in the unresolvable-uses message.
>
> ---
>
> ## RESUME 2026-07-19 #2 (LATEST-56) -- **HANDOFF. TCompileChecker headless-compile FIX SHIPPED (`cf372f8`); then a deep investigation concluded a headless full-build is a DEAD END for Micronite2027 (so VARINSPCODE's `i` error needs the IN-IDE ghost-check, not headless). User pivoted: land the compile fix (done), handoff (this), and DEFER the conversion editor to a separate session. main=`cf372f8`, origin=`dabd499`, 18 UNPUSHED (user holds push).**
>
> **PROJECT PURPOSE (user clarified this session -- load-bearing context that reframes the whole compile chase):** Micronite2027 exists to CONVERT Micronite2022 from BDE -> FireDAC + Firebird. The user works UNIT-BY-UNIT: bring a 2022 unit into 2027 (ORM3\CLIENT), then convert it. So M2022 units are EXPECTED not to compile as-is (VARINSP etc. MUST be converted); headless-compiling them was never the goal. drag-lint's role here is to (a) surface what a brought-in unit still needs, and (b) let the user look up an unknown symbol's M2022 definition in the INDEX instead of grepping.
>
> **M2022 HANDLING (done this session, per user's instruction):** (a) REMOVED `C:\Projects\M2022` (root) AND `C:\Projects\SysTools\source` from the IDE Library Search Path for BOTH Win32+Win64 -- fully reverting this session's additions back to the original config (KEPT `C:\Projects\M2022\SVG\Skins`, a real skin resource the app uses). Why: M2022 app-units are being converted, so they must NOT sit on the compile path forcing source recompiles. (b) KEPT M2022 in the drag-lint SCANNED INDEX via a dedicated `C:\Projects\.drag-lint\M2022.sqlite`, BUILT this session (`drag-lint index C:\Projects\M2022 --db C:\Projects\.drag-lint\M2022.sqlite` -- it was configured in the manifest `scan.projects` but had NEVER been built, and `index --all --only M2022` did NOT build it -> a named-index-resolution bug to chase). PURPOSE: when a brought-in 2027 unit references an unknown var/type/used-unit, find its M2022 definition via `query --name X --db ...\M2022.sqlite` / `find-unit` / go-to-def -- NOT grep.
>
> **>>> POST-RESUME PLAN (what the user asked -- ordered):**
> 1. **Wire M2022.sqlite into query/LSP resolution for 2027 files.** Right now it's a standalone DB (queryable only via explicit `--db`). For the user's workflow (edit a 2027 CLIENT file -> hover/go-to-def finds the M2022 definition automatically), M2022.sqlite must be in the resolved DB set for ORM3\CLIENT files (`ManifestDbForFile`/`ResolveActiveIndexDbs` -- see `resolve-dbs --platform win32`, which currently returns ORM3+SQL+Loader+TableTools+DragLint+Graph+OCRPDF+library-Win32 but NOT M2022). Decide: add M2022 as an always-consulted "reference" DB, or make CLIENT resolution include it. ALSO fix why `index --all --only M2022` is a no-op so future reindexes work.
> 2. **Build the "used-unit-not-resolvable" SEVERE-WARNING lint rule** (user's idea; the single highest-value new feature for this conversion work). Flags `uses X` where X resolves to no known unit (project + libraries + RTL) -- exactly the signal for a brought-in unit that still uses Orpheus/BDE/onoffRecord and needs conversion. Would have flagged everything this session fought (ovctcmmn/onoffRecord/Bde.DBTables) with NO compile. Infra EXISTS: `unit_uses` table + lint-rule plumbing (RuleId + configurable severity) + `DoUsesAudit`/`uses-audit` (already builds a `stem->file_id` IndexedUnits map for UNUSED-units + interface->impl moves -- the new rule is a sibling flagging the UNRESOLVABLE case). Brainstorm the DESIGN crux FIRST (superpowers:brainstorming): (a) unit aliases (`WinTypes`=Winapi.Windows, `DbiTypes`=BDE) must be honored or it false-positives; (b) platform-conditional (`Bde.DBTables` Win32-only) -> per-platform verdict; (c) library-index coverage or real units get flagged. User's 3 downstream fix-paths per flagged unit: comment out / rename (Orpheus->DevExpress, BDE->FireDAC) / add to project. MVP = just MARK visible. Scope: catches bad UNITS, NOT bad IDENTIFIERS (those need the compiler).
> 3. **In-IDE ghost-check for real compiler diagnostics** on a brought-in-but-not-yet-converted unit (the ONLY reliable way to get e.g. VARINSPCODE's `i` error; headless full-build is a dead end -- see below). This is reconcile plugin Tasks 4-6 / the existing `LiveDiagnostics.pas` ghost-check.
> 4. **CONVERSION EDITOR (deferred -- likely a SEPARATE session per the user).** The visual component-conversion rule-authoring tool (TOvc*/BDE -> DevExpress/FireDAC). "Come back when we can safely convert dfm and pas." Keep it out of THIS thread.
>
> **THE FIX (`cf372f8`, TCompileChecker in src/diagnostics/DRagLint.Diagnostics.CompileCheck.pas):** TWO bugs blocked `TCompileChecker.Run` from ever compiling a `.dproj` with `--platform` (refresh-findings / reconcile `--db`). (1) **MSB6003 "filename too long"** -- `ResolveIdeLibraryPath` injected the full IDE registry Search Path (~5k chars, 90+ dirs); msbuild repeats it ~4x across dcc flags (-U/-I/-R/...), overflowing the ~32k Windows cmdline limit so dcc NEVER ran (0 findings, ~2s). FIX = MINIMIZE: existence-filter + drop RAD-baseline dirs (`\Embarcadero\Studio\37.0\`, already on dcc's path) + drop redundant `\source`/`\src` trees (compiled DCUs cover them; DevExpress's ~40 \Sources dominate) + 8.3-shorten (GetShortPathName) + dedup -> **~700 chars, dcc cmd ~29k, under the limit.** (2) **MSB4018 "Platform not supported:win32"** -- `Run` passed `/p:Platform=<verbatim>`; `--platform` arrives LOWER-cased but RAD's DCC msbuild task wants exact case (fails BEFORE dcc runs -- this MASKED whether MSB6003 was fixed). FIX = normalize win32/win64 -> Win32/Win64 before `/p:Platform` + the registry read. **VERIFIED e2e:** `refresh-findings --project Micronite2027.dproj --platform win32 --full` now runs a REAL 32s compile (**453 findings**) vs 0/instant-fail. **No regression:** `run_reconcile.ps1` 38/38, `run_fresh_findings.ps1` all pass (both use a bare `.dpr`, not the `.dproj`+platform path I changed). Encoding OK (ASCII+CRLF). FIX KNOWN-LIMITS: drops ALL `\source` dirs (so source-only libs like Orpheus/SysTools aren't injected -- moot here since headless is a dead end; fine for compiled-lib projects); Win64 vendor macros ($(DXVCL)) are blanked (a fuller expansion would reuse TProjectResolver).
>
> **THE DEEPER WALL (why VARINSPCODE's `i` STILL won't come from a headless full build):** with all paths present, a Win32 `--full` build (`/t:Build` = `-B`) FORCE-recompiles every unit from SOURCE, including STALE M2022 definition units (`FTRDEFS`,`FLDRDEFS`,`DMREADINGS`). `C:\Projects\M2022\FTRDEFS.PAS` refs `fldr_path`/`CharList_FileName` -- **CORRECTION:** I first thought these were "declared nowhere," but that was an artifact of M2022's ROOT being UNINDEXED (I only searched ORM3 + library-Win32). The new `M2022.sqlite` FINDS `fldr_path` in `uPathRoutines.pas:62`. So FTRDEFS's errors are missing-uses / needs-conversion, NOT dead code -- and the M2022 index now RESOLVES them (a clean validation of the user's "find it in the index, not grep" workflow). The headless-full-build conclusion still holds: the IDE resolves these via its warm DCU cache / the 2022 project's own uses-closure, but a `-B` recompile of the copied units in 2027's context stops on ~65 errors before reaching VARINSPCODE.pas. The IDE only builds via INCREMENTAL compile reusing a precompiled `FTRDEFS.dcu`; `-B` throws DCUs away. Win64 is not an option (no 64-bit BDE: `F2613 Bde.DBTables`). **So the reliable route to VARINSPCODE's `i` is the plugin's IN-IDE ghost-check** (single edited buffer compiled against the warm DCU cache -- LiveDiagnostics.pas/RunGhostCheckAsync; reconcile plugin Tasks 4-6). ALSO: this shows the reconcile design's "always-full recompile on any staleness" is RISKY for legacy projects (surfaces stale-external-source noise) -- worth revisiting toward incremental.
>
> **IDE CONFIG CHANGE (reversible):** added `C:\Projects\M2022` + `C:\Projects\SysTools\source` to `HKCU\Software\Embarcadero\BDS\37.0\Library\{Win32,Win64}\Search Path` (user's decision -- these legacy-lib dirs were on NO IDE path; before, only `M2022\SVG\Skins` was). To REVERT: remove those two entries from each key. (A backup JSON was written to the session scratchpad; it likely won't survive /clear, but the two dirs above are the entire change.)
>
> **GOTCHAS:** (1) 18 commits UNPUSHED, user holds push -- do NOT push. (2) The compile-fix commit is `cf372f8`; the prior session's option-A (platform param + first-cut injection, buggy) is `8150240` -- both unpushed. (3) HEADLESS-COMPILE DIAGNOSIS TIP (used heavily this session): refresh-findings hides the raw msbuild output -- to see WHY a build fails, REPLICATE the tool's exact command manually (`cmd /c "call rsvars && msbuild <dproj> /v:normal /t:Build /p:Platform=Win32 /nologo"` with `$env:DCC_UnitSearchPath` set to the injection) via PowerShell Start-Process; and to see what `ResolveIdeLibraryPath` produces, temporarily `TFile.WriteAllText` its Result to a file (that is how the platform-case bug was found). (4) The deployed `third_party\dll-win64\drag-lint.exe` is CURRENT (rebuilt this session, has the fix). Build recipe = `build/build_draglint_win64.bat` via PowerShell Start-Process -Wait + log (EXIT:0, no `[dcc] Error`; note the script's `copy` does NOT check errorlevel, so verify the deployed exe md5 matches `src\cli\Win64\Debug\drag-lint.exe` if a lock is suspected). (5) `.pas` strict 7-bit ASCII + CRLF; DocInsight on new public surface. (6) No sqlite3 on PATH -> `C:\Python314\python` (stdlib sqlite3, open `?mode=ro`). (7) Autotest runners take an `$Exe` param + are stderr-banner-sensitive; run them directly (`& '.\run_reconcile.ps1'`) with `$ErrorActionPreference='Continue'`, not via a nested `powershell -File`. (8) DB copies for compile testing are in the session scratchpad (`orm3-copy/verify.sqlite`); the real ORM3 index `C:\Projects\DB\ORM3\drag-lint.sqlite` was NOT written (all test compiles used copies -- avoids FTRDEFS-noise pollution).
>
> ---
>
> ## RESUME 2026-07-19 (LATEST-55) -- **HANDOFF for /clear. RECONCILE Phase 1 SHIPPED; then a deep investigation found WHY VARINSPCODE's `i` error still won't render = a BUILD-ENVIRONMENT gap (NOT the DB / index / reconcile feature). USER CHOSE OPTION A: next session implements the fix in `TCompileChecker`. main=`56fff5e`, origin=`dabd499`, 16 UNPUSHED (user holds push).**
>
> **>>> NEXT ACTION (option A): implement the headless-compile fix in `src/diagnostics/DRagLint.Diagnostics.CompileCheck.pas`.** Two parts: (1) add a compile-**PLATFORM** input to `TCompileChecker.Run` (currently it runs msbuild with NO `/p:Platform`, so it builds the `.dproj` default = **Win64**; Micronite2027 is a **Win32** app -- uses BDE `Bde.DBTables` + Orpheus `ovctcmmn`, both 32-bit-only -- so Win64 can't even resolve BDE); (2) **inject the IDE global Library Path** for that platform. Injection seam (clean, no `.dproj` edit): the `.dproj`'s `DCC_UnitSearchPath` ends with `;$(DCC_UnitSearchPath)`, so setting the **environment variable** `DCC_UnitSearchPath` before msbuild APPENDS the IDE paths. Read the path from registry `HKCU\Software\Embarcadero\BDS\37.0\Library\<Platform>\Search Path`, expand `$(...)` macros (from `HKCU\...\BDS\37.0\Environment Variables` + BDS built-ins), and -- CRITICAL -- keep it SHORT (the full ~4341-char path overflows the Windows cmdline limit -> `MSB6003 "filename too long"`, dcc can't run): prefer **compiled-DCU dirs** (e.g. DevExpress `...\Library\RS37` = 1 dir vs 40 source dirs), dedup vs the project's own path, drop non-existent dirs. Thread the platform from the reconcile / refresh-findings callers (`DoRefreshFindings` / `RefreshProjectFindingsCore` / the reconcile `--db` phase -- they have `AArgs.CheckPlatform`). Then re-run `reconcile-project --project <Micronite2027.dpr> --db <ORM3-root> --full` for **Win32** and confirm VARINSPCODE's `i` error (E2003, line 106) lands in the ORM3-root DB.
>
> **THE INVESTIGATION (systematic-debugging, all proven by manual builds -- see memory `project-micronite-headless-compile`):** drag-lint diagnostics come from a HEADLESS msbuild compile whose findings fill the DB the LSP reads (`C:\Projects\DB\ORM3\drag-lint.sqlite`, confirmed via `resolve-dbs`). That compile has NEVER succeeded for Micronite2027: (a) WRONG PLATFORM (Win64 vs the app's Win32/BDE/Orpheus -> dies at `Bde.DBTables`); (b) MISSING IDE library paths (DevExpress `dxBar`, Orpheus `ovctcmmn`, shared `C:\Projects\M2022\onoffRecord` -- none in the `.dproj`, all on the IDE registry Library Path); (c) full-path injection overflows the cmdline limit (MSB6003). PROOF: `Win32 + DevExpress(RS37 compiled) + Orpheus(Win32 Release)` compiled hundreds of units (real hints captured, e.g. `uJobList.pas H2077`) and REACHED VARINSPCODE -- so the `i` error IS capturable once all paths are present. `last_compiled_unix` is NULL for all 846 ORM3-root files = the sweep has ALWAYS failed here. The bug is a build-environment gap, ORTHOGONAL to the reconcile feature (whose INDEX side reindexed VARINSPCODE fine). The line-106 `i` error is real + unconditional (VARINSPCODE.pas lines 53-54 `//var` `//  i: Integer;` commented out; used at 106; no `{$IFDEF}`).
>
> **DB STATE:** VARINSPCODE reindexed/fresh (file_id 846), 0 compiler_findings, and the false `dxBar not found` finding that my Win64 reconcile briefly wrote was CLEARED (it was a false positive in the IDE). No drag-lint CODE changed for the investigation (manual builds only -- nothing to revert).
>
> **RECONCILE FEATURE Phase 1 = SHIPPED (4 commits `caea831`..`56fff5e`).** Per the user's design steer ("do it in the existing action"), the index/findings-coherence capability was FOLDED into the EXISTING `reconcile-project` verb as an opt-in `--db [--full]` phase -- NOT a new `reconcile` verb (which would have collided with `reconcile-project` + the existing `run_reconcile.ps1`). Surface: `reconcile-project <proj>` = report only (unchanged); `--apply` = edit the `.dpr` (unchanged); `--db <db> [--full]` = NEW, heals the DB index+findings, never edits the `.dpr`. Via superpowers:subagent-driven-development (fresh implementer + spec/quality review per task; final whole-branch review APPROVED, merge-ready). T1 `caea831` = `TReconcileResult.ClosureFiles` + `src/core/DRagLint.Project.Members.pas` (`PairDfmSiblings`). T2 `1a71a6b` = `ISymbolStore.GetFileMTime` + `src/core/DRagLint.Project.Coherence.pas` (`ComputeCoherence`/`IsIncoherent`, timestamp via `DateTimeToUnix(GetLastWriteTime,False)` matching the indexer). T3 `1e7e976` = factored `DoRefreshFindings` steps 5-9 into `RefreshProjectFindingsCore` (reused by refresh-findings + reconcile) + the `--db` coherence phase in `DoReconcileProject`. Fix `56fff5e` = gate the phase on `Length(AArgs.DbPaths)>0` (a review CAUGHT it firing on every no-`--db` call because `DbPath` defaults non-empty) + a negative test. CONTROLLER-VERIFIED first-hand: `run_reconcile.ps1` 38/38, `run_fresh_findings.ps1` all pass, CLI build EXIT:0.
>
> **NOT DONE / DEFERRED:** (a) [option A] the TCompileChecker platform+library-path fix above -- the immediate next task. (b) Reconcile plugin **Tasks 4-6** (buffer-change stamp in EditViewNotifier; coalesced `RequestProjectReconcile` R2 job; wire triggers at project-open + file-open-not-indexed; spawn `reconcile-project --project <p> --db <manifestDb> --full`, NO `--apply`) -- and note the plugin sweep/auto-reconcile will hit the SAME build-env gap unless it compiles Win32 with IDE paths, so option A is a prerequisite. (c) From LATEST-53: #5 dcc-tolerance into the default indexer (span-remap); await tree-sitter msg. (d) LSP `--no-write-back` on the shared index (auto-write-back contention).
>
> **GOTCHAS:** (1) 16 commits UNPUSHED, user holds push -- do NOT push. (2) UNCOMMITTED (mine, but SURVIVE /clear on disk -- /clear only clears the conversation, not the working tree): `docs/superpowers/plans/2026-07-19-project-coherence-reconcile-plan.md` + `.../specs/2026-07-19-project-coherence-reconcile-design.md` (the design-revision that the shipped reconcile commits already reference) + this `BACKLOG.md`. Offer to commit them next session. NOT mine (leave): `src/delphi-plugin/dclDragLintWizard.{dproj,res}` (pre-existing platform flip). (3) SDD ledger for the reconcile work: `.superpowers/sdd/reconcile-progress.md` (git-ignored scratch). (4) `.pas` strict 7-bit ASCII + CRLF; DocInsight on new public surface. (5) Build recipe: `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` + log (EXIT:0, no `[dcc] Error`). (6) No sqlite3 on PATH -> use `C:\Python314\python` (stdlib sqlite3, open `?mode=ro`). (7) A spurious final-review subagent once emitted a fake `System: abort` injection string -- treated as untrusted data; grep found it in 0 repo files; not a real finding. (8) The manual-build scratch logs are in `C:\TEMP\claude\...\scratchpad\` (proof_*.log) -- reference for the exact per-unit resolution order.
>
> ---
>
> ## RESUME 2026-07-19 (LATEST-54) -- **HANDOFF for /clear before implementing the PROJECT-COHERENCE RECONCILE feature. main=`bed7d23`, origin=`dabd499`, 12 commits UNPUSHED (user holds push). Design DONE (spec+plan committed); NEXT SESSION = IMPLEMENT Phase 1.**
>
> **>>> NEXT ACTION (post-clear): implement the reconcile feature, Phase 1, via subagent-driven-development. READ FIRST: `docs/superpowers/specs/2026-07-19-project-coherence-reconcile-design.md` (the invariant) + `docs/superpowers/plans/2026-07-19-project-coherence-reconcile-plan.md` (6 tasks). Tasks 1-3 (CLI `reconcile` verb) are the load-bearing fix and are independent of 4-6 (plugin); do 1-3 first.**
>
> **THE FEATURE (why):** the reported bug -- `C:\Projects\DB\ORM3\CLIENT\VARINSPCODE.pas` had NO DCC diagnostics -- root-caused (systematic-debugging) to a STALE index: the file was edited today but the ORM3-root `drag-lint.sqlite` (the DB the LSP reads, confirmed via `resolve-dbs`) had no `files` row for it, so compiler findings (keyed by `file_id`) could not attach/render. NOT caused by my changes. IMMEDIATE FIX APPLIED: incrementally reindexed VARINSPCODE.pas into ORM3-root (now file_id 846) -- user should save it / run Full Compile Sweep to populate findings. 3 sibling files still missing from ORM3-root (TakeJob.pas / sgBlockLibrary.pas / SelectData.pas) -- OFFERED to reindex, not yet done. The DURABLE fix the user asked for = the coherence feature: every project member always indexed + compiled + fresh, self-healing on any discovered staleness.
>
> **THE DESIGN (approved, in the spec):** new `drag-lint reconcile --project <X.dproj> --db <db> [--full] [--json]` verb -- enumerate members from the .dpr `unit in '<path>'` list (+ sibling .dfm), compute the incoherent set (indexed / index-fresh via mtime TIMESTAMP not sha / compiled-fresh via last_compiled_unix), incrementally scan missing/stale members + .dfm, and if any incoherent run a FULL recompile (reuse the refresh-findings engine) -- ALL into the manifest DB the LSP reads (`ManifestDbForFile`/`ResolveActiveIndexDbs[0]`). Plugin: one coalesced `RequestProjectReconcile` (R2 job queue, async, never blocks IDE) wired at project-open + module-added/file-open-not-indexed; a per-file buffer-change timestamp stamped in `EditViewNotifier.Modified`. KEY DECISIONS: always-full recompile on any staleness (user); NO auto-save (user -- WIP may be unsaved); in-buffer DCC comes from the EXISTING ghost-check (overlay unsaved buffer -> compile -> restore, LiveDiagnostics.pas/RunGhostCheckAsync), never by saving. Phase 2 (later): project-wide multi-buffer ghost-overlay build + more self-healing callers.
>
> **WHAT ELSE SHIPPED THIS SESSION (12 unpushed, all on main):** (1) `0e0b864` tree-sitter grammar DLL refresh -- JEDI/JVCL fixes `e531000` (nested-const subrange, `inherited At`, `Operator:` field); both prod DLLs rebuilt + verified (3 constructs parse clean) + 9 live copies refreshed. (2) Feature A -- ConvRulesEditor independent FROM/TO platform selection COMPLETE (`8dd7595` spec, `142cd76` plan, `be8b76a`/`f345f36`/`eb9e472`/`c6b0080`/`ea63be8` = 5 TDD tasks; 109 model tests pass; e2e launch w/ `--from-platform win32 --to-platform win64` OK; new `ConvRules.Platform` unit + `TEngineAdapter.SetDbs` + platform dropdowns w/ live re-scope). (3) `cddf48f` agent unknown-type ancestry-bridge (proptree: resolve `unknown` prop types by bridging type-alias ancestor edges e.g. `TcxButton.Align` unknown->TAlign; scope-aware, refuses to guess) -- REVIEWED + merged from a worktree + verified read-only on the real lib. (4) `d6a1ab8` made that write-back AUTOMATIC (proptree opens the index writable by default + memoizes; `--no-write-back` opts out; graceful read-only fallback on locked/RO DB; verified idempotent on an alias fixture).
>
> **OPEN / DEFERRED (not blocking):** (a) reindex the 3 sibling missing files into ORM3-root; (b) POSSIBLE INTERACTION to weigh: the auto-write-back (`d6a1ab8`) makes proptree open the shared ORM3 index WRITABLE, so LSP hover/context calls now take write locks on the DB the IDE holds open -- could contend with the plugin's finding-writes (SQLITE_BUSY -> best-effort skip); consider having the LSP pass `--no-write-back` on the shared index; (c) Feature B (text-value castability -- enum value-mapping, `TXAlign`->`TYZAlign` via text-value conversion rules) -- a separate brainstorm, deferred.
>
> **GOTCHAS:** (1) 12 commits UNPUSHED, user holds push -- do NOT push. (2) `.pas` strict 7-bit ASCII + CRLF -- verify after every Write/Edit. (3) TRUST dcc64 over the self-lint parser (tree-sitter parse-recovery false positives on generic-heavy code). (4) Autotest harness quirk: the exe prints `(loaded defaults...)`+`FTS5 probe` to STDERR; a runner with `$ErrorActionPreference='Stop'`+`2>&1` aborts on it (affects run_proptree/run_index_preprocess) -- new runners must redirect stderr to `$null`. (5) `.dpr` build recipe = `build/build_draglint_win64.bat` via PowerShell Start-Process -Wait + log (EXIT:0, no `[dcc] Error`); editor = `build/_build_convrules_editor.bat`; tests = `build/_build_convrules_tests.bat`. (6) Dirty-but-NOT-mine: `src/delphi-plugin/dclDragLintWizard.{dproj,res}` (pre-existing platform flip). (7) No sqlite3 on PATH -- use Python (`C:\Python314\python`, built-in sqlite3) to inspect DBs; open with `?mode=ro`.
>
> ---
>
> ## RESUME 2026-07-16 (LATEST-53) -- **HANDOFF before a machine REBOOT. The v1.2.1 preprocessor port (INBOX-tree-sitter-100-percent-v1.2.1.md, section 3 -- all 5 changes) is COMPLETE, plus a new all-Delphi corpus harness. main=`dabd499`, origin/main=`10728a3`, **6 commits UNPUSHED** (user holds push deliberately; the earlier 9 ConvRulesEditor/v1.2.1-DLL commits WERE pushed this session -> origin is at `10728a3`, not `5713ee6`). Build EXIT:0. Waiting on a tree-sitter-team message before continuing (their Delphi-preprocessor work, esp. #5 tolerance integration into the indexer).**
>
> **CONTEXT (verified this session -- do not re-confuse the two repos):** drag-lint runs its OWN **pure-Delphi preprocessor** at `src/preprocess/*.pas` (PP-Task-1..10, built week of 2026-07-06 per `INBOX-tree-sitter-preprocessor-adoption.md` -- the decision was to build a native preprocessor rather than spawn `node` per file). Pipeline: `EnsureUtf8Bytes -> Delphi Preprocess() -> full delphi13 DLL`, **on by default** (`--no-preprocess` opts out). The JS at `C:\Projects\tree-sitter-delphi13\preprocessor` (v1.2.1) is the **TEST-TIME ORACLE ONLY** (never shipped); `tests/preprocess/lib/render.js` calls it so each Delphi change is byte-diffed against it (oracle-diff). So the section-3 changes had to be HAND-PORTED into Delphi -- a DLL refresh does NOT deliver them.
>
> **THE 5 CHANGES (all committed):**
> - **#3 BOM** `26f8463` (mine): blank a leading UTF-8 BOM (`EF BB BF`) to 3 spaces at every recursion entry, offset-preserving. Delphi-only test (Node's readFileSync strips BOM). `tests/preprocess/run_bom.ps1` 6/6.
> - **#4 lexer quotes** `1f635b8` (mine): MASM `"..."` asm-string skip (byte 34) + both `'`/`"` skips line-bounded (byte 10) so a stray quote can't hide later `{$ENDIF}`. `run_asm_quotes.ps1` 10/10 (3 oracle-diffs).
> - **#1 include-define propagation** `c8b7b64` (mine): ALREADY satisfied (defines-only recursion shares the parent's define dict by ref; no `expand` mode here). Locked with a nested transitive test. `run_include_modes.ps1` 13/13.
> - **#2 nearest-first `{$I}` resolution** `99ef437` (mine): new `TPPOptions.NearSearch` + `TPPOptionsDefault` + process-lifetime `GSubdirCache` + widened `ResolveInclude` (baseDir -> its subdirs -> up to 3 parent levels each w/ subdirs) + CLI `--no-near-search`. `run_include_resolve.ps1` 14/14 (4 oracle-diffs).
> - **#5 dcc-tolerance pass** `260dd7d` (**landed from a PARALLEL session / tree-sitter team** -- "the JS preprocessor is now FULLY ported"): new `DRagLint.Preprocess.Tolerance.pas` + `TPPOptions.Tolerances` (opt-in). Rule A (final routine-directive group w/o `;`) + Rule B (`array[..] of T` last record field w/o `;`). `run_tolerance.ps1` PASS. **NOTE: tolerance INSERTS a `;` -- the design note in Types.pas says it does so by REPLACING one adjacent whitespace byte, keeping offset-identity. Verify that claim before wiring into the indexer.** Also `dabd499` = `CorpusScanDelphi` all-Delphi corpus harness (no JS in the pipeline).
>
> **VERIFICATION:** `build/build_draglint_win64.bat` (via PowerShell Start-Process -Wait) BUILD_EXITCODE=0, no `[dcc] Error`. Preprocess battery: **12/13 green** (`run_asm_quotes/bom/closure_preprocess/expr/full_grammar_gate/include_modes/include_resolve/lexer/oracle_corpus/preprocess_core/profile/tolerance` all PASS). The ONE fail = `run_index_preprocess.ps1` -- a **PRE-EXISTING harness quirk**, NOT a regression: the exe prints `  FTS5 probe: AVAILABLE` to stderr and the harness's `2>&1` + `-ErrorAction Stop` treats that banner as a terminating error. The file was last touched at `211b235` (original PP-Task-9 wiring); none of the 6 port commits touched it. (Fix later: drop `Stop`/filter the banner in that one harness.)
>
> **>>> DECISION (2026-07-17, user): ADOPT THE CURRENT DELPHI PREPROCESSOR AS CANONICAL NOW.** The **Library corpus** (per-platform library index) scans **100%** with the current pure-Delphi preprocessor -- good enough to INCORPORATE and CONTINUE WORK on. When the NEW tree-sitter grammar/preprocessor is ready it will be SWAPPED IN as a drop-in replacement. The tree-sitter team's full-code scan (still in progress) found **gaps in an ADDITIONAL FOLDER** -- NOTED and NON-BLOCKING (to be covered by the new tree-sitter later). The INBOX reply `INBOX-tree-sitter-preprocessor-fully-ported.md` confirms the port is done + canonical; its splice-class item (~12 include-body-splice files that fail the all-Delphi harness but pass JS -- EurekaLog/fibplus/Indy/Orpheus) is a **documented design choice** (Delphi port is defines-only for offset-identity; `expand` body-splice deliberately not ported), NOT a defect.
>
> **OPEN / NEXT:**
> 1. **PUSH** the **6** commits (origin=`10728a3`) when the user is ready (their call; they hold push). NOTE: the correct unpushed count is **6**, origin=`10728a3` -- an earlier draft of this note said "15 / origin=5713ee6", which was WRONG (the first 9 ConvRulesEditor/DLL commits were already pushed this session; the tree-sitter INBOX reply independently confirms 6-ahead).
> 2. **#5 tolerance into the DEFAULT indexer** is still opt-in only. Before enabling: confirm end-to-end that tolerance's `;`-handling preserves the offset-identity span-mapping (Types.pas claims it replaces a whitespace byte rather than inserting -- verify). Not required for the "adopt now" decision (indexing uses defines-only; tolerance stays opt-in until verified).
> 3. **Continue ConvRulesEditor follow-ups:** Hint-absent-on-TcxButton index/proptree gap (a real unresolved-ancestry omission -- `Hint` is a TControl property genuinely not surfaced); a real "target platform" setting/arg (currently Win64 hard-coded). Plus still-open from LATEST-46: TRANSFER EDITOR brainstorm; auto-refresh IDE display after Full Sweep.
>
> **GOTCHAS for a cold start:** (a) 6 commits UNPUSHED (origin=`10728a3`), user holds push -- do NOT push. (b) TWO repos, two preprocessors -- Delphi `src/preprocess/` is PRODUCTION, JS `tree-sitter-delphi13/preprocessor` is the test oracle only. (c) TRUST `dcc64` over the self-lint parser: the PostToolUse drag-lint hook reported "2 errors" on the generic-heavy #2 code that dcc64 compiled clean (tree-sitter parse-recovery false positives). (d) `.pas` strict 7-bit ASCII + CRLF -- verify after every Write/Edit (I checked lone-LF=0/non-ASCII=0 each time). (e) `run_index_preprocess` "fail" is the stderr-banner harness quirk, not the code. (f) Progress ledger: `.superpowers/sdd/pp-v121-progress.md`. (g) Dirty-but-NOT-mine: `src/delphi-plugin/dclDragLintWizard.{dproj,res}` (pre-existing IDE platform-flip).
>
> ---
>
> ## RESUME 2026-07-16 (LATEST-52) -- **Auto-Match ambiguity fix + bottom status bar + Hint answer (user report). NOW COMMITTED: this session's work is in 2 commits `e1dc67b` (tree-sitter v1.2.1 DLLs) + `10728a3` (all ConvRulesEditor fixes 48..52). main=`10728a3`, 9 commits UNPUSHED (origin=`5713ee6`; user holds push). Only dirty = pre-existing plugin dproj/res platform flip (NOT this session). Checkpoint via handoff.**
> 
> **Q: AllowAllUp/Down present in both classes, why not auto-picked?** ROOT CAUSE: `DoAutoMatch` matched by the LAST path segment and required exactly ONE castable candidate. DevExpress `TcxButton` nests the same sub-button props many times -> **14 leaves** whose last segment is `AllowAllUp` (`Colors.Button.AllowAllUp`, `SpeedButtonOptions.AllowAllUp`, `ViewInfo...AllowAllUp`, ...) -> nCand=14 -> ambiguous -> skipped. Same for Down/ShowHint/ParentShowHint. FIX: `DoAutoMatch` now does **PASS 1 = exact FULL-PATH match** (From.path == To.path -- unique: only 1 leaf has the exact path `AllowAllUp`), **PASS 2 = last-segment fallback** (only when no exact-path match), still requiring a unique candidate. Verified end-to-end: AllowAllUp/Down (Boolean/Boolean) + ShowHint/ParentShowHint (Boolean/unknown via LATEST-51 inference) all auto-match now.
> 
> **Q: TcxButton ShowHint/ParentShowHint = unknown type?** Same unresolved-ancestry cause as Align (TcxBaseButton unresolved -> VCL-inherited props lose type). LATEST-51's `ResolveUnknownTypes` already handles it (Boolean<-unknown -> Boolean identity); combined with the exact-path fix they now auto-match.
> 
> **Q: Does TcxButton have a Hint property? Why wasn't Hint matched?** ANSWER: `Hint` is **ABSENT** from TcxButton's proptree in the index (From TabcToggleBtn.Hint=string, To TcxButton has NO Hint leaf). So there is no target to map to -- not a matcher bug, the property genuinely isn't surfaced (likely an unresolved-ancestry omission, since Hint is a TControl property; a deeper index/proptree fix would be needed to surface it, out of scope here). Reported to user.
> 
> **Q: Can't see the bottom of the form / feels cut off -> add a status line there.** FIX: added a bottom **TStatusBar** (`FStatusBar`, SimplePanel, docked alBottom, created first so it reserves the bottom edge). `SetStatus`/`SetError` now mirror to it (errors prefixed `[!]` since SimplePanel has no per-message colour). The top status label stays.
> 
> **VERIFICATION:** editor `dcc64 -B` exit 0, tests **88 pass / 0 fail**, launch smoke OK, deployed. Auto-match proven via proptree data (AllowAllUp/Down/ShowHint/ParentShowHint -> match; Hint -> absent). UNVERIFIED = human clicking the live UI.
> 
> **FILES (uncommitted):** ConvRules.MainForm.pas (DoAutoMatch 2-pass, FStatusBar + SetStatus/SetError mirror). Cumulative with LATEST-48..51. Plus staged tree-sitter v1.1.2 DLLs. Watch loop STOPPED.
> 
> ---
> 
> ## RESUME 2026-07-16 (LATEST-51) -- **Three more ConvRulesEditor UX fixes (user report). UNPUSHED; all this session UNCOMMITTED.**
> 
> **(A) Selecting a rule row now mirrors its From/To into the top pickers.** A "Fill From-classes" row is From-only; there was no way to set its To. FIX: `LoadGridForBlock` sets `FCbFrom.Text := Node.FromType; FCbTo.Text := Node.ToType`. AND `DoNewConversion` now UPDATES the selected From-only rule in place (sets its ToType) when the picker From matches the selected rule's From + it has no To yet -- instead of appending a duplicate. So the flow is: Fill From-classes -> select a From-only row (From picker fills) -> pick a To -> New Conversion sets that rule's To + auto-matches.
> 
> **(B) 'Align is unknown type' -- FIXED via unknown-type inference.** ROOT CAUSE (confirmed): proptree emits `type=unknown` for a property inherited from a parent the index couldn't resolve. `TcxButton` ancestry breaks at **`TcxBaseButton [unresolved]`**, so all 89/6107 VCL-inherited props (Align, Caption, Anchors, ...) lose their type. Mapping `TabcToggleBtn.Align (TAlign)` -> `TcxButton.Align (unknown)` -> `IsCastable(TAlign,unknown)=false` -> blocked. User's rule: "unknown = defined in a parent." FIX: new pure `IsUnknownType` + `ResolveUnknownTypes(var f,t)` in `ConvRules.Casts` -- when exactly one side is unknown, adopt the other side's known type (a same-named property is the same inherited member: Align is TAlign on both) -> identity link. Wired into BOTH `DoAssign` (manual) and `DoAutoMatch`. Both-unknown same-named pairs also link (IsCastable identical-name rule) -- intended (both inherit the same unresolved-parent member). NOT touched when both sides are known-but-different (no false identity). VERIFIED end-to-end: TabcToggleBtn.Align=TAlign, TcxButton.Align=unknown -> inferred TAlign -> castable.
> 
> **(C) Unit selector row moved ABOVE the From->To row** (user layout request). Row 1 = From Unit + Fill From-classes (y38-42); row 2 = From -> To + New Conversion (y70-74). Pure SetBounds Y-swap.
> 
> **VERIFICATION:** editor `dcc64 -B` exit 0, tests **88 pass / 0 fail** (new `TestUnknownTypeInference`: detect/infer-to/infer-from/both/known-untouched), launch smoke OK, deployed to `third_party/dll-win64/ConvRulesEditor.exe`. UNVERIFIED = human clicking the live UI.
> 
> **FILES (uncommitted):** ConvRules.Casts.pas (+IsUnknownType +ResolveUnknownTypes), ConvRules.MainForm.pas (row swap, LoadGridForBlock picker-mirror, DoNewConversion update-in-place, DoAssign+DoAutoMatch inference), tests/ConvRulesModelTests.dpr (88 tests). Cumulative with LATEST-48/49/50 (picker split, DFM-based Fill From-classes, proptree qualification). Plus staged tree-sitter v1.1.2 DLLs. Watch loop STOPPED.
> 
> ---
> 
> ## RESUME 2026-07-16 (LATEST-50) -- **THREE ConvRulesEditor bugs fixed (user report) + tree-sitter v1.1.2 applied. UNPUSHED (user holds push); all this session UNCOMMITTED.**
> 
> **User report:** (1) "Fill From-column" fills the FROM PROPERTY column with class names; (2) drop the '(unit control...)' comment; (3) manually picking TabcToggleBtn -> TcxButton errored "TabcToggleBtn is not indexed (no properties found)" -- "how is it possible?".
> 
> **THE CORE BUG (#3, was the big one -- systematic-debugging + TDD): `proptree` needs a UNIT-QUALIFIED class name, the pickers hand it a BARE one.** `GetProptree('TabcToggleBtn')` -> `proptree --qname TabcToggleBtn` -> "class not found" (0 leaves) -> "not indexed" error. But TabcToggleBtn IS indexed -- as `Abcbtn.TabcToggleBtn` (2016 property leaves). Verified EVERY bare class fails (TcxButton/TOvcTable/TPanel = 0 leaves), so **New Conversion never worked with the real pickers** (they emit bare `descendants --of` names). FIX: new `TEngineAdapter.ResolveClassQName` (query --name -> first class row's qualified_name; no-op if already dotted/unresolvable) + `GetProptree` auto-qualifies before the proptree call. Now `TabcToggleBtn`->`Abcbtn.TabcToggleBtn`->2016 leaves; `TcxButton`->`cxButtons.TcxButton`->6107. TDD: `TestProptreeBareClass` (bareclass.ok/nonempty + qualified-still-ok) -- was FAILING, now PASS.
> 
> **#1/#2 (design from user):** "Fill From-column" put CLASS names into the grid's col0 = the FROM-PROPERTY column (Leaf.Path:Type). Classes != properties. User's spec: Fill should create FROM-ONLY conversion ROWS in the rules LIBRARY (left), one per unit component class, To unassigned. Selecting a From-only row shows that class's flattened property list (even with no To); assigning a To auto-matches; nothing persisted until To chosen (SaveComplete drops empty rules). FIX: rewrote `DoLoadUnit` -> adds From-only `#convert <Class> ->` nodes (dedup vs existing FromTypes), RefreshRulesList + selects the first new row; dropped the grid-dump + the '(unit control -- pick a To class)' comment; button renamed **'Fill From-classes'** + hint updated; removed the now-wrong active-rule requirement. `LoadGridForBlock` guarded so an empty ToType skips the To proptree cleanly (From tree still loads -> From-only rows show properties).
> 
> **VERIFICATION:** editor `dcc64 -B` exit 0, tests **78 pass / 0 fail** (2 new bareclass tests), launch smoke OK, deployed to `third_party/dll-win64/ConvRulesEditor.exe`. FULL-CHAIN proof via the real exe: VARINSP Fill -> TabcToggleBtn row -> 2016 From leaves -> assign TcxButton (6107 leaves) for auto-match. **Still UNVERIFIED = a human clicking through the live UI.**
> 
> **FILES (uncommitted):** ConvRules.Engine.pas (ResolveClassQName + GetProptree qualify; + LATEST-49 ResolveUnitFile/DFM ListControlTypesInUnit; + LATEST-48 ListDescendantsOf overload), ConvRules.MainForm.pas (DoLoadUnit rewrite + LoadGridForBlock empty-To guard + button rename; + LATEST-48/49 picker split & DoLoadUnit cleanup), ConvRulesEditor.dpr (FromDbs/ToDbs), tests/ConvRulesModelTests.dpr (+bareclass, +fill-from-unit, +picker-datasource = 78 tests). Plus staged tree-sitter DLLs (now **v1.1.2** -- delphi13 win64 2,948,096 / win32 2,927,616 @ 11:06; adds the asm-`end`-in-comment fix on top of Local/DispID; CLI.pas 0 errors, System.Rtti.pas 0; self-index reindexed). tree-sitter watch loop is STOPPED (user).
> 
> ---
> 
> ## RESUME 2026-07-16 (LATEST-49) -- **"Fill From-column" BUG FIXED (systematic-debugging + TDD) + tree-sitter DispID/Local DLLs applied earlier this session. Still UNPUSHED (user holds push); all this session's work UNCOMMITTED.**
> 
> **THE BUG:** In ConvRulesEditor, user selected unit VARINSP + pressed "Fill From-column" -> nothing appeared in the grid's From column. **ROOT CAUSE (confirmed, not guessed):** `TEngineAdapter.ListControlTypesInUnit` called `GetProptree(AUnit)` -- i.e. `proptree --qname VARINSP` -- but (1) VARINSP is a UNIT, not a class; proptree needs a unit-qualified CLASS (`VARINSP.TVarInspDlg`); (2) even the right class's proptree returns published PROPERTIES, not the form's component FIELDS (only 2 leaves vs the 63 real components); (3) `proptree` prints "class not found" but **exits 0**, so `GetProptree` returned True + an empty tree -> 0 types -> the `Length(Types)=0` branch fired a silent SetStatus (not SetError) -> "nothing happened." A failing in-process test (`ListControlTypesInUnit('VARINSP')` returned **0 types**) reproduced it exactly before any fix.
> 
> **THE FIX (DFM-based, TDD):** `ListControlTypesInUnit` now: resolves the unit's .pas file via a new `ResolveUnitFile` (`query --name <Unit> --json` -> the kind=unit row's `file`), swaps `.pas`->`.dfm`, reads the DFM and collects the distinct `object <Name>: <TType>` / `inline <Name>: <TType>` component types. This is the AUTHORITATIVE component list -- it does NOT intersect the library index, because real legacy components (`TOvcTable`/Orpheus, `TRz*`/Raize, `Tcx*`/DevExpress) have UNRESOLVED ancestry-to-TComponent in the lib index and an intersect would wrongly DROP them (verified: TRzPanel/TcxButton are class-indexed but resolve as 0 TComponent-descendants). VARINSP now yields **63 distinct component types** (TOvcTable x28, TOvcController, all TOvcTC*, TRz*, TabcToggleBtn, TTable, TPanel x192, ...). `DoLoadUnit` cleaned up: dropped the now-pointless `LoadAllClasses` pre-call (the fill no longer needs the picker set) + stale "intersect" comment. `AControlSet` param kept for signature compat (documented unused).
> 
> **VERIFICATION:** 2 new in-process tests in `ConvRulesModelTests.dpr` (`TestFillFromUnit`): `fill.from-unit.nonempty` + `.has.TOvcController`/`.TPanel`/`.TOvcTable` (all were FAILING pre-fix, now PASS). Full suite **75 pass / 0 fail / 0 skip**. Editor `dcc64 -B` exit 0, deployed to `third_party/dll-win64/ConvRulesEditor.exe`, 2s launch smoke test OK. Tests skip-not-fail when exe/ORM3-db/VARINSP.DFM absent.
> 
> **NOTE for the user's workflow:** "Fill From-column" still REQUIRES an active rule first (FActiveHdr>=0) -- if no rule is selected/created it shows a RED "Select or create a rule first" error (visible, not silent). The silent-empty path is what's fixed. A non-form unit (no .dfm) still returns [] with a status message (best-effort, by design).
> 
> **FILES (uncommitted this session):** ConvRules.Engine.pas (+ResolveUnitFile, rewritten ListControlTypesInUnit, ListDescendantsOf overload from LATEST-48), ConvRules.MainForm.pas (FROM/TO picker split from LATEST-48 + DoLoadUnit cleanup), ConvRulesEditor.dpr (FromDbs/ToDbs from LATEST-48), tests/ConvRulesModelTests.dpr (picker-datasource + fill-from-unit tests). Plus the 6 staged tree-sitter DLLs. ALSO earlier this session: applied tree-sitter DispID/Local grammar-fix DLLs (0 syntax-errors on CLI.pas), reindexed self-index; watch loop was set up then STOPPED at user request. ?7 of that inbox flagged 2 NON-drag-lint compile issues in C:/Projects/MMSRV/ (uPipeCommon.pas:1196 stray end;, uPipes.Threads.pas:1416/1422 Result := ; ModelMaker stubs) -- reported, not fixed (other project).
> 
> ---
> 
> ## RESUME 2026-07-16 (LATEST-48) -- **GRAMMAR-DLL REFRESH LANDED + ALL 3 CONVRULES-EDITOR FEEDBACK BUGS FIXED + VERIFIED.** All source committed-ready; **still UNPUSHED (user holds push).** main=HEAD `d6090db` (LATEST-47's 8 commits) + NEW uncommitted work this session (staged DLLs + editor source edits, NOT yet committed -- see below).
> 
> **(A) TREE-SITTER GRAMMAR-DLL DRIFT -- RESOLVED.** The false parser-errors were a **6-week-stale May-29 delphi13 DLL**, not a grammar/code bug (grammar Opus fixed inline-`var`+`array of` back in v1.1.0 2026-07-06, plus a bonus `local`-as-varname fix). The fresh Win32/Win64 DLLs were already in the working tree. VERIFIED: `drag-lint check-ast src/cli/DRagLint.CLI.pas` now = **0 syntax-errors** (was 7); a synthetic `Local:` var + `array of THandle` also parse clean. **No exe rebuild needed** -- DLLs load at RUNTIME, so the existing 07:50 `drag-lint.exe` already picks up the 08:24 DLLs (proven by the 0-error result). The 6 refreshed tree-sitter DLLs are **git-add STAGED** (dll/, dll-win32/, dll-win64/ x {delphi13,dfm}) awaiting the user's commit. INBOX reply read; its ?3 suggestion (add a grammar build-stamp so drift is observable -- `drag-lint info` prints ABI `14` which never changes) is a FUTURE enhancement, not done.
> 
> **(B) THE 3 FEEDBACK BUGS -- ALL FIXED. Corrected diagnoses vs LATEST-47:**
> 1. **VARINSP missing from From-Unit picker** -- NOT a wrong-DB bug (the editor's ORM3 db `C:\Projects\DB\ORM3\drag-lint.sqlite` IS correct and DOES index CLIENT: 756 units incl. CLIENT\Micronite2027.dpr). ROOT CAUSE: `VARINSP.PAS` (914KB) was individually MISSING from the index -- it parses fine (3480 symbols, 0 errors) but was skipped in the last full scan. FIX: incrementally reindexed it (`drag-lint index CLIENT\VARINSP.PAS --db ORM3\drag-lint.sqlite`) -> now the 757th unit; From-Unit picker's `query find --kind unit` returns it. **No editor code change for bug 1.** (Note: the FTS5 text index still shows 0 for VARINSP -- incremental symbol-index update didn't refresh FTS; irrelevant to the unit picker, but a real drag-lint quirk if text-search on VARINSP is ever needed -> full reindex or an FTS-aware incremental.)
> 2. **From-class picker too narrow (TControl-only)** -- CORRECTED: `TOvcTable` does NOT "fail to resolve as TControl"; it resolves FINE as TControl+TComponent -- but ONLY in **lib-Win64** (it's absent from lib-Win32 entirely). `TTable` (BDE) is a `TComponent` descendant, NOT `TControl` (non-visual). FIX: broadened the FROM picker from `TControl` to **`TComponent`** descendants (the right superset for source components: visual + non-visual + legacy).
> 3. **Merge Win32+Win64 libs for FROM** -- FIX: FROM now queries the UNION of Win32+Win64 libs (+ project db); TO queries the TARGET-platform (Win64) lib + project only. This is what actually surfaces `TOvcTable` (Win64-only).
> 
> **EDITOR CODE CHANGES (3 files, uncommitted):**
> - `ConvRulesEditor.dpr`: split `DefaultDbs` into `FromDbs` (LibWin32+LibWin64+ProjectDb), `ToDbs` (LibWin64+ProjectDb), kept `DefaultDbs`=union for engine proptree/scaffold/validate. New globals `GEditorFromDbs`/`GEditorToDbs` set before CreateForm. Platform hard-coded Win64-target (const LibWin32/LibWin64/ProjectDb) -- a future "target platform" setting/arg is the clean next step but not required now.
> - `ConvRules.Engine.pas`: added `ListDescendantsOf(AAncestor, ADbs, ...)` overload (explicit per-query db set, so FROM can union libs) + dedupe across DBs; refactored `DbArgs` -> `DbArgsFor(ADbs)`.
> - `ConvRules.MainForm.pas`: `FAllClasses` split into `FFromClasses` (TComponent desc, union) + `FToClasses` (TControl desc, target); `LoadAllClasses` populates each picker from its own set; picker Hints + status text updated; `ListControlTypesInUnit` (From-column fill) now intersects with `FFromClasses`.
> 
> **VERIFICATION (all green):** editor `dcc64 -B` BUILD_EXITCODE=0; model tests **70 pass / 0 fail / 0 skip** (was 58 + 12 NEW in-process picker-datasource asserts, see below); exe launches + form constructs (2s alive smoke test, no crash); exe deployed to `third_party/dll-win64/ConvRulesEditor.exe`. END-TO-END data-layer proof of the picker queries: **FROM** (`descendants --of TComponent`, Win32+Win64+proj) = **6198** classes incl. TOvcTable=1, TTable=1, TEdit=1, TcxGrid=1; **TO** (`descendants --of TControl`, Win64+proj) = **2865** classes, TTable correctly EXCLUDED (0, non-visual), TcxGrid=1.
> 
> **NEW AUTOTEST -- in-process picker-datasource asserts (`tests/ConvRulesModelTests.dpr`, `TestPickerDatasource`).** User asked to autotest that TOvcTable/TTable/VARINSP are actually in the datasource FEEDING the combo boxes -- and specifically FROM INSIDE THE EXE, not via a shell `query` (in case the raw DB has them but the CODE filters them out). So the test constructs a REAL `TEngineAdapter` (the exact class the pickers use) and drives `ListDescendantsOf`/`ListProjectUnits` -- the same spawn+parse+filter+dedupe path that populates FCbFrom/FCbTo/FCbUnit. Whatever those return IS the combo Items. Asserts: FROM has TOvcTable + TTable + TEdit + TcxGrid; TO has TcxGrid + EXCLUDES TTable (non-visual); From-Unit has VARINSP. `Contains()` proven discriminating (same helper passes `from.has.TTable` AND `to.excludes.TTable` -- opposite verdicts, same name). Tests are CONDITIONAL: `Skip` (not fail) when the exe or a real DB is absent, so the suite still passes on a lean machine (new GSkip counter + "N skip" in the summary line). Editor exe UNCHANGED by this (only the test .dpr) -- no rebuild/redeploy needed. This .dpr edit is UNCOMMITTED alongside the 3 editor files.
> 
> **ONLY UNVERIFIED:** a human opening the deployed editor + dropping the From picker to eyeball TOvcTable/TTable/VARINSP in the live UI (non-interactive session can't foreground the window). Data-layer + build + launch are all proven.
> 
> **NEXT WHEN RESUMING:** (0) user decides on push -- LATEST-47's 8 commits + this session's changes (stage: the 6 DLLs already staged; `git add` the 3 editor .pas/.dpr; ConvRulesEditor.exe in dll-win64 is deployed-but-untracked-or-dirty). Suggested commit split: one for the tree-sitter DLL refresh, one for the 3-bug editor fix. (1) OPTIONAL future: "target platform" as a real setting/arg (currently Win64 hard-coded); grammar build-stamp per INBOX ?3; FTS-aware incremental reindex. (2) Still open from LATEST-46: TRANSFER EDITOR brainstorm; auto-refresh IDE display after Full Sweep.
> 
> ---
> 
> ## RESUME 2026-07-16 (LATEST-47) -- **CONVRULES-EDITOR (visual conversion rule-book editor) BUILT + ITERATED across a long session. It is a STANDALONE plain-VCL exe `src/tools/convrules-editor/ConvRulesEditor.exe` (deployed to `third_party/dll-win64/`) that AUTHORS/EDITS the existing `conversion.rules` DSL -- a front-end to `convert-apply`; it does NOT convert. main=HEAD `d6090db`, 8 commits UNPUSHED (origin/main=`5713ee6`; USER HOLDS PUSH until the feature is worth external trial -- this is deliberate, do not push).**
>
> **>>> INCOMING GRAMMAR REPLY TO DEAL WITH (read `C:\Projects\tree-sitter-delphi13\INBOX-draglint-reply-inline-var-array-of.md`):** The inline-`var`+`array of` "gap" I filed was NOT a grammar bug -- it was fixed 2026-07-06 (v1.1.0); my `drag-lint.exe` had a **6-week-STALE `tree-sitter-delphi13.dll`** (dated May-29, ~350 KB of grammar behind). The grammar Opus **rebuilt + shipped fresh Win32/Win64 DLLs** -> they are the DIRTY `third_party/dll-win32|win64/tree-sitter-delphi13.dll` + `tree-sitter-dfm.dll` in git status right now (UNCOMMITTED). It ALSO found + fixed a REAL adjacent gap: **`local` as a var name** (an FPC `procAttribute` the parser ate as a trailing directive on the prior decl -- the last CLI.pas error `f85b412` had deferred). With the fresh DLL, `DRagLint.CLI.pas` goes from 7 -> 0 syntax errors. **ACTION next session: (a) rebuild `drag-lint.exe` against the fresh DLLs (they're already staged next to the exe -- just `build_draglint_win64.bat`) and confirm `drag-lint lint src/cli/DRagLint.CLI.pas` shows 0 parser-errors; (b) `git add` the 4 refreshed tree-sitter DLLs with the next commit (they're the grammar fix, worth committing); (c) reply to the INBOX if desired.** This means the false parser-errors I saw ALL SESSION were the stale DLL, not code -- dcc64 was always right.
>
> **>>> NEXT ACTIONS WHEN RESUMING = fix the 3 OPEN feedback bugs (root causes already diagnosed this session; NOT yet fixed):**
>
> 1. **VARINSP missing from the "From Unit" picker.** `VARINSP.PAS` exists at `C:\Projects\DB\ORM3\CLIENT\VARINSP.PAS`, but the editor's `DefaultDbs` (in `ConvRulesEditor.dpr`) uses `C:\Projects\DB\ORM3\drag-lint.sqlite`, which does NOT index the `CLIENT\` subfolder (`query --text VARINSP` against it = 0 matches). FIX: point the editor at a DB that indexes CLIENT -- per the manifest that is the per-project `Micronite2027.sqlite` (or resolve via the manifest like the plugin's `ResolveActiveIndexDbs` does), NOT the ORM3-root DB. Consider resolving the project DB the same manifest-first way the LSP does.
>
> 2. **From-class picker lacks Orpheus `TOvc*` and BDE `TTable`.** Root cause: the picker filters to `query descendants --of TControl`, but (a) `TOvcTable` IS indexed in library-Win32/Win64 (1 match each) yet does NOT resolve as a `TControl` descendant (Orpheus has its own base / the ancestry chain to VCL `TControl` is unresolved in the index), and (b) `TTable` (BDE) descends NONE of TControl/TComponent/TDataSet in the index (BDE ancestry unresolved) AND is non-visual. So a `TControl`-only filter is WRONG for the FROM side -- the user converts non-visual + legacy components too. FIX DIRECTION (needs a quick design decision): for the FROM picker do not filter by `TControl`; options -- (i) broaden to `TComponent`, (ii) UNION several ancestor roots (`TControl` + Orpheus base + `TDataSet` + ...), or (iii) simplest: FROM = all classes (no ancestor filter), only the TO picker filters to `TControl`/target. The new `query descendants --of <T>` verb already takes ANY ancestor, so (ii) is cheap; but Orpheus/BDE ancestry being UNRESOLVED in the index may mean even that misses them -- verify by re-indexing the libs with Orpheus/BDE source on the path, or fall back to `query find --kind class` (all classes) for FROM.
>
> 3. **Merge Win32+Win64 libs for the FROM picker.** User is converting a Win32 app to Win64, so FROM should list the UNION of Win32+Win64 library classes; TO should list only the TARGET platform's classes. Currently the editor's `DefaultDbs` only lists `library-Win32.sqlite`. FIX: FROM pickers query BOTH `library-Win32.sqlite` + `library-Win64.sqlite` (union); TO queries only the target lib. Make the target platform a setting/arg.
>
> **WHAT SHIPPED THIS SESSION (8 unpushed commits `e968f56`..`d6090db`):**
> - `e968f56` plugin: pinned "Full Compile Sweep" to the TOP of the drag-lint menu (Win32+Win64 BPLs rebuilt).
> - `a669fbf` docs: the conversion rule-book editor SPEC (`docs/superpowers/specs/2026-07-15-conversion-rulebook-editor-design.md`) -- the design of record; includes the non-TControl-PAS-conversion TODO (Orpheus queue -> Spring4D/Delphi generic queue: those convert PAS code, not DFM).
> - `ae1a6fb` ConvRulesEditor v1 core: `TRuleBook` loss-less DSL model (parses+re-emits EVERY directive byte-faithfully) + `ConvRules.Casts` (castability classifier) + `ConvRules.Engine` (adapter that shells drag-lint: proptree/scaffold/validate) + code-built VCL UI (no .dfm, no DevExpress) with rules-library(%)+3-col grid+pool+directive tabs+Save(backup+validate). Self-contained console test runner `tests/ConvRulesModelTests.dpr`.
> - `c827b62` FIX: proptree JSON now parses -- `drag-lint proptree` appends a `(loaded defaults ...)` line AFTER the JSON; the adapter fed the whole output to ParseJSONValue -> nil -> empty grid. `SliceJsonObject` (string-literal-aware brace scanner) extracts just the `{...}`. + auto-select first rule on load.
> - `a647b32` same-type-castable FIX (TFont<-TFont was blocked; IsCastable now allows identity for any equal type name) + red/bold error messages (SetError) + Auto-Match button (unambiguous name+type matches) + From/To class pickers + New Conversion button.
> - `4723410` **NEW ENGINE VERB** `query descendants --of <T>` -- reverse of `query ancestors --of`; `ISymbolStore.FindDescendantNames` uses a SQLite RECURSIVE CTE over `type_ancestors` (which stores DIRECT edges only, so a flat `WHERE ancestor_name=X` gives only direct children -- the CTE walks transitively). Verified: 2,239 TControl descendants on lib-Win32 incl. TEdit/TcxTextEdit/TcxGrid.
> - `d6090db` real class pickers (all TControl descendants via the new verb, lazy-loaded, searchable) + "From Unit" picker (740 project units via `query find --kind unit`; "Fill From-column" pre-fills grid From col with a unit's control types, best-effort, optional) + SaveCompleteToString (Save writes ONLY #convert blocks that have >=1 #link; empty From/To scratch is dropped). 58/58 model+cast+engine tests green.
>
> **ALSO THIS SESSION -- tree-sitter grammar-gap TICKET (user asked to file it).** `C:\Projects\tree-sitter-delphi13\INBOX-draglint-grammar-gap-inline-var-array-of.md` (committed in that repo): the delphi13 grammar (v14) FAILS to parse an inline `var X: array of THandle;` (Delphi 10.3+ inline var + anonymous `array of` type) -- valid Delphi that `dcc64` compiles fine. Minimal repro + 5 regression cases + likely one-line fix (point the inline-var `type:` field at the shared type rule). The ~7 CLI.pas lint "parser-errors" trace to 3 real occurrences + cascade recovery noise; NOT compile errors.
>
> **HOW TO BUILD + TEST (all headless, IDE-independent -- these do NOT touch the plugin BPL):**
> - Editor: `dcc64 -B src/tools/convrules-editor/ConvRulesEditor.dpr` (via a rsvars wrapper .bat run from PowerShell Start-Process -Wait); deploy exe -> `third_party/dll-win64/ConvRulesEditor.exe`.
> - Tests: `dcc64 -B src/tools/convrules-editor/tests/ConvRulesModelTests.dpr` then run the exe -> "58 pass / 0 fail".
> - CLI (the `descendants` verb lives in the main exe): `build/build_draglint_win64.bat` (rebuilds + stages `third_party/dll-win64/drag-lint.exe`).
> - Verify the verb: `drag-lint query descendants --of TControl --db C:\Projects\.drag-lint\library-Win32.sqlite` -> 2239 lines.
> - `.pas/.dpr` are strict 7-bit ASCII + CRLF; the Write tool emits LF -- ALWAYS re-normalize to CRLF (PowerShell `[IO.File]::ReadAllText` -> replace -> WriteAllText) before committing, then rebuild once to confirm.
>
> **GOTCHAS for a cold start:** (1) 8 commits UNPUSHED -- USER HOLDS PUSH deliberately; do not push. (2) The editor is a SEPARATE exe -- building it does NOT need the IDE closed (unlike the plugin BPL); but a running ConvRulesEditor.exe locks its own exe (F2039 on rebuild) -> `Stop-Process ConvRulesEditor` first. (3) The tree-sitter lint reports FALSE parser-errors on valid Delphi (inline var + array of, and generics/qualified-types in var blocks as cascade) -- TRUST dcc64, not the lint parser, for compile status. (4) Headless UI verification: a non-interactive session CANNOT foreground the window for a screenshot; use a temporary `--selftest` arg + a `TFile.AppendAllText` log inside the form (the pattern used repeatedly this session), then STRIP it before commit. (5) `query descendants` uses a RECURSIVE CTE because type_ancestors stores DIRECT edges; a flat name-match returns only direct children (was the "49 descendants" bug). (6) The 3 open bugs all stem from the FROM picker being too narrow (TControl-only) + the editor pointing at the wrong ORM3 DB -- fix the DB + broaden the FROM filter together.
>
> ## RESUME 2026-07-15 (LATEST-46) -- **FRESH-FINDINGS FEATURE FULLY IMPLEMENTED + FIVE SYNC BUGFIXES so the uMain `H2219 'DoHandleException' declared but never used` finally renders in the IDE. main=HEAD `8a47f16`, 20 commits UNPUSHED (origin/main=`5713ee6`; USER drives push). Everything is committed at the source level and verified headlessly; the ONE unverified thing is a live-IDE visual check.**
>
> **>>> NEXT ACTIONS WHEN RESUMING (user said after handoff: "a few more things to add-fix"):**
> 0. **PUSH** the 20 commits when the user is ready (their call). NOTE the working tree is dirty-but-safe: `third_party/dll-win32|win64/dclDragLintWizard.{bpl,dcp}` are TRACKED and were rebuilt this session with the plugin fixes, so the committed BPL blob is older than the committed source -- the user may want to `git add` the rebuilt BPLs with the push. Also dirty (pre-existing, NOT this session): `src/delphi-plugin/dclDragLintWizard.{dproj,res}` (an IDE Win32<->Win64 platform-default flip).
> 1. **THE TRANSFER EDITOR brainstorm** -- the paused-twice VISUAL property-mapping tool for component conversion (source props -> target props, emits the conversion.rules). Resume with superpowers:brainstorming. Rationale `docs/lint/DESIGN-table-conversion-visual-aid.md`; memory `[[feature-table-conversion-visual-aid]]`. This is the real unblocker for the still-not-done VARINSP conversion (button props need judgment, not a mechanical remap -- see LATEST-45 below).
> 2. **OPTIONAL follow-up flagged this session:** auto-refresh the IDE display when a Full Compile Sweep finishes. Right now the sweep updates the DB but the user must re-open/save the file to make the LSP re-publish and show the new findings. A `didSave`/refresh nudge after the spawned child exits would close that gap.
>
> **THE ONLY UNVERIFIED THING:** open the IDE (either bitness) + `uMain.pas` -> the `H2219 'DoHandleException declared but never used'` glyph on line 74 should render. Everything upstream is verified headlessly (I drove the deployed LSP directly: H2219 now publishes with characters `[0,1]`, a valid range).
>
> **WHAT SHIPPED THIS SESSION (20 unpushed commits).** FEATURE `refresh-findings` (`532ed74`..`44a5e0f` + `febbfab`): schema v16 `files.last_compiled_unix` -> store methods (ClearCompilerFindingsForFile / SetFileCompiledAt / GetFileCompiledAt / GetStaleFileIds) -> `TCompileChecker.Run(AFullBuild)` (+ the MCP caller fix the plan missed) -> `refresh-findings --project X --db D [--full] [--json]` verb (>=2 stale -> full build, 1 -> incremental, 0 -> noop; per-file clear+insert+stamp; compile-fail stores errors but does NOT stamp) -> mode-decision tests -> IDE plugin spawn-on-save/idle + "Full Compile Sweep" menu -> docs (AI-USAGE/README/INDEX-SCHEMA v16/CHANGELOG) + battery green + final opus whole-branch review GO-WITH-FIXES (the one Important: `--platform` was advertised but ignored -> de-advertised in `44a5e0f`). Implemented via superpowers:subagent-driven-development, every task reviewed clean. Task 4 surfaced a **load-bearing bug**: `GetStaleFileIds` filtered `language='pascal'` but the indexer stores `'delphi13'` (the feature was inert) -> fixed to a `.pas/.dpr/.dpk` path filter.
>
> **THEN 5 SYNC BUGFIXES** -- all chasing "why doesn't the uMain H2219 show in the IDE", each root-caused with superpowers:systematic-debugging + IN-PROCESS instrumentation (KEY LESSON: shell layers -- the Bash tool, PowerShell -- re-quote `CreateProcessW` command strings DIFFERENTLY than Delphi, so you CANNOT diagnose a Delphi spawn/capture bug through them; add a temp `TFile.WriteAllText` dump inside the Delphi code and read that):
> - **`18f4338` CAPTURE.** (a) `ParseLine`'s msbuild regex matched a SINGLE severity word, but the RAD Studio msbuild dcc wrapper emits HINTS as TWO -- `uMain.pas(74): Hint warning H2219: ...` -- so EVERY hint (H-code) was silently dropped; fix tolerates the optional leading word AND derives the true severity from the `[HWEF]` code letter (new `SeverityFromCode`; the word "warning" in "Hint warning H2219" is misleading). (b) forward-slash `--project` broke `NormalizeFindings`: Delphi `ExtractFilePath` ignores `/`, so a `/`-path yielded base dir `C:/` and bare project-file findings absolutized to the CWD -> `FindFileIdByPath` missed -> ALL project findings dropped. Fixed at all 3 call sites (+ defensively inside NormalizeFindings). `T40_compile_parser` fixture gained Hint-warning cases (Tests 7-8) + its stale `-U` unit paths were repaired.
> - **`2f6d90a` DB-MISMATCH.** The Full Sweep menu + save/idle spawns wrote `GetActiveProjectDb` = `<projdir>\<projname>.sqlite` (`Micronite2027.sqlite`), but the LSP diagnostics overlay reads its primary DB via `ResolveActiveIndexDbs` -- which is MANIFEST-FIRST: for a manifest-covered file (ORM3 `uMain.pas`) it uses the ORM3-root `drag-lint.sqlite` and DELIBERATELY ignores the per-project DB. So the sweep refreshed a DB the IDE never reads. Fix: new `ResolveRefreshFindingsDb` = `ResolveActiveIndexDbs(LoadSettings)[0]`; all 3 spawns routed through it; + a `DebugLog` in `SpawnRefreshFindings` so the spawn + target DB are visible in `%TEMP%\drag-lint-plugin.log` (it was silent before -- a wrong-DB sweep looked like no sweep).
> - **`e78f1a0` CACHE-WIPE.** `ParseAndPushCompileOutput` (compile-check-on-save) called `Cache.ClearAllCompilerFindings` -- a GLOBAL wipe of EVERY file's compiler overlay -- then repopulated only from the sparse INCREMENTAL compile, which emits nothing for clean units -> a full-sweep-populated H2219 on a clean uMain vanished on the next unrelated save (the 97->90 drop). Fix: per-file refresh scoped to `ByFile` (the units this compile reported), never a global wipe.
> - **`e42360f` DOUBLE-COUNT.** `GetForFile` unions `FByFile` (LSP publish, already has H2219 merged from the DB) + `FCompilerByFile` (compile-check overlay, ALSO has it) by PLAIN concatenation, no dedup -> the same findings counted twice, transiently, during a compile race. Fix: `ParseAndPushCompileOutput` gains `APushOverlay`; saved-file paths pass `False` (the LSP-DB path is authoritative for saved files), the ghost-check / UNSAVED-buffer path passes `True` (no LSP publish for in-memory content -> the overlay is its only route to the gutter).
> - **`8a47f16` = THE ACTUAL RENDER BUG.** The H2219 finding has `col_no = 0` (the msbuild "Hint warning" line has no column), so `BuildDiagnostics` computed `character := ColNo - 1 = -1` -- an INVALID LSP position. The IDE PUBLISHED the diagnostic but SILENTLY DROPPED it -> NO gutter glyph, through all the cache/DB/double-count theories. Fix: when `ColNo <= 0`, span the line start (character 0..1) = a valid visible range; else keep the 0-based column. VERIFIED by driving the deployed LSP directly: H2219 now publishes `{"line":73,"character":0..1}` (was `-1`).
>
> **DEPLOY STATE (all on disk, IDE was closed at handoff):** the fixed exe (with the render fix) is deployed to `third_party/dll-win64/drag-lint.exe` -- an EXE-side fix, so it reaches BOTH IDEs via the spawned child, no BPL rebuild needed. Both BPLs were rebuilt clean (win32 + win64) with the plugin fixes (`e78f1a0` + `e42360f`). The `drag-lint.sqlite` DB has the H2219 ready (453 findings incl. uMain H2219 at file_id 206).
>
> **GOTCHAS for a cold start:** (1) 20 commits UNPUSHED -- push is the user's call; the tracked BPLs are dirty (committed-source-vs-BPL disagree). (2) Deploying/rebuilding is BLOCKED while the IDE runs (the LSP child locks `drag-lint.exe`; the loaded BPL locks the .bpl -- F2039). NEVER close the user's IDE to clear a lock (hard rule); ask the user to close it. (3) RAD Studio 37 keeps 32/64-bit packages in SEPARATE registry keys: `Known Packages` (32-bit -> `dll-win32\...bpl`) vs `Known Packages x64` (64-bit -> `dll-win64\...bpl`); both are already registered + not disabled. (4) Component-conversion discussions are ALL SAFE -- see LATEST-45 + the docs list in the memory RESUME line. (5) The VARINSP conversion is still blocked-by-design on the transfer editor. Read the memory RESUME line + this block first.
>
> ## RESUME 2026-07-14 (LATEST-45) -- **TWO REAL INDEXER BUG FIXES + a NEW feature (fresh compiler findings) SPEC+PLAN, both user-approved. main=HEAD `107c2be`; 5 commits UNPUSHED (origin/main=`5713ee6`; USER drives push -- nothing at risk, all committed). Working tree: only `docs/examples/devexpress-printer-crash-repro/` (WIP, untracked) + usual leave-those artifacts.**
>
> **>>> NEXT ACTION WHEN RESUMING = IMPLEMENT "fresh compiler findings"** via superpowers:subagent-driven-development from the PLAN `docs/superpowers/plans/2026-07-14-fresh-compiler-findings.md` (spec `docs/superpowers/specs/2026-07-14-fresh-compiler-findings-design.md`). 7 TDD tasks, all headless-testable via a new `tests/autotest/run_fresh_findings.ps1`:
> 1. schema: add `files.last_compiled_unix INTEGER` (bump SCHEMA_VERSION 15->16 in `src/storage/DRagLint.Storage.Schema.pas`; ALTER in `Migrate` after the existing additive ALTERs).
> 2. store methods (ISymbolStore + SQLite): `ClearCompilerFindingsForFile(fid)`, `SetFileCompiledAt(fid,unix)`, `GetFileCompiledAt(fid)`, `GetStaleFileIds` (last_compiled_unix IS NULL OR < mtime_unix, language='pascal') + a hidden `test-store-freshness` verb.
> 3. `TCompileChecker.Run` gains `AFullBuild: Boolean` (=> `/t:Build` / `-B` instead of `/t:Make`).
> 4. NEW verb `refresh-findings --project X.dproj --db D [--platform p] [--full] [--json]` = `DoRefreshFindings`: query stale -> **>=2 stale (or --full) => FULL build; exactly 1 => incremental; 0 => noop** -> compile out-of-process -> per-file clear+insert findings + stamp last_compiled_unix. COMPILE-FAIL: store errors but DO NOT stamp (retry next time). Covered-set: full=whole closure, incremental={the 1 stale fid}+{fids with emitted findings}.
> 5. mode-decision tests (incremental vs full vs noop via the --json `mode` field).
> 6. IDE plugin: spawn `refresh-findings` on the EXISTING save/idle hooks (`AutoCompileOnSave`, `GHOST_IDLE_MS`) + a "drag-lint: Full Compile Sweep" menu (=> --full). RAM-SAFE: the plugin only CreateProcessW's the child; engine runs in the Win64 child, NOT the 32-bit IDE (the design already offloads out-of-process -- LiveDiagnostics.pas:12). OTA not headless-testable -> BPL-build is the only gate + a live smoke.
> 7. docs (AI-USAGE + INDEX-SCHEMA schema_version->16) + battery + final review.
>
> **WHY fresh-findings exists:** user saw Delphi LSP report `H2219 private symbol 'DoHandleException' declared but never used` at `uMain.pas:74`, but drag-lint didn't. ROOT CAUSE (verified live): drag-lint runs an INCREMENTAL compile (`/t:Make`, no `-B`), so a clean unit with an up-to-date `.dcu` is SKIPPED and DCC never re-emits its hints. `compiler_findings` = 0 rows for ORM3; `check-unit uMain.pas` returns `[]`. drag-lint DOES replicate errors (a failed unit has no valid dcu so is always re-checked) but MISSES hints/warnings on clean unchanged units. The feature keeps that table fresh (recompile when a file's mtime > its last_compiled stamp, debounced). Design decisions were the user's: mtime-driven staleness, files.last_compiled_unix column, >=2-stale-means-never-fully-scanned=full-build, engine-in-child-for-RAM, full-sweep=user menu.
>
> **THEN (user: "Transfer Editor is next after we finish this one"):** the TRANSFER EDITOR brainstorm -- a VISUAL property-mapping tool for component conversion (source props -> target props, emits the conversion.rules). Rationale doc already written: `docs/lint/DESIGN-table-conversion-visual-aid.md` (the win = killing visual tedium, NOT 100% automation; must be a REPEATABLE pipeline: helper + procedure + run x10-20 tables; extends the deferred "IDE model-editor" to whole-table structural mapping). The brainstorm was PAUSED twice; resume with superpowers:brainstorming. Memory `[[feature-table-conversion-visual-aid]]`.
>
> **WHAT SHIPPED THIS SESSION (5 unpushed commits `a2c022d`..`107c2be`):**
> - **`a2c022d` fix(indexer): ExpandMacros expands ARBITRARY `$(NAME)` library-path macros.** Was only 4 hardcoded ($(BDS)/$(BDSCOMMONDIR)/$(Platform)/$(Config)); every DevExpress path uses `$(DXVCL)` -> ~37 DevExpress source folders were SILENTLY DROPPED from the library index (folder "didn't exist" -> AddFolderIfReal skipped it). Fix in `src/project/DRagLint.Project.Resolver.pas`: after the hardcoded replacements, resolve any remaining `$(NAME)` via the RAD Studio `...\BDS\37.0\Environment Variables` reg key then process env (bounded 8 passes). VERIFIED: `index --scan-libraries-win --dry-run` now resolves 39 DevExpress folders (was 0), 0 leftover `$(` macros. NEEDS a library reindex to take effect (DONE this session, both Win64 reindexes below). Secondary compile-fix mid-task: `TMatchEvaluator` is `of object` not an anon method -> switched to `TRegEx.Matches` + `StringReplace`.
> - **`6584394` fix(indexer): FORWARD-DECLARED classes now resolve.** DevExpress forward-declares every class (`TFoo = class;` then `TFoo = class(...)`), so the parser emits TWO skClass symbols. This broke resolution in two places: (1) `ResolveAncestry` (index-time) found BOTH stub+body as same-file candidates -> InScopeCount=2 -> "ambiguous" (its FP policy) -> the ancestry edge was left UNRESOLVED -> every class deriving from a forward-declared ancestor lost inherited-property type resolution (e.g. `TcxButton.Down` came back type=unknown); (2) proptree `ResolveClassByQName` returned the FIRST skClass = the childless stub -> 0 properties. Fix: `ResolveAncestry` drops forward-decl stubs (empty heritage + single line) from any name that also has a real body; proptree `IsForwardDeclClass` guard + `BodyOf` re-resolution for ancestors and nested class-typed props. Files: `src/storage/DRagLint.Storage.SQLite.pas`, `src/report/DRagLint.Convert.PropTree.pas`, `tests/autotest/run_proptree.ps1` (gained a `TFwd` stub+body case + a `TFwdChild(TFwd)` inherited-from-forward-decl case; both RED before, GREEN after). Convert battery 146 PASS / 0 FAIL. **NOTE: fix (1) is index-time -> needed a reindex.** Win64 library FULLY REINDEXED this session (6909 files, 2,176,138 symbols, ~50 min) -> VERIFIED `query ancestors --name TcxButton` = resolved:true, `proptree cxButtons.TcxButton` shows Down:Boolean/GroupIndex:Integer/Kind:TcxButtonKind/AllowAllUp:Boolean (were all `unknown`).
>   - **BROADER ISSUE FILED (not fixed):** `FindSymbolsByQualifiedName` / `FindSymbolByExactNameAnywhere` (store primitives, used in ~20 files) also return forward-decl stubs first -- they likely mis-resolve elsewhere too (autodoc, context bundles, convert). Only proptree + ResolveAncestry were fixed (contained). A store-primitive fix would be wider blast radius -> deferred, user's call.
> - **`a61cd6e` docs:** `docs/AI-CONVERT-RUNBOOK.md` (agent procedure for convert-apply, cross-linked from AI-USAGE + CONVERSION-RULES) + `docs/TCXGRID-UNBOUND-GUIDE.md` (research-agent-written, DevExpress-VCL-docs-grounded: fixed unbound TcxGrid Y x X mixed-type columns incl. in-cell TcxButton, feed via DataController.Values[r,c]; the future TOvcTable->TcxGrid target; wiki-filed too) + `docs/lint/DESIGN-table-conversion-visual-aid.md` (transfer-editor rationale).
> - **`595fd5c` + `107c2be`** = the fresh-findings spec + plan.
>
> **WHY the two fixes exist:** both surfaced while setting up a LIVE convert-apply test of `C:\Projects\DB\ORM3\CLIENT\VARINSP.PAS` (scope: ABC `TabcToggleBtn`->`TcxButton` [20 instances, only ABC type in all CLIENT; from `C:\Projects\ABC5\ABC5\Source\Abcbtn.pas`] + standalone OVC edits `TOvcSimpleField`/`TOvcDbSimpleField`/`TOvcMeter` [all confirmed standalone by parent-block check, parented by TPanel/TTabSheet]; EXCLUDED: all TOvcTable/TOvcTC*/cell types + non-visual `TOvcController`). **That live conversion is STILL NOT DONE.** The button scaffold `convert-scaffold Abcbtn.TabcToggleBtn -> cxButtons.TcxButton` explodes to thousands of nested paths AND the real `TabcToggleBtn` instances set props with NO clean `TcxButton` equivalent (`Layout`/`Style` = Orpheus enums; `Picture.Data`->cx `Glyph`; `Images`->`OptionsImage.Images`) -> the conversion needs JUDGMENT, not a mechanical remap. **That is exactly why the user chose to build the transfer editor first** rather than hand-author these rules. Win32 library index is STALE (Jul 9, pre-both-fixes) if 32-bit parity is ever needed (user said "we work on x64, ignore 32 for now").
>
> **PARKED (crash investigation, NOT drag-lint code):** the `uMain.pas` IDE-designer crash. Diagnosed via WER LocalDumps (configured for bds.exe; user ran the admin cmd) + x64 `cdb` on a 2.2 GB dump. VERDICT: a **DevExpress 2026.1.3.0** bug -- AV at 0x0 (call through nil) in `cxLibrary TdxHookProc` / `TDictionary<TcxObjectLink>` during form teardown. NOT drag-lint (absent from the crashed process), NOT the IDE Dark theme (Light still crashes). REAL trigger found via `__history` diff of `uStyles.dfm.~16~` (the last crashing version): an **ORPHANED `TdxGridReportLink` (`JobListPrinterLink1`) with NO `Component` property** in the `dxPrinter` (`TdxComponentPrinter`) inside the `TdmStyles` datamodule that uMain uses. Minimal repro built at `docs/examples/devexpress-printer-crash-repro/` (Form1=ribbon form uses DMStyles; DMStyles has the orphaned link; compiles clean). DevExpress asked for a small sample; **PENDING the user's designer-close test** to confirm the repro fires (the earlier Component=Form2.cxGrid1 version did NOT crash -- a VALID link; the orphaned-no-Component version matches the real crash). Full analysis: scratchpad `umain-crash-analysis.txt`. Also diagnosed + fixed a self-inflicted Save-All crash (our minimal .dproj lacked `<ProjectExtensions>` -> IDE AV'd synthesizing them; added the block; NOT worth reporting).
>
> **GOTCHAS for a cold start:** (1) 5 commits UNPUSHED -- push is the user's call. (2) The fresh-findings feature is SPEC+PLAN only, NO code written yet -- start at Task 1. (3) Win64 library index is CURRENT (reindexed this session with both fixes); Win32 is stale. (4) The store-primitive forward-decl issue is filed-not-fixed (see 6584394 note). (5) convert-apply live test on VARINSP is blocked-by-design on the transfer editor. Read the memory RESUME line + this block, then the plan.
>
> ## RESUME 2026-07-10 (LATEST-44) -- **COMPONENT-CONVERSION APPLY SHIPPED + PUSHED. `convert-apply` is a real, user-facing CLI verb that rewrites a Delphi component's `.pas` + `.dfm` on disk across ALL 5 surfaces. main=`2dd09d8`, origin SYNCED (pushed `7448d3f..2dd09d8`), tree clean (only usual leave-those untracked). NO release/tag (CLI+headless; a version bump can ride a later checkpoint).**
>
> **>>> NEXT ACTION WHEN RESUMING = REAL-LIFE TEST on a LIVE component (user chose this target).** Run `convert-apply` on a REAL, indexed project (an ORM3 CLIENT form; a TOvc*->Tcx* or TDBEdit->TcxDBEdit pair), DRY-RUN first then `--apply`, and CONFIRM the converted `.pas`+`.dfm` actually COMPILE (build the host project). Fixtures pass, but a real DevExpress form will surface bugs fixtures cannot (property-name mismatches, moved-depth shapes, owned parts, unindexed types). If it breaks -> superpowers:systematic-debugging -> fix to green. This is the true "basic component replacement WORKS" proof the user asked for.
>
> **THE RECIPE** (exe = `src/cli/Win64/Debug/drag-lint.exe`; index the project first if needed):
> ```
> drag-lint proptree         --qname MyUnit.TOvcEdit --db app.sqlite        # inspect the source tree
> drag-lint convert-scaffold --from TOvcEdit --to TcxTextEdit --out c.rules --db app.sqlite
> drag-lint convert-validate --rules c.rules --from TOvcEdit --to TcxTextEdit --db app.sqlite
> drag-lint convert-apply    --unit MyForm.pas --rules c.rules --db app.sqlite            # DRY-RUN (preview diff, writes nothing)
> drag-lint convert-apply    --unit MyForm.pas --rules c.rules --db app.sqlite --apply     # writes: .BCK<n> + recovery.txt + // comment
> ```
> `--only Name1,Name2` restricts to named instances; `--no-backup` skips the safety writes. Test battery (ALL 8 GREEN): `run_convert_apply.ps1` + `run_dfm_reemit.ps1` + `run_convert_rules.ps1` + `run_convert_scaffold.ps1` + `run_proptree.ps1` + `run_member_access_refs.ps1` + `run_self_field_refs.ps1` + `run_type_ref_gap_e.ps1`.
>
> **WHAT SHIPPED THIS SESSION** (2 dependent sub-projects, superpowers subagent-driven-development, 15 commits, EVERY task reviewed clean + a final opus whole-branch review GO-WITH-FIXES whose 2 findings were fixed):
> 1. **Batch 2a-i -- the pure DFM re-emit ENGINE** (`ReemitComponent` in `src/report/DRagLint.Convert.DfmReemit.pas`): parse an F object block -> in-memory `TDfmNode` tree (verbatim values) -> remap each leaf to its T path incl. MOVED-DEPTH (`Font.Size`->`Style.Active.Font.Size` via `PlaceAtPath`) + EVENTS + collection-relocate + binary-same-type-only-copy -> `EmitBlock` re-serializes a well-formed T block. New `#ignore`/rkIgnore DSL directive; hidden `convert-reemit` test verb. RUNTIME GATE caught a real bug (moved-depth #link silently broken for nested-in-sub-object leaves) -> FIXED (RemapLeaf dotted lookup key + HasDeepRuleUnder + RemapUnderPrefix). See LATEST-43 below for full detail.
> 2. **Ref-gap G -- SUPERVISED parser change (USER APPROVED the exact diff before it was applied)**: index property/field MEMBER access on typed receivers (`obj.Member`) as a new `kind='member-access'` ref, gated to NON-Self plain-identifier receivers (the complement of ref-gap D's Self. gate). Flood-checked on real ORM3 `ap.pas` = ~12% of refs (86/706), existing read/write/type_use/call untouched; D+E regressions green. Enables convert-apply surface #4. Spec `docs/superpowers/specs/2026-07-10-refgap-g-member-access-design.md`, plan `...plans/2026-07-10-refgap-g-member-access.md`, parser emission in `DRagLint.Parser.Delphi13.pas` exprDot case.
> 3. **`convert-apply` verb** (`src/report/DRagLint.Convert.Apply.pas` + `DRagLint.Convert.Backup.pas` + `DoConvertApply` in `DRagLint.CLI.pas`) -- the 5 rewrite surfaces: **#1** `.pas` decl retype (`tekReplaceInLine` on the field's type token, located via `Sym.Signature` exact match); **#2** `.pas` uses-add (reuses `TFindUnitRefactoring.Build`); **#3** `.dfm` block re-emit (feeds `ReemitComponent`; block located via `FindSymbolsByFile` StartLine/EndLine; `tekDeleteLines`+`tekInsertLines`); **#4** `.pas` property/event ACCESS rewrite (`Edit1.Caption`->`Edit1.Text` instance-scoped: query `member-access` refs named FromMember, resolve the receiver by a backward text scan to the identifier before the dot, rewrite only when the receiver is a converted instance); **#5** runtime creators (`TOldEdit.Create`->`TNewEdit.Create` + a `{ TODO: verify creator }` marker -- USER'S IDEA; detects real constructor calls via `GetConstructorNames`, not class-static refs). Per-unit input `--unit F.pas --rules r --db d [--only N1,N2] [--apply] [--no-backup]`. **DRY-RUN by default** (RenderDryRun, writes nothing); `--apply` writes with **next-free `.BCK<n>` backups + `recovery.txt` written FIRST (crash-safe) + an in-file `// drag-lint convert-apply` comment**; a **freshness guard** refuses (--apply) / warns (dry-run) on a stale OR not-indexed F/T type. Spec `...specs/2026-07-10-convert-apply-verb-design.md`, plan `...plans/2026-07-10-convert-apply-verb.md`.
>
> **KEY INVARIANTS VERIFIED by the final opus review (do not re-litigate):** edit-set NO COLLISION (all 5 surfaces target disjoint `[Col,EndCol)` spans; `TTextEditApplier.Apply` sorts back-to-front by EndLine/Line desc + Col desc); SKIP-ON-FAILURE HOLDS (a #3-re-emit-FAILED instance produces ZERO edits across ALL surfaces + never enters `ConvertedInstNames` -> no half-conversion); recovery-BEFORE-write; NO-double-backup (`Apply` called with `writeBackups:=False` because our layer already backed up); freshness sha/mtime byte-exact with the indexer. **CONTROLLER DECISIONS baked in:** NO default-valued silent drop (every DFM-present prop is carried or Dropped); owned-vs-child via `#note owned:<Class>` marker (2a-i deterministic stand-in).
>
> **OPEN / DEFERRED (ordered):**
> - **Batch 2a-0 (SUPERVISED, the last correctness gap)** -- the drag-lint index does NOT capture property `default` specifier values (VERIFIED: signatures are empty or type-only; `default True`/`default 0` dropped at parse time). 2a-0 = a supervised core-parser change (like ref-gaps D/E/G -- HAND THE USER THE EXACT `DRagLint.Parser.Delphi13.pas` DIFF BEFORE APPLYING) to capture `default X` into the store + surface on `TPropNode`. Closes the gap where a property ABSENT from the F DFM (== F default) whose F-default != T-default silently adopts T's default on re-emit. convert-apply already emits a divergence Note when F/T types differ + has a documented default-overlay seam in `RemapLeaf` where 2a-0 plugs in.
> - Deferred (documented, non-blocking): split/merge (one F -> several T), the expression interpreter, multi-declarator field-line auto-retype (currently WARNS + names the limitation), multi-db field/uses lookup (first readable db only -- mirrors the real single-store `TFindUnitRefactoring` API), nested-deeper-indent `.dfm` re-emit (one level tested), the IDE model-editor + T-side property-search navigator.
> - **STILL PENDING USER** (unchanged, live IDE): Batch F+G live-IDE smoke; confirm the drag-lint About entry renders in Help>About. Also open: ref-gap F (bare field read in expr); attach the FP-fixed BPL to a release (v1.1.0 zips are CLI-only).
>
> Read LATEST-43 below for the 2a-i engine detail, LATEST-42 for the v1.1.0-alpha state + the full Batch 2 brainstorm/decisions.

> ## RESUME 2026-07-10 (LATEST-43) -- **Track 3 Batch 2a-i (DFM component RE-EMIT ENGINE) BUILT + all tests GREEN, on `main`, UNPUSHED (user drives push). Built via superpowers subagent-driven-development, 10 tasks, EVERY task reviewed clean (SPEC PASS + QUALITY Approved, 0 blocking findings across all 10). Plan `docs/superpowers/plans/2026-07-10-track3-2a-i-dfm-reemit-engine.md`; spec `docs/superpowers/specs/2026-07-10-track3-2a-i-dfm-reemit-engine-design.md`. >>> WHAT SHIPPED (headless, CLI-only, NO BPL/IDE): (1) NEW pure unit `src/report/DRagLint.Convert.DfmReemit.pas` -- `ReemitComponent(AFromBlock, ARules, AFromTree, AToTree): TReemitResult` = structured DFM re-emit: `ParseDfmBlock` (fresh lossless tree-sitter-dfm walk -> in-memory TDfmNode tree w/ VERBATIM property values; the indexer's TDFMParser is symbol-only/lossy) -> remap each leaf to its T path incl. MOVED-DEPTH (`Font.Size` -> `Style.Active.Font.Size` via `PlaceAtPath` creating intermediate T sub-objects, recorded in Report.Created) + EVENTS + collection relocate-keep-items + binary same-type-only copy -> `EmitBlock` re-serializes a well-formed T block. Owned-vs-child = the 2a-i deterministic stand-in (`#convert` rule -> recurse+convert; `#note owned:<Class>` marker -> flag Report.OwnedParts; else contained child -> clone verbatim). Structured Report (dropped/ignored/mismatched/created/ownedParts/notes). PURE (no I/O/CLI/IDE/LLM). (2) NEW `#ignore <FromPath>` DSL directive (rkIgnore) in `DRagLint.Convert.Rules.pas`. (3) HIDDEN CLI test verb `convert-reemit --from-block F --rules F --from T --to T --db D` (`DoConvertReemit`, JSON out, NOT in help -- 2a-iii's `convert-apply` supersedes it; store-open transcribed byte-for-byte from `DoConvertValidate`). (4) `tests/autotest/run_dfm_reemit.ps1` -- 25/25 checks GREEN (11 spec cases: rename, moved-depth+Created, events, #ignore, unmapped-drop, #default, collection relocate, binary same-type/mismatch, owned-part w/ + w/o rule, contained child, identity round-trip). Convert-family no-regression: run_convert_rules/proptree/scaffold ALL PASS. >>> KEY RUNTIME FINDINGS (the compile-only tasks couldn't catch these; the CLI-verb runtime gate did): (a) BUG FOUND+FIXED -- moved-depth `#link Style.Active.Font.Size <- Font.Size` was NEVER applied when `Font.Size` lives INSIDE a nested F sub-object (ReemitComponent only saw top-level leaves/#link FromPaths, so HandleNested cloned the whole Font sub-object verbatim); the moved-depth headline feature vs GExperts was SILENTLY BROKEN. Fix = RemapLeaf takes an explicit dotted AFromPath lookup key + new HasDeepRuleUnder(prefix) + RemapUnderPrefix recursion + HandleNested dispatch #convert->deep-rule->clone. (b) the Task-3 text-shape `<`/`{` collection/binary detection (unverified until the runtime gate) WORKED FIRST RUN on real tree-sitter-dfm output, no engine fix. >>> 4 CONTROLLER DECISIONS locked at pre-flight (govern the engine): (1) NO default-valued silent drop -- every DFM-present prop is carried or Dropped (DFM omits defaults, so present==non-default). (2) F-default-vs-T-default divergence for props ABSENT from the DFM is a KNOWN GAP -> NEW SUPERVISED prereq **Batch 2a-0** (below). 2a-i has a default-overlay SEAM (documented in RemapLeaf) + emits a divergence Note when F/T types differ. (3) owned-vs-child via `#note owned:` marker (2a-ii swaps in the real index Controls/Components container check). (4) divergence Note when F/T root types differ. >>> NEXT = Batch 2a-ii (.pas side: declaration-type + uses-add via find-unit + property/event ACCESS rewrite via the ref index + the SELECTION model [class/kind/named x unit/project] + index-FRESHNESS guard) -> then 2a-iii (the user-facing `convert-apply` verb tying 2a-i+2a-ii + REVERT STACK + rules persistence/LIBRARY seeding; dry-run/--apply/--no-backup). >>> NEW PREREQUISITE FILED -- **Batch 2a-0** (surfaced during 2a-i pre-flight): the drag-lint index does NOT capture property `default` specifier values (`default True`/`default 0` dropped at parse time -- VERIFIED: property signatures are empty or type-only). 2a-0 = a SUPERVISED core-parser change (like ref-gap D/E -- hand the user the exact `DRagLint.Parser.Delphi13.pas` diff before applying) to capture `default X` into the symbol store + surface on `TPropNode` (e.g. a DefaultText field, resolved up the ancestor closure BuildPropTree already walks). It closes 2a-i's KNOWN GAP (a property absent from the F DFM == F default; if F-default != T-default, re-emit silently adopts T's default). Priority: before 2a-ii/iii deliver a user-facing apply that could silently flip defaults. >>> OPEN (implementer-flagged, corner case): a nested sub-object with BOTH a `#convert` AND deep `#link` rules recurses via `#convert` (documented/intended, but not test-covered). >>> STILL PENDING USER (unchanged, live IDE): Batch F+G smoke; confirm the drag-lint About entry renders in Help>About. OTHER OPEN FOLLOW-UPS (from LATEST-42): ref-gap F (bare field read in expr); attach the FP-fixed BPL to a release. main HEAD after the Task 10 docs commit is recorded in the SDD ledger. Read LATEST-42 below for the v1.1.0-alpha state + the full Batch 2 brainstorm/decisions.**
>
> ## RESUME 2026-07-10 (LATEST-42) -- **v1.1.0-alpha SHIPPED; a big Track 3 Batch 2 (apply) BRAINSTORM is COMPLETE (spec WRITTEN + USER-APPROVED, NOT yet built). main=`3b9dd84`, origin SYNCED, tree clean of real work. GH release v1.1.0-alpha = Latest (CLI zips win64+win32; the plugin BPL was rebuilt in later commits but is NOT in the release zips -- a future release could attach it). >>> NEXT ACTION WHEN RESUMING = BUILD Track 3 Batch 2a-i: the spec is at `docs/superpowers/specs/2026-07-10-track3-2a-i-dfm-reemit-engine-design.md` (approved) -- write the implementation PLAN (superpowers:writing-plans) then subagent-driven-build. 2a-i = a PURE Object Pascal unit (NO I/O/CLI/IDE/LLM): `function ReemitComponent(AFromBlock, ARules, AFromTree, AToTree): TReemitResult` in NEW `src/report/DRagLint.Convert.DfmReemit.pas` = structured DFM component RE-EMIT: parse one F component's DFM `object` block via tree-sitter-dfm -> in-memory {Name,Kind,Value,Children} tree -> remap each leaf to its T path incl. MOVED-DEPTH (`F.Font.Size` -> `T.Style.Active.Font.Size`, create intermediate sub-objects) + EVENTS (`OnClick` etc.) -> re-serialize a well-formed T block (indentation, nested sub-objects, collections/items, binary VERBATIM). Adds ONE DSL directive `#ignore <FromPath>` (rkIgnore) to `src/report/DRagLint.Convert.Rules.pas`. Reuses Batch 1's TConversionRuleSet/ParseConversionRules/ValidateConversionRules + TPropTree/BuildPropTree + the tree-sitter-dfm parse path. Test `tests/autotest/run_dfm_reemit.ps1`. Batch 2 (apply) is DECOMPOSED into: 2a-i (this, DFM re-emit engine) -> 2a-ii (.pas decl-type + uses via find-unit + property/event ACCESS rewrite via ref index + the SELECTION model class/kind/named x unit/project + index-FRESHNESS guard) -> 2a-iii (the `convert-apply` verb tying i+ii + the REVERT STACK + rules persistence/LIBRARY seeding; dry-run/--apply/--no-backup). <<< KEY BATCH-2 DECISIONS (all captured in the two specs -- the 2a-i spec + the BATCH 2 section appended to the Batch-1 spec `docs/superpowers/specs/2026-07-09-track3-component-conversion-batch1-design.md`): FOUR rewrite surfaces (pas type / uses / structured DFM / pas property+event ACCESSES); the GExperts-CANNOT-do differentiators = pas-side + events + moved-depth (GExperts is DFM-only, 1-level, no events); OWNED-part-vs-CONTAINED-child recognition = a nested DFM object that is a member of the parent's `Controls`/`Components` collections is a CONTAINED CHILD -> LEAVE ALONE, ELSE it's an OWNED part (field/column) -> convert WITH the parent, which REQUIRES a #convert rule for its type but WARN-not-refuse if missing (verified vs `C:\Projects\DB\ORM3\CLIENT\CompGroup2.dfm`: TRzPanel>TcxButton children [leave] vs TcxDBTreeList>TcxDBTreeListColumn columns [owned->convert]; note TField IS a TComponent so "is-TComponent" does NOT distinguish -- membership in Fields vs Controls/Components does); COLLECTION relocate-keep-items #link (move `TTable.Fields` -> `TXXTable.Data.Fields`, items unchanged); BINARY/complex value copied ONLY when F/T leaf types resolve (via proptree) to the SAME type else WARN (cross-type binary conv = the interpreter stage, later); `#ignore <FromPath>` = acknowledged drop, no warn (other unmapped non-default props still WARN); only MAPPED props assigned (no same-name auto-carry); TWO reports (a text file to open in IDE + content for the IDE Messages window); SAFETY = revert STACK (back up each touched file + record paths in a stack/manifest so a whole conversion action can be reverted as a unit, on top of dry-run/--apply/.bak); a growing conversion-rules LIBRARY that SEEDS a new pair from a similar one (TOvcDBEdit->TcxDBTextEdit from TOvcEdit->TcxTextEdit's shared base, DB-specifics hand-edited); NO LLM (the "conversion model" is the flat DSL text, engine is deterministic Object Pascal). Split/merge (one F -> several T, several F -> one T) + the small SAFE EXPRESSION INTERPRETER are DEFERRED past 2a. TWO EVENTUAL PARTS: (1) the ENGINE (CLI, now) + (2) a LATER IDE MODEL-EDITOR that edits the rule model with assistance -- flatten F's deep tree to a flat list, auto-assign unambiguous F->T leaves, and a T-SIDE PROPERTY NAVIGATOR WITH SEARCH (type "font" -> jump to `T.Style.Default.Font` instead of walking each level); presented as a GRID, stored as DSL text; its own brainstorm AFTER the engine is proven. >>> ALSO DONE THIS SESSION (2026-07-10, all shipped + pushed): (A) v1.1.0-alpha released (H1 butterfly verb + H3 Track3 Batch1 + H4 ref-gap E; commit `2753af9` version bump; GH release Latest). (B) string-equality-comparison FP FIX (commit `a274066`): the IDE plugin's LSP `BuildDiagnostics` ran the type-BLIND `.scm` rule despite already receiving a store -> now when a store is present it drops the `.scm` string-equality findings + uses the type-aware CheckTypeAware rule (fires only when BOTH operands are strings); `Word`/enum compares (`Key = VK_F10`) no longer misfire; new `run_string_equality_fp.ps1`; recorded as FP #3 in `docs/BACKLOG-lint-false-positives.md`; VK_F10 confirmed IS in the library index. (C) Plugin PLUGIN_VERSION bumped v1.0.0->v1.1.0-alpha + Win32 BPL rebuilt clean + deployed (commit `85c3437`; splash now shows v1.1.0). (D) library-drift output REWORDED (commit `c75965f`): "SOURCE NOT INDEXED (.pas/.inc/.dfm on disk, none in index)" instead of a bare "MISSING", + indexed the real Raize `DM2\Source`+`IX2\Source` into library-Win64 (the `Lib\RX13\Win64` roots have only .dcu + orphan .dfm, no .pas -- source lives in the sibling `Source\` folder). (E) YADF PORT note (`C:\Projects\YADF\docs\PORT-ide-splash-and-about.md`) FINALIZED + committed + PUSHED to the YADF remote (commit `5bf93b3` on YADF main) -- splash CONFIRMED by user; clarified the About entry is INSIDE the IDE Help>About dialog (IOTAAboutBoxServices.AddPluginInfo), NOT a standalone menu (this was the user's "no About menu" confusion). >>> STILL PENDING USER (live IDE, NOT headless): Batch F+G smoke; CONFIRM the drag-lint About entry renders in Help>About Embarcadero RAD Studio (plugins list). OPEN FOLLOW-UPS: ref-gap F (bare field read used as an expression operand -- `Result := client + 1` -- not indexed, so field-name-prefix rename leaves it stale; the narrowed field warning stays until F closes); attach the FP-fixed BPL to a release (v1.1.0 zips are CLI-only); the pre-existing "Rename.Build no impl-header rename" item (may overlap F). Read LATEST-41 below for H4 (ref-gap E) detail; LATEST-40 for H3 (Track 3 Batch 1).**
>
> --- (LATEST-41: H4 ref-gap E complete) ---
>
> ## RESUME 2026-07-09 (LATEST-41) -- **H4 = ref-gap E COMPLETE (SUPERVISED parser change, user-approved diff). The whole autonomous H1->H4 deferred-backlog program is DONE. main=`0d4a425`+docs, on `main`, tree clean of real work. All commits UNPUSHED til the push step (origin/main=`aedd0bf`).** Ref-gap E indexed FOUR type-USE shapes the ref index missed (under `--deep`, all emit `kind='type_use'`): (1) method-IMPL-header class qualifier (`Widget.Use` -> the `Widget`); (2) impl-header PARAM + RETURN types (surfaced by the round-trip test -- a 4th sub-shape found mid-impl, folded into the same edit); (3) local-var type annotations (`Local: Widget`); (4) `is`/`as` operands (`X is Widget`). Parser edits (commit `b67aeb3`, `src/parser/DRagLint.Parser.Delphi13.pas`, 4 gated EmitRef sites mirroring ref-gap D; reasoning kept INLINE per user for future revision): impl-header qualifier+args+ret walked in the defProc handler (method impls are NEVER routed through WalkDeclProc -- that's free-routine-only, `Pos('.')=0`); local-var type routed through EmitTypeUseReference in EmitRoutineLocals; is/as gated to exprBinary operator kIs/kAs + bare-identifier rhs. VERIFIED: round-trip test `run_type_ref_gap_e.ps1` GREEN (rename Widget->TWidget leaves ZERO stale sites); over-capture CLEAN (type_use never lands on a var/param name -- TTSNode=56 type_use, ANode/a/b=0; is/as never fires on `>`/`=`); ref-gap D + naming-autofix regressions PASS. The rename engine needed NO change (type-name-prefix autofix routes through the SAME TRenameRefactoring.Build / FindCallersByName kind-agnostic path as the generic rename verb -- NamingFix.pas:456). WARNING NARROWED (commit `0d4a425`, `DRagLint.CLI.pas`): the `--fix` stderr warning is RETIRED for type-name-prefix (ref-gaps D+E cover all its shapes -- verified NO warning fires) but RETAINED for field-name-prefix, narrowed to name the ONE remaining uncovered shape. >>> NEW FOLLOW-UP FILED = **REF-GAP F**: a BARE field read used as an EXPRESSION OPERAND (`Result := client + 1`) is still NOT indexed as a ref, so a field-name-prefix rename leaves that one site stale (verified: `Self.client` renames via ref-gap D, bare `client` in `client + Self.client` does NOT). This is analogous to ref-gap B (bare RHS reads) but needs its own careful gating to avoid over-capturing every local/param -- a separate batch, NOT folded into E. The narrowed field warning stays until F closes. <<< KEY MID-FLIGHT FINDINGS (both verified + adjudicated): (a) `type-name-prefix` autofix uses the RELAXED StartsWithPrefix (NamingChecks.pas:106-115,540) so it NEVER fires on a T-prefixed class -> the RED-test fixture had to be a NON-T name (`Widget`, renames to `TWidget`) to drive the real autofix; (b) Task-1 review's "committed .ps1 is LF" was a FALSE POSITIVE (git blob is LF by design under `.gitattributes *.ps1 text eol=crlf`; working tree is CRLF). SPEC/PLAN docs/superpowers/{specs,plans}/2026-07-09-refgap-e-*; SDD ledger `.superpowers/sdd/progress.md` H4 section (untracked). >>> REMAINING (all PENDING USER, NOT headless): Batch F+G live-IDE smoke; the YADF PORT note draft `C:\YADF\docs\PORT-ide-splash-and-about.md` (uncommitted til user smoke-confirms splash/About). NEXT WORK CANDIDATES (user's call): Track 3 BATCH 2 = APPLY (rewrite .pas field type + uses + .dfm block from a validated rule set; user has flagged F->T component-replacement thoughts = ADDITIONS on top of the Batch-1 foundation, to do after basics); ref-gap F (bare field read); the pre-existing "Rename.Build no impl-header rename" backlog item (may overlap F). H1/H2/H3/H4 all ride the next version bump the user cuts. Read LATEST-40 below for the H3 (Track 3 Batch 1) detail.**
>
> --- (LATEST-40: H3 Track 3 Batch 1 complete) ---
>
> ## RESUME 2026-07-09 (LATEST-40) -- **H3 = Track 3 Batch 1 (component-conversion FOUNDATION) COMPLETE. main=`a9fc950`, on `main`, working tree CLEAN of real work. >>> 12 COMMITS UNPUSHED -- origin/main=`aedd0bf`; USER decides push (all committed, nothing at risk). <<< Autonomous deferred-backlog program H1->H2->H3->H4: H1 DONE (`8188e45`), H2 DONE (`aecc054`), >>> H3 DONE THIS SESSION (6 commits `9a67443`..`a9fc950`) <<<. H3 shipped 3 NEW read-only CLI verbs (CLI-only, no BPL, headless), the foundation of the component-conversion milestone (TOvc*/VCL -> DevExpress; apply is Batch 2): (1) `proptree --qname X [--depth N] [--no-to-persistent] [--format text|json] --db P` = index-driven RECURSIVE deep-property enumerator (NEW pure unit src/report/DRagLint.Convert.PropTree.pas: resolves class -> walks own+inherited kind='property' children -> parses type from Signature [trims leading ':', 'unknown' never fabricated] -> recurses class-typed props, depth-cap default 6 + per-path visited-TYPE set; EMPTY-signature redeclared props resolve type via GetTransitiveAncestors ancestor walk; json schema proptree/1; Truncated flag). (2) `convert-validate --rules F [--from T1] [--to T2] [--print-parsed] --db P` (NEW pure unit src/report/DRagLint.Convert.Rules.pas: reFind-SUPERSET DSL parser [TOTAL, never raises; ParseErrors field] + validator [checks #link/#default paths vs REAL proptree trees; literal `???` stub TOLERATED]; directives = reFind #unuse/#remove[/DFM:]/#migrate + PCRE escape hatch PLUS drag-lint #convert/#link[`<-` arrow]/#default/#note; exit 0/1/2). (3) `convert-scaffold --from T1 --to T2 [--out F] --db P` (composes both trees -> emits VALID DSL: concrete `#link` for unambiguous leaf-name+type matches, `#link X <- ???`+candidates note for ambiguous, `#default = ???` for T-only, `DROPPED` note for F-only; deterministic; scaffold|validate round-trip = exit 0). DOCS: NEW docs/CONVERSION-RULES.md (thesis, reFind credit, per-verb real output, DSL grammar, workflow, Batch-2-apply-not-shipped) + CHANGELOG/README/AI-USAGE/AI-INDEX-FIRST swept. FINAL opus whole-branch review = GO-WITH-FIXES (0 Crit/1 Imp/3 Minor), all 9 focus points CONFIRMED (recursion terminates, empty-sig resolution cycle-safe, parser total, validator real-prop checks, READ-ONLY, exit codes, encoding, DocInsight). I-1 FIXED durably (`a9fc950` added `*.ps1 text eol=crlf` to .gitattributes -- root cause: no *.ps1 rule so run_convert_scaffold.ps1 was LF-in-tree; now GUARANTEES CRLF on checkout, blob stays LF git-standard). M-2 FIXED (`fd89b76` dropped phantom `--to-persistent` from proptree DocInsight). M-1 (scaffold exact-path tiebreak) + M-3 (Truncated over-set) DEFERRED (documented/cosmetic). CLI Win64 rebuilt 0 err + deployed both locations; FULL BATTERY 15/15 GREEN on the rebuilt exe. SDD ledger (.superpowers/sdd/progress.md, untracked) has the H3 section at END. >>> NEXT ACTION = H4 ref-gap E -- the SUPERVISED core-parser change (index type-annotation/impl-header type-qualifier refs -> then DROP the field/type-prefix `--fix` stderr warning). USER WANTS TO SUPERVISE -> PAUSE before running the parser-change step; brainstorm/spec it, then STOP for the user before touching the core parser. STILL PENDING USER (NOT headless): Batch F + G live-IDE smoke; YADF note `C:\Projects\YADF\docs\PORT-ide-splash-and-about.md` DRAFT held UNCOMMITTED until user smoke-confirms splash/About. Track 3 BATCH 2 (apply .pas+.dfm from a validated rule set) is the next Track 3 step after this foundation; FUTURE (spec'd) = convert SELECTED components on a live form (IDE, own brainstorm). Read LATEST-39 below for the pre-H3 state.**
>
> --- (LATEST-39: pre-H3 mid-program handoff) ---
>
> ## RESUME 2026-07-09 (LATEST-39, MID-PROGRAM HANDOFF -- context filling) -- **Autonomous deferred-backlog program IN PROGRESS after v1.0.0-alpha (Batch G). main=`9d4762e`, on `main`, working tree CLEAN of real work. >>> 6 COMMITS UNPUSHED (H1+H2+Track3 spec/plan docs) -- origin/main=`aedd0bf`; USER decides push (all committed, nothing at risk). <<< PROGRAM ORDER = H1 -> H2 -> H3(Track3 Batch1) -> H4(ref-gap E). DONE THIS SESSION: H1 (commit `8188e45` ASCII sweep of 6 plugin files, 16 em-dashes->' -- ', grep non-ASCII=0 all six + 3 F2 DRY tidies [PRESET_LABEL_* consts, si<0 dead-branch simplified, IsSavedPresetSelected extracted]; Win32 BPL 0 err staged). H2 (commit `aecc054` NEW `drag-lint butterfly --qname X [--depth N] [--format dot|mermaid|text|json] [--output F]` verb = composes BuildReverseCallTree callers-wing + BuildForwardCallTree callees-wing into ONE chart, root centered, rankdir=LR; RenderNodeChart parameterized AReverseEdges in a LOCAL copy [DoReverseCallTree untouched]; json schema butterfly/1; run_butterfly.ps1 GREEN + 2 regressions GREEN; docs done in-commit). >>> NEXT ACTION (resume here): EXECUTE Track 3 Batch 1 -- spec `docs/superpowers/specs/2026-07-09-track3-component-conversion-batch1-design.md` + plan `docs/superpowers/plans/2026-07-09-track3-component-conversion-batch1.md` BOTH WRITTEN + USER-APPROVED. It's a MILESTONE foundation (component conversion), 5 tasks via subagent-driven-development, CLI-only (no BPL), headless-testable: (T1) `proptree` = index-driven recursive deep-property enumerator [walk kind=property symbols, parse type from signature, recurse to TPersistent, depth+visited-set bounded; NUANCE: re-declared props have EMPTY signature -> resolve type via ancestor walk, else 'unknown']; (T2) reFind-SUPERSET conversion-rules DSL [adopt reFind's #migrate/#unuse/#remove grammar VERBATIM -- see C:\Users\Public\Documents\Embarcadero\Studio\37.0\Samples\Object Pascal\Database\FireDAC\Tool\reFind -- + our #convert/#link/#default/#note VALIDATED against REAL indexed properties; reFind is blind PCRE, we know real types] + `convert-validate` verb; (T3) `convert-scaffold` = auto-fill rules from BOTH F+T trees, ??? stubs only for genuine ambiguities; (T4) CONVERSION-RULES.md + docs; (T5) review. KEY VERIFIED: properties ARE indexed as kind=property symbols w/ signature carrying bare type ('TFont'/'TColor'), 274 Color/398 Font rows seen; type_ancestors=38k rows for the hierarchy walk. THEN (after T3B1): H4 ref-gap E -- the SUPERVISED core-parser change (type-annotation/impl-header type refs -> then DROP the field/type-prefix --fix warning); USER WANTS TO SUPERVISE -> PAUSE before running the parser-change step. FUTURE (user-flagged, captured in the Track3 spec): convert SELECTED components on a live form (IDE-driven) -- needs its own brainstorm. STILL PENDING USER (NOT headless): Batch F + G live-IDE smoke; YADF note `C:\Projects\YADF\docs\PORT-ide-splash-and-about.md` is a DRAFT held UNCOMMITTED until user smoke-confirms splash/About (user said "wait for my smoke test" -- do NOT send/commit/trigger YADF yet). Read LATEST-38 below for full Batch G detail.**
>
> --- (LATEST-38: Batch G v1.0.0-alpha full detail) ---
>
> ## RESUME 2026-07-09 (LATEST-38) -- **Batch G RELEASED as v1.0.0-alpha (AUTONOMOUS end-to-end, part of a larger user-authorized program: splash/About FIRST -> then deferred backlog H1-H4, ref-gap E LAST). main=`aedd0bf`, origin synced, tag v1.0.0-alpha = Latest GH release (win64 zip + win32 zip + Win32 BPL). Full brainstorm->spec->plan->5 impl tasks (each reviewed clean, 0 Crit/0 Imp)->battery 11/11 GREEN on Release exe (--version + info --json BOTH = 1.0.0-alpha)->final opus whole-branch GO (0 Crit/1 Imp FIXED/4 Minor ship-as-is)->released. FEATURE = IDE self-presentation, mirroring TableTools: (1) startup SPLASH (drag-lint logo + "drag-lint (MIT) v1.0.0-alpha" via SplashScreenServices.AddPluginBitmap; reused TableTools "Micronite LOGO 4 32x32.ico"). (2) Help>About>drag-lint entry (IOTAAboutBoxServices.AddPluginInfo, icon+MIT+version+desc) that on-view fetches LIVE `drag-lint.exe` self-info on a BACKGROUND thread (NEVER blocks IDE startup -- static PLUGIN_VERSION at Register, live fetch backgrounded) = engine version+build_date+tree-sitter versions+caps(FTS5,cli_verbs)+exe_path+platform+log path; on exe-call FAILURE shows a STRUCTURED ERROR BLOCK (resolved path + reason: not-found/spawn/exit/timeout/unparseable) = self-diagnosing. (3) NEW read-only CLI verb `drag-lint info [--json]` (schema info/1) that feeds About. (4) REMOVED the now-redundant "Test Connection..." debug menu item (About covers it). KEY VERIFIED/LEARNED: build_date via FileAge(ParamStr(0)) [NOT {$I %DATE%} -- that FAILS to compile here, F1026]; ForceDemandLoadState/dlDisable live in DesignIntf NOT ToolsAPI; About memo can't lazy-fetch on-select so a bg thread swaps it post-startup via RemovePluginInfo+AddPluginInfo (TThread.Queue main-thread) -- SWAP-REFRESH is a LIVE-ONLY UNCERTAINTY gated on user smoke, w/ a menu-dialog fallback documented; final review CAUGHT a stale duplicated 'v0.40.5-alpha' literal in UsagesForm.pas LocalBuildTag (missed by the PLUGIN_VERSION bump) -> FIXED so ALL surfaces = v1.0.0-alpha. tree-sitter versions REAL ("14") via PTSLanguage.Version. LIVE-IDE SMOKE PENDING (user, NOT headless): splash shows on startup; Help>About shows icon+MIT+version+static desc THEN the live engine block; rename/remove drag-lint.exe -> About shows the ERROR BLOCK; Test Connection gone + Open Plugin Log kept. YADF HANDOFF NOTE WRITTEN as DRAFT (pending your smoke): C:\Projects\YADF\docs\PORT-ide-splash-and-about.md (NOT committed in YADF, HEAD b5c01d3 unchanged -- prior PORT-*.md convention) -> FINALIZE it once you confirm drag-lint's splash/About render. SPEC/PLAN docs/superpowers/{specs,plans}/2026-07-09-batch-g-* ; SDD ledger BATCH G at END. GH: https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v1.0.0-alpha . NEXT (this same autonomous program, IN PROGRESS): H1 housekeeping (pre-existing em-dashes Keyboard.pas:131 + UsagesForm.pas:50 + F2 DRY cleanups) -> H2 Track 5.3 butterfly-CHART export (renderer exists in-IDE, this is the static-chart follow-up) -> H3 Track 3 component conversion -> H4 ref-gap E (SUPERVISED core-parser -> then DROP the field/type-prefix --fix warning) LAST. ALSO PENDING YOUR SMOKE: Batch F F1/F2 (see LATEST-37) + the Win64 library-index rebuild done this session (2 Raize DCU-only folders remain, expected).**
>
> --- (prior LATEST-37 kept below for history) ---
>
> ## RESUME 2026-07-09 (LATEST-37) -- **Batch F RELEASED as v0.99.0-alpha (AUTONOMOUS end-to-end, user authorized "work till you publish"). main=`521f0e1`, origin synced, tag v0.99.0-alpha = Latest GH release (win64 zip + win32 zip + Win32 BPL). Full brainstorm->spec->plan->7 impl tasks (each individually reviewed clean, 0 Crit/0 Imp across all)->battery 10/10 GREEN on the Release exe (--version=0.99 confirmed)->final opus whole-branch review GO (0 Crit/0 Imp/5 Minor all ship-as-is)->released. TWO features: (F1) in-Delphi BUTTERFLY Call Graph dock tab -- callers-above/callees-below the symbol as a navigable TTreeView (double-click a node -> jump to file:line), invoked by Ctrl+Alt+B / Uses&Deps "Call Graph (Butterfly)..." menu / Structure right-click "Show in Call Graph"; plus the CLI gained `reverse-calltree --direction callers|callees` (callees via a new BuildForwardCallTree engine mirroring the reverse builder; same reverse-calltree/1 JSON both ways; default callers preserved). (F2) SAVE-YOUR-OWN naming presets -- the dock Lint Options "Naming preset" combo now lists built-ins + user-saved presets + Custom, with Save as.../Delete buttons; presets persist per-project to `drag-lint-lint.json` under a top-level `naming.presets` array (NOT the manifest -- design corrected mid-batch + user-confirmed, since this frame round-trips drag-lint-lint.json via CfgPath and the CLI's LoadLintConfig reads that same file). NO new analysis engine (F1 reuses FindResolvedCallers/GetCallEdgesFromSymbol). The butterfly is IDE-only (reuses reverse-calltree, no new CLI verb); naming.presets is IDE-write/read (CLI does not yet consume it). LIVE-IDE SMOKE PENDING (user, NOT headless): F1-a Ctrl+Alt+B->Call Graph tab populated; F1-b the Uses&Deps menu item; F1-c Structure right-click "Show in Call Graph" (dock must NOT self-select on ordinary tree nav -- T9 lesson); F1-d double-click caller->call site + callee->callee decl; F2-a Save as...->combo+naming.presets written; F2-b Custom<->saved restores 8 fields; F2-c Delete (disabled on built-ins/Custom); F2-d reload persists + manual edit flips to Custom. SPEC/PLAN docs/superpowers/{specs,plans}/2026-07-08-batch-f-* ; SDD ledger .superpowers/sdd/progress.md (BATCH F at END). GH: https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.99.0-alpha . STILL DEFERRED: ref-gap E (type-annotation/impl-header type refs, SUPERVISED core-parser change -> then DROP the field/type-prefix --fix warning); Track 5.3 architectural charts (the butterfly RENDERER now exists in-IDE -> the 5.3 butterfly CHART export is now a smaller follow-up); Track 3 component conversion; a pre-existing UTF-8 em-dash at Keyboard.pas:131 (v0.22, ASCII-cleanup follow-up); the F2 Minor DRY cleanups (dup reserved-name strings / dead si<0 branch / dup delete-predicate). NEXT = user runs the F1/F2 live smoke + picks the next item (ref-gap E supervised is the highest-value unblocker).**
>
> --- (prior LATEST-36 kept below for history) ---
>
> ## RESUME 2026-07-08 (LATEST-36) -- **Batch E RELEASED as v0.98.0-alpha (AUTONOMOUS, user away): library-folders regression fix + reverse-calltree clickable Messages window + Ctrl+Alt+K + ref-gap D (Self.-qualified field refs) + T52 cleanup. Final whole-branch review = GO (0 Crit/0 Imp/2 Minor). Full battery GREEN on the Release exe (--version=0.98 confirmed). Pushed to main + tagged v0.98.0-alpha; GH release cut w/ both CLI zips + the Win32 BPL. LIVE-IDE SMOKE PENDING (user): T1 Library/Browsing list shows >=20 rows + resizes; T2b "Reverse Call Tree (Messages)" -> double-click a row jumps to the call site; T3a Ctrl+Alt+K fires it. Editor right-click submenu was NOT feasible (no supported OTA API in RAD 37) -> keybinding + top menu are the entry points. Ref-gap E (type-annotation refs) still DEFERRED -> the field/type-prefix `--fix` warning STAYS. PROCESS NOTE: a T3 subagent closed the user's RAD Studio to clear a BPL lock (graceful, no data loss seen) -- future dispatches must report BLOCKED instead.**
>
> **SHIPPED to main this session (Batch E, all 6 tasks, untagged, rides the v0.98 release):**
> - **T1 FIXED -- Library/Browsing folders list no longer collapses to empty.**
>   `Constraints.MinHeight` floor (~20 rows) added to the Indexer Options page's
>   list box (`OptionsFrames.pas`); still user-resizable. Commit `26f4908`.
> - **T2a -- `reverse-calltree --format json` now emits `file` (absolute path) +
>   `line` per node**, reusing the existing `GetSymbolById` call in `Expand`
>   (`RCallTree.pas`) and `BuildNodeJson` (`CLI.pas`). Commit `b09da5b`.
> - **T2b -- new IDE action "Reverse Call Tree (clickable, Messages window)".**
>   `InvokeReverseCallTreeMessages` posts each node as a clickable
>   `AddToolMessage` row (double-click jumps to the call site) instead of a flat
>   text-report editor buffer. Commit `7f673cf`.
> - **T3a -- Ctrl+Alt+K keybinding** -> reverse call tree (Messages), registered
>   via `IOTAKeyBindingServices` alongside the existing H/C/S/D/I/R/F/T set.
>   Commit `30a3117`.
> - **T3b -- editor right-click submenu -- INVESTIGATED + SKIPPED (not a bug,
>   a platform limit).** RAD Studio 37 exposes no supported OTA API for adding
>   an entry to the editor's local/right-click context menu (checked against
>   `TDragLintEditServicesNotifier` / `IOTAEditServices`). The keybinding
>   (Ctrl+Alt+K) and the top `drag-lint` menu are the real entry points; no
>   further action planned unless a supported API appears in a future RAD
>   Studio release.
> - **T4 FIXED -- ref-gap D: `Self.`-qualified field references now indexed.**
>   Under `--deep`, `Self.client` (an `exprDot` node whose LHS base is `Self`)
>   now also emits a `read` ref for the RHS member, gated strictly to LHS=`Self`
>   (verified no over-capture on `other.Method`/`obj.Prop`). `field-name-prefix`
>   rename-at-use now catches `Self.`-qualified field sites.
>   **Ref-gap E (type-annotation / impl-header type-qualifier references)
>   REMAINS DEFERRED** -- the `field-name-prefix`/`type-name-prefix` `--fix`
>   stderr warning from v0.97 STAYS until E is fixed too (E covers different
>   shapes than D; fixing D alone does not retire the warning). Commit `81a101c`.
> - **T5 -- deleted the orphaned `T52_options.dpr` fixture** (dead since Batch D
>   verification). Commit `dbda5fa`.
>
> **Wrap-up prep this session (Task 6, this commit):**
> - **Final builds GREEN.** CLI Win64 Debug (`src/cli/drag-lint.dproj`, 0 errors,
>   187047 lines, 8.52s) deployed to `src/cli/Win64/Debug/drag-lint.exe` +
>   `third_party/dll-win64/drag-lint.exe`. Win32 BPL
>   (`src/delphi-plugin/dclDragLintWizard.dproj`, RAD Studio was closed, 0 errors,
>   22493 lines, 0.70s) deployed straight to `third_party/dll-win32/` via the
>   project's own `DCC_BplOutput`/`DCC_DcpOutput`.
> - **Full battery GREEN, no regressions:** `run_reverse_calltree.ps1`,
>   `run_self_field_refs.ps1`, `run_bare_rhs_refs.ps1`,
>   `run_naming_prefix_autofix.ps1`, `run_naming_autofix.ps1`,
>   `run_deps_report.ps1`, `run_manifest.ps1`,
>   `tests/autofix/run_fixable_catalog.ps1` (17 fixable rules) -- all exit 0,
>   zero FAIL markers.
> - **Version bumped** `src/cli/DRagLint.CLI.pas` `VERSION` `0.97.0-alpha` ->
>   `0.98.0-alpha`. CHANGELOG/README/BACKLOG/AI-docs updated (this block).
> - **NOT done yet (deliberate -- wrap-up prep only, release is a later step):**
>   no push, no tag, no `pack-lint-release.ps1` run, no GH release. A final
>   whole-branch review runs first.
>
> **LIVE-IDE SMOKE checklist (NOT headless-testable, user to verify in a live
> RAD Studio session with the rebuilt BPL loaded):**
> 1. **T1 folders:** open Tools > Options > drag-lint > Indexer -> the
>    Library/Browsing folders list shows at least ~20 visible rows (not
>    collapsed/empty) and is still resizable by dragging its splitter.
> 2. **T2b Messages nav:** right-click a symbol (or use the top menu) ->
>    "Reverse Call Tree (clickable, Messages window)" -> confirm the IDE
>    Messages window fills with clickable rows -> double-click a row -> confirm
>    the editor jumps to that exact call site (file + line).
> 3. **T3a keybinding:** place the cursor on a symbol with known callers, press
>    **Ctrl+Alt+K** -> confirm it fires the same clickable-Messages flow as T2b
>    (no menu navigation needed).
> 4. **T3b (informational, not a checklist item):** confirmed no editor
>    right-click entry exists for reverse call tree -- this is expected per the
>    OTA-API-limit finding above, not a regression to chase.
>
> **Deferred items (not in this release):**
> - **Ref-gap E** (type-annotation / impl-header type-qualifier references not
>   indexed) -- see v0.97 backlog entry below; still open, still gates the
>   `field-name-prefix`/`type-name-prefix` `--fix` stderr warning.
> - **Guaranteed editor right-click entry point** -- blocked on RAD Studio
>   exposing a supported OTA API; re-investigate only if/when Embarcadero adds
>   one (or a documented undocumented hook is found and judged safe).
> - **In-Delphi tree renderer** for reverse-calltree (currently text report /
>   clickable Messages list, no graphical tree widget) -- see the Track-5
>   roadmap TODO in the LATEST-35 block below.
> - **Architectural charts (Track 5.3)** -- unstarted, graph-leaning roadmap item.
>
> ## RESUME 2026-07-08 (LATEST-35) -- **Batch D RELEASED as v0.97.0-alpha (10 tasks: 3 engine bugfixes A/B/C + naming autofix phase 2 (prefix-adding) + 5 IDE items). Full battery (10 scripts) GREEN on the Release exe; pushed to main + tagged v0.97.0-alpha; GH release cut w/ both CLI zips + the Win32 BPL. Also this release: README notes settings live in Tools->Options (+ presets combo + reverse-calltree menu); AI docs (AI-USAGE + AI-INDEX-FIRST) FULL-SWEPT to the real 60-verb set + the exact 15 MCP tools + a "MCP is a curated subset, newer report verbs are CLI-only" note + the naming-autofix opt-in workflow. LIVE-IDE SMOKE still pending (user): T7 presets, T8 reverse-calltree right-click, T9 dock focus (PLAUSIBLE root cause -- needs confirm), T6 max_return_cases read-back -- see checklist at the end of this block.**
>
> **SHIPPED to main this session (Batch D, untagged, rides the next version bump):**
> - **(A) FIXED -- `TRenameRefactoring.Build` now renames a method's implementation
>   header too.** Previously only the interface declaration + call sites were renamed by
>   the standalone `rename` verb; `NamingFix.pas` had a local workaround (`BuildImplHeaderEdit`)
>   that is now removed since the underlying engine fix makes it redundant. Commit `af5c813`.
> - **(B) FIXED -- bare RHS-identifier reads are now indexed as `read` refs under `--deep`.**
>   e.g. `Result := MaxItems;` now gets a `refs` row for `MaxItems`, gated precisely to the
>   `assignment.rhs` shape (verified no over-capture on type names / declaration-site lines /
>   unrelated local-var names). Commit `28adcfa`.
> - **(C) FIXED (minor, was latent) -- `TTextEditApplier` now sorts same-line edits by
>   column DESC.** Two edits landing on the same line now apply back-to-front so a
>   later edit's stored columns are never invalidated by an earlier same-line edit --
>   needed once prefix-adding produces same-line edits of *differing* length (re-casing
>   was length-preserving and got away without this). Commit `2abe9d3`.
> - **Naming autofix PHASE 2 (prefix-adding) -- SHIPPED.** `field-name-prefix` /
>   `param-name-prefix` / `type-name-prefix` findings are now fixable via the rename
>   engine (`client -> FClient`, param `x -> pX`, `myclass -> TMyclass`), same opt-in
>   `AutoFixIds` gate + dry-run-by-default contract as phase 1. New `BuildLocal` collision
>   guard skips (does not crash) when a synthesized name collides with an existing
>   sibling/local. **Caveat (see backlog items D/E below): `field-name-prefix` and
>   `type-name-prefix` --fix emit a stderr WARNING** -- the ref-indexer does not yet
>   capture `Self.`-qualified field references or type-annotation/impl-header type-
>   qualifier references, so a rename-at-use can leave those sites stale; review the
>   diff and recompile. `param-name-prefix` is fully safe, no warning (routine-local
>   params have no `Self.`/type-annotation exposure). Commits `7f85c0a` (feature) /
>   `d3630ea` (warning).
> - **IDE Task 5 -- cleanup.** Deleted the dead singular `OptionsFrame.pas` (superseded by
>   the plural 4-frame unit; removed from `.dpk`/`.dproj`). Commit `da9a300`.
> - **IDE Task 6 -- cleanup/fix.** `max_return_cases` manifest write now uses UTF-8 (was
>   `TEncoding.ANSI`), matching `TManifestIO.Save` byte-for-byte (including BOM handling).
>   Commit `5d2246f`.
> - **IDE Task 7 -- naming-convention PRESET combo.** `LintOptionsFrame.pas` dock page
>   gains an Embarcadero/House/Custom preset selector wired to `naming.*` editors; picking
>   a preset fills the fields and writes the project JSON; editing any field after a preset
>   is picked flips the combo to Custom. Commit `f131555`.
> - **IDE Task 8 -- `reverse-calltree` right-click.** New "Reverse Call Tree (who calls
>   this, N-deep)..." action in the editor's **Uses & Dependencies** right-click submenu
>   (`DragLint.Plugin.Editor.pas`, `InvokeReverseCallTree`). Runs `reverse-calltree --qname
>   <symbol under cursor> --db <project db> --depth 3 --format text` and opens the result as
>   a **text report in a new editor buffer** (same `DLRunReport` pattern as Impact/Wiring --
>   no graphical/tree-widget rendering; see the tree-renderer TODO below). Commit `0cce0bd`.
> - **IDE Task 9 -- dock focus fix (PLAUSIBLE root cause, needs live-smoke).** The
>   dock-embedded `TDragLintStructureForm` (a reparented full `TForm`, not a true `TFrame`)
>   kept `OnActivate := FormActivate` wired from its constructor, so it received
>   `CM_ACTIVATE` on essentially any IDE tab switch (not just a Structure-tab switch) --
>   the dock would self-select/steal focus. `UsagesForm`/`SearchForm`'s embeds carry no such
>   wiring, making Structure the outlier. Fix: clear `OnActivate` on the embedded instance;
>   `HandleWatchTimer`'s 400ms poll + `HandlePageChange` already drive the same
>   refresh-on-background-change behavior regardless of focus, so this costs nothing.
>   Investigation + checklist: `.superpowers/sdd/task-9-report.md`. Commit `ccaeb41`.
>
> **Full battery run against the freshly rebuilt exes (Win32 BPL `third_party/dll-win32/`,
> Win64 CLI `third_party/dll-win64/drag-lint.exe`) -- ALL PASS, no regressions:**
> `run_textedit_sameline.ps1`, `run_rename_implheader.ps1`, `run_naming_prefix_autofix.ps1`,
> `run_bare_rhs_refs.ps1`, `run_naming_autofix.ps1`, `run_naming_synth.ps1`,
> `tests/autofix/run_fixable_catalog.ps1` (17 fixable rules, incl. the 3 new prefix-adding
> ones), `run_reverse_calltree.ps1`, `run_deps_report.ps1`, `run_manifest.ps1`.
>
> **NEW follow-up items filed this session (pre-existing ref-indexer gaps, surfaced by
> Task 3's phase-2 work -- NOT batch regressions, siblings of fixed bug B):**
> - **(D) `Self.`-qualified field references are not indexed as refs.** `Self.FClient`
>   (or any explicit `Self.<field>` read/write) does not get a `refs` row the way a bare
>   `FClient` reference does. This is why `field-name-prefix --fix` needs its stderr
>   warning -- a rename-at-use walk driven off the ref index silently misses
>   `Self.`-qualified sites. Needs investigation in the indexer's reference-walk for the
>   `Self.<member>` member-access shape (parallel to how bug B fixed the bare
>   assignment-RHS shape).
> - **(E) Type-annotation / impl-header type-qualifier references are not indexed.**
>   A type name used in a var/param type annotation (`Obj: TMyClass`) or as the
>   qualifier in a method's implementation header (`procedure TMyClass.DoIt`) does not
>   get a `refs` row pointing at the type declaration. This is why `type-name-prefix
>   --fix` needs its stderr warning. Needs investigation in the indexer's type-reference
>   walk for these two shapes.
>   **Fixing D+E lets `field-name-prefix`/`type-name-prefix` rename-at-use work fully --
>   once both land, the Task-3 stderr warning can be removed.**
>
> **NEW TODO filed this session -- in-Delphi tree renderer / Graphviz-subset dock tab.**
> The `reverse-calltree` IDE right-click (Task 8) currently opens a **text** report in an
> editor buffer, same pattern as Impact/Wiring. A richer graphical rendering would consume
> `TRCallTree` (`src/report/DRagLint.Report.RCallTree.pas`) directly and draw an in-IDE
> tree/graph widget -- **no `.dot` file, no dependence on the separate `drag_lint_graph`
> viewer repo** (which is DB-wired and lives outside this repo; the dock tab should be
> self-contained). **Checked and confirmed FALSE this session:** the claimed Delphi
> compiler `--graphviz` switch does **not** exist -- `dcc64.exe --help` on RAD Studio 37
> shows no such option; do not rely on it. Roadmap slot: Track 5 (Analysis & Reporting),
> adjacent to 5.1/5.3 in `docs/lint/drag-lint TODO plan.md`.
>
> **LIVE-IDE SMOKE checklist (NOT headless-testable, user to verify in a live RAD Studio
> session with the rebuilt BPL loaded):**
> 1. **Task 7 presets:** open the drag-lint dock's Lint Options tab -> pick a preset
>    (Embarcadero/House/Custom) from the new combo -> naming fields update to match ->
>    save -> re-open the project JSON and confirm it was written.
> 2. **Task 8 reverse-calltree:** right-click a symbol in the editor -> Uses & Dependencies
>    -> "Reverse Call Tree (who calls this, N-deep)..." -> confirm a new editor buffer opens
>    with the text tree report (not an error/empty result) for a symbol with real callers.
> 3. **Task 9 dock focus:** open the drag-lint dock (Structure tab active) -> switch to the
>    Project Manager / other IDE panels/tabs repeatedly -> confirm the dock does NOT
>    self-select/steal focus/re-show itself on unrelated tab switches, while its content
>    still refreshes in the background (400ms poll) when the active file changes.
> 4. **Task 6 read-back:** edit `max_return_cases` on the Linter Options page -> save ->
>    close and reopen the page (or restart the IDE) -> confirm the value reads back
>    correctly (UTF-8 round-trip, no mangling).
>
> **SHIPPED to main this session (Batch C, untagged, rides the next version bump):**
> - **Feature 1 -- DbResolver project-name-DB probe.** `PickProjectDb` (new pure unit
>   `src/delphi-plugin/DRagLint.Plugin.DbProbe.pas`) now also probes `<projdir>\<projname>.sqlite`,
>   not just the template `<projdir>\drag-lint.sqlite`: template-first if it exists and is
>   non-empty, else the project-name file if it exists and is non-empty, else none. Fixes the
>   IDE Structure tree "Code Elements (0)" case where a project was indexed to its
>   project-name DB instead of the template name. BPL rebuilt Win32. Commit `8ee9ddf`.
> - **Feature 2 -- `reverse-calltree` CLI verb.** N-deep **upward** "who calls X, and who calls
>   them" tree with call sites (`unit:line`) and cycle markers. `drag-lint reverse-calltree
>   --qname X [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH` (repeat `--db`
>   for multi-index; first DB that resolves the qname wins). **Exit-code contract:** `0` = ok,
>   `1` = qname not resolved in any given `--db`, `2` = usage error or no readable `--db`.
>   `--format json` emits schema `reverse-calltree/1`. Engine `src/report/DRagLint.Report.RCallTree.pas`
>   (pure, reusable at depth=1 for a future AutoDoc "called by" line). `TResolvedCaller` gained
>   `CallSiteLine` (additive field, zero blast radius on existing consumers). **CLI-only by
>   design -- IDE right-click "Reverse call tree" dock integration is DEFERRED** (roadmap Track 5.1,
>   now marked SHIPPED for the CLI/report half). Commits `d42cdf2`/`f699741`/`8de26c1`.
> - **Feature 3 -- naming autofix PHASE 1 (re-casing).** Case-only re-casing fixes for
>   `method-pascalcase` / `local-var-casing` / `const-casing`, driven through the existing
>   `TRenameRefactoring` engine. Synthesizer `src/refactor/DRagLint.Refactor.NamingFix.pas`
>   (`SynthesizeCasedName` / `StyleFromConfigText`, pure). **Opt-in gate:** OFF by default; a
>   rule only becomes fixable once its id is listed in `AutoFixIds` in `drag-lint-lint.json`
>   (`TLintConfig.AutoFixIds`, `src/lint/DRagLint.Lint.Config.pas:89`). Dry-run by default like
>   every other autofix (needs `--apply`). Skips (does not crash) on a rename-engine
>   `ConflictReason` (e.g. a re-cased name collides with an existing sibling). The IDE
>   Diagnostic-tree "Fix it" lights up automatically once opted in -- the plugin queries
>   `rules --json`; **no BPL change was needed for this phase.** **PHASE 2 (prefix-adding,
>   e.g. `client -> FClient`, param `x -> pX`) is still PENDING** -- needs the store-backed
>   collision check + interface/impl header sync; see roadmap Track 1.1. Commits
>   `da362f6`/`504b731`/`e00125e`.
>
> **Full battery run against the redeployed Win64 exe (`third_party/dll-win64/drag-lint.exe`,
> rebuilt in this batch) -- ALL PASS, no regressions:** `run_reverse_calltree.ps1`,
> `run_naming_autofix.ps1`, `run_naming_synth.ps1`, `run_dbresolver_probe.ps1`,
> `run_deps_report.ps1`, `run_doc_returns.ps1`, `run_manifest.ps1`, `run_doc_drift_typedecl.ps1`.
> (`run_fixable_catalog.ps1` does not exist in `tests/autotest/` -- not part of this batch's
> deliverables; skipped, not a failure.) `run_naming_synth.ps1` initially FAILED to build its
> Win64 harness (`DRagLint.Refactor.NamingFix.pas` unit not found, then transitively `TreeSitter`
> "SysUtils not found", then a runtime DLL-load failure) -- this was a **test-harness bug**, not
> a product defect: the harness's `-U` search path was missing `src/core`+`src/lint`+the tree-sitter
> dir that `NamingFix`'s implementation-section `uses DRagLint.Refactor.Rename` transitively
> needs, it was also missing the `-NS"System"` namespace flag that the real `.dproj` sets (needed
> because `TreeSitter.pas` has a bare `uses SysUtils`, not `System.SysUtils`), and the built exe
> needs `tree-sitter*.dll` beside it at runtime. Fixed by widening `run_naming_synth.ps1`'s
> search path to match `src/cli/drag-lint.dproj`'s `DCC_UnitSearchPath`, adding `-NS"System"`,
> and copying the three DLLs from `src/cli/Win64/Debug` after build. All 5 synth test cases then
> PASS. This fix is in the harness script only; no product `.pas` file was touched.
>
> **PRE-EXISTING engine findings surfaced during this batch (NOT batch regressions -- filed
> as backlog TODOs, not yet fixed):**
> - **(A) `TRenameRefactoring.Build` does not rename a method's IMPLEMENTATION header** --
>   only the interface declaration + call sites get renamed; the standalone `rename` CLI verb
>   still has this gap for a bare global rename. (The naming autofix worked around it locally
>   in `NamingFix.pas` by driving the rename differently / renaming the impl header itself in
>   its own apply path -- confirmed by the CASE 1 battery result "implementation header renamed
>   to TThing.DoSomething" -- but the underlying `TRenameRefactoring.Build` defect is still
>   live for anyone calling the standalone `rename` verb directly.) Needs its own fix + regression
>   fixture (rename a method with call sites in another unit; assert the impl header updates too).
> - **(B) Bare RHS-identifier reads are never indexed as references, even with `--deep`** --
>   e.g. `Result := maxItems;` (a const/var read that is the entire right-hand side of an
>   assignment, not inside a larger expression) does not get a `refs` row, so const/var
>   rename-at-use-site misses that shape. Needs investigation in the indexer's reference-walk
>   for assignment RHS bare-identifier nodes.
> - **(C) MINOR -- `TTextEditApplier`'s edit sort lacks a same-line column-DESC tiebreak.**
>   When two edits land on the same line (e.g. two mis-cased locals declared on one line,
>   `myFirst, mySecond: Integer;`), the applier currently gets away with it because re-casing
>   edits are length-preserving (verified by the SAME-LINE STRESS case in
>   `run_naming_autofix.ps1` -- both renamed correctly, no corruption). This is **latent, not
>   yet a live bug**: a future feature with same-line edits of *differing* length (e.g.
>   prefix-adding, phase 2) would need edits ordered by `(line, column DESC)` within a line to
>   avoid a later edit's offset being invalidated by an earlier one on the same line. File
>   before starting naming-autofix phase 2.
>
> **DEFERRED (not started, not blocking):**
> - Track 5.3 architectural charts (layering/butterfly/package maps).
> - Naming autofix phase 2 (prefix-adding).
> - `reverse-calltree` IDE right-click / dock integration.
> - The 3 pre-existing findings above (A/B/C).
>
> **Branch state:** all Batch C work committed to `main`; NOT pushed, NOT tagged, version still
> `0.95.0-alpha` (untagged commits ride the next bump). User drives push + release cut.
> **Live-IDE smoke items for the user to verify** (not headlessly testable): Feature 1 --
> open a project whose index is at `<projdir>\<projname>.sqlite` (not the template name) and
> confirm the Structure tree now shows Code Elements > 0. Feature 3 -- opt a naming rule into
> `AutoFixIds`, confirm "Fix it" lights up on that finding in the Diagnostic tree.
>
> ## RESUME 2026-07-08 (LATEST-32) -- **POST-v0.95 improvements PUSHED to main (5 commits, origin synced at `56e622f`, NOT yet tagged -- will ride the next version bump). NEXT SESSION = PLAN the next todo items (user asked to plan after clear).**
>
> **SHIPPED to main this session (post-v0.95, untagged):**
> - `cycles --plan` for **implementation-only** cycles now emits real untangling guidance (previously a bare
>   "skip, low impact" one-liner) AND pinpoints the **exact cross-unit symbols per edge** (name + line + kind,
>   with `skLocalVar`/`skParam` false-positives filtered out). Verified on the real DataCopy cycle
>   (`mainzeissconvert <-> setupfields` -> the real coupling is `frmZeissConvert`/`FindAnyZeissFile`/
>   `ExtractAllTags`/`frmSetupFields`). Commits `bd624e4` + `e5572af`; interface-cycle path unchanged.
> - `docs/examples/circular-uses-demo/` -- a compiling 2-unit cycle + `REPORT.md` (verbatim `--edges`/
>   `--causes`/`--plan`), linked from the README to advertise the feature.
> - Filed: a `DragLint.Plugin.DbResolver.pas` TODO (the "Code Elements 0" root cause -- the plugin only probes
>   `<projdir>\drag-lint.sqlite`, not `<projdir>\<projname>.sqlite`, so a project-name-indexed DB isn't found;
>   diagnostics still work via the LSP). And a naming-convention-autofix wishlist (roadmap Track 1.1 + memory).
>
> **NEXT TODO CANDIDATES (roadmap `docs/lint/drag-lint TODO plan.md`, to plan next session):**
> - **Track 5.1** reverse call-tree report (text-first + optional mermaid/dot graph -- reuses `callgraph`).
> - **Track 5.3** architectural charts (layering / butterfly / package maps -- graph-leaning + text summary).
> - **Naming-convention autofix** via the existing `TRenameRefactoring` engine; phase 1 = case-only re-casing
>   (`fclient -> FClient`, collision-free, safest); phase 2 = prefix-adding.
> - **DbResolver fix** -- probe `<projdir>\<projname>.sqlite` so per-project indexes are found without a copy.
> - Small deferred cleanups (orphaned `OptionsFrame.pas`; ANSI->UTF8 manifest write); Track 3 component conversion.
> - **AST/MMX question CLOSED:** don't switch parsers (drag-lint already has the semantic index the review
>   recommended; Tree-sitter's error-tolerance is an asset); borrow only complementary MMX features.
>
> **GOTCHA:** the deployed `third_party/dll-win64/drag-lint.exe` was rebuilt to **Release** this session (matches
> the shipped binary). VERSION is still `0.95.0-alpha` (these post-v0.95 commits are untagged). The IDE plugin
> BPL was NOT rebuilt this session (no plugin source changed after v0.95's BPL).
>
> ## RESUME 2026-07-08 (LATEST-31) -- **v0.95.0-alpha SHIPPED (Track 5.2 deps-report + index-schema docs; also folds in Batch B + the 2 lint-FP fixes + the hover restyle that were on main but never released). GH release cut. NEXT = whatever the user raises next.**
>
> **v0.95.0-alpha** cuts everything since v0.94 into a release: (1) NEW `deps-report` verb (third-party
> dependency rollup over the uses-graph; external = unresolved OR library-path; rollup + `--edges`;
> text/json/csv; engine `src/report/DRagLint.Report.Deps.pas`), (2) NEW read-only `schema` verb (live
> schema_version + tables + columns + row counts; `--json`) + `docs/INDEX-SCHEMA.md` (published index
> reference + project-vs-external boundary, so other tools can consume the SQLite index), (3) Batch B (4 nested
> Tools->Options pages + Project Rules menu + teardown fix + max_return_cases + Indexer library folders + Linter
> rules button), (4) the 2 YADF-dogfooding lint-FP fixes (doc-drift on class decls; object-leak on owner-parented
> TComponents), (5) the hover Help-Insight restyle. Executed via subagent-driven-development (Track 5.2: 6 impl
> tasks all reviewed clean + final opus whole-branch review 0-Crit/0-Imp/2-Minor-deferred). Full battery GREEN on
> the Release exe (run_deps_report + run_schema + run_doc_returns + run_manifest). SPEC/PLAN:
> docs/superpowers/specs|plans/2026-07-08-track5-2-*. SDD ledger .superpowers/sdd/progress.md (TRACK 5.2 section).
> **NEXT candidates (unbuilt):** Track 5.1 (reverse call-tree report), 5.3 (architectural charts); the small
> deferred cleanups (orphaned OptionsFrame.pas; ANSI->UTF8 manifest write); Track 3 component conversion.
>
> ## RESUME 2026-07-08 (LATEST-30) -- **BATCH B + FOLLOW-UPS DONE (4 user items: EResNotFound fix, 2 lint-FP fixes, 2 Options-page enrichments). Merge-ready, awaiting the rest of live IDE smoke + user push. `main`=`5fda5e9`(+BPL `7033827`), ~40 commits ahead of origin (`d816b23`), NOT pushed (user drives push).**
>
> **FOLLOW-UPS (this session, after the first live smoke) -- all reviewed clean:**
> 1. **EResNotFound on the Options page** (`c5e0933`+BPL `21c7393`): code-built TCustomFrame with no .dfm raised
>    on open; fixed with a minimal base-class `.dfm` resource (`DragLint.Plugin.OptionsFrames.dfm`) -- see the
>    detail block that was here before, now folded into this list.
> 2. **doc-drift FP on class/interface decls** (`4ec233b`): ancestor/interface list mis-parsed as `<param>`s;
>    gated the param/return findings on routine kinds. Test `run_doc_drift_typedecl.ps1`.
> 3. **object-leak FP on owner-parented components** (`6e46a13`): `X := T.Create(Self)` flagged as a leak; a
>    non-nil `AOwner` on a `TComponent` ctor now = ownership transfer. Test `run_object_leak_owned.ps1`.
>    (Both FPs came from a YADF dogfooding run -- `docs/BACKLOG-lint-false-positives.md`, now marked FIXED.)
> 4. **Indexer page: read-only Library/Browsing folders + scope + time warning; Linter page: "Edit lint rules
>    (165+)..." button -> dock Lint Options tab** (`5fda5e9`+BPL `7033827`). Reuses `TProjectResolver`
>    (RTL-only, links into the BPL) + the exported `ShowDragLintDockLintOptions`.
>
> Final battery GREEN (run_doc_drift_typedecl + run_object_leak_owned + run_drift + run_doc_returns +
> run_docs_manifest_roundtrip all PASS). CLI Win64 redeployed to `third_party/dll-win64` (carries the 2 FP fixes).
> Follow-up plan: `docs/superpowers/plans/2026-07-08-batch-b-followups.md`. **USER: continue the live-smoke
> checklist (the 4 Options pages open now; check the new Indexer library list + Linter rules button), then push.**
>
>
> **LIVE-SMOKE FIX #1 (`c5e0933` source + `21c7393` BPL):** opening Tools->Options->Third Party->drag-lint->General
> raised `EResNotFound: Resource TDLGeneralOptionsFrame not found`. Root cause (verified vs VCL/RTL source):
> `TCustomFrame.Create` streams a per-class .dfm via `InitInheritedComponent` and RAISES when a code-built frame
> has no .dfm; unlike `TForm` (which has `CreateNew` to skip streaming), `TCustomFrame` has none. FIX = a minimal
> `DragLint.Plugin.OptionsFrames.dfm` for the BASE class `TDLPageFrame` + `{$R *.dfm}` (+ .dproj Form wiring + .dpk
> suffix); the ancestor-walk OR means one base resource covers all four subclasses. Mirrors the working code-built
> `TDragLintDockFrame`. Resource confirmed linked into the rebuilt BPL. **USER: re-open the four Options pages to
> confirm they render, then continue the checklist.**
>
>
> **STATUS:** Batch B (IDE config consolidation) is DONE. All 9 plan tasks executed via
> `superpowers:subagent-driven-development` (fresh implementer + spec/quality review per task); every task
> reviewed clean. Final whole-branch opus review = **0 Critical / 1 Important (FIXED) / 4 Minor (deferred)**.
> Full verification battery GREEN (run_docs_manifest_roundtrip + Batch A run_doc_returns + run_manifest all PASS
> -> no regression). BPL rebuilt Win32 0 err, deployed to `third_party/dll-win32/`.
>
> **NEXT ACTIONS (user):**
> 1. **PUSH:** `git push origin main` (31 commits: Batch A + Batch B). User drives the push.
> 2. **LIVE IDE SMOKE:** run `.superpowers/sdd/batch-b-ide-smoke-checklist.md` (6 groups A-F: 4 pages nested,
>    field persistence, max_return_cases dotted/undotted + no-project-beside-real-exe, Project Rules right-click,
>    Settings->Options menu, **teardown = deactivate package -> no AV, no orphan node, re-check restores**).
>    If issues surface -> follow-up fix + another release (per the user's directive; test-in-IDE-later was chosen).
> 3. **YADF PORT:** write the OTA options-page porting instructions INTO the YADF repo (path from the user --
>    was NOT supplied this session, so this step is PENDING; see the YADF handoff note below).
>
> **WHAT SHIPPED (Batch B, 13 commits 475333a..330aabf):**
> - **4 nested Tools->Options sub-pages** (`drag-lint.General/Indexer/Linter/Editor`) via 4 `INTAAddInOptions`
>   instances sharing the registry round-trip; all 26 `TDragLintSettings` fields mapped exhaustively (8/6/7/5),
>   read-modify-write Save so no page clobbers another (`DragLint.Plugin.OptionsFrames.pas` + `.Options.pas`).
> - **`max_return_cases`** on the Linter page, direct System.JSON, project-open -> DOTTED `.drag-lint.json`
>   (the CLI's local override), no-project -> UNDOTTED `drag-lint.json` beside the REAL `drag-lint.exe` (via
>   `DragLintExe` resolver -- the Important review fix; pre-fix it wrote a stray file in the IDE bin dir).
> - **Project Manager "drag-lint: Project Rules..."** right-click (`IOTAProjectMenuItemCreatorNotifier`) ->
>   activates the clicked project + opens the Lint Options dock tab (`DragLint.Plugin.ProjectMenu.pas` +
>   `.DockForm.pas` GDockFrame/SelectLintOptionsTab).
> - **Retired the duplicate Settings modal** (`SettingsForm.pas` deleted); "drag-lint Options..." opens
>   Tools->Options via `IOTAEnvironmentOptions140.EditOptions('', 'drag-lint.General')`.
> - **Teardown FIXED** (the user's explicit requirement + a real pre-existing leak): `UnregisterDragLintOptions`
>   (was implemented but NEVER called) + `UnregisterProjectMenu` wired into `Wizard.Destroyed` + unit
>   finalizations (primary + secondary net; idempotent).
> - **1 headless autotest** `run_docs_manifest_roundtrip.ps1` (cap-effect teeth, dotted fixture).
> - **8 docs refreshed** (README/INSTALL[+"Where to configure X" map]/USER-GUIDE/plugin+rules READMEs/
>   SCAN-DATABASES + AI-USAGE/AI-INDEX-FIRST), all facts verified against shipped code.
>
> **KEY EXECUTION EVENTS (all resolved):** (1) Task 3 first wrote UNDOTTED per-project `drag-lint.json` -> CLI
> reads the local override only from DOTTED `.drag-lint.json` -> per-project edit was INERT; FIXED (709aa9c).
> (2) Task 7's wizard wiring pulled `ProjectMenu.pas` into the build graph for the FIRST TIME and it FAILED --
> the unit was in `.dproj` DCCReference but NOT `.dpk contains` + unreferenced, so its missing `System.SysUtils`
> uses (Supports/SameText) never compiled; FIXED (405f72c: uses + `.dpk contains` + empty initialization).
> LESSON: a unit in DCCReference but absent from `.dpk contains` + unreferenced is NOT compiled -> a spurious
> "clean build". (3) Final review Important: no-project manifest write used `ParamStr(0)` (= IDE bds.exe dir);
> FIXED via `DragLintExe` (51f06c4).
>
> **DEFERRED FOLLOW-UPS (filed, non-blocking, post-push):** (a) delete orphaned `DragLint.Plugin.OptionsFrame.pas`
> (singular, old single-page frame -- now dead, verified INERT) + fold its layout helpers into the plural unit;
> (b) align the Linter frame's manifest write to `TEncoding.UTF8` to match the CLI's canonical `TManifestIO.Save`
> (byte-identical today for 0-9999 ASCII values); (c) tidy the test's redundant check-9.
>
> **SDD LEDGER:** `.superpowers/sdd/progress.md` (BATCH B section at END) = full per-task record + the 3 fixes.

> ## RESUME 2026-07-08 (LATEST-29) -- **BATCH A DONE (merge-ready). BATCH B PLANNED (spec+plan committed). NEXT = IMPLEMENT Batch B AUTONOMOUSLY, then PUBLISH. `main`=`eceaa16`, 17 commits ahead of origin, NOT pushed (user drives push).**
>
> **USER DIRECTIVE (this session):** planning is done; only implementation remains. Implement Batch B
> autonomously, publish (user pushes), then TEST in-IDE later; if the live smoke surfaces issues, do a
> follow-up fix + another release.
>
> **READ FIRST to implement Batch B:** `docs/superpowers/plans/2026-07-08-batch-b-ide-config-consolidation.md`
> (9 tasks, in order 1->9). Spec: `docs/superpowers/specs/2026-07-08-batch-b-ide-config-consolidation-design.md`.
> **Execute via `superpowers:subagent-driven-development`** (fresh subagent per task + two-stage review).
>
> **WHAT BATCH B IS (reshaped by investigation -- both original premises were wrong):**
> - **#4 "add a Tools->Options page" -- ALREADY EXISTS.** `DragLint.Plugin.Options.pas` (`TDragLintOptions`,
>   `INTAAddInOptions`) already registers a native Tools->Options page. Work = CONSOLIDATE + ENRICH, not create.
> - **#5 "Editor->Language tab" -- NOT OTA-FEASIBLE.** No interface adds a page under the built-in
>   Editor->Language branch; `INTAAddInOptions.GetArea` only reliably lands under "Third Party". Reframed as
>   dedicated Linter/Indexer sub-pages, NOT a literal Editor tab. Do NOT attempt GetArea string-guessing.
> - **THE PLAN:** split the single Options frame into **4 nested sub-pages** (`drag-lint.General/Indexer/
>   Linter/Editor`; all 26 `TDragLintSettings` registry fields mapped, each to exactly one page -- exhaustive
>   table in the plan/spec) sharing the registry round-trip (read-modify-write so no page clobbers another);
>   add **`max_return_cases`** to the Linter page (reads/writes manifest `drag-lint.json`, the one non-registry
>   field); add a **Project Manager right-click "drag-lint: Project Rules..."** (`IOTAProjectMenuItemCreatorNotifier`)
>   that activates the clicked project then opens the EXISTING Lint Options dock tab (reuse, no dup); **retire
>   the duplicate `ShowSettingsDialog` modal** -> "drag-lint Options..." opens Tools->Options; **FIX a real
>   pre-existing bug** -- `UnregisterDragLintOptions` is implemented but NEVER CALLED (leak/AV-on-uninstall) ->
>   wire into `Wizard.Destroyed` + `finalization` (the user's explicit "detach on uninstall AND deactivation"
>   requirement); **refresh docs** (user: README/INSTALL/USER-GUIDE/plugin+rules READMEs + a "Where to configure
>   X" map + corrected indexer descriptions; AI: AI-USAGE/AI-INDEX-FIRST); **write YADF porting instructions
>   INTO the YADF repo** at the very end (ask user for the YADF repo path then).
>
> **GIT:** `main`=`eceaa16`, 17 commits ahead of origin (Batch A's 15 + Batch B's spec `283bcac` + plan
> `eceaa16`), NOT pushed. Clean except the usual LEAVE-THOSE untracked (`.superpowers/`, forms-csv v4 spec,
> `tests/autotest/results/*.json`). Batch A is merge-ready code; Batch B is docs-only so far (code comes from
> the autonomous implementation session).
>
> **BATCH B GOTCHAS (baked into the plan; flagged here for a cold start):**
> - **IDE OTA UI is NOT headless-testable.** The ONLY automatable gates are: a clean Win32 BPL build (0 err,
>   RAD Studio CLOSED via `Get-Process bds`) and Task 6's `run_docs_manifest_roundtrip.ps1` (the `max_return_cases`
>   <-> `drag-lint.json` round-trip). The REAL verification is a **live IDE smoke checklist the USER runs** after
>   (Task 9 writes it). "Publish autonomously" = build-clean + reviewed + committed, NOT proven-in-IDE.
> - **BPL builds every task** (RAD Studio closed); BPL/DCP binary in a SEPARATE `build(plugin):` commit (Task 9).
> - If `DRagLint.Index.Manifest` won't link into the Win32 plugin BPL, use direct `System.JSON` for
>   `max_return_cases` (Task 3 NOTE) -- verify at build time.
> - Task 3 manifest WRITE must preserve unrelated keys (read-modify-write the JSON, don't full-`ToJson`).
> - Task 5 "open Tools->Options" has no guaranteed focused-open API in Studio 37 -> the plan has a fallback
>   (execute the IDE Tools|Options action, or a ShowMessage hint). Pick the cleanest that reliably works.
> - Project-menu action ACTIVATES the clicked project before opening the dock (the Lint Options frame is
>   hardwired to the ACTIVE project; activate-then-open sidesteps threading a path override).
> - **Do NOT edit out-of-repo `c:\Projects\CLAUDE.md` / global `~/.claude/CLAUDE.md`** -- flag to user only.
>
> **AFTER BATCH B ships + pushes + live-smoke:** if smoke surfaces issues -> follow-up fix + another release.
> Then the deferred v0.94 IDE live-smoke of "Create helper class" remains. Also the PRE-EXISTING test-hygiene
> backlog: `run_formsmap.ps1` DEFAULT `-Exe` points at a stale Win32 binary (green on Win64); `run_smoke.ps1`
> hardcoded stale-version-string check -- a "make autotest `-Exe` defaults Win64 + version-agnostic" pass.
>
> ---
>
> ## RESUME 2026-07-08 (LATEST-28) -- **BATCH A IMPLEMENTED, FINAL-REVIEWED, MERGE-READY. 14 commits on `main` (`d816b23`..`9fb29c8`). NOT pushed -- user drives the push.**
>
> **STATUS:** All 3 Batch-A items shipped via `superpowers:subagent-driven-development` (fresh implementer + two-stage
> review per task, order 3->2->1). Every task reviewed clean; a final opus whole-branch review found 0 Critical +
> 1 Important, which was FIXED + re-reviewed clean. `main` is 14 commits ahead of origin; tree clean (only the usual
> LEAVE-THOSE untracked: `.superpowers/`, forms-csv v4 spec, `tests/autotest/results/*.json`).
>
> **NEXT ACTION: push.** `git push origin main` (per convention the user drives the push). After push, origin in sync.
>
> **WHAT SHIPPED (14 commits):**
> - **Item 3 -- forms-csv multi-DB (Tasks 1-4).** Engine `AExtraStores` fan-out in `FindNearestFormCaller`/
>   `FindFormViaHook`/`BuildEdges` (PAS-line caches re-keyed Int64->path for cross-DB collision safety);
>   `GenerateFormsCsv(ADbPaths: TArray<string>)` overload; CLI `DoFormsCsv` passes all resolved DBs; IDE menu emits
>   multi `--db` (project DB first) + a stale-exe footer guard (parses the REAL `# forms-csv algorithm v4` footer,
>   NOT the plan's wrong `FORMS_CSV_ALGORITHM=` guess); Win32 BPL rebuilt (`build(plugin):` commit). Commits
>   `8800780`,`a24f0fa`,`e998762`,`bc50a4a`,`cd64077`,`7039aed`. **A real bug surfaced by the multi-DB test + fixed
>   (`cd64077`):** `BuildEdges` Pass1/Pass2 discovery queries only hit the primary store -> a form constructed
>   solely in COMMON printed DEAD even with COMMON `--db`; now fanned across `[AStore]+AExtraStores`. Test
>   `run_formsmap_multidb.ps1` proves client-only=DEAD -> client+common=resolved chain.
> - **Item 2 -- AutoDoc facts multi-DB (Tasks 5-6).** `TDocFactsBuilder.Build` gained `AExtraStores`; cross-DB
>   callers/used-in surface via NAME buckets only (resolved-caller Ids are per-DB); threaded through `BuildFor` +
>   `TDocBatchOptions` + a shared `OpenExtraStores` helper wired into all 4 `document` verbs. Test
>   `run_doc_multidb.ps1`. Commits `a563185`,`0e4c582`. (CLI quirk noted: `AArgs.DbPath` = the LAST `--db`.)
> - **Item 1 -- returns enumeration + docs config (Tasks 7-10).** New `drag-lint.json` `docs.max_return_cases`
>   (`TDocSettings`, default 20); `TDocFacts.ReturnCases` mined via the REUSED hover `MineReturnExpressions`;
>   `<returns>` emits `TODO: describe. Observed: <cases>.` (XML-escaped, idempotent -- parser stores ReturnsText
>   verbatim so the gate re-appends deterministically); cap threaded manifest->`Build`. Test `run_doc_returns.ps1`
>   (enumeration+escape, cap=1 differs, byte-identical idempotency, + both-exist-merge). Commits `c014d82`,`2dfec67`,
>   `71b6368`,`29ce202`. **Two manifest bugs found+fixed by tests:** (a) Task 10 -- `Load`'s no-config branch left
>   `Docs.MaxReturnCases=0` (enumeration dead); (b) final review -- both-exist merge dropped a LOCAL cap override
>   when a GLOBAL config exists (`037e400`: added `skMaxReturnCases` presence bit + carry `Result.Docs` in merge).
>
> **VERIFICATION (all against the fresh Win64 exe `src/cli/Win64/Debug/drag-lint.exe`):** `run_formsmap` 32/32,
> `run_formsmap_multidb`, `run_doc_multidb`, `run_doc_returns` (4 scenarios A/B/C/D), `run_manifest`, and all 16
> `tests/autodoc/*.ps1` -- ALL PASS.
>
> **KNOWN PRE-EXISTING (NOT Batch A, backlog candidates):** `run_formsmap.ps1`'s DEFAULT `-Exe` points at a STALE
> `Win32\Debug` binary (Jul-5, pre-Batch-A) so a no-arg run shows 4 spurious FAILs; it's 100% GREEN on the current
> Win64 exe. `run_smoke.ps1` has a hardcoded stale-version-string check (1/20 fail). BOTH are test-default hygiene,
> not product bugs -> a future "make autotest -Exe defaults Win64 + version-agnostic" pass. Also deferred (from the
> final review, all triaged KEEP-AS-IS): FormsMap `FileLines` dead `AFileId` param; store-list DRY between
> `QueryNameCallerRows` + the hook loop; `Build` reads the source file up to 3x/call; `LoadDocMaxReturnCases`
> reloads the manifest per verb.
>
> **AFTER PUSH:** Batch B = investigate -> plan -> handoff/clear -> implement -> publish for #4 (Tools->Options
> pages spike) and #5 (Editor->Language tabs spike). Plus the deferred v0.94 IDE live-smoke of "Create helper class".
>
> ---
>
> ## RESUME 2026-07-08 (LATEST-27) -- **BATCH A PLANNED + PUSHED. NEXT = IMPLEMENT the 10-task plan. Hover work is DONE + pushed. `main`=`66719ee`, origin IN SYNC.**
>
> **READ FIRST to implement:** `docs/superpowers/plans/2026-07-08-batch-a-multidb-facts-and-returns.md`
> (10 tasks, order 3->2->1). Spec: `docs/superpowers/specs/2026-07-08-batch-a-multidb-facts-and-returns-design.md`.
> **Execute via `superpowers:subagent-driven-development`** (fresh subagent per task + two-stage review).
>
> **WHAT BATCH A IS (3 user-queued items, reshaped by investigation):**
> - **Item 3 -- forms-csv multi-DB (root-cause fix, highest value).** NOT a code regression + NOTHING
>   lost: the polymorphic `CP2 -> imcPlanList -> plan-edit` chain AND button-caption navigation
>   (`Root -> 'Plan' -> frmX`) both WORK and are tested (verified via subagents this session; see the
>   design doc's Background section). The ONLY failure is a DB-SCOPE delivery gap: single-DB is baked in at
>   3 layers -- IDE menu `DragLint.Plugin.Editor.pas:2298` (`GetActiveProjectDb`), CLI `DoFormsCsv`
>   `CLI.pas:9675` (`DbPaths[0]`), engine `GenerateFormsCsv` (1 store). A CLIENT-only DB misses COMMON's
>   `uPLANLIST.PAS` launch-bodies -> reachable forms print DEAD FORM. FIX = make forms-csv query the full
>   manifest DB set (like `find-callers`/hover). User: **NO hedge cell** -- produce the real chain (see all
>   DBs) or declare DEAD definitively. Fully HEADLESS-testable (new `run_formsmap_multidb.ps1`: dead vs
>   CLIENT-only -> resolves with COMMON) + an exe-version footer guard on the IDE path. Tasks 1-4.
> - **Item 2 -- AutoDoc facts multi-DB.** The original "called-from parity via SliceJsonBracket" premise is
>   FALSE: AutoDoc uses IN-PROCESS `ISymbolStore` queries (no shell-out, no JSON parse), so the hover
>   stderr/JSON bug CANNOT occur there. The REAL gap (user chose to fix): `TDocFactsBuilder.Build` takes ONE
>   store -> callers in other DBs invisible. FIX = optional `AExtraStores` param; fan out only the 3
>   caller-facing queries (`FindResolvedCallers`/`FindUnresolvedNameCallers`/`FindCallersByName`); primary
>   store still owns symbol/body/calls-out. Tasks 5-6.
> - **Item 1 -- AutoDoc `<returns>` enumeration + docs config.** Reuse `MineReturnExpressions` (hover's pure
>   miner) in AutoDoc so `<returns>` shows `TODO: describe. Observed: <cases>` (XML-escaped, idempotent).
>   Cap via a NEW `drag-lint.json` `"docs"` block `max_return_cases` (default 20) -- user picked the real
>   config file over a const/CLI-flag. Tasks 7-10.
>
> **GIT:** `main`=`66719ee`, origin IN SYNC (0 ahead). Clean except the usual LEAVE-THOSE untracked
> (`.superpowers/`, forms-csv v4 spec, `tests/autotest/results/*.json`). Hover restyle (LATEST-26) shipped:
> source `be97e7c`, BPL `b807a79`, backlog `5d843ba` -- all pushed. This session also rewrote history to
> drop 2 IDE-generated files (`drag-lint.delphilsp.json`/`.dsv`) from the source commit.
>
> **PLAN GOTCHAS (baked into the plan, but flagged here for a cold start):**
> - Signature-growth: `Build` + `BuildFor` each gain `AExtraStores` (Tasks 5/6) THEN `AMaxReturnCases`
>   (Tasks 8/10) -- trailing + defaulted, `AExtraStores` FIRST. Don't reorder.
> - `APasLines` cache in FormsMap is keyed on per-DB FileId -> switch to PATH-keyed when multi-DB (FileIds
>   collide across DBs). Plan Task 1 Step 2 covers this.
> - Extra-store resolved-caller queries key on per-DB symbol Id (invalid cross-DB) -> use the NAME buckets
>   only in extra stores. Plan Task 5 Step 2 NOTE covers this; don't invent `FindSymbolIdByQName`.
> - `document --json` payload shape is uncertain -> inspect ONCE, then assert on `--apply`+grep if needed.
> - Build: CLI Win64 exe = the test target (`src/cli/Win64/Debug/drag-lint.exe`); IDE BPL Win32 only for the
>   item-3 plugin edit, RAD Studio CLOSED (`Get-Process bds`), via `_bpl_build.bat`; BPL/DCP in a SEPARATE
>   `build(plugin):` commit.
>
> **AFTER BATCH A ships + pushes:** Batch B = investigate -> plan -> handoff/clear -> implement -> publish
> for #4 (Tools->Options pages spike) and #5 (Editor->Language tabs spike). Plus the deferred v0.94 IDE
> live-smoke of the "Create helper class" menu.
>
> ---
>
> ## RESUME 2026-07-07 (LATEST-26) -- **HOVER RESTYLE DONE, DEBUG-STRIPPED, BUILT CLEAN, COMMITTED. Ready to push. Next: 3 user threads (#3 forms-csv, #4 Tools->Options, #5 Editor->Language) + 2 AutoDoc TODOs.**
>
> **STATE:** Closed out the hover Help-Insight restyle. Stripped ALL this-session debug scaffolding
> (`DebugBuildStamp` fn + comment, the `[STRING | ...]` Caption stamp, the `FetchHoverModel:`/
> `TryBuildHoverModel:`/`HoverTracker: STRUCTURED|STRING` `DebugLog` lines, and the unused
> `JStart/JEnd/Depth/InStr/Esc/Ch` locals in `FetchHoverModel`). Caught + fixed a latent compile break: an
> earlier partial strip had left a dangling `if not GotModel then` with no body in `HoverTracker` -- rewrote
> it to `if LspText <> '' then GotModel:= TryBuildHoverModel(...)`. Rebuilt the Win32 BPL with RAD Studio
> CLOSED: **Build succeeded, 0 Error(s), 20 hint-level warnings** (all pre-existing/benign). Ran
> `run_hover_multidb.ps1` = **10/10 PASS**.
>
> **GIT:** two commits added on `main` this session -- a source commit (CLI `DoHover` multi-db +
> `SliceJsonBracket` + dwell-structured `TryBuildHoverModel` + callers + all polish + z-order + green types +
> by-reference + CALLED-FROM body label + grid spacing, plus the new `run_hover_multidb.ps1` regression test
> and this BACKLOG update) and a separate `build(plugin):` commit for the rebuilt `dclDragLintWizard.bpl`/`.dcp`.
> **User drives the push.** LEFT UNCOMMITTED on purpose (not this work): IDE-generated `drag-lint.delphilsp.json`
> + `drag-lint.dsv`, the forms-csv v4 spec (thread #3), `tests/autotest/results/*.json`, `.superpowers/`.
>
> **STILL QUEUED:** 2 AUTODOC TODOs (Called-from parity via `SliceJsonBracket`+multi-db; Returns-format reuse)
> and 3 user threads (#3 forms-csv regression on the deployed CSV, #4 Tools->Options pages spike, #5
> Editor->Language tabs spike). Prior LATEST-25/24 blocks below retain the full root-cause + polish detail.
>
> ---
>
> ## RESUME 2026-07-07 (LATEST-25) -- **HOVER RESTYLE POLISH VISUALLY COMPLETE + USER-CONFIRMED ("Great!"). ONLY 2 THINGS LEFT: (1) strip debug scaffolding, (2) commit clean. Then user pushes. ALL fixes STILL UNCOMMITTED.**
>
> **STATE:** This session closed out the hover Help-Insight restyle live-smoke. It BUILT the pending
> Win32 BPL (RAD Studio was closed), fixed the z-order bug, then iterated the visual polish live with the
> user until they confirmed "Great!". The structured hover popup is DONE: a 1-line colored signature
> header (green `unit.pas (line)` locator, click-navigates to the definition); a PARAMETERS block with
> **fixed-green** types and untyped `var`/`out` params labelled **"by reference"**; a RETURNS block
> (type inline + mined `Result :=` lines); and a **blue + bold "CALLED FROM (N)" body label** with the
> callers grid docked tight beneath it (grey OS grid headers hidden; no body scrollbar).
>
> **GIT:** `main`=`0e80625` (still only the AV-crash fix committed). 13 commits ahead of origin. **ALL
> live-smoke + polish fixes REMAIN UNCOMMITTED** (user chose leave-uncommitted; commit comes after the
> debug-strip): `src/cli/DRagLint.CLI.pas`, `src/delphi-plugin/DragLint.Plugin.Editor.pas` +
> `.HoverForm.pas` + `.HoverTracker.pas`, `docs/lint/BACKLOG.md`, new `tests/autotest/run_hover_multidb.ps1`.
> Plus the usual LEAVE-THOSE (IDE json/dsv, rebuilt bpl/dcp, forms-csv spec, `results/*.json`). Latest
> deployed BPL = `third_party/dll-win32/dclDragLintWizard.bpl` @ 2026-07-07 17:10 (6561964 bytes).
>
> **WHAT THIS SESSION ADDED (on top of LATEST-24's 4 root-cause fixes, all still in the tree):**
> 1. **z-order fix** (`HoverForm.HandleWatchTick`): the IDE's own Code Insight popup jumped in front of
>    ours. Fixed by re-asserting `HWND_TOPMOST` on every 150 ms watch tick via
>    `SetWindowPos(..., SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE)` (NOACTIVATE = never steals editor
>    focus), guarded by `Visible and HandleAllocated`.
> 2. **Param types render FIXED green:** `GetSyntaxColor(srType)` now returns `CL_TYPE` (#217A3C) always
>    and Exits (like `srSection` blue), instead of reading `atIdentifier` (the user's IDE identifier
>    color was dark/grey, making types unreadable). User decision: "fixed green always".
> 3. **Untyped `var`/`out` params labelled "by reference":** in `RenderModel`, `P.TypeText=''` emits
>    `by reference` (muted) instead of a blank type. User decision: "by reference".
> 4. **CALLED FROM = a blue + bold BODY label, NOT a grid header (a deliberate pivot).** First attempt
>    made the ListView column-header bold+blue via `NM_CUSTOMDRAW`/`CN_NOTIFY` -- FRAGILE: a themed
>    header ignores `CDRF_NEWFONT`'s font (ended up blue-only, then neither). ABANDONED and fully
>    REVERTED (removed `CNNotify`, `FCallerHeaderFont`, `FHeaderUnthemed`, the `SetWindowTheme` un-theme,
>    and the `Winapi.CommCtrl`/`Winapi.UxTheme` uses). Replaced with: `FCallers.ShowColumnHeaders:=False`
>    (grey OS header hidden) + `RenderModel` gained an `ACallerCount` param and emits `CALLED FROM (N)`
>    as a blue bold `srSection` line at the BOTTOM of the body -- guaranteed bold+blue in every theme
>    because it is just colored RichEdit text. Signature: `RenderModel(const AModel; ACallerCount: Integer)`;
>    call site passes `Length(ACallers)`.
> 5. **Grid spacing tuned to the user's taste (final, confirmed):** callers-grid height dropped the ~28 px
>    header allowance to `6 + rows*18` (headers hidden); body height is `BodyLines*18 - 24`, which pulls
>    the grid up ~2 lines to dock under the label AND leaves just enough room to clear the body's vertical
>    scrollbar (the user's last two asks: "move the grid 2 lines up" then "expand down 4-6 px to lose the
>    scrollbar"). If the scrollbar ever returns on a differently-sized symbol, the clean size-independent
>    fix is to suppress the body's vertical scrollbar when content fits (not more pixel-nudging).
> 6. Already removed this session: the `[STRUCT | BPL <date>]` debug line in `RenderModel`.
>
> **REMAINING -- exactly 2 items, then the user pushes:**
> 1. **STRIP DEBUG SCAFFOLDING** (the `[STRUCT]` block is already gone; still to remove): (a) `function
>    DebugBuildStamp` in `HoverForm.pas` (now unused after the `[STRUCT]` removal -- delete it); (b) the
>    `[STRING | ' + DebugBuildStamp + ']'` stamp appended to the STRING-fallback `Caption` (in the string
>    `ShowAt` path, ~`HoverForm.pas:1057` area); (c) the diagnostic `DebugLog` lines -- `FetchHoverModel:
>    ...` / `TryBuildHoverModel: ...` in `Editor.pas` and `HoverTracker: STRUCTURED/STRING ...` in
>    `HoverTracker.pas`; (d) the unused locals `JStart/JEnd/Depth/InStr/Esc/Ch` in `FetchHoverModel`
>    (`Editor.pas`, the H2164 hints left after it switched to `SliceJsonBracket`). Then REBUILD the BPL
>    (RAD Studio CLOSED) and confirm 0 dcc errors.
> 2. **COMMIT CLEAN**, then the user pushes: the clean hover fixes (CLI multi-db `DoHover` +
>    `SliceJsonBracket` + dwell-structured `TryBuildHoverModel` + callers + all the polish + z-order +
>    green types + by-reference + CALLED-FROM body label + grid spacing) and fold `run_hover_multidb.ps1`
>    into the battery. The BPL/DCP go in a SEPARATE `build(plugin):` commit per the v0.88 convention.
>
> **STILL QUEUED after that:** 2 AUTODOC TODOs (below: Called-from parity via `SliceJsonBracket`+multi-db;
> Returns-format reuse) and 3 user threads (#3 forms-csv regression on the deployed CSV, #4 Tools->Options
> pages spike, #5 Editor->Language tabs spike).
>
> **BUILD RECIPE (proven all session):** Win32 BPL via a 3-line wrapper `.bat` (`rsvars` -> `cd
> src/delphi-plugin` -> `msbuild /t:Build /p:Config=Debug /p:Platform=Win32 dclDragLintWizard.dproj`),
> run from PowerShell `Start-Process cmd.exe -Wait` with the output redirected to a log; check
> `BUILD_EXITCODE=0` and no `error F2039` / `[dcc32 Error]`. It auto-deploys to
> `third_party/dll-win32/dclDragLintWizard.bpl`. GOTCHA CONFIRMED THIS SESSION: `bds.exe` (RAD Studio)
> holds the BPL lock -> `F2039 Could not create output file` even when every unit compiled 0-error; the
> user must CLOSE RAD Studio first. Check `Get-Process bds` before building.
>
> ---
>
> ## RESUME 2026-07-07 (LATEST-24) -- **HOVER RESTYLE LIVE-SMOKE DEBUG IN PROGRESS. Structured colored view NOW WORKS in the IDE. Finishing polish. ALL live-smoke fixes UNCOMMITTED (debug-quality).**
>
> **STATE:** The v0.94 hover milestone (LATEST-23 below) was declared done, then LIVE IDE SMOKE found real bugs.
> After a long debug chain the structured colored Help-Insight view NOW RENDERS in the IDE -- user confirmed:
> colored signature on ONE line, PARAMETERS/RETURNS bold blue (uppercase), green types, `RETURNS: boolean`
> inline, mined `Result := False` / `Result := rlines <> 0` lines, and the CALLED FROM grid populated with
> double-click navigation. What's left is VISUAL POLISH only.
>
> **GIT:** `main`=`0e80625` (the ONLY committed live-smoke fix = the AV crash). 13 commits ahead of origin
> (12 milestone + `0e80625`). **ALL OTHER live-smoke fixes are UNCOMMITTED working-tree edits** (user chose
> LEAVE UNCOMMITTED at the handoff): `src/cli/DRagLint.CLI.pas`, `src/delphi-plugin/DragLint.Plugin.Editor.pas`
> + `.HoverForm.pas` + `.HoverTracker.pas`, `docs/lint/BACKLOG.md`, new `tests/autotest/run_hover_multidb.ps1`.
> Plus the usual LEAVE-THOSE (IDE json/dsv, rebuilt bpl/dcp, forms-csv spec, `tests/autotest/results/*.json`).
>
> **4 ROOT-CAUSE BUGS FIXED THIS SESSION (all in the uncommitted tree except #1):**
> 1. **AV crash (COMMITTED `0e80625`):** `HandleMemoMouseMove` used the TMemo idiom
>    `Perform(EM_CHARFROMPOS,0,MakeLParam(X,Y))` on `FBody`, now a TRichEdit -> rich edit wants a `POINTL*` in
>    lParam -> deref'd garbage -> AV in MSFTEDIT.DLL. Fixed: `SendMessage(EM_CHARFROMPOS,0,LPARAM(@Pt))` +
>    `EM_EXLINEFROMCHAR` + `Winapi.RichEdit` in uses.
> 2. **`hover --qname` used only the LAST `--db` (CLI `DoHover`):** the arg parser sets `AArgs.DbPath` on
>    EVERY `--db` so it ends up = the LAST one; the plugin passes 3 dbs (ORM3, SQL, library) so hover queried
>    `library` (no symbol) -> "No symbol matched" -> `FetchHoverModel` False -> string fallback. FIXED: `DoHover`
>    now iterates `ResolveConsumerDbs(AArgs)` + uses the FIRST db that contains the qname. Regression test
>    `tests/autotest/run_hover_multidb.ps1` (10/10 pass -- target db first/middle/last).
> 3. **stderr-merged JSON -> parse nil (plugin `DragLint.Plugin.Editor.pas`):** `RunAndCaptureStdout` sets
>    `SI.hStdError:=WritePipe` (MERGES stderr into the captured stdout); the CLI writes banners
>    "(loaded defaults...)" / "  FTS5 probe:" to stderr AROUND the JSON, so `Output` = `{...json...}(loaded
>    defaults...)`; strict `TJSONObject.ParseJSONValue` returns nil on trailing non-JSON -> silent empty.
>    FIXED via a new shared `SliceJsonBracket(AText, AOpen, AClose)` (string-aware brace/bracket walk) used by
>    BOTH `FetchHoverModel` (object) AND `FetchHoverCallers` (array). THIS is why CALLED FROM showed 0 callers
>    even though `find-callers` returned data.
> 4. **Dwell path never used the structured view:** mouse-hover fires via `HoverTracker` (NOT the menu
>    `InvokeHover`); Task 8 only wired InvokeHover. FIXED: new interface fn
>    `TryBuildHoverModel(rawmd; out AModel; out ACallers): Boolean` in Editor.pas (mines qname via
>    `ExtractHoverQname`, fetches `hover --json` + callers-by-last-segment); HoverTracker calls it and shows
>    the structured popup on success, the string popup on any miss.
>
> **POLISH DONE (uncommitted, NOT yet built into the BPL -- RAD Studio was OPEN, blocking the rebuild):**
> - RETURNS inline (`RETURNS: boolean` + single value inline; multi lists below). New `srSection` role =
>   strong blue `CL_SECTION` #1560D6 for the uppercase bold PARAMETERS/RETURNS labels. Types green (`srType`).
> - Colors survive theming: `FBody.StyleElements:=[]` (TRichEditStyleHook was overriding `SelAttributes.Color`);
>   same now on `FCallers.StyleElements:=[]` + `Color:=clWindow`.
> - Window: `WordWrap:=False` + `ssBoth` so the signature stays 1 line; width measured from `AModel.Signature`
>   (NOT `FBody.Lines` which are pre-wrapped); `MAX_W=1200`; `PlaceAndShow` expands into available screen then
>   clamps to the work-area edge.
> - Borderless: `BorderStyle:=bsNone` + `WS_BORDER` thin frame in `CreateParams` (like Delphi Code Insight; the
>   colored signature line IS the header). Callers grid columns widened (Unit 260 / Line 55 / Code 620).
>
> **REMAINING POLISH (next session -- BUILD FIRST, then the user re-tests):** The user's LAST screenshot was
> still `BPL 15:19`, i.e. BEFORE the borderless/grid edits were built (RAD Studio open blocked the rebuild).
> So: (A) ensure RAD Studio CLOSED, rebuild the Win32 BPL (recipe below), user re-tests. Open items to verify
> AFTER the build (they may already be fixed by the uncommitted edits): (i) CALLED FROM column header showed
> "Called fro..." ABBREVIATED + the grid was a DARK color -> widened columns + `FCallers.StyleElements:=[]`
> should fix; (ii) title bar still said 'drag-lint' -> `bsNone` removes it. (iii) **NEW z-order bug, NOT yet
> addressed:** the Delphi IDE's OWN Code Insight popup jumps IN FRONT of ours (ours is `fsStayOnTop` +
> `HWND_TOPMOST` but the IDE tooltip still overlays it). Needs a fix -- design not decided (re-assert topmost
> after show / on a watch-timer tick, or detect+dismiss when the IDE popup appears).
>
> **AFTER POLISH IS VISUALLY CONFIRMED -- STRIP DEBUG THEN COMMIT CLEAN:** (a) the `[STRUCT | BPL <date>]`
> bottom line in `RenderModel`; (b) `function DebugBuildStamp` in HoverForm; (c) the diagnostic `DebugLog`
> lines (`FetchHoverModel: ...`, `TryBuildHoverModel: ...`, `HoverTracker: STRUCTURED/STRING ...`) in Editor.pas
> + HoverTracker.pas; (d) the unused locals (JStart/JEnd/Depth/InStr/Esc/Ch) left in `FetchHoverModel` after it
> switched to `SliceJsonBracket` (H2164 hints). THEN commit the clean fixes + fold `run_hover_multidb` into the
> battery. Two AUTODOC follow-ups already filed below (Called-from parity via SliceJsonBracket+multi-db; Returns
> format reuse). User drives push.
>
> **BUILD RECIPE (proven this session):** CLI Win64: rsvars + `msbuild /t:Build /p:Config=Debug
> /p:Platform=Win64 src/cli/drag-lint.dproj` -> copy `src/cli/Win64/Debug/drag-lint.exe` to
> `third_party/dll-win64/drag-lint.exe`. PLUGIN Win32 BPL: rsvars + `msbuild /p:Platform=Win32
> src/delphi-plugin/dclDragLintWizard.dproj` (auto-deploys to `third_party/dll-win32/dclDragLintWizard.bpl`).
> Run from PowerShell `Start-Process cmd.exe -Wait` w/ log; `BUILD_EXITCODE=0` + `0 Error(s)`. GOTCHA: RAD
> Studio (bds.exe) holds the BPL lock -> `F2039 Could not create output file`; CLOSE it first. GOTCHA: the
> drag-lint SELF-LINT reports FALSE-POSITIVE "errors" on literal `{ }` / `[ ]` inside `{ }` comments and on
> `'\'` char literals (use `#92`); the REAL dcc compiler is the gate, not the self-lint. Debug WITHOUT the IDE:
> self-test the CLI + slice logic via `.ps1` / PowerShell (this session PROVED both the multi-db fix AND the
> slice extraction before reopening RAD Studio).
>
> ---
>
> ## RESUME 2026-07-07 (LATEST-23) -- **HOVER HELP-INSIGHT RESTYLE IMPLEMENTED (Tasks 1-9, commits `365a471..f8bb756` + this task's hardening fix). OPEN: IDE LIVE SMOKE (user).**
> Executed as a 9-task sequence (SDD-style, one commit per task). What shipped: the IDE hover popup now renders as a
> Delphi-Help-Insight-style tooltip instead of a plain-text dump. **(1)** one-line clickable **signature header**
> (unit.pas + line number right-aligned; click -> jump to definition; line-0 hit test survives a wrapped/long
> signature). **(2)** body renders in a **TRichEdit**, colored + selectable (Ctrl+C copies), using the **IDE's own
> editor font** and **real IDE syntax colors** read via the registry (`DragLint.Plugin.RegistryColors.pas`/
> `DragLint.Plugin.Fonts.pas`), falling back to a built-in palette when the IDE colors aren't available. **(3)**
> parameters listed one per line with **const/var modifiers**, types **column-aligned**. **(4)** **Returns** section:
> mines distinct `Result :=` / `Exit(...)` RHS expressions out of the routine's body span (`ImplStartLine..
> ImplEndLine`) via `src/cli/DRagLint.Hover.Returns.pas` (`MineReturnExpressions`) -- caps at **10 distinct**, shows
> "and NN more" beyond that; loop-only `ExitLoop(...)` calls are correctly excluded from mining. **(5)** **Called
> from** section reuses the AutoDoc caller-facts path, same display convention as AutoDoc: **<=15 show all, >15 show
> 10 + "...and NN more"** trailer (trailer text does not navigate; real rows do). **(6)** **WCAG contrast guard**
> (`src/cli/DRagLint.Hover.Contrast.pas`, `ContrastRatio`/`EnsureReadable`) -- any colour pairing that would fail a
> 4.5:1 ratio (e.g. keyword-blue on a very dark theme background) is nudged to a readable variant before painting, so
> dark-theme readability holds even with a customized editor palette.
> **THIS TASK (9 of 9) folded in one hardening fix** caught in the Task 4 review: `DoHover` in
> `src/cli/DRagLint.CLI.pas` mines the Returns section by slicing `AllLines[Lo..Hi]` from `ImplStartLine`/
> `ImplEndLine` (1-based -> 0-based, `Hi` clamped to `High(AllLines)`); on a badly stale index `ImplStartLine` could
> sit past EOF making `Lo > Hi`, which fed a negative length into `SetLength(Body, Hi-Lo+1)`. Added a guard: if
> `Hi < Lo`, `Body` is zero-length (no returns mined, no crash) instead of computing the SetLength/copy. Verified
> against the full battery (`run_hover_returns`/`run_hover_contrast`/`run_typeat_scope`/`run_smoke`, 4/4 green) and a
> clean Win64 rebuild (0 dcc errors). Self-index (`tests/draglint_self.sqlite`) reindexed fresh (stale pre-`section`-
> column schema forced a delete+full-reindex rather than incremental; 132 files / 11,709 symbols / 60,038 refs / 0
> errors) -- confirms `DRagLint.Hover.Contrast`, `DRagLint.Hover.Returns`, `DragLint.Plugin.Fonts` are all indexed.
> **OPEN: IDE LIVE SMOKE (user)** -- reopen RAD Studio with the rebuilt BPL and walk
> `.superpowers/sdd/hover-ide-smoke-checklist.md` (11-point checklist: colored header in IDE font, clickable header,
> aligned params, mined Returns, Called-from cap, selectable+copyable body, dark-theme contrast, custom-color
> reflection, wrapped-header navigation, overload first-wins, DB-miss fallback).

> ## RESUME 2026-07-07 (LATEST-22) -- **v0.94.0-alpha SHIPPED (enum-helper). POST-SHIP: HOVER SCOPE BUG FIXED + ORM3 REINDEXED. 4 USER THREADS QUEUED (user picks order).**
> **Git:** `main` has **2 UNPUSHED local commits** past the v0.94 release: `ba5676d` (hover fix) + `e5039a8`
> (readonly-verbs test fix). Origin/main is still at the release commit `29ac50e` (v0.94.0-alpha, GH release
> LIVE + Latest, tag pushed). Working tree clean except IDE `delphilsp.json`/`.dsv` + 1 untracked forms-csv
> spec doc -- LEAVE THOSE. **Push of ba5676d+e5039a8 awaits user consent** (project rule: push only on request).
> schema **v15**.
>
> **HOVER BUG FIXED (`ba5676d`, reviewed clean 0-Crit/0-Imp).** Hovering a routine's PARAMETER/LOCAL VAR
> (e.g. `N` in `function Pad0(const N,DIGITS:integer)` at `C:\Projects\DB\ORM3\CLIENT\BASICSF.pas:1346`) resolved
> to an UNRELATED same-named GLOBAL. Root cause: `TTypeAtResolver.Resolve`
> (`src/resolver/DRagLint.Resolver.TypeAt.pas`) bare-identifier branch did a FLAT whole-DB name lookup
> (`FindSymbolByExactNameAnywhere`), no scope filter; `FindContainingSymbol` matches DECL-span not impl-body-span
> so returned the unit. FIX = new `ISymbolStore.FindEnclosingRoutineByImpl(fileId,line)` (routine whose
> `impl_start_line..impl_end_line` contains the line; kind IN the SHORT stored strings
> `'procedure'/'function'/'method'/'constructor'/'destructor'`) + scope-first pre-check: find enclosing routine ->
> `FindChildSymbolByName` -> use IF `Kind in [skParam,skLocalVar]` ELSE fall through to the unchanged global lookup.
> Surgical (dotted/member-access branch untouched). LSP hover benefits automatically (filters candidates by
> `TAResult.Resolved.QualifiedName`). Test `tests/autotest/run_typeat_scope.ps1` (shadow fixture, 7/7). Verified:
> N + DIGITS -> `BASICSF.Pad0.N`/`.DIGITS` `integer` at signature + body.
>
> **ORM3 REINDEXED (fix relies on params being indexed -- the DB predated the v14 skParam/skLocalVar feature).**
> `drag-lint index --all --only ORM3` -> `C:\Projects\DB\ORM3\drag-lint.sqlite` = 820 files, 64,732 symbols,
> **13,617 params + 7,049 local_vars**, schema v15, 0 errors, 106s. Hover fix now LIVE tree-wide. (Manifest ORM3
> section covers `C:\Projects\DB\ORM3` incl `CLIENT/`; `ResolveDbForFile` -> primary manifest DB = this one. The
> per-project CLIENT `Micronite2027.sqlite` is separate + still stale, but hover uses the manifest DB.)
>
> **4 USER THREADS STILL QUEUED (user picks order; #2 is the natural next since hover resolution is now correct):**
> - **#2 HOVER TOOLTIP FORMAT / FEATURE** -- match Delphi Help Insight: (a) respect dark/light THEME + IDE
>   FONTS/SIZES (from settings); (b) param name + type on ONE line (compact); (c) TOP HEADER LINE clickable ->
>   go to definition; (d) ADD a "Called from" section (like AutoDoc's caller facts), each line clickable -> jump
>   to that call site; (e) caller CAP: <=15 show all; >15 show 10 + "and NN more". Renderer
>   `src/cli/DRagLint.Hover.Renderer.pas` + plugin `DragLint.Plugin.HoverForm.pas`/`HoverTracker.pas`. Caller data:
>   reuse AutoDoc's Called-from facts path (`src/doc/DRagLint.Doc.Facts.pas` uses call_edges / resolved callers).
> - **#3 FORMS CSV REGRESSION** -- the DEPLOYED tester report
>   `\\htrtest\MICDATA_D\ATEST\TESTER\Micronite2027-forms 2026-07-07.csv` STILL reports some forms as "DEAD FORM"
>   that our forms-csv v4 fix (v0.87, `src/forms/DRagLint.FormsMap.pas`) was supposed to resolve; user says "our
>   preliminary review was working fine" -> DIAGNOSE why the fix isn't in the deployed report (stale deployed exe?
>   stale/per-project db passed by the IDE menu? a real regression?). Some forms ARE genuinely dead; the point is
>   the ones we KNOW how to resolve are still shown as dead.
> - **#4 TOOLS->OPTIONS PAGES** (OTAPI spike, research-first) -- register our own Tools->Options pages
>   (Indexer / Linter / YADF on separate pages) via `INTAAddInOptions` / `IOTAOptionsWizard`. May be large.
> - **#5 EDITOR->LANGUAGE TABS** (OTAPI spike, research-first) -- insert drag-lint under
>   Tools->Options->Editor->Language alongside Syntax Highlighter / Error Insight / Code Insight. May be
>   partly impossible via the public OTAPI -- report feasibility before building.
>
> **IMMEDIATE TODO (user, 2026-07-07) -- AFTER the current hover cycle finishes:** Reuse the hover "Returns"
> format (mined distinct `Result :=` / `Exit(...)` RHS -- shipping now via `src/cli/DRagLint.Hover.Returns.pas`
> `MineReturnExpressions`) inside **AutoDocumentation** so a generated `<returns>` doc can enumerate the actual
> return cases instead of a bare TODO. Difference from hover: AutoDoc may list MORE distinct cases -- **cap up to
> 20** (hover caps at 10), and make the cap **CONFIGURABLE** (a setting, e.g. in the docs config / drag-lint.json;
> hover=10 / autodoc=20 as defaults). Touch points: `src/doc/DRagLint.Doc.Facts.pas` (return facts) +
> `src/doc/DRagLint.Doc.Document.pas` (emit into `<returns>`); reuse `MineReturnExpressions` (already pure +
> shared). Own brainstorm->spec->plan mini-cycle. NOT part of the hover milestone; queued for right after it.
>
> **IMMEDIATE TODO (user, 2026-07-07) -- AUTODOC "Called from" PARITY:** the hover live-smoke surfaced a bug
> class AutoDoc likely SHARES. In the plugin, `RunAndCaptureStdout` MERGES the CLI's stderr banners
> ("(loaded defaults...)", "  FTS5 probe: ...") into captured stdout AROUND the JSON, and strict
> `TJSONObject.ParseJSONValue` returns nil on trailing non-JSON -> silent EMPTY results. Fixed in hover via a
> shared `SliceJsonBracket` helper (src/delphi-plugin/DragLint.Plugin.Editor.pas) for BOTH the `hover --json`
> object AND the `find-callers --json` array. ALSO fixed: `hover --qname` (CLI DoHover) only used the LAST
> `--db`, not all -> a symbol in an earlier db returned "No symbol matched". **AutoDoc's Called-from / Calls /
> Used-in facts (`src/doc/DRagLint.Doc.Facts.pas`) draw on the SAME find-callers/refs data -- audit for (a) the
> stderr-trailing-chatter JSON parse if AutoDoc shells out + captures merged stdout, and (b) multi-db coverage.
> Make AutoDoc's Called-from behave like the hover's (same slice + all-db search).** Verify against a symbol
> whose callers live in a NON-first db.
>
> **OPEN from v0.94 (user, deferred):** IDE live smoke for the "Create helper class" menu (reopen RAD Studio;
> 10-step checklist in `.superpowers/sdd/task-8-report.md`; BPL already built + committed `f16c5a3`).

> ## RESUME 2026-07-07 (LATEST-21) -- **ENUM-HELPER GENERATOR: IMPLEMENTED via SDD, final opus review READY TO RELEASE (0 Crit/0 Imp). RELEASE COMMIT STAGED -- PAUSED FOR USER PUBLISH SIGN-OFF.**
> `main` HEAD includes the release commit (VERSION `0.94.0-alpha` + this CHANGELOG + BACKLOG). **NOT pushed, NO GitHub release cut**
> -- the human drives push/publish (plan Task 10 Step 5). Clean except IDE json/dsv + 1 untracked forms-csv spec (LEAVE THOSE).
> **schema v15** (bumped from v14). Executed via **subagent-driven-development** (Tasks 0/1..9,9b + fixes, each implemented +
> per-task-reviewed clean, then a final whole-branch OPUS review = READY TO RELEASE). SDD ledger: `.superpowers/sdd/progress.md`
> (scroll to the "ENUM-HELPER GENERATOR MILESTONE" section at the END). Plan `docs/superpowers/plans/2026-07-07-enum-helper-generator.md`;
> spec `docs/superpowers/specs/2026-07-07-enum-helper-generator-design.md`.
> **>>> WHAT SHIPPED (3 coupled deliverables):**
> (A) **Generator** -- new `src/refactor/DRagLint.Refactor.EnumHelper.pas` (RESOLVE->GENERATE->PLACE->Build, reuses
> `TTextEditApplier`); CLI verbs `create-enum-helper` + `helpers-of`; IDE "Create helper class" menu (StructureForm.pas; BPL/DCP
> rebuilt Win32 + committed after the user closed RAD Studio). ONE Byte-family template (To*=Ord(Self); From*=`case Ord(member)`
> else first member; RTTI ToString/FromString default with `--tostring=case` override; ToDescription auto when a same-unit
> `<Enum>Descriptions` array exists). Idempotent create-only-if-missing.
> (B) **First-class helper indexing (schema v15)** -- new `type_helpers` edge table + `is_helper` symbol column (both in
> SCHEMA_DDL + Migrate; pre-v15 DB self-heals, regression-tested). Parser gained `TryWalkHelper` (the target is a `declHelper`
> node's `typeref` after `for`, NOT a plain `declClass`). Store methods `FindHelpersOfType(name)` +
> `FindHelpersOfTypeSymbol(id)`.
> (C) **`enum-helper-separate-units` lint rule (ON by default)** -- honored in BOTH DoLintAll + DoLintProject (single shared
> `TProjectLintRules.Run` call site, absent from every DefDisabled list). Validated **0 FP** on the self-index.
> **>>> KEY EXECUTION EVENTS (all resolved):** (1) Task 6 acceptance gate (real dcc64 compile+run) CAUGHT+FIXED a generator bug
> (case-mode FromString emitted invalid `case` on a string -> if/else-if chain). (2) USER DECISION mid-run: enums with explicit
> non-sequential ordinals lose Delphi auto-RTTI -> generator now AUTO-FALLS-BACK to case-mode even under default rtti (Task 6b,
> reads the enum decl source span, conservative-safe). (3) Task 9 FP sweep found `enum-helper-separate-units` had an 83% FP rate
> (name-only matching cross-linked same-named enums) -> Task 9b FIXED it via `FindHelpersOfTypeSymbol` symbol-identity match,
> self-index FP 6->1 (the genuine TP). Final opus review's 3 Minors all addressed (2 stale comments corrected; the "LF fixture"
> was a git-normalization false alarm -- `.gitattributes` stores all `.pas` as LF-in-blob/CRLF-on-checkout).
> **>>> NEXT ACTION = USER PUBLISH SIGN-OFF, then Task 10 Steps 3-5:** release-build win64+win32 exes, pack CLI-only zips, tag
> `v0.94.0-alpha`, push `main`+tag, cut the GitHub release (`--latest`, isPrerelease=false). **OPEN (user, deferred):** IDE live
> smoke for "Create helper class" (10-step checklist in `.superpowers/sdd/task-8-report.md`).
> **>>> FOLLOW-UP (own future milestone, unchanged):** the STRUCTURAL/SEMANTIC grep-elimination wishlist
> (`docs/superpowers/specs/2026-06-29-grep-elimination-indexer-wishlist.md`, addendum 2026-07-07) -- helper edges S1.1 SHIPPED
> here; section anchors S1.2 / uses-membership / decl-shape facts / outline-roster remain. The 2 old scoping docs
> `docs/lint/DESIGN-enum-helper-generator.md` + `INVESTIGATION-enum-helper-pattern.md` are SUPERSEDED by the spec but stay useful
> as ORM3 ground truth.
> **ALSO DONE (non-code):** appended a STRUCTURAL/SEMANTIC grep-elimination wishlist (addendum 2026-07-07) to
> `docs/superpowers/specs/2026-06-29-grep-elimination-indexer-wishlist.md` (helper edges S1.1 building now; section anchors S1.2
> maybe-folded-into-Task-4; uses-membership; decl-shape facts; outline/roster) -- SCHEDULED as its own future "indexer awareness"
> brainstorm milestone (user wants grep eliminated to reduce context/memory load). The 2 old scoping docs
> `docs/lint/DESIGN-enum-helper-generator.md` + `INVESTIGATION-enum-helper-pattern.md` are SUPERSEDED by the spec but stay
> useful as ORM3 ground truth.
> **--- v0.93.0-alpha + v0.92 both SHIPPED (LATEST-18/19 below); OPEN (none gating): IDE live smoke for the v0.93 Document
> menus + doc-drift Fix-it = USER; DLL refresh to v1.1.1 + pure-grammar swap (from v0.92). ---**
>
> ## RESUME 2026-07-07 (LATEST-19) -- **NEXT FEATURE = ENUM-HELPER GENERATOR (planned, NOT started -- brainstorm it). v0.93 shipped.**
> `main`=`2937f02` (enum-helper docs commit), synced w/ origin, clean except IDE json/dsv + 1 untracked forms-csv spec (leave). schema v14.
> **User (2026-07-07) wants drag-lint to AUTOMATE the standard enum `record helper`** -- `ToByte`/`FromByte`/`ToInteger`/
> `FromInteger`/`ToString`/`FromString` -- that ORM3's `C:\Projects\DB\ORM3\COMMON\MSCTYPES.PAS` hand-writes ~45x
> (MSCLIST *uses* them; the TYPES + helpers live in MSCTYPES). **Entry point:** right-click an enum MEMBER or the enum
> TYPE/class definition -> a context-menu item **"Create helper class"** (only when no helper exists yet).
> **>>> READ FIRST: `docs/lint/DESIGN-enum-helper-generator.md`** (scoping note + 6 open design Qs: ToString-RTTI-vs-case,
> helper placement, method set, member-vs-type trigger, CLI verb shape, IDE menu) **+ `docs/lint/INVESTIGATION-enum-helper-pattern.md`**
> (ground-truth pattern from MSCTYPES + the confirmed index support + a 10-case TESTING PLAN incl. a build+round-trip gate).
> **DE-RISKED:** the indexer ALREADY emits `skEnum` + `skEnumValue` (name+order, parser `DRagLint.Parser.Delphi13.pas:525-536`)
> -> the generator emits `ord(<member>)` and Delphi computes the ordinal, so NO parser change is needed (query
> `FindAllChildSymbols(enumId)` filtered to `skEnumValue`). It's a Track-4 Refactoring (code-gen action, sibling to
> AutoDocument/AutoFix; reuses the index + CLI verb + TTextEditApplier + IDE-menu substrate). **RESUME = run
> superpowers:brainstorming from those 2 docs (resolve the 6 Qs) -> writing-plans -> subagent-driven-development** (same
> flow as the last 2 milestones). Optional: reindex ORM3 to v14 (currently v13) to validate live against MSCTYPES enums
> (`drag-lint index C:\Projects\DB\ORM3 --db C:\Projects\DB\ORM3\drag-lint.sqlite`) -- NOT required (fixtures suffice).
> **--- v0.93.0-alpha (AutoDocument Finish) + v0.92 (preprocessor) both SHIPPED this session; see LATEST-18 below.
> OPEN (none gating): IDE live smoke for the Document unit/project menus + doc-drift Fix-it = USER (reopen RAD Studio);
> DLL refresh to v1.1.1 + pure-grammar swap (from v0.92). ---**
>
> ## RESUME 2026-07-06 (LATEST-18) -- **v0.93.0-alpha SHIPPED: AutoDocument Finish (Track 2 COMPLETE). Milestone done (14 SDD tasks + final whole-branch review that FOUND+FIXED 1 Critical).**
> `main` = release commit for v0.93.0-alpha, tag `v0.93.0-alpha`, VERSION CLI.pas:6=`0.93.0-alpha`, **schema still v14**.
> GH release LIVE (win64 3.82MB + win32 3.05MB CLI-only zips). Completes the AutoDocument track: whole-unit/project
> BATCH (`document --unit/--project/document-all`, facts-only default + `--stubs`), three ground-truth DOC-SOURCES
> (`@deprecated` directive / `<seealso>` call-graph capped / `<since>` git-opt-in-degrades-silently), the deterministic
> (no-LLM) `TDocDrift` engine (9 staleness signals), two LINT RULES (`doc-drift` ON+`--fix`-safe-subset-never-rewrites-prose;
> `missing-doc` OFF-by-default+single-fix-only-"Fix it"-excluded-from-batch), IDE menus (Document unit/project +
> doc-drift Fix-it), + a DocInsight-collection spike (recommendation: drag-lint SUPERSEDES the built-in). Executed via
> superpowers:subagent-driven-development (14 tasks each impl+reviewed CLEAN; final whole-branch opus review CAUGHT 1
> Critical the per-task reviews+guardrail all missed -- missing-doc was catalog-OFF but STILL FIRED at runtime because
> OFF-by-default is driven by the hardcoded DefDisabled list not the catalog flag; FIXED commit `e038503` in BOTH
> DoLintAll+DoLintProject + a bare-lint-all-yields-0 regression test; re-verified clean). NO-FABRICATION + IDEMPOTENCY
> both live-verified. Data-driven checkpoint: missing-doc measured 1302 on drag-lint's own tree -> USER chose OFF-by-default.
> Full battery green (lint 154/store 16/autodoc/autofix fixable=11/callresolve 12/preprocess 9). SDD ledger
> `.superpowers/sdd/progress.md` (full per-task + T13 final-review-found-Critical record). Spec/plan
> `docs/superpowers/specs|plans/2026-07-06-autodocument-finish-*`.
> **>>> OPEN (post-release):** (1) IDE LIVE SMOKE for the new Document unit/project menus + doc-drift Fix-it = DEFERRED TO
> USER (T10; reopen RAD Studio, right-click a symbol/unit -> Document unit/project; right-click a doc-drift finding -> Fix it).
> (2) plugin BPL (dclDragLintWizard) for the new menus was rebuilt in T10 commit `9883b7c` -- release ZIP is CLI-only per
> convention, BPL distributed separately. (3) Deferred cosmetic minors (final-review triage, ship-as-is): T1 double-sort,
> T2 scope-json-key, T3 3rd-local-read-helper, T6 facts-full-path-for-drift, T11c --fix-json-applied=false-on-fresh-insert
> (shared w/ doc-drift). (4) The DocInsight spike's "supersede the built-in" recommendation = a FUTURE decision (optional
> XML-doc emission), not scheduled. --- PRIOR (LATEST-17, now shipped as v0.92): in-process {$IFDEF} preprocessor. ---
> ## RESUME 2026-07-06 (LATEST-17) -- **v0.92.0-alpha SHIPPED: in-process {$IFDEF} preprocessor + per-config indexing. Milestone COMPLETE (all 12 SDD tasks + gate + final review READY-TO-PUBLISH).**
> `main` = release commit for v0.92.0-alpha, tag `v0.92.0-alpha`, VERSION CLI.pas:6=`0.92.0-alpha`, **schema still v14**.
> GH release LIVE (win64 3.78MB + win32 3.02MB CLI-only zips). The milestone ported the tree-sitter-delphi13 JS
> preprocessor to IN-PROCESS Object Pascal (NO Node in the shipped exe) so drag-lint resolves `{$IFDEF}` BEFORE
> parsing -> per-config-accurate indexing (only the active branch's symbols + `uses` indexed; the
> `{$IFDEF}`-cross-branch parse-failure class eliminated). Executed via superpowers:subagent-driven-development
> (11 impl tasks each impl+reviewed CLEAN 0-Crit/0-Imp; T8 empirical GATE PASSED raw-1->preprocessed-0; final
> whole-branch opus review = READY TO PUBLISH). Preprocess is ON by default; `--no-preprocess` reverts to
> all-branch; per-file try/except falls back to raw (never hard-fails). Offsets 1:1 (no source map). SDD ledger
> `.superpowers/sdd/progress.md` (full per-task record + the T12 final-review verdict + accumulated-minors triage).
> **>>> CROSS-REPO STATUS (important):** the tree-sitter-delphi13 grammar team REVIEWED our port + ran our
> oracle-diff harness and declared **the Delphi port CANONICAL for drag-lint** (no node, no serve.js). The one
> parity gap they flagged was **Task 6 (defines-only includes) -- which we SHIPPED**, so parity is COMPLETE and
> **we are the release trigger they're HOLDING their coordinated npm publish on**. New inbox docs (now committed):
> `docs/INBOX-tree-sitter-build-status-and-release-plan.md` (their v1.1.1-root/v1.1.0-pure build + coordinated
> release plan + the 3 things they need back), `docs/INBOX-tree-sitter-delivered.md`, `...-preprocessor-adoption.md`.
> **>>> FOLLOW-UPS -- CROSS-REPO LOOP CLOSED:** (1) DONE: replied to the grammar team (release trigger GO,
> tree-sitter-delphi13 `53f6ac7`). They REPLIED `docs/INBOX-tree-sitter-published-live.md`: **PUBLISHED the
> coordinated npm set** -- `tree-sitter-delphi13@1.1.1` (sha1 91a8e90fe854fab983e8919135c33db32bd0944e, the FULL
> DLL we bind) + `tree-sitter-delphi13-pure@1.1.0` (sha1 b6bd60d0a53f4129600b9b5d6588999de1ee10fa), both live +
> fresh-install-verified; JS `delphi13-preprocessor` stays 1.0.0 (Delphi canonical), DFM stays 1.0.0. Milestone
> CLOSED on their side; NO new asks. (2) DONE: D5 fast-follow tidy-up (`97754d0`). (3) QUEUED (own cycle, not
> gating anything -- their words): refresh the STALE bundled DLL `third_party/dll-win64/tree-sitter-delphi13.dll`
> (May 29) to the v1.1.1 build -> src/ 97.3%->99.1% + CLI.pas 39->1 errors, NO code change (`npx tree-sitter
> generate && node-gyp build` from master, or build from the npm tarball's src/; needs its own build+reindex+verify).
> (4) QUEUED post-milestone: swap to the pure grammar DLL (`tree_sitter_delphi13_pure`; drops pp_* rules; needs
> pre-resolved source -- our preprocessor now provides it) = separate milestone; grammar team offered to help line
> up the pure DLL + a before/after corpus if we prioritize it. (5) QUEUED: self-index reindex `--all --only
> DragLint` when the live IDE/LSP releases Delphi-RAG-lint.sqlite's lock (do NOT force-kill the IDE).
> --- PRIOR RESUME (LATEST-16, now DONE) --- PREPROCESSOR PORT MILESTONE: spec+plan DONE+PUSHED, about to EXECUTE via subagent-driven-development (12 tasks, on main). RESUME = dispatch PP-Task-1 implementer.**
> `main` synced with origin (0 ahead, clean except IDE json/dsv + 3 untracked docs -- leave those).
> **NO subagent work in flight** -- this handoff fired at a CLEAN boundary (before PP-Task-1 was dispatched),
> so nothing is lost; the next session resumes by dispatching PP-Task-1.
> **>>> READ FIRST: `.superpowers/sdd/progress.md` -> scroll to the "PREPROCESSOR PORT MILESTONE -- EXECUTION
> LEDGER" section at the END of the file (below the D5 ledger). It has the full mode / global-constraints /
> per-task model assignments / pre-flight-scan (CLEAN) / PP task status.**
> **MILESTONE:** port the tree-sitter-delphi13 JavaScript preprocessor to IN-PROCESS Object Pascal (NO Node.js
> in the shipped exe) so drag-lint resolves `{$IFDEF}` before parsing -> per-config-accurate indexing
> (~98.2% -> 99.3% on the grammar team's corpus; fixes the `{$IFDEF}`-cross-branch parse-failure class,
> the largest single class of misses). Spec `docs/superpowers/specs/2026-07-06-preprocessor-port-design.md`;
> plan `docs/superpowers/plans/2026-07-06-preprocessor-port-plan.md` (12 tasks, TDD, oracle-diff) -- both
> APPROVED + PUSHED.
> **KEY DESIGN DECISIONS (all approved in brainstorm):**
> - In-process port: 3 units (`DRagLint.Preprocess.Lexer/Expr/Preprocess`, ~500 lines mirroring the JS
>   `lexer.js`/`evalExpr.js`/`preprocess.js`) + a `DRagLint.Preprocess.Profile` define-profile resolver. No
>   Node, no subprocess, no server/frame protocol (all collapsed by the port decision).
> - `defines-only` include mode (read a `.inc`'s `{$DEFINE}`/`{$UNDEF}` into the parent, blank the `{$I}`
>   body) -> `Length(output) == Length(input)` -> offsets 1:1 -> NO source map (spans stored as original-file
>   offsets directly). Port ONLY `defines-only` + `off`; NEVER `expand` (body-splice).
> - Build against the CURRENT full grammar first (a valid shippable intermediate -- the full grammar parses
>   already-resolved single-branch input). The `pure` grammar DLL is a POST-MILESTONE follow-up (request it
>   from the grammar team AFTER the port is built). PP-Task-8 is a GATE that empirically verifies
>   preprocess->current-full-grammar parses resolved input at least as well as raw; a T8 FAILURE STOPS the
>   plan (pure DLL becomes a prerequisite after all).
> - FULLY per-config: BOTH within-file symbol extraction (T9) AND the `Index.Closure` uses-scanner (T10)
>   honor the active define profile. The index reflects exactly one build config; cross-platform coverage is
>   preserved at the multi-DB level (separate library-Win32 / library-Win64 DBs).
> - Define profile: from the `.dproj` (platform built-ins UNION Base + RELEASE config `DCC_Define`;
>   `--config Debug` / `--platform Win32` override) for projects; platform built-ins only for library scans;
>   Win64 built-ins fallback for a missing/loose `.dproj`.
> - The JS at `C:\Projects\tree-sitter-delphi13\preprocessor\` is the byte-for-byte TEST ORACLE (node
>   v24.13.0 confirmed) -- Node is a TEST-ONLY / dev dependency; the shipped drag-lint exe never calls it.
> **USER CONSENT:** execute directly on main (AskUserQuestion 2026-07-06). Execute all 12 tasks +
> task-reviews autonomously; final whole-branch review; PAUSE before Task 12 publish (version bump / tag /
> release) for user sign-off.
> **CROSS-REPO:** our preprocessor reply is committed + pushed to the tree-sitter-delphi13 repo (`60a57e7`);
> they DELIVERED all three of our asks (`docs/INBOX-tree-sitter-delivered.md` -- defines-only mode + serve.js
> [which we WON'T consume, since we're porting in-process] + README fix). NOTIFY them the preprocessor is
> PORTED + passing vs their oracle, and REQUEST the pure grammar DLL = Task 12 step 3 (AFTER the port is built).
> **STILL PENDING from D5 (LATEST-15, unchanged):** the D5 fast-follow tidy-up (5 deferred minors, 1 commit
> -- T7 confidence-sort comment / T3 inline-var+overload fixture / T10 same-leaf Calls assertion / T12-T13
> regex+probe tidy / T1 KindText figure). Non-blocking; do it before or after the preprocessor milestone.
> **GOTCHAS (preprocessor):** (1) the feature is ABOUT `{$..}` directives -- NEVER a literal `{` or `}` inside
> a Pascal `{ }` comment (directive literals are STRING constants; comments describing directives use `//`
> only). (2) byte-verify every new `.pas`/`.ps1` is CRLF (dcc64 + node both tolerate LF, so the build won't
> catch a lone-LF -- D5 lesson). (3) T2 must use a TBytes-based scanner (byte offsets, not char count) so
> UTF-8 offsets match tree-sitter -- the one real JS-divergence risk. (4) T5 fixtures are EXPECTED to expose
> lexer divergences (strings/comments/passthrough) -- that's the oracle-diff doing its job, not a defect.
>
> --- (prior) ---
> ## RESUME 2026-07-06 (LATEST-15) -- **v0.91.0-alpha SHIPPED (D5 call resolution -- THE Called-from bug fix). NEXT = D5 fast-follow tidy-up, THEN tree-sitter preprocessor discussion.**
> `main` = the v0.91.0-alpha release commit (VERSION CLI.pas:6=`0.91.0-alpha`, CHANGELOG + BACKLOG),
> tag `v0.91.0-alpha`, pushed + origin synced. **schema NOW v14** (call_edges + skLocalVar/skParam).
> GH release live (win64 + win32 CLI-only zips). BACKGROUND LIBRARY REINDEX launched at publish
> (v14 forces full reparse; log `C:\TEMP\d5-library-reindex.log`).
> **D5 executed via superpowers:subagent-driven-development -- all 13 tasks impl+reviewed CLEAN (0 Crit/0 Imp
> each) + final whole-branch opus review = READY TO PUBLISH (0 Crit/0 Imp).** Plan
> `docs/superpowers/plans/2026-07-06-d5-call-resolution-plan.md`; spec
> `docs/superpowers/specs/2026-07-06-d5-call-resolution-design.md`; SDD ledger `.superpowers/sdd/progress.md`
> (full per-task record + the deferred-minors roll-up).
> **What shipped:** schema v14 + `call_edges` table; parser emits typed params (`skParam`) + locals
> (`skLocalVar`); `TCallResolver` receiver-typing engine (`src/index/DRagLint.Index.CallResolver.pas`,
> prepare-once, 6 receiver kinds, FP-conservative -- reviewer PROVED no wrong-`certain` path);
> `ResolveCallTargets` whole-DB pass wired after `ResolveAncestry` at 3 sites; **THE BUG FIX** --
> AutoDocument Called-from now resolved (excludes confirmed-different, `?` for untypable, real caller
> never lost); Calls facts prefer resolved qualified callees; 6 verbs (find-callers --resolved,
> find-callees, ambiguous-calls, call-path, callgraph, purge-locals) + dump-call-edges; v13->v14
> migration self-heals. Full battery green: lint 154/store 16/autodoc 7/autofix 9/callresolve 12.
> **>>> NEXT ACTIONS (in order):**
> (1) **D5 FAST-FOLLOW tidy-up** (ONE commit, non-blocking, from the ledger roll-up): T7 CASE-ordinal/comment
>     on `confidence DESC` sort; T3 in-tree inline-var-deferral comment + overloaded-routine local/param fixture;
>     T10 harness assertion for same-leaf-different-qualified Calls (TAlpha.Run + TBeta.Run one body);
>     T12/T13 loosen purge success-message regex coupling; T1 fix `32->34` KindText figure in notes.
> (2) **tree-sitter PREPROCESSOR discussion (user-flagged 2026-07-06):** the tree-sitter-delphi13 Opus says
>     PURE tree-sitter is NOT enough for good indexing -- we need a PREPROCESSOR pass to handle Delphi
>     compiler directives / conditional compilation before parsing, to cut parse errors. It updated tree-sitter
>     but is still isolating more errors. Details dropped in `docs/INBOX-tree-sitter-preprocessor-adoption.md`
>     (untracked). DISCUSS + design how drag-lint adopts a preprocessor step in its parse pipeline. This is the
>     next real milestone candidate after the D5 fast-follow.
> **Working-tree note (HISTORICAL, resolved):** the CLI.pas YADF/reformat conflict was resolved during D5 by
> committing the IDE-reformatted CLI.pas as a baseline (`a14b58b`); YADF copy preserved at `.yadf-artifacts/`.
> D5 Task 7 regenerated the stray Run doc-comment correctly. Pre-existing dirty (leave as-is): drag-lint.delphilsp.json,
> drag-lint.dsv (IDE artifacts), + untracked forms-csv-v4 spec + docs/INBOX-tree-sitter-preprocessor-adoption.md.
>
> --- (prior) ---
> ## RESUME 2026-07-06 (LATEST-13) -- **v0.90.0-alpha SHIPPED (AutoDocument Chunk 1). NEXT = AutoDocument Chunk 2.**
> `main` = release commit (pushed, origin synced, clean). VERSION CLI.pas:6=`0.90.0-alpha`, **schema still v13**.
> Executed via superpowers:subagent-driven-development (8 tasks + final whole-branch opus review = READY TO
> RELEASE, 0 Critical / 0 Important). Plan `docs/superpowers/plans/2026-07-05-autodocument-chunk1-plan.md`;
> spec `docs/superpowers/specs/2026-07-05-autodocument-chunk1-design.md`. SDD ledger `.superpowers/sdd/progress.md`.
> **What shipped (AutoDocument Chunk 1 = generate + repair a DocInsight comment for ONE public decl via MANAGED
> REGIONS):** new `document --qname X [--apply|--json|--no-backup] [--db]` CLI verb + IDE "Document it" menu. Three
> new units src/doc/: `DRagLint.Doc.Facts` (index -> TDocFacts: Called-from/Calls/Used-in/Raises/Returns; no text),
> `DRagLint.Doc.Regions` (RenderFactsBlock + MergeComment: preserve hand prose, regen the sentinel-fenced facts
> block + managed <param> tags, idempotent; no index), `DRagLint.Doc.Document` (orchestrator -> TArray<TTextEdit>,
> classify created/extended/unchanged/not_found). Facts block fenced by `<!-- drag-lint:auto BEGIN/END -->` inside
> <remarks>; per-param `<!-- drag-lint:auto param -->`. Cap: >15 -> 10 + `(+N more)`. NEVER fabricates (summary/
> param = `TODO: describe.`); every fact index/AST-grounded. IDEMPOTENT (2nd run = unchanged, byte-identical --
> reviewer-traced end-to-end). Also exported the DocStub sig helpers (visibility only; generate-docs unchanged).
> **KEY BUILD DECISIONS / GOTCHAS (this ship):** (1) T3 outgoing-Calls = the flagged risk -- PRE-VERIFIED via a
> live spike (no store method filters refs by enclosing_symbol_id; GetReferencesFromFile emits EVERY identifier so
> the enclosing-filter over-captures locals/params) -> used the body-scan `Ident(` fallback (scratchpad/t3-calls-
> spike-decision.md). (2) real TSymbol field is `QualifiedName` NOT `QName` (plan text wrong). (3) `HasRet` must use
> `Facts.ReturnType<>''` (indexed Signature has no `function` kw; class fns=skMethod not skFunction). (4) TWO
> idempotency bugs caught by T5 review: the daUnchanged compare `SameText(Trim(RawBlock),Trim(Merged))` COULD NEVER
> MATCH (RawBlock has `///` stripped, Merged is `/// `-prefixed) -> fixed to per-line-normalized current-source-vs-
> Merged; AND `Called from:` embedded caller LINE NUMBERS that shift every apply -> fixed to file-name-only. (5)
> AUTO_PARAM sentinel is EMIT-ONLY (the doc parser strips it) -> managed/hand-typed is CONTENT-based. (6) multi-line
> hand <remarks> prose must be emitted PER-LINE (bare-LF join bug caught by T4 review). Battery at ship: lint 154/154,
> store 16/16, autodoc 6/6, autofix 9/9. IDE "Document it" LIVE SMOKE = DEFERRED TO USER (source Approved, BPL built).
> **>>> NEXT = AutoDocument Chunk 2** (roadmap `docs/lint/drag-lint TODO plan.md` Track 2.2/2.3): brainstorm ->
> spec -> plan -> SDD. Candidates: whole-UNIT / whole-PROJECT batch document; more doc sources (`<seealso>` from
> related symbols, `<since>`/`@deprecated` from VCS or `deprecated` directive); a `missing-doc` report-only lint
> rule; the RAD Studio DocInsight-collection spike. **DEFERRED (user):** semantic-drift detection (behaviour change
> -> hand prose needs updating -- needs intent understanding, not structure).
> **>>> 2 CHEAP FAST-FOLLOWS = DONE (commit `9113e16`, 2026-07-06, pushed):** (a) CalledFrom-dedupe REGRESSION
> fixture landed -- `tests/autodoc/run_doc_dedupe.ps1` + `doc_dedupe.pas` (CallsTwice invokes Target 2x -> dump-refs
> PROVED both refs enclose CallsTwice=id3 -> without dedupe it'd render twice; test asserts ONCE); (b) DEAD
> `action=not_found` JSON arm relabeled to defensive `'unknown'` + comment (daNotFound returns text+exit1 before the
> --json block). autodoc now 7/7. NOTE: this is a POST-release tidy-up on main AFTER the v0.90.0-alpha tag -- the
> released binary is unchanged (test-only + cosmetic). Optional remaining (c) a Calls/Raises-bearing idempotency
> fixture to harden the shift-invariance lock -- still open, low value. All other Minors DEFER-SAFE (T3 Calls
> over-capture, T4 blank-line drop + `TODO:` desc edge -- documented, best-effort).
> **>>> KNOWN BUG (found 2026-07-06 via real "Document it" use, USER-TRIAGED -> fix = D5 milestone):**
> AutoDocument's **Called-from facts are NAME-BASED -> FALSE callers for common method names** (Run/
> Execute/Create). `document --qname DRagLint.CLI.Run` listed DoFbSnapshot etc. that call a DIFFERENT
> `Run`. Root cause: Doc.Facts:244/:312 use `FindCallersByName(name)` = every ref to the name. USER
> CHOSE the proper fix (2026-07-06): resolve refs to symbol_id at index time = the **D5 indexer
> milestone** (see sec 6.x / line ~1422), then switch Called-from to `FindReferencesTo(symbolId)`.
> D5 now serves BOTH forms-csv AND AutoDocument. Full diagnosis in the D5 backlog item. Own chunk
> (brainstorm->spec->plan->SDD); not a v0.90.x patch. AutoDocument Chunk 1 otherwise SHIPPED + solid.
> CADENCE (user, unchanged): publish chunk -> plan next -> handoff -> clear -> implement -> publish.
>
> --- (prior) ---
> ## RESUME 2026-07-05 (LATEST-12) -- **v0.89.0-alpha SHIPPED. AutoDocument Chunk 1 DESIGNED (spec+plan). NEXT = EXECUTE the plan.**
> `main`=`fcbb439` (clean, pushed, origin synced). VERSION CLI.pas:6=`0.89.0-alpha`, **schema still v13**.
> **>>> NEXT ACTION = execute `docs/superpowers/plans/2026-07-05-autodocument-chunk1-plan.md` (8 tasks) via
> superpowers:subagent-driven-development (or executing-plans).** Spec (approved):
> `docs/superpowers/specs/2026-07-05-autodocument-chunk1-design.md`.
> **AutoDocument Chunk 1 = generate + repair a DocInsight comment for ONE public declaration** (vertical slice;
> Chunk 2 later widens to unit/project). Core = **managed regions**: drag-lint owns sentinel-fenced parts of the
> comment -- a facts block `<!-- drag-lint:auto BEGIN -->...<!-- drag-lint:auto END -->` inside `<remarks>`, plus
> per-param `<!-- drag-lint:auto param -->` markers -- regenerated idempotently, NEVER clobbering hand-written
> prose. `<summary>`/`<param>` bodies are always `TODO: describe.` (never fabricate; a wrong summary is worse than
> none). Facts block = **Called from / Calls / Used in units / Raises / Returns**, all index/AST-grounded, capped
> at 10 with `(+N more)` when the true total > 15 (<=15 shows all).
> **Plan tasks:** T1 scaffold 3 units under `src/doc/` (`DRagLint.Doc.Facts`/`.Regions`/`.Document`) + dproj
> wiring -> T2 Facts Called-from+Returns+cap -> T3 Facts Calls/Used-in/Raises (**RISK: outgoing-"Calls" store
> query is UNVERIFIED -- verify FIRST via a spike; body-scan fallback ready; the Calls section is omittable, since
> Called-from is the solid headline**) -> T4 Regions managed-block + MergeComment (also EXPORT the DocStub param
> helpers `ExtractParamList`/`ParseParamNames`/`SignatureHasReturn` to the interface) -> T5 `Doc.Document`
> orchestrator + new `document --qname X [--apply|--json|--no-backup]` CLI verb (template = `DoFindUnit`
> CLI.pas:6149; `generate-docs` stays legacy print-only) -> T6 six `tests/autodoc/run_doc_*.ps1` harnesses
> (generate / idempotent / extend / stale-param / cap / verb) -> T7 IDE "Document it" menu (live-smoke, cut last)
> -> T8 full battery + publish v0.90.0-alpha.
> **REUSES (do not rebuild):** `TDocStubGenerator` sig helpers (DocStub.pas), `TDocCommentScanner.Scan` +
> `FindDocRegionAbove` (Indexer.pas:148) + `TDocCommentParser.Dispatch`->`TParsedDoc`, `TTextEditApplier`,
> `ISymbolStore.FindCallersByName`/`GetSymbolById`/`GetSymbolSlice`.
> **BUILD GOTCHAS (in the plan):** new unit = a `<DCCReference>` in `src/cli/drag-lint.dproj` (after line 140) AND
> a CLI `uses` entry; NO literal `{`/`}` inside a Pascal `{ }` comment (breaks the compile -- the PostToolUse
> self-lint error-count jump is a canary, but the delphi-build result is the gate); run PS harnesses from a NEUTRAL
> CWD (C:\TEMP); `${tag}:` not `"$tag:"` in PowerShell; fixtures ASCII/CRLF, unit name = filename.
> **DEFERRED (user):** semantic-drift detection (behavior change -> hand-written prose needs updating) -- out of
> scope; needs intent understanding, not structure. Next-chunk doc-source candidates: `<seealso>`, `<since>`/
> `@deprecated`, whole-unit/project batch, the RAD Studio DocInsight-collection spike, a `missing-doc` lint rule.
> CADENCE (user): plan -> handoff -> clear -> implement -> publish. (You are at CLEAR: run implementation next.)
>
> --- (prior) ---
> ## RESUME 2026-07-05 (LATEST-11) -- **v0.89.0-alpha SHIPPED (AutoFix Chunk 2). AutoFix TRACK COMPLETE. NEXT = AutoDocument.**
> `main` tag `v0.89.0-alpha` (release commit; pushed, origin synced, clean). VERSION CLI.pas:6=`0.89.0-alpha`, **schema still v13**.
> Executed via superpowers:executing-plans (13 tasks + final whole-branch review: 0 Critical, 1 Important verified-safe [no change],
> 1 Minor fixed [EditedKeys keyed by file|line|rule]). Plan `docs/superpowers/plans/2026-07-05-autofix-chunk2-plan.md`;
> spec `docs/superpowers/specs/2026-07-05-autofix-chunk2-widen-fixable-design.md`.
> **What shipped (AutoFix Chunk 2 = widen the fixable set 3 -> 9, all sweep-verified):** 6 new fixable rules --
> `redundant-not-not` (not not X -> X), `redundant-as-tobject` (X as TObject -> X), `boolean-comparison-true`
> (=True/<>False -> X; =False/<>True -> not X, compound-operand paren-guarded via `IsSingleTokenAtom` incl. already-paren'd LHS),
> `reserved-word-casing` (lowercase keyword), `redundant-assigned-free` (drop `if Assigned(X) then` guard; delimited-then + single-line),
> `off-by-one-count` (append ' - 1'; **behaviour-CHANGING** -> `risky` tag). + risky-fix registry (`RISKY_FIX_RULE_IDS`+`IsRiskyFixRule`;
> `--fix --json` emits `risky:true`, text preview prints `[risky]`; Fix-it + Fix-all both apply it). + batch-fix-respects-config
> (already-correct via FinalizeAndOutput ShouldKeep; now TESTED `run_fix_respects_config.ps1` + DOCUMENTED docs/AI-USAGE.md sec 4b).
> + Minor 1 (`applied` per-finding, keyed file|line|rule) + Minor 2 (`--fix --format sarif` stderr note + text). Battery green at ship:
> lint 154/154, store 16/16, autofix 9 suites (single/unit/project/catalog=9/newrules/risky-tag/respects-config/applied-accounting/sarif-note).
> **3 pre-release bugs caught by tests:** registry desync (as-tobject+boolean-comparison had branches but weren't in FIXABLE_RULE_IDS ->
> caught by catalog=9 test); double-paren `(A and B) = False` -> `not ((A and B))` (fixed via IsSingleTokenAtom fully-paren'd fast-path);
> `applied:true` on no-edit findings (Minor 1). LESSON: literal `{`/`}` inside a Pascal `{ }` comment breaks compilation -- the self-lint
> error-count jump (16 -> 54) is a useful canary; the real Delphi build is the authoritative gate.
> **>>> AUTOFIX TRACK IS COMPLETE.** The 163-rule sweep (`scratchpad/sweep-result.json`) proved 9/163 is the full mechanically-safe set;
> the other 154 rules are report-only detectors (need type/flow/rename/restructure). No rule-widening remains.
> **>>> NEXT TRACK = AutoDocument** (Track 2 in `docs/lint/drag-lint TODO plan.md`): brainstorm -> spec -> plan -> SDD -> publish.
> Optional deferred Track-1 tail (not blocking): FAutoFix save-time auto-apply control (the per-rule IDE checkbox becomes a live
> auto-fix-on-save preference); `boolean-comparison-true` "last vs first depth-0 op" is verified-safe for all real inputs (review Important,
> no change). CADENCE (user, unchanged): publish chunk -> plan next -> handoff -> clear -> implement -> publish.
>
> --- (prior) ---
> ## RESUME 2026-07-05 (LATEST-10) -- **v0.88.0-alpha SHIPPED (AutoFix Chunk 1). NEXT MILESTONE = AutoFix Chunk 2.**
> `main` tag `v0.88.0-alpha` (pushed, origin synced, clean). VERSION CLI.pas:6=`0.88.0-alpha`, **schema still v13**.
> GitHub release live (win64 3.67MB + win32 2.94MB zips, `--latest`, isPrerelease=false).
> **Executed via superpowers:subagent-driven-development, 8 tasks + final whole-branch opus review (READY TO RELEASE,
> 0 Critical/0 Important) + 1 bundled doc fast-follow (`4dec6f1` -- BuildAutofixEdits summary listed all 3 rules).**
> SDD ledger `.superpowers/sdd/progress.md` (archive: progress-formscsv-v4-archive.md).
> **What shipped (AutoFix Chunk 1 = the full "Fix it" vertical slice on the 3 existing fixable rules):** T1 fix registry
> (`FIXABLE_RULE_IDS`+`IsFixableRule`, output-neutral) -> T2 `fixable` flag in `rules --json` -> T3 `lint --file F --fix
> --fix-line L --fix-rule R [--json]` single-finding fix (+ bundled fix: `lint` now honours `--file` as a path alias,
> which the IDE + spec contract needed) -> T4 whole-unit fix (test) -> T5 whole-project fix via `lint-all --fix --apply`
> (already worked through the shared FinalizeAndOutput --fix block; test locks it) -> T6 `FAutoFix` id-array in TLintConfig
> (`autofix` array round-trips drag-lint-lint.json) -> T7 IDE "Fix it"/"Fix all in unit|project" context menu on the
> Diagnostics tree (StructureForm.pas; ForceQueue string-only reload) -> T8 per-rule "auto-fix" checkbox in Lint Options
> (only on fixable rules). Battery green at ship: lint 154/154, store 16/16, fixable-catalog + fix-single + fix-unit +
> fix-project all exit 0. **IDE LIVE SMOKE PASSED (user, 2026-07-05): "Fix it" removed redundant parentheses in the real
> IDE.** BPL built clean (Win32); user deployed via deploy-staged.bat.
> **>>> NEXT MILESTONE = AutoFix Chunk 2. DIAGNOSIS DONE (2026-07-05) -- LEAD ITEM RESOLVED to TEST+DOC, NOT code:**
> The user asked that batch autofix ("Fix all in unit|project", `lint --fix`/`lint-all --fix`) apply ONLY fixes for
> CHECKED (enabled) rules. **DIAGNOSIS (CLI.pas:4623-4651, CONFIRMED by reading FinalizeAndOutput):** findings pass
> through `Cfg.ShouldKeep(F.RuleId, IsDefDis)` (the enable/disable config filter) into `Survivors` at 4626-4637
> **BEFORE** the `--fix` block (2c, :4651) -- and `--fix` operates only on `Survivors`/`Targeted`. The block's own
> comment says "quick-fixes for the CONFIG-SURVIVING findings." So **batch fix ALREADY skips disabled rules today**;
> `lint-all` routes through the same FinalizeAndOutput (Task 5), so it's gated identically. The user's requested
> behaviour ALREADY EXISTS -- it was just never TESTED or DOCUMENTED (the spec conflated the ENABLE checkbox with the
> separate AUTO-FIX checkbox). **USER DECISION 2026-07-05: "test + document it"** -- Chunk 2 lead item = (a) a
> regression test that toggles a rule OFF in drag-lint-lint.json, runs `lint --fix` (+ `lint-all --fix`), and asserts
> that rule's findings are NOT fixed; (b) document "batch fix respects the active rule set" in AI-USAGE.md + CHANGELOG.
> Small. The FAutoFix checkbox (Task 8) is thus NOT the batch gate -- it becomes a future SAVE-TIME auto-apply control
> (Track-1 later item). **Chunk 2's SUBSTANCE = WIDEN the fixable-rule set beyond the 3** (each new rule = a
> FIXABLE_RULE_IDS entry + a BuildAutofixEdits branch + a fixture; the catalog flag / "Fix it" item / auto-fix checkbox
> all light up automatically -- pick the next mechanical/side-effect-free rules to make fixable).**
> CADENCE (user, unchanged): publish chunk -> plan next batch -> handoff -> clear -> implement -> publish.
> Chunk-2 also-includes (from final-review Minors, all deferred): untargeted `lint --fix --json --apply` reports
> applied:true for no-edit findings (fold into gating, same JSON/edit accounting); `--fix --format sarif` falls to text;
> WIDEN the fixable-rule set beyond the 3 (each = a FIXABLE_RULE_IDS entry + a BuildAutofixEdits branch + a fixture).
> **Roadmap:** `docs/lint/drag-lint TODO plan.md` (Track 1 AutoFix -> Track 2 AutoDocument -> Track 3 Convert Components;
> Track 4 Refactoring = REFACTOR-LIST). Spec of what shipped: `docs/superpowers/specs/2026-07-05-autofix-chunk1-fix-it-design.md`.
>
> --- (prior) ---
> ## RESUME 2026-07-05 (LATEST-9) -- **NEXT = execute the AutoFix Chunk 1 plan via subagent-driven-development.**
> `main`=`21b287c` (clean, pushed, synced with origin). **>>> Execute
> `docs/superpowers/plans/2026-07-05-autofix-chunk1-plan.md` via superpowers:subagent-driven-development** -- 9 TDD
> tasks (CLI-first/unit-testable, then IDE/live-smoke): T1 fix registry (extract `FIXABLE_RULE_IDS` + `IsFixableRule`
> out of `BuildAutofixEdits`' hardcoded if/else, CLI.pas:4457, NO behavior change -- guardrail: lint suite 154/154
> stays green) -> T2 `fixable` flag in `rules --json` (DoRules emitter CLI.pas:4710) -> T3 single-finding fix verb
> `lint --file F --fix --fix-line L --fix-rule R [--apply|--json|--no-backup]` (extends the existing --fix block
> CLI.pas:4621; --json is a 1st-class AGENT contract -- CLI verbs run token-free) -> T4 whole-unit fix (test-only,
> whole-file path already exists) -> T5 whole-project fix (extend DoLintProject:6094 or DoLintAll:5878 -- DIAGNOSE
> which first) -> T6 `FAutoFix` id-array in TLintConfig (Lint.Config.pas, `autofix` array in drag-lint-lint.json,
> mirror FEnabled) -> T7 IDE StructureForm.pas: add `Code`/rule-id to TStructureNodeData, context-sensitive FPopup
> ("Fix it" on a fixable FINDING node; "Fix all in unit"/"in project" on the "Diagnostics" ROOT node), reload via
> Keyboard.pas:284 ForceQueue+IOTAModule.Refresh -> T8 2nd "auto-fix" checkbox per FIXABLE rule in LintOptionsFrame
> (RenderCatalog:860 / Save:1071) -> T9 publish v0.88.0-alpha (bump CLI.pas:6, CHANGELOG, pack, final opus review,
> tag, gh-release).
> **Spec (approved):** `docs/superpowers/specs/2026-07-05-autofix-chunk1-fix-it-design.md`.
> **Roadmap context:** `docs/lint/drag-lint TODO plan.md` was rewritten this session into 4 sequenced tracks
> (Track 1 AutoFix -> Track 2 AutoDocument -> Track 3 Convert Components; Track 4 Refactoring links to REFACTOR-LIST).
> AutoFix Chunk 1 = the full vertical slice PROVEN on the 3 existing fixable rules (self-assignment,
> redundant-parentheses, redundant-cast); WIDENING the rule set = later chunks (each new rule = a FIXABLE_RULE_IDS
> entry + a BuildAutofixEdits branch + a fixture; the catalog flag, "Fix it" item, and checkbox all light up
> automatically).
> **KEY DECISIONS (locked in brainstorm):** string rule-ids are canonical (NO numeric rule-number scheme); the 2nd
> checkbox renders ONLY on fixable rules; CLI verbs are token-free for AI orchestration so `--json` is a supported
> agent contract, bounded by the safe-fix registry (mechanical/side-effect-free rules only); CADENCE = publish each
> chunk as a release, then plan next -> handoff -> clear -> implement.
> **BUILD GOTCHAS (in the plan):** delphi-build recipe (staged win64 exe `third_party\dll-win64\` not the raw
> Release exe = 0xC0000135); run PS harnesses from a NEUTRAL CWD (C:\TEMP); fixture .pas must be CRLF; the plugin
> BPL only builds while RAD Studio is CLOSED, so T7/T8 end in a LIVE SMOKE (not unit-testable); additive guardrail =
> `lint --fix` whole-file output byte-identical after T1's registry refactor.
> **Also this session:** recorded the `handoff-always-safe` preference (never ask to confirm a handoff -- auto-memory
> `feedback_handoff_always_safe.md`).
>
> --- (prior) ---
> ## RESUME 2026-07-05 (LATEST-8) -- **v0.87.0-alpha PUBLISHED (forms-csv v4 navigation). Milestone COMPLETE.**
> `main` includes merge `b4c0268` (forms-csv v4) + tag `v0.87.0-alpha`. GitHub release live (win64+win32 zips,
> `--latest`, isPrerelease=false). VERSION `CLI.pas:6`=`0.87.0-alpha`. **No index-schema change (still v13).**
> Executed via superpowers:subagent-driven-development, 5 tasks + final whole-branch opus review (READY-TO-MERGE, 0
> Critical/0 Important) + 1 bundled fast-follow (schema-footer fix `fc18cce`). SDD ledger `.superpowers/sdd/progress.md`.
> **What shipped:** forms-csv resolves the plan-editor family (Z14slctFrm/Z19slctFrm + ~18 `TxxxPlan.EditForm`) from
> "(no path from MAIN)" to `frmMAIN -> ... -> frmControlPlan2 -> 'Plan' -> <form>` (VERIFIED against the full ORM3 db:
> all 6 named family forms resolve). **L1** interface dispatch = the existing name-based caller walk already bridges it
> (diagnosis proved the heritage helper = YAGNI, comment-only). **L2** proc-var hook (`PlanEditFormHook := ShowPlanEditor`,
> invisible to refs) = bounded source text-scan (`BuildHookMap`/`ParseHookAssign`) + dead-end continuation
> (`FindFormViaHook`) at the ProcessSite OC='' branch, reuses the L1 walk, loop-safe single hop. **L0** stderr guardrail:
> forms with callers but no MAIN-path (COMMON-absent db) -> "run against the full-tree index" note. `FORMS_CSV_ALGORITHM`=4.
> Also fixed the provenance footer (`schema v0`->real `schema_meta` version) and BUNDLED 2 same-day fixes now in a release:
> forms-csv header-move `fc7e630` + live-lint `unit-name-matches-file` FP `bb6eb82`. All in `DRagLint.FormsMap.pas`.
> **OPEN (fast-follows, sec 6.x -- none blocks anything):** (a) regression-guard the guardrail + `@Routine` hook form (2nd
> fixture unit + stderr assertion; verified out-of-band only); (b) BuildHookMap Pass A micro-opt; (c) IDE menu -> full-tree
> db (Layer 0 delivery); (d) D5 indexer milestone (receiver-type/proc-assign/impl_of refs -> removes L2 text-scan; own
> brainstorm->spec->plan, schema bump). **NEXT MILESTONE (unchanged): Change Signature** (REFACTOR-LIST.md "recommended
> next") -- brainstorm -> spec -> plan; reuses rename's cross-unit apply + Extract Method's liveness pass.
>
> --- (prior) ---
> ## RESUME 2026-07-05 (LATEST-7) -- **NEXT = execute the forms-csv v4 navigation plan via subagent-driven-development.**
> `main`=`812fab1` (clean, pushed, synced with origin). **>>> Execute
> `docs/superpowers/plans/2026-07-05-forms-csv-v4-navigation-plan.md` via superpowers:subagent-driven-development** -- 5 TDD
> tasks: T1 RED fixtures (a SECOND `tests/fixtures/formsmap-v4/` project: interface dispatch + hook) -> T2 Layer 1
> interface-method fan-in bridge (DIAGNOSE-then-fix: run `dump-refs` on the RED fixture FIRST to see if the direct case
> already resolves; YAGNI the heritage helper if so) -> T3 Layer 2 hook-registration TEXT-SCAN pre-pass + dead-end
> continuation -> T4 'Plan' caption at the bridge + `FORMS_CSV_ALGORITHM`->'4' + Layer 0 db-scope stderr guardrail -> T5
> real-DB smoke (Z14/Z19/family resolves against the FULL ORM3 db) + regression sweep.
> **Spec (all grounded root-cause evidence):**
> `docs/superpowers/specs/2026-07-05-forms-csv-v4-hook-and-interface-navigation-design.md`.
> **v4 GOAL:** the plan-editor form family (Z14/Z19 + ~18 `TxxxPlan.EditForm`) shows "(no path from MAIN)"; make it render
> `frmMAIN -> ... -> frmControlPlan2 -> 'Plan' -> <form>`. THREE grounded layers: **L0 db-scope (DOMINANT)** -- the report
> ran against the CLIENT-only `Micronite2027.sqlite` which lacks `COMMON\OBJECTS\uPLANLIST.PAS` where the `EditForm` launch
> bodies live (`query --name EditForm` = 0 on that db); run against the full `C:\Projects\DB\ORM3\drag-lint.sqlite` which has
> them. **L1 interface bridge** -- BACKWARD-CHAIN, fully index-queryable: launch body -> `type_ancestors` heritage ->
> `refs WHERE name_text='EditForm'` each carrying `enclosing_symbol_id` = the calling FORM method (VERIFIED at
> `ControlPlan2.pas:1451` `EditForm|btnSelFinalPlanClick`) -> form -> MAIN + `CaptionForHandler` = 'Plan'. Match by method
> NAME across the interface family (correct: all 19 plan editors share the one Plan button = a polymorphic dispatch hub; the
> slider picks which plan). **L2 hook edges** -- `uPLANLIST.PlanEditFormHook := ShowPlanEditor` (uPlanEditForms.pas:123, in
> `initialization`) is a proc-variable indirection; the parser emits NO ref for the hook field or the RHS routine there
> (only a `uPLANLIST` unit ref), so `find-callers ShowPlanEditor`=0 and it MUST be a text-scan of the source (bounded to
> already-known form-launching routines).
> **All work in `src/forms/DRagLint.FormsMap.pas`:** `BuildEdges`:585, `FindNearestFormCaller`:509, `ProcessSite`:620,
> `CaptionForHandler`:421, `FORMS_CSV_ALGORITHM`:70. No index-schema change in v4.
> **NEW spec section D5 (future indexer milestone, schema bump):** receiver-type on call refs + proc-assign refs +
> interface-impl method edges -> removes L2's text-scan + makes polymorphic dispatch precise (benefits find-callers/impact/
> graph too). Separate brainstorm->spec->plan.
> **BUILD GOTCHAS (in the plan):** run tests against the STAGED exe `third_party\dll-win64\drag-lint.exe` (the raw
> `src\cli\Win64\Release\drag-lint.exe` dies `0xC0000135` DLL-not-found -- no tree-sitter DLLs beside it); after each
> rebuild `copy src\cli\Win64\Release\drag-lint.exe third_party\dll-win64\`. Run `run_formsmap.ps1` from a NEUTRAL CWD
> (`C:\TEMP`) or assert the CSV directly -- its `$ErrorActionPreference=Stop` + the exe's `(loaded defaults)` stderr line
> = a spurious `NativeCommandError` from a config-bearing CWD. Fixture `.pas`/`.expected` must be CRLF (the Write tool emits
> LF -> byte-rewrite before committing). forms-csv Migrates -> use a SCRATCH COPY of any real db.
> **>>> AFTER v4 implementation: PUBLISH as a later release** (user directive) -- version bump + CHANGELOG + pack + tag +
> gh-release (mirror v0.86 mechanics), BUNDLING the two fixes already shipped THIS session onto main:
>   - `fc7e630` forms-csv header-move (provenance line -> padded footer, column header = row 1; 14 formsmap assertions pass).
>   - `bb6eb82` live-lint `unit-name-matches-file` FP fix (skips `drag-lint-live-*` buffer snapshots -- was firing on every
>     unsaved edit incl. SOFTWID.PAS during the v0.86 IDE smoke; RED->GREEN fixture `tests/lint/drag-lint-live-99999.pas`).
>   Both are in committed SOURCE + the staged win64 exe already, but NOT in a release yet.
> **STILL OPEN from v0.86 (unchanged):** (1) the win64 exe already carries the 2 fixes but the plugin BPL was NOT redeployed
> (no plugin source changed -- so the running IDE plugin is unaffected; the exe changes take effect on next reindex/lint);
> (2) fast-follow read-only for the ~11 analytical read verbs (sec.5).
>
> --- (prior) ---
> ## RESUME 2026-07-05 (LATEST-6) -- **v0.86.0-alpha PUBLISHED (full GitHub release, `--latest`, win32+win64). Milestone COMPLETE.**
> `main` = `65f317e` (clean, pushed, synced with origin), tag `v0.86.0-alpha` on `65f317e`, GitHub release live + `Latest`
> (isPrerelease=false): https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.86.0-alpha . VERSION `CLI.pas:6` =
> `0.86.0-alpha`. **No index-schema change (still v13).** Executed via superpowers:subagent-driven-development, 5 tasks,
> final whole-branch opus review (READY-WITH-FIXES -> 1 blocking comment fix applied `65f317e` + 1 fast-follow filed).
> **What shipped (D1-D4):** (D1/T1) shared `DragLint.Plugin.ExeResolver.DragLintExe` -- Win64-default resolution routed
> through ALL 11 plugin exe-spawn sites (plan named 5; sweep found 11, user approved delegating all; the 32-bit BPL is the
> only 32-bit artifact). (D2/T2) Structure tab: `ParseOutlineJson` slices first-`[`..last-`]` past CLI preamble noise +
> separate stderr pipe + line-sorted Diagnostics. (D3/T3) new `DRagLint.Core.Encoding.EnsureUtf8Bytes` (UTF-8 BOM strip /
> UTF-16 transcode / strict-scan passthrough / CP1252 fallback) at 4 ingest sites (Indexer/ParseCache/Linter/LSP) -- ANSI/
> UTF-16 sources (SOFTWID.PAS class, 0xAE/0xA9) now INDEX not SKIP + literals text-searchable; sha stays over RAW bytes
> (no re-index churn). (D4/T4) `TSQLiteSymbolStore.Create(;AReadOnly)` + `IsSchemaCurrent` -- 6 read verbs (outline/query*/
> find-unit/surface/context/dump-refs) open via `PRAGMA query_only=ON` (NOT OpenMode=ReadOnly, which fails on WAL) -> no
> DDL-on-read, kills the win32 FTS5-trigger-drop; stale DBs get actionable migrate message. Full battery green (lint 153/
> store 16/catalog 29/flowengine 43/extractmethod 81+e2e 17/migrate-v12 8/formsmap 18/encoding-ingest 12/readonly-verbs 21).
> Self-index reindexed incrementally 2026-07-05 (new symbols queryable). SDD ledger: `.superpowers/sdd/progress.md`.
> **>>> OPEN ITEM 1 (USER, ~5 min): manual IDE smoke.** Close RAD Studio, deploy the BPL (deploy-staged.bat -- note the
> committed BPL `606d659` already carries T1+T2 fixes; refresh C:\TEMP1\bpl_staging if it's stale before deploying), open
> BASICSF.pas: Structure tab shows SORTED Diagnostics + ~240 Code Elements (not "0"); run a reindex FROM the IDE -> SOFTWID
> .PAS indexes (not SKIP); text-search still works after a Structure refresh (FTS5 triggers intact). Report back.
> **>>> OPEN ITEM 2 (fast-follow, tracked in sec.5): read-only opens for the ~11 analytical read verbs** (hover/impact/
> usages/slice/cycles/resolve-uses/uses-report/typeat/bench-context/uses-audit/generate-docs) -- still Create+Migrate, would
> drop FTS5 triggers ONLY on a manual win32 invocation (IDE vector closed by T1; spec D4 scoped to the 6 named verbs).
> Convert to `OpenReadOnlyStore` (v0.86.1/backlog) to complete the DDL-on-read guarantee.
> **>>> NEXT MILESTONE: Change Signature** (REFACTOR-LIST.md "recommended next") -- new brainstorm -> spec -> plan; reuses
> rename's cross-unit apply + Extract Method's liveness pass.
>
> --- (prior) ---
> ## RESUME 2026-07-05 (LATEST-4) -- **v0.85 fully DONE (IDE smoke verified). NEXT ACTION = execute the v0.86 plan.**
> `main`=`b5c53a1` (clean, pushed). VERSION=`0.85.0-alpha`, tag `v0.85.0-alpha`=`2c303e4` released.
> **>>> Execute `docs/superpowers/plans/2026-07-05-win64-default-and-ide-fixes-plan.md` via
> superpowers:subagent-driven-development** -- 5 tasks: T1 shared `DragLintExe` resolver (Win64 default for EVERY plugin
> spawn; the 32-bit BPL is the only 32-bit artifact; win32 exe stays staged "just in case") -> T2 Structure tab: slice JSON
> out of the CLI output + separate stderr pipe + sort Diagnostics by line -> T3 `EnsureUtf8Bytes` ingest transcode (valid-
> CP1252/UTF-16 sources index instead of SKIP; sha stays over raw bytes) -> T4 read-only store opens for query verbs (no
> DDL-on-read; actionable stale-schema message) -> T5 ship **v0.86.0-alpha** (full battery + zips; final review BEFORE
> tag/push/gh; then USER smoke: BASICSF structure shows sorted diags + ~240 elements, SOFTWID indexes).
> Spec (all root-cause evidence): `docs/superpowers/specs/2026-07-05-win64-default-and-ide-fixes-design.md`.
> **Root causes proven 2026-07-05:** Structure "Code Elements 0" = 4 plugin resolvers pick `<bpl-dir>\drag-lint.exe` (STALE
> 0.84 WIN32, FTS5-less) whose preamble/DROP-TRIGGER noise lands in the MERGED stdout+stderr pipe before the JSON -> parse
> fails -> cached 0. SOFTWID.PAS skip = pipeline assumes UTF-8; the file is valid CP1252 (0xAE/0xA9 in a resourcestring).
> Win32 exe DB opens DROP the string_literals FTS triggers (Migrate DDL on read-looking verbs) -- degrades text search
> until the next win64 index run.
> **Gotchas for the cold session:** plugin BPL builds fail F2039 while RAD Studio is open (user must close; rebuild wrote
> directly into third_party\dll-win32 last time -- deploy-staged.bat copies from C:\TEMP1\bpl_staging which can be STALE,
> refresh it after every BPL rebuild); the extract-method verb PREVIEWS by default (--apply writes) unlike legacy rename;
> never CloseModule the active module from a key binding (use deferred IOTAModule.Refresh -- see Keyboard.pas comment).
> **After v0.86: Change Signature** is the recommended next refactoring (REFACTOR-LIST.md) -- new brainstorm->spec->plan;
> reuses rename's cross-unit apply + the Extract Method liveness pass.
>
> --- (prior) ---
> ## RESUME 2026-07-03 (LATEST-3) -- **v0.85.0-alpha PUBLISHED (Extract Method, refactoring-APPLY #1). Manual IDE smoke = the ONE open item.**
> `main`=`2c303e4` = tag `v0.85.0-alpha` (GitHub full release, `--latest`, win32+win64 zips:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.85.0-alpha). VERSION `CLI.pas:6`=`0.85.0-alpha`. No schema
> change (still v13). Suites at ship: lint 153/153 + store 16/16 + catalog 29/29 + flowengine 43/43 (+10 boundary-liveness)
> + extract-method unit 81/81 + e2e 17/17 (2x dcc64 compile-verified) + formsmap + migrate-v12.
> **SHIPPED: Extract Method v1** -- CLI `extract-method --file --from-line --to-line --name [--dry-run|--apply|--json|--no-backup]`
> (preview default, REFUSE-not-guess: 18+ reasons) + IDE **Ctrl+Alt+M** (preview dialog -> apply -> reload) + reusable
> `DRagLint.Analysis.Liveness.pas` (LiveAfterItem/LiveBeforeItem). Executed via SDD (7 tasks; notable catches: T3 tests
> exposed 2 real classification defects -> recursive must-def + exit-edge-only live-out + conditionally-assigned-escapes
> refuse; final review caught the IDE Apply spawn omitting `--apply` -- the extract-method verb previews by default, unlike
> legacy rename -- fixed + BPL rebuilt BEFORE the tag). Interim releases folded into the notes: v0.83.1 (migration hotfix),
> v0.84.0 (forms-csv Navigation v3).
> **>>> NEXT ACTION 1 (user, 5 min): manual IDE smoke** -- close RAD Studio, deploy the BPL (deploy-staged.bat), open a
> sample unit, select whole statements, Ctrl+Alt+M: check preview shows the new method, Apply rewrites the file (.bak
> appears), buffer reloads, result compiles. Items to watch (untestable outside the IDE): keybinding registration,
> EndingColumn<=1 whole-line-selection heuristic, CloseModule/OpenModule reload. Then remove the "manual IDE smoke pending"
> notes from CHANGELOG.md + REFACTOR-LIST.md.
> **>>> NEXT ACTION 2: Change Signature** (recommended next refactoring per REFACTOR-LIST.md) -- brainstorm -> spec -> plan,
> reusing rename's cross-unit machinery + the new liveness pass. Also queued: consolidate the verbose Extract Method Notes
> cell in REFACTOR-LIST.md; reconcile refuse-output stream (extract-method uses stderr, older verbs stdout).
>
> --- (prior) ---
> ## RESUME 2026-07-03 (LATEST-2) -- **v0.83.0-alpha SHIPPED; REFACTORING-APPLY frontier KICKED OFF -- Extract Method spec+plan WRITTEN, ready to implement.**
> `main`=`703c84b` (clean, pushed). Lint-DETECTION coverage CLOSED (see `docs/lint/MISSING-FEATURES.md`). The growth frontier is
> now refactoring-APPLY, tracked in **`docs/lint/REFACTOR-LIST.md`** (all ~30 refactorings + difficulty + progress; shipped =
> rename/find-unit/safe-delete; in-progress = extract-method).
> **>>> NEXT ACTION: execute the Extract Method implementation plan** `docs/superpowers/plans/2026-07-03-extract-method-plan.md`
> via **superpowers:subagent-driven-development** -- 7 TDD tasks: T1 boundary-liveness helper -> T2 selection+refuse guards ->
> T3 variable classification -> T4 synthesis+TextEdit emission -> T5 CLI verb + compile-verified e2e -> T6 IDE Ctrl+Alt+M ->
> T7 ship v0.84. Spec: `docs/superpowers/specs/2026-07-03-extract-method-design.md`. **Cut line if oversized = defer IDE (T6)
> to a fast-follow** (ship T1-5+7 first). Flip extract-method `[~]`->`[x]` in REFACTOR-LIST.md at ship.
> **Key design facts (so the cold session does not re-derive):** single-file (NO `--db`); v1 = value in-params + a SINGLE
> `Result` output (2+ outputs REFUSE); param types come from `TRoutineVar.TypeText` (NO type inference); "full M2 liveness" is
> LARGELY ALREADY BUILT -- `TDataFlowSolver` (fwd/bwd worklist) + `TLiveness` exist in `src/analysis`, Extract Method only adds
> boundary querying (replay per-item transfer, like `split-variable` does). Reuse `TTextEditApplier`,
> `TRenameRefactoring.BuildLocal`/`ConflictReason`. Prime directive = REFUSE rather than emit wrong code. Build = THIS Windows box
> only (delphi-build skill: rsvars+msbuild). Recommended refactor order after Extract Method = Change Signature (REFACTOR-LIST.md).
>
> --- (prior, v0.83 release) ---
> ## RESUME 2026-07-03 -- **v0.83.0-alpha PUBLISHED (FULL release, gh --latest, win32+win64). Autonomous fork reviewed + merged.**
> `main` at tag `v0.83.0-alpha`, origin synced. VERSION `CLI.pas:6`=`0.83.0-alpha`. **No schema change (still v13.)**
> Harness **lint 153/153 + store 16/16 + catalog 29/29 + flowengine 33/33**; OFF-suppression runtime-verified (both new rules
> bare=0, opt-in=1). Release zips are self-contained (Release exe + 3 tree-sitter DLLs + docs + `rules/`), 123 files each.
> **NEXT MAIN FOCUS = REFACTORING-APPLY frontier** (Extract Method / Change Signature via IDE+OTAPI -- a new, bigger project;
> lint-DETECTION coverage is effectively complete). No in-flight v0.83 work remains.
>
> The autonomous fork `feat/v083-deepen-rules` (forked from `main` @ v0.82.0-alpha) was ff-merged to main after a full code
> review (both rules clean: null-safe walks, correct OFF-by-default wiring, well-discriminating tests). Then bumped VERSION +
> CHANGELOG, rebuilt (Win64 Debug for tests + Win32/Win64 Release for zips), all harnesses green, published.
>
> **SHIPPED (2 new rules, both OFF-by-default, both clean src/ FP):**
> - **`split-variable`** (`refactoring`/`info`, OFF) -- a local reused for two UNRELATED purposes (>=2 disjoint def-use
>   lifetimes, both used). New M2 flow pass in `FlowChecks.pas` `CheckRoutine`, LINEAR-routine-only (bails on any branch/merge)
>   to stay sound + low-FP. Distinct from `overwrite-before-read` (RED run PROVED it: dead-store vs two-used-lifetimes).
>   src/ FP = **10 findings / 3 files**, all genuine reused-scratch-local idioms (col per TListColumn, GY layout cursor).
>   Commit `feat(lint): split-variable rule ...`.
> - **`separate-query-from-modifier`** (`refactoring`/`info`, OFF, CQS) -- a value-returning FUNCTION that also writes a field
>   (`Self.X :=` or `FXxx :=` not-a-local). New standalone AST check `TAstChecker.CheckSeparateQueryFromModifier`. src/ FP =
>   **3 findings / 3 files, ALL genuine CQS violations, ZERO false positives** (2 memoizing getters + 1 do-and-return-status).
>   Commit `feat(lint): separate-query-from-modifier rule ...`.
>
> **DEFERRED (Item 3, an ON rule -- NO code touched):**
> - **`object-leak` OwnsOracle enhancement** -- DEFERRED as an **empirical no-op**. The plan's premise is FALSE: verified with
>   the built exe (bare-lint AND check-ast) that object-leak ALREADY catches TFileStream/TMemoryStream/TBitmap
>   created-and-never-freed, and correctly excludes freed + all transfer cases. `object-leak`'s "created" flag is purely
>   syntactic (`ExprIsConstructor` = any `.Create`), never gated on a type-ownership oracle; there is no gap to strengthen.
>   Touching the ON rule = zero benefit + pure FP risk, so per the strict guardrail: defer, touch nothing. Evidence +
>   probe table in `docs/lint/DEFER-v083-object-leak-ownsoracle.md`. Commit `docs: defer object-leak OwnsOracle ...`.
>
> **Harness end-state (all green, NO regression):** lint **153** (151 -> +2 fixtures), store **16**, catalog **29**,
> flowengine **33**, exitcode **11 unit + 4 CLI**. OFF-suppression runtime-verified for both new rules (bare=0; --rule /
> --config enabled=1). Build: Win64 ExitCode 0, `OK: staged`, no `[dcc] Error`/`Fatal`.
>
> **DECISIONS (RESOLVED at release):** (1) both OFF rules accepted + shipped; (2) Item 3 deferral accepted (no-op that could
> only add FPs to an ON rule); (3) VERSION bumped to `0.83.0-alpha` + released FULL (`gh --latest`). Files that shipped:
> `FlowChecks.pas`, `AstChecks.pas`, `RuleCatalog.pas`, `CLI.pas`, 6 new test fixtures under `tests/lint/`, 1 deferral doc.

> ## RESUME 2026-07-02 (LATEST) -- **v0.82.0-alpha PUBLISHED (FULL release, gh --latest, win32+win64). All 7 SDD tasks done + final whole-branch review (opus) clean.** `main`=`29967f4`, origin synced, tag `v0.82.0-alpha` (isPrerelease=false, repo `latest`; https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.82.0-alpha). VERSION `CLI.pas:6`=`0.82.0-alpha`, **schema v13**. Harness **file 151/151 + store 16/16 + catalog 29/29 + flowengine 33/33** (+ ergonomics exit-code 12 unit+4 CLI, Task 1 enclosing-attribution verify.ps1). SDD ledger `.superpowers/sdd/progress.md`. Full CHANGELOG entry in `CHANGELOG.md`. NEXT = next milestone (won't-fix tail in MISSING-FEATURES); no in-flight v0.82 work remains.
>
> **What shipped (v0.82.0-alpha, 7 SDD tasks):** (T1) `refs.enclosing_symbol_id` schema v13 -- per-file innermost enclosing-routine attribution in `Indexer.IndexFile` (`ResolveEnclosingSymbolId`, largest-ImplStartLine tie-break, `IdxToId` map), `TReference.EnclosingSymbolId`, 3 consumer reads (+ fixed `GetReferencesFromFile` end_line/end_col gap), new `dump-refs` diagnostic. Additive `ALTER` migration, NULL-safe (reads 0 on old DBs). PARSER LIMIT: tree-sitter doesn't emit nested procs -> nested-proc refs dropped (top-level method bodies are exact; doesn't affect CK/feature-envy). (T2) 2 v0.81 Minors: `ArgsHaveNoEncoding` skips literalString; exit code from post-suppression Survivors (dropped `ADefaultExit` param). (T3) CBO/RFC/fan-in/fan-out retrofit -> `EnclosedByOwnMethod(EnclosingSymbolId)` replaces `InAnyMethodBody`; **guardrail byte-identical (120 findings src/)**; LCOM4 unchanged. (T4) `feature-envy` (#14 refactoring/info/OFF; method-name->declaring-class map, ambiguous skipped; src/ FP=36 RTL collisions). (T5) `instability` (#11 metrics/info/OFF; I=Ce/(Ca+Ce) integer-percent; config keys `instability`/`instability-floor`). (T6) `interface-object-mixing` (#4 first cut, resource-lifetime/info/OFF; same-routine object-aliased-into-interface AND manually-freed; **SHIPPED, src/ FP=0**). All 3 new rules OFF (catalog False + DefDisabled), runtime OFF-suppression controller-confirmed. Final review Important (instability `noiseFloor`->`instability-floor` param-name) FIXED (6a09dc2).
>
> **Reindex rollout (schema v13):** self-index (Delphi-RAG-lint.sqlite) reindexed + validated (enclosing_symbol_id populated). Full `index --all` (ORM3/SQL/AllProjects/Library/etc.) kicked off after release -- confirm it completed (log: scratchpad `v082-reindex-all.log`).
>
> **>>> v0.82 KEY DESIGN DECISIONS (user-approved, so the cold session does not re-litigate):** scope=BROAD (foundation +
> all consumers + independents). Attribution hook = **per-file in-memory in `IndexFile`** (innermost impl-range containment
> vs the file's in-memory symbols, map array idx->DB id via the in-scope `IdxToId`; NO parser-walk plumbing, NO whole-DB
> pass). Backfill = **NONE -- explicit full reindex of all DBs** once after the new exe ships (fast; per-file resolution
> keeps it current thereafter). Release carries `-alpha` again (schema still changing) but is a FULL `gh --latest` release.
> feature-envy ships OFF (enclosing attribution exact, but target-class own/foreign split stays name-based/heuristic).
> CBO/RFC retrofit has a mandatory NO-REGRESSION guardrail (existing CK fixtures + FP diff); LCOM4 stays (AST re-walk, not
> ref-based). #4 is ATTEMPT-OR-DEFER (ship nothing if too FP-prone). Task order + grounding file:line anchors in the plan/spec.
>
> **v0.81.0 SHIPPED + RELEASED.** `main`=`32f189b` (+ this docs commit), origin synced, tag `v0.81.0`, GitHub FULL release
> (isPrerelease=false, repo `latest`) win32+win64 (https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.81.0).
> VERSION `CLI.pas:6`=`0.81.0`. Harness **file 150/150 + store 14/14 + catalog 29/29 + flowengine 33/33**. Plan
> `docs/superpowers/plans/2026-07-02-v081-plan.md`; scout `.superpowers/sdd/v081-scout-brief.md`. Executed via SDD
> (subagent-per-task + 2-stage review + final whole-branch opus review = Ready-to-merge:Yes, verified OFF-suppression at runtime).
>
> **What shipped (2 rules -> 3 rule ids, all OFF-by-default):**
> - `default-encoding-io` (#9, `platform`, `warning`) -- pure-AST twin of `insecure-temp-file` in DeadCodeChecks.pas:
>   `IsDefaultEncodingApi` (callee match SaveToFile/LoadFromFile/TFile.*/TStreamReader/Writer) + `ArgsHaveNoEncoding`
>   (scans `exprArgs` NamedChildren for a `TEncoding` arg). OFF (src/ FP=65, mostly intentional ReadAllText on config files).
> - CK `fan-out` (Ce) + `fan-in` (Ca) in ClassMetrics.pas (`metrics`, `info`): fan-out reuses `ComputeCBO` (untouched);
>   fan-in = NEW `ComputeAllFanIn` whole-project reverse aggregation (inverts CBO's efferent set, deduped per source, same
>   self+ancestor exclusions; FanIn dict freed in Run's finally). Both OFF; DefDisabled in DoLintAll (ClassMetrics is
>   lint-all-only -- single call site, no lint-project/LSP leak). Config thresholds via `"thresholds":{...}`.
>
> **KEY DECISIONS / GOTCHAS (v0.81):**
> - User chose "fan-in + explicit fan-out alias" (fan-out numerically == the ON `high-coupling`/CBO -> ship fan-out OFF so it
>   does not double-fire in default output; opt-in for the fan-in/fan-out framing). CK `instability` deferred (range-flag shape, not a count).
> - `#4 interface/object mixing` DEFERRED to v0.82: the cheap slice (`.Free`/`.DisposeOf` on a pure interface var) generally
>   won't compile -> low value; the useful dual-handle form needs instance-aliasing/data-flow the codebase lacks. Bundle with feature-envy.
> - OFF-by-default reminder (v0.80 lesson, held): catalog `False` + the id in `DefDisabled` in EVERY emitting CLI path. The
>   final review verified no leak at runtime (0 findings unconfigured, N with --rule).
> - `.gitattributes *.pas eol=crlf` + `core.autocrlf=true` store all .pas as LF and check out CRLF -> a reviewer seeing an
>   "LF-only" .pas working-tree file is a transient artifact, NOT a defect; git serves CRLF on checkout.
> - v0.81 review MINORS (-> v0.82 backlog, non-blocking): (1) default-encoding-io `ArgsHaveNoEncoding` scans string-literal
>   args too, so a filename containing "TEncoding" falsely suppresses (only matters if promoted ON; fix = skip literalString
>   named children). (2) carried: exit code from RAW findings not survivors (bare cmd can print "0 finding(s)" yet exit 1).
>
> **v0.82 STATUS: SHIPPED (2026-07-02) -- v0.82.0-alpha released.** Executed via SDD on branch
> `feat/v082-enclosing-attribution` (merged --ff-only to main `29967f4`, tag `v0.82.0-alpha`). Spec
> `docs/superpowers/specs/2026-07-02-v082-enclosing-symbol-attribution-design.md`, plan
> `docs/superpowers/plans/2026-07-02-v082-plan.md`, ledger `.superpowers/sdd/progress.md`. See the v0.82 SHIPPED
> block at the TOP of this file for the full summary. The KEY DESIGN DECISIONS block below is retained as the design record.
>
> --- (prior milestone) ---
>
> **v0.80.0 SHIPPED + RELEASED.** `main`=`f3d3882`, origin synced, tag `v0.80.0`, GitHub FULL release (isPrerelease=false, repo `latest`) win32+win64 (https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.80.0). VERSION `CLI.pas:6`=`0.80.0`. Harness **file 149/149 + store 13/13 + catalog 29/29 + flowengine 33/33**. Plan `docs/superpowers/plans/2026-07-02-v080-plan.md`.
>
> **What shipped (3 rules + 4 cleanups + 1 fix), each subagent-implemented + 2-stage-reviewed + a final whole-branch opus review (Ready-to-merge: Yes):**
> - **Store-backed refactoring (category `refactoring`, all OFF-by-default):** `mutable-global-variable` (Global Data, `info`; new `CheckMutableGlobalVars` in AstChecks.pas generalizing `CheckGlobalFormVars` -- unit-scope `declVars` only, no `.dfm` gate / no type filter, `Exit` on defProc/defFunc; src/ FP=68 across 27 files). `repeated-type-switch` (Replace Conditional w/ Polymorphism, `info`; `CollectRepeatedTypeSwitch` in ProjectRules.pas -- normalized `case`-selector text grouped across >=3 distinct enclosing methods, deterministic, one finding/occurrence; src/ FP=4 name-based). `middle-man` (Remove Middle Man, `info`; `ComputeMiddleMan` in ClassMetrics.pas reusing `ComputeLCOM4`'s body-walk -- class w/ >=3 body methods where >half are pure one-line delegations to the SAME declared field, test `BestCount*2 > Total`; src/ FP=0).
> - **Fix:** `DoLintProject` routed through `FinalizeAndOutput` so OFF project rules no longer leak in bare `lint-project` (they did before -- repeated-type-switch was the first OFF project rule to expose it). ON project rules unaffected; `lint-project --json` now pretty-printed (matches lint-all).
> - **v0.79 cleanups:** double-free `warning`="is freed twice" / `info`="may be freed twice" split; magic-literal exempts compound-const initializers (`const K=60*1000`) via a bounded null-safe parent walk; not-assigned-interface `X as T` + multi-hop fixtures; flowengine test rename + a genuine reassign-clears test.
>
> **KEY GOTCHAS / DECISIONS (v0.80):**
> - OFF-by-default needs BOTH catalog `False` AND the rule id in the `DefDisabled` list in EVERY CLI path that emits it (DoLint/DoLintAll/DoLintProject) -> `ShouldKeep` suppresses; catalog `False` ALONE does NOT suppress CLI output. (Learned Task 3, re-hit as the Task 4 lint-project leak.)
> - Store refs are name-based with NO enclosing-method column; `FindContainingSymbol` keys the DECLARATION span not the impl-body span -> reliable per-method cross-class attribution (feature-envy) is not feasible without expression-level type inference -> DEFERRED to v0.81.
> - Project rules live in ProjectRules.pas (`CollectXxx` called from `TProjectLintRules.Run` under `WantRule`) or ClassMetrics.pas (per-class, reuse `ComputeLCOM4`'s CollectDefProcNodes/ProcByLine/FindProcContainingLine body-walk); both run project-wide via lint-all/lint-project, tested via `tests/lint-store/<case>/` (mode `lint-all`).
> - Full release (user directive): VERSION `0.80.0` (drop `-alpha`), tag `v0.80.0`, `gh release --latest` (no `--prerelease`). Graduates off the alpha line (v0.71-v0.79 were all `-alpha` prereleases).
> - v0.81 MINOR follow-ups (from reviews, non-blocking): exit code derived from RAW findings not survivors -- a bare command whose only matches are suppressed OFF rules can print "0 finding(s)" yet exit 1 (`--fail-on` unset); shared by DoLintAll+DoLintProject (fix by deriving default exit from Survivors in both). Optional clarifying comment in AstChecks.pas ~3220 (CheckMutableGlobalVars vs CheckGlobalFormVars delta).
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-02 -- **v0.79.0-alpha PUBLISHED -- M2-flow (#4 not-assigned-interface + #5 double-free) + Fowler refactoring-catalog batch (5 rules); NEXT = execute `docs/superpowers/plans/2026-07-02-v080-plan.md` (v0.80: deferred cleanups + store-backed refactoring signals) via subagent-driven-development, ship v0.80, then report remaining MISSING-FEATURES**
>
> **>>> NEXT ACTION (resume target): run superpowers:subagent-driven-development on `docs/superpowers/plans/2026-07-02-v080-plan.md`.** Phase 1 = 4 quick v0.79-review cleanups (flowengine test rename; double-free warning-vs-info message; not-assigned-interface X-as-T fixture; magic-literal compound-const exempt). Phase 2 = store-backed refactoring signals, SCOUT the store's member-access attribution FIRST, then mutable-global-variable -> middle-man -> repeated-type-switch -> feature-envy (feature-envy may DEFER if name-based signal too weak). Then release v0.80.0-alpha + report. Branch from main @ `21947a7`.
>
> **v0.79.0-alpha SHIPPED + RELEASED (autonomous session).** `main`=`6bd271a`, origin synced, tag `v0.79.0-alpha`,
> GitHub PRERELEASE win32+win64. VERSION `CLI.pas:6`=`0.79.0-alpha`. Harness **file 148/148 + store 11/11 + catalog 29/29
> + flowengine 31/31**. Spec `docs/superpowers/specs/2026-07-02-v079-flow-refactoring-rules-design.md`.
>
> **What shipped (7 rules + cleanup), each subagent-implemented + reviewed (C1/C2 got full opus reviews):**
> - **M2 data-flow (category `data-flow`, ON):** **`not-assigned-interface`** (#4 nullability, `warning`) -- interface-typed
>   local DEREFERENCED (`X.member`/`X as T`) before assignment; reuses the definite-assignment Must/May lattice for the
>   interface subset `used-before-assignment` skips (`IsInterfaceType`: store `tcInterface` or `'I'`+uppercase fallback),
>   deref-only, warning(Must)/info(May). **`double-free`** (#5, `warning`) -- raw `X.Free` twice with no reassign/nil between;
>   NEW forward `TFreedState{Must,May}` lattice in `Flow.Lattices.pas` (Join Must:=and/May:=or), `DetectFreedVarKind`
>   (fkRawFree->dangling / fkNiling[FreeAndNil/DisposeOf]->safe), per-item replay emit-BEFORE-advance, reassignment clears.
> - **Fowler refactoring-catalog (NEW category `refactoring`; DeadCodeChecks.Visit branches):** `message-chain` (Hide
>   Delegate, `hint`, **ON**, threshold 4; left-nested exprDot spine; src/ FP=0); `magic-literal` (Replace Magic Literal,
>   `hint`, **OFF**; literalNumber not 0/1/-1/2 + not const/enum/case/range/initializer; src/ FP=696); `boolean-flag-parameter`
>   (Remove Flag Argument, `hint`, **OFF**; Boolean param in if/case/while condition, skips override+Sender; FP=42);
>   `public-writable-field` (Encapsulate Variable, `info`, **OFF**; `public` class field, excl published/records; FP=44);
>   `loop-control-flag` (Replace Control Flag with Break, `hint`, **OFF**; flag var True/False in loop body + in condition; FP=1).
> - **Cleanup:** dropped unused MethNames in ComputeLCOM4; moved `metrics` catalog block after project-wide; DIT cycle-guard fixture.
>
> **KEY GOTCHAS / DECISIONS (v0.79):**
> - New category `refactoring` -> MUST be added to `tests/rules-catalog/RuleCatalogTests.dpr` `CanonicalBuckets` (else catalog self-test fails).
> - `drag-lint lint <folder>` runs ONLY `.scm` rules (skips built-in AST checks) -> FP-sanity must lint files INDIVIDUALLY (or use lint-all --db).
> - Numeric-literal node = `literalNumber`; qualified type/unit names = `typerefDot`/`moduleName` (distinct from value `exprDot`).
> - Add-a-flow-rule = emit inside `TFlowChecker.Check`'s CheckRoutine (runs unconditionally; filtered client-side) + `--rule`
>   allow-list/help + catalog `B(...,'data-flow',...)`; file-harness-testable (nil-store). Unit-test a lattice via `tests/flowengine/FlowEngineTests.dpr`.
> - `not-assigned-interface` KNOWN LIMITATION (documented in CHANGELOG): the short-circuit `and`/`or` seeding suppresses derefs
>   after ANY call passing the var (not just out/var params) -> a SAFE-DIRECTION false-negative; tightening needs callee-arity/store.
>
> **DEFERRED to v0.80 (from reviews -- all non-blocking):** (1) C2 flowengine test `TestFreedStateReassignClears` rename
> (asserts end-dangling; behavior correct); (2) `double-free` warning+info share one message string ("may be freed twice"
> reads oddly for the definite/warning case -> use "is freed twice" for warning); (3) `not-assigned-interface` add an `X as T`
> / multi-hop-chain fixture; (4) `magic-literal` exempt uses DIRECT parent only (compound const initializers `const K=60*1000`
> not exempt -- OK since OFF). **Store-backed refactoring signals (MISSING-FEATURES #14, next real batch):** `middle-man`,
> `feature-envy`, `repeated-type-switch`, generalize `global-form-variable`->`mutable-global-variable`. Also open: #9
> default-encoding-io, #4 interface/object mixing, CK fan-in/fan-out. The realistic ceiling is ~85%.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-02 -- **v0.78.0-alpha PUBLISHED -- #6/#11 CK class-metric suite (NOC/DIT/CBO/RFC/LCOM4); NEXT = v0.79 (M2-flow: nullability #4 + double-free #5) or the Fowler refactoring-catalog batch (#14)**
>
> **v0.78.0-alpha SHIPPED + RELEASED.** `main`=`e861a82`, origin synced, tag `v0.78.0-alpha`, GitHub PRERELEASE
> win32+win64. VERSION `CLI.pas:6`=`0.78.0-alpha`. Harness **file 141/141 + store 10/10 + catalog 29/29**.
>
> **What shipped:** the 5 CK class metrics as one store-backed, project-wide bundle (CLI `lint-all`/`lint-project`
> only -- NOT the per-file LSP), ON by default, severity `info`, NEW category `metrics`, per-rule `threshold`.
> New unit `src/lint/DRagLint.Lint.ClassMetrics.pas` (`TClassMetrics.Run(AStore, ACfg, ARuleId)`), invoked in
> `DoLintAll` right after `TProjectLintRules.Run`. Rules: **`too-many-children`** (NOC, direct subclasses, default 10),
> **`deep-inheritance`** (DIT, parent-chain depth, default 6), **`high-response`** (RFC = own methods + distinct
> call-names in bodies, default 50), **`high-coupling`** (CBO = distinct other-class `type_use` in decl/bodies minus
> self+ancestors, default 20), **`low-cohesion`** (LCOM4 = connected components of the method graph [shared-field OR
> call edges], per-method AST re-walk, default **26**). Six `tests/lint-store/` fixtures.
>
> **KEY DECISIONS / GOTCHAS (v0.78):**
> - **LCOM shipped as LCOM4** (connected components) and defaults **HIGH (26)** on purpose: OTA/NTA interface-implementer
>   classes and stateless `class function` facades structurally maximize LCOM4 without being god-classes, so a low
>   default is pure noise on idiomatic Delphi (all 14 findings @3 on src/ were such artifacts; max observed 25). The
>   other 4 defaults calibrated over src/ = 0 or all-genuine (RFC=11, all legitimately large classes).
> - **LCOM4 per-method AST re-walk** matches each body-method to its `defProc` node by `StartPoint.row+1 == ImplStartLine`
>   (exact), with a **range-containment fallback** (`FindProcContainingLine`) if that skews. **Excludes NESTED routines**
>   from a method's identifier set (root-guard, `CloneChecks.CollectLeaves` idiom, `TTSNode.Equal`) -- else a nested
>   proc's idents fold into the parent and falsely lower LCOM4. Both were review-caught + fixed.
> - **The store's refs are name-based** (`symbol_id` NULL); resolve `NameText` via `FindSymbolsByExactName`/
>   `ResolveTypeCategory`. `read`/`write` refs are partial -> LCOM uses AST, not refs. **DIT undercounts without an
>   RTL/library `--db`** (external parents count as 1 hop). CBO is efferent (type_use) only.
> - New category `metrics` needed adding to `tests/rules-catalog/RuleCatalogTests.dpr` `CanonicalBuckets` allowlist.
> - Spec `docs/superpowers/specs/2026-07-02-ck-class-metrics-design.md`; plan `docs/superpowers/plans/2026-07-02-ck-class-metrics.md`.
>
> **DEFERRED v0.79 cleanup (from the final whole-branch review -- Minors, none blocking):** delete the unused
> `MethNames` dict in `ComputeLCOM4`; optionally refactor the ~360-line `TClassMetrics.Run` (5 nested compute fns) into
> private methods; move the `metrics` catalog `B()` block out of the middle of the `project-wide` comment section; add
> fixtures for the DIT external-parent/cycle paths + the LCOM4 range-fallback; consider memoizing `GetTransitiveAncestors`
> per class and periodic `TAstParseCache.Clear` on huge indexes.
>
> **NEXT (choose): (a) v0.79 M2-flow rules** -- `#4 nullability`/not-assigned-interface (interface-typed local used
> before assignment; extend `FlowChecks` def-use lattice to interface refs) + `#5 double-free` (`X.Free`/`FreeAndNil(X)`
> reachable twice, no reassignment between). **(b) the Fowler refactoring-catalog batch** -- see `MISSING-FEATURES.md`
> section 14 (top picks: `magic-literal`, `boolean-flag-parameter`, `message-chain`, `public-writable-field`; then the
> store-backed `middle-man`/`feature-envy`/`repeated-type-switch`). Most of (b) is pure-AST, no new engine.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-02 -- **v0.77.0-alpha PUBLISHED -- #6 duplicate-code clone detection + LSP config parity; NEXT = v0.78 (CK class metrics + M2 flow)**
>
> **v0.77.0-alpha SHIPPED + RELEASED.** `main`=`ed2ec77`, origin synced, tag `v0.77.0-alpha`, GitHub PRERELEASE win32+win64.
> VERSION `CLI.pas:6`=`0.77.0-alpha`. Harness **file 141/141 + store 4/4 + catalog 29/29**.
>
> **What shipped:**
> - **#6 `duplicate-code`** (complexity, `info`, ON, `threshold` default **90**) -- NEW unit
>   `src/diagnostics/DRagLint.Diagnostics.CloneChecks.pas`. Type-2 (renamed-identifier tolerant) clone detection:
>   walk each `defProc` body's leaf tokens, normalize identifiers+literals to placeholders, Rabin-Karp maximal-match
>   over the concatenated token stream (unique per-routine barriers so a clone can't span routines), **coverage-based
>   overlap suppression** (collect candidates -> sort longest-first -> emit only if not already >=50% covered on BOTH
>   sides) collapses self-similar/repetitive regions. `TCloneChecker.Check(AFile)` = within-file (wired into CLI
>   `DoLint` ~4914); `TCloneChecker.CheckProject(FilePaths)` = within+cross-file (wired into `DoLintAll` ~5840, runs
>   ONLY there -- no double-report). Anchors at the lexicographically-later `(FilePath,StartLine)`; findings sorted with
>   a Message tiebreaker. Fixtures: `tests/lint/duplicate-code[.pas|-none.pas]` + `tests/lint-store/duplicate-code/`.
>   FP-sanity on src/: 90->~190, 100->142 (all genuine); chose 90 so a copy-pasted ~12-line routine (~96 tokens) is caught.
> - **LSP config parity** -- `src/lsp/DRagLint.LSP.Completion.pas` `BuildDiagnostics` now (a) runs the clone check and
>   (b) discovers an up-tree `drag-lint-lint.json`/`drag-lint.json` (`DiscoverLintConfig`) and filters lint+clone findings
>   via `Cfg.ShouldKeep`/`ApplySeverity`. Syntax errors + compiler findings always shown.
>
> **KEY GOTCHAS (cost real time this session -- will bite a cold start):**
> - **The IDE gets diagnostics from the `drag-lint lsp` SERVER via `TLspCompletion.BuildDiagnostics`
>   (= `TLinter.LintFile` + `CheckSyntaxErrors` + compiler findings), a DIFFERENT code path from the CLI `DoLint`.**
>   A rule wired into DoLint/DoLintAll does NOT appear in the IDE until it is ALSO added to `BuildDiagnostics`.
> - **The IDE pins a long-running `drag-lint.exe lsp` process and CACHES diagnostics** (the dock panel's "Copy
>   Diagnostics" dumps that cache = `FDiags`). Rebuilding the exe changes NOTHING in the IDE until you **kill every
>   `drag-lint.exe` AND fully restart RAD Studio**, then re-lint (edit+save). A partial restart keeps the stale LSP.
> - Plugin exe path = registry `HKCU\Software\drag-lint\DelphiPlugin\ExePath` (already -> `dll-win64`). A 32-bit IDE
>   spawns the 64-bit exe fine (separate process). No Win32 build needed for the engine.
> - `build\pack-lint-release.ps1` builds the win32 zip from `src\cli\Win32\Release` but only copies **win64** into
>   `third_party\` -- so `third_party\dll-win32\drag-lint.exe` stays STALE (still 0.63). Verify the ZIP's exe, not that path.
> - To drive the LSP headless for testing: `lsp` over stdin with `Content-Length`-framed initialize/initialized/didOpen,
>   Start-Process with `-RedirectStandardInput <file>` (blocking `ReadLine` on stdout hangs -- use file redirection).
> - The drag-lint tree-sitter self-parser errors on `{$I %DATE%}` -- don't put that directive in a `.pas`.
>
> **NEXT = v0.78 (authoritative per-item plan: `docs/lint/PLAN-v076-close-sections.md` Phase 3):**
> - **CK class metrics** (store-backed, use `tests/lint-store` harness): NOC / RFC / LCOM + DIT / CBO -- ship as one bundle.
> - **M2-flow** (extend `FlowChecks`): nullability / not-assigned-interface (#4), double-free (#5).
> - **#9 `default-encoding-io`** if cheap.
> - First task (CK suite) gets a fresh brainstorm -> writing-plans cycle.
>
> **WORKING-TREE NOTE:** `dclDragLintWizard.dproj` + `third_party/dll-win32/dclDragLintWizard.bpl|.dcp` show as modified
> -- RAD Studio IDE-session artifacts (the IDE rebuilt/touched the plugin BPL), NOT edits made this session; left
> uncommitted. `.claude/` + `.vscode/` untracked (local settings). Review/revert/commit separately if wanted.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.76.0-alpha PUBLISHED -- 6 rules (#2/#5/#9/#10/#11) + store-fixture harness; NEXT = v0.77 (CK suite + M2 flow items)**
>
> **v0.76.0-alpha SHIPPED + RELEASED.** `main`=`2e4e131`, origin synced, tag `v0.76.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.76.0-alpha . VERSION `CLI.pas:6`=`0.76.0-alpha`. Harness
> **file 139/139 + store 3/3 + catalog 29/29**. Executed the v0.76 CLOSE PLAN (`docs/lint/PLAN-v076-close-sections.md`):
> - **Phase 0 -- `tests/lint-store/` store-fixture harness** (`run_store_tests.ps1`): indexes each `<case>/` dir to a
>   throwaway SQLite store, runs `check-ast --db` (per-file, default) or `lint-all --db` (via `case.json` `"mode"`),
>   diffs vs `expected.txt` (`<rule> <file>:<line>` / `!<rule>` / `none`; single-subject shorthand `<rule> <line>`).
>   Optional `config.json` (--config) for OFF/thresholded rules. Smoke case = interproc object-leak. README documents it.
> - **#10 `dfm-hardcoded-credential`** (warning) -- `DRagLint.Lint.Linter.CheckDfmCredentials` in the DFM branch: a DFM
>   `property` whose name's last dotted segment is password/pwd/secret/apikey/privatekey/passphrase AND whose `value` is a
>   `string` node with non-empty decoded text. DFM grammar nodes: object>property{name,value}; value 'string' = quoted_string/char_code atoms.
> - **#10 `insecure-temp-file`** (warning) -- DeadCodeChecks: an exprCall whose entity text is a file API
>   (savetofile/loadfromfile/writealltext/tfilestream/...) containing a literalString with a hardcoded temp path
>   (`\temp\`/`c:\temp`/`/tmp/`/`\windows\temp`). src FP=0.
> - **#2 `multiple-statements-per-line`** (hint, **OFF by default**) -- DeadCodeChecks: 2+ sibling statement-type named
>   children of a node sharing StartPoint.Row; one finding per line (LastFlagged guard). Container-agnostic (IsStatementNodeType
>   set, not a fixed 'statements' container -- statements appear un-wrapped as assignment/exprCall/if/... in this grammar).
> - **#9 `nativeint-truncation`** (warning) -- AstChecks.CheckTypeAware cast region (sibling of win64-pointer-cast): a 32-bit
>   cast (integer/cardinal/longint/longword) of a TypeMap operand typed nativeint/nativeuint/intptr/uintptr/ptrint/ptruint.
>   Works pure-AST (same-file TypeMap) so file-harness-testable. src FP=0.
> - **#5 `abstract-method-instantiation`** (warning, STORE) -- CheckTypeAware exprDot branch (needs AStore<>nil): `TFoo.Create`
>   (exprDot rhs='Create', catches both paren + paren-less) where TFoo or a class ancestor has an abstract method with no
>   override. **KEY GOTCHA: the store records Modifiers as VISIBILITY ('public'), NOT the virtual/abstract directive.** Detect
>   abstract by SHAPE instead: `M.IsVirtual and (M.ImplStartLine = 0)` (virtual method, no body); concrete = ImplStartLine>0.
>   Walk ClsSym + GetTransitiveAncestors (Kind='class' only) -> FindAllChildSymbols; unimplemented = abstract names not in
>   concrete names. src FP=0.
> - **#11 `circular-uses`** (warning, STORE) -- `DRagLint.Lint.ProjectRules.CollectCircularUses` (called from `Run` when
>   WantRule; lint-all runs Run unconditionally): Tarjan SCC over the unit uses-graph. Build fid<->unitname (full+stem) from
>   skUnit syms; edges from GetUnitUsesForFile resolved to indexed units; SCC size>=2 -> one finding, anchored at the
>   ALPHABETICALLY-FIRST unit (deterministic output), full member list in the message. Found 1 REAL 8-unit cycle in
>   DragLint.Plugin.* (true positive). Distinct from interface-reference-cycle.
>
> **STORE API CHEAT-SHEET (from this session):** `ISymbolStore` (`src/core/DRagLint.Core.Interfaces.pas`): FindSymbolsByExactName,
> FindAllChildSymbols(parentId), GetTransitiveAncestors(symId)->TTypeAncestor{Name,Kind('class'|'interface'),SymbolId},
> GetUnitUsesForFile(fid)->TUnitUse{UnitName,Section,StartLine}, GetAllFileIds, GetFilePath, FindSymbolsByFile.
> **TSymbol** (`Core.Model.pas`): Kind(skClass/skMethod/skUnit/...), Name, ParentId, **Modifiers=VISIBILITY not directive**,
> **IsVirtual:Bool**, **ImplStartLine (0 = no body = abstract/interface)**. CheckTypeAware sig:
> `(AFile; AStore:ISymbolStore=nil; AFileId:Int64=0)`; DoLintAll calls it with the store at CLI ~5783; ProjectRules.Run at ~5827.
> **Add-a-store-rule = branch in CheckTypeAware (uses AStore) OR ProjectRules.Run + `tests/lint-store/<case>/`** (NOT tests/lint).
>
> **>>> NEXT (v0.77, the big/flow items -- do NOT rush):** #6 **clone/duplicate-code detection** (rolling-hash, biggest single
> item, own design doc) + **CK suite** NOC/RFC/LCOM + **DIT/CBO** (deferred here -- project store lacks RTL ancestors so DIT
> signal is limited in isolation; ship all class metrics together); #4 **nullability**/not-assigned-interface (M2 flow) +
> interface/object mixing; #5 **double-free** (M2 flow: X.Free reachable twice, no reassignment); #9 default-encoding-io (M1),
> variant-record-type-punning (deferred, no clean pure-AST signal); #10 unvalidated-deserialization (no clean signal).
> Phase-3 plan detail is still in `docs/lint/PLAN-v076-close-sections.md` (Phase 3 section).
>
> **UNCOMMITTED NOTE:** a few docs (INSTALL.md/README.md/docs/INSTALL.md/src/delphi-plugin/README.md) showed unexplained
> working-tree edits (stale "25 rules"->"130+" freshness fixes) NOT made this session; left OUT of the v0.76 commit for
> transparency. `.claude/`+`.vscode/` local settings also untracked/left out. Review + commit separately if wanted.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.75.0-alpha PUBLISHED; the v0.76 CLOSE PLAN (user: "close completely #4/#5/#6 + maybe #9/#10/#11, release 0.76")**
>
> **>>> NEXT SESSION: read `docs/lint/PLAN-v076-close-sections.md` -- the full phased plan.** TL;DR: the pure-AST fruit
> is picked; every remaining #4/#5/#6 item needs the M1 store / uses-graph / M2 flow, and the file-only harness can't test
> them. **Phase 0 = build a `check-ast --db` fixture harness (`tests/lint-store/`)** -- the enabler. Then Phase 1 (last
> pure-AST: dfm-hardcoded-credential, insecure-temp-file, multiple-statements-per-line) closes #10+#2; Phase 2 (store:
> abstract-method-instantiation, nativeint-truncation, circular-uses, DIT/CBO) closes #9+#11+most of #5 -> **that is v0.76**.
> Phase 3 (clone detection, CK suite, nullability [M2], double-free [M2]) is what fully closes #4+#6 -> **v0.77** (do NOT
> rush the flow/clone items). Full per-item approach + node types + store API + gotchas are in the PLAN doc.
>
> **v0.75.0-alpha SHIPPED + RELEASED.** `main`=`fab7ee5`, origin synced, tag `v0.75.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.75.0-alpha . VERSION `CLI.pas:6`=`0.75.0-alpha`. Harness
> **135/135**, catalog **29/29**, ~136 rules (80 built-in). Commit `6a9b300`.
> - **#4 `lossy-cast`** (info) -- AstChecks.CheckTypeAware, in the exprCall cast region: Ansi-narrowing cast
>   (ansistring/ansichar/shortstring/rawbytestring) of a Unicode-string operand (TypeMap type string/unicodestring/
>   widestring/widechar). src FP=2 (real).
> - **#5 `create-inside-try`** (warning) -- DeadCodeChecks try branch: a try WITH a `kFinally` whose FIRST protected
>   statement (first named child that is not a `k`-keyword) is `X := TFoo.Create`. **GOTCHA: a paren-less `TFoo.Create`
>   is an `exprDot` (NOT exprCall); with parens `TFoo.Create(...)` is `exprCall(entity=exprDot)` -- `IsConstructorAssignment`
>   handles both.** `UnwrapStmt` drills through `statement`/`statements` wrappers. FixInsight-parity. src FP=12 (real).
> - **#6 `cognitive-complexity`** (info, **threshold 25**) -- new `AstChecks.CheckCognitiveComplexity` (mirrors
>   CheckCyclomaticComplexity): per-defProc score = each if/ifElse/while/for/repeat/case/exceptionHandler adds `1+nesting`,
>   each kAnd/kOr/kXor adds 1; recursion stops at nested defProc. **Default 25 (NOT 15): cognitive scores higher than
>   cyclomatic -- at 15 it gave 216 findings on src/ vs cyclomatic's 115@15; 25 gives 100 = comparable.**
> - **#10 `weak-random-for-security`** (warning) -- DeadCodeChecks `assignment` branch: lhs is a security-named identifier
>   (`IsSecurityName`: password/passphrase/secret/token/apikey/privatekey/salt/nonce/sessionid/cryptokey/securitykey) and
>   rhs subtree calls System.Random/RandomRange. src FP=0. (`assignment` node = fields `lhs:`/`operator:`(kAssign)/`rhs:`.)
>
> **>>> NEXT (remaining tails):** #10 `dfm-hardcoded-credential` (scan DFM password props -- needs the DFM parse path) +
> `insecure-temp-file`; #6 **clone / duplicate-code detection** (biggest remaining, token-hash pass) + CK suite (needs
> graph); #4 nullability (flow); #5 abstract-method-instantiation (store); #9 nativeint-truncation (M1) +
> variant-record-type-punning; #11 circular-uses report + DIT/CBO (uses-graph). Many remaining need M1/M2/graph -> a
> `check-ast --db` test harness would unblock them. Also #2 multiple-statements-per-line still open (easy pure-AST).
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.74.0-alpha PUBLISHED -- #4 exhaustive-enum-case (store-aware) + #6 unit-too-large DONE; NEXT = #9/#10/#11 pure-AST tails (user-requested)**
>
> **v0.74.0-alpha SHIPPED + RELEASED.** `main`=`df331c8`, origin synced, tag `v0.74.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.74.0-alpha . VERSION `CLI.pas:6`=`0.74.0-alpha`. Harness
> **131/131**, catalog **29/29**. Commit `558c2d1`.
> - **#4 `exhaustive-enum-case`** (warning, **OFF by default**) -- in `AstChecks.CheckTypeAware`. A `case` on an enum-typed
>   selector that omits members and has no `else`. **FIRST store-aware rule that ALSO works pure-AST** (same-file enums): new
>   `CollectEnums` builds a same-file map from `declType`>`declEnum`>`declEnumValue` (name field); `ResolveEnumMembers` uses
>   that map first, then the store (`FindSymbolsByExactName`->`skEnum`->`FindAllChildSymbols`->`skEnumValue`). **KEY GOTCHA
>   (cost 4 debug builds): a `case` node's NAMED children INCLUDE the keyword tokens `kCase`/`kOf`/`kElse`/`kEnd`** -- so
>   NamedChild(0) is `kCase`, NOT the selector. Selector = first named child that is not a caseCase/statement and does not
>   start with 'k'. `else` = presence of a `kElse` child. caseCase has a `body` field + a `label` field (`caseLabel`>identifier).
>   Bails on a range label ('..'). OFF-by-default (subset-without-else is common); opt in via `"enabled"`/`--rule`. Config
>   sidecar `exhaustive-enum-case.config.json`. **Calling `.NodeType` on a NULL TTSNode ACCESS-VIOLATES in tree-sitter.DLL --
>   always guard with `.IsNull` first (short-circuit `and`).**
> - **#6 `unit-too-large`** (info, threshold=2000) -- in `DeadCodeChecks.Check` (new `AMaxUnitLines` param; root node
>   `EndPoint.Row+1`). Configurable; test via a low-threshold config sidecar.
>
> **INDEXER NOTE (user feedback this session): use the drag-lint SELF-INDEX, not Grep, for Delphi symbol lookups** --
> `Delphi-RAG-lint.sqlite` (outDir `C:\Projects\.drag-lint\`); `drag-lint query --name <Sym> --db <db>` /
> `drag-lint context --task "modify <Sym>" --db <db>`. CAVEAT: the self-index is dated ~Jun 29 so it MISSES today's new
> symbols (e.g. ResolveTypeCategory) -- reindex incrementally when querying just-changed code. Log substitutions to
> `stats/draglint-usage.log`.
>
> **>>> NEXT (user-requested order): #9 (portability), #10 (security), #11 (architecture) -- pure-AST tails.** Candidates:
> #9 `nativeint-truncation` (M1), `variant-record-type-punning`; #10 `weak-random-for-security` (Random for tokens),
> `dfm-hardcoded-credential` (scan DFM prop values), `insecure-temp-file`; #11 `circular-uses` report (cycle listing).
> Then: #6 clone detection (biggest); #4 lossy casts / nullability (flow/type); #6 cognitive-complexity + CK suite.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.73.0-alpha PUBLISHED -- #8 (2 rules) DONE; #1-#8 pure-AST items now closed. NEXT = clone detection (#6) OR store-backed rules (#4/#5/#6)**
>
> **v0.73.0-alpha SHIPPED + RELEASED.** `main`=`b3ec317`, origin synced, tag `v0.73.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.73.0-alpha . VERSION `CLI.pas:6`=`0.73.0-alpha`. Harness
> **129/129**, catalog **29/29**. **2 new pure-AST rules in `TDeadCodeChecker.Visit`** (commit `d936310`), same add-a-rule
> pattern as v0.72:
> - **#8 `repeated-else-if-condition`** (warning) -- same condition text twice in one if/else-if chain (later branch dead).
>   Walk the chain from its TOP (an `ifElse` that is NOT the else-slot of another if/ifElse) via the `else` field; compare
>   `NormaliseText(ChildByField('condition'))` case-insensitively. `if`/`ifElse` both have `condition:` + `else` fields.
> - **#8 `property-references-itself`** (warning) -- a property read/write accessor that names the property itself (infinite
>   recursion). Count identifier descendants of a `declProp` matching `ChildByField('name')`, EXCLUDING the name node
>   (by StartByte) and the type subtree (`ChildByField('type')` by Start/EndByte). No accessor-field knowledge needed.
>
> Both 0 FP over src/. **This session shipped v0.71 (unsafe-typecast + redundant-cast autofix), v0.72 (5 rules #5/#6/#7),
> v0.73 (2 rules #8) -- the pure-AST items in MISSING-FEATURES #1-#8 are now all closed.**
>
> **>>> NEXT (the remaining tail is bigger / needs engines):**
> 1. **#6 clone / duplicate-code detection** -- the biggest single remaining pure-AST-ish item; a token/hash pass over
>    routine bodies. Its own chunk (design first).
> 2. **Store-backed rules** (untestable in the file-only `lint <file>` harness -> need a `check-ast --db` test path):
>    #4 lossy Ansi<->Unicode / exhaustive-enum-case / nullability; #5 abstract-method-instantiation; #6 CK suite (DIT/NOC/
>    CBO/RFC/LCOM), cognitive complexity, unit-too-large; #9 nativeint-truncation. Also #10 more security (weak-random,
>    dfm-hardcoded-credential), #12 more .scm-rule autofixes (need a FixText payload on TLintFinding).
> 3. Still pending (human): v0.70 Lint Options tab in-IDE click-test.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.72.0-alpha PUBLISHED -- #5/#6/#7 pure-AST tail (5 rules) DONE; NEXT = #8 (repeated-else-if-condition / property-references-itself) OR clone detection (#6)**
>
> **v0.72.0-alpha SHIPPED + RELEASED.** `main`=`c661d4e`, origin synced, tag `v0.72.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.72.0-alpha . VERSION `CLI.pas:6`=`0.72.0-alpha`. Harness
> **127/127**, catalog **29/29**. **5 new pure-AST rules, all as branches in `TDeadCodeChecker.Visit`** (commit `2a6a970`;
> `src/diagnostics/DRagLint.Diagnostics.DeadCodeChecks.pas`) -- auto-covered by DoLintAll; DoLint dispatch + allow-list + help
> in `CLI.pas` (thresholds from `Cfg.ThresholdFor`); catalog `B()` in `RuleCatalog.pas`:
> - **#5 `destructor-without-override`** (warning) -- a class-decl destructor (`declProc` with a simple-`identifier` name, NOT a
>   `genericDot` impl signature) with no `kVirtual/kDynamic/kOverride/kAbstract` in its subtree. Excludes `class destructor`
>   (`kClass`). **GOTCHA learned: a defProc's header IS a declProc**, so guard on name-kind = identifier (decl) vs genericDot (impl).
> - **#6 `case-with-too-few-branches`** (hint, threshold=2) -- count `caseCase` children of a `case` node; flag `< N` (>=1).
> - **#6 `boolean-expression-complexity`** (info, threshold=4) -- count `kAnd/kOr/kXor` op nodes in an `exprBinary` subtree;
>   flag once at the chain TOP (parent operator is not itself boolean). Thresholds via new `Check(AFile, AMinCaseBranches=2, AMaxBoolOps=4)`.
> - **#7 `exception-constructed-but-not-raised`** (warning) -- an `exprCall` whose parent is `statement` (a raise wraps the call
>   in its `exception` field -> parent `raise`) and entity is `exprDot` `.Create` on an `E`+Upper / `*Exception` class.
> - **#7 `duplicate-exception-handler`** (warning) -- walk a `try` collecting `exceptionHandler` class texts (`HandlerClassText`:
>   `type` field else first non-variable typeref/identifier), case-insensitive; flag a repeat. Stops at nested `try`.
>
> FP-sanity src/ (101 files): 4 rules = 0; boolean-expression-complexity = 26 (ALL legit complex exprs 5-64 ops, info sev).
> **NODE-TYPE REFERENCE (verified this session):** `declProc`/`defProc` both have a `header` field (kConstructor/kDestructor
> children); directives (`kVirtual/kDynamic/kOverride/kAbstract`) are descendant nodes; `case`>`caseCase`>`caseLabel`;
> `try` with `exceptionHandler` (fields `variable:`, `body:`, type via `type`/scan); `raise` field `exception:`; qualified call
> entity = `exprDot` (lhs/rhs); boolean ops = `exprBinary` `operator:` -> `kAnd/kOr/kXor`; bare-stmt call parent = `statement`.
>
> **>>> NEXT (continue the loop):**
> 1. **#8 control-flow/expression** (pure-AST): `repeated-else-if-condition` (same test twice in an if/else-if chain -- need the
>    ifElse **condition** field name, verify first) + `property-references-itself` (a property read/write accessor naming the
>    property itself -> infinite recursion -- need property-decl structure). -> v0.73.
> 2. **#6 clone / duplicate-code detection** -- the biggest remaining single item; a token-hash pass. Its own chunk.
> 3. **Store-backed** (#4 lossy casts/enum-case, #5 abstract-method-instantiation, #6 CK suite) -- need M1/graph; `check-ast --db`.
> 4. Still pending (human): v0.70 Lint Options tab in-IDE click-test.
>
> **Add-a-rule pattern (v0.72-verified, node-triggered rules):** branch in `DeadCodeChecks.Visit` -> `EmitAt(node,id,msg,sev)`
> + allow-list + help + DoLint dispatch guard in `CLI.pas` (+ thresholds arg if parameterized) + `B()` catalog + `tests/lint/<id>.pas`+`.expected`.
> DoLintAll auto-covers. Build `build\build_draglint_win64.bat` (kill drag-lint.exe first). Publish `build\pack-lint-release.ps1 -Version X`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.71.0-alpha PUBLISHED -- #4 casts + #12 autofix DONE; NEXT = continue MISSING-FEATURES loop (#5) OR #12 .scm-rule FixText autofixes**
>
> **v0.71.0-alpha SHIPPED + RELEASED.** `main`=`bf273b3`, **origin synced (0 ahead)**, tag `v0.71.0-alpha`, GitHub PRERELEASE
> win32+win64: https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.71.0-alpha . VERSION `CLI.pas:6`=`0.71.0-alpha`.
> Harness **122/122**, catalog **29/29**. Tree clean (only untracked `.vscode/`).
>
> **DONE this session (user directive "complete #4 + #12 then publish v0.71"):**
> - **#4 `unsafe-typecast-without-is`** (commit `8e6f96f`, **OFF by default**): pure-AST in `AstChecks.CheckTypeAware` beside
>   redundant-cast. Flags a hard cast `TFoo(x)` of an object ref to a DIFFERENT class with no guarding `x is TFoo`. Fires only
>   when target is a plausible class (`LooksLikeClassType`: T-prefix minus a value/record denylist TDateTime/TColor/TRect/... ;
>   store `tcClass` authoritative when present) AND `x` declared `TObject` or a *different* T-class. Skips redundant same-type
>   cast, `TObject` upcast, guarded + value casts. `is` guards collected file-wide by operator **source text** ('is') via new
>   `CollectGuards` pre-pass (grammar-node-name independent) into a `'x|TFoo'` set. FP-sanity src/ (101 files) = **3**, all
>   `T...(Sender)` handler downcasts. Off-wiring mirrors function-result-ignored: `DefDisabled` in DoLint(~4751)+DoLintAll(~5786),
>   catalog `B(..,False)`, opt in via `<base>.config.json "enabled"` / `--rule`. Fixture + `.expected` + `.config.json`.
> - **#12 `redundant-cast` autofix** (commit `4c012de`): 3rd quick-fix in `BuildAutofixEdits` (`CLI.pas:~4448`). `TFoo(x)`->`x`
>   via `tekReplaceInLine` over `[StartCol, ')'+1)`; safe because redundant-cast fires only on a single-identifier arg (no
>   nested paren -> ')' is the first after '('). Verified `TStringList(SL).Add('x');`->`SL.Add('x');` (dry-run + --apply/.bak).
> - **Release** (commit `bf273b3`): VERSION bump + CHANGELOG "Unreleased" -> `## v0.71.0-alpha` (autofix subsystem + both cast
>   rules + function-result-ignored + a Deferred note); `build\pack-lint-release.ps1 -Version 0.71.0-alpha` (both exes verified
>   0.71.0-alpha); tag + push + `gh release create --prerelease` (2 assets).
>
> **>>> NEXT (user to choose / continue the loop):**
> 1. **#12 `.scm`-rule autofixes** (`redundant-not-not`, `boolean-comparison-true`, `redundant-as-tobject`) -- these `.scm` rules
>    have NO code emission point, so span-surgery from the finding text is fragile. Do it right: add an optional **`FixText`/fix-kind
>    to `TLintFinding`** (populated by the check or a `.scm` sidecar `fix` spec) so `BuildAutofixEdits` gets an exact replacement.
> 2. **#4 store-backed cast rules** (lossy Ansi<->Unicode, exhaustive enum-case, nullability) -- need the **M1 store** (member
>    sets, exact cross-unit types); UNtestable by the file-only `lint <file>` harness -> a store-backed path tested via `check-ast
>    --db`. **DEFERRED** (documented in CHANGELOG). 
> 3. **Continue MISSING-FEATURES loop at #5** (roadmap `.superpowers/sdd/missing-features-roadmap.md`) -> bundle -> publish v0.72.
> 4. **Still pending (human):** v0.70 Lint Options tab in-IDE click-test.
>
> **GOTCHAS unchanged:** (a) build `.bat` `copy` silently fails on an exe lock -> `Stop-Process drag-lint -Force` + verify
> LastWriteTime. (b) the bare `src\cli\Win64\Release\drag-lint.exe` produces NO output for `--version` (missing tree-sitter DLLs
> in that dir) -> test the canonical `third_party\dll-win64\drag-lint.exe` (has DLLs) or the zip. (c) `.pas`/`.expected` CRLF +
> 7-bit ASCII; config sidecar = `ChangeExtension(pas,'.config.json')`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.71 IN PROGRESS on `main` UNRELEASED -- #12 autofix + #4 redundant-cast SHIPPED; finish #4/#12 then publish v0.71**
>
> **User directive: "complete #4 and #12 then publish as 0.71; handoff+clear+resume when context nears 75%."** This handoff is
> that checkpoint (long session; clean point). `main`=`7d3163f`, **origin synced (0 ahead)**, tag still `v0.70.0-alpha`, tree clean
> (only untracked `.vscode/`). Harness **121/121**, catalog **29/29**.
>
> **DONE this session (both committed + pushed):**
> - **#12 autofix subsystem** (commit `df1bf6a`): `drag-lint lint <file> --fix` (and `lint-all`). Dry-run preview by default;
>   `--apply` writes with a `.bak` (unless `--no-backup`). New primitive **`tekReplaceInLine`** (char-range replace on one line)
>   + `EndCol` field in `src/refactor/DRagLint.Refactor.TextEdit.pas`. `BuildAutofixEdits` (in `src/cli/DRagLint.CLI.pas`, just
>   above `FinalizeAndOutput`, invoked from FinalizeAndOutput after config+baseline filtering) dispatches by rule id. Seed fixes:
>   `self-assignment` -> delete line (fits the existing line-applier); `redundant-parentheses` -> strip the outer `(` `)` of the
>   span. Verified: `X := (1);`->`X := 1;`, `X := X;` deleted, `Writeln((X));`->`Writeln(X);`.
> - **#4 `redundant-cast`** (commit `7d3163f`): pure-AST, low-FP. In `AstChecks.CheckTypeAware` (the per-file `TypeMap` check,
>   beside `win64-pointer-cast`): flags `TFoo(x)` where `x` is declared EXACTLY `TFoo`. T-prefixed class-like entity + single
>   identifier arg + exact case-insensitive type match -> 0 FP over src. `hint`, category `dead-code`. Wired allow-list + help +
>   DoLint dispatch (`CheckTypeAware`); DoLintAll auto-covers. Fixture `tests/lint/redundant-cast.pas`.
>
> **>>> NEXT (ordered):**
> 1. **#4 `unsafe-typecast-without-is`** -- a hard cast `TFoo(x)` with no guarding `x is TFoo`. Pure-AST feasible via T-prefix +
>    scan enclosing block for an `is` guard, but FP-prone (many unguarded casts are safe) -> ship **OFF-by-default** like
>    `function-result-ignored` (add to `DefDisabled` in DoLint ~4643 + DoLintAll ~5681; catalog `default_enabled=false`; test via
>    an enabling `unsafe-typecast-without-is.config.json` = `{ "enabled": [...] }`). A hard cast is an `exprCall` (no dedicated
>    node); `as`-cast = `exprBinary`+`kAs`.
> 2. **#4 lossy Ansi<->Unicode / exhaustive-enum-case / nullability** -- genuinely need the **M1 store** (enum member set, exact
>    types). Store rules can't be tested by the file harness (`lint <file>`, no `--db`). **Likely DEFER + document** (mirror the
>    function-result-ignored honesty). Consider a store-backed path tested via `check-ast --db`.
> 3. **#12 more autofixes** (`redundant-not-not`, `boolean-comparison-true`, `redundant-as-tobject`) -- these are **.scm** rules
>    with NO code emission point, so span-surgery from the finding text is fragile. Do it right: add an optional **`FixText`/fix-kind
>    to `TLintFinding`** (populated by the check / a `.scm` sidecar `fix` spec) so `BuildAutofixEdits` has an exact replacement.
> 4. **PUBLISH v0.71**: bump `VERSION` `src/cli/DRagLint.CLI.pas:6` -> `0.71.0-alpha`; move CHANGELOG "Unreleased" -> `## v0.71.0-alpha`
>    (already has function-result-ignored; add autofix + redundant-cast); `build\pack-lint-release.ps1 -Version 0.71.0-alpha`;
>    `git tag v0.71.0-alpha`; `gh release create ... --prerelease` (win32+win64 zips); push.
>
> **GOTCHAS:** (a) the build `.bat` `copy` step SILENTLY fails if `drag-lint.exe` is locked (the edit-hook spawns it) yet echoes OK
> -> ALWAYS `Stop-Process drag-lint -Force` then `Copy-Item` manually + verify LastWriteTime. (b) Add-a-rule = branch/emit + 3 CLI
> edits (allow-list ~4709/4614, help ~4724/4620, DoLint dispatch) + `B()` catalog + `tests/lint/<id>.pas`+`.expected`; DoLintAll
> usually auto-covers. (c) `.pas`+`.expected` must be CRLF + 7-bit ASCII. (d) config sidecar name = `ChangeExtension(pas,'.config.json')`
> = `<base>.config.json`, NOT `.pas.config.json`. (e) tree-sitter self-parser chokes on set-range literals `['A'..'Z']` -> use `>=`/`<=`;
> a `{ }` comment containing `{..}` closes early (breaks dcc). Also still pending: **v0.70 Lint Options tab in-IDE click-test** (human).
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.70.0-alpha PUBLISHED; rule 3 function-result-ignored DONE (OFF-by-default) on `main` UNRELEASED; NEXT = publish v0.71 OR continue #4 casts**
>
> **function-result-ignored SHIPPED to `main` (commit `48a0dc6`), UNRELEASED (main ahead of tag `v0.70.0-alpha`).**
> Pure-AST, same-unit (no store): flags a bare-statement call (exprCall whose parent is a `statement` node) to an
> unqualified identifier naming a same-unit FUNCTION (declProc with a return-type `type` field; collected in a pre-pass
> `LocalFunctions`). **SHIPS OFF BY DEFAULT** -- a real src/ FP-sanity gave **73 findings on clean code, ~all INTENTIONAL
> discards** (builder/adder `AddWrappedItem`/`AddNodeData`/`NewLabel`, runner `RunAndCaptureStdout`); discarding a result
> is common+usually-intentional in Delphi, no pure-AST heuristic separates bug from intent (why MISSING-FEATURES deferred
> it). Off-by-default wiring: appended to `DefDisabled` in DoLint (~4643) + DoLintAll (~5681 was `nil`); `ShouldKeep`
> suppresses it unless config `"enabled": ["function-result-ignored"]`; catalog `default_enabled=false`. Opt in via that
> config or `--rule function-result-ignored`. Fixture `tests/lint/function-result-ignored.pas` + enabling sidecar
> **`function-result-ignored.config.json`** (harness uses `ChangeExtension(pas, '.config.json')` = `<base>.config.json`,
> NOT `.pas.config.json`). Full harness **120/120**, catalog 29/29, default src run = 0.
>
> **>>> NEXT (user to choose):** (a) publish **v0.71** (bump VERSION 0.71.0-alpha + move CHANGELOG "Unreleased" -> v0.71 +
> pack + tag + gh prerelease + push) -- for one opt-in-off rule; OR (b) continue the MISSING-FEATURES loop at **#4 casts**
> (redundant-cast, unsafe-typecast-without-is [both pure-AST], lossy Ansi/Unicode, enum-case, nullability [M1-backed]) and
> bundle function-result-ignored into that release. Roadmap `.superpowers/sdd/missing-features-roadmap.md`.
> **Also still pending: the v0.70 Lint Options tab UI in-IDE click-test (search row + profile switch); fix-forward if bad.**
>
> --- (prior milestone -- v0.70 detail below) ---
>
> **v0.70.0-alpha SHIPPED + RELEASED** (origin/main=`636ffd2`, tag `v0.70.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.70.0-alpha ; VERSION `CLI.pas:6`=`0.70.0-alpha`;
> harness **119/119**, rule-catalog **29/29**). v0.70 = the #2 dead-code tail (2 of the 4 items) + the Lint Options tab UI:
> - **`redundant-parentheses`** (AST `hint`): flags nested `((X))` or a lone-term `(X)`/`(1)`; skips composite inners
>   AND initializer/constructor contexts (`N.Parent.NodeType` in defaultValue/arr|recInitializer/declConst/constInline --
>   there a single-element `(x)` is a REQUIRED constructor, e.g. `array[0..0] of string = ('x')`).
> - **`commented-out-code`** (AST `hint`): flags a comment whose ENTIRE stripped text is one statement -- anchored
>   `lhs := rhs;` (bare lvalue) or `idpath(...);` (paren immediately after id); skips `{$..}` + `///`.
> - Both **FP-hardened to 0 FP** over a real `src/` sanity (101 files). commented-out-code's naive first cut (`Pos(':=')>0`)
>   was **20/20 FP** on doc comments quoting code -> tightened to whole-statement anchoring.
> - Lint Options tab UI (commit `320cf9b`): search on its own row w/ a Segoe MDL2 magnifier glyph (`WideChar($E721)`,
>   keeps .pas 7-bit ASCII) + `Search` label; profile switch no longer respawns `drag-lint rules --json` (re-renders from
>   cached `FCatalogJSON`). **COMPILE-verified only; in-IDE click-test PENDING** (user chose publish-now over hold).
>
> **Add-a-rule pattern (v0.70-verified):** branch in `DeadCodeChecks.pas` `Visit` closure -> `EmitAt(node,id,msg,severity)`
> (EmitAt gained an optional severity, default 'warning') + 3 edits in `DRagLint.CLI.pas` (allow-list ~4614, help ~4620,
> DoLint dispatch ~4728; DoLintAll ~5628 runs the checker unconditionally = auto-covers) + `B(id,cat,sev,title)` in
> `RuleCatalog.pas` + `tests/lint/<id>.pas`+`.pas.expected` + rebuild `build\build_draglint_win64.bat` + `run_lint_tests.ps1`.
> **GOTCHA: the build .bat `copy` step silently fails on an exe lock (the edit-hook spawns drag-lint.exe) yet echoes OK ->
> STALE staged exe. Always `Stop-Process drag-lint -Force` then Copy-Item manually + verify LastWriteTime.**
>
> **>>> NEXT = `function-result-ignored` (user-approved 2026-07-01), targeting v0.71.** Needs symbol-store type resolution
> (function vs procedure) -> it CANNOT live in pure-AST `TDeadCodeChecker.Check(file)`; it needs a store-bearing checker +
> wiring in the store-backed DoLint/DoLintAll path (see `check-ast` -> `TAstChecker.Check(Store,file)` / `CheckTypeAware`).
> FP-prone even with the store (`List.Add`/`TStringList.Add`/`IndexOf` results are legitimately discarded) -> will need a
> denylist or user-defined-only scoping + an indexed-corpus sanity pass (mirror the src/ FP-harden loop; use ORM3 DB or the
> self-index). After rule 3 -> continue the loop at **#4 casts** (roadmap `.superpowers/sdd/missing-features-roadmap.md`).
> `multiple-statements-per-line` still deferred (easy/low-FP; a later chunk).
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.69.0-alpha PUBLISHED; NEXT = AUTONOMOUS MISSING-FEATURES LOOP (start #2 dead-code tail -> v0.70)**
>
> **v0.69.0-alpha SHIPPED + RELEASED** (origin/main=`b21c5af`, tag `v0.69.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.69.0-alpha ; VERSION `CLI.pas:6`=`0.69.0-alpha`; harness
> **117/117**). Bundle: D3 (2 naming rules) + D1a (`drag-lint rules` catalog) + D2a (`rename --kind symbol|param`) +
> D2b (`find-unit`+`safe-delete`) + D1b (IDE "Lint Options" dock tab) + **profiles+search** (tab now saves/loads FULL-config
> named profiles via an editable combo; `drag-lint lint --profile <name>` applies the full config; live rule search).
> Profiles+search: `Config.Load` full-profile override (lists REPLACE, maps override per-key; `ApplyConfigObject`/
> `ApplyNamingObject`), `ConfigWriter.ListProfileNames`+`SaveToProfile` (merge-preserving), tab combo + search + `FCfg`
> baseline. Subagent-driven, opus final review clean; t65 15/0, t63 39/0, t64 compile PASS.
>
> **D1b tab is CONFIRMED WORKING in the 32-bit IDE** after 4 post-merge fixes (all on main): (1) build the plugin **Win32**
> (not Win64) -> `third_party\dll-win32` (the IDE's load path); `_bpl_build.bat` is now Win32; `DCC_UsePackage` moved to the
> `.dproj` Base group so a cmdline Win32 build links `vclsmp`. (2) the frame is a code-built **`TForm`+`CreateNew`**, not a
> `TFrame` (a `.dfm`-less TFrame raises `EResNotFound`). (3) `ResolveExe` prefers the sibling `dll-win64\drag-lint.exe`
> engine (like `DLExe64`) -- the `dll-win32` exe can be a stale build predating `rules`. (4) `RenderCatalog` uses
> `AddOrSetValue`, never `Dict[key]:=` (SetItem raises "Item not found").
>
> **>>> NEXT = the AUTONOMOUS MISSING-FEATURES LOOP** (user directive 2026-07-01, user away). Go through
> `docs/lint/MISSING-FEATURES.md` top-down (#1..end), implement OPEN items + publish in CHUNKS (a section ~= a prerelease).
> Roadmap + per-rule cadence + release recipe: **`.superpowers/sdd/missing-features-roadmap.md`**. Most items are
> **CLI/lint/config** = console-testable + autonomously publishable; **section 13 (IDE Refactor tab + hard refactors) needs a
> human gate -> DEFER**. NEXT OPEN CHUNK = **#2 dead-code tail** (`function-result-ignored` [info, FP-prone],
> `commented-out-code` [lexer/comment scan], `redundant-parentheses` [AST]) -> bump v0.70 -> handoff -> repeat (#4 casts ->
> #5 -> #6 -> #7 -> #8 -> #9 -> #10 -> #11 -> #12 autofix). Per-rule: fixture (tree-sitter-verify) -> `CheckXxx` in
> `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas` -> ~4 CLI wiring edits in `src/cli/DRagLint.CLI.pas` -> `tests/lint`
> fixture -> rebuild CLI Win64 (`build\build_draglint_win64.bat` via Start-Process -Wait + log) -> harness green ->
> normalize CRLF -> commit. Ledger `.superpowers/sdd/progress.md`; rule-adding node-kinds in memory `project_lint_rules_v062.md`.
> **CAVEAT:** the profiles+search tab UI is COMPILE-verified only -- the in-IDE click-test (profiles combo + search) is
> PENDING; the fresh Win32 BPL is deployed in `third_party\dll-win32`; fix-forward v0.69.1 if the user's click-test finds a bug.
>
> **UI FOLLOW-UP 2026-07-01 (commit `320cf9b` on `main`, uncommitted->committed; COMPILE-verified, click-test PENDING):** per
> user feedback ("profile save-load works, though slow" + "put search on its own line with a word + icon-glyph"):
> (1) search TEdit moved out of the top button panel onto a dedicated 2nd row = a Segoe MDL2 Assets magnifier glyph
> (U+E721, set via `WideChar($E721)` so the .pas stays 7-bit ASCII) + a "Search" label + width-stretched edit;
> (2) `ProfileSelected` fast-path: skip re-spawning `drag-lint rules --json` on profile switch (catalog is static; reload
> `FCfg` + re-render from cached `FCatalogJSON`). Both platform BPLs rebuilt (dll-win32 + dll-win64), 0 errors/19 pre-existing
> hints. `DragLint.Plugin.LintOptionsFrame.pas`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.69 CODE-COMPLETE: D1b DONE + MERGED to local `main` @ `d4cac28`; NEXT = HUMAN in-IDE gate + v0.69 PUBLISH**
>
> **v0.69 D1b DONE + MERGED to local `main`** (ff `28597c3..d4cac28`; branch `feat/v069-d1b-lint-options-tab` deleted;
> **NOT pushed/tagged**; `main` 37 commits ahead of origin; VERSION still `0.68.0-alpha`). The 4th drag-lint IDE dock tab
> **"Lint Options"**: a VCL `TLintOptionsFrame` (`src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas`) that shells
> `drag-lint rules --json` (via `ProcRun.RunCaptureStdout`), renders rules grouped by category (tri-state header + per-rule
> checkbox + per-param editors + counts header), and round-trips the active project's `drag-lint-lint.json` through a NEW
> pure serializer `TLintConfigWriter` (`src/lint/DRagLint.Lint.ConfigWriter.pas`; merge-preserving `SaveToFile`; + read
> accessors/write mutators on `TLintConfig`). Wired via `DockForm.AddTab` (guarded `CreateEmbeddedLintOptions`); registered
> in `.dpk`/`.dproj` with `DCC_UnitSearchPath ..\core;..\lint` + `Core.Model` + `vclsmp` (TSpinEdit). BPL builds clean Win64
> (0 errors). Subagent-driven 5 tasks, each per-task-reviewed; **opus FINAL whole-branch review caught 2 real bugs the
> diff-scoped reviews missed, both FIXED + re-reviewed clean:** (Critical) complexity thresholds were keyed by param name
> `'threshold'` but the linter reads by RULE ID (`CLI.pas:4679-4715`) -> editing them was a silent no-op -> fixed to key by
> `Rule.Id`; (Important) `SaveToFile` whole-file overwrite dropped a project's `profiles` block (data loss) -> fixed to
> merge-preserve non-owned top-level keys (+T63 regression). Tests: T63 config round-trip **35/0**, T64 frame compile-smoke
> **OK**. `undeclared-identifier` decision: EXCLUDED from the catalog (index-only `check-ast` diagnostic, not
> `drag-lint-lint.json`-configurable; documented in `MISSING-FEATURES.md` section 13).
>
> **>>> REMAINING v0.69 (BOTH need the USER -- the agent CANNOT do these):**
> **(1) HUMAN in-IDE gate** -- open RAD Studio (it loads the FRESH BPL the build wrote to `third_party/dll-win64`, which
> shows ` M` tracked-but-uncommitted). Confirm a 4th **"Lint Options"** tab appears -> catalog loads
> (`115 rules across 12 categories, K enabled`) -> toggle a rule / a section tri-state / a param / a naming prefix -> Save
> -> `drag-lint-lint.json` round-trips. **TWO regression-specific checks the reviews surfaced:** (a) edit a COMPLEXITY
> threshold (e.g. `deep-nesting`) + confirm `drag-lint check` actually changes; (b) open a project whose `drag-lint-lint.json`
> has a `profiles` block + Save + confirm the profiles SURVIVE on disk.
> **(2) v0.69 PUBLISH** (separate gate, after the in-IDE gate): bump VERSION `0.69.0-alpha` (`src/cli/DRagLint.CLI.pas:6`)
> + CHANGELOG date + `git tag v0.69.0-alpha` + push + GitHub prerelease (win32+win64 zips).
> NOTE: win32-vs-win64 deploy path is the user's env detail (the plan's `C:\TEMP1\bpl_staging` staging is STALE -- the
> Win64 build writes straight to `third_party/dll-win64`); the new `*.bpl`/`*.dcp` gitignore is harmless (tracked BPLs stay
> tracked + committable). **v0.69 is now CODE-COMPLETE (D3 + D1a + D1b + D2a + D2b all on `main`).** Ledger:
> `.superpowers/sdd/progress.md`; task reports `.superpowers/sdd/d1b-*`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 (LATEST) -- **v0.69 D3 + D1a + D2a + D2b SHIPPED to `main` (NOT published); NEXT = D1b ONLY (IDE tab, MANUAL gate)**
>
> **v0.69 D2b DONE + MERGED to `main`** (local `main`=`951de40`; **NOT pushed/tagged**; `main` 21 commits ahead of origin).
> Two more `drag-lint` refactor subcommands, backed by a new range-edit primitive (new unit `DRagLint.Refactor.TextEdit`:
> `TTextEdit` + `TTextEditApplier` insert/delete + builders): **`find-unit --name <Sym> --in <file>`** (add the unit
> declaring <Sym> to <file>'s uses clause; impl-uses preferred; no-op if already imported) + **`safe-delete --name
> <QName>`** (delete decl + impl body ONLY when zero references; **REFUSES otherwise**). Both store-driven, dry-run default
> + `--json` + `--apply`. CORRECTNESS: safe-delete's zero-ref check uses `FindCallersByName` (NOT `FindReferencesTo`, which
> is always-empty because refs.symbol_id is NULL). Subagent-driven 5 tasks (plan
> `docs/superpowers/plans/2026-06-30-v069-d2b-finunit-safedelete-plan.md`); safe-delete got an OPUS review (verified at the
> SQL layer; every failure mode = over-REFUSAL never over-deletion); OPUS whole-branch = READY TO MERGE, no Critical/
> Important. Tests: textedit **5/5**, find-unit **5/5**, safe-delete **3/3** (incl. the refuse case), lint **117/117**.
> ORM3 sanity: safe-delete on a 161-caller symbol correctly REFUSED (exit 2). **D2 COMPLETE (D2a + D2b).** FOLLOW-UPS
> (non-blocking, in ledger): find-unit multi-entry-uses test + alias normalization; safe-delete both-spans fixture +
> refuse-on-ambiguous-QName. **NEXT = D1b ONLY** -- the IDE "Lint Options" dock tab consuming `drag-lint rules --json`;
> **MANUAL BPL gate** (RAD Studio closed to build the BPL + a human click-test; NOT fully autonomous). v0.69 publishes
> (VERSION bump 0.69.0-alpha + tag + GitHub release) only after D1b.
>
> **>>> D1b PLAN IS WRITTEN (commit 234ba5e): `docs/superpowers/plans/2026-06-30-v069-d1b-lint-options-tab-plan.md`.**
> NEXT ACTION = invoke **superpowers:subagent-driven-development** on that plan (NOT writing-plans -- the plan exists).
> Start Task 1 (`DRagLint.Lint.ConfigWriter` -- pure config serializer, console-testable T63). Tasks 2-3 = the
> `TLintOptionsFrame` VCL frame + dock wiring. **Task 4 BUILDS THE BPL and REQUIRES RAD Studio (`bds.exe`) CLOSED**
> (`_bpl_build.bat`; deploy via `deploy-staged.bat` -> `third_party\dll-win32`). Task 5 = the USER's manual in-IDE
> click-test checklist (agent cannot verify the UI). The plan embeds the full plugin-surface map (dock `AddTab` returns
> TTabSheet; mirror `OptionsFrame` TFrame pattern; `ProcRun.RunCaptureStdout`; OTAPI `GetActiveProjDir`; the two JSON
> shapes; the `.dpk` `contains` + `.dproj` `<DCCReference>` for BOTH new units). CAVEAT: the plan was written near a
> context ceiling -- Task 1 Step 3 (serializer body) + Task 2 Step 3 (frame render loop) are specified as algorithms,
> not line-by-line code; a fresh implementer has every integration fact but should flesh those two bodies (standard
> System.JSON + dynamic-VCL). ALSO at D1b: decide the D1a follow-up (index-only `undeclared-identifier` in the catalog?).
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 -- v0.69 D3 + D1a + D2a SHIPPED to `main`; NEXT = D2b then D1b
>
> **v0.69 D2a DONE + MERGED to `main`** (local `main`=`6cbce9d`->`6d6d1c5`; **NOT pushed/tagged**; `main` 13 commits ahead
> of origin). Two `drag-lint rename` subcommands packaging the existing `TRenameRefactoring` engine: **`rename --kind
> symbol --name <QName> --to <New>`** (index-driven cross-unit; dry-run default + `--json` + `--apply`; conflict guard =
> reserved word + sibling scope) + **`rename --kind param --file <F> --line <L> --col <C> --to <New>`** (NEW `BuildLocal`
> single-file AST routine-local rename = the param-name-prefix AUTOFIX, the user's #1 ask; conservative -- skips
> shadowing/qualified-members(exprDot+genericDot)/with). Subagent-driven (5 tasks, plan
> `docs/superpowers/plans/2026-06-30-v069-d2a-rename-refactor-plan.md`); a Task-1 opus review caught+FIXED a genericDot
> over-rename gap; OPUS whole-branch = READY TO MERGE, no over-rename path constructible, no Critical/Important. Tests:
> buildlocal **14/14**, rename-symbol **5/5**, rename-param **6/6**, lint **117/117**. ORM3 sanity: real param-rename
> dry-run correct + file unchanged. FOLLOW-UPS (non-blocking, in ledger): symbol-path inherits legacy name-global caller
> resolution (scope-filter later); BuildLocal `with`-block + overload-header under-rename (documented). **NEXT = D2b**
> (find-unit [uses-clause INSERT] + safe-delete [decl/body DELETE] -- NEW edit primitives beyond the replace-only Apply;
> own plan; FindSymbolsWithNoCallers/FindReferencesTo + declUses/declUsesUnit) -> then **D1b** (IDE "Lint Options" tab,
> MANUAL BPL gate). v0.69 publishes only after D2b + D1b.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 -- v0.69 D3 + D1a SHIPPED to `main`; NEXT = D1b (IDE Lint Options tab, MANUAL gate)
>
> **v0.69 D1a DONE + MERGED to `main`** (local `main`=`6cbce9d`, ff from `29f3be3`, **NOT pushed/tagged**). New command
> **`drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]`** = the single machine-readable catalog of every
> rule (built-in + external `.scm`). New unit `src/lint/DRagLint.Lint.RuleCatalog.pas` (in-code REGISTRY of ~62 built-ins
> + `.scm` sidecar-json merge -> `TRuleInfo{id,category,title,default_severity,default_enabled,source,params}` + summary
> counts); thin `DoRules` CLI handler (text + `--json`). Real output = **115 rules across 12 categories**. Subagent-driven
> (5 tasks, plan `docs/superpowers/plans/2026-06-30-v069-d1a-rules-catalog-plan.md`), each reviewed + OPUS whole-branch =
> READY TO MERGE, no Critical/Important (registry severities/thresholds cross-checked vs live code, zero mismatches).
> Tests: rulecatalog console **29/29**, rules-cli **11/11**, lint **117/117**, lintconfig **30/30**. FOLLOW-UP: decide at
> D1b whether index-only `check-ast` diagnostics (`undeclared-identifier`) belong in the catalog. **NEXT = D1b** (the IDE
> "Lint Options" dock tab CONSUMING `drag-lint rules --json` -- SEPARATE plan, **MANUAL BPL gate**: RAD Studio closed to
> build the BPL + a human click-test; not fully autonomous) -> then **D2** (refactor CLI). Ledger `.superpowers/sdd/progress.md`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 -- v0.69 D3 SHIPPED to `main`; NEXT = D1
>
> **v0.69 D3 DONE + MERGED to `main`** (local `main`=`d829b79`, fast-forward from `08f8e8f`, **NOT pushed/tagged** -- v0.69
> publishes only after D2). Two naming rules close MISSING-FEATURES #1: **`reserved-word-casing`** (info, ON -- non-lowercase
> Pascal keyword tokens; `True`/`False`/`nil` + symbol-ops exempt) + **`hungarian-or-short-identifier`** (info, OFF by default,
> `short_identifier_check=false` -- short/Hungarian param+local names; i/j/k/n/x/y exempt). 4 new `TNamingConfig` fields
> (`keyword_case`/`min_identifier_len`/`hungarian_prefixes`/`short_identifier_check`); per-fixture `.config.json` harness
> support (also covers `param-name-prefix` ON). Subagent-driven (plan `docs/superpowers/plans/2026-06-30-v069-d3-naming-rules-plan.md`),
> 6 commits, each task-reviewed + OPUS whole-branch review = **READY TO MERGE, no Critical/Important**. lint harness
> **117/117**, lintconfig **30/30**. ORM3 sanity: both rules 0 on real code (quiet by default, ideal). **VERSION still
> `0.68.0-alpha`** (D3 does not bump). Naming wave now **9 rules**; MISSING-FEATURES #1 = `[x]`. Ledger:
> `.superpowers/sdd/progress.md`. **NEXT = D1 (next deliverable) -> invoke writing-plans on the v0.69 spec section 1.**
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 (LATE) -- v0.68.0-alpha SHIPPED; v0.69 PLANNED + SPECCED, NEXT = IMPLEMENT (writing-plans)
>
> **Branch `main`**, working tree clean. **v0.68.0-alpha SHIPPED + RELEASED** (origin/main=`be67919`, tag
> `v0.68.0-alpha`, GitHub PRERELEASE win32+win64; lint harness **112/112**):
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.68.0-alpha . VERSION (`CLI.pas:6`) = `0.68.0-alpha`.
> 12 new rules built subagent-driven (plan `docs/superpowers/plans/2026-06-30-v068-naming-deadcode-plan.md`), each
> task-reviewed, opus whole-branch review = no Critical/Important: 7 NAMING (new `DRagLint.Diagnostics.NamingChecks`,
> config-driven via a `naming` block + `TNamingConfig`); 3 AST DEAD-CODE (new `DRagLint.Diagnostics.DeadCodeChecks`);
> 2 STORE-BACKED (extend `DRagLint.Lint.ProjectRules`). Naming=info, dead-code/data-flow=warning, all on by default
> EXCEPT `param-name-prefix` (ships OFF, `param_prefix=''` -- param conventions are project-specific).
>
> **FP-HARDENING wave (post-implementation, driven by REAL ORM3/DevExpress sanity -- the unit harness passed but
> real code was noisy; the "defaults=zero FP" design assumption did NOT hold):** relaxed T/F prefix (accept
> `TfrmMain`/`FfID` + DevExpress `Tdx`/`Tcx`), short-all-caps exemption (`OK`/`GLE`), skip published/event-handler
> methods + `Sender`-first params, PROPERTY-ACCESSOR exclusion for `unused-private-member` (parses declProp
> getter/setter -> **5747->957 on ORM3**), separator-robust `unit-name-matches-file`. DevExpress form 30 findings -> 0.
>
> **NEXT ACTION -- IMPLEMENT v0.69 (3 independent deliverables; each its OWN writing-plans plan; build order D3 -> D1 -> D2).**
> Spec (brainstormed + approved, ASCII): **`docs/superpowers/specs/2026-06-30-v069-settings-refactor-design.md`**.
> - **D3 [SHIPPED to main d829b79 -- see latest RESUME above]:** 2 naming rules in `NamingChecks` (extend `TNamingChecker.Check`,
>   same 4-site wiring + `naming` config): `reserved-word-casing` (info, ON -- non-lowercase Pascal keywords) +
>   `hungarian-or-short-identifier` (info, OFF by default -- short names + Hungarian prefixes; FP-prone). New `naming`
>   fields keyword_case / min_identifier_len / hungarian_prefixes / short_identifier_check.
> - **D1 (catalog + IDE tab):** new `drag-lint rules [--json]` = single rule catalog (in-code REGISTRY for built-ins +
>   the `.scm` jsons; emits id/category/severity/enabled/params + counts). Then a 4th IDE-dock tab "Lint Options"
>   (`DragLint.Plugin.DockForm.AddTab`; new `TLintOptionsFrame`): rules grouped by category, section tri-state + per-item
>   checkboxes + inline param editors -> reads/writes the active project `drag-lint-lint.json`. BPL manual-test gate.
> - **D2 (refactor CLI -- PACKAGING, engine EXISTS):** `src/refactor/DRagLint.Refactor.Rename.pas` already has
>   `TRenameRefactoring.Build/Apply/RenderDryRun` (+ `resolve-uses`, `TDeadCodeFinder`; current `rename --qname` wraps it).
>   Ship `rename --kind symbol` (cross-unit; harden overloads/qualified/DFM/keyword-conflict), `rename --kind param`
>   (NEW single-file routine-local builder `BuildLocal` = the `param-name-prefix` AUTOFIX, the user's #1 ask), `find-unit`
>   (add-to-uses via resolve-uses), `safe-delete` (verify 0 refs then delete). All dry-run preview + `--apply` (backups,
>   ANSI/CRLF). New `tests/refactor` DB-fixture harness.
> **DEFERRED -> MISSING-FEATURES section 13:** in-IDE Refactor tab + OTAPI apply (M); HARD refactorings (Change Params,
> Extract Method, Extract Interface/Superclass, Pull/Push, Declare/Introduce Var/Field).
> **REFERENCES for D2 + deferred:** Delphi 11/12 Refactor catalog + why it degraded -> `docs/lint/Comprehensive report on
> the refactor.md` + `.superpowers/sdd/delphi-refactor-research.md`; **Martin Fowler refactoring catalog
> https://refactoring.com/catalog/ (user-flagged 2026-06-30 -- canonical mechanics).** Feature memories:
> `feature-autofix-param-rename` (=D2 param-rename), `feature-naming-settings-presets` (=D1 tab + a future preset selector).
>
> **FOLLOW-UPS (non-blocking, logged in the SDD ledger `.superpowers/sdd/progress.md`):** `unused-private-member`
> intra-class-call residual FP + perf (cache `FindSymbolsByExactName` -- SLOW on the 64MB ORM3 index, 2-min timeout);
> `unused-unit-in-uses` operator/helper allow-list (`KSideEffectUnits`) is narrow; add a private-class-method
> `method-pascalcase` fixture + a nested-class `referenced-never-set` fixture. **SQL DDL index TODO** still open
> (grep-elimination wishlist `docs/superpowers/specs/2026-06-29-grep-elimination-indexer-wishlist.md` P2 item 9).
>
> **Gotchas (still apply):** `.pas`/`.dfm` strict 7-bit ASCII + CRLF (Edit/Write emit LF -> normalize before commit);
> NEVER put `}` or a nested `{` inside a `{ }` Pascal comment (real dcc64 error); a NEW unit needs BOTH the `.dpr`
> `uses ... in '..'` AND a `.dproj` `<DCCReference>`; new-unit build via the delphi-build skill (scratchpad bat +
> `Start-Process -Wait`); after a build that changed symbols, kill orphaned `drag-lint.exe`/`drag_lint_graph.exe`
> (they lock `third_party\dll-win64\drag-lint.exe` -> pack/deploy "used by another process").
>
> --- (history below) ---

> Last updated 2026-06-29 (handoff). **v0.65.1-alpha SHIPPED + RELEASED** (origin/main @ 0613e48,
> tag v0.65.1-alpha, GitHub PRERELEASE, harness **80/80**). Git clean + pushed. Since v0.63: v0.64.x
> robustness, v0.65.0 FP-8/FP-9 project-membership fixes, v0.65.1 = R2 IDE job queue + dock status bar
> + clickable lint Messages (double-click -> file:line) + float-equality & string-equality FP fixes
> (skip quoted non-alpha literal operands). Coverage gap doc: `docs/lint/MISSING-FEATURES.md`.
> **M1 COMPLETE 2026-06-29 (autonomous run) -- all 5 rules exact.** Resolver infra + all 5 rule upgrades
> on `main` (7 commits, harness 80/80 throughout): 9ffc642 P1 heritage (SCHEMA 11), ed65c22 P2
> type_ancestors + ResolveAncestry + IsDescendantOf/Implements + `query ancestors`, 63e8104 P3
> ResolveTypeCategory + skTypeAlias capture + `query typecat`, b4aafb5 P4-core (float-equality/
> freeandnil-on-interface/win64-pointer-cast store-aware), 7cda86e P4b virtual-method-in-constructor
> cross-unit (SCHEMA 12 is_virtual + GetVirtualMethodsIncludingAncestors), a04e5a2 P4b string-equality
> precise store path, 0bc26b1 docs. Tests: `tests/heritage/run_all_m1_tests.ps1` (33 assertions, green).
> **Real-code proof:** CLI.pas string-equality 285 (heuristic) -> 30 (resolver), ~90% FP cut. Full status:
> `docs/superpowers/plans/2026-06-29-m1-type-resolver-plan.md` (STATUS at bottom).
> **NOT YET CUT as a release** (VERSION still 0.65.1) -- user wants M1+M2 bundled (or cut standalone v0.66).
> **DEFERRED (not M1 blockers):** cross-DB library-ancestry bridge (needs lib DBs reindexed to v12; low
> marginal value for the 5 rules since RTL types are intrinsics/I-prefixed -- belongs with Wave D) + ORM3
> full before/after (needs ORM3 reindex). Design recorded in the plan's Phase 5.
> **M2 DESIGN DONE 2026-06-29 (spec ae02d57, user-approved).** The data-flow/CFG/def-use engine is fully
> designed: `docs/superpowers/specs/2026-06-29-m2-dataflow-cfg-engine-design.md`. Decisions: intraprocedural
> CFG engine + interprocedural object-leak in ONE milestone; full monotone dataflow-lattice framework;
> 4 check families (definite-assignment: used-before-assignment / function-result-not-set / out-param-not-set;
> liveness: overwrite-before-read / write-only-local; loop-var-after-loop; object-leak); FP stance
> definite=warning / possible=info, opaque @var/var/out calls = possible assignment; managed types skipped
> (W1036), exact via M1 ResolveTypeCategory when store present. Units: DRagLint.Analysis.Cfg -> .DataFlow ->
> .Flow.Lattices -> Diagnostics.FlowChecks; intra checks need NO store (standard tests/lint harness).
> **RESUME -> invoke the writing-plans skill** on that spec to produce the staged implementation plan, then
> build **stage 1 (CFG builder + tests/flowengine unit tests)** per spec section 10. Confirm tree-sitter
> control-flow node kinds (while/for/repeat/case/try/kFinally/kExcept/Break/Continue) against real parses
> first (grep the fixture, never trust assumed names).
> **#12 Ergonomics** (SARIF, quick-fixes/autofix, baseline file, severity profiles) = the release AFTER
> M1+M2. Each phase: fixture -> green harness -> Win64 build -> commit. Keep tests/lint/run_lint_tests.ps1 green.
> **Pending (not in a tagged release after v0.65.1):** float-equality fix + string-equality non-alpha
> guard are on main (commits c869073, d845976) -- fold into v0.67 or cut a quick v0.65.2.
> **Stale branches** v0.22..v0.35 etc. are old dev branches (no pending work) -- deletable.
> **IDE build gotchas:** any BPL change needs RAD Studio CLOSED (bpl lock) + a manual test cycle; a VCL
> control must NOT read ClientHeight/Width (or any handle-bound prop) in its ctor before being parented
> (forces CreateWnd -> "control has no parent window") -- lay out in a Resize override.
> **Roadmap (the through-line):** `docs/superpowers/specs/2026-06-28-lint-completeness-roadmap-design.md`
> -- R1 robustness -> R2 IDE job queue -> M1 type resolver (early) -> Waves A-E (no-resolver rules,
> naming on-by-default, metrics/CK, type-dependent, cross-call-graph frontier). Decisions: serialize
> heavy IDE jobs (keep LSP live), build type resolver EARLY, naming ON by default, FP policy = when
> unsure don't report but keep the rule.
> Companion research: [REPORT-1-delphi-lint-landscape.md](REPORT-1-delphi-lint-landscape.md) (the field),
> [REPORT-2-draglint-implementation-plan.md](REPORT-2-draglint-implementation-plan.md) (original waves).
> Last lint-all ORM3 report: `C:\Projects\DB\ORM3\lint-report-20260628-122356.txt`.
> This file = what is DONE, how to resume, and what is NOT done yet (ideas/plans).

---

## 1. Status (what shipped)

**10 GitHub releases, v0.47.0-alpha .. v0.56.0-alpha (each "Latest"), all on `main`.** ~53 distinct
lint rule ids. Harness `tests/lint/run_lint_tests.ps1` = **51 fixtures green**; `selftest unused-locals`
PASS. Win64+Win32 zips bundle the `rules/` folder + `INSTALL.md` (self-contained).

Categories covered: bug-patterns (empty/bare except, raise-bare/reraise/raise-in-finally,
off-by-one, not-in/not-comparison precedence, comparison-same-operands, division-by-zero,
self-assignment, code-after-exit, nil/boolean/classname compares, redundant-not-not, empty-conditional/
loop/case), resource+lifetime (unprotected-object-free, use-after-free, freeandnil-on-interface,
missing-inherited-ctor/dtor, control-flow-in-finally, **interface-reference-cycle** ARC),
concurrency (**ui-access-in-thread**), security (sql-injection-concat, hardcoded credential/
connection-string/ip/path), platform (win64-pointer-cast, locale-sensitive-conversion, float-equality
incl. TDateTime, gettickcount-wraparound, inline-assembly), complexity/structure (too-many-parameters/
locals, method-too-long, deep-nesting, god-class, public-field, with-multiple-items, **layering-violation**
config-driven, unused-public-symbol), FireDAC (firedac-open-execsql-mismatch), plus assert-call,
uppercase-compare, outputdebugstring, length-zero-compare, magic numbers, etc.

Infra: `// drag-lint:ignore [rule...]` suppression; `lint --disable id1,id2`; `lint --rules-dir <dir>`;
`lint-project --db <idx> [--layers <json>]` (project-wide rules); bundled `rules/`; `build/pack-lint-release.ps1`.

---

## 2. Resume point (start here next session)

- Repo `C:\Projects\Delphi-RAG-lint`, branch **`main`** (single branch; the feature branch was merged + deleted).
- **Two rule engines:** (A) external `.scm`+`.json` in `rules\` (hot-loaded, no recompile); (B) Pascal
  built-ins in `src\diagnostics\DRagLint.Diagnostics.AstChecks.pas` (class `TAstChecker`) + project-wide
  rules in `src\lint\DRagLint.Lint.ProjectRules.pas`.
- **Add a `.scm` rule:** drop `rules\<id>.scm` + `<id>.json`; add `tests\lint\<id>.pas` + `<id>.expected`;
  run `pwsh tests\lint\run_lint_tests.ps1`. No rebuild.
- **Add a built-in:** new `class function TAstChecker.CheckXxx(const AFile): TArray<TLintFinding>` (copy an
  existing one's parse boilerplate); wire one line in `DoLint` (CLI ~line 3979+) + add the id to the
  `--rule` allow-list (CLI, the `unknown rule` guard) + its message; add a `tests\lint` fixture; rebuild.
- **Add a project rule:** extend `TProjectLintRules` (Store-based) or call a `TAstChecker` file-list fn
  from `DoLintProject`; test via `tests\lint-project\` (index a fixture, run `lint-project --db`).
- **Build (Win64 Release):** `build\pack-lint-release.ps1 -Version X` builds win64+win32, deploys the win64
  exe to `third_party\dll-win64`, and zips with `rules\`. (Or plain msbuild; ~7s.)
- **Release:** bump `VERSION` const (CLI.pas line 6), CHANGELOG top entry, `rules\README.md`; commit; push;
  `git tag vX` ; `gh release create vX --repo Alexl-git/Delphi-RAG-Lint --latest --notes-file ... <zips>`.
- **CRITICAL gotchas:** Edit/Write emit LF -> **normalize touched `.pas` to CRLF** before commit
  (`(t -replace "\r\n","\n") -replace "\n","\r\n"`, UTF8-no-BOM); strict 7-bit ASCII; DocInsight `///` on
  new public decls. A NEW unit must be added to BOTH the `.dpr` `uses ... in '..'` AND the `.dproj`
  `<DCCReference>` (the .dpr uses is what the compiler resolves; missing it = F2613). The canonical
  `third_party\dll-win64\drag-lint.exe` is gitignored (ships via release zip, not git).
- **tree-sitter node kinds:** discover via `C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse <f>`.
  Key: a NO-paren call (`X.Open`, `GetTickCount`) is `exprDot`/`identifier`, NOT `exprCall`; anon method =
  `lambda`; `if`(no else) vs `ifElse`; `TFoo.Create` no-paren = `exprDot`. `.` anchors work for concrete
  node kinds but an anchored `(_)` wildcard does NOT constrain child count.

---

## 3. Big-ticket NOT done: a cross-unit type resolver

The single largest remaining investment. Several shipped rules are HEURISTIC because there is no real
type resolution: `float-equality-comparison`, `win64-pointer-cast`, `freeandnil-on-interface` use a
flat per-file name->type map (string prefixes), and `interface-reference-cycle` uses the I-prefix
convention. A resolver would make them EXACT and unlock new precise rules.

**Plan (multi-step, each could be its own release):**
1. Expose a symbol's resolved declared type from the index (the `symbols` table has `signature`; the
   `unit_uses` graph gives scope). Add an `ISymbolStore` query: given a unit + identifier, return its
   declared type, and given a type name, return its kind (class/interface/enum/record/alias) + ancestry.
2. Build a per-routine scope chain (locals -> params -> fields -> unit-level -> used-units) so an
   identifier resolves to a symbol -> type. (Today's flat map ignores scope/shadowing.)
3. Resolve type ancestry (class parent chain, implemented interfaces) cross-unit -> makes
   interface-reference-cycle exact (no I-prefix guess) and enables `non-linear-cast` (hard cast between
   unrelated classes), `redundant-cast` (X already that type), exact Ansi/Unicode lossy cast.
4. Rewrite the heuristic rules to use the resolver; add the new exact rules above + `exhaustive-enum-case`
   (case over an enum missing values -- needs enum member count), `stringlist-duplicates-unsorted`,
   `format-argument-type-mismatch`.

This is infrastructure first; budget it as a milestone, not a single rule.

---

## 4. Rule-idea backlog (no type resolver needed -- "more small batches")

Detectable from AST / index today; pick batches of these:

- **FireDAC:** `parambyname-in-loop` (extend the existing `field-by-name-in-loop` walk to `.ParamByName`);
  `dataset-open-without-close` (Open/Connected:=True without try-finally Close -- flow-ish);
  `query-created-without-owner-never-freed` (flow); `fetchall-on-large` (low signal).
- **Resource:** `stream-not-freed` / `criticalsection-not-released` / `file-not-closed` (Enter/Leave,
  FileOpen/CloseFile pairing per routine, like CheckUnprotectedFree); `double-free` (X.Free twice).
- **Security:** `unsanitized-shellexecute` (ShellExecute/CreateProcess/WinExec with a non-literal arg);
  `weak-random-for-security` (Random near token/password identifiers); `unsafe-string-api`
  (StrCopy/StrCat/StrPCopy -- unbounded); `path-traversal` (file API with concatenated path var).
- **Control-flow / expr:** `constant-condition` (`if True`/`while False`); `loop-executes-at-most-once`
  (unconditional Exit/Break/raise in a loop body); `ifthen-both-branches` (SysUtils.IfThen evaluates both
  args -- a pitfall); `assignment-result-ignored` (function called as a statement).
- **Maintainability:** `commented-out-code` (comment that parses as Pascal -- info, FP-prone);
  `duplicated-code` / clones (token-hash across impl ranges); `magic-string`; `multiple-statements-per-line`
  (needs same-line sibling detection -> built-in).
- **Metrics:** `cyclomatic-complexity` / `cognitive-complexity` (count decision points incl. and/or in a
  routine body -- verify `kAnd`/`kOr` node names first); `too-many-nested-routines`; `too-many-exit-points`.
- **Platform:** `pchar-arithmetic`; `variant-record-type-punning`; `deprecated-rtl-function` (StrCopy, Str/Val,
  GetMem-without-FreeMem); `sizeof-pointer-assumption` (`SizeOf(Pointer) = 4`).
- **Naming (low-FP subset already partly covered):** `field-not-f-prefixed`, `class-not-t-prefixed`,
  `interface-not-i-prefixed`, `exception-not-e-prefixed`, `param-prefix`, `unit-name-mismatch-file`
  (needs unit name vs filename) -- ship OFF-by-default or as a separate "conventions" profile to avoid noise.

---

## 5. Infra / UX backlog (high adoption value)

- **SARIF output** (`--format sarif`) for GitHub code-scanning / CI. (JSON + text exist.)
- **Per-`.scm` enable/disable**: honor `"enabled": false` in each `.json` + `--enable <id>` (today only
  `--disable` exists; `.scm` rules otherwise always run). Lets naming/style rules ship off-by-default.
- **Persistent config file** `drag-lint-lint.json` (CWD): `{ "disabled":[...], "enabled":[...],
  "thresholds": { "too-many-parameters": 7, ... }, "severity": { "<id>":"warning" } }`. Today thresholds
  are hardcoded conservative defaults; `--disable` is per-run only.
- **IDE-plugin deploy of `rules\`**: confirm the OTAPI plugin ships/points `rules\` beside the spawned exe
  (or passes `--rules-dir`); otherwise `.scm` rules are dormant in the IDE.
- **Quick-fixes / autofix** (the SonarDelphi/DelphiLint differentiator): e.g. `Assigned(X)` for `X <> nil`,
  remove redundant `as TObject`, `- 1` for off-by-one, `SameText` for uppercase-compare.
- **Baseline / suppression file** (ignore the existing N findings; only flag new ones) for adoption on
  large legacy codebases.
- **CI exit-code policy** by severity (fail build on `error`/`warning` but not `info`).
- **A unified test runner** that also exercises the `lint-project` rules (index a fixture + assert) -- today
  those are manual (`tests/lint-project/README.md`).
- **Read-only opens for the analytical read-verb family (v0.86 fast-follow).** v0.86 (D4) made the 6 SPEC-named
  read verbs open read-only via `PRAGMA query_only=ON` (outline/query*/find-unit/surface/context/dump-refs), which
  kills the DDL-on-read / win32 FTS5-trigger-drop for them. But ~11 other PURE-READ analytical verbs still use
  `Create + Migrate` (write path) and would re-run Migrate's FTS5-probe/DROP-TRIGGER if invoked with a **win32** exe
  against a shared DB: `resolve-uses` (CLI.pas:2072), `hover` (:3819), `impact` (:3988), `usages` (:4240), `slice`
  (:4328), `bench-context` (:5115), `uses-report` (:5321), `typeat` (:5655), `cycles` (:7179), `uses-audit` (:7553),
  and `generate-docs` (:5687 -- redundant write open; it also opens a read-only store at :5712). NOT a v0.86 blocker:
  the spec scoped read-only to exactly the 6 verbs, and the IDE win32-exe vector is closed by the T1 Win64-default
  resolver -- these only regress on a MANUAL `win32 drag-lint hover` against a shared DB. Fix: audit each verb's store
  usage (read-method only) then switch to `OpenReadOnlyStore`; `generate-docs`/`check-unit` have conditional store use
  -- verify before flipping. Completes the "kills DDL-on-read" guarantee for the whole read surface. (Whole-branch
  review finding, v0.86 final review 2026-07-05.)

---

## 6. forms-csv + indexing backlog (new 2026-06-26d)

These items were added by the user after the forms-csv false-DEAD investigation concluded.
Priority order: 1 -> 2 -> 3 -> 4 -> 5 -> 6.

### 6.1 hg post-commit auto-reindex hook (ORM3 repo) -- DONE 2026-06-26

**Status: IMPLEMENTED.** User-level hook fires for all ORM3 sub-repos.

**Files delivered:**
- `C:\Users\alexanderl\mercurial.ini` -- added `[hooks] post-commit.orm3reindex = python:...`
- `C:\Users\alexanderl\hg-hooks\orm3_reindex.py` -- Python hook; checks `repo.root` contains
  `ORM3`; spawns `drag-lint index C:\Projects\DB\ORM3 --db C:\Projects\DB\ORM3\drag-lint.sqlite`
  as a background process (CREATE_NO_WINDOW); logs to `C:\Users\alexanderl\hg-hooks\orm3_reindex.log`.

**Verify:** commit any .pas in CLIENT/COMMON/SERVER/PACKAGE/tools, then:
  `Get-Content C:\Users\alexanderl\hg-hooks\orm3_reindex.log`

### 6.2 GridLayout: "popup on grid" note in forms-csv

**Problem:** GridLayout (frmGridLayout, C:\Projects\DB\ORM3\CLIENT\GridLayout.pas) appears
as "DEAD FORM - no callers found" in forms-csv because it is NOT launched by a form-to-form
call. It is launched by the `TGridMenuPopup` component embedded in many forms, for Save
Layout As / Load Layout functionality.

**Fix:** Hard-code a special note for GridLayout in `DRagLint.FormsMap.pas` or use a
"known popup forms" table. The note should say something like: "popup on grid (TGridMenuPopup
Save/Load Layout)" in the Notes column instead of "DEAD FORM".

**Alternative:** Detect `TGridMenuPopup` as a call site in BuildEdges -- query for refs to
frmGridLayout from TGridMenuPopup and emit an edge like "TGridMenuPopup (Save Layout As)".

**File:** src/forms/DRagLint.FormsMap.pas

### 6.3 Two-DB indexing model (Platform + Project) -- DONE v0.60.0-alpha 2026-06-26

**User request:** "For indexing let's use 2 libraries:
1. Platform -- Delphi Library and browsing path for the given platform selected for the
   current project (changes when platform changes)
2. Project -- All project members compiled and scanned as forms, pas, Inc, etc...
By default drag-lint should be working with these 2 SQLite DBs."

**Spec:** `docs/superpowers/specs/2026-06-26-two-db-model-design.md` (committed ee10b25)
**Plan:** `docs/superpowers/plans/2026-06-26-two-db-model.md` (committed a04f24a) -- 4 tasks ALL DONE
**Commits:** cda2876 (CLI platform detect), 4ab9018 (plugin), 65da564 (index auto-DB), 92576bc (release)

**Design (approved 2026-06-26):**
- Platform DB: one DB per target platform (Win32/Win64) covering Delphi RTL + VCL +
  DevExpress (all dirs on the IDE's Library Path and Browse Path for that platform).
  Already partially exists as `C:\Projects\.drag-lint\library-Win32.sqlite` /
  `library-Win64.sqlite` -- needs to become the canonical "Platform" DB.
- Project DB: covers all units in the project's .dpr/.dproj (including COMMON/OBJECTS,
  not just CLIENT). Already exists as `C:\Projects\DB\ORM3\drag-lint.sqlite`.
- CLI consumers (query, lint, forms-csv) would auto-load both when no --db given;
  `resolve-dbs --platform <p>` already does something similar via the manifest.
- Model change: manifest `indexes` array -> tag each DB as `platform` or `project`; CLI
  resolves by platform tag + project working dir.

### 6.4 Unit-membership lint rule

**User request:** "Lint function -- checks all used units if they do not belong to the
Platform they must be in the project folder and must be member of both dpr and dproj.
If not there should be a warning about it."

**Implementation (not yet started):**
- Walk all units in the Project DB; for each unit's `unit_uses` entries, check if the
  used unit is in the Platform DB OR (exists in the project folder AND is listed in
  both the .dpr uses clause AND the .dproj DCCReference list).
- Report warning: `unit-not-in-project` (used unit not in Platform DB and not in .dpr/.dproj).
- Requires parsing .dpr and .dproj to enumerate listed units -- .dpr `uses..in` clauses
  and .dproj `<DCCReference Include="...">` elements.
- Can be a `lint-project` rule (Store-based, operates on the whole index + project files).

### 6.5 Form global-variable lint rule

**User request:** "Forms often have global variables with the same name associated with
them. I think we should comment this all out and report as a warning. The use of these
may cause 2 different forms creating 2 TForm and saving it in the same variable causing a leak."

**Background:** VCL's auto-generated unit-level global `var Form1: TForm1;` -- if two
instances are created (ShowModal twice, or Show + ShowModal), the second overwrites the
global pointer and the first leaks (no reference to Free it).

**Implementation (not yet started):**
- Detect unit-level variable declarations where:
  (a) The variable type is a class that descends from TForm (or TCustomForm)
  (b) The variable name matches the class name minus the `frm`/`T` prefix convention
- Report as `global-form-variable` warning with message:
  "Global form variable '<name>' may leak if the form is created more than once.
   Consider removing the global and creating/freeing the form locally."
- Can be a `.scm` rule or a built-in in TAstChecker.
- For the "comment out" part: this would be an autofix suggestion (future; not in scope now).

### 6.6 Batch lint runner

**User request:** "There should be a function to run Lint over all project members.
The output should be captured in some place that AI or user can read and AI can action upon it."

**Background:** `lint-project --db <idx>` already runs project-wide rules; `lint <file>` runs
per-file rules. What's missing is a single command that runs all rules over all project
members and captures the consolidated output.

**Implementation (not yet started):**
- `drag-lint lint-all --project <dproj> --db <db> --out <report.txt|json|sarif>`:
  (a) enumerate all .pas units in the .dproj
  (b) run `lint` on each file (all per-file rules)
  (c) run `lint-project` rules against the full index
  (d) aggregate findings, deduplicate, sort by severity then file
  (e) write to --out (default: `<project-dir>\docs\lint-report-<date>.txt`)
- Output format should be AI-friendly: structured JSON with file, line, rule id, message.
  Also a human summary (counts by severity/rule).
- The AI can then read the report and action on the highest-severity items.
- Relates to 6.3 (2-DB model): batch runner should auto-load Platform + Project DBs.

### 6.x forms-csv v4 fast-follows (filed 2026-07-05, post-v0.87 ship)

v0.87 shipped forms-csv v4 (interface-dispatch + hook navigation). The whole-branch review
cleared it Ready-to-merge; the schema-footer Minor was bundled into the release. These
remain as low-priority fast-follows (none affects shipped navigation correctness):

- **Regression-guard the Layer 0 guardrail + the `@Routine` hook form.** Both are verified
  only OUT-OF-BAND (the formsmap harness pipes forms-csv stderr to `Out-Null`, and the v4
  fixture uses the bare `Field := Routine` hook form). Add: (a) a 2nd hook-registration
  fixture unit exercising `PlanHook := @ShowThing4` (the address-of idiom the real ORM3 tree
  may use), and (b) a harness assertion that captures forms-csv stderr and checks the
  guardrail note fires N=<expected> on a bodies-absent index. Higher-value of the two = the
  `@`-form fixture (that path touches real navigation output; a regression would silently
  drop an edge). `ParseHookAssign` already strips one leading `@` (v0.87); this just guards it.
- **`BuildHookMap` Pass A micro-optimization (optional).** Pass A is
  `O(files x lines x ANodes)` -- bounded in practice (PasLines cached; the full 66 MB ORM3 db
  runs in 12.6 s), so this is a nice-to-have. Early-out lines without a `.Create`/`CreateForm`
  token before the per-node `IsLaunchLine` loop.
- **Layer 0 delivery (invocation, not algorithm) -- carried from 6.x:** the IDE forms-csv
  menu should pass a COMMON-inclusive (full-tree) db so the plan-editor family resolves in
  the IDE, not just from the CLI against the full ORM3 db. (Plugin invocation change.)
- **D5 indexer milestone (schema bump, separate brainstorm->spec->plan):** receiver-type on
  call refs (`receiver_type_symbol_id`) + proc-variable-assignment refs (`kind='proc-assign'`)
  + interface-implementation method edges (`impl_of`). Removes L2's text-scan and makes
  polymorphic dispatch precise (benefits find-callers / impact / graph too). Spec D5 has the
  rationale.
  **>>> NOW DOUBLY-MOTIVATED + USER CHOSE THIS as the AutoDocument Called-from fix (2026-07-06).**
  BUG FOUND via real "Document it" use: the AutoDocument **Called-from facts are NAME-BASED and
  produce FALSE callers for common method names** (Run/Execute/Create/Add...). `document --qname
  DRagLint.CLI.Run` listed DoFbSnapshot/DoLinkOrm/DoLintAll/DoCompileCheck/DoGhostCheck as callers
  -- but those call DIFFERENT `Run`s (TFbSnapshot.Run, TOrmLinker.Run, TCompileChecker.Run, ...).
  ROOT CAUSE: `TDocFactsBuilder.Build` (src/doc/DRagLint.Doc.Facts.pas:244 + :312 for Used-in)
  calls `FindCallersByName(LastSeg(qname))` -> `SELECT * FROM refs WHERE name_text = 'Run'` matches
  EVERY ref to the name across the corpus (query --name Run shows ~13 DISTINCT symbols named Run).
  This VIOLATES the feature's "every fact is ground-truth" promise -- confidently-wrong facts, worst
  for exactly the common names people document most. VERIFIED refs are NOT resolved to the target
  symbol_id (find-callers --name Run is equally noisy; dump-refs shows callee side name-only).
  THE FIX (user-chosen 2026-07-06 = "resolve refs to symbol_id at index time, proper fix"): D5's
  receiver-type resolution lets AutoDocument switch Called-from from `FindCallersByName(name)` to
  `FindReferencesTo(symbolId)` (that store method ALREADY EXISTS, Interfaces.pas:76) for precise,
  target-specific callers. So D5 now serves BOTH forms-csv (L2 removal) AND AutoDocument (correct
  Called-from) -- stronger case to prioritize. When D5 lands, ALSO update Doc.Facts:244/:312 +
  add a run_doc harness asserting a common-name symbol (e.g. a fixture with two same-named methods)
  lists ONLY its real callers. INTERIM (if D5 is far off): consider labeling the fact "Referenced by
  (by name)" so it doesn't read as ground-truth -- but the user chose the proper fix, so interim is
  optional. This is NOT a v0.90.x quick patch; it's the D5 chunk (own brainstorm->spec->plan->SDD).

---

## 7. IDE plugin -- lint-all menu command (target v0.63)

**User request (2026-06-28):** "Create code that would generate such a report after
parsing all .dpr/.dproj that I could invoke in the drag-lint menu in the IDE."

**Goal:** A single IDE menu item "Run Lint All (Full Report)" that:
1. Reads the currently-active project path from the IDE via OTAPI
   (`(BorlandIDEServices as IOTAProjectManager).GetCurrentProject.FileName`)
2. Resolves the two-DB pair (Platform + Project) via the manifest / `resolve-dbs`
   logic already in the CLI -- or just hard-codes the manifest path for now.
3. Spawns `drag-lint lint-all --project <active.dproj> --db <project.sqlite>` as a
   background process (non-blocking -- the IDE must not freeze).
4. Writes the report to `<project-dir>\docs\lint-report-<date>.txt`.
5. On completion, opens the report file in the IDE's default editor
   (`(BorlandIDEServices as IOTAFileSystem).OpenFile(reportPath)` or `ShellExecute`
   to notepad if the IDE file system API is unavailable).
6. Shows a brief status in the IDE's message view: "Lint-all complete: N findings
   (E errors, W warnings) -- report: <path>".

**Implementation notes:**
- The wizard already has a toolbar/menu integration point (`TDragLintWizard`,
  `dclDragLintWizard.bpl`). Add a new `TAction` / `TMenuItem` entry there.
- Background process: use `TProcess` or `CreateProcess` + a `TThread` that waits on
  the process handle and posts completion back to the main thread via
  `TThread.Synchronize` (same pattern as existing index-on-save).
- Requires BPL rebuild and re-deploy (`build\pack-lint-release.ps1`).
- Must work even when the IDE currently has no project open (disable the menu item
  in that case via `OnUpdate`).

**Design doc:** `docs/superpowers/specs/2026-06-28-new-lint-rules-v062-v063-design.md`
(see section 8 -- IDE lint-all menu).

---

## 8. Pointers

- Rule list (user-facing): `rules/README.md`. Per-file harness: `tests/lint/`. Project-rule fixtures:
  `tests/lint-project/`. Release script: `build/pack-lint-release.ps1`.
- The two research reports (landscape + plan) sit beside this file in `docs/lint/`.
