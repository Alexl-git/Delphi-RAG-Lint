# Autodoc convergence, `refs.receiver_text` (schema v20), and cross-DB traversal

Date: 2026-08-10
Status: DIAGNOSED (causes proven) + DESIGNED (not yet implemented)
Owner ruling: reproducibility is the acceptance gate -- "if autodoc can revert back to 0
for cases where there was no original doc from user, then the feature works correctly and
every new autodoc run is a reproducible result."

---

## 1. Why the first autodoc pass made lint WORSE

Measured, whole-repo, `lint-all` before vs after the 1,316-edit autodoc pass:

| | before | after | delta |
|---|---|---|---|
| total findings | 3,321 | 4,190 | +869 |
| `doc-drift` | 573 | 867 | +294 |
| `doc-param-no-description` | 0 | 574 | +574 |

Every other rule was byte-identical, so the whole regression came from the doc pass.

Within `doc-drift`, the message shapes moved like this:

| message | before | after |
|---|---|---|
| managed facts block is out of date | 1 | 514 |
| signature param X has no `<param>` tag | 387 | 171 |
| function returns a value but has no `<returns>` | 179 | 177 |

### Cause 1 -- autodoc ran against a STALE index (the dominant cause)

The pipeline order was `autodoc -> build -> reindex -> lint-all`. Facts were therefore
computed from a DB that predated recent source changes, and then validated by `lint-all`
against a freshly reindexed DB. The two disagreed 514 times.

PROVEN on `DRagLint.Doc.Facts.pas`: the pass wrote

    Complexity: 73 (cyclomatic, outer body), 813 lines (full implementation)

while the lint rule -- which shares the exact same formula by construction
(`CyclomaticCountDecisions`, used by both `TAstChecker.CyclomaticOf` and the
Auto-Document Complexity fact) -- reports **75**. Running the cyclomatic rule over the
pre-doc (`HEAD`) file and the post-doc file gives **75 for both**, so comments do not
change the metric and `73` was simply a wrong number computed from stale line spans.

**Fix: reindex FIRST.** `reindex -> autodoc -> reindex -> lint-all`. No code change.

### Cause 2 -- RETRACTED. There is no second cause.

An earlier draft of this note claimed a second, independent cause: that `BodyLoc`
(`Result.BodyLoc := ASym.ImplEndLine - ASym.ImplStartLine`, raw span arithmetic, comment
lines included) was self-referential, because autodoc would write doc blocks onto NESTED
routines whose lines land inside the enclosing routine's span -- so documenting a unit
would inflate the very line count being documented (813 -> 839).

**That was wrong, and it was disproven by building the fixture that should have shown
it.** `tests/autodoc/fixtures/doc_idem_unit.pas` has an outer routine with two nested
routines and a cyclomatic complexity of 16, above the `docs.complexity_min` threshold of
10, so the `Complexity: N (cyclomatic, outer body), M lines (full implementation)` fact is
genuinely emitted. Result:

* the nested routines get NO doc blocks of their own -- `document --unit` does not
  document nested routines, so nothing inserts lines inside an implementation span;
* `BodyLoc` is therefore stable across passes;
* `run_doc_idempotent_unit.ps1` converges to **0 edits** on pass B.

So BOTH numbers in the real file -- complexity `73 -> 75` AND lines `813 -> 839` -- have
the single explanation in Cause 1: they were computed against an index that predated the
source. The engine IS reproducible when the index matches disk. `BodyLoc` needs no change.

Keeping the retraction on the record because the fixture is the evidence, and the next
person to see `813 -> 839` will reach for the same wrong explanation.

### Cause 1b -- the REAL source of the 514: drift regenerated under different options

Reindexing first drove autodoc to a fixed point -- pass A applied **2** edits (down from
1,316) and the pass-B dry run reported **0 pending edits across 0 files**, which is the
owner's acceptance gate met. Yet `lint-all` STILL reported 514
`doc-drift: managed facts block is out of date`.

Autodoc and the linter therefore disagreed about the same blocks, reading the same index.
`document --unit` on `DRagLint.Core.Interfaces.pas` said "120 public decl(s), nothing to
document" while `lint-all` flagged that one file **80** times.

The staleness test regenerates the block and compares
(`DRagLint.Doc.Drift.TDocDrift.Analyze`):

    Facts := TDocFactsBuilder.Build(AStore, ASym);          // <-- no options
    Fresh := TDocRegions.RenderFactsBlock(Facts, '', IncludeRet);
    if CollapseAllWhitespace(CurBlock) <> CollapseAllWhitespace(Fresh) then ... stale

and `Build`'s signature defaults `AIncludeSeeAlso` to **False**:

    class function Build(const AStore: ISymbolStore; const ASym: TSymbol;
      AIncludeSeeAlso: Boolean = False; ...

while the DOCUMENTER passes `AArgs.DocSeeAlso`, which defaults to **True** ("now the
default"). So `document` writes blocks WITH `<seealso>` and the checker regenerates them
WITHOUT -- the compare measures the option difference, not drift. 651 of the 908 managed
blocks in `src/` carry `<seealso>`, and 514 of those fall in the 97 files `lint-all`
scans.

This is a checker/writer split introduced by the "seealso ON BY DEFAULT" change, which
updated the writer and not the checker.

**Fix (implemented 2026-08-10):** thread the flag rather than flip a default, so
`--no-seealso` stays correct in both directions --
`TDocDrift.Analyze(..., AIncludeSeeAlso: Boolean = True)` ->
`TDocLintRules.RunDocDrift(AStore, AIncludeSeeAlso)` -> both CLI call sites
(`DoLintAll`, `DoLintProject`) pass `AArgs.DocSeeAlso`.

**A wrong turn worth recording:** an intermediate step "disproved" the seealso hypothesis
by running `drag-lint lint <file> --rule doc-drift` and getting 0 findings on files that
carry `<seealso>`. That test was invalid -- `doc-drift` is a STORE-WIDE rule and is not in
the single-file `lint` verb's rule list at all, so the command was erroring with
`unknown rule "doc-drift"` and the 0 was the error, not a clean result. It briefly led to
the conclusion that `lint-all` was the broken path. Check that a rule actually RAN before
reading its count as evidence.

### Note: `doc-param-no-description` is NOT a bug

`DRagLint.Doc.Regions.EmitEngineParam` emits a `<param>` for every signature parameter by
ruling D-3 (structure always; meaning only where the source states it), and the LINTER
reports the ones lacking prose. That is the designed division of labour, recorded on that
routine. The 574 findings are the linter doing its job.

The owner's 2026-08-10 ruling refines it: **the tag must reflect the CURRENT situation,
including the correct TYPE**, because the doc-comments are also generated into `doc`/HTML
help files where a complete parameter table is the deliverable -- not merely a tooltip.

---

## 2. Design: `<param>` / `<returns>` carry the declared type

`symbols.signature` ALREADY stores the full parameter list with types and the result type:

    (const AName: string; ACallSitesOnly: Boolean = True; AReachableToFileId: Int64 = 0): TArray<TResolvedCaller>

so this needs **no schema change**. `TDocFacts.ReturnType` already exists.

Plan:

1. `DRagLint.Refactor.DocStub.ParseParamNames` currently discards the type ("Strip type
   after colon"). Add a sibling `ParseParamDecls` returning `(Qualifier, Name, TypeText)`
   and have `ParseParamNames` delegate to it, so there stays ONE extractor -- the unit
   already documents that a second parser is how the name half and the meaning half end
   up disagreeing.
2. Add `ParamTypes: TArray<TDocParamNote>` to `TDocFacts`, populated in
   `TDocFactsBuilder.Build` from `ASym.Signature`.
3. `EmitEngineParam` falls back to the declared type when no harvested note exists, so an
   undocumented parameter renders as `<param name="AName">const string</param>` rather
   than an empty tag. Stale params are already deleted and new ones inserted (see the
   `param no longer exists` path in `DRagLint.Doc.Regions`).

This satisfies the ruling, improves generated help, and incidentally clears the 574
`doc-param-no-description` findings because the tag is no longer description-less.

**Idempotence risk to respect:** `ParseParamNames` carries a scar comment -- a malformed
name "was never equal to itself on the next run, so the block was rewritten forever".
Whatever type text is emitted must be byte-stable across runs, so it must come from the
indexed signature verbatim, never re-formatted.

---

## 3. Design: `refs.receiver_text` -- schema v20

### The defect

`TQueryRule.Create` is constructed in ONE place yet was documented with 77 callers
(5 shown + 72 more). The claimed callers include `DRagLint.CLI.PrintReferences`, which
contains only:

    JArr := TJSONArray.Create;
    JObj := TJSONObject.Create;
    JObj.AddPair('id', TJSONNumber.Create(R.Id));

`TJSONArray` / `TJSONObject` / `TJSONNumber` are RTL types that are NOT in this project's
DB (RTL lives in `library-Win64.sqlite`). The call therefore resolves to nothing and lands
in the unresolved-name bucket, which keys on the LEAF NAME only:

    WHERE r.name_text = :n COLLATE NOCASE
      AND r.id NOT IN (SELECT ref_id FROM call_edges)

The `refs` table is `(id, symbol_id, file_id, kind, name_text, start_line, start_col,
end_line, end_col, enclosing_symbol_id)` -- there is **no receiver column**. The qualifier
`TJSONArray` is discarded at index time, so by doc-build time the information needed to
tell these apart no longer exists. Every project constructor named `Create` (35 of them)
matches every unresolved `Create(` site in the corpus.

An ambiguity gate exists and works, but has a deliberate escape:

    NameUnambiguous := (not CanBeCallTarget(ASym.Kind))
                    or (Distinct.Count > 0)
                    or LeafNameIsUnambiguous(AStore, LastSeg(ASym.QualifiedName));

`Distinct.Count > 0` means "at least one caller resolved, so the list is MIXED and the
` ?` marker will warn the reader". That reasoning holds at the scale the fixture tests
(`calledfrom.pas`: 1 real + 1 marked guess). It does not hold at 1 real + 76 guesses.
Corpus-wide: 25 of 513 caller lists carry `(+N more)` with N >= 20; 19 of them N >= 50.

### The fix

Add `refs.receiver_text TEXT` (schema v19 -> **v20**), populated at index time with the
qualifier as written at the call site (`''` for a bare/unqualified call). Additive
`ALTER` in `Migrate()`, exactly as v13 (`enclosing_symbol_id`) and v17 (`prop_access`)
were retrofitted. Requires a reindex with `--force-reparse` to populate.

The bucket filter then becomes exact rather than statistical:

> attribute an unresolved `Create` ref to `TQueryRule.Create` only when `receiver_text`
> is EMPTY (a bare `Create` / `inherited Create`) or NAMES `TQueryRule` (or an ancestor
> or alias of it).

`TJSONArray.Create` is then excluded outright -- not capped, not marked ` ?`, simply and
correctly absent. No display cap and no proportional heuristic is needed, because nothing
is being guessed any more.

**Open question to settle before implementing:** how the indexer represents the receiver
for `inherited Create`, `Self.Create`, a fully qualified `System.JSON.TJSONArray.Create`,
and construction through a class-reference variable (`FClass.Create`). These decide
whether "empty receiver" is a safe allow-rule or needs its own handling.

---

## 4. Design: cross-DB traversal to the Library index

Storing the receiver makes the bucket precise. Resolving it against the Library DB makes
the fact RICH -- and is the better long-term answer, because it converts an unresolved ref
into a correctly-resolved one instead of merely excluding it.

`TJSONArray.Create` resolved against `library-Win64.sqlite` yields
`System.JSON.TJSONArray.Create`, which is not a project symbol, so it leaves
`TQueryRule.Create`'s bucket by construction -- no filter required. It also enables real
`Calls:` facts and result types for RTL/DevExpress/Spring targets.

What exists already:

* the doc engine takes `AExtraStores` (multi-DB fan-out) and already name-buckets across
  them, gated on the leaf name being unambiguous in BOTH stores;
* `DRagLint.Plugin.DbResolver` already prefers `library-Win32.sqlite` /
  `library-Win64.sqlite` with a legacy `drag-lint-library.sqlite` fallback;
* the manifest can resolve DBs per platform (`resolve-dbs --platform`).

What is missing: cross-DB lookup at **resolve** time (the call resolver runs against one
DB when building `call_edges`). That is the heavier half and should be specified before
it is written.

The Library platform DBs must also be rebuilt at v20 so `receiver_text` exists there too.

---

## 5. Order of work

1. Reindex-first pipeline ordering (no code) -- this is the WHOLE of cause 1, and cause 1
   is the whole defect.
2. DONE: `tests/autodoc/run_doc_idempotent_unit.ps1` + `fixtures/doc_idem_unit.pas` lock
   convergence at `--unit` scale with an emitted `Complexity:` fact. The pre-existing
   `run_doc_idempotent.ps1` locks one symbol (`--qname doc_generate.Add`) in a two-symbol
   fixture, which is why a corpus-scale failure could slip past it. The new test is GREEN,
   which is itself the evidence that the engine is reproducible.
3. `<param>` / `<returns>` carry declared types.
4. `refs.receiver_text` (v20) + the receiver-aware bucket filter + `--force-reparse`.
5. Rebuild Library platform DBs at v20.
6. Cross-DB traversal at resolve time.
7. Docs: schema version + indexing architecture. NOTE: the "~43 files name deleted DBs"
   figure was an OVERCOUNT -- `SCAN-DATABASES.md` and `INDEXING-AND-DB-ARCHITECTURE.md`
   already carry correct "these were DELETED" notices, and `docs/lint/BACKLOG.md`'s hits
   are all dated session-log entries that are historical record and must NOT be rewritten.
   The genuinely stale, user-facing one was `docs/INSTALL.md` (fixed 2026-08-10: it told a
   new user to build the retired single-file `drag-lint-library.sqlite` instead of the
   per-platform `library-Win32/Win64.sqlite`).
