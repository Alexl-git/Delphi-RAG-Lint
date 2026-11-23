# Plan TT-DFMREAD -- `repo read-dfm` (1.54, DFM -> field repository)

Spec: `docs\superpowers\specs\2026-11-22-field-repository-v2-design.md` sections 1-4, 8, 9 (first bullet; engine side of
the second). Lane fence: `src\sql\DRagLint.FieldRepo.DfmRead*.pas`, `src\cli\DRagLint.CLI.RepoDfm.pas`, one hub commit.

## Reuse (no second parser)

| Need | Existing code used |
|---|---|
| DFM objects + decoded properties | `TDFMParser.Parse` (DfmObjects) + `ExtractDfmPropertyRows` (dfm_properties), the index producers |
| binary DFM | RTL `ObjectBinaryToText` in memory, then the same reader (as `Convert.GlyphVacuum` does) |
| handler code | `LSP.SyntaxTree.ParseDelphiUtf8` (tree-sitter), after `TAstParseCache.ApplyPreprocess` |
| change set, `--select`, log lines | `FieldRepo.ChangeSet` |
| kinds, macros, dependencies | `FieldRepo.Kinds` |
| PK of a lookup table | `FieldRepo.SchemaFacts.PrimaryKey` |

## Units

1. `DfmRead` -- one form as records: datasets, persistent fields (kind, props, lookup wiring, events), components.
2. `DfmReadSql` -- tables and columns of a SELECT; only facts, else a reason.
3. `DfmReadCalc` -- handler text -> CALC_BODY / event body with macros (slice per field; refuses what it cannot express).
4. `DfmReadPlan` -- facts of N datasets against a repository -> change set; apply in one transaction.
5. `DfmReadSelection` -- `ExpandSelection` (4.4, S1 / S2 / S3 / S5).
6. `CLI.RepoDfm` -- `repo read-dfm --dfm <file>[;...] [--dataset N] --direction dfm-to-repo [--apply | --select f] [--json]`.

## Rulings made here

* Table: `UpdateOptions.UpdateTableName` -> `TableName` -> a SELECT over one table. Per field: select-list item
  (`a.COL AS F`), else `Origin` when it names a table of the same FROM. Otherwise unresolved, reported, no change.
* Paradox `TOOLS.DB` -> `TOOLS`; names are upper-cased; an existing repository row is matched case-insensitively.
* Only properties the DFM states make updates (absent = no claim). Schema-derived columns are filled on insert only.
* OnGetText has no column in the landed v2 model: stored in DL_LAYOUT_EVENTS, LAYOUT_TYPE `Field`. Other field events are
  named in the output and not stored (1.3: five events first).
* CALC_BODY of one field = a slice of the OnCalcFields handler (statements up to its last assignment; other calc fields'
  assignments cut out; unneeded locals dropped; every other effect kept). A top-level `if C then Exit` becomes a block.
* Inherited (override-only) fields and datasets are reported, not resolved through the ancestor's DFM.
* `ExpandSelection` lives in `DfmReadSelection` (lane fence), not in the spec's `FieldUse`; a selected lookup also adds its
  SOURCEKEY.
* A bad `--select` file exits 2 (spec section 3); the older `refresh-schema` still exits 1.
* A body the macros cannot express is listed BLOCKED with its text, never stored.
* Two datasets that disagree: every alternative is listed unchecked.
* A read never deletes: a field missing from a DFM is only "not selected there" (FR-2).

## Tests

`tests\fieldrepo\DfmReadTests.dpr` (pure units) and `tests\autotest\run_fieldrepo_dfmread.ps1` (CLI: text = binary,
all kinds, lookups, events, conflict, unresolved, apply, select, idempotent second run, dry run changes no byte).