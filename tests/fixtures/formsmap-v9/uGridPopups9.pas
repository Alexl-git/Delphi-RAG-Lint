unit uGridPopups9;

{ dxBar fixture (dxbar2): TWO classes in ONE non-form unit, each with a FIELD
  called popGridMenu (the uGridPopup.pas shape). Each class builds its own
  popup, so menu-tree must give two external roots keyed by class + field
  (TGridMenu9.popGridMenu, TTreeMenu9.popGridMenu), never one merged root.

  Cross-routine sub-item children:
  - TGridMenu9.subLayouts is a FIELD created and linked in Create and filled in
    FillLayouts (another method of the same class, written BEFORE Create, so
    the walk meets the filler first);
  - TTreeMenu9 passes its local sub-item to AddViews(pSub) (parameter binding);
    TGridMenu9 declares an AddViews too, earlier in the file: the call must
    resolve to the caller's own class;
  - TTreeMenu9.Create also links a sub-item (Recent Views) whose items are
    added by a routine the project does not declare: it stays a header and
    the walk says so in a note.
  Both classes have a DoExport handler: each item names its own class. }

interface

uses
  System.Classes
  , dxBar
  ;

type
  TGridMenu9 = class
  private
    popGridMenu: TdxBarPopupMenu;
    subLayouts : TdxBarSubItem;
    procedure FillLayouts;
    procedure AddViews(pSub: TdxBarSubItem);
    procedure DoExport(Sender: TObject);
    procedure DoPickLayout(Sender: TObject);
  public
    constructor Create(pOwner: TComponent);
  end;

  TTreeMenu9 = class
  private
    popGridMenu: TdxBarPopupMenu;
    procedure AddViews(pSub: TdxBarSubItem);
    procedure DoExport(Sender: TObject);
    procedure DoPickView(Sender: TObject);
  public
    constructor Create(pOwner: TComponent);
  end;

implementation

procedure TGridMenu9.FillLayouts;
var
  L: TdxBarItemLink;
  B: TdxBarButton;
begin
  L:= subLayouts.ItemLinks.Add;
  B:= TdxBarButton.Create(popGridMenu);
  L.Item:= B;
  B.Caption:= 'Compact Layout';
  B.OnClick:= DoPickLayout;
end;

procedure TGridMenu9.AddViews(pSub: TdxBarSubItem);
var
  B: TdxBarButton;
begin
  B:= TdxBarButton.Create(pSub);
  B.Caption:= 'Wrong View';
  B.OnClick:= DoExport;
  pSub.ItemLinks.Add(B);
end;

constructor TGridMenu9.Create(pOwner: TComponent);
var
  btn: TdxBarButton;
begin
  popGridMenu:= TdxBarPopupMenu.Create(pOwner);
  btn:= TdxBarButton.Create(pOwner);
  btn.Caption:= 'Export Rows';
  btn.OnClick:= DoExport;
  popGridMenu.ItemLinks.Add.Item:= btn;
  subLayouts:= TdxBarSubItem.Create(pOwner);
  subLayouts.Caption:= 'Pick Layout';
  with popGridMenu.ItemLinks.Add do
  begin
    BeginGroup:= True;
    Item:= subLayouts;
  end;
end;

procedure TGridMenu9.DoExport(Sender: TObject);
begin
end;

procedure TGridMenu9.DoPickLayout(Sender: TObject);
begin
end;

constructor TTreeMenu9.Create(pOwner: TComponent);
var
  btn : TdxBarButton;
  sub : TdxBarSubItem;
  dead: TdxBarSubItem;
begin
  popGridMenu:= TdxBarPopupMenu.Create(pOwner);
  btn:= TdxBarButton.Create(pOwner);
  btn.Caption:= 'Export Nodes';
  btn.OnClick:= DoExport;
  popGridMenu.ItemLinks.Add.Item:= btn;
  sub:= TdxBarSubItem.Create(pOwner);
  sub.Caption:= 'Pick View';
  popGridMenu.ItemLinks.Add.Item:= sub;
  AddViews(sub);
  dead:= TdxBarSubItem.Create(pOwner);
  dead.Caption:= 'Recent Views';
  popGridMenu.ItemLinks.Add.Item:= dead;
  FillFromRegistry(dead);
end;

procedure TTreeMenu9.AddViews(pSub: TdxBarSubItem);
var
  B: TdxBarButton;
begin
  B:= TdxBarButton.Create(pSub);
  B.Caption:= 'Flat View';
  B.OnClick:= DoPickView;
  pSub.ItemLinks.Add(B);
end;

procedure TTreeMenu9.DoExport(Sender: TObject);
begin
end;

procedure TTreeMenu9.DoPickView(Sender: TObject);
begin
end;

end.
