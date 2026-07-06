unit doc_generate;

interface

function Add(A, B: Integer): Integer;
function UseAdd: Integer;

implementation

function Add(A, B: Integer): Integer;
begin
  Result := A + B;
end;

function UseAdd: Integer;
begin
  Result := Add(1, 2);
end;

end.
