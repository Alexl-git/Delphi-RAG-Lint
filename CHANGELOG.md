# Changelog

All notable changes to Delphi-RAG-Lint. This project is **alpha -- expect
breaking changes** until v1.0.

## v0.65.1-alpha -- 2026-06-29

IDE plugin release: the **R2 background job queue + dock status bar**, plus **clickable
lint findings** in the Messages view -- and one CLI false-positive fix.

### Added (IDE plugin)
- **R2 background job queue** -- reindex / lint-all / forms-csv now run through one
  serialized worker thread, so they no longer collide on the project SQLite DB
  ("database is locked"). `forms-csv` no longer freezes the IDE (it was a synchronous
  UI-thread call). Duplicate enqueues coalesce by key; clean join-on-shutdown.
- **Dock status bar** -- a strip along the bottom of the drag-lint dock window shows the
  running job + live %, queue depth ("N queued"), the last result, and a **Cancel**
  button (clears pending jobs). New units `DragLint.Plugin.JobQueue` +
  `DragLint.Plugin.StatusBar`.
- **Clickable lint findings** -- Run Lint All posts each finding to the IDE **Messages**
  view as a tool message; double-click jumps to `file:line`. Capped at 2000/run so a
  huge project cannot flood the pane (the full list still opens as the report).

### Fixed
- **`float-equality-comparison` no longer fires on a quoted string/char literal operand**
  (e.g. `SS = '+'`, `SS = '-.'`). A quoted literal is never a float, so it now forces
  string context -- this guards against the flat (no-scope) type map mis-resolving a
  same-named variable to a float when another routine declares it `Double`. Regression
  fixture `float-equality-string-fp` (FP silent + a real `i = 0.0` still fires). Harness 79/79.
- Status bar no longer crashes dock creation ("control has no parent window"): layout
  moved out of the constructor into a `Resize` override, so no window handle is forced
  before the panel has a parent.

### Notes
The IDE plugin ships as the Win32 BPL in the repo (`third_party/dll-win32`). The release
zips are the CLI (one FP fix over v0.65.0).

---

## v0.65.0-alpha -- 2026-06-29

CLI-side false-positive fixes and internal tidies. The R2 IDE job queue + dock status
bar (Stream B) are being developed on a separate branch and will land in a later
prerelease after manual IDE testing.

### Fixed

**Project-membership false positives** (from the ORM3 field report,
`LINT-FALSE-POSITIVES-20260628.md` FP-8 / FP-9)
- **FP-8 `unit-not-in-dpr` mis-parsed the `.dpr`/`.dpk` uses clause.** Form-name hints
  (`uMain in 'uMain.pas' {frmMain}`) and compiler directives (`{$IFDEF}` / `{$ENDIF}`)
  were extracted as if they were unit names. The clause is now comment-scrubbed first
  (`{...}`, `(* *)`, `//`, string literals preserved) so only real `Ident` /
  `Ident in 'file.pas'` entries are treated as units. A stray `;` inside a hint can no
  longer truncate the clause.
- **FP-9 `unit-not-in-project` broke on dotted unit names.** `ChangeFileExt` stripped
  `.ViewModel` from `Foo.ViewModel` as if it were a file extension, so a unit registered
  as `Foo.ViewModel.pas` never matched the used `Foo.ViewModel`. Normalization now strips
  only known source extensions (`.pas`/`.dpk`/`.dpr`) and both sides of every comparison
  use the same `NormUnit`.
- **FP-9: `*_SERVER` units are no longer flagged** against a CLIENT/COMMON project --
  they belong to the sibling SERVER project (scope error).

> The bulk of the `unit-not-in-project` volume (third-party `dx*`/`cx*`/EurekaLog units,
> generated `COMMON\OBJECTS\` units) is an index-coverage / search-path-resolution problem,
> deferred to v0.66 as a dedicated project-membership accuracy feature.

**Internal (`CheckSyntaxErrors`)**
- `BuildConditionalRanges` now reuses the once-decoded upper-cased source instead of
  decoding the file again and upper-casing every line.
- The conditional-region spanning check is now per-range, so a file with several separate
  `{$IF}..{$IFEND}` blocks correctly suppresses an error node straddling a middle block
  (previously only the outer first..last hull was tested).

### Internal / tests
- Pure parsing/normalization helpers split into the dependency-free unit
  `DRagLint.Lint.ProjectChecks.Parse` (no SQLite/FireDAC/Core), unit-tested by a new
  `tests\projectchecks\` console harness (21/21).

### Notes
All 78/78 lint fixtures + 21/21 project-checks tests pass.

---

## v0.64.1-alpha -- 2026-06-29

Fix-forward release completing and correcting v0.64.0-alpha (which shipped with several
items unreviewed/incomplete).

### Added / Completed

**IDE plugin**
- **All plugin commands now use the Win64 `drag-lint.exe`** (via a shared `DLExe64`
  resolver preferring `..\dll-win64\`), not just LSP + lint-all. Heavy commands
  (Analyse/References/compile-check/ghost-recover/check-ast/find-usages/symbol-search/
  forms-csv/rename/format/index/etc.) no longer run the 32-bit exe, which OOMed on large
  indexes. Falls back gracefully when the Win64 exe is absent.
- **Run Lint All streams live progress** to the IDE Messages view (completes the
  v0.64.0 "IDE plugin TBD"): `RunCaptureStreaming` reads the child pipe line-by-line and
  posts throttled `lint-all: [i/N] NN% file` updates on the main thread (`TThread.Queue`).

### Fixed

**False positives / rules**
- **Fortification (real guards, replacing v0.64.0's documentation-only stub):**
  - `large-magic-number` now exempts 0/1/-1/2, powers of two (4,8,...,65536), and hex
    literals from firing.
  - `string-equality-comparison` now skips comparisons where an operand is a numeric,
    `nil`, or boolean literal (conservative heuristic pending the v0.65 type resolver).
  - Each backed by a RED->GREEN negative fixture that also asserts the rule still fires.
- **FP-1 `{$IF}/{$IFEND}` cleanup:** hoisted the directive scan (removed a per-error-node
  O(N) source re-decode), removed dead code, fixed an `{$IFEND}` open/close double-match,
  and narrowed the line-1 root-error suppression so a genuine line-1 error still fires.
  The `syntax-error-ifend` fixture now also asserts a genuine error fires (line 17).

### Changed
- `lint-all --quiet` is now documented in `--help`.

### Notes
All 78/78 test fixtures pass. (FP-2..FP-9 from the field false-positive report are
scheduled for v0.65, along with the grep-elimination indexer wishlist.)

---

## v0.64.0-alpha -- 2026-06-28

### Added

**Performance & Visibility**
- **Parse-once optimization** -- Per-file parse cache in `TAstParseCache` so all ~36
  `TAstChecker` methods reuse one `TTSTree` instead of each re-reading and re-parsing
  the file. Expected: materially faster `lint-all` on large projects.
- **Lint-all progress streaming** -- CLI streams per-file progress to stderr; IDE
  plugin reads incrementally and posts throttled progress updates (v0.64 IDE plugin TBD).

**False-positive fixes**
- **FP-1: `{$IF}/{$IFEND}` syntax-error suppression** -- `CheckSyntaxErrors` now
  detects unbalanced conditional-compilation directives and suppresses ERROR/MISSING
  nodes within those regions. This eliminates ~12 false positives in codebases using
  `{$IF}/{$IFEND}` blocks that the tree-sitter grammar cannot fully parse.
- **Fortification audit** -- Documented known false positives in `string-equality-comparison`
  and `nil-comparison` rules pending type-aware guards (v0.19+ milestone). Fixtures added
  to guide future type-resolution integration.

### Notes

All 76/76 test fixtures pass. Harness includes syntax-error-ifend fixture (FP-1 guard test).

---

## v0.63.0-alpha -- 2026-06-28

### Added

Eleven new built-in (`TAstChecker`) lint rules and an IDE menu command. Each rule
ships with a TDD fixture under `tests/lint/` verified by
`tests/lint/run_lint_tests.ps1` (75/75 green). Built-ins are compiled into the
exe (no `.scm`/`.json`); a Win64 rebuild is required to add one.

**Security**
- **`unsafe-shellexecute`** (error) -- `WinExec`/`ShellExecute`/`CreateProcess`
  called with a non-literal command/executable argument (command injection, CWE-78).
- **`path-traversal`** (warning) -- `AssignFile`/`FileOpen`/`CreateFile`/`TFile.Open`
  whose path argument is a string concatenation (CWE-22).

**Bugs / control flow**
- **`loop-executes-at-most-once`** (warning) -- a `for`/`while`/`repeat` whose first
  body statement is `Exit`/`Break`/`raise`.
- **`format-argument-count`** (error) -- `Format('...', [...])` specifier count does
  not match the argument count.
- **`format-specifier-type-mismatch`** (error) -- a literal `Format` argument whose
  type is incompatible with its specifier family.
- **`try-except-swallowed`** (warning) -- a `try..except` whose handler neither
  re-raises nor logs nor calls `Application.HandleException`.
- **`virtual-method-in-constructor`** (warning) -- a constructor that calls a
  `virtual`/`dynamic`/`override` method declared in its own class; the call
  dispatches to a descendant override before that descendant is initialised.

**Resource / lock safety**
- **`dataset-open-without-close`** (warning) -- a dataset opened (`X.Open` /
  `X.Active := True`) without a matching `Close` in a `finally` block.
- **`criticalsection-not-released`** (error) -- `X.Enter`/`X.Acquire` without a
  matching `Leave`/`Release` in a `finally` block.

**Metrics**
- **`too-many-exit-points`** (info) -- a routine with more than 5 `Exit` statements.
- **`cyclomatic-complexity`** (info) -- a routine whose decision-point count exceeds 15.

**IDE**
- **Drag-Lint > Run Lint All (Full Report)** menu command in the wizard BPL --
  spawns `drag-lint lint-all` on the active project in the background, opens the
  report, and posts a summary to the Messages view.

### Notes

- **`virtual-method-in-constructor`** shipped as a pure-AST, same-file check
  (no DB). The original DB-backed design was dropped: the index's `modifiers`
  column records only visibility (`public`/`protected`/...), not
  `virtual`/`dynamic`/`override`, so the attribute is read straight from each
  class's declaration in the file being linted. This covers the common
  same-class case; cross-unit ancestry (calling an inherited virtual declared in
  a base unit) still needs the planned type resolver.

## v0.62.0-alpha -- 2026-06-28

### Added

Nine new pure `.scm` lint rules (no exe rebuild required to add a query rule;
each ships with a TDD fixture under `tests/lint/` verified by
`tests/lint/run_lint_tests.ps1`):

- **`unsafe-string-api`** (warning) -- calls to `StrCopy`/`StrCat`/`StrPCopy`/
  `StrMove`/`StrPos`/`StrLen`, unbounded C-style PChar routines with no length
  guard. Prefer `System.AnsiStrings` equivalents or the string/`TStringHelper` APIs.
- **`deprecated-rtl-function`** (info) -- `OemToAnsi`/`AnsiToOem`/`StrPas`,
  obsolete RTL routines; prefer `TEncoding` / modern string APIs.
- **`sleep-in-vcl`** (warning) -- `Sleep()` on the main thread freezes the VCL
  UI; use `TTimer` for delays or `TThread.Sleep` in a background thread.
- **`constant-condition`** (warning) -- `if True`/`if False`/`while False`, an
  always-constant condition (dead code or logic error). `while True` (event
  loop) is intentionally left alone.
- **`ifthen-both-branches`** (warning) -- `SysUtils.IfThen` evaluates both
  arguments before calling; side effects in either branch always execute. Use a
  real `if`/`then`/`else` when branches have side effects.
- **`sizeof-pointer-assumption`** (warning) -- `SizeOf(Pointer) = 4`/`8` bakes
  in a platform assumption (breaks across Win32/Win64). Guard with
  `{$IFDEF WIN64}` or compare to `SizeOf` of a platform-aware type.
- **`pchar-arithmetic`** (warning) -- `+`/`-` on a PChar-named variable;
  pointer arithmetic is unsafe and platform-specific. Use `PChar[N]` or string APIs.
- **`boolean-result-returned-directly`** (info) -- redundant
  `if Cond then Result := True else Result := False`; write `Result := Cond`
  (or `Result := not Cond`) directly.
- **`concat-in-loop`** (info) -- `S := S + X` self-concatenation is O(n^2);
  accumulate with `TStringList` or use `string.Join`, especially inside loops.

## v0.61.0-alpha -- 2026-06-26

### Added

- **`global-form-variable` lint rule** -- warns on unit-level variables whose
  declared type is a form class (potential memory leak if the form is created
  more than once without cleanup). Fires only when a sibling `.dfm` confirms
  this is a form unit. Detected via built-in AST check; works in live edit mode.
- **`unit-not-in-project` lint rule** -- `lint-project` cross-checks every unit
  used by the indexed project against the platform library DB and the project's
  `.dpr`/`.dproj`. Reports units that are neither a known library unit nor
  formally registered as a project member.
- **`frmGridLayout` popup note** -- `forms-csv` no longer labels `frmGridLayout`
  as "DEAD FORM"; it now shows "popup via TGridMenuPopup (Save/Load Layout)" in
  the Notes column. A `KnownPopupForms` table in `FormsMap.pas` generalises the
  pattern for future popup-only forms.
- **`lint-all` batch command** -- `drag-lint lint-all [--db <idx>] [--project
  <.dproj>] [--disable id,...] [--output <file>]` runs every per-file AST rule
  over all `.pas` files in the project index, then all project-wide rules
  (god-class, unused-public-symbol, interface-reference-cycle, layering, unit
  membership), applies `drag-lint:ignore` suppressions, and writes a consolidated
  report. Files that trigger encoding errors are skipped with a stderr notice.
  Exit 1 if any findings, 0 if none.

## v0.60.0-alpha -- 2026-06-26

### Added

- **Two-DB model** -- CLI consumers (`query`, `lint`, `forms-csv`, `resolve-dbs`)
  now auto-select the correct platform library DB with no `--db` flags needed.
  Platform is detected from the first `.dproj` found in the manifest section that
  covers the current working directory (`<Platform Condition=...>` element); falls
  back to `--platform` flag, then manifest `defaultPlatform`.
- **`index` manifest auto-DB** -- `drag-lint index <path>` without `--db` now
  looks up the manifest section covering `<path>` and uses that section's DB
  (e.g. `index C:\Projects\DB\ORM3\CLIENT` auto-selects
  `C:\Projects\DB\ORM3\drag-lint.sqlite` even when run from a different directory).
- **Plugin platform-aware library DB** -- the IDE plugin's `ResolveActiveIndexDbs`
  now reads `indexes.outDir` from the manifest beside the engine exe and calls
  `IOTAProject.CurrentPlatform` to pick `library-Win64.sqlite` for Win64 projects
  instead of always using `library-Win32.sqlite`.

## v0.59.4-alpha -- 2026-06-24

### Added

- **"Copy All Diagnostics" context menu** -- right-clicking in the Structure
  panel's diagnostic tree now includes a "Copy All Diagnostics" item (below a
  separator). Clicking it copies all diagnostics for the current file to the
  clipboard as plain text, one per line:
  `[sev] (line:col) message  [rule-code]`
  prefixed with the file path. Handy for pasting into bug reports or search.

## v0.59.3-alpha -- 2026-06-24

### Fixed (critical -- reindex FTS5 crash, third pass)

- **Root cause identified**: the Embarcadero SQLite 3.45.3 (64-bit) lacks
  `SQLITE_ENABLE_FTS5`. The v0.59.2 probe correctly detected this and set
  `FFts5Available=False`, but the `DROP TRIGGER` calls that follow need an
  **exclusive WAL lock** -- and the LSP server's concurrently-open connection
  blocks that lock, causing `DROP TRIGGER` to fail silently (swallowed by
  `TryExec`). The FTS5 sync triggers from a prior index run remained alive,
  so every `INSERT INTO string_literals` still fired them and crashed.

  Three-layer fix:

  1. **`PRAGMA busy_timeout = 5000`** (Connect): gives `DROP TRIGGER` up to
     5 seconds to acquire the exclusive lock once the LSP releases its reader,
     instead of failing instantly with `SQLITE_BUSY`.

  2. **`UpsertStringLiteral` / `DeleteStringLiteralsForFile` guard**: when
     `FFts5Available=False`, both methods are silent no-ops. Even if `DROP
     TRIGGER` still fails despite the timeout, the triggers can never fire
     because we never touch `string_literals`. This is the definitive backstop.

  3. **Plugin: stop LSP before indexing** (requires IDE restart to load new
     BPL): `InvokeReindexProject` now stops `GLspClient` on the UI thread
     before spawning the background indexer, eliminating the WAL lock race
     entirely. The LSP is restarted lazily on the next hover/query.

  Side effect: when FTS5 is unavailable the `string_literals` table is not
  updated during reindex (text search returns an informative error). This is
  correct -- without FTS5 the text-search index is unusable regardless.

## v0.59.2-alpha -- 2026-06-24

### Fixed (critical -- reindex FTS5 crash, second pass)

- **FTS5 probe via temp table** -- the v0.59.1 fix used `CREATE VIRTUAL TABLE
  IF NOT EXISTS string_fts USING fts5(...)` to detect fts5 availability, but
  `IF NOT EXISTS` short-circuits silently when `string_fts` already exists in
  the DB from a prior fts5-capable index run. This left `FFts5Available=True`
  while the module was absent, so the sync triggers still fired on every
  `INSERT INTO string_literals` and crashed with the same FATAL error.
  Fix: probe by creating `temp.fts5_probe USING fts5(x)` -- a throw-away temp
  virtual table that is always independent of what tables exist in the main DB.
  If the probe fails, any leftover sync triggers are dropped so INSERTs into
  `string_literals` cannot reach the fts5 module at all.

## v0.59.1-alpha -- 2026-06-24

### Fixed (critical -- reindex FATAL crash)

- **FTS5 graceful degradation** -- reindexing any project crashed with
  `ESQLiteNativeException: no such module: fts5` on the default Embarcadero
  SQLite DLL (which is built without `SQLITE_ENABLE_FTS5`). The v0.58
  text-constant index added FTS5 virtual tables; `Migrate()` ran them inside the
  main transaction, so the first `CREATE VIRTUAL TABLE ... USING fts5` aborted
  the entire migration. Fix: FTS5 DDL is now applied outside the core
  transaction and silently skipped if the fts5 module is absent. All other
  drag-lint features continue to work normally; only `query --text` will report
  "FTS5 not available" on affected SQLite builds.

## v0.59.0-alpha -- 2026-06-24

### Fixed (IDE plugin)

- **Find Usages tab name restored** -- the tab was briefly renamed "Blast Radius"
  in v0.58.0-alpha, which was semantically incorrect. Blast Radius (transitive
  impact analysis, callers of callers, N levels deep) is a separate future feature
  that needs engine work. The current tab shows direct usages and is named
  "Find Usages" again.

### Improved (index diagnostics)

- **Binary DFM detection** -- before parsing, the DFM indexer now detects binary
  (TPF0) DFMs (`$FF` magic byte) and emits a clear advisory message instead of
  a generic "parse contains syntax errors". Fix: save the form as Text DFM in the
  IDE (`File > Save As Text`).
- **Located parse errors** -- when tree-sitter reports syntax errors, both the DFM
  and Delphi 13 parsers now walk the ERROR/MISSING nodes and report each as
  `file(line,col): parse error [TYPE]` (up to 10 per file) instead of a single
  generic string. The reindex report in the IDE now shows exact source locations.
- **Win64 build output excluded** -- `"Win64"` added to the global `exclude` list
  in `drag-lint.json`. Build output dirs (`Win64\Debug\`, `Win64\Release\`, etc.)
  are pruned from all index walks, eliminating stale DCU/EXE content from results.

### Fixed (IDE plugin -- LSP freshness after reindex)

- **LSP restart after reindex** -- after "Reindex This Project" completes, the
  plugin now stops and frees `GLspClient` on the main thread so the next query
  (hover, Find Usages, Search) uses the freshly built index. Previously the LSP
  server kept the old index loaded in memory and queries returned stale data until
  the IDE was restarted.

## v0.58.0-alpha -- 2026-06-23

### Added (text-constant index / query --text)

- `query --text "<phrase>"`: full-text search over indexed string content --
  error messages, DFM captions, SQL exception text, resourcestrings. Searches
  string literals only, never identifiers. Default mode is exact phrase match.
  - `--any-order`: all terms must match in any order (FTS5 implicit AND across tokens).
  - `--substring`: trigram index match; finds the phrase as a substring of a
    literal (e.g. `query --text "password" --substring` catches
    `'Invalid password'` and `'Password mismatch'`).
  - `--source pas|dfm|sql`: restrict to one source kind.
  - `--limit N`: cap results (default 200).
  - `--json`: machine-readable output with `file_path`, `start_line`,
    `start_col`, `source`, `kind`, `owner_name`, `text`, `enclosing` fields.
- **Sources indexed:**
  - Delphi `.pas`: string literals, `const` string constants,
    `resourcestring` declarations, and `Format`-call format strings.
  - DFM `.dfm`: string properties (captions, hints, messages).
  - SQL: `CREATE EXCEPTION` messages -- indexed only from `MS*.sql` files by
    default (migration-script convention). Pass `--no-sql-ms` to index every
    `.sql` file.
- **Engine:** FTS5 with `unicode61` tokenizer (phrase + any-order) and a
  parallel `trigram` FTS5 table (substring). Storage schema v10 adds
  `string_literals` (base table), `string_fts` (phrase/any-order external-
  content FTS5 vtab), and `string_fts_tri` (trigram substring vtab), kept in
  sync via `AFTER INSERT/DELETE` triggers on `string_literals`.
- **Self-diagnostics:** `--selftest-fts5` checks FTS5 availability;
  `--selftest-schema` verifies schema v10 tables and triggers are present.

### Added (IDE plugin)

- IDE plugin: new unified **Search (no grep)** dock tab - one Kind dropdown (Symbol/Text/Usages) + query field + a clickable results grid that jumps to source; Advanced toggle exposes per-kind refinements (kind filter / text mode+source / usages width). Find Usages no longer shows a debug dump on no-results.
- **Blast Radius tab** (renamed from Find Usages) - shows direct usages of a symbol by category (declarations, reads, writes, calls, type-uses, events) and a unit-impact count roll-up; clicking any result jumps to source.
- **Navigation for form units** - clicking a result in any dock tab that refers to a form unit (e.g., `TfrmFoo` in `uMyForm.pas`) now opens the `.pas` code editor directly, not the form designer.
- **Symbol Search tab removal** - folded into the unified Search and Blast Radius tabs; no longer a separate dock tab.

## v0.57.0-alpha -- 2026-06-23

### Fixed (DFM)

- `lint` no longer mis-parses `.dfm` files with the Pascal grammar. The linter
  now selects the tree-sitter grammar by file extension: a `.dfm` is parsed with
  the dedicated DFM grammar (`tree_sitter_dfm`, already used by indexing), so a
  valid form is clean instead of emitting one spurious `parser-error` per Pascal
  set-literal (`[akLeft, akTop, akRight]`, `[]`) and per root `object .. end`.
  A genuinely malformed DFM still surfaces a real `parser-error` from the DFM
  grammar (ERROR/MISSING walk, mirroring `CheckSyntaxErrors`). Only single-file
  `lint <x.dfm>` was affected (folder lint already globbed only `*.pas/*.dpr/*.dpk`)
  -- which is exactly what the on-save hook runs. Reported: every `.dfm` produced
  4-45 false errors; e.g. the 11.5k-line `Blueprint4.dfm` ribbon form went 45 -> 0.

### Tests

- `tests/lint/dfm-valid.dfm` (must be clean) + `tests/lint/dfm-broken.dfm` (must
  flag a real error); `run_lint_tests.ps1` now also globs `*.dfm`. 53/53 pass.

## v0.56.0-alpha -- 2026-06-21

### Added (thread-safety)

- `ui-access-in-thread` (warning): VCL/FMX UI access from a background thread.
  Inside a method named `Execute` whose class (declared in the same file) has a
  base whose name contains `Thread`, it flags strong UI members -- assignment to
  `.Caption`, or calls to `.SetFocus`/`.Repaint`/`.BringToFront` -- that are NOT
  inside a nested anonymous method (a likely `Synchronize`/`Queue` body). Tuned
  for low false positives.

## v0.55.0-alpha -- 2026-06-21

### Added (batch)

- `hardcoded-connection-string` (warning): a string literal with connection-string
  keywords (`Password=`, `User ID=`, `Data Source=`, ...) -- a hardcoded secret (CWE-798).
- `gettickcount-wraparound` (warning): `GetTickCount` wraps after ~49.7 days; use
  `GetTickCount64` for elapsed-time math.
- `hardcoded-ip-address` (info): a string literal that is an IPv4 address.

## v0.54.0-alpha -- 2026-06-21

### Added (architecture)

- `layering-violation` (warning, `lint-project --db --layers <file.json>`):
  config-driven architecture enforcement. Assign units to layers by name globs,
  declare allowed dependencies, and flag forbidden cross-layer `uses` edges.
  Config: `{ "layers":[{"name":"UI","match":["*.UI.*"]},...], "allow":[{"from":"UI","to":["Business"]},...] }`.
  Default-deny among defined layers; units matching no layer are ignored (RTL/3rd-party).
  Pass the config with `--layers`, or place `drag-lint-layers.json` in the working dir.

## v0.53.0-alpha -- 2026-06-21

### Added (batch)

- `uppercase-compare` (warning): `UpperCase(X)`/`LowerCase(X)` compared to a string
  literal -- fragile (silently always-false if the literal's case differs) and slow;
  use `SameText`.
- `outputdebugstring` (info): `OutputDebugString` debug tracing left in code.
- `length-zero-compare` (info): `Length(X) = 0` / `> 0` -- for strings prefer `X = ''`.

### Changed

- `float-equality-comparison` now also flags `TDateTime` / `TDate` / `TTime` operands
  (they are `Double`-backed, so `=` / `<>` is unreliable).

## v0.52.0-alpha -- 2026-06-21

### Added (batch)

- `use-after-free` (warning): use of an object after a raw `X.Free` (dangling
  reference) within the same block, until `X` is reassigned. `FreeAndNil(X)` clears
  tracking. Catches the classic `X.Free; ...; X.Something` crash.
- `win64-pointer-cast` (warning): a 32-bit cast (`Integer`/`Cardinal`/`LongInt`/
  `LongWord`) of a pointer-typed value (`Pointer` / `P...`) -- truncates on Win64;
  use `NativeInt`/`NativeUInt`.
- `hardcoded-absolute-path` (info): a string literal that is an absolute drive path
  (`'C:\...'`) -- breaks on other machines; read from config or compute at runtime.

## v0.51.0-alpha -- 2026-06-21

### Added (project-wide)

- `interface-reference-cycle` (warning, `lint-project --db`): class A holds an
  interface implemented by class B, and B holds an interface implemented by A --
  a mutual strong interface reference that leaks under ARC. Parses every indexed
  source file, maps interface implementors and interface-typed fields, and reports
  each mutual pair. Fix by marking one side's field `[weak]` or `[unsafe]`.

## v0.50.0-alpha -- 2026-06-21

### Added (resource lifetime)

- `unprotected-object-free` (warning): a locally-created object freed without
  try-finally protection -- it leaks if code between creation and `Free` raises.
  Per routine, correlates `X := ...Create...` with a later `X.Free` / `FreeAndNil(X)`
  on the same variable that is NOT inside a `finally` (so destructor field-frees and
  correctly-protected frees are not flagged).

## v0.49.0-alpha -- 2026-06-21

### Added (FireDAC)

- `firedac-open-execsql-mismatch` (warning): `Open` on a data-modifying statement
  (INSERT/UPDATE/DELETE) or `ExecSQL` on a SELECT. Correlates a literal
  `X.SQL.Text := '...'` with a later `X.Open` / `X.ExecSQL` on the same variable,
  in program order -- only fires when the SQL is a recognizable literal.

## v0.48.0-alpha -- 2026-06-21

### Added (more lint rules)

- `not-comparison-precedence` (warning): `not A = B` parses as `(not A) = B`.
- `redundant-not-not` (info): `not not X` double negation.
- `public-field` (info): public data field on a class breaks encapsulation.
- `empty-on-handler` (warning): `on E: ... do ;` empty handler swallows the exception.
- Routine metrics (info, built-in, conservative defaults): `too-many-parameters` (>7),
  `too-many-locals` (>25), `method-too-long` (>120 lines), `deep-nesting` (>5).
- Type-aware (lightweight per-file type map): `float-equality-comparison` (warning):
  `=` / `<>` on `Single`/`Double`/`Extended`/`Real` operands; `freeandnil-on-interface`
  (warning): `FreeAndNil` on an interface-typed variable.
- `locale-sensitive-conversion` (warning): `StrToFloat`/`FloatToStr`/`StrToDate`/... without
  an explicit `TFormatSettings` (locale-dependent cross-machine bug).

### Added (CLI)

- **`--disable id1,id2,...`** on `lint` -- drop those rule ids from the output
  (per-rule control without editing files).

- **Per-line suppression** -- `// drag-lint:ignore` (silence all rules on that
  line) or `// drag-lint:ignore <rule-id> [<rule-id> ...]` (silence specific
  rules). Applies to both `.scm` and built-in rules.
- **`drag-lint lint-project --db <index.sqlite> [--rule <id>] [--json]`** --
  index-wide ("project") lint rules that need the whole symbol/refs graph:
  - `god-class` (info): a class with many methods *and* many fields.
  - `unused-public-symbol` (info): an exported (interface-section) free routine
    with no references/callers anywhere in the index -- possible dead public API.
    (Best for applications; libraries expose API for external callers.)

## v0.47.0-alpha -- 2026-06-21

### Added (lint rule expansion -- 25 new rules)

A research-backed first stage of a real Delphi linter (see
`docs/lint/REPORT-1-delphi-lint-landscape.md` and `REPORT-2-...-implementation-plan.md`).
**20 new external `.scm` rules** (data-driven, hot-loaded from `rules\`) and
**5 new built-in rules** (compiled in; need flow/scope analysis), all TDD-tested
via `tests\lint\run_lint_tests.ps1` (28/28).

- **Exceptions:** `empty-except`, `empty-finally`, `bare-except`,
  `raise-bare-exception`, `reraise-loses-stack`, `raise-in-finally` (built-in),
  `control-flow-in-finally` (built-in).
- **Control flow / dead code:** `empty-conditional`, `empty-loop-body`,
  `empty-case-branch`, `not-in-precedence`, `off-by-one-count`,
  `code-after-exit` (built-in).
- **Expression bugs:** `comparison-same-operands`, `division-by-zero-literal`,
  `nil-comparison`, `self-assignment`, `classname-string-compare`,
  `boolean-comparison-true` (now also `<>`).
- **Resources / clarity:** `redundant-assigned-free`, `with-multiple-items`,
  `inline-assembly`, `assert-call` (now single-arg only),
  `missing-inherited-ctor` / `missing-inherited-dtor` (built-ins).
- **Security:** `sql-injection-concat` (CWE-89), `hardcoded-credential`
  (CWE-798; `var` and `const`).
- Refined `compiler-magic-comments` to also flag `BUG`.

### Added (CLI)

- **`drag-lint lint <file> --rules-dir <path>`** -- point the linter at an
  explicit external-rules folder (CI / IDE / testing).
- `lint` now prints a one-line note to stderr when **0** external `.scm` rules
  are loaded, so a missing `rules\` folder is no longer silent (built-in checks
  still run).

### Packaging

- The release archive now bundles the `rules\` folder next to `drag-lint.exe`
  (required for the `.scm` rules to load). See `INSTALL.md`.

## v0.44.0-alpha -- 2026-06-14

### Added (forms-csv test-helper navigation map)
- **`forms-csv --project <dproj> --db <sqlite> [--out <f.csv>] [--root <TfrmMAIN>]`**
  -- emits a tester-oriented CSV, one row per navigable form (forms/dialogs only;
  data modules and frames excluded via class-ancestry). Columns: `#`, `Unit`,
  `FormName`, `PAS lines`, `Navigation`, `Called From`, `Notes`.
  - **Navigation**: the button/menu captions a tester clicks from the application's
    main form to reach each form, e.g. `frmMAIN -> 'Job List' -> 'Open Folder'`.
    Built by resolving form-construction sites (`TfrmX.Create` incl. named ctors,
    `Application.CreateForm`) to their enclosing routine, mapping that to the owning
    form, and reading the bound control's caption from the `.dfm`. Resolves direct
    handlers, handlers reached indirectly within a form, and `TAction` captions;
    falls back to `(via Routine)` when no captioned control binds the launch
    (keep-the-gap), and `(no path from MAIN)` when unreachable. BFS = shortest path;
    cycle-safe.
  - **Called From**: the distinct forms that directly open this one (with captions).
  - Root form auto-detected from the `.dpr` (last `Application.CreateForm` of a form
    at/before `Application.Run`); override with `--root`. Inventory is restricted to
    the project's own units (skips `*- Copy`/`.bak` backups).
  - Requires a **current** index -- re-index the project if rows show mostly
    `(no path from MAIN)` (stale construction-site line numbers break edge detection).
- **IDE plugin: "Generate Test Helper CSV..."** Tools-menu item -- saves all, runs
  `forms-csv` on the active project, opens the CSV.

## v0.43.0-alpha -- 2026-06-12

### Added (semantic diagnostics + uses cleanup)
- **`check-unit <unit.pas> [--project <dproj>] [--platform win32|win64]
  [--shadow <dir>] [--resolve-uses]`** -- compile ONE unit in full project
  context (deps from DCUs) for real semantic errors (`E2003` etc.) without a
  full build. `--shadow` overlays an unsaved-buffer copy so errors reflect edits
  before save, never touching the file. `--platform` matches the project's
  active config (picks dcc32/dcc64 + that platform's RTL lib; avoids `F2048`).
  `--resolve-uses` annotates undeclared identifiers with the unit to add.
- **`cycles --db <sqlite> [--edges] [--causes]`** -- circular unit dependencies
  (Tarjan SCC over the unit-uses graph). `--edges` lists each cycle's actual
  `A uses B [section]` edges, flags interface edges as move-to-implementation
  candidates and layering inversions (COMMON -> CLIENT/SERVER). `--causes`
  pinpoints the specific symbols in A's interface that reference B (the
  types/vars/methods to move/extract), with line numbers and an honest note
  where the index couldn't resolve a ref. `--plan` emits a followable markdown
  refactoring playbook per cycle (files, symbols with use + declaration line,
  an auto-classified fix -- extract-contract or invert-dependency -- numbered
  steps, and a verify command) that a junior dev or small model can execute.
- **`uses-audit <unit.pas>`** -- index proposal of interface->implementation
  moves + unused units (conservative; project units only).
- **`uses-fix <unit.pas> --project <dproj> [--apply] [--remove-unused]`** --
  compiler-VERIFIED uses-clause cleanup: move interface-only imports down,
  optionally comment out unused units (skips those with init/final sections).
  Each edit is shadow-compiled and kept only if it adds no new error vs the
  baseline; dry-run by default, `--apply` writes after a `.bak`. With no
  `<unit>` target it runs a project-wide dry-run sweep report.

### Known limitation (uses-fix)
- `uses-fix`'s per-unit verify is **best-effort, not a faithful full-build
  check**: a single-unit `dcc` compile can reuse a stale `.dcu` (masking a real
  error) or abort on an RTL dependency (`F1026`), so a move that breaks the full
  build can pass per-unit. A safety guard now rejects edits whose verify compile
  *fatally aborted*, but the `.dcu`-reuse case can still false-pass. **Always do
  a full project build after `--apply`**; treat `cycles`/`uses-audit` as
  advisory. Reliable bulk cleanup needs full-project-build verification.

### Fixed
- **Duplicate file rows on re-index.** Mixed-separator stored paths
  (`C:/root\sub\file.pas`) defeated the `files.path` UNIQUE upsert, so each
  re-index inserted a duplicate row and left stale `unit_uses`/refs. Paths are
  now canonicalised at the store boundary; an incremental re-index is a true
  no-op (`skipped N up-to-date`).

### Added
- **Dedicated dockable Graph window.** The graph is now its own
  `INTACustomDockableForm` ("drag-lint Graph", under View > Tool Windows) rather
  than a tab -- so it can sit open beside the Structure window, both visible at
  once. It hosts the standalone viewer **in-place**: the plugin launches
  `drag_lint_graph.exe --parent-hwnd <thisWindow>`, the viewer renders as a
  child filling the window, and the plugin terminates it on close. Jump-to-source
  still flows through the named-pipe contract. (Viewer side: new `--parent-hwnd`
  embed mode.)
- **Hover: IDE-style Parameters block.** Proc-like hovers now break the
  signature into a `**Parameters:**` list (one `name : type` per line, with
  `const`/`var`/`out` preserved) plus a `**Returns:**` line -- mirroring the
  IDE's parameter insight -- even when the symbol has no doc-comment. Works in
  the LSP popup and `drag-lint hover` (which no longer errors on no-doc
  symbols). Generic types stay intact (top-level split respects `<> () []`).
- **Structure window: right-click navigation menu.** Single/double-click still
  goes to the declaration; the new context menu adds **Go to Implementation
  (body)** -- scans the file for the `TClass.Method` body line -- and **Find
  Usages** (opens the usages view for the symbol). Right-click selects the node
  under the cursor first.

## v0.42.0-alpha -- 2026-06-12

### Added
- **`index --scan-libraries-win`** and **`index --scan-libraries-all`**: build a
  single library index from the IDE's registry Library + Browsing paths.
  `-win` covers Win32 + Win64 (the IDE's native targets, and what `--scan-libraries`
  still aliases to); `-all` enumerates **every** platform subkey under
  `...\BDS\37.0\Library` (Android/iOS/Linux64/OSX/Win64x/...), adding the
  platform-specific `source\rtl\posix`, `source\rtl\ios` and `posix\osx` trees so
  `Posix.*` / `iOSapi.*` / `Macapi.*` / `Androidapi.*` symbols resolve. Both
  deduplicate across HKCU+HKLM and 32/64-bit registry views; `$(Platform)` now
  expands per-platform instead of a hardcoded `Win64`.

### Fixed (compiler hygiene)
- Cleared inline-expansion hints (H2443) by adding `FireDAC.Stan.Param` and
  `System.Generics.Collections` to the units that needed them; removed dead
  locals and the superseded `ParseJsonOutput` method (H2164/H2219/W1050).

## v0.41.0-alpha -- 2026-06-05

### Added
- **AI-usage guide** (`docs/AI-USAGE.md`): copy-paste instructions so an AI
  agent drives drag-lint over CLI or MCP, with the token-saving context-bundle
  workflow.
- **Unit initialization/finalization** are now indexed (kinds `initialization`/
  `finalization`), so structure/section views can show them.
- **Symbol `section`** (interface vs implementation) + member **types**
  captured into signatures; `query` shows `section` + `usable_from_other_units`;
  `resolve-uses` is section-aware (won't suggest implementation-only symbols).

### Changed (token economy)
- **Lean context bundle:** `drag-lint context` now slices only the target
  symbol's body (not the whole parent class). `bench-context` on a real project:
  **~556 vs ~33,762 tokens (~60x)**.
- **`--full-surface` switch** (CLI) / `full_surface` (MCP `get_context_bundle`):
  by default the auto-generated published DFM component fields are stripped from
  a form's class surface; pass the switch to keep them when working on the form.

### Fixed
- Plugin open-in-IDE: only `GotoLine` after `OpenFile` succeeds (was scrolling
  the wrong file).
- Indexer skips `__history` / `.git` / backup dirs in folder scans.

## v0.40.5-alpha -- 2026-05-31

### Added (major)

**SQL-aware drag-lint.** Three new capabilities indexed alongside Delphi
and DFM:

- **Tier 1: Firebird DDL extractor** (`src/parser/DRagLint.Parser.Sql.pas`).
  New `IParser` implementation; the indexer dispatches `.sql` extensions
  to it automatically. New `TSymbolKind` values: `skSqlTable`,
  `skSqlColumn`, `skSqlIndex`, `skSqlTrigger`, `skSqlGenerator`,
  `skSqlProcedure`, `skSqlView`, `skSqlException`, `skSqlDomain`,
  `skSqlConstraint`. SQL columns are stored as children of their table
  (same shape as Delphi fields-of-class). Trigger references emit
  `sql_table_ref` rows. Real-world numbers from Micronite
  `C:\Projects\DB\SQL\` (39 files, 14s):

  ```
  489 sql_table   8012 sql_column   619 sql_trigger
  282 sql_generator   193 sql_domain    90 sql_index
    4 sql_view       395 sql_procedure   8 sql_exception
  ```

- **Tier 2: live Firebird snapshot** (`drag-lint fb-snapshot
  --connection "..." --db <sql.sqlite>`). Connects via FireDAC
  `DriverID=FB`, pulls `RDB$RELATIONS`, `RDB$RELATION_FIELDS`,
  `FIB$FIELDS_INFO`, `FIB$DATASETS_INFO`, `FIB$ENUMVALUES` into
  `fb_relations` / `fb_columns` / `fb_field_info` / `fb_datasets` /
  `fb_enum_values`. Each row stamps `snapshot_at` for drift detection.
  Post-pass cross-links `fb_relations.sql_table_symbol_id` and
  `fb_columns.sql_column_symbol_id` to the Tier 1 DDL symbols by name.
  Each `FIB$*` block is wrapped in try/except, so a permission denial
  or schema mismatch on one optional table doesn't abort the snapshot.
  Verified against `MICRONITEV6A.FDB`: 134 relations / 2273 columns /
  2049 field_info / 129 datasets in 0.5s, 99% cross-link rate for
  relations and 93% for columns.

  Required runtime DLLs (Win32, beside `drag-lint.exe`): `fbclient.dll`
  + `icudt63.dll` + `icuin63.dll` + `icuuc63.dll` + `msvcp140.dll` +
  `vcruntime140.dll` + `zlib1.dll`. Source: `%FIREBIRD%\WOW64\`.

- **Tier 3: Delphi ↔ SQL ORM linker** (`drag-lint link-orm --db
  <proj.sqlite> --db <sql.sqlite>`). Cross-references Delphi
  classes/interfaces/fields against SQL tables/columns by Delphi/Micronite
  naming convention (T/I/F-prefix strip). New `orm_links` table records
  `(delphi_symbol_id + delphi_db_index, sql_symbol_id + sql_db_index,
  confidence, link_kind, evidence)`. Cross-DB indices track origin DBs.
  Verified against MICRONITE_V4DataModel.Classes.pas + MS*.SQL:
  158 `class_to_table` + 1367 `field_to_column` bindings at
  confidence 1.0.

### Added (storage)

Schema bumped **v5 → v6** (additive; existing DBs migrate cleanly):

- `fb_relations`, `fb_columns`, `fb_field_info`, `fb_datasets`,
  `fb_enum_values` — Tier 2 snapshot tables
- `orm_links` — Tier 3 cross-DB bindings

`TSQLiteSymbolStore.GetConnection: TFDConnection` exposed as a leaf
accessor for utilities (uses-report, fb-snapshot, link-orm) that need
raw table scans. Intentionally **not** on `ISymbolStore` — calling
code knows it's reaching into the SQLite impl.

### Added (autotest)

Three new SQL-aware checks: `sql_table SAMPLE indexed`,
`sql_generator indexed`, `link-orm command exits 0`. Fixture:
`tests/autotest/fixtures/sample_schema.sql` exercises every Tier 1
DDL kind. Total now **17 PASS** in ~1.5s.

### Notes for the graphing tool

- **Cross-DB symbols**: see `Delphi-RAG-Lint-Graph/docs/cross-db-symbols.md`.
- **SQL symbol contract**: see `Delphi-RAG-Lint-Graph/docs/sql-symbols.md`.

---

## v0.40.2-alpha -- 2026-05-31

### Fixed (critical — IDE freeze)

User pressed `Tools > drag-lint > Test Connection...` on v0.40.1, the
LSP handshake succeeded (confirmed in the debug log), then the IDE
froze for over 2 minutes and had to be killed.

Root cause: `TDragLintLspClient.Stop` did `CloseHandle(FStdOutRead)`
and then `FReaderThread.WaitFor`. On Windows, closing a pipe handle
does NOT reliably unblock a `ReadFile` running on another thread when
the child process still holds the write end open. The reader thread
sat in `ReadFile` forever, `WaitFor` never returned, and the IDE
froze.

Fix in `Stop`:

1. **`TerminateProcess(FProcessHandle, 0)` first** — kills the child
   immediately. Its write end of stdout closes, causing our reader's
   `ReadFile` to return `ERROR_BROKEN_PIPE`. Reader exits naturally.
2. Close the pipe handles next.
3. `WaitForSingleObject(ReaderHandle, 2000ms)` with a hard upper
   bound — `TThread.WaitFor` has no timeout overload, so the raw
   Windows API is the correct primitive here. If the reader still
   hasn't exited in 2s, log it and leak the thread instance (the OS
   will reclaim once the child is fully gone) rather than freezing
   the IDE.
4. Reap the child handle.

Additional belt: **`InvokeTestConnection` now runs Start + Initialize
+ Stop on a `TThread.CreateAnonymousThread`** and posts the report
back via `TThread.Queue`. Even if a future regression makes Stop
slow, the IDE thread is no longer involved.

### Note

The plugin log path now actually matches what the dialogs claim
(v0.40.1 fix). If you saw `C:\TEMP\drag-lint-plugin.log` doesn't
exist after Test Connection on v0.39, that was the bug — the real
log was at `%LOCALAPPDATA%\Temp\drag-lint-plugin.log`.

---

## v0.40.1-alpha -- 2026-05-31

### Added (diagnostics)

- **Plugin version + BPL build timestamp** on every user-visible
  dialog. The new `PluginBuildTag` function reads
  `GetModuleName(HInstance)` + `FileAge` at runtime and reports
  `drag-lint plugin v0.40.1-alpha (BPL built YYYY-MM-DD HH:MM:SS)`.
  Appears at the top of:
  - Tools > drag-lint root entry (`Execute`)
  - `Test Connection...` report
  - `LSP server failed to start` dialog (with BPL dir + resolved exe)
  - `LSP initialize handshake failed` dialog
  - `Open Plugin Log` when no log exists yet
  Lets you verify at a glance that the IDE is loading the BPL you
  just installed, without having to inspect the file modtime by hand.

### Fixed (logging)

- **Plugin log path mismatch** — `DebugLog` wrote to
  `TPath.GetTempPath` while the diagnostic dialogs printed
  `GetEnvironmentVariable('TEMP')`. Under Windows TMP/TEMP precedence
  the two can diverge, so users opened the displayed path and found
  no file. Both now resolve via a single `GetPluginLogPath` function
  with a fallback to "alongside the BPL" if the temp dir isn't
  writable.

### Changed (build output)

- `dclDragLintWizard.dproj` now writes `BplOutput` / `DcpOutput` to
  `..\..\third_party\dll-win32\` instead of `..\..\build\v021\`. The
  staged `drag-lint.exe` + tree-sitter DLLs already live there, and
  it's on the standard PATH the project README recommends, so
  installing the package from RAD Studio puts the BPL right next to
  the exe the plugin resolves. The "next to BPL" lookup succeeds the
  moment install finishes.

---

## v0.40.0-alpha -- 2026-05-31

### Fixed (critical -- IDE plugin AVs)

Two access violations made the v0.16-v0.39 plugin essentially unusable on
real projects:

- **AV during editor paint** -- `TOTAEditView.BeginPaint -> System.TObject.GetInterface`
  recursing into `ElisionParser.ApplyElisions`. Root cause:
  `TDragLintEditServicesNotifier.EditorViewActivated` called
  `EditView.AddNotifier(TDragLintEditViewNotifier.Create)` on every focus
  change without tracking the returned index, so each editor view
  accumulated a growing list of duplicate notifier interface refs.
  Re-installing the BPL (or any path that freed an older instance) left
  the IDE iterating a dangling vtable.
- **AV on IDE exit** -- `TCodeIDocModule.AllowSave -> TInterfaceList.Get ->
  System.@IntfCopy`, forcing users to kill RAD Studio instead of closing
  it cleanly. Root cause:
  `TDragLintSaveNotifier` was added to every opened module's notifier
  list (`AModule.AddNotifier(Self)`) without explicit removal before the
  BPL unloaded.

Fix:
- Both notifier classes now track every `AddNotifier` registration in a
  thread-safe `TList<TRegistration>` with a `TMonitor` lock.
- `RegisterSaveNotifierForModule` and `EditorViewActivated` now dedupe
  -- repeated calls for the same module/view are a no-op.
- `UnregisterAllSaveNotifiers` and `UnregisterAllViewNotifiers`
  iterate the tracker, call `RemoveNotifier(Index)` on each, swallow any
  exception from a partially-destroyed module, and clear the list.
- Three teardown paths trigger these:
  1. `ofnFileClosing` in `TDragLintProjectNotifier.FileNotification`
     drops a save-notifier the moment its module closes.
  2. `TDragLintWizard.Destroyed` calls all three unregisters
     (`UnregisterAllSaveNotifiers`, `UnregisterDragLintEditViewNotifier`,
     `UnregisterProjectNotifier`) before the BPL code segment is dropped.
  3. The unit `finalization` blocks call them again as a safety net.

### Fixed (UI freeze)

- **`Tools > drag-lint > Show Inline Info`** previously called
  `Sleep(4000)` on the IDE UI thread to keep its hint window visible,
  freezing the editor. v0.40 keeps a singleton `THintWindow` + `TTimer`
  with `Interval := 4000` so the auto-close runs without blocking.
  Re-invoking before the timer fires tears down the prior hint and
  restarts the timer.

### Note on the LSP handshake failure

Still pending root-cause -- use v0.39's `Test Connection...` menu to
collect the report. v0.40's fixes are orthogonal (notifier lifecycle vs.
subprocess + pipe setup).

---

## v0.39.0-alpha -- 2026-05-29

### Added (plugin diagnostics)

- **`Tools > drag-lint > Test Connection...`** — runs through the exact
  LSP startup sequence the plugin uses internally and shows a
  human-readable report:
  - BPL path + directory
  - Resolved `drag-lint.exe` candidate (next-to-BPL or PATH fallback)
  - `Start` result (subprocess spawn)
  - `Initialize` result (handshake)
  - Path to the detailed log file
  All without the user having to install/uninstall the package or
  trigger a real hover.

- **`Tools > drag-lint > Open Plugin Log`** — opens
  `%TEMP%\drag-lint-plugin.log` in the user's default text editor.
  When the log doesn't exist yet (first run before any plugin LSP
  invocation), shows an informational dialog.

### Notes

- The Test Connection report is the fastest path to diagnose the
  "LSP initialize handshake failed" error from v0.21-v0.37. Run it,
  share the report.
- The plugin log is timestamped; previous runs append, so check
  the tail of the file for the most recent attempt.

---

## v0.38.0-alpha -- 2026-05-29

### Added (diagnostics)

- **`%TEMP%\drag-lint-plugin.log`** — the IDE plugin's LSP client now
  writes a detailed timestamped log of every subprocess event, send,
  receive, and error to a file in the user's temp dir. Created
  automatically on first plugin invocation; appended thereafter.

  When the plugin shows "LSP server failed to start" or "LSP initialize
  handshake failed", the dialog now includes the log file path.

### Fixed

- **`CreateProcessW` cmd-line did not quote the exe path** — if the BPL
  was installed at a path containing spaces (e.g.
  `C:\Program Files\drag-lint\dclDragLintWizard.bpl`), the cmd line
  `<unquoted exe> lsp` was tokenized by Windows and the process spawn
  succeeded but the args got mangled. Now quotes the exe path
  explicitly.

- **`CREATE_NO_WINDOW` flag added** to `CreateProcessW` so the
  spawned drag-lint subprocess does not pop a console window.

- **`Initialize` request timeout bumped from 5s to 10s** — the 5s
  timeout was occasionally too short on slow disks / first-run cold
  starts.

### Notes

- The BPL is loaded into RAD Studio's process at IDE startup. To pick
  up the v0.38 BPL changes you must either:
  1. Close RAD Studio entirely, replace
     `dclDragLintWizard.bpl`, and restart, OR
  2. Component → Install Packages → uncheck drag-lint → OK,
     replace the BPL file, then re-check it.
- The `drag-lint.exe` standalone is unchanged behavior from v0.37 —
  only the BPL plugin gained logging.

---

## v0.37.0-alpha -- 2026-05-29

### Fixed (critical)

- **`drag-lint index` failing on Win32** with `[FireDAC][Phys][SQLite] ERROR: near "ON": syntax error`. The `FQUpsertFile` prepared query used SQLite's UPSERT syntax (`INSERT ... ON CONFLICT(path) DO UPDATE SET ...`) which requires SQLite 3.24+. RAD Studio 13's bundled Win32 FireDAC SQLite library is older than that and rejects the keyword. Win64 was unaffected. Rewrote the query to use `INSERT OR REPLACE INTO files(...)` which is supported in every SQLite version. Behavior unchanged for the indexer (files.id may differ on re-index, but symbols/refs cascade and incremental skip path was already bypassing this query for already-indexed files).

### Notes

- v0.36's dual-arch fix made the Win32 IDE plugin path actually usable; this v0.37 fix makes auto-indexing work in that path. Both fixes are required for a functioning IDE plugin install.
- Win64 standalone CLI users were unaffected by this bug (the Win64 FireDAC SQLite is current enough).

---

## v0.36.0-alpha -- 2026-05-29

### Fixed (critical)

- **Binary architecture mismatch.** Releases through v0.35 shipped
  `drag-lint.exe` (Win32) bundled with `tree-sitter*.dll` (Win64). The
  exe would silently fail to load the DLLs with
  `STATUS_INVALID_IMAGE_FORMAT` (0xC000007B). Any prior install was
  non-functional regardless of CLI vs IDE-plugin use.

### Added (distribution)

- **Dual-architecture release artifacts.** Every binary now ships in
  two matched variants:
  - `drag-lint-v0.36.0-alpha-win32.zip` — `drag-lint.exe` + 3 DLLs as
    PE32 (Intel i386). **Required for the IDE plugin** since RAD Studio
    13 itself is a 32-bit process; the `dclDragLintWizard.bpl` is also
    Win32 and goes in this bundle.
  - `drag-lint-v0.36.0-alpha-win64.zip` — same contents as PE32+
    (x86-64). For standalone CLI / LSP / MCP usage where the process
    runs outside any IDE.

- **New build scripts** at `build/`:
  - `build_draglint_win32.bat` / `build_draglint_win64.bat` —
    msbuild-driven Delphi 13 builds for either platform; output staged
    to `third_party/dll-win32/` or `dll-win64/`.
  - `_buildruntime32.bat` / `_buildruntime64.bat` — `cl.exe` build of
    `tree-sitter.dll` runtime library with explicit `/MACHINE:X86` or
    `/MACHINE:X64`.
  - `_buildgrammar32_manual.bat` / `_buildgrammar64_manual.bat` —
    direct `cl.exe` build of `tree-sitter-delphi13.dll` from
    `parser.c + scanner.c`. Replaces the `tree-sitter build` invocation
    because the bundled tree-sitter CLI defaults to x64 and ignores
    `vcvars32.bat` for cross-arch.
  - `_builddfm32_manual.bat` / `_builddfm64_manual.bat` — same for
    `tree-sitter-dfm.dll`.

### Notes

- The IDE plugin BPL was already Win32 (correct for the IDE). The bug
  was only on the matching tree-sitter DLLs.
- Standalone CLI users who put the Win64 DLLs on PATH and ran the
  Win64 `drag-lint.exe` directly from `src/cli/Win64/Debug/` would
  have a working install; only the `third_party/dll/` bundled folder
  was broken.
- For the IDE plugin, copy the Win32 bundle next to the BPL or onto
  PATH. The Win64 bundle is irrelevant in that context — the IDE is
  Win32.

---

## v0.35.0-alpha -- 2026-05-29

Final polish version closing the v0.16-v0.35 marathon (20 versions total).

### Added

- **Hover tooltip** (`DragLint.Plugin.HoverTracker`): a `TTimer` polls every
  200ms; when the mouse cursor is stable for >= 600ms, the caret row of the
  active editor view is looked up in the diagnostic cache. If a diagnostic is
  found, `Application.HintWindow.ActivateHint` shows the message near the
  cursor. Caret-based (not pixel-precise); limitation documented.

- **New setting `EnableHoverTooltip`** (default True): persisted in the
  registry; exposed in both Tools > drag-lint > Settings and
  Tools > Options > drag-lint (Hover Tooltip group).

- **3 new lint rules** (total built-in count now 13+):
  - `boolean-comparison-true` (info) -- `X = True` or `X = False`: redundant
    boolean comparison; use the expression directly.
  - `redundant-as-tobject` (info) -- `(X as TObject)`: every Delphi object is
    already a TObject; cast is a no-op.
  - `inherited-bare` (info) -- bare `inherited;` call: verify it invokes the
    intended ancestor method.
  Rules in both `rules/` and `third_party/dll/rules/`.

- **README rewritten** as a comprehensive getting-started guide covering CLI,
  LSP server (Zed / VS Code), MCP server (Claude / Cursor), and RAD Studio
  plugin install paths; full command/tool/rule reference.

- **T61** -- HoverTracker compile smoke (`dcc64 -B T61_hovertracker.dpr`).
- **T62** -- Verify 3 new lint rules fire on `RuleTest.pas` (extended with
  boolean compare, `as TObject`, and bare `inherited` examples).

### Changed

- VERSION bumped to `0.35.0-alpha` in `DRagLint.CLI` and `DRagLint.LSP.Server`.

### Notes

Skipped rules that require data-flow analysis (single-line-if-then,
string-concat-loop, pos-with-substring, freeandnil-missing,
repeat-without-until): tree-sitter query syntax alone is insufficient for
these; deferred to a future session with a flow analysis pass.

---

## v0.34.0-alpha -- 2026-05-29

### Added

- **Workspace mode** (`drag-lint workspace index|status|add`): a
  `.drag-lint-workspace.json` file at a repo root lists multiple projects
  (`path` + optional `scan_dir: true`) and a `shared_db` path. All projects
  index into one shared SQLite, so symbols from PACKAGE, SERVER, CLIENT, and
  COMMON are all queryable together.

  - `workspace index [--config PATH]` -- indexes every listed project into
    the shared DB. Discovers config by walking up from the current directory.
  - `workspace status [--config PATH]` -- lists projects with per-project
    file counts from the shared DB.
  - `workspace add <projfile> [--config PATH]` -- appends a new project entry
    and saves.

- **Plugin workspace detection**: `TDragLintProjectNotifier.SpawnIndexer`
  now walks up from the active `.dproj` directory looking for
  `.drag-lint-workspace.json`. When found and `EnableWorkspaceMode` is True
  (default), it spawns `workspace index --config` instead of a single-project
  index, and uses the shared DB path for the session.

- **New setting `EnableWorkspaceMode`** (default True): available in both
  Tools > drag-lint > Settings and Tools > Options > drag-lint.

- **New module** `DRagLint.Workspace.Config` (`src/workspace/`):
  `TWorkspaceConfig` record, `TWorkspaceConfigIO.LoadFromFile`,
  `SaveToFile`, `FindWorkspaceRoot`.

- **T59** -- workspace config load/save round-trip.
- **T60** -- `drag-lint workspace index` on a 1-project fixture creates
  the shared DB.

---

## v0.33.0-alpha -- 2026-05-29

### Added

- **Find Usages form** (`Ctrl+Alt+F` or `Tools > drag-lint > Find Usages...`):
  InputBox prompts for a symbol name; shells `drag-lint query find-callers
  --name <name> --context 3 --db <db> --format json`; results are grouped by
  file in a `fsStayOnTop` TTreeView form. Double-click on a caller node opens
  the file and navigates the IDE editor to that line.
  New unit: `DragLint.Plugin.UsagesForm`.

- **Symbol Search form** (`Ctrl+Alt+T` or `Tools > drag-lint > Symbol Search...`):
  Modal TForm with a debounced TEdit (300ms); calls `drag-lint query --name
  <text>` as the user types; top-30 results shown in a TListView (qualified
  name | kind | location). Enter on the selected row or double-click navigates
  the IDE editor to that location. ESC closes with no action.
  New unit: `DragLint.Plugin.SymbolSearchForm`.

- **T57** -- UsagesForm compile + public-API smoke test.
- **T58** -- SymbolSearchForm compile + public-API smoke test.

---

## v0.32.0-alpha -- 2026-05-29

### Added

- **Inline code lens** -- `TDragLintCodeLensCache` populates per-file
  symbol caller counts on `EditorViewActivated`. `PaintLine` renders
  dim grey `[N callers]` text next to method declarations. New setting
  `EnableCodeLens` (default True) gates the feature; available in both
  Tools > drag-lint > Settings and Tools > Options > drag-lint.

- **4 new tree-sitter-query lint rules** (shippable subset of planned 6):
  - `compiler-magic-comments` (info) -- flags comments containing
    TODO/FIXME/HACK/XXX.
  - `nested-with` (warning) -- flags nested `with` statements where
    scope ambiguity becomes exponential.
  - `assert-call` (info) -- flags every `Assert()` call; reminder to
    include the descriptive second argument.
  - `case-magic-numbers` (info) -- flags integer literals as case
    branch labels; consider naming the constant.

  Rules not shipped (grammar limitations): `try-without-finally` (no
  `kTry` node target), `result-assignment-after-exit` (requires flow
  analysis). With v0.28 (5 rules), v0.31 (`parser-error`), and v0.32
  (4 rules), drag-lint ships **10 built-in lint rules** plus 3
  programmatic AST checks.

- **New unit** `DragLint.Plugin.CodeLensCache` -- singleton
  `TDragLintCodeLensCache` (get/set/invalidate/populate); registered in
  both `.dpk` and `.dproj`.

- **T55** -- CodeLensCache smoke test (get, invalidate, clear, singleton
  identity).

- **T56** -- v0.32 lint rule pack smoke test (all 4 rules fire on
  `RuleTest.pas`).

---

## v0.31.0-alpha -- 2026-05-29

### Added

- **Compiler-less AST diagnostics** -- `drag-lint check-ast <file>`
  runs without `dcc.exe`. Two programmatic checks via new
  `DRagLint.Diagnostics.AstChecks.TAstChecker`:
  - `unbalanced-begin-end` -- depth-aware lexer counting begin/end
    keywords outside strings/comments; flags mismatches at file end.
  - `undeclared-identifier` -- regex-extracts identifiers (uppercase
    first letter, length > 2) and queries the symbol index; identifiers
    not found AND not in the built-in allowlist are flagged.
    Requires `--db` to be useful. Allowlist shipped in
    `rules/builtin-symbols.txt`.
  Findings flow through the same `publishDiagnostics` path; compatible
  with Zed, VS Code, or any LSP client.

- **`parser-error` rule** (`rules/parser-error.scm` +
  `rules/parser-error.json`) -- catches `ERROR` nodes emitted by the
  tree-sitter grammar for malformed syntax. Works via the existing
  `.scm` rule loader (`TLinter`).

- **MCP `run_ast_checks` tool** (14th in catalog) -- mirrors
  `run_compile_check` shape: `{"target":"path.pas","db":"..."}`.

- **Settings: `ScanLibraries` toggle** -- new checkbox in
  Tools > Options > drag-lint and Tools > drag-lint > Settings.
  When True, the plugin auto-index appends `--scan-libraries` to
  the spawned `drag-lint index` command, pulling in RTL + DevExpress
  + Spring4D + browsing-path libraries. Off by default (heavy;
  ~480k symbols on a typical install).

- **Tools > drag-lint > Run AST Checks** menu entry -- spawns
  `drag-lint check-ast <active-file>` and broadcasts `textDocument/
  didSave` for LSP refresh. Produces findings without a compiler.

---

## v0.30.0-alpha -- 2026-05-29

### Added (IDE integration)

- **Custom Structure form** (`DragLint.Plugin.StructureForm`) -- Tools >
  drag-lint > Show Structure opens a non-modal, stay-on-top TForm with
  a TTreeView populated with two roots:
  - "Diagnostics (N)" -- pulled from the v0.29 diagnostic cache;
    severity prefix + message; double-click jumps editor to line.
  - "Code Elements (M)" -- pulled from a new `TDragLintStructureCache`
    that shells out to `drag-lint surface` per file. Cached per file
    path.
  Refresh button re-pulls both. Form is a separate window rather than
  injecting into the IDE's native Structure pane (sibling-tab
  registration requires custom-window hosting that is too fragile
  across BDS versions; v0.31+ may revisit).

- **Native Tools > Options page** (`DragLint.Plugin.Options` +
  `DragLint.Plugin.OptionsFrame`) -- implements `INTAAddInOptions` so
  drag-lint appears under Tools > Options as a proper IDE-native panel.
  Frame hosts all v0.22-v0.29 settings (drag-lint.exe path, project DB
  template, AutoIndex, AutoReindexOnSave, EnableHover/Completion/
  SignatureHelp/Diagnostics, EnableInlineMarkers + 4 per-severity
  toggles). Save happens on OK click; Cancel discards changes.
  The Tools > drag-lint > Settings... menu shortcut remains and now
  shows the same form in a modal wrapper for users who prefer the menu
  flow.

### Notes

- Structure form is a standalone TForm rather than docked into the
  IDE's Structure pane. Provides the same data with less integration
  risk.
- Options frame and modal SettingsForm now share the same field set;
  v0.31 may unify them into a single TFrame consumed by both contexts.

---

## v0.29.0-alpha -- 2026-05-29

### Added

- **In-editor visual diagnostics** -- LSP `publishDiagnostics` notifications now
  paint directly into the RAD Studio editor via `IOTAEditViewNotifier`:
  - **Gutter dot** (6x6 filled circle) on every diagnostic line, colored by
    max severity on that line.
  - **Wavy underline** (2-pixel sawtooth) over the diagnostic column range,
    one per diagnostic item.
  - **Ctrl+Alt+I** -- displays a `THintWindow` popup with all diagnostic
    messages for the current cursor line.
- **Registry-aware colors** (`DragLint.Plugin.RegistryColors`) -- reads
  `HKCU\Software\Embarcadero\BDS\37.0\Editor\Highlight\` keys (`Syntax Error`,
  `Warning`, `Hint`, `Information`) so markers honor the user's custom IDE color
  theme.
- **Per-severity toggles** -- 5 new settings (`EnableInlineMarkers`,
  `ShowErrorsInline`, `ShowWarningsInline`, `ShowHintsInline`, `ShowInfoInline`)
  exposed in the Settings dialog. Defaults: markers on, Info off.
- **T47** -- smoke test: registry color reader returns non-zero defaults.
- **T48** -- smoke test: diagnostic cache stores and retrieves by file + line
  with case-insensitive path matching.

### Notes

- Mouse-hover tooltip deferred to v0.30; Ctrl+Alt+I is the v0.29 substitute.
- Theme-switch detection is not live; colors are read once at plugin load.
  Restart the IDE after changing editor colors.

---

## v0.28.0-alpha -- 2026-05-28

### Added

- **5 new built-in tree-sitter-query lint rules** under `rules/`. Each rule is
  a `.scm` tree-sitter query + `.json` metadata pair. Loaded automatically at
  startup from `<exedir>/rules/` by the existing v0.3 `TQueryRules` engine.

  | Rule id | Severity | Description |
  |---------|----------|-------------|
  | `goto-statement` | warning | `goto` is a Delphi anti-pattern |
  | `with-statement` | info | `with` makes symbol scope ambiguous |
  | `empty-procedure-body` | info | `begin end` body with no statements |
  | `large-magic-number` | info | Numeric literal not in the common-constants allow-list |
  | `string-equality-comparison` | info | `=` binary expression (fires on all `=`, not just strings -- type-aware precision deferred to v0.19+) |

- **`tests/fixtures/T44_lint_pack.bat`** -- regression test that runs
  `drag-lint lint RuleTest.pas` and asserts all 5 new rules fire.

### Notes

- Rules use predicates shipped in v0.3 (`#eq?`, `#not-eq?`, `#match?`,
  `#not-match?`). The `empty-procedure-body` rule uses `#match?` on the body
  text -- it does not fire when `begin` and `end` are separated by comments.
- The `string-equality-comparison` rule is intentionally over-eager: it fires
  on every `=` binary expression regardless of type. Precise string-only
  detection waits on v0.19+ type-resolution data being plumbed into the lint
  engine.
- The original `writeln-in-source` rule remains as the reference example for
  the `.scm` + `.json` authoring pattern.

---

## v0.27.0-alpha -- 2026-05-29

### Added

- **`drag-lint generate-test --qname X [--framework dunitx|dunit]`** --
  emits a DUnitX (or DUnit) test scaffold for the given symbol.
  Builds `T<Class><Method>Tests` with `[TestFixture]` + `[Test]`
  attributes, HappyPath body instantiates the subject + asserts via
  `Assert.AreEqual`, EdgeCases body has a TODO.

- **`drag-lint format <file> [--yadf-path PATH]`** -- shells to YADF
  (https://github.com/Alexl-git/YADF) for in-place .pas/.dpr/.dpk
  formatting. Auto-detects YADF.exe via `HKCU\Software\YADF\ExePath`
  registry, then `C:\Projects\YADF\Win32\Release\EXE\YADF.exe`
  fallback. 30s timeout.

- **Plugin: Refactor preview form** (`DragLint.Plugin.RefactorForm`)
  replaces the v0.24 two-`InputBox` flow with a proper VCL modal
  dialog. Symbol qname + new name fields, Write .bak checkbox,
  Preview button (runs `drag-lint rename --dry-run` and shows the
  edit list in a memo), Apply button (enabled only after a successful
  preview; confirms via MessageDlg before applying).

- **Plugin Tools menu `Format with YADF`** -- shells `drag-lint format
  "<active-file>"` and shows YADF stdout summary. User saves manually
  before running.

### Notes

- Test stub generation is name-based -- the suggested class instantiation
  doesn't import the unit; you'll need to add the `uses` clause yourself.
- YADF format runs in-place. If the file has unsaved IDE buffer changes,
  YADF formats the on-disk version while the IDE buffer remains stale.
  Future v0.28+ may integrate Save-before-Format.
- Refactor preview dialog still calls drag-lint.exe as a subprocess
  rather than direct interop. Keeps the design-time package small.

---

## v0.26.0-alpha -- 2026-05-29

### Added — compiler diagnostic integration (replaces Error Insight)

The pipeline that lets the plugin replace RAD Studio's Error Insight with
the real dcc32/dcc64 H/W/E/F output. Four components ship in v0.26:

- **`drag-lint compile-check <target>`** -- runs the appropriate
  compiler against a `.dproj` (msbuild) or `.pas` (dcc64 -Q -B),
  parses every H/W/E/F line, and INSERTS into the v0.8 `compiler_findings`
  table. Output: text summary or `--format json`. Exit codes:
  0 success, 1 errors found, 2 spawn failed.

- **LSP `publishDiagnostics` now merges compiler findings.** When the
  IDE plugin (or any LSP client) saves a file, the editor's diagnostics
  panel includes BOTH our lint findings AND any compiler findings in the
  database for that file. Source tags: `'drag-lint'` for lint,
  `'dcc'` for compiler.

- **MCP `run_compile_check` tool** -- Claude/Cursor/etc. can request
  a compile, get back the structured finding array. Tool 13 in our
  catalog. Args: `{target, msbuild_path?, db?}`.

- **Plugin Tools menu adds two entries**:
  - `Tools > drag-lint > Compile && Diagnose` -- spawns msbuild against
    the active project's .dproj, captures output, persists findings,
    broadcasts `textDocument/didSave` to refresh the LSP diagnostics
    view for every affected file. Shows a summary dialog.
  - `Tools > drag-lint > Import Build Log...` -- TOpenDialog to browse
    for a saved msbuild/dcc output file; parses, persists, broadcasts
    didSave.

### Notes

- Single-file `.pas` compile-checks can fail when cross-unit dependencies
  aren't available. That's expected -- the parser still ingests the
  resulting errors so you see what would need to be fixed.
- `Clear Compiler Findings` Tools menu entry is deferred to v0.27
  to avoid pulling FireDAC into the design-time plugin.
- Refactor preview form (originally v0.25 F1, then v0.26 carry-over)
  is deferred again to v0.27. The InputBox + ShowMessage flow from
  v0.24 still works; v0.27 will give it a proper VCL form.

---

## v0.25.0-alpha -- 2026-05-29

### Added

- **`drag-lint generate-docs --qname X [--format xmldoc|pasdoc]`** --
  generates a doc-comment stub for a symbol. Parses the signature
  (or falls back to reading the declaration line from source when
  the signature field is empty), extracts parameters and return type,
  and emits an XMLDoc `/// <summary>...` block or a PasDoc `{** ... *}`
  block. Pipe stdout into your editor or clipboard.

- **MCP tool `generate_doc_stub`** -- same as the CLI.

- **`drag-lint find-deadcode [--kind K] [--include-private]`** --
  inverse of v0.17 `impact`. Lists symbols with zero callers in the
  index (excluding constructors/destructors and known entry points
  like `Main`, `Register`, `initialization`, `finalization`).
  Output: `<qname>  [<kind>]  <file>:<line>`.

- **MCP tool `find_deadcode`** -- same as the CLI.

### Notes

- Refactor preview form (the originally-planned v0.25 F1) moves to
  v0.26 along with the bigger compiler-diagnostic integration scope.
- Dead-code analysis is name-based (same caveat as v0.24 rename):
  symbols in unrelated classes with the same short name are treated
  as cross-referenced. Precision-perfect mode awaits `refs.symbol_id`
  population (still parked).
- Doc stubs are pure scaffolding -- they emit TODO placeholders for
  the user to fill in. v0.26 may add LLM-assisted prose suggestions
  via the existing context-bundle infrastructure.

---

## v0.24.0-alpha -- 2026-05-29

### Added (Refactoring)

- **`drag-lint rename --qname Foo.TBar.Baz --to NewName`** -- rewrites
  every occurrence of a symbol. Uses the existing index's
  declaration site + `FindCallersByName` results. Edits are sorted
  back-to-front so applying them doesn't shift columns mid-pass.
  Source files are written back as ANSI + CRLF to preserve the
  project's strict-ASCII conventions. A `.bak` backup is written before
  each file mutation unless `--no-backup` is passed. `--dry-run` shows
  the diff without writing. Exit codes: 0 success, 1 not-found,
  2 collision, 3 I/O error.

- **MCP tool `rename_symbol`** -- same as the CLI, callable from
  Claude/Cursor/etc. Args: `{qname, to, dry_run?, db?}`. Returns
  `{edits: [...], files_touched: N, applied: bool}`. Total MCP tool
  count is now 12.

- **Plugin Tools menu `Rename Symbol...`** -- two InputBox prompts
  (qname + new name) and shows the equivalent CLI command. v0.24
  plugin is dry-run only -- full integration (synchronous spawn +
  apply on confirm) moves to v0.25 polish. Keystroke `Ctrl+Alt+R`.

### Notes

- Rename is name-based, not inheritance-aware. Overrides that share
  the same name will be renamed; symbols in unrelated classes with the
  same short name will ALSO be renamed (since `FindCallersByName` is
  name-based, not symbol-id-based). v0.22+ remains parked on
  populating `refs.symbol_id` for precision; once that lands the
  rename can become id-based.
- DFM event-handler bindings (`OnClick = btnOKClick` etc.) are indexed
  as `event-binding` refs in v0.16; the rename catches those too
  because `FindCallersByName` returns them. Saving forms after a
  rename will then sync the .dfm with the .pas.

---

## v0.23.0-alpha -- 2026-05-29

### Added (editor reactivity)

- **Custom completion popup form** (`DragLint.Plugin.CompletionForm`).
  Borderless `fsStayOnTop` TListBox popup replaces `ShowMessage` for
  Show Completion. Parses LSP completion items into glyph-prefixed rows
  (M/f/C/F/v/T/I/U/p/e/R for LSP CompletionItemKind values), Enter or
  double-click inserts via `IOTAEditWriter.Insert`, ESC and deactivate
  close, 30s timer fallback.

- **Custom signatureHelp popup form** (`DragLint.Plugin.SignatureForm`).
  Borderless single-line TLabel popup. Shows full signature with the
  active param index appended as `[arg N]`. ESC/deactivate/30s-timer close.

- **Background reindex on file save** (`DragLint.Plugin.SaveNotifier`).
  `TDragLintSaveNotifier` implements `IOTAModuleNotifier` (NOT
  `IOTAIDENotifier.ofnFileSaved` — that enum value doesn't exist in
  Delphi 13's ToolsAPI). `AfterSave` per-module; checks the
  `AutoReindexOnSave` setting + extension whitelist (.pas/.dpr/.dpk/.inc/
  .dfm) + cached project DB path, then spawns `drag-lint.exe index <file>
  --db <projdb>` detached. Cache `GLastProjectDb` is set by the existing
  project-open hook.

- **New setting `AutoReindexOnSave`** (REG_DWORD, default 1). Toggle in
  Tools → drag-lint → Settings dialog.

### Notes

- True incremental `textDocument/didChange` remains deferred — we still
  treat on-disk file as source of truth.
- IOTAOptionsForm (proper Tools → Options integration) still deferred.

---

## v0.22.0-alpha -- 2026-05-29

### Added (IDE polish)

- **Auto-index on project open** (`DragLint.Plugin.ProjectNotifier`). The
  plugin hooks `IOTAIDENotifier.FileNotification`; when a `.dproj` opens,
  it spawns `drag-lint.exe index <projdir> --db <projdir>\.drag-lint.sqlite`
  asynchronously (CreateProcessW with DETACHED_PROCESS) and posts an
  "indexing project..." title message to the IDE Messages pane. Honors the
  AutoIndex toggle (default ON) from settings.

- **Settings persistence + Tools menu dialog** (`DragLint.Plugin.Settings`
  + `DragLint.Plugin.SettingsForm`). Registry-backed config at
  `HKCU\Software\drag-lint\DelphiPlugin` with seven fields: ExePath,
  DbPathTemplate (use `<projdir>` for project dir), AutoIndex, EnableHover,
  EnableCompletion, EnableSignature, EnableDiagnostics. Modal VCL settings
  dialog built programmatically (no .dfm). New menu entry "Settings..."
  under Tools > drag-lint.

- **Keystroke bindings** (`DragLint.Plugin.Keyboard`) via
  `IOTAKeyboardServices.AddKeyboardBinding`:
  - `Ctrl+Alt+H` → Hover at Cursor
  - `Ctrl+Alt+C` → Show Completion
  - `Ctrl+Alt+S` → Show Signature Help
  - `Ctrl+Alt+D` → Run Diagnostics
  Each handler checks the corresponding Enable* setting before invoking.

- **Custom hover popup form** (`DragLint.Plugin.HoverForm`). Borderless
  `fsStayOnTop` VCL form replaces `ShowMessage` for hover only.
  TMemo content (Consolas 9pt), auto-sized up to 600x400, positioned just
  below the cursor. Auto-closes on ESC, click-outside (deactivation), or
  after 30s.

### Notes

- Completion + signatureHelp still use `ShowMessage` in v0.22; their custom
  popups move to v0.23.
- Incremental `didChange` editor updates and pre-D13 IDE versions remain
  deferred.

---

## v0.21.0-alpha -- 2026-05-28

### Added

- **Delphi IDE plugin (OTAPI design-time package)** — `src/delphi-plugin/` with
  `dclDragLintWizard.bpl` design-time package for RAD Studio 13 Florence (37.0).
  Registers as a wizard in the IDE's Tools menu with four entries: Hover at Cursor,
  Show Completion, Show Signature Help, Run Diagnostics. Menu invocations are
  modal for v0.21 (no custom popup forms or keystroke bindings — deferred to v0.22).

- **LSP client (`TDragLintLspClient`)** — spawns `drag-lint.exe lsp` as a persistent
  subprocess with `Winapi.Windows.CreateProcess` and round-trips JSON-RPC 2.0
  requests over anonymous pipes (`CreatePipe`). Handles `initialize` → `hover` /
  `completion` / `signatureHelp` → `shutdown` lifecycle. Implemented in
  `DragLint.Plugin.LspClient` (unit).

- **publishDiagnostics notification routing** — LSP `textDocument/publishDiagnostics`
  notifications are collected and posted to RAD Studio's Messages pane via
  `IOTAMessageServices.AddToolMessage`. Thread-safe via `TThread.Queue` to marshal
  IDE callbacks from the LSP client's read pump.

### Notes

- **v0.21 is scope-reduced** — Tools menu invocation only (no keystroke bindings,
  no custom popup forms). Full editor integration with hot-keys and rich popups
  moves to v0.22 pending polish of OTAPI event wiring.
- **LSP client tested standalone** — `tests/fixtures/T27_lsp_client.dpr` exercises
  the client with real `drag-lint.exe` binary; round-trips initialize + shutdown
  + basic requests verify the pipe protocol and JSON-RPC framing.
- **Requires PATH setup** — the v0.21 wizard expects `drag-lint.exe` on the system
  PATH; plugin will not launch without it.
- **No schema changes.** All features are read-only over v0.20 symbol tables.

---

## v0.20.0-alpha -- 2026-05-28

### Added

- **LSP `textDocument/completion`** — member completion after `.` (resolves LHS
  via TTypeAtResolver, enumerates child symbols), identifier completion via
  prefix LIKE match. Trigger characters `[".", "(", ","]`. Returns `CompletionList`
  with `isIncomplete: false`.

- **LSP `textDocument/signatureHelp`** — parses function/procedure signature,
  computes `activeParameter` from comma count in the call context. Trigger
  characters `["(", ","]`.

- **LSP `textDocument/didOpen` + `textDocument/didSave`** — triggers lint run;
  results pushed as `textDocument/publishDiagnostics` notifications. Mapped
  severities (Error/Warning/Information/Hint) + source="drag-lint" + rule code.

- **Module: `DRagLint.LSP.Completion`** — TLspCompletion class for building
  completion and signature items.

- **Storage helpers: `FindSymbolsByPrefix` + `FindAllChildSymbols`** — query the
  symbol_table for prefix-matched identifiers and child symbols of a given
  parent.

### Notes

- **`didChange` deliberately not wired in v0.20** — server re-runs lint only on
  `didSave` (file-based, matching the indexer model). v0.21 OTAPI will be the
  path to incremental updates.
- **Completion uses prefix-LIKE** — no fuzzy matching yet. Defer to v0.21+.
- **Integration verified** — LoopFBN.pas test confirms 5 lint findings round-trip
  into LSP diagnostics correctly.

---

## v0.19.0-alpha -- 2026-05-28

### Added

- **`drag-lint typeat file:line:col`** — resolves the identifier at the given
  source position and returns containing symbol (unit, class, method),
  token text, resolved symbol (with qualified name), signature, and documentation.
  Supports dotted access (e.g., `Foo.Bar`) via parent_id lookup against class
  / record / interface parent symbols. Example: `drag-lint typeat Docs.pas:42:15
  --db myproj.sqlite` resolves the symbol at line 42, column 15.

- **MCP: `get_type_at_position` tool** — same as CLI `typeat` but callable from
  Claude Code, Cursor, or Zed. Arguments: `file` (relative path from repo root),
  `line` (1-based), `col` (1-based), `db` (optional path to SQLite).

- **LSP: textDocument/hover enriched** — when hovering over an identifier
  reference (not just declaration), hover now includes resolved symbol info
  (qualified name, signature, doc) via the type-at-position resolver.

### Notes

- **Pragmatic scope:** Top-level symbols (units, classes, methods) and dotted
  access against known class/record/interface parent symbols. Unresolved
  positions (e.g., inside `with` statements, generic substitutions, local
  variables) return a clear note rather than an error.
- **Deferred to v0.21 (OTAPI):** Local variable inference, generic type
  substitution, scope-based symbol lookup (e.g., `with TMyClass do Foo` →
  resolve Foo as a method of TMyClass).

---

## v0.18.0-alpha -- 2026-05-28

### Added

- **`drag-lint context --task "verb qname"`** — composes v0.16 docs + v0.17
  surface/slice/callers/impact into one AI-ready Markdown/JSON/raw payload.
  Verbs: `modify` (default), `inspect`, `refactor`, `delete`, `extend`.
  Automatically includes class surface, implementation slice, caller context
  (configurable depth), and impact summary (for refactor/delete). Output
  formats: `--format md|json|raw`. Example: `drag-lint context --task "modify
  Foo.TBar.Baz" --caller-context 3 --max-callers 10 --db myproj.sqlite`.

- **`drag-lint bench-context [--n N] [--md]`** — measures AI token-reduction
  ratio by sampling N random documented symbols from the database. For each
  symbol, computes the bundle token estimate (using chars / 3.7 heuristic) and
  compares against the baseline (full source file char count / 3.7). Reports
  average reduction ratio: "Bundle avg 234 tokens vs Baseline avg 1847 tokens
  = 7.9x reduction". Useful for understanding bundle efficiency on real
  codebases. Token estimate is a heuristic (not BPE); v0.19+ may add real
  tokenization.

- **MCP: `get_context_bundle` tool** — same as CLI `context` but callable from
  Claude Code, Cursor, or Zed. Arguments: `task` (string), `db` (optional path
  to SQLite), `caller_context` (optional integer, default 3), `max_callers`
  (optional integer, default 5), `format` (optional "md"|"json"|"raw").

### Notes

- **No schema changes.** All features are read-only over v0.16/v0.17 tables.
- **Token heuristic:** Reduction ratio uses simple chars / 3.7 estimate.
  Small single-file fixtures (Docs.pas, ~500 lines) may show ratio < 1 due to
  overhead. Real-project benchmarks (Micronite ORM3 with 795 files) should show
  5-10x reduction. Scaling improves as corpus size increases.
- **TBundleCaller record:** Internal structure introduced. `TContextBundle.Callers`
  array now resolves FilePath at bundle-build time (no lazy lookup).

---

## v0.17.0-alpha -- 2026-05-28

### Added

- **`drag-lint impact --qname X [--depth N]`** — transitive callers via
  `WITH RECURSIVE` SQLite CTE. Walks the reference graph to depth N (default 3)
  and reports per-depth caller count + distinct unit count. Useful for
  blast-radius analysis: "how many units would a change to this symbol
  impact?" Output format: `Depth 1: 42 callers in 8 units (+42)`.

- **`drag-lint surface --qname TFoo [--include-impl] [--all-visibility]`** —
  returns the class/interface/record declaration block sliced from the source
  file (interface section only, unless `--include-impl` is set). No method
  bodies, just the interface. `--all-visibility` includes private/protected
  sections; default heuristic skips lines containing the word `private` (naive
  but covers 95% of real codebases). Use case: feed the surface to an AI to
  understand a type's contract without drowning in implementation detail.

- **`drag-lint slice --qname Foo.TBar`** — returns a minimal multi-chunk
  source extraction: unit header + class declaration + per-method impl bodies
  (~70% smaller than the full unit, optimised for AI context windows). Chunks
  are tagged (`unit-header`, `class-decl`, `impl-method`, `unit-trailer`) so
  callers can reassemble or filter as needed. Impl-end detection is heuristic
  (searches for next `procedure`/`function`/`end.` line); works on standard
  formatting but may over/under-include on unusual layouts.

- **`drag-lint query find-callers --context N`** — extends the v0.16
  `find-callers` command to include N lines of surrounding source per match.
  Each result row includes the `context_text` field (N lines before + the call
  + N lines after, from the source file). Formats: text (one per line) and
  JSON (nested array). Zero context (default) suppresses the field for
  backward compatibility.

- **MCP: 3 new tools** —
  - `get_impact` — same as CLI `impact`, returns transitive callers by depth.
  - `get_surface` — same as CLI `surface`, returns class interface slice.
  - `get_slice` — same as CLI `slice`, returns symbol-relevant unit chunks.
  - `find_callers` extended — new optional `context` arg (integer, default 0);
    when set, each result includes `context_text`.

### Notes

- **No schema changes.** All features are read-only over v0.16's
  `symbols`, `refs`, `files` tables. Existing v4 indexes work as-is.
- **Private-section heuristic:** `surface` uses line-grep for `private` /
  `protected` to filter output. Proper visibility analysis (walking child
  symbols and their `modifiers` column) is deferred to v0.18.
- **Impl-end heuristic:** `slice` detects procedure/function end by finding
  the next `procedure`, `function`, `constructor`, `destructor`, or `end.`
  keyword at the source level. Non-standard indentation or unusual nesting
  may cause over/under-inclusion; use `--verbose` to inspect chunks.

---

## v0.16.0-alpha -- 2026-05-28

### Added

- **`symbol_docs` table (schema v4).** One row per documented symbol:
  `format`, `raw_block`, `summary`, `remarks`, `returns_text`, `params_json`,
  `exceptions_json`, `example_text`, `seealso_json`, `since_text`, `deprecated`
  (INTEGER flag), plus `start_line` / `end_line` for the source range.
  v3 databases are migrated transparently on first open -- no manual steps.

- **`DRagLint.Parser.DocComments` module.** A single-pass comment-region
  scanner (`TDocCommentScanner`) walks every `.pas` file and collects comment
  blocks keyed by line range. A format dispatcher (`TDocCommentParser`)
  selects the right sub-parser and populates a `TParsedDoc` record.
  `DRagLint.Parser.Delphi13` matches regions to symbols by line proximity at
  emit time.

- **XMLDoc support.** Recognises `/// <tag>...</tag>` and `{/** ... */}` blocks.
  10 tag types handled: `summary`, `remarks`, `returns`, `example`, `param`,
  `exception`, `see`, `seealso`, `since`, `deprecated`.

- **PasDoc support.** Recognises `{** ... }` and `(** ... *)` blocks with
  `@tag` prefix notation. Same 10 tags as XMLDoc.

- **Oneline support.** Single `///`, `//1`, or `///1` comment lines above a
  declaration are captured as `oneline` format with the line text as `summary`.

- **Loose comment capture** (opt-in). `{ ... }` and `(* ... *)` blocks
  immediately above a symbol are stored as `loose` format when
  `captureLooseComments: true` is set in `.drag-lint.json`. A noise filter
  (no letters = skip) suppresses divider lines. Off by default.

- **`drag-lint hover --qname X [--format md|plain|json]`.** CLI command
  returning the structured doc for any indexed symbol. Default format is
  `plain` (human-readable); `md` emits Markdown; `json` emits the raw row.

- **`drag-lint query find` extended.** Three new filters:
  - `--doc-tag deprecated` -- symbols marked `@deprecated` / `<deprecated>`.
  - `--doc-tag since` -- symbols with a `@since` / `<since>` annotation.
  - `--doc-contains TEXT` -- full-text search across `summary`, `remarks`,
    `returns_text`, `params_json`, `example_text`.
  - `--no-docs [--kind K] [--public]` -- symbols with no doc comment at all.

- **MCP: 3 new tools.**
  - `get_symbol_doc` -- returns the full structured doc row for a qualified name.
  - `find_by_doc_tag` -- returns all symbols bearing a given tag (`deprecated`
    or `since`).
  - `find_undocumented` -- returns symbols with no doc comment, with optional
    `kind` and `public_only` filters.

- **LSP `textDocument/hover` enriched.** When a symbol has a `symbol_docs`
  row the hover payload now includes summary, parameter table, returns, and
  exceptions in Markdown. Shared with the CLI `hover --format md` renderer.

- **`.drag-lint.json` `docs` section.**
  ```json
  {
    "docs": {
      "captureLooseComments": false,
      "allowBlankLineGap": 1,
      "implPrecedence": "interface"
    }
  }
  ```
  `captureLooseComments` enables the loose-comment path. `allowBlankLineGap`
  (default 1) permits up to N blank lines between a comment block and its
  symbol. `implPrecedence` (default `"interface"`, reserved for future use):
  when both interface and implementation declarations have doc comments,
  selects which side wins. v0.16 always uses interface; set up for v0.17+.

### Notes

- The comment-region scanner respects string literals (odd-quote check) and
  merges adjacent same-kind line comments (`///`) into a single block.
- Schema v3 databases auto-migrate to v4 transparently; no re-index needed
  for schema changes (existing symbols gain docs on next incremental run).

---

## v0.15.0-alpha -- 2026-05-27

### Added
- **`drag-lint export obsidian --open`** -- after writing the notes,
  creates `.obsidian/` in the output dir, registers the folder in
  `%APPDATA%\obsidian\obsidian.json`, and launches
  `obsidian://open?vault=<basename>`. Turns the previous three-step
  flow (export -> drag folder onto Obsidian -> trust vault) into a
  single CLI invocation.

### Fixed
- **Mojibake in Obsidian-export notes.** Source files contained
  literal Unicode em-dashes (`U+2014`), pipe arrows (`U+2192`), and
  ellipses (`U+2026`) interpreted by Delphi 13 as Windows-1252 bytes,
  producing `â€"` etc. when written out as UTF-8. All non-ASCII
  characters scrubbed from `.pas` sources per the project's strict-
  ASCII rule. Re-export to refresh existing vaults.

---

## v0.14.0-alpha -- 2026-05-27

### Added
- **`.drag-lint.json`** — per-project config. Located in cwd or any
  ancestor directory. Loaded before CLI flags; CLI overrides config.
  Recognised keys:
  ```json
  {
    "db": "drag-lint.sqlite",
    "project": "MyApp.dproj",
    "path": "C:/src",
    "rule": "field-by-name-in-loop",
    "watch": { "interval": 5 }
  }
  ```
- Save typing on repeat invocations:
  ```
  cd C:\proj                       # has .drag-lint.json
  drag-lint index                  # uses configured --db and --path
  drag-lint query --name TFoo      # uses configured --db
  ```

### Notes
- Missing or invalid `.drag-lint.json` is silently ignored.
- A small status line "(loaded defaults from <path>)" prints when the
  file was honoured, so you know it took effect.

---

## v0.13.0-alpha — 2026-05-27

### Added
- **`drag-lint diff --db <old.sqlite> --db <new.sqlite>`** — compare two
  indexes by `qualified_name`. Reports added, removed, and signature-
  changed symbols. Use case: "what did this PR change in the public
  API?" Build an index before the change, build one after, run diff.
  `--json` for tool integration.

### Example output
```
+ DRagLint.Lint.ProjectChecks.TProjectChecks  [class]
+ DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr  [method]
+ DRagLint.CLI.TArgs.Watch  [field]
+ DRagLint.CLI.TArgs.Interval  [field]
+ DRagLint.Lint.ProjectChecks  [unit]
Summary: 5 added, 0 removed, 0 changed
```
That diff was the captured drag-lint API delta from v0.7 to v0.13.

---

## v0.12.0-alpha — 2026-05-27

### Added
- **`drag-lint todos [<path>]`** — scan `.pas`/`.dpr`/`.dpk`/`.inc` for
  `// TODO`, `// FIXME`, `// HACK`, `// XXX`, `// REVIEW`, `// NOTE`
  comments. Word-boundaried so noise like "fixmessage" doesn't false-
  trip. Skips `//` inside string literals (odd-quote check on the line
  prefix). Optional author tag captured from `// TODO @alex ...` or
  `// TODO Alex: ...` forms — must start with a letter, so Delphi's
  built-in `// TODO 1 -oAuthor -cCategory : ...` priority digits don't
  consume the slot. `--json` for tool integration.

### Examples

```
drag-lint todos C:\path\to\src
drag-lint todos C:\path\to\src --json | jq '[.[] | select(.keyword=="FIXME")]'
```

Real-world: 68 todos found in the Micronite COMMON folder; 1 in the
drag-lint self-corpus.

---

## v0.11.0-alpha — 2026-05-27

### Added
- **`drag-lint index --watch [--interval N]`** — keep the index hot by
  polling the target folder(s) every `N` seconds (default 5). Each tick
  re-walks every resolved file; the existing mtime+sha256 incremental
  skip means unchanged files cost roughly nothing. Self-test on the
  drag-lint corpus: first tick = 0.14s for 16 files / 315 symbols,
  subsequent ticks = 0.02s (all skipped). Combine with `--project` to
  watch every folder pulled in by a .dproj's DCC paths.

### Notes
- Polling, not OS-level filesystem events. Trade-off: simpler, portable,
  no signal-handling subtleties; latency capped at `--interval` seconds.
  A v0.12 candidate is `ReadDirectoryChangesW`-backed watcher for
  sub-second response.
- No schema bump.

---

## v0.10.0-alpha — 2026-05-27

### Added
- **`drag-lint graph`** — emit a unit-level dependency graph from the
  index. One node per indexed source file, one edge per (file A
  references symbol defined in file B) pair, edge weight = count of
  references. Two output formats:
  - `--format dot` — Graphviz, renders via `dot -Tsvg drag-graph.dot -o
    drag-graph.svg` (or pasted into any online Graphviz viewer)
  - `--format mermaid` — Mermaid syntax, renders inline in
    GitHub/Obsidian/most Markdown viewers without external tools
- `--name <substr>` filter restricts the graph to edges whose source OR
  target path contains the substring. Useful for "show me everything
  depending on or used by the parser layer" → `--name Parser`.
- `--output <file>` writes the graph to a file instead of stdout.

### Notes
- Edge resolution is name-only: refs are joined to symbols by
  `LOWER(name)` because the indexer leaves `refs.symbol_id` NULL today.
  That means a ref to a generic name like `Create` will fan out to every
  unit defining a `Create`. Still useful as a structural snapshot — the
  real architectural arrows dominate the small noise. A future iteration
  will resolve `symbol_id` at index time.
- Self-test on drag-lint corpus: `CLI -> Storage.SQLite (48), CLI ->
  Core.Indexer (46), CLI -> Lint.Linter (44), ...` — matches the real
  hierarchy.

---

## v0.9.0-alpha — 2026-05-27

### Added — two project-shaped lint rules

- **`unit-not-in-dpr`** (project-level). Cross-checks the .dproj's
  `<DCCReference Include="..."/>` list against the matching .dpr/.dpk's
  `uses` clause. Emits a warning for every unit listed in the .dproj but
  missing from the program/package source (the dangerous case — drops out
  of the build on next IDE re-open), and an info-level finding for the
  reverse (compiles via search path today, but IDE doesn't track it).
  Invoked via `drag-lint lint --project <file.dproj>`. Self-test on
  drag-lint itself: 0 findings (clean). Real-world test on a 700-file
  Micronite client: 22 mismatches caught, every one a real "I forgot to
  add this to the dpr" bug.

- **`inline-comment-in-multiline-args`** (file-level, layout heuristic).
  Detects trailing `// ...` comments placed inside multi-line argument
  lists, array/set literals, and record initialisers — the exact pattern
  that YADF and other Pascal reformatters reflow incorrectly, silently
  destroying the next array element. Tracks paren/bracket depth,
  `{...}` and `(* ... *)` block comments, and `'string'` literals so URL
  fragments inside license headers don't false-trip. Skips closing-paren
  lines (no reflow target). Real-world test on Micronite client: 70 hits
  across array-of-record initialisers in `Blueprint4.ViewModel.pas`.

### Notes
- Project-level lint introduces `--project <file.dproj>` to the lint
  subcommand. File/folder lint and project lint are independent and can
  be combined in one invocation (run together, findings merge).
- No schema bump in v0.9.

---

## v0.8.0-alpha — 2026-05-27

### Added
- **Type-use references.** The indexer now emits `kind='type_use'` references
  for every `typeref` AST node — field types, parameter types, function
  return types, class/interface inheritance lists, generic type arguments,
  and qualified type names (`Unit.TFoo`). `find-callers --name ISymbolStore`
  on the drag-lint self-corpus now returns 5 sites (was 1): the interface
  decl, the field decl in the Indexer, the ctor parameter, the LSP field,
  and the concrete `TSQLiteSymbolStore` inheritance line. Total refs across
  the same corpus went 1251 → 1528 (+277).
- **`drag-lint import-log <logfile>`** — parse a msbuild/dcc compiler log
  and store findings in a new `compiler_findings` table (schema v3). Cross-
  references each finding to the indexed `files` row when the path matches,
  preserves the raw path otherwise. Accepts three formats:
  - `Foo.pas(45,10): Error E2010: ...`
  - `Foo.pas(45): Hint warning H2077: Value assigned to 'X' never used`
  - `[dcc64 Error] Foo.pas(45,10): E2010 ...`
- **`drag-lint query hints --name <code>`** — query the compiler-finding
  store. `--name H2077` returns every dead-write the compiler flagged across
  the project, with file/line. `--rule <severity>` filters by severity
  (Fatal/Error/Warning/Hint). Useful answer to "where's the dead code?" —
  the Delphi compiler already knows; this just stores its answer for
  cross-session querying.

### Notes
- Schema bumped to v3 (`compiler_findings` table + index). v2 indexes are
  upgraded transparently — existing fuzzy/symbol tables are untouched.

---

## v0.7.0-alpha — 2026-05-27

### Added
- **LSP position resolution.** `textDocument/definition`,
  `textDocument/references`, and (new) `textDocument/hover` now work on
  the cursor position. Implementation reparses the file under the URI
  with tree-sitter, walks to the smallest named node containing the
  cursor, drills into `genericDot`/`exprDot` to pick the rhs identifier
  if the cursor is on a qualified name, then queries the symbol table by
  that identifier text.
- **Hover** returns a Markdown block with the symbol kind + every
  qualified name matching that bare name + first declaration line.

### Fixed
- `file:///` URI encoding emitted an extra leading slash for absolute
  Windows paths (`file:////C:/...`). Strip the leading slash from the
  encoded path before prepending.

### Verified
- Cursor on `FStore.UpsertSymbol` in `DRagLint.Core.Indexer.pas`:
  - definition → 2 results: `ISymbolStore.UpsertSymbol` (interface) and
    `TSQLiteSymbolStore.UpsertSymbol` (concrete impl), each with proper
    file URI + range
  - references → 3 results: the call site + both declarations
- Cursor on `ISymbolStore` in the interface declaration: definition
  returns the interface decl range; references currently returns just
  the declaration because v0.7 refs are call-site-only (not type-use).
  Type-use refs are a v0.8 enhancement.

### Known limitations to flag publicly
- LSP `textDocument/references` only finds call sites today. Type uses
  (`X: ISymbolStore`, class inheritance, parameter types) are NOT
  emitted as refs by the indexer — they'd need a parser-side
  enhancement. Tracked as v0.8.
- No incremental parse on `textDocument/didChange`. The LSP server uses
  the on-disk index + reparses the cursor's file on each request.
  Re-running `drag-lint index` is sub-second per file thanks to v0.4
  incremental, so editor save + index-on-save covers most cases.

---

## v0.6.0-alpha — 2026-05-27

### Added
- **`drag-lint lsp`** — Language Server Protocol stdio server, framed with
  Content-Length headers per spec. `initialize`, `shutdown`, `exit`, and
  `workspace/symbol` work today. `textDocument/definition` and
  `textDocument/references` return empty arrays (placeholders) — they
  need position-to-token resolution which is a v0.7 item (tree-sitter
  reparse on cursor position).
- **`drag-lint top --by fanin`** — ranks names by reference count across
  the index. Aggregates refs by name first (fast path), then attaches a
  sample symbol for context. 1.5 s on 473 k-symbol corpora.
- **`drag-lint export enums`** — emit every `(enum, value)` pair from the
  index. Four formats: `firebird-sql` (CREATE TABLE + INSERTs), `csv`,
  `json` (nested-values), `delphi-const` (paste-ready arrays).
- **`drag-lint export obsidian`** — write one `.md` per unit with YAML
  frontmatter, full symbol list, and a "Referenced by" section using
  `[[wikilinks]]` so Obsidian's graph view becomes a navigable
  cross-reference map of the codebase.

### Fixed
- **Parser**: multi-segment unit names like `DRagLint.Core.Interfaces`
  were getting truncated to just the first identifier (`DRagLint`).
  `WalkUnit` now takes the full text of the `moduleName` node so the
  qualified path is preserved. **Indexes built before this commit need a
  full re-index** (delete the .sqlite and re-run `drag-lint index`) to
  pick up the correct unit names.

---

## v0.4.0-alpha — 2026-05-27

### Added
- **MCP stdio server** — `drag-lint serve --db <file>` speaks JSON-RPC 2.0
  / MCP `2024-11-05` and exposes `find_symbol`, `find_callers`, and `lint`
  as typed tools. Claude Code / Cursor / Zed can wire it via the standard
  `mcpServers` config block. The CLI is still available for token-tight
  use; same engine underneath.
- **Incremental reindex** — `IndexFile` skips files whose `mtime_unix` AND
  `sha256` are already in the `files` table. Reformatting an entire
  project (e.g. with YADF) and re-running `index` only re-parses the
  files that actually changed. The CLI summary line reports the skip
  count when nonzero.

### Notes
- Documentation external-vendor scrub: README, CHANGELOG, design doc,
  and `rules/README.md` no longer name specific commercial vendors or
  upstream open-source library authors except Delphi/Embarcadero
  themselves. Required attribution (MIT) is preserved in
  `third_party/<repo>/LICENSE`.

---

## v0.3.0-alpha — 2026-05-27

### Added
- **Persistent trigram index for fuzzy lookup.** Schema bumped to v2 with a
  new `symbol_trigrams` table populated alongside every symbol insert.
  Fuzzy queries on 473k-symbol indexes drop from ~5,500 ms to ~520 ms
  (>10× improvement). Legacy v1 databases are upgraded lazily on first
  fuzzy query.
- **`drag-lint index --scan-libraries`** — index Delphi Library + Browsing
  paths from the registry (HKCU + HKLM, Win32 + Win64) without needing a
  `.dproj`. Useful as a one-time "library knowledge base" build.
- **Multi-database queries** — repeat `--db <file.sqlite>` to query across
  several indexes at once. Results are concatenated. Useful for separating
  per-project indexes from a shared `delphi-libs.sqlite`.
- **Tree-sitter query predicates** (`#eq?`, `#not-eq?`, `#match?`,
  `#not-match?`, `#any-of?`, `#not-any-of?`) evaluated by the external
  rule loader. Sample `writeln-in-source.scm` now uses `(#eq? @callee
  "WriteLn")` so it fires only on real `WriteLn` calls.

### Changed
- README + design docs reworded to avoid naming any prior commercial tool.

### Known limitations
- Fuzzy lookup latency target was <500 ms — we hit ~520 ms on 473k symbols.
  Further wins likely need a daemon (MCP server in v0.4).
- `--scan-libraries` pulls in a wide path set — a large 3rd-party VCL
  component library alone can take 3 minutes to index. Use `--dry-run`
  first to inspect what will be scanned.

---

## v0.2.0-alpha — 2026-05-27

### Added
- **Full symbol coverage**: `interface`, `record`, `enum`, `enum_value`,
  `property`, `field` symbols emitted in addition to the v0.1 set
  (`unit`, `class`, `method`, `procedure`, `function`, `constructor`,
  `destructor`).
- **DFM form indexing** (via `tree-sitter-dfm.dll`). `object Name: TClass`
  emits `form` (root) or `component` (nested); event-handler bindings
  (`OnClick = btnOKClick`) emit references that show up in `find-callers`.
- **External lint rule plugins**. `<exedir>\rules\*.scm` query files +
  matching `*.json` metadata loaded at startup and run alongside built-in
  rules.
- **`drag-lint index --project <file.dproj>`** mode. Resolves the .dproj's
  `DCC_UnitSearchPath`, the .dpr's `uses X in 'path'` clauses, and Library
  + Browsing paths from registry (HKCU + HKLM, Win32 + Win64). Expands
  `$(BDS)` macros and deduplicates the result.
- `--dry-run` flag to inspect the resolved folder list without indexing.

### Changed
- `FindCallersByName` no longer hardcodes `kind='call'` — matches all
  reference kinds including DFM event-bindings.

---

## v0.1.0-alpha — 2026-05-27

Initial public surface:
- Indexer for `.pas`, `.dpr`, `.dpk` via `tree-sitter-delphi13`
- SQLite store (FireDAC), per-file transactions
- `query --name`, `query --qname` with **fuzzy fallback** (Levenshtein)
- `query find-callers --name <X>` returns deterministic call sites
- Built-in lint rule `field-by-name-in-loop`
- CLI: index / query / lint / --json / --version / --help

Scaled tested on:
- Micronite ORM3 (708 .pas + 86 .dfm + .dpr + .dpk = 795 files) → 44 169
  symbols, 42 341 references, 8 s
- Delphi RTL+VCL+FMX+Data (1295 files) → 212 083 symbols, 250 663 references,
  60 s
- Large 3rd-party VCL component library full install (4460 files) →
  473 756 symbols, 387 668 references, 179 s
