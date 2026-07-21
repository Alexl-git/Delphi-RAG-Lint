# proptree Assignability Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.
>
> **RESUME NOTE:** This plan is written for a FRESH session (handoff before implementation). Each task's implementer READS the named source region first (the exact current code is not transcribed here -- read it, then edit). Spec: `docs/superpowers/specs/2026-07-20-proptree-assignability-engine-design.md`. Handoff evidence + editor contract: `docs/lint/2026-07-20-proptree-assignability-engine-handoff.md`.

**Goal:** Make `proptree` (and `convert-scaffold`) emit per-leaf ASSIGNABILITY -- `is_writable`, `visibility`, `member_kind`, and the correct per-class concrete `type` -- so the ConvRulesEditor and `convert-scaffold` only ever offer VALID assignment targets (no read-only `.Handle`, no deep `LookAndFeel/Painter` noise, no cross-type `Properties` mismatch, plus public fields for PAS conversions).

**Architecture:** Additive `proptree/1 -> proptree/2` JSON schema (back-compat: absent fields default to today's "show everything"). Visibility, concrete-type, and public-field work needs NO re-index (data already in the index -- verified). Writability needs a new `prop_access` column captured at extraction + a library/project re-index. Do all no-re-index parts first (testable immediately), then R1 + re-index last.

**Tech Stack:** Delphi 13 (Studio 37), Win64 console build (`build/build_draglint_win64.bat`), FireDAC/SQLite, PowerShell autotests, Python 3.14 sqlite3 for DB assertions.

## Global Constraints

- All `.pas` source: strict 7-bit ASCII, CRLF, no BOM. Verify after every edit (`$b=[IO.File]::ReadAllBytes(p); ($b|?{$_ -gt 127}).Count` = 0). DocInsight `///` on new public surface.
- **Back-compat is load-bearing:** `is_writable` defaults **TRUE** when absent, `visibility` defaults `""`, `member_kind` defaults `"property"`. A proptree/1 consumer / old exe / un-re-indexed DB must behave exactly as today.
- Schema token: `schema` field in proptree JSON goes `proptree/1` -> `proptree/2`. Additive only -- keep every existing field.
- `is_writable = (prop_access <> 'ro')`. Fields = writable EXCEPT typed class constant (`const X: T = ...`) = read-only.
- Visibility = EFFECTIVE most-derived (a published redeclaration of a protected/public ancestor is published); resolve empty-`modifiers` rows via the ancestor walk (do not drop them).
- `--min-visibility published|public` default = emit ALL (back-compat). DFM surface = published; PAS surface = published + public (+ public fields).
- R3 class-accuracy: `Properties` must resolve to the queried class's own most-derived CONCRETE type and recurse into THAT -- a wrong-class concrete leaf must NEVER appear.
- Build recipe: `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` + log; require `BUILD_EXITCODE=0`, no `[dcc] Error`. Never the MCP build tool or Bash+cmd. Kill orphaned drag-lint.exe if the exe is locked.
- Use drag-lint query (self-index `C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite`) for Delphi symbol lookups; Grep only for text/non-Delphi.
- Do NOT push (user holds push). Deployed exe is gitignored.

---

### Task 1: `prop_access` schema column + migration

**Files:** `src/storage/DRagLint.Storage.SQLite.pas` (schema DDL + version bump + migration path); `src/storage/DRagLint.Storage.Schema.pas` if the version constant lives there. Test: a new autotest `tests/autotest/run_prop_access_migrate.ps1` (model on `tests/autotest/run_migrate_v12.ps1`).

**Deliverable:** `symbols` gains a nullable `prop_access TEXT` column; the schema version bumps; opening an OLD DB migrates cleanly (adds the column, existing rows NULL). No extraction yet -- column only.

- [ ] Read the current schema DDL + the `Migrate` version-step pattern (search the self-index: `drag-lint query --name Migrate --db <self>` / read `DRagLint.Storage.SQLite.pas` around the CREATE TABLE symbols + the version migration ladder).
- [ ] Write the failing test: migrate a copy of an existing DB with the new exe; assert `PRAGMA table_info(symbols)` includes `prop_access`; assert existing rows have `prop_access IS NULL`; assert re-open is idempotent.
- [ ] Add the column to the CREATE TABLE + an `ALTER TABLE symbols ADD COLUMN prop_access TEXT` migration step at the next version number.
- [ ] Build; run the test to green; commit.

---

### Task 2: proptree/2 schema + R2 visibility + `--min-visibility` (no re-index)

**Files:** `src/report/DRagLint.Convert.PropTree.pas` (`TPropNode` gains `Visibility`, `IsWritable`, `MemberKind`; visibility resolution); `src/cli/DRagLint.CLI.pas` (`DoPropTree` JSON emit + `--min-visibility` arg + `schema` -> `proptree/2`). Test: `tests/autotest/run_proptree_visibility.ps1`.

**Interfaces (produced):** `TPropNode.Visibility: string`, `.IsWritable: Boolean` (default True this task), `.MemberKind: string` (default 'property'); proptree JSON per leaf adds `visibility`, `is_writable`, `member_kind`; top-level `schema="proptree/2"`; CLI `--min-visibility published|public`.

- [ ] Read `TPropNode`, `CollectProps`/`Walk`/`DeclaredIn` resolution, and `DoPropTree`'s JSON builder.
- [ ] Write failing test (fixture with published/public/protected props across an ancestor chain incl. a bare redeclaration that raises visibility): `--min-visibility published` emits only published leaves; `--min-visibility public` adds public leaves each carrying `visibility`; no flag = all; `schema` = `proptree/2`; `is_writable` present (true), `member_kind` = "property".
- [ ] Implement: carry effective (most-derived; ancestor-walk for empty `modifiers`) visibility onto `TPropNode`; emit the 3 new JSON fields + bump schema; honor `--min-visibility`. Keep `is_writable` hard-coded true here (R1 fills it later).
- [ ] Build; green; commit.

---

### Task 3: R3 concrete polymorphic type -- class-accurate (no re-index)

**Files:** `src/report/DRagLint.Convert.PropTree.pas` (concrete-type resolution in `CollectProps`/`ResolveInheritedType`/the bridge). Test: `tests/autotest/run_proptree_polymorphic.ps1`.

**Deliverable:** for a queried class, a redeclared property (`Properties`) resolves to that class's most-derived CONCRETE (non-empty-signature) type and recurses into THAT; a most-derived visibility-only (empty-signature) redeclaration does NOT collapse to the base (prefer nearest concrete own-class signature). Composes with the existing unknown-type bridge/down-propagation.

- [ ] Read `CollectProps` (most-derived dedup), `ResolveInheritedType`, `ResolveViaBridgedAncestry`.
- [ ] Write failing test: fixture with `TBaseEdit` (`property Props: TBaseProps`), `TCheckBox`(`Props: TCheckProps`), `TBtnEdit`(`Props: TBtnProps`), and a bare-redeclaration subclass. Assert `proptree TCheckBox` -> `Props.type = TCheckProps` and recurses to a checkbox-only leaf, and a `TBtnProps`-only leaf is ABSENT; `proptree TBtnEdit` -> `TBtnProps`.
- [ ] Implement/verify the winning-declaration TYPE token (not just DeclaredIn) is used; guard the empty-signature-redeclaration covariance case.
- [ ] Build; green; commit.

---

### Task 4: R4 public fields as targets (no re-index)

**Files:** `src/report/DRagLint.Convert.PropTree.pas` (`CollectProps`/`Walk` include `skField`); CLI emit already carries `member_kind`. Test: `tests/autotest/run_proptree_fields.ps1`.

**Deliverable:** public/published `skField` members are emitted as leaves with `member_kind="field"`, `is_writable=true` (typed class-const = false); they appear under `--min-visibility public`, NOT under `published`.

- [ ] Read the property-kind filter in `CollectProps`/`Walk`.
- [ ] Write failing test: fixture class with a `public FThing: Integer;` field + a `const KMax: Integer = 5;` typed const + a private field. Assert under `--min-visibility public`: `FThing` leaf present, `member_kind="field"`, `is_writable=true`; `KMax` `is_writable=false`; private field absent; under `--min-visibility published`: no fields.
- [ ] Implement field inclusion gated by effective visibility + mode.
- [ ] Build; green; commit.

---

### Task 5: convert-scaffold consumes assignability (no re-index)

**Files:** `src/cli/DRagLint.CLI.pas` `DoConvertScaffold` (+ the scaffold matcher in `src/report/DRagLint.Convert.*`). Test: `tests/autotest/run_convert_scaffold_assignability.ps1`.

**Deliverable:** `convert-scaffold` restricts auto-`#link` TARGETS to `is_writable=true` and (DFM surface) `visibility=published`, using the R3 concrete type for the compatibility test. Add `--surface dfm|pas` (or reuse `--min-visibility`) to pick the target surface.

- [ ] Read `DoConvertScaffold` + how it auto-matches To paths to From paths.
- [ ] Write failing test: scaffold to a target that has a read-only leaf + a public-only leaf. Assert the read-only leaf gets NO auto-`#link` (or is `#ignore`d); a DFM-surface scaffold excludes the public-only leaf; a PAS-surface scaffold includes it.
- [ ] Implement the filter (depends on Tasks 2-4 fields being present; on a proptree/1 DB it degrades to today's behavior via the defaults).
- [ ] Build; green; commit.

---

### Task 6: R1 writability extraction (`read`/`write` -> `prop_access`) + inheritance

**Files:** `src/parser/DRagLint.Parser.Delphi13.pas` (property_declaration -> capture accessor clause); `src/core/DRagLint.Core.Indexer.pas` (persist `prop_access`); `src/report/DRagLint.Convert.PropTree.pas` (wire `IsWritable` from resolved `prop_access`, inheritance like `type`). Tests: `tests/autotest/run_prop_access_extract.ps1` + extend `run_proptree_visibility`/a writable fixture.

**Deliverable:** property extraction records `prop_access` = `ro`/`rw`/`wo` from the `read`/`write` clause; a bare redeclaration inherits the ancestor's accessors (own decl else nearest ancestor with a non-empty accessor clause; adding `write` -> `rw`). proptree `is_writable` = `prop_access <> 'ro'`.

- [ ] Read the parser's property_declaration handling + how signature/type is currently extracted; find where accessors are dropped.
- [ ] Write failing test: index a fixture with `property RO: Integer read FRO;`, `RW: ... read FRW write FRW;`, `WO: ... write FWO;`, and a bare `property RO;` redeclaration in a subclass. Assert stored `prop_access` = ro/rw/wo; subclass bare `RO` resolves to ro. Assert `proptree` `Handle`->`is_writable=false`, `Caption`->`true` on a real control fixture.
- [ ] Implement extraction + `prop_access` persistence + inheritance resolution + wire `IsWritable`.
- [ ] Build; green; commit.

---

### Task 7: Re-index + full-corpus verification

**Files:** none (operational). 

**Deliverable:** libraries (`library-Win32`, `library-Win64` ~1.8GB) + project DBs re-indexed so `prop_access` is populated corpus-wide; spot-checks pass on real controls.

- [ ] Investigate a properties-only incremental pass; if not viable, run `drag-lint index --all` per the manifest (`third_party/dll-win64/drag-lint.json`). Expect this to be slow; watch for locks (kill orphaned drag-lint.exe / drag_lint_graph.exe).
- [ ] Verify: `proptree cxButtons.TcxButton --min-visibility published --db library-Win32` -> `.Handle`/`.Count`-style read-only leaves have `is_writable=false`; `.Caption` true; deep `LookAndFeel/Painter/ViewInfo` internals absent at published; a wrong-class `Properties` concrete leaf absent.
- [ ] Reindex the drag-lint self-index if engine symbols changed.

---

### Task 8: Update index documentation (user request)

**Files:** `docs/INDEXING-AND-DB-ARCHITECTURE.md`; the proptree/schema docs (`docs/AI-USAGE.md`, `docs/CONVERSION-RULES.md`); `CLAUDE.md` index section if it enumerates schema/columns; `CHANGELOG.md`.

**Deliverable:** documentation reflects the new `prop_access` column, the `proptree/2` schema (the 4 additive leaf fields + back-compat defaults), the `--min-visibility` flag, and the DFM/PAS target-surface semantics.

- [ ] Update `INDEXING-AND-DB-ARCHITECTURE.md`: add `prop_access` to the symbols-table schema description + the extraction note.
- [ ] Document `proptree/2` (is_writable/visibility/member_kind + concrete type + defaults) and `--min-visibility` wherever proptree/1 is described.
- [ ] Changelog entry. Commit.

---

## Self-Review

**Spec coverage:** R1 -> Task 1 (column) + Task 6 (extract) + Task 7 (re-index); R2 -> Task 2; R3 -> Task 3; R4 -> Task 4; convert-scaffold consumption -> Task 5; proptree/2 schema -> Task 2 (+ filled by 3/4/6); doc update -> Task 8. All spec sections mapped. ✓
**Placeholder scan:** Deliverables + test expectations are concrete; exact Delphi code is intentionally read-then-write per task (handoff-resume flow) -- each task names the exact file + region to read first. No "TBD"/"add error handling" hand-waves. ✓
**Type consistency:** `TPropNode.{Visibility,IsWritable,MemberKind}` and the JSON keys `visibility`/`is_writable`/`member_kind` are used identically across Tasks 2-6; `prop_access` values `ro`/`rw`/`wo` and `is_writable = prop_access<>'ro'` consistent Tasks 1/6. ✓
**Ordering:** no-re-index Tasks 1-5 are independently testable before the expensive Task 6/7; back-compat defaults let Tasks 2-5 land while `is_writable` is still a placeholder. ✓
