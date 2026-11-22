# Fast one-file lint on a large index (1.52.3)

`drag-lint lint <file.pas> --db <project.sqlite>` runs the project-aware part of
unused-public-symbol for that one unit: a public routine that only its own unit uses
("own-unit tier") is reported so it can move to the implementation section.

## What changed in 1.52.3

Before 1.52.3 that tier loaded EVERY reference of the index into memory to decide
"used only by its own unit". On a large project index that was most of the lint time.
Now it asks the index once per public name of the unit (the `idx_refs_name_nocase`
index), so the cost follows the size of the unit, not the size of the project.

Measured on the drag-lint self index (712k references), rule cache warm:

| unit | before | after |
|---|---|---|
| DRagLint.CLI.Export.pas | 20.5 s | 9.1 s |
| DRagLint.CLI.Format.pas | 15.8 s | 5.5 s |
| unused-public-symbol stage (Export) | 8.1 s | 0.0 s |

With a cold rule cache Export went from 48.5 s to 29.7 s. The findings are byte-identical
(Export 13, Format 1, TaintRules 20).

## Things to know

- Nothing to switch on: every one-file `lint` with `--db` gets it, so do the IDE's
  lint-on-save and the LSP diagnostics.
- `lint-all` was not affected (it already walks the whole project once).
- To see the stage times yourself: set `DRAGLINT_PROFILE=1` and run the lint.
- Guard: `tests\autotest\run_unused_public_own_unit_perf.ps1` fails when the stage takes
  more than 1 s on the big file again.
