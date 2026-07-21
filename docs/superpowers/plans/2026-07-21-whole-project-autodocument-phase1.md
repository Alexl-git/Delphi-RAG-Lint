# Whole-Project Auto-Document — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.
>
> **RESUME NOTE:** Written for a FRESH session. Each task's implementer READS the named source region first (exact current code is intentionally not transcribed — read it, then edit). Spec: `docs/superpowers/specs/2026-07-21-whole-project-autodocument-phase1-design.md`.

**Goal:** Surface whole-project auto-document in the IDE menu and make its deterministic (no-AI) DocInsight output richer (real `Result := …` returns, tighter "used in" cap, index-derived facts) and less noisy (skip trivial property accessors).

**Architecture:** Additive. The `document` verb family and its facts layer (`src/doc/DRagLint.Doc.Facts.pas` gathers `TDocFacts`, `src/doc/DRagLint.Doc.Regions.pas` renders the managed `<!-- drag-lint:auto -->` block) already exist and are used by `document --qname/--unit/--project/document-all`. This phase (1) enables the already-built return-case miner + a caller cap via manifest `docs` config, (2) adds a batch-mode trivial-accessor filter, (3) adds a group of cheap index-lookup facts, and (4) adds an IDE menu item that spawns `document --project --apply`.

**Tech Stack:** Delphi 13 (Studio 37), Win64 console build (`build/build_draglint_win64.bat`), FireDAC/SQLite, PowerShell autotests, Python 3.14 sqlite3 for DB assertions, Open Tools API (plugin BPL).

## Global Constraints

- All `.pas`: strict 7-bit ASCII, CRLF, no BOM. Verify after every edit (`$b=[IO.File]::ReadAllBytes($p); ($b|?{$_ -gt 127}).Count` = 0). DocInsight `///` on new public surface.
- Deterministic, NO AI (project rule "No LLM API calls — pure Object Pascal"). Every fact is index/AST-derived ground truth. Never fabricate; follow the existing `?`-suffix honesty convention for uncertain facts.
- Managed output stays INSIDE the existing `<!-- drag-lint:auto BEGIN/END -->` region so regeneration never disturbs hand-written prose.
- `document --qname` (single symbol, explicit request) is NEVER affected by the trivial-accessor filter.
- Facts-only, not `--stubs`. New fact lines render omit-when-empty to keep the block lean.
- Build recipe: `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` + log; require `BUILD_EXITCODE=0`, no `[dcc] Error`. Never the MCP build tool or Bash+cmd. Kill orphaned drag-lint.exe if the exe is locked. Test exe = `src/cli/Win64/Debug/drag-lint.exe`; deployed copy = `third_party/dll-win64/drag-lint.exe` (gitignored).
- Autotests: model on an existing doc runner (`tests/autodoc/run_doc_drift_engine.ps1`); take `-Exe`, redirect the exe's stderr banner, `$ErrorActionPreference='Continue'`, Check/$script:Failed/exit-code. Build fixtures into a temp DB — do NOT pollute a real corpus DB. No sqlite3 on PATH → `C:\Python314\python` (`?mode=ro`).
- Use `drag-lint query` on the self-index (`C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite`, now v17) for Delphi symbol lookups; Grep only for text/non-Delphi.
- Do NOT push (user drives push). Plugin BPL work follows `C:\Projects\Delphi_IDE_OptionsPage_HOWTO.md` conventions where relevant.

---

### Task 1: Enable real returns + tighten the caller cap (enhancement A — config)

**Files:**
- Read: `src/cli/DRagLint.CLI.pas` `LoadDocMaxReturnCases` (~1016), the `Opts.MaxReturnCases:=` sites in `DoDocumentUnit`/`DoDocumentProject`/`DoDocumentAll`/`DoDocument` (~6597/6683/6709/6735), and how the facts builder caps `CalledFrom` (`src/doc/DRagLint.Doc.Facts.pas` `TDocFactsBuilder.Build` + the `CalledFromTotal` handling); `src/doc/DRagLint.Doc.Regions.pas` `RenderFactsBlock` "Called from"/returns emit.
- Modify: `third_party/dll-win64/drag-lint.json` (add `docs` section); `src/cli/DRagLint.CLI.pas` (a `LoadDocMaxCallers` loader mirroring `LoadDocMaxReturnCases`, threaded into the doc modes + facts builder) IF no caller-cap config exists.
- Test: `tests/autotest/run_doc_returns_and_callers.ps1`.

**Interfaces (produced):** manifest `docs.max_return_cases` (int) + `docs.max_callers` (int) honored by all `document` batch modes; the facts builder caps `CalledFrom` at `max_callers` (default 5) and `ReturnCases` at `max_return_cases` (default 6).

- [ ] Read the regions above. Confirm whether a caller cap is already config-driven or a hard-coded constant; if constant, add `LoadDocMaxCallers` (default 5) exactly like `LoadDocMaxReturnCases` and thread it wherever the caller list is truncated.
- [ ] **Write the failing test** `run_doc_returns_and_callers.ps1`: a fixture unit with (a) a function whose body has ≥2 distinct `Result := X;` / `Result := Y;` sites, and (b) ≥7 call sites of it across the fixture. Index into a temp DB with a manifest/config that sets `max_return_cases=6`, `max_callers=5`. Run `document --qname <fn> --db <temp>`; assert the emitted comment's `<returns>` contains the mined RHS expressions (NOT "TODO: describe") and the "Called from:" line lists exactly 5 entries + "(+N more)".
- [ ] Run it → RED (returns show TODO / callers not capped at 5).
- [ ] Add the `docs` section to the manifest (`max_return_cases: 6`, `max_callers: 5`); implement/thread `LoadDocMaxCallers` if needed. Do NOT change the absent-section loader defaults for return-cases (only the manifest carries the on-value); the caller-cap in-code default may be 5.
- [ ] Build; run the test → GREEN. Commit.

---

### Task 2: Skip trivial property accessors in batch modes (enhancement B)

**Files:**
- Read: `src/cli/DRagLint.CLI.pas` `DoDocumentUnit`/`DoDocumentProject`/`DoDocumentAll` (the loop that enumerates decls to document) + the arg parser (~600-690, where `--stubs`/`--seealso` etc. are parsed); how a property's `read`/`write` accessor name links to a method symbol (the R1 extraction work + the `symbols` property rows; a method is an accessor iff its name appears in a property's read/write clause for the same type). Symbol line span = `start_line/impl_start_line`..`impl_end_line`.
- Modify: `src/cli/DRagLint.CLI.pas` (the batch-mode decl filter + `--include-accessors` arg + `LoadDocAccessorMaxLines` default 2).
- Test: `tests/autotest/run_doc_skip_accessors.ps1`.

**Interfaces (produced):** batch `document` modes skip a decl that is a property accessor whose impl body line count `<= accessor_trivial_max_lines` (default 2); `--include-accessors` overrides; `document --qname` unaffected.

- [ ] Read the regions above. Determine the precise accessor linkage available (property read/write → method). If precise linkage is not resolvable for a symbol, fall back to `Get*/Set*` name-prefix AND accessor-of-some-property; document the fallback in the report.
- [ ] **Write the failing test** `run_doc_skip_accessors.ps1`: a fixture class with `FA: Integer` + `property A: Integer read GetA write SetA;` where `GetA` is a 1-line `Result := FA;`, `SetA` is a 1-line `FA := Value;`, a non-trivial `function GetB: Integer;` (3-line body doing real work, backing `property B: Integer read GetB;`), and an ordinary `procedure DoWork;`. Index to a temp DB. Assert: `document --unit <file> --db <temp>` documents `GetB` + `DoWork` but NOT `GetA`/`SetA`; `document --qname <...GetA> --db <temp>` DOES document `GetA`; `document --unit <file> --include-accessors --db <temp>` documents all four.
- [ ] Run it → RED.
- [ ] Implement the filter in the batch modes (gated by `accessor_trivial_max_lines`, default 2, from config); add `--include-accessors`; report skipped count.
- [ ] Build; run the test → GREEN. Commit.

---

### Task 3: Cheap fact group — overrides, implements, overload set, virtual/abstract

**Files:**
- Read: `src/doc/DRagLint.Doc.Facts.pas` (`TDocFacts` record + `TDocFactsBuilder.Build`, including the existing `Deprecated` source-line fallback pattern and the `SeeAlso` gather for how it resolves related symbols); `src/doc/DRagLint.Doc.Regions.pas` `RenderFactsBlock` (the `Sb.AppendLine(APrefix + 'Called from: ' ...)` block ~137-143 — the exact place new lines go, with `MoreSuffix`/`JoinRefs` helpers). For the data: how ancestry/heritage is queried (the `ResolveAncestry` output / ancestor edges used by proptree), how overloads are found (same `name` + same `parent_id`), and how a method's interface-membership can be resolved (heritage to an interface + matching member signature).
- Modify: `src/doc/DRagLint.Doc.Facts.pas` (+fields, +gather), `src/doc/DRagLint.Doc.Regions.pas` (+render lines).
- Test: `tests/autotest/run_doc_cheap_facts.ps1`.

**Interfaces (produced):** `TDocFacts` gains `Overrides: string`, `OverriddenBy: TArray<string>` + `OverriddenByTotal: Integer`, `Implements: string`, `OverloadOrdinal, OverloadCount: Integer`, `IsAbstract, IsVirtual: Boolean`. `RenderFactsBlock` emits one omit-when-empty line each: `Overrides: X`, `Overridden by: A, B (+N)`, `Implements: I.M`, `Overload k of n`, `abstract`/`virtual` marker.

- [ ] Read the regions above.
- [ ] **Write the failing test** `run_doc_cheap_facts.ps1`: a fixture with `TBase = class ... procedure DoPaint; virtual; abstract; end;`, `TDerived = class(TBase) procedure DoPaint; override; end;`, a second `TDerived2 = class(TBase) procedure DoPaint; override; end;`, an interface `IGreeter = interface function Greet: string; end;` + `TGreeter = class(TInterfacedObject, IGreeter) function Greet: string; end;`, and an overloaded `procedure Log(const S: string); overload;` + `procedure Log(const N: Integer); overload;`. Index to a temp DB. Assert the managed block for: `TBase.DoPaint` → `abstract` marker + `Overridden by: ...TDerived..., ...TDerived2...`; `TDerived.DoPaint` → `Overrides: ...TBase.DoPaint`; `TGreeter.Greet` → `Implements: ...IGreeter.Greet`; one `Log` → `Overload 1 of 2` (and the other `2 of 2`).
- [ ] Run it → RED.
- [ ] Implement the fields + gather + render (each line omit-when-empty; caps + `(+N)` for `Overridden by`). Reuse existing ancestry/overload/heritage query helpers — do not reinvent.
- [ ] Build; run the test → GREEN. Commit.

---

### Task 4: Cheap fact — Platform / conditional (best-effort; deferrable)

**Files:**
- Read: how (if at all) a decl's enclosing `{$IFDEF MSWINDOWS}`/platform guard is recoverable — check the index schema (is a define/conditional recorded per symbol?) and the `Deprecated` source-line fallback in `TDocFactsBuilder.Build` as a model for a bounded source read.
- Modify (only if cheaply feasible): `src/doc/DRagLint.Doc.Facts.pas` (`Platform: string` field + gather), `src/doc/DRagLint.Doc.Regions.pas` (render `Platform: Win32-only`).
- Test: `tests/autotest/run_doc_platform_fact.ps1` (only if implemented).

**Interfaces (produced, IF implemented):** `TDocFacts.Platform: string`; renders `Platform: <p>-only` when set.

- [ ] Investigate feasibility. **Decision gate:** if the guard is NOT cheaply derivable (requires a non-trivial upward source scan or brace-matching across the file), DO NOT implement — instead record in the report that Platform is deferred to Phase 2, add a one-line note to the spec's "resolved" list, and commit nothing for this task (mark it done-deferred). Only proceed if it's a bounded lookup/scan comparable to `Deprecated`.
- [ ] IF feasible: **write the failing test** — a fixture with a routine under `{$IFDEF MSWINDOWS}...{$ENDIF}` → assert its block shows `Platform: Win32` (or the platform label the engine uses). Run → RED.
- [ ] IF feasible: implement + render. Build; test → GREEN. Commit.

---

### Task 5: IDE menu item — "Auto-Document Whole Project…"

**Files:**
- Read: `src/delphi-plugin/DragLint.Plugin.Editor.pas` — the `SubGen` submenu build (~4546-4553), `AddWrappedItem`, the existing `InvokeGenerateDocs` handler (the model: how a spawn-based action resolves context + runs the exe + reports to Messages/Output), and how the ACTIVE project's `.dproj` path is obtained (the same resolution `InvokeReindexProject`/reconcile actions use).
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (new `InvokeAutoDocumentProject` + `AddWrappedItem(SubGen, 'Auto-Document Whole Project...', InvokeAutoDocumentProject)`).
- Build: the plugin BPL (per the standard plugin build; not the console build). Verify manually in the IDE.

**Interfaces (produced):** a new menu item that spawns `drag-lint document --project <active.dproj> --apply` (facts-only) and streams the result to the plugin Output.

- [ ] Read the regions above.
- [ ] Implement `InvokeAutoDocumentProject`: resolve the active project's `.dproj`; if none, show a friendly message and exit. Spawn the deployed exe `document --project <dproj> --apply` (do NOT add `--no-backup`; backups are wanted). Stream per-file output + a final one-line summary (edits, files, accessors skipped) to the plugin Output, mirroring `InvokeGenerateDocs`/other spawn actions. Add the `SubGen` menu item next to "Doc Comment Stub (symbol)…".
- [ ] Build the plugin BPL clean (0 errors). Verify ASCII+CRLF on the edited `.pas`.
- [ ] **Manual verification (record in report):** in a live IDE with a project open, invoke the item; confirm it writes DocInsight into the project's source, leaves `.bak` files, and prints the summary. (No automated IDE test — this is a spawn wrapper over the CLI-tested behavior.)
- [ ] Commit (source only; the BPL/exe are build artifacts per repo convention).

---

### Task 6: Docs + CHANGELOG

**Files:**
- Modify: `docs/AI-USAGE.md` and/or `docs/CONVERSION-RULES.md` (the `document`-verb section — document `--include-accessors`, the manifest `docs` config keys, the new managed-block fact lines, and the IDE "Auto-Document Whole Project" menu item); `CHANGELOG.md`.

- [ ] Read the current `document`-verb documentation in those files.
- [ ] Update them: the new `docs` manifest keys (`max_return_cases`, `max_callers`, `accessor_trivial_max_lines`), `--include-accessors`, the trivial-accessor default behavior, the new fact lines (overrides/overridden-by/implements/overload/virtual-abstract[/platform if shipped]), and the IDE menu item. Add a `CHANGELOG.md` entry.
- [ ] Commit.

---

## Operational follow-on (NOT a code task — after Phase 1 ships + user drives)

Reindex **YADF** (`C:\Projects\YADF\YADF.dproj`) + **YADFOT** (`C:\Projects\YADF\YADFOT.dproj`) at v17 (add both to the manifest `indexes.sections`, or index ad-hoc DBs). In the YADF repo create a branch (e.g. `feat/self-documentation`), run the new menu item / CLI to auto-document there, review/debug on the branch, then merge to YADF main and ship YADF + drag-lint as next versions. This is user-driven (branch/merge/ship decisions) and gated on manual review of the generated docs.

---

## Self-Review

**Spec coverage:** Component 1 (menu) → Task 5; Component 2 (returns + caller cap) → Task 1; Component 3 (trivial accessors) → Task 2; Component 4 cheap facts → Task 3 (+ Platform → Task 4, deferrable per spec); config surface → Tasks 1+2; testing → each task's TDD; docs → Task 6; YADF/YADFOT rollout → Operational follow-on. All spec sections mapped. ✓

**Placeholder scan:** Deliverables, fixture shapes, flag names (`--include-accessors`), config keys (`max_return_cases`/`max_callers`/`accessor_trivial_max_lines`), and field names are concrete. Exact Delphi code is intentionally read-then-write per the RESUME NOTE (repo convention; each task names the exact file+region to read). Task 4 has an explicit decision gate (implement-if-cheap else defer), not a hand-wave. ✓

**Type/name consistency:** `TDocFacts` fields (`Overrides`/`OverriddenBy`/`OverriddenByTotal`/`Implements`/`OverloadOrdinal`/`OverloadCount`/`IsAbstract`/`IsVirtual`/`Platform`), config keys, and `--include-accessors` are used identically across Tasks 1-6. `document --qname` never-filtered stated consistently in the Global Constraints + Task 2. ✓

**Ordering:** Task 1 (config) and Task 2 (filter) are independent; Task 3/4 (facts) independent; Task 5 (menu) invokes the CLI behavior so lands after 1-4 give it good output; Task 6 docs last. Each task ends with an independently testable deliverable (Task 5's is a manual IDE check, by nature). ✓
