# FEATURE REQUEST -- an `Assigned` section in the hover popup and in auto-document

Raised **2026-08-01** by the user, at the start of the session that resumed Phase 3 at T6.
Queued: **implement soon**, after the current Phase 3 execution plan
(`docs/superpowers/plans/2026-07-24-autodocument-phase3-harvest-and-facts.md`) reaches a
committable point. NOT part of Phase 3's 17 tasks.

## The request, verbatim in substance

> In our description popup and autodocument info, add -- for objects and maybe even for any
> variable -- a section showing the code line where we create them or assign values to them.
> Just like we show them for `Result := ...`. Unless there are more than 5 (make it settable in
> settings). Call the section **`Assigned`**.

## What it means concretely

Today the doc/hover render already answers *"where does the value come from"* for exactly one
subject: the function result. `AnalyzeReturns` collects `Result := <expr>` sites and renders them
as the `<returns>` cases. The request generalises that to any **object or variable**:

- **Subject:** a field (`FFoo`), a local, a parameter, a global -- anything with a declaration the
  index already knows. "Objects" (class-typed) are the primary target; plain variables are the
  "maybe even" stretch and should be behind the same code path, not a second one.
- **Content:** the source lines that **create** it (`FFoo := TFoo.Create(...)`) or **assign** it
  (`FFoo := ASomething`, `FreeAndNil(FFoo)` is an assignment-shaped mutation worth considering).
- **Section name:** literally `Assigned` -- in the hover popup's structured facts block and in the
  generated DocInsight `<remarks>` (or its own tag, to be decided at design time).
- **Cap:** show at most **5** by default, and make the cap a setting.

## The cap already has a precedent -- follow it, do not invent one

`CalledFrom` solved the identical "cap the list, make it configurable" problem in Phase 1 T1.
Mirror it exactly rather than adding a new mechanism:

| concern | existing anchor |
| --- | --- |
| manifest key | `docs.max_callers` in `third_party/dll-win64/drag-lint.json` |
| manifest parse | `src/index/DRagLint.Index.Manifest.pas:437` (read), `:649` (validate `>= 0`), `:737` (write) |
| loader + default-on-failure | `LoadDocMaxCallers`, `src/cli/DRagLint.CLI.pas:1071` (default 5) |
| wired into options | `src/cli/DRagLint.CLI.pas:6916, 7060, 7111, 7388` |
| consumed / capped at render | `src/doc/DRagLint.Doc.Facts.pas:783-790` |
| MCP surface | `src/mcp/DRagLint.MCP.Server.pas:240, 778` |

So the new setting is **`docs.max_assigned`, default 5**, added the same way at the same six sites.
Note `Manifest.pas:609`'s warning: the partial-update path must not let writing one `docs.*` key
silently reset the others.

## Where the work lands

- **Fact collection:** `src/doc/DRagLint.Doc.Facts.pas` -- next to `AnalyzeReturns` /
  `AnalyzeReturnsOwner` (the latter's dispose-gate at ~line 1882 is the conservative-omission
  pattern documented in `docs/lint/2026-07-29-ownership-yield-finding.md`; the same conservatism
  question will come up here).
- **Render (document):** `src/doc/DRagLint.Doc.Document.pas`.
- **Render (hover / LSP popup):** the hover facts path -- the popup's structured facts block, same
  place the Phase 2 facts (complexity / reads-writes / covered-by / dfm-wiring / sql-tables /
  ownership) surface.
- **Storage question, to be settled at design time:** is `Assigned` an **index-time fact** (a
  `symbol_facts` column, like the Phase 2 facts -- means a schema bump and a reindex) or a
  **query-time** analysis (like the returns cases -- no schema change)? The returns precedent says
  query-time is possible; the hover path's latency budget may say otherwise.

## Open questions for the design pass

1. Scope of "any variable" -- locals only within their routine, or fields across the whole unit /
   descendant tree? Field assignment sites are the useful case and the expensive one.
2. Does the cap truncate silently or say "5 of 23"? `CalledFrom` renders a count when it truncates
   (`Doc.Facts.pas:783-790`) -- match that.
3. `FreeAndNil` / `Free` sites: part of `Assigned`, or a separate lifecycle line? The ownership
   fact already reasons about disposal.
4. Non-callable subjects: `Used by:` was added for types in Phase 3 T4; `Assigned` for a *type*
   has no meaning, so the section must be suppressed, not emitted empty (Phase 3 T3 established
   the omit-empty-tags rule -- follow it).

## Status

**Not started.** No branch, no spec, no plan. This document is the request of record.
