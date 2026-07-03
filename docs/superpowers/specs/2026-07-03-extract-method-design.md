# Extract Method -- design (refactoring-APPLY, v1)

**Status:** approved design, pre-implementation. **Milestone:** first entry on the
refactoring-APPLY frontier (`docs/lint/REFACTOR-LIST.md`). **Build box:** this Windows
machine only (RAD Studio 37; rsvars+msbuild).

## 1. Overview

Extract a contiguous run of complete statements out of a routine body into a new
`private` method (for a class method) or a new implementation-section procedure (for
a free routine), replacing the selection with a call. The transformation is
**single-file** and driven by a line range; it reuses drag-lint's existing M2
data-flow engine to classify which routine locals cross the selection boundary.

**Prime directive:** never emit non-compiling or semantics-changing code. When any
precondition is uncertain, **refuse** with a specific reason. Coverage is sacrificed
for safety, always.

## 2. Goals / non-goals

**v1 goals**
- CLI verb `extract-method` with the standard refactor workflow (`--dry-run` default /
  `--apply` / `--json` / `--no-backup`).
- Inputs -> value parameters; **exactly one** output -> function `Result`; zero outputs
  -> `procedure`. **Two or more outputs -> refuse.**
- Correct parameter types with **no type inference** (read from the existing var table's
  `TypeText`).
- Full IDE integration: editor-selection -> name prompt -> preview -> apply -> reload.
- A test harness including a **compile-verification** pass on the happy cases.

**Non-goals (v1)**
- Multiple outputs / `var`/`out` parameters (deferred to v2).
- Extracting across routine boundaries or partial statements.
- Blocks containing control flow that escapes the selection (`Exit`/`Break`/`Continue`/
  `goto`) -- refused, not rewritten.
- Any cross-unit edit (Extract Method has exactly one caller: the extraction site).

## 3. Architecture

New and reused units:

| Unit | Role |
|---|---|
| `src/refactor/DRagLint.Refactor.ExtractMethod.pas` (**new**) | `TExtractMethodRefactoring.Build` (compute the `TTextEdit` set or a refuse reason), `RenderDryRun`. The orchestrator. |
| `DRagLint.Analysis.Cfg` (reuse) | `TCfgBuilder.Build(defProc, src)` -> `TCfg` (`Blocks`/`Succ`/`Pred`, `Skipped`, `Opaque` items, `ComputePreds`). |
| `DRagLint.Analysis.DataFlow` (reuse) | `TDataFlowSolver<TArray<Boolean>>.Solve` -- the generic backward worklist solver already handles branchy routines. |
| `DRagLint.Analysis.Flow.Lattices` (reuse) | `TLiveness` (backward `IDataFlowAnalysis`), `TRoutineVarTable`/`TRoutineVar` (`Name`, `Kind`, **`TypeText`**), `CollectReadsAndCallDefs`, `AssignmentTargetIndex`, `TVarKind`. |
| `DRagLint.Refactor.TextEdit` (reuse) | `TTextEdit` + `TTextEditApplier.Apply` (back-to-front multi-location, ANSI/CRLF-preserving, `.bak`) + dry-run render. |
| `DRagLint.Refactor.Rename` (reference) | `ConflictReason` (name-collision / reserved-word check) pattern; class-declaration / header handling patterns. |
| `DRagLint.CLI` (extend) | `extract-method` verb parse + dispatch. |
| `DragLint.Plugin.Keyboard`, `DragLint.Plugin.RefactorForm` (extend) | Ctrl+Alt+M binding + selection read + preview dialog. |

**Good news from the code survey:** the "full M2 liveness" chosen for data flow is
**largely already built** -- `TLiveness` + `TDataFlowSolver` already compute per-block
live-in/live-out over the general CFG. The only new data-flow code is querying liveness
at the selection's boundary (replaying a block's transfer up to an item, the same
technique `TFreedState`/`split-variable` already use). This materially lowers engine risk.

## 4. The algorithm

Input: `file`, line range `[L1..L2]`, new method `name`.

### 4.1 Locate & validate the selection
1. Parse the file; find the enclosing `defProc` whose body span contains `[L1..L2]`
   (via `CfgFindProcs` + span containment). If none / more than one -> refuse.
2. Within the routine's statement list, resolve `[L1..L2]` to a **contiguous run of
   complete statements at one nesting level** (a sub-sequence of one statement list).
   If the range cuts a statement, or crosses a block boundary (starts in a `then`,
   ends outside; etc.) -> refuse.
3. If `TCfg.Skipped` (routine has `goto`/labels/`asm`) -> refuse.

### 4.2 Classify variables (data flow)
Build the CFG (`ComputePreds`), the var table (`TRoutineVarTable`), and solve `TLiveness`.
Only **routine locals/params** (var-table entries) can become parameters; `Self`,
fields (`FXxx`), and globals are referenced directly in the moved body and need no
parameter. For the selected region S:
- **defs(S)** = vars assigned in S (`AssignmentTargetIndex` over S's items).
- **inputs** = upward-exposed uses of S (read in S before defined in S), restricted to
  var-table entries -> **value parameters**.
- **live-out(S)** = liveness just after the last statement of S (solver block value +
  intra-block replay).
- **outputs** = `defs(S) INTERSECT live-out(S)`.
  - 0 -> `procedure`; 1 -> `function` returning it (call site `v := name(...)`); **>=2
    -> refuse** ("N values escape the selection; not extractable as one method").
- **method-internal locals** = `defs(S)` that are neither inputs nor outputs and are
  referenced only within S -> declared as locals of the new method and **moved** out of
  the enclosing routine's `var` section.
- A var that is both an input and the single output is fine: it is a value parameter
  **and** the `Result` (`v := name(..., v, ...)`).

### 4.3 Synthesize the method
- **Signature:** `procedure|function <Owner>.<name>(<in1>: <T1>; ...)[: <RT>];` with types
  from `TRoutineVar.TypeText`. If any input/output has empty `TypeText` -> refuse
  (cannot synthesize a correct signature).
- **Body:** the selected statements verbatim, re-indented, preceded by a `var` section
  for method-internal locals. For a function, the single output is `Result`.
- **Placement:**
  - *Method:* implementation inserted after the enclosing routine's `end;`; the
    declaration is inserted into the owning class's `private` section (found, or created
    if absent) -- the class declaration provides the forward visibility.
  - *Free routine:* there is no class declaration to provide visibility, so the new
    procedure's implementation is inserted **immediately before** the enclosing routine
    (its only caller), so it is declared before use. (No separate forward declaration.)
  - Name collision with an existing member/routine -> refuse (`ConflictReason`).

### 4.4 Emit edits
One `TTextEdit` set, applied by `TTextEditApplier`:
1. Replace the selection with the call statement.
2. Insert the new method implementation.
3. (methods) Insert the method declaration into the class `private` section.
4. Delete the moved-out internal-local declarations. Edge: if removing them empties the
   enclosing routine's `var` section, remove the now-dangling `var` keyword too (an empty
   `var` section is a syntax error).

## 5. Refuse preconditions (the safety net)

Selection not inside exactly one routine body; not a clean statement run (cut statement
/ crosses nesting); routine `Skipped` (`goto`/`asm`); contains `Exit`/`Break`/`Continue`/
`goto`/label escaping the selection; `>=2` outputs; an input/output has unknown type;
references a `with`-bound name (`Opaque` items -- scope ambiguity); the selection
declares a nested routine or an inline `var` used after the selection; new name collides
or is reserved. Every refusal returns a specific message (text + JSON) and a nonzero exit.

## 6. CLI

```
drag-lint extract-method --file <F> --from-line <L1> --to-line <L2> --name <N>
                         [--dry-run | --apply | --json | --no-backup]
```
- No `--db` (single-file). Default is dry-run (preview only). `--json` emits the edit set.
- Refuse reasons -> stderr, nonzero exit. Verb registered in the CLI's known-verb list
  and help.

## 7. IDE integration

- Keyboard binding **Ctrl+Alt+M** -> `InvokeExtractMethod` (mirrors the existing
  Ctrl+Alt+R rename path).
- Read the current selection's start/end rows via OTAPI (`IOTAEditView` block) and the
  active module's file name.
- Prompt for the method name; run `extract-method --dry-run`, show the preview in a
  `RefactorForm`-style memo; **Apply** runs `--apply` (with the backup checkbox) and
  then reloads the buffer (follow the rename dialog's post-apply reload pattern).
- If the selection is unusable, surface the CLI's refuse message in the dialog.

## 8. Testing

- `tests/refactor/extractmethod/` fixtures + `run_extract_method.ps1` (dry-run / `--json`
  / `--apply`, mirroring `run_rename_symbol.ps1`):
  - **happy:** procedure (0 outputs); function/Result (1 output); in+out single var;
    internal-locals moved; field/global referenced (no param emitted).
  - **refuse:** 2+ outputs; `Exit` in block; escaping `Break`; cut statement; selection
    spanning nesting; unknown type; `with`-scope; name collision.
- **Compile-verification** on the happy cases: apply into a copy, then `dcc32` it and
  assert it compiles (à la `BuildLocalTests`). This is the strongest correctness signal.
- General-CFG **liveness unit tests** in the flowengine suite (branch + loop + nested
  cases) to lock down the boundary-liveness querying.
- Catalog/self-tests unaffected (Extract Method is a verb, not a lint rule).

## 9. Key design decisions (locked in brainstorming)

1. **Target = Extract Method** -- the flagship, and the only candidate that reuses the M2
   engine drag-lint already has.
2. **Depth = in-params + single Result**; 2+ outputs refuse. Covers the common cases,
   stays correct by refusing the hard one.
3. **Surface = CLI engine + full IDE integration** in this deployment.
4. **Data flow = full M2 liveness** (general CFG). De-risked by the existing
   `TLiveness` + `TDataFlowSolver`.

## 10. Sizing & the cut line

This is a large single deployment: new refactoring unit + boundary-liveness querying +
CLI verb + IDE wiring + tests. The implementation plan will decompose it into reviewable
tasks. If it proves too big at plan time, the pre-agreed cut line is to **defer the IDE
surface (section 7) to a fast-follow** and ship the CLI engine + tests first -- flagged
explicitly, never trimmed silently.
