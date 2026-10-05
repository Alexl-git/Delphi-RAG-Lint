unit uMain6;

interface

uses
  System.Classes, Data.DB, Vcl.Forms, Vcl.Menus, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.ActnList, Vcl.ExtCtrls, uHelpers6, uEdit6, uReports6, uNag6;

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
    procedure mnuAssignGroupsClick(Sender: TObject);
    procedure btnEditItemClick(Sender: TObject);
    procedure actReportsExecute(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    procedure DoNagTimer(Sender: TObject);
  end;

var
  frmMain6: TfrmMain6;

implementation

{$R *.dfm}

procedure TfrmMain6.mnuAssignGroupsClick(Sender: TObject);
begin
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

end.