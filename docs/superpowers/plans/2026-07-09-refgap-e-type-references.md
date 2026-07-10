# Ref-gap E -- type-reference indexing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **SUPERVISION GATE: Task 2 (the core-parser change) MUST STOP and hand the exact parser diff to the USER before applying it. Do NOT edit `DRagLint.Parser.Delphi13.pas` without the user's explicit go.**

**Goal:** Index the three type-USE reference shapes the reference index currently misses (impl-header type-qualifier, local-var type annotation, `is`/`as` type-test operand), so a `type-name-prefix` autofix rename rewrites every site; then drop the now-unneeded `field-name-prefix`/`type-name-prefix` `--fix` stderr warning -- gated on a round-trip test proving the rename leaves zero stale old-name references.

**Architecture:** Three small, individually-gated `EmitRef('type_use', ...)` additions to the tree-sitter walk in `src/parser/DRagLint.Parser.Delphi13.pas`, mirroring the ref-gap D precedent (commit `81a101c`). No new ref kind, no schema change, no rename-engine change (the rename finds sites by name via `FindCallersByName`, which is kind-agnostic). A two-phase headless autotest is the gate: Phase 1 asserts the new refs are indexed; Phase 2 renames the fixture, reindexes, and asserts zero old-name refs remain ("recompiles clean" without a compiler). Only when green is the warning removed.

**Tech Stack:** Delphi 13 (RAD Studio 37), tree-sitter Delphi grammar, `ISymbolStore`/SQLite index, PowerShell autotests. CLI-only (the parser lives in the indexer/CLI). NO BPL, NO IDE.

## Global Constraints

- **Encoding:** all edited/new `.pas` + `.ps1` strict 7-bit ASCII, NO BOM, CRLF `\r\n` (including `///` DocInsight comments). `*.ps1` is governed by `.gitattributes` `text eol=crlf` (added in H3). NO em-dashes, NO smart quotes, NO Unicode.
- **DocInsight:** any new/changed public surface gets a `///` spec-comment; the new parser emit-point comments follow the ref-gap D inline-comment style (`// Ref-gap E: ...`). The parser change is internal (no public API), so no public DocInsight is added -- inline comments only.
- **TDD:** the RED test is written + run RED FIRST (Task 1), BEFORE any parser change. GREEN only after the supervised parser edit.
- **Reuse, do not reinvent:** emit `kind='type_use'` (the existing kind); do NOT add a new ref kind. Do NOT change the rename engine -- it is already kind-agnostic by name (`FindCallersByName`, verified `Storage.SQLite.pas:1954` "Match any reference kind").
- **Build (CLI Win64 Debug):** invoke the `delphi-build` skill recipe -- a 3-line wrapper .bat (rsvars -> cd -> msbuild) run via PowerShell `Start-Process -Wait` to a log, then read the log for `BUILD_EXITCODE=0` and no `[dcc] Error`. Project `src/cli/drag-lint.dproj`, `/p:Config=Debug /p:Platform=Win64`. RAD Studio being OPEN does NOT block a CLI build. If the exe is locked, kill the orphaned `drag-lint.exe` (NEVER close RAD Studio -- report BLOCKED).
- **Deploy after build:** copy the built exe to BOTH `src/cli/Win64/Debug/drag-lint.exe` AND `third_party/dll-win64/drag-lint.exe`.
- **Test invocation:** run repo tests as native pwsh: `.\tests\autotest\run_X.ps1` (NOT `powershell -File`).
- **VERIFIED facts (do not re-litigate):** the parser already emits `type_use` for `typeref` nodes UNCONDITIONALLY (`DRagLint.Parser.Delphi13.pas:1333-1338`). The rename finds sites by `name_text` via `FindCallersByName` (`Rename.pas:115`), kind-agnostic. `refs.symbol_id` is NULL (rename is name-based). Probe (2026-07-09) confirmed the 3 shapes ABSENT: for `TMyclass`, captured lines were interface decls + construction; MISSING were impl-headers, local-var type, `is` operand.

---

## File Structure

- `tests/autotest/run_type_ref_gap_e.ps1` -- NEW two-phase gate (Task 1 writes it; Task 3 turns it green).
- `src/parser/DRagLint.Parser.Delphi13.pas` -- the 3 gated `EmitRef('type_use')` additions (Task 2, SUPERVISED).
- `src/cli/DRagLint.CLI.pas` -- remove the `--fix` warning block (`:4866-4873`) + update its comment (`:4857-4865`), AFTER Task 3 is green (Task 4).
- CHANGELOG.md / README.md / docs/lint/BACKLOG.md / `.superpowers/sdd/progress.md` -- docs (Task 5).

---

## PHASE 1 -- The failing test (SAFE, no parser change)

### Task 1: Write + run RED the two-phase round-trip test

**Files:**
- Test: `tests/autotest/run_type_ref_gap_e.ps1`

**Interfaces:**
- Consumes: the deployed `drag-lint.exe` (`index`, `query find-callers`, the `type-name-prefix` autofix via `lint --fix --apply`). Model the fixture-build + Check harness on `tests/autotest/run_self_field_refs.ps1` (ref-gap D's test) and `tests/autotest/run_naming_prefix_autofix.ps1` (for the `--fix --apply` + `autofix` config wiring).
- Produces: the RED evidence that gates Task 2.

- [ ] **Step 1: Read the two model tests** to copy their exact harness idioms.

Run (Read tool, not bash): `tests/autotest/run_self_field_refs.ps1` (fixture build, index `--deep`, `find-callers --name` + assert refs at expected lines) and `tests/autotest/run_naming_prefix_autofix.ps1` (how a fixture opts into `type-name-prefix` autofix via a `drag-lint-lint.json` and drives `lint ... --fix --apply`). Note the exe-path param default and the `Write-Ascii` helper.

- [ ] **Step 2: Write `tests/autotest/run_type_ref_gap_e.ps1`**

The fixture (build fresh in a temp workdir; ASCII/CRLF via a `Write-Ascii` helper) -- a class referenced in EVERY target shape:
```pascal
unit TypeRefE;

interface

type
  TMyclass = class
  private
    FValue: Integer;
  public
    constructor Create;
    procedure Use(pParam: TMyclass);
    function Make: TMyclass;
  end;

implementation

constructor TMyclass.Create;
begin
end;

procedure TMyclass.Use(pParam: TMyclass);
var
  Local: TMyclass;
begin
  Local := TMyclass.Create;
  if pParam is TMyclass then Local.Free;
end;

function TMyclass.Make: TMyclass;
begin
  Result := TMyclass.Create;
end;

end.
```
Record the 1-based line numbers of the three target shapes AS BUILT (they depend on the exact fixture text -- compute them in the script or hard-code after building once):
- impl-header qualifiers: the `TMyclass.Create` / `TMyclass.Use` / `TMyclass.Make` implementation header lines;
- local-var type: the `Local: TMyclass;` line;
- `is` operand: the `if pParam is TMyclass` line.

Also write a fixture `drag-lint-lint.json` beside it enabling `type-name-prefix` autofix, modeled EXACTLY on `run_naming_prefix_autofix.ps1`'s config (the `autofix` array must include `type-name-prefix`).

**Phase 1 assertions (refs indexed):**
```powershell
& $exe index $work --db $db --deep | Out-Null
$refs = & $exe query find-callers --name TMyclass --db $db --json | ConvertFrom-Json
$lines = @($refs | ForEach-Object { $_.start_line })
# The three shapes the probe confirmed MISSING pre-E:
Check ($lines -contains $implHeaderLine1) "impl-header qualifier TMyclass.Create indexed (line $implHeaderLine1)"
Check ($lines -contains $localVarLine)    "local-var type Local: TMyclass indexed (line $localVarLine)"
Check ($lines -contains $isOperandLine)   "is-operand pParam is TMyclass indexed (line $isOperandLine)"
```
Assert against the ACTUAL built line numbers. (Interface decls + construction are already indexed -- do not assert those as the teeth; the teeth are the three missing shapes.)

**Phase 2 assertions (round-trip -- zero stale refs):**
```powershell
# Rename TMyclass -> TMyClass via the type-name-prefix autofix (opt-in config), --apply.
& $exe lint $work --fix --apply --db $db 2>$null | Out-Null   # match run_naming_prefix_autofix.ps1's exact invocation
# Reindex the mutated fixture, then assert NO ref/symbol still names the OLD 'TMyclass'.
& $exe index $work --db $db --deep | Out-Null
$stale = & $exe query find-callers --name TMyclass --db $db --json | ConvertFrom-Json
Check (@($stale).Count -eq 0) "zero stale 'TMyclass' refs after rename+reindex (count=$(@($stale).Count))"
$sym = & $exe query --name TMyclass --db $db --json | ConvertFrom-Json
Check (@($sym).Count -eq 0) "zero symbols still named 'TMyclass' (count=$(@($sym).Count))"
$new = & $exe query --name TMyClass --db $db --json | ConvertFrom-Json
Check (@($new).Count -ge 1) "class now resolves under new name TMyClass"
```
NOTE: the exact `type-name-prefix` casefix maps `TMyclass -> TMyClass` (capitalize the letter after the `T` prefix). Confirm the produced name by running the autofix once during authoring and asserting that name. If the autofix invocation differs (e.g. needs `--config` or a specific rule filter), copy it verbatim from `run_naming_prefix_autofix.ps1`.

End with the standard `if ($script:Failed) { 'FAIL'; exit 1 } else { 'PASS'; exit 0 }` footer. Exe-path param default `"$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"`.

- [ ] **Step 3: Run it RED**

Run: `.\tests\autotest\run_type_ref_gap_e.ps1`
Expected: FAIL. Specifically Phase 1's three shape-line checks FAIL (those refs are not indexed pre-E), and Phase 2 likely FAILs too (the rename leaves the impl-header/local/is-as sites, so a stale `TMyclass` ref survives reindex). Capture the exact RED output -- this is the gate evidence for Task 2.

- [ ] **Step 4: Commit the RED test**

```bash
git add tests/autotest/run_type_ref_gap_e.ps1
git commit -m "test(refgap-e): RED -- impl-header/local-var/is-as type refs not yet indexed (round-trip leaves stale refs)"
```
(Commit message ends with the Co-Authored-By trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.)

---

## PHASE 2 -- The SUPERVISED parser change

### Task 2: Emit `type_use` refs for the three shapes -- STOP FOR USER REVIEW FIRST

**Files:**
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas`

**Interfaces:**
- Consumes: `TWalkState.EmitRef(const AKind, ANameText: string; const ARangeNode: TTSNode)` (existing, line ~143); `NodeText`, `ChildByField`, `NodeType`, `NamedChild(i)` (existing TS helpers). The ref-gap D block at `~1348-1360` (the `exprDot` / `Self.` gate) is the style template.
- Produces: `type_use` refs at the 3 new shapes, picked up unchanged by `FindCallersByName`.

- [ ] **Step 1: Explore the live AST for the 3 shapes -- confirm node types + field names BEFORE writing any emit code.**

The parser change depends on the EXACT grammar node types/field names, which must be confirmed against the live tree, not guessed. Options: (a) find an existing debug/dump path in the parser or a test that prints node types; (b) add a temporary throwaway dump (removed before commit) that logs `NodeType` + child field names for the fixture; (c) read the grammar's node-type usage already in `DRagLint.Parser.Delphi13.pas` (grep for how method-impl headers, `declVar`, and binary `is`/`as` expressions are walked elsewhere -- e.g. `defProc`, `declVar`, the operator field on binary expressions). Determine for each shape:
- **impl-header qualifier:** which node carries the implementation routine's qualified name, and how the `Class.Method` split is represented (a `genericDot`/`exprDot`-like node with `lhs`/`rhs`? a dotted identifier?). The qualifier is the `lhs`.
- **local-var type:** whether the impl-body `declVar` node's type child is already routed through the `typeref` walk (Step 2 of emit-point 2 in the spec -- VERIFY: it may already be reached, in which case NO code is needed for this shape). Index the fixture and check whether `Local: TMyclass` (its line) is already an indexed ref BEFORE changing anything.
- **is/as operand:** the binary-expression node type and its operator field / RHS field for `is` and `as`.

Write down the confirmed node types/fields; the emit code in Step 3 uses them.

- [ ] **Step 2: STOP. Present the proposed parser diff to the USER and WAIT for explicit approval.**

This is the SUPERVISION GATE. Produce the exact minimal diff for `DRagLint.Parser.Delphi13.pas` -- the 3 gated `EmitRef('type_use', ...)` blocks (or fewer, if the local-var shape is already covered per Step 1) -- with the confirmed node types/gates, each commented `// Ref-gap E: ...` in the D style. Present it to the user WITHOUT applying it. Do NOT edit the parser file until the user says go. If dispatched as a subagent, RETURN the proposed diff + the Step-1 findings and STOP; the controller relays to the user.

- [ ] **Step 3: After the user's GO -- apply the 3 (or fewer) gated emit points.**

Each block mirrors the ref-gap D shape-gate: locate the node, verify the gate (impl-section header / operator is `is`/`as` / etc.), extract the type identifier's text + node, call `AState.EmitRef('type_use', <name>, <identNode>)`. Emit UNCONDITIONALLY (not behind `AState.EmitUsageRefs`), matching the existing `typeref` emission at line 1333. Keep each gate TIGHT (bare-identifier RHS only for is/as; qualifier only when it is the lhs of a method-impl header) to avoid over-capture. Strict ASCII/CRLF.

- [ ] **Step 4: Build CLI Win64 Debug + deploy.**

Use the delphi-build recipe (rsvars+msbuild wrapper .bat via `Start-Process -Wait`, read log). Confirm `BUILD_EXITCODE=0`, no `[dcc64] Error`. Deploy the exe to BOTH `src/cli/Win64/Debug/drag-lint.exe` and `third_party/dll-win64/drag-lint.exe`.

- [ ] **Step 5: Commit the parser change** (test still not fully green until Task 3 verifies -- but the parser edit is a self-contained commit).

```bash
git add src/parser/DRagLint.Parser.Delphi13.pas
git commit -m "fix(index): emit type_use refs for impl-header/local-var/is-as type sites (ref-gap E; gated, no over-capture)"
```
(Co-Authored-By trailer.)

---

## PHASE 3 -- Verify GREEN + over-capture check

### Task 3: Run the round-trip test GREEN + regression + over-capture diff

**Files:**
- (No source edits; verification only. If a gate over-captures, return to Task 2 Step 3 to tighten -- re-presenting the diff to the user if the parser logic changes materially.)

- [ ] **Step 1: Run `run_type_ref_gap_e.ps1` GREEN.**

Run: `.\tests\autotest\run_type_ref_gap_e.ps1`
Expected: PASS (exit 0). Phase 1's three shape lines now indexed; Phase 2's zero-stale-refs + new-name assertions hold. Capture the GREEN output.

- [ ] **Step 2: Over-capture diff check.**

Index a REAL unit (e.g. a file already in the self-index or a representative project unit) BEFORE and AFTER cannot both exist post-build, so instead: index the same real unit with the NEW exe and count `type_use` refs, and reason about the delta vs the shapes intended (impl-headers/locals/is-as). Concretely: pick a unit with known method impls + `is`/`as` uses, index it `--deep`, and spot-check that the NEW `type_use` refs correspond ONLY to real type-qualifier / type-annotation / is-as positions -- NOT to unrelated identifiers, method names, or variables. If any unintended capture appears (e.g. a variable named like a type, an `as` value-cast), STOP and tighten the gate (Task 2 Step 3; re-present to user if the logic changes).

- [ ] **Step 3: Regression battery.**

Run each (native pwsh) and confirm exit 0, zero FAIL:
`.\tests\autotest\run_self_field_refs.ps1`, `.\tests\autotest\run_bare_rhs_refs.ps1`, `.\tests\autotest\run_naming_prefix_autofix.ps1`, `.\tests\autotest\run_naming_autofix.ps1`.
These prove E did not disturb ref-gap D's `Self.` gating or the existing prefix autofixes.

- [ ] **Step 4: (No commit -- verification task.) Record the GREEN + over-capture + regression evidence** for the Task 4 gate. If everything is green, proceed to drop the warning; if not, fix before Task 4.

---

## PHASE 4 -- Drop the warning (GATED on Task 3 green)

### Task 4: Remove the field/type-prefix `--fix` warning

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (remove `:4866-4873` warning block; update comment `:4857-4865`)

**Interfaces:**
- Consumes: nothing new. This is a deletion gated on Task 3 being fully green (refs indexed + round-trip clean + no over-capture + regressions pass). Do NOT do this task if Task 3 left any red.

- [ ] **Step 1: Remove the warning emission block.**

Delete the `for F in NamingTargets do ... Writeln(ErrOutput, 'drag-lint: warning: field-name-prefix/type-name-prefix autofix may leave ...'); Break; end;` block (currently `DRagLint.CLI.pas:4866-4873`). Update the preceding comment (`:4857-4865`) to record that ref-gaps D + E now cover the Self.-field and type-reference shapes, so the warning is no longer needed (leave a one-line historical note pointing at the two ref-gap commits + this batch). Strict ASCII/CRLF.

- [ ] **Step 2: Build CLI Win64 Debug + deploy** (same recipe as Task 2 Step 4). Confirm `BUILD_EXITCODE=0`.

- [ ] **Step 3: Confirm the warning is gone.**

Run the `type-name-prefix` autofix in dry-run on a fixture with the rule opted in and confirm NO `field-name-prefix/type-name-prefix autofix may leave ...` line is written to stderr. (Reuse the Task 1 fixture + config; run `lint --fix` WITHOUT `--apply` and grep stderr for the warning text -- expect absent.)

- [ ] **Step 4: Full battery (15 + the new test).**

Run the full battery: the 15 existing tests (`run_proptree`, `run_convert_rules`, `run_convert_scaffold`, `run_info_verb`, `run_butterfly`, `run_forward_calltree`, `run_reverse_calltree`, `run_naming_presets_roundtrip`, `run_self_field_refs`, `run_bare_rhs_refs`, `run_naming_prefix_autofix`, `run_naming_autofix`, `run_deps_report`, `run_manifest`, `tests\autofix\run_fixable_catalog`) PLUS `run_type_ref_gap_e`. All exit 0, zero FAIL.

- [ ] **Step 5: Commit.**

```bash
git add src/cli/DRagLint.CLI.pas
git commit -m "feat(cli): drop the field/type-prefix --fix warning -- ref-gaps D+E now cover all rename sites"
```
(Co-Authored-By trailer.)

---

## PHASE 5 -- Docs + final review

### Task 5: Docs + ledger

**Files:**
- Modify: CHANGELOG.md, README.md (only if it documents the warning), docs/lint/BACKLOG.md, `.superpowers/sdd/progress.md`

- [ ] **Step 1: CHANGELOG** -- under `## Unreleased`, add an entry: ref-gap E indexes impl-header/local-var/is-as type references (kind=`type_use`, gated, no over-capture); the `field-name-prefix`/`type-name-prefix` `--fix` warning is now DROPPED because ref-gaps D + E cover every rename site; note the round-trip test as the gate.

- [ ] **Step 2: README** -- if it mentions the warning or the "autofix may leave references unrenamed" caveat, remove/update that line. If it does not mention it, no change (grep first).

- [ ] **Step 3: BACKLOG (docs/lint/BACKLOG.md)** -- new LATEST-41 resume block: H4 (ref-gap E) COMPLETE; the whole H1->H4 program is DONE; the `--fix` warning is retired; note remaining pending user items (Batch F/G live-IDE smoke, YADF PORT note draft). Demote LATEST-40.

- [ ] **Step 4: SDD ledger (`.superpowers/sdd/progress.md`)** -- append an H4 section (same style as the H1/H2/H3 sections) recording the supervised parser change, the 3 emit points, the round-trip gate, the warning drop, and the review verdict.

- [ ] **Step 5: Commit.**

```bash
git add CHANGELOG.md README.md docs/lint/BACKLOG.md
git commit -m "docs(refgap-e): CHANGELOG/README/BACKLOG -- ref-gap E indexed + --fix warning retired (H4 done)"
```
(Co-Authored-By trailer. `.superpowers/` is untracked -- it will not be added; that is expected.)

---

### Task 6: Final whole-branch review

- [ ] **Step 1: Whole-branch review** (requesting-code-review, most-capable model) of the H4 diff. FOCUS: (a) the 3 gates are TIGHT (no over-capture -- the review re-checks the over-capture reasoning); (b) the emit is by-name and correct for unresolved types; (c) ref-gap D's `Self.` gating is untouched; (d) the warning removal is safe (D+E genuinely cover the shapes); (e) read-only-ness of the parser change (it only emits refs, never mutates); (f) encoding. Address Critical/Important; defer Minor with a note.

- [ ] **Step 2: Close-out.** Update BACKLOG/ledger with the review verdict. This batch (H4) plus H1/H2/H3 ride the next version bump the user cuts (or its own tag). The autonomous H1->H4 program is COMPLETE; the next Track-3 step (Batch 2 apply) and the pending user smoke items remain as the follow-ons.

---

## Live/manual notes

- The parser change is CLI-only (indexer) -- NO BPL, NO IDE. A reindex is needed to see the new refs; the test reindexes its own fixture (no whole-tree reindex).
- **Optional manual smoke (NOT a battery gate):** after the round-trip test is green, rename the fixture via `type-name-prefix --apply`, then compile the renamed fixture with rsvars+dcc32 and confirm 0 errors -- a real-compiler confidence path. Documented here + in the test header; not run in CI (keeps the battery compiler-free).

---

## Self-Review notes

- **Spec coverage:** all 3 shapes (Task 2), the reuse-`type_use`-no-consumer-change decision (Task 2, verified), the two-phase round-trip test with reindex-zero-stale-refs gate + optional compile smoke (Task 1 + live notes), the warning drop gated on the test (Task 4), the SUPERVISED pause (Task 2 Step 2, and the header banner), docs (Task 5), review (Task 6). All spec sections mapped.
- **Placeholder scan:** the one genuine unknown (exact grammar node types/field names; whether impl-body local-var types are already reached) is EXPLICITLY a verify-first step (Task 2 Step 1) that must resolve before the emit code -- not a hand-waved placeholder. Line numbers in the test are computed/confirmed against the built fixture (Task 1 Step 2), not guessed.
- **Type consistency:** `EmitRef('type_use', name, node)` is the single mechanism throughout; `FindCallersByName` is the single query the test + rename both rely on; the fixture class name `TMyclass` -> `TMyClass` is consistent across Task 1's two phases.
- **Supervision:** Task 2 Step 2 is a hard STOP-for-user step, restated in the header banner and the plan's REQUIRED-SUB-SKILL line -- the parser is not edited without the user's go.
- **YAGNI:** no new ref kind, no rename-engine change, no shapes beyond the 3 named, no compiler-in-CI. Warning removal is a pure deletion gated on green.
