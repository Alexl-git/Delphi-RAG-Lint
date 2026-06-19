unit uDemoList;
interface
uses Vcl.Forms, Vcl.StdCtrls, uDemoEdit, uDemoChild;
type
  TfrmList = class(TForm)
    btnEdit: TButton;
    btnOpen: TButton;
    procedure btnEditClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
  end;
implementation
{$R *.dfm}
procedure TfrmList.btnEditClick(Sender: TObject);
begin
  TfrmEdit.Create(Self).ShowModal;
end;
procedure TfrmList.btnOpenClick(Sender: TObject);
begin
  TfrmChild.CreateForFolder(Self, 0);
end;
end.
