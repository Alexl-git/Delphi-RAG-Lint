unit uDemoMain;
interface
uses Vcl.Forms, Vcl.StdCtrls, Vcl.ActnList, uDemoList, uDemoReports, uDemoGap;
type
  TfrmMain = class(TForm)
    btnLists: TButton;
    ActionList1: TActionList;
    actReports: TAction;
    btnReports: TButton;
    procedure btnListsClick(Sender: TObject);
    procedure actReportsExecute(Sender: TObject);
  public
    procedure OpenLists;
    procedure OpenGap;
  end;
var frmMain: TfrmMain;
implementation
{$R *.dfm}
procedure TfrmMain.btnListsClick(Sender: TObject);
begin
  OpenLists;
end;

procedure TfrmMain.OpenLists;
begin
  TfrmList.Create(Self).ShowModal;
end;

procedure TfrmMain.actReportsExecute(Sender: TObject);
begin
  TfrmReports.Create(Self).ShowModal;
end;

procedure TfrmMain.OpenGap;
begin
  TfrmGap.Create(Self).ShowModal;
end;
end.
