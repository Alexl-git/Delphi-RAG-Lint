# MEASUREMENT: missing-doc / doc-drift first-run wave on drag-lint's own tree

AutoDocument Finish milestone, Task 11 data-driven checkpoint. This measures how
noisy the two ON-by-default documentation lint rules (`missing-doc`, `doc-drift`)
actually are when run over drag-lint's own `src/` tree, so the noise level is a
known, documented number before the milestone ships (Task 13).

## Method

- Indexed drag-lint's own `src/` tree (128 files, 11209 symbols, 0 parse errors)
  to a throwaway scratch DB (`C:\TEMP\claude\scratch-index\measure.sqlite` --
  NOT one of the user's real indexes).
- Ran `drag-lint lint-all --db <scratchDb> --json` twice against the same DB:
  once with the default rule set (the two doc rules ON, as they ship), and once
  with `--disable missing-doc,doc-drift`, then diffed the two `--json` arrays to
  isolate exactly what the two rules contribute (no other rule's count can drift
  between the two runs since the DB and file set are identical).
- Staged exe: `third_party\dll-win64\drag-lint.exe` (freshly rebuilt this task).
- Both runs executed from a neutral CWD (`C:\TEMP`), pwsh 7.

## Results

| metric                                   | count |
|-------------------------------------------|------:|
| `missing-doc` findings                     |  1302 |
| `doc-drift` findings                       |   550 |
| doc-rule contribution (1302 + 550)         |  1852 |
| total findings WITH the two doc rules ON   |  7304 |
| total findings WITHOUT the two doc rules   |  5452 |
| difference (matches doc-rule contribution) |  1852 |

Breakdown:

- `missing-doc`: 1302 findings, all severity `warning`, spread across 104 of the
  128 indexed files (public-surface-only -- private/local helpers are excluded
  by design, per the rule's noise mitigation).
- `doc-drift`: 550 findings, all severity `warning`, spread across 45 of the
  128 indexed files.
- Both rules report at `warning` severity, so a CI gate using the default
  `--fail-on error` would NOT break on this wave; a stricter `--fail-on warning`
  gate would.

## Honest read

1302 `missing-doc` findings is a LARGE first-run wave, not a small one. It is
not "a few hundred" -- it is over a thousand, spread across the large majority
of files (104/128) in a codebase that has had significant, but incomplete,
DocInsight (CDD) investment (the v0.90.0-alpha AutoDocument push documented many
public decls, but the codebase predates that push and most of ~11k indexed
symbols were written before the DocInsight convention existed). The rule is
public-surface-only, which is the correct and working noise mitigation --
without it the count would be far higher across all ~11209 symbols -- but on a
codebase this large and this partially documented, "public-surface-only" still
leaves four figures of findings.

`doc-drift` at 550 is smaller but still substantial, and is the more interesting
number: every one of those 550 is a case where a decl already HAS a doc comment
that has drifted from the code (stale param, missing raises, etc.), not merely
undocumented. That is a real, actionable signal, not noise from absence.

## Decision (Task 11b / Task 13 -- FINAL)

Driven by this measurement, `missing-doc` ships **OFF by default (opt-in)** and
`doc-drift` ships **ON by default**. The reasoning:

Shipping `missing-doc` ON would mean any drag-lint user who runs `lint-all` (or
the IDE's live-lint) against a pre-existing, partially-documented codebase --
which describes most real Delphi codebases, including drag-lint's own -- would
see a four-figure wave of warnings on the very first run. It only fires on public
surface and at `warning` severity (so a default `--fail-on error` CI gate would
not break), but a 1302-finding first run is NOT a "reasonable, barely-noticeable
default." So `missing-doc` ships OFF; users opt in via config
`"enabled": ["missing-doc"]` (or `--rule missing-doc`) once they are ready to
invest in DocInsight coverage. The rule catalog reports `default_enabled=false`,
and the CLI's store-backed `lint-all` / `lint-project` paths add it to their
default-disabled set so it is genuinely OFF at runtime (regression-guarded in
`tests\autodoc\run_missing_doc.ps1`: a bare `lint-all` yields zero missing-doc
findings, while the config-enabled run still fires).

`doc-drift` at 550, being a correctness-of-existing-docs signal (a decl that
already HAS a doc comment which drifted from the code) rather than an absence
signal, is a safer ON-by-default candidate on its own merits and ships ON.
