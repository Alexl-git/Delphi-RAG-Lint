# Enum-Helper Generator + first-class helper indexing -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate the standard enum `record helper` (ToByte/FromByte/ToInteger/FromInteger/ToString/FromString) from a CLI verb + IDE menu, backed by first-class helper indexing (schema v15) and an ON-by-default separate-units lint rule.

**Architecture:** A new `src/refactor/DRagLint.Refactor.EnumHelper.pas` runs a RESOLVE -> GENERATE -> PLACE pipeline that queries the index for the enum + members + any existing helper, builds one Byte-family helper from a deterministic template, and emits two `TTextEdit`s (decl after the enum; bodies in the implementation section) applied by the existing `TTextEditApplier`. The indexer gains a first-class helper-target edge (`type_helpers` table) so the create-only-if-missing guard and the new lint rule never parse heritage strings.

**Tech Stack:** Delphi 13 (Studio 37, Win32/Win64), tree-sitter-delphi13, SQLite (FireDAC), DUnitX-style PowerShell harnesses, dcc64 compile-check.

## Global Constraints

- **Encoding:** all `.pas` output is strict 7-bit ASCII, CRLF, no BOM, no Unicode. Generated helper text obeys this.
- **Schema migration invariant (v0.83.1):** new tables go in `SCHEMA_DDL` AND are created in `Migrate()` via `TryExec('CREATE TABLE IF NOT EXISTS ...')`; indexes on retrofitted columns go ONLY in `Migrate()`. A pre-v15 DB must migrate without "no such column/table" on any query. (See `src/storage/DRagLint.Storage.Schema.pas` header comment + `Migrate()` at `DRagLint.Storage.SQLite.pas:449`.)
- **Schema bump:** `SCHEMA_VERSION` 14 -> 15 in `src/storage/DRagLint.Storage.Schema.pas:6`.
- **Build recipe:** invoke the `delphi-build` skill (rsvars -> msbuild via `Start-Process -Wait`, read the log for `BUILD_EXITCODE=0` + no `[dcc] Error`). NEVER the MCP build tool; NEVER `cmd.exe /c build.bat` from Bash.
- **Reindex after a schema-changing build** before querying with the new exe: `drag-lint index --all --only DragLint` (or the changed dir). Kill orphaned `drag-lint.exe` if a DB is locked.
- **Canonical exe for local queries/tests:** `third_party\dll-win64\drag-lint.exe`.
- **Both lint paths:** any rule default (ON/OFF) MUST be honored in BOTH `DoLintAll` and `DoLintProject` (AutoDocument LATEST-19 Critical: a catalog-OFF rule fired at runtime via a DefDisabled gap). Add a regression test.
- **Refactor test-harness template:** `tests/refactor/run_extract_method.ps1` (dry-run / `--json` / `--apply --no-backup` / refuse / usage-error / `Test-Compiles` dcc64 gate). Mirror it for `run_enum_helper.ps1`.
- **Commit cadence:** every task ends with a commit. Do not push until the release task (the human drives release).

---

## Task 0: AST probe -- confirm how a `record helper for TX` exposes its target

**Files:**
- Create (throwaway): `tests/refactor/fixtures/enumhelper/_probe_helper.pas`
- Read: `src/parser/DRagLint.Parser.Delphi13.pas:342-470` (`ClassNodeIsRecord`, `HeritageTextOf`, `TryWalkClassOrRecord`)

**Interfaces:**
- Consumes: nothing.
- Produces: a documented finding (in the Task 1 commit message / a comment) of the tree-sitter node type that marks a helper (`kHelper`?) and how the target type (`for TX`) appears (a `typeref` child? a `helper` field?). Task 1 depends on this fact.

- [ ] **Step 1: Write a probe fixture**

`tests/refactor/fixtures/enumhelper/_probe_helper.pas`:
```pascal
unit ProbeHelper;
interface
type
  TColor = (clRed, clGreen, clBlue);
  TColorHelper = record helper for TColor
    function ToByte: Byte;
  end;
  TPlain = record
    Field: TColor;
  end;
implementation
function TColorHelper.ToByte: Byte;
begin
  Result := Ord(Self);
end;
end.
```

- [ ] **Step 2: Dump the AST / heritage for the helper vs the plain record**

Run (uses the existing dump path -- confirm the exact subcommand with `drag-lint --help`; `dump-refs` and `context` exist, and a parse-tree dump may be under a debug verb):
```bash
third_party/dll-win64/drag-lint.exe index tests/refactor/fixtures/enumhelper --db tests/enumhelper_probe.sqlite
third_party/dll-win64/drag-lint.exe query --name TColorHelper --db tests/enumhelper_probe.sqlite --json
third_party/dll-win64/drag-lint.exe query --name TPlain      --db tests/enumhelper_probe.sqlite --json
```
Expected: `TColorHelper` is `skRecord`; inspect its `heritage` field -- it should contain the target `TColor` (proving the target is a `typeref` in the class node). `TPlain`'s heritage should be empty (proving a plain record with a `TColor` field does NOT carry `TColor` in heritage). RECORD THIS OUTCOME.

- [ ] **Step 3: Read `HeritageTextOf` + `ClassNodeIsRecord` to identify the helper marker**

Read `src/parser/DRagLint.Parser.Delphi13.pas:342-434`. Determine: does the `declClass` node contain a token distinguishing `record helper` from a plain `record`? (Look for a `kHelper` / `helper` child token, analogous to how `ClassNodeIsRecord` scans for `kRecord`.) If tree-sitter exposes no explicit helper token, the fallback marker is: the record node has a heritage `typeref` (a plain record never does) -- but confirm this against the probe output, because a record CAN have an interface list in some dialects. Document the chosen marker.

- [ ] **Step 4: Clean up the probe DB, keep the fixture**

```bash
rm -f tests/enumhelper_probe.sqlite
```
The `_probe_helper.pas` fixture stays (Task 6 reuses it). No commit yet -- fold this finding into Task 1's commit.

---

## Task 1: Indexer -- capture the helper-target edge (`type_helpers`), schema v15

**Files:**
- Modify: `src/storage/DRagLint.Storage.Schema.pas` (bump `SCHEMA_VERSION`; add `type_helpers` DDL to `SCHEMA_DDL`)
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (`Migrate()` ~line 573: `CREATE TABLE IF NOT EXISTS type_helpers` + indexes; new store methods `InsertHelperEdge` / `FindHelpersOfType`)
- Modify: `src/core/DRagLint.Core.Model.pas` (new `THelperEdge` record)
- Modify: `src/core/DRagLint.Core.Interfaces.pas` (add the two store methods to `ISymbolStore`)
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (`TryWalkClassOrRecord` ~461: when the node is a helper, capture the target)
- Modify: the indexer that persists parsed symbols (find via `grep 'type_ancestors'` in the index pipeline -- the resolve pass at `DRagLint.Storage.SQLite.pas:3014-3078` writes `type_ancestors`; add a sibling that writes `type_helpers`)
- Test: `tests/heritage/` already exists for ancestor edges -- add `tests/autotest/run_helper_edges.ps1` (or extend an existing heritage harness)

**Interfaces:**
- Consumes: the AST helper-marker finding from Task 0.
- Produces:
  - `THelperEdge = record HelperSymbolId: Int64; TargetName: string; TargetSymbolId: Int64; TargetFileId: Int64; HelperKind: string; end;` (`HelperKind` = `'record'|'class'`).
  - `ISymbolStore.FindHelpersOfType(const ATargetName: string): TArray<THelperEdge>;` -- all helpers whose target normalizes to `ATargetName` (across the whole DB).
  - `type_helpers` table: `helper_symbol_id INTEGER, target_name TEXT, target_symbol_id INTEGER, target_file_id INTEGER, helper_kind TEXT`.

- [ ] **Step 1: Write the failing store round-trip test**

Add to a new `tests/autotest/run_helper_edges.ps1` (model on `run_migrate_v12.ps1` for the migrate check + `run_extract_method.ps1` header). First assertion: after indexing `_probe_helper.pas`, `query helpers-of TColor` (the new verb from Task 5, OR a direct store call exercised via a tiny DUnitX test) returns exactly one edge whose helper is `TColorHelper` and target is `TColor`; and `helpers-of TPlain` returns none.

Since the CLI verb lands in Task 5, for THIS task write a DUnitX unit test instead: `tests/StorageHelperEdgesTests.dpr` calling `Store.FindHelpersOfType('TColor')`. Assert `Length = 1`, `Result[0].HelperSymbolId` resolves to `TColorHelper`, and `FindHelpersOfType('TPlain') = 0`.

- [ ] **Step 2: Run it -- verify it fails (method/table absent)**

Build the test dpr; expect a compile error (`FindHelpersOfType` undefined) or a runtime "no such table: type_helpers".

- [ ] **Step 3: Add the model record + interface method**

`DRagLint.Core.Model.pas` (after `TTypeAncestor`):
```pascal
  /// <summary>v15: one helper-target edge -- a `record helper for T` /
  /// `class helper for T` declaration linked to its target type T. Captured
  /// first-class so the enum-helper generator's create-only-if-missing guard
  /// and the enum-helper-separate-units lint rule never string-parse heritage.</summary>
  THelperEdge = record
    HelperSymbolId: Int64 ;
    TargetName    : string;
    TargetSymbolId: Int64 ;
    TargetFileId  : Int64 ;
    HelperKind    : string; // 'record' | 'class'
  end;
```
`DRagLint.Core.Interfaces.pas` (in `ISymbolStore`):
```pascal
    /// <summary>v15: all helpers (record/class) whose target type name matches
    /// ATargetName (whole-DB). Empty when no helper targets that type.</summary>
    function FindHelpersOfType(const ATargetName: string): TArray<THelperEdge>;
```

- [ ] **Step 4: Add the schema (DDL + Migrate) -- bump to v15**

`DRagLint.Storage.Schema.pas`:
```pascal
  SCHEMA_VERSION = 15;
```
Append to `SCHEMA_DDL` (after the `string_literals`/FTS block, at the very end; it is base SQLite so order relative to FTS5-first does not matter as long as it is a plain-DDL statement -- append with a leading comma):
```pascal
    , 'CREATE TABLE IF NOT EXISTS type_helpers (' +
      '  helper_symbol_id INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,' +
      '  target_name      TEXT NOT NULL,' +
      '  target_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' +
      '  target_file_id   INTEGER,' +
      '  helper_kind      TEXT NOT NULL)'
    , 'CREATE INDEX IF NOT EXISTS idx_type_helpers_helper ON type_helpers(helper_symbol_id)'
    , 'CREATE INDEX IF NOT EXISTS idx_type_helpers_target ON type_helpers(target_name)'
```
`DRagLint.Storage.SQLite.pas` `Migrate()` (right after the `type_ancestors` block ~line 581), mirroring it:
```pascal
  TryExec('CREATE TABLE IF NOT EXISTS type_helpers (' +
          '  helper_symbol_id INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,' +
          '  target_name      TEXT NOT NULL,' +
          '  target_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' +
          '  target_file_id   INTEGER,' +
          '  helper_kind      TEXT NOT NULL)');
  TryExec('CREATE INDEX IF NOT EXISTS idx_type_helpers_helper ON type_helpers(helper_symbol_id)');
  TryExec('CREATE INDEX IF NOT EXISTS idx_type_helpers_target ON type_helpers(target_name)');
```

- [ ] **Step 5: Parser -- capture the target when the node is a helper**

In `TryWalkClassOrRecord` (`DRagLint.Parser.Delphi13.pas` ~436-461), after computing `Kind`, detect the helper marker (per Task 0's finding). Store the helper target on the emitted symbol so the indexer can persist it. Simplest low-risk approach that avoids a parser-output schema change: reuse the existing `Heritage` capture (the target already lands there) and have the INDEXER classify a `skRecord`/`skClass` whose node is a helper. If Task 0 found an explicit `kHelper` token, add a `IsHelper: Boolean` + `HelperTarget: string` to the parser's symbol output; otherwise the indexer derives it from heritage of a helper-marked record. Document the choice in a comment. Whichever: the persisted `type_helpers.target_name` is the verbatim target type name (e.g. `TColor`), normalized the same way `type_ancestors.ancestor_name` is.

- [ ] **Step 6: Indexer -- persist the helper edge; store method reads it**

In the resolve/persist pass that writes `type_ancestors` (`DRagLint.Storage.SQLite.pas:3014-3078`), add a sibling that, for each helper-marked type symbol, inserts a `type_helpers` row (resolve `target_symbol_id`/`target_file_id` the same way ancestors are resolved -- best-effort; NULL when unresolved). Implement `FindHelpersOfType` as a `SELECT ... FROM type_helpers th JOIN symbols s ON s.id = th.helper_symbol_id WHERE th.target_name = :n`.

- [ ] **Step 7: Build (delphi-build skill) + run the store test -- verify PASS**

Build the CLI + test dpr. Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`. Run `tests/StorageHelperEdgesTests.exe`: `FindHelpersOfType('TColor')=1`, `('TPlain')=0`.

- [ ] **Step 8: Migration regression test**

Extend `run_helper_edges.ps1`: copy a pre-v15 fixture DB (or an old `tests/*.sqlite`), open it with the new exe, run `query --name X` -- assert it MIGRATES and does not error with "no such table: type_helpers". (Mirrors `run_migrate_v12.ps1`.)

- [ ] **Step 9: Commit**

```bash
git add src/storage src/core src/parser tests/heritage tests/autotest/run_helper_edges.ps1 tests/StorageHelperEdgesTests.dpr tests/refactor/fixtures/enumhelper/_probe_helper.pas
git commit -m "feat(index): first-class helper-target edge (type_helpers), schema v15 + Task 0 AST-probe finding"
```

---

## Task 2: EnumHelper RESOLVE -- enum + members + existing-helper guard

**Files:**
- Create: `src/refactor/DRagLint.Refactor.EnumHelper.pas` (interface + RESOLVE only this task)
- Test: `tests/refactor/EnumHelperTests.dpr` (new DUnitX runner) + `tests/refactor/run_enum_helper.ps1` (created here, grown in later tasks)
- Read: `src/refactor/DRagLint.Refactor.Rename.pas` (for the store-query + result-record idiom), `DRagLint.Refactor.TextEdit.pas` (`TTextEdit` shape)

**Interfaces:**
- Consumes: `ISymbolStore.FindHelpersOfType` (Task 1); `FindAllChildSymbols` / symbol lookup (existing store).
- Produces:
```pascal
  TEnumHelperMethod = (ehmToByte, ehmFromByte, ehmToInteger, ehmFromInteger, ehmToString, ehmFromString);
  TEnumHelperMethods = set of TEnumHelperMethod;
  TToStringMode = (tsmRtti, tsmCase);

  TEnumHelperResolve = record
    Found         : Boolean;             // enum located
    EnumName      : string;              // 'TColor'
    EnumFileId    : Int64;
    EnumFilePath  : string;
    Members       : TArray<string>;      // declaration order, real named members
    EnumEndLine   : Integer;             // decl end (insertion anchor for the helper decl)
    EnumEndCol    : Integer;
    HasHelper     : Boolean;             // any type_helpers edge targets this enum
    HelperSameUnit: Boolean;             // the existing helper is in EnumFileId
    HelperUnitPath: string;              // path of the existing helper's unit ('' if none)
    DescArrayName : string;              // '<Enum>Descriptions' if a same-unit array const exists, else ''
  end;

  TEnumHelperRefactoring = class
    class function Resolve(const AStore: ISymbolStore; const AEnumQName: string): TEnumHelperResolve; static;
  end;
```

- [ ] **Step 1: Write the failing RESOLVE test**

`tests/refactor/fixtures/enumhelper/simple.pas`:
```pascal
unit Simple;
interface
type
  TColor = (clRed, clGreen, clBlue);
implementation
end.
```
DUnitX test: index `simple.pas`, call `TEnumHelperRefactoring.Resolve(Store, 'TColor')`. Assert `Found`, `EnumName='TColor'`, `Members=['clRed','clGreen','clBlue']` in order, `HasHelper=False`, `DescArrayName=''`.

- [ ] **Step 2: Run -- verify fail (unit/class absent)**

Build `EnumHelperTests.dpr`; expect compile error `TEnumHelperRefactoring undefined`.

- [ ] **Step 3: Implement RESOLVE**

Look up the `skEnum` by qname. Get `skEnumValue` children in declaration order (order by `start_line, start_col` or the stored order). Call `FindHelpersOfType(EnumName)`; set `HasHelper`/`HelperSameUnit`/`HelperUnitPath`. Scan same-unit const decls for a `<EnumName>Descriptions` array (a `query --name <EnumName>Descriptions` style lookup filtered to the enum's file; `DescArrayName` = that name or ''). Capture the enum decl's end position for the insertion anchor.

- [ ] **Step 4: Run -- verify PASS**

Build + run: assertions green.

- [ ] **Step 5: Add the already-has-helper + separate-unit fixtures/tests**

`tests/refactor/fixtures/enumhelper/already_has_helper.pas` (enum + its helper same unit) -> `HasHelper=True, HelperSameUnit=True`. A two-file case (enum in one, helper in another) -> `HasHelper=True, HelperSameUnit=False, HelperUnitPath=<other>`. Run -- PASS.

- [ ] **Step 6: Commit**

```bash
git add src/refactor/DRagLint.Refactor.EnumHelper.pas tests/refactor/EnumHelperTests.dpr tests/refactor/fixtures/enumhelper
git commit -m "feat(refactor): EnumHelper RESOLVE -- enum+members+existing-helper guard"
```

---

## Task 3: EnumHelper GENERATE -- the Byte-family template

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.EnumHelper.pas` (add GENERATE)
- Test: `tests/refactor/EnumHelperTests.dpr`

**Interfaces:**
- Consumes: `TEnumHelperResolve` (Task 2).
- Produces:
```pascal
  TEnumHelperGen = record
    DeclText  : string;        // the `TXHelper = record helper for TX ... end;` block
    BodiesText: string;        // the implementation-section method bodies
    NeedsTypInfo: Boolean;     // True when RTTI ToString/FromString emitted and System.TypInfo may be absent
  end;

  // added to TEnumHelperRefactoring:
  class function Generate(const AResolve: TEnumHelperResolve;
    const AMethods: TEnumHelperMethods; const AToStringMode: TToStringMode): TEnumHelperGen; static;
```

- [ ] **Step 1: Write the failing generate test (golden-ish, logic not whitespace)**

Test: `Generate(resolveForTColor, [all 6], tsmRtti)`. Assert `DeclText` contains `TColorHelper = record helper for TColor`, `function ToByte: Byte;`, `class function FromByte(const AValue: Byte): TColor; static;`. Assert `BodiesText` contains `Result := Ord(Self);`, a `case AValue of` with `Ord(clRed): Result := clRed;` ... and `else` + `Result := clRed;` (first member). Assert RTTI ToString body `GetEnumName(TypeInfo(TColor), Ord(Self))` and `NeedsTypInfo=True`.

- [ ] **Step 2: Run -- verify fail**

- [ ] **Step 3: Implement GENERATE (exact template from the spec Section 3)**

Emit decl + bodies per the spec. `From*` = `case Ord(member)` over `AResolve.Members`, `else Result := <Members[0]>`. `To*` = `Ord(Self)`. RTTI ToString/FromString when `tsmRtti` (`NeedsTypInfo := True`); when `tsmCase`, emit per-member `Ord(m): Result := '<m>';` in ToString and the inverse in FromString (`NeedsTypInfo := False`). `ToDescription` only if `AResolve.DescArrayName <> ''` and `ehm...` -- note ToDescription is NOT one of the 6 flags; include it automatically when `DescArrayName<>''`. Respect `AMethods` subset. All text CRLF, ASCII. `{ TColorHelper }` comment before the bodies.

- [ ] **Step 4: Run -- verify PASS**

- [ ] **Step 5: Add subset + tsmCase + descriptions tests**

`Generate(..., [ehmToByte, ehmFromByte], tsmRtti)` -> only those two present, no ToString. `tsmCase` -> ToString has string literals, `NeedsTypInfo=False`. A resolve with `DescArrayName='TColorDescriptions'` -> `ToDescription` body `Result := TColorDescriptions[Self];`. Run -- PASS.

- [ ] **Step 6: Commit**

```bash
git add src/refactor/DRagLint.Refactor.EnumHelper.pas tests/refactor/EnumHelperTests.dpr
git commit -m "feat(refactor): EnumHelper GENERATE -- one Byte-family template (case idiom, RTTI/case ToString)"
```

---

## Task 4: EnumHelper PLACE -- two TTextEdits, populate empty impl, refuse rule

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.EnumHelper.pas` (add PLACE + top-level `Build`)
- Test: `tests/refactor/EnumHelperTests.dpr`

**Interfaces:**
- Consumes: `TEnumHelperResolve`, `TEnumHelperGen`; `TTextEdit` (from `DRagLint.Refactor.TextEdit`).
- Produces:
```pascal
  TEnumHelperAction = (ehaBuilt, ehaExists, ehaNoImplSection, ehaNotFound);
  TEnumHelperResult = record
    Action  : TEnumHelperAction;
    Edits   : TArray<TTextEdit>;      // decl edit + bodies edit (empty unless ehaBuilt)
    Message : string;                 // human reason for exists/no-impl/not-found
    EnumName: string;
    FilePath: string;
  end;

  // top-level entry the CLI + IDE call:
  class function Build(const AStore: ISymbolStore; const AEnumQName: string;
    const AMethods: TEnumHelperMethods; const AToStringMode: TToStringMode): TEnumHelperResult; static;
```

- [ ] **Step 1: Write the failing PLACE test**

Test `Build(Store,'TColor',[all6],tsmRtti)` on `simple.pas`. Assert `Action=ehaBuilt`, exactly 2 edits. Edit#1 inserts the decl right after the enum decl line (`clBlue);` line). Edit#2 inserts the bodies in the implementation section. Assert the bodies edit's insertion line is at/after the `implementation` keyword. Assert `System.TypInfo` gets added to the implementation `uses` (or a `uses System.TypInfo;` is emitted) when `NeedsTypInfo` and it is absent.

- [ ] **Step 2: Run -- verify fail**

- [ ] **Step 3: Implement PLACE + Build**

- Decl edit: insertion point = end of the enum type decl (`AResolve.EnumEndLine/Col`), same `type` section, with correct indentation + a leading blank line.
- Bodies edit: locate the `implementation` keyword position in the source. If the impl section is empty, insert right after `implementation` (a blank line then `{ TXHelper }` + bodies). If it has routines, insert after the last one (or just before the final `end.`). Source the `implementation` position from the Task 1 section-anchor fact if available, else a bounded scan over preprocessed text for the `implementation` keyword (case-insensitive, not inside a string/comment -- reuse preprocessor-normalized text).
- `uses`: if `NeedsTypInfo` and neither interface nor implementation `uses` contains `System.TypInfo`/`TypInfo`, add it to the implementation `uses` (a third edit, or fold into the bodies edit). Query `unit_uses` for membership (do not string-scan).
- Refuse: if the source has NO `implementation` keyword -> `Action:=ehaNoImplSection`, no edits, message. If `AResolve.HasHelper` -> `Action:=ehaExists`, message names the unit (`HelperUnitPath`). If `not Found` -> `ehaNotFound`.

- [ ] **Step 4: Run -- verify PASS**

- [ ] **Step 5: Interface-only-unit + refuse tests**

`tests/refactor/fixtures/enumhelper/interface_only.pas` (enum in interface, EMPTY implementation section) -> `ehaBuilt`, bodies land in the empty impl. `already_has_helper.pas` -> `ehaExists`, no edits. A malformed fragment with no `implementation` -> `ehaNoImplSection`. Run -- PASS.

- [ ] **Step 6: Commit**

```bash
git add src/refactor/DRagLint.Refactor.EnumHelper.pas tests/refactor/EnumHelperTests.dpr tests/refactor/fixtures/enumhelper
git commit -m "feat(refactor): EnumHelper PLACE -- decl+bodies edits, populate empty impl, refuse rules"
```

---

## Task 5: CLI verb `create-enum-helper`

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (arg parsing for the verb + `--methods`/`--tostring`; a `DoCreateEnumHelper`; dispatch at ~10388; add a `helpers-of <T>` query verb too for Task 1's parity + the IDE enablement)
- Test: `tests/refactor/run_enum_helper.ps1` (grow it: e2e dry-run/json/apply/refuse/usage)

**Interfaces:**
- Consumes: `TEnumHelperRefactoring.Build`; `TTextEditApplier.Apply/RenderDryRun` (existing).
- Produces: CLI verbs `create-enum-helper` and `helpers-of` (both `--db`, `--json`).

- [ ] **Step 1: Write the failing e2e test**

Grow `run_enum_helper.ps1` (header/`Assert`/`Test-Compiles` copied from `run_extract_method.ps1`). Assertions: index `simple.pas` to a temp DB; `create-enum-helper --qname TColor --db <db> --json` returns `action=built`, `edits=2`; `--apply --no-backup` writes the helper into a temp copy and `Test-Compiles` PASSES; running it again returns `action=exists` and makes NO change (idempotent, byte-identical); `--qname TNope` -> nonzero exit / not-found; missing `--qname` -> usage error nonzero.

- [ ] **Step 2: Run -- verify fail (unknown verb)**

- [ ] **Step 3: Implement `DoCreateEnumHelper` + `DoHelpersOf` + parsing + dispatch**

Parse `--qname`, `--methods <csv>` (default all 6), `--tostring rtti|case` (default rtti), `--apply`, `--no-backup`, `--json`, `--db`. Open the read-only store, call `Build`, apply edits when `--apply` and `Action=ehaBuilt`. JSON: `{qname,file,action,edits,applied}` mirroring `DoDocument`. Refuse actions -> nonzero exit + message (stderr). `helpers-of`: print the `FindHelpersOfType` rows (`--json` array of `{helper,target,unit}`). Wire both into the dispatch chain (~`DRagLint.CLI.pas:10388`), and register them in the `--help`/usage text.

- [ ] **Step 4: Build + run e2e -- verify PASS**

Build (delphi-build). Run `run_enum_helper.ps1` -- all pass, including the dcc64 compile of the applied result.

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/refactor/run_enum_helper.ps1
git commit -m "feat(cli): create-enum-helper + helpers-of verbs (dry-run/json/apply/idempotent)"
```

---

## Task 6: Full 10-case fixture suite + build/round-trip acceptance gate

**Files:**
- Create: fixtures under `tests/refactor/fixtures/enumhelper/` (explicit_ordinals, negative_ordinal, doc_interleaved, descriptions_reuse, roundtrip_use)
- Modify: `tests/refactor/run_enum_helper.ps1` (add cases 2,3,5,7,8,9,10 from the spec)

**Interfaces:**
- Consumes: the CLI verb (Task 5).
- Produces: the acceptance-gate suite. No new source interfaces.

- [ ] **Step 1: Add fixtures for spec cases 2,3,5,7**

- `explicit_ordinals.pas`: `TSpec = (sp_Undefined=0, sp_Double=1, sp_Upper=2);`
- `negative_ordinal.pas`: `TEST = (Elem1=-2, Elem2=0, Elem3);`
- `doc_interleaved.pas`: enum with `{$REGION 'x'}` + `///` lines between members.
- `descriptions_reuse.pas`: enum + `const TColorDescriptions: array[TColor] of string = ('r','g','b');`

- [ ] **Step 2: Add the round-trip USE fixture (case 8, the gate)**

`roundtrip_use.pas`: a unit that (after the helper is applied to `simple.pas` and both are compiled together, OR a self-contained unit with enum+helper+asserts) exercises all 6 methods and asserts round-trips: `clRed.ToByte=0`, `TColor.FromByte(2)=clBlue`, `clGreen.ToString='clGreen'`, `TColor.FromString('clBlue')=clBlue`, `TColor.FromInteger(1)=clGreen`. A console program returning nonzero on any failed assert.

- [ ] **Step 3: Extend `run_enum_helper.ps1` with cases 2,3,5,7,9,10**

- case 2: FromByte maps `Ord(sp_Double)->sp_Double`; `else` = `sp_Undefined`.
- case 3 (negative): applied result COMPILES; FromByte is a plain `case` over the members (Elem1 falls to else); NO ShortInt variant text present.
- case 5 (doc_interleaved): generated helper members == the real enum members (noise skipped).
- case 7 (descriptions): a `ToDescription` is generated using `TColorDescriptions`.
- case 9 (placement): decl is immediately after the enum decl; bodies in the impl section; interface_only fixture populates the empty impl.
- case 10 (CLI/IDE parity): assert the CLI-applied text equals the text an IDE call would apply (same `Build` output) -- exercise `Build` twice with identical args -> identical edits.

- [ ] **Step 4: Wire the round-trip build (case 8) into the harness**

In `run_enum_helper.ps1`: apply the helper to a temp copy of `simple.pas`, then `dcc64 -B` compile a small program that USES it and runs the round-trip asserts; assert exit 0. This is the acceptance gate.

- [ ] **Step 5: Run the whole suite -- verify all PASS**

Run: `pwsh tests/refactor/run_enum_helper.ps1`. Expected: `enum-helper: all pass`.

- [ ] **Step 6: Commit**

```bash
git add tests/refactor/fixtures/enumhelper tests/refactor/run_enum_helper.ps1
git commit -m "test(refactor): full enum-helper 10-case suite + build/round-trip acceptance gate"
```

---

## Task 7: Lint rule `enum-helper-separate-units` (ON by default)

**Files:**
- Modify: `src/lint/DRagLint.Lint.DocRules.pas` OR the appropriate rule unit (a cross-unit relationship rule -- likely `DRagLint.Lint.ProjectRules.pas` since it needs the whole-DB helper edge); add the rule + catalog entry + doc-comment
- Modify: wherever the rule catalog + default-enabled set live (ensure ON in BOTH `DoLintAll` and `DoLintProject`)
- Test: `tests/lint-project/` (or `tests/lint/`) -- a new fixture pair + a catalog/default assertion

**Interfaces:**
- Consumes: `ISymbolStore.FindHelpersOfType` (Task 1); the enum symbol + its file.
- Produces: rule id `enum-helper-separate-units`, ON by default.

- [ ] **Step 1: Write the failing rule test**

Two fixtures: enum `TX` in `unitA.pas`, `TXHelper record helper for TX` in `unitB.pas`. Assert the rule FIRES with a message naming both units. A same-unit fixture -> NO finding. Plus: assert the rule is ON by default in the catalog AND fires in a bare (no-config) run through BOTH lint paths.

- [ ] **Step 2: Run -- verify fail (rule absent)**

- [ ] **Step 3: Implement the rule**

For each `skEnum`, `FindHelpersOfType(enumName)`; for any edge whose `TargetFileId`/helper file != the enum's file, emit a finding: `"helper <THelper> (unit <A>) is separate from enum <TX> (unit <B>); consider co-locating."` Register in the catalog with default ON. Ensure the ON default is applied in both `DoLintAll` and `DoLintProject` (check the DefDisabled/ShouldKeep path -- AutoDocument LATEST-19 lesson).

- [ ] **Step 4: Run -- verify PASS**

- [ ] **Step 5: Regression test -- default honored in both paths**

Add an explicit test toggling nothing (bare run) that the rule appears in `DoLintProject` output AND `DoLintAll` output. (Mirrors the missing-doc regression `e038503`.)

- [ ] **Step 6: Commit**

```bash
git add src/lint tests/lint-project
git commit -m "feat(lint): enum-helper-separate-units rule (ON by default, both lint paths)"
```

---

## Task 8: IDE menu "Create helper class"

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.StructureForm.pas` (context-menu item + enablement predicate + spawn via `DragLintExe`)
- (No automated test -- IDE smoke is user-driven, per every prior IDE feature.)

**Interfaces:**
- Consumes: the `create-enum-helper --apply` CLI verb (Task 5); `helpers-of` for enablement; the shared `DragLintExe` resolver.
- Produces: an IDE menu action. No new code interface.

- [ ] **Step 1: Add the menu item + enablement predicate**

Model on the AutoDocument "Document it" item. Enable when the symbol under cursor is a `skEnum`, OR a `skEnumValue` whose parent is a `skEnum`, AND `helpers-of <enum>` returns none. Reuse the structure-tab's symbol-at-cursor resolution.

- [ ] **Step 2: Wire the action -> spawn the CLI verb**

On click: resolve the enum's qname, spawn `DragLintExe create-enum-helper --qname <X> --apply` via the shared resolver; on success reload the buffer (string-only ForceQueue reload, per the AutoFix/ExtractMethod IDE pattern).

- [ ] **Step 3: Build the plugin BPL (delphi-build, Win32 as the IDE loads Win32/Win64 per convention)**

Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`. Do NOT run deploy-staged.bat; the user reopens RAD Studio to smoke-test.

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.StructureForm.pas
git commit -m "feat(plugin): 'Create helper class' context menu (spawns create-enum-helper)"
```

---

## Task 9: Full battery + reindex + self-lint

**Files:**
- Run: all test harnesses; reindex the DragLint self-index.

**Interfaces:** none.

- [ ] **Step 1: Run the full battery**

Run the lint / store / refactor / autodoc / autofix / migrate / formsmap / helper-edges / enum-helper harnesses. Expected: all green. Record counts.

- [ ] **Step 2: Reindex the self-index (schema v15) + sanity-check the new rule's FP count**

`drag-lint index --all --only DragLint` with the new exe. Then run the linter on this repo and RECORD the `enum-helper-separate-units` finding count (the ON-by-default risk check). If the count is high/noisy on this repo + ORM3, flag it in the release notes and reconsider the default (spec Section 6).

- [ ] **Step 3: Commit any harness/index updates**

```bash
git add tests
git commit -m "test: full battery green on schema v15 + enum-helper; record separate-units FP count"
```

---

## Task 10: Final whole-branch review + release

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas:6` (VERSION bump), `CHANGELOG`, `docs/lint/BACKLOG.md`

**Interfaces:** none.

- [ ] **Step 1: Request a final whole-branch review**

Use superpowers:requesting-code-review over the whole branch diff (all tasks). Address Critical/Important before release (per the AutoDocument milestone, the final review is where a per-task-missed Critical surfaces -- e.g. a default honored in one lint path but not the other).

- [ ] **Step 2: Bump VERSION + CHANGELOG + BACKLOG**

`CLI.pas:6` -> the next alpha (e.g. `0.94.0-alpha`). CHANGELOG entry. BACKLOG resume line.

- [ ] **Step 3: Build release exes (win64 + win32, delphi-build) + pack CLI-only zips**

Per the v0.87 release convention: release commit = CLI.pas + CHANGELOG + BACKLOG only; BPL/DCP in a SEPARATE build(plugin) commit; release ZIP is CLI-only. Kill any orphaned `drag-lint.exe` before packing.

- [ ] **Step 4: Commit the release + tag**

```bash
git add src/cli/DRagLint.CLI.pas CHANGELOG* docs/lint/BACKLOG.md
git commit -m "release(doc): v0.94.0-alpha -- enum-helper generator + first-class helper indexing"
git tag v0.94.0-alpha
```

- [ ] **Step 5: Publish the GitHub release (user drives the push)**

Push `main` + tag; create the GitHub release (win64 + win32 CLI zips), `--latest`, isPrerelease=false. (The human runs the push/publish; do not push autonomously without the release being ready.)

---

## Self-Review

**Spec coverage:**
- Section 3 (Byte template) -> Task 3. Section 4 pipeline (RESOLVE/GENERATE/PLACE) -> Tasks 2/3/4. Revised placement (populate empty impl) -> Task 4 Step 5 + Task 6 case 9. Section 5 (helper indexing, schema v15) -> Task 1 (+ Task 0 AST probe). Section 6 (separate-units rule, ON default, both paths) -> Task 7. Section 7 (CLI verb) -> Task 5. Section 8 (IDE menu) -> Task 8. Section 9 (10-case suite + build/round-trip gate) -> Task 6 (+ RESOLVE/PLACE cases in 2/4). S1.2 section anchors -> Task 4 Step 3 uses it if present, else bounded scan (folded, optional). FP-count risk -> Task 9 Step 2. Final-review Critical-catch discipline -> Task 10 Step 1.
- Gap check: `--methods`/`--tostring` -> Task 3 + Task 5. `ToDescription` auto -> Task 3. Idempotency -> Task 5 Step 1. Migration retrofit -> Task 1 Steps 4+8. All covered.

**Placeholder scan:** No TBD/TODO. Two deliberate implementation-choice points (Task 1 Step 5 parser-marker approach; Task 4 Step 3 section-anchor source) each state the decision rule + fallback, grounded in Task 0's finding -- not placeholders.

**Type consistency:** `TEnumHelperResolve`/`TEnumHelperGen`/`TEnumHelperResult` flow Task 2->3->4. `TEnumHelperMethods`/`TToStringMode` defined in Task 2 interfaces, consumed in Task 3/5. `THelperEdge`/`FindHelpersOfType` defined in Task 1, consumed in Tasks 2/7/8. `Build` (Task 4) is the single entry consumed by Task 5 (CLI) + Task 8 (IDE). Consistent.
