unit ite;
interface
implementation
procedure P(C: Boolean; var X: Integer);
begin
  if C then X := 1 else X := 1;
  if C then X := 1 else X := 2;
end;

procedure P2(C: Boolean; var X: Integer);
begin
  if C then
  begin
    X := 2;
  end
  else
  begin
    X := 2;
  end;
end;

procedure P3(C: Boolean);
begin
  if C then WriteLn('same') else WriteLn('same');
  if C then WriteLn('a') else WriteLn('b');
  if C then begin WriteLn('a'); WriteLn('b'); end else begin WriteLn('a');  WriteLn('b'); end;
  if C then begin WriteLn('a') end else begin WriteLn('b') end;
  if C then
  begin
    WriteLn('a'); // first
  end
  else
  begin
    { second } WriteLn('a');
  end;
  if C then begin WriteLn('a'); end else begin WriteLn('a'); WriteLn('a'); end;
end;
end.
