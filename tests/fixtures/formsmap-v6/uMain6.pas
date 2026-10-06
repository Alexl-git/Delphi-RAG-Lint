unit uMain6;

interface

uses
  System.SysUtils, System.Classes, Data.DB, Vcl.Forms, Vcl.Menus, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.ActnList, Vcl.ExtCtrls, uHelpers6, uEdit6, uReports6, uNag6,
  uImportVM6, uMdi6, uPanel6, uSerial6, uCache6;

type
  TfrmMain6 = class(TForm)
    mnuMain: TMainMenu;
    mnuSetup: TMenuItem;
    mnuGroups: TMenuItem;
    mnuAssignGroups: TMenuItem;
    mnuEdit: TMenuItem;
    mnuEditItem: TMenuItem;
    pgcMain: TPageControl;
    tsData: TTabSheet;
    tsReports: TTabSheet;
    btnEditItem: TButton;
    btnRunReports: TButton;
    alMain: TActionList;
    actReports: TAction;
    tmrNag: TTimer;
    qryItems: TDataSet;
    tsMore: TTabSheet;
    btnImport: TButton;
    btnMdi: TButton;
    btnPanel: TButton;
    btnSerial: TButton;
    btnCache: TButton;
    procedure mnuAssignGroupsClick(Sender: TObject);
    procedure btnEditItemClick(Sender: TObject);
    procedure actReportsExecute(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnImportClick(Sender: TObject);
    procedure btnMdiClick(Sender: TObject);
    procedure btnPanelClick(Sender: TObject);
    procedure btnSerialClick(Sender: TObject);
    procedure btnCacheClick(Sender: TObject);
  private
    FVM: IImportVM6;
    FCache: TfrmCache6;
    procedure DoNagTimer(Sender: TObject);
  end;

var
  frmMain6: TfrmMain6;

implementation

{$R *.dfm}

procedure TfrmMain6.mnuAssignGroupsClick(Sender: TObject);
begin
  if qryItems.FieldByName('ID').IsNull then Exit;
  OpenAssignGroups;
end;

procedure TfrmMain6.btnEditItemClick(Sender: TObject);
var
  F: TfrmEdit6;
begin
  F := TfrmEdit6.Create(Self);
  try
    F.ItemId := qryItems.FieldByName('ID').AsInteger;
    F.ShowModal;
  finally
    F.Free;
  end;
end;

procedure TfrmMain6.actReportsExecute(Sender: TObject);
begin
  frmReports6 := TfrmReports6.Create(Self);
  frmReports6.Show;
end;

procedure TfrmMain6.FormCreate(Sender: TObject);
begin
  tmrNag.OnTimer := DoNagTimer;
end;

procedure TfrmMain6.DoNagTimer(Sender: TObject);
begin
  TfrmNag6.Create(Self).ShowModal;
end;

procedure TfrmMain6.btnImportClick(Sender: TObject);
begin
  FVM := TImportVM6.Create;
  FVM.OpenImport;
end;

procedure TfrmMain6.btnMdiClick(Sender: TObject);
begin
  TfrmMdi6.Create(Application);
end;

procedure TfrmMain6.btnPanelClick(Sender: TObject);
begin
  frmPanel6 := TfrmPanel6.Create(Self);
end;

procedure TfrmMain6.btnSerialClick(Sender: TObject);
var
  F: TfrmSerial6;
begin
  if qryItems.IsEmpty then raise EInvalidOpException.Create('Add an item before defining serial numbers');
  F := TfrmSerial6.Create(Self);
  try
    F.Execute(1);
  finally
    F.Free;
  end;
end;

procedure TfrmMain6.btnCacheClick(Sender: TObject);
begin
  FCache := TfrmCache6.Create(Self);
end;

end.