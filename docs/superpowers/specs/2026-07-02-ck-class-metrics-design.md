# Design: v0.78 CK class-metrics suite (NOC / DIT / CBO / RFC / LCOM4)

> Authored 2026-07-02 (resume after v0.77.0-alpha). Store-backed class metrics,
> shipped as one bundle. Read `docs/lint/BACKLOG.md` (RESUME 2026-07-02) and
> `docs/lint/PLAN-v076-close-sections.md` Phase 3 for context. This spec is the
> input to the writing-plans step.

## Goal

Add the five Chidamber & Kemerer object-oriented class metrics that drag-lint does
not yet emit -- **DIT, NOC, CBO, RFC, LCOM** -- as store-backed lint rules over the
whole indexed project. Each is a separate rule with its own configurable threshold.
They complement the existing coarse `god-class` (methods>20 AND fields>15) with
finer-grained, individually-tunable structural signals.

WMC (weighted methods per class) is **intentionally excluded** -- it is already
covered per-method by `cyclomatic-complexity` and `cognitive-complexity`.

## Scope

**In scope**
- 5 new lint rules (one per metric), computed project-wide from the symbol store.
- LCOM shipped as **LCOM4** (connected components of the method graph).
- All 5 ship **ON by default**, with thresholds calibrated so a clean `src/` run
  yields ~0 findings.
- Tested via the `tests/lint-store/` harness (mode `lint-all`).

**Out of scope**
- The per-file LSP / IDE diagnostics path. Like `circular-uses` and `god-class`,
  these metrics need the whole index and run only in the CLI `lint-all` / project
  path -- **not** in `TLspCompletion.BuildDiagnostics`. (Future extension: surface
  them in the IDE by running the project pass against the LSP store.)
- Autofix -- metrics are advisory; there is nothing to rewrite.
- WMC (see above).
- Recategorizing the existing `god-class` rule (stays in `project-wide`).

## Background: what the store gives us (and its limits)

Verified against `src/core/DRagLint.Core.Interfaces.pas`,
`src/parser/DRagLint.Parser.Delphi13.pas`, and `src/lint/DRagLint.Lint.ProjectRules.pas`:

- **Class members** -- `FindAllChildSymbols(classId)` returns the class's methods
  (`skMethod`/`skFunction`/`skProcedure`/`skConstructor`/`skDestructor`), `skField`,
  `skProperty`, etc. Each method symbol carries `ImplStartLine`/`ImplEndLine`
  (its body span; 0 when it has no body -- abstract/interface/forward).
- **Heritage** -- each class/interface `TSymbol.Heritage` holds the raw ancestor
  text (e.g. `'TBar, IBaz'`). The store also resolves ancestry into edges
  (`ResolveAncestry` -> `GetTransitiveAncestors`), and `ResolveTypeCategory(name, fileId)`
  resolves a type name in-scope to a category (`tcClass`, `tcInterface`, ...).
- **References** -- `GetReferencesFromFile(fileId)` returns every reference emitted
  in a file, each with `Kind`, `NameText`, and `StartLine`. Reference kinds the
  parser emits: `call` (invocations, incl. paren-less), `type_use` (type mentions),
  and -- only when `EmitUsageRefs` is on (it is, for non-library indexing) --
  `read`/`write` (base identifier of `obj.member`, assignment LHS, call args).
  **Reference `symbol_id` is NULL** (unresolved at parse time): references are
  name-based; resolve `NameText` via `FindSymbolsByExactName` / `ResolveTypeCategory`,
  the pattern `unused-unit-in-uses` already uses.
- **AST on demand** -- `TAstParseCache.Get(path)` returns the parsed tree for a
  file (cached), as used by `BuildPropertyAccessorSet` in ProjectRules.

Two limits drive design decisions below:

1. **`read`/`write` refs are partial** -- they miss plain field reads in
   conditions/RHS expressions. A field-access set built from stored refs would
   systematically undercount access and overstate LCOM. => LCOM computes
   field-access from a **direct AST re-walk** of each method body (complete),
   via the parse cache.
2. **RTL ancestors are not indexed** in a project-only store (`TObject`,
   `TComponent`, `TForm`, ...). => DIT sees only project-internal depth plus one
   external hop; it undercounts. Documented; improves when the RTL library DB is
   also passed via `--db`.

## Architecture

New unit **`src/lint/DRagLint.Lint.ClassMetrics.pas`** exposing:

```pascal
type
  TClassMetrics = class
  public
    /// <summary>Computes the 5 CK class metrics over AStore and returns findings
    /// for classes exceeding each rule's threshold. nil store -> no findings.
    /// Never raises.</summary>
    class function Run(const AStore: ISymbolStore; const ACfg: TLintConfig;
      const ARuleId: string = ''): TArray<TLintFinding>;
  end;
```

Invoked from `DoLintAll` in `src/cli/DRagLint.CLI.pas` immediately after the
existing `TProjectLintRules.Run(Store, '')` call (~line 5836), and from the
`lint-project` path if present. Findings flow through the same
`Cfg.ShouldKeep` / `Cfg.ApplySeverity` finalize filter as every other finding.
(`ARuleId` mirrors ProjectRules' single-rule filter for `--rule`.)

**Two-phase computation** (one shared per-class gather feeds all 5 metrics -- the
class is never scanned five times):

- **Phase 1 -- inventory.** Iterate `GetAllFileIds`; for each `skClass` symbol
  build a `TClassInfo`:
  - `Id, Name, FileId, Path, DeclLine, DeclCol`
  - `Methods: TArray<TSymbol>` (body-bearing + declared), `Fields: TArray<TSymbol>`
  - `Heritage` (raw text)
  - resolved `DirectParentId: Int64` (0 = none/external) and
    `HasExternalParent: Boolean`
  Keep a `TDictionary<Int64, TClassInfo>` keyed by class Id and a
  `name -> TList<Int64>` map for resolution.

- **Phase 2 -- finalize & emit.** Compute each metric per class from the inventory
  (plus `GetReferencesFromFile` for CBO/RFC and the parse cache for LCOM), compare
  to the rule's threshold, and emit one finding per class per exceeded threshold,
  anchored at `DeclLine`/`DeclCol`.

Internal helpers (kept private, each single-purpose and testable in isolation):
`BuildInventory`, `ResolveDirectParent`, `ComputeNOC`, `ComputeDIT`,
`ComputeCBO`, `ComputeRFC`, `ComputeLCOM4`.

## Metric definitions (exact algorithms)

Let `C` be a class in the inventory. `field-names(C)` = lowercased `skField` child
names. `methods(C)` = child symbols of method kinds. `body-methods(C)` = those with
`ImplStartLine > 0`. A reference `r` is *in* method `m` when `r.StartLine` is within
`[m.ImplStartLine, m.ImplEndLine]`; refs come from `GetReferencesFromFile(C.FileId)`.

**Direct parent** (shared by NOC + DIT): the first name in `C.Heritage` for which
`ResolveTypeCategory(name, C.FileId) = tcClass`. If that name maps to a class in the
inventory -> `DirectParentId` (internal edge). If it resolves to `tcClass` but is
not in the inventory -> `HasExternalParent := True` (RTL/third-party parent).
Interfaces in the heritage list are skipped for parent purposes.

**DIT (`deep-inheritance`)** -- depth of the inheritance chain.
Walk `DirectParentId` upward from `C`, counting hops; a visited-set guards cycles
and a hard cap (32) bounds runaway. When the chain reaches a class with
`HasExternalParent`, add 1 final hop and stop. `DIT(C)` = hop count.
Fires when `DIT(C) > threshold` (default 6). *Undercounts without RTL DB.*

**NOC (`too-many-children`)** -- number of **direct** subclasses.
`NOC(C)` = count of inventory classes whose `DirectParentId = C.Id`. Direct only
(not transitive). Fires when `NOC(C) > threshold` (default 10).

**CBO (`high-coupling`)** -- efferent coupling to other classes.
Collect every `type_use` reference within `C`'s declaration span and its
method-body spans; resolve each `NameText` via `ResolveTypeCategory(name, C.FileId)`.
`CBO(C)` = count of distinct names resolving to `tcClass`, excluding `C` itself and
`C`'s ancestors. (Type-use is the reliable coupling signal: using another class's
object requires naming its type somewhere in a field/var/param.) Fires when
`CBO(C) > threshold` (default 20).

**RFC (`high-response`)** -- response set size.
`RFC(C)` = `|methods(C)|` + `|distinct call NameText (case-insensitive) within C's
method-body spans|`. Fires when `RFC(C) > threshold` (default 50).

**LCOM4 (`low-cohesion`)** -- connected components of the method graph.
Nodes = `body-methods(C)`. For each body-method, re-walk its body subtree from
`TAstParseCache.Get(C.Path)` (locate the tree node whose span matches the method's
impl range) and collect (a) identifier leaves whose lowercased text is in
`field-names(C)` -> the method's accessed-field set, and (b) call names in
`method-names(C)` -> intra-class call edges. Add an undirected edge between two
methods when they share >=1 accessed field OR one calls the other. `LCOM4(C)` =
number of connected components (union-find; an isolated method is its own
component). Classes with <=1 body-method have `LCOM4 <= 1` and never fire.
Fires when `LCOM4(C) > threshold` (default 3).

## Rules, category, severity, defaults

| Rule id | Metric | Severity | Default | Default threshold |
|---|---|---|---|---|
| `deep-inheritance` | DIT | info | ON | 6 |
| `too-many-children` | NOC | info | ON | 10 |
| `high-coupling` | CBO | info | ON | 20 |
| `high-response` | RFC | info | ON | 50 |
| `low-cohesion` | LCOM4 | info | ON | 3 |

- New catalog **category `metrics`** (catalog counts are relative / self-checked,
  so no count-constant bump is needed).
- Each rule registered with `B(id, 'metrics', 'info', title, True,
  [MkParam('threshold','int','<n>')])` in `src/lint/DRagLint.Lint.RuleCatalog.pas`
  (near the `project-wide` block, ~line 190).
- Thresholds read via `ACfg.ThresholdFor('<id>', <default>)` inside
  `TClassMetrics.Run`.
- Messages cite metric, value, and threshold, e.g.
  `Low cohesion: TFoo has LCOM4=5 (>3) -- the class may combine unrelated
  responsibilities; consider splitting.`

**Threshold defaults above are provisional.** During implementation, run each rule
over `src/` and tune so clean code produces ~0 findings (the calibration the
project applied to `cognitive-complexity`, which shipped ON at 25). Record the
final numbers in the CHANGELOG and BACKLOG.

## Wiring checklist

1. New unit `src/lint/DRagLint.Lint.ClassMetrics.pas` (+ add to the CLI `.dproj`
   and any package that compiles the lint layer).
2. Call `TClassMetrics.Run(Store, Cfg, '')` in `DoLintAll` (~CLI:5836) beside
   `TProjectLintRules.Run`; append its findings to the same list so
   `ShouldKeep`/`ApplySeverity` filtering applies.
3. Optionally support `--rule <id>` in the `lint-project` path (pass `AArgs.Rule`).
4. 5 `B()` entries in `RuleCatalog.pas`.
5. CHANGELOG "Unreleased" section; mark the #6 CK items in
   `docs/lint/MISSING-FEATURES.md`.

## Testing

`tests/lint-store/` cases, `case.json` mode `lint-all`, tiny multi-unit fixtures.
Each case sets a **low** `config.json` threshold so small engineered classes trip
the rule, and includes a negative assertion. One case per metric:

- `deep-inheritance/` -- a 4-deep class chain across 2 units; threshold 2 ->
  fires on the deepest; `!deep-inheritance` on a shallow class.
- `too-many-children/` -- one base with 3 direct subclasses; threshold 2 -> fires
  on the base; `!too-many-children` on a leaf.
- `high-coupling/` -- a class whose methods use N other classes' types; threshold
  low -> fires; a decoupled class does not.
- `high-response/` -- a class with several methods each calling several distinct
  routines; threshold low -> fires.
- `low-cohesion/` -- a class with two field-disjoint, non-calling method clusters
  (LCOM4=2); threshold 1 -> fires; a cohesive class (shared field) does not.

`expected.txt` asserts `<rule> <file>:<line>` at the class decl and `!<rule>` for
the negative. Then a FP-sanity pass over `src/` per rule before locking thresholds.
All three harnesses green: `run_lint_tests.ps1`, `run_store_tests.ps1`,
`run_rulecatalog_tests.ps1`.

## Known limitations (document in CHANGELOG)

- **DIT undercounts** without the RTL/library index (external parents count as one
  hop). Passing the library DB via `--db` improves it.
- **Name-based resolution** (refs and heritage) can mis-resolve on same-named types
  in different units; acceptable for advisory `info` metrics.
- **CBO is efferent only** (classes this class uses), type-use based; afferent
  coupling and call-target-class resolution are out of scope.
- **LCOM4 excludes body-less methods** (abstract/interface/forward have no body to
  analyze); constructors/destructors are included (may inflate cohesion) -- a
  calibration knob, not a correctness issue.

## Release

Bundle all 5 rules as **v0.78.0-alpha** per the standard recipe in
`PLAN-v076-close-sections.md` (build Win64, all harnesses green, FP-sanity, bump
`VERSION` at `CLI.pas:6`, CHANGELOG, `pack-lint-release.ps1`, tag, GitHub
prerelease win32+win64, update BACKLOG + memory + wiki). The M2-flow items
(nullability #4, double-free #5) remain the next milestone after this.

## Decisions resolved (this brainstorm)

- LCOM variant: **LCOM4** (connected components) -- most actionable, lowest noise.
- Enablement: **ON by default** with thresholds calibrated against `src/`.
- Home: **new unit** `DRagLint.Lint.ClassMetrics` (not an extension of the already
  large `TProjectLintRules.Run`).
- Surface: **CLI `lint-all` / project path only**, not the per-file LSP/IDE path.
