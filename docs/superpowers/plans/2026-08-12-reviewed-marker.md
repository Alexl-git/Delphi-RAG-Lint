# Plan -- `dl:ok` reviewed-marker

**Design:** `docs/superpowers/specs/2026-08-12-reviewed-marker-design.md` (approved)
**Date:** 2026-08-12
**Goal:** every remaining lint message is accounted for -- fixed, ruled out by a
tightened rule, or recorded as reviewed-and-accepted by a human. Prove it by
driving YADF from 156 findings to 0.

## What the design did not know

The "ONE central filter between rule output and report output" the owner required
**already exists**:

* `ApplyLineSuppressions` -- `src/cli/DRagLint.CLI.pas:5512`. Today it honours
  `// drag-lint:ignore` (bare = suppress every rule on the line) and
  `// drag-lint:ignore <rule-id> ...`.
* Applied at `src/cli/DRagLint.CLI.pas:6319`, step 0 of `FinalizeAndOutput`,
  ahead of the config enable/disable filter (step 1) and the baseline filter
  (step 2b). Every finding-producing command routes through `FinalizeAndOutput`
  (5 call sites: DoLint, DoLintAll, and three others).

So this is an EXTENSION of one existing function, not a new pipeline stage. The
structural half of the owner requirement is already satisfied; what is missing is
the hash, the staleness report, and the insertion UX.

Corollary the design got wrong: the line text is NOT already shared with the
baseline. `ApplyLineSuppressions` has its own `LineCache` using
`TFile.ReadAllLines(F.FilePath)` (default encoding); `TBaseline.FingerprintsOf`
(`src/lint/DRagLint.Lint.Baseline.pas:150`) builds a SEPARATE cache reading the
same files with `TEncoding.UTF8`. Every finding file is read twice per run.

## Task 1 -- `DRagLint.Lint.ReviewMarker.pas` (pure, no I/O)

New unit. Pure functions only, so it is testable without a store, a file, or a
config. Everything else in this plan depends on it.

```pascal
type
  TReviewMarker = record
    RuleId : string;   // as written
    Hash   : string;   // 4 hex, lowercased; '' when absent
    Reason : string;   // free text after '--', may be ''
  end;

/// Code tokens of one source line, comments excluded, whitespace dropped,
/// identifiers lowercased. The string that gets hashed.
class function NormalizeLine(const ALineText: string): string;

/// 4 lowercase hex chars over NormalizeLine(ALineText).
class function HashLine(const ALineText: string): string;

/// Parses every 'dl:ok' marker on a line. [] when there is none.
class function Parse(const ALineText: string): TArray<TReviewMarker>;

/// The marker text to append for (rule, line) -- the ONE routine that formats a
/// marker, shared by the LSP code action and (later) the IDE plugin.
class function FormatMarker(const ARuleId, ALineText, AReason: string): string;

/// Appends ARuleId to an existing dl:ok comment on the line, or appends a new
/// comment. Returns the whole new line. Preserves 7-bit ASCII; adds no trailing
/// whitespace.
class function InsertInto(const ALineText, ARuleId, AReason: string): string;
```

**Tokenizer scope.** `NormalizeLine` needs only enough Pascal lexing to know
what is NOT code: `//` to end of line, `{...}` and `(*...*)` (single-line spans
only -- a marker on a line inside an open block comment is not a marker), and
string literals `'...'` with `''` escapes, whose contents are preserved verbatim
and NOT lowercased (case is significant inside a literal; lowercasing it would
make two genuinely different lines hash the same).

REUSE CHECKED, REJECTED: `TClosureResolver.StripCommentsAndStrings`
(`src/index/DRagLint.Index.Closure.pas:614`) does the comment half correctly but
blanks string-literal CONTENT, which would collide test rows 2 and 4. It is also
a private method of a class in the index layer. Hand-roll in the new pure unit,
modelled on it; do not take a `src/lint` -> `src/index` dependency for it.

**Tests (write first, one per row):**

| # | Input | Assert |
|---|---|---|
| 1 | `if a then` vs `IF   A  THEN` | same hash |
| 2 | `x := 1;` vs `x := 2;` | different hash |
| 3 | `except` vs `except // dl:ok bare-except@7f3a` | same hash (comments excluded) |
| 4 | `S := 'Abc';` vs `S := 'abc';` | DIFFERENT hash (literals keep case) |
| 5 | `// dl:ok bare-except@7f3a -- rethrown` | Parse -> 1 marker, all 3 fields |
| 6 | `// dl:ok bare-except@7f3a, deep-nesting@7f3a -- x` | Parse -> 2 markers |
| 7 | `// dl:ok bare-except` (no hash) | Parse -> 1 marker, Hash='' |
| 8 | line with no marker | Parse -> [] |
| 9 | `S := '// dl:ok fake@0000';` | Parse -> [] (marker inside a literal is not a marker) |
| 10 | InsertInto on a line already carrying dl:ok | merges, one comment, no dup |
| 11 | InsertInto output | no trailing whitespace, no non-ASCII |

Row 9 is the one that bites: the naive `Pos('dl:ok', ...)` that
`ApplyLineSuppressions` uses today would match inside a string literal.

## Task 2 -- extend `ApplyLineSuppressions`

Same function, same call site. Rename to `ApplyLineMarkers` since it now both
drops and ADDS findings; keep `drag-lint:ignore` working unchanged.

Per finding on line L with rule R, using the design's table:

| marker on L | hash | outcome |
|---|---|---|
| lists R | matches | suppressed |
| lists R | mismatches | REPORTED + a `review-marker-stale` finding on the marker |
| lists R | absent (`@` omitted) | suppressed + `review-marker-stale` hint (unverifiable) |
| does not list R | -- | reported normally |
| lists R, R produced nothing | -- | `review-marker-unused` finding |

`review-marker-unused` needs the markers on lines that produced NO finding, so
the pass must walk the marker-bearing lines of each file that had at least one
finding -- not only the finding lines. Bound the cost: only files already in the
line cache (i.e. already read for this run) are scanned, so no new I/O.

Both new rule ids get catalogue entries (`src/lint/DRagLint.Lint.RuleCatalog.pas`)
with severity `hint`, default ON. They pass through step 1, so
`--disable review-marker-unused` works for free.

**Collapse the double file read** while here: one shared line cache for
`ApplyLineMarkers` and `TBaseline.FingerprintsOf`.

## Task 3 -- LSP code action `drag-lint: mark reviewed` -- DEFERRED

**Owner ruling 2026-08-12: DEFERRED out of this plan entirely.** Tasks 1, 2, 4
and 5 ship a working `dl:ok` on the CLI without it; marking by hand or with a
small script is the stopgap. File the code-action road as its own spec. The rest
of this section is the scoping already done, kept for that follow-on.

**Bigger than the design assumed: there is NO code-action support at all.**
`grep -r 'codeAction' src` returns zero hits, so this is not "add an action to
the existing handler" -- it is the whole `textDocument/codeAction` road:

1. advertise `codeActionProvider` in the initialize result
   (`src/lsp/DRagLint.LSP.Server.pas`);
2. handle the `textDocument/codeAction` request, mapping the request range to
   the diagnostics already computed for that document;
3. return one `quickfix` action per diagnostic whose edit is
   `TReviewMarker.InsertInto` applied to the diagnostic's line;
4. client side in the VS Code extension.

It applies `TReviewMarker.InsertInto` to the diagnostic's line, must preserve
CRLF and 7-bit ASCII, and uses the Task 1 formatter -- the marker text is never
formatted in two places.

**Sequencing note:** Tasks 1, 2, 4 and 5 deliver the whole value on the CLI
without any of this. Task 3 is the ergonomics layer and should be built LAST, or
split into its own follow-on -- it is the only task that can grow without bound
(client packaging, LSP lifecycle, the engine-rebuild-kills-the-client dance).
Marking findings by hand or with a small script is a perfectly good stopgap for
proving YADF at 0.

## Task 4 -- YADF round-trip regression (the load-bearing test)

YADF is the tool most likely to touch marked code, and it has real golden
coverage: `C:\Projects\YADF\Test\run_tests.ps1`, 22 scripts over 84 golden files,
53 cases, 32 snippets.

1. Run YADF over a file containing markers; assert every marker survives verbatim.
2. Assert the hash still MATCHES after YADF reformats the line. This is the test
   that pins the "whitespace dropped, identifiers lowercased" normalisation. If
   it fails, the scheme is broken for the one tool most likely to break it.

## Task 5 -- apply to YADF, prove 0

Current: **156** findings (`bare-except` 4, `out-param-not-set` 7,
`object-leak` 3, complexity family + duplicate-code 91, `concat-in-loop` 15,
`compiler-magic-comments` 16, rest singles). Order:

1. Rule hardening first (INBOX-yadf-triage-2026-08-12) -- do NOT mark a false
   positive as reviewed; that hides a rule bug behind a human signature.
2. `commented-out-code` -> disable (owner ruling, config only).
3. `bare-except` -> the per-project exception-class unit
   (`docs/INBOX-exception-class-unit-...`).
4. Whatever genuinely remains -> `dl:ok` with a real reason.

## Out of scope

Block/file-level markers; project-wide rule suppression (that is the config's
disable list). Hardening `--baseline` to fingerprint on
`enclosing qualified name + normalized token sequence` is a separate, related
win -- the Task 1 normalizer is exactly the primitive it would need.
