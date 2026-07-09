# Batch E -- library-folders regression + reverse-calltree clickable Messages + fast access + ref-gap D + cleanup

> **Date:** 2026-07-08
> **Status:** design approved (autonomous session -- user away, directives locked before departure); ready for implementation plan.
> **Mode:** AUTONOMOUS end-to-end -- brainstorm -> spec -> plan -> subagent-driven implementation with per-task reviews -> final review -> cut **v0.98.0-alpha** + push + GH release -> handoff. No mid-run check-ins.
> **Predecessor:** Batch D (v0.97.0-alpha) shipped naming autofix phase 2 + the reverse-calltree IDE right-click (text-into-editor) + the naming presets combo + engine fixes A/B/C. This batch fixes three issues the user hit in live v0.97 IDE use, adds ref-gap D, and does a filed cleanup.

## Why these, and the autonomous-scope decisions

Five items, all reusing existing surfaces. Because this runs unsupervised to a public release, the scope was trimmed to what can be built safely and (mostly) verified headlessly; two riskier pieces are explicitly deferred to a supervised session:

- **DEFERRED -- ref-gap E (type-annotation / impl-header type refs):** needs NEW ref-walk handling across multiple decl cases (declVar/declArg/declField) + `defProc` header splitting, with real over-emit risk and an unconfirmed grammar shape. Too broad a core-parser change to ship unsupervised. Gap D (the common case) ships now; E follows supervised.
- **DEFERRED (as primary mechanism) -- a full editor right-click submenu:** RAD Studio 37 has **no clean, supported OTA API** to inject items into the code-editor context menu (unlike the Project Manager's `IOTAProjectMenuItemCreatorNotifier`); the only path is fragile VCL `TPopupMenu` surgery on the edit window, which cannot be live-verified while the user is away. Instead this batch delivers the user's underlying goal -- fast access to reverse-calltree without the top menu -- via a **keybinding** (supported), and attempts the editor-popup splice only as a clearly-labelled, failure-safe best-effort.

## Global constraints (bind every task)

- **Encoding:** all `.pas`/`.dfm`/`.dpr`/`.dproj`/`.dpk` strict 7-bit ASCII, no BOM, CRLF. DocInsight comments ASCII.
- **DocInsight (CDD):** new/changed public surface gets a `///` `<summary>` (+ tags as apt).
- **TDD** for headless-testable tasks (CLI json field, ref-gap D): failing test first, then green. IDE-UI tasks are NOT headless-testable -- build gate + a live-smoke checklist the user runs; do NOT fabricate UI tests.
- **Build:** `delphi-build` skill recipe (rsvars + msbuild via `Start-Process cmd.exe -Wait` + log; `BUILD_EXITCODE=0`, no `[dcc] Error`). CLI = `src/cli/drag-lint.dproj` Win64; plugin = `src/delphi-plugin/dclDragLintWizard.dproj` Win32, RAD Studio (`bds.exe`) CLOSED. Deploy CLI Win64 -> `third_party/dll-win64`; BPL auto-deploys to `third_party/dll-win32`.
- **Commit cadence:** one source commit per task; the final BPL/DCP in a `build(plugin):` commit.
- **Self-lint noise:** the self-lint's "errors" on braces/brackets-in-comments + `'\'` char literals are false positives; the real `dcc` compiler is the gate.
- **Release:** cut v0.98.0-alpha at the end (user pre-authorized). Handoff doc + auto-memory update.

---

## Task 1 -- Fix the empty Library/Browsing folders list (regression)

**Problem.** The Indexer Options page's read-only Library/Browsing folder list is EMPTY. Root cause (regression from commit `9d48f0a`): both `FGrpLibIndex` and `FMemoLibPaths` got an `akBottom` anchor and the frame's design height grew to ~752px; the IDE hosts the frame `Align=alClient` and shrinks it to the real (~450px) options client area, so the `akTop+akBottom` memo's effective height **collapses to ~0** -- the list renders with no visible rows even though `PopulateLibPaths` fills `Lines` correctly. NOT a resolver/registry/Batch-C-deletion/exception problem (the populate path is intact).

**Change** (`src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas`, `TDLIndexerOptionsFrame`, ~lines 379/414-420/439-451):
- Keep the resizable `akBottom` behaviour but add a floor so the host shrink cannot crush the memo: set `FMemoLibPaths.Constraints.MinHeight := LH;` (with `LH = 320`, ~20 lines at the default font) and `FGrpLibIndex.Constraints.MinHeight := <its design height>;`. This directly satisfies the user's ">= 20 visible lines" ask AND preserves grow-when-taller.
- (Alternative if MinHeight proves insufficient in the alClient host: drop `akBottom` from the memo and keep a fixed `LH` height. Prefer the MinHeight approach so it still grows.)
- Verify the resolver path is unchanged (`TProjectResolver.ResolveLibraryPaths` reading `HKCU+HKLM \Software\Embarcadero\BDS\37.0\Library\{Win32,Win64}`, values `Search Path`/`Browsing Path`, macros expanded). Secondary caveat to note (NOT fix here): `AddFolderIfReal` drops non-existent paths, so a mis-resolved `$(BDS)` would still yield empty -- out of scope, but mention in the report if observed.

**Testing.** IDE-UI -- no headless test. Gate = BPL builds 0-err; live-smoke: open Tools > Options > Third Party > drag-lint > Indexer, confirm the Library/Browsing list shows the resolved folders (>= 20 lines visible), and that resizing the Options window grows/shrinks it without collapsing below ~20 lines.

**Risk.** Low. Layout-only change; the data path is already correct.

---

## Task 2 -- Reverse call tree -> clickable IDE Messages window

**Goal.** Make every reverse-calltree node navigable: emit the tree to the IDE **Messages window**, where each node is a clickable `unit(line)` entry that double-clicks to the call site. (The v0.97 action dumps `--format text` into a read-only editor buffer -- not navigable.)

**Two parts.**

### 2a (headless, CLI) -- emit a full source path per node in the reverse-calltree JSON

`AddToolMessage(FileName, ...)` needs a FULL file path to navigate; the current `site` field is filename-only (`Format('%s:%d', [C.Location, C.CallSiteLine])`, `C.Location = ExtractFileName(...)`). Rather than have the plugin run one `query` subprocess per node (expensive for deep trees), add the full path to the JSON at the source:
- In the reverse-calltree engine / CLI JSON emitter (`src/report/DRagLint.Report.RCallTree.pas` builds the node; `DoReverseCallTree`/`BuildNodeJson` in `src/cli/DRagLint.CLI.pas:~10104` emits it), add a **`file`** field carrying the caller's full source path (the store has `file_path` before it is truncated to a filename -- surface it on the node record, e.g. `TRCallNode.SiteFile`, populated alongside `Site`). Keep `site` as-is (back-compat). Bump the JSON schema note to `reverse-calltree/1` + the new optional `file` field (additive).
- The node's line is already in `site` (`unit:line`); parse it or add a `line` int field too (cleaner -- add `SiteLine: Integer` to the node and emit `"line"`).

**Testing (headless):** extend `tests/autotest/run_reverse_calltree.ps1` -- assert each `--format json` node now carries a `file` (absolute path, exists) and a `line` (numeric) matching the `site`. Determinism preserved.

### 2b (IDE) -- new "Reverse Call Tree (Messages)" action that posts clickable messages

- Add `InvokeReverseCallTreeMessages` in `src/delphi-plugin/DragLint.Plugin.Editor.pas`, modelled on the EXISTING clickable-message emitter `PostLintReportToMessages` (Editor.pas:3687-3725, which already does `MS.AddToolMessage(fullpath, text, 'drag-lint', line, col)` via `Supports(BorlandIDEServices, IOTAMessageServices, MS)`).
- Flow (reuse the async + `TThread.Queue` discipline of `DLRunReport`, since OTA calls must be main-thread): resolve `Db := GetActiveProjectDb`; `DLAskQName(Q)`; run `reverse-calltree --qname "%s" --db "%s" --depth 3 --format json` via `RunAndCaptureStdout` on a bg thread; `SliceJsonBracket(out, '{','}')` -> parse the `reverse-calltree/1` object; walk the nested `callers`; for each node, in a `TThread.Queue` block call `MS.AddToolMessage(node.file, Format('%s -> %s', [callerQName, calleeQName]), 'drag-lint', node.line, 0)` (the node is the caller; its parent is the callee -- pair them). Bracket with `AddTitleMessage('drag-lint: reverse call tree for <Q>')` and show the Messages window.
- Indent/format the message text to convey tree depth (e.g. leading spaces per level) so the Messages list reads as a tree while each row stays clickable.
- Keep the existing `InvokeReverseCallTree` (text-into-editor) too -- the Messages version is an additional action ("Reverse Call Tree (clickable)..." or similar), not a replacement (user may want either).

**Testing (IDE):** no headless test for the OTA posting; gate = BPL builds 0-err; live-smoke: right-click/menu -> Reverse Call Tree (Messages) -> the Messages window fills with the tree, each row double-clicks to the call site. The 2a JSON `file`/`line` fields ARE headless-tested (they're the load-bearing data).

**Risk.** Low-medium. 2a is a clean additive JSON field (headless-tested). 2b reuses the proven `PostLintReportToMessages` + `DLRunReport` patterns; the only new surface is the JSON walk + per-node AddToolMessage.

---

## Task 3 -- Fast access to reverse-calltree (keybinding + best-effort right-click)

**Goal (user's real ask).** Reach reverse-calltree without the top drag-lint menu. RAD Studio 37 has **no supported OTA API** for the editor context menu, so:

**3a (supported) -- keybinding.** Wire the reverse-calltree action(s) into the existing keyboard-binding registration (`src/delphi-plugin/DragLint.Plugin.Keyboard.pas`, `BindKeyboard`/`IOTAKeyBindingServices`, ~lines 95/309-321 -- the same place `InvokeHover`=Ctrl+Alt+H etc. are bound). Assign an unused chord (e.g. `Ctrl+Alt+R` for reverse-calltree, or `Ctrl+Alt+K` -- pick one not already taken; verify against the existing bindings). Bind the Messages version (2b) as the primary (it's the navigable one). This is the reliable "fast access" win.

**3b (best-effort, failure-safe) -- editor popup splice.** ATTEMPT to add a small "drag-lint" submenu (Hover / Go to Definition / Reverse Call Tree (Messages) / Impact / Rename -- reusing the existing `InvokeHover`/`InvokeGoToDefinition`/`InvokeReverseCallTreeMessages`/`InvokeImpact`/`InvokeRename` procs) to the editor right-click by splicing a VCL `TPopupMenu` item onto the active edit window, hosted in the existing `TDragLintEditServicesNotifier` (`src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas:354`, which already holds live `EditWindow`/`EditView` handles in `WindowActivated`/`EditorViewActivated`). **This is unsupported/fragile** -- so it MUST be wrapped so any failure (handle not found, VCL shape changed, exception) is swallowed and NEVER crashes the plugin or blocks activation; if the splice can't attach, it silently no-ops and the keybinding + top menu remain the entry points. Clearly comment it as best-effort. If, during implementation, the splice proves too fragile to attach safely at all, SKIP 3b entirely and ship 3a only -- note it in the report + handoff for the user's live test.

**Testing.** No headless test (both are IDE surfaces). Gate = BPL builds 0-err. Live-smoke: the keybinding invokes reverse-calltree (Messages); IF 3b attached, the editor right-click shows a drag-lint submenu. Handoff flags 3b as needing live confirmation.

**Risk.** 3a low (proven keybinding path). 3b is inherently fragile -- mitigated by making it failure-safe + skippable; it is a bonus, not the deliverable (3a is).

---

## Task 4 -- Ref-gap D: index Self.-qualified field references

**Goal.** `Self.client` (read or write of a field via `Self.`) is not captured as a ref to `client`, so field-name-prefix rename-at-use misses those sites. Fix the common case (D); type-annotation refs (E) are deferred.

**Change** (`src/parser/DRagLint.Parser.Delphi13.pas`, the `exprDot` case ~lines 1348-1354, under `EmitUsageRefs`/--deep). The `exprDot` node has `lhs` = base identifier, `rhs` = member. Today the handler emits `read` for the `lhs` base only and skips `rhs`. Add: also emit a `read` ref for the `rhs` member identifier, **GATED to `SameText(NodeText(lhs), 'Self')`** -- so only `Self.member` is captured, NOT arbitrary `obj.Method`/`obj.Prop` (ungated would flood the index). Same gated-addition pattern as bug B.

**Testing (headless).** Extend `tests/autotest/run_naming_prefix_autofix.ps1` (CASE 1) and/or a dedicated `run_self_field_refs.ps1` modelled on `run_bare_rhs_refs.ps1`: fixture with a field used as `Self.client := X;` and `X := Self.client;` -> assert a `refs` row for `client` at each site (positive), AND that a non-Self `other.Method` does NOT gain a spurious member ref (negative, guards over-capture). Bonus: a field-name-prefix `--fix --apply` over the Self.-using fixture now rewrites the `Self.client` sites (the whole point).

**Risk.** Low-medium (core ref-walk, like B) but tightly gated (single `Self` gate) + negative-controlled. Note: this SHRINKS but does not fully close the field/type-prefix warning gap -- gap E (type annotations) remains, so the Task-3-of-Batch-D warning stays until E lands. Document that.

---

## Task 5 -- Cleanup: delete orphaned T52_options.dpr + .bat

Delete `tests/fixtures/T52_options.dpr` (and its companion `.bat` if present) -- they reference the singular `DragLint.Plugin.OptionsFrame` unit deleted in Batch D Task 5, are dead (no `.ps1`/battery runs them), and would fail to compile if ever invoked. Confirmed dead in Batch D's review. `git rm` them. No build impact (they're not in any project). Trivial.

---

## Task 6 -- Wrap-up: build, battery, docs, release, handoff

- Final CLI Win64 rebuild (Tasks 2a, 4) + Win32 BPL rebuild (Tasks 1, 2b, 3), RAD Studio closed, deploy.
- Full battery on the deployed exe: the new/changed `run_reverse_calltree.ps1` (json file/line fields), `run_self_field_refs.ps1` (or the extended prefix battery), plus a regression set (`run_naming_prefix_autofix.ps1`, `run_naming_autofix.ps1`, `run_bare_rhs_refs.ps1`, `run_deps_report.ps1`, `run_manifest.ps1`, `tests/autofix/run_fixable_catalog.ps1`). All PASS or STOP.
- Docs: CHANGELOG v0.98 section; README (note the reverse-calltree Messages action + keybinding); BACKLOG `RESUME LATEST-36` (mark ref-gap D fixed; note E still deferred + why; the library-folders regression fixed; the RCT-Messages + keybinding; 3b best-effort status). If the AI docs need the new action/keybinding, add it.
- **Release v0.98.0-alpha:** bump `VERSION` (CLI.pas:6), run `build/pack-lint-release.ps1 -Version 0.98.0-alpha`, verify `--version` + battery on the Release exe, release commit (version+CHANGELOG+README+BACKLOG+AI docs), push main, tag, GH release with both CLI zips + the Win32 BPL, mark Latest.
- **Handoff:** write the live-IDE smoke checklist (Task 1 folders; Task 2b Messages navigation; Task 3a keybinding + 3b right-click status) into the BACKLOG + auto-memory; run the handoff skill.

---

## Explicitly out of scope / deferred (recorded for the handoff)

- **Ref-gap E** (type-annotation + impl-header type-qualifier refs) -- supervised session; bigger core-parser change, over-emit risk, unconfirmed grammar shape.
- **A guaranteed editor right-click submenu** -- no supported OTA API in RAD Studio 37; 3b is a failure-safe best-effort only. If a robust right-click is required, it's its own investigation (VCL edit-window popup splice, live-verified).
- In-Delphi tree renderer / Graphviz-subset dock tab (filed TODO); arch charts Track 5.3; naming-settings deeper presets.
