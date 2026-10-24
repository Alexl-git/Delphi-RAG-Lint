unit uGridPopup9;

{ dxBar fixture: a popup built in a NON-form unit (the uGridPopup.pas shape):
  `with pop.ItemLinks.Add do begin BeginGroup := True; Item := btn end`,
  ItemLinks.Insert(0) of a sub-item, ItemLinks.Add(X) and ItemLinks.AddButton.
  No .dfm declares popGridMenu9, so it stays an external root. }

interface

uses
  System.Classes
  , dxBar
  ;

type
  TGridPopup9 = class
  public
    { a TdxBarManager parameter is context, not a link owner: Build is a builder, not a helper }
    procedure Build(pOwner: TComponent; pMgr: TdxBarManager);
    procedure DoCopy(Sender: TObject);
    procedure DoLayout(Sender: TObject);
  end;

var
  popGridMenu9: TdxBarPopupMenu;

implementation

procedure TGridPopup9.Build(pOwner: TComponent; pMgr: TdxBarManager);
var
  btn: TdxBarButton;
  sub: TdxBarSubItem;
  L  : TdxBarItemLink;
begin
  { the popup itself is created here, as uGridPopup.pas does: its links must
    still land in an external root named popGridMenu9 }
  popGridMenu9:= TdxBarPopupMenu.Create(pOwner);
  popGridMenu9.BarManager:= pMgr;
  btn:= TdxBarButton.Create(pOwner);
  btn.Caption:= 'Copy Cell';
  btn.OnClick:= DoCopy;
  with popGridMenu9.ItemLinks.Add do
  begin
    BeginGroup:= True;
    Item:= btn;
  end;
  sub:= TdxBarSubItem.Create(pOwner);
  sub.Caption:= 'Select Layout';
  popGridMenu9.ItemLinks.Insert(0).Item:= sub;
  btn:= TdxBarButton.Create(pOwner);
  btn.Caption:= 'Default Layout';
  btn.OnClick:= DoLayout;
  sub.ItemLinks.Add(btn);
  L:= sub.ItemLinks.AddButton;
  L.Item.Caption:= 'Saved Layout';
  L.Item.OnClick:= DoLayout;
end;

procedure TGridPopup9.DoCopy(Sender: TObject);
begin
end;

procedure TGridPopup9.DoLayout(Sender: TObject);
begin
end;

end.
