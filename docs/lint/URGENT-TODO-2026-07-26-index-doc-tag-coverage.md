# URGENT TODO -- doc-tag coverage is missing from the index

**Found:** 2026-07-26, during Auto-Document Phase 3 (branch `feat/autodoc-phase3`).
**Status:** Gap 1 (this doc's main subject) CLOSED by Task 3c (2026-07-27, commit -- see
git log). Gap 2 (`HasXmlTags` sniff) was already closed by T3b. **A new, narrower gap was
exposed by closing gap 1 -- see "Task 3c: what shipped" below, and its own status is OPEN.**

## The problem

`symbol_docs` *has* columns for all five tag types -- `exceptions_json`, `example_text`,
`seealso_json`, `since_text`, `deprecated` -- but they are **substantially under-populated**, so a
question like "which symbols carry a hand-written `<since>`?" cannot be answered from the index
and falls back to Grep.

### Measurement -- and a correction to an earlier draft of this file

An earlier version of this note claimed `<since>` and `<seealso>` were "mostly missing" from the
index, based on comparing index rows against a raw `grep` of `src/**/*.pas`. **That comparison was
contaminated and the claim was overstated.** Corrected here.

The grep counted every textual occurrence, including ones that are not documentation at all. Queried
from the index (`string_literals`), the tag texts appear as **string constants** -- engine emitters
and prose:

| Tag text | in `string_literals` | where |
| --- | --- | --- |
| `<since`     | 6 | `Doc.Regions.pas` emits it; `CLI.pas` `--help`; `MCP.Server.pas` prose; `Parser.DocComments.pas` regex |
| `<seealso`   | 3 | `Doc.Regions.pas` emits `<seealso cref="`; `CLI.pas` `--help` |
| `<exception` | 5 | emitters / prose |
| `<example`   | 3 | emitters / prose |
| `<deprecated`| 3 | emitters / prose |

So most of the grep hits were the engine's own emitters, not authored doc comments. Reindexing the
self-index with the T3b exe (2026-07-26, 1734 `symbol_docs` rows over 17,846 symbols) left the
counts **unchanged** at `<exception>` 12, `<example>` 0, `<seealso>` 2, `<since>` 3,
`<deprecated>` 1 -- confirming T3b's `HasXmlTags` fix did not move coverage, because the dominant
blocker is gap 1 below (no row is written at all), not parsing.

**What is therefore actually established:**

- The structural gap in gap 1 is **real and provable from the code** regardless of counts: a comment
  whose only tags are `<example>` / `<seealso>` / `<since>` yields **no `symbol_docs` row**.
- `<example>` has **0** rows in this repo's index.
- The **practical volume** of documentation lost to gap 1 in this repo is **not yet quantified** --
  the honest answer is "unknown", and the earlier table implied otherwise. Whoever picks this up
  should measure it properly (count authored `///` blocks whose only tags are those three) rather
  than trusting a text scan.

## Root cause -- two independent gaps, both already identified in Phase 3

1. **`TParsedDoc.HasContent` omits `ExampleText`, `SeeAlso` and `SinceText`.**
   `src/parser/DRagLint.Parser.DocComments.pas` -- the OR-chain is
   `(Summary<>'') or (Remarks<>'') or (ReturnsText<>'') or Params or Exceptions or Deprecated`.
   `src/core/DRagLint.Core.Indexer.pas:435` only writes a `symbol_docs` row when `HasContent` is
   True. So a comment carrying **only** `<example>` / `<seealso>` / `<since>` produces **no row at
   all** -- the symbol reads as entirely undocumented everywhere (index, `context` bundle, MCP,
   LSP hover, `HasDoc`).

2. **`Dispatch`'s `HasXmlTags` sniff did not recognize `<since>` / `<seealso>` / `<deprecated>` (nor
   `<value>`) as XML tags**, so such a comment was mis-dispatched to `ParseOneline` and never
   parsed as XML -- the fields arrived empty even when a row was written.
   **T3b (commit `2438fb4`) fixed the sniff.** The residual after that fix is gap 1.

## What to do

1. **DONE (Task 3c).** ~~Extend `HasContent`'s OR-chain~~ with `ExampleText`, `SeeAlso` and
   `SinceText`. **Do this carefully** -- Phase 3 already had one regression from widening this
   exact predicate. It ripples to at least six consumers: `Core.Indexer.pas:435` (writes the
   `symbol_docs` row), `Context.Bundler.pas:131` and `Resolver.TypeAt.pas:497` (`HasDoc`),
   `MCP.Server.pas:617` ("no doc comment"), `LSP.Server.pas:1031` and `LSP.Completion.pas:140`
   (hover / completion routing). Widening it for these three tags is *correct* -- a comment
   carrying an `<example>` IS documented -- unlike the blank-slot case that was reverted in T3
   round 2.
2. **DONE (Task 3c).** ~~Reindex~~ and re-run the table above. `<example>` went 3 -> 10 raw rows
   (0 -> 3 in the isolated "only this tag" shape the gap actually describes); see "Task 3c: what
   shipped" above for the full before/after and the honest C3 count.
3. **Partially open.** `MCP.Server.pas`'s `FormatDocAsJson` already surfaces `since`/`seealso_json`;
   `LSP.Server.pas`'s hover already surfaces `SinceText`/`ExampleText` (not `SeeAlso`);
   `Context.Bundler.pas`'s `## Doc` section surfaces none of the three. Still nobody's TODO --
   named precisely above so a future task can pick the exact gaps rather than re-discovering them.

## Task 3c: what shipped (2026-07-27)

Extended `TParsedDoc.HasContent`'s OR-chain in `src/parser/DRagLint.Parser.DocComments.pas`
(both `ParseXmlDoc` and `ParsePasDoc`; `ParseOneline`/`ParseLoose` checked and confirmed to need
no change -- they never populate the three fields at all) to also recognize `HasExampleTag`,
`Length(SeeAlso) > 0`, and `HasSinceTag` -- presence flags, not content tests (a content test on a
stripped view is what made `<since>` delete nested content in an earlier T3b round; see the code
comment for the full reasoning on why this widening does not repeat the T3-round-2 blank-slot
mistake).

All six named consumers verified deliberately:

- `Core.Indexer.pas:435` -- now writes a `symbol_docs` row for these three shapes (the fix).
- `Context.Bundler.pas:131` / `Resolver.TypeAt.pas:497` -- `HasDoc:= Doc.HasContent` reads the
  storage layer's `GetSymbolDoc`, which already sets `HasContent:= True` unconditionally whenever
  a row exists; both flip correctly with no code change, verified live via `drag-lint context`
  (the `## Doc` section now appears for a since-only symbol, previously absent).
- `MCP.Server.pas:617` -- stops returning `{"error":"no doc comment"}`; `FormatDocAsJson` already
  serializes `since`/`seealso_json` (though not `example_text` -- see below).
- `LSP.Server.pas:1031` -- hover routing now enters `RenderHoverMarkdown`, which already renders
  `SinceText` (a `> _Since: x_` badge) and `ExampleText` (a `## Example` fenced block) meaningfully;
  it does **not** render `SeeAlso` at all (checked directly in `DRagLint.Hover.Renderer.pas` --
  neither `RenderHoverMarkdown` nor `RenderHoverPlain` reference `ADoc.SeeAlso`).
- `LSP.Completion.pas:140` -- no behaviour change: the gate is `Doc.HasContent AND (CleanSummary
  <> '')`, and `CleanSummary` stays empty for a since/example/seealso-only comment regardless of
  `HasContent`, so completion's documentation preview correctly still shows nothing for this shape
  (that field only ever surfaces Summary/Returns text; unaffected either way).

A seventh site was found and checked: `Storage.SQLite.pas:2136`'s `UpsertSymbolDoc` has its own
internal `if not ADoc.HasContent then Exit;` guard. It reads the SAME already-widened field passed
through from the indexer's call (its only caller), so it inherits the fix automatically -- no code
change needed there.

**Routing ripple** (`ExistingHasAnyTag` in `Doc.Document.pas`, which ORs in `Existing.HasContent`
directly): confirmed via the idempotency sweep and `run_doc_p3_preserve_tags.ps1`, both re-run
before and after. Two symbols that used to need a two-cycle "additive-then-merge" dance to reach
their final form (`preserve_tags.TabSeparatedSeeAlso`, whose only tag is a bare `<seealso/>`, and
`preserve_tags.SinceWithNestedExample`, whose nested `<example>` trips `HasExampleTag` on the
unstripped parse) now reach it in one cycle -- a verified, non-destructive, purely-faster
convergence (both symbols' repair-path emission already round-trips `<seealso>`/`<since>`/
`<example>` verbatim, per T3b). The idempotency sweep's pinned `$aExpectedSettleAt2` set was
updated to drop `TabSeparatedSeeAlso` (the sweep's own comment explicitly anticipates this: "a
name DISAPPEARING is an improvement -- update the pin"); `run_doc_p3_preserve_tags.ps1`'s
explanatory comments (not its assertions, which were already robust to the timing change) were
corrected to match.

**Coverage measured from the index** (`C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite`, schema v18):
before this session's reindex, `exceptions_json`/`example_text`/`seealso_json`/`since_text`/
`deprecated` = 16/3/6/7/5 over 1781 `symbol_docs` rows (already drifted from this doc's earlier
12/0/2/3/1-over-1734 snapshot -- the self-index had gone stale relative to T3b's final commits,
unrelated to this task). After the fix + a self-index-only reindex: 22/10/12/13/10 over 1820 rows.
**Caveat:** part of this delta reflects the reindexer catching up on files whose mtimes predated
their last commit (confirmed via `git log`), not solely the `HasContent` widening -- e.g.
`deprecated` moved even though that disjunct was untouched. The clean, isolated signal is
`example_text` (3 -> 10, and `<example>` is structurally guaranteed to need this fix to move at
all) and the query below, which is immune to that confound.

**Honest C3 quantification, from the index** (not grep -- see this doc's own earlier correction
for why a text scan overstates this): a query for `symbol_docs` rows where summary/remarks/
returns_text/params_json/exceptions_json are all blank and not deprecated, but at least one of
example_text/seealso_json/since_text is populated -- i.e. "a comment whose ONLY tag is one of the
three" -- returns **9 rows, all 9 in test fixtures under `tests/autodoc/fixtures/docp3/`, 0 in
production `src/`**. The structural gap was real and is now closed; its practical volume in this
repo today is genuinely small (three of the nine are the new `indexcoverage.pas` fixture written
for this task's own TDD test).

### New finding: a narrower, pre-existing gap is now reachable through more doors

This doc's own "Related, lower priority" section (below) already documented, before this task,
that an **unmodeled tag** (`<value>`, `<typeparam>`, `<para>`, `<code>`, `<list>`,
`<permission>`, `<inheritdoc/>` -- no `TParsedDoc` field at all) is destroyed by `document
--apply`'s repair path when routed there, as a pre-existing, out-of-Phase-3-scope gap. Widening
`HasContent`/`ExistingHasAnyTag` adds three MORE conditions that route a comment into that same
repair path, so an unmodeled tag co-occurring with an `<example>`/`<seealso>`/`<since>`-only
comment (nothing else) now reaches the SAME pre-existing destruction one step earlier than before.

**Confirmed, reproduced, not fixed** (`tests/autodoc/run_doc_p3_valuetag_caller.ps1`,
`fixtures/docp3/valuetag_caller.pas`, symbol `HasValueAndExample`: `<value>Hand-written; must
survive.</value>` + `<example>Example text.</example>`, with a caller so the additive `Merged`
is non-empty): before Task 3c, `HasValueAndExample`'s only tag `HasContent` recognized was
`<example>` becoming `HasExampleTag` -- excluded, so `ExistingHasAnyTag` stayed False and the
FIRST apply took the safe fresh/additive-insert path (`"action":"created"`), leaving `<value>` and
`<example>` both untouched (this is exactly what this test asserts and was passing). After Task
3c, `HasExampleTag` is now part of `HasContent`, so `ExistingHasAnyTag` is True from the very
first parse -- the FIRST apply now takes the repair path (`"action":"extended"`), which deletes
`[Existing.StartLine..EndLine]` and re-inserts `Merged`; `Merged` preserves `<example>` (T3b/T3c
gave it a field and repair-path emission) but has **no representation for `<value>` at all**, so
`<value>` is silently deleted on the very first apply -- one cycle earlier than the same class of
destruction could already happen via any OTHER pre-existing `HasContent` trigger (a real summary,
a `<deprecated/>`, etc., all of which already routed to repair before this task).

**Blast radius, measured from the index, not assumed:** the C3 query above already shows 0
production-`src/` symbols carry only example/seealso/since with nothing else; cross-referencing
for an ADDITIONALLY co-occurring unmodeled tag narrows the risk further still. Today this
reproduces in exactly one place: the dedicated test fixture built to probe this exact boundary.

**Why this was not fixed in Task 3c:** a real fix needs the repair path itself to detect and
verbatim-preserve a tag type it has no field for (this doc's own pre-existing "Related, lower
priority" item, below) -- that is parser/`Doc.Regions.pas` work, not an `HasContent` OR-chain
edit, and touches the exact machinery (`Doc.Document.pas`'s repair-vs-fresh routing and the
delete-branch mechanics) Task 3c's own brief flagged as off-limits ("the single most
defect-prone area of this phase"). `run_doc_p3_valuetag_caller.ps1` was deliberately left
**failing** (not adjusted to expect the new destruction) so the regression stays visible rather
than silently accepted. Recommended as its own follow-up task.

## Related, lower priority

- **`YADF.sqlite` and `YADFOT.sqlite` are not in the index manifest**
  (`third_party/dll-win64/drag-lint.json`), so `resolve-dbs` never selects them and a consumer must
  pass `--db` explicitly. They live at `C:\Projects\YADF\YADF.sqlite` (v18) and
  `...\YADFOT.sqlite` (**still v17**). Adding them would make YADF questions index-answerable by
  default. The Phase 3 T17 rollout already has "reindex both YADF DBs" as a step.
- **Unmodeled tags are not parsed or stored at all**: `<value>`, `<typeparam>`, `<para>`, `<code>`,
  `<list>`, `<permission>`, `<inheritdoc/>`. These have no `TParsedDoc` field and no `symbol_docs`
  column, so they are invisible to the index *and* destroyed by `document --apply`'s repair path
  (pre-existing, not a Phase 3 regression). Closing that needs either parser work or verbatim
  raw-line preservation -- its own scope decision, deliberately left out of Phase 3. **Task 3c
  (2026-07-27) made this reachable through three more doors** (an unmodeled tag co-occurring with
  an example/seealso/since-only comment now also triggers it, one apply cycle sooner than before)
  -- see "New finding" above for the confirmed repro (`run_doc_p3_valuetag_caller.ps1`, left
  failing on purpose) and why it was not fixed here.
