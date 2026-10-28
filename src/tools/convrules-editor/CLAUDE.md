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
* **Model tests (no engine beside the runner, live tests SKIP): 3117 pass / 0 fail / 20 skip** on conv/startup2 (f8d91391 + conv/startup + STARTUP2 long reads behind the progress window, 2026-10-27; 3237 / 0 / 0 on the 1.36.0-alpha-20261027-142316 pin). With the engine: `tests\ConvRulesModelTests.exe`, engine chosen explicitly: a
  `drag-lint.exe` beside the runner, else `CONVRULES_TEST_ENGINE`, else none (live
  tests SKIP; first line says which). Baseline on the 1.36.0-alpha-20261027-142316 pin:
  **3204 pass / 0 fail / 0 skip** (main bcbd1c35, before a1270 + drv2b; re-measure). The old 5 "VARINSP fixture" failures were a fixture defect:
  VARINSP is outside Micronite2027's compile closure, so its project DB never holds it; the picker / fill tests now use AssignGroups. A rebuild of `dll-win64` mid-run
  kills it: discard that run.
* **GUI drivers** (`tests\gui\`, by hand): `pwsh -NoProfile -File <driver> -Exe
  <ConvRulesEditor.exe>`, the exe beside a STAGED COPY of a pin (never `dll-win64`)
  whose Win64 library index answers. Not in the autotest battery. Checks:
  * `drive-unit-rules-toolbar.ps1` 41 -- menu bar, Uses Units commands, Swap
  * `drive-unit-picker.ps1` 20 -- unit picker
  * `drive-unit-harvest.ps1` 21 -- Unit Rules harvest (`-ProofNoDestination`)
  * `drive-file-menu.ps1` 21 -- New / Save As / Exit, unsaved guard; gateleak: Save As + Open posted under the Save As dialog open nothing (saveas.reentrant.not.nested, RED = 2); env.vcl.atoms
  * `drive-owning-open.ps1` 6 -- cross-book double-click through `ConfirmDiscard`
  * `drive-engine-wait.ps1` 16 -- progress window, Cancel, retry, cached reload; N7 Save under the progress window (menu path + real Ctrl+S) refused, book untouched (the key check is a guard only: it cannot go RED on a pre-N1 exe)
  * `drive-book-depth.ps1` 21 -- `#depth` combo
  * `drive-convert-tab.ps1` 34 -- Convert tab end to end (`-ProofNoIndex`); gateleak: a posted Add... while the Open dialog is up opens no second one (add.reentrant.not.nested, RED = 2 dialogs); env.vcl.atoms (`-ProofAtomCheck` = FAIL): the editor's VCL global atoms exist -- killed Delphi processes leak them, a full table gives FindControl nil and dead buttons (the old add.dialog flake); `vcl-atoms.ps1` reclaims the dead ones before launch; N1: a real click on Convert under the progress window is reported; N7/N11 (`n7.*`): POSTED WM_COMMAND (Add..., Convert) and BM_CLICK (Delete) under the progress window are refused and reported, none runs (RED on a pre-InputGate exe: Open dialog over the window + a real Convert); DRV-2b: the N1 click is made with the editor topmost and must land on it (`-ProofOccluded` = n1.click.under.progress + n1.lost.click.reported FAIL), `-ForeignActive` activates another window while the progress window is up (a pre-DRV-2b exe fails n7.refusal.reported: the notice waited for Screen.ActiveForm)
  * `drive-convert-batch.ps1` 22 -- B4 batch mode: 2 units in ONE convert-apply, batch note, `.BCK1` x4, then a `CONVRULES_BATCH=off` relaunch runs per-unit (`-ProofNoBatch` = RED). No retry since N11: every driver's `WaitIdle` also asks the editor (registered message `ConvRulesEditor.Busy`: 2 busy / 1 idle / no answer = blocked = busy), and `ConvRules.InputGate` refuses + reports a click that still lands in busy work
  * `drive-validate-scope.ps1` 18 -- scoped validation on Save, Auto-Match gate
  * `drive-inherited-offer.ps1` 16 -- C8 inherited instances (`-ProofNoInheritance`; `-ProofGateYes` adds a ~20 s real conversion, 17)
  * `drive-glyph-link.ps1` 23 -- glyph expressions (`-ProofNoGlyph`)
  * `drive-convert-request.ps1` 28 -- IDE convert request (`-ProofNoRequest`)
  * `drive-work-list.ps1` 13 -- Work list tab (`-ProofNoPasUses`)
  * `drive-qualify-fix.ps1` 21 -- qualify quick fix (`-ProofNoFix` = 16 pass / 5 fail; `-UseAlt` 25 (D4); `-QualifyAll` 23 (D6), `-ProofNoQualifyAll` = 10 / 2)
  * `drive-save-encoding.ps1` 15 -- Save question, File > Encoding, UTF-16 BOM note
  * `drive-convert-encoding.ps1` 29 (mixed.* N4-1; `-ProofNoMixed` = 28 / 1) -- Convert tab lower question, and the PRE-run encoding question (raise.prerun.* No then Yes; N2: Yes keeps every place as note rows, Cancel adds none; raise.* SKIP without `convert_encoding_guard`; the main exe before conv-1026 = 15 / 5)
  * `drive-migrate.ps1` 24 -- A4 #migrate: Work list -> Migrate dialog -> DL_NONE / rename, Save, re-run marks; D5 bulk DL_NONE, D6-B opens the row's book (`-ProofNoMigrate` = 13 / 7, `-ProofNoBulk` = 22 / 2)
  * `drive-startup-responsive.ps1` 8 -- STARTUP: a convert-request launch (harvest fed by the Convert tab) reads NO library unit list and settles responsive (busy query + menu); showing Unit Rules classifies (`library`). STARTUP2: the --form descendant sets and the Unit Rules library list run behind the progress window -- the busy query never goes unanswered over 2 s (`startup.form.answers`, `unitrules.show.answers`). The exe before conv/startup fails startup.no.library.list; before conv/startup2 = 6 / 2 (6056 / 5250 ms unanswered); prints the measured ms
  * `drive-rule-chains.ps1` 22 (measured on the 1.36.0 pin; the merged-book Save status carries a `[!]` validate prefix there) -- rule chains on Save: mark + status, dialog once per key, Conversion > Rule chains..., Split to `.stage2.rules` + Convert tab order, Merge, no dialog on close (`-ProofNoChain` = 5 / 0: the `proof.*` lines pass only when NO chain status / dialog / row appears)
* In a worktree pass `--db <wt>\src\tools\convrules-editor\_D-RAG\ConvRulesEditor.sqlite` and index with `--project ConvRulesEditor.dpr`.

## Unit map (who owns which decision)

* `Model` -- rule book parse/emit, nodes, `#depth`, Snapshot (dirty), `SaveCompleteWithMap`.
* `BlockOps` / `BlockFile` -- block merge (conflict/duplicate), file-scope blocks.
* `SkipList` / `FormTypes` / `RuleCatalog` -- class-picker skip marks, form-type rows, rule catalog.
* `UnitPick` (decisions) / `UnitPicker` (form) -- unit picker, Swap replacements.
* `UsesHarvest` / `UnitStatus` (`TDestinationResolver`) / `UnitMask` -- Unit Rules harvest, classify, masks/filter.
* `ValidateScope` -- scoped validation on Save, diagnostics -> rule marks, pending blocks, `AddStaticWarningMark` (the one way a static mark is added).
* `Glyph` (decisions) / `GlyphForm` (dialog) -- G[I/N] expressions, count links, glyph notes.
* `Inheritance` -- C8 analysis, offers, order warning, gate; `InheritanceEngine` -- its engine binders.
* `ConvertRun` -- pure Convert decisions: backups, preflight, `ParseApplyJson`, row notes, progress text.
* `ConvertRunner` -- executes a run: the per-unit loop and the book-major batch loop (B4, `RunConversionBatched`), backup/apply/restore, steps, report lines; `NotReachedUnits`, `JobRunsBatched`.
* `ConvertBatch` -- pure batch decisions: `BatchModeFor`, `BatchChunks` (8 per call), `BatchTimeoutMs`, `BatchUnitsMatch`, `BatchOfSingle`.
* `ConvertRerun` -- pure raise-and-re-run decisions: `EncodingRefusedRows`, `RaiseRerunPlan` (Yes/No/Cancel), `RerunJob`, `ShouldAskRaise`, `RerunStatusText`, `RunRowsOf`.
* `ConvertTab` -- Convert tab UI (editor-only); `ConvertRequest` -- `convert-request/1` parse, validate, scope.
* `WorkList` (pure) / `WorkListTab` (UI) -- pas_uses work list.
* `QualifyFix` (decisions) / `QualifyForm` (dialog) -- the one-click qualify #convert quick fix (apply/1 `qualify_fixes[]`).
* `RuleChains` (decisions) / `ChainForm` (dialog) -- CHAIN-1: chains, cycles, duplicate From, unit chains (`FindRuleChains`, marks, `MergeChainPlan` / `ApplyChainMerge`, `SplitChainPlan` / `StageBookPath` / `StageBookText`) and the Rule chains dialog (Merge / Split / Keep). Pure unit: no UI, engine or file I/O.
* `ConvCatalog` / `Casts` -- cast options incl. `ckValue` (StripDB).
* `TextEncoding` -- the encoding ladder, detection, round trip, pre-save decision, ReadTextDetect / WriteTextAtLevel.
* `Engine` -- `TEngineAdapter`: every engine call (incl. `ApplyConversionBatch`, apply-batch/1), pipes, timeouts, capabilities, resolve cache.
* `EngineWait` -- progress window / cancellable long call (editor-only). `InputGate` -- N7/N11 queue filter decisions (`MainForm.AppMessage` wires it). `DropTarget` -- OLE glue only.
* `MainForm` -- wiring only.

## Standing traps

* Never `TFile.ReadAllText` / `WriteAllText(.., TEncoding.ASCII)` on a user's book: `ReadTextDetect` / `WriteTextAtLevel`.
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
