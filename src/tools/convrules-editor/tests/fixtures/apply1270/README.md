# apply1270 fixtures

Real `convert-apply --format json` captures (apply/1) that the model tests parse.

## Reproducible: `make-capture.ps1`

`pwsh -NoProfile -File make-capture.ps1 -Pin <third_party\engine-pinned\<version>-<stamp>>` rebuilds the tiny
"Fix" project from text in a temp dir, indexes it with a STAGED copy of the pin (own `drag-lint.json`, no real
DB touched) and rewrites (default: in place):

- `apply-cast-site-1270.json`
- `apply-uses-1270.json`
- `apply-pas-uses-1270.json`
- `apply-pas-uses-resolution-1282.json`

Two runs are byte-identical (volatile `uses_reindex.ms` is zeroed, the temp dir becomes `C:\\fix`). Each file's
`_note` names the engine version, pin and sha256 it was captured with. Run it after every engine re-parse/re-pin (N3). -Root keeps the project + staged engine + scratch DBs in a folder you name (re-runnable in place; default a new temp folder). Captured on the 1.36.0 pin (1.33.0 before); the file names
keep the version of the engine that first produced the shape.

## NOT reproducible from text (kept as captured)

- `apply-stripdb-1270.json`, `apply-exit6-castlib-1280.json` -- need ORM3 CLIENT `dmToolStats.pas` and
  `convrules\BDE-to-FireDAC.rules`.
- `apply-batch-1315.json`, `apply-skip-1315.json`, `apply-desc-1315.json`, `apply-gap-1315.json` -- the
  FixUnit/DescUnit fixture of `tests\gui\drive-convert-tab.ps1` family.
- `apply-missing-fields-sample.json` -- hand-written malformed shapes.
- `apply-encoding-refused-contract.json`, `batch-encoding-refused-contract.json` -- hand-written to the ENGINE
  contract of `docs\superpowers\plans\2026-10-25-converter-text-encoding.md` (E1', `encoding_refused`); recapture
  when ENGINE ships `convert_encoding_guard`.

## Shape drift vs the 2026-10-11 captures

`#convert` trailing units now emit `uses` add rows (1.28.1), `pas_uses` rows carry resolution / candidates and
`enum-value` kinds (1.28.2), `uses_unresolved[].line` is real (1.28.1), `convert-class-inferred` warnings exist
(1.28.3). `classes_built` dropped (uses 2 -> 1, pas-uses 4 -> 3); measured on the 1.33.0 pin, not explained, and
no test asserts it. The ambiguous-resolution shape no longer reproduces from this project; the test keeps the
verbatim 1.28.2 rows as `AMBIG_JSON`.

## 1.33.0 -> 1.36.0 re-capture diff (2026-10-27)

Structural compare (JSON, _note ignored): the only differences are additive engine fields -- top-level `exit_code` (0) and `pas_uses[].rules_file` (`Fix.rules`) plus an empty `migrate_to`. No value changed.
