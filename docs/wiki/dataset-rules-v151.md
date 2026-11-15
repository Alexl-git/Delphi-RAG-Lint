# Dataset and transaction rules (`dataset-edit-without-post`, `sql-select-star`, `transaction-without-rollback`, dataset loops)

Four lint checks for code that works on a dataset or a database transaction. All four look at the syntax tree of one unit; none needs the index (run `lint-all` for a whole project as usual).

## Running them from the CLI
```
drag-lint lint <unit.pas>                                         (every default-on rule)
drag-lint lint-all --db <project.sqlite> --rule dataset-edit-without-post
drag-lint lint-all --db <project.sqlite> --enable sql-select-star  (a rule that ships OFF)
```

## dataset-edit-without-post (warning, OFF by default)

Ships OFF since 1.51: on the measured projects every hit was a change handler that leaves the edit open for a later Post by design. Turn it on with `--enable dataset-edit-without-post`.
`Q.Edit`, `Q.Append` or `Q.Insert` (no arguments) starts a record change, the same routine then writes a field of that dataset (`Q.FieldByName('A').AsInteger := 1`, `Q.Fields[0].AsString := ..`, or the same inside `with Q do`), and it never calls `Post`, `Cancel`, `CheckBrowseMode` or a cursor move on `Q`. The edit is lost, or it is posted by accident when the cursor moves.
* Not reported: a routine that only calls `Edit` (the Save button's handler posts), a dataset passed on to another routine, a `Post` / `Cancel` on the same dataset anywhere after the edit, `Next` / `Prior` / `First` / `Last` / `Locate` (they post on their own).

## sql-select-star (info, OFF by default)
A style rule, so it ships OFF; turn it on with `--enable sql-select-star`.
`SELECT *` or `SELECT alias.*` in a string literal that is assigned to `.SQL.Text` / `.CommandText`, added with `.SQL.Add` or passed to `Open`, `ExecSQL`, `Execute`, `ExecuteDirect`. A later `ALTER TABLE` silently changes the result set. A concatenated string, `COUNT(*)` and a multiplication are not reported.

## transaction-without-rollback (warning)
`StartTransaction` and `Commit` on the same connection or transaction object in one routine that also has a `try ... except` at or after the start, and no `Rollback` on that connection anywhere in the routine. The except part swallows the error and the transaction stays open. Not reported: a routine without any `try` (the exception goes to the caller), a Rollback in the except or finally part, a routine that only starts the transaction.

## Dataset loop that never advances (reported as `loop-condition-invariant`)
`while not Q.Eof do` / `repeat ... until Q.Eof` (and `Bof`) whose body never calls `Next`, `Delete` or another cursor move on `Q`, or a `Continue` that runs before the loop's own `Next`. Not reported: a loop that can `Break` / `Exit` / raise, a loop that hands `Q` to another routine, a `Next` in an enclosing `finally`, `Next; Continue;`.

Guards: `tests\lint\dataset-edit-without-post.pas`, `sql-select-star.pas`, `transaction-without-rollback.pas`, `dataset-loop-without-next.pas`.
