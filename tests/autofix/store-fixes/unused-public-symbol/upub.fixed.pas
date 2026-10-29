unit upub;

interface

procedure Run;

implementation

/// <summary>Used only below.</summary>
function Twice(A: Integer): Integer;
begin
  Result:= A * 2;
end;

procedure Run;
begin
  Writeln(Twice(2));
end;

end.
