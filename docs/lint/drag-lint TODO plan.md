# drag-lint TODO plan -- the "Action" roadmap

> **What this is.** The long-term plan for turning drag-lint from a tool that
> *analyses* Delphi into one that *acts on* it. Four tracks, sequenced by
> maturity and risk. All of them share one substrate (the apply engine + a
> Settings surface + a Diagnostic-tree right-click + batch application), so the
> order below front-loads the tracks that reuse the most of what already exists.
>
> **Original ideas preserved.** Nothing from the earlier flat wishlist was
> dropped -- every item is carried below, just organised and grounded against
> what the codebase already has. Where a track overlaps an existing roadmap
> (Refactoring), this doc links out instead of duplicating.
>
> **Cross-links:** the refactoring track lives in
> [REFACTOR-LIST.md](REFACTOR-LIST.md) (difficulty-rated, with a recommended
> order). Feature/infra backlog: [BACKLOG.md](BACKLOG.md). Detection coverage:
> [MISSING-FEATURES.md](MISSING-FEATURES.md).

## Shared substrate (build once, all four tracks reuse it)

Every track below applies text edits to source and is driven the same way. The
pieces that already exist:

- **Apply engine:** `src/refactor/DRagLint.Refactor.TextEdit.pas` --
  `TTextEdit` + `TTextEditApplier` (back-to-front multi-location apply,
  ANSI/CRLF-preserving, `.bak`, dry-run render). Every apply-style feature
  builds on this.
- **CLI convention:** a verb with `--dry-run` / `--apply` / `--json` /
  `--no-backup` (dry-run default). Established by `rename`, `uses-fix`,
  `extract-method`, and the `lint --fix` seed.
- **IDE wiring pattern:** a keyboard/menu action that reads the editor
  selection, previews the change, applies, and reloads the buffer. Established
  by Extract Method's `Ctrl+Alt+M`.
- **Not yet built, needed by 3 of the 4 tracks:** a **Settings surface** (which
  fixes/rules to offer vs ignore) and a **Diagnostic-tree right-click "Fix it"**
  and **batch (unit / project) apply** UX. Build this ONCE and Tracks 1-3 share
  it. (The Settings surface also serves the pending naming-settings page --
  BACKLOG / `feature_naming_settings_presets`.)

## Sequence (recommended)

1. **Track 1 -- AutoFix** (closest to done, lowest risk; the apply engine + a
   3-rule seed already exist). Ship this first.
2. **Track 2 -- AutoDocument** (most differentiated; the index already holds the
   data). Second.
3. **Track 3 -- Convert Components** (highest value, highest risk; needs a
   recursive deep-property matcher + a machine-readable rules table -- its own
   milestone). Third.
4. **Track 4 -- Refactoring** runs in parallel as its own tracked frontier; see
   [REFACTOR-LIST.md](REFACTOR-LIST.md). Not re-planned here.

---

## Track 1. AutoFix

**Offer to fix the problems lint finds, per the user's settings, from the IDE.**

### Already built (the starting point)
- `lint --fix` applies quick-fixes for findings that have a registered autofix;
  dry-run unless `--apply` (`DRagLint.CLI.pas` -- `Fix`/`Apply` flags,
  `BuildAutofixEdits`). Riding on `TTextEditApplier`.
- **Seed autofix set (v0.71, mechanical / no type info):** `self-assignment`
  (delete the statement), `redundant-parentheses` (strip the outer parens),
  `redundant-cast` (strip the cast). Deliberately conservative -- only exact,
  side-effect-free text edits are wired.
- Routine-local `rename --kind param` is effectively a param/var autofix already.

So the *engine* and the *safe-fix criterion* are answered for a handful of
rules. The remaining work is **breadth of fixable rules** + **the UX/settings/
batch layer** -- which is exactly items 2-5 below.

### 1.1 Offer to fix problems that lint found. *(original item 1)*
Expand the fixable-rule set beyond the 3-rule seed. Candidates are rules whose
fix is an exact, side-effect-free text edit (no type inference, no data-flow):
e.g. `redundant-begin-end`, unnecessary-`with` removal (careful), missing/extra
semicolons, obvious dead assignments, formatting-class findings. Each new
fixable rule = a branch in `BuildAutofixEdits` + a fixture proving RED->GREEN.
Rules whose fix needs a decision or type info are **not** auto-applied -- they
belong to the Settings gate (1.2) as "offer, don't auto-apply."

**Naming-convention autofix via global rename** *(user request 2026-07-08)*: make
the naming-convention findings fixable by driving the existing global-rename
engine (`TRenameRefactoring.Build/Apply`, `src/refactor/DRagLint.Refactor.Rename.pas`).
Do it in two phases by safety: **(phase 1, safest)** a **case-only** fix --
`fclient -> FClient`, i.e. the identifier already matches the convention except
capitalization; a pure re-casing rename is near-mechanical and collision-free
(same symbol in a case-insensitive language), so it can be a registered fixable
rule that lights up "Fix it". **(phase 2)** prefix-ADDING (`client -> FClient`,
param `x -> pX`) -- changes the identifier, so it needs the store-backed collision
check the rename engine already does; params are routine-local (use `BuildLocal`,
safe scope) and must sync the interface/impl headers. See the auto-rename-params
+ naming-settings notes in auto-memory for the fuller design.

### 1.2 Settings page: which AutoFix to offer, which to ignore. *(original item 2)*
The Settings surface (shared substrate). Per-rule tri-state: **auto-apply /
offer-on-request / never**. This is the same Settings surface the naming-settings
page needs -- build one, not two. Persist per-project (and a global default).

### 1.3 Diagnostic-tree right-click "Fix it". *(original item 3)*
On the IDE Diagnostic tree, right-click a finding that has a fix -> **Fix it** ->
selection + click applies that one fix. IDE plumbing on top of the CLI; the
Extract Method preview/apply/reload wiring is the template. Only show "Fix it"
where a fix is registered (per 1.1) and permitted (per 1.2).

### 1.4 AutoFix per unit (follows Settings). *(original item 4)*
A right-click on the tree (or a per-unit menu) that applies every settings-
permitted fix for the whole unit in one pass. Batch application of the same
`TTextEdit` set; reconcile same-line multi-fixes (the applier orders by line --
overlapping column edits need care, already noted in `BuildAutofixEdits`'
remarks).

### 1.5 Same AutoFix for the whole project. *(original item 5)*
Project-wide batch: enumerate the `.dproj` units, run lint + apply permitted
fixes across all of them, aggregate a report. Relates to the `lint-all`
project-runner backlog item (BACKLOG sec 7).

---

## Track 2. AutoDocument

**Generate/extend DocInsight doc-comments from what the indexer already knows.**
This is the most *differentiated* track -- nobody else can auto-write DocInsight
from a symbol index.

### Already built (the starting point)
- `generate-docs --qname <Foo.TBar.Baz> [--format xmldoc|pasdoc]` already emits
  a doc stub (`DoGenerateDocs`, v0.25).
- The index already answers **"called from"** (`find-callers`), **"calls" /
  impact** (`impact`, `context`), and **uses** (`uses-report`) -- the raw
  material for the sections below.

### 2.1 Create or extend a doc-comment from index data. *(original item 1)*
Follow the DocInsight (`///` XML) format. Populate what the index knows *for
sure*, and be careful never to fabricate prose you can't justify (a wrong
`<summary>` is worse than none):
- `<summary>` -- stub (or leave a TODO marker rather than guess).
- `<param name="">` -- one per parameter (names are known exactly).
- `<returns>` -- for functions where the return value is derivable (return type;
  a single `Result :=` const; etc.).
- `<remarks>` -- a **"Called from"** section (N sites, or the callers) and a
  **"Calls"** section, both straight from the index -- *this is the original
  idea, and it's feasible today.*
- **Suggestion (open):** mine **Spring4D**'s DocInsight usage to see which other
  tags they include widely, and auto-emit the ones we can ground in index data.
- Merge semantics: if a comment already exists, *extend* the auto-derivable
  sections without clobbering hand-written prose.

### 2.2 AutoDocument the whole unit. *(original item 2)*
Apply 2.1 across every public declaration in a unit (settings/scope-gated like
Track 1's per-unit apply). Public surface only, per the project's CDD rule.

### 2.3 AutoDocument the whole project + investigate Delphi's doc-collection. *(original item 3)*
- Project-wide batch (like 1.5).
- **Investigate (open question the user raised):** does Delphi collect
  documentation into a specified folder during compilation, what is it supposed
  to collect, and why did it never give meaningful results? This is the
  RAD Studio **DocInsight/XML-doc output** option (`--doc`-style per-project
  emission). Confirm what it emits, then decide "we do better than the built-in"
  vs "we feed/augment it." Short spike, not a milestone.

---

## Track 3. Convert Components

**Convert a component from one type to another, recursively and in batches --
deeper than GExperts can.** Highest value, highest risk, least built. Likely its
own milestone (Very Hard on the REFACTOR-LIST scale).

### Already have (partial)
- [`Type_Conversion.md`](../../../Type_Conversion.md) -- the human catalogue of
  Orpheus `TOvc*` -> DevExpress `cx`/`dx` conversions (exact steps, DFM block
  templates, unit changes, property/event mappings). This is the raw material
  for a machine-readable rules table.
- The `mc-form-converter` skill (BDE `TTable` -> FireDAC `TFDMemTable`
  delta-streaming) -- a worked conversion path.

### 3.1 Convert components from one type to another. *(original item 1)*
E.g. `TTable` -> `TFDMemTable` / `TFDTable` / `TFDQuery`, or `TDBEdit` ->
`TcxDBEdit`. Rewrites the DFM component declaration + its properties + the `.pas`
field type + `uses`.

### 3.2 Define what a "batch conversion" is. *(original item 2)*
Design a **machine-readable conversion-rules format** -- the same shape as
`Type_Conversion.md`, made executable. A rule specifies: source type -> target
type; property map (including *nested* properties, see 3.3); event map; units to
**add**; units to **remove** (and the check that they're safe to remove). This
format is the deliverable of 3.2 and the input to 3.1.

### 3.3 Recursive deep-property matching (the novel part, beyond GExperts). *(original item 3)*
GExperts has a 1-level type-conversion, **very useful** for simple pairs but it
can't see deep matches: for `TDBEdit` vs `TcxDBEdit`, most matching properties
live **deeper than one level** (`Properties.SomeSub.X`), so GExperts misses and
doesn't convert them. drag-lint's version must:
- **recursively** find matching properties across the property trees of both
  types;
- build the conversion **rules-tables** per specific type->type pair (3.2) so
  conversions run in batches;
- **add** the `uses` units the target type needs, and **check whether old units
  can be removed** entirely;
- record the units added/removed **in the conversion rules** themselves.

Needs: DFM parsing (have the `tree-sitter-dfm` grammar), a property-tree matcher
(new), and the `uses` add/remove logic (Find-Unit + `uses-fix` already do parts).

---

## Track 4. Refactoring

**Continue with the refactoring apply-frontier.** *(original item 4)*

This track is already fully tracked in
[REFACTOR-LIST.md](REFACTOR-LIST.md) -- a difficulty-rated roadmap with a
recommended order (next up: **Change Signature**, then Introduce/Inline Variable,
Split Variable apply, Encapsulate Field, Extract Interface). It is not
re-planned here; this bullet exists so the theme isn't lost. All refactorings use
the same shared substrate (apply engine + CLI verb + IDE action) as Tracks 1-3.

---

## Track 5. Analysis & Reporting  *(added 2026-07-08, user request)*

**First-class analysis reports that package existing engine primitives into the
kind of navigable output Peganza PAL / SciTools Understand / FixInsight ship.**
These are *reporting/visualization* deliverables, NOT new analysis engines --
the traversals already exist; the work is turning them into consumable reports
(and, where useful, richer charts). Prompted by the indexer-landscape review
(`docs/lint/REPORT-3-REVIEW-INDEXERS.txt`): the competitor survey there is a
useful feature-gap checklist, orthogonal to the parser choice.

### Already built (the substrate these reuse)
- **Caller/callee traversal:** `callgraph --direction callers|callees --depth N`
  (N-deep resolved call tree, cycle-guarded) + `find-callers --resolved` +
  `impact` (transitive). The reverse-call-tree *traversal* is done.
- **Uses graph:** `uses-report --include-external --depth N` (CSV) + the resolved
  uses-graph + `circular-uses` (Tarjan SCC, v0.76). The dependency *data* is done.
- **Graph emit + viewer:** `graph --format dot|mermaid [--name <root>]` +
  the `drag_lint_graph` viewer. Basic chart emission is done.

### 5.1 Reverse call-tree report
A first-class report (not just the raw `callgraph` dump): "who calls X, and who
calls them" as a navigable N-deep **reverse** tree, per-symbol, with call sites
(unit:line) and cycle markers. Reuses `callgraph --direction callers`; adds a
report format (text tree + `--format mermaid|dot` chart + `--json`) and, in the
IDE, a right-click "Reverse call tree" on a symbol that renders it in the dock
(the `drag_lint_graph` viewer is the render target). Compare: PAL's reverse call
trees, Understand's call butterfly charts.

### 5.2 Third-party dependency report
A dependency report that **isolates external / third-party / library units**
(RTL, DevExpress, Spring4D, Jedi, TMS, ...) from project units, and shows, per
external dependency: which project units pull it in, the shortest uses-path to
it, and a rollup ("project depends on N external libraries; here is the surface
touched"). Reuses `uses-report --include-external` + the resolved uses-graph +
the library-path resolution now surfaced on the Indexer Options page. Output:
CSV/JSON + a grouped text report; optionally a chart. Compare: PAL's third-party
dependency lists, Understand's dependency reports.

### 5.3 Architectural charts
Higher-level charts than the current raw uses-graph: **layering diagrams**
(group units into layers/packages and show cross-layer edges + violations --
builds on the `circular-uses` / layering analysis that already "leads the field"
per MISSING-FEATURES sec 11), **butterfly / call-tree charts** (a symbol with its
callers on one side and callees on the other), and **module/architecture
overviews** (package-level dependency maps). Reuses the `graph` emitter + the
`drag_lint_graph` viewer; the new work is the *aggregation* (unit -> layer/
package grouping, edge rollup) and the chart layouts. Compare: SciTools
Understand's architectural / butterfly charts, PAL's structure reports.

> **Scoping note:** all three are report/output layers over shipped traversals,
> so each is a bounded feature (a CLI report verb + format + optional IDE
> dock/chart), not a milestone-sized engine build. Sequence within the track by
> value: 5.2 (dependency report -- cleanest, pure data rollup) is likely the
> easiest first; 5.1 (reverse call tree) reuses `callgraph` almost directly; 5.3
> (architectural charts) is the largest (needs the layer/package aggregation +
> chart layout work). Each should get its own brainstorm -> spec -> plan when
> picked up.

---

## First chunk chosen

Track 1 (AutoFix) goes first. The very first slice is scoped in a separate spec +
plan (see the SDD spec/plan under `docs/superpowers/`). Rationale: the apply
engine and a safe 3-rule seed already exist, so the first slice delivers visible
value (more fixes + the "Fix it" UX) at the lowest risk, and it builds the shared
Settings/tree/batch substrate that Tracks 2-3 then inherit.
