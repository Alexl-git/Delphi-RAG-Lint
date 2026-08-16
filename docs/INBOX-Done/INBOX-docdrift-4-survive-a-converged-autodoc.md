> # CLOSED 2026-08-16 (session 22) -- both halves accounted for.
>
> The 6 survivors split exactly as the session-21 measurement said:
>
> * **3 were `exception-cref-transitive-raise`** -- FIXED (one-hop callee
>   resolution). `DRagLint.FormsMap.GenerateFormsCsv` now yields zero findings.
> * **3 were the `TreeSitter.pas` "managed facts block is out of date" shape**,
>   which this note characterised as *"the doc WRITER and the doc CHECKER
>   disagree about the same block"*.
>
> Re-measured after reindexing: the checker reports `ddFactsBlockStale` on
> `TTSNodeHelper.Child` (:970), `TTSNodeHelper.NamedChild` (:1026) and
> `TTSNode` (:206) -- and `document` DOES now produce an edit for each. **Writer
> and checker agree.** These are ordinary pending regeneration, not a
> disagreement, and running autodoc over `third_party\delphi-tree-sitter` clears
> them.
>
> The likely reason they agree now is the caller-list fix landed in the same
> session ([[INBOX-autodoc-caller-list-fabricates-callers-for-common-method-names]]):
> those three blocks carried the fabricated 59-entry `Called from:` list, so the
> writer previously regenerated the same wrong content and reported convergence
> while the checker kept flagging it. With the fabricated list suppressed the
> writer now emits a genuinely different, shorter block.
>
> **Not applied here on purpose** -- `third_party\delphi-tree-sitter` is vendored
> source, and rewriting vendored files is a separate decision for the owner.

> **MEASURED 2026-08-16 (session 21). CONFIRMED, count is 6 not 4, and HALF of it is a different note.**
>
> Ran `document --project` -> reindex -> `lint-all` three times on drag-lint's own source:
>
> | round | autodoc | doc-drift |
> |---|---|---|
> | 1 | 22/1031 decls, 44 edits applied | 6 |
> | 2 | **nothing to document** | 6 |
> | 3 | nothing to document | 6 |
>
> So autodoc CONVERGES on the first pass -- no oscillation, which is what the convergence guard exists to catch -- and six findings survive it.
>
> **They are two unrelated kinds, and the note treats them as one:**
>
> * **3 x `managed facts block is out of date` in `TreeSitter.pas`.** The CHECKER says stale while the WRITER says *""nothing to document""*. Two components disagreeing about the same block -- this is the real content of this note.
> * **3 x `documented <exception cref="Exception"> but the body never raises it""`** (`Project.Resolver` x2, `FormsMap` x1). **These are NOT this note's defect** -- they are `INBOX-exception-cref-transitive-raise`, now confirmed with a worked example: `FormsMap.pas:76` documents the SINGULAR `GenerateFormsCsv` overload (declared `:95`), whose implementation at `:1561` is a one-line delegation to the array overload, and the `raise Exception.Create` lives in THAT overload at `:1545`. The tag is correct; the checker only inspects the routine's own body.
>
> **Fixing the transitive-raise checker would take this note from 6 to 3** and leave a much sharper question: why do the writer and the checker disagree on three TreeSitter.pas blocks?

# 4 `doc-drift` findings survive an autodoc run that reports "nothing to document"

Observed 2026-08-14, LoopZero round 2 on drag-lint's own source, immediately
after `document --project` applied 820 edits and then reported
`1281 public decl(s), nothing to document`.

    src\project\DRagLint.Project.Resolver.pas:231:7  documented <exception cref="Exception"> but the body never raises it
    src\project\DRagLint.Project.Resolver.pas:256:7  (same)
    src\forms\DRagLint.FormsMap.pas:75:1             (same)
    src\refactor\DRagLint.Refactor.EnumHelper.pas:236:5  managed facts block is out of date

## Three of them are NOT a disagreement -- do not "fix" them together

The three `<exception cref="Exception">` findings are about a HAND-WRITTEN tag.
Autodoc owns the managed facts block between the `drag-lint:auto` fences and
nothing else, so "nothing to document" and "this hand-written exception tag is
wrong" are statements about different regions of the same comment. Both are
true. The finding is arguably correct and wants a human to delete or correct the
tag; it is not repairable by `--fix` and should not be made so.

Worth checking separately whether the finding itself is right: `<exception>` on a
routine that delegates to something which DOES raise is a defensible doc, and
this rule cannot see through a call. Sample before acting.

## NARROWED 2026-08-14: it is CHECKER-SIDE, both writer paths agree

Re-measured after the empty-render fix, with the repo freshly reindexed and
autodoc converged:

    document --qname DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate
      -> doc: up to date (no change)
    document --project src\cli\drag-lint.dproj
      -> doc: 1282 public decl(s), nothing to document
    lint-all
      -> EnumHelper.pas:236:5  doc-drift: managed facts block is out of date

So the project-scoped writer and the qname-scoped writer AGREE the block is
current, and only `TDocDrift.Analyze` disagrees. That eliminates the
"project-scoped and qname-scoped paths disagree" hypothesis recorded below and
moves the whole search to the CHECKER's regeneration.

There is precedent for exactly this and it names the mechanism: `9414826`, where
the repair path called `BuildFor`'s two-argument overload, which hardcodes
`AIncludeSeeAlso := False` while the checker defaults it True -- the checker saw
a block WITH seealso, called it stale, and the repairer emitted nothing. Look
for the same shape in the OPTIONS the checker passes: `AIncludeSeeAlso`,
`MaxCallers`, `MaxReturnCases`, `ComplexityMin`.

**Two concrete oddities in this particular block, either of which could be the
thing that does not round-trip:**

1. Its `Returns:` line is full of Delphi string literals with embedded quotes:

       /// Returns: Default(TEnumHelperGen); Ord(Self); GetEnumName(TypeInfo(' + EnumName + '), Ord(Self)); ''' + M + '''; ''''; ...

   `'''` and `''''` are exactly where a parse -> render round-trip loses or gains
   a character, and the checker compares TEXT.

2. Its `Calls:` line ends with an English word:

       /// Calls: Default, ...TEnumHelperRefactoring.Generate.EmitFromCase, so

   `so` is not a callee. The same shape appears in `Doc.SharedFacts` after this
   session's edits (`Calls: defect, ...`), so the callee extractor is picking
   words out of PROSE -- a separate defect worth its own note, and possibly the
   one that makes this block unstable.

Start with (1): it is testable in one edit by simplifying that routine's return
expressions in a scratch copy and re-running lint-all.

## The FOURTH one is the real defect

`EnumHelper.pas:236` says **managed facts block is out of date** -- that IS the
engine's own region, so the writer and the checker disagree about the same
bytes. This is the class that produced the 514 false doc-drift findings (checker
regenerating without `<seealso>`), the `AUTO_TYPE` ownership marker, and the
implementation-section scope fix. Each time, the four things they must agree on
were OPTIONS, OWNERSHIP, SCOPE and PROTECTION.

One lead, unverified: the block immediately above (the `Resolve` declaration,
line 222) ends its `Called from:` line with a ` ?` uncertainty marker --

    /// Called from: ...TEnumHelperRefactoring.Build (...), DRagLint.CLI.DoIndex (DRagLint.CLI.pas) ?

and `JoinRefs` emits ` ?` only on a MIXED-confidence list. If the writer and the
checker disagree about whether that marker belongs, the block round-trips
differently through each path. Check whether `document --qname` on the symbol at
236 proposes an edit; if it does, the project-scoped and qname-scoped paths
disagree, which is a narrower and more tractable bug than it looks.

## Why this matters more than 4 findings

`document --project ... --apply` reporting "nothing to document" is the gate the
whole autodoc pipeline is trusted on, and 2026-08-14 already established that
that gate can be green over corrupted source (see
`INBOX-autodoc-not-idempotent-on-yadf.md`, which is why `doc-orphan-block`
exists). A residual doc-drift on the engine's OWN region is a second, independent
way for that gate to be green while something is wrong.
