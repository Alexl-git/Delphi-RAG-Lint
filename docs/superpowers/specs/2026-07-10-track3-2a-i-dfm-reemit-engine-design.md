# Track 3 -- Batch 2a-i: structured DFM component re-emit engine -- design

**Date:** 2026-07-10
**Status:** Approved (design); implement via TDD
**Milestone:** Track 3 (component conversion), Batch 2 (apply), sub-batch 2a-i --
the FIRST buildable piece; 2a-ii (.pas side + selection) and 2a-iii (the
convert-apply verb + revert stack + rules persistence) both depend on it.
**Prior art / foundation:** Batch 1 (proptree + reFind-superset DSL parser/
validator + convert-scaffold) is shipped (v1.1.0-alpha). GExperts is the thing to
beat: it converts a selected component's DFM only (never the .pas), does 1-level
type mapping, and cannot map events or moved-depth properties.

## What 2a-i is (and is not)

A **pure Object Pascal unit** -- NO file I/O, NO CLI, NO IDE, NO LLM. It takes the
source text of ONE F component's DFM `object` block plus a validated rule set plus
the F and T property trees, and returns the RE-EMITTED T `object` block as text
plus a structured report. Being pure makes it fully headless-testable and reusable
by 2a-ii/iii.

It is a **full structured re-emit**, NOT a line/text replacement: it parses F's
object block into an in-memory tree, remaps each leaf to its T path (which may be
DEEPER or SHALLOWER -- `F.Font.Size` -> `T.Style.Active.Font.Size`), creates
intermediate sub-objects as needed, and re-serializes a well-formed T block with
correct nesting and indentation. Text replacement is wrong precisely because
properties move nesting depth.

### Out of scope for 2a-i (later sub-batches / future)
- Reading/writing files, locating the component in a real .dfm, the CLI verb
  (2a-iii).
- The .pas side -- declaration type, uses, property-access rewrite (2a-ii).
- The selection model (all-of-class / kind / named x unit / project) (2a-ii).
- The revert stack + rules persistence/library seeding (2a-iii).
- Split/merge (one F -> several T, or several F -> one T) and the expression
  interpreter -- DEFERRED past 2a. 2a is 1:1 `#link` + `#default` + `#ignore` only.
- Cross-type binary/collection VALUE conversion -- deferred to the interpreter
  stage; 2a-i copies a binary/complex value ONLY when F and T leaf types are the
  same resolved type, else WARNS.

## Inputs / outputs (the interface 2a-ii/iii consume)

```pascal
type
  /// One leaf or sub-node of a parsed DFM object: a scalar property, an event
  /// binding, a nested sub-object, or a collection (item list).
  TDfmNodeKind = (dnkScalar, dnkEvent, dnkSubObject, dnkCollection, dnkBinary);

  TReemitReport = record
    Dropped   : TArray<string>;  // unmapped F props/events with a NON-default value -> WARN (potential loss)
    Ignored   : TArray<string>;  // #ignore'd F props -> acknowledged, NO warn
    Mismatched: TArray<string>;  // binary/complex where F/T resolved types differ -> WARN, not copied
    Created   : TArray<string>;  // intermediate T sub-objects synthesized (Style/Active/Font ...)
    OwnedParts: TArray<string>;  // nested owned parts (fields/columns) needing their own #convert rules -> WARN
    Notes     : TArray<string>;  // free-form (e.g. "collection Fields relocated to Data.Fields, items unchanged")
  end;

  TReemitResult = record
    DfmText: string;             // the well-formed T object block (indentation preserved/normalized)
    Report : TReemitReport;
    Ok     : Boolean;            // False only on a HARD failure (unparseable F block, no #convert header)
    Error  : string;            // populated when Ok = False
  end;

/// <summary>Re-emit an F component's DFM object block as the T equivalent, driven
/// by a validated 1:1 rule set and the F/T property trees. Pure: no I/O.</summary>
function ReemitComponent(const AFromBlock: string; const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TReemitResult;
```

## The transform algorithm

1. **Parse** `AFromBlock` with tree-sitter-dfm into an in-memory F object tree.
   Grammar node types available (confirmed in `DRagLint.Parser.DFM.pas`): `object`
   (fields: `name`, `class`), `property` (field: `value`), `identifier_value`,
   `qualified_identifier`, `quoted_string`, `char_code`, `string`. Events are
   recognized as `property` whose name starts with `On` and whose value is an
   `identifier_value` (the handler method) -- already handled by the DFM parser.
   The in-memory model is a tree of `{ Name, Kind, ValueText, Children }`.
2. **Root type swap:** the F block's `object <Name>: <FromType>` -> `<Name>: <ToType>`
   from the `#convert F -> T` header.
3. **Per-leaf remap** (each scalar/event/sub-object leaf of F, by its dotted path):
   - If an explicit **`#link ToPath <- FromPath`** matches this leaf's FromPath ->
     place the value at ToPath in the T tree, CREATING intermediate sub-objects
     (record each in `Created`). ToPath is validated to exist in `AToTree`
     (proptree); a `???` stub ToPath is left as a Note, not placed.
   - Else if the leaf is **`#ignore`'d** -> skip silently, record in `Ignored`.
   - Else (UNMAPPED): if the value differs from the property's default -> record in
     `Dropped` (WARN); a default-valued unmapped prop is dropped silently. **Only
     mapped properties are assigned** -- no auto-carry by same-name (per decision).
   - **`#remove` / `#remove DFM:`** -> ensure the property does not appear in T.
   - **`#default ToPath = Value`** -> set T's property to Value (for T-only props).
4. **Owned parts (nested `object` that is NOT a Controls/Components child):** decide
   OWNED vs CHILD via the parent's collection/composition properties in `AToTree`/
   the index -- a nested object whose class is the element type of a NON-
   Controls/Components collection is an OWNED PART. For each owned part:
   - if a `#convert <PartType> -> <T-PartType>` rule set exists -> recurse
     (ReemitComponent on the part block with the part's rules);
   - else -> leave the part unconverted + record it in `OwnedParts` (WARN).
   A nested object that IS a Controls/Components child is left ALONE (it is an
   independent component; the container conversion does not touch it).
   - **Collection relocate-keep-items:** a collection-level `#link Coll <- Coll`
     (or to a different T path, e.g. `Data.Fields <- Fields`) moves the whole
     collection to the T path and KEEPS its items as-is (no per-item conversion) --
     record a Note. Distinct from descending to convert each item.
5. **Binary / complex values (`dnkBinary`, collections):** copy the value VERBATIM
   ONLY when the F leaf's type and the T target leaf's type resolve (via proptree/
   the index) to the SAME type (possibly after a rename mapping F's type name to
   T's). If they differ -> record in `Mismatched` (WARN), do NOT copy (cross-type
   binary conversion is the interpreter stage).
6. **Re-serialize** the T object tree to well-formed DFM text: `object Name: TType`
   ... nested `object`s and `item` lists at correct indentation ... `end`.
   Round-trip fidelity required for: scalars (string/number/enum/boolean/set),
   nested sub-objects (Font/Properties), collections/item-lists (Columns/Items),
   binary `{ ... }` + multiline string values (VERBATIM). Indentation normalized to
   the DFM 2-space convention.

## Reports (two, per decision)

The engine returns `TReemitReport` (structured). 2a-iii will render it TWO ways:
1. a **text file** the user opens in the IDE later (may be dropped later -- treat
   as secondary), and
2. content to **copy into the IDE Messages window**.
2a-i itself only produces the structured record; the two renderings live in 2a-iii.
WARN-level entries: `Dropped` (non-default unmapped value), `Mismatched` (binary
type mismatch), `OwnedParts` (needs its own rules). `Ignored` and default-valued
drops are silent.

## New DSL directive (small addition to Batch 1's grammar)

- **`#ignore <FromPath>`** -- intentionally do NOT map this F property/event, and do
  NOT warn even if it has a non-default value (acknowledged drop). Other unmapped
  props still warn. Added to `TRuleKind` (rkIgnore) + the parser + validator
  (FromPath should exist in `AFromTree`, else a parse-tolerant note). convert-scaffold
  (Batch 1) can later emit `#ignore` stubs; not required for 2a-i.
- The **collection-level `#link`** reuses the existing `rkLink` shape; the engine
  distinguishes "collection relocate" from "leaf assign" by whether ToPath/FromPath
  resolve (in proptree) to a collection/sub-object vs a scalar leaf.

## Index freshness (guard belongs to 2a-ii/iii, noted here)

The T-tree SHAPE that step 3/4 rely on comes from proptree (the index). A STALE
index -> wrong T shape -> broken re-emit. 2a-i takes the trees as INPUTS (already
built by the caller), so the freshness guard (verify the F/T component types are
indexed and current vs disk mtime/sha; warn/refuse on stale) lives in the CALLER
(2a-ii/iii). 2a-i documents the requirement but does not implement I/O.

## Testing (headless, TDD)

Pure engine -> fully unit-testable via a PowerShell autotest that feeds an F block
string + a rules string + fixture F/T trees (built with proptree on tiny fixtures)
and asserts on the returned DfmText + Report. Cases:
- **1:1 rename** (`#link Text <- Caption`): F `Caption = 'Hi'` -> T `Text = 'Hi'`.
- **Moved-depth** (`#link Style.Active.Font.Size <- Font.Size`): T block has a
  nested `object Style ... object Active ... object Font ... Size = N ... end`,
  and `Created` lists the synthesized sub-objects.
- **Event map** (`#link Properties.OnChange <- OnClick`): the handler method name
  is carried to the T path.
- **#ignore**: an `#ignore SomeProp` with a non-default value -> NOT in `Dropped`,
  IS in `Ignored`.
- **Unmapped non-default** -> in `Dropped` (WARN); unmapped default-valued ->
  silent.
- **Owned part w/o rule**: a nested non-Controls/Components object (a "field")
  with no `#convert` for its type -> left as-is + in `OwnedParts`.
- **Owned part w/ rule**: recurses + converts the part.
- **Contained child**: a nested TControl-child object -> left ALONE, not in
  `OwnedParts`.
- **Binary same-type** copied verbatim; **binary mismatch** -> `Mismatched`, not
  copied.
- **Collection relocate** (`#link Data.Fields <- Fields`) -> items unchanged, Note
  recorded.
- **Re-serialization fidelity**: a round-trip of a block with scalars + a nested
  sub-object + a collection + a binary blob yields well-formed, re-parseable DFM.

## Files (2a-i)

- `src/report/DRagLint.Convert.DfmReemit.pas` (or `src/convert/...`) -- NEW pure
  unit: the in-memory DFM object model + `ReemitComponent` + the report types.
- `src/report/DRagLint.Convert.Rules.pas` -- ADD `rkIgnore` to `TRuleKind` + parse
  `#ignore` + (optional) validate its FromPath. Small, backward-compatible.
- Test: `tests/autotest/run_dfm_reemit.ps1`.
- `.dproj`: add the new unit's DCCReference (the compiles-clean-but-not-compiled
  trap).

## Global constraints

- Encoding: all new/edited `.pas` + `.ps1` strict 7-bit ASCII, no BOM, CRLF.
- DocInsight on every new public type/function; comment and test agree.
- TDD: failing test first (RED), implement to GREEN, evidence for both.
- Reuse Batch 1's `TConversionRuleSet`/`ParseConversionRules`/`ValidateConversion
  Rules` + `TPropTree`/`BuildPropTree`; reuse tree-sitter-dfm via the existing DFM
  parse path. NO new analysis engine beyond the in-memory DFM model + the remap.
- CLI Win64 Debug build for the test harness (the engine links into drag-lint.exe
  so the .ps1 can drive it via a thin `convert-reemit`-style test hook OR a
  dedicated headless test entry). NO BPL, NO IDE.

## Risks / notes

- **tree-sitter-dfm coverage of exotic values** (nested collections-in-collections,
  `MASKINACTIVE`-style binary, `WideString`/`#nnn` char runs): start with the
  common shapes the test enumerates; add cases as real DevExpress DFMs surface
  them. Anything the model can't confidently round-trip -> emit VERBATIM (never
  corrupt) and note it.
- **Owned-vs-child recognition** leans on the parent's Controls/Components vs other
  collection properties being resolvable in proptree/the index. RTL base classes
  (TComponent.Components, TWinControl.Controls) must be indexed for the negative
  test; if not confidently resolvable, FALL BACK to the visual heuristic (nested
  object's type descends from TControl -> child) and note the fallback. (2a-ii owns
  wiring the real index in; 2a-i takes trees as inputs and can be tested with
  fixtures that include the container-collection properties.)
- **Re-serialization is where correctness lives** -- a mis-serialized DFM won't load
  in the IDE. The round-trip fidelity test (parse -> re-emit -> re-parse equals) is
  the load-bearing gate.

## Self-review notes

- Every Batch-2 decision from the 2026-07-10 brainstorm is reflected: structured
  re-emit (not text), #ignore suppression, binary same-resolved-type rule, owned-vs-
  child via Controls/Components membership + proptree element-type match, collection
  relocate-keep-items, require-rules-but-WARN, the two reports (structured here,
  rendered in 2a-iii), moved-depth + events as first-class.
- Pure/headless boundary keeps 2a-i independently provable; I/O + selection +
  freshness-guard + verb are explicitly 2a-ii/iii.
- Reuses Batch 1 types + tree-sitter-dfm; the only new DSL surface is `#ignore`.
