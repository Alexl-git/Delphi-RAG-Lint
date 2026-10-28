unit CvUse;

interface

uses
  System.Classes, System.Generics.Collections, CvLib;

type
  { TScreenCursorOld in a comment stays }
  TCvUse = class(TComponent)
  public
    F: TOldField;
    FCur: TScreenCursorOld;
    function Cur(P: TScreenCursorOld): TScreenCursorOld;
    function Thing(O: TObject): Integer;
  end;

implementation

function TCvUse.Cur(P: TScreenCursorOld): TScreenCursorOld;
var
  C: TScreenCursorOld;
  L: TList<TScreenCursorOld>;
  S: string;
begin
  S:= 'scoWait';
  C:= scoWait;
  if P = scoDefault then C:= TScreenCursorOld(1);
  if P = scoBusy then C:= scoDefault;
  L:= TList<TScreenCursorOld>.Create;
  try
    L.Add(C);
  finally
    L.Free;
  end;
  F.Size:= Length(S); // scoWait in a line comment stays
  Result:= C;
end;

function TCvUse.Thing(O: TObject): Integer;
var
  G: TGoneOld;
begin
  G:= nil;
  if O is TOldThing then Result:= (O as TOldThing).Tag + TOldThing(O).Tag else Result:= 0;
  if G <> nil then Inc(Result);
end;

end.
