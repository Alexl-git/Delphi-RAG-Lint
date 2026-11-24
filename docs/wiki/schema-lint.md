# schema-lint

Two lint rules that compare your code with the database's declared column lengths:
`schema-maxlen-drift` and `schema-length-bound`. They read the lengths from the project's
**field repository** (`.dlrepo`), never from the code index, and run in `lint-all` and
`lint <file>`. Both are ON by default and stay silent when the project has no repository or the
repository holds no schema facts.

## Running it from the CLI

```
drag-lint lint-all --db <project.sqlite> --project <App.dproj>
drag-lint lint-all --db <project.sqlite> --project <App.dproj> --rule schema-length-bound
drag-lint lint <Unit.pas> --db <project.sqlite> --project <App.dproj>
```

When the rules run, `lint` and `lint-all` print one line on stderr naming the facts they used. A
repository that is configured but missing or unreadable is named there too; having none is silent
(`DRAGLINT_DEBUG` shows the reason):

```
drag-lint: schema facts 2026-11-22T12:00:00Z (ddl) from MyApp.dlrepo
```

## Reaching it in the IDE

The findings appear wherever lint findings appear (the drag-lint panel, the gutter); there is
no separate menu item.

## What it needs

* A project index (`<project folder>\_D-RAG\<project>.sqlite`).
* A field repository with schema facts. The lint verbs find it from the project (`--project`, or
  the project the `--db` belongs to): `"fieldRepository": "<path>"` in
  `<project folder>\_D-RAG\drag-lint-project.json` (relative to the project folder), else a
  `"fieldRepository"` value on the project's section of `drag-lint.json`.
  The schema facts are written by `repo refresh-schema` / `repo seed-fb`. A repository without
  them, or no repository at all, makes both rules silent.
* For ORM targets: `link-orm --db <sql.sqlite> --db <project.sqlite>` (the project index LAST --
  link-orm writes its links into the last `--db`).

## The rules

| Rule | Fires when |
|---|---|
| `schema-maxlen-drift` | a constant `<TABLE>_<FIELD>_MAXLEN` (any case; a `$` in the table name written `_`) whose column is known has a value different from the column's char length; or a single string literal longer than the char length is assigned to a resolved column target |
| `schema-length-bound` | `Copy(x, i, N)` is assigned to a resolved column target, or `.Size := N` / `.MaxLength := N` is set on a resolved field, with N (a literal or a constant the index resolves) larger than the char length; or a `.dfm` `TStringField` / `TWideStringField` persistent field whose `Size` (20 when the `.dfm` omits it) differs from the char length |

The char length is the field's own `CHAR_LENGTH`, else its domain's.

### Which targets are resolved

Resolution is conservative; anything it cannot prove is silent:

1. a class field linked by `link-orm` (`TORDERS.FNOTE` -> `ORDERS.NOTE`), or a property that
   writes such a field directly (`write FNOTE`; a setter method may shorten the value, so it is silent);
2. a `.dfm` persistent field: its dataset's table comes from `UpdateOptions.UpdateTableName`,
   else `TableName`, and the column from `FieldName`;
3. `<dataset>.FieldByName('<COLUMN>')` on such a dataset, where the index binds `<dataset>` to the
   form's component (a local of the same name is silent; another unit naming `frm.qryOrders` counts).

A constant counts as N only when the index binds the name on that line to it. A line edited since the
index was built is skipped. Not seen: a `TableName` / `UpdateTableName` assigned in code.

A local variable named after a field (`tDIMABBR`, `fldNOTE`) is resolved only with the option
`schema_rules.local_naming_match` (1.54, OFF by default; see [v154-schema-rules](v154-schema-rules)). Only the
text of the target's own line is read, so a statement that spans lines is silent.

## Accepting a finding

Add a `DL_EXCEPTIONS` row to the repository (rule id or `*`, dataset `<unit>.<component>`,
table, field, property; an empty column matches anything) with a reason, or put a `dl:ok`
review on the line as for any rule.

## Example

```pascal
const
  MSCLIST_DIMABBR_MAXLEN = 35;   // DIMABBR holds 10 -> schema-maxlen-drift
...
  pList.DIMABBR := Copy(pText, 1, MSCLIST_DIMNAME_MAXLEN);   // 35 > 10 -> schema-length-bound
  pOrder.NOTE := '123456789012345678901';                    // 21 > 20 -> schema-maxlen-drift
  qryOrders.FieldByName('NOTE').Size := 30;                  // 30 > 20 -> schema-length-bound
```

See also: [field-repository](field-repository), [link-orm](link-orm).
