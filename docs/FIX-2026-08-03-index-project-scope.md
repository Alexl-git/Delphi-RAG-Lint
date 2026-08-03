# Fix: `index --project` indexed the whole machine, and the wizard wrote a DB nobody read

**Date:** 2026-08-03. **Trigger:** the user reindexed `C:\Projects\DataCopy\DataCopy.dproj`
from the IDE menu and it was still running after an hour on a project of 42 source files.

**Result: 1 h+ and unfinished -> 11.9 s.** Two independent defects, both in the same user
action. Either one alone would have wasted the run.

---

## Defect 1 -- `index --project` walked the IDE's entire library path

### Symptom

`drag-lint index --project DataCopy.dproj --db DataCopy.sqlite --platform Win64`, launched
13:32, was at ~1,000 files by 13:38 and growing at 76 files/min with ~3,600 still to go. Of
those 1,000 files, **35 belonged to DataCopy** -- 3.5%. The rest were the RAD Studio source
tree, Raize, Spring4D, and OmniThreadLibrary's `tests\`, `examples\` and `bag of stuff\`
folders. It had already indexed 90 `.dpr` and 45 `.dpk` files -- other people's demo
projects. When killed, the DB was 184 MB.

### Root cause

`DoIndex`'s `--project` branch resolved its scan scope through `TProjectResolver.Resolve`,
which ends with an unconditional

```pascal
ReadLibraryPaths(List, ['Win32', 'Win64']);   // Resolver.pas:444
```

-- the IDE's registry Library *Search Path* + *Browsing Path*, for **both** platforms, from
HKCU and HKLM in both registry views. `DoIndex` then walked every folder it got back
**recursively** (`CLI.pas:1904-1908`).

`DataCopy.dproj` declares **no `DCC_UnitSearchPath` at all**, so of the **153 folders**
resolved, **151 came purely from the registry**.

This also explains the apparently-ignored `--platform Win64`: the platform list on that line
is a hardcoded literal, so a Win64 run still pulled every Win32 library folder. 164 indexed
paths contained `\Win32\`; zero contained `\Win64\`.

Every one of those files is already in `library-Win32.sqlite` / `library-Win64.sqlite`
(2.29 M / 2.16 M symbols, rebuilt to schema v19 the same morning). A consumer reaches them by
passing a second `--db` -- which the LSP already does.

### Fix

`TProjectResolver.Resolve` is **unchanged**. Its other two callers -- `check-unit`
(`CLI.pas:9214`) and the compile helper (`CLI.pas:10013`) -- build a *compiler* search path
and genuinely need the library folders; a `dcc` invocation must be able to find the RTL. Its
own comment says so: *"the project's folders (incl. library + DCU output)"*.

Instead the shared body moved into a private `CollectProjectFolders`, and the resolver gained

```pascal
function ResolveProjectOnly(const ADprojPath: string): TArray<string>;
```

which is `Resolve` minus the `ReadLibraryPaths` call. `DoIndex`'s `--project` branch uses it.
A `.dproj` search path that itself points into a library tree IS still honoured -- that is an
explicit statement by the project author, unlike the registry tail, which no project asked
for.

### Why not `TClosureResolver`

The obvious alternative was the existing `TClosureResolver`, which the manifest's `smClosure`
sections already use and which returns a precise unit closure. It was rejected: it yields
`.pas`/`.inc` **only**. `Loader.sqlite`, built by that path, contains 84 files and **zero
`.dpr` and zero `.dfm` rows**. Switching `--project` to a pure closure would have silently
dropped every form's DFM from project indexes, breaking the wizard's structure view, DFM event
wiring and `forms-csv`. Walking the project's own folders keeps that coverage.

The trade-off is that a loose unit in the project folder that nothing references still gets
indexed. That is deliberate, matches the pre-existing behaviour of the wizard's own
project-folder pass, and is asserted explicitly in the test.

---

## Defect 2 -- the wizard indexed one DB and read another

`InvokeReindexProject` (`Editor.pas:4452`) took its target from `GetActiveProjectDb`, which is
`ChangeFileExt(projFile, '.sqlite')` -> `DataCopy\DataCopy.sqlite`. But the LSP and the graph
viewer resolve their DBs through `ResolveActiveIndexDbs`, which on this project selected
`DataCopy\drag-lint.sqlite`. Both were observed live:

```
drag-lint.exe lsp        --db C:\Projects\DataCopy\drag-lint.sqlite --db ... --db library-Win64.sqlite
drag_lint_graph.exe      --db C:\Projects\YADF\YADF.sqlite --db C:\Projects\DataCopy\drag-lint.sqlite ...
drag-lint.exe index --project ... --db C:\Projects\DataCopy\DataCopy.sqlite      <- the reindex
```

So even had the hour-long index completed, **it could not have changed a single answer the IDE
gave.**

This is the *same defect already fixed once*: Task 6 fixed it for `refresh-findings` and left a
comment saying exactly why -- *"Using GetActiveProjectDb directly (the old behaviour) wrote
`<projdir>\<projname>.sqlite`, which for a manifest-covered file is exactly the DB the LSP
deliberately ignores -- so findings never appeared."* The reindex command was never updated.

**Fix:** `ResolveRefreshFindingsDb` -> renamed `ResolvePrimaryIndexDb` (it was never specific
to refresh-findings, and the misleading name is plausibly why the reindex path was missed), and
`InvokeReindexProject` now calls it. Anything that writes an index from the wizard must.

### Defect 2b -- the same bug in every other menu item (full audit)

An audit of all 28 remaining `GetActiveProjectDb` call sites found the defect was **the norm,
not the exception**. It affects readers as badly as writers, and on DataCopy it had already
broken them all: `GetActiveProjectDb` returns `<projdir>\<projname>.sqlite`, a file that
**does not exist** for any project whose index is named differently -- so Hover, Impact,
Wiring, Class Surface, Symbol Slice, Type at Cursor, Find Dead Code, Compiler Hints, Top
Symbols, Find Undocumented, Circular Uses, Uses Audit/Report, Reverse Call Tree, Butterfly,
Symbol Search, Rename, Generate Docs/Test, Export Enums/Graph/Obsidian and Forms CSV were all
querying a nonexistent DB and reporting "no index found".

**27 call sites** were switched to `ResolvePrimaryIndexDb`. Two were deliberately left:

| Site | Why it stays |
|---|---|
| `ResolvePrimaryIndexDb`'s own `if Result = '' then Result := GetActiveProjectDb` | It *is* the fallback. Rewriting it makes the function call itself. |
| `InvokeLintAll`'s third tier | It already tries `ResolveActiveIndexDbs`, then `ManifestDbForFile`, and only then falls back -- the same chain `ResolvePrimaryIndexDb` implements. |

Writers among the 27, where the wrong DB actually corrupted state rather than merely
answering nothing: **`InvokeImportLog`** (`import-log --db` writes `compiler_findings`) and
**`InvokeAutoDocumentProject`**, whose batch is *index -> document --apply -> index*; that
third step exists precisely to keep hover/LSP correct after `--apply` shifts line numbers, and
aimed at the wrong DB it produced exactly the staleness it was meant to prevent.

The replacement was done with a scripted, reviewed pass (dry-run first, 27 lines listed and
checked before applying) rather than a blind find/replace -- prose inside `{ }` comment blocks
mentions the name too and must not be rewritten.

---

## Feature -- Format Whole Project with YADF

`Format with YADF` only ever acted on the current editor file; `drag-lint format` takes a
single `<file>` (handing it a directory answers `File not found`, exit 2). Added
`InvokeFormatProjectYadf`, registered next to it in the root menu.

**It refuses to run on unsaved work rather than saving for the user.** `format` rewrites files
on disk and the IDE then reloads them, so an editor buffer with unsaved edits is silently
discarded on reload. A `SaveAll` would quietly commit edits the user never chose to commit;
not saving destroys them. Neither is ours to decide across a whole project, so the command
stops and names the offending units (capped at 15 + "and N more", in project order).

Supporting helpers:

- `ActiveProjectUnits` -- the project's `.pas` **members**, not the project folder. A loose
  unit beside the `.dproj` is not reformatted: nothing compiles it and it may be scratch.
- `UnsavedProjectUnits` -- dirty detection by **byte-diff against disk**, not an `IOTAModule`
  Modified flag, which is not exposed on this OTA interface version. Same technique and same
  reason as the pre-existing `CollectUnsavedOverlays`.

Then a confirmation dialog (it rewrites every unit in place), one `format` line per unit, and
a trailing re-index. No `|| exit /b 1` between the format lines -- one unit YADF cannot parse
must not abandon the rest half-formatted -- while the re-index always runs, so the index
matches whatever ended up on disk. It goes through the job queue with the LSP stopped in
`OnPreRun`, since the trailing index needs the exclusive WAL lock.

**Not automatically verifiable:** the console suite does not link the form units, so a green
suite says nothing about this menu item. It is compile-verified and follows the established
job-queue pattern; the unsaved-guard and the formatting run still want a manual pass in a live
IDE.

---

## Verification

- New battery runner **`tests/autotest/run_index_project_scope.ps1`**. It asserts the resolved
  scope FIRST and hard-exits if that fails, *without* starting an index -- with the bug present
  a real index runs for hours, so a naive test would hang the battery instead of failing it.
  Red before the fix (`resolved 153 folder(s); 152 outside the project tree`), green after
  (`resolved 1 folder(s); 0 outside`). It also pins `.dpr` and `.dfm` coverage, so a future
  switch to pure-closure mode fails loudly.
- `DataCopy` reindexed with the fixed engine: **2 scan folders, 35 files, 3,000 symbols, 16,802
  refs, 11.9 s**, 0 files outside `C:\Projects\DataCopy`, 9 `.dfm` + 2 `.dpr` present, schema
  v19 facts populated -- written to `drag-lint.sqlite`, the DB the IDE actually reads.
- The abandoned 184 MB partial index is parked at
  `C:\Projects\DataCopy\DataCopy.sqlite.abandoned-runaway` (plus its `-wal`/`-shm`) and can be
  deleted.

### One self-inflicted detour worth recording

The blanket rename was done with `sed -i` on a `.pas` file, which rewrote all 4,911 line
endings from CRLF to LF. `tests/autotest/run_encoding_guard.ps1` caught it -- that guard exists
because a previous task did the identical thing to two `.pas` files. **Do not use `sed -i` on
`.pas`/`.dfm`/`.ps1` in this repo**; `.gitattributes` declares `text eol=crlf` for all three.
The file was renormalized and the guard re-run.
