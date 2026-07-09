# Track 3 -- Component conversion, BATCH 1 (foundation) -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship the foundation of the component-conversion milestone: an index-driven recursive deep-property enumerator (`proptree`), a reFind-superset conversion-rules DSL that is validated against REAL indexed properties (`convert-validate`), and an assisted rules scaffolder (`convert-scaffold`). All CLI-only, read-only, headless-testable. NO apply (that is Batch 2).

**Architecture:** Two new pure engine units under `src/report/` (property-tree enumerator; DSL parser+validator) consumed by three new CLI verbs in `DRagLint.CLI.pas`. The enumerator walks the SQLite index's `kind='property'` symbols, parses each type from its `signature` field, and recurses into class-typed property types up to `TPersistent` (depth-capped, cycle-guarded). The DSL is a line grammar that is a superset of Embarcadero reFind's `#migrate/#unuse/#remove`.

**Tech Stack:** Delphi 13 (RAD Studio 37), `ISymbolStore`/SQLite index, `System.JSON`, PowerShell autotests. No BPL, no IDE.

## Global Constraints

- **Encoding:** all `.pas` + `.ps1` strict 7-bit ASCII, NO BOM, CRLF -- including `///` DocInsight comments.
- **DocInsight:** every new public type/function/verb gets a `///` spec-comment; comment and test must agree.
- **TDD:** each verb gets a failing test first (RED), run red, implement to GREEN. Provide RED/GREEN evidence.
- **No new *analysis* engine beyond the property-tree walk** -- reuse `ISymbolStore` queries (the property symbols + `type_ancestors` are already indexed). The enumerator is a new REPORT/traversal over existing index data, same category as `RCallTree`/`Deps`.
- **CLI build:** Win64 Debug via rsvars+msbuild (`src/cli/drag-lint.dproj`, `/p:Platform=Win64`); deploy exe to `src/cli/Win64/Debug/` AND `third_party/dll-win64/`. RAD Studio being open does NOT block a CLI build; if the exe is locked by an orphaned `drag-lint.exe`, kill THAT (not RAD Studio).
- **Test invocation:** run repo `.ps1` as native pwsh (`.\tests\autotest\run_X.ps1`), NOT `powershell -File` (`$PSScriptRoot` collapses otherwise).
- **VERIFIED index facts (do not re-litigate):** properties ARE indexed as `kind='property'` symbols with `qualified_name` (owning class) and a `signature` field carrying the bare type (e.g. `'TFont'`, `'TColor'`). **NUANCE:** re-declared/inherited properties (`property Color;`) have an EMPTY signature -- the enumerator must resolve the type by walking the ancestor chain (`type_ancestors`/`heritage`) to the first declaration that carries a type, else mark `type=unknown` (never fabricate).
- **YAGNI:** no apply, no DFM rewrite, no IDE, no batch-convert-everything -- Batch 2+. No DSL sugar beyond the reFind superset.

---

## File Structure

- `src/report/DRagLint.Convert.PropTree.pas` -- NEW pure unit: `TPropNode`/`TPropTree` records + `function BuildPropTree(const AStore: ISymbolStore; const AClassQName: string; const AOpts: TPropTreeOptions): TPropTree;` (recursive deep enumerator + ancestor-resolution for empty signatures + depth cap + visited-type set).
- `src/report/DRagLint.Convert.Rules.pas` -- NEW pure unit: `TConversionRuleSet` + `function ParseConversionRules(const AText: string): TConversionRuleSet;` (reFind-superset line parser) + `function ValidateConversionRules(const ARules: TConversionRuleSet; const AFromTree, AToTree: TPropTree): TArray<TRuleError>;`.
- `src/cli/DRagLint.CLI.pas` -- `DoPropTree`, `DoConvertValidate`, `DoConvertScaffold` + dispatch + usage lines. `DoConvertScaffold` composes the enumerator (both F+T trees) + emits a rules file.
- Tests: `tests/autotest/run_proptree.ps1`, `run_convert_rules.ps1`, `run_convert_scaffold.ps1`.
- Docs: `docs/CONVERSION-RULES.md` (DSL reference, credits reFind), CHANGELOG, README, AI-USAGE.
- `.dproj`: add the two new units to `DCCReference` (a new unit needs BOTH the `uses`/reference AND `<DCCReference>` -- the "compiles clean but not actually compiled" trap).

---

## PHASE 1 -- The deep-property enumerator

### Task 1: `BuildPropTree` engine + `proptree` verb

**Files:**
- Create: `src/report/DRagLint.Convert.PropTree.pas`
- Modify: `src/cli/DRagLint.CLI.pas` (DoPropTree + dispatch + usage), `src/cli/drag-lint.dproj` (DCCReference)
- Test: `tests/autotest/run_proptree.ps1`

**Interfaces:**
- Consumes: `ISymbolStore` -- specifically the ability to (a) resolve a class qname to its symbol, (b) enumerate `kind='property'` child symbols of a class (by `parent_id`), (c) read a symbol's `signature`, (d) walk ancestors (`type_ancestors`/`heritage`) to resolve an empty property signature + to include inherited properties, (e) resolve a type name to a class symbol for recursion. Grep `ISymbolStore` (`src/core/DRagLint.Core.Interfaces.pas`) for existing methods that give these; if a needed query is missing, add a focused read-only method mirroring the existing ones (e.g. `GetPropertiesOfClass(AClassId): TArray<TSymbol>`), NOT a raw SQL leak in the verb.
- Produces:
  ```pascal
  type
    TPropNode = record
      Path       : string;   // dotted, e.g. 'Font.Color'
      TypeName   : string;    // 'TColor'; 'unknown' if unresolvable
      DeclaredIn : string;    // class qname where this property is first declared
      IsClassTyped: Boolean;  // True if TypeName resolves to a class we recursed into
      Kind       : string;    // 'scalar' | 'class' | 'enum' | 'set' | 'unknown'
    end;
    TPropTreeOptions = record Depth: Integer; ToPersistent: Boolean; end;
    TPropTree = record
      RootType  : string;
      Nodes     : TArray<TPropNode>;   // flattened, each with its dotted Path
      Truncated : Boolean;
    end;
  function BuildPropTree(const AStore: ISymbolStore; const AClassQName: string;
    const AOpts: TPropTreeOptions): TPropTree;
  ```
  Recursion: for each property whose `TypeName` resolves to an indexed class, recurse (prefixing `Path` with `<prop>.`), bounded by `AOpts.Depth` (default 6) AND a visited-TYPE set (so `Parent: TWinControl` back-refs terminate). Empty signature -> walk ancestors to find the typed declaration; still empty -> `TypeName='unknown'`, `Kind='unknown'`, no recursion. Set `Truncated:=True` when the depth cap stops a class-typed expansion.

- [ ] **Step 1: Write the failing test `tests/autotest/run_proptree.ps1`**

Build a fixture with a class whose property is ITSELF a class (to exercise recursion), e.g.:
```pascal
unit PropFix;
interface
type
  TInner = class(TPersistent)
  private FShade: Integer;
  published property Shade: Integer read FShade write FShade;
  end;
  TOuter = class(TPersistent)
  private FInner: TInner; FName: string;
  published
    property Inner: TInner read FInner write FInner;
    property Name: string read FName write FName;
  end;
implementation
end.
```
Index it, then:
```powershell
$json = & $exe proptree --qname 'PropFix.TOuter' --format json --db $db
$o = $json | ConvertFrom-Json
Check ($o.root_type -match 'TOuter') 'root is TOuter'
$paths = $o.properties | ForEach-Object { $_.path }
Check ($paths -contains 'Name') 'has scalar prop Name'
Check ($paths -contains 'Inner') 'has class-typed prop Inner'
Check ($paths -contains 'Inner.Shade') 'RECURSED into Inner.Shade (the deep match)'
$shade = $o.properties | Where-Object { $_.path -eq 'Inner.Shade' }
Check ($shade.type -match 'Integer') 'Inner.Shade type is Integer'
```
Model the fixture build/index/exe-path on `tests/autotest/run_forward_calltree.ps1`. ASCII/CRLF. Native-pwsh invocation.

- [ ] **Step 2: Run it RED** -- `.\tests\autotest\run_proptree.ps1` -> FAIL (proptree verb unknown). Confirms teeth.

- [ ] **Step 3: Implement `BuildPropTree`** in `DRagLint.Convert.PropTree.pas` with full DocInsight. Add whatever focused read-only `ISymbolStore` method(s) the walk needs (properties-of-class, resolve-type-to-class-id, ancestors-of-class) if not already present, implemented in the SQLite store the same way existing queries are. Handle the empty-signature ancestor-resolution nuance.

- [ ] **Step 4: Implement `DoPropTree`** in CLI.pas (mirror `DoReverseCallTree`'s multi-db resolve + format switch): `--qname` (required), `--depth N` (default 6), `--to-persistent` (default on), `--format text|json` (default text), multi-`--db`. json schema `proptree/1` `{ qname, root_type, truncated, properties:[{path,type,declared_in,kind,is_class_typed}] }`. Add dispatch (`else if Args.Command = 'proptree' then Result:= DoPropTree(Args)`) + usage line + the unit to `.dproj` DCCReference.

- [ ] **Step 5: Build CLI Win64, deploy, run test GREEN** -- `.\tests\autotest\run_proptree.ps1` -> `RESULT: PASS`. Then `.\tests\autotest\run_reverse_calltree.ps1` -> still PASS (no dispatch regression).

- [ ] **Step 6: Commit**
```bash
git add src/report/DRagLint.Convert.PropTree.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dproj tests/autotest/run_proptree.ps1
git commit -m "feat(cli): proptree verb -- index-driven recursive deep-property enumerator (Track 3 Batch 1)"
```

---

## PHASE 2 -- The reFind-superset rules DSL

### Task 2: DSL parser + validator + `convert-validate` verb

**Files:**
- Create: `src/report/DRagLint.Convert.Rules.pas`
- Modify: `src/cli/DRagLint.CLI.pas` (DoConvertValidate + dispatch + usage), `.dproj` (DCCReference)
- Test: `tests/autotest/run_convert_rules.ps1`

**Interfaces:**
- Consumes: `BuildPropTree` (Task 1) for validation.
- Produces:
  ```pascal
  type
    TRuleKind = (rkUnuse, rkRemove, rkMigrate, rkConvert, rkLink, rkDefault, rkNote, rkPcre);
    TConversionRule = record
      Kind: TRuleKind;
      // rkConvert: FromType/ToType + UnitsAdd; rkLink: ToPath/FromPath;
      // rkDefault: ToPath/Value; rkMigrate: Scope/Old/New/UnitsAdd; rkUnuse: UnitName;
      // rkRemove: PropName + DfmOnly; rkNote: Text; rkPcre: Search/Replace
      FromType, ToType, ToPath, FromPath, Old, New, Scope, UnitName, PropName, Value, Text, Search, Replace: string;
      UnitsAdd: TArray<string>;
      DfmOnly : Boolean;
      LineNo  : Integer;
    end;
    TConversionRuleSet = record Rules: TArray<TConversionRule>; end;
    TRuleError = record LineNo: Integer; Message: string; end;
  function ParseConversionRules(const AText: string): TConversionRuleSet;
  function ValidateConversionRules(const ARules: TConversionRuleSet;
    const AFromTree, AToTree: TPropTree): TArray<TRuleError>;
  ```
  Parser: line-based. `#unuse U` / `#remove [DFM:] P` / `#migrate [Class:][obj.]Old -> New [, U [, U]]` (reFind verbatim) + `#convert F -> T [, U ...]` / `#link ToPath <- FromPath` / `#default ToPath = Value` / `#note text`. Blank + `//`/`;`-comment lines ignored. A non-`#` line containing ` -> ` is an rkPcre passthrough (reFind escape hatch). Unknown `#directive` -> a parse error (captured, not raised).
  Validator: `#link`/`#default` ToPath must exist in `AToTree.Nodes[].Path`; `#link` FromPath must exist in `AFromTree`; `#convert` types should be resolvable (informational if trees empty). Emit `TRuleError` per violation; empty array = valid. THIS is the "we know real properties" check that reFind lacks.

- [ ] **Step 1: Write failing test `run_convert_rules.ps1`**

Two parts. (a) PARSE: feed a rules string covering every directive (incl. an adopted reFind snippet like `#migrate TTable -> TFDTable, FireDAC.Comp.Client` and `#unuse BDE`) and assert the parsed count + a couple of field values via a tiny CLI `convert-validate --rules <f> --print-parsed` (or assert via the validate output). (b) VALIDATE: on the PropFix fixture from Task 1, a rules file with `#link Name <- Inner.Shade` validates OK, but `#link Bogus.Path <- Name` yields an error naming the bad ToPath. Assert exit codes (0 valid / 1 has-errors / 2 bad-args) + that the error text names the offending path. ASCII/CRLF, native pwsh.

- [ ] **Step 2: Run it RED.**

- [ ] **Step 3: Implement `ParseConversionRules` + `ValidateConversionRules`** in `DRagLint.Convert.Rules.pas` (full DocInsight). Keep the parser total (never raises; malformed lines -> captured errors).

- [ ] **Step 4: Implement `DoConvertValidate`** in CLI.pas: `--rules <file>` (required), optional `--from`/`--to` + `--db` (to build the trees for validation; if omitted, parse-only + report parse errors). Print OK or the list of `line N: message`. Exit 0 (valid/parse-ok) / 1 (errors found) / 2 (bad args / unreadable file). Dispatch + usage + `.dproj`.

- [ ] **Step 5: Build, deploy, test GREEN** + `run_proptree.ps1` still green.

- [ ] **Step 6: Commit**
```bash
git add src/report/DRagLint.Convert.Rules.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dproj tests/autotest/run_convert_rules.ps1
git commit -m "feat(cli): convert-validate verb + reFind-superset conversion-rules DSL parser/validator (Track 3 Batch 1)"
```

---

## PHASE 3 -- The assisted scaffolder

### Task 3: `convert-scaffold` verb

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (DoConvertScaffold + dispatch + usage)
- Test: `tests/autotest/run_convert_scaffold.ps1`

**Interfaces:**
- Consumes: `BuildPropTree` (both F + T trees), the `TConversionRule*` types (to emit valid DSL text).
- Produces: `DoConvertScaffold` -- `--from F --to T [--out <file>] --db PATH`. Emits a rules file (stdout or `--out`) that is VALID reFind-superset DSL, pre-filled:
  1. `#convert F -> T` header (+ best-guess uses-add from the declaring units).
  2. For each T path: if exactly one F path matches by name+type -> `#link Tpath <- Fpath`. If multiple F candidates -> `#link Tpath <- ???` + `#note candidates: Fpath1, Fpath2, ...`. If no F source -> `#default Tpath = ???` (or the T default if discoverable).
  3. For each F path with no T target -> `#note DROPPED <Fpath> (no T target)`.

- [ ] **Step 1: Write failing test `run_convert_scaffold.ps1`**

Build TWO fixture classes F and T where: one property matches unambiguously by name+type (-> a concrete `#link`), one T property has multiple plausible F sources (-> a `???` + candidates note), and one F property has no T counterpart (-> a DROPPED note). Assert the emitted output contains: the `#convert` header, at least one concrete `#link X <- Y` (no `???`), at least one `#link ... <- ???` with a `candidates:` note, and a `DROPPED` note. Then feed the emitted file back through `convert-validate --from F --to T --db $db` and assert it validates without PARSE errors (the scaffolder emits well-formed DSL; the `???` are values not paths, so they're not path-validation failures -- confirm the scaffold marks them so validation tolerates stubs, e.g. `???` recognised as an explicit-unfilled marker that validate reports as a WARNING not a hard error, OR the test asserts only parse-validity). ASCII/CRLF, native pwsh.

- [ ] **Step 2: Run it RED.**

- [ ] **Step 3: Implement `DoConvertScaffold`** (full DocInsight). Match F<->T paths by (leaf name case-insensitive + compatible type). "Ambiguous" = >1 F path sharing the T leaf's name or type. Emit deterministic output (stable ordering -- sort paths) so the test is stable.

- [ ] **Step 4: Build, deploy, test GREEN** + `run_proptree.ps1` + `run_convert_rules.ps1` still green.

- [ ] **Step 5: Commit**
```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_convert_scaffold.ps1
git commit -m "feat(cli): convert-scaffold verb -- auto-fill conversion rules from real F/T property trees (Track 3 Batch 1)"
```

---

## PHASE 4 -- Docs + verify

### Task 4: `docs/CONVERSION-RULES.md` + doc sweep + battery

**Files:**
- Create: `docs/CONVERSION-RULES.md`
- Modify: CHANGELOG, README, docs/AI-USAGE, docs/AI-INDEX-FIRST

- [ ] **Step 1: Write `docs/CONVERSION-RULES.md`** -- the DSL reference: every directive with an example, the reFind lineage (credit + link to the RAD Studio reFind samples), the `#convert`/`#link`/`#default`/`#note` additions, the "validated against real indexed properties" thesis, and the `proptree`/`convert-validate`/`convert-scaffold` workflow. Note Batch 2 (apply) is not yet shipped.

- [ ] **Step 2: Doc sweep** -- CHANGELOG (the 3 verbs + DSL, "Track 3 foundation; apply is Batch 2"); README (3 verbs in the CLI list + a pointer to CONVERSION-RULES.md); AI-USAGE + AI-INDEX-FIRST (the 3 read-only verbs).

- [ ] **Step 3: Full battery** -- run `run_proptree`, `run_convert_rules`, `run_convert_scaffold` + the existing battery (`run_info_verb`, `run_butterfly`, `run_forward_calltree`, `run_reverse_calltree`, `run_naming_presets_roundtrip`, `run_self_field_refs`, `run_bare_rhs_refs`, `run_naming_prefix_autofix`, `run_naming_autofix`, `run_deps_report`, `run_manifest`, `run_fixable_catalog`). All exit 0, zero FAIL.

- [ ] **Step 4: Commit**
```bash
git add -A
git commit -m "docs(track3): CONVERSION-RULES.md + CHANGELOG/README/AI-docs for proptree/convert-validate/convert-scaffold"
```

---

### Task 5: Final review

- [ ] **Step 1: Whole-branch review** (requesting-code-review, most-capable model): correctness of the recursion (depth cap + visited-set termination; empty-signature ancestor resolution), the parser totality (never raises), the validator's real-property checks, and read-only-ness (no index writes). Address Critical/Important; defer Minor with a note.
- [ ] **Step 2:** This batch ships in a version bump WITH H1/H2 (all CLI-only, no BPL) at the next release the user cuts -- OR its own tag. Update BACKLOG + ledger noting Batch 2 (apply) is the next Track 3 step.

---

## Live/manual notes

- All three verbs are CLI + read-only + headless-tested. NO IDE, NO BPL this batch.
- A real end-to-end demo (scaffold a TOvcEdit->TcxTextEdit rules file against the library index, then hand-finish it) is a nice manual smoke but not a gate -- the fixture tests are the gate. If done, note that real DevExpress trees are DEEP (the `Truncated` flag + depth cap matter).

---

## Self-Review notes

- **Spec coverage:** enumerator (Task 1), DSL parse+validate (Task 2), scaffolder (Task 3), docs (Task 4), review (Task 5). All spec deliverables mapped. Apply is explicitly Batch 2 (out of scope, stated).
- **Verified-not-assumed:** properties ARE indexed as symbols with type-carrying signatures (274 Color / 398 Font rows seen); the empty-signature-on-redeclaration nuance is real and is handled by ancestor-resolution in Task 1. `type_ancestors` (38k rows) supports the hierarchy walk.
- **Type consistency:** `TPropTree`/`TPropNode` defined in Task 1, consumed by Tasks 2+3; `TConversionRule*` defined in Task 2, consumed by Task 3; `proptree/1` schema fields match the Task 1 test assertions.
- **Termination:** every recursion (Task 1) is bounded by BOTH a depth cap and a visited-TYPE set -- explicitly required so DevExpress's cross-referential trees can't loop.
- **Reuse:** the enumerator is index-driven (no new analysis engine); the DSL adopts reFind's grammar (no reinvention); the scaffolder composes the enumerator (no new matching engine beyond name+type pairing).
