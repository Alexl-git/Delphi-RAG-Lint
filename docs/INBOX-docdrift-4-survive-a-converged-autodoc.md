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
