# RESUME -- 2026-08-13 (session 15)

Supersedes `RESUME-2026-08-13b-shared-unit-docs-and-menu.md`.

Read this, then continue
`docs/superpowers/plans/2026-08-13-shared-unit-docs-and-menu.md` **from Task 3**.
Tasks 1 and 2 are DONE. **Task 4's premise must be re-measured before it is
implemented** -- see "Task 4 is now doubtful" below.

## Status

`main` = **`9414826`**, **3 commits unpushed** (`11ea4af`, `aeeeee6`,
`9414826`). Working tree clean apart from untracked `docs/INBOX-*.md`, which is
where they belong. Battery **267/267** on the shipping binaries (265 baseline +
2 new tests).

Pushing still needs `git config http.postBuffer 524288000` +
`http.version HTTP/1.1`.

### Shipped this session

**`aeeeee6` -- autofix planned repairs into third-party code.**
`TDocLintRules.FixEditsForDocDrift(AStore)` took the store and nothing else, so
it walked EVERY documented decl in the database. One `doc-drift` finding in
YADF's own code made `lint-all --project YADF.dproj --fix` plan 22 edits into
`C:\Projects\DelphiAST` -- a vendored root the same run had just reported as
skipped -- and write `.bak` files into that third-party repo. It is the defect
`document --project` was fixed for on 2026-08-12, reached by the OTHER writer
entry point; the ownership fix had been applied per COMMAND, not at the seam.
Now takes the targeted findings, like its already-scoped sibling
`FixEditsForMissingDoc`. Summary line now counts EDITS WRITTEN, not fixable
findings ("applied 11 fix(es) across 0 file(s)" was self-contradictory).

**`9414826` -- the checker and the repairer rendered under different options.**
`FixEditsForDocDrift` called the TWO-ARGUMENT convenience overload of
`TDocumenter.BuildFor`, which hardcodes `AIncludeSeeAlso := False`
(`Doc.Document.pas:129`), while `TDocDrift.Analyze` defaults it True. So the
checker compared against a render WITH `<seealso>` and said "managed facts block
is out of date, fixable"; the repairer regenerated one WITHOUT it, got something
byte-identical to disk, returned `daUnchanged`, and emitted nothing. **That is
the whole of the long-standing "writer and checker disagree" mystery.** It was
never an index problem. `DoLintAll` had the invariant written down beside its own
call (`CLI.pas:10042`) and only the checker obeyed it.

Also added **`DRAGLINT_FIXDOC_TRACE`** (env var, ErrOutput). Four gates can drop
a decl silently, one of them a bare `except`; the trace named this one in a
single run (`DROP BuildFor-0-edits`). Keep it -- this seam has cost four
investigations.

### Measured effect

| | before | after |
|---|---|---|
| YADF total findings | 10 | **8** |
| YADF `doc-drift` | 2, unrepairable | **0** |
| autofix summary | `applied 11 fix(es) across 0 file(s), 22 skipped` | `no fixable findings` -> then a real 4-edit repair |
| edits planned into `C:\Projects\DelphiAST` | 22 | **0** |
| second `--fix` pass | still 22 skipped | no-op |

10 -> 8 is exactly what plan Task 1 Step 7 predicted. It was Task 2's defect.

### An unexpected bonus, worth knowing

Applying the repair **deleted junk cross-project facts** from YADF's docs:
`dxRibbon.pas` and `dxRichEdit.*`/`FMX.ListBox`/`REST.Backend.EMSApi` entries off
`TGroupKind`/`TGroup`, and four `TestCachedUpdates.dpr` callers off
`TGroup.Create`. That is precisely the junk plan Task 4 Step 3 names and calls
"stale TEXT from the union-DB era". **It is now gone from the SOURCE**, not just
absent from the DB.

## Resume point -- Task 3, the `dl:shared` marker

Task 3 is unaffected by anything above; start at its Step 1 (write the failing
test `tests/autotest/run_shared_unit_marker.ps1`). Nothing in Tasks 1-2 changed
its interfaces.

## Task 4 is now DOUBTFUL -- re-measure before implementing

Task 4 exists to stop project A reporting project B's block as stale. Its
evidence was YADF's residual `doc-drift`. **That residual is now zero, and its
cause was the seealso option mismatch, not project scope.** Before writing any of
Task 4:

1. Run the cycle on YADFOT and YADFSetup (they were 45 each) and see whether
   cross-project doc churn actually still happens now that both defects are gone.
2. If it does, capture ONE concrete decl where project A and project B disagree,
   with both rendered blocks, before touching `TDocDrift.Analyze`.
3. Task 4's `certain`-entry guard was justified by the `TestCachedUpdates.dpr` /
   `dxRibbon` junk. That junk has been cleaned out of the source. The guard may
   now be insurance against nothing.

**Five plan-stated mechanisms have died on contact with a built engine this
session** (both of Task 1's candidate causes; Task 2's stated direction; the
config-discovery hypothesis; and Task 4's junk premise). The habit that caught
all five: reproduce against the shipping binary FIRST.

## Not done yet (ordered)

1. **Task 3** -- `dl:shared` marker: grammar, reader, CLI surface. Unblocked.
2. **Task 4** -- structured staleness. RE-MEASURE FIRST (above).
3. **Tasks 5-6** -- the two IDE menu items (Put a Shared Unit Marker; About
   dialog absorbing the six debug items). Both need a LIVE IDE check; the plugin
   has no automated coverage. Build BPLs with RAD Studio CLOSED, both platforms.
4. **Task 7** -- LoopZero on YADF, YADFOT, YADFSetup, DataCopy. YADF is already
   at 8. Do NOT run YADFOT/YADFSetup before the marker lands.
5. **Item D, the type-blind pair** -- `concat-in-loop` is 15 on DataCopy alone.
   Separate plan.

## Open decisions for the owner

* **`C:\Projects\DelphiAST` still holds collateral damage** from the `aeeeee6`
  defect: 2 modified sources + 2 `.pas.bak` (2026-08-13 10:22), pure autodoc
  churn, no human edits. The 2026-08-12 precedent was to `git checkout` back to
  `master@dfb2326` and delete the `.bak`s. NOT done -- it is a separate repo and
  was never asked for.
* **Should `dl:shared` also soften `unused-public-symbol`?** Unchanged from the
  previous resume doc; recommendation is still documentation-only for v1.
* **YADF working tree** has 7 modified files. Only `YADF.Groups.pas` and
  `YADF.LineScan.pas` are this session's doc repairs; the other five are
  leftovers from the episodic-memory agent's 2026-08-13 autodoc run. `.bak` files
  sit beside all of them.

## Filed this session

* `docs/INBOX-buildfor-defaulted-args-diverge-between-entry-points.md` (NEW) --
  `BuildFor`'s remaining defaulted tail still diverges: manifest
  `max_return_cases` is 6, the default is 20; extra stores and base dir are not
  passed by the repair path at all. Same defect class as `9414826`, deliberately
  NOT fixed because it is unmeasured. Also records that `lint-all` and `document`
  discover DIFFERENT config files from the same CWD (measured not to be the cause
  here, but wrong on its own).
* `docs/INBOX-ignored-files-already-indexed-are-never-evicted.md` (UPDATED) --
  now carries the measurement: YADF's DB reports 18 files while a full
  `--force-reparse` parses 9. The other 9 are ghosts (DelphiAST) frozen ~150
  lines stale -- `PushNames` recorded at line 564 with its body at 905..908, in a
  779-line file that has it at 414. `--force-reparse` does NOT clear them; only
  `--rebuild` does. Still open.
* `docs/INBOX-document-project-ignores-ownroots-and-writes-into-third-party.md`
  (UPDATED) -- reopened and re-fixed for the second entry point.

## Gotchas that will bite a cold start

* **KILL the episodic-memory `sync-cli.js` node PARENTS FIRST.** 15 were running
  at session start today.
* **`index --all --only YADF --force-reparse` parses 9 files; the DB has 18.**
  Do not trust a reindex to refresh anything outside the compile closure. If you
  need those rows gone, `--rebuild`.
* **`lint-all` only reports ownRoots, but store-wide rules still SEE everything.**
  Any store-wide walk that produces EDITS must be scoped to the findings. Check
  anything else reaching `TDocumenter.BuildFor` that way.
* **`BuildFor`'s defaulted tail is a trap.** Omitting an argument silently
  substitutes a different configuration and the compiler is happy. That is
  exactly how `9414826` hid.
* The battery takes **~16 minutes** -- run it in the background, not in a
  foreground turn (the 10-minute cap kills it).
* Staging the built exe fails while any `drag-lint.exe` runs; kill it first. The
  build reports only "failed to stage".
* The Write tool emits LF; `.pas`/`.dpr`/`.ps1`/`.md` are strict 7-bit ASCII +
  CRLF. Byte-check after every write.
* Run the battery with `pwsh`, never `powershell.exe`.
* Rebuilding the engine kills the VS Code LSP client -- *Developer: Reload
  Window*.
