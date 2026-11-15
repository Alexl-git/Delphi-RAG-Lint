unit ProcessMessagesHandler;

interface

implementation

procedure TForm1.Button1Click(Sender: TObject);
begin
  Application.ProcessMessages;
  Work;
end;

procedure TForm1.Helper(A: Integer);
begin
  Application.ProcessMessages;
end;

procedure TForm1.Button2Click(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to 3 do
    Application.ProcessMessages;
end;

end.
