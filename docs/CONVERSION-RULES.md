# Conversion Rules DSL (Track 3, Batch 1)

`drag-lint`'s component-conversion foundation: an **index-driven** way to plan a
component/type migration (for example `TDBEdit` -> `TcxDBEdit`, or any
`TPersistent`-rooted class to another) from the REAL, AST-exact property trees of
both types, and a small **reFind-superset** rule language to record the plan.

This is Batch 1 -- the **read-only foundation**. Three new CLI verbs let you
inspect the property trees, auto-draft a conversion-rules file from them, and
validate that file's paths against the trees. **Applying** a validated rule set
(rewriting `.pas` + `.dfm`) is **Batch 2 and is NOT yet shipped.**

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

## The three verbs

All three are **read-only, CLI-only, headless.** They resolve their index DBs
from the manifest (or from repeated `--db PATH`), and with multiple `--db` the
FIRST db that resolves the qname (symbol ids are per-DB) wins.

### 1. `proptree` -- deep property enumerator

```
drag-lint proptree --qname <TClass> [--depth N] [--no-to-persistent]
                    [--format text|json] --db PATH [--db ...]
```

Walks a class's `property` symbols (own **and** inherited), parses each property's
type from its indexed signature, and recurses into class-typed property types --
producing flattened dotted paths (`Font.Color`, `Sub.Color`). By default it stops
the ancestor climb at `TPersistent`/`TObject`; `--no-to-persistent` climbs past.
Recursion is depth-capped (default **6**) with a visited-type cycle guard.

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

JSON output uses schema **`proptree/1`**:

```
$ drag-lint proptree --qname Vcl.Graphics.TFont --format json --db library-Win64.sqlite
{
  "schema": "proptree/1",
  "qname": "Vcl.Graphics.TFont",
  "root_type": "TFont",
  "truncated": false,
  "properties": [
    {
      "path": "Color",
      "type": "TColor",
      "declared_in": "Vcl.Graphics.TFont",
      "kind": "scalar",
      "is_class_typed": false
    }
  ]
}
```

`truncated` is `true` when the depth cap stopped an expansion. `is_class_typed`
marks the paths that recursion descended into.

Exit codes: **0** ok; **1** qname does not resolve to a class in any db; **2**
usage error / no readable db.

### 2. `convert-scaffold` -- auto-draft a rules file

```
drag-lint convert-scaffold --from <FromType> --to <ToType>
                           [--out <file>] --db PATH [--db ...]
```

Enumerates BOTH deep property trees (via `proptree`'s engine) and emits a VALID,
pre-filled reFind-superset rules file. Output is deterministic (paths sorted). For
each target (`To`) path it looks for source (`From`) paths whose **leaf name**
matches (case-insensitive) AND whose declared **type** is compatible:

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
names it); **2** missing `--from`/`--to` or no readable db.

### 3. `convert-validate` -- check a rules file

```
drag-lint convert-validate --rules <file> [--from <FromType>] [--to <ToType>]
                           [--print-parsed] --db PATH
```

Parses a rules file and, when `--from`/`--to` types are supplied, validates its
`#link`/`#default` **paths** against the REAL property trees of those types (built
with `proptree`'s engine). This is the crux reFind cannot do: reFind is blind PCRE
text; we know the real properties, so a `#link` target/source typo is a validation
error, not a silent no-op.

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

Exit codes: **0** valid / parse-ok; **1** errors found (parse or validation); **2**
bad args (no `--rules`) or unreadable rules file.

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
| `#link <ToPath> <- <FromPath>` | deep property assignment. **Note the `<-` arrow** -- reversed vs `#migrate`'s `->`. Read it "target gets source." |
| `#default <ToPath> = <value>` | set a target property to a default when no source maps to it |
| `#note <text>` | a human comment carried in the rule (the scaffolder emits `candidates:` and `DROPPED` notes) |

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

## Batch 2 (apply) is NOT yet shipped

Batch 1 is the read-only foundation: **enumerate, scaffold, validate.** It does
NOT rewrite any source. Actually applying a validated rule set -- rewriting the
`.pas` uses/property assignments and the `.dfm` component blocks -- is **Batch 2**
and has not shipped. A validated rules file today is a checked, machine-readable
plan; the applier that consumes it comes later.

## See also

- `docs/AI-USAGE.md`, `docs/AI-INDEX-FIRST.md` -- the verb inventory these three
  verbs join.
- reFind `readme.txt` (section 3.2) -- the adopted rule-format reference.
