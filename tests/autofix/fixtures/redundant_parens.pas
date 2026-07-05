unit redundant_parens;
interface
implementation

procedure P(var X: Integer; const A, B: Integer);
begin
  X := ((A + B));
end;

end.
