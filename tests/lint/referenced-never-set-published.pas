unit rnsp;
interface
uses Vcl.Forms, Vcl.StdCtrls;
type
  TForm1 = class(TForm)
    Label1: TLabel;
    procedure Use;
  end;
implementation
procedure TForm1.Use;
begin
  Label1.Caption:= 'x';
end;
end.