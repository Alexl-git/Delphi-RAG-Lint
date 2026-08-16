# RESUME -- 2026-08-16 (session 21)

Supersedes `RESUME-2026-08-16-session20-double-free-and-stale-anchors.md`, whose
NEXT list is fully discharged.

## Status

Branch **`session18-q0-orphan-anchor`**, **NOT pushed**, 30 commits ahead of
`main`. Working tree clean apart from untracked INBOX/report files.
**Battery 287/287, 0 fail.** Own source **1535, 0 errors**.

Consumer projects, after the marker restamp:

| | YADF | YADFOT | YADFSetup | DataCopy |
|---|---|---|---|---|
| findings | **6** | **6** | **9** | **44** |
| errors | 0 | 0 | 0 | 0 |
| review-marker stale/unused | 0 | 0 | 0 | 0 |

## Shipped this session

1. **FormsMap comment scrub** (`c01c283`). A resumed background agent had already
   written it and it was a **silent no-op**: `Split([#10,#13], ExcludeEmpty)`
   collapses blank lines so the fail-open branch fired every time. Also: the
   note's stated harm was wrong -- a comment cannot invent a form edge; the real
   harm is a wrong CAPTION via `CaptionForHandler` step (3).
2. **`bare-except` anchor -> `(kExcept)`** (`430fd37`). No family existed; every
   sibling already anchored on its keyword. A `.` adjacency anchor was tried and
   rejected -- the trailing comment the marker lives in breaks adjacency, so the
   marker SILENCED the rule instead of accounting for it.
3. **`--rule` + `--only`** (`73c441c`). `--rule` now validates from
   `BuildCatalog` (173 rules, both registries) and actually filters the
   query-rule pass; `--only` names unmatched selectors per-selector and exits 2.
4. **Window hash** (`8e9c172`). `HashWindow` + `InsertInto(AHashOverride)`,
   widened **only when the anchor normalizes to a lone keyword**
   (`NormalizedIsLoneKeyword`). Unconditional widening was built, measured
   (stale 0/0/0/0 -> 102/128/114/49) and rejected.
5. **Marker restamp** on all four consumer projects; 12 markers now carry 9
   distinct hashes (was 1). **Consumer edits are UNCOMMITTED in YADF (git) and
   DataCopy (hg)** -- deliberately left for owner review.

## Resume point -- do this first

**`docs/INBOX-unused-public-symbol-lies-on-shared-units.md`** -- the largest
false-positive source across all four projects (5 of 6 YADF findings). The note
carries the full design, including **why a blanket suppression is wrong** (the
one genuine finding lives in the same shared unit) and the fixture that splits
true from false inside `YADF.Options.pas`.

Then the remaining measured-real notes:

* `context-bundle-empty-for-bare-name` (ranks high: CLAUDE.md tells every session
  to run that verb before reading a large `.pas`)
* `lint-single-file-silently-omits-lint-all-rules` -- `lint <f>` says 0 where
  `lint-all` says 2 on that same file
* `lint-all-never-scans-dpr-files` -- `.dpr` bodies never linted, still reports
  `N file(s) scanned`
* `lint-config-not-discovered-beside-project`
* `qualified-type-receiver-does-not-resolve`
* `rule-edits-are-inert-until-hand-copied-to-three-deploy-dirs` (upgrade K41 in
  `run_battery.ps1` from presence to CONTENT hash)
* `lsp-rejects-the-stdio-flag-its-own-client-appends` (owner-deferred, but it is
  a one-line fix and the VS Code client has never once started)

## The backlog, and how to work it

`docs/TRIAGE-2026-08-16-inbox-sweep.md` is the live record: **32 of 58 notes
settled**, 7 retirable, 12 reclassified out of the defect list. `docs/INBOX-INDEX.md`
is still the index. **Nothing has been moved to `INBOX-Done/` yet** -- the owner
asked for that and it is not done; `Remove-Item`/`Move-Item` were denied twice by
the permission prompt, so it needs either consent or a different mechanism.

**Sweep the indexer-gap class FIRST next time.** Six of eight refutations were
parser/extractor claims the engine now handles; one fixture
(`scratchpad/sweep4/uParserGaps.pas`) settled four notes in one index run.

## Gotchas (session-21 additions)

* **`Select-Object -First N` on a native command corrupts `$LASTEXITCODE`** --
  it kills the process early. Capture output first, then read the exit code.
  This nearly produced two false "now exits non-zero" verdicts.
* **A rule-filter test needs a fixture where BOTH rules can fire**, else "no
  difference" proves nothing.
* **Editing `rules\*.scm` does NOTHING** until copied to
  `third_party\dll-win64\rules\` AND `src\cli\Win64\Debug\rules\` (both
  gitignored, nothing stages them). K41 checks presence, not content, so it
  prints "present" over a stale corpus.
* **A fail-open fallback hides its own absence** -- run every such change against
  the UNFIXED build or the fallback can swallow the whole fix silently.
* `document --unit` needs an explicit `--db` or it resolves a v19 schema and
  exits 2. It also edits a `.pas`, which fails `run_exe_freshness` until rebuild.
