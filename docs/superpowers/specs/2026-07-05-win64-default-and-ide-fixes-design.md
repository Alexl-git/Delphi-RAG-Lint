# Win64-by-default + IDE Structure/Encoding Fixes (Design)

Date: 2026-07-05
Status: approved (user policy ruling, in-session)
Scope: plugin exe resolution, Structure tab, source-encoding ingest, read-only DB opens. Ships as v0.86.0-alpha.

## User ruling (verbatim intent)

> We decoupled the 32-bit IDE and 64-bit drag-lint. Unless this is an IDE bpl it
> should be 64 bit by default. Maintain 32-bit "just in case" for a release, but
> if the OS is 64-bit all should default to 64-bit except the IDE.

## Findings this design responds to (all root-caused 2026-07-05)

1. **Structure tab "Code Elements 0"**: the tab shells `outline --format json`
   via ITS OWN resolver that picks `<bpl-dir>\drag-lint.exe` = the WIN32 exe
   (stale 0.84, FTS5-less sqlite). The win32 exe prints preamble + a
   DROP-TRIGGER block BEFORE the JSON; the plugin merges stderr+stdout into one
   pipe and `ParseJSONValue` fails on the leading noise -> 0 symbols (cached).
   The win64 exe with identical args returns all 240 BASICSF symbols.
2. **Win32-exe leakage inventory** (all resolve bpl-dir first): StructureForm
   `ResolveExePath` (:157), LiveDiagnostics (:664), ProjectNotifier
   `ResolveExePath` (:128), Editor `DLExe` (:2457, the DLExe64 fallback).
   Keyboard's `DLExtractMethodExe` is already 64-first. Heavy verbs already use
   `DLExe64`.
3. **FTS5 trigger-drop side effect**: any win32-exe DB open runs Migrate, and
   its missing-FTS5 branch DROPS the `string_literals` sync triggers on the
   SHARED DB -- a read-looking verb (outline) mutates the index. Triggers come
   back on the next win64 index run, but text search silently degrades between.
4. **SOFTWID.PAS skip** (`EEncodingError`): the file is VALID CP1252 (a
   copyright resourcestring with 0xAE/0xA9). The whole text pipeline assumes
   source bytes are UTF-8 (tree-sitter TSInputEncodingUTF8 + all
   `TEncoding.UTF8.GetString` slice helpers); 0xAE/0xA9 are invalid UTF-8 ->
   literal extraction throws -> file skipped. Bisect-proven.
5. **Diagnostics ordering**: Structure tab lists messages in cache order; with
   ~400 findings per file the list is unusable without line-number order.

## Design

### D1. Single shared exe resolver -- 64-bit default (policy)

New tiny unit `src/delphi-plugin/DragLint.Plugin.ExeResolver.pas`:

```pascal
/// <summary>Resolves the drag-lint CLI executable for ALL plugin spawn sites.
/// Policy (2026-07-05): the IDE BPL is the only 32-bit artifact; everything it
/// spawns defaults to the Win64 build. Order:
///   1. Settings ExePath override (set + exists);
///   2. <bpl-dir>\..\dll-win64\drag-lint.exe   (the Win64 staged exe -- DEFAULT);
///   3. <bpl-dir>\drag-lint.exe                (Win32 sibling -- "just in case");
///   4. bare 'drag-lint.exe' (PATH).</summary>
function DragLintExe: string;
```

- Replace the bodies of: Editor `DLExe`/`DLExe64` (both delegate; keep names so
  call sites do not churn), StructureForm `ResolveExePath`, LiveDiagnostics'
  inline resolution, ProjectNotifier `ResolveExePath` (settings override
  semantics preserved), Keyboard `DLExtractMethodExe` (delete the KEEP-IN-SYNC
  copy, call the shared one).
- Win32 exe REMAINS built + staged + packaged in releases (unchanged build
  scripts, pack-lint-release keeps both zips).

### D2. Structure tab robustness + diagnostics sort

- `ParseOutlineJson` (StructureCache.pas): slice the payload from the FIRST
  `[` through the LAST `]` before parsing (the lint-store harness precedent);
  parse failure -> empty result, as today.
- `RunAndCaptureSurface`: stop merging stderr into the JSON pipe -- give
  stderr its own pipe (drain it; log tail on nonzero exit via DLT).
- `BuildTree` (StructureForm.pas): sort `FDiags` by `Line` ascending (stable;
  ties keep cache order) before inserting under "Diagnostics (N)". Code
  Elements are already position-ordered by the CLI (`outline` contract).
- Structure cache invalidation stays as-is (RefreshForFile already invalidates).

### D3. Encoding: transcode-at-ingest (fixes SOFTWID-class skips)

One helper at the byte-ingest boundary, used by BOTH the indexer
(`TIndexer.IndexFile`) and the lint/AST parse path (`Diagnostics.ParseCache`):

```pascal
/// <summary>Returns ABytes as valid UTF-8 for the parse/slice pipeline.
/// UTF-8 BOM: stripped. UTF-16 BOM: transcoded. Valid UTF-8: returned as-is.
/// Anything else is treated as ANSI (CP1252) and transcoded to UTF-8.</summary>
function EnsureUtf8Bytes(const ABytes: TBytes): TBytes;
```

- Validation = strict UTF-8 scan (no exceptions for control flow).
- The content sha256 stays computed over the RAW file bytes (file identity /
  up-to-date checks unchanged).
- Consequence: refs/symbols columns on lines containing high-bytes are byte
  columns of the TRANSCODED text (may shift by +1 per 2-byte char). Accepted:
  rare, and today those files are not indexed at all.
- Fixture: a SOFTWID-like unit with 0xAE/0xA9 in a resourcestring must index
  (symbols > 0, 0 errors) and its literal must be text-searchable.

### D4. Read-only opens for query verbs (stops DDL-on-read)

- `TSQLiteSymbolStore.Create(APath, AReadOnly)` (default False): read-only
  opens SKIP Migrate entirely (no DDL, no trigger drops) and set FireDAC
  OpenMode=ReadOnly.
- Read verbs pass AReadOnly=True: outline, query (all subcommands), find-unit,
  surface, context, dump-refs, resolve-dbs consumers. Write verbs (index,
  import-log, forms-csv which Migrates today, lint-all if it writes caches)
  unchanged.
- Old-schema guard: on read-only open, check `schema_meta.schema_version`; if
  < current, fail with the actionable message
  `index schema vN < vM: run "drag-lint index <dir> --db <db>" to migrate`
  instead of surprising field errors.
- This kills finding 3 for EVERY exe bitness, independent of D1.

## Out of scope

- Making the win32 sqlite FTS5-capable (ship newer sqlite3.dll for win32) --
  tracked as a backlog note, not this milestone.
- CLI suppressing its stderr preamble under --format json (D2's slicing makes
  it moot for the plugin; revisit if other JSON consumers appear).

## Release

v0.86.0-alpha: version bump, CHANGELOG, both platforms rebuilt + staged (win32
restaged so the "just in case" exe is current), zips + tag + GitHub release
(mirror v0.85 mechanics). Plugin BPL rebuilt + restaged; user smoke: Structure
tab on BASICSF.pas shows sorted diagnostics + ~240 code elements; reindex log
shows SOFTWID.PAS indexed (not skipped).

## After this milestone

Next refactoring on the APPLY frontier: **Change Signature**
(REFACTOR-LIST.md "recommended next"): reuses rename's cross-unit machinery +
Extract Method's liveness; brainstorm -> spec -> plan as its own milestone.
