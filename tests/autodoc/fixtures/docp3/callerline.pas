unit callerline;

interface

// Auto-Document Phase 3, Task 4 -- the CALLER-LINE render fixture. Two
// separate defects meet on one line of this unit's generated output.
//
// TPoint2 is a RECORD. A record cannot be called, yet the renderer labelled
// its reference list "Called from:" -- on the YADF rollout a record rendered
// "Called from:" over what were plain type mentions. Those references reach
// the list through the NON-ROUTINE path: CanBeCallTarget is False for a
// record, so DRagLint.Doc.Facts does not restrict the name-match bucket to
// call sites, and every entry it collects arrives with Confidence
// 'unverified'. The same line therefore also carried a ' ?' on its ONLY
// entry, and a marker present on every entry of a uniform list distinguishes
// nothing.
//
// MakePoint and SumPoint are the CONTROLS for both halves. OriginSum calls
// each of them from inside this same unit, which the resolver turns into a
// real call_edges row, so their caller lists are uniformly CERTAIN and render
// plain -- the behaviour Task 4 must leave byte-identical. Without OriginSum
// neither routine would have a caller at all, no "Called from:" line would be
// emitted for either, and "a callable still says Called from:" would be a
// vacuous assertion over an absent line.

type
  TPoint2 = record
    X: Integer;
    Y: Integer;
  end;

function MakePoint(AX, AY: Integer): TPoint2;
function SumPoint(const APoint: TPoint2): Integer;
function OriginSum: Integer;

implementation

function MakePoint(AX, AY: Integer): TPoint2;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function SumPoint(const APoint: TPoint2): Integer;
begin
  Result := APoint.X + APoint.Y;
end;

function OriginSum: Integer;
begin
  Result := SumPoint(MakePoint(0, 0));
end;

end.
