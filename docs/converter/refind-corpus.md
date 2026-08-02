# The reFind corpus (Task 9)

Two of Embarcadero's own **reFind** migration instruction files, imported verbatim as
first-class rule books of ours. They are a **product deliverable**, not a test fixture:
a user can open either of them from the editor's `Open...` dialog. They are also the
corpus a conformance test runs against, because they are real input written by someone
who was not us.

## Where the files came from

| Our file | Source (RAD Studio 37.0 samples) | Bytes |
|---|---|---|
| `convrules\FireDAC_Migrate_BDE.rules` | `...\Samples\Object Pascal\Database\FireDAC\Tool\reFind\BDE2FDMigration\FireDAC_Migrate_BDE.txt` | 4 025 |
| `convrules\FireDAC_Rename_Units.rules` | `...\Samples\Object Pascal\Database\FireDAC\Tool\reFind\AD2FDMigration\FireDAC_Rename_Units.txt` | 9 015 |

Sample root: `C:\Users\Public\Documents\Embarcadero\Studio\37.0\Samples\...`.

**Content is byte-identical to the source** (verified by MD5:
`d608b371...` and `c749858d...`). Only the extension changed, `.txt` -> `.rules`, so the
editor's file dialog (`Conversion rules (*.rules;*.txt)`) offers them by default. Both
files are pure 7-bit ASCII with CRLF endings and a terminating CRLF, so they already
match our source convention; no transcoding was needed.

## The new top-level `convrules\` directory

Rule books were promoted out of `docs\examples\convrules\` into a top-level
`convrules\` directory: they are shipped data, not documentation samples.
`sample.rules` moved there with `git mv` (history preserved).
`docs\examples\convrules\casts.castlib` was **left where it is** -- it is a cast
library, not a rule book, and both the editor and the tests resolve it by that path.

`*.rules text eol=crlf` was added to `.gitattributes` so a clone on any machine
reproduces the exact bytes the round-trip assertion checks.

## What loaded, and how cleanly

Every line classified. `TRuleBook.LoadFromString` produced **zero `rnkUnknown` nodes**
across both files, and `SaveToString` reproduced both byte-for-byte on the **first**
run -- no parser change was needed.

That headline is real but easy to over-read; "What each assertion actually proves"
below is the part that matters.

| File | Lines | Blank | Recognised | Node kinds |
|---|---|---|---|---|
| `FireDAC_Migrate_BDE.rules` | 77 | 8 | 69 | `#migrate` x60, `#unuse` x6, `#remove` x2, `#remove DFM:` x1 |
| `FireDAC_Rename_Units.rules` | 211 | 14 | 197 | bare `old -> new` x197, parsed as `rnkPcre` |

## What each assertion actually proves

**Read this before citing the green ticks as evidence.** The three per-file assertions
are not equally meaningful, and two of them are much weaker than they look.

### `.roundtrip` -- line splitting and line endings ONLY

`TRuleNode.Emit` (`ConvRules.Model.pas:313-317`) opens with
`if not Dirty then Exit(Raw)`, and `LoadFromString` never sets `Dirty`. So a
load-then-save round-trip echoes every node's verbatim `Raw` text and exercises
**zero** field decomposition or reconstruction -- for `#migrate`, `#unuse` and
`#remove` exactly as much as for `rnkPcre`.

What it does prove is still worth having, but it is narrow: that `TStringList`
line-splitting, CRLF handling and the trailing-newline convention are faithful. It
carries **no independent weight** as evidence that the grammar understands reFind.
`TestReFindCorpusReconstructs` is the test that does (below).

### `.recognised.nontrivial` -- a floor against a degenerate parser, not comprehension

The `>= 20` threshold exists only to stop a parser "passing" by classifying the whole
file as blank. For `FireDAC_Rename_Units.rules` it is **met by the file's format
alone**: every one of its 197 non-blank lines contains ` -> `, so the count is a
property of the input shape, not of anything the parser worked out.

### `.no.unknown` -- the assertion with real content, and it differs per file

* **Strong for `FireDAC_Migrate_BDE.rules`.** Every line starts with `#`, and
  `ParseLine` dispatches on the actual directive keyword through an explicit chain
  (`ConvRules.Model.pas:588-641`). An unrecognised directive falls through to
  `rnkUnknown` (`:650-651`). Zero unknown here means the keywords really are
  recognised.
* **Weak for `FireDAC_Rename_Units.rules`.** Non-`#` lines are classified by
  `if Pos(ARROW_MIGRATE, T) > 0 then N.Kind := rnkPcre else N.Kind := rnkUnknown`
  (`ConvRules.Model.pas:655-660`), with `ARROW_MIGRATE = ' -> '`. That is an
  **unanchored substring test**: no anchoring, no validation of either operand, no
  check for multiple arrows. Prose containing " -> " anywhere would classify as
  `rnkPcre` and count as recognised. All 197 lines happen to contain the substring, so
  the file's clean result is fully explained by its line shape -- the catch-all is
  wide, and it would absorb malformed input just as happily.

## What the reconstruction test proves (`TestReFindCorpusReconstructs`)

Marking a node `Dirty` forces `Emit` to rebuild the line **out of the fields the parser
decomposed it into**, instead of echoing `Raw`. Doing that to the real BDE corpus and
getting the original bytes back is genuine parse/emit-are-inverses evidence.

| Check | Result |
|---|---|
| `refind.bde.reconstruct.count` | **9** nodes have a reconstruction path: 6 x `#unuse`, 2 x `#remove`, 1 x `#remove DFM:` |
| `refind.bde.reconstruct.exact` | those 9 rebuild from their parsed fields **byte-exactly** |
| `refind.bde.reconstruct.live` | perturbing one parsed field changes the output -- so the check above is not vacuous |
| `refind.bde.migrate.notdecomposed` | **60 of 60** `#migrate` nodes carry no parsed fields at all |

So the honest scope of real superset evidence in this corpus is **9 lines out of 69**.

### The pinned gap: `#migrate` is recognised but never decomposed

`ParseLine` sets `N.Kind := rnkMigrate` and nothing else (`ConvRules.Model.pas:637-641`
-- the comment there says "content edited via Raw"), and `Emit` has no `rnkMigrate`
branch, so it falls to the `else` and returns `Raw` (`:357-359`). `FromType`, `ToType`
and `Units` stay empty. All 60 `#migrate` lines therefore round-trip **vacuously**, and
that includes every interesting form in the file:

* `#migrate Session.* -> FDManager.*, FireDAC.Comp.Client` -- wildcard receiver.
* `#migrate TQuery:DataSource -> MasterSource` -- the `Class:member` qualified form.
* `#migrate TTable -> TFDTable, <eleven units>` -- long uses-add tails.

Their survival is **tolerance, not comprehension**: the model cannot mangle a tail it
never parsed. `refind.bde.migrate.notdecomposed` pins this deliberately -- if someone
teaches the parser to split `#migrate`, that check fails on purpose and this document
must be updated in the same commit.

### Still not validated at all

The tests prove the corpus **parses, classifies and re-emits**. They say nothing about
whether the engine would **apply** it correctly. Untested here: the semantics of every
`#migrate` form above, `#remove DFM: Origin` as an actual DFM-only removal, and every
`rnkPcre` line, which we keep verbatim and hand to the regex path untouched.

## The demo project as a scan fixture

`...\reFind\BDE2FDMigration\Demo` holds the classic **mastapp** BDE project (real forms,
real `.dfm`s, real `TTable`/`TQuery` wiring). It is available as a real-form fixture for
the DFM/PAS scanners whenever we want scan tests against something we did not author.
Not wired into the suite yet.

## Test

`ConvRulesModelTests.dpr`, 12 checks in two tests:

* `TestReFindCorpusLoads` / `CheckReFindCorpus` -- 8 checks, 3 assertions per file plus
  a presence check. Because the files are committed, **a missing file is a FAIL, not a
  Skip.**
* `TestReFindCorpusReconstructs` -- 4 checks on the BDE corpus: reconstructable count,
  byte-exact field reconstruction, a sensitivity guard proving that check is live, and
  the pinned `#migrate` gap.

All of them are deliberately unrelaxable. If a future grammar change makes a construct
unknown, or breaks reconstruction, the correct response is to fix the parser or record
the gap **here**, never to lower the bar. Doc and test must agree: if you change what
one of these checks asserts, change this document in the same commit.

## Licensing

These are **Embarcadero RAD Studio sample files**, redistributed from a local install.
Fine for internal use while this repository is unpublished. **Revisit before any public
release or redistribution** -- check the RAD Studio sample licence terms, and be
prepared to replace them with equivalent rule books of our own authorship, or to ship
only a script that imports them from the user's own installation.
