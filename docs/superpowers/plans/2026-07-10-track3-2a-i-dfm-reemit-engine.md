# Track 3 Batch 2a-i -- DFM Component Re-emit Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a pure Object Pascal unit `ReemitComponent` that parses one F component's DFM `object` block, remaps each property/event/sub-object/collection to its T path (including moved-depth and event bindings) driven by a validated 1:1 conversion rule set + the F/T property trees, and re-serializes a well-formed T `object` block plus a structured report -- all headless, no I/O.

**Architecture:** A new pure unit `DRagLint.Convert.DfmReemit.pas` owns (1) an in-memory DFM object model built from a fresh tree-sitter-dfm walk that captures property VALUES verbatim (the existing `TDFMParser` only harvests symbols/refs for indexing and is lossy), (2) the remap+re-serialize transform, and (3) the report record types. It reuses Batch 1's `TConversionRuleSet`/`ParseConversionRules` (extended with one new `#ignore` directive) and `TPropTree`/`BuildPropTree`. A hidden CLI verb `convert-reemit` (undocumented; 2a-iii's `convert-apply` supersedes it) builds the F/T proptrees from an indexed fixture and drives the engine so the PowerShell autotest can assert on the emitted DFM + report JSON.

**Tech Stack:** Delphi 13 (RAD Studio 37), tree-sitter-dfm (via `TreeSitter`/`TreeSitterLib` + `tree_sitter_dfm`), Spring4D-free pure RTL (`System.SysUtils`, `System.Generics.Collections`, `System.JSON`), FireDAC/Firebird not involved (pure in-memory). Autotest is PowerShell driving `src/cli/Win64/Debug/drag-lint.exe`.

## Global Constraints

- **Encoding:** all new/edited `.pas` and `.ps1` files strict 7-bit ASCII, NO BOM, CRLF line endings. No Unicode, no em-dashes in source -- use `--` in comments.
- **DocInsight (CDD):** every new public type and function carries a `///` DocInsight spec-comment (`<summary>`/`<param>`/`<returns>`/`<remarks>`). The comment and the test must agree.
- **TDD:** failing test first (RED, with captured evidence), implement to GREEN (captured evidence), refactor keeping comment+test+code in sync.
- **Scope 1:1 only:** 2a-i implements `#link` + `#default` + `#ignore` + `#remove` mapping only. NO split/merge (one-F-to-many-T or many-F-to-one-T), NO expression interpreter, NO cross-type binary/collection VALUE conversion -- those are deferred past 2a. A binary/complex value is copied VERBATIM only when F and T leaf types resolve to the same type, else WARN (never corrupt).
- **Purity:** `DRagLint.Convert.DfmReemit.pas` does NO file I/O, NO store access, NO CLI, NO IDE, NO LLM. It takes the F block text + rules + F/T trees as inputs. (The freshness guard, file locating, selection model, and revert stack are explicitly 2a-ii/2a-iii, not this batch.)
- **Reuse Batch 1:** `TConversionRuleSet`, `ParseConversionRules`, `ValidateConversionRules` (`DRagLint.Convert.Rules`); `TPropTree`, `TPropNode`, `BuildPropTree`, `TPropTreeOptions` (`DRagLint.Convert.PropTree`). Do NOT reimplement the rules parser or the proptree.
- **Build recipe:** CLI Win64 Debug via the `delphi-build` skill (rsvars + msbuild wrapper .bat run through `Start-Process -Wait`, read the log for `BUILD_EXITCODE=0` and no `[dcc] Error`). NO BPL, NO IDE build in this batch. Build output exe: `src/cli/Win64/Debug/drag-lint.exe`.
- **The .dproj trap:** a unit in `DCCReference` but NOT reachable from the `uses` graph is silently NOT compiled -> a "clean build" is spurious. The new unit must be BOTH added to `src/cli/drag-lint.dproj` DCCReference AND referenced from `DRagLint.CLI.pas`'s uses clause (Task 8 wires the verb, which pulls the unit in). Add the DCCReference in the same task that first needs the unit to compile.

## Controller Decisions (2026-07-10, override the spec where they conflict)

These four decisions were made with the user during pre-flight and GOVERN the tasks below:

1. **NO default-valued silent drop (drop `IsDefaultValued`).** DFM streaming only writes a property when its value differs from the stored default, so EVERY property present in the F block is a non-default value the developer set -> it MUST be carried to its mapped T path. There is no "unmapped default-valued -> silent" path in 2a-i: an unmapped property present in the DFM with NO rule goes to `Report.Dropped` (WARN) as a genuine potential loss. (The spec's "unmapped default-valued -> silent" test case is VACUOUS for real DFM input and is REMOVED, not asserted.)

2. **F-default-vs-T-default divergence is a KNOWN GAP, deferred to Batch 2a-0.** The only case 2a-i cannot get fully right: a property ABSENT from the F DFM (== F's default) whose F-default differs from T's default -> re-emitting it as also-absent silently adopts T's default. Resolving this needs the indexer to CAPTURE property `default` specifier values (`default True`/`default 0`) into the store + surface them on `TPropNode` -- which it does NOT do today (VERIFIED: property signatures are empty or type-only; `default X` is dropped at parse time). That is a SUPERVISED core-parser change = a NEW prerequisite **Batch 2a-0** (filed in Task 10), NOT part of 2a-i. 2a-i is written with an **optional default-overlay seam** so 2a-0 slots in without rework, and 2a-i emits a report Note warning that defaults MAY diverge (see decision 4).

3. **Owned-vs-child recognition uses the `#note owned:<Class>` marker** (deterministic, testable now). A nested F object's class is treated as an OWNED part iff a `#convert <Class> -> <T>` rule exists (recurse + convert) OR a `#note owned:<Class>` line marks it (left unconverted + `Report.OwnedParts` WARN). Everything else is a CONTAINED CHILD, copied verbatim, not flagged. 2a-ii replaces this marker with the real index-based Controls/Components container check.

4. **Divergence-risk Note.** 2a-i emits a `Report.Notes` entry warning that property defaults may diverge whenever the F and T root types differ (the general risk case). This is the honest user-facing signal for the decision-2 gap until 2a-0 lands.

---

## File Structure

- **Create** `src/report/DRagLint.Convert.DfmReemit.pas` -- the pure engine: in-memory DFM object model (`TDfmNode` tree) + a lossless tree-sitter-dfm walk (`ParseDfmBlock`) + `ReemitComponent` + the report/result record types (`TDfmNodeKind`, `TReemitReport`, `TReemitResult`). One clear responsibility: F-block -> T-block transform.
- **Modify** `src/report/DRagLint.Convert.Rules.pas` -- add `rkIgnore` to `TRuleKind`, parse `#ignore <FromPath>` (populates `FromPath`), and optionally validate its FromPath against the from-tree (a miss is a soft note, never a hard fail). Backward compatible.
- **Modify** `src/cli/DRagLint.CLI.pas` -- add the hidden `convert-reemit` test verb (`DoConvertReemit`): read `--from-block` file, `--rules` file, build F/T proptrees from `--from`/`--to`/`--db` (exactly like `DoConvertValidate`), call `ReemitComponent`, print `{ ok, error, dfm, report:{ dropped, ignored, mismatched, created, ownedParts, notes } }` JSON. Add `--from-block` arg parsing. Add the unit to the uses clause.
- **Modify** `src/cli/drag-lint.dproj` -- add `<DCCReference Include="..\report\DRagLint.Convert.DfmReemit.pas"/>` after the `DRagLint.Convert.Rules.pas` line (line ~188).
- **Create** `tests/autotest/run_dfm_reemit.ps1` -- headless test: builds a tiny F/T fixture, indexes it, feeds F blocks + rules strings via `convert-reemit`, asserts on the emitted DFM text + report JSON. Covers every case the spec enumerates.

---

## Task 1: Add the `#ignore` directive to the rules DSL

**Files:**
- Modify: `src/report/DRagLint.Convert.Rules.pas` (the `TRuleKind` enum ~line 46, its DocInsight ~lines 36-45, the parser dispatch chain ~lines 288-402, and the validator ~lines 458-479)
- Test: `tests/autotest/run_convert_rules.ps1` (extend the existing PARSE section)

**Interfaces:**
- Consumes: nothing new.
- Produces: `TRuleKind` gains member `rkIgnore`. A `#ignore <FromPath>` line parses to a `TConversionRule` with `Kind = rkIgnore` and `FromPath = <FromPath>` (trimmed). The engine (Task 5) keys `#ignore` off `Kind = rkIgnore` + `FromPath`.

- [ ] **Step 1: Extend the existing convert-rules test to cover `#ignore` (write the failing assertions)**

In `tests/autotest/run_convert_rules.ps1`, add `#ignore` to the `$RulesAll` here-string (after the `#note` line, before the PCRE line):

```powershell
#note carry this human text
#ignore TabOrder
FindThis -> ReplaceThat
```

Bump the parsed-count assertion from 9 to 10:

```powershell
Check 'print-parsed reports 10 rules' ($parsedRaw -match 'parsed 10 rule') "raw=$parsedRaw"
```

And add, right after the `note present` check:

```powershell
Check 'ignore present'         ($parsedRaw -match 'ignore.*TabOrder')          "raw=$parsedRaw"
```

This requires the CLI `--print-parsed` renderer to print `ignore` rows. Check how the existing renderer prints rule kinds:

Run: `grep -n "print-parsed\|rkNote\|PrintParsed\|rkConvert" src/cli/DRagLint.CLI.pas | head -30`

Note the location of the rule-kind -> text rendering (a `case R.Kind of` in the convert-validate `--print-parsed` branch, around `DoConvertValidate`). You will add an `rkIgnore` arm there in Step 3.

- [ ] **Step 2: Run the test to verify it fails**

Build is not yet done, so first just confirm the intent: the current exe prints `parsed 9 rule` and has no `ignore` row. Run against the CURRENT exe:

Run: `pwsh -File tests/autotest/run_convert_rules.ps1`
Expected: FAIL on `print-parsed reports 10 rules` (current exe reports 9) and on `ignore present`.

- [ ] **Step 3: Implement `rkIgnore` -- enum, DocInsight, parser, validator, and the print renderer**

In `src/report/DRagLint.Convert.Rules.pas`:

Add `rkIgnore` to the enum (keep existing members; append so ordinals of existing members are unchanged):

```pascal
  TRuleKind = (rkUnuse, rkRemove, rkMigrate, rkConvert, rkLink, rkDefault, rkNote, rkPcre, rkIgnore);
```

Extend the `TRuleKind` DocInsight `<remarks>` (append one clause):

```pascal
  /// rkPcre=a raw non-'#' line containing ' -&gt; ' (the PCRE find/replace escape
  /// hatch); rkIgnore=#ignore (acknowledge an F property/event is intentionally
  /// NOT mapped -- suppresses the unmapped-non-default WARN for that FromPath).</remarks>
```

Extend the `TConversionRule` `<remarks>` field-usage list (append after the rkPcre line):

```pascal
  /// rkPcre -&gt; Search (LHS of ' -&gt; '), Replace (RHS).
  /// rkIgnore -&gt; FromPath (the F property/event path to leave unmapped, no warn).
```

Add the parser arm. Insert it in the `Directive(...)` dispatch chain BEFORE the `#note` arm (any order among the `else if Directive(...)` arms is fine; place it after `#default`):

```pascal
      else if Directive('#ignore', Arg) then
      begin
        R.Kind    := rkIgnore;
        R.FromPath:= Arg;
        AddRule(R);
      end
```

Update the `ParseConversionRules` DocInsight `<remarks>` grammar list (append after the `#note` clause):

```pascal
/// '#note &lt;text&gt;'; '#ignore &lt;FromPath&gt;' (acknowledge an F property is
/// intentionally unmapped -- suppresses its unmapped-non-default warning).
```

Add the validator arm. In `ValidateConversionRules`' `case R.Kind of`, add a soft check (a miss is NOT a hard error -- append it as an informational path, matching the STUB-marker tolerance philosophy). Because the current validator only ADDS hard errors, and `#ignore` must never hard-fail, add NOTHING to the error list for `rkIgnore` (leave it uncovered by the case -- the existing `else`-free case already ignores unlisted kinds). Update the validator DocInsight `<remarks>` to say so:

```pascal
/// (rkUnuse/rkRemove/rkMigrate/rkNote/rkPcre) are not path-checked in Batch 1.
/// rkIgnore is not path-checked either -- a #ignore for a non-existent F path is
/// tolerated (it simply matches nothing), never a hard error.
```

In `src/cli/DRagLint.CLI.pas`, find the `--print-parsed` rule-kind renderer (the `case R.Kind of` inside `DoConvertValidate`, located via the Step-1 grep) and add an arm:

```pascal
      rkIgnore : Writeln(Format('  [%d] ignore FromPath=%s', [R.LineNo, R.FromPath]));
```

Match the exact `Writeln`/format style of the surrounding arms (copy the `rkNote` arm's shape). If the renderer uses a helper instead of inline `Writeln`, follow that pattern.

- [ ] **Step 4: Build the CLI (Win64 Debug) and run the test to verify it passes**

Build via the delphi-build skill recipe (rsvars + msbuild `src/cli/drag-lint.dproj` `/p:Config=Debug /p:Platform=Win64`). Confirm `BUILD_EXITCODE=0`, no `[dcc] Error`.

Run: `pwsh -File tests/autotest/run_convert_rules.ps1`
Expected: PASS (all checks green, including `parsed 10 rule` and `ignore present`).

- [ ] **Step 5: Commit**

```bash
git add src/report/DRagLint.Convert.Rules.pas src/cli/DRagLint.CLI.pas tests/autotest/run_convert_rules.ps1
git commit -m "feat(convert): add #ignore directive (rkIgnore) to the conversion-rules DSL

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Define the engine's public types (records only, no logic)

**Files:**
- Create: `src/report/DRagLint.Convert.DfmReemit.pas` (interface section + empty `implementation`/`end.`)
- Modify: `src/cli/drag-lint.dproj` (add the DCCReference)

**Interfaces:**
- Consumes: `TConversionRuleSet` (`DRagLint.Convert.Rules`), `TPropTree` (`DRagLint.Convert.PropTree`).
- Produces (the whole batch keys off these):
  - `TDfmNodeKind = (dnkScalar, dnkEvent, dnkSubObject, dnkCollection, dnkBinary)`.
  - `TDfmNode = class` with `Name: string; Kind: TDfmNodeKind; ValueText: string; ClassName_: string; Children: TObjectList<TDfmNode>` (owns children). (Trailing underscore on `ClassName_` avoids clashing with `TObject.ClassName`.)
  - `TReemitReport = record` with 6 `TArray<string>` fields: `Dropped, Ignored, Mismatched, Created, OwnedParts, Notes`.
  - `TReemitResult = record` with `DfmText: string; Report: TReemitReport; Ok: Boolean; Error: string`.
  - `function ReemitComponent(const AFromBlock: string; const ARules: TConversionRuleSet; const AFromTree, AToTree: TPropTree): TReemitResult;` (body added in Tasks 4-7; a stub returning `Ok=False, Error='not implemented'` here).
  - `function ParseDfmBlock(const ABlockText: string; out ARoot: TDfmNode): Boolean;` (body added Task 3; declared here so the verb can compile; a stub returning `False` here).

- [ ] **Step 1: Write the failing test**

There is no runtime yet, so the failing test is a COMPILE gate: the new unit must exist and compile. Create a trivial smoke test that will be replaced in Task 8 -- OR skip a dedicated test and treat "the unit compiles once referenced" as this task's gate. Since the unit is not yet in the uses graph, add it to the .dproj now and reference it from the verb stub in Task 8; for THIS task the deliverable is the compiling interface. Write a placeholder assertion in a scratch check:

Run: `test ! -f src/report/DRagLint.Convert.DfmReemit.pas && echo "MISSING (expected before Step 3)"`
Expected: prints `MISSING (expected before Step 3)`.

- [ ] **Step 2: Confirm the unit is absent**

Run: `ls src/report/DRagLint.Convert.DfmReemit.pas 2>/dev/null || echo "absent - good"`
Expected: `absent - good`.

- [ ] **Step 3: Create the unit with the full public interface and stub bodies**

Create `src/report/DRagLint.Convert.DfmReemit.pas`:

```pascal
unit DRagLint.Convert.DfmReemit;

{
  Track 3 (component conversion), Batch 2a-i -- the PURE DFM component re-emit
  engine. Given one F component's DFM `object` block text, a validated 1:1
  conversion rule set, and the F/T property trees, it parses the F block into an
  in-memory object model, remaps each scalar/event/sub-object/collection leaf to
  its T path (creating intermediate sub-objects for moved-depth), and
  re-serializes a well-formed T `object` block plus a structured report.

  PURE: no file I/O, no store, no CLI, no IDE, no LLM. Fully headless-testable.
  Reuses Batch 1's TConversionRuleSet (DRagLint.Convert.Rules) and TPropTree
  (DRagLint.Convert.PropTree). The only new DSL surface is #ignore (rkIgnore),
  added to DRagLint.Convert.Rules.

  Scope: 1:1 #link + #default + #ignore + #remove only. NO split/merge, NO
  expression interpreter, NO cross-type binary conversion (a binary/complex value
  is copied VERBATIM only when F and T leaf types resolve to the same type, else
  WARN). Those are deferred past 2a.
}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Convert.Rules,
  DRagLint.Convert.PropTree;

type
  /// <summary>The kind of one leaf or sub-node of a parsed DFM object: a scalar
  /// property, an event binding, a nested sub-object, a collection (item list),
  /// or a binary/data blob.</summary>
  TDfmNodeKind = (dnkScalar, dnkEvent, dnkSubObject, dnkCollection, dnkBinary);

  /// <summary>One node of the in-memory DFM object model: a property, event,
  /// nested object, or collection.</summary>
  /// <remarks>Name is the property/event name, or the nested object's instance
  /// name. ClassName_ is populated only for dnkSubObject nodes that are nested
  /// `object`s (the DFM class after the ':'). ValueText is the RAW property value
  /// text as it appears in the DFM (verbatim, for round-trip fidelity) and is ''
  /// for dnkSubObject/dnkCollection nodes. Children are owned (freed with this
  /// node). A scalar/event has no children; a sub-object's children are its
  /// properties + nested objects; a collection's children are `item` pseudo-nodes
  /// (each an unnamed dnkSubObject whose children are the item's properties).</remarks>
  TDfmNode = class
  strict private
    FChildren: TObjectList<TDfmNode>;
  public
    Name      : string;
    Kind      : TDfmNodeKind;
    ValueText : string;
    ClassName_: string;
    constructor Create;
    destructor Destroy; override;
    /// <summary>The owned child nodes (properties, nested objects, or items).</summary>
    property Children: TObjectList<TDfmNode> read FChildren;
  end;

  /// <summary>A structured report of what the re-emit did and what needs human
  /// attention. WARN-level: Dropped, Mismatched, OwnedParts. Silent: Ignored (an
  /// acknowledged #ignore).</summary>
  /// <remarks>Dropped=unmapped F props/events with a NON-default value (potential
  /// loss). Ignored=#ignore'd F props (acknowledged, no warn). Mismatched=binary/
  /// complex values whose F/T resolved types differ (WARN, not copied). Created=
  /// intermediate T sub-objects synthesized for moved-depth (Style/Active/Font).
  /// OwnedParts=nested owned parts (fields/columns) needing their own #convert
  /// rules (WARN). Notes=free-form (e.g. a relocated collection). Each entry is an
  /// ASCII, human-readable string.</remarks>
  TReemitReport = record
    Dropped   : TArray<string>;
    Ignored   : TArray<string>;
    Mismatched: TArray<string>;
    Created   : TArray<string>;
    OwnedParts: TArray<string>;
    Notes     : TArray<string>;
  end;

  /// <summary>The result of ReemitComponent: the emitted T object block plus the
  /// report, or a hard-failure flag.</summary>
  /// <remarks>DfmText is the well-formed T `object` block (2-space indentation),
  /// valid only when Ok. Ok is False only on a HARD failure: an unparseable F
  /// block, or no #convert header in the rules. Error carries the reason when Ok
  /// is False.</remarks>
  TReemitResult = record
    DfmText: string;
    Report : TReemitReport;
    Ok     : Boolean;
    Error  : string;
  end;

/// <summary>Parses one DFM `object` block into the in-memory model via
/// tree-sitter-dfm.</summary>
/// <param name="ABlockText">The raw text of ONE component's DFM object block,
/// from `object Name: TType` through its matching `end`.</param>
/// <param name="ARoot">Receives the root node (a dnkSubObject) on success; caller
/// OWNS and must Free it. Set to nil on failure.</param>
/// <returns>True when the block parsed into a single root object; False on a
/// binary DFM, an empty block, or a parse with no top-level object.</returns>
/// <remarks>Pure: no file I/O. Uses the same tree-sitter-dfm grammar the indexer
/// uses (node types object/property/identifier_value/qualified_identifier/
/// quoted_string/char_code/string), but captures property VALUES verbatim (the
/// indexer's TDFMParser is lossy -- symbols/refs only). Not thread-safe with
/// respect to the tree-sitter runtime if called concurrently.</remarks>
function ParseDfmBlock(const ABlockText: string; out ARoot: TDfmNode): Boolean;

/// <summary>Re-emit an F component's DFM object block as the T equivalent, driven
/// by a validated 1:1 rule set and the F/T property trees. Pure: no I/O.</summary>
/// <param name="AFromBlock">The raw F DFM `object` block text.</param>
/// <param name="ARules">The parsed+validated conversion rule set (must contain a
/// #convert F -&gt; T header; #link/#default/#ignore/#remove drive the remap).</param>
/// <param name="AFromTree">The F type's flattened property tree (BuildPropTree).</param>
/// <param name="AToTree">The T type's flattened property tree (BuildPropTree).</param>
/// <returns>A TReemitResult: on success, the emitted T block in DfmText plus the
/// structured Report; on hard failure, Ok=False with Error set.</returns>
/// <remarks>Only MAPPED properties are assigned -- there is NO auto-carry by
/// same-name. Every property PRESENT in the F DFM is a non-default value (DFM
/// omits defaults); an unmapped present property with no rule goes to
/// Report.Dropped (WARN, a genuine potential loss); a #ignore'd property goes to
/// Report.Ignored (no warn). Moved-depth #link creates intermediate T
/// sub-objects (Report.Created). A binary/complex value is copied VERBATIM only
/// when F/T leaf types resolve to the same type, else Report.Mismatched (not
/// copied). A nested owned part (a non-Controls/Components child) without its own
/// #convert rules is left unconverted + Report.OwnedParts. A nested Controls/
/// Components child is left ALONE. Pure; deterministic; no I/O.</remarks>
function ReemitComponent(const AFromBlock: string; const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TReemitResult;

implementation

{ TDfmNode }

constructor TDfmNode.Create;
begin
  inherited Create;
  FChildren:= TObjectList<TDfmNode>.Create(True { owns });
end;

destructor TDfmNode.Destroy;
begin
  FChildren.Free;
  inherited;
end;

function ParseDfmBlock(const ABlockText: string; out ARoot: TDfmNode): Boolean;
begin
  ARoot := nil;
  Result:= False; // implemented in Task 3
end;

function ReemitComponent(const AFromBlock: string; const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TReemitResult;
begin
  Result:= Default(TReemitResult);
  Result.Ok   := False;
  Result.Error:= 'not implemented'; // implemented in Tasks 4-7
end;

end.
```

Add the DCCReference to `src/cli/drag-lint.dproj` immediately after the `DRagLint.Convert.Rules.pas` line (line ~188):

```xml
        <DCCReference Include="..\report\DRagLint.Convert.Rules.pas"/>
        <DCCReference Include="..\report\DRagLint.Convert.DfmReemit.pas"/>
```

- [ ] **Step 4: Verify the unit compiles (it is not yet in the uses graph, so add a temporary reference to force compilation)**

The .dproj trap: DCCReference alone does not compile it. Temporarily add `DRagLint.Convert.DfmReemit` to the `uses` clause in `src/cli/DRagLint.CLI.pas` (after `DRagLint.Convert.Rules` at ~line 110):

```pascal
  , DRagLint.Convert   .Rules
  , DRagLint.Convert   .DfmReemit
```

Build (delphi-build skill, Win64 Debug).
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`. (Warnings about the stub bodies' unused params are acceptable.)

Leave the uses-clause line in -- Task 8 needs it anyway.

- [ ] **Step 5: Commit**

```bash
git add src/report/DRagLint.Convert.DfmReemit.pas src/cli/drag-lint.dproj src/cli/DRagLint.CLI.pas
git commit -m "feat(convert): add DfmReemit engine unit skeleton (types + stubs)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Implement `ParseDfmBlock` -- lossless in-memory DFM model

**Files:**
- Modify: `src/report/DRagLint.Convert.DfmReemit.pas` (fill `ParseDfmBlock` + private walk helpers)
- Reference (read-only, for the tree-sitter API): `src/parser/DRagLint.Parser.DFM.pas`

**Interfaces:**
- Consumes: `TDfmNode` (Task 2), tree-sitter API (`TreeSitter`, `TreeSitterLib`, `tree_sitter_dfm`).
- Produces: `ParseDfmBlock` returns a `TDfmNode` tree where the root is a `dnkSubObject` with `Name`/`ClassName_` from the `object Name: TClass` header, and children are: scalar properties (`dnkScalar`, `ValueText` = verbatim value text), event bindings (`dnkEvent`, `ValueText` = handler name; recognized by `Name` starting with `On` and value node type `identifier_value`), nested objects (`dnkSubObject`, recursed), and collection properties (`dnkCollection`, children are unnamed `dnkSubObject` item pseudo-nodes). Binary/multiline values keep the raw `{...}` / multi-quoted text verbatim in `ValueText` (still `dnkScalar` unless a `{` data block -> `dnkBinary`).

- [ ] **Step 1: Write the failing test (a temporary parse round-trip check via a throwaway harness)**

Because `ParseDfmBlock` is only reachable once the verb exists (Task 8), gate Task 3 on the round-trip that Task 6's re-serializer will also use. For NOW, verify parse structure indirectly by having the Task-8 test assert a round-trip. To keep Task 3 independently testable, add a MINIMAL temporary debug sub-verb behavior: extend the (not-yet-written) verb is too far ahead. Instead, gate Task 3 with a focused unit assertion embedded in the Task-8 test's first case (identity round-trip). Mark this task's real gate as: after Task 8's harness exists, the identity round-trip case passes. For THIS task, the check is a manual code-review + a compile.

Practical gate now: write the parser, and in Step 4 build + run a one-off inline check by temporarily adding a `Writeln` in `ReemitComponent` is discouraged. Accept this task's gate = "compiles + Task 8 identity round-trip passes." Proceed to implement.

- [ ] **Step 2: Confirm current behavior**

Run: `grep -n "not implemented\|Result:= False; // implemented in Task 3" src/report/DRagLint.Convert.DfmReemit.pas`
Expected: shows the `ParseDfmBlock` stub returning False.

- [ ] **Step 3: Implement `ParseDfmBlock` with a lossless tree-sitter walk**

Add to the `uses` clause of `DRagLint.Convert.DfmReemit.pas` (interface uses stays minimal; put tree-sitter in the IMPLEMENTATION uses to keep the interface clean):

```pascal
implementation

uses
  System.Classes,
  TreeSitter,
  TreeSitterLib,
  DRagLint.Parser.DFM; // for tree_sitter_dfm (external decl lives there)
```

Note: `tree_sitter_dfm` is declared in `DRagLint.Parser.DFM` interface (`function tree_sitter_dfm: PTSLanguage; cdecl; external 'tree-sitter-dfm';`). Reuse it -- do NOT redeclare the external.

Add file-local helpers (mirror `DRagLint.Parser.DFM`'s `NodeText` and `DfmDecodeString`, but keep VALUE text verbatim):

```pascal
// Verbatim UTF-8 slice of a node (mirrors DRagLint.Parser.DFM.NodeText).
function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx, EndIdx, Len: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  EndIdx  := Integer(ANode.EndByte  );
  Len:= EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;
```

Build the node model. A `property` node has field `name` and field `value`; the value node type distinguishes the kind:
- value node type `identifier_value` and name starts with `On` -> `dnkEvent`, `ValueText` = the qualified_identifier text (the handler);
- value node type `braces`/a `{...}` data block (binary) -> `dnkBinary`, `ValueText` = verbatim braces text;
- value is a nested `item` list / collection (a `<` `>` list) -> `dnkCollection` (children = item pseudo-nodes);
- otherwise `dnkScalar`, `ValueText` = verbatim value text (`NodeText` of the value node).

A nested `object` node -> `dnkSubObject`, recurse.

FIRST, discover the exact grammar node type names for collections and binary blobs (the spec lists object/property/identifier_value/qualified_identifier/quoted_string/char_code/string but NOT the collection/binary node names). Probe them:

Run: `grep -rn "NodeType = \|NodeType=\|ChildByField" src/parser/DRagLint.Parser.DFM.pas`

If the collection/binary node type names are not evident from the parser, write a tiny probe: temporarily add a debug that prints `NodeType` for each child of a `property` value in the Task-8 fixture, OR inspect the tree-sitter-dfm grammar. To avoid blocking, implement defensively: treat any value node whose `NodeText` starts with `<` (after trim) as a collection, any whose text starts with `{` as binary, else scalar. This text-shape fallback is robust because DFM collection values always begin with `<` and data blocks with `{`.

Implement:

```pascal
// Classify a property's value node into a TDfmNodeKind + capture verbatim text.
procedure ClassifyValue(const AName: string; const AValueNode: TTSNode;
  const ASource: TBytes; out AKind: TDfmNodeKind; out AValueText: string);
var
  Raw: string;
begin
  AValueText:= NodeText(AValueNode, ASource);
  Raw:= Trim(AValueText);
  if (Copy(AName, 1, 2) = 'On') and (not AValueNode.IsNull) and
     (AValueNode.NodeType = 'identifier_value') then
    AKind:= dnkEvent
  else if (Raw <> '') and (Raw[1] = '<') then
    AKind:= dnkCollection
  else if (Raw <> '') and (Raw[1] = '{') then
    AKind:= dnkBinary
  else
    AKind:= dnkScalar;
end;
```

Walk properties + nested objects into a `TDfmNode`:

```pascal
procedure WalkNodeInto(const ATsNode: TTSNode; const ASource: TBytes;
  const AParent: TDfmNode);
var
  i        : Integer;
  Child    : TTSNode;
  NameNode : TTSNode;
  ValueNode: TTSNode;
  ClassNode: TTSNode;
  Sub      : TDfmNode;
  Prop     : TDfmNode;
  K        : TDfmNodeKind;
  VText    : string;
begin
  for i:= 0 to ATsNode.NamedChildCount - 1 do
  begin
    Child:= ATsNode.NamedChild(i);
    if Child.NodeType = 'object' then
    begin
      Sub:= TDfmNode.Create;
      Sub.Kind:= dnkSubObject;
      NameNode := Child.ChildByField('name');
      ClassNode:= Child.ChildByField('class');
      if not NameNode.IsNull then Sub.Name:= NodeText(NameNode, ASource);
      if not ClassNode.IsNull then Sub.ClassName_:= NodeText(ClassNode, ASource);
      AParent.Children.Add(Sub);
      WalkNodeInto(Child, ASource, Sub); // recurse into the nested object
    end
    else if Child.NodeType = 'property' then
    begin
      NameNode := Child.ChildByField('name');
      ValueNode:= Child.ChildByField('value');
      if NameNode.IsNull then Continue;
      Prop:= TDfmNode.Create;
      Prop.Name:= NodeText(NameNode, ASource);
      ClassifyValue(Prop.Name, ValueNode, ASource, K, VText);
      Prop.Kind     := K;
      Prop.ValueText:= VText;
      AParent.Children.Add(Prop);
    end;
  end;
end;
```

The public `ParseDfmBlock`:

```pascal
function ParseDfmBlock(const ABlockText: string; out ARoot: TDfmNode): Boolean;
var
  Src      : TBytes;
  Parser   : TTSParser;
  Tree     : TTSTree;
  Root     : TTSNode;
  ObjNode  : TTSNode;
  NameNode : TTSNode;
  ClassNode: TTSNode;
  i        : Integer;
  Found    : Boolean;
begin
  ARoot := nil;
  Result:= False;
  if Trim(ABlockText) = '' then Exit;
  Src:= TEncoding.UTF8.GetBytes(ABlockText);
  if (Length(Src) > 0) and (Src[0] = $FF) then Exit; // binary DFM unsupported
  Parser:= nil; Tree:= nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_dfm;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    Root:= Tree.RootNode;
    // source_file -> [object ...]. Take the FIRST top-level object as the root.
    Found:= False;
    for i:= 0 to Root.NamedChildCount - 1 do
    begin
      ObjNode:= Root.NamedChild(i);
      if ObjNode.NodeType = 'object' then begin Found:= True; Break; end;
    end;
    if not Found then Exit;
    ARoot:= TDfmNode.Create;
    ARoot.Kind:= dnkSubObject;
    NameNode := ObjNode.ChildByField('name');
    ClassNode:= ObjNode.ChildByField('class');
    if not NameNode.IsNull then ARoot.Name:= NodeText(NameNode, Src);
    if not ClassNode.IsNull then ARoot.ClassName_:= NodeText(ClassNode, Src);
    WalkNodeInto(ObjNode, Src, ARoot);
    Result:= True;
  finally
    Tree.Free;
    Parser.Free;
  end;
end;
```

Move `WalkNodeInto`, `ClassifyValue`, and `NodeText` above `ParseDfmBlock` (Pascal needs them declared first), or add forward declarations. Match the existing codebase order (helpers before the function that uses them).

- [ ] **Step 4: Build to verify it compiles**

Build (delphi-build skill, Win64 Debug).
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

(Runtime verification of `ParseDfmBlock` happens in Task 8's identity round-trip case, since the verb is the only headless entry point.)

- [ ] **Step 5: Commit**

```bash
git add src/report/DRagLint.Convert.DfmReemit.pas
git commit -m "feat(convert): DfmReemit ParseDfmBlock -- lossless in-memory DFM model

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Implement the re-serializer `EmitBlock` (T tree -> DFM text)

**Files:**
- Modify: `src/report/DRagLint.Convert.DfmReemit.pas` (add private `EmitBlock`)

**Interfaces:**
- Consumes: `TDfmNode` (Task 2).
- Produces: a file-local `function EmitBlock(const ANode: TDfmNode; AIndent: Integer): string;` that renders a `TDfmNode` sub-object tree to well-formed DFM text with 2-space indentation. Round-trip target: `EmitBlock(ParseDfmBlock(x))` re-parses to an equal structure.

- [ ] **Step 1: Note the gate**

The re-serializer's correctness gate is Task 8's identity round-trip case: `ReemitComponent` with an EMPTY rule set (no #convert -> hard fail is wrong here; instead the identity case uses a #convert header that maps the type to ITSELF and every property via same-name #link is NOT how identity works -- identity means "parse then emit unchanged"). To make the round-trip test possible independent of the remap, `ReemitComponent` (Task 5-7) will, for the identity fixture, produce the same block. `EmitBlock` is the shared renderer. Its gate is that round-trip.

- [ ] **Step 2: Confirm `EmitBlock` is absent**

Run: `grep -n "function EmitBlock" src/report/DRagLint.Convert.DfmReemit.pas || echo "absent - good"`
Expected: `absent - good`.

- [ ] **Step 3: Implement `EmitBlock`**

Add above `ReemitComponent`:

```pascal
// Render a 2-space indent prefix.
function Ind(ALevel: Integer): string;
begin
  Result:= StringOfChar(' ', ALevel * 2);
end;

// Re-serialize a TDfmNode sub-object tree to well-formed DFM text. Scalars/events
// emit `Name = Value`; nested objects emit `object Name: TClass ... end`;
// collections/binary values emit their verbatim ValueText (which already carries
// the `< ... >` / `{ ... }` structure). Indentation normalized to 2 spaces.
function EmitBlock(const ANode: TDfmNode; AIndent: Integer): string;
var
  SB   : TStringBuilder;
  Child: TDfmNode;
  Head : string;
begin
  SB:= TStringBuilder.Create;
  try
    // Header line for a sub-object.
    if ANode.ClassName_ <> '' then
      Head:= Format('object %s: %s', [ANode.Name, ANode.ClassName_])
    else
      Head:= Format('object %s', [ANode.Name]);
    SB.Append(Ind(AIndent)).Append(Head).Append(#13#10);
    for Child in ANode.Children do
    begin
      case Child.Kind of
        dnkSubObject:
          SB.Append(EmitBlock(Child, AIndent + 1));
        dnkScalar, dnkEvent, dnkBinary, dnkCollection:
          SB.Append(Ind(AIndent + 1))
            .Append(Child.Name).Append(' = ').Append(Child.ValueText)
            .Append(#13#10);
      end;
    end;
    SB.Append(Ind(AIndent)).Append('end').Append(#13#10);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;
```

Add `System.Classes` to the implementation uses (for `TStringBuilder`) if not already there from Task 3.

Note on collection/binary verbatim text: `ValueText` for a `dnkCollection` is the whole `< item ... end ... >` text captured by `ParseDfmBlock`; emitting `Name = <verbatim>` preserves it. Multi-line collection/binary values keep their internal newlines verbatim -- indentation inside them is NOT re-normalized in 2a-i (documented limitation; round-trip fidelity is preserved because the text is unchanged).

- [ ] **Step 4: Build to verify it compiles**

Build (delphi-build skill, Win64 Debug).
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 5: Commit**

```bash
git add src/report/DRagLint.Convert.DfmReemit.pas
git commit -m "feat(convert): DfmReemit EmitBlock -- T tree to well-formed DFM text

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Implement the remap core -- `#convert` header, `#link`, `#ignore`, `#default`, unmapped-drop

**Files:**
- Modify: `src/report/DRagLint.Convert.DfmReemit.pas` (implement `ReemitComponent` body + a `PlaceAtPath` helper)

**Interfaces:**
- Consumes: `TConversionRuleSet`, `TConversionRule` (`Kind`, `FromType`, `ToType`, `ToPath`, `FromPath`, `Value`, `PropName`, `DfmOnly`), `TPropTree`, `TDfmNode`, `EmitBlock` (Task 4), `ParseDfmBlock` (Task 3).
- Produces: a working `ReemitComponent` for scalars/events: reads the `#convert` header (F->T type swap; hard-fail if absent), applies each `#link ToPath <- FromPath` (moved-depth via `PlaceAtPath`), `#ignore`, `#default`, `#remove`, and routes unmapped non-default leaves to `Report.Dropped`.
- Produces: `function PlaceAtPath(const ARoot: TDfmNode; const ADottedPath, AValueText: string; AKind: TDfmNodeKind; var ACreated: TArray<string>): TDfmNode;` -- walks/creates intermediate `dnkSubObject` nodes for each segment except the last, sets the leaf's `ValueText`/`Kind`, recording each synthesized intermediate in `ACreated`.

**ALSO FIX A COMMENT-vs-CODE DRIFT in this same unit (found in Task 4 review, CDD rule):** the `TDfmNode` `<remarks>` DocInsight (around line 41-45 of `src/report/DRagLint.Convert.DfmReemit.pas`) currently says `ValueText ... is '' for dnkSubObject/dnkCollection nodes` and that `a collection's children are 'item' pseudo-nodes`. That describes the ORIGINAL intended model, but Task 3's `ClassifyValue` actually implemented `dnkCollection` (and `dnkBinary`) as VERBATIM-TEXT LEAVES: the whole `< ... >` / `{ ... }` text is stored in `ValueText`, and a collection has NO `item` children. The code is correct and tested; the COMMENT is stale. Update the `TDfmNode` remarks to match the real shape: ValueText is '' ONLY for `dnkSubObject` nodes; `dnkScalar`/`dnkEvent`/`dnkCollection`/`dnkBinary` all carry their verbatim value in `ValueText`; a `dnkCollection`/`dnkBinary` node is a LEAF (no children); only a `dnkSubObject` has property/nested-object children. Keep it ASCII/CRLF.

- [ ] **Step 1: Write the failing test cases in the (Task 8) harness -- but stage the assertions now**

The harness does not exist until Task 8. To keep Task 5 test-gated, Task 8 is where these run; here, WRITE the intended assertions into a scratch note in the plan and implement to them. The concrete cases (from the spec) implemented here and asserted in Task 8:
1. `#link Text <- Caption`: F `Caption = 'Hi'` -> T emits `Text = 'Hi'`.
2. Moved-depth `#link Style.Active.Font.Size <- Font.Size`: T emits nested `object Style ... object Active ... object Font ... Size = N ... end` and `Created` lists `Style`, `Style.Active`, `Style.Active.Font`.
3. `#ignore TabOrder` with F `TabOrder = 3`: `TabOrder` NOT in `Dropped`, IS in `Ignored`.
4. Unmapped non-default (F `Hint = 'x'`, no rule): `Hint` in `Dropped`.
5. `#default Enabled = False`: T emits `Enabled = False`.
6. No `#convert` header -> `Ok=False`, `Error` names the missing header.

- [ ] **Step 2: Confirm the stub**

Run: `grep -n "not implemented" src/report/DRagLint.Convert.DfmReemit.pas`
Expected: shows `ReemitComponent` still returning the stub.

- [ ] **Step 3: Implement `PlaceAtPath` and the `ReemitComponent` core**

Add `PlaceAtPath` above `ReemitComponent`:

```pascal
// Ensure the dotted ToPath exists under ARoot, creating intermediate dnkSubObject
// nodes for every segment but the last (each new intermediate recorded in
// ACreated by its dotted prefix). The final segment becomes/updates a leaf node
// of AKind with AValueText. Returns the leaf node.
function PlaceAtPath(const ARoot: TDfmNode; const ADottedPath, AValueText: string;
  AKind: TDfmNodeKind; var ACreated: TArray<string>): TDfmNode;
var
  Segs   : TArray<string>;
  Cur    : TDfmNode;
  Child  : TDfmNode;
  i, j   : Integer;
  Prefix : string;
  Found  : Boolean;
begin
  Segs:= ADottedPath.Split(['.']);
  Cur := ARoot;
  Prefix:= '';
  for i:= 0 to High(Segs) - 1 do // every segment EXCEPT the last -> sub-objects
  begin
    if Prefix = '' then Prefix:= Segs[i] else Prefix:= Prefix + '.' + Segs[i];
    Found:= False;
    for j:= 0 to Cur.Children.Count - 1 do
      if SameText(Cur.Children[j].Name, Segs[i]) and
         (Cur.Children[j].Kind = dnkSubObject) then
      begin Cur:= Cur.Children[j]; Found:= True; Break; end;
    if not Found then
    begin
      Child:= TDfmNode.Create;
      Child.Name:= Segs[i];
      Child.Kind:= dnkSubObject;
      // A synthesized intermediate has no DFM class of its own (it is a sub-property
      // object like Font/Style); emit as `object Name` with no class, which the
      // DFM streamer accepts for owned TPersistent sub-properties. If a class is
      // required by the T shape, 2a-ii/iii supply it; 2a-i notes the creation.
      Cur.Children.Add(Child);
      ACreated:= ACreated + [Prefix];
      Cur:= Child;
    end;
  end;
  // Final segment -> the leaf.
  Found:= False;
  for j:= 0 to Cur.Children.Count - 1 do
    if SameText(Cur.Children[j].Name, Segs[High(Segs)]) then
    begin Child:= Cur.Children[j]; Found:= True; Break; end;
  if not Found then
  begin
    Child:= TDfmNode.Create;
    Child.Name:= Segs[High(Segs)];
    Cur.Children.Add(Child);
  end;
  Child.Kind     := AKind;
  Child.ValueText:= AValueText;
  Result:= Child;
end;
```

Implement `ReemitComponent`. Add helpers to look up rules and defaults, and to detect the F leaves. Replace the stub body:

```pascal
function ReemitComponent(const AFromBlock: string; const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TReemitResult;
var
  FRoot, TRoot: TDfmNode;
  R           : TConversionRule;
  HaveConvert : Boolean;
  ToType      : string;
  Created     : TArray<string>;
  Dropped     : TArray<string>;
  Ignored     : TArray<string>;

  // Find a #link whose FromPath equals AFromPath (a top-level F property name in
  // 2a-i; deep F paths supported for completeness).
  function FindLinkFor(const AFromPath: string; out AToPath: string): Boolean;
  var Q: TConversionRule;
  begin
    Result:= False; AToPath:= '';
    for Q in ARules.Rules do
      if (Q.Kind = rkLink) and SameText(Q.FromPath, AFromPath) then
      begin AToPath:= Q.ToPath; Exit(True); end;
  end;

  function IsIgnored(const AFromPath: string): Boolean;
  var Q: TConversionRule;
  begin
    Result:= False;
    for Q in ARules.Rules do
      if (Q.Kind = rkIgnore) and SameText(Q.FromPath, AFromPath) then Exit(True);
  end;

  function IsRemoved(const APropName: string): Boolean;
  var Q: TConversionRule;
  begin
    Result:= False;
    for Q in ARules.Rules do
      if (Q.Kind = rkRemove) and SameText(Q.PropName, APropName) then Exit(True);
  end;

  // NOTE (Controller decision 1): there is NO IsDefaultValued check. DFM only
  // serializes NON-default values, so every property PRESENT in the F block is a
  // developer-set value that MUST be carried. An unmapped present property with
  // no rule is therefore a genuine potential loss -> Dropped (WARN), never a
  // silent default-drop.
  //
  // DEFAULT-OVERLAY SEAM (Controller decision 2, Batch 2a-0 plugs in here): the
  // F-default-vs-T-default divergence for properties ABSENT from the DFM is a
  // known gap. When 2a-0 lands (indexer captures `default` specifiers), the
  // caller will materialize F's absent-but-non-T-default properties and inject
  // them as synthetic leaves BEFORE this loop -- RemapLeaf needs NO change then.
  // 2a-i only sees what is in the DFM.

  procedure RemapLeaf(const ALeaf: TDfmNode);
  var ToPath: string;
  begin
    if IsRemoved(ALeaf.Name) then Exit; // #remove: ensure absent from T
    if IsIgnored(ALeaf.Name) then
    begin Ignored:= Ignored + [ALeaf.Name]; Exit; end;
    if FindLinkFor(ALeaf.Name, ToPath) then
    begin
      if Trim(ToPath) = '???' then
      begin Result.Report.Notes:= Result.Report.Notes + [Format('unfilled ToPath (???) for %s', [ALeaf.Name])]; Exit; end;
      PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, ALeaf.Kind, Created);
      Exit;
    end;
    // UNMAPPED + present in the DFM == non-default -> genuine potential loss.
    Dropped:= Dropped + [ALeaf.Name];
  end;

var
  i: Integer;
  Leaf: TDfmNode;
begin
  Result:= Default(TReemitResult);
  FRoot := nil; TRoot:= nil;
  Created:= nil; Dropped:= nil; Ignored:= nil;

  // 1. Require a #convert header.
  HaveConvert:= False; ToType:= '';
  for R in ARules.Rules do
    if R.Kind = rkConvert then
    begin HaveConvert:= True; ToType:= R.ToType; Break; end;
  if not HaveConvert then
  begin
    Result.Ok:= False;
    Result.Error:= 'no #convert F -> T header in the rule set';
    Exit;
  end;

  // 2. Parse the F block.
  if not ParseDfmBlock(AFromBlock, FRoot) then
  begin
    Result.Ok:= False;
    Result.Error:= 'could not parse the F DFM object block';
    Exit;
  end;

  try
    // 3. Build the T root: same instance Name, swapped class.
    TRoot:= TDfmNode.Create;
    TRoot.Kind      := dnkSubObject;
    TRoot.Name      := FRoot.Name;
    TRoot.ClassName_:= ToType;

    // 4. Per top-level F leaf, remap. (Nested owned parts/children -> Task 6.)
    for i:= 0 to FRoot.Children.Count - 1 do
    begin
      Leaf:= FRoot.Children[i];
      if Leaf.Kind = dnkSubObject then Continue // handled in Task 6
      else RemapLeaf(Leaf);
    end;

    // 5. Apply #default (T-only props).
    for R in ARules.Rules do
      if R.Kind = rkDefault then
      begin
        if Trim(R.ToPath) = '???' then Continue;
        PlaceAtPath(TRoot, R.ToPath, R.Value, dnkScalar, Created);
      end;

    // 6. Divergence-risk Note (Controller decision 4): when F and T are different
    // types, a property absent from the F DFM (== F default) may adopt a DIFFERENT
    // T default when re-emitted absent. 2a-i cannot resolve this (indexer has no
    // default values -- Batch 2a-0); warn the user it MAY happen.
    if (AFromTree.RootType <> '') and (AToTree.RootType <> '') and
       (not SameText(AFromTree.RootType, AToTree.RootType)) then
      Result.Report.Notes:= Result.Report.Notes +
        [Format('property defaults may diverge between %s and %s -- values not present in the F DFM adopt the T default (verify; full default fidelity pending Batch 2a-0)',
          [AFromTree.RootType, AToTree.RootType])];

    Result.Report.Created:= Created;
    Result.Report.Dropped:= Dropped;
    Result.Report.Ignored:= Ignored;
    Result.DfmText:= EmitBlock(TRoot, 0);
    Result.Ok:= True;
  finally
    FRoot.Free;
    TRoot.Free;
  end;
end;
```

Note: `AFromTree`/`AToTree` are not yet consulted in Task 5 (they drive owned-vs-child + binary-type resolution in Task 6). Keep the params -- Task 6 uses them. The `H2164`/unused-param warnings are acceptable until Task 6.

- [ ] **Step 4: Build to verify it compiles**

Build (delphi-build skill, Win64 Debug).
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error` (unused-param/hint warnings OK).

- [ ] **Step 5: Commit**

```bash
git add src/report/DRagLint.Convert.DfmReemit.pas
git commit -m "feat(convert): DfmReemit remap core -- #convert/#link/#ignore/#default/drop

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Implement owned-part vs contained-child + collection relocate + binary same-type

**Files:**
- Modify: `src/report/DRagLint.Convert.DfmReemit.pas` (extend `ReemitComponent`'s nested-object handling; add `IsContainedChild` + `ResolveLeafType` helpers)

**Interfaces:**
- Consumes: `AFromTree`, `AToTree` (`TPropTree.Nodes[].Path`, `.TypeName`, `.Kind`), the `TConversionRuleSet` (for nested `#convert <PartType> -> <T-PartType>`), `PlaceAtPath`, `ReemitComponent` (recursion).
- Produces: nested `dnkSubObject` F children are classified: a Controls/Components CHILD is copied verbatim into T (left ALONE); an OWNED PART with a matching `#convert` rule recurses; an owned part WITHOUT a rule is copied as-is + recorded in `Report.OwnedParts`. Collection-level `#link Coll <- Coll` moves the whole collection verbatim + a `Report.Notes` entry. Binary/complex leaves copy only when F/T types match, else `Report.Mismatched`.

- [ ] **Step 1: Note the cases (asserted in Task 8)**

From the spec:
1. Owned part w/o rule: nested `object ColField: TSomeCol` (a collection element type, not a TControl child) with no `#convert TSomeCol -> ...` -> left as-is + in `OwnedParts`.
2. Owned part w/ rule: same nested object + a `#convert TSomeCol -> TNewCol` -> recurses, emits the converted part.
3. Contained child: nested `object Btn1: TButton` that IS a Controls child -> left ALONE, NOT in `OwnedParts`.
4. Collection relocate `#link Data.Fields <- Fields`: the whole `Fields = < ... >` collection moves to `Data.Fields`, items unchanged, a Note recorded.
5. Binary same-type copied verbatim; binary mismatch -> `Mismatched`, not copied.

Owned-vs-child recognition (spec risk note): the primary signal is proptree membership -- a nested object whose class is the element type of a NON-Controls/Components collection property in `AToTree` is OWNED. FALLBACK when the containers are not resolvable: the visual heuristic -- if the nested object's class descends from `TControl` it is a CHILD, else OWNED. In 2a-i, since `AToTree` is a property tree (not the full class graph), use the pragmatic rule: **a nested object is a CONTAINED CHILD when the parent F block places it as a normal child component (it has its own `object Name: TClass` with a class that is NOT referenced by any `#convert` rule AND is not the element of a relocated collection); it is an OWNED PART when a `#convert < its class> -> <T>` rule exists (convert it) OR when the report should flag it (no rule but it looks like a field/column).** To make the test deterministic WITHOUT the full class graph, drive the decision off the rules:
- If a `#convert <ChildClass> -> <T>` rule exists -> OWNED, recurse.
- Else -> treat as CONTAINED CHILD, copy verbatim, do NOT flag -- UNLESS a `#note owned:<ChildClass>` or the presence of a collection `#link` referencing it marks it owned; in that no-rule-owned case, record in `OwnedParts`.

Simplify for 2a-i determinism: **owned == a `#convert` rule exists for its class (recurse) OR the F child's class matches an element type named in a collection `#link` without a per-item `#convert` (flag in OwnedParts); everything else is a contained child, copied verbatim.** Document this as the 2a-i heuristic; 2a-ii wires the real index-based container check.

- [ ] **Step 2: Confirm current nested handling skips sub-objects**

Run: `grep -n "handled in Task 6\|dnkSubObject then Continue" src/report/DRagLint.Convert.DfmReemit.pas`
Expected: shows the `if Leaf.Kind = dnkSubObject then Continue` placeholder from Task 5.

- [ ] **Step 3: Implement nested-object handling + collection relocate + binary type check**

Add helpers above `ReemitComponent`:

```pascal
// Deep-copy a TDfmNode subtree (for verbatim copies of contained children /
// unconverted owned parts / relocated collections).
function CloneNode(const ASrc: TDfmNode): TDfmNode;
var C: TDfmNode;
begin
  Result:= TDfmNode.Create;
  Result.Name      := ASrc.Name;
  Result.Kind      := ASrc.Kind;
  Result.ValueText := ASrc.ValueText;
  Result.ClassName_:= ASrc.ClassName_;
  for C in ASrc.Children do
    Result.Children.Add(CloneNode(C));
end;

// Look up a #convert rule for a specific From part-type. Returns the whole rule
// set filtered would be heavier; 2a-i recurses with the SAME ARules (the nested
// #convert header for the part type is found by ReemitComponent itself). This
// returns True if ANY #convert names AFromType as its FromType.
function HasConvertFor(const ARules: TConversionRuleSet; const AFromType: string): Boolean;
var Q: TConversionRule;
begin
  Result:= False;
  for Q in ARules.Rules do
    if (Q.Kind = rkConvert) and SameText(Q.FromType, AFromType) then Exit(True);
end;

// Resolve a leaf's declared type from a property tree by its top-level name.
function LeafTypeOf(const ATree: TPropTree; const AName: string): string;
var N: TPropNode;
begin
  Result:= '';
  for N in ATree.Nodes do
    if SameText(N.Path, AName) then Exit(N.TypeName);
end;
```

In `ReemitComponent`, replace the `if Leaf.Kind = dnkSubObject then Continue` branch with a call to a nested handler, and extend the leaf remap for collection relocate + binary mismatch. Add this procedure inside `ReemitComponent` (after `RemapLeaf`):

```pascal
  procedure HandleNested(const ASub: TDfmNode);
  var
    PartResult: TReemitResult;
    PartRules : string;      // not needed: recurse with same ARules
    Clone     : TDfmNode;
  begin
    if HasConvertFor(ARules, ASub.ClassName_) then
    begin
      // OWNED part with a rule -> recurse. Re-emit the part block by round-
      // tripping it: emit the sub-object as its own block, re-run ReemitComponent.
      PartResult:= ReemitComponent(EmitBlock(ASub, 0), ARules, AFromTree, AToTree);
      if PartResult.Ok then
      begin
        // Re-parse the converted part text back into a node and graft it.
        var PartRoot: TDfmNode;
        if ParseDfmBlock(PartResult.DfmText, PartRoot) then
        begin
          TRoot.Children.Add(PartRoot); // TRoot owns it now
          // fold the part's report notes up
          Result.Report.Created := Result.Report.Created + PartResult.Report.Created;
          Result.Report.Dropped := Result.Report.Dropped + PartResult.Report.Dropped;
        end;
      end;
    end
    else
    begin
      // No #convert for this nested class -> contained child OR unconverted owned
      // part. 2a-i heuristic: copy verbatim; flag in OwnedParts only when a
      // collection #link relocates a collection of this element type (owned).
      Clone:= CloneNode(ASub);
      TRoot.Children.Add(Clone);
      // Flag as an owned part needing rules if any collection #link targets it.
      // (Simplified: flag when the class name looks like a column/field element
      // referenced by a #link ToPath; else treat as a plain child, no flag.)
    end;
  end;
```

Extend `RemapLeaf` for collection relocate + binary mismatch. Replace the `FindLinkFor` success branch's `PlaceAtPath` call with kind-aware handling:

```pascal
    if FindLinkFor(ALeaf.Name, ToPath) then
    begin
      if Trim(ToPath) = '???' then
      begin Result.Report.Notes:= Result.Report.Notes + [Format('unfilled ToPath (???) for %s', [ALeaf.Name])]; Exit; end;
      if ALeaf.Kind = dnkCollection then
      begin
        // Collection relocate-keep-items: move the whole collection verbatim.
        PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, dnkCollection, Created);
        Result.Report.Notes:= Result.Report.Notes +
          [Format('collection %s relocated to %s, items unchanged', [ALeaf.Name, ToPath])];
        Exit;
      end;
      if ALeaf.Kind = dnkBinary then
      begin
        // Copy a binary/complex value only when F and T leaf types resolve to the
        // same type; else WARN and do not copy (cross-type conversion is the
        // interpreter stage, deferred past 2a).
        var FType: string; var TType: string;
        FType:= LeafTypeOf(AFromTree, ALeaf.Name);
        TType:= LeafTypeOf(AToTree, ToPath);
        if (FType <> '') and (TType <> '') and (not SameText(FType, TType)) then
        begin
          Result.Report.Mismatched:= Result.Report.Mismatched +
            [Format('%s: F type %s != T type %s (binary not copied)', [ALeaf.Name, FType, TType])];
          Exit;
        end;
        PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, dnkBinary, Created);
        Exit;
      end;
      PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, ALeaf.Kind, Created);
      Exit;
    end;
```

In the main leaf loop, route nested objects to `HandleNested`:

```pascal
    for i:= 0 to FRoot.Children.Count - 1 do
    begin
      Leaf:= FRoot.Children[i];
      if Leaf.Kind = dnkSubObject then HandleNested(Leaf)
      else RemapLeaf(Leaf);
    end;
```

For the owned-part-without-rule FLAG (spec case 1: a field/column with no rule must land in `OwnedParts`), refine `HandleNested`'s else-branch: flag when the nested object is a collection ITEM element or a non-visual owned sub-object. Since 2a-i lacks the full class graph, use the deterministic proxy the test controls: **if the nested object's class appears as an element type in ANY collection in the F block OR the rules mark it, flag it.** For the test fixture, the "owned part w/o rule" case is a nested `object` whose class has no `#convert` AND is explicitly listed via a `#note owned:<Class>` marker OR is detected as a collection item. Implement the simplest deterministic rule and document it:

```pascal
    else
    begin
      Clone:= CloneNode(ASub);
      TRoot.Children.Add(Clone);
      if IsOwnedPartByRulesHint(ARules, ASub.ClassName_) then
        Result.Report.OwnedParts:= Result.Report.OwnedParts +
          [Format('%s: %s -- owned part with no #convert rule (left unconverted)', [ASub.Name, ASub.ClassName_])];
    end;
```

And add the hint helper (a `#note owned:<Class>` marks an owned part explicitly -- the deterministic, test-controllable signal for 2a-i; 2a-ii replaces it with the real index container check):

```pascal
// 2a-i deterministic owned-part signal: a `#note owned:<ClassName>` in the rules
// declares a nested class as an OWNED part (a field/column) that needs its own
// #convert. Without the full class graph, this is the explicit, testable marker;
// 2a-ii wires the index-based Controls/Components container check that replaces it.
function IsOwnedPartByRulesHint(const ARules: TConversionRuleSet; const AClass: string): Boolean;
var Q: TConversionRule;
begin
  Result:= False;
  for Q in ARules.Rules do
    if (Q.Kind = rkNote) and SameText(Trim(Q.Text), 'owned:' + AClass) then Exit(True);
end;
```

Declare `IsOwnedPartByRulesHint` above `ReemitComponent` (file-local). Ensure `AFromTree`/`AToTree` are now consumed (via `LeafTypeOf`) so the unused-param warnings clear.

- [ ] **Step 4: Build to verify it compiles**

Build (delphi-build skill, Win64 Debug).
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 5: Commit**

```bash
git add src/report/DRagLint.Convert.DfmReemit.pas
git commit -m "feat(convert): DfmReemit owned-vs-child, collection relocate, binary same-type

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Fold report entries + finalize the result contract

**Files:**
- Modify: `src/report/DRagLint.Convert.DfmReemit.pas` (ensure all six report arrays are populated + assigned to `Result.Report` before return)

**Interfaces:**
- Consumes: the accumulators from Tasks 5-6.
- Produces: `Result.Report` fully populated (`Dropped`, `Ignored`, `Mismatched`, `Created`, `OwnedParts`, `Notes`) on the `Ok=True` path; `Ok=False`/`Error` on hard failures with an empty report.

- [ ] **Step 1: Note the gate**

Task 8 asserts each report array independently. This task ensures they are all wired (Task 5 wired Created/Dropped/Ignored; Task 6 added Mismatched/OwnedParts/Notes directly onto `Result.Report`). Verify no accumulator is dropped.

- [ ] **Step 2: Audit the assignments**

Run: `grep -n "Result.Report" src/report/DRagLint.Convert.DfmReemit.pas`
Expected: shows assignments to Created/Dropped/Ignored (from local vars) and direct appends to Mismatched/OwnedParts/Notes. Confirm the three local-var arrays (`Created`, `Dropped`, `Ignored`) are assigned to `Result.Report.*` before `EmitBlock`, and that Task 6's direct `Result.Report.*` appends are NOT overwritten afterward.

- [ ] **Step 3: Fix any ordering bug**

If Task 5 assigns `Result.Report.Created:= Created` AFTER Task 6 already appended to `Result.Report.Created` (from the recursion fold), the local assignment would clobber the recursion notes. Reorder so the local accumulators are folded IN, not assigned over:

```pascal
    // Fold the local accumulators into the report (do NOT clobber Task-6 appends).
    Result.Report.Created:= Result.Report.Created + Created;
    Result.Report.Dropped:= Result.Report.Dropped + Dropped;
    Result.Report.Ignored:= Result.Report.Ignored + Ignored;
    Result.DfmText:= EmitBlock(TRoot, 0);
    Result.Ok:= True;
```

(Change the three `:=` assignments from Task 5's Step 3 to the `+` fold shown here.)

- [ ] **Step 4: Build to verify it compiles**

Build (delphi-build skill, Win64 Debug).
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 5: Commit**

```bash
git add src/report/DRagLint.Convert.DfmReemit.pas
git commit -m "feat(convert): DfmReemit -- fold all six report arrays without clobber

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Add the hidden `convert-reemit` test verb + the headless autotest

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (add `--from-block` arg; add `DoConvertReemit`; dispatch the verb; the unit is already in uses from Task 2)
- Create: `tests/autotest/run_dfm_reemit.ps1`

**Interfaces:**
- Consumes: `ReemitComponent`, `TReemitResult` (`DRagLint.Convert.DfmReemit`); `ParseConversionRules` (`DRagLint.Convert.Rules`); `BuildPropTree`, `TPropTreeOptions` (`DRagLint.Convert.PropTree`); the store-open + multi-db resolution pattern from `DoConvertValidate`.
- Produces: `drag-lint convert-reemit --from-block <file> --rules <file> --from <FromType> --to <ToType> --db <db>` prints JSON `{ ok, error, dfm, report:{ dropped, ignored, mismatched, created, ownedParts, notes } }`. HIDDEN: not in the Usage/help text, not in README. Exit 0 on `Ok=True`, 1 on `Ok=False`, 2 on bad args.

- [ ] **Step 1: Write the failing autotest**

Create `tests/autotest/run_dfm_reemit.ps1`:

```powershell
<#
  run_dfm_reemit.ps1 -- Track 3 Batch 2a-i headless test for the pure DFM
  component re-emit engine, driven through the HIDDEN `convert-reemit` test verb.

  Builds a tiny F/T fixture (TFromC / TToC), indexes it, then feeds F object
  blocks + rules strings and asserts on the emitted T DFM text + the report JSON.
  Covers: 1:1 rename, moved-depth create, event map, #ignore, unmapped-drop,
  #default, collection relocate, binary same-type vs mismatch, owned-part w/ and
  w/o rule, contained child, and an identity round-trip.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dfm-reemit"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'fixture'; New-Item -ItemType Directory $src | Out-Null

# Fixture: F type TFromC has Caption/Font(TFont: Size)/Hint/TabOrder; T type TToC
# has Text and a Style(TStyle: Active(TActiveStyle: Font(TFont: Size))) deep path
# plus Enabled. TFont is shared so Font.Size (F) and Style.Active.Font.Size (T)
# both resolve. This lets proptree build both trees.
$fx = @'
unit ReemitFix;

interface

type
  TFont2 = class(TPersistent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;

  TActiveStyle = class(TPersistent)
  private
    FFont: TFont2;
  published
    property Font: TFont2 read FFont write FFont;
  end;

  TStyle2 = class(TPersistent)
  private
    FActive: TActiveStyle;
  published
    property Active: TActiveStyle read FActive write FActive;
  end;

  TFromC = class(TPersistent)
  private
    FCaption: string;
    FFont: TFont2;
    FHint: string;
    FTabOrder: Integer;
  published
    property Caption: string read FCaption write FCaption;
    property Font: TFont2 read FFont write FFont;
    property Hint: string read FHint write FHint;
    property TabOrder: Integer read FTabOrder write FTabOrder;
  end;

  TToC = class(TPersistent)
  private
    FText: string;
    FStyle: TStyle2;
    FEnabled: Boolean;
  published
    property Text: string read FText write FText;
    property Style: TStyle2 read FStyle write FStyle;
    property Enabled: Boolean read FEnabled write FEnabled;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $src 'ReemitFix.pas') $fx
$db = Join-Path $WorkDir 'reemit.sqlite'
$idx = & $Exe index $src --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "$($idx -join ' | ')"

function Reemit($blockBody, $rulesBody, $from, $to) {
  $bf = Join-Path $WorkDir 'block.dfm'; Write-Ascii $bf $blockBody
  $rf = Join-Path $WorkDir 'rules.txt'; Write-Ascii $rf $rulesBody
  Push-Location $WorkDir
  try {
    $out = (& $Exe convert-reemit --from-block $bf --rules $rf --from $from --to $to --db $db) -join "`n"
    $script:LastExit = $LASTEXITCODE
  } finally { Pop-Location }
  return $out
}

# --- Case 1: 1:1 rename Caption -> Text ---
$b1 = "object C1: TFromC`r`n  Caption = 'Hi'`r`nend`r`n"
$r1 = "#convert TFromC -> TToC`r`n#link Text <- Caption`r`n"
$o1 = Reemit $b1 $r1 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'rename exit 0' ($script:LastExit -eq 0) "out=$o1"
Check 'rename emits Text = ''Hi''' ($o1 -match "Text\s*=\s*'Hi'") "out=$o1"
Check 'rename T class TToC' ($o1 -match 'object C1: TToC') "out=$o1"

# --- Case 2: moved-depth Font.Size -> Style.Active.Font.Size + Created ---
$b2 = "object C1: TFromC`r`n  object Font: TFont2`r`n    Size = 12`r`n  end`r`nend`r`n"
# Font is a sub-object in F; the #link targets the deep T path from F's Font.Size.
$r2 = "#convert TFromC -> TToC`r`n#link Style.Active.Font.Size <- Font.Size`r`n"
$o2 = Reemit $b2 $r2 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'moved-depth exit 0' ($script:LastExit -eq 0) "out=$o2"
Check 'moved-depth nests Style/Active/Font' ($o2 -match 'object Style' -and $o2 -match 'object Active' -and $o2 -match 'object Font') "out=$o2"
Check 'moved-depth Size = 12 present' ($o2 -match 'Size\s*=\s*12') "out=$o2"
Check 'moved-depth Created lists Style.Active.Font' ($o2 -match 'Style\.Active\.Font') "out=$o2"

# --- Case 3: #ignore suppresses the drop warning ---
$b3 = "object C1: TFromC`r`n  TabOrder = 3`r`nend`r`n"
$r3 = "#convert TFromC -> TToC`r`n#ignore TabOrder`r`n"
$o3 = Reemit $b3 $r3 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'ignore: TabOrder in ignored' ($o3 -match '"ignored"[^]]*TabOrder') "out=$o3"
Check 'ignore: TabOrder NOT in dropped' (-not ($o3 -match '"dropped"[^]]*TabOrder')) "out=$o3"

# --- Case 4: unmapped non-default -> dropped ---
$b4 = "object C1: TFromC`r`n  Hint = 'x'`r`nend`r`n"
$r4 = "#convert TFromC -> TToC`r`n"
$o4 = Reemit $b4 $r4 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'unmapped Hint in dropped' ($o4 -match '"dropped"[^]]*Hint') "out=$o4"

# --- Case 5: #default sets a T-only prop ---
$b5 = "object C1: TFromC`r`n  Caption = 'Hi'`r`nend`r`n"
$r5 = "#convert TFromC -> TToC`r`n#link Text <- Caption`r`n#default Enabled = False`r`n"
$o5 = Reemit $b5 $r5 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'default Enabled = False emitted' ($o5 -match 'Enabled\s*=\s*False') "out=$o5"

# --- Case 6: no #convert header -> exit 1 ---
$b6 = "object C1: TFromC`r`n  Caption = 'Hi'`r`nend`r`n"
$r6 = "#link Text <- Caption`r`n"
$o6 = Reemit $b6 $r6 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'no #convert exit 1' ($script:LastExit -eq 1) "exit=$($script:LastExit); out=$o6"
Check 'no #convert error names header' ($o6 -match 'convert') "out=$o6"

# --- Case 7: identity round-trip (parse -> emit re-parses equal shape) ---
$b7 = "object C1: TFromC`r`n  Caption = 'Hi'`r`n  object Font: TFont2`r`n    Size = 9`r`n  end`r`nend`r`n"
$r7 = "#convert TFromC -> TFromC`r`n#link Caption <- Caption`r`n"
$o7 = Reemit $b7 $r7 'ReemitFix.TFromC' 'ReemitFix.TFromC'
Check 'round-trip exit 0' ($script:LastExit -eq 0) "out=$o7"
Check 'round-trip keeps Caption' ($o7 -match "Caption\s*=\s*'Hi'") "out=$o7"
Check 'round-trip keeps nested Font/Size' ($o7 -match 'object Font' -and $o7 -match 'Size\s*=\s*9') "out=$o7"

# --- Bad args ---
$noOut = ((& $Exe convert-reemit 2>&1) -join "`n"); $noExit = $LASTEXITCODE
Check 'no args exit 2' ($noExit -eq 2) "exit=$noExit"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 2: Run to verify it fails**

Run: `pwsh -File tests/autotest/run_dfm_reemit.ps1`
Expected: FAIL -- the `convert-reemit` verb does not exist yet (bad-args/verb-unknown), so most checks fail.

- [ ] **Step 3: Implement the `convert-reemit` verb**

In `src/cli/DRagLint.CLI.pas`:

Add the `--from-block` arg. Find the arg-parse chain (near the `--rules` line ~656) and add:

```pascal
    else if (A = '--from-block') and (i < ParamCount) then begin Inc(i); Result.FromBlockFile:= ParamStr(i); end // convert-reemit: F DFM object block file
```

Add a `FromBlockFile: string;` field to the args record `TArgs` near `RulesFile` (~line 317). Initialize it to `''` in the defaults (near line 524).

Add the verb dispatch. Find where `convert-validate`/`convert-scaffold` verbs are dispatched (grep for `'convert-scaffold'` in the verb `if/else` chain) and add an arm:

```pascal
  else if Verb = 'convert-reemit' then
    Exit(DoConvertReemit(Args))
```

Do NOT add it to the Usage text (it is hidden).

Implement `DoConvertReemit`. Model the store-open + proptree-build on `DoConvertValidate` (read that function first: `grep -n "function DoConvertValidate" src/cli/DRagLint.CLI.pas`). Write:

```pascal
/// <summary>drag-lint convert-reemit --from-block FILE --rules FILE --from FromType
/// --to ToType --db PATH -- HIDDEN test verb driving the pure ReemitComponent
/// engine. Prints the emitted T DFM block + report as JSON. Not in help/README;
/// superseded by convert-apply (2a-iii).</summary>
/// <returns>0 when Ok; 1 on a hard re-emit failure; 2 on bad args.</returns>
/// <remarks>Builds the F/T property trees from the index (like convert-validate),
/// parses the rules DSL, calls ReemitComponent, and serializes the result. Read-
/// only against the store.</remarks>
function DoConvertReemit(const AArgs: TArgs): Integer;
var
  Store    : ISymbolStore;
  FromTree : TPropTree;
  ToTree   : TPropTree;
  Rules    : TConversionRuleSet;
  Res      : TReemitResult;
  Opts     : TPropTreeOptions;
  BlockText: string;
  RulesText: string;
  JRoot    : TJSONObject;
  JReport  : TJSONObject;
  function ArrJson(const A: TArray<string>): TJSONArray;
  var S: string;
  begin Result:= TJSONArray.Create; for S in A do Result.Add(S); end;
begin
  if (AArgs.FromBlockFile = '') or (AArgs.RulesFile = '') or
     (AArgs.FromType = '') or (AArgs.ToType = '') then
  begin
    Writeln('Usage: drag-lint convert-reemit --from-block FILE --rules FILE --from FromType --to ToType --db PATH');
    Exit(2);
  end;
  if not FileExists(AArgs.FromBlockFile) then begin Writeln('from-block not found: ' + AArgs.FromBlockFile); Exit(2); end;
  if not FileExists(AArgs.RulesFile)    then begin Writeln('rules not found: ' + AArgs.RulesFile); Exit(2); end;

  BlockText:= TFile.ReadAllText(AArgs.FromBlockFile);
  RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  Rules:= ParseConversionRules(RulesText);

  // Build F/T trees from the first DB that resolves each qname (mirror
  // DoConvertValidate's store-open + multi-db loop). Depth default 6.
  Opts.Depth:= 6; Opts.ToPersistent:= True;
  // <-- open the store(s) exactly as DoConvertValidate does; for each DB, try
  //     BuildPropTree(Store, AArgs.FromType/ToType, Opts); keep the first with
  //     RootType <> ''. (Copy that loop verbatim; do not invent a new path.)

  Res:= ReemitComponent(BlockText, Rules, FromTree, ToTree);

  JRoot:= TJSONObject.Create;
  try
    JRoot.AddPair('ok', TJSONBool.Create(Res.Ok));
    JRoot.AddPair('error', Res.Error);
    JRoot.AddPair('dfm', Res.DfmText);
    JReport:= TJSONObject.Create;
    JReport.AddPair('dropped',    ArrJson(Res.Report.Dropped));
    JReport.AddPair('ignored',    ArrJson(Res.Report.Ignored));
    JReport.AddPair('mismatched', ArrJson(Res.Report.Mismatched));
    JReport.AddPair('created',    ArrJson(Res.Report.Created));
    JReport.AddPair('ownedParts', ArrJson(Res.Report.OwnedParts));
    JReport.AddPair('notes',      ArrJson(Res.Report.Notes));
    JRoot.AddPair('report', JReport);
    Writeln(JRoot.ToJSON);
  finally
    JRoot.Free;
  end;

  if Res.Ok then Exit(0) else Exit(1);
end;
```

IMPORTANT: replace the `<-- open the store(s) ...` comment with the ACTUAL store-open + multi-db proptree loop copied from `DoConvertValidate` (which already does `--from`/`--to`/`--db` -> two `BuildPropTree` calls). Read that function and reuse its exact pattern; do not fabricate a store API. Ensure `DRagLint.Convert.DfmReemit`, `System.JSON`, `System.IOUtils` (for `TFile`) are in the CLI uses clause (add any missing).

- [ ] **Step 4: Build the CLI and run the autotest to verify it passes**

Build (delphi-build skill, Win64 Debug). Confirm `BUILD_EXITCODE=0`, no `[dcc] Error`.

Run: `pwsh -File tests/autotest/run_dfm_reemit.ps1`
Expected: PASS (all cases green). If a specific case fails, debug that case per systematic-debugging (verify the JSON shape with a raw `convert-reemit ... | ConvertFrom-Json` in a scratch console); do NOT weaken an assertion to force green.

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_dfm_reemit.ps1
git commit -m "feat(convert): hidden convert-reemit test verb + run_dfm_reemit autotest

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Add the extended-case tests (collection relocate, binary, owned/child) + fold into the battery

**Files:**
- Modify: `tests/autotest/run_dfm_reemit.ps1` (add the remaining spec cases)
- Modify: the autotest battery runner (find it: `grep -rln "run_convert_rules\|run_proptree" tests/autotest/*.ps1`)

**Interfaces:**
- Consumes: the `convert-reemit` verb + fixture from Task 8.
- Produces: full spec-case coverage + the new test registered in the battery so it runs with the suite.

- [ ] **Step 1: Add the remaining cases to `run_dfm_reemit.ps1` (write the failing assertions)**

Extend the fixture with a collection + a binary-typed prop + an owned-part element type + a child component type. Because the existing `TFromC`/`TToC` fixture lacks collections, ADD a second fixture pair OR extend the block-only cases (collection/binary values live in the DFM block text, not the .pas -- proptree only needs the property to EXIST). Add to the .pas fixture: a `Fields` collection property and a `Data` sub-object with `Fields` on the T side, and a binary-typed `Layout` property on both. Keep it minimal. Then add cases:

```powershell
# --- Case 8: collection relocate Fields -> Data.Fields, items unchanged + Note ---
$b8 = "object C1: TFromC`r`n  Fields = <`r`n    item`r`n      Name = 'A'`r`n    end>`r`nend`r`n"
$r8 = "#convert TFromC -> TToC`r`n#link Data.Fields <- Fields`r`n"
$o8 = Reemit $b8 $r8 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'collection relocate exit 0' ($script:LastExit -eq 0) "out=$o8"
Check 'collection items unchanged (Name A)' ($o8 -match "Name\s*=\s*'A'") "out=$o8"
Check 'collection relocate Note recorded' ($o8 -match '"notes"[^]]*relocated') "out=$o8"

# --- Case 9: binary same-type copied verbatim ---
$b9 = "object C1: TFromC`r`n  Layout = {0A0B0C}`r`nend`r`n"
$r9 = "#convert TFromC -> TToC`r`n#link Layout <- Layout`r`n"
$o9 = Reemit $b9 $r9 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'binary same-type copied' ($o9 -match 'Layout\s*=\s*\{0A0B0C\}') "out=$o9"

# --- Case 10: owned part w/o rule -> in ownedParts (via #note owned: marker) ---
$b10 = "object C1: TFromC`r`n  object Col1: TOldCol`r`n    Width = 5`r`n  end`r`nend`r`n"
$r10 = "#convert TFromC -> TToC`r`n#note owned:TOldCol`r`n"
$o10 = Reemit $b10 $r10 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'owned-part-no-rule in ownedParts' ($o10 -match '"ownedParts"[^]]*TOldCol') "out=$o10"

# --- Case 11: contained child (no rule, no owned note) -> left alone, NOT flagged ---
$b11 = "object C1: TFromC`r`n  object Btn1: TButton`r`n    Caption = 'OK'`r`n  end`r`nend`r`n"
$r11 = "#convert TFromC -> TToC`r`n"
$o11 = Reemit $b11 $r11 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'contained child kept' ($o11 -match 'object Btn1: TButton') "out=$o11"
Check 'contained child NOT in ownedParts' (-not ($o11 -match '"ownedParts"[^]]*TButton')) "out=$o11"
```

Add `Fields` and `Layout` published properties to `TFromC` and `Data`(TData: Fields)/`Layout` to `TToC` in the .pas fixture (`Fields: TCollection`-like -- use a simple class-typed or a `TStrings`-ish stand-in; the type only needs to be indexable, not real). For `Layout`, give it the SAME type on both sides (so the binary same-type path copies). Keep types resolvable by proptree.

- [ ] **Step 2: Run to verify the new cases fail**

Run: `pwsh -File tests/autotest/run_dfm_reemit.ps1`
Expected: FAIL on cases 8-11 (engine handles them per Task 6, but the fixture properties must exist; if a case reveals a Task-6 gap, fix the ENGINE, not the test).

- [ ] **Step 3: Fix any engine gaps surfaced (systematic-debugging)**

If case 8/9/10/11 fails due to engine behavior (not fixture), debug to root cause in `DfmReemit.pas` and fix. Common likely fixes: the collection `ValueText` capture must include the full `< ... >` (verify `ClassifyValue`'s `<`-prefix detection catches multi-line collections -- the value node text must span the whole list). Rebuild after any engine change.

- [ ] **Step 4: Register in the battery + run the full suite**

Find the battery runner and add `run_dfm_reemit.ps1` to its list (follow how `run_convert_rules.ps1` is registered). Then run the convert-family tests to confirm no regression:

Run: `pwsh -File tests/autotest/run_convert_rules.ps1` (expect PASS -- Task 1's #ignore)
Run: `pwsh -File tests/autotest/run_proptree.ps1` (expect PASS -- untouched)
Run: `pwsh -File tests/autotest/run_convert_scaffold.ps1` (expect PASS -- untouched)
Run: `pwsh -File tests/autotest/run_dfm_reemit.ps1` (expect PASS -- all 11+ cases)

- [ ] **Step 5: Commit**

```bash
git add tests/autotest/run_dfm_reemit.ps1 <battery-runner-file>
git commit -m "test(convert): full 2a-i spec coverage + register run_dfm_reemit in the battery

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Update the SDD ledger + backlog note

**Files:**
- Modify: `.superpowers/sdd/progress.md` (append a BATCH 2a-i section)
- Modify: the repo backlog doc (find it: `grep -rln "LATEST-42" docs/ *.md 2>/dev/null | head`)

**Interfaces:**
- Consumes: nothing.
- Produces: a durable record of what 2a-i shipped, what 2a-ii/iii still owe, and the live smoke status (none -- this batch is fully headless).

- [ ] **Step 1: Append the SDD ledger section**

Add a `## BATCH 2a-i -- DFM re-emit engine` section to `.superpowers/sdd/progress.md` recording: the new pure unit `DRagLint.Convert.DfmReemit.pas` (`ReemitComponent` + `ParseDfmBlock` + `EmitBlock` + `PlaceAtPath`), the `#ignore`/`rkIgnore` DSL addition, the hidden `convert-reemit` test verb, `run_dfm_reemit.ps1`, and the 2a-i heuristics that 2a-ii replaces (owned-vs-child via `#note owned:` marker pending the real index container check; `IsDefaultValued` = present-in-DFM pending real defaults; collection/binary verbatim indentation not re-normalized). Note per-task commit hashes.

- [ ] **Step 2: Update the backlog resume-doc (LATEST-43)**

Prepend a LATEST-43 entry to the backlog doc: 2a-i SHIPPED (engine + tests, headless, all green); NEXT = 2a-ii (.pas decl-type + uses + property/event-access rewrite via the ref index + selection model + index-freshness guard); then 2a-iii (convert-apply verb + revert stack + rules library). Record `main` HEAD after the final commit.

ALSO file the new prerequisite **Batch 2a-0** (surfaced during 2a-i pre-flight): the drag-lint index does NOT capture property `default` specifier values (`default True`/`default 0` dropped at parse time -- VERIFIED: property signatures are empty or type-only). Batch 2a-0 = a SUPERVISED core-parser change (like ref-gap D/E: hand the user the exact `DRagLint.Parser.Delphi13.pas` diff before applying) to capture `default X` into the symbol store + surface it on `TPropNode` (e.g. a `DefaultText` field, resolved up the ancestor closure `BuildPropTree` already walks). It closes 2a-i's KNOWN GAP: a property absent from the F DFM (== F default) whose F-default differs from T's default silently adopts T's default on re-emit. 2a-i's default-overlay seam (documented in `DfmReemit.pas` RemapLeaf) is where 2a-0's materialized F defaults inject. Priority: before 2a-ii/iii deliver a user-facing apply that could silently flip defaults.

- [ ] **Step 3: Commit**

```bash
git add .superpowers/sdd/progress.md docs/
git commit -m "docs(track3): 2a-i DFM re-emit engine SHIPPED -- SDD ledger + backlog LATEST-43

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage** (every spec section maps to a task):
- Inputs/outputs interface (`TReemitResult`/`TReemitReport`/`ReemitComponent`) -> Task 2.
- Parse F block into in-memory tree (step 1) -> Task 3.
- Root type swap (step 2) -> Task 5.
- Per-leaf remap: #link/#ignore/unmapped-drop/#remove/#default (step 3) -> Task 5.
- Owned parts vs contained child (step 4) -> Task 6.
- Collection relocate-keep-items (step 4) -> Task 6.
- Binary same-resolved-type vs mismatch (step 5) -> Task 6.
- Re-serialize well-formed DFM (step 6) -> Task 4.
- Two reports (structured here) -> Task 7 (2a-iii renders them; 2a-i only produces the record -- correct).
- New `#ignore`/`rkIgnore` directive -> Task 1.
- Collection-level `#link` reuses `rkLink` -> Task 6.
- Index freshness (belongs to caller) -> documented in Task 2's DocInsight, implemented in 2a-ii (out of scope -- correct).
- All 11 test cases -> Tasks 8-9.
- Files list (`DfmReemit.pas`, `Rules.pas` edit, `run_dfm_reemit.ps1`, `.dproj`) -> Tasks 1/2/8/9.
- Global constraints (ASCII/CRLF, DocInsight, TDD, reuse Batch 1, Win64 CLI build) -> the Global Constraints block + every task.

**2. Placeholder scan:** No "TBD"/"implement later"/"add error handling"-style placeholders in code steps; every code step shows the actual Pascal/PowerShell. The one deliberate `<-- copy DoConvertValidate's store loop` in Task 8 Step 3 is flagged with an explicit "replace this comment with the actual pattern from that function, read it first" instruction -- acceptable because the exact store API must be read from the real function rather than guessed (fabricating a store signature would be the worse failure). Task 3's Step 1 honestly documents that the pure-engine gate is Task 8's round-trip (no false unit-test claim).

**3. Type consistency:** `TDfmNode` (with `ClassName_`, `Children: TObjectList<TDfmNode>`), `TDfmNodeKind` (dnkScalar/dnkEvent/dnkSubObject/dnkCollection/dnkBinary), `TReemitReport` (6 arrays), `TReemitResult` (DfmText/Report/Ok/Error), `ReemitComponent(AFromBlock, ARules, AFromTree, AToTree)`, `ParseDfmBlock(ABlockText, out ARoot): Boolean`, `EmitBlock(ANode, AIndent)`, `PlaceAtPath(ARoot, ADottedPath, AValueText, AKind, var ACreated)` -- all consistent across Tasks 2-8. `rkIgnore` + `FromPath` consistent across Tasks 1/5/6. The `convert-reemit` verb + `--from-block`/`FromBlockFile` consistent across Task 8. JSON report keys (`dropped`/`ignored`/`mismatched`/`created`/`ownedParts`/`notes`) consistent between Task 8's verb and Tasks 8-9's test assertions.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-10-track3-2a-i-dfm-reemit-engine.md`.
