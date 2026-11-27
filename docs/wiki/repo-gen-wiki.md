# repo gen-wiki: a wiki page per repository table

```
drag-lint repo gen-wiki (--repo <file> | --project <file>) --out <dir> [--per-field] [--table <T,...>] [--db <project db>] [--dry-run] [--json]
```

Writes Markdown pages from the field repository into the folder `--out`: one page per repository table with one anchored
section per field. A section gives the caption, the type, the kind, the descriptions, and where the field is shown, edited
and used by code, read from the project index.

| Flag | Meaning |
|---|---|
| `--out <dir>` | the folder the pages go to |
| `--per-field` | one page per field; the table page then becomes an index of its fields |
| `--table <T,...>` | only these tables |
| `--db <project db>` | the project index the shown / edited / used facts are read from |
| `--dry-run` | list what would be written, write nothing |
| `--json` | the result as JSON |

A second run with no change writes nothing and says `0 written, N unchanged`. A page of a table that left the repository
is listed as `stale page: FILE` and is never deleted. `index` never writes a page: the pages are made only by this verb.

See also [field-repository](field-repository) for the repository itself and [repo-field-usage](repo-field-usage) for the
usage facts.
