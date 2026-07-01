# tests/lint-store -- store-backed rule fixtures

The file harness (`tests/lint/run_lint_tests.ps1`) runs `lint <file>` with **no
`--db`**, so store / uses-graph / flow rules never fire. This harness closes that
gap: each case directory is indexed into a throwaway SQLite store, then the
store-bearing check path (`check-ast --db` per file, or `lint-all --db` for the
whole project) is run against it.

## Layout

```
tests/lint-store/<case>/
  *.pas          one or more units (the class/enum/uses spread across units)
  expected.txt   directives (see below)
  config.json    OPTIONAL -- passed via --config (OFF-by-default / thresholded rules)
  case.json      OPTIONAL -- { "mode": "check-ast" | "lint-all", "subject": "<file.pas>" }
```

`mode` defaults to `check-ast` (run over every `.pas` in the case, or just
`subject` if set). `lint-all` runs the whole-project store path once.

## expected.txt directives

```
<rule> <file>:<line>   finding MUST be present at file:line
<rule> <line>          shorthand when the case has a single subject .pas
!<rule> <file>         rule must NOT fire in <file>
!<rule>                rule must NOT fire anywhere in the case
none                   the case must produce ZERO findings of ANY rule
```

Blank lines and `#`-comments are ignored. The harness tolerates extra findings
not named in `expected.txt` (assert only what the case is about).

## Run

```
pwsh -File tests\lint-store\run_store_tests.ps1
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter abstract-*
```

Keep fixture cases **tiny** -- `lint-all` over a large index takes minutes; a
2-3 file case indexes and checks in well under a second.
