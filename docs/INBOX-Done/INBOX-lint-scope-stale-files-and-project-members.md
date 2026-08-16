> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21). REFUTED by measurement.** Bug 1 (incremental index never prunes vanished files): the indexer now prunes -- fixture test showed `--prune: removed 1 file(s) no longer on disk` and the vanished unit's symbol gone from the index on the next incremental run. Bug 2 (cannot scope lint to project members): `lint-all --project` exists and was used throughout this session with correct per-project file counts.

# INBOX -- lint reports findings for files that no longer exist, and cannot be scoped to project members

Found 2026-08-06 on `C:\Projects\DataCopy` after the user moved six retired units out of the project
root into `Backup-20260805\`. Two separate defects, both hit in the same run.

---

## Bug 1 -- incremental index never prunes vanished files (DEFECT, high)

Repro:

```
# baseline
drag-lint lint-all --db C:\Projects\DataCopy\drag-lint.sqlite --json --quiet   -> 1414 findings

# user moves 6 units from the root into Backup-20260805\
drag-lint index C:\Projects\DataCopy --db C:\Projects\DataCopy\drag-lint.sqlite
  -> "Done. Files: 35, Symbols: 3083, Refs: 17038, skipped 17 up-to-date"

drag-lint lint-all --db ... --json --quiet                                     -> 674 findings
```

674 still includes findings whose `file_path` is `C:\Projects\DataCopy\CMMACPY.pas`,
`...\DataCopy2.pas`, `...\MainZeissConvert.pas`, `...\DPP2CSV_Main.pas`, `...\DataCopy.pas`,
`...\Main_Copy_CSV_With_Tag.pas` -- **none of which exist any more**. Roughly 249 of the 674 are
attributed to files that are gone.

The incremental walk adds new files and refreshes changed ones, but nothing removes rows for files that
were deleted or moved since the last run. The stale rows then feed the linter, which happily reports on
source that is not there. A user acting on those findings would go looking for a file that does not
exist -- and worse, the counts used to judge "did my cleanup help?" are wrong.

**Suggested fix:** after a full-root walk, delete `files` rows (and their dependent symbols/refs)
whose path was not visited AND no longer exists on disk. Gate it on a full walk -- a targeted
`index <subdir>` must NOT purge everything outside that subdir. A `--prune` flag would be the
conservative first cut; pruning by default on `index <root>` is the correct end state.

~~Note the existing `drag-lint diff --db old --db new` machinery already reasons about
appeared/disappeared files, so the concept exists in the codebase.~~
**CORRECTION (2026-08-06):** it does not. `DoDiff` (CLI.pas:3735-3845) compares SYMBOLS by
qualified name/kind between two DBs; there is no file-level appeared/disappeared logic to
reuse. Nor did the store have any way to delete a file row -- only the per-file *dependent*
clears the re-indexer uses (`DeleteFileDocs`, `DeleteUnitUsesForFile`, ...).

---

## Bug 2 -- `lint-all --project <dproj>` does not scope the finding set (DEFECT or missing feature, medium-high)

```
drag-lint lint-all --db <db>                                      -> 674
drag-lint lint-all --db <db> --project C:\Projects\DataCopy\DataCopy.dproj -> 675
```

The flag is accepted (it appears in `help` for `lint-all`) and changes nothing measurable. There is
currently **no way to lint only the units a given project actually compiles.**

### Why this matters, in the user's words

> "the linter should not pick them up anyway because they are not project members. So if they happen
> to reside in the same folder, what if I had more related projects in the same folder? This is not
> illegal, so why linter complains about non-members?"

This is a normal layout, not an abuse. `C:\Projects\DataCopy` contains BOTH `DataCopy.dproj` and
`SortTest.dproj`. Reviewing DataCopy today means wading through 62 findings from
`SortTest.dxSettings.pas` and 31 from `uSortTestMain.pas` that belong to a different program. With the
retired units still present it was far worse: 989 of 1414 findings came from source that no project
compiles.

### CORRECTION (verified 2026-08-06): per-project indexing ALREADY EXISTS and works

An earlier draft of this note said the index is folder-scoped by design. That is wrong, and the
correction matters because it changes what needs building.

`index --project <file.dproj>` resolves the PROJECT's own search paths and follows the unit closure
ACROSS FOLDERS. Dry-run against a real multi-folder project:

```
drag-lint index --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj --dry-run
  Project: C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj
  Resolved 21 unique scan folders:
    C:\Projects\DB\ORM3\CLIENT
    C:\Projects\DB\ORM3\COMMON
    C:\Projects\DB\ORM3\COMMON\OBJECTS
    C:\Projects\spring4d\Source\...  (x14)
    ...
```

The manifest also already accepts a `.dproj` as an `include` -- the `Loader` section does exactly this:
`"include": ["C:\\Projects\\Loader2019\\Loader2025.dproj"]`. And `settings.currentProjectsIndexing`
is already `"perProject"`.

So the capability is there; ORM3 is merely CONFIGURED as a folder root
(`"include": ["C:\\Projects\\DB\\ORM3"]`), which unions CLIENT and SERVER into one DB. The user's
layout (CLIENT / OBJECT / COMMON, and SERVER / OBJECT / COMMON) is exactly what per-project scanning
is for.

**Tradeoff to design around, not a blocker:** a per-project scan also pulls in the resolved LIBRARY
paths (Spring4D, PDFlib, TbcParser, CAD above). That duplicates the `Library` sections and would
inflate each project DB. A per-project section wants an exclude for library roots -- or the resolver
wants a "project units only, libraries come from the Library DB" mode. Worth adding as a section-level
option, since every real project will hit it.

### What is STILL missing after that correction

Per-project INDEXING solves membership at index time. It does not solve the lint filter: with a
per-project DB, `lint-all` would still report on the Spring4D sources pulled into that DB. So the gap
narrows but does not close --

**the LINT consumer still has no project-member filter on top of the index.**

### Suggested fix

Make `--project` mean what it looks like it means: restrict findings to the transitive unit closure of
that `.dproj` (the `.dpr` uses clause + `DCCReference` entries + units reached through them). drag-lint
already computes closures -- `lint --project` supports `unit-not-in-dpr`, and `index --project` exists.

Worth considering alongside:
- report the owning project per finding when a DB spans several, so a mixed run is at least legible;
- a `--exclude <glob>` on lint-all for the "vendored/backup subfolder" case, which is the other half
  of how people hit this.

---

## Status

**BOTH FIXED 2026-08-06.**

### Bug 1 -> `index --prune` (opt-in)

`ISymbolStore.PruneMissingFiles(ARoots)` + a `--prune` flag on every `index` form. After the
walk (and BEFORE the resolve passes, so uses/ancestry/call edges are recomputed against the
survivors) it deletes every indexed file that lies under a walked root and no longer exists
on disk, then reports what it removed.

Two things turned out better than the plan above:

- **The dependent rows did not need a hand-written sweep.** Every file-owned table already
  declares `REFERENCES files(id) ON DELETE CASCADE` and `Migrate` sets
  `PRAGMA foreign_keys = ON`, so a single `DELETE FROM files` takes symbols / refs /
  unit_uses / di_bindings / string_literals with it, and transitively symbol_docs /
  symbol_trigrams / type_ancestors / type_helpers / symbol_facts. A hand-written list would
  have silently missed the next table added.
- **`string_literals` IS deleted explicitly first, and must be.** Its FTS5 shadow tables are
  synced by `AFTER DELETE` triggers, and SQLite fires triggers for FK-cascaded rows only when
  `recursive_triggers` is on. Left to the cascade, `query --text` would have gone on matching
  deleted source.

Scoping was the risk: a prune that walked one folder but purged a shared DB would be worse
than the bug. Roots are absolutized (so `index . --prune` is not a silent no-op), folder roots
get a trailing separator so `App` cannot swallow `AppTools`, and a root naming a single FILE
is matched whole rather than as a prefix.

Still opt-in, deliberately -- the deletion is not undoable. Pruning by default remains the
end state; `tests\autotest\run_index_prune.ps1` pins the current contract by asserting the
no-flag run still leaves the stale row, so that change has to be made here on purpose.

Test: `tests\autotest\run_index_prune.ps1` -- indexes TWO folders into ONE db, deletes a file
from each, prunes scoped to one, and requires the other folder's equally-missing file to
survive untouched. Also asserts the cascade (the file's symbols go too) and idempotence.

### Bug 2 -> `lint-all --project` now scopes the finding set

`--project` means what it looks like it means: the run is restricted to that project's compile
closure (`TClosureResolver`) plus each closure unit's sibling `.dfm`, the project file, and its
sibling `.dpr`/`.dpk`.

Both passes are scoped, which is the part that is easy to get half-right: filtering the file
list only narrows the PER-FILE rules, and every project-wide rule (god-class, clone detection,
layering, the doc rules, used-unit-not-resolvable) reads the whole store -- so the non-member
noise walks straight back in through them unless the finding set is filtered too.

Two decisions worth knowing about:

- **The `.dfm` siblings are in scope on purpose.** The closure yields `.pas`/`.inc` only, so
  scoping strictly to it would silently drop every form's DFM findings from a project run.
- **The `.dpr`/`.dproj` are in scope on purpose.** Every `unit-not-in-dpr` finding is anchored
  to the program file or the `.dproj`, never to the offending unit -- so without them the one
  rule `--project` explicitly enables would have been filtered out of its own project's run.

An unresolvable `--project` now exits 2 rather than scoping to nothing: a linter reporting a
clean bill of health because its scope was empty is the most dangerous failure available to it.

Test: `tests\autotest\run_lint_project_scope.ps1` -- one folder, two projects, one shared DB
(the DataCopy situation). Measured 22 findings bare -> 11 scoped to AppA; the other project's
unit and the unreferenced stray are dropped, the transitive dependency is kept, `--project AppB`
scopes to ITS member, and the scope summary is asserted to land on stderr rather than in the
JSON document.

### Not addressed here

The per-project INDEXING tradeoff noted above -- a per-project scan also pulling in resolved
LIBRARY roots (Spring4D, PDFlib, ...) and inflating each project DB -- is untouched. It wants a
section-level "project units only, libraries come from the Library DB" option. With `lint-all
--project` now filtering, the pressure to solve it at index time is lower.
