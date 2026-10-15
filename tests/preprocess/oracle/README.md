# JS preprocessor oracle (test-only)

The `ORACLE-DIFF` checks in `tests\preprocess\run_*.ps1` compare drag-lint's
Pascal preprocessor with the grammar project's own `preprocess()`, byte for
byte. That code belongs here:

```
tests\preprocess\oracle\preprocessor\preprocess.js   (+ cli.js and the modules it requires)
```

It comes from the `preprocessor\` folder of the tree-sitter-delphi13 grammar
repository. When you bring it, record the source repository, the commit and its
license in `ORIGIN.txt` beside this file, and pick the commit that matches the
grammar that built `third_party\dll-win64\tree-sitter-delphi13.dll`.

Until it is here, or when `node` is not on PATH, every `ORACLE-DIFF` check prints
`[SKIP] ... -- <reason>` and its runner exits **77** (SKIP), which
`tests\run_battery.ps1` reports separately from PASS. The other checks of those
runners still run and can still fail. See `tests\preprocess\lib\OracleRequire.ps1`.

Node is a TEST-ONLY dependency: the shipped drag-lint exe never calls it.
