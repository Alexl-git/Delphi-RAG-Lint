# schema-unknown-column, schema-type-mismatch, schema-required-not-set (lane SCHEMA, 1.54)

Three checks that compare dataset code, SQL texts and persistent fields with the schema facts of the project's field
repository (`.dlrepo`), and an option for the two older schema rules. They run in `lint` and `lint-all`, in the IDE and in
VS Code.

```
drag-lint lint-all --db <project.sqlite> --project <App.dproj> --rule schema-unknown-column
drag-lint lint <unit.pas> --db <project.sqlite> --rule schema-type-mismatch
drag-lint lint-all --db <project.sqlite> --project <App.dproj> --rule schema-required-not-set
```

Turn one off with `"disabled": ["schema-type-mismatch"]` in the lint config, accept one line with a `dl:ok` marker, or accept
a table or column with a `DL_EXCEPTIONS` row of the repository (rule id or `*`, dataset `<unit>.<component>`, table, field).

## What they need

* A project index and a field repository with schema facts (see [schema-lint](schema-lint) and
  [field-repository](field-repository)). The repository is the one of `--project`, else of the project the index belongs to.
  Without a repository, or with one that holds no schema facts, all three are silent; a configured repository that is missing
  is named on stderr.
* A table counts as known when a schema read covered it: at least one of its columns has a stored type. A table entered from
  forms or by hand only is not judged.
* Keep the repository current (`repo refresh-schema`): a column added to the database after the last schema read is
  reported as missing.

## schema-unknown-column (warning, project-wide)

* `Q.FieldByName('NOTEX')` where the one SQL text of `Q` is `SELECT * FROM ORDERS` (or its `TableName` is `ORDERS`) and the
  table has no such column -- `FieldByName` raises at run time.
* A select item or an `INSERT` column that the known table does not have, in a SQL text of the code or of the form
  (`SQL.Strings`, `CommandText`). One finding per text, with all its columns.
* A persistent field of the form whose `FieldName` the table does not have -- the dataset does not open.

## schema-type-mismatch (warning, project-wide)

* An accessor whose kind clashes with the column: reading `AsInteger`, `AsFloat`, `AsDateTime` and their kin of CHAR / VARCHAR
  (converts the text, EConvertError for anything else); `AsInteger` / `AsBoolean` on DATE, TIME, TIMESTAMP; `AsDateTime` on a
  number; `AsInteger`, `AsFloat`, `AsDateTime` on BOOLEAN; any of them on a BLOB (these raise, read or written). On
  `FieldByName('X')`, and on a persistent field, also of another unit's data module (`dmMain.qryX.AsInteger`).
* A persistent field class of another kind than its column (`TIntegerField` on a VARCHAR) -- the dataset does not open.

Allowed: writing text with any accessor (`FieldByName('CODE').AsInteger := 5`: a string field calls `SetAsString`), writing
`AsInteger` of a memo; `AsString`, `AsVariant`, `Value`, `AsBoolean` on text and numbers (flag columns), `AsInteger` on NUMERIC, `AsFloat`
on a date, memo fields on text.

## schema-required-not-set (warning, project-wide, OFF by default)

An `INSERT` that names its columns and leaves out one that is NOT NULL and that nothing fills. Not reported: a column with a
default (its own or its domain's), a trigger or a sequence; a column a generator is named after; a numeric primary key;
calculated rows; an `INSERT` without a column list. OFF because the repository does not know which columns a BEFORE INSERT
trigger fills, apart from keys. `Append` / `Post` on a dataset is not followed.

## Silent when

* the SQL is built by an expression, has a macro (`&NAME`, `!NAME`) in the select list, the row count or the FROM clause, is
  set in several places, or the dataset is a parameter, passed on or
  aliased (see [v154-sql-rules](v154-sql-rules): the same reader);
* UNION, CTE, derived table; a computed item; an unqualified column of a join; `*` over several tables;
* the field is calculated, lookup, internal or aggregate, or the unit's code sets `FieldName := 'X'`; `FindField` (it answers
  nil on purpose); `RDB$` and other pseudo columns;
* another unit, or code of the form itself, sets the SQL or `TableName` of a form's dataset or hands the dataset on; the
  component is inherited, or a descendant form has its own SQL;
* the dataset class cannot speak to the repository's database: only FireDAC, IBX, IBDAC, FIBPlus, UIB, UniDAC, Zeos and
  dbExpress classes count. BDE and ADO datasets read another database that may reuse the table names (a Paradox to Firebird
  loader does), and so may a project's own descendant class;
* the column's type or domain is not resolved, or it is OCTETS text.

Not judged: `WHERE` and `UPDATE .. SET` columns, a field kept in a variable (`F := Q.FieldByName('X')`), a FireDAC connection
to another database than the repository's.

## Local names (option of schema-maxlen-drift and schema-length-bound, OFF)

```
"schema_rules": { "local_naming_match": true }
```

A local variable named `t<FIELD>` or `fld<FIELD>` (the part after the prefix in upper case: `tDIMABBR`, `fldNOTE`) then
counts as that column: `tDIMABBR := Copy(s, 1, 35)` and a literal that is too long are reported. Only when every column of
that name has one and the same char length; the table is shown as `*` when there are several. Needs the index.

## What the rules add over the compiler

dcc32 37.0 (the BDE needs Win32) with all warnings and hints compiles every positive case without a message about the field, the SQL or the type;
the compiler sees strings. The errors appear when the line runs or the dataset opens.

## Measured

Read-only copies of five project indexes, 2026-11-24, against one repository seeded from the Micronite DDL script of
2026-10-29 (140 tables, 2205 columns). Every finding was read and compared with the live database.

| corpus | schema-unknown-column | schema-type-mismatch | schema-required-not-set |
|---|---|---|---|
| Loader2025 (Paradox to Firebird) | 2, both right (`GONOFF.OFF` became `OOFF`) | 19, all right (TIME columns that became DOUBLE PRECISION) | 0 |
| Micronite2027 client, MicroniteMW1Service server (ORM3) | 0 | 0 | 0 |
| TableTools370P | 0 | 0 | 0 |
| M2022 | 0 | 0 | 0 |

Before BDE and ADO datasets were excluded the Loader had about 70 wrong findings, all on Paradox tables (now a negative
fixture). The same copies against a script of 2025-02 reported every column added since then: keep the repository current.
The two default-on rules have findings on one corpus only; `schema-required-not-set` found nothing and stays OFF.

Fixtures: `tests\fixtures\v154\SCHEMA`, runner `tests\autotest\run_v154_SCHEMA.ps1`.
