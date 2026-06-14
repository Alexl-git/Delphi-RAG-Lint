unit uDemoList;
interface
uses Vcl.Forms, Vcl.StdCtrls, uDemoEdit;
type
  TfrmList = class(TForm)
    btnEdit: TButton;
    procedure btnEditClick(Sender: TObject);
  end;
implementation
{$R *.dfm}
procedure TfrmList.btnEditClick(Sender: TObject);
begin
  TfrmEdit.Create(Self).ShowModal;
end;
end.
