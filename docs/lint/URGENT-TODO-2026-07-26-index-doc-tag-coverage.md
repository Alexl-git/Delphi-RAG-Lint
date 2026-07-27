# URGENT TODO -- doc-tag coverage is missing from the index

**Found:** 2026-07-26, during Auto-Document Phase 3 (branch `feat/autodoc-phase3`).
**Status:** Gap 1 (this doc's main subject) CLOSED by Task 3c (2026-07-27, commit -- see
git log). Gap 2 (`HasXmlTags` sniff) was already closed by T3b. Closing gap 1 exposed a
pre-existing repair-path defect through FOUR triggers and THREE distinct content-loss classes
(not just "unmodeled tags"). **All three loss classes CLOSED by Task 3f (2026-07-27) --
see "Task 3f: all three loss classes closed", below. The two known-defect pins this doc
created have been flipped to assert the fix.**

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
through from its caller, so it inherits the fix automatically -- no code change needed there.

**Two corrections to the Task 3c report's own exhaustiveness claims** (caught in review,
2026-07-27): `UpsertSymbolDoc` has **two** callers, not one as the report said --
`Core.Indexer.pas:435` and `tests/fixtures/T7_storage.dpr:37` (a DUnit-less standalone `.dpr`
storage round-trip check; harmless, it sets `Doc.HasContent := True` itself before calling, so it
never relied on the parser-computed value at all). And `Storage.SQLite.pas:2189`'s
`Result.HasContent := True` inside `GetSymbolDoc` is a **fifth** `HasContent` *assignment* site,
not counted in the report's "all four sites" self-review -- that review's "four" meant the four
**parser-side** sites that decide, from a raw comment, whether it counts as documented
(`ParseXmlDoc`/`ParsePasDoc` widened, `ParseOneline`/`ParseLoose` checked and correctly left
alone); `GetSymbolDoc`'s assignment is the READ-side reconstruction (unconditionally True whenever
a row exists, by construction correct for the widened shapes too) and should have been named
explicitly as the fifth, not folded silently into "four."

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

### New finding: FOUR triggers now route to the repair path, and THREE loss classes result

**Correction (2026-07-27 review):** the first version of this section framed the whole finding as
"unmodeled tags are destroyed," and scoped the recommended follow-up to "verbatim raw-line
preservation of unmodeled tags." **That framing is incomplete and would leave two of the three
loss classes below unfixed even after that follow-up shipped.** Only ONE of the three losses
involves an unmodeled tag at all; the other two destroy content in tags this task exists to
support. A reviewer built seven probe shapes; **all seven** flip from a cycle-1 `"action":
"created"` (safe) to `"action":"extended"` (repair) on the very first `document --apply`. Three
of them lose content. Read this section in full before scoping any follow-up task from it.

**The four triggers** (any one of these now makes `Existing.HasContent` -- and therefore
`ExistingHasAnyTag` -- True from the ORIGINAL parse alone, no longer needing a second apply cycle
to reach the repair path via an intermediate additive-then-merge step):

1. `HasExampleTag` (any `<example>`, Task 3c).
2. A standalone `<seealso cref="X"/>` (`Length(SeeAlso) > 0`, Task 3c).
3. `HasSinceTag` (any `<since>`, Task 3c).
4. **An INLINE `<see cref="X"/>` reference, undisclosed in the original Task 3c report.**
   `DRagLint.Parser.DocComments.pas` (`EnsureParserRegexes`): `RxSee` is
   `'<(?:see|seealso)\s+cref="([^"]+)"\s*/?>'` -- it matches `<see .../>` and `<seealso .../>`
   identically and matches ANYWHERE in the cleaned text, not just at the top level. So
   `Length(Result.SeeAlso) > 0` fires just as much on an inline `<see cref="X"/>` sitting inside
   prose or inside ANOTHER tag's body as it does on a standalone top-level `<seealso>`. The repo
   already maintains a SEPARATE field, `SeeAlsoIsInline` (parallel array, same index
   correspondence), specifically because `<see>` and `<seealso>` are different author-facing tags
   that render differently -- so the conflation for ROUTING purposes was a known distinction the
   Task 3c widening did not carry through to `ExistingHasAnyTag`.

**The three loss classes**, each independently reproduced (`t3c_lossprobe2.pas`, a throwaway
fixture: three procedures with a caller each, applied once with `document --qname --apply`):

1. **Unmodeled tag destroyed** (the originally-reported class). `<para>Body with an inline
   <see cref="Other.Thing"/> reference.</para>` -- reaches the repair path via trigger 4 above,
   and `<para>` has no `TParsedDoc` field at all, so the entire tag AND its body text are deleted;
   only the bare `<see cref="Other.Thing"/>` survives (re-emitted as if it were a standalone
   entry). Reproduced in the repo's own suite as
   `tests/autodoc/fixtures/docp3/valuetag_caller.pas`'s `HasValueAndExample`
   (`<value>` + `<example>`, trigger 1) -- see `tests/autodoc/run_doc_p3_valuetag_caller.ps1`,
   converted to a pinned-known-defect runner (below).
   ```
   BEFORE: /// <para>Body with an inline <see cref="Other.Thing"/> reference.</para>
   AFTER:  /// <see cref="Other.Thing"/>
   ```
2. **Multi-line `<example>` indentation flattened.** `<example>` IS one of the three tags this
   task exists to support, and code samples -- its normal content -- are routinely multi-line and
   indented. `EmitTagged`'s re-serialization does not preserve interior indentation:
   ```
   BEFORE: /// <example>
           ///   Foo := TBar.Create;
           ///     Foo.Run;
           /// </example>
   AFTER:  /// <example>Foo := TBar.Create;
           /// Foo.Run;</example>
   ```
   No unmodeled tag involved -- pure formatting loss in a tag T3b/3c already model, newly exposed
   because reaching the repair path at all now requires only ONE apply instead of two.
3. **Trailing author prose beside a modeled tag deleted, and a FABRICATED empty
   `<summary></summary>` appears in its place.**
   ```
   BEFORE: /// <since>1.0</since> Trailing prose the author wrote.
   AFTER:  /// <summary></summary>
           /// <since>1.0</since>
   ```
   Root cause, traced (not just observed): `MergeComment`'s per-tag "is this genuinely standalone"
   check calls `TDocRegions.BuildStandaloneFor(RawBlock, 'summary')`, which strips every OTHER
   preserved container (here, `<since>...</since>`) out of the raw block and then feeds the
   STRIPPED text back through a fresh `ParseXmlDoc` call to get `StandaloneSummary`. Stripping the
   `<since>` tag leaves the trailing prose ("Trailing prose the author wrote.") as the only text
   remaining, with NO tag left before it -- so `ParseXmlDoc`'s own "untagged text before the first
   tag becomes the summary" fallback (designed for genuine leading prose) fires on this orphaned
   trailing text and sets `StandaloneSummary.HasSummaryTag := True`. Back in the emission code,
   `if StandaloneSummary.HasSummaryTag and not IsEngineOwnedRegardlessOfContent(SummaryRaw) then
   EmitTagged('<summary>', SummaryRaw, ...)` fires -- but `SummaryRaw` (`AExisting.Summary`, read
   from the UNSTRIPPED original parse, by design, to avoid exactly the nested-content-deletion bug
   `<since>` had in an earlier round) is `''`, because in the unstripped text the `<since>` tag
   genuinely precedes that prose. The presence flag says "hand-written summary, empty" (so it is
   preserved as a blank slot, per the T3-round-2 rule); the content read says "nothing." Neither
   half is wrong on its own -- the interaction between "strip for presence, read unstripped for
   content" and "untagged trailing text becomes a phantom summary" is the gap. No unmodeled tag
   involved either.

**The mitigating fact, verified both ways (not assumed):** all three loss classes are **NOT a new
destruction class**. Rebuilt the pre-Task-3c exe (`git checkout 551c078 --
src/parser/DRagLint.Parser.DocComments.pas`) and re-ran the identical caller-bearing probe shapes
across two apply cycles: pre-Task-3c, cycle 1 = `"action":"created"` (safe, additive, original
comment completely untouched) and cycle 2 = `"action":"extended"` -- the SAME three losses already
happened, just one cycle later, via the pre-existing "additive-then-merge" mechanism (the inserted
facts `<remarks>` fence gets folded into the same scanned region on the next scan, which flips
`Remarks<>''` -- always part of `HasContent`, untouched by Task 3c -- and routes to repair). Task
3c did not create a new way to lose this content; it removed the ONE extra apply cycle of safety
margin these particular shapes used to have. Practically: `document --apply`, run once, is exactly
what the IDE's "Auto-Document Whole Project" menu action does -- that single run now destroys
content it used to leave alone.

**Blast radius, measured from the index, not assumed:** the C3 query above shows 0 production-
`src/` symbols carry the isolated three-tag shape at all (see the methodological caveat below for
why that query needs a post-fix-built index to mean anything). Cross-referencing for an
ADDITIONALLY co-occurring unmodeled tag, or for multi-line `<example>` content, or for trailing
prose beside a lone `<since>`/`<seealso>`/`<example>`, narrows the risk further still within THIS
repo today; none of it was checked against ORM3/YADF/other consumer repos, whose comments this
task's C3 query has never been run over.

**Not fixed in Task 3c; FIXED in Task 3f -- see "Task 3f: all three loss classes closed", below.**
The analysis in the rest of this paragraph is what scoped that task, and it held up: all three did
need the repair path itself to change, and the fix landed entirely inside `Doc.Regions.pas`.
All three loss classes need the repair path itself
(`Doc.Regions.pas`'s `MergeComment`, plus probably `BuildStandaloneFor`'s stripped-reparse
interaction with the untagged-prefix fallback for #3, and `EmitTagged`'s re-serialization for #2)
to change -- not an `HasContent` OR-chain edit, and touches the exact machinery (`Doc.Document.pas`
repair-vs-fresh routing, delete-branch mechanics) Task 3c's own brief flagged off-limits. A
follow-up task must be scoped to **all three loss classes**, not "unmodeled tags" alone -- #2
(indentation) and #3 (trailing prose / phantom summary) need fixing even if #1 (unmodeled tags)
is deferred further, since they destroy content in tags this task explicitly exists to support.

**Test posture (superseded by Task 3f -- kept for the record):**
`tests/autodoc/run_doc_p3_valuetag_caller.ps1` was converted (2026-07-27) to the same known-defect
idiom `run_doc_p3_idempotency_sweep.ps1`'s SWEEP D already uses -- a loud banner naming the defect
and this doc, PASSING assertions that pinned the CURRENT (bad) behaviour explicitly. **Task 3f
flipped that pin: it now asserts that `<value>` survives verbatim, exactly once, and the banner is
gone.** The same flip was applied to `run_doc_p3_preserve_tags.ps1`'s pinned "malformed seealso
fragment does not round-trip" assertion, which was the same loss class under a different name.
Loss classes #2/#3 had no committed coverage at all; Task 3f added
`tests/autodoc/fixtures/docp3/residual_lines.pas` + `tests/autodoc/run_doc_p3_residual_lines.ps1`,
which cover all three classes (two shapes for #1, including the mixed-line case), a control shape
that must NOT change, a 3-cycle fixed point per shape with the cycle-1 branch action pinned, and a
`--strip` round-trip in both directions.

**Idempotency-sweep gap, also fixed 2026-07-27:** the sweep pins md5 fixed points and `edits:0` on
later cycles, but (before this fix) pinned a cycle-1 **action string** only for `NoCommentAtAll`.
A fresh-to-repair branch flip that still converges to the same final content by cycle 2 was
therefore invisible to it. Three `idempotency_shapes.pas` symbols
(`SincePlusEmptyRemarks`/`ExamplePlusEmptyRemarks`/`SeeAlsoPlusEmptyRemarks`) silently changed
branch under the Task 3c widening (cycle 1: `created` -> `extended`) without the sweep or the
original Task 3c report noticing -- confirmed safe (same non-destructive mechanism as
`TabSeparatedSeeAlso`, not one of the three loss classes above, since none of these three carry
multi-line content, trailing prose, or an unmodeled tag), but genuinely unpinned. SWEEP C now pins
the cycle-1 action for all eight `*PlusEmptyRemarks`-family shapes (six "CRITICAL" + two
"CONTROL"), so a future branch flip is visible instead of silent.

### Task 3f: all three loss classes closed (2026-07-27)

**All three are fixed.** `TDocRegions.MergeComment`'s repair path now carries through, verbatim,
every line of the existing region it cannot fully account for. The mechanism is one new private
helper, `TDocRegions.SplitResidualLines`, plus ~20 lines of wiring in `MergeComment`; nothing in
`Doc.Document.pas` changed at all, and `RegionFullyEngineOwned` / `IsFenceOnlyRemarksSpan` /
`CommentLinesContain` / the delete-branch gating were **not touched**.

**The rule is LINE-LEVEL OWNERSHIP: the engine owns a line only when it can represent everything
on it.** `SplitResidualLines` marks the character spans the emitter re-emits (the eight
`PRESERVED_VERBATIM_CONTAINERS`, the self-closing `<see>`/`<seealso>`/`<deprecated/>` forms, the
engine's own `<!-- drag-lint ... -->` markers, and the untagged leading run `ParseXmlDoc`'s own
fallback turns into the summary), then calls any line with unaccounted non-whitespace *residual*.
Every span that touches a residual line is **retracted**, transitively to a fixed point, so nothing
on a residual line is ALSO re-emitted from the model. `MergeComment` then re-parses only the
accounted lines (`Eff`) and drives every existing gate off that; the residual lines are re-emitted
verbatim, in source order, after every modeled tag and before the facts `<remarks>` block.

Why the two rejected alternatives are wrong, both reproduced:
* re-emitting only the *unaccounted characters* of a mixed line mangles the author's prose exactly
  the way reading `<deprecated>`'s message from a stripped view once did ("Added in  and still
  valid.") -- `<para>Body with an inline <see cref="X"/> reference.</para>` would come back as
  `<para>Body with an inline  reference.</para>`;
* emitting the whole line but NOT retracting its spans duplicates every tag on it -- **unboundedly**
  for `<see>`/`<seealso>`, whose parser regex is a plural `.Matches`.

Per loss class:
1. **Unmodeled tag** -- nothing on the line is accounted for, so the whole line is carried through.
   Covered by the flipped pins in `run_doc_p3_valuetag_caller.ps1` (`<value>`) and
   `run_doc_p3_preserve_tags.ps1` (the malformed cref-less `<seealso>`), and by
   `ValueBesideSummary` / `ParaWithInlineSee` in the new `residual_lines.pas` fixture.
2. **Multi-line `<example>` indentation** -- a multi-line `<example>` that is not nested inside
   another container is deliberately treated as unaccounted and handed back verbatim. It IS modeled,
   but the engine cannot re-serialize a code sample without destroying its indentation
   (`StripXmlDocPrefix` TrimLefts every line before `ExampleText` is even captured, and `EmitTagged`
   Trims every continuation line), so verbatim is the only faithful option. A NESTED multi-line
   `<example>` stays accounted, so shapes like `SinceWithNestedExample` are untouched.
3. **Trailing prose / phantom `<summary>`** -- the prose shares its line with the modeled tag, so
   the line is residual, the `<since>` span is retracted, and the line is emitted verbatim. The
   phantom summary disappears as a consequence, not as a separate fix: the line that produced the
   orphaned trailing text is no longer part of the text `BuildStandaloneFor` reparses at all.

**Deliberate conservatism:** when the carried-through lines are the ONLY thing there would be to
write, `MergeComment` returns `''` and the region is left completely untouched. That keeps the
`Merged=''` branch's own `RegionFullyEngineOwned` guard reachable and exercised by the fixture that
covers it (`unhandledtags.HasValueTag`, still byte-identical after an apply) instead of quietly
bypassing it.

**Known residuals, deliberately NOT closed by Task 3f:**
* Tag ORDER is not preserved. The emitter has always written tags in one fixed order regardless of
  the order the author used, and the carried-through block sits at one derived position. Content
  round-trips through `--strip` exactly; relative order does not, for shapes whose source order
  already differed from the emitter's.
* SWEEP D's two shapes (`preserve_tags.DeprecatedWithNestedReturns` /
  `ExampleWithNestedRemarks`) are a DIFFERENT defect class -- the unkeyed singular-match residual,
  which needs parser position-tracking. Their lines are fully accounted for, so Task 3f is inert on
  them and their pins are unchanged and still assert the defect.
* Unmodeled tags are still not PARSED or STORED (no `TParsedDoc` field, no `symbol_docs` column), so
  they remain invisible to the index, `context`, MCP and hover. Task 3f makes `document --apply`
  stop destroying them; it does not make them queryable.

### Methodological caveat for the C3 query and any reuse of it

The C3 query (above) only returns a meaningful count against an index built by a **post-fix**
exe. Against a **pre-fix** index the affected `symbol_docs` rows do not exist at all (that is the
entire bug this task closes), so the identical query returns a false **0** -- indistinguishable
from "genuinely no such symbols exist." Confirmed directly: the query was run against this
session's pre-fix baseline snapshot and it also returned 0, for the wrong reason (no rows, not "no
matching shape among existing rows"). **Do not reuse this query against the ORM3/library DBs
until they are reindexed with a post-fix exe** -- per the user's 2026-07-26 decision those DBs stay
on the old schema/exe until the structure is final, so the query would currently read as "0
affected symbols" there regardless of the true count.

### Corrected baseline figures (2026-07-27 review)

The original Task 3c report's battery figures did not reconcile and have been re-established here
by direct, repeated measurement (`git ls-files` / `Glob` / `find`, three independent methods, all
agreeing):

| | autodoc | autotest | total |
|---|---|---|---|
| Tracked (`git ls-files`) | 44 | 65 | **109** |
| On-disk | 44 | 67 | **111** |
| Untracked | 0 | 2 | **2** |

**Correction (Task 3f, 2026-07-27, direct recount at HEAD `f668031` before any Task 3f file was
added):** the `autotest` figures above are each one LOW. `git ls-files tests/autotest/*.ps1`
returns **66**, not 65, and `Get-ChildItem` returns **68**, not 67. The untracked count of 2 is
right, and both named files are right; only the totals were off. Correct baseline:
**tracked 110 = 44 + 66; on-disk 112 = 44 + 68.** Task 3f adds one runner
(`tests/autodoc/run_doc_p3_residual_lines.ps1`), taking on-disk to **113** and tracked to **111**
once committed.

The 2 untracked runners are both in `tests/autotest/`: `run_hover_callsite.ps1` and
`run_typeat_generic_member.ps1`. Both are real, substantial (133 and 198 lines), self-hermetic
regression tests for a PRIOR, unrelated session's work (LSP hover call-site resolution and
generic/inherited member resolution -- matches the "LATEST-63" hover session in the project's own
memory notes), not scratch. Both currently **PASS**. Left uncommitted here, deliberately -- not
this task's work, and the established pattern in this repo/phase is that the user holds
commit/push for prior-session work; committing them as a side effect of an unrelated task would be
its own scope creep. Flagged here so they are not mistaken for abandoned or broken.

**The true red set, re-verified 2026-07-27** (on-disk total = 111):

- `tests/autotest/run_smoke.ps1` -- **pre-existing, unrelated to this task.** Uses the **Win32**
  exe (`third_party/dll-win32/drag-lint.exe`), which this task never builds or touches (only Win64
  is built/deployed here). Current concrete symptoms: a `--version` string mismatch (test expects
  `0.46.0-alpha`, the stale Win32 binary reports `0.86.0-alpha` -- many versions behind) and an LSP
  `initialize` timeout (`result=TIMEOUT_INIT`), which then cascades into 3 more LSP-smoke failures
  downstream of it. 5 of 20 checks fail. Needs a Win32 rebuild to investigate further; out of this
  task's scope.
- `tests/autotest/run_fresh_findings.ps1` -- **flaky, not attributable to this task.** A reviewer's
  run showed `[FAIL] H2219 stored for the unused private method`. Re-run 4 times in this session
  (1 as part of the full battery, 3 standalone reruns), all 4 **PASS**, including that exact check.
  Classified as flaky in the same family as `run_manifest.ps1` (already documented as such) --
  plausibly timing-sensitive around its own `dcc64` subprocess spawn/compile step. Not
  root-caused here; re-run before trusting either a red or a green result from a single pass.
- `tests/autodoc/run_doc_p3_valuetag_caller.ps1` -- this task's regression, now converted to the
  pinned-known-defect idiom (PASSES again, loudly, as of 2026-07-27 -- see "New finding" above).

So, against the 109 TRACKED runners: 106 reliably pass, 1 reliably fails
(`run_smoke.ps1`, pre-existing/unrelated), 1 is flaky (`run_fresh_findings.ps1`,
pre-existing/unrelated), 1 (`run_doc_p3_valuetag_caller.ps1`) is a pinned known-defect that
currently passes. Against the 111 ON-DISK runners, add the 2 untracked, both currently passing:
108 reliably pass, 1 reliably fails, 1 flaky, 1 pinned-known-defect-passing.

## Related, lower priority

- **`YADF.sqlite` and `YADFOT.sqlite` are not in the index manifest**
  (`third_party/dll-win64/drag-lint.json`), so `resolve-dbs` never selects them and a consumer must
  pass `--db` explicitly. They live at `C:\Projects\YADF\YADF.sqlite` (v18) and
  `...\YADFOT.sqlite` (**still v17**). Adding them would make YADF questions index-answerable by
  default. The Phase 3 T17 rollout already has "reindex both YADF DBs" as a step.
- **Unmodeled tags are not parsed or stored at all**: `<value>`, `<typeparam>`, `<para>`, `<code>`,
  `<list>`, `<permission>`, `<inheritdoc/>`. These have no `TParsedDoc` field and no `symbol_docs`
  column, so they remain invisible to the index, `context` bundles, MCP and hover. **Task 3f
  (2026-07-27) fixed the DESTRUCTION half of this** -- `document --apply`'s repair path now carries
  such a tag through verbatim (see "Task 3f: all three loss classes closed", above), along with the
  other two loss classes ("New finding"). What is still open is only the QUERYABILITY half: giving
  these tags a parsed field and an index column so they can be searched. That is a separate,
  additive change (new columns, schema bump, indexer + renderers) with no destruction risk behind
  it any more, so it is no longer urgent.
