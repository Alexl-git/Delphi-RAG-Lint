# RESUME -- 2026-08-13 (session 14)

Read this, then execute
`docs/superpowers/plans/2026-08-13-shared-unit-docs-and-menu.md` from **Task 1**.
The spec it argues from is
`docs/superpowers/specs/2026-08-13-shared-unit-doc-staleness.md`.

## Status

`main` = **`11ea4af`**, **1 commit unpushed** (the spec+plan). Everything through
`47c5791` is pushed -- including the engine changes and both rebuilt IDE plugin
BPLs. Battery **265/265** on the shipping binaries.

**Pushing needs `git config http.postBuffer 524288000` + `http.version
HTTP/1.1`.** Without them a push carrying several 7-8 MB BPL revisions returns a
bare `remote: Internal Server Error`. Nothing is wrong with the repo.

### Shipped this session

Both owner rulings, in `87539c5`:

* **`try-except-swallowed` accepts a DOCUMENTED deliberate swallow** -- an except
  body that runs NO code and carries a non-marker comment. A handler that RUNS
  code and merely has a trailing comment still fires. A `dl:ok` marker does NOT
  count as documentation, and that is deliberate: it is what keeps the rule OUT
  of `COMMENT_SENSITIVE`, so a marker suppresses normally instead of being
  reported unused. DataCopy 18 -> 8.
* **`field-name-prefix` is a BACKING-FIELD convention** -- private and
  strict-private only. The type-based ("is it T-something?") heuristic is gone.

Plus: `unused-parameter` exempts VCL form events with no `Sender` (exact name
list, never a `Form*` prefix -- that would exempt `TFoo.Format`); `object-leak`
ownership resolves through the LIBRARY store via a new manifest-driven
`ResolveLibraryDb`; both IDE plugin BPLs rebuilt for Win32 and Win64.

### Counts (all six re-measured on the shipping binaries)

| Project | now |
|---|---|
| YADF | **10** |
| YADFOT | **45** |
| YADFSetup | **45** |
| DataCopy | **117** |
| SortTest | **2** |
| DataCopyTests | **76** |

## Resume point -- the first thing to do

**Plan Task 1: reproduce the autofix stale-anchor skip, then fix it.**

```powershell
$exe = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
cd C:\Projects\YADF
& $exe lint-all --project 'C:\Projects\YADF\YADF.dproj' --fix --apply
```

prints, and has printed identically across three reindexes:

```
autofix: applied 11 fix(es) across 0 file(s), 22 skipped (stale index) (.bak written)
```

`applied 11` is false (`Touched` is 0), and the 22 never clear -- so YADF's last
2 `doc-drift` findings cannot be repaired by any command. The report bug is
certain from source (`CLI.pas:6733` prints `FixCount`, the count of fixable
FINDINGS, while one finding emits a delete+insert PAIR). **The skip cause is NOT
established -- reproduce it before changing anything.** Two candidates are named
in the plan; neither is assumed.

## Not done yet (ordered)

1. **Plan Tasks 1-3** -- the three engine defects. They gate everything: until
   the repair path converges and `document --project` stops under-reporting, no
   documentation change can be measured.
2. **Plan Task 3-4** -- the `dl:shared` marker and the structured staleness
   comparison.
3. **Plan Tasks 5-6** -- the two IDE menu items (Put a Shared Unit Marker; About
   dialog absorbing the six debug items). Both need a LIVE IDE check; the plugin
   has no automated coverage.
4. **Plan Task 7** -- LoopZero on YADF, YADFOT, YADFSetup, DataCopy.
5. **Item D, the type-blind pair** -- `concat-in-loop` is 15 findings on DataCopy
   alone, the largest single rule left. Needs store-backed built-ins superseding
   the `.scm` queries; copy the `string-equality-comparison` precedent. Separate
   plan.

## Awaiting an owner decision

**Should `dl:shared` also soften `unused-public-symbol`?** `SaveOptionsToIni` is
reported unused by YADF while having 15 call sites in a unit only YADFOT and
YADFSetup compile -- the same single-project blindness. Recommendation:
documentation-only for v1, so one mechanism changes one behaviour and the effect
is measurable.

## Gotchas that will bite a cold start

* **KILL the episodic-memory `sync-cli.js` node PARENTS FIRST.** On 2026-08-13 a
  resumed agent committed `46d66ac` to `main` AND ran autodoc over five YADF
  source files mid-session -- which read exactly like a regression in the work in
  progress and cost real time. Review anything it committed; do not inherit it.
  Its commit hardcoded `C:\Projects\.drag-lint` with a fixed Win64 preference and
  called `Migrate` on a 2.2 GB shared index; both were rewritten in `87539c5`.
* **Do NOT LoopZero YADFOT/YADFSetup before the marker lands.** All three YADF
  projects compile the same units; documenting per project makes them overwrite
  each other's inbound facts turn by turn.
* **REPRODUCE A BACKLOG ITEM BEFORE IMPLEMENTING IT.** Three in a row have now
  died: `object-leak` cause A did not exist; `empty-except` is comment-sensitive
  by accident; and the `out`-argument read (item B) could not happen at all --
  `CollectReadsAndCallDefs` adds a bare identifier argument to `CallDefs` ONLY,
  never to `Reads`. That mechanism was written, measured at zero, and reverted.
* **`tools\dumpnode <file> <nodeType>` prints named AND anonymous children.** A
  `try` node's last child is an anonymous `;` AFTER `kEnd` that the s-expression
  form does not show; a handler that skipped `kEnd` and kept scanning counted it
  as code and silently defeated the whole swallow ruling. `dumptree`/`dumpcase`
  cannot show this.
* A `{ }` comment must never contain `}` or `{$` -- it closes the comment early.
  Cost one build today.
* Staging the built exe fails while any `drag-lint.exe` runs (the LSP holds one).
  Kill it, then copy; the build reports only "failed to stage".
* The Write tool emits LF; `.pas`/`.dpr`/`.ps1`/`.md` here are strict 7-bit ASCII
  + CRLF. Byte-check after every write.
* Run the battery with `pwsh`, never `powershell.exe`.
* Rebuilding the engine kills the VS Code LSP client -- *Developer: Reload
  Window*.
* **Sample ~12 findings before believing a count, and sample the ANALYSER, not
  the source shape.**

## Other open items filed this session

* `docs/INBOX-used-before-assignment-real-shape-is-intra-item-ordering.md` -- the
  real defect is intra-item evaluation order around short-circuit `and`.
* `C:\Projects\DataCopy\NOTES-backup-naming-decision-2026-08-13.md` -- owner
  ruled HOLD on switching backup names to wall-clock; switching breaks
  `SweepStrandedZeissGroups`, which finds a backup by rebuilding its name from
  the source's timestamp. Also records that tester item B3 needs a re-run with a
  real deny-ACL, because a folder's read-only attribute is ignored by Windows
  (measured).
