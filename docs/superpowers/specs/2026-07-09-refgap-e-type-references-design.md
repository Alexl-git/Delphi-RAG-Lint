# Ref-gap E -- index type-annotation / impl-header / is-as type references: design

**Date:** 2026-07-09
**Status:** Approved (design); implement via TDD -- WITH A SUPERVISED PAUSE
**Program:** H4 of the post-Batch-G autonomous deferred-backlog program
(H1 done, H2 done, H3 = Track 3 Batch 1 done; H4 = this, the LAST item).
**Supervision:** the user explicitly wants to SUPERVISE the core-parser change.
The RED test is written first (safe); implementation PAUSES for user review of
the exact parser diff BEFORE the parser is touched.

## Problem

The `type-name-prefix` and `field-name-prefix` naming autofixes rewrite a
type/field DECLARATION and every reference the index knows about. But the
reference index does not capture certain type-USE positions, so a
`type-name-prefix --apply` rename (e.g. `TMyclass` -> `TMyClass`) can leave old
-name references behind -- the file then fails to compile with exit code 0 and
no other diagnostic. To be honest about this, the CLI emits a stderr warning
whenever `field-name-prefix`/`type-name-prefix` autofix is in the opted-in set
(`DRagLint.CLI.pas:4866-4873`).

Ref-gap **D** (shipped v0.98, commit `81a101c`) closed the `Self.`-qualified
FIELD case. Ref-gap **E** closes the remaining TYPE-reference shapes, after which
the warning can be dropped.

### Verified gap (probe fixture, 2026-07-09)

Indexing a class `TMyclass` referenced in every shape, the index CAPTURES:
- interface declaration type positions (param / return / field / class-var
  types) -> `kind='type_use'` (via the existing `typeref` walk);
- construction sites (`TMyclass.Create`) -> `kind='read'`.

It MISSES (all three confirmed absent from the refs table):
1. **Impl-header type-qualifier** -- `TMyclass.Use`, `TMyclass.Make`,
   `TMyclass.Create` (the class name qualifying a method IMPLEMENTATION header).
   THIS is the shape that breaks `type-name-prefix` autofix: rename the class
   decl and these headers still say the old name.
2. **Local-var type annotation** -- `Local: TMyclass;` inside a method body.
3. **`is` / `as` type-test operand** -- `if X is TMyclass` / `X as TMyclass`.

## Why the fix is small (verified facts, do not re-litigate)

- The parser already emits `kind='type_use'` for `typeref` nodes UNCONDITIONALLY
  (`DRagLint.Parser.Delphi13.pas:1333-1338`, before the `--deep` guard). E just
  widens WHERE `type_use` is emitted; it introduces NO new ref kind.
- The rename engine finds sites via `TRenameRefactoring.Build` ->
  `FindCallersByName(ShortName)` (`Rename.pas:115`), which matches refs by
  `name_text` and is KIND-AGNOSTIC (SQLite store comment,
  `Storage.SQLite.pas:1954`: "Match any reference kind (call, event-binding,
  type_use, ...)"). So new `type_use` refs are picked up by the rename with NO
  consumer change.
- `refs.symbol_id` is NULL in the index (see `TextEdit.pas:58`), which is exactly
  why the rename is name-based -- reinforcing that a by-name `type_use` emit is
  the right and sufficient mechanism.

## Approach (chosen: A -- three surgical gated emit points)

Add three individually-gated `EmitRef('type_use', <typename>, <node>)` calls to
the tree-sitter walk in `src/parser/DRagLint.Parser.Delphi13.pas`, each mirroring
ref-gap D's tight-AST-shape-gate precedent (no over-capture). Emitted
unconditionally (like the existing `typeref` walk), NOT behind `--deep`, because
type references matter for shallow scans too.

Rejected alternatives:
- **B (broaden the general identifier walk to emit `type_use` for any identifier
  that resolves to a type):** over-captures (shadowing, coincidental names) and
  needs parse-time symbol resolution the parser deliberately defers. Against the
  architecture.
- **C (post-index resolution pass, parser untouched):** duplicates type-position
  knowledge the AST already has, more code, and does not avoid the risk the user
  is supervising for (the impl-header qualifier is far easier to see in the AST).

### The three emit points

1. **Impl-header qualifier.** At the method-implementation header node
   (`defProc` / the qualified routine name in the implementation section), emit a
   `type_use` for the class-qualifier identifier immediately left of the
   method-name dot. Gate: implementation-section routine header whose name is
   `Qualifier.Method`; emit only for `Qualifier` when it is a bare identifier.
2. **Local-var type annotation.** Ensure a `declVar`'s type child inside a
   method body routes through the existing `typeref` emission. IMPLEMENTATION
   NOTE: first VERIFY whether the current walk already descends into impl-body
   `declVar` types (the probe showed line 19 `Local: TMyclass` absent, so likely
   NOT reached under the impl body). If already reached, this shape needs no new
   code and E is points 1+3 only; if not, add the descent/emit. The test asserts
   the line-19 shape regardless of which is true.
3. **`is` / `as` operand.** At the binary-expression node whose operator is `is`
   or `as`, emit a `type_use` for the RHS identifier. Gate: operator in
   {`is`,`as`} AND RHS is a bare identifier (not a nested expression / not a
   cast-to-variable). Confirm the grammar's node type + operator field names
   against the live tree before coding.

All three emit by NAME (unresolved/unknown identifiers emitted as-is -- same
discipline as the existing `type_use` walk; the rename is name-based).

## Data flow (unchanged pipeline, wider capture)

```
tree-sitter walk -> EmitRef('type_use', <typename>, <node>) -> refs(name_text,file,line,col)
    + 3 NEW emit points (impl-header qualifier / local-var type / is-as operand)
        |
        v
type-name-prefix autofix -> TRenameRefactoring.Build -> FindCallersByName(typename)
    -> matches ALL refs by name_text (kind-agnostic) -> rewrites every site incl. the 3 new shapes
```

## Dropping the `--fix` warning (end goal, GATED)

After E lands, D + E together cover every shape the warning names. The warning
STAYS until the round-trip test (below) passes. When green, REMOVE the warning
block at `DRagLint.CLI.pas:4866-4873` and update its explanatory comment
(`:4857-4865`). This removal is a SEPARATE FINAL STEP, gated on the test -- never
done speculatively.

## Testing

### NEW `tests/autotest/run_type_ref_gap_e.ps1` -- the load-bearing gate

Fixture = a class referenced in ALL target shapes (interface decls, impl-headers,
a local-var type, an `is`/`as` test, construction). Two phases:

**Phase 1 -- refs indexed (RED->GREEN teeth).** Index `--deep`, then
`find-callers --name TMyclass` MUST return `type_use` refs at every shape line --
specifically the impl-header lines, the local-var line, and the `is` line the
probe confirmed are CURRENTLY MISSING. Pre-E these are absent (RED); post-E they
must appear (GREEN).

**Phase 2 -- round-trip rename leaves ZERO stale refs (the real proof).** Run
`type-name-prefix --apply` (opt-in via a fixture `drag-lint-lint.json` `autofix`
entry) to rename `TMyclass` -> `TMyClass` (or drive `TRenameRefactoring` directly
if cleaner headless), REINDEX the renamed fixture, then assert:
- ZERO refs/symbols still name the OLD `TMyclass` (every
  impl-header/local/is-as/decl now the new name), AND
- the class symbol + all shape sites resolve to the NEW name.

This zero-stale-refs assertion IS "recompiles clean" without a compiler -- the
headless CI gate.

**Optional manual smoke (documented, NOT a battery gate).** Rename the fixture,
then compile it with rsvars+dcc32 and confirm 0 errors. Written into the test
header comment + this spec as a confidence path; NOT run in CI (keeps the battery
compiler-free, consistent with the other 15 tests).

### Regression

`run_self_field_refs`, `run_bare_rhs_refs`, `run_naming_prefix_autofix`,
`run_naming_autofix` must stay green (E must not disturb D's `Self.` gating or
the existing prefix autofixes). Then the full 15-test battery after the CLI
rebuild.

### Over-capture check

After implementing, re-run the probe AND diff the TOTAL `type_use` ref count on a
real indexed unit (before vs after) to confirm only the intended shapes were
added -- no flood. If any gate over-captures (e.g. `as` used as a value cast),
tighten it before proceeding.

## Sequencing (with the SUPERVISED PAUSE)

1. Write `run_type_ref_gap_e.ps1`; run it RED (impl-header / local / is-as lines
   absent). Proves the gap + the test's teeth. SAFE, non-invasive.
2. **PAUSE -- hand back to the user before touching the core parser.** The user
   reviews the RED test + the exact 3 gated `EmitRef` edits (as a diff) BEFORE
   they are applied to `DRagLint.Parser.Delphi13.pas`.
3. After the user's go: apply the 3 emit points; rebuild CLI Win64 (parser lives
   in the indexer/CLI, NO BPL); reindex; run the test GREEN (both phases).
4. Over-capture diff check; regression battery (15/15).
5. ONLY once the round-trip is green: remove the `--fix` warning + update its
   comment.
6. Docs: CHANGELOG (E indexed + warning dropped), BACKLOG/ledger.
7. Final whole-branch review (most-capable model).

The parser edit is small (est. ~15-25 lines across 3 gated blocks) but is in the
core tree-sitter walk -- hence the pause at step 2.

## Files

- `src/parser/DRagLint.Parser.Delphi13.pas` -- the 3 gated `EmitRef('type_use')`
  additions (the SUPERVISED change).
- `src/cli/DRagLint.CLI.pas` -- remove the `--fix` warning block (`:4866-4873`) +
  its comment (`:4857-4865`) AFTER the round-trip test is green.
- `tests/autotest/run_type_ref_gap_e.ps1` -- NEW two-phase gate.
- CHANGELOG / README (if it documents the warning) / BACKLOG / SDD ledger.

## Global constraints

- Encoding: all edited/new `.pas` + `.ps1` strict 7-bit ASCII, no BOM, CRLF.
  `*.ps1` is now governed by `.gitattributes` `text eol=crlf` (added in H3).
- DocInsight on any new/changed public surface (minimal here -- the parser change
  is internal; the emit-point comments follow the ref-gap D comment style).
- TDD: RED first, GREEN after the supervised parser edit.
- Build: CLI Win64 Debug via the delphi-build recipe; deploy to
  `src/cli/Win64/Debug/` + `third_party/dll-win64/`. NO BPL. RAD Studio open does
  NOT block a CLI build; never close it (report BLOCKED).

## Out of scope

- Any ref shape beyond the three named (e.g. type refs inside attribute
  arguments, RTTI-string type names) -- not observed to break the autofix; file
  a follow-up only if a real case surfaces.
- Changing the rename engine (it is already kind-agnostic by name).
- Field-name-prefix beyond what D already covers (E is TYPE references; the
  warning drop depends on BOTH D and E, both of which will then be complete).

## Self-review notes

- **Verified-not-assumed:** the 3 missing shapes were confirmed absent via a live
  probe (captured lines 9/10/11/21/26; missing 14/17/19/22/24). The rename engine
  being kind-agnostic-by-name was confirmed in `Rename.pas:115` +
  `Storage.SQLite.pas:1954`. So "reuse `type_use`, no consumer change" is proven,
  not hoped.
- **Termination / over-capture:** each emit point is gated to an exact AST shape;
  the over-capture diff check (before/after `type_use` count on a real unit) is a
  hard step, not optional.
- **The supervised pause is a first-class step (step 2), not a courtesy** -- the
  parser is the one thing the user asked to review before it changes.
- **The warning drop is gated on the round-trip, not on "refs now exist"** -- the
  zero-stale-refs reindex assertion is the real proof the rename is complete.
