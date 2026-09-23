unit uFillerB;

{ Filler: with four units the incremental index takes the SCOPED resolve
  path (limit = files div 3), which is the path check 6 exercises. The call
  below keeps one call edge OUTSIDE the mutated unit: with none, the edge set
  is empty mid-run and the pass falls back to WHOLE-DB (CallEdgesNeedRebuild). }

interface

procedure FillB;

implementation

uses
  uFillerA;

procedure FillB;
begin
  FillA;
end;

end.
