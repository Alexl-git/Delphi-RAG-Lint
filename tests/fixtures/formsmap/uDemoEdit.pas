unit uDemoEdit;
interface
uses Vcl.Forms, Vcl.StdCtrls;
type
  TfrmEdit = class(TForm)
    btnBack: TButton;
    procedure btnBackClick(Sender: TObject);
  end;
implementation
uses uDemoList;
{$R *.dfm}
procedure TfrmEdit.btnBackClick(Sender: TObject);
begin
  TfrmList.Create(Self).ShowModal;
end;
end.
