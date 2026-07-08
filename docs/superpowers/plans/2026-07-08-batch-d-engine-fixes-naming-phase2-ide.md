# Batch D Implementation Plan -- engine fixes (A/B/C) + naming autofix phase 2 + IDE items + cleanups

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear the three pre-existing engine findings Batch C filed (A/B/C), ship naming autofix phase 2 (prefix-adding), two small cleanups, a naming-presets combo, a reverse-calltree IDE right-click, and a dock focus-stealing fix.

**Architecture:** Eight tasks, one phased plan. Phase 1 (Tasks 1-4) is headless engine/CLI, TDD. Phase 2 (Tasks 5-9) is IDE-only (BPL build + live smoke, no headless UI tests), landing before ONE final Win32 BPL build. Every task reuses an existing surface; no new engines.

**Tech Stack:** Delphi 13 (Studio 37), Win64 (CLI), Win32 (plugin BPL), tree-sitter parse, FireDAC/SQLite index, PowerShell autotest batteries. Spec: `docs/superpowers/specs/2026-07-08-batch-d-engine-fixes-naming-phase2-ide-design.md`.

## Global Constraints

- **Encoding (all `.pas`/`.dfm`/`.dpr`/`.dproj`/`.dpk`):** strict 7-bit ASCII, no BOM, CRLF. DocInsight comments ASCII. Never introduce Unicode or LF.
- **DocInsight (CDD):** every new/changed public type/function gets `///` `<summary>` (+ `<param>`/`<returns>`/`<remarks>` as apt). Comment and test agree.
- **TDD** for Phase 1 (Tasks 1-4): failing test first, then green. Phase 2 (Tasks 5-9) is NOT headless-testable -- build gate + live smoke only; do NOT fabricate UI tests.
- **Build:** `delphi-build` skill recipe (rsvars + msbuild via `Start-Process cmd.exe -Wait` + log; `BUILD_EXITCODE=0`, no `[dcc] Error`). CLI = `src/cli/drag-lint.dproj` Win64; plugin = `src/delphi-plugin/dclDragLintWizard.dproj` Win32, RAD Studio (`bds.exe`) CLOSED (`Get-Process bds` empty). Deploy CLI Win64 -> `third_party/dll-win64/drag-lint.exe`; BPL auto-deploys to `third_party/dll-win32/`.
- **Dependencies:** Task 1 (C) precedes Task 3 (phase 2); Task 2 (A) precedes Task 3. Task 4 (B) is independent. Phase 2 IDE tasks (5-9) are independent of each other; all land before the final BPL build (Task 10).
- **Commit cadence:** one source commit per task; the final BPL/DCP in a `build(plugin):` commit.
- **Self-lint noise:** the drag-lint self-lint reports false-positive "errors" on literal braces/brackets inside `{ }` comments and `'\'` char literals; the REAL `dcc` compiler is the gate, not the self-lint.
- **Release:** rides the next version bump (likely v0.97.0-alpha); user drives push/tag/release.

---

# PHASE 1 -- Engine / CLI (headless-testable)

## Task 1 (C): TTextEditApplier same-line column tiebreak

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.TextEdit.pas:106-108` (the `Apply` comparer)
- Test: `tests/autotest/run_textedit_sameline.ps1`

**Interfaces:**
- Produces: no signature change -- `TTextEditApplier.Apply` now orders same-line edits by column DESC (larger column first) so a later same-line edit's offset is not invalidated by an earlier one on the same line.

- [ ] **Step 1: Write the failing test**

Create `tests/autotest/run_textedit_sameline.ps1`. Since `TTextEditApplier` has no CLI verb, drive it through a feature that produces two same-line differing-length edits: the naming autofix does not yet do prefix-adding (Task 3), so test via a small console harness that constructs two `tekReplaceInLine` edits on one line with DIFFERENT replacement lengths and applies them. Mirror `run_dbresolver_probe.ps1`'s harness pattern (a `.dpr` built with dcc64 via the rsvars wrapper).
`tests/autotest/fixtures/textedit/SameLineHarness.dpr`:
```pascal
program SameLineHarness;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, DRagLint.Refactor.TextEdit;
var
  Edits: TArray<TTextEdit>;
  E1, E2: TTextEdit;
  Path: string;
begin
  // Build a one-line fixture: "  a := b;"  (cols 1-based)
  Path := TPath.Combine(TPath.GetTempPath, 'sameline_fixture.pas');
  TFile.WriteAllText(Path, '  aa := bb;' + sLineBreak, TEncoding.ANSI);
  // Two replaces on line 1, differing lengths: 'aa'->'FIRST' (col 3..5), 'bb'->'X' (col 9..11)
  E1 := Default(TTextEdit); E1.FilePath := Path; E1.Kind := tekReplaceInLine; E1.Line := 1; E1.Col := 3;  E1.EndCol := 5;  E1.Text := 'FIRST';
  E2 := Default(TTextEdit); E2.FilePath := Path; E2.Kind := tekReplaceInLine; E2.Line := 1; E2.Col := 9;  E2.EndCol := 11; E2.Text := 'X';
  Edits := [E1, E2];
  TTextEditApplier.Apply(Edits, False);
  Writeln(Trim(TFile.ReadAllText(Path)));  // expect: FIRST := X;
end.
```
The `.ps1` builds the harness (dcc64, `-U` search path incl. `src/refactor` + `src/core` + deps, `-NS"System"`), runs it, asserts output = `FIRST := X;`.

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh tests/autotest/run_textedit_sameline.ps1`
Expected: FAIL -- with line-only sort the two same-line edits compare equal, so `TList.Sort` keeps their input order (`[E1, E2]` = left col 3 first). Applying the left edit first (`aa`->`FIRST`, +3 chars) shifts the line so the right edit's stored columns (9..11) now point past `bb` -> corrupted output (not `FIRST := X;`). The input order `[E1, E2]` in the harness makes this deterministic, not luck-dependent: left-first same-line application is exactly the bug. (After the fix, the comparer reorders to right-first regardless of input order.)

- [ ] **Step 3: Add the column-DESC tiebreak**

In `src/refactor/DRagLint.Refactor.TextEdit.pas`, change the comparer at line 107-108:
```pascal
      Cmp:= TComparer<TTextEdit>.Construct(
        function(const A, B: TTextEdit): Integer
        begin
          Result:= EditTopLine(B) - EditTopLine(A);
          if Result = 0 then Result:= B.Col - A.Col; // same line: larger column first (back-to-front)
        end);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh tests/autotest/run_textedit_sameline.ps1`
Expected: PASS -- output `FIRST := X;` (right edit applied first, left edit's columns still valid).

- [ ] **Step 5: Commit**

```bash
git add src/refactor/DRagLint.Refactor.TextEdit.pas tests/autotest/run_textedit_sameline.ps1 tests/autotest/fixtures/textedit/SameLineHarness.dpr
git commit -m "fix(textedit): order same-line edits by column DESC (back-to-front apply, unblocks prefix-adding)"
```

## Task 2 (A): promote impl-header rename into TRenameRefactoring.Build

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.Rename.pas` (`Build`, ~line 104-130 -- add the impl-header edit)
- Modify: `src/refactor/DRagLint.Refactor.NamingFix.pas` (remove `BuildImplHeaderEdit` + its call at 303-307; the method path now gets the impl header from `Build`)
- Test: `tests/autotest/run_rename_implheader.ps1` (standalone `rename` verb renames the impl header)

**Interfaces:**
- Consumes: `TSymbol.ImplStartLine`/`ImplEndLine` (`src/core/DRagLint.Core.Model.pas:75-76`), `AStore.GetFilePath(Sym.FileId)`.
- Produces: `TRenameRefactoring.Build` now also emits a `TRenameEdit` for the method's implementation header (`Type.Name` on `ImplStartLine`) when `ImplStartLine > 0` and `<> StartLine`. No signature change.

**Scope note (IMPORTANT -- keep A minimal):** A promotes ONLY the impl-header edit (the filed bug). Do NOT change `Build`'s declaration-site column behavior. NamingFix's `EmitRenameEdits` has a separate "same-line finding column override" (NamingFix.pas:229-238) that compensates for `Build`'s decl edit using the keyword column -- that override is a NamingFix concern, NOT part of this bug; leave it untouched. After A, NamingFix drops only `BuildImplHeaderEdit` + the call at 303-307; its override logic stays.

- [ ] **Step 1: Write the failing test**

Create `tests/autotest/run_rename_implheader.ps1`. Fixture: a unit with a class method declared in `interface` and defined in `implementation`, with a call site. Index it, run the standalone `rename` verb (`drag-lint rename --qname <Unit.TClass.Method> --to <NewName> --db <db> --apply`), then assert the implementation header `procedure TClass.NewName;` was renamed (not left as `TClass.OldName`). Follow `run_deps_report.ps1` scaffolding.
```powershell
# Fixture unit u1.pas:
#   type TThing = class procedure DoIt; end;   (interface)
#   procedure TThing.DoIt; begin end;          (implementation)  <- the impl header
#   ... a call site: var t: TThing; ... t.DoIt;
# rename --qname u1.TThing.DoIt --to DoItNow --apply
# ASSERT: interface 'procedure DoItNow;' AND impl 'procedure TThing.DoItNow;' AND call 't.DoItNow;'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh tests/autotest/run_rename_implheader.ps1`
Expected: FAIL -- the impl header stays `TThing.DoIt` (interface + call rename, impl header missed).

- [ ] **Step 3: Add the impl-header edit to Build**

In `src/refactor/DRagLint.Refactor.Rename.pas`, after the reference-sites loop (after line 124, before the sort at 126-128), add an impl-header edit modeled on `NamingFix.BuildImplHeaderEdit` but emitting a `TRenameEdit` (Build's `Apply` does its own forward-scan token match, so `Col` need only be near the identifier; the scan finds the exact token):
```pascal
    // Implementation-section header (procedure TFoo.Bar;) -- NOT a decl symbol nor
    // a refs row, so neither branch above catches it. Emit it explicitly when the
    // symbol has a separate impl body (ImplStartLine > 0 and <> the decl line).
    if (Sym.ImplStartLine > 0) and (Sym.ImplStartLine <> Sym.StartLine) then
    begin
      var ImplPath: string := AStore.GetFilePath(Sym.FileId);
      if TFile.Exists(ImplPath) then
      begin
        var ILines := TStringList.Create;
        try
          ILines.Text := TEncoding.ANSI.GetString(TFile.ReadAllBytes(ImplPath));
          if Sym.ImplStartLine <= ILines.Count then
          begin
            var LnText := ILines[Sym.ImplStartLine - 1];
            // find ShortName preceded by '.' (the dotted Type.Name member shape)
            var ScanAt := 1;
            while ScanAt + Length(ShortName) - 1 <= Length(LnText) do
            begin
              if SameText(Copy(LnText, ScanAt, Length(ShortName)), ShortName)
                 and (ScanAt >= 2) and (LnText[ScanAt - 1] = '.') then
              begin
                Edit.FilePath := ImplPath;
                Edit.Line     := Sym.ImplStartLine;
                Edit.Col      := ScanAt;
                Edit.OldName  := ShortName;
                Edit.NewName  := ANewName;
                List.Add(Edit);
                Break;
              end;
              Inc(ScanAt);
            end;
          end;
        finally
          ILines.Free;
        end;
      end;
    end;
```
Add `System.Classes` (TStringList) + `System.IOUtils` (TFile) to the unit's `uses` if not already present (they are used elsewhere in Rename.pas -- verify).

- [ ] **Step 4: Simplify NamingFix (drop the now-redundant workaround)**

In `src/refactor/DRagLint.Refactor.NamingFix.pas`: remove the `BuildImplHeaderEdit` function (153-195) and its call at 303-307 (the `if SameText(F.RuleId, 'method-pascalcase') ... ImplEdit ...` block). The `Build` call at 299 now covers the impl header. Remove the now-unused `ImplEdit`/`ImplFound` locals (251-252).

- [ ] **Step 5: Build CLI Win64 + run both tests**

Build `src/cli/drag-lint.dproj` (Win64), deploy exe to `src/cli/Win64/Debug/` and `third_party/dll-win64/drag-lint.exe`.
Run: `pwsh tests/autotest/run_rename_implheader.ps1` -> PASS.
Run: `pwsh tests/autotest/run_naming_autofix.ps1` -> PASS (method-pascalcase impl-header re-casing still works, now via Build; NamingFix's CASE 1 impl-header assertion must still hold).

- [ ] **Step 6: Commit**

```bash
git add src/refactor/DRagLint.Refactor.Rename.pas src/refactor/DRagLint.Refactor.NamingFix.pas tests/autotest/run_rename_implheader.ps1 tests/autotest/fixtures/
git commit -m "fix(rename): TRenameRefactoring.Build renames the method implementation header too (fixes standalone rename verb; NamingFix drops its workaround)"
```

## Task 3 (phase 2): naming autofix prefix-adding

**Depends on:** Task 1 (C) + Task 2 (A).

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.NamingFix.pas` (new `SynthesizePrefixedName`; extend `BuildNamingFixEdits` filter + dispatch; add the `BuildLocal` collision guard)
- Modify: `src/cli/DRagLint.CLI.pas` (`FIXABLE_RULE_IDS`: add the 3 prefix rule-ids; the store-backed naming append in `FinalizeAndOutput` already routes all naming rules through `BuildNamingFixEdits`, so extend its rule-id filter to include the 3 prefix ids)
- Test: `tests/autotest/run_naming_prefix_autofix.ps1`

**Interfaces:**
- Consumes: `TRenameRefactoring.Build`/`BuildLocal`/`ConflictReason`, `TNamingConfig` prefix fields (`ClassPrefix`/`ExceptionPrefix`/`InterfacePrefix`/`PointerPrefix`/`FieldPrefix`/`ParamPrefix`), `ResolveSymbolAt`, `ReadIdentifierAt`.
- Produces:
  - `function SynthesizePrefixedName(const AOldName, APrefix: string): string;` -- returns `APrefix + Cap(AOldName)`; if `AOldName` already starts with `APrefix` followed by an uppercase (already prefixed), returns it unchanged. Empty prefix or empty name -> returns `AOldName`.
  - `BuildNamingFixEdits` handles `field-name-prefix`, `param-name-prefix`, `type-name-prefix` in addition to the 3 case rules.

- [ ] **Step 1: Write the failing test**

Create `tests/autotest/run_naming_prefix_autofix.ps1` (mirror `run_naming_autofix.ps1`). Fixtures + a `drag-lint-lint.json` opting the 3 prefix rules into `AutoFixIds` and setting the prefixes (`field_prefix:"F"`, `param_prefix:"p"`, `type_prefix.class:"T"`):
```powershell
# CASE field-name-prefix: `client: TObject;` field -> `FClient` at decl + all uses.
# CASE param-name-prefix: `procedure P(x: Integer);` + body use of x -> `pX` at decl header,
#   impl header, AND body (BuildLocal syncs all). Nothing outside the routine changes.
# CASE type-name-prefix: `myclass = class ... end;` -> `TMyClass` at decl + refs.
# OPT-IN GATE: same fixtures with the rule NOT in AutoFixIds -> identifier UNCHANGED.
# COLLISION SKIP: `procedure P(x: Integer); var pX: Integer;` -> synthesized 'pX' already
#   exists as a local in scope -> NO edit applied, exit 0, x unchanged.
# SAME-LINE (exercises Task 1): `procedure P(a, b: Integer);` both param-prefixed ->
#   both become pA, pB on the one line, no corruption.
# DRY-RUN: --fix without --apply -> file unchanged.
# DETERMINISM: two --fix --apply runs identical.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh tests/autotest/run_naming_prefix_autofix.ps1`
Expected: FAIL -- the 3 prefix rules are not fixable yet (no edits; identifiers unchanged).

- [ ] **Step 3: Add the SynthesizePrefixedName helper**

In `src/refactor/DRagLint.Refactor.NamingFix.pas`, beside `SynthesizeCasedName`:
```pascal
/// <summary>Returns APrefix + Cap(AOldName): the identifier with the naming-convention
/// prefix prepended and its first letter capitalized (e.g. 'client' + 'F' -> 'FClient';
/// 'x' + 'p' -> 'pX'). Idempotent: if AOldName already starts with APrefix followed by an
/// uppercase letter (already prefixed), returns AOldName unchanged. Empty APrefix or empty
/// AOldName returns AOldName. Unlike SynthesizeCasedName this CHANGES the identifier, so the
/// caller MUST collision-check the result before applying.</summary>
function SynthesizePrefixedName(const AOldName, APrefix: string): string;
begin
  if (AOldName = '') or (APrefix = '') then Exit(AOldName);
  // Already prefixed? (APrefix followed by an uppercase letter)
  if (Length(AOldName) > Length(APrefix))
     and SameText(Copy(AOldName, 1, Length(APrefix)), APrefix)
     and CharInSet(AOldName[Length(APrefix) + 1], ['A'..'Z']) then Exit(AOldName);
  Result := APrefix + UpperCase(AOldName[1]) + Copy(AOldName, 2, MaxInt);
end;
```
Add `System.Character` (CharInSet) to `uses` if needed (or use `AOldName[..] in ['A'..'Z']` set test which needs no unit).

- [ ] **Step 4: Extend BuildNamingFixEdits dispatch + add the collision guard**

In `BuildNamingFixEdits` (NamingFix.pas):
1. Extend the rule filter (line 264-265) to also accept `field-name-prefix`, `param-name-prefix`, `type-name-prefix`.
2. After recovering `OldName` (line 276), branch: if the rule is a prefix rule, compute `NewName` via `SynthesizePrefixedName` with the prefix chosen per rule from `ANaming`:
   - `field-name-prefix` -> `ANaming.FieldPrefix`
   - `param-name-prefix` -> `ANaming.ParamPrefix`
   - `type-name-prefix` -> the prefix for the symbol's kind: class->`ClassPrefix`, exception->`ExceptionPrefix`, interface->`InterfacePrefix`, pointer->`PointerPrefix` (resolve the kind from the store symbol; if ambiguous, default to `ClassPrefix`).
   Else (case rule) keep the existing `SynthesizeCasedName` path.
3. Route the rename:
   - `param-name-prefix` -> `BuildLocal` (routine-local, syncs both headers). **Collision guard (NEW, load-bearing):** before calling `BuildLocal`, verify the synthesized `NewName` does not already exist as another local/param in the same routine scope. Implement a helper `LocalNameCollides(AFile, ALine, ACol, ANewName): Boolean` that parses the enclosing routine (reuse the AST parse cache the way `BuildLocal` does) and checks whether any param or local var in that routine (other than the one being renamed) has the name `ANewName` (case-insensitive). If it collides, SKIP (do not emit edits) -- mirror the global path's `ConflictReason` skip. (If parsing the scope proves infeasible, a conservative fallback: read the routine's text span and skip if `ANewName` appears as a whole-word token elsewhere in the routine header/var block -- justify in the report if you fall back.)
   - `field-name-prefix` / `type-name-prefix` -> global `Build` + the existing `ConflictReason` skip (already in place at line 298 for the case path -- apply the same guard).
4. The impl-header edit is now emitted by `Build` itself (Task 2), so no separate `BuildImplHeaderEdit` call is needed for the method/type global path.

- [ ] **Step 5: Register the 3 prefix rule-ids as fixable**

In `src/cli/DRagLint.CLI.pas`, add `field-name-prefix`, `param-name-prefix`, `type-name-prefix` to `FIXABLE_RULE_IDS` (bump the array bound from `[0..13]` to `[0..16]`). The store-backed naming append in `FinalizeAndOutput` filters findings by the naming rule-ids before calling `BuildNamingFixEdits` -- extend that filter to include the 3 prefix ids (find the naming-append block added in Batch C Task 6; it currently lists the 3 case ids).

- [ ] **Step 6: Build CLI Win64 + run the battery to green**

Build + deploy. Run: `pwsh tests/autotest/run_naming_prefix_autofix.ps1` -> PASS (all cases incl. collision-skip + same-line). Run: `pwsh tests/autotest/run_naming_autofix.ps1` -> still PASS (phase-1 unaffected). Run the fixable-id guard test `tests/autofix/run_fixable_catalog.ps1` -> update its expected count (14 -> 17) + add the 3 new ids as store-backed exceptions; PASS.

- [ ] **Step 7: Commit**

```bash
git add src/refactor/DRagLint.Refactor.NamingFix.pas src/cli/DRagLint.CLI.pas tests/autotest/run_naming_prefix_autofix.ps1 tests/autofix/run_fixable_catalog.ps1
git commit -m "feat(autofix): naming phase 2 -- prefix-adding (field/param/type) via the rename engine, with a BuildLocal collision guard (opt-in)"
```

## Task 4 (B): index bare-RHS-identifier reads as references

**Files:**
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (the `assignment` handler in the usage-ref block, ~line 1357-1363)
- Test: `tests/autotest/run_bare_rhs_refs.ps1`

**Interfaces:**
- Produces: under `--deep`, an assignment whose RHS is a bare identifier (`X := someVar;`) now emits a `read` ref for that identifier. No new public signature.

**Gating (CRITICAL -- avoid over-capture):** do NOT add a blanket `if NodeType = 'identifier' then EmitRef('read')` -- `Walk` visits declaration-name and type-name identifiers too, which would balloon the index with spurious reads. Handle it INSIDE the `assignment` case: after emitting the LHS `write`, inspect the RHS field and emit a `read` ONLY when the RHS is itself a bare `identifier` node.

- [ ] **Step 1: Write the failing test**

Create `tests/autotest/run_bare_rhs_refs.ps1`. Fixture with a const/var read as a bare assignment RHS, plus negative controls:
```powershell
# unit u.pas:
#   const MaxItems = 10;
#   procedure P; var r: Integer; begin r := MaxItems; end;   <- bare RHS read of MaxItems
#   type TFoo = class end;   <- TFoo is a TYPE NAME (negative: must NOT gain a read ref)
# index --deep into a temp DB.
# ASSERT (positive): a refs row exists for 'MaxItems' at the read site -- verify via
#   `find-callers --name MaxItems --db <db> --json` (or impact) showing the P site,
#   OR drive const-casing rename-at-use and assert the RHS 'MaxItems' is rewritten.
# ASSERT (negative, GUARD against over-capture): the type name 'TFoo' did NOT gain a
#   spurious 'read' ref (its only refs should be genuine uses, not its own declaration).
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh tests/autotest/run_bare_rhs_refs.ps1`
Expected: FAIL (positive assertion) -- `MaxItems` has no ref row for the bare-RHS read.

- [ ] **Step 3: Emit a read for a bare-identifier RHS in the assignment handler**

In `src/parser/DRagLint.Parser.Delphi13.pas`, in the `assignment` case (line 1357-1363), after emitting the LHS write and BEFORE the generic recurse, add:
```pascal
    if NodeType = 'assignment' then
    begin
      var Lhs:= ANode.ChildByField('lhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') then AState.EmitRef('write', NodeText(Lhs, AState.Source), Lhs);
      // A bare-identifier RHS is a READ of that symbol (e.g. `Result := maxItems;`).
      // Guarded to the assignment's own rhs field so declaration/type-name identifiers
      // elsewhere are never captured (they are not reached through this case).
      var Rhs:= ANode.ChildByField('rhs');
      if (not Rhs.IsNull) and (Rhs.NodeType = 'identifier') then AState.EmitRef('read', NodeText(Rhs, AState.Source), Rhs);
      for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
      Exit;
    end;
```
VERIFY the tree-sitter grammar's `assignment` node exposes a `rhs` field (check the grammar / an existing `ChildByField('rhs')` use; if the field is named differently, e.g. `right`/`value`, use that name -- confirm against `tree-sitter-delphi13` node types). If there is no named rhs field, walk the assignment's named children and treat the child that is NOT the lhs and is an `identifier` as the RHS read.

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh tests/autotest/run_bare_rhs_refs.ps1`
Expected: PASS -- `MaxItems` now has a read ref; `TFoo` did NOT gain a spurious ref.

- [ ] **Step 5: Regression -- bound the blast radius**

Run the existing index/query batteries that exercise refs (`run_deps_report.ps1`, `run_reverse_calltree.ps1`, any find-usages/impact battery) -> all PASS. Additionally, index a small known fixture BEFORE and AFTER and confirm the ref-count delta is only the new bare-RHS reads (no explosion from declaration/type identifiers). Note the delta in the report.

- [ ] **Step 6: Commit**

```bash
git add src/parser/DRagLint.Parser.Delphi13.pas tests/autotest/run_bare_rhs_refs.ps1 tests/autotest/fixtures/
git commit -m "fix(index): emit a read ref for a bare-identifier assignment RHS under --deep (gated to assignment.rhs; no over-capture)"
```

---

# PHASE 2 -- IDE-only (BPL build + live smoke; NOT headless-testable)

All land before ONE final Win32 BPL build (Task 10). RAD Studio CLOSED. No fabricated UI tests.

## Task 5 (cleanup a): delete the dead singular OptionsFrame.pas

**Files:**
- Delete: `src/delphi-plugin/DragLint.Plugin.OptionsFrame.pas` (SINGULAR)
- Modify: `src/delphi-plugin/dclDragLintWizard.dpk` (remove from `contains`, ~line 55)
- Modify: `src/delphi-plugin/dclDragLintWizard.dproj` (remove the `<DCCReference>`, ~line 93)

- [ ] **Step 1: Confirm dead + check the test fixture**

Grep the repo for `TDragLintOptionsFrame` and `DragLint.Plugin.OptionsFrame` (singular). Confirm the only references are: the unit itself, the plural unit's header comment, and `tests/fixtures/T52_options.dpr`. Check whether `T52_options.dpr` is a LIVE test (referenced by any `.ps1` battery or build) or dead. If live and it depends on the singular unit, STOP and report (the deletion would break a live test -- escalate). If dead/unreferenced, proceed.

- [ ] **Step 2: Remove the unit from the build + delete the file**

Remove the `DragLint.Plugin.OptionsFrame in '...'` line from `dclDragLintWizard.dpk`'s `contains` clause and the matching `<DCCReference Include="...DragLint.Plugin.OptionsFrame.pas"/>` from `dclDragLintWizard.dproj`. Delete `src/delphi-plugin/DragLint.Plugin.OptionsFrame.pas`. (No helper-folding needed -- the plural unit already has `DLNewGroup`/`DLNewLabel`/`DLNewCheck` equivalents.)

- [ ] **Step 3: Build the BPL to confirm it still links**

Build `src/delphi-plugin/dclDragLintWizard.dproj` (Win32, RAD Studio closed). Expected: `BUILD_EXITCODE=0`, no `[dcc32 Error]`. (This build also validates that nothing referenced the deleted unit.)

- [ ] **Step 4: Commit**

```bash
git add -u src/delphi-plugin/dclDragLintWizard.dpk src/delphi-plugin/dclDragLintWizard.dproj
git rm src/delphi-plugin/DragLint.Plugin.OptionsFrame.pas
git commit -m "chore(plugin): delete dead singular OptionsFrame.pas (superseded by the plural 4-frame unit)"
```

## Task 6 (cleanup b): manifest write ANSI -> UTF8

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas:750` (`TDLLinterOptionsFrame.WriteMaxReturnCases`)

- [ ] **Step 1: Change the encoding**

At `OptionsFrames.pas:750`, change `TFile.WriteAllText(Path, Root.ToJSON, TEncoding.ANSI)` to `TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8)` -- matching the canonical `TManifestIO.Save` (`src/index/DRagLint.Index.Manifest.pas`, writes `TEncoding.UTF8`). Verify the read at ~line 722 (`TFile.ReadAllText(Path)`, default encoding) round-trips a UTF8 file (it does -- default decode handles UTF8 with/without BOM; TEncoding.UTF8 write here emits no BOM via TFile.WriteAllText... VERIFY: if TFile.WriteAllText with TEncoding.UTF8 prepends a BOM, and the CLI's manifest reader does not expect one, keep parity with TManifestIO.Save's exact call -- match whatever TManifestIO.Save does byte-for-byte).

- [ ] **Step 2: Build the BPL**

Folds into Task 10's final build, but do a quick compile check now (or defer to Task 10). No separate test -- covered by live smoke (edit max_return_cases, confirm read-back).

- [ ] **Step 3: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas
git commit -m "fix(plugin): write the max_return_cases manifest as UTF-8 to match TManifestIO.Save"
```

## Task 7 (presets): naming convention preset combo on the Lint Options dock frame

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` (add a preset combobox + a small constant preset table + apply/detect logic)

**Interfaces / facts (verify in code before building):**
- `LintOptionsFrame.pas` already binds every `naming.*` param to inline editors and writes the project `drag-lint-lint.json` (per the exploration: the naming.* param editors are built ~line 20-36 mapping). Find the editor controls for the naming prefixes/cases and how they persist (the JSON write path).

- [ ] **Step 1: Add the preset table + combobox**

Add a `TComboBox` "Naming preset" near the top of the naming section, with items: `Embarcadero (A...)`, `House (p...)`, `Custom`. Define a Pascal constant table mapping each preset to a bundle of naming values:
```pascal
// Embarcadero: param prefix 'A', field 'F', class 'T', exc 'E', intf 'I', ptr 'P',
//              method/local PascalCase.
// House (p):   param prefix 'p', field 'F', class 'T', exc 'E', intf 'I', ptr 'P',
//              method/local PascalCase. (matches CLAUDE.md pMyParam/FMyField/TMyClass)
// The two differ mainly in ParamPrefix (A vs p); keep the rest aligned with
// TNamingConfig.Default. Verify exact bundles against TNamingConfig.Default
// (src/lint/DRagLint.Lint.Config.pas:109) so 'Custom' detection is accurate.
```

- [ ] **Step 2: Apply-on-select + detect-on-load**

`OnSelect`: when the user picks Embarcadero or House, bulk-set the naming param editors to that bundle's values (then the existing JSON write persists them). Picking `Custom` leaves the current values as-is. On frame load (and after any manual edit to a naming field), detect: if the current naming values match a known preset's bundle exactly, show that preset in the combo; else show `Custom`. Wire the "manual edit flips to Custom" via the existing editors' OnChange (set combo to Custom without reapplying).

- [ ] **Step 3: Build the BPL (defer to Task 10 or quick check now)**

Compile check; full build in Task 10. No headless test (IDE UI).

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas
git commit -m "feat(plugin): naming-convention preset selector (Embarcadero/House/Custom) on the Lint Options dock frame"
```

## Task 8 (right-click): reverse-calltree IDE menu action (text into editor)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (new `InvokeReverseCallTree` + a menu item)

**Interfaces:**
- Consumes: `GetActiveProjectDb` (Editor.pas:1370), `DLAskQName` (2922-2933), `DLRunReport` (2878-2906). The CLI verb `reverse-calltree` exists (`CLI.pas:10044`).

- [ ] **Step 1: Add InvokeReverseCallTree (mirror InvokeImpact)**

After `InvokeWiring` (~Editor.pas:3102), add:
```pascal
{ Reverse call tree for the symbol under the cursor: who calls X, and who calls
  them, N-deep, with call sites and cycle markers. Text into an editor buffer
  (graphical in-dock rendering is a filed TODO). }
procedure InvokeReverseCallTree(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db:= GetActiveProjectDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;
  DLRunReport(Format('reverse-calltree --qname "%s" --db "%s" --depth 3 --format text', [Q, Db]), 'drag-lint-reverse-calltree.txt');
end;
```

- [ ] **Step 2: Add the menu item**

In the "Uses && Dependencies" submenu (after the `InvokeWiring` item at Editor.pas:3834), add:
```pascal
  AddWrappedItem(SubUses, 'Reverse Call Tree (who calls this, N-deep)...'          , InvokeReverseCallTree );
```
(Placed beside Impact/Wiring -- it is a call/dependency relationship, so "Uses & Dependencies" fits better than "Inspect Symbol".)

- [ ] **Step 3: Build the BPL (defer to Task 10 or quick check now)**

Compile check; full build in Task 10.

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas
git commit -m "feat(plugin): 'Reverse Call Tree...' right-click action (text report into the editor)"
```

## Task 9 (dock focus): stop the dock self-selecting on tab switches

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.DockForm.pas` and/or `src/delphi-plugin/DragLint.Plugin.GraphWindow.pas` (the offending show/activate trigger -- LOCATE via live investigation)

**This is a systematic-debugging task -- the trigger is NOT statically obvious.** Confirmed NOT the cause: `ShowDragLintDock` (DockForm.pas:461, the menu action -> intended) and `DragLintGraphNotifyActiveUnit` (GraphWindow.pas:442, sends WM_COPYDATA to the separate viewer, not the dock). The self-select-on-tab-switch fires from some OTHER path -- likely an editor/module notifier that pushes an update to the dock and re-`Show`s it, or an IDE dockable behavior. Follow superpowers:systematic-debugging: reproduce, instrument, find the actual `Show`/`Activate`/`Select`/`BringToFront` call that fires on a background update, THEN fix.

- [ ] **Step 1: Reproduce + locate (investigation)**

Search the plugin for every `.Show`/`.Activate`/`.BringToFront`/`.SetFocus`/`ShowDockableForm`/`ActivateDockableForm` call and every editor/module-change notifier (`IOTAIDENotifier`/`IOTAEditorNotifier`/view-activation hooks) that could touch the dock on a tab switch. Identify the one that fires on background updates (not just first open). Document the exact call + trigger in the report before changing anything.

- [ ] **Step 2: Fix -- show-on-top once at startup, then stay put**

Change the offending path so: (a) the dock is surfaced on top ONCE at IDE startup / first open (keep `ShowDragLintDock`'s intended behavior + the desktop-restore registration), and (b) background data updates NEVER re-`Show`/activate/select the dock -- they update its content in place regardless of which tab is focused. If the trigger is an update-notifier calling `Show`, gate it: only `Show` when the dock is not already created/visible, or drop the `Show` from the update path entirely (update content, don't touch z-order/focus). Preserve: startup surfacing, `wsMinimized -> wsNormal` restore on the explicit menu action, and background content refresh.

- [ ] **Step 3: Build the BPL (defer to Task 10 or quick check now)**

Compile check; full build in Task 10.

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.DockForm.pas src/delphi-plugin/DragLint.Plugin.GraphWindow.pas
git commit -m "fix(plugin): dock no longer self-selects on tab switches (show on top once at startup, then stay put)"
```

---

# WRAP-UP

## Task 10: Final BPL build + full battery + docs + TODO + BACKLOG

**Files:**
- Build: `src/delphi-plugin/dclDragLintWizard.dproj` (Win32, final, carrying Tasks 5-9)
- Modify: `docs/lint/BACKLOG.md`, `docs/lint/drag-lint TODO plan.md`, any AI/IDE verb docs

- [ ] **Step 1: Final builds**

Rebuild the Win32 BPL (RAD Studio closed) carrying Tasks 5-9; confirm `BUILD_EXITCODE=0`, deploy to `third_party/dll-win32/`. Confirm the CLI Win64 (Tasks 1-4) is built + deployed to `third_party/dll-win64/drag-lint.exe`.

- [ ] **Step 2: Full battery on the deployed exe**

Run the Batch D new scripts + a representative regression set: `run_textedit_sameline.ps1`, `run_rename_implheader.ps1`, `run_naming_prefix_autofix.ps1`, `run_bare_rhs_refs.ps1`, `run_naming_autofix.ps1`, `run_naming_synth.ps1`, `tests/autofix/run_fixable_catalog.ps1`, `run_reverse_calltree.ps1`, `run_deps_report.ps1`, `run_manifest.ps1`. All PASS. If any regression FAILS, STOP (BLOCKED) -- do not paper over.

- [ ] **Step 3: Docs + TODO + BACKLOG**

- `docs/lint/drag-lint TODO plan.md`: Track 1.1 -- mark naming autofix PHASE 2 (prefix-adding) SHIPPED. Note A/B/C fixed.
- `docs/lint/BACKLOG.md`: prepend a `RESUME 2026-07-08 (LATEST-35)` block summarizing the 8 tasks; mark A/B/C FIXED; record the reverse-calltree IDE right-click (text-only) + dock-focus fix + presets + cleanups.
- File the TODO: **in-Delphi tree renderer / Graphviz-subset dock tab** (consumes `TRCallTree` directly; no `.dot`, no dependence on the DB-wired `drag_lint_graph` viewer). Note: the claimed Delphi compiler `--graphviz` switch appears NOT to exist -- treat as false unless `dcc64 --help` on RAD Studio 37 shows it.
- Add `reverse-calltree` IDE action to any IDE-usage doc that lists menu actions.

- [ ] **Step 4: Commit + report**

```bash
git add "docs/lint/drag-lint TODO plan.md" docs/lint/BACKLOG.md docs/
git commit -m "docs(batch-d): mark A/B/C fixed + naming phase 2 shipped; RESUME LATEST-35; file in-Delphi tree-renderer TODO"
# BPL/DCP in a separate build(plugin): commit
git add third_party/dll-win32/dclDragLintWizard.bpl third_party/dll-win32/dclDragLintWizard.dcp
git commit -m "build(plugin): rebuild Win32 BPL carrying Batch D IDE tasks (cleanups, presets, right-click, dock focus)"
```

Report branch state (commits ahead of origin) and the LIVE-IDE SMOKE items for the user (NOT headless-testable): presets combo (pick a preset -> fields update -> JSON saved); reverse-calltree right-click (text tree opens); dock focus (switch to Project Manager -> dock stays put; still updates in background; startup surfaces it once); cleanup (b) (edit max_return_cases -> read-back OK). User drives push/release.

---

## Notes on anchors verified during planning (do not re-investigate)

- **C:** comparer at `TextEdit.pas:106-108`; `EditTopLine` returns EndLine for deletes else Line; line-based edits carry Col=0 so the tiebreak is a safe no-op for them.
- **A:** `Build` collects decl edit (Sym.StartLine/Col) + `FindCallersByName` refs, sorts via `CompareEdits`; misses the impl header. `Apply` (Rename.pas:201-217) does its own forward-scan token match, so a `TRenameEdit` near the identifier works. `TSymbol.ImplStartLine`/`ImplEndLine` at Model.pas:75-76. The workaround to promote is `NamingFix.BuildImplHeaderEdit` (153-195). Keep A minimal: promote ONLY the impl header; leave NamingFix's decl-column override (229-238) alone.
- **Phase 2:** `BuildNamingFixEdits` (NamingFix.pas:197-318) dispatches per rule-id; `BuildLocal` (Rename.pas) syncs impl (Walk) + interface/forward headers (SyncForwardHeaders:392-456) but has NO collision check -- the new guard is the load-bearing piece. `FIXABLE_RULE_IDS` in CLI.pas (currently [0..13]); the naming append is in `FinalizeAndOutput`.
- **B:** the usage-ref block is `Delphi13.pas:1343-1385`, gated on `AState.EmitUsageRefs` (--deep). The `assignment` handler (1357-1363) emits LHS write then recurses; a bare RHS identifier falls through with no ref. Fix INSIDE the assignment case (check the rhs field), NOT a blanket identifier case. Verify the grammar's rhs field name.
- **Task 8:** `InvokeImpact` template at Editor.pas:3072-3081; "Uses && Dependencies" submenu at 3821-3834; `DLAskQName`/`DLRunReport`/`GetActiveProjectDb` confirmed.
- **Task 9:** NOT `ShowDragLintDock` (DockForm.pas:461) nor `DragLintGraphNotifyActiveUnit` (GraphWindow.pas:442, targets the separate viewer). The trigger is elsewhere -- live investigation required.
- **Task 5:** singular `OptionsFrame.pas` dead; in `.dpk:55` + `.dproj:93`; helpers already duplicated in the plural unit; check `tests/fixtures/T52_options.dpr` liveness before deleting.
- **Task 6:** offending write at `OptionsFrames.pas:750` (`TEncoding.ANSI`); canonical `TManifestIO.Save` writes UTF8 -- match it byte-for-byte (watch BOM).
- **Task 7:** `LintOptionsFrame.pas` already binds naming.* editors + writes the project JSON; verify `TNamingConfig.Default` (Config.pas:109) to define accurate preset bundles + Custom detection.
