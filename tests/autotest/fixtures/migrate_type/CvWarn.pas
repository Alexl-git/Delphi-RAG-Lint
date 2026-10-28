unit CvWarn;

interface

uses
  System.Classes, CvLib;

type
  TCvWarn = class(TComponent)
  public
    F: TOldField;
    function Go: Integer;
  end;

implementation

function TCvWarn.Go: Integer;
var
  C: TScreenCursorOld;
  T: TOldThing2;
begin
  C:= scoOther;
  T:= nil;
  C:= CvLib.scoWait;
  Result:= Ord(C) + F.Size + Ord(T = nil);
end;

end.
