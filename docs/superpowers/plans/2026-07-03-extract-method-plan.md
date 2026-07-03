# Extract Method Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single-file "Extract Method" refactoring to drag-lint -- pull a selected run of statements out of a routine into a new method, replacing the selection with a call -- exposed as a CLI verb and wired into the IDE.

**Architecture:** A new orchestrator unit (`DRagLint.Refactor.ExtractMethod`) reuses the existing M2 analysis stack (CFG + generic data-flow solver + `TLiveness` + the routine var table) to classify which routine locals cross the selection boundary, synthesizes the new method, and emits a `TTextEdit` set applied by the existing `TTextEditApplier`. A new `extract-method` CLI verb and an IDE keyboard action (Ctrl+Alt+M) drive it.

**Tech Stack:** Delphi 13 / RAD Studio 37, tree-sitter (Object Pascal grammar), the existing `src/analysis` M2 engine, `src/refactor` text-edit engine, DUnit-style console test exes + PowerShell fixture runners.

## Global Constraints

- **Source encoding:** all `.pas`/`.dfm` files are strict 7-bit ASCII, CRLF line endings. Never introduce Unicode or LF. (`TTextEditApplier` already preserves ANSI+CRLF -- do not bypass it.)
- **DocInsight comments** (`///` XML) are REQUIRED on every new public type/method (`<summary>`, `<param>`, `<returns>`, `<remarks>` for ownership/invariants).
- **Build:** this Windows box only. Build via the `delphi-build` skill recipe (rsvars + msbuild wrapper `.bat` run from PowerShell `Start-Process -Wait`, read the log for `BUILD_EXITCODE=0` and no `[dcc] Error`). CLI project: `src/cli/drag-lint.dproj` (Win64 Debug for tests; deploy the exe to `third_party/dll-win64/drag-lint.exe`).
- **Prime directive:** never emit non-compiling or semantics-changing code. Every uncertain precondition REFUSES with a specific reason (text + JSON) and a nonzero exit. Coverage is always sacrificed for safety.
- **Refactor CLI workflow (match the existing verbs):** default is dry-run (preview only); `--apply` writes (with `.bak` unless `--no-backup`); `--json` emits the edit set.
- **Spec:** `docs/superpowers/specs/2026-07-03-extract-method-design.md`. Read it before starting.

---

## File Structure

| File | Responsibility |
|---|---|
| `src/analysis/DRagLint.Analysis.Liveness.pas` (**new**) | `LiveAfterItem` -- query the live-variable set at an arbitrary CFG item boundary, on top of the general solved liveness. |
| `src/refactor/DRagLint.Refactor.ExtractMethod.pas` (**new**) | `TExtractMethodRefactoring` -- selection resolution, variable classification, method synthesis, edit emission, dry-run render. The orchestrator. |
| `src/cli/DRagLint.CLI.pas` (modify) | `extract-method` verb: arg parse + dispatch + output. |
| `src/delphi-plugin/DragLint.Plugin.Keyboard.pas` (modify) | Ctrl+Alt+M binding -> `InvokeExtractMethod`. |
| `src/delphi-plugin/DragLint.Plugin.RefactorForm.pas` (modify) | reuse/extend the preview dialog for Extract Method (name prompt + preview + apply + reload). |
| `tests/refactor/ExtractMethodTests.dpr` (**new**) | Console unit tests for the engine (classification + synthesis + refuse). |
| `tests/refactor/extractmethod/*.pas` + `run_extract_method.ps1` (**new**) | CLI fixtures (dry-run/json/apply) + compile-verification. |
| `tests/flowengine/FlowEngineTests.dpr` (modify) | Unit tests for `LiveAfterItem` (branch/loop). |
| `docs/lint/REFACTOR-LIST.md`, `CHANGELOG.md`, `src/cli/DRagLint.CLI.pas` (VERSION) | Ship. |

**Reused signatures (confirmed; do not redefine):**
- `DRagLint.Analysis.Cfg`: `TCfgBuilder.Build(const AProc: TTSNode; const ASrc: TBytes): TCfg`; `TCfg` has `Blocks: TObjectList<TCfgBlock>`, `EntryIdx`, `ExitIdx`, `Skipped`, `ComputePreds`; `TCfgBlock` has `Items: TList<TCfgItem>`, `Succ`, `Pred`; `TCfgItem = record Node: TTSNode; Opaque: Boolean; end;`; `function CfgFindProcs(const ARoot): TArray<TTSNode>`.
- `DRagLint.Analysis.DataFlow`: `TDataFlowSolver<TValue>.Solve(const ACfg; const AAnalysis: IDataFlowAnalysis<TValue>; out AIn, AOut: TArray<TValue>): Boolean`.
- `DRagLint.Analysis.Flow.Lattices`: `TVarKind = (vkLocal, vkParamVar, vkParamOut, vkParamConst, vkParamValue, vkResult)`; `TRoutineVar = record Name: string; Kind: TVarKind; TypeText: string; ... end;`; `TRoutineVarTable` (build for a `defProc`; indexable, `Count`, `Get(i): TRoutineVar`); `TLiveness` (a backward `IDataFlowAnalysis<TArray<Boolean>>` keyed by var-table index); `procedure CollectReadsAndCallDefs(const ANode; const ASrc; AVars: TRoutineVarTable; AReads, ACallDefs: TList<Integer>)`; `function AssignmentTargetIndex(const ANode; const ASrc; AVars: TRoutineVarTable): Integer` (whole-identifier lhs -> var index, else -1).
- `DRagLint.Refactor.TextEdit`: `TTextEdit` (`FilePath`, `Kind` in {`tekInsertInLine`,`tekInsertLines`,`tekDeleteLines`,`tekReplaceInLine`}, `Line`, `Col`, `EndLine`, `EndCol`, `Text`); `TTextEditApplier.Apply(const AEdits: TArray<TTextEdit>; ABackup: Boolean): TArray<string>`; `TTextEditApplier.RenderDryRun(const AEdits): string`.
- `DRagLint.Refactor.Rename`: `TRenameRefactoring.ConflictReason(...)` (name reserved / sibling collision -> reason or '') and `BuildLocal` (the canonical routine-subtree AST walk -- **read this before Task 2/3**).

**Grounding rule for AST steps:** where a step walks tree-sitter nodes (statement lists, `var` sections, class `private` sections), first read the analogous existing walk and mirror its node-type/field usage. Do NOT invent grammar node names. Canonical references: `TRenameRefactoring.BuildLocal` (routine subtree + declArgs/declVars) and `TCfgBuilder.Build` in `DRagLint.Analysis.Cfg.pas` (statement decomposition).

---

### Task 1: Boundary-liveness helper (M2 core)

**Files:**
- Create: `src/analysis/DRagLint.Analysis.Liveness.pas`
- Test: `tests/flowengine/FlowEngineTests.dpr` (add cases)

**Interfaces:**
- Consumes: `TCfg`, `TDataFlowSolver<TArray<Boolean>>.Solve`, `TLiveness`, `TRoutineVarTable`, `CollectReadsAndCallDefs`, `AssignmentTargetIndex`.
- Produces: `function LiveAfterItem(const ACfg: TCfg; AVars: TRoutineVarTable; const ASrc: TBytes; ABlockIdx, AItemIdx: Integer): TArray<Boolean>;` -- the set of live var-table indices immediately AFTER item `AItemIdx` of block `ABlockIdx`. Also `function LiveBeforeItem(...)` (same, before the item) for selection entry.

**Background:** liveness is backward. The solver gives per-block `AOut[b]` (live at block exit) and `AIn[b]` (live at block entry). `LiveAfterItem(b, k)` = start from `AOut[b]` and apply the per-item backward transfer for items `Count-1 .. k+1`; the per-item transfer is `live_before(i) = uses(i) OR (live_after(i) AND NOT defs(i))`, computed with `AssignmentTargetIndex` (the killed def) + `CollectReadsAndCallDefs` (the uses), exactly as `split-variable` does inside `FlowChecks.pas` (read that block first). Opaque items (`with`) use everything: OR in all locals.

- [ ] **Step 1: Read the reference implementations.** Read the `split-variable` block in `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas` (its backward `LiveNow`/`LiveAfter` sweep) and `TLiveness` in `src/analysis/DRagLint.Analysis.Flow.Lattices.pas`. Confirm the per-item transfer order (kill def, then add reads) and the Opaque handling.

- [ ] **Step 2: Write the failing test.** In `FlowEngineTests.dpr` add a test that builds a CFG for a branchy routine and asserts liveness at an item boundary. Fixture routine (embed as a string parsed via the existing test harness helper -- mirror how FlowEngineTests builds a CFG from source):

```pascal
// routine under test:
//   procedure P(a: Integer);
//   var x, y: Integer;
//   begin
//     x := a;           // item 0
//     if a > 0 then     // branch
//       y := x          // item in a branch block
//     else
//       y := 0;
//     Writeln(y);       // last item: y live-in, x dead
//   end;
// Assert: LiveAfterItem(at 'x := a') includes x (x used on some path), excludes y.
// Assert: LiveAfterItem(at the merge, after 'Writeln(y)') excludes both.
```

Assert the boolean array at the chosen item matches the expected live set (map names via the var table).

- [ ] **Step 3: Run it to verify it fails.** Run the flowengine runner: `pwsh -File tests\flowengine\run_flowengine_tests.ps1`. Expected: the new case FAILs (unit/function not found).

- [ ] **Step 4: Implement `LiveAfterItem`/`LiveBeforeItem`.** In the new unit: solve `TLiveness` once (`TDataFlowSolver<TArray<Boolean>>.Solve`), then replay the per-item backward transfer within the target block from `AOut[block]` down to the target item. Reuse `AssignmentTargetIndex` + `CollectReadsAndCallDefs`; handle Opaque by OR-ing all local indices. Return a copy (never alias the solver arrays). DocInsight the two functions.

- [ ] **Step 5: Run it to verify it passes.** Run: `pwsh -File tests\flowengine\run_flowengine_tests.ps1`. Expected: all cases PASS (33 prior + the new ones).

- [ ] **Step 6: Commit.**

```bash
git add src/analysis/DRagLint.Analysis.Liveness.pas tests/flowengine/FlowEngineTests.dpr
git commit -m "feat(analysis): boundary-liveness helper (LiveAfterItem/LiveBeforeItem)"
```

---

### Task 2: Selection resolution + refuse guards

**Files:**
- Create: `src/refactor/DRagLint.Refactor.ExtractMethod.pas` (skeleton + resolution)
- Create: `tests/refactor/ExtractMethodTests.dpr`
- Test runner: `tests/refactor/run_extractmethod_unit_tests.ps1` (mirror `run_buildlocal_tests.ps1`)

**Interfaces:**
- Consumes: `TCfgBuilder.Build`, `CfgFindProcs`, `TCfg.Skipped`.
- Produces:
```pascal
type
  TExtractOutcome = (eoOK, eoRefused);
  TExtractSelection = record
    Proc      : TTSNode;   // enclosing defProc
    IsMethod  : Boolean;   // true if Proc is a class method (has a qualified name)
    OwnerClass: string;    // class name if IsMethod
    FirstItem, LastItem: Integer;  // indices into the flattened statement run
    StartLine, StartCol, EndLine, EndCol: Integer; // byte span of the run
  end;
  // Main entry (filled out across Tasks 2-4):
  TExtractMethodRefactoring = class
    class function Build(const AFile: string; AFromLine, AToLine: Integer;
      const ANewName: string; out ARefuse: string): TArray<TTextEdit>;
    class function RenderDryRun(const AEdits: TArray<TTextEdit>): string;
  end;
```
`Build` returns `nil` + a non-empty `ARefuse` on refusal; a non-empty edit array + empty `ARefuse` on success.

- [ ] **Step 1: Read `TRenameRefactoring.BuildLocal`** in `src/refactor/DRagLint.Refactor.Rename.pas` to learn the routine-subtree walk, the statement-list node type, and how it maps (line,col) to nodes. Mirror it here.

- [ ] **Step 2: Write failing refuse tests** in `ExtractMethodTests.dpr` (parse an embedded fixture, call `Build`, assert `ARefuse` matches). Cases: (a) range spans two routines -> refuse "selection is not inside a single routine"; (b) range cuts a statement -> refuse "selection must be whole statements"; (c) routine has `goto` (`TCfg.Skipped`) -> refuse "routine uses goto/asm"; (d) range contains `Exit` -> refuse "selection contains Exit"; (e) `Break` that escapes -> refuse; (f) range crosses nesting (starts in a `then`) -> refuse. Each asserts a substring of the refuse reason.

- [ ] **Step 3: Run to verify fail.** Run: `pwsh -File tests\refactor\run_extractmethod_unit_tests.ps1`. Expected: FAIL (unit missing).

- [ ] **Step 4: Implement resolution + guards.** In `Build`: parse via the AST cache; `CfgFindProcs` + span containment to find the unique enclosing `defProc` (else refuse); build the CFG, `ComputePreds`; if `Skipped` refuse. Flatten the enclosing statement list; map `[AFromLine..AToLine]` to a contiguous complete-statement run at one nesting level (else refuse: cut / crosses nesting). Scan the run for escaping control flow (`Exit`, `goto`, label, and `Break`/`Continue` not enclosed by a loop *within* the run) and Opaque/`with` items -> refuse. Set `IsMethod`/`OwnerClass` from the `defProc` header (qualified name). Return refuse for now on success paths (`ARefuse := 'not-yet-implemented'`) so only refuse tests pass. DocInsight all public members.

- [ ] **Step 5: Run to verify the refuse tests pass.** Run: `pwsh -File tests\refactor\run_extractmethod_unit_tests.ps1`. Expected: the 6 refuse cases PASS.

- [ ] **Step 6: Commit.**

```bash
git add src/refactor/DRagLint.Refactor.ExtractMethod.pas tests/refactor/ExtractMethodTests.dpr tests/refactor/run_extractmethod_unit_tests.ps1
git commit -m "feat(refactor): extract-method selection resolution + refuse guards"
```

---

### Task 3: Variable classification

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.ExtractMethod.pas`
- Modify: `tests/refactor/ExtractMethodTests.dpr`

**Interfaces:**
- Consumes: `TRoutineVarTable`, `LiveAfterItem`/`LiveBeforeItem` (Task 1), `CollectReadsAndCallDefs`, `AssignmentTargetIndex`, `TRoutineVar.TypeText`.
- Produces (internal, used by Task 4):
```pascal
type
  TExtractVars = record
    Inputs   : TArray<Integer>;  // var-table indices -> value params (in run order of first use)
    OutputIdx: Integer;          // single output var-table index, or -1
    Internals: TArray<Integer>;  // defined-in-run, not input, not output -> new-method locals
    OutputIsInput: Boolean;      // output var is also an input (in+out single var)
    Refuse   : string;           // '' if OK; else why (>=2 outputs / unknown type)
  end;
  class function ClassifyVars(const ASel: TExtractSelection; ACfg: TCfg;
    AVars: TRoutineVarTable; const ASrc: TBytes): TExtractVars;
```

- [ ] **Step 1: Write failing classification tests.** Fixtures: (a) block reading `a`, computing local `t`, no live-after -> Inputs={a}, OutputIdx=-1, Internals={t}; (b) block computing `sum` used after -> OutputIdx=sum, Inputs may be {}; (c) `x := x + d` where x live after and read before -> OutputIdx=x, OutputIsInput=true, Inputs contains x and d; (d) two vars live after -> Refuse "2 values escape"; (e) an input whose `TypeText` is '' -> Refuse "unknown type". Assert the record fields.

- [ ] **Step 2: Run to verify fail.** Run the unit runner. Expected: FAIL.

- [ ] **Step 3: Implement `ClassifyVars`.** Compute over the run's items: `defs` (via `AssignmentTargetIndex`), upward-exposed uses (read before defined within the run -> Inputs, restricted to var-table entries), and `live-out = LiveAfterItem(lastItem)`. Outputs = defs INTERSECT live-out. If `Length(Outputs) >= 2` -> Refuse. `OutputIdx` = the single output or -1; `OutputIsInput` = output in Inputs. Internals = defs minus Inputs minus {OutputIdx} that are referenced only within the run (verify no use outside via a routine-wide scan). Reject if any Input or the Output has empty `TypeText`. Skip `Self`/field/global identifiers (not in the var table) -- they need no param. DocInsight.

- [ ] **Step 4: Run to verify pass.** Run the unit runner. Expected: classification cases PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/refactor/DRagLint.Refactor.ExtractMethod.pas tests/refactor/ExtractMethodTests.dpr
git commit -m "feat(refactor): extract-method variable classification (in/out/internal via M2 liveness)"
```

---

### Task 4: Method synthesis + edit emission

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.ExtractMethod.pas`
- Modify: `tests/refactor/ExtractMethodTests.dpr`

**Interfaces:**
- Consumes: `TExtractSelection`, `TExtractVars`, `TRoutineVar` (Name/TypeText), `TTextEdit`, `TRenameRefactoring.ConflictReason`.
- Produces: the completed `TExtractMethodRefactoring.Build` (returns the full `TArray<TTextEdit>`).

- [ ] **Step 1: Read** `TTextEditApplier` in `src/refactor/DRagLint.Refactor.TextEdit.pas` (edit kinds + line/col semantics) and how `BuildLocal` locates the `var` section + class declaration, so insertion points use real node fields.

- [ ] **Step 2: Write failing synthesis tests.** For each happy fixture, assert the resulting edited source (apply the returned edits in-memory) equals an expected `.pas` string: (a) 0-output procedure extraction; (b) 1-output function returning Result, call site `v := N(...)`; (c) in+out single var `v := N(v, ...)`; (d) internal local moved into the new method's `var` and removed from the original; (e) name collision -> `Build` refuses via `ConflictReason`. Include one free-routine fixture asserting the new proc is inserted BEFORE the caller.

- [ ] **Step 3: Run to verify fail.** Expected: FAIL.

- [ ] **Step 4: Implement synthesis + edits.** Signature: `procedure|function <Owner>.<Name>(<in>: <Type>; ...)[: <RType>];` from `TRoutineVar.TypeText`; function iff `OutputIdx >= 0` with `RType` = output's type. Body = the run's source text (re-indented) preceded by a `var` block for Internals; for a function the output var is written to `Result` (rename the output var to `Result` inside the body, or append `Result := <out>;`). Emit edits: (1) `tekReplaceInLine`/`tekDeleteLines`+insert -- replace the run with the call (`N(args);` or `v := N(args);`); (2) insert the implementation (method: after enclosing `end;`; free routine: immediately before the enclosing routine); (3) method: insert the declaration into the class `private` section (find it or create one -- mirror the class-decl location logic; if none, refuse rather than guess); (4) delete moved Internals' declarations, and if that empties the `var` section, delete the `var` keyword too. Call `ConflictReason` on `ANewName`; refuse on conflict. DocInsight.

- [ ] **Step 5: Run to verify pass.** Run the unit runner. Expected: all happy + collision cases PASS.

- [ ] **Step 6: Commit.**

```bash
git add src/refactor/DRagLint.Refactor.ExtractMethod.pas tests/refactor/ExtractMethodTests.dpr
git commit -m "feat(refactor): extract-method synthesis + TextEdit emission"
```

---

### Task 5: CLI verb + end-to-end + compile-verification

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas`
- Create: `tests/refactor/extractmethod/*.pas` (+ `.expected` where useful), `tests/refactor/run_extract_method.ps1`

**Interfaces:**
- Consumes: `TExtractMethodRefactoring.Build/RenderDryRun`, `TTextEditApplier.Apply`.
- Produces: CLI verb `extract-method --file <F> --from-line <L1> --to-line <L2> --name <N> [--dry-run|--apply|--json|--no-backup]`.

- [ ] **Step 1: Read an existing refactor verb dispatch** (the `rename` / `safe-delete` verb handler in `DRagLint.CLI.pas`) to mirror arg parsing, the `--dry-run`/`--apply`/`--json`/`--no-backup` handling, backup + output, exit codes, and the known-verb/help registration.

- [ ] **Step 2: Write the failing e2e test** `run_extract_method.ps1` (mirror `run_rename_symbol.ps1`): copy a fixture to a temp file, run `extract-method --from-line --to-line --name --dry-run` and assert the preview contains the new signature; run `--json` and assert a parseable edit array; run `--apply` and assert the file now contains the call + the new method; run a refuse fixture and assert nonzero exit + the reason. **Compile-verification:** after `--apply`, compile the result with `dcc32`/`dcc64` (mirror `run_buildlocal_tests.ps1`) and assert it builds.

- [ ] **Step 3: Run to verify fail.** Run: `pwsh -File tests\refactor\run_extract_method.ps1`. Expected: FAIL ("unknown verb extract-method").

- [ ] **Step 4: Implement the verb.** Add `extract-method` to the verb dispatch, parse the flags, call `Build`; on refuse print the reason to stderr and exit nonzero; else print `RenderDryRun` (default/`--dry-run`), or the JSON edit set (`--json`), or apply via `TTextEditApplier.Apply` (`--apply`, backup unless `--no-backup`) and report touched files. Register in the known-verb list + help text.

- [ ] **Step 5: Build + deploy + run.** Build Win64 Debug (`delphi-build` recipe) -> deploy to `third_party\dll-win64\drag-lint.exe`. Run: `pwsh -File tests\refactor\run_extract_method.ps1`. Expected: PASS including compile-verification. Also run the full refactor + lint suites to confirm no regression.

- [ ] **Step 6: Commit.**

```bash
git add src/cli/DRagLint.CLI.pas tests/refactor/extractmethod tests/refactor/run_extract_method.ps1
git commit -m "feat(cli): extract-method verb + end-to-end + compile-verified tests"
```

---

### Task 6: IDE integration

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Keyboard.pas`
- Modify: `src/delphi-plugin/DragLint.Plugin.RefactorForm.pas`

**Interfaces:**
- Consumes: OTAPI (`IOTAEditView` selection block, active module file name), the `extract-method` CLI verb (subprocess, like the rename dialog).
- Produces: Ctrl+Alt+M editor action -> preview dialog -> apply -> reload.

- [ ] **Step 1: Read the rename IDE path** -- `InvokeRename` in `DragLint.Plugin.Keyboard.pas` and `ShowRefactorDialog` in `DragLint.Plugin.RefactorForm.pas` -- to mirror the binding, subprocess spawn, preview memo, Apply, and post-apply reload.

- [ ] **Step 2: Add the binding + selection read.** Add Ctrl+Alt+M -> `InvokeExtractMethod`. Read the current `IOTAEditView` block start/end rows and the active module's file name. If there is no non-empty selection, show a message and stop. (No automated IDE test -- the plugin loads only in RAD Studio; verify manually in Step 4.)

- [ ] **Step 3: Wire the dialog.** Prompt for the method name; spawn `drag-lint.exe extract-method --file <F> --from-line <r1> --to-line <r2> --name <N> --dry-run`, show output in the preview memo; **Apply** re-spawns with `--apply` (honor the backup checkbox); on success, reload the buffer (mirror the rename dialog's reload). Surface a refuse reason in the memo.

- [ ] **Step 4: Manual verification.** Build the IDE package (`delphi-build`, Win32; deploy BPLs with RAD Studio closed via `deploy-staged.bat`), open a sample unit, select a statement block, press Ctrl+Alt+M, confirm preview + apply + the file updates and compiles. Record the result in the commit message.

- [ ] **Step 5: Commit.**

```bash
git add src/delphi-plugin/DragLint.Plugin.Keyboard.pas src/delphi-plugin/DragLint.Plugin.RefactorForm.pas
git commit -m "feat(ide): Ctrl+Alt+M Extract Method (selection -> preview -> apply -> reload)"
```

---

### Task 7: Ship (docs + release)

**Files:**
- Modify: `docs/lint/REFACTOR-LIST.md`, `CHANGELOG.md`, `src/cli/DRagLint.CLI.pas` (VERSION)

- [ ] **Step 1: Flip the tracker.** In `REFACTOR-LIST.md` move Extract Method from `[~]` to `[x]` (note: CLI + IDE, v1 = in-params + single Result).

- [ ] **Step 2: CHANGELOG + VERSION.** Add a `## v0.84.0-alpha` section (Extract Method: CLI verb + IDE, single-file, in-params + single Result, refuses on 2+ outputs / escaping control flow / unknown type). Bump `VERSION` `CLI.pas:6` `0.83.0-alpha -> 0.84.0-alpha` (no index-schema change).

- [ ] **Step 3: Full verification.** Build Win64 Debug + deploy; run lint / store / catalog / flowengine / refactor suites -- all green. Build Win32 + Win64 **Release**; package the two zips (mirror the v0.83 release: exe + 3 tree-sitter DLLs + docs + `rules/`, 123 files).

- [ ] **Step 4: Commit, tag, release.**

```bash
git add -A && git commit -m "chore(release): v0.84.0-alpha -- Extract Method (refactoring-APPLY)"
git tag -a v0.84.0-alpha -m "v0.84.0-alpha -- Extract Method"
git push origin main && git push origin v0.84.0-alpha
gh release create v0.84.0-alpha --title "v0.84.0-alpha -- Extract Method" --notes-file <notes> --latest <win64.zip> <win32.zip>
```

- [ ] **Step 5: Update auto-memory + BACKLOG** RESUME block to v0.84 shipped; next refactor target = Change Signature (per `REFACTOR-LIST.md`).

---

## Notes for the executor

- **If oversized:** the pre-agreed cut line (from the spec) is to ship Tasks 1-5 + 7 (CLI engine, tested + released) and defer Task 6 (IDE) to a fast-follow. Flag it; do not trim silently.
- **Order matters:** Tasks 1->4 are a strict dependency chain (each unit-tested in isolation). Task 5 makes it usable; Task 6 is additive; Task 7 ships.
- **Reindex** the self-index after the symbol-adding build if you will query it (incremental, only the changed unit).
