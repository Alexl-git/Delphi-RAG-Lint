# AutoFix Chunk 1: "Fix it" + per-rule auto-fix setting -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the complete AutoFix vertical slice -- a queryable fix registry, a `fixable` flag in the rule catalog, a single-finding + unit + project fix CLI verb with `--json`, an IDE context-sensitive "Fix it" / "Fix all in unit|project" menu on the Diagnostics tree, and a per-rule "auto-fix" checkbox in Lint Options -- proven end-to-end on the existing 3 fixable rules (`self-assignment`, `redundant-parentheses`, `redundant-cast`).

**Architecture:** CLI first (unit-testable), IDE last (live smoke only). Extract the hardcoded fixable-rule knowledge in `BuildAutofixEdits` into a single registry that both the catalog (`fixable` flag) and the fixer read from. Add a targeted fix mode (`--file/--line/--rule`) and batch (unit/project) modes, all reusing the existing `TTextEditApplier`. The plugin reads the catalog `fixable` set to gate its menu items and the second settings checkbox; the fix runs the CLI and reloads the buffer with the Extract-Method `ForceQueue`/`Refresh` pattern. A new `FAutoFix` id-array in `TLintConfig` persists the per-rule auto-fix choice to `drag-lint-lint.json`.

**Tech Stack:** Delphi 13 / RAD Studio 37, FireDAC/SQLite, the drag-lint CLI (`src/cli/drag-lint.dproj`), the VCL IDE plugin (BPL), `TTextEditApplier`, `TLintConfig`/`TLintConfigWriter`, PowerShell test harnesses under `tests/`.

**Spec:** `docs/superpowers/specs/2026-07-05-autofix-chunk1-fix-it-design.md` -- read it first (D1-D4, decisions, out-of-scope).

## Global Constraints

- `.pas`/`.dfm` strict 7-bit ASCII, CRLF, no BOM. DocInsight `///` on new public declarations; `{ }` for unit-local helpers, matching each file's existing style.
- Build ONLY via the `delphi-build` skill recipe: a wrapper `.bat` (`rsvars` -> `cd` -> `msbuild /t:Build /p:Config=Release /p:Platform=Win64 src\cli\drag-lint.dproj`) run from PowerShell `Start-Process -Wait` with a log; confirm `BUILD_EXITCODE=0` and no `[dcc] Error`. Never Bash+cmd, never the MCP build tool.
- After each ENGINE rebuild: `Copy-Item src\cli\Win64\Release\drag-lint.exe third_party\dll-win64\ -Force`. Run CLI tests against the STAGED exe `third_party\dll-win64\drag-lint.exe` (the raw `src\cli\Win64\Release\drag-lint.exe` dies `0xC0000135` -- no tree-sitter DLLs beside it).
- Run PowerShell test harnesses from a NEUTRAL CWD (e.g. `C:\TEMP`) OR assert output directly; the exe prints `(loaded defaults...)` to stderr, which trips a spurious `NativeCommandError` under `$ErrorActionPreference='Stop'` from a config-bearing CWD.
- Fixture `.pas` files must be CRLF (the Write tool emits LF -> byte-rewrite before committing).
- **Additive-only guardrail:** existing `lint --fix` whole-file output for the 3 rules MUST stay byte-identical after the Task-1 registry refactor. The full lint suite (`tests/lint/run_lint_tests.ps1`, 154 tests) and store suite MUST stay green.
- **The plugin BPL only builds while RAD Studio is CLOSED.** IDE tasks (7-8) are NOT unit-testable outside the IDE -- they end in a documented live smoke, not an automated assertion. Do not attempt a BPL build with the IDE open (F2039).
- String rule-ids are canonical -- do NOT introduce numeric rule ids.

## File Structure

- `src/cli/DRagLint.CLI.pas` -- fix registry (Task 1), catalog `fixable` (Task 2), single-finding + unit + project fix verb + `--json` (Tasks 3-5).
- `src/lint/DRagLint.Lint.Config.pas` -- `FAutoFix` id-array + read/write (Task 6).
- `src/delphi-plugin/DragLint.Plugin.StructureForm.pas` -- `TStructureNodeData.Code`, context-sensitive popup, "Fix it"/"Fix all" items, CLI spawn + buffer reload (Task 7).
- `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` -- per-rule auto-fix checkbox render + save (Task 8).
- Tests: `tests/autofix/` (new) for the CLI fix fixtures + a `rules --json fixable` assertion; reuse `tests/lint/run_lint_tests.ps1` for the additive-only guardrail.

---

### Task 1: Fix registry -- extract the hardcoded fixable rules

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- `BuildAutofixEdits` (`:4457`); add a file-level registry above it.

**Interfaces:**
- Produces: `function IsFixableRule(const ARuleId: string): Boolean;` and `function FixableRuleIds: TArray<string>;` (both file-level, read by Task 2's catalog and Task 3's verb). `BuildAutofixEdits` keeps its exact signature `function BuildAutofixEdits(const AFindings: TArray<TLintFinding>; out AFixableCount: Integer): TArray<TTextEdit>;` and identical output.

- [ ] **Step 1: Read the current fixer.** Read `BuildAutofixEdits` (`src/cli/DRagLint.CLI.pas:4457-4560` approx -- through the end of the `redundant-cast` branch and the function's `end;`). Note the 3 rule-ids and their exact edit logic. Do NOT change the edit logic in this task -- only lift the rule-id SET out.

- [ ] **Step 2: Add the registry constant + helpers** immediately above `BuildAutofixEdits`:

```pascal
{ The set of rule-ids that have a registered, mechanical, side-effect-free
  quick-fix. Single source of truth for both the rules-catalog 'fixable' flag
  and the fix verbs. Widening AutoFix = add an id here AND a branch in
  BuildAutofixEdits (kept in lockstep; a guard test asserts they agree). }
const
  FIXABLE_RULE_IDS: array[0..2] of string =
    ('self-assignment', 'redundant-parentheses', 'redundant-cast');

function IsFixableRule(const ARuleId: string): Boolean;
var S: string;
begin
  for S in FIXABLE_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result := False;
end;

function FixableRuleIds: TArray<string>;
var I: Integer;
begin
  SetLength(Result, Length(FIXABLE_RULE_IDS));
  for I := 0 to High(FIXABLE_RULE_IDS) do Result[I] := FIXABLE_RULE_IDS[I];
end;
```

- [ ] **Step 3: Build + stage.** Wrapper `.bat` -> `BUILD_EXITCODE=0`, no `[dcc] Error`. `Copy-Item src\cli\Win64\Release\drag-lint.exe third_party\dll-win64\ -Force`.

- [ ] **Step 4: Guardrail -- existing lint --fix output unchanged.** From `C:\TEMP`, run the lint suite against the staged exe: `pwsh -File C:\Projects\Delphi-RAG-lint\tests\lint\run_lint_tests.ps1 -Exe C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`. Expected: `154 pass / 0 fail`. (This proves the refactor was output-neutral -- `BuildAutofixEdits` still emits identical edits.)

- [ ] **Step 5: Commit.**

```bash
git add src/cli/DRagLint.CLI.pas
git commit -m "refactor(autofix): extract fixable-rule set into a registry (no behavior change)"
```

---

### Task 2: `fixable` flag in the rules catalog

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- `DoRules` JSON emitter (`:4710-4718`).
- Test: `tests/autofix/run_fixable_catalog.ps1` (new).

**Interfaces:**
- Consumes: `IsFixableRule` (Task 1).
- Produces: `rules --json` rule objects each gain `"fixable": true|false`. The IDE (Tasks 7-8) reads this.

- [ ] **Step 1: Write the failing test.** Create `tests/autofix/run_fixable_catalog.ps1` (CRLF):

```powershell
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
Push-Location C:\TEMP
try {
  $json = & $Exe rules --json 2>$null | Out-String
  $obj  = $json | ConvertFrom-Json
  $byId = @{}; foreach($r in $obj.rules){ $byId[$r.id] = $r }
  Check 'self-assignment fixable=true'        ($byId['self-assignment'].fixable -eq $true)
  Check 'redundant-parentheses fixable=true'  ($byId['redundant-parentheses'].fixable -eq $true)
  Check 'redundant-cast fixable=true'         ($byId['redundant-cast'].fixable -eq $true)
  # a rule with no fix must be false (pick a stable always-present rule):
  Check 'cyclomatic-complexity fixable=false' ($byId['cyclomatic-complexity'].fixable -eq $false)
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 2: Run it -- expect FAIL.** From `C:\TEMP`: `pwsh -File C:\Projects\Delphi-RAG-lint\tests\autofix\run_fixable_catalog.ps1`. Expected: the 3 `fixable=true` checks FAIL (the field is absent, so `.fixable -eq $true` is false). Capture as RED.

- [ ] **Step 3: Emit the flag.** In `DoRules`' JSON loop, after `O.AddPair('source', R.Source);` (`:4716`), add:

```pascal
        O.AddPair('fixable', TJSONBool.Create(IsFixableRule(R.Id)));
```

- [ ] **Step 4: Build + stage** (Global Constraints recipe). Then rerun the test from `C:\TEMP` -- expect PASS (all 4 checks).

- [ ] **Step 5: Commit.**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/run_fixable_catalog.ps1
git commit -m "feat(autofix): rules --json marks fixable rules"
```

---

### Task 3: Single-finding fix verb (`--file/--line/--rule`) + `--json`

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- `DoLint`'s `--fix` block (`:4621-4639`) to honor targeting flags; the `TArgs` parsing (near `:746`) to accept `--fix-line` and `--fix-rule` (reuse existing `--file`).
- Test: `tests/autofix/run_fix_single.ps1` (new) + fixtures under `tests/autofix/fixtures/`.

**Interfaces:**
- Consumes: `IsFixableRule`, `BuildAutofixEdits`, `TTextEditApplier` (existing).
- Produces: `drag-lint lint --file F --fix --fix-line L --fix-rule R [--apply|--json|--no-backup]` fixes ONLY the finding(s) at `(L, R)` in F. `--json` prints `{"file","line","rule","fixable","applied":bool,"preview":bool}`.

Rationale for shape: extend the existing `lint --fix` (which already wires `--apply`/`--no-backup`/`TTextEditApplier`) with two optional targeting flags rather than add a parallel verb -- least code, one fix path. When `--fix-line`/`--fix-rule` are absent, `--fix` behaves exactly as today (whole file).

- [ ] **Step 1: Create the RED fixture.** `tests/autofix/fixtures/redundant_parens.pas` (CRLF, strict ASCII), a minimal compilable unit whose body contains a `redundant-parentheses` finding, e.g. `X := ((A + B));` inside a procedure. Note the 1-based line of the offending statement (call it L).

- [ ] **Step 2: Write the failing test.** `tests/autofix/run_fix_single.ps1` (CRLF): copy the fixture to a scratch file in `C:\TEMP`, run `& $Exe lint --file <scratch> --fix --fix-line L --fix-rule redundant-parentheses --json` (preview) and assert the JSON reports `fixable=true, applied=false, preview=true`; then run with `--apply` and assert the scratch file's content had the extra parens stripped and a `.bak` exists. Mirror the `Check` helper from Task 2. (Do not run the harness from a config-bearing CWD.)

- [ ] **Step 3: Run it -- expect FAIL** (the targeting flags don't exist; `--fix` currently fixes the whole file and emits no per-finding JSON). Capture RED.

- [ ] **Step 4: Add the targeting flags to `TArgs` + parser.** Add `FixLine: Integer` and `FixRule: string` fields to `TArgs`; parse `--fix-line <n>` and `--fix-rule <id>` in the arg loop near `:746` (mirror an existing int/string flag). Default `FixLine := 0`, `FixRule := ''`.

- [ ] **Step 5: Implement targeting + JSON** in the `--fix` block (`:4621`). Before `BuildAutofixEdits`, when `AArgs.FixLine > 0` or `AArgs.FixRule <> ''`, filter `Survivors` to findings matching `(StartLine = FixLine)` and/or `(SameText(RuleId, FixRule))`. Then build edits from the filtered set. When `AArgs.AsJson`, instead of the text `Writeln`s, emit one JSON object per targeted finding: `{"file":F.FilePath,"line":F.StartLine,"rule":F.RuleId,"fixable":IsFixableRule(F.RuleId),"applied":AArgs.Apply,"preview":not AArgs.Apply}` (build with `TJSONObject`/`TJSONArray`, mirror the emitter at `:4644-4661`). Apply/preview via the existing `TTextEditApplier` calls.

- [ ] **Step 6: Build + stage**, then rerun `run_fix_single.ps1` from `C:\TEMP` -- expect PASS (preview JSON correct; `--apply` strips the parens + writes `.bak`).

- [ ] **Step 7: Guardrail.** Rerun `tests/lint/run_lint_tests.ps1` (154 pass) AND `tests/autofix/run_fixable_catalog.ps1` -- both green (whole-file `--fix` with no targeting flags still behaves as before).

- [ ] **Step 8: Commit.**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/
git commit -m "feat(autofix): single-finding fix via --fix-line/--fix-rule + --json"
```

---

### Task 4: Whole-unit fix

**Files:**
- Modify: none if `lint --file F --fix --apply` already fixes a whole unit (it does). This task is a TEST that proves the unit path + adds a multi-finding fixture.
- Test: `tests/autofix/run_fix_unit.ps1` (new) + `tests/autofix/fixtures/multi.pas`.

**Interfaces:**
- Consumes: the Task-3 `--fix` path (no targeting flags = whole file).
- Produces: verified whole-unit behavior; no new CLI surface.

- [ ] **Step 1: Fixture.** `tests/autofix/fixtures/multi.pas` (CRLF): a unit with TWO fixable findings of DIFFERENT rules (e.g. one `redundant-parentheses` and one `self-assignment`), on different lines.

- [ ] **Step 2: Write the test.** `run_fix_unit.ps1`: copy to scratch, run `& $Exe lint --file <scratch> --fix --apply`, assert BOTH findings are fixed in the output file and the `autofix: applied N fix(es)` line reports N=2. Preview mode (`--fix` no `--apply`) reports 2 fixable, writes nothing.

- [ ] **Step 3: Run it.** Expect PASS immediately (the whole-file path already exists). If it FAILS, diagnose (e.g. same-line multi-fix column reconciliation -- the fixture deliberately uses different lines to avoid that; if a real gap appears, STOP and report, do not patch blindly).

- [ ] **Step 4: Commit.**

```bash
git add tests/autofix/
git commit -m "test(autofix): whole-unit fix applies all fixable findings"
```

---

### Task 5: Whole-project fix

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add a project-fix path. Check `DoLintProject` (`:6094`) and `DoLintAll` (`:5878`) FIRST: if one already enumerates `.dproj` units and runs lint per unit, extend it to honor `--fix`/`--apply`; otherwise add `--fix` handling to the project runner.
- Test: `tests/autofix/run_fix_project.ps1` (new) + a tiny `.dproj` fixture with 2 units.

**Interfaces:**
- Consumes: the Task-3 `--fix` path per unit.
- Produces: `drag-lint lint-project --project P.dproj --fix --apply` (or the existing project verb + `--fix`) fixes fixable findings across all units; `--json` aggregates per-file results.

- [ ] **Step 1: Read the project runners.** Read `DoLintProject` (`:6094`) and `DoLintAll` (`:5878`). Determine which enumerates units and is the right host for `--fix`. RECORD which verb you extended in the task report.

- [ ] **Step 2: Fixture.** `tests/autofix/fixtures/proj/` with a minimal `.dproj` referencing two `.pas` units, each carrying one fixable finding (CRLF, ASCII).

- [ ] **Step 3: Write the failing test.** `run_fix_project.ps1`: copy the project dir to scratch, run the project verb with `--fix --apply`, assert BOTH units were fixed and the report names 2 files. Expect FAIL first (project verb ignores `--fix`).

- [ ] **Step 4: Implement.** In the chosen project runner, when `AArgs.Fix`, route each unit's findings through `BuildAutofixEdits` + `TTextEditApplier` (dry-run vs `--apply`); aggregate a `applied N fix(es) across M file(s)` summary; `--json` = an array of the per-file objects from Task 3.

- [ ] **Step 5: Build + stage**; rerun `run_fix_project.ps1` -- PASS. Then the guardrails: `run_lint_tests.ps1` (154), `run_fixable_catalog.ps1`, `run_fix_single.ps1`, `run_fix_unit.ps1` -- all green.

- [ ] **Step 6: Commit.**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/
git commit -m "feat(autofix): whole-project fix across .dproj units"
```

---

### Task 6: `FAutoFix` config field (per-rule auto-fix persistence)

**Files:**
- Modify: `src/lint/DRagLint.Lint.Config.pas` -- add `FAutoFix: TArray<string>` + accessors + JSON round-trip, mirroring `FDisabled`/`FEnabled`.
- Test: `tests/autofix/run_config_autofix.ps1` OR a store/config unit test if one exists (check `tests/lint-store/`).

**Interfaces:**
- Consumes: the existing `TLintConfig` parallel-array + `ApplyConfigObject` machinery.
- Produces: `function TLintConfig.IsAutoFix(const ARuleId: string): Boolean;`, `procedure AddAutoFix(const AIds: TArray<string>);`, `function AutoFixIds: TArray<string>;`, and `drag-lint-lint.json` round-trips an `"autofix": ["rule-id", ...]` array. Task 8 (Lint Options) reads/writes these.

- [ ] **Step 1: Read the config unit.** Read `src/lint/DRagLint.Lint.Config.pas` around `FDisabled`/`FEnabled` (`:36-80`) and `ApplyConfigObject` (`:51`). Note exactly how `disabled`/`enabled` arrays serialize to/from JSON so `autofix` mirrors them.

- [ ] **Step 2: Write the failing test.** A test that writes a `drag-lint-lint.json` with `"autofix":["redundant-cast"]`, loads it via `TLintConfig`, and asserts `IsAutoFix('redundant-cast')=True` and `IsAutoFix('self-assignment')=False`; then adds `self-assignment`, re-serializes, and asserts both are present. Use the existing config-test harness pattern if `tests/lint-store/` has one; else a small PowerShell round-trip via a CLI verb that prints the effective config (check whether one exists -- e.g. `lint --print-config`; if not, a DUnitX/console test on `DRagLint.Lint.Config`). RECORD which harness you used.

- [ ] **Step 3: Run it -- expect FAIL** (field absent).

- [ ] **Step 4: Implement.** Add `FAutoFix: TArray<string>` to `TLintConfig`; `IsAutoFix`/`AddAutoFix`/`AutoFixIds` (copy the `FEnabled` accessor shape); parse `"autofix"` in `ApplyConfigObject` (mirror `enabled`); serialize it in the writer path. Keep it independent of enabled/disabled (a rule can be enabled+autofix, enabled+not-autofix, etc.).

- [ ] **Step 5: Build + stage**; rerun the test -- PASS. Guardrail: `run_lint_tests.ps1` (154) + the store suite green (config is shared).

- [ ] **Step 6: Commit.**

```bash
git add src/lint/DRagLint.Lint.Config.pas tests/
git commit -m "feat(autofix): persist per-rule auto-fix choice in drag-lint-lint.json"
```

---

### Task 7: IDE -- "Fix it" / "Fix all" on the Diagnostics tree

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.StructureForm.pas` -- `TStructureNodeData` (`:68-73`), the diagnostic-node builder (`:442`), `FPopup` setup (`:313`), + new handlers.

**Interfaces:**
- Consumes: catalog `fixable` (Task 2 -- fetched via `rules --json` once, cached); the single-finding verb (Task 3); unit/project verbs (Tasks 4-5); the shared `DragLintExe` resolver + `RunAndCaptureStdout`; the `ForceQueue`+`IOTAModule.Refresh(True)` reload pattern (`Keyboard.pas:284`).
- Produces: a context-sensitive popup: root node -> "Fix all in unit"/"Fix all in project"; fixable finding -> "Fix it"; else disabled.

> **NOT unit-testable outside the IDE.** This task ends in a documented live smoke, not an assertion. Requires the BPL to build (RAD Studio CLOSED) + deploy.

- [ ] **Step 1: Carry the rule-id on the node.** Add `Code: string;` to `TStructureNodeData` (`:68-73`). In the diagnostic-node builder (`:442`, where `D.Line` is copied), also set `NodeData.Code := D.Code;` (rule-id from `TDragLintDiagnostic.Code`). Store the file on the node or reuse `FCurrentFile`.

- [ ] **Step 2: Cache the fixable set.** On dock/structure load, run `drag-lint rules --json` once via the exe resolver, parse the `fixable` ids into a `TStringList`/`TDictionary` field `FFixableRules`. (Reuse the existing catalog fetch if the Lint Options tab already loaded it -- otherwise fetch here.)

- [ ] **Step 3: Add the popup items.** In `FPopup` setup (`:313`, alongside "Copy All Diagnostics"), add `Fix it`, `Fix all in unit`, `Fix all in project` items via the existing `AddPopupItem` helper, each with an `OnClick`.

- [ ] **Step 4: Context-sensitivity.** Add an `FTree.OnContextPopup` (or `FPopup.OnPopup`) handler: find the clicked/selected node; if it is the "Diagnostics" ROOT -> enable the two "Fix all" items, disable "Fix it"; if it is a finding whose `Code` is in `FFixableRules` -> enable "Fix it", disable "Fix all"; else disable all three.

- [ ] **Step 5: Wire the actions.** "Fix it" -> spawn `drag-lint lint --file <FCurrentFile> --fix --fix-line <node.Line> --fix-rule <node.Code> --apply` via the resolver; on success, reload the buffer with the `TThread.ForceQueue(procedure begin QMod := (BorlandIDEServices as IOTAModuleServices).FindModule(F); if QMod<>nil then QMod.Refresh(True); end)` pattern (copy from `Keyboard.pas:284-297`). "Fix all in unit" -> `... lint --file <F> --fix --apply` then reload. "Fix all in project" -> the Task-5 project verb with the active `.dproj`, then reload open modules (or prompt a re-open). After any fix, refresh the diagnostics (re-run lint) so the tree updates.

- [ ] **Step 6: Build the BPL (RAD Studio CLOSED) + deploy.** Follow the plugin build/deploy recipe (deploy-staged.bat / the BPL project). Confirm no F2039.

- [ ] **Step 7: LIVE SMOKE (record in the task report).** Open a unit with a `redundant-parentheses` finding: (a) right-click the finding -> "Fix it" -> the parens are stripped, the buffer reloads, a `.bak` appears; (b) right-click a NON-fixable finding -> "Fix it" is greyed; (c) right-click the "Diagnostics" ROOT -> "Fix all in unit" fixes every fixable finding; (d) "Fix all in project" runs across the project. Capture what happened for each.

- [ ] **Step 8: Commit** (source + rebuilt BPL per repo convention).

```bash
git add src/delphi-plugin/DragLint.Plugin.StructureForm.pas
git commit -m "feat(autofix): IDE Fix it / Fix all on the Diagnostics tree"
```

---

### Task 8: IDE -- per-rule "auto-fix" checkbox in Lint Options

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` -- `RenderCatalog` (`:860`, per-rule row) + `Save` (`:1071`); the catalog parse to read `fixable`.

**Interfaces:**
- Consumes: catalog `fixable` (Task 2); `TLintConfig.IsAutoFix`/`AddAutoFix`/`AutoFixIds` (Task 6).
- Produces: a second checkbox per FIXABLE rule that round-trips the `autofix` array in `drag-lint-lint.json`.

> **NOT unit-testable outside the IDE.** Ends in a live smoke.

- [ ] **Step 1: Parse `fixable` in the catalog.** Wherever the frame parses `rules --json` into its rule records (`ParseCatalog`), read the new `fixable` bool onto the rule record (add a `Fixable: Boolean` field to that record type).

- [ ] **Step 2: Render the second checkbox.** In `RenderCatalog`, right after creating `RuleCB` (`:871-880`), if `Rule.Fixable`, create a second `TCheckBox` (caption `auto-fix`) positioned to the right of `RuleCB` on the same row (adjust `RuleCB.Width` to leave room; the auto-fix box anchors `[akTop, akRight]`). Set its `Checked := FCfg.IsAutoFix(Rule.Id)`. Track it in a `TDictionary<string,TCheckBox>` field `FAutoFixCBs` keyed by rule-id (mirroring how `RuleMap` tracks enable boxes) so `Save` can read it. Do NOT create the box for non-fixable rules.

- [ ] **Step 3: Save the auto-fix state.** In `Save` (`:1071`), after gathering enabled/param state, walk `FAutoFixCBs`: collect the rule-ids whose box is checked and pass them to the config via `AddAutoFix`/set the `autofix` array, then let `TLintConfigWriter` persist it (Task 6 made `autofix` round-trip). Ensure a rule toggled off is removed from the array.

- [ ] **Step 4: Build the BPL (RAD Studio CLOSED) + deploy.**

- [ ] **Step 5: LIVE SMOKE (record in the report).** Open the Lint Options tab: (a) the 3 fixable rules show a second `auto-fix` checkbox; non-fixable rules do NOT; (b) toggle `redundant-cast` auto-fix ON, Save, reopen -> it persists (check `drag-lint-lint.json` has `"autofix":["redundant-cast"]`); (c) toggle it OFF, Save -> removed from the JSON. Confirm the "Fix all in unit" from Task 7 only sweeps auto-fix-ON rules.

- [ ] **Step 6: Commit.**

```bash
git add src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas
git commit -m "feat(autofix): per-rule auto-fix checkbox in Lint Options"
```

---

### Task 9: Publish Chunk 1

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (VERSION), `CHANGELOG.md`, `docs/lint/BACKLOG.md`.

- [ ] **Step 1: Full regression battery** against the staged exe from `C:\TEMP`: `run_lint_tests.ps1` (154), store suite (16), `run_fixable_catalog.ps1`, `run_fix_single.ps1`, `run_fix_unit.ps1`, `run_fix_project.ps1`, the Task-6 config-autofix test (whichever harness it landed in), plus `run_formsmap.ps1` (33) as a shared-store sanity. Record counts.

- [ ] **Step 2: Version + CHANGELOG.** Bump `VERSION` in `src/cli/DRagLint.CLI.pas:6` (0.87.0-alpha -> 0.88.0-alpha). Add a CHANGELOG entry (Added: AutoFix Chunk 1 -- Fix it / Fix all / per-rule auto-fix + fixable catalog flag + --json). Update BACKLOG resume pointer.

- [ ] **Step 3: Pack.** `pwsh -File build\pack-lint-release.ps1 -Version 0.88.0-alpha` (builds win64+win32 Release, syncs the win64 exe, produces both zips). Confirm both zips.

- [ ] **Step 4: Final whole-branch review** (opus) over the full diff before tagging. Fix any Critical/Important.

- [ ] **Step 5: Commit + tag + push + gh release.**

```bash
git add -A && git commit -m "release: v0.88.0-alpha -- AutoFix Chunk 1 (Fix it / Fix all / per-rule setting)"
git tag -a v0.88.0-alpha -m "v0.88.0-alpha -- AutoFix Chunk 1"
git push origin main && git push origin v0.88.0-alpha
gh release create v0.88.0-alpha <win64.zip> <win32.zip> --title "..." --notes-file <notes> --latest
```

- [ ] **Step 6: Update auto-memory** (MEMORY.md + topic file) with the shipped state and the NEXT chunk (widen the fixable-rule set).

---

## After this chunk

Plan Chunk 2 (widen the fixable-rule set: each new rule = a `FIXABLE_RULE_IDS` entry + a `BuildAutofixEdits` branch + a fixture; the catalog flag, the "Fix it" item, and the auto-fix checkbox all light up automatically). Then handoff -> clear -> implement, per the usual cycle. Later: save-time auto-application; then Track 2 (AutoDocument).
