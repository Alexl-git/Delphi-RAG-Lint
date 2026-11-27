# metrics

Size and complexity numbers read from the index: one row per routine, class,
unit and folder, a total, and two sections (repeated parameter groups, one
implementor / one descendant). `--save` and `--trend` show how the numbers moved
between two index runs. Every number comes from stored facts; nothing is
estimated, and a routine without stored facts has no row.

## Running it from the CLI

```
drag-lint metrics --db <file.sqlite> [--level routine,class,unit,folder|all] [--in <path prefix>] [--top <n>] [--save] [--trend] [--json]
```

* `--db` is the index to read. It is opened read-only.
* `--level` picks the row tables (default all four). The total line and the two
  sections are always printed.
* `--in <path prefix>` keeps the files whose path starts with that text. Fan
  values are still counted over the whole index.
* `--top <n>`: the text tables show the `n` rows with the highest cyclomatic
  value (default 20, `0` = all). `--json` is never cut.
* `--json` prints one document (below).

## What the columns mean

| column | routine | class | unit | folder / total |
|---|---|---|---|---|
| `cyclomatic` | its stored value | sum over its routines | sum | sum |
| `cyclomatic_max` | same value | largest routine | largest | largest |
| `routines` | 1 | its routines | its routines | sum |
| `body_loc` | its stored value | sum over routines that are not nested | same | sum |
| `lines` | body span | declaration span | file length | sum |
| `comment_lines` | inside the body | declaration + its routines | whole file | sum |
| `params` | declared parameters | largest count | largest | largest |
| `fan_in` | distinct routines calling it | heirs in this index | units using it | outside units using a unit of the folder |
| `fan_out` | distinct routines it calls | declared ancestors | units it uses | units used outside the folder |

A nested routine has its own row (`nested` = true, `parent` = the enclosing
routine); its lines are already inside the enclosing routine's `body_loc`, so
sums above routine level leave it out. A folder row covers the units directly
in that folder, not its sub-folders. The total row has no fan (`-` in text,
`null` in JSON). A record is a class row only when it has routines.

## The two sections

* **Repeated parameter groups**: three or more parameters (same name and type)
  that occur together in three or more differently named routines. Overloads,
  overrides and an interface method with its implementors count once. A group
  of four shared by the same routines is one row of four, not four rows of
  three.
* **One implementor / one descendant**: an interface with exactly one
  implementing type, or a class with exactly one direct descendant, counted
  inside this index. A heir in a unit outside the index is not seen, so read a
  row as "one in this project".

## Saving and comparing

```
drag-lint metrics --db <db> --save            append a snapshot, print the rows
drag-lint metrics --db <db> --trend           compare the last two snapshots
drag-lint metrics --db <db> --save --trend    save, then compare with the one before
```

`--save` appends one line (the total and every unit row) to
`<db>.metrics.jsonl`, the history file beside the index. The index itself is not
written. `--trend` compares the last two lines: the total numbers as
`from -> to (delta)`, then each unit that was added, removed or changed;
unchanged units are counted. With fewer than two snapshots `--trend` is refused
and says how many the file holds. `--save` and `--trend` record the whole
index, so they are refused together with `--in`.

## JSON

`metrics --json`: `schema` (`metrics/1`), `db`, `indexed_at_unix`, `total`,
`folders[]`, `units[]`, `classes[]`, `routines[]`, `param_groups[]`,
`single_heirs[]`. A row has `level`, `name`, `parent`, `kind`, `file`, `line`,
`symbol_id`, `nested`, `units`, `classes`, `interfaces`, `routines`,
`cyclomatic`, `cyclomatic_max`, `body_loc`, `body_loc_max`, `lines`,
`comment_lines`, `params`, `fan_in`, `fan_out`. Row order is fixed: routines
and classes by file, line, name; units by name; folders by path.
`param_groups[]` = `{params[], routines[{name, file, line}]}`;
`single_heirs[]` = `{kind, name, file, line, heir, heir_file, heir_line}`.

`metrics --trend --json`: `schema` (`metrics-trend/1`), `snapshots`, `from`,
`to`, `total{number: {from, to, delta}}`, `units[{status, name, file,
numbers}]`, `units_unchanged`.

Member names and their meaning are stable; later versions add members, they do
not rename them. The same rows are available to engine code through
`DRagLint.Query.Metrics.LoadMetrics`.

Exit codes: 0 = answered; 1 = the history file cannot be read or written;
2 = no `--db`, an index that is missing or unreadable, an unknown `--level`,
`--save` / `--trend` with `--in`, or `--trend` with fewer than two snapshots;
3 = an unknown flag.

## Examples

```
drag-lint metrics --db <db> --level routine
drag-lint metrics --db <db> --level unit,folder --top 0
drag-lint metrics --db <db> --in C:\Projects\App\src\reports --json
drag-lint metrics --db <db> --save --trend
```
