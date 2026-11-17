unit MissingBeginUpdateV152;

interface

implementation

procedure P(T: TArray<string>);
var
  Cmb: TComboBox;
  Lst: TListBox;
begin
  Cmb := TComboBox.Create(nil);
  for var V in T do Cmb.Items.Add(V);
  for var V in T do Lst.Items.Add(V);
  for var V in T do ListBox1.Items.Add(V);
end;

end.