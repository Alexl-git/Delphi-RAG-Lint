# Lint false positives found reviewing DataCopy's full report (2026-08-03)

Source report: `C:\Projects\DataCopy\lint-report-20260803-192824.txt` -- **1871
findings** produced by the IDE's *drag-lint > Run Lint All* menu command.

Every item below was verified against the real source and the real indexes, not
inferred from the message text. Counts are from the DataCopy corpus (24 .pas
files across one live project plus six retired legacy units).

**Result: 1871 -> 1175 findings, and 6 errors -> 0.** All of Part A and Part B
are now implemented (B9 is a config decision, not a defect -- see below), plus
B10, a case-sensitivity bug in the store found while chasing the last five
findings.

| rule | before | after |
|---|---|---|
| `used-unit-not-resolvable` | 420 | 46 (all genuine) |
| `doc-drift` | 225 | 6 |
| `field-name-prefix` | 107 | 79 |
| `method-pascalcase` | 34 | 2 |
| `unused-unit-in-uses` | 16 | 1 |
| `unit-not-in-dpr` | 12 | 1 |
| `unused-private-member` | 12 | 4 (all genuine dead code) |
| `format-argument-count` | 6 | **0** |
| `type-name-prefix` | 4 | 1 |

`local-var-casing` is unchanged at 367 by design (B9).

**Regression status: full battery 215 runners / 215 PASS** (2026-08-05 16:09,
run under `pwsh`). Two harness traps cost a run each and are worth knowing:
- `run_battery.ps1` spawns each runner via `Start-Process -FilePath 'pwsh'` and
  reads `$proc.ExitCode`. Run the battery from Windows PowerShell instead of
  `pwsh` and every ExitCode comes back null -> all 215 score FAIL while the
  per-runner logs show clean passes. Run it with `pwsh`.
- Do NOT rebuild `drag-lint.exe` while the battery runs. Runners default to
  `src\cli\Win64\Debug\drag-lint.exe`; a rebuild mid-run swaps the binary under
  them. That is what produced a phantom `boolean-comparison-true` failure in
  `run_lint_tests` (155/1); re-run clean it is 156/0.

---

## Part A -- FIXED in this session

### A1. `used-unit-not-resolvable`: the library DB could never be opened (WAL)
**420 findings, 333 of them false.**

`TProjectChecks.CheckUsedUnitResolvable` opened the library index with
`OpenMode=ReadOnly`. Every drag-lint index is WAL-mode, and SQLite cannot open a
WAL database read-only without write access to its `-shm` wal-index -- it fails
with `disk I/O error`. So passing a library DB **aborted the entire lint-all
run**, and not passing one left the library source empty, which is why every
third-party and RTL unit in the project got flagged.

The codebase already documents this exact trap and its fix in
`DRagLint.Storage.SQLite.pas:641-651` (open with normal params, then
`PRAGMA query_only = ON`). `CheckUsedUnitResolvable` was the one place that
still used the broken form.

*Fixed:* `src\lint\DRagLint.Lint.ProjectChecks.pas` -- mirror the documented
read path.

### A2. `used-unit-not-resolvable`: the library query named a non-existent column
Once the connection opened, the next failure was
`no such column: unit_name_norm`. The lookup was:

```sql
SELECT 1 FROM symbols WHERE unit_name_norm = :N LIMIT 1
```

`symbols` has **no** `unit_name_norm` column in any schema version -- that column
lives on `unit_uses`, which records what a file *uses*, not what a unit
*declares*. This code path had therefore never worked.

*Fixed:* a library unit is simply an indexed FILE, so the stems now come from
`files.path` through the **same `NormUnit`** used on the project-member side --
the shared normalization is what keeps both sides comparable. Loaded once into a
set instead of one query per used unit.

### A3. `used-unit-not-resolvable`: DCU-only installs reported as unresolvable
**31 findings, all false.**

Raize/Konopka (`RzButton`, `RzPanel`, `RzStatus`, `RzLstBox`, ... 11 units) ships
as **`.dcu` only**: `...\CatalogRepository\BonusKSVC\8.0.1\Lib\RX13\Win32` is on
the Library search path, but its *sources* are on neither the Library nor the
Browsing path. drag-lint indexes source, so these units can never enter the
library index -- yet the compiler resolves them fine.

*Fixed:* after all other sources fail, scan the platform's Library search path
for `<unit>.dcu`. Built lazily, so a clean project never pays for the walk.

### A4. `unit-not-in-dpr`: every library unit reported
**12 findings, 11 of them false.**

The rule skipped units by a hardcoded name-prefix list (`System.`, `Vcl.`,
`Forms`, `SysUtils`, ...), which cannot know about EurekaLog's injected block
(`EMemLeaks`, `EResLeaks`, `ExceptionLog7`, `EAppVCL`, ...), DevExpress or Raize.

*Fixed:* only report a unit that **exists as a `.pas` beside the `.dproj`** --
the only case where "add it to DCCReference" is meaningful.

*The 1 survivor is a true positive:* `EExtraExceptionInfo.pas` really is a local
file used by `DataCopy.dpr` and absent from the `.dproj` (it is also untracked in
Mercurial). Worth adding to the project.

### A5. `unused-unit-in-uses` ran on `.dpr` files
**16 findings, 11 of them false.**

A program's uses clause is the project's unit-**inclusion** list, not an import
list: `DataCopy.dpr` legitimately names every unit it links even though its main
block references symbols from almost none of them.

*Fixed:* the rule now skips `.dpr`/`.dpk`.

### A6. The IDE menu never passed a library DB  *(your request)*
`lint-all` takes the first existing `--db` as the project index and the **second**
as the platform library index, but `InvokeLintAll` only ever passed one. The
plugin already had `GetPlatformAwareLibraryDbPath` (resolves
`library-<active platform>.sqlite` from the manifest `outDir`) -- it simply was
not called here.

*Fixed:* `src\delphi-plugin\DragLint.Plugin.Editor.pas` -- append the platform
library DB when it exists, silently omit it when it has not been built.

---

## Part B -- FIXED (2026-08-05)

Implementation notes per item are inline below; each entry keeps its original
diagnosis so the reasoning stays auditable.

### B1. INDEXER: unit-level global `var` declarations are not indexed
**Highest value item.** `uGlobals.pas` declares 11 interface-section globals
(`HeaderFields`, `AllHeaderFields`, `TagList`, `EXEDir`, `ZEISSNameFilterAlpha`,
`HelpSystem`, ...). **Not one of them is in the index.** Same for
`MainZeissConvert`'s `StartOnce: TEvent` and `ShellLibrary: HMODULE`.

`form` vars (`frmZeissConvert`) and `const` blocks (`BoolToStrA`) ARE indexed --
so the extractor appears to recognize a unit-level `var` only when its type is a
form class, and drops the rest.

Repro:
```
drag-lint query --name ZEISSNameFilterAlpha --db C:\Projects\DataCopy\drag-lint.sqlite --exact
-> 0 match(es)          (declared uGlobals.pas:18, used uZeissRoutines.pas:117,119)
```

Consequences seen in this report: the 5 surviving `unused-unit-in-uses` findings
are all false because of it -- `uZeissRoutines` really does use `uGlobals`
(`HeaderFields` at 472-476, `ZEISSNameFilter*` at 117-119). It equally breaks
`find-callers`, `query --name`, and every ref-resolution consumer for the very
common "globals unit" pattern.

### B2. `format-argument-count`: comments counted as arguments -- **all 6 `[error]`s**
```pascal
s2file1:= Format('%schr.txt', [{IncludeTrailingBackslash(fpath),} CopyLeftL(PN2_fname2, LPN2-7)]);
```
One specifier, one real argument. The rule reports "1 specifier but 2 arguments"
because it splits the open-array on commas **without stripping comments first**.
`StripPasCommentsKeepLayout` already exists in
`DRagLint.Lint.ProjectChecks.Parse` and is the right tool. These are the only
`error`-severity findings in the whole report, so they carry outsized weight.

### B3. `field-name-prefix` on record fields
**~13+ findings, all false.** Every `FileLockInfo.pas` hit is a record field --
including `RM_UNIQUE_PROCESS` / `RM_PROCESS_INFO`, Windows Restart Manager API
structs whose field names (`dwProcessId`, `strAppName`, `TSSessionId`) are
**mandated by the API**. Records are data carriers; the `F` convention is for
class backing fields. The rule should not fire on record/packed-record members.

### B4. `field-name-prefix` on published DFM component fields with qualified types
In `CMMACPY.pas` exactly two of ~40 published component fields are flagged:
```pascal
Timer1: Vcl.ExtCtrls.TTimer;      // line 67  -- FLAGGED
ImageList1: Vcl.Controls.TImageList; // line 75  -- FLAGGED
StTrayIcon1: TStTrayIcon;         // line 66  -- not flagged
```
The published-component detector works, but **fails when the field's type is
namespace-qualified**. Renaming these would break the `.dfm`. Same detector
drag-lint already uses for the lean context-bundle surface.

### B5. `method-pascalcase` on DFM event handlers
**~34 findings, most false.** `drpFromDropFiles`, `edtBckPropertiesButtonClick`
are IDE-generated handler names (`<ComponentName><Event>`); the component name
supplies the leading lowercase. They cannot be renamed without breaking the DFM
event wiring. Exempt methods that are DFM-referenced handlers.

### B6. `doc-drift` demands `<param>` on drag-lint's own generated doc blocks
**225 findings -- the second-largest rule.** The doc blocks it complains about
were written by drag-lint's Auto-Document feature:
```pascal
/// <returns><!-- drag-lint:auto -->Observed: False; True.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: ... / Implements: ... / Reads: ...
/// <!-- drag-lint:auto END -->
/// </remarks>
function BackupFile(const AFile: string; out AMess: string): Boolean;
```
The generator deliberately does not invent `<param>` prose, then `doc-drift`
reports "signature param AFile has no `<param>` tag" for every parameter. The
tool is grading its own output. Either the generator should emit `<param>`
stubs, or the missing-param check should not fire on a block that is entirely
`drag-lint:auto` (no hand-written `<summary>`).

### B7. `unused-private-member` on message handlers and method references
`RestoreWindow` is `procedure RestoreWindow(var msg: TMessage); message wm_User + 1;`
-- dispatched by the VCL, never called by name. `DoHandleException` is passed as
a method reference (`Synchronize(DoHandleException)`), a bare reference the
resolver does not count. Both must be exempt.

### B8. `type-name-prefix` -- records mislabelled, API/attribute types flagged
`RM_UNIQUE_PROCESS` and `RM_PROCESS_INFO` are **records**, reported as
`Class "..." should start with the "T" prefix`. Two issues: the message asserts
the wrong kind, and API-mapped types cannot be renamed. `INICaptionAttribute`
also follows the Delphi attribute convention (`XxxAttribute`, used as
`[INICaption]`), where a `T` prefix would be wrong.

---

## How each Part B item was fixed

- **B1** `DRagLint.Parser.Delphi13.pas` -- new `declVar` branch beside `declConst`,
  emitting `skVarDecl` for unit-level vars (guarded by `RoutineDepth = 0`, since
  routine locals come from `EmitRoutineLocals` and Delphi 13 inline body vars are
  locals too). `skVarDecl` had been consumed by the hover/LSP renderers but
  **emitted by nothing**. Verified: `uGlobals.ZEISSNameFilterAlpha : TRegEx`,
  `uGlobals.HeaderFields : TStringList`, `MainZeissConvert.StartOnce : TEvent`
  now resolve. Needs `index --force-reparse` once, since the DBs are otherwise
  skipped as up-to-date.
- **B2** `DRagLint.Diagnostics.AstChecks.pas` -- a comment is a NAMED child of
  `exprBrackets`, so build a comment-free element array and use it for both the
  count and the specifier/argument pairing (the type check indexed the same
  shifted list). Mirrors the existing `NodeType = 'comment'` skip in the
  executable-code walk.
- **B3/B4** `DRagLint.Diagnostics.NamingChecks.pas` -- new `InRecordDecl` state,
  set from a grammar-agnostic `TypeNodeIsRecord` (leading `record` / `packed
  record` keyword) and carried down the declType subtree; and the component-field
  skip now tests the LAST dotted segment of the field type.
- **B5** same unit -- the `declProc` branch now skips QUALIFIED names. The grammar
  reaches implementation headers through that node type; they arrive with no
  enclosing `declSection`, so the published/implicit-first exemption never
  applied and every DFM handler was reported at its implementation line. The
  `defProc` branch already documented this reasoning.
- **B7** `DRagLint.Parser.Delphi13.pas` + `DRagLint.Lint.ProjectRules.pas` -- the
  `message` directive was not captured at all (`modifiers` held only `private`),
  so no rule could exempt it. Added `ProcIsMessageHandler` (same `procAttribute`
  shape as `ProcIsVirtual`), recorded as `message` in Modifiers, and guarded
  `unused-private-member` on it.
- **B8** `DRagLint.Diagnostics.NamingChecks.pas` -- message now names the actual
  construct (`Record "..."` vs `Class "..."`), and exempts API-style names
  (ALL-CAPS with underscores) and `...Attribute` classes.
- **B6** `DRagLint.Doc.Drift.pas` -- `ddParamMissing` now requires evidence of
  human authorship (`<summary>` present, or at least one `<param>` already
  written, or no `drag-lint:auto` marker at all). Drift means doc and code moved
  APART; a symbol nobody documented has not drifted, and `missing-doc` already
  covers it.

### B10. STORE: identifier matching was case-SENSITIVE (found chasing the last 5)

The five surviving `unused-private-member` findings turned out to be two
different things, and the second was the most serious bug in this whole review.

**Four are TRUE POSITIVES.** `DoHandleException` is declared and implemented but
never called -- a leftover from the standard `TThread` idiom
(`HandleException` -> `Synchronize(DoHandleException)`) after the body was
replaced by EurekaLog's `ExceptionManager.Handle`. `Synchronize` does not appear
in those units at all. The rule is right; the code is dead.

**The fifth exposed a real defect.** `TagMRUAdd` is declared at
`DataCopy2.pas:130` and called three times as `TAGMRUAdd;`. Delphi identifiers
are case-insensitive, so those are the same routine -- but every identifier
comparison in the store used SQLite's default BINARY collation:

```
find-callers TagMRUAdd   (name as DECLARED)  -> 0 caller(s)
find-callers TAGMRUAdd   (name as CALLED)    -> 3 caller(s)
```

The dead-code false positive was the mild symptom. The severe ones:
`find-callers` -- the index's headline query -- **silently under-reports**, and
**rename refactoring would skip those call sites and emit code that does not
compile**. A confident wrong answer is worse than no answer.

*Fixed:* `COLLATE NOCASE` at all five identifier-comparison sites in
`DRagLint.Storage.SQLite.pas` -- `FindCallersByName`, the dead-code finder's
`LEFT JOIN`, the reference query, the resolved-call membership filter, and BOTH
hops of the recursive caller-walk CTE. Fixing only the one that was visible
would have left the same landmine in the other four. There is no index on
`refs(name_text)` (only `idx_refs_enclosing`), so these were already table scans
and NOCASE costs nothing. Verified: `TagMRUAdd`, `TAGMRUAdd` and `tagmruadd` all
return 3.

**Still open (indexer ref-extraction, same family as B1):** a method passed as a
reference rather than called is not recorded as a reference. Not reproduced on
this corpus -- the DoHandleException findings turned out to be genuine dead code
-- so it stays a known gap without a failing case here.

---

## RESUME POINT (handoff 2026-08-05)

### Status

All of Part A and Part B implemented; DataCopy **1871 -> 1129 findings, 6 errors -> 0**; full battery
**215 / 215 PASS** under `pwsh`. Artifacts built and staged:
`third_party\dll-win64\drag-lint.exe` (16:55, covers the newest engine source) and
`third_party\dll-win32\dclDragLintWizard.bpl` (17:37, covers everything incl. the hover changes).

**NOTHING IS COMMITTED.** Branch `main`, in sync with origin, working tree dirty on purpose.

### The working tree holds TWO work streams -- never `git add .`

| this work | someone else's |
|---|---|
| `src/delphi-plugin/DragLint.Plugin.{DbResolver,Editor,HoverForm}.pas` | `FEATURES.txt` |
| `src/diagnostics/DRagLint.Diagnostics.{AstChecks,NamingChecks}.pas` | `docs/editors/` |
| `src/doc/DRagLint.Doc.Drift.pas` | `docs/INBOX-editor-integration-and-delphilsp-union.md` |
| `src/lint/DRagLint.Lint.{ProjectChecks,ProjectRules}.pas` | `docs/superpowers/specs/2026-08-05-delphilsp-union-design.md` |
| `src/parser/DRagLint.Parser.Delphi13.pas` | |
| `src/storage/DRagLint.Storage.SQLite.pas` | |
| `third_party/dll-win32/dclDragLintWizard.{bpl,dcp}` (rebuilt) | |
| this doc + the three `docs/INBOX-*` files listed below | |

### Also changed OUTSIDE the repo

Three roots appended to `HKCU\Software\Embarcadero\BDS\37.0\Library\{Win32,Win64}\Browsing Path`:
`C:\Projects\tpshellshock\source`, `C:\Projects\SysTools\source`, `C:\Projects\kbmMemTable\Source`
(Win32 113->116, Win64 120->123). Remove those three entries to undo.

Deliberately the **Browsing** path, not the Library path: Library is a compiler search path, and
`kbmMemTable`'s source does not compile here (`E2072` at `kbmMemTable.pas:4939`), so adding it there
could break real builds. drag-lint's `--scan-libraries-win` scans Library **and** Browsing, so the
browsing entry is enough for the index. All 9 units are now in both `library-Win32.sqlite` and
`library-Win64.sqlite`, which took `used-unit-not-resolvable` from 46 to 1.

### Hover popup rework (same session, NOT covered by the battery)

`src/delphi-plugin/DragLint.Plugin.HoverForm.pas` -- plugin-only, so the engine battery does not
exercise it. Compiles clean; **never seen running**. Needs a live-IDE look at the frame and the grab
band before it is trusted.

- New `MeasureTextWidth` measures candidate lines in the real body font. The old `~7.6 px/char`
  estimate is only valid for a monospaced cell: it padded narrow popups and wrapped wide ones that
  would have fitted.
- New `MaxPopupWidthAt(X,Y)` caps on the work area of the monitor the popup lands on, replacing the
  hardcoded `MAX_W = 900` (string path) / `1200` (structured path).
- `PlaceAndShow` now clamps WIDTH as well as height, and uses `Screen.MonitorFromPoint` instead of
  `SPI_GETWORKAREA` -- the latter reports the PRIMARY monitor only, so popups on a second screen were
  clamped against the wrong rectangle.
- Menu popups are content-sized too; they previously took `MAX_W` unconditionally.
- Resize: `WS_THICKFRAME` in `CreateParams` + `WM_NCHITTEST` reporting a 6 px band on
  right/bottom/corner. NOT top/left -- the popup is anchored top-left to the hovered token, so
  dragging that corner would move the anchor out from under the cursor and trip drift dismissal.
  `FSizing` (set between `WM_ENTERSIZEMOVE`/`WM_EXITSIZEMOVE`) suppresses `HandleWatchTick`, the sole
  auto-dismissal, which would otherwise close the popup the instant an edge is grabbed.

### Gotchas that will bite a cold start

1. **Run the battery with `pwsh`.** It spawns runners via `Start-Process -FilePath 'pwsh'` and reads
   `$proc.ExitCode`; under a Windows PowerShell parent every ExitCode is null and all 215 score FAIL
   while the logs show clean passes. Cost two full runs.
2. **Never rebuild `drag-lint.exe` while the battery runs** -- runners resolve
   `src\cli\Win64\Debug\drag-lint.exe` and a mid-run swap invents a phantom failure.
3. **`deploy-staged.bat` would REGRESS the plugin** -- it copies the BPL from `C:\TEMP1\bpl_staging`
   (a July 5 build). The plugin build already writes straight to `third_party\dll-win32`.
4. **`index <folder> --db <large.sqlite>` never terminates** -- see
   `docs/INBOX-incremental-index-hangs-on-large-db.md`; use the commit-then-kill workaround and allow
   a big single file several minutes before calling a plateau.
5. Rebuilding the BPL needs RAD Studio CLOSED (it locks `dclDragLintWizard.bpl`).

### Not done yet

- Decide on committing (and whether to separate the two streams).
- Visual check of the hover popup.
- `local-var-casing` (367) -- config decision, not a defect. Same question for `const-casing` on the
  `rsXxx` resourcestring convention.
- Consider excluding DataCopy's six retired legacy units from index scope; they are not in
  `DataCopy.dproj`, cannot compile on this machine, and carry a large share of the remaining 1129.
- `docs/INBOX-parse-error-shellshock-units.md` -- bisect `StShlCtl.pas` to find the real construct
  (the `{$I+}` hypothesis is disproved in the doc).
- Carried over from 2026-08-03 and still open: the nine-DB manifest reindex to schema v19
  (`drag-lint index --all --config third_party\dll-win64\drag-lint.json --jobs 0`; `--jobs` does
  nothing without `--config`), then section 6 of
  `docs/INBOX-index-schema-v19-reindex-for-converter.md`. See `docs/lint/PLAN-post-v122-leftovers.md`.

---

### B9. `local-var-casing` -- rule design, not a bug
**367 findings, the single largest rule.** It demands PascalCase for locals and
flags `i`, `j`, `k`, `stmp`, `found`. Idiomatic Delphi loop counters and
camelCase locals are not defects, and mass-renaming 367 locals in working legacy
code is churn with real risk. Recommend either narrowing the rule (exempt short
loop indices; accept camelCase) or turning it off for this project via config.
Same question applies to `const-casing` flagging the standard `rsXxx`
resourcestring convention.

---

## Part C -- true positives worth acting on in DataCopy

- 46 remaining `used-unit-not-resolvable`: SysTools (`StDrop`, `SsBase`,
  `ststrL`, `StAbout`, `StBrowsr`, `StShrtCt`, `StTrIcon`, `stRegINI`),
  `kbmMemTable`, `Basics2`. These have **no source and no `.dcu`** anywhere on
  the Library path -- they genuinely do not resolve. All are confined to the
  retired legacy units (`DataCopy2`, `MainZeissConvert`, `CMMACPY`, `DataCopy`,
  `Main_Copy_CSV_With_Tag`, `DPP2CSV_Main`), which are **not part of
  `DataCopy.dproj`** and cannot be compiled on this machine.
- `EExtraExceptionInfo.pas` should be added to `DataCopy.dproj`'s DCCReference
  list (see A4).

**Scope note:** of the 24 files linted, only ~10 belong to `DataCopy.dproj`. The
legacy units carry a large share of the findings and cannot be build-verified,
so cosmetic cleanup there is unverifiable churn. Worth deciding whether to
exclude them from the index scope before doing code-level cleanup.
