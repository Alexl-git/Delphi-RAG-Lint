unit redundant_not_not;

interface

implementation

procedure Demo;
var
  Flag, B: Boolean;
begin
  Flag := True;
  B := not not Flag;
end;

end.
