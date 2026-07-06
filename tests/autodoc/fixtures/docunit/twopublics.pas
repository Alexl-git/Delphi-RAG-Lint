unit twopublics;
interface
type
  TThing = class
  private
    FLast: Integer;
  public
    function Add(A, B: Integer): Integer;
    procedure Reset;
  end;
implementation
function TThing.Add(A, B: Integer): Integer;
begin Result := A + B; end;
procedure TThing.Reset;
begin FLast := Add(0, 0); end;
end.
