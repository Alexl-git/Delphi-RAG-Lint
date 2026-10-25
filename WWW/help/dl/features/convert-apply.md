---
id: convert-apply
title: convert-apply
summary: "Locates .dfm component instances that match a #convert rule from a conversion-rules file and rewrites all five surfaces: declaration retype, uses-add"
product: DL
group: component-conversion
order: 60001
since: 1.2.0-alpha
status: shipped
updated: 1.34.1-alpha
---

# convert-apply

Locates .dfm component instances that match a #convert rule from a conversion-rules file and rewrites all five surfaces: declaration retype, uses-add.

Convert the forms and units that use an old component to its replacement, by the rules in a conversion-rules book. Preview first; add --apply to write.

## How to run it

Full flag list: [convert-apply in the CLI reference](../cli.md#convert-apply).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--unit` | `<F.pas>` |  |  |
| `--rules` | `<file>` |  |  |
| `--db` | `PATH` |  |  |
| `--only` |  |  |  |
| `--castlib` | `<file>` |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--raise-encoding` | `<path>=utf8-bom` |  |  |
| `--no-warn-unlinked` |  |  |  |
| `--no-reconcile-uses` |  |  |  |
| `--no-reindex` |  |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |

**Needs:** index

## Details

Locates `.dfm` component instances that match a `#convert` rule from a
conversion-rules file and rewrites all five surfaces: declaration retype,
uses-add, `.dfm` re-emit, property/event access-site rewrite, and
runtime-creator retype/TODO markers. Reach for it to actually perform a
component-type conversion, after validating and scaffolding the rules file.

### Running it from the CLI
```text
drag-lint convert-apply --unit <F.pas> --rules <file> --db PATH [--db ...] [--only Name1,Name2,...] [--apply] [--no-backup]
```
`--unit <F.pas>` is the unit to convert. `--rules <file>` is the
conversion-rules file. `--only Name1,Name2,...` restricts the conversion to
named component instances. Without `--apply` this is dry-run only: a preview
that writes nothing. `--apply` writes for real, with backups and a
`recovery.txt`, unless `--no-backup` is also given. `--db PATH` is required
and may be repeated.

### Uses rules: #unuse, #use, #useswap
A book's unit rules act on the unit being converted, in the same single
write: `#unuse Old` takes Old out of whichever uses clause holds it, `#use New`
adds New to the implementation uses when neither clause has it, and
`#useswap Old -> New1, New2` swaps them in Old's section (a unit without Old
is not touched). A unit the book both adds and removes is kept. An entry to
remove inside a `{$IF...}` region refuses the unit (exit 1, nothing written).
The JSON `uses[]` lists every change with its action, section, line and rule.

### Uses reconciliation (C9, 1.27.0; on by default)
convert-apply re-indexes the converted `.pas` and `.dfm` IN MEMORY (nothing
is written to a database, so the dry run shows exactly what `--apply` will
write) and decides each `#unuse` / `#useswap Old` from what the converted
unit still needs:
* **kept** while a component the converted `.dfm` still streams has a class
  from that unit (an unconverted instance, a second component type, an
  inherited instance) -- a `kept` row and a warning naming the components;
* **removed** when only `.pas` code still needs it -- the remove row names the
  references left dangling (`needed_by`, and `pas_uses[]` rows with status
  `global-dangling`); the compile errors are the intended signal;
* **kept** when no `--db` indexes the unit (`unit-rule-unverified`): pass the
  platform library `--db` (`drag-lint resolve-dbs --platform Win32|Win64`) so
  the engine can see it.

Presence is scope-alias aware (`#unuse DBTables` matches `Bde.DBTables`,
`#use DB` is satisfied by `Data.DB`). When a To type is declared in two
units, none is picked: it is reported in `uses_unresolved` (with the line of
the retyped field) and as a `uses-unit-ambiguous` warning -- add `#use <unit>`
to the book to choose. That `#use` then puts the unit where the retyped field
needs it: the INTERFACE uses when the field is declared there, moved there when
the unit used it only in its implementation (a `moved` row). Every unit the
conversion itself writes into the uses clause (a To type's unit, or a unit
named after the To type on a `#convert` line) is an `add` row with rule
`#convert`, counted in `uses_added`. After `--apply`
the unit's own project index is refreshed (`--no-reindex` skips it).
`--no-reconcile-uses` restores the 1.26 behaviour exactly.

### Cast links in code (1.27.0)
A `#link To <- From : Cast` converts the `.dfm` as before, but never rewrites
a `.pas` access site: a cast's `pas` template is a statement, and there is no
correct place to put a statement inside an expression such as
`pic1.Picture.Data := 'seed'`. Each such site is left as it is and reported
as a `cast-not-applied` warning naming the file, line, instance and cast --
"convert this access site by hand". The unit will not compile until you do;
that compile error is the signal.

### StripDB: dropping a Paradox .db (1.27.0)
`#link TableName <- TableName : StripDB` (with `--castlib` pointing at the
shipped `casts.castlib`) turns `'MET1.db'` into `'MET1'` -- in the `.dfm`, and
in code where the table name is assigned one plain string that ends the
statement on its line (`t1.TableName := 'MET1.db';`). Anything else in code
(a concatenation, a variable, a read, a string split over lines, a
`with t1 do TableName := ...`) is left alone and listed as a warning to check
by hand, naming its line. Values without `.db` are never touched.

### What is left to convert (1.27.0)
Every run also lists what the unit's code still uses: each member reached
through a converted instance, and each global from a unit the run removes.
JSON `pas_uses[]` gives one row per member with its kind, where it is declared
(the From class found through the unit's own uses, so a VCL `TLabel` is never
read as the FMX one; when nothing settles it the row says `resolution:
ambiguous` and lists the `candidates`, 1.28.2), its lines and a status -- `mapped`, `cast-refused`, `not-rewritten` (a rule
covers it, but convert-apply does not edit the code for that rule's shape -- a
dotted path such as `#link Properties.X <- X` -- so the code still names the
old member), `same-name` (the new type has the same name, so it carries over),
`unmapped` (no rule and no such member: your work list) or `global-dangling`.
Text mode prints a one-line count and the unmapped and not-rewritten members
with their lines.

### Encoding guard (1.34.1)
A value `--apply` would write into a `.pas` that the file's current encoding
cannot hold (an ANSI unit receiving U+0413, say) refuses the unit: nothing is
written, exit `1`, and apply/1 carries `refusal_kind: "encoding_refused"` plus
`encoding_refused {file, file_encoding (ansi|utf8|utf8-bom|utf16-bom),
raise_to: "utf8-bom", chars_total, chars[] {code, text, line}}` (distinct code
points, at most 8, first line each). The dry run reports the same refusal.
`--raise-encoding "<path>=utf8-bom"` (repeatable; the path must be a `--unit`
of the call or its `.dfm`, the only level is `utf8-bom`, anything else is exit
`2`) stores that file as UTF-8 with a BOM in the same write transaction as the
edits, also when every value would have fitted; the `.BCK<n>` backup applies as
usual. A text `.dfm` never refuses: a value its encoding cannot hold is written
as Delphi `#codes` (`'Gr'#246'sse'`). A binary (TPF0) `.dfm` has no text
encoding and is never compared or rewritten. `info --json`
`capabilities.convert_encoding_guard` is `true` when this ships.
### Exit codes
`0` converted (or nothing to do); `1` the unit was REFUSED (a deliberate
refusal: nothing written, the reason printed); `2` a write failed or was
rolled back, or the run could not start (a missing unit or rules file);
`3` an unknown argument;
`6` the `--castlib` cannot be used (it fails to load, or names an unknown
`value` keyword) -- a configuration error, so it no longer reads as a write
failure. A batch (`--unit` repeated) exits with the worst unit's code.

### Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

### What it needs
An index IS required -- `convert-apply` reads the project's index database.
The project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`;
run `drag-lint resolve-dbs --project <X.dproj>` if you are unsure which one.

### Example
Illustrative only:
```text
drag-lint convert-apply --unit C:\Projects\MyApp\frmOrders.pas --rules C:\Projects\MyApp\convert-rules\OvcTable-to-cxGrid.rules --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --only tblOrders
```
This would preview (no `--apply`) the conversion of the `tblOrders` component
in `frmOrders.pas` across all five surfaces, without writing any changes.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
