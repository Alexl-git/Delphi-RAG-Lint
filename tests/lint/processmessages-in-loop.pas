unit ProcessMessagesInLoop;

interface

implementation

procedure P(var Done: Boolean);
var
  I: Integer;
begin
  while not Done do
  begin
    Application.ProcessMessages;
  end;
  for I := 0 to 3 do
    Application.ProcessMessages();
  repeat
    Application.ProcessMessages;
  until Done;
  Application.ProcessMessages;
  for I := 0 to 3 do
    Application.Terminate;
end;

end.
