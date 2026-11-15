unit FoUnit;

interface

type
  TCounter = class
  private
    Count: Integer;
  public
    function Sum(A: Integer): Integer;
    function Twice(Count: Integer): Integer;
  end;

procedure RunAll;

implementation

{ the local Count hides the field Count; Self.Count still reaches the field }
function TCounter.Sum(A: Integer): Integer;
var
  Count: Integer;
begin
  Count:= A + 1;
  Result:= Count + Self.Count;
end;

{ declined: a parameter's name is part of the signature }
function TCounter.Twice(Count: Integer): Integer;
begin
  Result:= Count * 2;
end;

procedure RunAll;
var
  C: TCounter;
begin
  C:= TCounter.Create;
  try
    WriteLn(C.Sum(1), C.Twice(2));
  finally
    C.Free;
  end;
end;

end.
