# convrules/vendor -- Embarcadero reFind corpus, imported verbatim

These are NOT our rule books. They are byte-identical copies of the reFind
sample rule files that ship with RAD Studio 37.0, renamed .txt -> .rules:

| File | Source under the RAD Studio samples tree |
|---|---|
| `FireDAC_Migrate_BDE.rules`  | `reFind/BDE2FDMigration/FireDAC_Migrate_BDE.txt` |
| `FireDAC_Rename_Units.rules` | `reFind/AD2FDMigration/FireDAC_Rename_Units.txt` |

Sample root: `C:/Users/Public/Documents/Embarcadero/Studio/37.0/Samples/Object
Pascal/Database/FireDAC/Tool/reFind/`. See `docs/converter/refind-corpus.md`.

## Why they are in a subfolder (moved 2026-09-08)

Neither file contains a single `#convert`. `FireDAC_Migrate_BDE.rules` is 60
`#migrate` plus 6 `#unuse` and 3 `#remove`; `FireDAC_Rename_Units.rules` is 197
bare `old -> new` lines with no directive at all, parsed as `rnkPcre`. So they
contribute ZERO rows to the rule catalog, while still being read on every
`ScanRulesFolder` pass over `convrules/`.

The real reason for the move is the duplicate rule, not the wasted read.
`FindDuplicates` enforces "an atomic rule lives in exactly ONE file" by bare type
name. The moment atomization promotes any of these `#migrate` type lines into a
`#convert` -- `TTable -> TFDTable` already collides with
`BDE-to-FireDAC.rules` -- the duplicate report would start firing against a
vendor file that nobody owns and nobody may edit.

`ScanRulesFolder` is NON-RECURSIVE, so `vendor/` is out of the scan while the
files stay open-able by hand.

## Do not edit these files

Their value is that they are verbatim. Derive from them into a book under
`convrules/` -- as `BDE-to-FireDAC.rules` already does -- and leave these alone.
