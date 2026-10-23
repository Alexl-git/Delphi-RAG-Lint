unit MT.Dynamic;

{ menu-tree fixture: a caption the reader cannot evaluate (one dynamic node +
  a note) and an item that is created but never parented (a note, in no root).
  Compiled, never run. }

interface

uses
  Vcl.Menus;

procedure BuildDynamicMenu(MainMenu: TMainMenu);

implementation

uses
  System.SysUtils;

type
  TDynHandlers = class
    class procedure DoStatic(Sender: TObject);
    class procedure DoDynamic(Sender: TObject);
  end;

class procedure TDynHandlers.DoStatic(Sender: TObject);
begin
end;

class procedure TDynHandlers.DoDynamic(Sender: TObject);
begin
end;

procedure BuildDynamicMenu(MainMenu: TMainMenu);
var
  Root  : TMenuItem;
  Leaf  : TMenuItem;
  Dyn   : TMenuItem;
  Orphan: TMenuItem;
  SomeVar: string;
begin
  SomeVar:= ExtractFileName(ParamStr(0));
  Root:= TMenuItem.Create(nil);
  Root.Caption:= 'Fixture Dynamic';
  MainMenu.Items.Add(Root);

  Leaf:= TMenuItem.Create(Root);
  Leaf.Caption:= 'Static Leaf';
  Leaf.OnClick:= TDynHandlers.DoStatic;
  Root.Add(Leaf);

  Dyn:= TMenuItem.Create(Root);
  Dyn.Caption:= SomeVar;
  Dyn.OnClick:= TDynHandlers.DoDynamic;
  Root.Add(Dyn);

  Orphan:= TMenuItem.Create(Root);
  Orphan.Caption:= 'Orphan Item';
end;

end.
