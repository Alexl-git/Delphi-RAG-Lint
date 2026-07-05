# forms-csv v4 Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** forms-csv resolves the plan-editor form family (Z14/Z19/~18 `TxxxPlan.EditForm` implementations) to a real path `frmMAIN -> ... -> frmControlPlan2 -> 'Plan' -> <form>` instead of "(no path from MAIN)", by bridging interface-method dispatch (index-driven) and one proc-variable hook hop (text-scan).

**Architecture:** All changes are in `src/forms/DRagLint.FormsMap.pas`, additive to the existing `BuildEdges` / `FindNearestFormCaller` / `ProcessSite` / `CaptionForHandler` machinery. Layer 1 (interface bridge) extends the existing name-based caller walk with `type_ancestors` interface awareness -- no new source scanning, all from the index. Layer 2 (hook edges) adds a bounded text-scan pre-pass for `<HookField> := <FormLaunchingRoutine>` registrations. A stderr guardrail (Layer 0) announces when the db lacks the launch bodies. `FORMS_CSV_ALGORITHM` bumps to `'4'`.

**Tech Stack:** Delphi 13 / RAD Studio 37, FireDAC over SQLite (`TSQLiteSymbolStore`), existing forms-csv test harness `tests/autotest/run_formsmap.ps1` + fixtures under `tests/fixtures/formsmap/`. Build via `build/build_draglint_win64.bat` (delphi-build skill recipe). PowerShell test harnesses.

**Spec:** `docs/superpowers/specs/2026-07-05-forms-csv-v4-hook-and-interface-navigation-design.md` -- read it first; it carries the grounded root-cause evidence (D0-D5) and the exact ORM3 examples.

## Global Constraints

- `.pas` strict 7-bit ASCII, CRLF, no BOM. DocInsight `///` on any new public declaration (these are all unit-local `function`s, so a normal `{ }` comment suffices; keep the existing comment style in FormsMap.pas).
- `.pas`/`.expected` fixture files must be CRLF (git will warn on LF; convert with a byte-rewrite if the Write tool emits LF -- the existing fixtures are CRLF).
- No index-schema change in v4 (the schema-bumping receiver-type/proc-assign work is the separate D5 milestone, explicitly out of scope here).
- Build ONLY via wrapper .bat from PowerShell `Start-Process -Wait` with a log; confirm `BUILD_EXITCODE=0` and no `[dcc] Error`. Never Bash+cmd, never the MCP build tool.
- The engine test exe must have its tree-sitter DLLs beside it: run tests against the STAGED exe `third_party\dll-win64\drag-lint.exe` (restage after each rebuild via `copy src\cli\Win64\Release\drag-lint.exe third_party\dll-win64\`), NOT the raw `src\cli\Win64\Release\drag-lint.exe` (which dies 0xC0000135 DLL-not-found).
- The formsmap harness sets `$ErrorActionPreference='Stop'` and the exe prints `(loaded defaults...)` to stderr; running it via `& $exe ... 2>&1` from a config-bearing CWD trips a NativeCommandError. Run the harness from a neutral CWD (e.g. `C:\TEMP`) OR assert the generated CSV directly (the reviewer/implementer may reproduce assertions in Python against the CSV -- see Task 1's note). Do not treat that PowerShell stderr artifact as a test failure.
- Additive-only: the existing 14 formsmap assertions MUST stay green. v4 must not change navigation for forms already resolved by plain edges.

## Existing code the tasks build on (read before starting)

- `BuildEdges` (`src/forms/DRagLint.FormsMap.pas:585`) -- outer function; contains nested `FileLines`, `TryAddEdge(AFrom, ATo, ACaption)`, `ProcessSite(...)`. `PasLines: TDictionary<Int64, TArray<string>>` caches file lines. `AClassToNode: TDictionary<string, TFormNode>` maps form class -> node.
- `ProcessSite` (`:620`) -- resolves one launch site. Non-form-launcher branch at `:685-708` calls `FindNearestFormCaller(AStore, OC, Rout, AClassToNode, PasLines, Vis2, FormCls, FormRout)` and on success `TryAddEdge(FormCls, ATargetClass, Cap)`.
- `FindNearestFormCaller` (`:509-576`) -- signature:
  `function FindNearestFormCaller(AStore: TSQLiteSymbolStore; const AOwnerClass, ARoutine: string; AClassToNode: TDictionary<string, TFormNode>; APasLines: TDictionary<Int64, TArray<string>>; AVisited: TDictionary<string, Boolean>; out AFormClass: string; out AFormRoutine: string): Boolean;`
  Queries `refs WHERE name_text = :rout AND f.language LIKE 'delphi%'`, for each hit `FindEnclosingImpl` -> (COwner, CRout); if COwner is a form node -> return it; else recurse.
- `CaptionForHandler(AStore, ANode, ARoutine, AVisited)` (`:421`) -- returns the DFM caption for a routine bound as an event handler in ANode's form, '' if none.
- `FindEnclosingImpl(ALines, ALine, out AOwnerClass, ARoutine)` (`:323`) -- text-scan of source lines to find the enclosing `class.method`.
- `FORMS_CSV_ALGORITHM = '3'` (`:70`).
- `type_ancestors` columns: `symbol_id, ordinal, ancestor_name, ancestor_kind, ancestor_symbol_id, ancestor_file_id`. Query pattern (from SQLite.pas:2804): `SELECT ordinal, ancestor_name, ancestor_kind, ancestor_symbol_id FROM type_ancestors WHERE symbol_id = :sid ORDER BY ordinal`.
- `AStore.GetConnection: TFDConnection` for ad-hoc `TFDQuery`.

---

### Task 1: Test scaffold -- interface-dispatch + hook fixtures (RED for the whole feature)

**Files:**
- Create: `tests/fixtures/formsmap/Demo.dpr` additions are NOT wanted (keep the existing 7-form fixture intact). Instead create a SECOND fixture project: `tests/fixtures/formsmap-v4/` with its own `Demo4.dpr`, `Demo4.dproj`, and units below.
- Create fixture units (all under `tests/fixtures/formsmap-v4/`):
  - `Demo4.dpr`, `Demo4.dproj` (root project; CreateForm(TfrmRoot4) then Application.Run)
  - `uRoot4.pas` + `uRoot4.dfm` (TfrmRoot4: has a button `btnPlan` Caption 'Plan' whose OnClick method calls `APlan.EditThing`)
  - `uPlanIntf4.pas` (interface `IThingPlan4` declaring `procedure EditThing;`)
  - `uPlans4.pas` (two classes implementing IThingPlan4: `TDirectPlan4.EditThing` does `TfrmDirect4.Create(nil).ShowModal`; `THookPlan4.EditThing` calls `ThingHook()` a proc-var)
  - `uDirect4.pas` + `uDirect4.dfm` (TfrmDirect4 -- editor form, Layer-1 target)
  - `uHooked4.pas` + `uHooked4.dfm` (TfrmHooked4 -- editor form, Layer-2 target)
  - `uHookReg4.pas` (registers `uPlans4.ThingHook := ShowThing4` in initialization; `ShowThing4` does `TfrmHooked4.Create(nil).ShowModal`)
- Modify: `tests/autotest/run_formsmap.ps1` -- add a second block that indexes `formsmap-v4` and asserts the v4 paths.

**Interfaces:**
- Produces: the fixture project + the harness assertions that Tasks 2-4 must turn green. No production code yet.

- [ ] **Step 1: Create the fixture units.** Mirror the real ORM3 shape minimally. Key requirement: `TfrmRoot4` must be the detected root (only CreateForm in Demo4.dpr) and reachable; its `btnPlanClick` method calls `APlan.EditThing` where `APlan: IThingPlan4`. Write each unit as compilable Object Pascal (interface + implementation + `end.`), strict ASCII/CRLF. Keep forms trivial (a TButton on TfrmRoot4 with Caption='Plan'; empty editor forms). GROUNDING: copy the structure of an existing `tests/fixtures/formsmap/uDemo*.pas` + `.dfm` pair for the DFM caption/button wiring so the `event-binding` ref is emitted the same way.

- [ ] **Step 2: Add the harness assertions** to `run_formsmap.ps1` (new block, after the existing formsmap block; use a separate `$db4`/`$out4`/`$WorkDir4`). Assert:
  - `frmDirect4` nav == `frmRoot4 -> 'Plan' -> frmDirect4` (Layer 1 + caption)
  - `frmHooked4` nav == `frmRoot4 -> 'Plan' -> frmHooked4` (Layer 1 + Layer 2 + caption)
  - the CSV still emits a footer/header per v0.86 layout (sanity)
  Write the assertions with the existing `Check` helper + regex, mirroring the existing block's style.

- [ ] **Step 3: Build + stage the current engine** (so the test runs against real v3 behavior). Wrapper bat -> `BUILD_EXITCODE=0`; `copy src\cli\Win64\Release\drag-lint.exe third_party\dll-win64\`.

- [ ] **Step 4: Run the v4 assertions -> expect FAIL (RED).** From a neutral CWD, index `formsmap-v4` into `$db4` and run forms-csv, then check the two nav assertions. Expected: both frmDirect4 and frmHooked4 show `(no path from MAIN)` (v3 can't bridge the interface). Capture this RED output in the task report. (If frmDirect4 unexpectedly already resolves, note it -- the existing `FindNearestFormCaller` may partially handle the non-interface direct case; the interface indirection is what must fail.)

- [ ] **Step 5: Commit** `test(forms-csv): v4 interface+hook navigation fixtures (RED)`.

---

### Task 2: Layer 1 -- interface-method fan-in bridge

**Files:**
- Modify: `src/forms/DRagLint.FormsMap.pas` -- add a helper `InterfaceMethodCallers` and wire it into `FindNearestFormCaller`.

**Interfaces:**
- Consumes: `type_ancestors` (via `AStore.GetConnection`), the existing `FindNearestFormCaller` recursion + `AVisited`.
- Produces: `FindNearestFormCaller` now also succeeds when the concrete method `C.M` is reached only through an interface-typed call site (`APlan.M`).

- [ ] **Step 1: Add the heritage->interface helper.** In `BuildEdges`' scope (or as a file-level function taking `AStore`), add:

```pascal
{ Returns the interface names in AClassSymbolId's heritage (type_ancestors rows
  with ancestor_kind = 'interface'). Used to bridge a concrete method to the
  interface-typed call sites that dispatch to it (v4 Layer 1). }
function HeritageInterfaces(AStore: TSQLiteSymbolStore; AClassSymbolId: Int64): TArray<string>;
var Q: TFDQuery; L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= AStore.GetConnection;
      Q.SQL.Text:= 'SELECT ancestor_name FROM type_ancestors ' +
        'WHERE symbol_id = :sid AND ancestor_kind = ''interface''';
      Q.ParamByName('sid').AsLargeInt:= AClassSymbolId;
      Q.Open;
      while not Q.Eof do begin L.Add(Q.FieldByName('ancestor_name').AsString); Q.Next; end;
    finally Q.Free; end;
    Result:= L.ToArray;
  finally L.Free; end;
end;
```

- [ ] **Step 2: Resolve a class name -> its class symbol id.** `FindNearestFormCaller` has `AOwnerClass` (a class NAME). Add a tiny lookup (reuse an existing store method if one resolves a class name to its symbol id; otherwise a `SELECT id FROM symbols WHERE name = :n AND kind = 'class' LIMIT 1`). GROUNDING: check `TSQLiteSymbolStore` for an existing name->id helper before adding a query; note which you used in the report.

- [ ] **Step 3: Diagnose the exact break with the RED fixture, THEN fix.** The existing `refs WHERE name_text = :rout` loop is NAME-only, so `APlan.EditThing` call sites already appear as `EditThing` refs and their `FindEnclosingImpl` should yield `TfrmRoot4.btnPlanClick`. So the interface bridge may be needed for a SUBTLER reason -- pin it before coding. Run `dump-refs tests/fixtures/formsmap-v4/uPlans4.pas` and `... uRoot4.pas` against `$db4` and inspect:
  - Does the launch (`TfrmDirect4.Create` inside `TDirectPlan4.EditThing`) get enclosing-attributed to `EditThing`? (expected yes)
  - When `ProcessSite` handles that launch, is `OC` = `TDirectPlan4` (a non-form class)? Then `FindNearestFormCaller('TDirectPlan4','EditThing',...)` runs. Does its `refs WHERE name_text='EditThing'` query FIND the `uRoot4` call site, and does `FindEnclosingImpl` there yield `TfrmRoot4`?
  Record the exact answer. The bridge fix is one of:
  (a) If the call site IS found and resolves to `TfrmRoot4` -> Layer 1 ALREADY works for the direct case; the RED must be caused by something else (e.g. the launch not attributed, or the form-node lookup). Fix that specific gap; the `HeritageInterfaces` helper may be unnecessary for the direct case -> keep it only if Task 3's hook path needs it, else drop it (YAGNI).
  (b) If the call site is NOT found (e.g. the interface method `IThingPlan4.EditThing` is a distinct symbol and the concrete `TDirectPlan4.EditThing` refs don't include the interface-typed callers) -> implement the bridge: in `FindNearestFormCaller`, treat ANY `refs WHERE name_text = ARoutine` hit whose `FindEnclosingImpl` resolves to a form node as a valid caller, regardless of owner class (name-based interface dispatch per spec D1). `HeritageInterfaces` is then used to justify/scope the match (only bridge when `AOwnerClass` implements an interface declaring `ARoutine`).
  Implement whichever the evidence dictates; RECORD the dump-refs output + which branch in the report.

- [ ] **Step 4: Rebuild + stage; run the v4 harness.** `frmDirect4` must now resolve to `frmRoot4 -> 'Plan' -> frmDirect4` (GREEN for Layer 1). `frmHooked4` may still be `(no path)` (Layer 2 not done). The existing 14 formsmap assertions + the real formsmap block MUST stay green.

- [ ] **Step 5: Commit** `feat(forms-csv): Layer 1 interface-method fan-in bridge (v4)`.

---

### Task 3: Layer 2 -- hook-registration text-scan + dead-end continuation

**Files:**
- Modify: `src/forms/DRagLint.FormsMap.pas` -- add a hook-registration pre-pass in `BuildEdges` and a dead-end continuation in `ProcessSite`/`FindNearestFormCaller`.

**Interfaces:**
- Consumes: the set of form-launching routines already discovered during the launch-site passes; `PasLines`; `FindNearestFormCaller`.
- Produces: a `HandlerToHook: TDictionary<string, string>` (routine name -> hook field name) consulted when fan-in dead-ends.

- [ ] **Step 1: Build the hook map (text-scan pre-pass).** In `BuildEdges`, after the launch-site passes have identified form-launching routines, scan the source lines of every indexed `.pas` for assignments of shape `<ident>.<HookField> := <Routine>` or `<HookField> := <Routine>` where `<Routine>` is a known form-launching routine name. For each match, add `HandlerToHook.Add(RoutineNameLower, HookFieldName)`. Reuse `PasLines`/`FileLines`. Keep the match strict (a `:=` with a known-launcher RHS identifier and a simple LHS) to avoid false positives. GROUNDING: get the list of `.pas` file paths from the same query BuildEdges already uses for refs, or `SELECT DISTINCT path FROM files WHERE language LIKE 'delphi%'`.

- [ ] **Step 2: Continuation on dead-end.** When `FindNearestFormCaller` (or `ProcessSite`'s non-form branch) dead-ends on a launcher routine `R` that has no form-reachable callers, look up `R` in `HandlerToHook`. If found (hook field `H`), continue fan-in by searching for `H`'s INVOCATION sites: `refs WHERE name_text = H` (the `PlanEditFormHook()` call inside `EditThing`), take each enclosing routine, and recurse through the Task-2 interface bridge. This rejoins the interface path to `frmRoot4`. Pass the `HandlerToHook` map + a visited guard down; do not loop.

- [ ] **Step 3: Rebuild + stage; run the v4 harness.** `frmHooked4` must now resolve to `frmRoot4 -> 'Plan' -> frmHooked4` (GREEN for Layer 2). Existing assertions stay green.

- [ ] **Step 4: Commit** `feat(forms-csv): Layer 2 hook-registration edges via text-scan (v4)`.

---

### Task 4: Caption + algorithm bump + Layer 0 guardrail

**Files:**
- Modify: `src/forms/DRagLint.FormsMap.pas` -- caption reuse at the bridged edge, `FORMS_CSV_ALGORITHM -> '4'`, stderr guardrail note.

**Interfaces:**
- Consumes: `CaptionForHandler`, the bridged form + its invoking method from Tasks 2-3.
- Produces: the hop caption is the DFM button label (`'Plan'`) not `(via ...)` when a caption resolves; a stderr note when interface dispatches are unresolved.

- [ ] **Step 1: Caption at the bridge.** Where Tasks 2-3 `TryAddEdge(FormCls, Target, Cap)`, ensure `Cap` comes from `CaptionForHandler(AClassToNode[FormCls], <the form method that invokes the dispatch/hook>, Vis)` with the existing `if Cap = '' then Cap := '(via ' + Rout + ')'` fallback. (Tasks 2-3 may already do this if they reuse the existing `ProcessSite` caption logic; this step verifies/threads the correct invoking method so the caption is the BUTTON, not the interface method.) The v4 fixture's `btnPlanClick` binding must yield `'Plan'`.

- [ ] **Step 2: Bump `FORMS_CSV_ALGORITHM`** from `'3'` to `'4'` (`:70`). Update the `run_formsmap.ps1` footer/provenance assertion if it pins the version string (the existing test asserts `# forms-csv algorithm v` prefix only -- confirm it does not pin `v3` exactly; if it does, update to `v4`).

- [ ] **Step 3: Layer 0 guardrail.** In `GenerateFormsCsv`, count forms that ended as `(no path from MAIN)` whose `Called From` names an interface-dispatch method with zero indexed implementing bodies in the db (i.e. the launch bodies are absent). If `> 0`, `Writeln(ErrOutput, Format('forms-csv: %d dispatch(es) unresolved -- db may not include COMMON; run against the full-tree index', [N]))`. Keep it a single stderr line; do not change the CSV. GROUNDING: a simple proxy is acceptable -- e.g. count `(no path)` forms whose Called From is nonempty but unresolved; refine only if noisy. State the exact heuristic in the report.

- [ ] **Step 4: Rebuild + stage; full v4 harness green + existing formsmap green.** Confirm the caption is `'Plan'` (not `(via ...)`), version is v4, and the guardrail line appears when run against a bodies-absent db (simulate by indexing only `uRoot4`+`uPlanIntf4` without `uPlans4`).

- [ ] **Step 5: Commit** `feat(forms-csv): 'Plan' caption at bridged edge + v4 bump + db-scope guardrail`.

---

### Task 5: Real-DB smoke + regression sweep

**Files:**
- Modify: none (verification task); optionally add a documented smoke script under `tests/` if useful.

- [ ] **Step 1: Real-DB smoke.** Against the full ORM3 db `C:\Projects\DB\ORM3\drag-lint.sqlite` (NOT the CLIENT-only db), run `forms-csv --project <ControlPlan2's .dproj or the CLIENT app .dproj> --db C:\Projects\DB\ORM3\drag-lint.sqlite --out <tmp>`. Assert `Z19slctFrm` and `Z14slctFrm` (and other `TxxxPlan.EditForm` family forms: EWrkSLCT, SmallBatch100Final, TrpsSlct, Z19OSelect) now render `frmMAIN -> ... -> frmControlPlan2 -> 'Plan' -> <form>` instead of `(no path from MAIN)`. Capture before/after (v3 staged vs v4 staged) in the report. NOTE: use a SCRATCH COPY of the db if any write path is touched; forms-csv Migrates, so copy the db first.

- [ ] **Step 2: Guardrail smoke.** Run the same forms-csv against the CLIENT-only `Micronite2027.sqlite`; confirm the stderr guardrail note fires (bodies absent) and the forms stay `(no path)` -- correct behavior for a scope-limited db.

- [ ] **Step 3: Full regression battery.** Rebuild + stage, then run the existing suites that could be touched: `run_formsmap.ps1` (existing 14 + new v4 block), plus a sanity `run_lint_tests`/`run_store_tests` (forms-csv shares the store) -- all green. Report counts.

- [ ] **Step 4: Commit** (if any doc/smoke-script added) `test(forms-csv): v4 real-DB smoke + regression evidence`. If nothing to commit, record the smoke evidence in the task report only.

---

## After this milestone

- Publish as a later release (user directive): version bump + CHANGELOG + pack + tag/gh-release, mirroring v0.86 mechanics, bundled with the already-committed header-move + live-lint fixes.
- D5 indexer milestone (receiver-type on call refs + proc-assign refs + interface-impl method edges) -- separate brainstorm -> spec -> plan; removes Layer 2's text-scan and sharpens dispatch resolution.
- Layer 0 delivery: IDE forms-csv menu passes a COMMON-inclusive db (plugin invocation change).
