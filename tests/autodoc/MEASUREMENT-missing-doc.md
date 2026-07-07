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

FLAG for the user/controller (per the spec's data-driven checkpoint): shipping
`missing-doc` ON by default means any drag-lint user who runs `lint-all` (or the
IDE's live-lint) against a pre-existing, partially-documented codebase -- which
describes most real Delphi codebases, including drag-lint's own -- will see a
four-figure wave of warnings on the very first run. That is not necessarily
wrong (the rule is opt-outable via `--disable missing-doc` or the config
profile, and it only fires on public surface, and it is `warning` not `error`
severity so it will not fail a default CI gate) -- but it is NOT a "reasonable,
barely-noticeable default" either. This is a judgment call for the user at
Task 13: keep `missing-doc` ON by default (accept that first run on an
undocumented codebase is noisy, matching the "encourage documentation" intent),
or flip its shipped default to OFF (opt-in) and let users turn it on once they
are ready to invest in DocInsight coverage. `doc-drift` at 550, being a
correctness-of-existing-docs signal rather than an absence signal, reads as a
safer ON-by-default candidate on its own merits regardless of the `missing-doc`
decision.
