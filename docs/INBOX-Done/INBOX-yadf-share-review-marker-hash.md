> # SHIPPED 2026-08-17 (session 25) -- WITHOUT touching the normaliser.
>
> The note's pessimism was right about the cost of changing `NormalizeLine` and
> wrong about the request being blocked by it. The owner asked for the hash
> function; that needs no normaliser change at all.
>
> * **`C:\Projects\YADF\vendor\drag-lint\DRagLint.Lint.ReviewMarker.pas`** -- a
>   byte-identical copy. Of the note's two options, the vendored copy was taken
>   over the shared search path: a cross-repo unit path would put drag-lint's
>   source tree inside YADF's build.
> * **`README-MIRROR.md`** beside it carries the "this is a mirror" statement, so
>   the unit itself stays byte-identical and the check can be a hash rather than
>   a fuzzy diff. It also states the design rule in the place a YADF developer
>   will actually read it: **VERIFY AND WARN, NEVER REWRITE**, and use
>   `HashWindow` + `NormalizedIsLoneKeyword`, not `HashLine`.
> * **`tests\autotest\run_reviewmarker_yadf_mirror.ps1`** compares the SHA256s.
>   Negative control run: appending ONE byte to the mirror turns it red, and it
>   was restored.
>
> **ZERO re-stamps, and `NormalizeLine` is untouched** -- so none of the 249
> existing markers move. Nothing in YADF was edited; the vendored folder is new
> and left untracked for the owner, whose working tree holds uncommitted edits.
>
> The suite SKIPS loudly when the YADF copy is absent (it is a separate repo that
> need not exist on every machine). A skip is a fail-open, so it is paired with a
> positive control on the side that is always present: if drag-lint's own copy
> goes missing or turns into a stub, that is a FAILURE, not a skip.

> # RE-COUNTED 2026-08-16 (session 22). The "change is nearly free" window has CLOSED.
>
> The note's own gate is *"Do not change the normaliser without counting first"*,
> and it predicted the cost would rise once the zero-findings push put markers
> into the consumer repos. It has. Counted today:
>
> | repo | files | `dl:ok` markers |
> |---|---|---|
> | Delphi-RAG-lint | 9 | **43** (was 27 at filing) |
> | YADF | 10 | **147** (was **0** at filing) |
> | DataCopy | 11 | **59** |
> | **total** | 30 | **249** |
>
> A normaliser change now costs **249 re-stamps across three repos**, two of them
> consumer repos currently holding uncommitted owner edits. Treat `NormalizeLine`
> as frozen unless there is a correctness reason, and budget the re-stamp.
>
> **YADF still has NO copy of the unit** -- the sharing has not happened, so the
> two cannot yet disagree. But note what the 147 means: those markers were
> written INTO YADF by drag-lint, not produced by YADF. YADF is already a
> consumer of the hash without owning the function.
>
> **The live hazard for whoever ships this.** The hash function changed after
> this note was filed: `TReviewMarkers.HashWindow` now hashes a bounded WINDOW
> for lone-keyword anchors, instead of `HashLine`'s single line. Any copy handed
> to YADF must ship `HashWindow` (and `NormalizedIsLoneKeyword`) or the two
> implementations will disagree on exactly the anchors that motivated the change
> -- and the disagreement will look like stale reviews, not like a version skew.
> Existing markers stamped before that change may also need re-stamping.
>
> Nothing was written to YADF or DataCopy here, per the standing "consumer files
> will wait" instruction. Recommendation unchanged and now better evidenced:
> **VERIFY and WARN, never rewrite.**

# Share the dl:ok hash function with YADF -- to VERIFY, not to refresh

Filed 2026-08-12, at the owner's request: *"could you provide the same hashing
function to YADF. Maybe we'll add a feature there to keep hash current? For that
we need an identical Hash function."*

## The conclusion that should shape the feature

**A correct normalisation-invariant hash gives YADF nothing to keep current.**

`TReviewMarkers.NormalizeLine` already drops every space and tab outside string
literals and lowercases all code. That is precisely the set of changes YADF
makes. So after a YADF pass the hash is bit-for-bit what it was, and a
"refresh the hash" step would find nothing to do.

The only edits that move the hash are edits that change what the code MEANS --
`i` renamed to `j`, `0` changed to `1`. Those are exactly the edits that must
invalidate a review. A YADF feature that refreshed the hash would therefore fire
only in the cases where refreshing is wrong: it would silently re-validate a
review of code no human re-examined, which is the one failure the whole design
exists to prevent.

**So: give YADF the function so it can VERIFY and WARN. Never rewrite.**

A useful YADF behaviour would be: on encountering a line carrying a `dl:ok`
marker whose hash no longer matches, emit a warning naming the file and line.
That turns YADF into a second detector for stale reviews, at zero risk.

## Mechanics

`src/lint/DRagLint.Lint.ReviewMarker.pas` is already pure -- it uses only
`System.SysUtils` and `System.Hash`, touches no store, config or file system, and
was built that way so a bare console program could test it. It drops into YADF
unmodified.

Two options, decide when picking this up:

* **Search path** -- YADF adds `C:\Projects\Delphi-RAG-lint\src\lint` to its unit
  path and uses the unit directly. Single source of truth, zero drift, but a
  cross-repo build dependency.
* **Vendored copy** -- YADF keeps its own copy with a header stating it is a
  mirror, plus a test in drag-lint's battery asserting the two files are
  byte-identical. Self-contained, drift caught by CI rather than prevented.

Prefer the search path if YADF's build can reach across repos; it needs checking.

## Do not change the normaliser without counting first

Any change to `NormalizeLine` invalidates every existing hash. As of filing there
are **27 markers in the drag-lint tree and 0 in YADF**, so a change is nearly
free right now -- and will not be after the zero-findings push puts markers in
YADF and DataCopy.

One change was proposed and declined 2026-08-12: folding whitespace and case
INSIDE string literals. Declined because no formatter rewrites literal content
(it would change the program), so it buys no reformat-immunity, while making
`'Customer not found'` and `'CUSTOMERNOTFOUND'` share a hash -- letting a genuine
edit to a message, SQL fragment or path slip under an existing review.
