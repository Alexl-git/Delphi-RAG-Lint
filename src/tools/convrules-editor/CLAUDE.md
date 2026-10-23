# convrules-editor -- converter stream instructions

Live rules only. Hand-over and state notes never live here: the latest handoffs are in
`docs\handoffs\RESUME.md`, the standing task list is `docs\CONVERTER-BACKLOG.md`, and
every past branch's hand-over notes are verbatim in
`docs\handoffs\archive\convrules-editor-HANDOVER-ARCHIVE.md` (Grep it -- .md is not
indexed). Inherited claims from any of these: re-verify against the tree before repeating.

## The engine under this editor is PINNED -- check it first

The editor shells out to `drag-lint.exe` (`ConvRules.Engine.pas`); the engine stream
rebuilds that exe in the same tree, without warning. At session start, and again before
any GUI or engine-touching work:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\check-engine-drift.ps1
```

| exit | meaning | do |
|---|---|---|
| 0 | pin matches the deployed engine, no new INBOX notes | carry on |
| 1 | engine drifted, or new/open notes addressed to us | read the notes, decide on a re-pin |
| 2 | cannot answer (pin or engine missing/unreadable) | fix that first; never read 2 as fine |

Match on the exit code, not the text. **The version string is not a drift signal** --
two different builds have reported the same version; compare SHA256 and build stamp.

* **Pins** live in `third_party\engine-pinned\<version>-<yyyyMMdd-HHmmss>\` (exe,
  tree-sitter DLLs, `drag-lint.json`, full `rules\`, `ENGINE-PIN.json` manifest;
  gitignored). `ConvRulesEditor.exe` sits beside it; `ResolveDragLintExe` prefers a
  `drag-lint.exe` next to `ParamStr(0)`, so **launch the editor FROM the pin dir**.
  Launched elsewhere it falls through to the live `third_party\dll-win64\`.
* **Re-pin** only when the engine change is settled: copy `dll-win64` to a new
  `<version>-<stamp>\`, write `ENGINE-PIN.json` with a SHA256 **you computed yourself**,
  then verify the pin RUNS (`info` reports the pinned DLL paths, `rules` a non-zero
  count, one real query answers). Three engine sessions may deploy to `dll-win64`: tell
  them before a re-pin starts and when it ends.

## Test kit (current values)

* **Build both** the tests and `build\_build_convrules_editor_local.bat` (no
  `dll-win64` staging unless given `stage`): `MainForm.pas`, `ConvertTab.pas` and the
  other forms are outside the tests' compile closure, so a tests build never sees their
  compile breaks. Testable decisions belong in the pure units below, not in forms.
* **Model tests (no engine beside the runner, live tests SKIP): 2224 pass / 0 fail / 19 skip** after the 1.31.5 apply-field work (B1/B3/B6/B7/B8, C-2). With the engine: `tests\ConvRulesModelTests.exe`, engine chosen explicitly: a
  `drag-lint.exe` beside the runner, else `CONVRULES_TEST_ENGINE`, else none (live
  tests SKIP; first line says which). Baseline on the 1.31.5 pin:
  **2281 pass / 5 fail / 0 skip** -- the 5 are the VARINSP fixture
  (`picker.unit.has.VARINSP`, `fill.from-unit.*`). A rebuild of `dll-win64` mid-run
  kills it: discard that run.
* **GUI drivers** (`tests\gui\`, by hand): `pwsh -NoProfile -File <driver> -Exe
  <ConvRulesEditor.exe>`, the exe beside a STAGED COPY of a pin (never `dll-win64`)
  whose Win64 library index answers. Not in the autotest battery. Checks:
  * `drive-unit-rules-toolbar.ps1` 41 -- menu bar, Uses Units commands, Swap
  * `drive-unit-picker.ps1` 20 -- unit picker
  * `drive-unit-harvest.ps1` 21 -- Unit Rules harvest (`-ProofNoDestination`)
  * `drive-file-menu.ps1` 19 -- New / Save As / Exit, unsaved guard
  * `drive-owning-open.ps1` 6 -- cross-book double-click through `ConfirmDiscard`
  * `drive-engine-wait.ps1` 9 -- progress window, Cancel, retry, cached reload
  * `drive-book-depth.ps1` 21 -- `#depth` combo
  * `drive-convert-tab.ps1` 23 -- Convert tab end to end (`-ProofNoIndex`)
  * `drive-validate-scope.ps1` 18 -- scoped validation on Save, Auto-Match gate
  * `drive-inherited-offer.ps1` 16 -- C8 inherited instances (`-ProofNoInheritance`; `-ProofGateYes` adds a ~20 s real conversion, 17)
  * `drive-glyph-link.ps1` 23 -- glyph expressions (`-ProofNoGlyph`)
  * `drive-convert-request.ps1` 28 -- IDE convert request (`-ProofNoRequest`)
  * `drive-work-list.ps1` 13 -- Work list tab (`-ProofNoPasUses`)
  * `drive-qualify-fix.ps1` 20 -- qualify quick fix (`-ProofNoFix` = 15 pass / 5 fail)
* In a worktree pass `--db <wt>\src\tools\convrules-editor\_D-RAG\ConvRulesEditor.sqlite` and index with `--project ConvRulesEditor.dpr`.

## Unit map (who owns which decision)

* `Model` -- rule book parse/emit, nodes, `#depth`, Snapshot (dirty), `SaveCompleteWithMap`.
* `BlockOps` / `BlockFile` -- block merge (conflict/duplicate), file-scope blocks.
* `SkipList` / `FormTypes` / `RuleCatalog` -- class-picker skip marks, form-type rows, rule catalog.
* `UnitPick` (decisions) / `UnitPicker` (form) -- unit picker, Swap replacements.
* `UsesHarvest` / `UnitStatus` (`TDestinationResolver`) / `UnitMask` -- Unit Rules harvest, classify, masks/filter.
* `ValidateScope` -- scoped validation on Save, diagnostics -> rule marks, pending blocks.
* `Glyph` (decisions) / `GlyphForm` (dialog) -- G[I/N] expressions, count links, glyph notes.
* `Inheritance` -- C8 analysis, offers, order warning, gate; `InheritanceEngine` -- its engine binders.
* `ConvertRun` -- pure Convert decisions: backups, preflight, `ParseApplyJson`, row notes, progress text.
* `ConvertRunner` -- executes a run: per-unit backup/apply/restore, steps, report lines.
* `ConvertTab` -- Convert tab UI (editor-only); `ConvertRequest` -- `convert-request/1` parse, validate, scope.
* `WorkList` (pure) / `WorkListTab` (UI) -- pas_uses work list.
* `QualifyFix` (decisions) / `QualifyForm` (dialog) -- the one-click qualify #convert quick fix (apply/1 `qualify_fixes[]`).
* `ConvCatalog` / `Casts` -- cast options incl. `ckValue` (StripDB).
* `Engine` -- `TEngineAdapter`: every engine call, pipes, timeouts, capabilities, resolve cache.
* `EngineWait` -- progress window / cancellable long call (editor-only). `DropTarget` -- OLE glue only.
* `MainForm` -- wiring only.

## Standing traps

* `IfThen` evaluates BOTH arguments -- a nil deref in the unused branch still crashes.
* `GetMenu(main)` returns 0 (VCL style paints its own bar): drivers ask the form with
  `MAIN_MENU_QUERY_MSG` and invoke items by PATH (`[W]::InvokeMenu($main, 'File|Save As...')`).
* Status text is readable only from the `TStatusBar` (`FLblStatus` and `LblScope` are windowless TLabels).
* Drivers: `LB_GETTEXT` into a LOCAL buffer; capture child windows with `PrintWindow`;
  count only engine children created after the editor started (reused PIDs).
* One stale `--db` fails the WHOLE query (exit 2, names the DB); `index --project
  <x.dproj> --db <db>` migrates it in seconds -- do not route around it.
* `convert-apply` needs the unit INDEXED; "could not locate .dfm object block" means
  check the `--db` set, not the .dfm.
* The project file is always `ProjectFileForDb(GEditorProjectDb)` -- never the Unit
  Rules Destination (that would re-scope the editor's DB).
* A new defaulted anonymous-method parameter on an existing overload broke callers
  (E2250): add a NEW name instead.
* Capabilities are probed once via `CapabilityNames` (`info --json`); restart the editor after a re-pin.
* Never `lint-all --rule doc-drift --fix --apply` here (it de-indents `///` blocks); fix autodoc by hand.
* Judge `dl:ok` markers with `lint-all` (never per-file on a `.dpr`) and the SAME
  `--enable` rules the markers suppress.
* Qualify `#convert` classes until the engine's `#link` class-scope fix lands.
* Main-menu shortcuts only with Ctrl (N, O, S, Shift+S) -- a bare key fires inside edit controls.
* A unit or `#depth` insert shifts every `#convert` index: re-find headers by NODE.
* `TJSONNumber` is not a `TJSONString`; type-check every apply/1 read, never raise on a bad shape.

## Engine correspondence

Notes in: `docs\INBOX-*engine-to-converter*.md`; ours out: `docs\INBOX-REPLY-*.md`. The
drift check lists both, newest first.
