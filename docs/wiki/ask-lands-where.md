# ask: lands-where

**Where does this field's value end up?** From an ORM property or a form control, across the process boundary to the database column, the server code that writes and reads it, and the triggers that touch it. One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question lands-where --target <selection> --db <client.sqlite> --server-db <server.sqlite> --sql-db <sql-index.sqlite>
```

The same question through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question lands-where -Target <selection> -DbPath <CLIENT index> -ServerDbPath <SERVER index> -SqlDbPath <SQL-script index>
```

## You select

Any one of:

* an ORM class property -- `uCAUSFAIL.TmcCAUSFAIL.REASON`;
* the matching interface property -- `iCAUSFAIL.ImcCAUSFAIL.REASON`;
* a backing field -- `<Unit>.<Class>.f<FIELD>`;
* a form control -- `<Form>.<Control>`, which first resolves through the same chain as [`feeds-from`](ask-feeds-from).

## The chart shows

ORM property -> `TABLE.COLUMN` (anchored to its declaration in the SQL scripts) -> the server DataService rows that WRITE and READ it (anchored: the `INSERT` / `UPDATE` column list, the `SELECT` alias, and `Obj.<PROP>` member accesses) -> the triggers whose bodies use `NEW.<COL>` / `OLD.<COL>`; plus the client form bindings whose data-source chain resolves to that table.

## Read it carefully

* **The property-to-column hop is a naming convention.** `Tmc<T>.PROP` = `T.PROP` is graded `[inferred]`, with the measured count printed: 1,991 of 1,997 table-class properties on ORM3 CLIENT follow it.
* **Column states.** A column is shown as one of: `column` (declared in the current scripts), `older-script-only`, `quoted` (a quoted identifier -- see the engine note below), `server-sql` (used by the server's SQL but not declared in any script), or `not a column`.
* **Positional binds.** A `Params[i]` bind is visible only through the `Obj.<PROP>` access that feeds it.
* **The schema is script-derived**, as for [`consumers`](ask-consumers): the `MS*.SQL` migration scripts, newest script wins -- not the live database.
* **Known engine gap:** the SQL-script index currently drops QUOTED column identifiers (e.g. `"ACTION"`, `"TABLE"` -- exactly the reserved-word columns), so such columns may show as `quoted` rather than `column` until the engine fix lands.

## It stands on

Three indexes read together -- the CLIENT project index, the SERVER project index and the SQL-script index -- joined on qualified name, file and line (the cross-database identity contract in the [index schema](https://github.com/Alexl-git/Delphi-RAG-Lint/blob/main/docs/INDEX-SCHEMA.md)), plus DFM bindings and member accesses.
