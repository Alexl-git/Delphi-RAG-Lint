# import-coverage

Reads a Delphi code-coverage report and keeps, per routine, how many lines ran. `ask risk`
([ask-risk](ask-risk)) uses it to rank complex, untested routines.

```
drag-lint import-coverage --file <report.xml> --db <file.sqlite> [--json]
```

## Formats

* DelphiCodeCoverage EMMA XML: `srcfile` / `class` / `method` with a `coverage type="line, %" value="75% (3/4)"`
  child. The `(covered/total)` part is the data; a line figure wins over block, which wins over method.
* Cobertura XML: `class filename=".."` / `method` with `line number=".." hits=".."` children.

## Where it is stored

In a sidecar file `<db>.coverage.json` beside the index, not in the index. Every table of the index belongs to the
schema and a new one would be a SCHEMA_VERSION bump that re-opens every library index; `metrics --save` already keeps
its history the same way (`<db>.metrics.jsonl`). The index is opened read-only. A re-import replaces the file.

## Matching, and what is not dropped

A record matches an indexed routine when the file base name is the same (any case) and the record's
`Class.Method` equals the routine's qualified name or one is a dotted suffix of the other. The summary lists every
record that matches no routine, every report file that matches no indexed file, and counts the indexed routines
that have no record. Those routines score as 0% covered in `ask risk`.

Exit 0 = imported; 1 = sidecar not writable; 2 = missing `--file` / `--db`, file or index missing, no routine record
in the report; 3 = unknown flag.
