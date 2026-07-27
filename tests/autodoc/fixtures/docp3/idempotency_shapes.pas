unit idempotency_shapes;

interface

// Phase 3, Task 3b review round 4 -- IDEMPOTENCY SHAPES.
//
// Every round of this task asserted CYCLE-1 correctness, and three separate
// non-idempotent shapes shipped because nothing swept for a fixed point.
// This fixture exists purely to be swept: run_doc_p3_idempotency_sweep.ps1
// applies `document --apply` to each symbol below three times (reindexing
// between cycles) and asserts an md5 FIXED POINT from cycle 2 onward.
//
// The shapes here are the round-4 review's own measured reproductions of the
// CRITICAL: a comment whose only HasContent-bearing tag is an EMPTY or
// WHITESPACE-ONLY <remarks> never reached a fixed point -- `document --apply`
// appended another facts block on every single run, forever (measured:
// 364 -> 517 -> 670 -> 823 bytes over four applies, "action":"created",
// "edits":1 every cycle). Cause: RxRemarks.Match is SINGULAR and takes the
// FIRST match, which is the author's own empty tag, however many facts
// blocks accumulate below it -- so Remarks stays '', HasContent stays False,
// BuildForSymbol's ExistingHasAnyTag stays False, and control lands in the
// FRESH-INSERT branch, which had no idempotency guard at all and inserted
// unconditionally.
//
// Every symbol has a CALLER so Facts.CalledFrom is non-empty and the engine
// genuinely has something to write -- a fact-free comment produces an empty
// Merged and is left alone by a different mechanism entirely, so a fact-free
// shape would be stable whether or not the guard exists.

// ---------------------------------------------------------------------
// The three CRITICAL shapes: the only HasContent-bearing tag is an empty or
// whitespace-only <remarks>.
// ---------------------------------------------------------------------

/// <remarks></remarks>
procedure EmptyRemarksOnly;

procedure CallsEmptyRemarksOnly;

/// <remarks>   </remarks>
procedure WhitespaceRemarksOnly;

procedure CallsWhitespaceRemarksOnly;

/// <remarks>
/// </remarks>
procedure TwoLineRemarksOnly;

procedure CallsTwoLineRemarksOnly;

// ---------------------------------------------------------------------
// The three PRE-EXISTING SIBLINGS the same guard closes: a hand-written tag
// that does NOT appear in ExistingHasAnyTag's OR-chain, sitting alongside an
// empty <remarks>. Measured growth pre-fix: <since> 403 -> 566 -> 729 -> 892,
// <example> 401 -> 558 -> 715 -> 872, <seealso> 408 -> 567 -> 726 -> 885.
// The <since> one is squarely inside this task's own remit.
// ---------------------------------------------------------------------

/// <since>1.0</since>
/// <remarks></remarks>
procedure SincePlusEmptyRemarks;

procedure CallsSincePlusEmptyRemarks;

/// <example>sample</example>
/// <remarks></remarks>
procedure ExamplePlusEmptyRemarks;

procedure CallsExamplePlusEmptyRemarks;

/// <seealso cref="X"/>
/// <remarks></remarks>
procedure SeeAlsoPlusEmptyRemarks;

procedure CallsSeeAlsoPlusEmptyRemarks;

// ---------------------------------------------------------------------
// CONVERGENT CONTROLS: these two already reached a fixed point BEFORE the
// round-4 guard (measured 378/378/378/378 and 391/391/391/391) because
// HasSummaryTag / Exceptions.Length both DO appear in ExistingHasAnyTag's
// OR-chain, so they route to the REPAIR branch, which has always had a
// CommentLinesEqual idempotency compare. They are here as regression
// anchors: the guard must not perturb a shape that was already stable.
// ---------------------------------------------------------------------

/// <summary>Real.</summary>
/// <remarks></remarks>
procedure SummaryPlusEmptyRemarks;

procedure CallsSummaryPlusEmptyRemarks;

/// <exception cref="EZ">boom</exception>
/// <remarks></remarks>
procedure ExceptionPlusEmptyRemarks;

procedure CallsExceptionPlusEmptyRemarks;

// ---------------------------------------------------------------------
// NON-DESTRUCTIVENESS: an UNMODELED tag (<value> has no TParsedDoc field at
// all -- the documented residual this task does not close) alongside an
// empty <remarks>. The round-4 guard must make this shape stable WITHOUT
// routing it into the repair branch, which deletes the region and re-inserts
// Merged -- and Merged cannot represent <value>, so a routing-based fix
// (widening ExistingHasAnyTag) would have converged by DESTROYING the tag.
// The guard suppresses a duplicate INSERT instead, so nothing is deleted and
// the hand-written <value> survives.
// ---------------------------------------------------------------------

/// <value>Hand-written value tag; unmodeled, must not be destroyed.</value>
/// <remarks></remarks>
procedure ValuePlusEmptyRemarks;

procedure CallsValuePlusEmptyRemarks;

// ---------------------------------------------------------------------
// LOAD-BEARING IN THE OTHER DIRECTION: no doc comment at all, with a caller.
// The guard must still let a genuine first insert through -- if it suppressed
// this, the whole `document` verb would stop producing output and every other
// runner in the battery would go red. Cycle 1 must CREATE a facts block;
// cycles 2 and 3 must then be a fixed point (via the repair branch, which
// the created block's own <remarks> now routes it to).
// ---------------------------------------------------------------------

procedure NoCommentAtAll;

procedure CallsNoCommentAtAll;

// ---------------------------------------------------------------------
// GAPPED SHAPE: the same empty-<remarks>-only comment, but separated from
// its declaration by a blank line. The destruction/growth in this task has
// been shape-dependent throughout (MergeAdjacentSameKind only folds regions
// whose lines abut), so the gapped twin of the CRITICAL shape is swept too
// rather than assumed equivalent.
// ---------------------------------------------------------------------

/// <remarks></remarks>

procedure GappedEmptyRemarks;

procedure CallsGappedEmptyRemarks;

implementation

procedure EmptyRemarksOnly;
begin
end;

procedure CallsEmptyRemarksOnly;
begin
  EmptyRemarksOnly;
end;

procedure WhitespaceRemarksOnly;
begin
end;

procedure CallsWhitespaceRemarksOnly;
begin
  WhitespaceRemarksOnly;
end;

procedure TwoLineRemarksOnly;
begin
end;

procedure CallsTwoLineRemarksOnly;
begin
  TwoLineRemarksOnly;
end;

procedure SincePlusEmptyRemarks;
begin
end;

procedure CallsSincePlusEmptyRemarks;
begin
  SincePlusEmptyRemarks;
end;

procedure ExamplePlusEmptyRemarks;
begin
end;

procedure CallsExamplePlusEmptyRemarks;
begin
  ExamplePlusEmptyRemarks;
end;

procedure SeeAlsoPlusEmptyRemarks;
begin
end;

procedure CallsSeeAlsoPlusEmptyRemarks;
begin
  SeeAlsoPlusEmptyRemarks;
end;

procedure SummaryPlusEmptyRemarks;
begin
end;

procedure CallsSummaryPlusEmptyRemarks;
begin
  SummaryPlusEmptyRemarks;
end;

procedure ExceptionPlusEmptyRemarks;
begin
end;

procedure CallsExceptionPlusEmptyRemarks;
begin
  ExceptionPlusEmptyRemarks;
end;

procedure ValuePlusEmptyRemarks;
begin
end;

procedure CallsValuePlusEmptyRemarks;
begin
  ValuePlusEmptyRemarks;
end;

procedure NoCommentAtAll;
begin
end;

procedure CallsNoCommentAtAll;
begin
  NoCommentAtAll;
end;

procedure GappedEmptyRemarks;
begin
end;

procedure CallsGappedEmptyRemarks;
begin
  GappedEmptyRemarks;
end;

end.
