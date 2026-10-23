# apply1270 fixtures

Real `convert-apply --format json` captures (apply/1) that the model tests parse.

## Reproducible: `recapture.ps1`

`pwsh -NoProfile -File recapture.ps1 -Pin <third_party\engine-pinned\<version>-<stamp>>` rebuilds the tiny
"Fix" project from text in a temp dir, indexes it with a STAGED copy of the pin (own `drag-lint.json`, no real
DB touched) and rewrites (default: in place):

- `apply-cast-site-1270.json`
- `apply-uses-1270.json`
- `apply-pas-uses-1270.json`
- `apply-pas-uses-resolution-1282.json`

Two runs are byte-identical (volatile `uses_reindex.ms` is zeroed, the temp dir becomes `C:\\fix`). Each file's
`_note` names the engine version, pin and sha256 it was captured with. Captured on the 1.33.0 pin; the file names
keep the version of the engine that first produced the shape.

## NOT reproducible from text (kept as captured)

- `apply-stripdb-1270.json`, `apply-exit6-castlib-1280.json` -- need ORM3 CLIENT `dmToolStats.pas` and
  `convrules\BDE-to-FireDAC.rules`.
- `apply-batch-1315.json`, `apply-skip-1315.json`, `apply-desc-1315.json`, `apply-gap-1315.json` -- the
  FixUnit/DescUnit fixture of `tests\gui\drive-convert-tab.ps1` family.
- `apply-missing-fields-sample.json` -- hand-written malformed shapes.

## Shape drift vs the 2026-10-11 captures

`#convert` trailing units now emit `uses` add rows (1.28.1), `pas_uses` rows carry resolution / candidates and
`enum-value` kinds (1.28.2), `uses_unresolved[].line` is real (1.28.1), `convert-class-inferred` warnings exist
(1.28.3). `classes_built` dropped (uses 2 -> 1, pas-uses 4 -> 3); measured on the 1.33.0 pin, not explained, and
no test asserts it. The ambiguous-resolution shape no longer reproduces from this project; the test keeps the
verbatim 1.28.2 rows as `AMBIG_JSON`.
