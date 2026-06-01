unit DragLint.Plugin.DockForm;

{ Dockable IDE panel prototype (Phase 3/4 host).

  Proves the OTAPI dockable-window mechanism works: a panel you can park at the
  bottom of the IDE like the GExperts Grep Results window.  For now it shows
  placeholder content; the scoped symbol-search results (Phase 3) and the graph
  (Phase 4) will be hosted in this frame once docking is confirmed.

  Mechanism: implement INTACustomDockableForm, RegisterDockableForm once, then
  CreateDockableForm to get a dockable TCustomForm.  A FreeNotification watcher
  nils our form variable if the IDE frees the panel (no dangling pointer) --
  version-independent (the older RegisterFieldAddress is not in this ToolsAPI).
  Teardown unregisters the dockable form -- same defensive shutdown discipline
  as the rest of the plugin (avoids unload AVs). }

interface

procedure ShowDragLintDock;        { open / focus the dockable panel }
procedure UnregisterDragLintDock;  { idempotent teardown }

implementation

uses
  System.SysUtils, System.Classes, System.IniFiles, System.Actions,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ActnList,
  Vcl.ImgList, Vcl.Menus,
  DesignIntf,   { TEditState / TEditAction }
  ToolsAPI;

type
  TDragLintDockFrame = class(TCustomFrame)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TDragLintDockable = class(TInterfacedObject, INTACustomDockableForm)
  public
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolBarActionList: TCustomActionList;
    function GetToolBarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string;
      IsProject: Boolean);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
  end;

  { Nils GForm when the IDE frees the panel, so a later Show cannot touch a
    dangling pointer.  (Replaces the older RegisterFieldAddress mechanism.) }
  TFormWatch = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent;
      Operation: TOperation); override;
  end;

const
  DOCK_IDENTIFIER = 'DragLintDockable';

var
  GDockable:    INTACustomDockableForm = nil;
  GForm:        TCustomForm = nil;
  GRegistered:  Boolean = False;
  GWatch:       TFormWatch = nil;

{ ---- frame (placeholder content) ---------------------------------------- }

constructor TDragLintDockFrame.Create(AOwner: TComponent);
var
  L: TLabel;
  M: TMemo;
begin
  inherited;
  L := TLabel.Create(Self);
  L.Parent  := Self;
  L.Align   := alTop;
  L.Layout  := tlCenter;
  L.Height  := 22;
  L.Caption := '  drag-lint dockable panel -- docking works. Park me at the '
    + 'bottom like Grep.';

  M := TMemo.Create(Self);
  M.Parent     := Self;
  M.Align      := alClient;
  M.ReadOnly   := True;
  M.ScrollBars := ssBoth;
  M.WordWrap   := False;
  M.Lines.Add('Prototype panel hosted via INTACustomDockableForm.');
  M.Lines.Add('');
  M.Lines.Add('Next: Phase 3 scoped symbol search (project / current form /');
  M.Lines.Add('everywhere) renders results here; Phase 4 hosts the graph.');
end;

{ ---- free watcher -------------------------------------------------------- }

procedure TFormWatch.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = GForm) then
    GForm := nil;
end;

{ ---- INTACustomDockableForm --------------------------------------------- }

function TDragLintDockable.GetCaption: string;
begin
  Result := 'drag-lint';
end;

function TDragLintDockable.GetIdentifier: string;
begin
  Result := DOCK_IDENTIFIER;
end;

function TDragLintDockable.GetFrameClass: TCustomFrameClass;
begin
  Result := TDragLintDockFrame;
end;

procedure TDragLintDockable.FrameCreated(AFrame: TCustomFrame);
begin
end;

function TDragLintDockable.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TDragLintDockable.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TDragLintDockable.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TDragLintDockable.GetToolBarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TDragLintDockable.GetToolBarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TDragLintDockable.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TDragLintDockable.SaveWindowState(Desktop: TCustomIniFile;
  const Section: string; IsProject: Boolean);
begin
end;

procedure TDragLintDockable.LoadWindowState(Desktop: TCustomIniFile;
  const Section: string);
begin
end;

function TDragLintDockable.GetEditState: TEditState;
begin
  Result := [];
end;

function TDragLintDockable.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

{ ---- show / teardown ----------------------------------------------------- }

procedure ShowDragLintDock;
var
  NTA: INTAServices;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTA) then Exit;

  if GWatch = nil then
    GWatch := TFormWatch.Create(nil);

  if GDockable = nil then
    GDockable := TDragLintDockable.Create;
  if not GRegistered then
  begin
    NTA.RegisterDockableForm(GDockable);
    GRegistered := True;
  end;

  if GForm = nil then
  begin
    GForm := NTA.CreateDockableForm(GDockable);
    if GForm <> nil then
      GForm.FreeNotification(GWatch);
  end;

  if GForm <> nil then
  begin
    if GForm.WindowState = wsMinimized then
      GForm.WindowState := wsNormal;
    GForm.Show;
  end;
end;

procedure UnregisterDragLintDock;
var
  NTA: INTAServices;
begin
  if Supports(BorlandIDEServices, INTAServices, NTA) then
  begin
    if GRegistered and (GDockable <> nil) then
    begin
      try NTA.UnregisterDockableForm(GDockable); except end;
      GRegistered := False;
    end;
  end;
  GForm := nil;        { owned/freed by the IDE }
  GDockable := nil;
  FreeAndNil(GWatch);
end;

initialization

finalization
  try UnregisterDragLintDock; except end;

end.
