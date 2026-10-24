unit uMain8;

{ forms-csv v8 fixture root form. Its .dfm declares mnuMain > mnuTools with ONE
  design-time child (Design Item); FormCreate adds three more in code: a direct
  item, an item through the uMenuUtils8 helper, and a submenu with a child. }

interface

uses
  System.Classes
  , Vcl.Forms
  , Vcl.Menus
  , Vcl.StdCtrls
  , uMenuUtils8
  , uDesign8
  , uReports8
  , uExport8
  , uDeep8
  , uSide8
  ;

type
  TfrmMain8 = class(TForm)
    mnuMain: TMainMenu;
    mnuTools: TMenuItem;
    mnuDesign: TMenuItem;
    btnSide: TButton;
    procedure FormCreate(Sender: TObject);
    procedure mnuDesignClick(Sender: TObject);
    procedure btnSideClick(Sender: TObject);
  private
    procedure mnuCodeReportsClick(Sender: TObject);
    procedure mnuHelperExportClick(Sender: TObject);
    procedure mnuDeepClick(Sender: TObject);
  end;

var
  frmMain8: TfrmMain8;

implementation

{$R *.dfm}

procedure TfrmMain8.FormCreate(Sender: TObject);
var
  X  : TMenuItem;
  Sub: TMenuItem;
  Z  : TMenuItem;
begin
  X:= TMenuItem.Create(Self);
  X.Caption:= 'Code &Reports';
  X.OnClick:= mnuCodeReportsClick;
  mnuTools.Add(X);
  AddMenuItem(mnuTools, 'Helper Export', mnuHelperExportClick);
  Sub:= TMenuItem.Create(Self);
  Sub.Caption:= 'More';
  mnuTools.Add(Sub);
  Z:= TMenuItem.Create(Self);
  Z.Caption:= 'Deep Item';
  Z.OnClick:= mnuDeepClick;
  Sub.Add(Z);
end;

procedure TfrmMain8.mnuDesignClick(Sender: TObject);
begin
  TfrmDesign8.Create(Self).ShowModal;
end;

procedure TfrmMain8.btnSideClick(Sender: TObject);
begin
  TfrmSide8.Create(Self).ShowModal;
end;

procedure TfrmMain8.mnuCodeReportsClick(Sender: TObject);
begin
  TfrmReports8.Create(Self).ShowModal;
end;

procedure TfrmMain8.mnuHelperExportClick(Sender: TObject);
begin
  TfrmExport8.Create(Self).ShowModal;
end;

procedure TfrmMain8.mnuDeepClick(Sender: TObject);
begin
  TfrmDeep8.Create(Self).ShowModal;
end;

end.
