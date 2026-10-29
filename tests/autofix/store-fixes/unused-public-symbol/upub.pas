unit upub;

interface

/// <summary>Used only below.</summary>
function Twice(A: Integer): Integer;
procedure Run;

implementation

function Twice(A: Integer): Integer;
begin
  Result:= A * 2;
end;

procedure Run;
begin
  Writeln(Twice(2));
end;

end.
