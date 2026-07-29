# Converter Editor -- STATUS / resume

**Branch:** `feat/converter-editor` (worktree `C:\Projects\Delphi-RAG-lint-converter`,
from `main@cf372f8`). **UNPUSHED** -- user holds push. Working tree: `sample.rules`
has the user's live TabcToggleBtn->TcxButton test data (229 lines) -- do NOT revert it.

Design: `docs/converter/2026-07-20-converter-editor-unit-replacement-design.md`
Plan:   `docs/converter/2026-07-20-converter-editor-unit-replacement-plan.md`

## NEXT ACTION (2026-07-29)

**Implement `docs/superpowers/plans/2026-07-29-proptree-ancestor-scope.md` on branch `main`, in a
FRESH worktree** (`main` = `674706a`). Spec:
`docs/superpowers/specs/2026-07-29-proptree-ancestor-scope-design.md`.

This is the fix that makes `Name`, `Tag`, `Left`, `Top` assignable -- see "Why `Name`/`Tag` cannot
be assigned" below for the measured root cause. Do the work on `main`, NOT on
`feat/converter-editor`, and NEVER in `C:\Projects\Delphi-RAG-lint` (another team's checkout, on
`feat/autodoc-phase3`, ~44 dirty files).

Order of business next session:

1. Create a worktree of `main` and run the plan's Task 1 -- capture the baseline leaf counts
   BEFORE changing anything, because criteria 10-11 are regression guards on chains that work today.
2. Tasks 2-5 as written. The query-time fallback (Task 3) is the one that pays off immediately:
   it repairs indexes already on disk, with no re-index, which matters because a full library
   rebuild currently aborts.
3. Then rebuild the editor on `feat/converter-editor` and confirm in the GUI that the To pool
   finally offers `Name`/`Tag`/`Left`/`Top` for `cxButtons.TcxButton`.

## LATEST -- resume here (2026-07-28b): Examine + grid search shipped; two engine INBOX notes filed

Three things landed after the curation merge, all on `feat/converter-editor`, all UNPUSHED.
Suite **340 pass / 0 fail / 0 skip**; both exes build clean; the editor is deployed at
`third_party\dll-win64\ConvRulesEditor.exe` (2026-07-28 18:06).

**Launch it pinned to the healthy index** -- the default "Both" unions in the broken 9.1 MB
Win32 fragment and silently truncates the From list:

```
third_party\dll-win64\ConvRulesEditor.exe --from-platform win64
```

### 1. From/To search boxes above the grid (`29f6386`)

Two filter boxes with Clear buttons, mirroring the pool search: filter by From, by To, or both
as AND, with a matched/total count so a filtered grid never silently looks short. Verified live,
including Assign under an active filter -- safe because every grid handler reads the selected
row's cell TEXT rather than indexing into the leaf array.

### 2. Examine (spec F, `da6b320`..`442e064`, 6 commits)

Pick any set of `.dfm`/`.pas` files; the grid paints green every From property those files
actually use. On the real `ORM3\CLIENT\VARINSP.dfm`: *"Examined 1 file(s): 21 of 299 From
properties used"*, with `Left`, `Top`, `Width`, `Height`, `GroupIndex`, `Caption`, `Images`,
`Layout`, `Picture` green out of 299 rows. That is the point of the feature -- a `TabcToggleBtn`
exposes 3905 proptree leaves and a real form assigns nine.

Spec: `docs/superpowers/specs/2026-07-28-examine-used-properties-design.md`.
Plan: `docs/superpowers/plans/2026-07-28-examine-used-properties.md`.
Logic lives in the pure, headless `ConvRules.Usage.pas`; the form only picks files, calls
`ComputeUsage`, and paints.

**User rulings recorded in the spec:** DFM and PAS are unioned into ONE green; PAS matching is
deliberately LOOSE (any `.PropName` occurrence counts, so another component's `.Caption` marks
`Caption` used -- accepted to catch `with` blocks and typed locals); used properties with no
grid row are reported rather than dropped.

**Two real bugs the reviews caught**, both fixed with RED evidence: the `<...>`/`(...)` skip
cleared on a terminator sitting inside a quoted DFM literal (`Caption = 'Y > Z'`), after which a
mid-list `end` popped the block stack and later properties were silently dropped -- UNDER-reporting,
the one failure mode this design must not have; and `ScanPasText` ran a full-text scan per
candidate (~7810 of them), now a single token-harvest pass.

### 3. Two engine INBOX notes filed (copies in BOTH checkouts)

- `INBOX-index-all-win32-library-rebuild-aborts.md` -- five runs, three launch methods, all dead
  mid-write at exit -1. Disk ruled out (151 GB free). Run 5's last line is the `DIAG:` for a file
  that had just reported a parse error.
- `INBOX-proptree-ancestor-climb-stops-early.md` -- **this is the one that blocks mapping.**

### Why `Name`/`Tag` cannot be assigned (diagnosed, engine-side)

The FROM side is fine: `Abcbtn.TabcToggleBtn` climbs to `TComponent` and returns `Name`, `Tag`,
`Left`, `Top`, `Width`, `Height`, `Visible`, `Hint`. The **TO** side truncates:
`cxButtons.TcxButton` stops at `TcxCustomButton`. So there is a `Name` row with nothing to map it
to. A cross-unit ancestor hop only works when the ancestor name is globally unique --
`TWinControl` exists in both `Vcl.Controls` and `FMX.Controls.Win`, so nearly all of VCL truncates,
while `TGraphicControl` is unique, which is the only reason the ABC5 chain works. Plain
`Vcl.StdCtrls.TEdit` fails identically, so this is not a DevExpress problem. A project form
(`uMain.TfrmMAIN`) with both databases climbs ZERO levels.

Until that is fixed, Examine still marks the From rows correctly; what is missing is a To target.

## PREVIOUS (2026-07-28): spec E IMPLEMENTED, all 8 tasks + final review DONE

**MERGED INTO `main` (local only, nothing pushed).** `main` is now **`87a9d3c`**:
`4536c20` is the merge of `feat/converter-editor`, `87a9d3c` a follow-up test fix.
Suite on the merged result: **296 pass / 0 fail / 0 skip**; both exes `BUILD_EXITCODE=0`;
proptree autotest 20/0, convert-rules autotest 26/0.

`feat/converter-editor` (`01354e8..3949ec3`, 14 curation commits) was **deliberately NOT
deleted** — it is checked out in this worktree, which still holds a third workstream's 15
uncommitted files.

### The merge resolved the owed `f65fb9c` cherry-pick

Merging conflicted in two ENGINE files, `src/cli/DRagLint.CLI.pas` and
`src/report/DRagLint.Convert.PropTree.pas` — nothing to do with curation. This branch had been
carrying `f65fb9c` (`proptree --refs-as-leaves`) while `main` advanced **74 commits** on the same
code (proptree/2, `--min-visibility`). The 14 curation commits themselves had **zero** file
overlap with main. Both conflicts were resolved KEEP-BOTH, so main now has proptree/2 *and* the
ref-leaf flag, and they compose: `cxButtons.TcxButton` goes 11074 -> 7748 leaves with
`--refs-as-leaves`, and 592 -> 404 when combined with `--min-visibility published`.

The merge was done in a THROWAWAY worktree, never by checking out `main` in
`C:\Projects\Delphi-RAG-lint` — that checkout is on `feat/autodoc-phase3` with 33 dirty files of
the engine team's in-flight work, and switching it would have disrupted them.

**FIXED in `674706a`** (was: `TreatRefsAsLeaves` read uninitialised). `TPropTreeOptions` has only
unmanaged fields, so a local is genuine stack garbage in Delphi -- nothing zeroes it -- and
`BuildPropTree` reads that field (`DRagLint.Convert.PropTree.pas:824`) to decide whether a
TComponent-typed property is emitted as a reference LEAF or recursed into. Six construction
sites existed; five set only `Depth` + `ToPersistent`: `DoConvertValidate`, `DoConvertReemit`,
`DoConvertScaffold`, `DoConvertApply` (all `DRagLint.CLI.pas`) and `BuildApplyPlan`
(`DRagLint.Convert.Apply.pas:994` -- confirmed as the fifth). So those verbs could enumerate a
different property surface run to run.

Fix: `Opts := Default(TPropTreeOptions);` at every site, which also protects the next field
somebody adds to the record, plus a `<remarks>` on the record stating the invariant.
**No behaviour change beyond removing the nondeterminism** -- the convert verbs now
deterministically get the documented default `False`, and only the `proptree` verb sets the
field from `--refs-as-leaves`. proptree autotest 20/0 and convert-rules autotest 26/0, both
unchanged.

**Worth knowing:** the fixtures never exercised a TComponent-typed property through the
`convert-*` verbs, so output was byte-identical before and after -- the bug was real but silent
under current coverage, and there is still no regression tripwire for this class of defect. A
canary test using a TComponent-typed property through `convert-scaffold` would provide one.

Separately, `ConvRules.Engine.pas` still refuses to pass `--refs-as-leaves`, with a comment that
is now false (the flag exists on main since the merge). Whether the `convert-*` verbs should
HONOUR `--refs-as-leaves` rather than always using the legacy default is a product decision,
deliberately not taken here.

**The merge also exposed a real defect in our own Task 1 test:** it asserted `sample.rules` has
`>= 3` `#convert` blocks — true only of the UNCOMMITTED 3-block fixture in this worktree. The
committed file has 2, so the suite failed for anyone with a clean checkout. Fixed in `87a9d3c`.
Lesson worth keeping: a test that leans on working-tree-only fixture state passes locally and
fails for everyone else.

Rule-book curation shipped: a modal window over a WORKING SET of files (order = composition
precedence) that can split blocks out, copy them out, delete them, merge another file in with
per-conflict resolution, and compose the set into one `.rules` file for `--rules`. Three pure
headless units (`ConvRules.BlockFile` / `.BlockOps` / `.WorkingSet`) plus one code-built VCL
form (`ConvRules.CurationForm`), reached from a `Curate...` button on the main form.

Executed with `superpowers:subagent-driven-development`: a fresh implementer per task, a
spec+quality review after each, then a whole-branch review on the most capable model. Ledger,
briefs and per-task reports are in `.superpowers/sdd/2026-07-27-rulebook-curation/` -- kept on
purpose while the branch is unmerged.

**What the final whole-branch review caught that eight per-task reviews could not:** writing
into a file that is ALSO in the working set left that file's in-memory blocks stale, so Compose
silently omitted a moved rule from the file handed to `--rules`, and a later save on that member
erased the block from disk. Fixed by `TWorkingSet.SyncFromText`. It also found that ignoring a
save's result was systemic (4 sites), that `ConcatBlocks` was documented PURE while mutating its
`const` input (Delphi dynamic arrays are references with no copy-on-write on element writes),
and that criteria 9 and 13 were individually satisfied but mutually inconsistent -- criterion 13
requires `.castlib` files in the working set, criterion 9 composes the set into a `.rules` file,
and nothing reconciled the two grammars. Merge/compose now refuse a catalog target rather than
silently corrupting it; castlib-aware merging is a designed feature, not a guess, and is NOT
implemented.

**Known, deliberate limits** (all recorded in the ledger with rulings):
- Criterion 10's integration test passes no `--from`/`--to`, so it proves the composed file is
  grammatically valid DSL, NOT that every `#link` path resolves against a property tree.
- The VCL form has no automated tests by explicit user ruling -- clean build plus an 8-step
  manual checklist run against a live GUI. That ruling cost two Criticals caught in review;
  if this area grows, extract the handler logic into a headless controller.
- `DoCopy` still lacks the same-file guard `DoSplit` has.

### Two hazards for whoever works in this worktree next

1. **A concurrent workstream's uncommitted edits live here** -- ORM3/schema wording in
   `ConvRulesModelTests.dpr`, plus dirty `ConvRules.Engine.pas`, `sample.rules` and docs. One
   subagent "reverted" them to make staging easier and destroyed them; they were recovered from
   the pre-rescope commit with `git diff 9805cdc 59f011d -- <file> | git apply --3way`. Never
   run `git checkout/restore/stash/clean/reset --hard` in this tree, and never
   `git commit -- <pathspec>` (a pathspec bypasses the index and sweeps in unstaged hunks).
2. While driving the GUI for the manual checklist, a subagent briefly sent Escape to an
   unrelated Notepad++ installer window on the same desktop via an unscoped window search. It
   caught it, made the tooling process-scoped, and confirmed no effect -- but GUI automation on
   a shared desktop needs process-scoped window handles.

## PREVIOUS (2026-07-27b): spec E APPROVED, ONE merged plan, ready to EXECUTE

**Next action: execute `docs/superpowers/plans/2026-07-27-rulebook-curation.md`** via
`superpowers:subagent-driven-development` (user's choice: fresh subagent per task, review
between tasks). 8 tasks in 4 phases, TDD, one commit each. Task 1 Step 1 records the test
baseline BEFORE anything changes -- do not start on a red suite.

The plan carries the full Delphi source for the three pure units, every test body, the
curation form, and a phase/effort/milestone/risk frame. All 14 EARS criteria are mapped to
tests in the coverage table at the end of the file. No editor code has been written yet.

**Two plans briefly existed** -- two sessions worked this spec in parallel on 2026-07-27.
The phase-level one (`...-rulebook-curation-editor.md`, 21 KB) was FOLDED IN (its phases,
effort estimates, milestones, risk table and edge cases) and removed, per the user's
"merge the two, one file, one pointer". Three of its proposals were deliberately NOT
adopted, and the plan records why: its `LinkMerge` sample used `System.Move` over a managed
`TArray<string>` (refcount corruption) and had malformed `for` loops; its DUnitX-style
`Assert.AreEqual` does not match this suite's `Check()` runner; and its line-ending design
(detect on load, rewrite every `\n` on save) is a whole-file normalisation that would break
criterion 1 on any mixed-terminator file. A copy is in the session scratchpad if needed.

### `library-Win32.sqlite` is STILL BROKEN -- and it is an ENGINE bug, not a timeout

**The agent-timeout diagnosis was DISPROVED on 2026-07-27b. Do not act on it, and do not
retry the same way a fourth time.**

The rebuild was re-run outside the agent entirely, as a Windows **Scheduled Task**
(`schtasks /run /tn draglint-rebuild-lib32`, batch `C:\Projects\.drag-lint\rebuild-lib32.bat`)
-- no agent process tree, no tool timeout, nothing the harness can reap. It **failed anyway**:
started 18:37:55, indexed ~11 minutes, grew the DB to **108 MB**, then ended with
`EXITCODE=-1` and its log REPLACED by a CLI usage dump headed
`ERROR: unknown command: index,--all,--only,Library,--platform,win32`.

That message is a red herring in two ways, both verified rather than assumed:

- the comma-joining is only how drag-lint's dispatcher formats the arg list in its error
  text -- it is NOT evidence of mis-passed arguments;
- the command form is **valid**: `... --dry-run` prints a correct one-section plan, both
  from `C:\Projects` and from `C:\Windows\System32`. Invocation and CWD are not the cause.

Decisive fact: **two runs launched two completely different ways died at nearly the same
point** -- 116 MB (agent-launched) and 108 MB (Task Scheduler) of a ~1.9 GB index. A harness
timeout cannot explain a failure that reproduces under Task Scheduler at the same size.
Something inside `index --all` aborts partway and, on the way out, truncates its own
redirected stdout -- which is why the record of the file it died on keeps disappearing.

**RESOLVED as far as this workstream can take it -- handed to the engine team.** The
append-mode log finally captured where it stops. Two more runs, both under Task Scheduler:

- run 4: 18:56:06 -> 20:03:41, **67 minutes**, 108 MB, died mid-number writing
  `...\DevExpress\VCL\ExpressPrinting System\Sources\dxPSContainerLnk.pas -> 15`
- run 5: 23:59:00 -> 23:59:46, **46 seconds**, 9.5 MB, died mid-path writing
  `    DIAG: C:\Progr` -- immediately after `...\Raize\CS5\...\CSIdVers.inc -> 0 symbols,
  0 refs, **1 errors**`, i.e. while emitting the DIAG detail line for a file that had just
  reported a parse error. That is the sharpest clue available and the suggested first look.

Five runs, three launch methods, all dead mid-write with exit -1, zero stderr, no Windows
error event. **Disk space was ruled out**: `C:` has 151 GB free. Full evidence, the repro
command, and the manifest-vs-CWD gotcha are written up in
**`docs/INBOX-index-all-win32-library-rebuild-aborts.md`** for the engine team.

`library-Win32.sqlite` is now a **9.5 MB** fragment (each failed run leaves a smaller one --
the rebuild is destructive). The scheduled task has been DELETED, so nothing will retry on
its own. **Do not re-run it a sixth time without an engine fix**; use `library-Win64.sqlite`.

Logs kept at `C:\Projects\.drag-lint\rebuild-lib32-run2.log` (append mode -- keep it that
way; something inside `index --all` truncates its own redirected stdout on the way out).

**Manifest gotcha found while diagnosing:** which config wins depends on CWD.
`C:\Projects\.drag-lint.json` (settings-only, NO `indexes` section, NO exclude) wins when CWD
is `C:\Projects`; `third_party\dll-win64\drag-lint.json` -- the one the previous session added
the `SourceD3` exclude to -- wins otherwise. Run library rebuilds from the exe's own directory
or that exclude silently does not apply.

**Meanwhile nothing is blocked:** `library-Win64.sqlite` is UNTOUCHED, 1.87 GB, schema v18,
and already has ABC5 + Orpheus.

Verify afterwards (expect ~1.9 GB, not 116 MB):

- `drag-lint schema --db C:\Projects\.drag-lint\library-Win32.sqlite --format json` -> 18
- `drag-lint query --name TabcToggleBtn --db <win32>` -> 1 match (ABC5 landed)
- `drag-lint query --name TOvcTable --db <win32>` -> present (Orpheus landed)
- `drag-lint query --name TabcsfRichEditDialog --db <win32>` -> **1** match.
  2 means the `SourceD3` duplicates came back and the new exclude did not take.

**Meanwhile nothing is blocked:** `library-Win64.sqlite` is UNTOUCHED, reads schema 18, and
already contains ABC5 (`Abcbtn.TabcToggleBtn`) -- every proptree and query in this session
came from it. There is also `library-Win32.sqlite.bak` (1840 MB, 2026-07-20) but it predates
the v18 reindex and lacks ABC5/Orpheus, so it is a poor fallback.

### Two config changes made this session (both reversible)

1. **Win32 registry library Search Path** gained `C:\Projects\ABC5\ABC5\Source` and
   `C:\Projects\Orpheus\source` (`HKCU\SOFTWARE\Embarcadero\BDS\37.0\Library\Win32`).
   Both were on the **Win64** path only -- that asymmetry, not a missing index, is why
   ABC5 looked absent. Done with RAD Studio CLOSED; the IDE rewrites this key on exit,
   so never edit it while `bds.exe` runs.
2. **`third_party\dll-win64\drag-lint.json`**: the `Library` section gained
   `"exclude": ["SourceD3","Delphi5","Delphi7","BuildD3","BuildD4","BuildD5","BuildD7","BuildCB3","BuildCB4","BuildCB5"]`.
   ABC5's `Source\SourceD3` holds 34 Delphi-3-era duplicates of units already in `Source`.
   Section-level exclude IS honored for `source: registry-libraries` -- verified in
   `DRagLint.Index.Plan.BuildFilter` (`SectionExclude := ASection.Exclude`, used by the
   library branch).

### Scope decided with the user

**E first, then A+B+C, D to INBOX.**

- **E** (spec written + approved) -- rule-book/catalog curation: modal form, header grid
  over a multi-file WORKING SET, split/copy/delete/merge, and Compose. Composition exists
  because `--rules` is SINGULAR (`DRagLint.CLI.pas:721` assigns a single string, unlike
  `--db`), so using several books at once needs NO engine change.
- **A+B+C** (next spec) -- alias resolution + compatibility tiers; name-driven target
  ranking that reuses the EXISTING right-hand pool list (search box + a "compatible types"
  checkbox replacing today's exact-type `FPoolTypeFilter`, sorted by score with a tier
  badge); auto-suggested enum member maps in a modal, persisted to the singleton
  `casts.castlib`.
- **D** -- DSL merge/split of property VALUES. Deferred. Motivating real case for the
  INBOX note: ABC5's `TNumGlyphs = 1..4` means `Glyph` is a multi-frame strip in one
  bitmap, so ABC -> cx glyph transfer is inherently a split.

### Key findings that drove the design

- `cxGraphics.TcxImageIndex` (cxGraphics.pas:212) and ABC's `TImageIndex` (Abcbtn.pas:315,
  resolved via `uses ImgList` -> `Vcl.ImgList.TImageIndex`) are the **SAME type**:
  `System.UITypes.TImageIndex = type Integer` (System.UITypes.pas:935). Abcbtn.pas:30
  declares its own `TImageIndex`, but it sits inside `{$IFNDEF DELPHI5}` and
  `ABCDEFS.INC:57-62` defines `DELPHI5` unconditionally, so it is compiled out.
- The editor blocks that link anyway: `ConvRules.Casts.TypeFamilyOf` matches a hard-coded
  list of RTL primitive SPELLINGS, so both sides are `tfUnknown` and only the `SameText`
  identity escape hatch (Casts.pas:177) passes. Measured on `cxButtons.TcxButton`
  (published, depth 2): 216 leaves, **118** non-class leaves the classifier cannot reason
  about, ~38 of them secretly Integer or string -- `TColor` 11, `TComponentName` 10,
  `TConstraintSize` 4, `TNumGlyphs`/`TFontName` 3 each, `TcxImageIndex`/`TCursor` 2 each,
  `TCaption`/`TTabOrder`/`TModalResult` 1 each. `TCaption = type string` is the sharpest:
  Caption->Caption works only because both sides happen to be spelled `TCaption`.
- **The index cannot resolve the alias chain for you.** System.UITypes' *enums* are indexed
  (`System.UITypes.TFontStyle`, `TMsgDlgType`) but its simple/alias/subrange type
  declarations are NOT: `System.UITypes.TImageIndex`, `TColor`, `TCursor`, `TCaption`,
  `TComponentName` have no type rows. A static (ideally generated) alias table is the only
  option today; `base_type`/`base_family` on proptree leaves is an engine ask.
- **Enum member maps are feasible today.** `enum_value` rows exist, qualified as
  `Abcbtn.TabcButtonLayout.ablGlyphLeft`; ordinal is reconstructable from
  `start_line`/`start_col`. CAVEAT: explicit-valued enums (`TFoo = (a = 1, b = 5)`) store
  `signature: ''`, so position != value -- name matching must be primary and ordinal only
  a suggestion. Worked example: `TabcButtonLayout` (6 members, common prefix `ablGlyph`)
  vs `Vcl.Buttons.TButtonLayout` (4, prefix `blGlyph`) -> 4 auto-match, 2 surplus.
- **Merge conflict rule** (the user's, and it is correct): the DSL writes `#link To <- From`,
  so a TARGET linked twice from different sources is a genuine conflict (ask which);
  one source feeding two targets is legal fan-out; an identical link is skipped.
- `sample.rules` already holds a real `TabcToggleBtn -> tcxButton` scaffold: ~210 links,
  most of them junk from proptree recursion
  (`#link Action.Owner.Observers.OnCanObserve <- ...`), with `Caption` and `Align` present
  and **no `ImageIndex` link at all** -- the gap above, sitting in the user's own output.

## Previous (2026-07-23): the index is now schema v18

The engine session reindexed EVERY drag-lint DB on this machine to **schema_version 18**
(one additive table, `symbol_facts`). Inbox copy:
`docs/INBOX-index-schema-v18-reindex-for-converter.md`.
**No converter rebuild is required** -- verified on 2026-07-23, not assumed:

- **The version gate is `>=`**, so an older exe reads a newer DB
  (`TSQLiteSymbolStore.IsSchemaCurrent`: `Result := AFound >= AExpected`, consumed by
  `OpenReadOnlyStore` / `OpenWritableStore`). Tested both directions:
  - the worktree-staged `drag-lint.exe` (Jul 21 build) against the **v18** ORM3 DB -> accepted,
    no stale-schema complaint;
  - main's fresh **v18** exe against a **v17** DB -> `index schema v17 < v18: ... migrate`,
    and that DB is skipped.
- **The editor never opens the index directly and caches no `symbols.id`.** Zero references to
  `symbols.id` / `symbol_id` / `schema_version` anywhere under `src/tools/convrules-editor/`;
  it shells out to `drag-lint.exe` and keys everything on dotted property paths, and
  `sample.rules` stores textual paths (`#link Color <- Color`). The inbox's "rowids were
  reassigned" gotcha -- its headline risk -- therefore does not apply to this workstream.

**HAZARD -- do NOT swap in the fresh v18 exe until BOTH library DBs read 18.** Measured
2026-07-23 18:15: ORM3 = **18**; `library-Win64.sqlite` = mid-reindex (732 MB and growing);
`library-Win32.sqlite` = still **17** (file untouched since Jul 21 -- the inbox's "rebuilding"
claim was not yet true on disk). A v18 exe SKIPS a v17 DB rather than failing loudly, and the
editor's default `--from-platform both` draws on Win32 -> the From pool would quietly lose
Win32-only types. The stale-schema line lands on stdout but `SliceJsonObject` discards CLI
preamble, so it would fail SILENTLY. Verify before swapping:
`drag-lint schema --db C:\Projects\.drag-lint\library-Win64.sqlite --format json` -> expect 18
(same for Win32).

**RE-TEST once the reindex lands: `prop_access` is now populated everywhere.** ORM3 previously
read NULL, and `ParseProptreeJson` defaults `IsWritable := True` when `is_writable` is absent
(`ConvRules.Engine.pas` ~L228) -- so every project-type leaf LOOKED writable. With real
`ro`/`rw`/`wo` data, `RefreshPool` will start hiding leaves and Auto-Match / `DoAssign` will
start blocking targets that were assignable last session. **A thinner To-pool is the read-only
filter finally working, not a regression** -- this is the first time that filtering can be
exercised on project types at all.

**TRAP for any future CLI build from this worktree:** this branch's
`src/storage/DRagLint.Storage.Schema.pas` still reads `SCHEMA_VERSION = 16`. Reading is fine
(18 >= 16), but a `drag-lint.exe` built HERE would stamp v16 on anything it indexes. Merge or
rebase `main` before building the CLI from this branch (e.g. to restore `--refs-as-leaves`).
The editor exe links none of the storage layer, so it is unaffected.

**Not re-run this session:** the model suite hits the live library DBs and the reindex was in
flight. Rebuild + run `ConvRulesModelTests.exe` after the reindex verifies -- the test source's
v17-era comments/skip messages were refreshed for v18, so the staged test exe now predates its
source (strings only, no behavior change).

## Previous session (2026-07-21)

All committed on `feat/converter-editor` (22 commits UNPUSHED, user holds push; never pushed):
- **proptree/2 (v17) editor wiring** (commit `d4b4382`): hide read-only To targets; DFM/PAS
  surface combo (`--min-visibility`); public leaves tagged `(PAS-only)`; 30s watchdog in
  `RunCapture`. v17 exe deployed to the worktree `third_party/dll-win64/`.
- **ORM3 re-indexed to v17** (CLIENT+SERVER+COMMON) -> unit-picker/fill work again;
  `prop_access` populated (rw5560/ro242/wo4/NULL8, 770 units). v16 backup at
  `C:\Projects\DB\ORM3\drag-lint.sqlite.v16.bak`. Libraries were already v17.
- **CLASS-CAST feature, editor half** (commits `b641903`/`e1e6f70`/`01354e8`): data-driven
  `.castlib` (`docs/examples/convrules/casts.castlib`, cast `AssignGraphic`
  TPicture/TBitmap/TGraphic/TPngImage/TIcon -> TdxSmartGlyph) parsed by pure
  `ConvRules.CastLib.pas` (`LoadCastLib`/`ClassCastFor`); editor loads it (`GEditorCastLib`),
  `CanCast = IsCastable OR class-cast`, `AssignLink` emits `#link ... : AssignGraphic` (NO
  grammar change). Spec+plan: `docs/superpowers/{specs,plans}/2026-07-21-castlib-class-casts-*`.
  SDD ledger + review findings: `.superpowers/sdd/progress.md`.
- Model suite **157/0/0**. Editor rebuilt + staged: `third_party/dll-win64/ConvRulesEditor.exe`
  (+ `casts.castlib` beside it) -- testable now.

**NEXT (resume point, in order):**
1. **Continue debugging / testing** the editor: launch `third_party\dll-win64\ConvRulesEditor.exe`;
   confirm a TBitmap/TPicture glyph -> TdxSmartGlyph maps to `: AssignGraphic` (not blocked),
   and the proptree/2 read-only/PAS filtering on real controls (TcxButton is fast; TcxCheckBox
   still explodes -- blocker 1 below).
2. **Write the ENGINE handoff spec** for `convert-apply` to REALIZE class casts (layered: DFM
   byte-carry if `compat` matches -> pas `Assign` template -> `// TODO` marker) + the `{src}`
   sourcing decision. Mirror the proptree/2 handoff; deliver a copy to the `main` checkout. NOT
   yet written -- this is the class-cast engine half.
3. Minor post-merge polish (`.superpowers/sdd/progress.md`): 2 parser tests (empty-name block,
   `LoadCastLib` missing path) + optional 3-up `ResolveCastLib` fallback.

**Build recipe (worktree):** `dcc64 -B ConvRulesEditor.dpr` in `src/tools/convrules-editor/`
(or scratchpad `build_editor.bat`); tests likewise -> `ConvRulesModelTests.exe`. Run from
PowerShell `Start-Process -Wait`, check `BUILD_EXITCODE=0` + `model-tests: N pass / 0 fail`.

**Open engine blockers (on `main`; doc `docs/converter/2026-07-21-proptree-v17-integration-blockers.md`):**
(1) **STILL OPEN at v18** -- `--refs-as-leaves` is absent from BOTH deployed exes (verified
2026-07-23: the `proptree` usage lines of the staged Jul-21 exe and main's v18 exe are
byte-identical, both proptree/2, neither offers the flag). So proptree still explodes on some
DevExpress controls (TcxCheckBox ~6982 leaves; public surface times out) and the 30 s watchdog
is still the only guard. The cherry-pick of converter `f65fb9c` into main is still owed -- the
v18 build does NOT fix it.
(2) RESOLVED -- ORM3 is now v18 (was v17, originally v16).

---

## DONE + committed (all verified)

| Commit | What | Verified |
|---|--------|------|
| `6666d1f`..`ff6b91a` | Milestone 1 -- `#use`/`#useswap`, auto-derive, Unit Rules tab, docs | model 125/0, autotest 26/0 |
| `d4070a1` | wait-cursor (hourglass on heavy handlers) + Auto-Match GLOBAL last-segment uniqueness (kills garbage pairings) | model 125/0 |
| `f65fb9c` | proptree `--refs-as-leaves`: referenced TComponent props are leaves, not expanded (owned TPersistent still expands). Editor passes the flag. | proptree autotest 20/0; TcxButton 6208->4539 |
| `4c50ef5` | tests resolve drag-lint.exe from THIS checkout (worktree-relative), not a hardcoded sibling | model 125/0 |

Builds: editor + CLI clean. Suites: model **125/0**, convert-rules **26/0**, proptree **20/0**.

**Recovered (my error, fixed):** an earlier `git checkout -- sample.rules` reverted
the user's saved matches; restored from `sample.rules.bak.2`. The Save button is
correct (backup .bak -> SaveCompleteToString ASCII/CRLF -> validate; drops only
#convert blocks with ZERO #link as scratch).

## OPEN DECISION (evidence-gated on user re-test)

The To-tree is now correct but still large (**4539 leaves** at the editor's default
depth, which truncates at depth 4). Deep OWNED DevExpress internals
(LookAndFeel 1745 / Painter 1093 / ViewInfo 680) dominate. Depth-cap is OUT (user's
real matches are 4-5 deep; going deeper explodes: depth5=28k, depth6=56k, times out).
The two principled cures, pending user's re-test verdict:
- **pragmatic denylist** -- proptree stops expanding known internal base types
  (`*Painter`, `*ViewInfo`, `TcxLookAndFeel*`). Quick, DevExpress-specific.
- **published-only** -- index per-property visibility (schema + RE-INDEX all
  libraries; visibility is NOT stored today -- `GetClassSurface` derives it by
  re-parsing source sections) then proptree filters to published. Correct, big.

## NEXT SESSION -- user's new requests (2026-07-20)

**Session 2026-07-20b (this session):** items **1 + 3 DONE** (editor-only; built +
staged `third_party/dll-win64/ConvRulesEditor.exe`, model suite still **125/0**).
Item **2 is BLOCKED** at the index level (property accessors are not indexed -- see
its note). Change is confined to `ConvRules.MainForm.pas` (UI only; `sample.rules`
untouched). Await user re-test.

### 1. Window / grid / pool sizing -- DONE 2026-07-20b (UI, `ConvRules.MainForm.pas` BuildUI)
Shipped: window 1100->1600; grid gains `goColSizing` (drag-resizeable columns) +
wider cols (From/To 330, cast 110); pool panel 280->400 with its controls anchored
akRight so they stretch; two new pool buttons (item 3) fit above Assign/Unassign.
- Widen the window (Width 1100 -> ~1550-1650).
- **Grid columns RESIZEABLE**: add `goColSizing` to `FGrid.Options`.
- Widen From/To grid columns; make the grid's client area WIDER THAN the sum of its
  column widths (currently cols sum ~590 inside a ~436 client -> clipped). Options:
  widen the middle client region (shrink left/right or grow window) and/or set
  column widths to fit with margin.
- Widen the right **pool** panel (`PoolPanel.Width` 280 -> ~360-400) and the
  library left panel as needed.
- Files: `ConvRules.MainForm.pas` BuildUI (`Width`, `LeftPanel.Width`,
  `PoolPanel.Width`, `FGrid.ColWidths[]`, `FGrid.Options + [goColSizing]`).

### 2. Filter INVALID / impossible To (target) leaves -- BLOCKED (index has no accessors)
> **BLOCKER found 2026-07-20b:** the index does NOT store property `read`/`write`
> accessors. A property Symbol's `Signature` is TYPE-ONLY (`: HWND`, `: string`,
> or empty) -- verified against `library-Win64.sqlite`: across 841 `Caption` rows
> and every `Handle` row, ZERO signatures carry a `read`/`write` token. So
> writability CANNOT be derived from the current index. The real fix needs the
> tree-sitter property extractor to capture the accessor clause into the symbol
> (schema/extract change) THEN a full RE-INDEX of the library DBs (Win64 lib is
> ~1.8 GB) -- i.e. the same "big" bucket as the published-only option under OPEN
> DECISION. Options: (a) do the indexer change + re-index (correct, big); (b) a
> pragmatic editor-side denylist of well-known read-only names (Handle, ComObject,
> ComponentCount, ...) -- quick but brittle, may hide a valid same-named target;
> (c) defer until the indexer work lands. NOT implemented this session.
>
> **HANDED OFF to the engine team (2026-07-20b):** thorough evidence-based design in
> `docs/converter/2026-07-20-proptree-assignability-engine-handoff.md` (copy dropped
> in the engine checkout `C:\Projects\Delphi-RAG-lint\docs\lint\`). Refined finding:
> only **writability** needs a re-index; **visibility** (in `modifiers`:
> published/public) and **concrete polymorphic type** (`TcxCheckBox.Properties` ->
> `TcxCheckBoxProperties` already captured) are proptree/CLI plumbing, NO re-index.
> Contract = proptree/2 JSON (`is_writable`, `visibility`), back-compat defaults.
>
> **2026-07-21: ENGINE SHIPPED proptree/2 (v17) + editor WIRED.** TPropLeaf gains
> IsWritable/Visibility/MemberKind; GetProptree passes `--min-visibility`; RefreshPool
> hides read-only + tags PAS-only; DFM/PAS surface combo; Auto-Match/DoAssign skip
> read-only; 30 s watchdog in RunCapture. Model suite 126/0/3-skip. BUT two engine
> blockers remain (see `docs/converter/2026-07-21-proptree-v17-integration-blockers.md`):
> (1) v17 dropped `--refs-as-leaves` -> some controls' proptree explodes/times out
> (TcxCheckBox); (2) v17 exe HARD-refuses pre-v17 project DBs -> ORM3 needs a v17
> re-index for the unit-picker/fill features. Editor works today for library targets.

- **Read-only leaves are not valid assignment targets** (e.g. `...Handle`). A To
  path is only usable if the FINAL segment is WRITABLE (and every intermediate
  segment READable). `cxButton.LookAndFeel.Painter.ClockGlass.Handle := x` won't
  compile because Handle is read-only.
- Needs proptree to expose per-leaf **read/write** (the property Signature carries
  `read`/`write` specifiers; check whether the indexer captures them, or parse the
  signature). Add e.g. `is_writable` to proptree/1 JSON; the editor's To pool
  (`RefreshPool`) then excludes non-writable leaves (or greys + blocks Assign).
- This ALSO overlaps the deep-internals noise (denylist / published-only above);
  read-only filtering + denylist together would cut most of the useless deep paths.
- Files (engine): `src/report/DRagLint.Convert.PropTree.pas` (emit writability),
  `src/cli/DRagLint.CLI.pas` (JSON field). Editor: `ConvRules.Engine.pas`
  (`TPropLeaf` gains a flag, ParseProptreeJson reads it), `ConvRules.MainForm.pas`
  (`RefreshPool` filter + `DoAssign` guard).

### 3. To-search helper buttons -- DONE 2026-07-20b (UI, `ConvRules.MainForm.pas`)
Shipped both: **"Find in From by name"** (`DoFindInFrom`) selects the From-grid row
whose last-segment name matches the highlighted pool leaf; **"Only this type" /
"Show all types"** (`DoOnlyType` + `FPoolTypeFilter`, applied in `RefreshPool`,
auto-cleared on block load) toggles the pool to one type. Helper fns `TypeOfCell` /
`LeafNameOf` added beside `PathOfGridCell`.

Original spec (for reference):
Next to the pool search box (`FPoolFind`), for the currently highlighted pool leaf:
- **"Find in From by name"** button -- copy the highlighted To leaf's bare name into
  a From-side filter and select/scroll the matching From grid row (align From<->To by
  name).
- **"Only <type>" button** -- filter the pool to leaves whose TYPE matches the
  highlighted leaf's type (e.g. highlight `Popup: Boolean` -> show only Boolean
  To leaves). Extend `RefreshPool`'s filter to accept an optional type constraint;
  the button toggles it from the highlighted leaf's `TPropLeaf.TypeName`.
- Files: `ConvRules.MainForm.pas` (pool panel buttons, `RefreshPool` type-filter,
  a From-grid select-by-name helper).

## Build / test quick ref
- Editor: `dcc64 -B ConvRulesEditor.dpr` in `src/tools/convrules-editor/` (worktree
  paths; the repo `build/_build_convrules_editor.bat` hardcodes the MAIN checkout --
  use a worktree wrapper, e.g. in the session scratchpad).
- Tests: `dcc64 -B -NS... ConvRulesModelTests.dpr` in `.../tests/`; run exe ->
  `model-tests: N pass / 0 fail`.
- CLI: `build/build_draglint_win64.bat` (relative-path safe) -> stages
  `third_party/dll-win64/drag-lint.exe`.
- Autotests: `tests/autotest/run_proptree.ps1` / `run_convert_rules.ps1`
  `-Exe <deployed drag-lint.exe>` (the `src/cli/Win64/Debug/` copy crashes -- missing
  tree-sitter DLL beside it). Both flip `$ErrorActionPreference='Continue'` for the
  exe's `(loaded defaults)` stderr note.

## Phase 2 (later, unchanged)
`convert-apply` executes `#use`/`#useswap` on a real `uses` clause (normalization
already implemented pure in `ConvRules.Units.NormalizeUnitSets`). Then DFM inventory,
value/enum casts, AI apply-by-name.
