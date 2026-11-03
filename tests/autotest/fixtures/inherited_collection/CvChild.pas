unit CvChild;
interface
uses System.Classes, CvLib, CvBase;
type
  TCvChild = class(TCvBase)
  public
    function Cur: Integer;
  end;
implementation
function TCvChild.Cur: Integer;
var
  C: TScreenCursorOld;
begin
  C:= scoWait;
  Result:= Ord(C);
end;
end.
