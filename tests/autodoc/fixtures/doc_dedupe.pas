unit doc_dedupe;

interface

function Target(A: Integer): Integer;
function CallsTwice: Integer;

implementation

function Target(A: Integer): Integer;
begin
  Result := A + 1;
end;

function CallsTwice: Integer;
var
  X: Integer;
  Y: Integer;
begin
  X := Target(1);
  Y := Target(2);
  Result := X + Y;
end;

end.
