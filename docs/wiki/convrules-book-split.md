# The BDE and Data.DB rule books (D2 split)

The old single BDE-to-FireDAC book is two books, split by the DECLARING UNIT of each rule's
From symbol:

| Book | Holds |
|---|---|
| `convrules\BDE-to-FireDAC.rules` | what is declared in `Bde.DBTables` (TTable, TQuery, TDatabase, ...) |
| `convrules\DataDB-to-FireDAC.rules` | what is declared in `Data.DB` and shared by every TDataSet family (fields, Params, ...) |

Every rule was moved verbatim, so the two books together plan and produce exactly what the
single book did. The guard `tests\autotest\run_convert_book_split.ps1` proves it (dry-run plan
equality, byte equality of the applied `.dfm`/`.pas`, and positive controls).

## How to run
Check both books in the Convert tab (or pass both to `convert-apply --rules`), BDE book first.
The books run in the order given and the project is reindexed between them.

## What to know
* **Order matters.** The BDE book converts first; Book-2 contains rules that depend on its output.
  Listing Book-2 above the BDE book gives a warning note in the Convert tab (it does not refuse
  the run: running Book-2 alone is legitimate).
* Components whose class has a rule in a book that is NOT checked are reported before the run
  (pre-check note: "N component(s) in M .dfm file(s) have a rule in a rule book this run does not apply").
* There is no rule chain between the books; the dependency is containment.
