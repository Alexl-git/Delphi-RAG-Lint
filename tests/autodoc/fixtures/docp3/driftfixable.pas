unit driftfixable;

// v(ADP3 T3d) fixture for deferred-defect register items D2, D3 and D4.
//
// D2 -- ddValueButNoReturns used to claim Fixable=True unconditionally. Since
//   v(ADP3 T3)'s omit-when-empty rule, MergeComment writes an engine <returns>
//   ONLY when a return case is minable, so on a function with nothing minable
//   the finding survived `lint-all --fix --apply` forever: a false promise.
//   MinableReturn and NoMinableReturn are the two sides of that, and
//   BlankReturnsSlot is the third shape (a human's empty tag, preserved
//   verbatim, so no fix can ever clear it either).
//
// D3 -- once every engine-written <returns> carries the provenance marker
//   (v(ADP3 T1)), ReturnsText is never empty for a managed tag, so
//   ddValueButNoReturns silently stopped firing on one. MarkedReturns pins
//   that as the DELIBERATE, correct answer: the tag demonstrably exists.
//
// D4 -- RunDocDrift's population came from ListDocumentedSymbols, which
//   filtered on a non-null summary, so RemarksOnlyStaleFacts (documented by
//   <remarks> alone) produced NO doc-drift row at all -- while `document
//   --apply` cleaned the very same stale block. The two routes diverged.
//
// Nothing here calls anything else in the unit, deliberately: an isolated
// symbol renders an EMPTY facts block, which is what makes the hand-written
// fence on RemarksOnlyStaleFacts unambiguously stale.

interface

/// <summary>A function whose body assigns Result, so the engine CAN mine a
/// return case and synthesise the missing tag. No returns tag on purpose.</summary>
function MinableReturn(Key: Integer): string;

/// <summary>A function whose body assigns nothing at all, so no return case is
/// minable and no fix for the missing tag exists. No returns tag on purpose.</summary>
function NoMinableReturn(Key: Integer): string;

/// <summary>A function carrying a HUMAN's deliberately empty returns tag. The
/// tag is preserved verbatim on every repair, so the finding can never be
/// cleared mechanically even though a return case IS minable here.</summary>
/// <returns></returns>
function BlankReturnsSlot(Key: Integer): string;

/// <summary>A function carrying an ENGINE-written returns tag (provenance
/// marker present). ddValueButNoReturns must NOT fire: the tag exists.</summary>
/// <returns><!-- drag-lint:auto --> Observed: IntToStr(Key).</returns>
function MarkedReturns(Key: Integer): string;

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: driftfixable.NoSuchCallerAnyMore.
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RemarksOnlyStaleFacts;

implementation

uses
  System.SysUtils;

function MinableReturn(Key: Integer): string;
begin
  Result := IntToStr(Key);
end;

function NoMinableReturn(Key: Integer): string;
begin
  // Deliberately never assigns Result and never Exit(value)s, so
  // MineReturnExpressions yields nothing for this routine.
  Inc(Key);
end;

function BlankReturnsSlot(Key: Integer): string;
begin
  Result := IntToStr(Key);
end;

function MarkedReturns(Key: Integer): string;
begin
  Result := IntToStr(Key);
end;

procedure RemarksOnlyStaleFacts;
begin
  // No callers, no calls: the fresh facts render is empty, so the fence above
  // this routine's declaration is stale by construction.
end;

end.
