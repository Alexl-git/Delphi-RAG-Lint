# lint-project test fixtures

`lint-project` rules (`god-class`, `unused-public-symbol`, `interface-reference-cycle`)
need the whole symbol index, so they are tested against a built index rather than the
per-file `tests/lint/` harness.

Reproduce the interface-reference-cycle check:

```
drag-lint index tests/lint-project --db %TEMP%\cyc.sqlite
drag-lint lint-project --db %TEMP%\cyc.sqlite --rule interface-reference-cycle
```

Expected: one finding -- `TAlpha` and `TBeta` (in `CycTest.pas`) hold each other's
interface (`IBeta` / `IAlpha`), an ARC cycle.
