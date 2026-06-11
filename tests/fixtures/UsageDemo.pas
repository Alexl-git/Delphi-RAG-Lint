unit UsageDemo;
interface
type
  TForm1 = class(TForm)
    dxDBGrid1: TObject;
    procedure Btn1Click(Sender: TObject);
  end;
implementation
procedure TForm1.Btn1Click(Sender: TObject);
begin
  dxDBGrid1.DataSource := nil;
  if dxDBGrid1.Enabled then
    dxDBGrid1.Refresh;
  DoSomething(dxDBGrid1);
end;
end.
