# Track 3 -- Component conversion, BATCH 1 (foundation): design

**Date:** 2026-07-09
**Status:** Approved (design); implement via TDD
**Scope:** The FIRST batch of the Track 3 milestone (component conversion,
TOvc* / VCL -> DevExpress cx/dx and similar). This batch ships the FOUNDATION --
the index-driven deep-property enumerator, a reFind-superset conversion-rules
DSL (parse + validate against REAL indexed properties), and an assisted
scaffolder. **Apply (rewriting .pas + .dfm) is DEFERRED to Batch 2.**
**Prior art:** Embarcadero **reFind** (`reFind.exe` + its `#migrate/#unuse/#remove`
rules; samples at `...\Samples\...\FireDAC\Tool\reFind`). We adopt its grammar and
supersede it with real type knowledge.

## Thesis (why this beats reFind and GExperts)

- **reFind** is blind PCRE text matching -- it does not know real properties or
  types, so (per the user) it "mostly doesn't work" for non-trivial conversions.
- **GExperts** does only 1-level type conversion -- it misses deep matches
  (`TDBEdit` vs `TcxDBEdit`: most matches live at `Properties.Sub.X`).
- **drag-lint** has an AST-exact index of the ACTUAL source of both F and T
  (both are registered / on disk; the library index already parsed them down the
  class hierarchy to `TPersistent`). So we can enumerate the REAL deep property
  trees and auto-generate correct conversion links -- semantic, not pattern-guess.

## Property source (settled)

The SQLite index. `symbols` has `kind` (='property'), `name`, `qualified_name`,
`signature` (carries the property's type, e.g. `property Color: TColor read...`),
`parent_id` (owning class), `heritage`; plus `type_ancestors` (class hierarchy,
38k+ rows). To build a class's DEEP property tree:
1. Enumerate `kind='property'` symbols whose `parent_id` is the class (and,
   walking `type_ancestors`, its ancestors up to `TPersistent`).
2. Parse each property's TYPE out of its `signature`.
3. If that type resolves (via the index) to another class, RECURSE into its
   property tree (bounded depth + visited-set for cycles), producing paths like
   `Font.Color`, `Properties.EditFormat`.
No RTTI, no running code, no DFM needed for the tree itself.

---

## Deliverable 1 -- `drag-lint proptree` (the deep-property enumerator)

`drag-lint proptree --qname <TClass> [--depth N] [--to-persistent] [--format text|json] --db PATH [--db ...]`

- Emits the class's recursive property tree: each node = `path` (dotted, e.g.
  `Font.Color`), `type`, `declared_in` (which class in the hierarchy), `kind`
  (scalar | class-typed | enum | set). Recurses into class-typed properties up to
  `TPersistent` (default) or a depth cap.
- Multi-db: first db that resolves the class wins (mirror `DoReverseCallTree`).
- `--format json` -> schema `proptree/1` `{ qname, root_type, properties:[{path,
  type, declared_in, kind, is_class_typed}] }`. text -> an indented tree.
- Bounded: depth cap (default e.g. 6) + a visited-type set so `TWinControl.Parent:
  TWinControl` style back-references terminate.
- Read-only. This is the novel engine that proves we see what reFind/GExperts
  can't; it is independently useful ("show me every property of TcxGrid, deep").
- **Headless-testable:** `run_proptree.ps1` on a fixture with a class whose
  property is itself a class (so recursion is exercised) asserts a deep path
  appears with the right type + `declared_in`.

## Deliverable 2 -- the conversion-rules DSL (reFind superset)

A line-based text rule file (`.conv` or `.rules`), **superset of reFind's
grammar** so existing reFind files parse:

**Adopted from reFind (verbatim semantics):**
```
#unuse <unit>                              remove a unit from the PAS uses clause
#remove <property>                         remove a property (PAS + DFM)
#remove DFM: <property>                    remove a property (DFM only)
#migrate [<Class>:] [<obj>.] <old> -> <new> [, <unit> [, <unit> ...]]
                                           replace identifier/type; optional
                                           class-scope or object-scope; optional
                                           uses-add (one or more units)
<pcre-search> -> <pcre-replace>            raw PCRE line (kept for escape-hatch)
```

**drag-lint SUPERSET additions (what reFind lacks; each is a new `#` directive so
reFind ignores/tolerates or we own the parser):**
```
#convert <FromType> -> <ToType> [, <unit> ...]   declare the type-pair this block
                                                 converts (groups the links; adds
                                                 target uses). The header a batch
                                                 conversion keys on.
#link <ToPath> <- <FromPath>                     deep property assignment: T's
                                                 (possibly nested) path receives
                                                 F's (possibly nested) path.
                                                 Resolves the ambiguous-color case
                                                 (T.Font.Color <- F.Color).
#default <ToPath> = <value>                       set a target property to a
                                                 protocol default when no F source
                                                 maps to it.
#note <text>                                      a human comment carried in the
                                                 rule (documentation).
```

- The DSL is **validated against REAL indexed properties**: `#link`/`#default`
  target paths must exist in T's index-derived property tree (Deliverable 1); a
  `#link` source path must exist in F's -- else a diagnostic (this is the crux of
  "we know real properties/values where reFind only text-matches").
- A **loader/validator** (`DRagLint.Convert.Rules.pas`, pure) parses a rule file
  into a `TConversionRuleSet` record and validates it against the F/T property
  trees, emitting typed errors (unknown target path, unknown source path,
  unresolvable type, unknown unit).
- **Verb:** `drag-lint convert-validate --rules <file> [--db PATH]` -> reports OK
  or a list of rule errors; exit 0/1/2. Headless-testable.

**File organisation:** one rule file per type-pair in a conversions folder (e.g.
`conversions/TOvcEdit-to-TcxTextEdit.conv`), OR a single combined file with
multiple `#convert` blocks. Support BOTH: the loader reads a file OR a folder;
`#convert` headers delimit per-pair blocks so a **batch** conversion (Batch 2)
can apply every matching pair it finds.

## Deliverable 3 -- `drag-lint convert-scaffold` (the assisted author)

`drag-lint convert-scaffold --from <FromType> --to <ToType> [--out <file>] --db PATH`

The value-add over hand-writing reFind rules: since we enumerate BOTH trees
(Deliverable 1), we auto-generate a rules file pre-filled with the matches we can
infer, leaving only the genuinely ambiguous ones as TODO for the user:

1. Enumerate F's and T's deep property trees.
2. **Unambiguous auto-links:** where a T path and an F path match by name+type
   (exactly one candidate each side) -> emit a ready `#link ToPath <- FromPath`.
3. **Ambiguous (the color case):** where multiple F paths could feed one T path
   (or vice versa) -> emit a `#link ToPath <- ???` with a `#note` listing the
   candidate F paths, for the user to choose.
4. **T-only (no F source):** emit `#default ToPath = <T's own default if known,
   else ???>`.
5. **F-only (no T target):** emit a `#note DROPPED FromPath (no T target)` so
   nothing is silently lost.
6. Emit the `#convert From -> To` header + a best-guess `#unuse`/uses-add from
   the F/T declaring units (from the index).

Output is a valid (if partially `???`-stubbed) rule file the user finishes by
hand -- turning "author reFind PCRE by guesswork" into "fill in the few real
ambiguities." Headless-testable: `run_convert_scaffold.ps1` asserts the emitted
file has the `#convert` header, >=1 concrete `#link`, and `???` stubs only where
genuinely ambiguous.

---

## FUTURE (user-flagged 2026-07-09, needs its own brainstorm)

- **Convert SELECTED components on a live form (IDE-driven, interactive).** Beyond
  the CLI batch/file conversion: let the user pick specific components on a form in
  the IDE and convert just those, using the validated rule sets. This is an IDE
  feature (component selection UI + apply) that builds on the Batch 1 foundation +
  Batch 2 apply. **Needs a dedicated brainstorm** (selection model, which OTA
  form-designer APIs expose the selected components, how apply targets one instance
  vs the whole type). Deferred until the CLI foundation + apply are proven.

- **Value SPLIT / MERGE across F<->T properties, via a small expression interpreter
  (user-flagged 2026-07-10).** A 1:1 `#link ToPath <- FromPath` is not always enough:
  sometimes ONE source property packs SEVERAL values that must be BROKEN OUT into
  several target properties (F.combined -> T.a, T.b, T.c), and sometimes SEVERAL
  source properties must be ASSEMBLED into one target (F.a, F.b -> T.combined). To
  express those, the conversion DSL needs a SMALL, SAFE EXPRESSION LANGUAGE on the
  RHS of a link/default -- e.g. `#link T.Width <- Extract(F.Bounds, 'w')` (split) and
  `#link T.Bounds <- Format('%d,%d', [F.Left, F.Top])` (merge), or a compact infix
  form. **Needs its own brainstorm/spec** covering: the interpreter's grammar +
  evaluator (a tiny pure expression engine -- string/number ops, a handful of
  built-ins like substring/split/join/format, NO Turing-completeness), how it plugs
  into `convert-validate` (validate that referenced F/T paths exist AND that the
  expression parses/type-checks) and `convert-scaffold` (leave a `???`-expression
  stub the user fills), and the APPLY side (Batch 2+) that actually evaluates it
  against a component instance's real values. This is an ADDITION on top of the
  1:1-link foundation shipped in Batch 1 -- the basics land first, then this.

## BATCH 2 (apply) -- scope decided in brainstorm 2026-07-10 (spec: separate 2a-i/ii/iii docs)

The apply milestone. Decisions locked with the user; each sub-batch gets its own
spec+plan+build (brainstormed one at a time). Engine is pure Object Pascal,
deterministic, CLI-first, headless -- NO LLM (the "conversion model" is the DSL /
rule text file, not an AI model). NO IDE until the engine is proven.

**The value proposition (what GExperts CANNOT do):** GExperts converts a selected
component on a form but rewrites the DFM ONLY (never the .pas), does 1-level type
mapping, and cannot map events. drag-lint's apply rewrites FOUR surfaces and
handles moved-depth properties AND events, using the AST/index:
1. `.pas` DECLARATION type (Edit1: TOvcEdit -> TcxTextEdit).
2. `.pas` USES clause (add T's unit via find-unit; optional #unuse F's unit).
3. `.dfm` component block -- a FULL STRUCTURED RE-EMIT (not text replace): parse F's
   object block into a property/event tree, remap each leaf to its T path (which may
   be DEEPER or SHALLOWER -- e.g. F.Font.Size -> T.Style.Active.Font.Size), create
   intermediate sub-objects as needed, re-serialize a well-formed T block. Same for
   EVENTS (OnClick etc., which DevExpress nests 2-3 deep -- GExperts can't match).
4. `.pas` PROPERTY/EVENT ACCESSES at every use site of a converted instance
   (Edit1.Caption := x -> Edit1.Text := x) via the ref index -- the differentiator
   that leans on ref-gaps D/E.

**Selection model (core, not deferred):** convert ALL instances of a class (all
TOvcEdit), ALL of a KIND (a named group like "BDE" = several FromTypes), or NAMED
component(s) (just Edit1, DBGrid2). Each scoped to ONE unit (.pas+.dfm) OR the whole
PROJECT. (Mirrors GExperts' "this one / these selected / these classes" choice but
adds pas + project scope.)

**T-tree shape source:** Batch 1's `proptree` (the index) gives T's DEEP property
tree; the `#link ToPath <- FromPath` rule carries the full dotted T path. Apply
places each mapped value at its ToPath, creating intermediate sub-objects, validated
against proptree. **FRESHNESS GUARD REQUIRED:** verify the index is current for the
F and T component types before relying on it (mtime/sha vs disk; warn/refuse on
stale/unindexed type) -- a stale index would produce a wrong T-tree shape.

**Property RENAME uses `#link`** (Text <- Caption): apply reads it as rename in DFM
+ rewrite `.Caption`->`.Text` in pas on converted instances. `#default` sets a
T-only property's value. (No new directive; convert-scaffold already emits these.)
Split/merge (one F -> several T, or several F -> one T) + the small expression
interpreter are DEFERRED past 2a (see the FUTURE item below); 2a is 1:1 `#link` +
`#default` only.

**Safety = revert stack (not just per-file .bak):** before an apply action, back up
each touched file AND record the touched paths in a stack/manifest, so the user can
REVERT a whole conversion action as a unit later. Dry-run by default (unified diff,
no writes); --apply writes; re-validate the rule set before applying.

**Rules persistence + a growing conversion LIBRARY:** save every rule set so a
re-run/redo starts from the last setting, not scratch. SEED a new conversion from a
similar one (TOvcDBEdit -> TcxDBTextEdit populates from TOvcEdit -> TcxTextEdit's
shared base, then DB-specific props are hand/assisted-edited). The library grows as
users convert more.

**2a decomposition (3 sub-specs, built in order -- each provable headless):**
- **2a-i:** the structured DFM component RE-EMIT engine (pure unit): parse an F
  object block -> in-memory property/event tree -> remap each leaf to its T path
  (proptree-validated, intermediate sub-objects created) -> re-serialize a
  well-formed T object block (indentation, nested sub-objects, events, binary/
  collection/item values preserved or defaulted). Headless, no file I/O.
  Foundation for ii+iii.
- **2a-ii:** the `.pas` side (rewrite decl type + uses via find-unit + property/
  event ACCESS rewrite via the ref index) + the SELECTION model (class / kind /
  named x unit / project) + the index-freshness guard.
- **2a-iii:** the `convert-apply` verb tying i+ii together + the REVERT STACK +
  rules persistence / library seeding. Dry-run/--apply/--no-backup contract.

**OWNED PART vs CONTAINED CHILD (decided 2026-07-10):** In a DFM, a contained child
control (Edit1 on a TPanel) AND an owned composed part (a TTable's persistent TField,
a TcxDBTreeList's TcxDBTreeListColumn) BOTH appear as a nested `object` node -- the DFM
syntax does not distinguish them. The RECOGNITION RULE (index-derived): a nested object
that is a member of the parent's `Controls`/`Components` container collections is a
CONTAINED CHILD -> LEAVE ALONE (convert the container, not its independent children).
Any OTHER nested object is a COMPOSED PART of the parent (a field/column/sub-object) ->
it must be converted WITH the parent, which REQUIRES a #convert rule set for its element
type. Match the nested object's class against the parent's collection/composition
property element types via proptree (TDataSet.Fields -> TField; TcxDBTreeList.Columns ->
TcxDBTreeListColumn). TField IS a TComponent (so "is a TComponent" does NOT distinguish
it) but is NOT in Controls/Components -- it's in Fields -> owned part. (Verified against
CompGroup2.dfm: RzPanel2/TRzPanel contains TcxButton children [leave]; cxDBTreeList1/
TcxDBTreeList contains TcxDBTreeListColumn columns [owned -> convert].)
- **REQUIRE rules but WARN, do not refuse:** when apply descends into an owned part and
  no #convert rule exists for its type, emit a clear WARNING ("TTable converted but its
  Fields need TField -> TXXField rules -- not converted") and leave those parts
  unconverted. NEVER silently half-convert. Warn (not refuse) because a big component is
  converted via lots of trial-and-error before committing -- refusing would block
  iteration. convert-scaffold can pre-generate the per-owned-part-type rule stubs.
- **COLLECTION relocate-keep-items:** sometimes F and T share the SAME element type
  (TTable.Fields and TXXTable.Fields both hold TField) OR the collection just MOVES to a
  different T path (TTable.Fields -> TXXTable.Data.Fields) without item-type change. The
  DSL needs a COLLECTION-LEVEL #link that moves the whole collection and keeps its items
  as-is (no per-item conversion) -- distinct from descending to convert each item.

**Two eventual parts (the second is a later, separate milestone):**
1. The ENGINE (above) -- CLI, deterministic, flat-text rule model.
2. An IDE MODEL-EDITOR -- edits the rule model with assistance: flatten F's deep
   tree to a flat list, auto-assign unambiguous F->T leaves, and a T-SIDE PROPERTY
   NAVIGATOR WITH SEARCH (type "font" -> jump to T.Style.Default.Font instead of
   walking each level). Presented as a GRID, stored as the DSL text. Its own
   brainstorm AFTER the engine is proven.

## Explicitly OUT of scope (Batch 2+)

- **Apply** -- rewriting the `.pas` field type + `uses` and the `.dfm` component
  block from a validated rule set. (Batch 2; will reuse `uses-fix`/Find-Unit for
  the uses side and `tree-sitter-dfm` for the DFM block.)
- Batch conversion "on everything found" (scan a project for all F instances and
  apply) -- Batch 2/3.
- An IDE action -- CLI-only for this whole milestone until apply is proven.
- A human-friendly DSL sugar layer beyond the reFind superset -- only if the
  superset proves clunky in real use.

## Files (Batch 1)

- `src/report/DRagLint.Convert.PropTree.pas` -- the pure deep-property enumerator
  (index-driven; the reusable engine behind `proptree` + the scaffolder).
- `src/report/DRagLint.Convert.Rules.pas` -- the reFind-superset DSL parser +
  `TConversionRuleSet` + validator (pure).
- `src/cli/DRagLint.CLI.pas` -- `DoPropTree`, `DoConvertValidate`,
  `DoConvertScaffold` verbs + dispatch + usage lines.
- Tests: `run_proptree.ps1`, `run_convert_rules.ps1` (parse+validate a sample
  incl. an adopted reFind snippet), `run_convert_scaffold.ps1`.
- Docs: CHANGELOG, README (the 3 verbs + the DSL summary), a new
  `docs/CONVERSION-RULES.md` (the DSL reference, crediting reFind), AI-USAGE.

## Testing / verification

All three verbs are read-only + headless. TDD each. Full battery re-run for no
regression. NO BPL (CLI-only). Ships in a version bump with H1/H2 (or its own
tag -- decide at release).

## Risks / notes

- **Signature type-parsing:** extracting the property type from `signature` text
  must handle `read/write`, generics, and qualified types. Start pragmatic (the
  token after the property name up to `read`/`;`), harden against real DevExpress
  signatures from the library index. If a type can't be parsed, mark the node
  `type=unknown` (don't fabricate) -- same discipline as the tree-sitter
  "unknown" fallback.
- **Recursion blow-up:** DevExpress property trees are deep + cross-referential;
  the depth cap + visited-type set are load-bearing. Log/emit a `truncated` flag
  when the cap stops expansion (like `TRCallSummary.Truncated`).
- **Property vs published:** default to published + public properties (the ones
  that matter for DFM/conversion); note the visibility filter.
