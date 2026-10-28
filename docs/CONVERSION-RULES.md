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
drag-lint proptree --qname <TClass> [--depth N] [--rules <file>] [--progress-interval S]
                    [--no-to-persistent]
                    [--min-visibility published|public]
                    [--format text|json] --db PATH [--db ...]
```

Walks a class's `property` symbols (own **and** inherited), parses each property's
type from its indexed signature, and recurses into class-typed property types --
producing flattened dotted paths (`Font.Color`, `Sub.Color`). By default it stops
the ancestor climb at `TPersistent`/`TObject`; `--no-to-persistent` climbs past.
Recursion is depth-capped with a visited-type cycle guard. **Depth** is the
class-recursion budget: root members are 1-segment paths, and a K-segment path
needs depth >= K-1 (depth 2 already holds `Constraints.Items.CustomConstraint`).
The depth is `--depth N` (an integer >= 1), else the `#depth N` of the book named
by `--rules <file>`, else **5** (1.20.6; before that the documented default was
6, but a run with no `--depth` actually used the global parse default 3). A
non-numeric `--depth`, `--depth 0` / negative, a missing `--rules` file, or a
book whose `#depth` is invalid or repeated is a usage error (exit 2); so is a
`--depth` that is not plain decimal digits (`+3`, `$A` -- the check `#depth`
uses).
`convert-scaffold` takes the same `--depth` / `--rules` with the same rule. Each
visited class's own **fields** and class-scoped **consts** are also walked and
emitted as flat leaves (`member_kind: "field"` -- see below; never recursed into,
even when class-typed).

**Progress (1.20.6).** A deep tree can take a while (FireDAC `TFDQuery` at depth
4 is ~66 classes and ~26k nodes). `--progress-interval S` (whole seconds, the
same digits-only check as `--depth`; `x`, `-1`, `+3`, `1.5` and a missing value exit 2) makes
`proptree` and `convert-scaffold` write ONE JSON line to **STDERR** at most every
`S` seconds while the tree is expanded and emitted -- never to stdout, so the
verb's own output is byte-identical with or without it:

```
{"progress":{"elapsed_s":12.3,"verb":"proptree","class":"FireDAC.Comp.Client.TFDQuery","depth":2,"max_depth":5,"classes_done":41,"classes_queued":7,"nodes":3114}}
```

`elapsed_s` counts from the start of the verb (one decimal, `.` in every locale);
`depth` is the breadth-first level being expanded (`max_depth` once expansion is
over and the nodes are being emitted); `classes_done` is the number of classes
resolved into the member cache so far; `classes_queued` the classes still waiting
at this or a deeper level (0 while emitting); `nodes` the nodes emitted so far (0
while expanding). `class` is the tree's root (`convert-scaffold` builds the FROM
tree, then the TO tree). The key set and order are fixed; `elapsed_s`,
`classes_done` and `nodes` never decrease. The first line comes after one full
interval, so a run shorter than `S` prints none. Writing the document AFTER the
tree is built prints no progress: since 1.20.6 (T2i) it is one buffered write
(`TFDQuery --depth 5 --json`, 101,063 nodes / 37 MB: under 1 s of a ~14 s run).

**Stream order (1.20.6).** `proptree`, `convert-scaffold`, `convert-apply`
(dry run and `--apply`, `--format json`), `convert-reemit`, `info --json`,
`query --name --json`, `outline --format json` and `sql` -- the verbs the rules
editor runs -- flush every STDERR line they wrote (the `(loaded defaults ...)`
banner, freshness and resolver notes, progress lines) BEFORE the first byte of the stdout document,
and write the document in one piece; nothing follows it on either stream. So a
caller that merges the two streams into one pipe gets the notes as a preamble
and the complete document after them.

**Default 0 = OFF.** A caller that merges stdout and stderr (the rules editor
does, then parses from the first `{` to the last `}`) must leave it off: a
progress line in the preamble carries a `{` of its own.
`convert-apply` / `convert-validate` never build a tree and never emit progress:
they reject `--progress-interval` as an unknown argument (exit 3).
**Cancel = kill the process.** That is safe with the default write-back: each
type the ancestry-bridge recovers is memoised by its own SQLite statement, so a
killed run leaves the index consistent (pinned by a kill test and
`PRAGMA integrity_check`); `--no-write-back` never writes at all. `info --json`
advertises the flag as `capabilities.progress_lines: true`.

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
                           [--out <file>] [--surface dfm|pas]
                           [--depth N] [--rules <file>] [--progress-interval S]
                           --db PATH [--db ...]
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
limit and neither `--depth` nor a book's `#depth` applies (a bad `#depth` is still
reported as a `line N:` error) -- a 9-segment path validates as readily as a
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
| `#unuse <unit>` | remove a unit from the PAS `uses` clause. **convert-apply 1.27.0 (C9):** a WATCH LIST entry -- kept while a component the converted `.dfm` still streams has a class declared in it (`kept` row + warning), removed when only `.pas` code needs it (dangling references named on the row), kept when no `--db` knows it; scope-alias aware (`#unuse DBTables` matches `Bde.DBTables`). `--no-reconcile-uses` = the unconditional 1.26 removal. |
| `#remove <property>` | remove a property from PAS and DFM |
| `#remove DFM: <property>` | remove a property from the DFM only |
| `#migrate [<Class>:] [<obj>.] <old> -> <new> [, <unit> ...]` | replace `old` with `new`; optional class-scope / object-scope; optional uses-add(s). Inside a `#convert` block convert-apply applies the plain forms `#migrate Old -> New` and `#migrate Old -> DL_NONE` to the converted instances' `.pas` sites (C18 slice 1, see "Member migration") |
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
| `#convert <From> -> <To> [, <unit> ...]` | declares the type-pair this block converts (groups the links; optional target uses-add). A From-only header -- `#convert TFoo -> ` (the editor writes it while authoring) or `#convert TFoo` -- parses as From `TFoo` with an EMPTY To, never as a class named `TFoo ->`, and is a `line N:` error: `#convert TFoo has no To type` (1.20.6, R27). Likewise `#useswap X -> ` with no New unit: `#useswap X has no replacement unit`. |
| `#link <ToPath> <- <FromPath>` | deep property assignment. **Note the `<-` arrow** -- reversed vs `#migrate`'s `->`. Read it "target gets source." **Type-identity carry (2026-09-16):** when both sides are CLASS-TYPED and of the SAME class (`#link Font <- Font`, both `TFont`), every sub-leaf the `.dfm` streams under the source (`Font.Charset`, `Font.Name`, ...) is carried to the same leaf under the target automatically -- the five hand-written `Font.*` lines become one. When the types DIFFER (`OptionsImage.Glyph <- Picture`, `TdxSmartGlyph <- TPicture`) nothing is carried implicitly and every dotted leaf must be named, because an invented target path is how a form stops loading. An explicit per-leaf `#link` / `#ignore` / `#remove` always wins over the carry; a carried leaf is reported (`sub-leaf-carried` in `convert-apply --format json`, `report.carried[]` in `convert-reemit`) so the leaves nobody typed are visible. Not implemented: the "target type is an ancestor of the source type" case -- the engine has no class graph, so that still needs explicit leaves. |
| `#default <ToPath> = <value>` | set a target property to a default when no source maps to it |
| `#ignore <FromPath>` | acknowledge an F property/event is intentionally NOT mapped -- suppresses its unmapped-non-default warning (other unmapped props still warn). Added in Batch 2a-i for the re-emit engine. Scoped to its own `#convert` block (see *Rule scope* below). |
| `#warn <FromPath> "<text>"` | 1.26.5: a book-authored WARNING, once per converted instance whose SOURCE `.dfm` streams `<FromPath>` (a `.dfm` streams only non-default values, so present = non-default; absent never fires). Carries nothing and is independent of `#link`. See *Book warnings and reference checks* below. |
| `#check-ref <ToPath> <Class>.<Prop>[, ...]` | 1.26.5: the CONVERTED block's `<ToPath>` value must be a name some `.dfm` of the project carries on a listed `<Class>.<Prop>`. See below. |
| `#note <text>` | a human comment carried in the rule (the scaffolder emits `candidates:` and `DROPPED` notes) |
| `#use <unit>` | add a unit to the PAS `uses` clause (the companion to reFind's `#unuse`) |
| `#useswap <Old> -> <New1> [, <New2> ...]` | replace unit `<Old>` with one-or-more `<New>` units. Sugar for `#unuse Old` + `#use New1` + `#use New2` ... |
| `#depth <N>` | the book's property-tree depth for `proptree --rules` / `convert-scaffold --rules` (1.20.6). `N` is decimal digits 1..10, at most one per book; anything else (`#depth 11`, `#depth x`, a bare `#depth`, a second `#depth`) is a `line N:` error in `convert-validate` and a usage error (exit 2) in `proptree`/`convert-scaffold`. Precedence: `--depth N` > `#depth N` > 5. `convert-validate`/`convert-apply` resolve paths lazily and ignore it. `--print-parsed` shows it as `line L: depth N`. |

**Single pass.** convert-apply is SINGLE PASS: every rule matches the ORIGINAL source; an output is never re-matched. `#convert TA -> TB` plus `#convert TB -> TC` leaves a TA as TB (and a TB as TC); the first rule per From type wins; a cycle (`TA -> TB`, `TB -> TA`) swaps the two classes in one run; a unit swap chain (`#useswap A -> B` plus `#useswap B -> C`) ends with B and C (ADD wins). ENGINE trace 2026-10-26, `docs\INBOX-engine-to-converter-chain1.md`; confirmed by ENGINE 2026-10-28 and pinned by `tests\autotest\run_convert_single_pass.ps1`. A From type is matched BY ITS BARE NAME, case-insensitively (`Bde.DBTables.TTable` = `TTable`); the index is not consulted for the match. Since 1.37.0 convert-validate and convert-apply (dry run and `--apply`) WARN about both shapes, exit code unchanged: `line N: warning: chain: TB is also a From type (line M converts TA -> TB; single pass, TA ends as TB)` and `line N: warning: duplicate From TA (line M wins)`. To chain, run the stages as separate books in order (`X.rules`, then `X.stage2.rules`; the Convert tab reindexes between books) or merge the rules into one `TA -> TC`; ConvRulesEditor marks chains on Save and offers both (wiki: convrules-editor-rule-chains).

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

Without BOTH `--from` and `--to`, `convert-validate` only PARSES the book: no
path is checked, it still prints `OK`, and (1.26.1) a `NOTE:` line on stderr
says so. `convert-apply` validates every block against its own types.

### Rule scope (1.26.1)

A `#convert` block owns the lines from its `#convert` up to the next one. When
`convert-apply` / `convert-reemit` converts a `.dfm` object, it runs that
object's block (the first `#convert` whose From type is the object's class):

- `#link`, `#ignore`, `#default`, `#remove` and `#apply` of **that block**, plus
  the **file-scope** ones written before the first `#convert` (BDE-to-FireDAC's
  `#remove` list);
- every `#convert`, `#mapping` and `#note` line of the book (a `#mapping` is
  named and `#apply`'d from any block; `#note owned:<Class>` marks a class).

The `.pas` access-site rewrite follows the same scope: a site on instance X is
rewritten only by the `#link`s of X's block (plus file-scope ones), so each
site gets exactly one edit and two blocks may rename one path differently.
A file-scope `#link` -- one with no `#convert` above it -- belongs to no
block and rewrites the sites of EVERY converted instance, just as it applies
to every block's `.dfm` objects.

So an `#ignore ReadOnly` in the TDatabase block no longer suppresses the TTable
block's `#link UpdateOptions.ReadOnly <- ReadOnly`, and two blocks may link the
same source path to different targets. Until 1.26.0 the whole book ran in every
block: the first `#link` of a path anywhere won, any `#ignore` anywhere
suppressed it, and a `#default` was written into every block's instances.

### Carried without a rule (1.26.1)

Two `.dfm` entries are DefineProperties pseudo-properties, not published, so no
rule can name them; `convert-apply` carries them unless a rule of the block names
them first (`#ignore Left` still drops it):

- **`Left` / `Top`** -- a non-visual component's designer position
  (TComponent.DesignInfo). Carried verbatim, and ONLY when the From class does
  not publish them: on a control (TLabel, ...) they are ordinary published
  properties, so the book's `#link Left <- Left` carries them (once) and with
  no link they are dropped and reported unlinked like any other property.
- **`ParamData = < item ... end>`** -- how TQuery / TStoredProc (and TFDQuery /
  TFDStoredProc / TFDCommand) stream `Params`. Carried under the same name; each
  item member is mapped through the block's `#link Params.Items.<X>` (a renaming
  link renames it; one with a cast is not applied inside a collection), else kept
  when the target's `Params` item publishes the same member with the same type,
  else NOT carried and reported per item:
  `ParamData item <n> (<Name>): <line> not carried -- <why>` (reemit note). A
  target with no `Params` property gets nothing, and `ParamData` counts as
  dropped. An `#ignore Params.Items.<X>` drops that member silently.

### Book warnings and reference checks (1.26.5)

Both directives are block-scoped like every property rule (a file-scope one,
before the first `#convert`, applies in every block) and change nothing that
is written -- they only report.

**`#warn <FromPath> "<text>"`** fires once per converted instance whose SOURCE
`.dfm` block streams `<FromPath>`; it never fires when the property is absent.
The text runs from the first to the last double quote (no escaping). In it:

| Placeholder | Becomes |
|---|---|
| `<value>` | the streamed source value (a simple quoted string unquoted) |
| `<name>` | the instance name |
| `{Prop}` | another SOURCE property of the same instance; empty when it is absent |

```
#warn IndexName "index <value> must exist on table {TableName} in the target database"
```

`convert-apply` reports `line N: warning: <inst>: <expanded text>` (N = the
instance's `.dfm` object line) in `warnings[]`, and an `items[]` entry of kind
`book-warning` with `instance`, `path` (the FromPath), `value`, `text` and
`rule_line`. `convert-validate` makes it a `line N:` error when the FromPath or
a `{Prop}` names no member of the block's From type (`warn FromPath not found
in --from tree: X`, `warn placeholder {X} not found in --from tree`), and when
the directive is malformed (`#warn needs <FromPath> "<text>"`). A file-scope
`#warn` is checked only in single-pair mode (`--from`/`--to`), like a
file-scope `#link`.

**`#check-ref <ToPath> <Class>.<Prop>[, <Class>.<Prop> ...]`** checks the
value the CONVERTED block holds at `<ToPath>` (whether it came from a `#link`,
a `#default` or a resolved default); nothing happens when it holds none. The
last dot splits class from property; the class is matched by its bare name
against each `.dfm` object's type token.

```
#check-ref ConnectionName TDatabase.DatabaseName, TFDConnection.ConnectionName
```

* a value containing `\` or `:` is a file path, not a name -- kind
  `ref-path-like`:
  `line N: warning: <inst>: <ToPath> '<v>' looks like a file path, not a <C.P / C.P> name (#check-ref line L)`
* a value no listed `Class.Prop` carries in ANY `.dfm` of the project index
  (every unit, case-insensitive) -- kind `ref-dangling`:
  `line N: warning: <inst>: <ToPath> '<v>' matches no <C.P / C.P> in the project's .dfm files -- the reference dangles unless it is defined outside the project's .dfm files (e.g. a FireDAC connection definition) (#check-ref line L)`
  (a path-like value usually gets both lines);
* when the project index holds no `.dfm` property facts at all (an index built
  before the text index, or a project whose `.dfm`s stream nothing), ONE line
  per run, kind `ref-not-checked`:
  `line L: warning: #check-ref not checked -- the project index holds no .dfm property facts (reindex it with this engine)`.

The facts are the index's `.dfm` property values (`string_literals` kind
`dfm-prop`), read from the `--db` that holds the unit, so a name defined only
outside the project (a BDE alias, a FireDAC connection definition file) is
reported as dangling: on DMTEST every `'MicroniteSystem'` dataset is (87).
`convert-validate` errors on a ToPath naming no member of the block's To type
and on a malformed line; the `Class.Prop` targets are not checked (the class
may live in no `--db`). `items[]` entries carry `value`. `info --json`:
`capabilities.book_warn`, `capabilities.check_ref`.

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
exists: a unit whose uses entry to change sits in a `{$IF...}` region (the message
names the entry and the clause), and a `.dfm` that changed after indexing: the
line range the index recorded for an instance no longer opens `object <Name>:`
(or `inherited`/`inline`), its first `end` at the opener's indent is not the
recorded end line (a block that lost lines now ends on a later sibling's `end`),
or the `.dfm` was cut short so the range runs past its end
(`<Name>: index is stale for this .dfm -- reindex`; reindex and run again), and
(R26) a unit-rule removal -- `#unuse`, or `#useswap`'s Old -- of the unit that
declares the From type of an instance that stays unconverted (skipped, an
`inherited`/`inline` object, or left out by `--only`, which filters instances
and never unit rules): removing it would
break the compile (E2003), so the unit is refused with
`<rule> would leave <N> unconverted instance(s) of <Type> -- unit not changed`
(e.g. `#unuse LibA would leave 1 unconverted instance(s) of TSrcBtn -- unit not changed`;
the declaring unit is the From type's indexed declaring file).
With `--only` (1.23.0, C12 N4), a removal whose stranded instances are ALL
own instances `--only` left out is SKIPPED instead of refused -- the user chose
the scope: the unit stays in uses, `uses[]` gets a row
`{action: "skipped", unit, section, line, rule, reason: "would leave N unconverted instance(s) of <Type>"}`,
and `warnings[]` / text `Warnings:` a `line N: warning: <rule> skipped -- ...`
line (`items[]` kind `unit-rule-skipped`). A stranded instance left for any
other reason (a failed re-emit, an `inherited`/`inline` object) keeps the
refusal. `info --json`: `capabilities.only_skips_unit_rules: true`.
A `#convert` From or To type that resolves in no `--db` (1.23.0, owner
ruling) refuses the unit too, dry run and `--apply` alike, before any rule
error is reported: the converter cannot convert a type it cannot see, and the
cause is a parsing / index gap in the library or project index, not the book:
`<Type> (line N) resolves in no --db -- index gap in the library or project index; reindex, or report it, before converting`.
A BARE `#convert` From or To type (`#convert TLabel -> ...`) is resolved in
the converted unit's own scope -- the class every `#link` / `#default` /
`#ignore` path of that block is checked against, and the one the `.dfm` block
is re-emitted from -- by the same rule as `pas_uses[]`: the unit's own class,
else the LAST uses entry that declares it, else a lone unit-level declarer.
A nested class (`LibNest.TNestHost.TSolo`) is never a declarer, and the first
class of that name across the `--db` files is never taken (it used to be: a
VCL unit's `#convert TLabel` was checked against `FMX.StdCtrls.TLabel`). A
qualified type (`#convert Vcl.StdCtrls.TLabel`) is always exactly that class.
A bare To type that is no block's From is a class of the unit AFTER
conversion, so the unit the book makes it use settles a tie first (a `#use`, a
`#convert` line's trailing unit, a `#useswap` New whose Old the unit uses, a
uses entry the book does not remove -- the uses reconciliation's own rule).

**Inference, then refusal** (owner ruling 2026-10-11). A bare type the scope
still leaves ambiguous is INFERRED when exactly one candidate survives, in
this order: (a) the project's framework -- the `.dproj` beside the project
file the unit's index holds (or the one `.dproj` in the unit's folder):
`<FrameworkType>VCL|FMX</FrameworkType>`, else a `DCC_Namespace` naming `Vcl`
but not `FMX` (or the reverse) -- drops a `Vcl.*` / `FMX.*` candidate of the
other framework; (a2) the form file's kind -- a `.dfm` form is VCL and a `.fmx` form FMX (each framework streams its own), so a candidate of the other framework is excluded; (b) the `.dfm` evidence -- the properties the unit's `.dfm`
streams directly on objects of that class: a candidate that does not declare
one that another candidate does is dropped (a property NO candidate declares,
such as `ExplicitLeft`, tells nothing and is ignored). An inference converts,
with a warning (`items[]` kind `convert-class-inferred`):
`#convert TLabel resolved to Vcl.StdCtrls.TLabel (line 1): inferred from the project framework VCL (P.dproj); qualify the line to silence this: #convert Vcl.StdCtrls.TLabel -> TSolo`.
Zero or several survivors REFUSE the unit, in detail -- the line and its
text, the bare name, every candidate and why it was not chosen
(`not in the unit's uses`, `tie: the uses entry X names another candidate
too`, `framework mismatch: the project is VCL (P.dproj)`, `form-file mismatch: U.dfm is a VCL form`, `.dfm property X not
declared`, `tie: fits ... as well as another candidate`), and what to do:
`REFUSED: #convert TLabel -> TSolo (line 1): the bare name TLabel is ambiguous in this unit's scope -- candidates FMX.StdCtrls.TLabel (not in the unit's uses), Vcl.StdCtrls.TLabel (not in the unit's uses) -- qualify the #convert line (paste one of the suggested lines, apply/1 qualify_fixes[]) or add the declaring unit to the unit's uses; nothing was validated against a guess`,
followed in text mode by the qualified lines, ready to paste:

```
  line 1 of book.rules -- replace "#convert TLabel -> TSolo" with one of:
    #convert FMX.StdCtrls.TLabel -> TSolo    { not in the unit's uses }
    #convert Vcl.StdCtrls.TLabel -> TSolo    { not in the unit's uses }
  or: add FMX.StdCtrls to the unit's uses
```

`apply/1` carries the same as `qualify_fixes[]` (always present; `[]` when
nothing was ambiguous), one object per ambiguous `#convert` side, refused or
inferred: `{rule_line, current, name, side: "from"|"to", outcome:
"refused"|"inferred", chosen, inference, suggestions: [{replacement,
candidate, why, alternative}], alternative}` -- `replacement` is the whole
line with the name qualified (the inferred class first), `alternative` is
`#use <Unit>` for a To type and `add <Unit> to the unit's uses` for a From
type. Gate on `info --json` `capabilities.convert_qualify_fix`. This
supersedes ruling R8a for a `#convert` To type: an unsettled tie is no longer
converted with the tie merely reported in `uses_unresolved[]`.
Every such refusal behaves the same way: exit
1, NOTHING written (neither `.pas` nor `.dfm`), one text line
`REFUSED: <reason>`, and in `apply/1` JSON `"ok": false`, `"refused": true`,
`"reason": "<reason>"` (`error` holds the same text). `refused` (a JSON bool)
and `reason` are always present: `false` and `""` on success and on every
genuine failure -- rule errors, the freshness guard, a missing file. The editor
keys its "refused -- not changed" row on `refused == true`. An unreachable-path
warning is not a refusal. Schema stays `apply/1` (additive).
`convert-validate` and `convert-reemit` resolve a bare `--from` / `--to` by
the same rule with no unit: the book's own qualification of it (the first
`#convert` whose From -- or To -- has that bare name), else a lone unit-level
declarer (a bare name used to resolve to nothing there, so `convert-validate`
printed `OK` without checking a path). There is no unit, so nothing is
inferred: an ambiguous one exits 1 with
`ERROR: --from <Type> is ambiguous -- declared by <Unit>, <Unit> (no unit to scope it; the book does not qualify it). Qualify it, or qualify the book's #convert line. Nothing was validated against a guess`
and one `  use: --from <Unit>.<Type>` line per candidate.

### Text encoding of rule books and sources

The editor reads and writes rule books on an encoding ladder: ASCII-7, ASCII-8
(ANSI), UTF-8, UTF-8 with BOM, UTF-16 with BOM. A book's level is detected from
its bytes on open; a new book is ASCII-7 (the default). Save checks the text
against that level and, when a character would be lost, asks before raising it
(UTF-8 for an ASCII book); it never writes `?` silently. UTF-16 is always saved
with a BOM. File > Encoding sets the level Save and Save As write.

ENGINE contract (**engine side pending** -- CONV-ENC is built on the ENGINE branch,
not merged):

* apply/1 refusal keys: `refusal_kind: "encoding_refused"` and
  `encoding_refused {file, file_encoding (ansi|utf8|utf8-bom|utf16-bom),
  raise_to "utf8-bom", chars_total, chars[{code, text, line}]}`.
* `--raise-encoding "<path>=utf8-bom"` re-runs the unit with that file raised.
* Characters outside ASCII in a text `.dfm` are written as `#`-codes.
* Capability `convert_encoding_guard` (in `info --json`): without it the Convert
  tab does not offer the raise question.

On a yes to the raise question the editor re-runs the refused unit with
`--raise-encoding` and applies ALL its books again: a refused unit is restored
unchanged, so earlier books were rolled back. User view: wiki page
`convrules-editor-encoding`.

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

**`--only` names (1.23.0).** Names match case-insensitively. A name that
names no `.dfm` object of a `#convert` From type (own, `inherited` or
`inline`) is IGNORED -- never an error, the exit code is unchanged -- and
reported: `apply/1` carries `only_matched[]` and `only_unmatched[]` (spelled
as given, in `--only` order, always present, `[]` without `--only`), and
text mode prints `--only: no #convert instance named X, Y (ignored)`.

**Batch (1.23.0).** `--unit` may repeat. Every unit then runs in ONE process:
the book is validated once and every class's members are resolved once
(measured on DMTEST with `BDE-to-FireDAC.rules`: 36-42 s per unit as
separate processes, 45.7 s for three units batched). Text prints one
`=== unit i of N: <path> ===` section per unit -- that unit's normal output --
then `batch: N unit(s) -- a ok, b refused, c failed; classes_built K; exit E`.
JSON is one `apply-batch/1` document: `schema`, `mode`, `rules_file`,
`units_count`, `ok` (every unit ok), `exit_code` (the worst unit's),
`ok_count`, `refused_count`, `failed_count`, `classes_built` (the run's
total) and `units[]` -- one ordinary `apply/1` object per unit, in `--unit`
order, equal to that unit's single-unit `apply/1` (its `classes_built` is the
unit's own: the book's validation set plus what its run added). A single
`--unit` still emits a bare `apply/1`. A unit's refusal or failure never stops
the others; the process exits with the worst unit's code (6 > 2 > 1 > 0). Exit 6 (1.28.0) is a castlib the engine cannot load or execute (an unknown `value` keyword) -- a CONFIGURATION error, deliberately not 2, which on this verb means a write failure or rollback. Under
Addendum (1.33.1): the castlib is parsed and validated ONCE, before any unit runs. A top-level exit 6 = no unit of the batch was touched: every unit is refused with the castlib reason and `exit_code` 6 (a normal `units[]` of `apply/1` objects, nothing written, no backups), whatever the other units would have done.
`--apply`, every file a unit would touch is checked writable FIRST: a read-only
or locked file fails that unit (exit 2, `ok: false`, `refused: false`,
`cannot write <file>: ... -- unit not changed, nothing written`) with nothing
written, no `.BCK` and no recovery record. A write that fails AFTER that check
(a lock taken in between, a full disk) is ROLLED BACK (1.25.1): every file of
the unit already written is restored byte-identical -- from its `.BCK`, or under
`--no-backup` from the bytes read just before the write -- and the unit fails
with `write failed for <unit>: <error> -- rolled back, unit not changed` (exit
2; the `.BCK` files and the recovery record stay). Only when the rollback
itself fails is the unit left partly converted: `... -- rollback FAILED for
<files>: the unit may be PARTLY converted; restore it from the .BCK backups
recorded in recovery.txt`. A single `--unit` reports either as `ERROR: ...`,
exit 2.

**How the ConvRules editor uses it (B4, 2026-10-23).** When the engine reports
the `batch_units` capability, the run is unscoped and has two or more units, the
Convert tab converts book by book: ONE reindex before the first book, one
`.BCK<N>` restore point per unit (the editor's own, so it calls with
`--no-backup`), then per book one `convert-apply --unit ... --apply --no-backup
--format json` over chunks of at most 8 units (watchdog 600 s + 120 s per extra
unit) and ONE `index --project` after each chunk. Each `units[]` entry is read
like a single-unit `apply/1` (refused, failed, converted); an answer that is no
`apply-batch/1`, whose `units[]` do not follow the `--unit` order, or whose
`exit_code` contradicts its counts restores every unit of the chunk. A one-unit
chunk reads the bare `apply/1` the engine answers it with. `CONVRULES_BATCH=off`
in the editor's environment, an IDE-scoped run (`--only` would bind every unit)
or a single unit keeps the per-unit path. Known on the 1.33.0-alpha-20261021 pin
(captures `src\tools\convrules-editor\tests\fixtures\apply1270\batch-*-1330.json`):
G1 no progress inside a call, so the editor can only say "applying units 1-8";
G2 an unindexed unit answers `ok: true, edits_count: 0` (the editor's preflight
refuses unindexed units first); G3 `units[]` entries carry no `exit_code`; G4 the
engine reindexes after EVERY unit inside the call (`uses_reindex`).

**What is atomic, exactly (1.25.1).** Per unit, across its `.pas` and `.dfm`:
an edit set the applier would refuse (overlapping delete ranges) -- nothing is
written, dry run and `--apply` alike, exit 1; a file not writable before the
write -- nothing is written, exit 2; a write failing part-way -- rolled back,
exit 2; a rollback failing -- reported with the files it could not restore, exit
2. In batch mode each of these fails that unit only.
`info --json` advertises it as `capabilities.batch_units: true`.

**Addendum 1.33.0 (CONVERTER gaps G1-G3, all additive).**

* **An unindexed unit is refused (G2).** A `--unit` whose `.pas` no supplied
  `--db` indexes is REFUSED -- `ok: false`, `refused: true`, `reason`
  `<unit> is not covered by any supplied --db (<dbs>) -- index its project,
  then re-run; nothing was planned`, exit 1 -- dry run and `--apply`, single
  and batch alike. Before, both a single run and a batch planned the unit's
  unit rules, skipped every instance (the index locates them) and reported
  `ok: true` -- so `--apply` half-converted the unit. In a batch it is one
  refusal (`refused_count`); the other units run as before.
* **`exit_code` on every `apply/1` (G3).** Each `units[]` entry, and a single
  run's bare `apply/1`, carries `exit_code` -- that unit's own code (0 / 1 / 2
  / 6), the last key. `units[i]` still equals the single run of that unit.
* **`--progress` (G1).** Off by default. With it, convert-apply writes one
  JSON line to STDERR as each unit finishes, flushed at once:
  `{"progress":{"verb":"convert-apply","unit_done":i,"units":N,"unit":"<path as given>","ok":true|false,"refused":true|false,"exit_code":E}}`.
  stdout is byte-identical with and without it, but a caller that merges the
  two streams must leave it off. `info --json` advertises it as
  `capabilities.batch_progress: true`. Pinned by
  `tests\autotest\run_apply_batch_gaps.ps1`.

**Which blocks are validated (1.20.6).** Before planning, `convert-apply`
validates the WHOLE book: every `#convert` block against its OWN From/To types,
and each `#mapping` against the block(s) that `#apply` it -- each path resolved
segment by segment as in `convert-validate` above (the `.dfm` rule; private
never; no depth limit), except that a referenced component (a `TComponent`-typed
property such as `Connection`) is a leaf here, so a path THROUGH it
(`Connection.Params.X`) is not found -- the plan could not apply it either.
Every block is also freshness-checked: a stale type behind ANY block warns on a
dry run and refuses `--apply`, a unit-rules-only run included. A block whose
From or To type resolves in no `--db` REFUSES the unit (1.23.0, owner ruling;
see *Refusals*): that is an index gap, not a rule-book error.
Validation and the plan share one member cache per `--db` (json
`classes_built` = the classes whose members were resolved). A path error ends
with the block it was checked in: `(#convert line N: From -> To)`.

**Inherited forms (1.22.0, C8).** `convert-apply` does not convert `inherited`
/ `inline` `.dfm` objects: the component is DECLARED by an ancestor, which is
where it has to be converted. Such an object whose class is a From type of the
book is SKIPPED -- its `.dfm` lines are left as they are -- while the unit's own
instances, its code and its unit rules convert as usual (until 1.21.1 the whole
unit was refused). Each one is reported:

* text: `line N: warning: inherited instance <Name>: <Type> skipped -- <reason>`
  under `Warnings:` (N is its `.dfm` line);
* JSON: the same text in `warnings[]`, an `items[]` entry of kind
  `inherited-instance-skipped`, and one object in `inherited[]` (always present,
  `[]` when none):
  `{name, type, line, ancestor_unit, ancestor_state, reason}`.

The **declaring ancestor** is the nearest class up the owner's ancestor chain
(the index's `type_ancestors`, several levels up when needed) whose `.dfm` opens
the component with `object`; a `.dfm` that only re-opens it with `inherited` is
passed over. The owner is the form's root class, or the class of the nearest
enclosing `inline` frame for a frame's children. `ancestor_state` is
`unconverted` (that ancestor still has the From type -- convert it first),
`converted` (it already has the To type -- RETYPED since 1.26.0, below),
`mismatched` (it has a third type, named in
`reason`; `ancestor_unit` set) or `outside` (not determinable: no ancestor in
the `--db` declares it, the chain leaves the index, or an ancestor's `.dfm` on
the way is missing or binary -- that STOPS the walk, since it might declare the
component, and the reason names the file; `ancestor_unit` is then `""`, never
guessed). The owner class and component names match case-insensitively, and
`--only` filters `inherited[]` like the other instances.
R26 (see *Refusals*) still counts every such instance as left unconverted. `info --json`
advertises the behaviour as `capabilities.inherited_instances: true`; an engine
without the key still refuses the unit.

**Retyping inherited instances** (1.26.0, C8 N2 / N2a). An instance whose
declaring ancestor ALREADY has the block's To type is converted, not skipped:

* the header becomes `inherited X: TTo` (or `inline X: TTo`) -- the keyword is
  kept, and nested blocks and `inline`-frame children are retyped the same way;
* the properties the block overrides convert per the book -- `#link`, `#ignore`,
  `#remove`, casts -- through the same re-emit as an own instance. A property
  the block does NOT stream is inherited from the ancestor, not at its declared
  default, so for such a block no default is resolved, no `#default` is written
  (the ancestor's own conversion wrote it, or a carried value superseded it),
  and a `#mapping` whose source the block does not stream is skipped silently;
* code access sites on X are rewritten exactly as for an own instance, and the
  To type's unit is added to the uses (the usual section rule; the descendant
  declares no field, so there is nothing to retype in its type section and no
  creator site).

Every code rewrite -- own instances' and inherited ones' -- is scoped to the
instance's FIELD (1.26.0): a member access is rewritten only when its receiver
is bound by the resolver to the field the `.dfm`'s root class declares or
inherits, or is unbound, bare or `Self.`-qualified, inside a routine of that
class that declares no local or parameter of the same name. A local, a
parameter or another class's same-named field is left alone.

Because the scoping relies on the resolver's binds, a `--db` whose edges were
derived by a resolver older than 1.12.0 (or that has no resolver stamp) is
REFUSED, dry run and `--apply` alike, with the `index ... --resolve-only`
command that fixes it. A site the index cannot vouch for -- no reference for
its receiver on its line, a member reached through `with X do`, an unbound
reference to a converted ancestor's field -- is not rewritten and is reported:
`access site <file>:<line> <receiver>.<member> not verified against the index
-- not rewritten`, `items[]` kind `access-site-unverified`, json
`access_sites_unverified`.

Code that uses an UNCONVERTED ancestor's field without a `.dfm` block -- the
ancestor still declares it with the block's From type -- is listed as well
(1.26.7): `inherited[]` action `skipped`, `ancestor_state` `unconverted`,
`reason` `ancestor not converted`, `line` its first `.pas` reference. Nothing is
rewritten; convert the ancestor first. Gate on
`capabilities.inherited_code_unconverted`.

Code that uses a converted ancestor's field WITHOUT a `.dfm` block (N2a) is
followed too: every access in the unit on a field an ancestor declares -- any
number of levels up, bound to that field by the resolver (`refs.symbol_id`),
the ancestor's `.dfm` opening the component with the To type -- is rewritten.
A local or parameter of the same name binds to itself and is left alone.
The editor then shows no "left" note for it: a use of a converted ancestor's field (action
`code`) counts as left ("N inherited code use(s) left") only when the matching `pas_uses[]`
entry is not `mapped` or there is none; once it is `mapped` the code is converted and nothing is left.

`inherited[]` gains `action`: `retyped`, `code` (an N2a field; `line` is its
first reference in the `.pas`) or `skipped` (every other state, and a retype
whose block cannot be located or re-emitted -- `reason` says why). A retyped
instance is one `converted[]` line, `<Name>: inherited <TFrom> -> <TTo>
(declared in <Unit>)`, with an `items[]` entry of kind
`inherited-instance-retyped` -- not a warning. `--only` filters retyped and
code entries by name (a code-only name counts in `only_matched[]`); R26 does not
count a retyped instance as left unconverted. `info --json` advertises it as
`capabilities.inherited_retype: true`.
**Resolved defaults are written to streamable paths only** (1.25.2). A
`#link`'d source property absent from the block is written with its declared
`default` -- only when every hop of the target path is a PUBLISHED property
(the only kind a `.dfm` streams); a path through a public hop such as a
collection's `Items` or `TFieldDefs.ParentDef` gets nothing. A property's
attributes (`[Default(False)]`) are never read as its `default` clause.

**The most-derived declaration wins** (1.26.1). The value written is the
SOURCE's declared default -- the value the source component really had -- and
it is written even when it equals the target's default (a deliberate choice,
D3: Delphi trims a redundant default on the next save, while leaving a property
absent silently adopts a value nobody chose). One exception: when the TARGET
class redeclares the default of an inherited property, and the source's
default comes from a class the target also descends from, the target's
redeclaration is the more derived one and wins -- nothing is written and a
reemit note says so (`N resolved default(s) not written -- <paths>: <T>
redeclares the default, and the most-derived declaration wins, so the T default
applies`). TAutoIncField -> TFDAutoIncField is the case: Data.DB.TField declares
`AutoGenerateValue default arNone`, TFDAutoIncField redeclares `default
arAutoInc`, and writing `arNone` turned auto-increment off. A default the source
class redeclared itself is still written (it is the source's real value), as is
one both classes share. Top-level, same-named paths only. The target's class
chain is followed across units and through a generic ancestor
(`TDstG = class(TGenBase<Integer>)`), as far as the index resolves it; an
ancestor the index cannot resolve ends the chain, and the source default is
then written.

**Collections** (1.25.1). A collection-valued property (`FieldDefs = < item ...
end>`) streams as ONE leaf. A whole-collection `#link FieldDefs <- FieldDefs`
relocates it verbatim, as before. Links on its ITEM members --
`#link FieldDefs.Items.Name <- FieldDefs.Items.Name` -- now take effect too, and
ahead of an `#ignore FieldDefs` on the same block (they are the more specific
rule): when every such link is an identity link and the To type publishes the
property with the SAME collection type, the collection is carried verbatim
(reemit note `collection FieldDefs carried, items unchanged (#link FieldDefs.*
at line(s) ...; N item(s))`). When they cannot be honoured -- a renaming item
link, another collection type, or none on the `.dfm` surface (FireDAC's
TFDTable publishes neither FieldDefs nor IndexDefs) -- the collection is NOT
carried, a reemit note says why with its item count, and it is COUNTED as
dropped: `dropped FieldDefs`, the `dropped on N of M` warning and `unlinked[]`.
A collection the book does not mention at all is dropped and counted the same
way. A bare `#ignore FieldDefs` with no item links accepts the drop SILENTLY, even for a non-empty collection -- a deliberate choice of the book, like any `#ignore`.

**Descendant warnings** (1.25.0). Converting an ANCESTOR does not touch its
descendants: each descendant `.dfm` still says `inherited X: TOld`, and VCL
streaming then fails at load (`EClassNotFound`, or `EReadError` on an
overridden property the To type lacks); descendant code using From-only
members no longer compiles. `convert-apply` SAYS so; converting the descendant next retypes them (C8 N2, 1.26.0).
For every instance the run converts it lists each descendant unit -- a class
descending from the unit's root class at any level (the index's
`type_ancestors`), or a form hosting that class as an `inline` frame -- whose
`.dfm` re-opens the instance (`inherited` / `inline`, still the From type) or
whose code references the field (a method of a descendant class):

```
line N: warning: descendant <Unit> still streams <Name> as <TOld> -- convert it next (needs C8 N2)
```

N is the line of the instance's `object` block in the converted (ancestor)
`.dfm`. JSON: that string in `warnings[]`, `items[]` kind
`descendant-not-converted`, and `descendants[]` (always present)
`{unit, name, type, line, reason}` -- `line` is the descendant `.dfm`'s
block, or its first code reference when the `.dfm` does not re-open it;
`reason` is `dfm`, `code` or `both`. `--only` filters it; in batch mode each
unit's `apply/1` carries its own. It is a WARNING: the unit is never refused
because of it, and descendants are not edited. LIMIT: a descendant outside the
`--db` set cannot be seen -- the list covers the project index only.
`info --json`: `capabilities.descendant_warnings: true`.

`convert-apply` locates every `.dfm` component instance whose class matches a
`#convert FromType` rule, then rewrites all **5 conversion surfaces** for each:

1. **`.pas` declaration retype** -- `Name: FromType;` -> `Name: ToType;` on the
   instance's published field declaration.
2. **`.pas` uses-add** -- adds ToType's declaring unit to the `.pas` `uses`
   clause (once per distinct ToType), via `TFindUnitRefactoring.Build` -- the
   INTERFACE uses when the retyped field is declared in the interface section
   (1.23.0; a form's published fields always are), else the implementation
   uses when the unit has one. A To unit the unit already uses ONLY in its
   implementation clause is MOVED to the interface clause in that case.
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

   **A `#link` carrying a CLASS cast never rewrites a `.pas` access site** (1.27.0,
   interim owner decision until a member-replacement feature is designed). A
   cast's `pas` template is a STATEMENT (`{dst}.Assign({src});`) and an access
   site is the member token INSIDE an expression (`pic1.Picture.Data := 'seed'`):
   there is no correct splice, and `{src}` would read the From member the
   retyped instance no longer has. 1.26.x spliced it anyway and wrote
   `pic1.pic1.Glyph.Assign(CastPic(pic1.Picture));.Data := 'seed'`. Now every
   bound site is left as it is and reported once:
   `line N: #link To <- From : Cast -- access site <file>:<line> <inst>.<From>
   not rewritten: the cast's pas template is a statement and has no correct
   splice inside an expression; convert this access site by hand` -- a warning,
   `items[]` kind `cast-not-applied` with `instance`, `file`, `line`, `path`
   (the From member) and `value` (the cast). A cast the `--castlib` does not
   know, or one with no `pas` template, keeps its single per-rule
   `cast-not-applied`. The `.dfm` half of the cast (`dfm` hints, `dfmdata`,
   `compat`) is unchanged. The 1.26.x kind `cast-applied` is retired. Because
   a template no longer reaches the `.pas`, the converted unit fails to compile
   at exactly those sites, and the uses reconciliation has no template routine
   to add. `info --json`: `capabilities.cast_site_refusal: true`.

**Value casts: `StripDB`** (1.27.0, C15). A castlib `cast` block with a
`value <transform>` line is a VALUE cast: a transform built into the engine
that rewrites a linked STRING value. It is not a class cast -- no `pas`
template, never refused like one. The one transform is `strip-db`, shipped as

```
cast StripDB
  accepts string
  yields  string
  value   strip-db
  todo    'TableName kept its .db where it was not one string literal -- check by hand'
end
```

and named in a book as `#link TableName <- TableName : StripDB`. It removes ONE
trailing `.db`, any case (`'MET1.db'` -> `'MET1'`, `'X.DB'` -> `'X'`); every
other value is left exactly as it is (`'A.dbf'`, `'A.db.bak'`, `'MET1'`, `''`).
No patterns and no parameters. An unknown `value` keyword is a castlib LOAD
ERROR: convert-apply fails the unit (exit 2) naming the file, the line and the
keyword, because a cast silently not performed is the worse outcome.
On the `.dfm` side the value of each converted instance is rewritten when that
changes it. On the `.pas` side only `<instance>.<Prop> := '<one literal>';`
has the literal rewritten, quotes re-escaped -- STRICTLY: the literal must be
followed on the SAME line by nothing but blanks / closed comments and `;`
(blanks, tabs and `{comments}` between the property and `:=` are fine). A
literal that ends its line (a continuation may follow, even behind a comment
line), one followed by `#nn` or `+`, and a statement ended by `else` / `end`
without `;` are CHECKS, never rewrites. Any other right-hand side (a
concatenation, a variable, a call, `Format(...)`) and every read of the
property get NO edit and a warning. Every OTHER reference to the property in
the unit -- `with t1 do TableName := 'W.db';`, a site the index cannot vouch
for, another object's same-named member -- is a `value-cast-check` naming its
line (`... the receiver is not resolved to a converted instance (a with block,
or a site the index cannot vouch for), not rewritten; the .dfm value is, check
by hand`): the `.dfm` value changes regardless, so silence is not an option.
A `.dfm` value that is not ONE string literal (a multi-line `'A' + 'B.db'`, a
`'X.db'#0` char code) is a `value-cast-check` too, left as it is. Report:
`items[]` kind `value-cast-applied` (field `access_sites`; `old_value`, `value`,
`file`, `line` -- for the `.dfm` the property's own line) and
`value-cast-check` (field `warnings`, e.g. `line 2: warning: SForm.pas:28
t2.TableName -- value cast StripDB: non-literal assignment, check by hand`);
text `value casts: N value(s) changed (.dfm D, .pas P), W site(s) to check by
hand`. A renaming value-cast link (`#link To <- From : StripDB`, To <> From)
renames the member like a plain link and reports its literals for checking.
`info --json`: `capabilities.value_cast_strip_db: true`.

**What the `.pas` still uses (`pas_uses[]`, 1.27.0).** Every run -- dry run
and `--apply` -- lists what the unit's code uses that the book does not
convert, so the next rule to write is visible. One row per (instance, member)
the code reaches through a converted instance (the same bound sites surface #4
rewrites), then one per global the unit uses from a unit the uses
reconciliation removes:

```
{"instance":"pic1","from_type":"TPicOld","to_type":"TPicNew","member":"DoOld",
 "kind":"method","visibility":"public","declaring_unit":"LibOld",
 "declared_in":"TPicOld","status":"unmapped","lines":[26,28],"count":2}
```

`status`: `mapped` (a `#link` whose From path starts with the member covers it -- a value cast such as StripDB included --
for that instance's `#convert` block, and convert-apply handles its sites),
`cast-refused` (a CLASS-cast `#link` covers it: its sites are refused, above),
`not-rewritten` (a `#link` covers it, but convert-apply makes NO `.pas` edit
for that link shape -- a dotted To or From path, e.g. the Orpheus->cx `#link
Properties.X <- X`: the site still names the From member and may not compile;
precedence cast-refused > not-rewritten > mapped), `same-name` (no link, but the To type or one of
its ancestors has a member of that name -- carried implicitly), `unmapped` (no
link and no such member: the work list) and `global-dangling` (a routine,
const, var or type from a removed unit -- the remove row's `needed_by`,
uncapped; only when the reconciliation ran). `declared_in` names the class that
declares the member, an ancestor of the From type included, followed across the
`--db` stores; `kind`/`visibility`/`declared_in`/`declaring_unit` are `''`
when no `--db` holds the member (pass the library index for inherited RTL/VCL
members). **The From class is resolved through the unit's scope (1.28.2)**,
never by bare name: the unit itself, then the LAST uses entry that declares
the name (Delphi's order; an interface field sees the interface uses only),
then the book's qualified `#convert` From, then a lone declarer -- so a VCL
`Label1: TLabel` is no longer read as `FMX.StdCtrls.TLabel` because the
library indexes both. Each row carries `resolution`: `resolved`, `ambiguous`
(several declarers and nothing settles it -- `candidates[]` lists their units,
and kind/declarer stay `''`, nothing is picked; a `StdCtrls` entry matching
both `FMX.StdCtrls` and `Vcl.StdCtrls` is ambiguous too), `class-not-found`,
`member-not-found`, or `kind-unknown` (a global whose kind the index lacks).
An unresolved To class makes `same-name` impossible: the row is `unmapped`.
`kind` adds `enum-value`. Lines are the unit's own, sorted. Text mode prints `pas uses: N
unmapped, M global-dangling, K same-name, J mapped, C cast-refused, R
not-rewritten` and one `<status> <inst>.<member> (<kind>, <visibility>, <class>
in <unit>) -- line(s) ...` per unmapped and per not-rewritten member (an
unresolved row prints `(declaring class ambiguous: <units>)` or its
resolution instead). Not listed: a member reached with no receiver (`with
X do`) and a site the index cannot vouch for. `info --json`:
`capabilities.pas_uses: true`, `capabilities.pas_uses_resolution: true`.

   **Member migration (C18 slice 1).** Inside a `#convert From -> To` block,
   `#migrate Old -> New` renames the member at every bound access site of the
   block's converted instances -- methods, events and properties alike
   (`btnTop.Click` -> `btnTop.Press`, `btnTop.OnClick := H` -> `btnTop.OnPress := H`),
   items[] `migrate-applied` (field `access_sites`; `path` Old, `value` New,
   `old_value` the member as written). `#migrate Old -> DL_NONE` is a
   DELIBERATE BREAK: the site's member access is wrapped, keeping the old text,
   `N := btnTop.Count;` -> `N := DL_NONE(btnTop.Count);`, so the unit fails to
   compile on exactly those lines (E2003 `DL_NONE`) until converted by hand;
   items[] `deliberate-break` (field `todos`, `value` `DL_NONE`, `old_value` the
   wrapped text). Both feed `pas_uses[]` status `mapped`. Sites use the `#link`
   rename's own discovery and binding; columns are converted from the index's
   UTF-8 bytes. NEVER rewritten, each an items[] `migrate-check` warning: a member
   reached through `with inst do` (the with line), a site whose receiver the
   index cannot vouch for, and a whole rule slice 1 does not realise -- a scoped
   form (`Class:` / `obj.`), a call / assignment template, trailing uses units,
   or a member a `#link` (or an earlier `#migrate`) of the block already
   converts. A `#migrate` before the first `#convert` is not a member migration
   and stays unapplied, as before. Idempotent: a renamed site no longer names
   Old, and a wrapped one is not wrapped twice. `info --json`:
   `capabilities.migrate_members: true`.
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
- `tests/autotest/run_convert_book_depth.ps1` -- the `#depth` directive and the
  `--depth` > `#depth` > 5 precedence of `proptree` / `convert-scaffold`.
- `tests/autotest/run_proptree_progress.ps1` -- `--progress-interval` progress
  lines (off by default, stderr only, the line format, exit 2 / exit 3 cases, the
  `info` capability keys, kill-safety of the write-back; the `TFDQuery` arms need
  `-LibDb <scratch library copy>`).
- `tests/autotest/run_proptree_output_speed.ps1` -- the stdout document of
  `proptree` / `convert-scaffold`: stderr ++ stdout on a merged stream, a missing
  `--progress-interval` value, byte-identity against a pre-1.20.6 engine
  (`-OldExe`, every call of the `run_proptree*` / `run_convert_scaffold*`
  runners as json and text, all `--min-visibility` values) and `TFDQuery` depth 5
  under 60 s through a replica of the editor's pipe drain (`-LibDb`).
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
