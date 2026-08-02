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

Everything. `TRuleBook.LoadFromString` produced **zero `rnkUnknown` nodes** across both
files, and `SaveToString` reproduced both byte-for-byte on the **first** run -- no
parser change was needed.

| File | Lines | Blank | Recognised | Node kinds |
|---|---|---|---|---|
| `FireDAC_Migrate_BDE.rules` | 77 | 8 | 69 | `#migrate` x60, `#unuse` x6, `#remove` x2, `#remove DFM:` x1 |
| `FireDAC_Rename_Units.rules` | 211 | 14 | 197 | bare `old -> new` x197, parsed as `rnkPcre` |

Notes on the two interesting shapes:

* **`#migrate ... -> ..., Unit1, Unit2, ...`** -- the long uses-add lists (`TTable`
  carries eleven units) round-trip because `rnkMigrate` is a Raw-only kind: the model
  does not decompose the tail, so it cannot mangle it. That is a *tolerance*, not
  comprehension -- see "Not actually validated" below.
* **Bare `old -> new`** -- reFind's plain find/replace form, which the whole
  `FireDAC_Rename_Units.txt` file is made of. Our grammar accepts any non-`#` line
  containing ` -> ` as `rnkPcre`, the raw PCRE escape hatch, so all 197 lines classify
  and re-emit unchanged. Filename-target lines (`uADGUIxFormsfAbout.dfm ->
  FireDAC.VCLUI.About.dfm`, `.lfm`, `.lrs`, `.rc`, `.res`, `.dcr`, `.inc`) are just
  ordinary `rnkPcre` rows to us.

### Not actually validated

The conformance test proves the corpus **parses and round-trips**, not that our engine
would **apply** it correctly. Specifically untested here:

* `#migrate Session.* -> FDManager.*` -- a wildcard receiver.
* `#migrate TQuery:DataSource -> MasterSource` -- the `Class:member` qualified form.
* `#remove DFM: Origin` -- DFM-only property removal.
* Every `rnkPcre` line: we keep it verbatim and hand it to the regex path untouched.

## The demo project as a scan fixture

`...\reFind\BDE2FDMigration\Demo` holds the classic **mastapp** BDE project (real forms,
real `.dfm`s, real `TTable`/`TQuery` wiring). It is available as a real-form fixture for
the DFM/PAS scanners whenever we want scan tests against something we did not author.
Not wired into the suite yet.

## Test

`ConvRulesModelTests.dpr` -> `TestReFindCorpusLoads` / `CheckReFindCorpus`, 8 checks.
Because the files are committed, **a missing file is a FAIL, not a Skip.** The three
assertions per file -- non-trivial recognised count, zero unknown, exact round-trip --
are deliberately unrelaxable: if a future grammar change makes a construct unknown, the
correct response is to fix the parser or record the gap here, never to lower the bar.

## Licensing

These are **Embarcadero RAD Studio sample files**, redistributed from a local install.
Fine for internal use while this repository is unpublished. **Revisit before any public
release or redistribution** -- check the RAD Studio sample licence terms, and be
prepared to replace them with equivalent rule books of our own authorship, or to ship
only a script that imports them from the user's own installation.
