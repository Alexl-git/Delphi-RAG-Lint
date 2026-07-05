# AutoFix Chunk 1: "Fix it" + per-rule auto-fix setting (Design)

Date: 2026-07-05
Status: approved (user, in-session)
Track: AutoFix (Track 1 of the drag-lint "Action" roadmap -- see
`docs/lint/drag-lint TODO plan.md`).
Scope: CLI fix engine (single-finding + batch, queryable fix registry, catalog
`fixable` flag, `--json`) + IDE plugin UX (context-sensitive "Fix it" /
"Fix all in unit" / "Fix all in project" + a per-rule "auto-fix" checkbox in
Lint Options). Proven end-to-end on the existing 3 fixable rules; widening the
rule set is deferred to later chunks.

## Problem / goal

drag-lint detects lint problems but only *applies* fixes in a limited way: a
whole-file `lint --fix` for a hardcoded set of 3 rules. There is no way to fix
**one** finding, no way to fix a **unit** or **project** from the IDE, no UI
signal of which rules are fixable, and no per-rule control over auto-application.

**Chunk 1 goal:** build the complete AutoFix vertical slice -- CLI engine + IDE
UX + settings -- and prove it on the 3 rules that already have fixes. Once the
slice works, *widening* to more rules is purely additive (add a registry entry;
the checkbox and the menu items light up automatically). The long-term end-state
("fix all lints") is reached one published chunk at a time.

## Existing building blocks (grounded, 2026-07-05)

- **Apply engine:** `src/refactor/DRagLint.Refactor.TextEdit.pas` --
  `TTextEdit` + `TTextEditApplier` (back-to-front multi-location apply,
  ANSI/CRLF-preserving, `.bak`, dry-run render). Reused, not replaced.
- **Existing fixer:** `BuildAutofixEdits` (`src/cli/DRagLint.CLI.pas:4457`) --
  a hardcoded `if/else` chain over 3 rule-ids: `self-assignment` (delete the
  statement line(s)), `redundant-parentheses` (strip the outer parens on a
  single-line span), `redundant-cast` (strip a `TFoo(x)` cast where `x` is a
  single identifier). Invoked by `lint --fix` (dry-run unless `--apply`).
- **Config:** `TLintConfig` (`src/lint/DRagLint.Lint.Config.pas:34`) -- parallel
  id-arrays `FDisabled`/`FEnabled` (+ severity/threshold arrays), `ShouldKeep`,
  round-tripped to the project's `drag-lint-lint.json`. **No autofix field yet.**
- **Rule catalog:** `drag-lint rules --json` returns per-rule `id`, `title`,
  `category`, `default_enabled`, params. **No `fixable` field yet.**
- **Lint Options frame:** `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas`
  -- loads the catalog, renders each category as a `TGroupBox` with a per-rule
  `RuleCB: TCheckBox` (enable/disable) built in `RenderCatalog` (`:860`),
  round-trips `drag-lint-lint.json` via `TLintConfigWriter` in `Save` (`:1071`).
- **Diagnostics tree:** `src/delphi-plugin/DragLint.Plugin.StructureForm.pas` --
  a `TTreeView` (`FTree`) with an existing `TPopupMenu` (`FPopup`, "Copy All
  Diagnostics"). Node data is `TStructureNodeData` (`Line/Name/QName/Kind`) --
  it does **NOT** currently carry the rule-id (`Code`). Findings come from
  `TDragLintDiagnostic` (`DiagnosticCache.pas`: `Line/StartCol/EndCol/Severity/
  Source/Code/Message`). File is the form-level `FCurrentFile`.
- **CLI spawn:** the plugin runs `drag-lint.exe` via the shared `DragLintExe`/
  `DLExe64` resolver (`DragLint.Plugin.ExeResolver`) + `RunAndCaptureStdout`.
- **Buffer reload pattern:** Extract Method reloads the edited buffer via a
  deferred `TThread.ForceQueue` closure that calls `IOTAModuleServices.
  FindModule(F).Refresh(True)` (`DragLint.Plugin.Keyboard.pas:284`) -- deferred
  off the key-dispatch stack to dodge a `TEditSource` dangling-refcount crash.
  Reused as a **pattern** (not an exposed helper).

## Key decisions (resolved in brainstorm)

1. **String rule-ids are canonical.** No numeric rule-number scheme is
   introduced -- the whole system already keys on string ids (catalog, config,
   finding `Code`, `BuildAutofixEdits`). A numeric id would create a second
   parallel identity to keep in sync and churn on every rule add/remove. (If a
   user-visible short number is ever wanted, it is a *display*-only field in the
   catalog, not the command key -- out of scope for Chunk 1.)
2. **Second checkbox appears only on fixable rules.** The "auto-fix" checkbox in
   Lint Options renders only when the rule's catalog entry has `fixable: true`.
3. **Prove on 3, widen later.** Chunk 1 ships the full machinery working on
   `self-assignment` / `redundant-parentheses` / `redundant-cast`. Adding more
   fixable rules is a later, additive chunk.
4. **Menu placement by node.** Individual **"Fix it"** is on a *finding* node
   (enabled only when that finding's rule is fixable). **"Fix all in unit"** and
   **"Fix all in project"** are on the **"Diagnostics" ROOT node** of the tree.
   One context-sensitive `TPopupMenu`; items enable/disable per selected node.
5. **`--json` is a first-class agent contract.** Because the CLI verbs are
   callable token-free by an AI orchestrator, the fix verb emits structured JSON
   (per finding: file, line, rule, fixable, applied|preview) so an orchestrator
   can drive fixes without scraping text. The safe-fix registry (mechanical,
   side-effect-free rules only) is the guardrail that makes blind/batch/agent
   application safe.
6. **Publish per chunk.** Chunk 1 ships as its own release; then plan the next
   chunk, handoff, clear, implement -- the usual cycle.

## Design

### D1. CLI -- queryable fix registry + catalog `fixable` flag

Extract the hardcoded fixable-rule knowledge out of `BuildAutofixEdits`' `if/else`
chain into a single **fix registry**: a list mapping a fixable rule-id to its
edit-builder. `BuildAutofixEdits` then iterates the registry instead of a fixed
chain (behavior byte-identical for the 3 rules -- guardrail: existing `lint --fix`
output must not change). `rules --json` gains a per-rule **`"fixable": true|false`**
field sourced from the registry (a rule is fixable iff it has a registry entry).
This one field drives every downstream UI decision (which rules show the second
checkbox and the "Fix it" item).

### D2. CLI -- single-finding fix verb

Add a targeted fix mode: fix exactly the finding at `--file F --line L --rule R`
(with `--dry-run` default / `--apply` / `--json` / `--no-backup`, matching the
established verb convention). It runs the linter (or reuses cached findings) for
that file, selects the finding(s) matching `(line, rule)`, builds their edits via
the registry (D1), and applies via `TTextEditApplier`. `--json` reports
`{file, line, rule, fixable, applied|preview}` (plus before/after span where
cheap). Whole-**unit** fix = the existing whole-file `--fix` for that unit.
Whole-**project** fix = the whole-file fixer applied across the `.dproj`'s units,
aggregating a report. (Whether this is a new `fix` verb or an extension of
`lint --fix` with targeting flags is an implementation choice for the plan; the
contract above is what matters.)

### D3. IDE -- context-sensitive "Fix it" menu on the Diagnostics tree

- Add the rule-id to the tree node data: extend `TStructureNodeData` with a
  `Code` field and populate it from `TDragLintDiagnostic.Code` when building
  finding nodes.
- Wire an `OnContextPopup` / `OnPopup` handler on `FTree`/`FPopup` that inspects
  the clicked node:
  - **root ("Diagnostics") node** -> show/enable **"Fix all in unit"** and
    **"Fix all in project"**;
  - **fixable finding node** -> show/enable **"Fix it"**;
  - **non-fixable finding node** -> both disabled/hidden.
  "Fixable" is determined from the catalog `fixable` set (D1), cached in the form.
- On click: spawn the CLI (single-finding fix for "Fix it"; unit/project batch for
  the root items) via the shared exe resolver with `--apply`, then reload the
  affected buffer(s) using the `ForceQueue` + `IOTAModule.Refresh(True)` pattern.
  Single "Fix it" is always available on a fixable finding (explicit user action);
  the batch items honor the per-rule auto-fix setting (D4) -- only rules toggled
  on are swept.

### D4. IDE -- per-rule "auto-fix" checkbox in Lint Options

- In `RenderCatalog`, next to each rule's existing `RuleCB` enable checkbox, add a
  second **"auto-fix"** `TCheckBox`, created **only when the rule is `fixable`**
  (from the catalog). Layout: to the right of, or on the same row as, the enable
  checkbox (implementation detail for the plan; must not disturb the param-editor
  layout below the rule row).
- Semantics: **auto-fix ON** = this rule participates in "Fix all in unit/project"
  (and any future save-time auto-application). **OFF** = the fix is still
  individually available via "Fix it", just not swept in bulk.
- Persistence: add a new id-array `FAutoFix` to `TLintConfig` (mirroring the
  `FDisabled`/`FEnabled` parallel-array pattern), written to/read from
  `drag-lint-lint.json` via `TLintConfigWriter`. `Save` walks the rule controls
  and records the auto-fix state alongside enabled/params.

## Global constraints (inherited by the plan)

- `.pas`/`.dfm` strict 7-bit ASCII, CRLF, no BOM. DocInsight `///` on new public
  declarations; `{ }` for unit-local helpers, matching each file's style.
- Build via the `delphi-build` recipe (wrapper .bat -> `rsvars` -> msbuild,
  `src/cli/drag-lint.dproj` Win64 Release from PowerShell `Start-Process -Wait`);
  confirm `BUILD_EXITCODE=0`, no `[dcc] Error`. Never Bash+cmd, never MCP build.
- After each engine rebuild, restage: `Copy-Item src\cli\Win64\Release\drag-lint.exe
  third_party\dll-win64\ -Force`; run CLI tests against the STAGED exe.
- The plugin BPL only builds while RAD Studio is closed; IDE changes need a BPL
  rebuild + a live smoke (D3/D4 are not unit-testable outside the IDE).
- Additive-only: `lint --fix` whole-file output for the 3 rules must stay
  byte-identical after the D1 registry refactor.

## Testing

- **CLI (RED->GREEN, per rule):** fixture files that trigger each of the 3 rules;
  assert the single-finding fix verb produces the correct edited output (and the
  `--json` shape), dry-run vs `--apply`, `.bak` created, ANSI/CRLF preserved.
  Guardrail: existing `lint --fix` whole-file output is byte-identical after the
  registry refactor (D1).
- **CLI catalog:** `rules --json` marks exactly the 3 rules `fixable: true` and
  all others `false`.
- **CLI batch:** unit fix and project fix apply across multiple findings/files and
  report correctly; honor the enabled/auto-fix config.
- **IDE:** live smoke -- right-click a fixable finding -> "Fix it" edits the buffer
  and reloads; right-click the "Diagnostics" root -> "Fix all in unit"/"in
  project" run; non-fixable finding greys the item; the Lint Options auto-fix
  checkbox shows only on fixable rules and round-trips to `drag-lint-lint.json`.
  (IDE UI wiring is not unit-testable outside the IDE -- verify by smoke.)

## Files

- `src/cli/DRagLint.CLI.pas` -- fix registry (D1), catalog `fixable` (D1),
  single-finding + batch fix verb + `--json` (D2).
- `src/lint/DRagLint.Lint.Config.pas` -- `FAutoFix` id-array + read/write (D4).
- `src/delphi-plugin/DragLint.Plugin.StructureForm.pas` -- `TStructureNodeData.Code`,
  context-sensitive popup, "Fix it"/"Fix all" items, CLI spawn + buffer reload (D3).
- `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` -- per-rule auto-fix
  checkbox render + save (D4).
- Tests: CLI fix fixtures + a `rules --json fixable` assertion under `tests/`.

## Out of scope (deferred to later chunks)

- **Widening the fixable-rule set** beyond the 3 -- the "create as many fixits as
  we can" phase; each new rule = a registry entry + a fixture, added incrementally
  and published per chunk.
- **Save-time automatic application** (apply auto-fix-ON rules on file save).
- **AutoDocument / Convert Components** (Tracks 2 and 3).
- A user-visible numeric rule id (display-only; not needed).

## After this chunk

Publish Chunk 1 as a release (version bump + CHANGELOG + pack + tag + gh-release,
per the usual cycle). Then plan Chunk 2 (widen the fixable set), handoff, clear,
implement.
