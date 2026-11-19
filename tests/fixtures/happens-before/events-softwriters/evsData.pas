unit evsData;

interface

uses
  evsMissing;

var
  GAddr: Integer;
  GWith: Integer;
  GAbs: Integer;
  GAlias: Integer absolute GAbs;
  GPlain: Integer;
  GPlainTwin: Integer;
  GReadOnly: Integer;

procedure Touch;

implementation

procedure Poke(pP: PInteger);
begin
  pP^ := 2;
end;

procedure Touch;
var
  L: Integer;
begin
  Poke(@GAddr);
  with TMissingThing.Make do
    GWith := 3;
  GAlias := 4;
  Poke(@GPlainTwin);
  L := GPlain + GPlainTwin + GReadOnly + GAbs + GWith + GAddr;
  if L > 0 then
    Exit;
end;

end.
