unit uDemoMain;
interface
uses Vcl.Forms, Vcl.StdCtrls, uDemoList;
type
  TfrmMain = class(TForm)
    btnLists: TButton;
    procedure btnListsClick(Sender: TObject);
  end;
var frmMain: TfrmMain;
implementation
{$R *.dfm}
procedure TfrmMain.btnListsClick(Sender: TObject);
begin
  TfrmList.Create(Self).ShowModal;
end;
end.
