unit uMain9;

{ dxBar menu reader fixture (spec 2026-10-24-dxbar-menus.md, T1). The .dfm
  declares a TdxBarManager with an IsMainMenu bar (sub-item Setup > Groups,
  action-bound, + BeginGroup Users), two ribbon tabs (Main, Lists), a
  Quick Access Toolbar bar, a TdxBarPopupMenu and backstage Buttons.
  FormCreate links more items in code: a button on the Lists bar through a
  local link, a sub-item inserted at 0 into Bars[0] (= the main-menu bar)
  with a static and a data-driven child, and a popup button through the
  uBarUtils9 helper. }

interface

uses
  System.Classes
  , Vcl.Forms
  , Vcl.ActnList
  , dxBar
  , dxRibbon
  , dxRibbonBackstageView
  , uBarUtils9
  , uA9
  , uB9
  , uC9
  , uD9
  , uE9
  , uF9
  ;

type
  TfrmMain9 = class(TForm)
    dxBarManager1: TdxBarManager;
    barMainMenu: TdxBar;
    barLists: TdxBar;
    barHome: TdxBar;
    barQAT: TdxBar;
    subSetup: TdxBarSubItem;
    btnGroups: TdxBarButton;
    btnUsers: TdxBarButton;
    btnCustomers: TdxBarLargeButton;
    btnSuppliers: TdxBarButton;
    btnHome: TdxBarButton;
    lblInfo: TdxBarStatic;
    btnOrphan: TdxBarButton;
    btnOptions: TdxBarButton;
    btnExit: TdxBarButton;
    ActionList1: TActionList;
    actGroups: TAction;
    dxRibbon1: TdxRibbon;
    tabHome: TdxRibbonTab;
    tabLists: TdxRibbonTab;
    popGrid: TdxBarPopupMenu;
    dxRibbonBackstageView1: TdxRibbonBackstageView;
    procedure FormCreate(Sender: TObject);
    procedure actGroupsExecute(Sender: TObject);
    procedure btnUsersClick(Sender: TObject);
    procedure btnCustomersClick(Sender: TObject);
    procedure btnSuppliersClick(Sender: TObject);
    procedure btnHomeClick(Sender: TObject);
    procedure btnOrphanClick(Sender: TObject);
    procedure btnOptionsClick(Sender: TObject);
    procedure btnExitClick(Sender: TObject);
  private
    FPresetNames: TStringList;
    procedure btnVendorsClick(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure btnPresetClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
  end;

var
  frmMain9: TfrmMain9;

implementation

{$R *.dfm}

procedure TfrmMain9.FormCreate(Sender: TObject);
var
  Btn: TdxBarButton;
  Sub: TdxBarSubItem;
  L  : TdxBarItemLink;
  I  : Integer;
begin
  Btn:= TdxBarButton.Create(Self);
  Btn.Caption:= 'Vendor List';
  Btn.OnClick:= btnVendorsClick;
  L:= barLists.ItemLinks.Add;
  L.Item:= Btn;

  Sub:= TdxBarSubItem.Create(Self);
  Sub.Caption:= 'Presets';
  with TdxBarItemLink(dxBarManager1.Bars[0].ItemLinks.Insert(0)) do
    Item:= Sub;
  Btn:= TdxBarButton.Create(Self);
  Btn.Caption:= 'Reset Presets';
  Btn.OnClick:= btnResetClick;
  Sub.ItemLinks.Add(Btn);
  for I:= 0 to FPresetNames.Count - 1 do
  begin
    Btn:= TdxBarButton.Create(Self);
    Btn.Caption:= FPresetNames[I];
    Btn.OnClick:= btnPresetClick;
    with Sub.ItemLinks.Add do
      Item:= Btn;
  end;

  AddBarButton(popGrid, 'Export Grid', btnExportClick);
end;

procedure TfrmMain9.actGroupsExecute(Sender: TObject);
begin
  TfrmA9.Create(Self).ShowModal;
end;

procedure TfrmMain9.btnUsersClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain9.btnCustomersClick(Sender: TObject);
begin
  TfrmB9.Create(Self).ShowModal;
end;

procedure TfrmMain9.btnSuppliersClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain9.btnHomeClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain9.btnOrphanClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain9.btnOptionsClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain9.btnExitClick(Sender: TObject);
begin
  TfrmF9.Create(Self).ShowModal;
end;

procedure TfrmMain9.btnVendorsClick(Sender: TObject);
begin
  TfrmC9.Create(Self).ShowModal;
end;

procedure TfrmMain9.btnResetClick(Sender: TObject);
begin
  TfrmD9.Create(Self).ShowModal;
end;

procedure TfrmMain9.btnPresetClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain9.btnExportClick(Sender: TObject);
begin
  TfrmE9.Create(Self).ShowModal;
end;

end.
