# Enum-Helper Generator -- design scoping note (pre-brainstorm)

**Status:** SCOPING (not yet brainstormed/specced). Next session: run
superpowers:brainstorming from this note + `INVESTIGATION-enum-helper-pattern.md`, then
writing-plans, then subagent-driven-development -- same flow as AutoDocument/preprocessor.
**Ground truth:** `docs/lint/INVESTIGATION-enum-helper-pattern.md` (the ORM3 MSCTYPES.PAS
pattern + the confirmed index support + the testing plan).

## The feature (user's words, 2026-07-07)

drag-lint should AUTOMATE generating the standard enum `record helper` -- the
`ToByte`/`FromByte`/`ToInteger`/`FromInteger`/`ToString`/`FromString` pattern that ORM3's
MSCTYPES.PAS hand-writes ~45 times. Entry point: **right-click on an enum MEMBER or the enum
type/class DEFINITION -> a context-menu item "Create helper class" (only when no helper exists
yet)**.

## Where this fits

This is a new **Refactoring** (Track 4 of `docs/lint/drag-lint TODO plan.md`) -- a CODE-GENERATION
action, sibling to AutoDocument (generate doc-comments) and AutoFix (rewrite code). It reuses the
same shared substrate every action track uses: the index (enum + members), the CLI verb, the
`TTextEditApplier` apply engine, and the IDE context-menu wiring. Ships as its own minor version.

## What's already de-risked (from the investigation)

- Index captures `skEnum` (type) + `skEnumValue` per member (name + order + parent). NO parser change
  needed -- generate `ord(<member>)`, Delphi computes the literal. Query via
  `FindAllChildSymbols(enumId)` filtered to `skEnumValue` in declaration order.
- The generation shape is fully specified by the MSCTYPES reference (see investigation doc):
  `T<Enum>Helper = record helper for T<Enum>` + the 6 methods, impl bodies mechanical.
- "Create only if missing" -> query the index for an existing `record helper for T<Enum>` before
  offering the action / emitting the edit.

## Open design questions (decide in the brainstorm)

1. **ToString / FromString generation** -- RTTI (`GetEnumName`/`GetEnumValue` on `TypeInfo(TX)`,
   no external string source, member-identifier strings) vs case-based (needs a string source). The
   user listed ToString/FromString explicitly. RECOMMEND: RTTI default (works for any enum with
   RTTI -- i.e. a named enum in the interface or with `{$M+}`; a scoped/`{$SCOPEDENUMS ON}` enum
   still has RTTI). Confirm RTTI availability for the target enums (ORM3 enums are plain named enums
   -> RTTI works).
2. **Which methods** -- default set = the user's 6 (ToByte/FromByte/ToInteger/FromInteger/ToString/
   FromString). Optional `ToDescription` when a parallel `<Enum>Descriptions: array[TX] of string`
   const is detected in the same unit (bonus). A `--methods` flag / a settings page to choose the set.
3. **Helper placement** -- insert the helper TYPE decl immediately after the enum decl (same `type`
   section) + the impl bodies in the unit's `implementation` section. Corner: enum in an
   INTERFACE-ONLY unit (no implementation) -> either an inline record-helper with inline method
   bodies, or refuse + tell the user. Decide.
3b. **Negative / >255 ordinals** -- FromByte over a member with ordinal <0 or >255 is unreachable via
    a Byte; generating `ord(member)` in the case is still correct (just never matched). Decide whether
    to warn. FromInteger handles the full range. (Investigation corner #1/#3.)
4. **Right-click on a MEMBER vs the TYPE** -- both resolve to the same enum type (a member's parent is
   the enum). The menu enablement: symbol under cursor is a `skEnum` OR a `skEnumValue` whose parent is
   a `skEnum`, AND no helper exists. Same generated output either way.
5. **CLI verb shape** -- e.g. `create-enum-helper --qname <TEnum> [--apply] [--methods ...]
   [--no-tostring] [--db PATH]` emitting a TTextEdit. `--json` for AI orchestration. Idempotent
   (2nd run = helper exists = no-op).
6. **IDE menu** -- add "Create helper class" to the Structure-tab / editor context menu, modeled on
   the AutoDocument "Document unit"/"Document it" items in `DragLint.Plugin.StructureForm.pas`;
   enablement predicate = the point-4 condition; spawns the CLI verb via `DragLintExe`; reloads the
   buffer. IDE live smoke deferred to user (as with prior IDE work).

## Non-goals / guards

- Do NOT overwrite an existing helper (create-only-if-missing).
- Do NOT fabricate ToString strings that aren't derivable -- RTTI names are ground-truth; a
  case-based custom-string mode needs a real source (a descriptions array), else don't offer it.
- Generated Object Pascal MUST compile + round-trip -- the testing plan's case #8 (a build+run
  round-trip) is the real gate, not text-matching.

## Execution flow (next session)

1. Reindex ORM3 to v14 (currently v13) if you want to query the real MSCTYPES enums live --
   `drag-lint index C:\Projects\DB\ORM3 --db C:\Projects\DB\ORM3\drag-lint.sqlite` (incremental).
   NOT required for the feature build (fixtures suffice); only for live validation against MSCTYPES.
2. brainstorm (resolve the 6 open questions) -> spec -> writing-plans -> subagent-driven-development.
3. Testing plan already written (investigation doc) -- fold it into the plan's per-task tests +
   the final build+round-trip gate.
