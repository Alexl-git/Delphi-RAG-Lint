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
