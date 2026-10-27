# Member migration (#migrate) in ConvRulesEditor

Replace a member that converted code still uses. You can rename it, or mark it `DL_NONE`
so that you convert it by hand later. You do not type the rule yourself. This is A4,
slice 1 of member replacement (C18).

## What it does

The Work list shows each FROM member that a converted unit's `.pas` still uses. Pick a row
and press **Migrate...**. The editor then writes one line into the `#convert <From> -> <To>`
block for that row, in the book that converted the row (see **Which book** below):

* `#migrate Old -> New` renames every site of the member on a converted instance.
* `#migrate Old -> DL_NONE` is a *deliberate break*. Each site becomes
  `DL_NONE(btnTop.Count)`, so the unit does not compile there until you convert it by hand.

The next Convert run applies the line. The row's note then reads
`; migrate: 3 renamed, 2 deliberate break(s), 1 to check`. The run report has one line for
each item, with the status `migrate`, `deliberate break` or `migrate check`.

## Where

* **Work list tab > Migrate...** works on the focused instance row. The button is hidden when
  the engine lacks `migrate_members`. The new **Rule** column shows the open book's line for
  the row, for example `#migrate Count -> DL_NONE (line 5, unsaved)`.
* **Several rows at once.** The Work list takes a multiple selection (Ctrl+click,
  Shift+click). When two or more distinct members of one book are selected, the dialog
  offers **DL_NONE for all N selected rows**. Tick it and Apply writes
  `#migrate <member> -> DL_NONE` for every selected member into its own block. A line that
  is already DL_NONE is left as it is; a member whose pair has no block is skipped and named.
  The status bar says `DL_NONE for 2 member(s) in Fix.rules: 1 written, 1 changed, 1 already
  DL_NONE -- not saved: ...`, then `skipped K: ...` when any. A member that several units
  use is written once.
* **Classes tab > Members list** sits under the `#link` grid and lists every `#migrate`
  line of the active block in the columns Old | New | Kind (`rename`, `DL_NONE`,
  `legacy`) | Note. The Note column holds the engine's reason when a line is not
  applied, then any warning marks. Use **Add...**, **Edit...** and **Delete** to change
  the lines. Add and Edit are disabled without `migrate_members`; Delete always works.
* **Rule tree:** a block that holds member migrations shows `; N migrate` in its marker cell.

## What one click changes

| block before | pick | block after |
|---|---|---|
| `#convert TSrcBtn -> TDstBtn` / `#link Caption <- Caption` | `btnTop.Click`, rename `Press` | ... / `#migrate Click -> Press` (appended at the block end) |
| ... / `#migrate Click -> Press` | `btnTop.Click`, rename `Tap` | ... / `#migrate Click -> Tap` (changed in place, never a second line) |
| ... | `btnTop.Count`, DL_NONE | ... / `#migrate Count -> DL_NONE` |
| ... | rename to `Items.Count` | Apply disabled: the engine applies only a plain rename or DL_NONE |

The book is changed in memory and is not saved. The status bar says
`Wrote #migrate Click -> Press into #convert TSrcBtn -> TDstBtn (line 3 of Fix.rules) --
not saved: File > Save, then Convert again`.

## When a line is not applied

The dialog and the Members list use the engine's own words, before any run:

* a scoped line (`Class:` / `obj.`);
* a call or assignment form;
* no replacement;
* a replacement template;
* trailing `, Unit` names.

The editor also warns when a `#link` of the block already converts the member
(`book line K already converts Old`), when a line renames nothing (identity), and when a
line sits before the first `#convert`. These warnings become marks on the line at Save.

## Needs

* Engine 1.32.0-alpha or later, which reports `migrate_members` in `info --json`. The pin
  1.35.0-alpha also sends `pas_uses[].migrate_to`.
* A `#convert` block for the row's From -> To pair in the target book. The editor matches
  the bare type names. If the book has no such block, the dialog says so and Apply is
  disabled.

## Which book

Each Work list row carries the book that converted it (`pas_uses[].rules_file`, engine
1.35.0-alpha and later). When that book is not the open one, **Migrate...** opens it first,
with the usual unsaved-changes question, and the status bar starts with
`Opened Fix.rules (it converted the row) -- `. If the row names a book that is no longer on
disk, the open book is used and the status says so. An engine that does not send
`rules_file` keeps the old behaviour: the open book. When the selected rows come from
several books, only the focused row is migrated and the bulk choice is not offered.

## Limits

* Slice 1 covers a rename and DL_NONE only. Templates and user code are slice 2; globals
  are slice 3.
* A rename is one row at a time. Only DL_NONE applies to several rows at once.
* A deliberate break keeps the engine status `mapped`, with `migrate_to` = DL_NONE. The
  Work list's default filter therefore hides such a row. The row note and the report still
  count it.

## The BDE book's legacy tail

`convrules\BDE-to-FireDAC.rules` ends with 43 `#migrate` lines of reFind heritage. 25 of
them carry units, and 3 are scoped or dotted. 15 are in member form, for example
`dcrDefault -> gcrDefault` and `IsAlias -> IsConnectionDef` (measured 2026-10-26). The
Members list shows the 28 that are not in member form as `legacy`, each with the engine's
reason.

*D2 split (2026-10-27).* The 43 lines no longer live in one trailer: the 28 BDE ones sit above the first
`#convert` of `BDE-to-FireDAC.rules` (file-scope), and the 15 `Data.DB` ones moved to
`DataDB-to-FireDAC.rules` (run it after the BDE book). `UpdateRecordTypes -> FilterChanges` now sits inside
 the TTable / TQuery / TStoredProc blocks and is applied by the engine.
