# Rule chains in ConvRulesEditor

A rule book with `#convert TA -> TB` and `#convert TB -> TC` looks as if it converts a TA
all the way to TC. It does not. convert-apply is SINGLE PASS: every rule matches the
ORIGINAL source and an output is never matched again. A TA ends as TB, a TB ends as TC, and
nothing used to tell you. ConvRulesEditor now finds these cases on every Save and File >
Validate, marks the rules involved, and offers a one-click fix.

## The four kinds

* **Chain** -- `TA -> TB` plus `TB -> TC`. A TA ends as TB, never TC. Two chains that share a
  tail (`TA -> TB`, `TX -> TB`, `TB -> TC`) are reported separately.
* **Cycle** -- `TA -> TB` plus `TB -> TA`. The two classes are SWAPPED in one run; nothing
  loops. A cycle is only a warning and has no fix (a merge would be `TA -> TA`).
* **Duplicate From** -- two `#convert` headers with the same From type. The first one wins;
  the later ones are never applied.
* **Unit chain** -- a `#useswap A -> B` whose Old unit is added by another line (another
  `#useswap X -> A`, a `#use A`, or a header's `, A` uses-add). ADD wins, so the unit ends
  with both A and B.

Type names are compared by their BARE name (after the last dot, case-insensitive):
`Bde.DBTables.TTable` and `TTable` are the same type. A `#convert` header with no To type is
scratch and takes no part.

## The marks

Every line a finding involves gets a warning mark (a chain: each stage; a duplicate: the
winner and each loser; a unit chain: both unit lines), for example
`chain TA -> TB -> TC: stage 1 of 2 -- convert-apply is single pass, so a TA ends as TB,
never TC`. Marks are session state like the engine's: they are never written into the book.
When a Save finds chains, the status line ends with a "Rule chains" note that gives the
counts and points to Conversion > Rule chains.... A book without
chains shows nothing new.

## The dialog: Conversion > Rule chains...

The dialog lists every finding; the fixable ones (chains and unit chains) are checked.
Cycles and duplicates are listed with the fix buttons disabled.

* **Merge** -- enabled when every checked finding can be merged.
* **Split** -- enabled when every checked finding is a chain.
* **Keep** -- close the dialog; every listed finding counts as asked.

**It asks once.** After File > Save or File > Save As finds a fixable chain, the dialog opens
once per chain per session. It never opens when the Save comes from closing the editor,
opening another book, or the Convert tab's lower question; the marks and the status line
are the standing signal. Open a book (Open, New) and the asked list starts again.
`Conversion > Rule chains...` always shows the current findings, asked or not, without
saving first. Cycles and duplicates alone do not open the dialog on Save.

## Merge: one rule TA -> TC

Merge replaces the first stage with `#convert TA -> TC` (using the last stage's uses-add),
composing the stages from the left. The last stage block stays as it is, because a TB may
also exist on its own in your sources. Merge edits the book and does NOT save: review it,
then Save. The block starts with a `#note chain merge: ...` line that counts what was
composed, carried, dropped and noted.

In plain words:

1. `#link` lines are joined through the middle class: `B.x <- A.y` plus `C.z <- B.x`
   becomes `C.z <- A.y`. If both stages have a cast, the link gets no cast and a note asks
   you to pick one; otherwise the one cast is kept.
2. A `#ignore B.x` in the second stage becomes `#ignore A.y`.
3. A first-stage `#link B.x <- A.y` with no second-stage line for `B.x` is DROPPED: run in two
   passes, the second pass drops the unlinked `B.x` too, and TC may have no `x` at all. A
   `#note chain merge: dropped ...` names the line, `#ignore A.y` follows it, and the Merge
   status lists every dropped line. Link `A.y` to a TC property yourself if the value should carry.
4. A first-stage `#default B.x = v` follows a second-stage link to `#default C.z = v`; it is
   dropped with a note through an `#ignore`, and dropped with a note when nothing matches.
5. `#migrate Old -> New` followed by `#migrate New -> Newer` becomes `#migrate Old -> Newer`;
   all other `#migrate` lines are kept and de-duplicated.
6. Everything else of the first stage (`#ignore`, `#remove`, `#apply`, `#tag`, `#warn`,
   `#checkref`, `#pcre`, notes, comments) is kept. The second stage's leftover `#apply`,
   `#warn`, `#checkref`, `#remove` and `#pcre` lines follow one `#note` that names where
   they came from. Its leftover `#link` / `#ignore` lines (they name paths of the middle
   class that a TA never has), tags, notes and comments are dropped.
7. A unit chain is merged by rewriting the ADDING line only: `#useswap A -> B` becomes
   `#useswap A -> C`, a header's `, B` becomes `, C`, `#use B` becomes `#use C`. The
   `B -> C` swap stays.
8. If a stage block was edited away since the dialog found it, Merge refuses and changes
   nothing.

## Split: stage books run in order

Split keeps each chain's first stage in the book and moves every later stage into its own
book beside it: `X.rules` stays, `X.stage2.rules` holds stage 2, `X.stage3.rules` stage 3.
Cycle members, duplicate losers and the file-scope lines stay put. A stage book gets the
source's `#depth` line, a copy of every `#mapping` group that a moved block `#applies` (the
engine resolves `#apply` inside the book it runs; the status says which names were
copied), then the moved blocks verbatim. An existing stage file is appended to (its own
`#depth` line governs; the moved blocks' copy is dropped), with the usual duplicate-header
warning. Every encoding question is asked before the first file is written.

Split writes the stage books first, then removes the moved blocks and saves the source.
Every file gets a backup and the usual encoding question; cancelling that question aborts
before anything is written. If saving the source fails, the status names both files and says
the blocks now exist in both; the stage books are never deleted. On success the status
names the blocks and files moved and tells you to convert with the base book first, then
the stage 2 book (check both on the Convert tab, in that order).

## Running the stages on the Convert tab

The Convert tab runs the CHECKED books in list order, one after the other, on every unit,
and reindexes between books. So `X.rules` then `X.stage2.rules` really does turn a TA into
TB and then into TC: book 2 reads book 1's output. The folder scan lists `X.rules` before
`X.stage2.rules`; use **Move Up** and **Move Down** under the book list to change the order.
The tab does not yet warn about a wrong order across books (a later book holding the
earlier stage); that is planned as CHAIN-2.

Source: spec `docs\superpowers\specs\2026-10-27-converter-chain1-design.md`; engine facts:
`docs\CONVERSION-RULES.md` (single pass).
