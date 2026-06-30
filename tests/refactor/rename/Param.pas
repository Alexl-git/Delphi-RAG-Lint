unit Param;
interface
procedure Go(Value: Integer);
implementation
procedure Go(Value: Integer);
begin
  Writeln(Value);
  Value := Value + 1;
end;
end.
