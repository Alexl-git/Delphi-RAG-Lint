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

## Architecture layering

```
drag-lint index tests/lint-project/layers --db %TEMP%\layers.sqlite
drag-lint lint-project --db %TEMP%\layers.sqlite --layers tests/lint-project/layers/drag-lint-layers.json --rule layering-violation
```

Expected: one finding -- `App.UI.Main` (UI layer) uses `App.Data.DAO` (Data layer),
which is forbidden (UI may only use Business). UI->Business and Business->Data are allowed.
