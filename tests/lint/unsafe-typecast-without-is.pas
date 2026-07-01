unit unsafecast;
interface
uses Vcl.StdCtrls, Vcl.Graphics;
implementation

procedure Handle(Sender: TObject);
var
  E : TEdit;
  N : Integer;
  C : TColor;
begin
  TButton(Sender).Caption := 'a';
  if Sender is TComboBox then
    TComboBox(Sender).Text := 'b';
  TButton(E).Caption := 'c';
  TObject(E).Free;
  TEdit(E).Text := 'd';
  C := TColor(N);
end;
end.
