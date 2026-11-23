# verify-index: measure drag-lint's resolution against DelphiLSP (internal)

`verify-index` takes a deterministic sample of references that drag-lint resolved, asks DelphiLSP where each name is declared, and reports how often the two disagree. Each disagreement is a candidate resolver bug: the `wrong` gap class, measured instead of noticed by chance. Status internal: accepted, not in `--help`. 1.53.1 adds stratified sampling of the doubtful cases and gap logging.

```
drag-lint verify-index --project <x.dproj> --db <copy.sqlite> [--sample 200] [--seed 1] [--json]
drag-lint verify-index --db <db> --delphi-lsp-config <x.delphilsp.json> --dry-run
```

Read-only: the DB is opened read-only, no source file or log is written. Use a COPY of the project DB anyway. Exit: 0 the run finished with no mismatch, 1 at least one mismatch, 2 setup error (one `ERROR: verify-index: ...` line on stderr, nothing on stdout).

## What is sampled

References of kind call, read, write, write-through, type_use, member-access, property-spec or record-field whose target is resolved and is not a local variable or parameter (locals are resolved inside one routine; sampling them would flatter the rate). The target is the call edge's target when the edge is `certain`, else the reference's symbol. The order is a seeded hash: the same DB, `--sample` and `--seed` give the same references in the same order. `--dry-run` prints the sample (outcome `sampled`) without starting DelphiLSP and needs no `.delphilsp.json`.

## Outcomes and the rate

| outcome | when | in the rate |
|---|---|---|
| match | a DelphiLSP location is in the expected file and on the declaration lines, or on the implementation line | yes |
| mismatch | DelphiLSP answered with locations and none matches | yes |
| empty | `null` or `[]`, also after one retry of that reference | no |
| error | an error response or no answer within `--timeout-ms` | no |
| skipped | the source line no longer starts with the name (file changed since the index), a non-ASCII character precedes the column, or the file cannot be read | no |

Rate = mismatch / (match + mismatch), 0 when that denominator is 0. `empty`, `error` and `skipped` stay out so they cannot fake accuracy. Text output: one summary line, then one tab-separated row per non-match reference (file:line:col, name, kind, drag-lint's answer, DelphiLSP's answer). `--json` writes one document with `counts`, `rate` and the same rows.

## The .delphilsp.json requirement

DelphiLSP is configured from the project's `.delphilsp.json`, which RAD Studio writes when the project is opened. `--project <x.dproj>` finds `<project base>.delphilsp.json` beside it; `--delphi-lsp-config <file>` names another. The verb starts one headless DelphiLSP (`--delphi-lsp <exe>` or the installed Studio, `--delphi-lsp-bits`), sends `initialize` with the file's `settings`, waits `--warmup-ms` (default 5000) and asks `textDocument/definition` per reference. The child lives in the drag-lint job object and is gone when the verb exits. `--trace <file>` appends every frame.

## Risks (read the numbers with these)

* DelphiLSP's definition convention (declaration vs implementation, forward class declarations) is unmeasured; a match accepts the declaration range and the implementation line. Forward declarations may show as mismatch until 1.53.1.
* DelphiLSP may answer `null` while the project still loads; the warm-up and the one retry bound it, and `empty` is kept out of the rate.
* LSP columns are UTF-16 code units; lines with a non-ASCII character before the reference are skipped, not guessed.
* A mismatch row prints both paths, so a path-form false positive (case, short path) is visible.