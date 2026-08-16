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
