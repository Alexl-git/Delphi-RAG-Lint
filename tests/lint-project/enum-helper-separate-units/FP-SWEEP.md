# enum-helper-separate-units -- ON-by-default FP sweep (Task 9)

Spec Section 6 risk check: this rule is ON by default (a deliberate divergence
from the OFF-by-default convention most advisory rules use in this codebase).
Before release, sanity-check the real-world false-positive count.

## Method

1. Reindexed the DragLint self-index (`C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite`)
   with the freshly-built v15 exe: `drag-lint index --all --only DragLint`
   (531 files, 14527 symbols, 26.8s). Confirmed `type_helpers` populated
   (9 rows: 2 real production helpers -- `TSymbolKindHelper`,
   `TTypeCategoryHelper` in `DRagLint.Core.Model.pas` -- plus 4 TreeSitter
   helpers plus 3 rows from enum-helper-generator test fixtures that live
   under `tests/`).
2. Ran `drag-lint lint-all --db <self-index> --json` (whole-tree, 441 .pas
   files after exclusions, 7485 total findings across all rules).
3. Filtered to `rule == "enum-helper-separate-units"`.

## Result: 6 findings on the self-index

| # | Helper (unit) | Enum (unit) | Verdict |
|---|---|---|---|
| 1 | `TSymbolKindHelper` (`src\core\DRagLint.Core.Model.pas`) | `TSymbolKind` (`src\delphi-plugin\DragLint.Plugin.StructureCache.pas`) | **FALSE POSITIVE** |
| 2 | `TColorHelper` (`tests\refactor\fixtures\enumhelper\_probe_helper.pas`) | `TColor` (`tests\fixtures\Kinds.pas`) | **FALSE POSITIVE** (fixture noise) |
| 3 | `TColorHelper` (`tests\refactor\fixtures\enumhelper\_probe_helper.pas`) | `TColor` (`tests\heritage\typecat.pas`) | **FALSE POSITIVE** (fixture noise) |
| 4 | `TColorHelper` (`tests\refactor\fixtures\enumhelper\_probe_helper.pas`) | `TColor` (`tests\lint\magic-literal.pas`) | **FALSE POSITIVE** (fixture noise) |
| 5 | `TModeHelper` (`tests\refactor\fixtures\enumhelper\ModeHelperUnit.pas`) | `TMode` (`tests\refactor\fixtures\enumhelper\Mode.pas`) | **TRUE POSITIVE** (this is the rule's own deliberately-crafted positive test fixture, used by `run_enum_helper_separate_units.ps1`) |
| 6 | `TColorHelper` (`tests\refactor\fixtures\enumhelper\_probe_helper.pas`) | `TColor` (`tests\refactor\fixtures\enumhelper\simple.pas`) | **FALSE POSITIVE** (fixture noise) |

**1 true positive (by design) / 5 false positives, all from the same root cause.**

## Root cause of the false positives

`CollectEnumHelperSeparateUnits` (`src/lint/DRagLint.Lint.ProjectRules.pas`,
~line 354) calls `AStore.FindHelpersOfType(Sym.Name)` for every indexed
`skEnum` symbol, passing only the enum's bare **name** (a string). The store
method (`TSQLiteSymbolStore.FindHelpersOfType`,
`src/storage/DRagLint.Storage.SQLite.pas` ~line 3593) queries:

```sql
SELECT th.*, s.kind FROM type_helpers th
JOIN symbols s ON s.id = th.helper_symbol_id
WHERE th.target_name = :target_name
```

This is a **name-only** match. The `type_helpers` table already carries
`target_symbol_id` / `target_file_id` (populated at index time -- verified
non-null for the fixtures spot-checked above), but the rule never uses them
to confirm the helper's *actual* target enum is the *same declared symbol*
as the candidate enum being compared. Any second, unrelated type that
happens to share the enum's bare name anywhere else in the indexed tree
(a different `TColor`, a different `TSymbolKind`, etc.) gets spuriously
cross-linked.

This bites in two ways on this repo:
- **Real production code**: `DragLint.Plugin.StructureCache.pas` declares
  its own local `TSymbolKind` (an IDE-outline-cache enum, `skUnknown,
  skUnit, skClass, ...`) that is textually unrelated to
  `DRagLint.Core.Model.pas`'s `TSymbolKind` (the core AST symbol-kind enum
  that `TSymbolKindHelper` actually extends). Same name, different types,
  different units -- the rule cannot tell them apart today.
- **Test fixtures**: the enum-helper generator's own round-trip fixtures
  (`_probe_helper.pas`'s throwaway `TColorHelper`) get name-matched against
  every unrelated `TColor` enum elsewhere in the tree (other rules'
  fixtures, `Kinds.pas`, `typecat.pas`).

## Interpretation

The false-positive rate on a ~14.5k-symbol, 441-file self-index is small in
absolute count (5) but the *mechanism* is systematic, not incidental --
name-only matching will misfire on **any** codebase with two same-named
enums declared in different units (a common pattern: local/private mirrors
of a shared enum, or copy-pasted definitions). ORM3 (833 files, ~53k
symbols -- roughly 3.6x this repo) is very likely to have more name
collisions of this shape and was not re-parsed for helper edges as part of
this task (schema is already v15 there, but `type_helpers` is empty --
migration stamps the version without re-parsing; a real reindex was out of
scope per Task 9's "no huge ORM3 reindex" constraint). The true-positive
rate found here (co-located-by-design fixture only) is consistent with the
rule being sound in principle but under-qualified in its matching key.

## Recommendation for the release task

**Fix the matching before shipping ON by default**, OR flip the default to
OFF until fixed. Concretely: prefer matching by `target_symbol_id` (already
populated) when both the helper's edge and the candidate enum resolve to
the same file+symbol identity, falling back to name-only matching *within
the same unit* only (which is moot, since same-unit is already skipped) --
i.e. require the candidate enum to be the actual declaration the edge's
`target_symbol_id` points at, not just any same-named enum. This is a small,
targeted change to `CollectEnumHelperSeparateUnits` / `FindHelpersOfType`
(add an overload or a symbol-id-aware WHERE clause) and does not require
re-scoping the rule.

Given the mechanism is systematic and already produces one real-code false
positive on our own ~14.5k-symbol tree, **do not ship ON-by-default as-is**.
Either (a) fix the symbol-identity matching first (preferred -- the fix is
small and the rule's intent is sound), or (b) flip `default_enabled` to
`false` for this release and revisit once the matching is tightened.

## ORM3 result

Schema already stamped v15 (migrated), but `type_helpers` has 0 rows (no
files re-parsed with the helper-edge-populating code since the v15 schema
landed -- sha-based invalidation skips unchanged files, and edge population
happens at parse time, not at migration time). Per Task 9 scope ("do NOT
kick off a multi-hour whole-tree reindex"), a full ORM3 reindex was not run.
ORM3 is therefore **not currently checkable** for this rule without a
reindex; the self-index count above is the basis for the recommendation.
