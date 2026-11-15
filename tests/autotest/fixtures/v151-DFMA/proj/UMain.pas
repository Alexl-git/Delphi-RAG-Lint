unit UMain;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Data.DB;

type
  TMainForm = class(TForm)
    lblUser: TLabel;
    DataSource1: TDataSource;
    procedure FormCreate(Sender: TObject);
    procedure ShowReport;
    procedure ShowReportOnce;
    procedure FillTitle;
  end;

var
  MainForm: TMainForm;

implementation

uses
  UDm, UReport;

{$R *.dfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  lblUser.Caption:= dmMain.UserName;
  if Assigned(ReportForm) then
    ReportForm.Caption:= 'ready';
end;

procedure TMainForm.ShowReport;
begin
  ReportForm:= TReportForm.Create(Application);
  ReportForm.ShowModal;
end;

procedure TMainForm.ShowReportOnce;
begin
  if not Assigned(ReportForm) then
    ReportForm:= TReportForm.Create(Application);
  ReportForm.Show;
end;

procedure TMainForm.FillTitle;
var
  Other: TReportForm;
begin
  ReportForm.edtTitle.Text:= 'Report';
  ReportForm.Caption:= 'not a control';
  Other:= nil;
  Other.edtTitle.Text:= 'local';
end;

end.
