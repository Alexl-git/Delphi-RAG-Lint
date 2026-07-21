# Design: Whole-Project Auto-Document — Phase 1 (IDE menu + richer facts)

- Date: 2026-07-21
- Status: Approved (design confirmed; ready for implementation plan)
- Repo: `C:\Projects\Delphi-RAG-lint` (main)
- Phase 2 (deferred, separate spec): the *analysis* fact group (reads/writes fields, returned-object
  ownership, complexity, DFM wiring, SQL touched, covered-by-tests) via an index-time facts layer
  consumed by BOTH autodoc and the hover popup. Not in this spec.

## Motivation

drag-lint already has a deterministic (no-AI) documentation engine: the `document` verb writes managed
DocInsight `///` comments into source. `document --project <X.dproj> --apply` documents every public
declaration in the project's compile closure. Two gaps the user hit:

1. **Not in the IDE menu** — the whole-project mode is CLI-only; the menu exposes only single-symbol
   "Doc Comment Stub" and a "Find Undocumented" report.
2. **The auto-facts could be richer and less noisy** — `<returns>` shows `TODO` (the real return-case
   miner is built but gated off), and a whole-project run documents trivial 1-2 line property accessors,
   adding clutter.

This spec closes both, plus adds a group of cheap, index-derived facts to the managed block.

## Scope (Phase 1)

In: (1) an IDE menu item for whole-project autodoc; (2) enable real `<returns>` cases + tune the caller
cap (config only); (3) skip trivial property accessors in batch modes; (4) a "cheap fact group" of
index-lookup facts in the managed block; (5) tests; (6) the operational YADF/YADFOT rollout.

Out (Phase 2): any fact needing dataflow/CFG/escape analysis, and the hover-popup enrichment.

## Component 1 — IDE menu item

- **Placement:** `drag-lint → Generate && Export → "Auto-Document Whole Project…"`, added in
  `src/delphi-plugin/DragLint.Plugin.Editor.pas` (the `SubGen` submenu, next to `InvokeGenerateDocs`),
  via the existing `AddWrappedItem(SubGen, ...)` pattern with a new `InvokeAutoDocumentProject` handler.
- **Action:** resolve the active project's `.dproj` (the same active-project resolution other plugin
  actions use), then spawn the deployed engine exe:
  `drag-lint document --project <active.dproj> --apply` (facts-only; NOT `--stubs`).
- **Apply flow (user decision):** **apply directly, with backup.** No preview/confirm dialog. `--apply`
  writes DocInsight into every eligible public decl and keeps a `.bak` per modified file (the default;
  do NOT pass `--no-backup`). Safety net = the managed `drag-lint:auto` regions regenerate without
  disturbing hand-written prose + the `.bak` files + the user's git branch.
- **Reporting:** stream the engine's per-file result to the plugin Messages/Output (edit count, files
  changed, trivial accessors skipped) like other spawn-based plugin actions; surface a one-line summary.
- **Scope of "project":** the ACTIVE project only. Multi-project groups are out of scope.

## Component 2 — real returns + caller cap (config only, no new engine code)

The return-case miner is already built: `TDocFacts.ReturnCases` is populated by the same
`MineReturnExpressions` miner the hover popup uses, capped by `Opts.MaxReturnCases` which is loaded from
the manifest via `LoadDocMaxReturnCases` (`docs.max_return_cases`, default 20 only on a load *failure*;
a successful load with no `docs` section yields 0 → disabled → bare `TODO`). Today the manifest
(`third_party/dll-win64/drag-lint.json`) has no `docs` section, so returns are off.

- Add a `docs` section to the manifest with:
  - `max_return_cases`: **6** (turns on real `Result := …` cases in `<returns>`).
  - `max_callers`: **5** (tightens the "Called from" list to the user's "first 5 then (+N more)").
- Confirm whether a `max_callers` loader already exists (mirroring `LoadDocMaxReturnCases` /
  `DocManifest.Docs`); if not, add it the same way and thread it into `DoDocumentUnit/Project/All` +
  the facts builder's caller cap. If the caller cap is currently a hard-coded constant, replace that
  constant read with the config value (default 5).
- No behavior beyond config + the (possibly new) `max_callers` plumbing. Verify with a real symbol that
  `<returns>` shows mined cases and "Called from" shows ≤5 + "(+N more)".

## Component 3 — skip trivial property accessors (batch modes only)

- **Definition of a trivial accessor:** a method that is a property accessor — i.e. its name appears in
  some property's `read` or `write` clause (precise; use the accessor data now available from the R1
  extraction work, or resolve via the property rows) — AND whose implementation body length
  (`impl_end_line - impl_start_line`) is `<=` the threshold. Heuristic `Get*/Set*` name-matching is a
  fallback ONLY if precise accessor linkage is unavailable for a given symbol.
- **Threshold:** configurable `docs.accessor_trivial_max_lines`, **default 2**. Body `> threshold` →
  non-trivial → documented normally.
- **Where:** applies to the BATCH modes only — `document --unit`, `document --project`,
  `document-all`. The single-symbol `document --qname` is NEVER filtered (an explicit request always
  documents, even a trivial accessor).
- **Opt-out:** `--include-accessors` forces documenting trivial accessors even in batch modes.
- **Reporting:** count skipped accessors and include in the run summary ("K trivial accessors skipped").

## Component 4 — cheap fact group (managed block)

Add to `TDocFacts` (`src/doc/DRagLint.Doc.Facts.pas`), populate in `TDocFactsBuilder.Build` from the
index, and render in the managed `drag-lint:auto` block (`src/doc/DRagLint.Doc.Regions.pas`
`RenderFactsBlock`). All are pure index lookups — no new analysis. Each renders as one line, omitted
when empty (keep the block lean):

- **Overrides / Overridden by** — from the ancestry/heritage + virtual/override data:
  `Overrides: TAncestor.DoPaint` and `Overridden by: TDesc1, TDesc2 (+N)` (capped, with `(+N more)`).
- **Implements** — the interface member a method satisfies: `Implements: IComparable.CompareTo`.
- **Overload set** — `Overload 2 of 4` (by same name + parent type).
- **Virtual / abstract markers** — flag `abstract` (must-override contract) and `virtual`.
- **Platform / conditional** — `Platform: Win32-only` when the decl is guarded by a platform `{$IFDEF}`.
  **Best-effort:** if the index does not carry the guard cleanly (it may require an upward source scan
  from the decl line, like the existing `Deprecated` fallback), and that scan is non-trivial, DEFER this
  one fact to Phase 2 rather than ship a flaky signal. Confirm feasibility during implementation; the
  spec does not require it if the data isn't cheaply available.

Rendering stays inside the existing `<!-- drag-lint:auto BEGIN/END -->` region so regeneration is safe
and hand prose is preserved. Facts marked uncertain follow the existing `?`-suffix honesty convention.

## Config surface (manifest `docs` section)

New optional `docs` object in `third_party/dll-win64/drag-lint.json` (and documented in the manifest
schema). All keys optional with the defaults above:

```json
"docs": {
  "max_return_cases": 6,
  "max_callers": 5,
  "accessor_trivial_max_lines": 2
}
```

**Mechanism (kept simple, low-risk):** enhancement A (return cases + caller cap) ships ON by
**committing the `docs` section to the manifest** with the values above — no change to the loader's
absent-section defaults, so no global surprise for other callers. Enhancement B (trivial-accessor skip)
is a NEW code path; its default (on, ≤2 lines, batch modes only) lives **in code**, independent of the
manifest, with `accessor_trivial_max_lines` as an optional override. Absence of a `docs` key → that
key's loader default. `document --qname` is unaffected by all of the above.

## Files touched

- `src/doc/DRagLint.Doc.Facts.pas` — `TDocFacts` new fields (Overrides, OverriddenBy+total, Implements,
  OverloadOrdinal/OverloadCount, IsAbstract/IsVirtual, Platform); `TDocFactsBuilder.Build` gathering;
  caller cap from config.
- `src/doc/DRagLint.Doc.Regions.pas` — `RenderFactsBlock` renders the new lines (omit-when-empty).
- `src/cli/DRagLint.CLI.pas` — the trivial-accessor filter in `DoDocumentUnit/DoDocumentProject/
  DoDocumentAll`; `--include-accessors` arg; `LoadDocMaxCallers` / `LoadDocAccessorMaxLines` (mirror
  `LoadDocMaxReturnCases`); thread configs.
- `third_party/dll-win64/drag-lint.json` — the `docs` section.
- `src/delphi-plugin/DragLint.Plugin.Editor.pas` — `InvokeAutoDocumentProject` + the `SubGen` menu item.
- Docs: `docs/AI-USAGE.md` / `docs/CONVERSION-RULES.md` (document-verb section) + `CHANGELOG.md`.

## Testing

- `tests/autotest/` (or `tests/autodoc/`) new runners, deterministic, over purpose-built fixtures:
  - **Trivial-accessor filter:** a class with a 1-line getter, a 1-line setter, a 3-line non-trivial
    getter, and a normal method. Assert `document --unit`/`--project` skips the two trivial accessors,
    documents the 3-line one + the method; `document --qname` on a trivial accessor STILL documents it;
    `--include-accessors` documents all.
  - **Returns + caller cap:** a function with multiple `Result :=` sites and >5 callers → `<returns>`
    shows the mined cases; "Called from" shows exactly 5 + "(+N more)".
  - **Cheap facts:** a fixture with an `override` (asserts Overrides + Overridden by), an interface impl
    (Implements), an overloaded method (Overload N of M), and an `abstract` method (marker). Platform
    fact tested only if shipped.
- Plugin: the menu item is verified manually in a live IDE (spawn + apply + backup + Messages summary).
- All `.pas` strict 7-bit ASCII + CRLF + DocInsight on new public surface. Build via
  `build/build_draglint_win64.bat` (EXIT:0). Plugin BPL built per the IDE-package rules.

## Operational rollout (after Phase 1 ships)

1. Reindex **YADF** + **YADFOT** at v17 (add both to the manifest `indexes.sections`, or index ad-hoc
   DBs) so `document --project` has a compile-closure index.
2. In the **YADF repo**, create a branch (e.g. `feat/self-documentation`).
3. Run the new menu item (or the CLI) to auto-document on that branch.
4. Review / debug the generated DocInsight on the branch until satisfied.
5. Merge to YADF main; ship YADF as the next version; ship drag-lint as the next version.

## Open questions — resolved

1. Apply flow → **apply directly with backup** (user); git branch is the safety net.
2. Return cases / caller cap → config (`max_return_cases`=6, `max_callers`=5).
3. Trivial-accessor scope → batch modes only, default ≤2 lines, `--include-accessors` opt-out,
   `document --qname` never filtered.
4. Platform fact → best-effort; defer if not cheaply index-derivable.
   **[RESOLVED 2026-07-21 — ADP1 Phase 1 implementation: DEFERRED to Phase 2.** No per-symbol
   `{$IFDEF}` guard is persisted in the index, and deriving it at document time needs a nesting-aware
   upward source scan (`{$IFDEF}`/`{$ELSE}`/`{$ENDIF}`), not a bounded decl-line read like the
   `Deprecated`/`abstract` probes — i.e. the decision gate's defer condition. Phase 2's index-time
   facts layer (the preprocessor already holds the guard during indexing) is the cheap, correct home.]
5. Analysis facts + hover enrichment → Phase 2 (separate spec).
