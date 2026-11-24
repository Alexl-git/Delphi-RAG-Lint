# sql-param-mismatch and query-in-loop (lane SQL, 1.54)

Two checks for code that runs SQL through a dataset component, and an option of `field-by-name-in-loop`. They run in
`lint` and `lint-all`, in the IDE and in VS Code.

```
drag-lint lint <unit.pas> --db <project.sqlite> --rule sql-param-mismatch
drag-lint lint-all --db <project.sqlite> --rule query-in-loop
```

Turn one off with `"disabled": ["query-in-loop"]` in the lint config, or approve one line with a `dl:ok` marker.

## sql-param-mismatch (warning, firedac)

Reads the one SQL text of a query and compares its parameters with the code:

* `Q.ParamByName('ID2')` when the SQL has only `:ID` -- FireDAC raises "Parameter [ID2] not found" at run time.
* `Q.Open` / `Q.ExecSQL` when one of the SQL's parameters is never set -- reported at the first run.

The SQL may be a literal, literals joined with `+`, a constant of the unit or (with the index) of another unit,
`SQL.Clear` + `SQL.Add` lines in one statement list, `Open('..')`, or the `SQL.Strings` / `CommandText` of the form. The query may be a local variable, a field or component
of the class, or a component of another unit's data module (`DM.qOrders`, needs the index). Parameter names are compared
without case. Known classes: TFDQuery, TFDCommand, TQuery, TADOQuery, TSQLQuery, TIBQuery, TIBSQL and the UniDAC, Zeos,
MyDAC, ODAC, SDAC, PgDAC and IBDAC queries.

Silent when:

* the SQL is built by an expression, loaded from a file, or set in more than one place;
* the SQL has a macro (`&X`, `!X`), positional (`?`) or numbered (`:1`) parameters, or a colon name in a comment; it is
  `EXECUTE BLOCK` or DDL (the colons are PSQL variables); `::` casts and colons in quoted text are not parameters;
* `ParamCheck` or `ResourceOptions.ParamCreate` is switched, or code adds, clears or parses `Params` itself;
* the dataset is a parameter, is passed on, aliased or put into a `with` of several targets, or is not created by one
  `T.Create` in the routine (locals);
* the component is inherited, or a descendant form has its own SQL;
* for a field or a component: no index, or another unit sets its SQL or takes the dataset over;
* never-set only: a parameter is set by a name the code computes, by position or as `Open(sql, [values])`; a
  `MasterSource` / `DataSource` fills the parameters; the form stores a value in `ParamData`; the statement is a stored
  procedure call or has `RETURNING .. INTO :x`; a component whose parameters no code of the unit sets.

## query-in-loop (hint, firedac)

A dataset is opened or executed once per loop iteration:

* `D.Open`, `ExecSQL`, `Execute`, `ExecProc`, `Active := True` in the body of `for`, `for in`, `while` or `repeat`;
* with the index: a call in the loop of a routine whose own SQL the index knows (`symbol_facts.sql_reads` /
  `sql_writes`), directly or one call further down, over certain call edges only.

Silent when:

* the receiver is the loop variable or is taken from it (`for DS in List do DS.Open`, `List[I].Open`), or is assigned in
  the loop from something else than a `Create`;
* the loop has at most ten literal steps (`for I := 0 to 3`, `for S in ['A', 'B']`);
* it is a retry loop (`try .. except` around the call and a way out, or a counter named retry / attempt / tries) or a
  polling loop (`while True`, `Terminated`, `Sleep`); the loop condition names the same dataset (`until Q.RowsAffected = 0`);
* the branch leaves the loop (`Break`, `Exit`, `raise` at the end of its statement list): the query runs once;
* an `if` asks a cache or the dataset first (`TryGetValue`, `ContainsKey`, `not D.Active`, `= nil`); a called routine that
  uses a dictionary cache is not followed;
* array DML (`Execute(Count)`, `Params.ArraySize`); in-memory datasets; a whole statement taken from a list or a DDL text;
* an anonymous method or nested routine declared in the loop; a call more than two levels away.

## field-by-name-in-loop: ParamByName (option, OFF)

`"thresholds": {"field-by-name-in-loop.param_by_name": 1}` makes the rule also report `ParamByName` in a loop, one
finding per outermost loop (hint). Not reported: a loop that sets the SQL, creates the dataset or passes it on. There is
no automatic fix for this part.

## What the rules add over the compiler

dcc64 37.0 with all warnings and hints compiles both cases without a message; the parameter error appears only when the
line runs.

## Measured

See the numbers below; the corpora are copies of real project indexes.

<!-- measured -->
