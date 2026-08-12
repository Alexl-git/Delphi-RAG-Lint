# RESUME -- 2026-08-12 (d). The `dl:ok` reviewed-marker shipped; LSP code actions are next

Supersedes `RESUME-2026-08-12c-ownership-perf-and-review-markers.md` as the entry
point. That doc's "NEXT BUILD" item is DONE.

Branch `feat/dl-ok-reviewed-marker`, merged to `main`.

## What shipped

**`DRagLint.Lint.ReviewMarker.pas`** -- a pure unit (no file/store/config access):
`NormalizeLine`, `HashLine`, `Parse`, `FormatMarker`, `InsertInto`. The hash is 4
hex over the line's CODE TOKENS: comments excluded, whitespace dropped,
identifiers lowercased, **string-literal content preserved verbatim and
case-sensitive** (lowercasing it would let `'Abc'` and `'abc'` share a hash).
Compiler directives count as CODE, not comment -- an IFDEF of A and an IFDEF of B
are different programs.

**`ApplyLineSuppressions` -> `ApplyLineMarkers`** (`src/cli/DRagLint.CLI.pas`).
Same function, same call site, still step 0 of `FinalizeAndOutput`.

**Two catalogue rules**, category `review-markers`, both `hint`, both ON:
`review-marker-stale` and `review-marker-unused`.

## THE THING THE SPEC GOT WRONG, AND IT MADE THE BUILD SMALLER

**The "one central filter" the owner required already existed.** `ApplyLineSuppressions`
at `DRagLint.CLI.pas:5512`, applied at step 0 of `FinalizeAndOutput`, which all
five finding-producing commands route through. This was an EXTENSION, not a new
pipeline stage, and the "no future rule can forget it" requirement was already
satisfied structurally.

Its position AHEAD of the config filter is load-bearing and worth not "tidying":
findings from DISABLED rules are still present at step 0, so a `dl:ok` naming a
disabled rule still counts as used and is not falsely reported unused.

Also wrong in the spec: "the line text is already read and cached for the baseline
fingerprint, so the per-finding cost is a hash, not an I/O". There are TWO caches
(`ApplyLineMarkers`' own, and `TBaseline.FingerprintsOf`'s), reading every finding
file twice with DIFFERENT encodings (default vs UTF8). Not collapsed yet -- see
backlog.

## TWO FALSE-POSITIVE CLASSES, BOTH FOUND BY DOGFOODING

Neither was findable by reading the code. Both would have shipped silently.

1. **Comment-sensitive rules.** Some rules treat a comment as content, so writing
   the marker is itself enough to stop the rule firing. **Measured, not assumed**
   (probe of the empty-* family): `empty-except` and `empty-case-branch` both go
   1 -> 0 findings when ANY trailing comment is added; `empty-on-handler` does not.
   Left unhandled this is a loop with no exit -- mark it, the comment silences the
   rule, `review-marker-unused` says remove it, removing it brings the finding
   back. Handled by `COMMENT_SENSITIVE` in `ApplyLineMarkers`.
   **If you add a rule that inspects comments, add its id there.**
2. **The scanner read its own documentation as a marker.** The doc-comment on
   `ApplyLineMarkers` spells out the grammar `// dl:ok <rule-id>@<hash>`, and the
   unused-scan reported a marker for a rule literally named `<rule-id>` in
   drag-lint's own source. Fixed by validating rule ids against
   `TRuleCatalog.BuiltinRegistry`. Bonus: a typo'd id (`bare-excpet`) now fails
   safe -- it suppresses nothing AND is not claimed to be a marker, so the
   original finding stays visible.

## Tests -- 57 new assertions, three suites

* `tests/reviewmarker/ReviewMarkerTests.dpr` + `run_review_marker_tests.ps1` --
  **37/37**. Pure unit, bare `dcc64`, modelled on `tests/baseline`.
* `tests/reviewmarker/run_review_marker_e2e.ps1` -- **13/13**. All five marker
  states through the real CLI.
* `tests/reviewmarker/run_review_marker_yadf.ps1` -- **7/7**. Marker survives the
  REAL YADF binary verbatim, hash still matches, file still 7-bit ASCII. SKIPs
  (exit 2) when YADF is not built -- this repo does not own YADF's build.

`tests/autodoc/run_docrules_catalog.ps1` asserts a hardcoded built-in rule count.
It went red on the first battery run (116 -> 118) -- **that is the tripwire
working**, so it was bumped deliberately and annotated, not loosened.

## Numbers

| Project | Findings | Note |
|---|---|---|
| YADF | **149** (was 156) | `out-param-not-set` 7 -> 0 by fixing the rule |
| DataCopy | **493** | doc-drift 192, used-unit-not-resolvable 99, commented-out-code 55 |
| drag-lint itself | **1,870** | 95 files, 250s |

`out-param-not-set` now exempts the Try-pattern: a FUNCTION whose name starts with
`Try`. `TryXxx(...; out Y): Boolean` defines Y only when it returns True, and
Delphi zero-initialises `out` params on entry anyway. Name-based on purpose -- the
precise test needs the return VALUE tracked per path, and the solver answers
assignment-reachability. A Try-named PROCEDURE gets no exemption (no Result, so no
contract). All 7 YADF findings went, no collateral.

## RULING: the complexity family is NOT to be bulk-marked

90 of YADF's 149 are complexity + duplicate-code. Sampled 12 as the plan required:
every one is MARGINALLY over a generic threshold (cognitive 69 and 95 vs 65,
cyclomatic 34 and 35 vs 30, nesting 6 vs 5, boolean 6 vs 4) in a tokeniser and a
layout engine, where long `case` dispatch and repeated token-shape blocks are
inherent. 90 `dl:ok` signatures would be bulk suppression wearing a review's
clothes, and a per-line marker is the worst place to put it in a file YADF itself
rewrites. **That category wants per-project threshold calibration or real
refactoring; neither is honestly represented by a fabricated 0.**

Useful fact for whoever does take it on: YADF has REAL golden coverage --
`C:\Projects\YADF\Test\run_tests.ps1`, 22 scripts over 84 golden files, 53 cases,
32 snippets, and it fails fast if the exe is stale relative to `YADF*.pas`. So a
refactor there is verifiable against golden OUTPUT, not merely "it compiles".

## NEXT: the LSP code-action road (deliberately cut from this build)

**There is no `codeAction` support anywhere in `src`** -- `grep -r codeAction src`
returns zero hits. The owner's "mark reviewed" right-click is therefore not a small
addition; it is:

1. advertise `codeActionProvider` in the initialize result (`src/lsp/DRagLint.LSP.Server.pas`);
2. handle `textDocument/codeAction`, mapping the request range to the diagnostics
   already computed for that document;
3. one `quickfix` per diagnostic, whose edit is `TReviewMarkers.InsertInto` on the
   diagnostic's line -- **come through that routine, never format the marker text
   a second time**;
4. VS Code client wiring.

Rebuilding the engine kills the VS Code LSP client (`dragLint.serverPath` is the
exe the build overwrites) -- recover with *Developer: Reload Window*.

## Backlog created this session

* `docs/INBOX-lint-config-not-discovered-beside-project.md` -- `lint-all --project`
  discovers a lint config only in CWD, never beside the project file. With
  `--config` it works; without it a per-project rule ruling is SILENTLY a no-op.
  The LSP already walks up and gets this right, so CLI and editor disagree about
  which rules are enabled for the same project. **This blocked applying the
  owner's `commented-out-code` ruling properly.**
* Collapse the double file read (`ApplyLineMarkers` + `TBaseline.FingerprintsOf`).
* `object-leak` 3/3 false on YADF, still unfixed -- two blind spots, both in
  `docs/INBOX-yadf-triage-2026-08-12-...`: a correct `finally X.Free` nested inside
  a `try..except` is not matched, and `TGroup` transfers ownership INSIDE ITS
  CONSTRUCTOR (`AParent.Children.Add(Self)`), which the rule only looks for at the
  call site. Deeper AST work; deliberately not half-fixed.
* Dataflow findings lower-case the identifier in the message (`"arec"` for `ARec`)
  -- cosmetic, makes findings harder to grep.
* `--baseline` could reuse `TReviewMarkers.NormalizeLine` to become reformat-immune
  the same way; it is exactly the primitive that fingerprint wants.

## Gotchas that still bite (carried forward, all re-confirmed today)

* **The episodic-memory plugin RESUMES old sessions and edits source.** Kill the
  `sync-cli.js` node PARENTS, not the children. Three were live at session start
  today, each with a `claude.exe --resume` child.
* **Run the battery with `pwsh`, never `powershell.exe`.**
* Redirected logs are BLOCK-BUFFERED; check for the process, not the log tail.
* A long library index locks the deployed exe -- run it from a COPIED exe.
* `--only <name>` matching nothing indexes nothing and **exits 0**.
* `git add -A docs` sweeps ~35 deliberately untracked INBOX notes. Stage explicitly.
* The Write tool emits LF; `.pas`/`.dpr`/`.md` here are strict 7-bit ASCII + CRLF.
  Byte-check after every write.
* **Delphi comments do not nest.** A `{ ... }` comment containing a brace-form
  compiler directive closes early and leaves a live conditional -- cost one build
  this session (`E2280 Unterminated conditional directive`).
