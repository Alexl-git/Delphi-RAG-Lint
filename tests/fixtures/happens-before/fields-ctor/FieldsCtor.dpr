program FieldsCtor;

{ check-init fixture fields-ctor (lane HBFIELDS): the constructor model (spec 5.5).
  TBoth: FList is set by every constructor (directly, through Self., through a Self method, through a
  sibling constructor); FHalf is the MAY twin that CreateFor does not set.
  TPeer / TPeerBad: the same write through Self and through another object (receiver twin).
  TEarly: Peek reads FLog before Create writes it; TEarly2 writes first (the SET twin). }

uses
  fcData in 'fcData.pas';

var
  B: TBoth;

begin
  B:= TBoth.CreateFor(1);
  B.Run;
  TPeer.Create.Show;
  TPeerBad.Create(nil).Show;
  TEarly.Create.Peek;
  TEarly2.Create.Peek;
end.