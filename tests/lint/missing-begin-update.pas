unit MissingBeginUpdate;

interface

implementation

procedure P;
var
  I: Integer;
begin
  for I := 1 to 1000 do
    ListBox1.Items.Add(IntToStr(I));
  Memo1.Lines.BeginUpdate;
  try
    for I := 1 to 1000 do
      Memo1.Lines.Add(IntToStr(I));
  finally
    Memo1.Lines.EndUpdate;
  end;
  ListBox1.Items.Add('x');
  for I := 1 to 3 do
    Edit1.Text := IntToStr(I);
end;

procedure Q;
var
  I: Integer;
begin
  for I := 1 to 1000 do
    Memo2.Lines.Add(IntToStr(I));
end;

end.
