# v0.69 -- Rule catalog + Lint Options tab, refactor CLI, close #1 naming -- design

> Status: approved 2026-06-30 (brainstorming). Three independent deliverables, each
> packaging infrastructure that *already exists* rather than building new engines.
> **Value prop:** the IDE's native Refactor is degraded because it leans on a flaky
> async LSP / background-compiler symbol model; drag-lint's persisted, deterministic
> SQLite index is the substrate that avoids that failure mode -- cross-unit rename /
> find-references / dead-code are computed from a stable index, not a racing compiler.
> v0.69 surfaces that substrate as (1) a machine-readable rule catalog + a 4th IDE
> "Lint Options" tab, (2) packaged refactor CLI commands (rename / find-unit /
> safe-delete), and (3) the two naming rules that close MISSING-FEATURES #1.
> Build order: **(2) refactor CLI (S/S-M, but mostly packaging) is deferred to last;
> ship (3) first (small, closes #1) -> (1) catalog + tab -> (2) refactor CLI.**
> Each deliverable gets its OWN `writing-plans` implementation plan next session.
> VERSION bumps to `0.69.0-alpha` (`src/cli/DRagLint.CLI.pas:6`) at release.

---

## 0. Architecture invariant (all three deliverables)

Everything stays **out-of-process**, consistent with the existing plugin design: the
CLI exe (`third_party\dll-win64\drag-lint.exe`) computes; the IDE tab/UI is a thin
consumer that shells out to the CLI and renders/edits JSON. No analysis logic moves
into the BPL. The standalone `drag-lint-config.exe` (`src/config/`) is the same kind
of thin consumer, so the new "Lint Options" frame is built self-contained to be
hostable by both the dock and the config exe later.

**Decomposition:** the three deliverables share no code paths and can be implemented,
tested, and shipped independently. They are sequenced (3 -> 1 -> 2) only by
risk/leverage, not by dependency.

---

## 1. Deliverable 1 -- Rule catalog + "Lint Options" IDE tab

### 1a. `drag-lint rules` -- the catalog command (NEW)

Today there is **no single catalog**: 55 external `rules\*.scm` each carry a
`rules\<id>.json` (only `id`, `severity`, `message` -- no category/params); ~40+
built-in rules exist only as ids in the CLI help "known:" string
(`src/cli/DRagLint.CLI.pas:4492`) and the `DoLint` `--rule` allow-list; `rules\README.md`
has a hand-maintained ~85-row table that drifts. `drag-lint rules` becomes the single
machine-readable source of truth for EVERY check.

- **Syntax:** `drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]`.
  Default emits a grouped text table (id, category, severity, enabled); `--json`
  emits the structured catalog below.
- **Per-rule record:**
  ```json
  { "id": "too-many-parameters",
    "category": "complexity",
    "title": "Routine has too many parameters",
    "default_severity": "info",
    "default_enabled": true,
    "source": "builtin",                       // scm | builtin | project | flow
    "params": [ { "name": "threshold", "type": "int", "default": 7 } ] }
  ```
- **Built from two sources, merged:**
  1. A small in-code **REGISTRY** (new unit `DRagLint.Lint.RuleCatalog`) of the
     built-ins -- their category/title/default-severity/source/params. The
     configurable ones map their `params` to `TLintConfig.ThresholdFor` names
     (`too-many-parameters`, `too-many-locals`, `method-too-long`, `deep-nesting`,
     `cyclomatic-complexity`, `too-many-exit-points`) and to the `TNamingConfig`
     knobs (the `naming` block fields). The registry is the one place that knows a
     rule is parameterized.
  2. The on-disk `.scm` sidecar `.json` files (read via the existing rules-dir loader)
     for the external rules: `source:"scm"`, category looked up from the registry's
     scm-category map (default `"other"` if unmapped), params none.
- **Categories:** reuse the `rules/README.md` groupings -- `bug-patterns`,
  `resource-lifetime`, `security`, `platform`, `complexity`, `structure`, `naming`,
  `dead-code`, `data-flow`, `firedac`, `project-wide`, `other`.
- **Counts:** the command also yields the totals the user wants to surface -- total
  rule count + per-category counts (a `--json` `summary` object; in text mode a header
  line `N rules across M categories`).

### 1b. "Lint Options" -- 4th dock tab (BPL)

The dock is `src/delphi-plugin/DragLint.Plugin.DockForm.pas` (`TDragLintDockFrame`),
which builds tabs in code via `AddTab(caption)` (currently `'Structure'`,
`'Search (no grep)'`, `'Find Usages'`; the Graph tab is a separate tool window). Add
`FTabLintOptions := AddTab('Lint Options');` hosting a new self-contained frame
**`TLintOptionsFrame`** (new unit `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas`).

The frame:
- (a) shells out to `drag-lint rules --json` (via the dock's existing `ResolveExe` +
  process-runner) to load the catalog;
- (b) renders rules **grouped by category** in collapsible sections; each rule a
  checkbox; each SECTION header a **tri-state** checkbox that selects/deselects the
  whole group (checked / unchecked / grayed-mixed);
- (c) inline editors for parameterized rules -- a spin-edit for int thresholds; text
  fields for naming prefixes / a combo for casing styles (driven by the rule's
  `params` from the catalog);
- (d) a header counts line: `N rules across M categories, K enabled`;
- (e) on change, READS + WRITES the active project's `drag-lint-lint.json` (the v0.66
  config: `disabled` / `enabled` lists, `severity` map, `thresholds`, and the v0.68
  `naming` block). A checkbox toggles membership of `disabled`; a severity combo writes
  `severity[id]`; a threshold spin writes `thresholds[id]`; a naming editor writes the
  `naming` block field. Round-trips through the same JSON shape the CLI reads, so the
  CLI remains the consumer of record.
- **Active project dir** is resolved via OTAPI (the plugin already does this elsewhere
  for indexing/forms -- mirror that helper; do NOT re-implement).

Keep `TLintOptionsFrame` free of OTAPI-only dependencies in its core (catalog load +
config read/write) so the standalone `drag-lint-config.exe` (`src/config/`, which has
`Indexes`/`Settings` tabs via `Config.MainForm.pas`) can host it as a 3rd tab later;
the OTAPI project-dir lookup is injected by the host.

**BPL constraint:** building the plugin requires RAD Studio **closed** plus a manual
in-IDE test cycle (load the BPL, open the dock, toggle rules, confirm the project's
`drag-lint-lint.json` changed). Called out in Testing as a manual gate.

---

## 2. Deliverable 2 -- Refactor CLI commands (packaging, NO IDE tab this release)

The rename ENGINE ALREADY EXISTS: `src/refactor/DRagLint.Refactor.Rename.pas` --
`TRenameEdit` (FilePath/Line/Col/OldName/NewName), `TRenameRefactoring.Build(AStore,
AQName, ANewName)` (index-driven cross-unit rename via `FindSymbolsByQualifiedName` +
`FindCallersByName`), `Apply(AEdits, AWriteBackups)` (back-to-front, writes `.bak`),
`RenderDryRun(AEdits)` (preview). Also existing: `resolve-uses` (which unit declares a
symbol), `query find-callers` (Find References), and
`DRagLint.Refactor.DeadCode.TDeadCodeFinder.Find(AStore, AKind, AIncludePrivate)`
(unused symbols). The current `rename --qname ... --to ...` command already wraps
`Build/Apply/RenderDryRun`. So this deliverable is **PACKAGING**, not engine-building.

Ship a unified command surface. Each subcommand: a `--json` edit-set output
(serialize `TArray<TRenameEdit>`), a **default dry-run text preview** (`RenderDryRun`),
and `--apply` to write files (backups ON by default; `--no-backup` to suppress).
All four reuse `TRenameEdit` / `Apply` / `RenderDryRun`, and on `--apply` MUST preserve
strict **ANSI / CRLF / no-BOM** (the repo encoding rule -- `Apply` already does this).

- **`drag-lint rename --kind symbol --name <QualifiedName> --to <New> [--json|--apply]`**
  -- cross-unit symbol rename; wraps the existing `Build/Apply/RenderDryRun` (a thin
  re-spelling of today's `rename --qname`). **Harden for:** overloads (rename all
  decls sharing the qname), qualified `Unit.Sym` references, DFM-published names, and
  **conflict detection** -- refuse to rename to a Pascal keyword or to a name already
  declared in the target scope. (Size S.)

- **`drag-lint rename --kind param --file <F> --line <L> --col <C> --to <New> [--json|--apply]`**
  -- rename a routine-LOCAL parameter or local var. A param is NOT an indexed symbol,
  so this needs a **NEW single-file edit-builder** in the refactor unit
  (`TRenameRefactoring.BuildLocal(const AFile: string; ALine, ACol: Integer; const
  ANewName: string): TArray<TRenameEdit>`) that: parses the file, finds the param/local
  decl at the given position, finds all references within the ROUTINE scope (the
  `defProc` body, plus the interface `declProc` header for a param), emits
  `TRenameEdit`s, then reuses `Apply` / `RenderDryRun`. **Guards/edge cases:** shadowing
  (inner decl of same name), `with` statements (a bare ident may be a member, not the
  local -- skip ambiguous), nested routines (don't cross into a nested `defProc` that
  re-declares the name), and **syncing the interface `declProc` header <-> impl
  `defProc` header** for a param. This is the natural **autofix for the v0.68
  `param-name-prefix` rule** (the user's #1 ask). (Size S-M.)

- **`drag-lint find-unit --name <Symbol> --in <file> [--json|--apply]`** -- package the
  existing `resolve-uses` result as an edit that adds the resolving unit to the file's
  `uses` clause (insert into the `interface` or `implementation` uses; pick by where the
  symbol is referenced). Default dry-run shows the inserted unit + line. (Size S.)

- **`drag-lint safe-delete --name <QualifiedName> [--json|--apply]`** -- verify ZERO
  references (reuse `TDeadCodeFinder` / `FindReferencesTo`), then emit edits removing
  the declaration (and, for a routine, its implementation body). **Refuse** (nonzero
  exit, no edits) if any reference exists. (Size S-M.)

**File touch-points:** new builder in `DRagLint.Refactor.Rename.pas`; `safe-delete`
edit-shaping helper alongside `DRagLint.Refactor.DeadCode.pas`; CLI dispatch +
arg-parse + help in `src/cli/DRagLint.CLI.pas` (mirror the existing `DoRename` /
`DoResolveUses` handlers).

---

## 3. Deliverable 3 -- close MISSING-FEATURES #1 (two naming rules)

Two new rules in `src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas` -- extend
`TNamingChecker.Check`, same 4-site CLI wiring as v0.68 (`--rule` allow-list, help
string, `DoLint` dispatch, `DoLintAll` dispatch), config via the `naming` block /
`TNamingConfig`. These are the only items left open under MISSING-FEATURES #1
(`MISSING-FEATURES.md:28`: "Reserved-word casing (lowercase keywords);
Hungarian/short-identifier flags -- deferred").

1. **`reserved-word-casing`** (`info`, **ON by default**) -- flag Pascal reserved
   words / keywords not written in all-lowercase (e.g. `Begin` / `BEGIN` instead of
   `begin`). Low-FP. Needs a built-in keyword list (the Delphi 13 reserved words +
   common directives); configurable preference via a new `naming` field
   `"keyword_case": "lowercase"` (default `lowercase`; `""` disables). Walk keyword
   tokens from the AST/lexer, not identifiers.

2. **`hungarian-or-short-identifier`** (`info`, **OFF by default** -- FP-prone, opt-in)
   -- flag BOTH (a) overly-short identifiers (single letters / `tmp`-style below a
   configurable min length, with loop-counter exemptions `i`/`j`/`k`/`n`/`x`/`y`) AND
   (b) Hungarian type-prefix names (`lpszName`, `intCount`, `strFoo` -- a configurable
   prefix list). Configurable via new `naming` fields:
   ```json
   "min_identifier_len": 3,
   "hungarian_prefixes": ["lpsz","psz","sz","lp","int","str","dw","b","p","n"],
   "short_identifier_check": false   // master on/off for this rule
   ```
   Document the FP risk in `rules/README.md` (legitimate short names, domain
   abbreviations); shipped OFF so it never regresses a quiet run.

Both close MISSING-FEATURES #1 entirely (mark the `[ ]` line `[x]`).

---

## 4. Config touch-points (summary)

- **D1:** no new config keys; reads/writes the existing v0.66 `drag-lint-lint.json`
  (`disabled`/`enabled`/`severity`/`thresholds`/`naming`). `drag-lint rules` reports
  `default_*` values (pre-config); the tab overlays the project config on top.
- **D2:** no config; CLI args only.
- **D3:** extends `TNamingConfig` / the `naming` block with `keyword_case`,
  `min_identifier_len`, `hungarian_prefixes`, `short_identifier_check` (parsed by
  `TLintConfig.Load`; absent -> defaults above).

---

## 5. Non-goals (v0.69) -- to be recorded in MISSING-FEATURES.md

- **IDE "Refactor" tab + OTAPI apply** (size M, next release): the in-editor
  refactoring experience -- a 5th dock tab with a Delphi-style Refactorings-Pane preview
  and applying edits to the editor BUFFERS via OTAPI (not files on disk). The v0.69
  refactor CLI commands are the deterministic foundation it will wrap.
- **HARD refactorings:** Change Parameters, Extract Method, Extract
  Interface/Superclass, Pull Members Up / Push Down, Move, Inline, Declare
  Variable/Field, Introduce Variable/Field -- all need type inference and/or call-site
  signature rewriting beyond the current index. Deferred.
- **D1 hosting in `drag-lint-config.exe`** -- the frame is built host-agnostic, but
  wiring it into the config exe's tab set ships later.
- Background research: `.superpowers/sdd/delphi-refactor-research.md` and
  `docs/lint/Comprehensive report on the refactor.md`. **Canonical refactoring mechanics
  (for D2 + the deferred set): Martin Fowler's catalog -- https://refactoring.com/catalog/
  (user-flagged 2026-06-30; consult per-refactoring when building the rename/safe-delete/find-unit
  edits and when designing the deferred Extract Method / Change Params / etc).**

---

## 6. Testing

- **D3 (naming) -- `tests/lint`:** TDD fixture per rule (positive fires + guarded
  negative does not). `reserved-word-casing`: a unit with `Begin`/`BEGIN` fires;
  all-lowercase keywords do not; `keyword_case:""` disables. `hungarian-or-short-identifier`:
  OFF by default fixture (asserts NO finding without `short_identifier_check:true`);
  ON fixture fires on `lpszName` / `i2` and exempts `i`/`j` loop vars. Existing harness
  stays green (new ids => existing `.expected` unaffected unless a fixture newly fires;
  add `!<rule>` guards where needed).
- **D2 (refactor) -- NEW `tests/refactor` DB-fixture harness:** mirror the
  `tests/lint-project` pattern -- index a small fixture project into a temp `.sqlite`,
  run the command, assert the **dry-run edit set** (text), and for `--apply` assert the
  **resulting file content** (incl. ANSI/CRLF preserved). Cases: `rename --kind symbol`
  cross-unit + keyword-conflict refusal; `rename --kind param` with shadowing /
  interface-header sync; `find-unit` insert; `safe-delete` success + refuse-on-reference.
- **D1 (catalog + tab):**
  - **`drag-lint rules --json`** -- a CLI test asserting the catalog contains a known
    built-in (`too-many-parameters` with its `threshold` param), a known `.scm` rule
    (`goto-statement`, `source:"scm"`), correct category bucketing, and a non-zero
    summary count. Runnable headless (no IDE).
  - **BPL manual-test gate** (no automated UI test): build the plugin with RAD Studio
    closed (delphi-build skill), load it, open the dock's "Lint Options" tab, toggle a
    rule + a threshold + a naming prefix, confirm the project `drag-lint-lint.json`
    round-trips. Documented as a manual checklist in the plan.

---

## 7. Definition of done

- **D3:** both rules live (`reserved-word-casing` ON, `hungarian-or-short-identifier`
  OFF by default), config fields parsed, each with a passing TDD fixture (positive +
  guarded negative); harness green; MISSING-FEATURES #1 line marked `[x]`;
  `rules/README.md` + CHANGELOG updated.
- **D1:** `drag-lint rules` (text + `--json`) emits the full catalog (every built-in +
  every `.scm`) with category/params/counts and a passing CLI test; the dock has a
  working "Lint Options" tab that loads the catalog, groups by category with tri-state
  section toggles + inline param editors + a counts header, and round-trips the active
  project's `drag-lint-lint.json` (manual BPL gate passed); `rules/README.md` notes the
  catalog command as the canonical rule source.
- **D2:** all four subcommands (`rename --kind symbol|param`, `find-unit`,
  `safe-delete`) ship with dry-run default, `--json` edit set, and `--apply` (backups
  on, ANSI/CRLF preserved); `tests/refactor` harness green; conflict/refuse guards
  proven; `param` rename documented as the `param-name-prefix` autofix.
- VERSION = `0.69.0-alpha`; CHANGELOG + MISSING-FEATURES updated; real-code sanity on
  ORM3 (rules catalog counts sane; a rename/safe-delete dry-run on a real symbol is
  correct). Publish **v0.69.0-alpha**.
