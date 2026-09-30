# Conversion Rules DSL (Track 3, Batch 1)

`drag-lint`'s component-conversion foundation: an **index-driven** way to plan a
component/type migration (for example `TDBEdit` -> `TcxDBEdit`, or any
`TPersistent`-rooted class to another) from the REAL, AST-exact property trees of
both types, and a small **reFind-superset** rule language to record the plan.

Batch 1 is the **read-only foundation**: three CLI verbs let you inspect the
property trees, auto-draft a conversion-rules file from them, and validate that
file's paths against the trees. Batch 2 (`convert-apply`) is **shipped**: it
applies a validated rule set for real, rewriting `.pas` + `.dfm` on disk (dry-run
by default, `--apply` to write, with automatic backups). See
[Batch 2 (apply)](#batch-2-apply-shipped) below for the full workflow, the 5
conversion surfaces, and what is still deferred (split/merge, the expression
interpreter, full default-value fidelity).

> **Driving a conversion end-to-end (agents):** this file is the DSL + design
> reference. For a task-oriented, step-by-step procedure -- ensuring both types
> are indexed, scaffold -> validate -> dry-run -> apply -> verify-by-compile,
> with the real freshness-guard messages and index-gap fixes -- follow
> [`AI-CONVERT-RUNBOOK.md`](AI-CONVERT-RUNBOOK.md).

## Why this exists (the thesis)

Two existing tools solve pieces of the "convert one component type to another"
problem, and both fall short in the same way:

- **RAD Studio's reFind** is blind PCRE text-matching. Its rule file is a list of
  regex find/replace and a few `#` directives; it has no idea what properties a
  type actually has, so it cannot tell you a `#link` target is a typo, and it
  cannot find where the real work is.
- **GExperts' component conversion** does only **one level** of type conversion.
  It maps the top-level component but misses the deep matches -- and for pairs
  like `TDBEdit` vs `TcxDBEdit` **most** of the interesting properties live one or
  two levels down (`Properties.Sub.X`, `Style.Font.Color`, ...), not on the
  component itself.

`drag-lint` already has an **AST-exact index** of BOTH source trees, down to
`TPersistent`. So it can:

1. **Enumerate the REAL deep property trees** of the source and target types
   (own + inherited, recursing into class-typed properties) -- `proptree`.
2. **Auto-generate a correct, pre-filled conversion-rules file** from those two
   trees, matching by leaf-name + type, and leaving only the genuine ambiguities
   for a human -- `convert-scaffold`.
3. **Validate** a rules file's `#link`/`#default` paths against the real trees,
   catching path typos reFind cannot -- `convert-validate`.

The result: instead of authoring reFind rules by guesswork, you fill in the few
real ambiguities in an already-valid draft.

## Lineage and credit

The rule language is a **strict superset** of Embarcadero's **reFind** tool (the
FireDAC migration utility). We adopt reFind's directives verbatim and add four
new `#` directives that reFind does not have. Credit to Embarcadero reFind for the
grammar lineage.

reFind ships with RAD Studio. The tool, its `readme.txt` (rule-format reference,
section 3.2), and the real BDE/ADO/DBX/IBX migration rule samples are here:

```
C:\Users\Public\Documents\Embarcadero\Studio\37.0\Samples\Object Pascal\Database\FireDAC\Tool\reFind\
```

(`readme.txt` plus the `BDE2FDMigration`, `ADO2FDMigration`, `DBX2FDMigration`,
`IBX2FDMigration`, ... sample subfolders.)

## The verbs

All four are **read-only, CLI-only, headless.** `proptree`, `convert-scaffold`
and `convert-validate` resolve their index DBs from the manifest (or from
repeated `--db PATH`), and with multiple `--db` the FIRST db that resolves the
qname (symbol ids are per-DB) wins. `glyph-vacuum` walks `--root` folders
directly (not the index) and treats `--db` as optional per-class enrichment.

### 1. `proptree` -- deep property enumerator

```
drag-lint proptree --qname <TClass> [--depth N] [--no-to-persistent]
                    [--min-visibility published|public]
                    [--format text|json] --db PATH [--db ...]
```

Walks a class's `property` symbols (own **and** inherited), parses each property's
type from its indexed signature, and recurses into class-typed property types --
producing flattened dotted paths (`Font.Color`, `Sub.Color`). By default it stops
the ancestor climb at `TPersistent`/`TObject`; `--no-to-persistent` climbs past.
Recursion is depth-capped (default **6**) with a visited-type cycle guard. Each
visited class's own **fields** and class-scoped **consts** are also walked and
emitted as flat leaves (`member_kind: "field"` -- see below; never recursed into,
even when class-typed).

A re-declared / inherited property (for example `property Color;`, which the index
stores with an empty signature) resolves its type from the first ancestor
declaration that carries one; if none does, it is emitted as `type=unknown`,
`kind=unknown`, and is NOT recursed into (types are never fabricated).

Text output (real, from a fixture where `TFrom` has `Color`, a class-typed `Sub`,
and `Gone`):

```
$ drag-lint proptree --qname ConvFix.TFrom --db convfix.sqlite
TFrom  (4 properties)
Color: Integer [scalar]
Sub: TSub [class]
  Color: Integer [scalar]
Gone: Integer [scalar]
```

The indent is the path's dot-depth, so the nested `Sub.Color` leaf reads under
`Sub`. A real VCL example -- `Vcl.StdCtrls.TLabel` -- shows the deep recursion the
thesis is about: its class-typed `Font` property expands into `Font.Family`,
`Font.Style`, ... rather than stopping at `Font`.

JSON output uses schema **`proptree/2`** (additive over the earlier
`proptree/1`: adds `visibility`, `is_writable`, `member_kind` per leaf plus a
class-accurate concrete `type` -- every `proptree/1` field is kept, so a
consumer written against `proptree/1` still parses this fine, it just
doesn't look at the new keys):

```
$ drag-lint proptree --qname Vcl.Graphics.TFont --format json --db library-Win64.sqlite
{
  "schema": "proptree/2",
  "qname": "Vcl.Graphics.TFont",
  "root_type": "TFont",
  "truncated": false,
  "properties": [
    {
      "path": "Color",
      "type": "TColor",
      "declared_in": "Vcl.Graphics.TFont",
      "kind": "scalar",
      "is_class_typed": false,
      "visibility": "published",
      "is_writable": true,
      "member_kind": "property"
    }
  ]
}
```

`truncated` is `true` when the depth cap stopped an expansion. `is_class_typed`
marks the paths that recursion descended into. `type` is the class-accurate
CONCRETE per-class type -- e.g. on `TcxCheckBox`, `Properties` resolves to
`TcxCheckBoxProperties`, never a same-named sibling class's type.

The three `proptree/2` leaf fields:

- **`is_writable`** (bool) -- would assigning to this leaf be valid? For a
  property, `true` unless the resolved accessor is read-only (`prop_access =
  'ro'`; a write-only `'wo'` accessor IS still a valid assignment target).
  For a field leaf, `true` except a typed class constant (Object Pascal
  constants are never assignable). **Defaults to `true` when absent** --
  reading a pre-v17 / un-re-indexed DB behaves exactly like `proptree/1`
  (today's "everything is a candidate target" default).
- **`visibility`** (string) -- the EFFECTIVE, most-derived member visibility:
  `"published"` \| `"public"` \| `"protected"` \| `"private"` \| `""`
  (unresolvable). Delphi's `strict private`/`strict protected` are collapsed
  to `"private"`/`"protected"` (the strict/non-strict distinction is
  same-unit-only, irrelevant to cross-unit assignability). **Defaults to
  `""` when absent.**
- **`member_kind`** (string) -- `"property"` for a property leaf, `"field"`
  for a flat field/class-const leaf (see above). **Defaults to `"property"`
  when absent.**

A new **`proptree --min-visibility published|public`** flag filters the
EMITTED leaves by effective visibility (applies to both `text` and `json`
output): unset (default) emits ALL leaves, exactly as `proptree/1` did
(back-compat); `published` emits only published leaves AND never emits a
field (fields, even published ones, are never DFM-streamable -- this is a
member_kind-based exclusion, the node's own reported `visibility` is
untouched); `public` emits published+public leaves, including public fields.

Exit codes: **0** ok; **1** qname does not resolve to a class in any db; **2**
usage error / an explicit `--db` that does not exist / invalid `--min-visibility` value. A named `--db` that is missing is always exit 2 -- never a tree built from the remaining databases.

### 2. `convert-scaffold` -- auto-draft a rules file

```
drag-lint convert-scaffold --from <FromType> --to <ToType>
                           [--out <file>] [--surface dfm|pas] --db PATH [--db ...]
```

Enumerates BOTH deep property trees (via `proptree`'s engine) and emits a VALID,
pre-filled reFind-superset rules file. Output is deterministic (paths sorted).
Auto-`#link`/`#default` TARGETS (the `To` side only -- `From` remains an
unrestricted candidate source pool) are restricted to leaves that are actually
**valid assignment targets**, using the `is_writable`/`visibility`/
`member_kind` fields `proptree/2` stamps onto every leaf (see above --
convert-scaffold's `To` tree comes from the same `BuildPropTree` call, so no
extra flags are needed to get the data, only `--surface` to pick the bar):

- **`--surface dfm`** (the default) requires `member_kind='property'` AND
  effective `visibility='published'` -- the DFM-streamable surface, matching
  today's dominant component-conversion use case.
- **`--surface pas`** relaxes the bar to `visibility` in
  (`published`,`public`) and ANY `member_kind`, so a public FIELD can be a
  target too.
- On EITHER surface, `is_writable=false` (a read-only property, or a typed
  class constant) is NEVER a valid target.
- A `To` path that fails the bar is fully excluded -- no `#link`, no
  `#default`, no `#note` -- mirroring how `proptree --min-visibility` silently
  drops a tier-failing leaf. On a `proptree/1`-shaped (pre-v17 / un-re-indexed)
  DB every leaf reads as writable/unresolvable-visibility, so the filter
  degrades to prior (unfiltered) behavior via the documented defaults.

For each target (`To`) path that passes the surface bar, it looks for source
(`From`) paths whose **leaf name** matches (case-insensitive) AND whose
declared **type** is compatible:

- **exactly one** compatible source -> a concrete `#link ToPath <- FromPath`;
- **more than one** -> `#link ToPath <- ???` followed by `#note candidates: ...`
  (a genuine ambiguity for you to resolve);
- **zero** -> `#default ToPath = ???` (target-only property, no source).

Source paths with no compatible target become `#note DROPPED FromPath (no T
target)`. The header is a `#convert From -> To` line (with a best-guess `, unit`
uses-add taken from the qname unit prefixes when discoverable -- never
fabricated).

Real output for the same fixture (`TFrom` -> `TTo`):

```
$ drag-lint convert-scaffold --from ConvFix.TFrom --to ConvFix.TTo --db convfix.sqlite
#convert ConvFix.TFrom -> ConvFix.TTo
#note scaffold: review every ??? -- concrete #link lines are inferred by leaf-name+type
#default Caption = ???
#link Color <- ???
#note candidates: Color, Sub.Color
#link Sub <- Sub
#link Sub.Color <- ???
#note candidates: Color, Sub.Color
#note DROPPED Gone (no T target)
```

`--out <file>` writes an ASCII/CRLF file; omit it for stdout. Every concrete path
emitted is guaranteed to exist in the real trees and every `???` is tolerated by
the validator, so the draft round-trips clean through `convert-validate`.

Exit codes: **0** success; **1** either type is unresolved in every db (the verb
names it); **2** missing `--from`/`--to`, invalid `--surface` value (must be
`dfm`\|`pas`), or an explicit `--db` that does not exist. Rules scaffolded from a narrowed corpus would be silently wrong, so a missing `--db` refuses outright.

### 3. `convert-validate` -- check a rules file

```
drag-lint convert-validate --rules <file> [--from <FromType>] [--to <ToType>]
                           [--print-parsed] --db PATH
```

Parses a rules file and, when `--from`/`--to` types are supplied, validates its
`#link`/`#default` **paths** against the REAL members of those types. This is the
crux reFind cannot do: reFind is blind PCRE text; we know the real properties, so a
`#link` target/source typo is a validation error, not a silent no-op.

**How a path is resolved (1.20.6).** No property tree is built. Each path is
resolved SEGMENT BY SEGMENT against a per-class member cache (`proptree`'s own
per-member resolution, each class resolved once per run), so there is no depth
limit and `--depth` does not apply -- a 9-segment path validates as readily as a
1-segment one, and the BDE book's TQuery block checks in seconds (the old depth-6
tree of `FireDAC.Comp.Client.TFDQuery` did not finish in 20 minutes). A rule path
names a `.dfm`-streamed property, so the `.dfm` rule applies: the LEAF must be a
published property; each INTERMEDIATE hop must be published, or public AND
class-typed (a collection's public `Items`, which a `.dfm` streams as `item`
blocks); a protected hop, a public leaf or a field does not pass. **Private and
strict private members never resolve** (and `proptree` no longer lists them). A
hop may not pass through a type already passed through on the same path (the
same cycle guard `proptree` applies).

**Unreachable paths are warnings, not errors (1.20.6, owner ruling
2026-09-30).** A path can fail in two different ways, and they are reported
differently:

- **NOT FOUND** -- some segment names no member at all on its hop (a typo, a
  member of another class), or an intermediate hop has no children to name: a
  scalar or other NON-class-typed hop, a field, or a referenced component --
  whatever its visibility. This is an **error**: `line N: link FromPath not
  found in --from tree: <path>`, exit 1.
- **UNREACHABLE** -- every segment names a member that EXISTS, but one of them
  is inaccessible on the `.dfm` surface: private or strict private anywhere,
  protected anywhere (a class-typed hop included), or a public LEAF (a public
  field leaf too). This is a **warning**, the rule is KEPT in the book, and
  exit stays 0.

A path that runs INTO a private member stops there: the private member's type
is never expanded, so nothing after it is checked. `FPriv.Typo` is therefore
UNREACHABLE naming `FPriv`, not NOT FOUND -- the misspelled tail is not looked
at. (A protected or public hop is still descended, so `ProtPart.Typo` IS NOT
FOUND.)

The warning text, exactly (one line, printed on **stdout** beside the errors):

```
line N: warning: <path>: <Member> is <visibility> in <DeclaringClass>; never applied unless a descendant class changes its visibility
```

`<Member>` is the FIRST offending segment, `<visibility>` its visibility as
declared (`private`, `strict private`, `protected`, `public`, `published` for a
field), and `<DeclaringClass>` the qualified class that declares it. When a
class redeclares an ancestor's member in a private section, the warning names
the REDECLARATION (the descendant, `private`), not the ancestor's member.

Why a warning: such a rule is like `if 1 > 2 then ...` -- no `.dfm` can stream
the member, so the rule never fires. It can still be right to keep it: a
descendant class (`TMyTable = class(TTable)`) may republish the member, and then
the same rule applies to that descendant. The BDE book's 16 `FieldOptions.*` and
`Constraints.Items.*` links (protected in `Data.DB.TDataSet`) are exactly this
case.

`convert-apply` and the hidden `convert-reemit` SKIP what is unreachable, per
`#convert` block (the block of the component being converted), keep
converting everything else, and report it:

- a `#link` or `#default` line with an unreachable path is not applied;
- a `#mapping` line keeps its place (branches are still tried in order, first
  match wins) and loses only its unreachable TARGETS: a value matching that
  branch sets the branch's reachable targets and never falls through to a
  later `#when` or `#else`;
- a `#mapping` whose `#when` SOURCE path is unreachable is skipped WHOLE for
  that block -- no branch and no `#else` fires (the conservative reading: that
  branch can never match, and letting another branch write in its place would
  set a value nobody chose);
- a mapping applied by two blocks is judged per block: reachable in one and
  unreachable in the other, it still applies in the first, and the warning
  names the second block's class only.

Reporting: text mode prints the same `line N: warning: ...` line under
`Warnings:`; apply/1 JSON appends the same text to the string array
`warnings[]`, mirrors it in `items[]` as kind `rule-path-unreachable`, and adds
one object per path to `unreachable[]` (always present, `[]` when none):

```
{ "line": 274, "path": "FieldOptions.AutoCreateMode", "member": "FieldOptions",
  "visibility": "protected", "class": "Data.DB.TDataSet", "reason": "unreachable",
  "message": "line 274: warning: FieldOptions.AutoCreateMode: FieldOptions is protected in Data.DB.TDataSet; never applied unless a descendant class changes its visibility" }
```

`convert-validate` has no JSON mode; its warnings are text lines only.

- Without `--from`/`--to` it is **parse-only**: only unknown-directive parse
  errors surface; path checks are skipped.
- A literal `???` path is an **explicit-unfilled stub** (what the scaffolder
  emits) -- tolerated, not an error.
- `--print-parsed` dumps `parsed N rule(s)` plus one `line L: kind ...` summary
  per rule (handy for confirming a parse with no trees).

Clean validation prints `OK`:

```
$ drag-lint convert-validate --rules rules.txt --from ConvFix.TFrom --to ConvFix.TTo --db convfix.sqlite
OK
```

A bad target path is reported with its 1-based line number:

```
$ drag-lint convert-validate --rules bad-rules.txt --from ConvFix.TFrom --to ConvFix.TTo --db convfix.sqlite
line 4: link ToPath not found in --to tree: Sub.Nonexistent
```

#### Glyph expressions -- `#link <ToPath> <- <FromPath> G[I/N] ... [: <Cast>]`

A `#link` may carry a **glyph expression** after its FromPath (design:
`docs\superpowers\specs\2026-09-17-glyph-strip-G-grammar-design.md`):

| term | meaning |
|---|---|
| `G[I/N]` | glyph slot I of a source known to hold N glyphs |
| `G[I]` | slot I of the source's ACTUAL count |
| `G[*/N]` | all N slots in order (the identity for that N) |
| `G[count]` | an integer: the number of terms in the alternative chosen for the sibling image link on the same FromPath |

Terms written side by side stitch into one image (`G[1/6]G[2/6]`); commas
separate **per-N alternatives** (`G[*/4], G[1/5]G[2/5]G[3/5]G[4/5]` = "when the
source holds 4 take all four, when it holds 5 take the first four"). Spaces are
allowed between terms and around commas, never inside `G[..]`. The cast suffix is
split off first, then the expression at the first ` G[`, so FromPath is still the
bare source property the `--from` tree check sees.

`convert-validate` checks every expression **in parse-only mode too** (no tree is
needed) and names the column inside the expression. Errors: a malformed term;
`I < 1`, `N < 1` or `I > N` (a `G[I]` is bounded by the N its alternative's
denominators fix); two denominators in one alternative; two alternatives for one
N; two denominator-less alternatives; `G[count]` anywhere but as the whole
expression; and a `G[count]` link without **exactly one** image link from the same
FromPath in its `#convert` block. A straight carry of a glyph-count property
(`NumGlyphs`, `GlyphCount`, `NumStates`, `ImageCount`) beside a G-link in the same
block is a **warning** -- printed as `line N: warning: ...`, it never changes the
exit code:

```
$ drag-lint convert-validate --rules glyph.rules
line 2: link OptionsImage.Glyph <- Picture: G-expression column 27: slot 6 exceeds its count 5 (in "G[*/4], G[1/5]G[2/5]G[3/5]G[6/5]")
line 4: link Glyph2 <- Picture: G-expression column 9: two alternatives for N=4 -- at most one alternative may apply to a given N (in "G[1/4], G[*/4]")
line 3: warning: link OptionsImage.NumGlyphs <- NumGlyphs is a straight carry of the source glyph count beside the G-link on line 2 -- right only for identity alternatives; write "#link OptionsImage.NumGlyphs <- Picture G[count]" instead
```

`--print-parsed` shows the expression as its own field:
`line 2: link OptionsImage.Glyph <- Picture [glyph G[*/4], G[1/5]G[2/5]G[3/5]G[4/5]] [cast AssignGraphic]`.

**Not yet realised.** Extracting and stitching the slots is the next build
(CV-2). Until it lands, `convert-apply` (and the hidden `convert-reemit`)
**refuse** a book whose `#link` carries a glyph expression (exit 1, one
`line N: ... not yet realised` line per G-link) instead of carrying the source
image whole. Also still to come with CV-2: the validate error for a G-link on a
source class that has no N reader in `docs\GLYPH-CLASSES.md`.

Exit codes: **0** valid / parse-ok (warnings allowed); **1** errors found (parse or
validation); **2** bad args (no `--rules`) or unreadable rules file.

### 4. `glyph-vacuum` -- measure before you rule

```
drag-lint glyph-vacuum --root <D> [--root <D> ...] --out <D> [--append] [--db <X> ...]
```

Before writing a `#link`/`G[I/N]` glyph rule, measure every streamed graphic
under the legacy roots. Five outputs land under `--out`: `instances.tsv`,
`classes.tsv`, `skipped.tsv`, an `images\` folder of extracted payloads, and a
reviewable `gallery.html`. `--append` merges a rescan into an existing run by
`(dfm_path, object_path, property)` identity, so re-running the vacuum is
idempotent. A binary `.dfm` is converted in memory with `ObjectBinaryToText`
(not `ObjectResourceToText`) before parsing, so binary and text `.dfm` are
measured alike.

`instances.tsv` is one row per component+graphic property -- wrapper, format,
size, bpp, the streamed count property + value, its declared default, the
inferred N and whether they agree, and a payload sha. When the `.dfm` streams
no count property (its value equalled the class's own default, so Delphi
omitted it) and `--db` resolves the class, the count property and its default
are instead read off the CLASS's own property tree, so `count_default` can
still be reported. `classes.tsv` rolls instances up per class: N-distributions,
disagreements between instances of the same class, and `runtime_refs` (code
that touches the property outside the `.dfm`).

## The rule language

Blank lines and lines beginning `//` or `;` are ignored. An unknown `#directive`
is captured as a parse error (never raised).

### reFind directives (adopted verbatim)

| Directive | Meaning |
|---|---|
| `#unuse <unit>` | remove a unit from the PAS `uses` clause |
| `#remove <property>` | remove a property from PAS and DFM |
| `#remove DFM: <property>` | remove a property from the DFM only |
| `#migrate [<Class>:] [<obj>.] <old> -> <new> [, <unit> ...]` | replace `old` with `new`; optional class-scope / object-scope; optional uses-add(s) |
| `<pcre-search> -> <pcre-replace>` | raw PCRE find/replace (escape hatch: any non-`#` line containing ` -> `) |

Real reFind sample lines (from the BDE2FD sample):

```
#unuse BDE.DBTables
#remove SessionName
#remove DFM: Origin
#migrate TTransIsolation -> TFDTxIsolation, FireDAC.Stan.Option
#migrate ukModify -> arUpdate, FireDAC.Phys.Intf
```

(readme.txt documents a single trailing unit; our superset accepts one-or-more
`, U [, U ...]`, which is harmless.)

### drag-lint superset directives (new)

| Directive | Meaning |
|---|---|
| `#convert <From> -> <To> [, <unit> ...]` | declares the type-pair this block converts (groups the links; optional target uses-add) |
| `#link <ToPath> <- <FromPath>` | deep property assignment. **Note the `<-` arrow** -- reversed vs `#migrate`'s `->`. Read it "target gets source." **Type-identity carry (2026-09-16):** when both sides are CLASS-TYPED and of the SAME class (`#link Font <- Font`, both `TFont`), every sub-leaf the `.dfm` streams under the source (`Font.Charset`, `Font.Name`, ...) is carried to the same leaf under the target automatically -- the five hand-written `Font.*` lines become one. When the types DIFFER (`OptionsImage.Glyph <- Picture`, `TdxSmartGlyph <- TPicture`) nothing is carried implicitly and every dotted leaf must be named, because an invented target path is how a form stops loading. An explicit per-leaf `#link` / `#ignore` / `#remove` always wins over the carry; a carried leaf is reported (`sub-leaf-carried` in `convert-apply --format json`, `report.carried[]` in `convert-reemit`) so the leaves nobody typed are visible. Not implemented: the "target type is an ancestor of the source type" case -- the engine has no class graph, so that still needs explicit leaves. |
| `#default <ToPath> = <value>` | set a target property to a default when no source maps to it |
| `#ignore <FromPath>` | acknowledge an F property/event is intentionally NOT mapped -- suppresses its unmapped-non-default warning (other unmapped props still warn). Added in Batch 2a-i for the re-emit engine. |
| `#note <text>` | a human comment carried in the rule (the scaffolder emits `candidates:` and `DROPPED` notes) |
| `#use <unit>` | add a unit to the PAS `uses` clause (the companion to reFind's `#unuse`) |
| `#useswap <Old> -> <New1> [, <New2> ...]` | replace unit `<Old>` with one-or-more `<New>` units. Sugar for `#unuse Old` + `#use New1` + `#use New2` ... |

Example superset block:

```
#convert ConvFix.TFrom -> ConvFix.TTo, ConvFix
#link Sub.Color <- Sub.Color
#link Color <- Sub.Color
#default Caption = 'untitled'
#note Color was ambiguous; resolved to the nested source
```

`#link`/`#default` **ToPath** must exist in the `--to` tree; `#link` **FromPath**
must exist in the `--from` tree (unless it is the `???` stub). That is exactly what
`convert-validate` checks.

### Unit replacement: `#use` / `#useswap`

`#use`/`#useswap` manage the target `.pas` `uses` clause. They are **file-level**
(they may live outside any `#convert` block), so a standalone swap such as
`#useswap FOLDERDEF -> imcFOLDERS` stands on its own. `#useswap Old -> New1, New2`
is exactly `#unuse Old` + `#use New1` + `#use New2`.

The **converter editor** ("Unit Rules" tab) authors these and can **auto-derive**
them from the `#convert` blocks: each To-type's declaring unit becomes a `#use`,
each From-type's a `#unuse`. Normalization (the "no doubles" rule, shared with the
apply path) is:

- **ADD** = every `#use` + every `#useswap` New + every `#convert` trailing unit;
- **REMOVE** = every `#unuse` + every `#useswap` Old;
- add each ADD unit only if not already present; a unit in both sets -> **ADD wins**
  (it is needed), reported as a conflict.

_Status:_ **executed by `convert-apply` since 1.20.6** (`info --json` ->
`capabilities.apply_unit_rules: true`). Per unit: remove Old from whichever clause
holds it; add each New once (case-insensitive, never a duplicate in either section)
into the section Old was in; a `#useswap` whose Old the unit does not use makes NO
edit. `#use` adds to the **implementation** uses (a clause is created when there is
none). An
entry to remove inside a `{$IF...}` region refuses the whole unit (exit 1, nothing
written; see *Refusals* below). A unit with no `.dfm`, a book with no `#convert` block, or a `.dfm` no
block matches, gets its unit rules alone. The `apply/1` JSON reports them as
`uses[]` / `uses_removed` / `uses_added` plus `component_part`.

### Refusals (`refused` / `reason`, 1.20.6)

Some units `convert-apply` will not touch at all, because no safe rewrite
exists: a `.dfm` holding an `inherited`/`inline` object of a From type
(`inherited instances of <Type> are not converted yet -- unit not changed`), and
a unit whose uses entry to change sits in a `{$IF...}` region (the message
names the entry and the clause). Every such refusal behaves the same way: exit
1, NOTHING written (neither `.pas` nor `.dfm`), one text line
`REFUSED: <reason>`, and in `apply/1` JSON `"ok": false`, `"refused": true`,
`"reason": "<reason>"` (`error` holds the same text). `refused` (a JSON bool)
and `reason` are always present: `false` and `""` on success and on every
genuine failure -- rule errors, the freshness guard, a missing file. The editor
keys its "refused -- not changed" row on `refused == true`. An unreachable-path
warning is not a refusal. Schema stays `apply/1` (additive).

## End-to-end workflow

1. **Inspect** both trees to see what you are working with:

   ```
   drag-lint proptree --qname MyUnit.TDBEdit  --db app.sqlite
   drag-lint proptree --qname cxDBEdit.TcxDBEdit --db app.sqlite
   ```

2. **Draft** a rules file from the real trees:

   ```
   drag-lint convert-scaffold --from MyUnit.TDBEdit --to cxDBEdit.TcxDBEdit \
     --out tdbedit-to-tcxdbedit.rules --db app.sqlite
   ```

3. **Hand-finish** the file: resolve each `#link ... <- ???` using the
   `#note candidates:` list, fill each `#default ... = ???`, and delete or keep
   the `DROPPED` notes as intent records.

4. **Validate** the finished file until it is clean:

   ```
   drag-lint convert-validate --rules tdbedit-to-tcxdbedit.rules \
     --from MyUnit.TDBEdit --to cxDBEdit.TcxDBEdit --db app.sqlite
   ```

   Fix any `line N: ...` path errors it reports; a clean run prints `OK` and
   exits 0.

## Batch 2 (apply): shipped

Batch 1 is the read-only foundation: **enumerate, scaffold, validate.** Batch 2
adds the user-facing **`convert-apply`** verb that rewrites the real `.pas` +
`.dfm` files on disk from a validated rule set.

**Batch 2a-i (shipped, headless):** the pure DFM component **re-emit engine** --
`ReemitComponent` in `src/report/DRagLint.Convert.DfmReemit.pas`. Given one F
component's DFM `object` block, a validated rule set, and the F/T property trees,
it parses the block into an in-memory tree, remaps each leaf to its T path
(including **moved-depth** -- `Font.Size` -> `Style.Active.Font.Size`, creating the
intermediate T sub-objects -- and **events**), and re-serializes a well-formed T
block plus a structured report (dropped / ignored / mismatched / created /
carried / ownedParts / notes). It is **pure** (no file I/O, no CLI, no IDE) and is exercised
headlessly through a **hidden** `convert-reemit` test verb. This is more than
GExperts does: GExperts converts the DFM only, one level deep, and cannot map
events or moved-depth properties. `convert-apply` drives this engine for real,
per located instance, as surface #3 below.

**Shipped -- the `convert-apply` verb.** The full workflow:

```
drag-lint proptree --qname Unit.TOldEdit --db myapp.sqlite         # inspect F's tree
drag-lint proptree --qname Unit.TNewEdit --db myapp.sqlite         # inspect T's tree
drag-lint convert-scaffold --from Unit.TOldEdit --to Unit.TNewEdit \
  --out rules.txt --db myapp.sqlite                                # draft the rules
drag-lint convert-validate --rules rules.txt \
  --from Unit.TOldEdit --to Unit.TNewEdit --db myapp.sqlite         # check the paths
drag-lint convert-apply --unit MyForm.pas --rules rules.txt \
  --db myapp.sqlite                                                 # DRY-RUN: preview
drag-lint convert-apply --unit MyForm.pas --rules rules.txt \
  --db myapp.sqlite --apply                                         # write for real
```

Without `--apply`, `convert-apply` is dry-run only: it prints the planned edits
(`TTextEditApplier.RenderDryRun`) and writes nothing. `--apply` writes the edits
for real. `--only Name1,Name2,...` restricts the run to specific `.dfm` instance
names; `--db` may repeat for a multi-DB index.

**Which blocks are validated (1.20.6).** Before planning, `convert-apply`
validates the WHOLE book: every `#convert` block against its OWN From/To types,
and each `#mapping` against the block(s) that `#apply` it -- each path resolved
segment by segment as in `convert-validate` above (the `.dfm` rule; private
never; no depth limit), except that a referenced component (a `TComponent`-typed
property such as `Connection`) is a leaf here, so a path THROUGH it
(`Connection.Params.X`) is not found -- the plan could not apply it either.
Every block is also freshness-checked: a stale type behind ANY block warns on a
dry run and refuses `--apply`, a unit-rules-only run included. A block whose
From or To type resolves in no `--db` is an error on its `#convert` line.
Validation and the plan share one member cache per `--db` (json
`classes_built` = the classes whose members were resolved). A path error ends
with the block it was checked in: `(#convert line N: From -> To)`.

**Inherited forms.** `convert-apply` does not convert `inherited` / `inline`
`.dfm` objects yet. If the unit's `.dfm` holds one whose class is a From type
of the book, the whole unit is refused (exit 1, nothing written, unit rules
included): `inherited instances of <Type> are not converted yet -- unit not
changed`.

`convert-apply` locates every `.dfm` component instance whose class matches a
`#convert FromType` rule, then rewrites all **5 conversion surfaces** for each:

1. **`.pas` declaration retype** -- `Name: FromType;` -> `Name: ToType;` on the
   instance's published field declaration.
2. **`.pas` uses-add** -- adds ToType's declaring unit to the `.pas` `uses`
   clause (once per distinct ToType), via `TFindUnitRefactoring.Build`.
3. **`.dfm` object-block re-emit** -- the instance's whole `object Name: Class
   ... end` block is replaced with the re-emitted T block from `ReemitComponent`
   (Batch 2a-i), including moved-depth properties and event renames. A hard
   re-emit failure skips the WHOLE instance (no partial conversion: its `.pas`
   retype/uses edits are withheld too).
4. **`.pas` property/event access-site rewrite** -- for each renaming `#link
   ToMember <- FromMember` rule (single-segment paths only -- a moved-depth
   `#link` like `Style.Active.Font.Size <- Font.Size` is `.dfm`-only, surface #3
   above), every `Instance.FromMember` use site in the `.pas` file is rewritten
   to `Instance.ToMember`. This is what makes the conversion actually **compile**:
   the `.dfm` and the `.pas` end up agreeing on the same member name. Powered by
   ref-gap G's `kind='member-access'` reference (`obj.Member` on a plain-identifier,
   non-`Self` receiver), scoped to receivers that are converted instances of THIS
   unit -- an access on an unconverted receiver (e.g. `Other.Caption` when `Other`
   has no `#convert` rule) is left untouched.
5. **Runtime-creator retype + TODO marker** -- every explicit `FromType.Xxx(...)`
   construction (e.g. `Edit1 := TOldEdit.Create(Self);`) gets its type token
   rewritten to ToType, PLUS an unconditional `{ TODO: drag-lint convert --
   verify creator for ToType (was FromType.Xxx); ToType's ctor/init may differ }`
   end-of-line comment -- constructor ARGUMENTS are never auto-fixed, so the
   marker is the safety net a human checks by hand.

**Safety (the `--apply` write path):** before writing anything, a **freshness
guard** (`CheckFreshness`) verifies both the F and T types are indexed AND their
declaring source files are up to date on disk (mtime+sha256 against what was
indexed) -- refusing to build a plan from a stale property tree. Then, unless
`--no-backup`:
- a `recovery.txt` block (`[timestamp] convert-apply --rules ...`, naming every
  original-file -> backup-file mapping) is written **before** the conversion
  writes land, so a crash mid-write still leaves a recoverable trail;
- each touched file is copied to `<file>.BCK<n>` (next-free `n` -- re-running
  `convert-apply` never clobbers an earlier backup, `.BCK1` stays `.BCK1`);
- the converted `.pas` file gets a `// drag-lint convert-apply` comment block
  prepended, naming the backup file and the rules file used.

`--no-backup` still converts the files but skips all three (no `.BCK<n>`, no
`recovery.txt`, no in-file comment) -- use only when you have your own VCS/backup
discipline.

**Still deferred:** split/merge (one F -> several T), the expression interpreter,
and full default-value fidelity (see the known gap below) -- these remain out of
scope for the shipped applier.

**Enabling capability shipped -- ref-gap G (`member-access` indexing):**
`convert-apply`'s property/event-access rewrite (surface #4) needs the index to
know which MEMBER was accessed on which receiver. Ref-gap G adds a
`kind='member-access'` reference for `obj.Member` on plain-identifier non-`Self`
receivers (tightly gated to avoid flooding), which the applier queries -- scoped
to the converted instance -- to find exactly those sites.

**Property-default divergence -- CLOSED.** A property ABSENT from the F DFM is
an UNREAD value, not a missing one: a `.dfm` is sparse, so Delphi omits a
property whose value equals its declared `default`. A rule-referenced source
that is absent-because-default now has its value resolved and written into the
target **explicitly**, since F's default and T's default are different values
that merely share a name. It cost no parser change and no index change: the
`default` clause is read at query time from the declaring line, so the
anticipated **Batch 2a-0** was never needed.

Two cases are still reported instead of carried, and both are deliberate --
a property with no `default` clause is always streamed, so its absence is
genuinely unknown; and one whose `stored` clause is not `stored True` is
omitted regardless of its value, so its absence says nothing either. The
`defaults-may-diverge` note now fires only for those and NAMES them, instead of
firing on every conversion whose types differ.

## Tests

The conversion-rules, re-emit engine, and applier are covered by these headless
autotests (run each individually; there is no aggregating runner):

- `tests/autotest/run_proptree.ps1` -- the `proptree` deep-property enumerator.
- `tests/autotest/run_convert_rules.ps1` -- the DSL parser + `convert-validate`
  (including the Batch 2a-i `#ignore` directive).
- `tests/autotest/run_convert_scaffold.ps1` -- the `convert-scaffold` generator.
- `tests/autotest/run_dfm_reemit.ps1` -- the Batch 2a-i DFM re-emit engine (via the
  hidden `convert-reemit` verb): 1:1 rename, moved-depth, events, `#ignore`,
  unmapped-drop, `#default`, collection relocate, binary same-type/mismatch,
  owned-part vs contained-child, and an identity round-trip.
- `tests/autotest/run_member_access_refs.ps1` -- ref-gap G's `member-access`
  reference indexing that surface #4 depends on.
- `tests/autotest/run_convert_apply.ps1` -- the `convert-apply` verb end-to-end:
  instance location, all 5 conversion surfaces (including a consolidated case
  exercising every surface -- decl retype, uses-add, `.dfm` re-emit with a
  moved-depth property and an event rename, property-access rewrite, and
  creator retype/TODO -- in ONE `--apply` run), the freshness guard, dry-run vs
  `--apply`, the `.BCK<n>`/`recovery.txt`/in-file-comment backup scheme, and
  `--no-backup`.

## See also

- `docs/AI-USAGE.md`, `docs/AI-INDEX-FIRST.md` -- the verb inventory these three
  verbs join.
- reFind `readme.txt` (section 3.2) -- the adopted rule-format reference.
