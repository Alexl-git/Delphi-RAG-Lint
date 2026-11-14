unit UFreeNotify;

{ component-missing-free-notification when both the owning class and the
  property type descend from TComponent only through a class of another unit:
  the index answers the ancestry. (+) must fire, (-) must not. }

interface

uses
  Classes, UBaseComp;

type
  THolder = class(TBaseComp)
  private
    FPeer: TBaseComp;
    FSafePeer: TBaseComp;
    procedure SetPeer(const Value: TBaseComp);
    procedure SetSafePeer(const Value: TBaseComp);
  published
    property Peer: TBaseComp read FPeer write SetPeer;
    property SafePeer: TBaseComp read FSafePeer write SetSafePeer;
  end;

implementation

procedure THolder.SetPeer(const Value: TBaseComp);
begin
  FPeer := Value; { (+) }
end;

procedure THolder.SetSafePeer(const Value: TBaseComp);
begin
  FSafePeer := Value; { (-) }
  if Value <> nil then
    Value.FreeNotification(Self);
end;

end.
