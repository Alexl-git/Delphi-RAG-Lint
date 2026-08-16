# INBOX: a `<returns>` type baseline was ATTEMPTED and REVERTED -- it destroys hand-written prose in malformed blocks

> **2026-08-16 -- RECLASSIFIED, and its one open precondition is now PROVEN.**
>
> **This is a DESIGN RECORD, not a defect.** The destructive behaviour lived in a
> change that was reverted and never shipped; nothing destructive is in the tree.
> `INBOX-INDEX.md` listed it under "known-wrong output / DESTRUCTIVE", which sent
> this session looking for a live bug that does not exist. Index corrected.
>
> **The precondition it left open was the real content**, and it is worth more
> than the `<returns>` question:
>
> > *"the guard was never really guarding the malformed block; it was guarded by
> > accident, because nothing wanted to write there."*
> >
> > *"Any future attempt must first make the malformed-region guard hold on a
> > declaration the engine DOES have output for."*
>
> **Measured 2026-08-16: it holds.** A routine WITH a caller -- so the engine has
> `Called from:` + `Pure` to write, confirmed by running the identical routine
> with no block, which produces `1 edit(s)` -- is left completely alone when its
> block opens an auto fence that never closes. `nothing to document`, file
> byte-identical, hand-written `<value>` intact.
>
> Pinned by `tests\autodoc\run_doc_malformed_region_holds.ps1`, **5/5**, whose
> control arm exists precisely so this cannot pass for D5's reason. The
> precondition is no longer an open question, so a future `<returns>` attempt has
> something to build on rather than a warning to re-derive.
>
> **The recommendation below still stands** -- the 116 findings are honest and
> actionable, `<returns>Integer</returns>` tells a reader nothing the signature
> does not, and generating them would trade a human to-do list for noise. Nobody
> should ship the baseline. This note now records WHY, plus the one fact that
> would be needed if that judgement is ever revisited.

Date: 2026-08-10. Status: **reverted, not shipped.** Read this before trying it again.

## What was attempted

The `<param>` type baseline (owner ruling, commit f3e66e6) cleared 574
`doc-param-no-description` findings by giving an undocumented parameter its
DECLARED TYPE as the tag body, under the `AUTO_TYPE` ownership marker.

The obvious parallel: 116 remaining
`doc-drift: function returns a value but has no <returns> tag` findings. The
declared return type is already in `TDocFacts.ReturnType`, so the same shape
applied -- mined observation first, declared type as the baseline beneath it:

```pascal
function EmitEngineReturns(const AF: TDocFacts): string;
begin
  Obs := Trim(ObservedSuffix(AF.ReturnCases));
  if Obs <> '' then Exit(EmitTagged('<returns>' + AUTO_MARK, Obs, '</returns>'));
  if Trim(AF.ReturnType) <> '' then
    Exit(EmitTagged('<returns>' + AUTO_TYPE, EscXml(Trim(AF.ReturnType)), '</returns>'));
  Result := '';
end;
```

It built clean and 69 of 71 autodoc runners passed.

## Why it was reverted

`tests/autodoc/run_doc_p3_guards.ps1` went RED on its D5 arm:

```
[FAIL] D5 unterminated-fence arm: the hand-written <value> SURVIVES
[FAIL] D5 unterminated-fence arm: the whole doc block is byte-identical
```

The fixture's `UnterminatedFenceHandProse` carries a hand-written `<value>` after
an `AUTO_BEGIN` that never reaches an `AUTO_END` -- a MALFORMED region the engine
must fail-CLOSED on and leave alone. After the change its whole doc block had been
replaced by a single generated line and the author's `<value>` was gone:

```
/// <returns><!-- drag-lint:auto type -->Integer</returns>
function UnterminatedFenceHandProse: Integer;
```

**The mechanism is the important part.** Before the change, a function with no
minable return case emitted NOTHING, so that declaration produced no edit and
never entered MergeComment's rewrite path at all. Emitting a baseline `<returns>`
for EVERY function turns "no edit" into "always an edit", which drags
previously-untouched declarations into the rewrite -- including the malformed ones
whose entire protection was that the engine had nothing to say about them.

So the guard was never really guarding the malformed block; it was guarded by
accident, because nothing wanted to write there. The `<param>` baseline did not
expose this only because those decls were already being rewritten for other
reasons.

## Do not simply re-apply it

Any future attempt must first make the malformed-region guard hold on a
declaration the engine DOES have output for. That is a change to
MergeComment/region ownership on an engine that REWRITES SOURCE, and it is the
load-bearing part -- the emit itself is five lines.

## And consider whether it is even wanted

Unlike the 171 `has no <param> tag` findings -- which were unfixable by
construction (the checker graded implementation-section decls the writer never
touches; fixed in e61a475) -- these 116 are HONEST and ACTIONABLE: they say "this
function returns a value and nobody has documented what". A human writing one
sentence clears each. Generating `<returns>Integer</returns>` would clear the
finding while telling the reader nothing the signature does not already say, and
the tooltip/HTML-help argument that justified `<param>` types is weaker here:
there is exactly one return value and its type sits at the end of the signature
being rendered directly above.

Recommendation: leave them. They are a to-do list for humans, not noise.
