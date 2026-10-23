unit MT.Builder;

{ menu-tree fixture: the RegisterDragLintMenu shape -- a Create(nil) root put
  on the main menu (or, failing that, under Tools), item / separator / header
  helpers, inline-var submenus, Format and const captions, a direct item with
  a wrapper, Insert, and the catalog builder with anonymous-method factories.
  Compiled, never run. }

interface

uses
  Vcl.Menus;

procedure BuildMainMenu(MainMenu: TMainMenu);

implementation

uses
  System.SysUtils
  , MT.Wrapper
  , MT.Catalog
  ;

const
  CAP_EXPORT = 'Export Everything';

procedure DoOpen(Sender: TObject);    begin end;
procedure DoFind(Sender: TObject);    begin end;
procedure DoExport(Sender: TObject);  begin end;
procedure DoFormat(Sender: TObject);  begin end;
procedure DoCatalog(Sender: TObject); begin end;
procedure DoDirect(Sender: TObject);  begin end;
procedure DoAbout(Sender: TObject);   begin end;

{ A stand-in for INTAServices.AddActionMenu: takes a TMenuItem, builds nothing. }
procedure AddActionMenu(const pName: string; pAction: TObject; pItem: TMenuItem; pBefore, pChild: Boolean);
begin
end;

function AddItem(pParent: TMenuItem; const pCaption: string; pProc: TMenuProc): TMenuItem;
var
  W: TClickWrapper;
begin
  Result:= TMenuItem.Create(pParent);
  Result.Caption:= pCaption;
  W:= TClickWrapper.Create(pProc);
  Result.OnClick:= W.HandleClick;
  pParent.Add(Result);
end;

function AddSep(pParent: TMenuItem): TMenuItem;
begin
  Result:= TMenuItem.Create(pParent);
  Result.Caption:= '-';
  pParent.Add(Result);
end;

function AddHeader(pParent: TMenuItem; const pCaption: string): TMenuItem;
begin
  Result:= TMenuItem.Create(pParent);
  Result.Caption:= pCaption;
  Result.Enabled:= False;
  pParent.Add(Result);
end;

procedure BuildMainMenu(MainMenu: TMainMenu);
var
  Root  : TMenuItem;
  Direct: TMenuItem;
  Wrap  : TClickWrapper;
begin
  Root:= TMenuItem.Create(nil);
  Root.Caption:= 'Fixture';
  if MainMenu <> nil then MainMenu.Items.Add(Root)
  else AddActionMenu('ToolsMenu', nil, Root, True, True);

  AddItem(Root, 'Open...', DoOpen);
  AddSep(Root);
  AddItem(Root, Format('Find %s...', ['Text']), DoFind);
  AddItem(Root, CAP_EXPORT, DoExport);

  var SubTools: TMenuItem:= TMenuItem.Create(Root);
  SubTools.Caption:= 'Tools && Options';
  Root.Add(SubTools);
  AddHeader(SubTools, 'Formatting');
  AddItem(SubTools, 'Format Unit', DoFormat);

  var SubCat: TMenuItem:= TMenuItem.Create(Root);
  SubCat.Caption:= 'Catalog';
  Root.Add(SubCat);
  BuildCatalogMenu(SubCat,
    function(AParent: TMenuItem; const ACaption: string): TMenuItem
    begin
      Result:= AddItem(AParent, ACaption, DoCatalog);
    end,
    procedure(AParent: TMenuItem; const ACaption: string)
    begin
      AddHeader(AParent, ACaption);
    end);

  Direct:= TMenuItem.Create(Root);
  Direct.Caption:= 'Direct ' + 'Item';
  Wrap:= TClickWrapper.Create(DoDirect);
  Direct.OnClick:= Wrap.HandleClick;
  Root.Insert(0, Direct);

  AddSep(Root);
  AddItem(Root, 'About', DoAbout);
end;

end.
