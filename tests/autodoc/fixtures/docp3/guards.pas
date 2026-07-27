unit guards;

interface

// v(ADP3 T3d) fixture for the GROUP B register items: the two fail-closed arms
// of RegionFullyEngineOwned (D5), the decayed-fence-beside-an-unmodeled-tag
// shape (D12), the two T3f carry-through minors, and the duplicate <since>
// (D11). Every shape here is deliberately contrived: each one exists to make
// exactly ONE branch of exactly one guard decide the outcome, so that removing
// that branch changes the answer instead of being masked by a second check
// that would have said the same thing anyway.

// --- D5: RegionFullyEngineOwned's two FAIL-CLOSED arms ---------------------
//
// Both shapes below reach the Merged='' delete branch (the engine-owned,
// EMPTY <returns> supplies HasContent while contributing nothing to Merged,
// and neither routine has a minable return case or a caller, so no <returns>
// and no facts block are regenerated). Each then hangs on ONE line of
// RegionFullyEngineOwned:
//
//   UnterminatedFenceHandProse -- the hand-written line sits AFTER an
//     AUTO_BEGIN that never reaches an AUTO_END. That ordering is the whole
//     point: the pre-round-3 fail-OPEN code set an InFence flag it never
//     reset, so every line from the BEGIN through EOF read as engine-owned
//     and the author's <value> was deleted with the rest of the region.
//
//   StrayFenceEndHandProse -- the hand-written line ALSO carries an
//     AUTO_MARK, so the ordinary per-line marker check would wave it through;
//     only the stray-AUTO_END arm rejects it. Put the <value> on its own,
//     marker-free line instead and the test still passes -- but via the
//     marker check, proving nothing about the arm it claims to cover.

/// <returns><!-- drag-lint:auto --></returns>
/// <!-- drag-lint:auto BEGIN -->
/// <value>Hand-written after an unterminated fence; must survive.</value>
function UnterminatedFenceHandProse: Integer;

/// <returns><!-- drag-lint:auto --></returns>
/// <value>Hand-written beside a stray END; must survive.</value> <!-- drag-lint:auto --> <!-- drag-lint:auto END -->
function StrayFenceEndHandProse: Integer;

// --- D12: an unmodeled tag beside a DECAYED facts fence --------------------
//
// The fence asserts a caller that does not exist. No caller means the fresh
// render is empty, so the engine wants to say nothing at all -- but the
// <value> line is residual, "residual alone is not output", Merged comes out
// '' and the delete branch's guard then correctly refuses to delete a region
// containing hand-written source. Net: the stale fact is never cleaned.

/// <value>Unmodeled tag beside a decayed fence; must survive.</value>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: guards.NoSuchCallerAnyMore
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ValueBesideDecayedFence;

// --- T3f minor 1: the <remarks> non-retractable rule was too broad ---------
//
// This <remarks> carries no fence and no engine marker, and the routine has no
// caller, so the engine will emit NO <remarks> of its own. There is therefore
// no duplicate to avoid and no stale fact to trade against -- yet the
// unconditional rule made the span non-retractable, which aborted the
// carry-through and dropped the tail.

/// <summary>Summary, so the region reaches the repair path.</summary>
/// <remarks>Plain hand prose, no fence, no marker.</remarks> <value>tail value</value>
procedure UnfencedRemarksTail;

// --- T3f minor 3: the abort's blast radius was the whole region ------------
//
// The <returns> line legitimately aborts its OWN carry-through (its span is
// engine-regenerated, so handing the line back verbatim would freeze engine
// text AND duplicate the tag). The <value> line, two lines above, is innocent
// -- it overlaps nothing non-retractable -- and used to be deleted anyway.

/// <summary>Summary, so the region reaches the repair path.</summary>
/// <value>Innocent unmodeled tag; must survive another line's abort.</value>
/// <returns><!-- drag-lint:auto -->Observed: STALE</returns> hand tail
function AbortBlastRadius: Integer;

procedure CallsAbortBlastRadius;

// --- D11: two <since> tags -------------------------------------------------
//
// RxSinceTag is read with a SINGULAR .Match, so only the first survives the
// parse. The second one's fate is what this shape measures.

/// <since>1.0</since>
/// <since>2.0</since>
/// <summary>Two since tags; the parser models only one.</summary>
procedure TwoSinceTags;

implementation

function UnterminatedFenceHandProse: Integer;
begin
end;

function StrayFenceEndHandProse: Integer;
begin
end;

procedure ValueBesideDecayedFence;
begin
end;

procedure UnfencedRemarksTail;
begin
end;

function AbortBlastRadius: Integer;
begin
  Result := 42;
end;

procedure CallsAbortBlastRadius;
begin
  AbortBlastRadius;
end;

procedure TwoSinceTags;
begin
end;

end.
