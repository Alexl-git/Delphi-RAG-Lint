# ask: feeds-from

**What feeds this control?** The chain behind one data-aware control, hop by hop, down to the database column. One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question feeds-from --target <Form>.<Control> --db <project.sqlite> --sql-db <sql-index.sqlite>
```

The same question through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question feeds-from -Target <Form>.<Control> -DbPath <Delphi project index> -SqlDbPath <SQL-script index>
```

Example target: `frmCausFail.colREASON`.

## You select

One data-aware control on a form (a DB edit, a grid column, a lookup, ...), named `<Form>.<Control>`.

## The chart shows

One row per hop, each graded and anchored to a file and line:

control -> datasource (DFM) -> dataset (DFM, or a code assignment -- every assignment site is scanned) -> view-model type -> table -> `TABLE.COLUMN`

## Read it carefully

* **The table hop is `[inferred]`.** It comes from table-name literals in the view-model's unit, tie-broken on the columns the controls are bound to. Every other hop is read from DFM or code.
* **A broken chain says so; it never guesses.** It ends in "chain stops here: <reason>" instead of inventing a table.
* **Interface-typed view-models stop the chain**, because the concrete type behind the interface is not known statically.
* **Dangling designer datasources.** A datasource that points at a data module not in the project is shown `[dangling]`; if code re-points it at run time, that is shown as `[re-pointed at routine:line]`.
* **Coverage is printed on the chart.** Measured on ORM3 CLIENT on 2026-09-23: 267 of 808 field-bound controls reach exactly one table, and 426 sit under dangling designer datasources.
* **The schema is script-derived**, as for [`consumers`](ask-consumers): the `MS*.SQL` migration scripts, newest script wins -- not the live database.

## It stands on

DFM data bindings and component properties, dataset assignments in code, the view-model types from the Delphi index, table-name string literals, and the SQL-script index for the table and column hop.
