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
| `#ignore <FromPath>` | acknowledge an F property/event is intentionally NOT mapped -- suppresses its unmapped-non-default warning (other unmapped props still warn). Added in Batch 2a-i for the re-emit engine. |
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
ownedParts / notes). It is **pure** (no file I/O, no CLI, no IDE) and is exercised
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

**Known gap -- property-default divergence:** a property ABSENT from the F DFM
equals F's default (DFM omits defaults). If F's default differs from T's default,
re-emitting it as also-absent silently adopts T's default. The engine warns when
F and T types differ, but full fidelity needs the index to capture `default`
specifiers -- a future **Batch 2a-0** (a supervised core-parser change).

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
