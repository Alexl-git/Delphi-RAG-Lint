# RESUME -- 2026-08-16 (session 21)

Supersedes `RESUME-2026-08-16-session20-double-free-and-stale-anchors.md`, whose
NEXT list is fully discharged.

## Status

Branch is **`main`** -- `session18-q0-orphan-anchor` was merged (44 commits) and
`main` is **71 commits ahead of `origin/main`, deliberately unpushed**.

> **RELEASE GATE.** Owner, 2026-08-16: *"To github we'll publish new release only
> after all 11+1 are done."* Nothing goes to GitHub until the 11 verifiable notes
> in `docs\NEXT-SESSION-PLAN-2026-08-16.md` are finished. Do not offer to push
> before then.

**Battery 293/293, 0 fail.**

| | session start | now |
|---|---|---|
| INBOX open notes | 60 | **23** |
| `INBOX-Done\` | 55 | **86** |
| YADF | 14 | **5** |
| YADFOT | 12 | **5** |
| YADFSetup | 15 | **8** |
| DataCopy | 60 | **43** |

Zero errors in all four projects. Own source 1527, 0 errors, 99 files scanned.

## Shipped (14 fixes)

`bare-except` anchor -> `(kExcept)` · FormsMap comment scrub · `--rule` covers
both rule registries · `--only` names unmatched selectors · window hash for
lone-keyword anchors · marker restamp on 4 projects · `unused-public-symbol`
shared-unit honesty · `.dpr` bodies linted · lint-config discovered beside the
`.dproj` · `lint <file>` says what it skips · `lsp --stdio` accepted ·
`local-field-prefix` autofix (NEW capability) · schema version stamped last ·
build stages the rule corpus + K41 content hash · `referenced-never-set`
Result/Self writes · `deep-nesting` counts `exprIf` · object-leak self-linking ·
context bundle resolves a bare name · `used-before-assignment` managed arrays.

## Resume point

`docs\INBOX-INDEX.md` was rewritten and is accurate. It splits the 23 open notes
into **verifiable now (11)**, **not verifiable in a normal session (7)** and
**not defects (5)**.

**Best next item: `exception-cref-transitive-raise`.** It is measured, worked
through, and its note now records BOTH the correct fix and the tempting-but-wrong
one (do not suppress on "delegates and raises nothing" -- that describes most
routines and would gut the rule; resolve the callee instead). Fixing it takes
`docdrift-4` from 6 survivors to 3 and leaves a much sharper question: why do
the doc WRITER and the doc CHECKER disagree about three `TreeSitter.pas` blocks
when autodoc reports "nothing to document"?

## Two decisions left for the owner

1. **43 previously-untracked files were committed** by a `git add -A docs/`.
   CLAUDE.md says INBOX notes stay untracked; `INBOX-Done\` was already tracked,
   so the two halves were inconsistent -- but this was a side effect, not a
   decision. Untrack if unwanted.
2. **Consumer repos have UNCOMMITTED edits**, deliberately left for review:
   YADF (git) and DataCopy (hg) carry the 12-marker restamp, autodoc edits, and
   7 stale `deep-nesting` marker removals.

## Gotchas earned this session

* **`Select-Object -First N` on a native command corrupts `$LASTEXITCODE`** --
  it kills the process early. Capture output first, then read the code.
* **PowerShell `-eq`/`-ne` on strings is CASE-INSENSITIVE.** A fix that changed
  only letter case read as "file unchanged". Use `-ceq`.
* **A single silent fixture proves nothing about a threshold rule.** The
  `deep-nesting` defect needed six-plain / six-with-else / seven-plain side by
  side before the silence could be attributed.
* **Editing `rules\*.scm` did nothing** until copied beside the exe. Now staged
  by the build and content-checked by K41 -- but if either regresses, this is
  the first thing to suspect, because everything still passes.
* **A fail-open fallback hides its own absence.** Run such a change against the
  UNFIXED build or the fallback can swallow the whole fix silently.
* **Three notes had the WRONG stated mechanism.** Re-measure before coding: the
  fix was found by measurement in every case, never by reading the note.
