unit BooleanAssignIf;

interface

implementation

procedure P(X: Integer);
var
  Ok, Flag: Boolean;
begin
  if X > 0 then
    Ok := True
  else
    Ok := False;
  if X > 1 then
    Flag := False
  else
    Flag := True;
  if X > 2 then
    Ok := True
  else
    Flag := False;
  if X > 3 then
    Ok := True
  else
    Ok := True;
end;

function F(X: Integer): Boolean;
begin
  if X > 0 then
    Result := True
  else
    Result := False;
end;

end.
