> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# The `Calls:` fact list harvests ENGLISH WORDS out of comments

> **FIXED 2026-08-14 (session 19).** The diagnosis in "Where to look" below was
> right, and the cause was narrower than "scanned as TEXT": both body scanners
> DID skip strings and comments, but each declared its brace depth as a **LOCAL,
> reset to zero on every line**, and neither handled star-paren comments at all.
> So a block comment opened on an EARLIER line was invisible while a single-line
> one was handled correctly -- which is why this survived so long and why the
> surviving entries look arbitrary.
>
> Fix: `TBodyScanState` in `DRagLint.Doc.Facts`, carried across the body's lines
> by both `CollectCallIdents` and `CollectRaiseClass`, plus star-paren handling in
> each. State starts "not in a comment" at `ImplStartLine`, which is correct
> because the routine's own doc-comment sits above that line and is not scanned.
>
> **`CollectRaiseClass` had the identical bug and is the sharper edge**, which
> this note did not cover: prose reading "we raise EFoo when ..." inside a block
> comment produced not a noisy fact line but a **fabricated
> `<exception cref="EFoo"/>` tag** for a class that is never raised. Reproduced:
> `docs\INBOX-...`-style fixture in
> `tests\autotest\run_doc_facts_ignore_comment_prose.ps1` rendered
>
>     /// Calls: defect, pretend, so, uProse2.Helper
>     exception crefs = EOnlyInProse, EReal
>
> before the fix -- three prose words and one invented exception -- and only
> `uProse2.Helper` / `EReal` after. That test carries a control asserting the real
> callee and the real exception ARE still documented, since all four negative
> assertions would otherwise pass with the facts line missing entirely.
>
> Point 2 of "Why it matters" (residual doc-drift) is worth re-measuring now:
> comment-derived entries were unstable in exactly the way that note describes.

Class: **wrong**. Found 2026-08-14 while narrowing the EnumHelper doc-drift.

## Evidence -- two independent sites, both in committed source

`src\refactor\DRagLint.Refactor.EnumHelper.pas`, the `Generate` block:

    /// Calls: Default, DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate.EmitFromCase, so

`src\doc\DRagLint.Doc.SharedFacts.pas`, the `BlockDrifted` block, regenerated
during this session:

    /// Calls: defect, DRagLint.Doc.SharedFacts.CollapseWs, DRagLint.Doc.SharedFacts.IsTruncated, ...

`so` and `defect` are not callees. Both are ordinary words from the prose in the
routine's own comments -- `defect` appears in the comment block added to
`BlockDrifted` this session, and the entry appeared in the SAME autodoc pass that
rendered that comment.

## Why it matters more than the noise

1. It puts a **false claim** in the documentation: the block asserts the routine
   calls something that does not exist. That is the failure class this repo
   treats as worse than an absent fact -- `doc-param-not-in-signature` was split
   out of doc-drift and raised to `error` for exactly this reason (documentation
   that is FALSE rather than merely incomplete).
2. It is a plausible cause of the residual doc-drift in
   `docs\INBOX-docdrift-4-survive-a-converged-autodoc.md`: an entry derived from
   COMMENT text is unstable in a way an entry derived from code is not -- edit
   the prose and the fact changes -- so writer and checker can disagree about a
   block nobody touched.
3. It is self-reinforcing: the fact is rendered INTO a comment, which is then
   itself prose the next extraction can read.

## Where to look

The bare-name fallback in `DRagLint.Doc.Facts`' Calls section -- the body scan
that collects identifiers when a call does not resolve through `call_edges`.
`IsCompilerIntrinsic` already filters a deliberately restricted list of RTL
names; there is no filter for "this token came from a comment or a string".

The body is read with `SourceLines(...)` and scanned as TEXT, which is the
likely root: a token inside `{ }`, `(* *)`, `//` or a string literal is
indistinguishable from code to a text scan. `DRagLint.Lint.SharedUnit`'s header
argues this exact point at length for the `dl:shared` marker and ships a
comment/string state machine (`ScanHeader`) to solve it. Same trap, third unit.

## MEASURED: 150 entries corpus-wide, not two strays

    grep -rh "^\s*/// Calls:" src --include=*.pas \
      | sed 's/^\s*\/\/\/ Calls: //' | tr ',' '\n' | sed 's/^ *//;s/ *$//' \
      | grep -cE "^[a-z]+$"
    -> 150

Most frequent: `itself` (3), `index` (3), `file` (3), `all` (3), `constantly`
(2), `children` (2), `by` (2), `body` (2), `based` (2), `access` (2), and a long
tail including `yet`, `until`, `word`, `untouched`, `unreferenced`, `unchanged`,
`write`, `type`.

`constantly`, `unreferenced`, `untouched`, `until` and `yet` are not identifiers
in any dialect. A handful (`default`, `index`, `write`, `type`) are Delphi
keywords or could shadow a real lowercase name, so the true count needs the
keyword set excluded before it is quoted -- but the class is established, and it
is corpus-wide documentation that asserts calls which do not exist.

Note the filter is deliberately narrow (single all-lowercase token, no dot), so
150 is a FLOOR: prose words that happen to be capitalised at the start of a
sentence are not counted here and are indistinguishable from real callees by
this test.
