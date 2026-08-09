unit decayrouting;

interface

// v(ADP3 T3d) fixture for the GROUP C register items -- the decay/routing
// class. Every shape here is routed to the FRESH-INSERT branch, which can only
// ever ADD a block: it has no repair and no delete. That single property is
// what produces all five behaviours below.
//
// The routing itself is deliberate and was chosen over the alternative
// (widening the repair-vs-fresh term so these shapes take the repair path),
// because the repair path DELETES the region and re-emits only what it models
// -- which would destroy the very hand-written tags these shapes carry. See
// DRagLint.Doc.Document.pas' own comment on that reverted widening.
//
// What makes every shape land on the fresh branch: the routing term reads
// TParsedDoc.HasContent, and an EMPTY <remarks></remarks> contributes nothing
// to it (HasContent tests Remarks <> '', not HasRemarksTag). RxRemarks is a
// SINGULAR .Match, so when a second, non-empty <remarks> follows, the parse
// still reads the author's empty one -- forever, however many facts blocks
// accumulate below it.

// --- N5: a verbatim quote of the engine's own block suppresses the insert ---
//
// The fresh branch's guard refuses to insert a block whose lines are already
// sitting above this declaration. Here the author has quoted -- exactly -- the
// block the engine is about to write, so the guard matches and the symbol
// silently never receives its own. Contrived (the quoted caller list has to
// match this symbol's real one) but silent.

/// <remarks></remarks>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: decayrouting.CallsQuotedBlockExact (decayrouting.pas)
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure QuotedBlockExact;

procedure CallsQuotedBlockExact;

// --- N7: the guard's scan loop, NEGATIVE path ------------------------------
//
// The control for N5, and the only shape that reaches the containment scan's
// mismatch path at all. Every previously-committed shape answers False through
// the "inner is longer than outer" early-out, never through the loop. The
// existing region must therefore stay AT LEAST AS LONG as the block the engine
// would insert, so the loop really runs, compares, and fails on ONE character:
// the quoted file name says .pos where the real block says .pas. The runner
// derives both lengths and asserts that relation rather than trusting it.
//
// v(ADP3 T13): the quoted block gained a `Pure` line because the real one did
// -- QuotedBlockNearMiss has a body and no detected effect, so the engine now
// renders Pure for it. Without this line the existing region would be SHORTER
// than the block to insert, the early-out would answer first, and the
// discrimination check would (correctly) report that it no longer discriminates.
// Keep the two in step: if the rendered fact lines change again, this quoted
// copy must change with them, and only the .pos/.pas character may differ.
//
// v(PHASE C, B8): the quoted block gained the two <summary> lines below for the
// same reason it gained `Pure` at T13 -- the real block grew. B8 wraps
// engine-owned prose at 100 columns, so the harvested summary the engine renders
// for this symbol is now TWO lines instead of one, and the block measured off
// the N6 shape went from 7 lines to 9. Without these the existing region is
// again SHORTER than the block to insert and the early-out, not the scan loop,
// is what answers -- which is precisely what the discrimination check caught.

/// <summary><!-- drag-lint:auto -->--- N7: the guard's scan loop, NEGATIVE path
/// ------------------------------</summary>
/// <remarks></remarks>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: decayrouting.CallsQuotedBlockNearMiss (decayrouting.pos)
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure QuotedBlockNearMiss;

procedure CallsQuotedBlockNearMiss;

// --- N6: two sibling <remarks> elements in the converged output ------------
//
// The author's empty element stays where it is and the engine's is inserted
// beside it. Stable and reversible, but not well-formed DocInsight.

/// <remarks></remarks>
procedure EmptyRemarksSibling;

procedure CallsEmptyRemarksSibling;

// --- T3f minor 4: the ORDER of the two siblings has a consequence ----------
//
// An attributed <remarks xml:lang="en"> is valid XML doc that the parser's
// strict pattern cannot represent, so it is carried through verbatim as a
// residual line -- which the emitter places BEFORE the facts block. A
// consumer that reads "the <remarks> element" (Delphi Help Insight does)
// therefore renders the author's element and never sees the facts at all.

/// <remarks xml:lang="en">Attributed remarks prose must survive.</remarks>
/// <summary>Real summary beside a VALID but attributed remarks element.</summary>
procedure AttributedRemarksOrder;

procedure CallsAttributedRemarksOrder;

// --- N4: decayed facts report `unchanged` forever --------------------------
//
// The runner drives this one: it ADDS a second caller, applies (a second block
// is inserted, the first stays), then REMOVES that caller and applies again.
// The engine then matches the FIRST block, reports the symbol up to date, and
// leaves the second block on disk asserting a caller that no longer exists.

/// <remarks></remarks>
procedure DecayAddThenRemove;

procedure CallsDecayAddThenRemove;
// N4-EXTRA-CALLER-DECL

implementation

procedure QuotedBlockExact;
begin
end;

procedure CallsQuotedBlockExact;
begin
  QuotedBlockExact;
end;

procedure QuotedBlockNearMiss;
begin
end;

procedure CallsQuotedBlockNearMiss;
begin
  QuotedBlockNearMiss;
end;

procedure EmptyRemarksSibling;
begin
end;

procedure CallsEmptyRemarksSibling;
begin
  EmptyRemarksSibling;
end;

procedure AttributedRemarksOrder;
begin
end;

procedure CallsAttributedRemarksOrder;
begin
  AttributedRemarksOrder;
end;

procedure DecayAddThenRemove;
begin
end;

procedure CallsDecayAddThenRemove;
begin
  DecayAddThenRemove;
end;
// N4-EXTRA-CALLER-IMPL

end.
