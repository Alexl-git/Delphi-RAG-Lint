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
  Winapi.Windows, Winapi.ShellAPI,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ActnList,
  Vcl.ImgList, Vcl.Menus,
  Vcl.ExtCtrls,
  DesignIntf,   { TEditState / TEditAction }
  ToolsAPI,
  DragLint.Plugin.StructureForm,
  DragLint.Plugin.UsagesForm,
  DragLint.Plugin.SymbolSearchForm,
  DragLint.Plugin.DbResolver,
  DragLint.Plugin.Settings;

{$R *.dfm}

type
  { v0.42: the dock panel hosts a tabbed view of the drag-lint tools, matching
    the delphi-terminal sample's single-window-with-tabs layout: Structure,
    Find Usages, Symbol Search (all live) + a Graph launcher. The form-reparent
    embeds (Structure, Find Usages) are built in HandleInitTimer, one message
    turn after construction, because reparenting a TForm while the IDE is still
    constructing the dock host AV'd. }
  TDragLintDockFrame = class(TCustomFrame)
  private
    FPages:      TPageControl;
    FStructure:  TForm;          { embedded TDragLintStructureForm }
    FTabStruct:  TTabSheet;
    FTabUsages:  TTabSheet;
    FTabSearch:  TTabSheet;
    FTabGraph:   TTabSheet;
    FInited:     Boolean;
    FInitTimer:  TTimer;         { v0.42: defers the embed off the ctor }
    procedure HandlePageChange(Sender: TObject);
    procedure HandleInitTimer(Sender: TObject);
    procedure HandleOpenGraph(Sender: TObject);
    function  AddTab(const ACaption: string): TTabSheet;
    procedure AddPlaceholder(ATab: TTabSheet; const AText: string);
    function  ResolveExe: string;
    function  ResolveDbArgs: string;
    procedure BuildGraphTab(ATab: TTabSheet);
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

function TDragLintDockFrame.AddTab(const ACaption: string): TTabSheet;
begin
  Result := TTabSheet.Create(FPages);
  Result.PageControl := FPages;
  Result.Caption := ACaption;
end;

procedure TDragLintDockFrame.AddPlaceholder(ATab: TTabSheet; const AText: string);
var
  L: TLabel;
begin
  L := TLabel.Create(ATab);
  L.Parent    := ATab;
  L.Align     := alClient;
  L.Alignment := taCenter;
  L.Layout    := tlCenter;
  L.WordWrap  := True;
  L.Caption   := AText;
end;

function TDragLintDockFrame.ResolveExe: string;
begin
  Result := LoadSettings.ExePath;
  if (Result = '') or not FileExists(Result) then
    Result := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(Result) then
    Result := 'drag-lint.exe';
end;

function TDragLintDockFrame.ResolveDbArgs: string;
var
  Dbs: TArray<string>;
  P:   string;
begin
  Result := '';
  try
    Dbs := ResolveActiveIndexDbs(LoadSettings);
  except
    SetLength(Dbs, 0);
  end;
  for P in Dbs do
    if P <> '' then
      Result := Result + Format(' --db "%s"', [P]);
end;

procedure TDragLintDockFrame.HandleOpenGraph(Sender: TObject);
var
  Exe: string;
begin
  { Launch the standalone graph viewer if present next to the BPL / exe. True
    in-dock embedding is a separate cross-BPL effort. }
  Exe := ExtractFilePath(GetModuleName(HInstance)) + 'DragLintGraphViewer.exe';
  if not FileExists(Exe) then
    Exe := ExtractFilePath(ResolveExe) + 'DragLintGraphViewer.exe';
  if FileExists(Exe) then
    ShellExecute(0, 'open', PChar(Exe), nil, PChar(ExtractFilePath(Exe)), SW_SHOWNORMAL)
  else
    MessageBox(0,
      'Graph viewer (DragLintGraphViewer.exe) was not found next to the plugin.'#13#10 +
      'Build/copy it there, or open it from its own project for now.',
      'drag-lint', MB_OK or MB_ICONINFORMATION);
end;

procedure TDragLintDockFrame.BuildGraphTab(ATab: TTabSheet);
var
  Btn: TButton;
  L:   TLabel;
begin
  L := TLabel.Create(ATab);
  L.Parent    := ATab;
  L.Align     := alTop;
  L.WordWrap  := True;
  L.Caption   := ' The graph viewer is a separate window. In-dock embedding is '
    + 'planned; for now launch it here:';
  L.Height    := 40;

  Btn := TButton.Create(ATab);
  Btn.Parent  := ATab;
  Btn.Align   := alTop;
  Btn.Height  := 30;
  Btn.Caption := 'Open Graph Viewer';
  Btn.OnClick := HandleOpenGraph;
end;

constructor TDragLintDockFrame.Create(AOwner: TComponent);
begin
  inherited;

  FPages := TPageControl.Create(Self);
  FPages.Parent   := Self;
  FPages.Align    := alClient;
  FPages.OnChange := HandlePageChange;

  { Tabs are created here (empty); the form-reparent embeds (Structure, Find
    Usages) are filled in HandleInitTimer, one message turn later, because
    reparenting a TForm during the IDE's dock construction AV'd. Symbol Search
    (native controls) + Graph (a button) are safe to build immediately. }
  FTabStruct := AddTab('Structure');
  FTabUsages := AddTab('Find Usages');
  FTabSearch := AddTab('Symbol Search');
  FTabGraph  := AddTab('Graph');

  BuildGraphTab(FTabGraph);

  FPages.ActivePage := FTabStruct;

  FInitTimer := TTimer.Create(Self);
  FInitTimer.Interval := 50;
  FInitTimer.OnTimer  := HandleInitTimer;
  FInitTimer.Enabled  := True;
end;

procedure TDragLintDockFrame.HandleInitTimer(Sender: TObject);
begin
  FInitTimer.Enabled := False;
  if FInited then Exit;
  FInited := True;

  try
    FStructure := CreateEmbeddedStructure(Self, FTabStruct);
  except
    on E: Exception do
    begin
      FStructure := nil;
      AddPlaceholder(FTabStruct, 'Structure failed to load: ' + E.Message);
    end;
  end;

  try
    CreateEmbeddedUsages(Self, FTabUsages);
  except
    on E: Exception do
      AddPlaceholder(FTabUsages, 'Find Usages failed to load: ' + E.Message);
  end;

  try
    CreateEmbeddedSymbolSearch(Self, FTabSearch, ResolveExe, ResolveDbArgs);
  except
    on E: Exception do
      AddPlaceholder(FTabSearch, 'Symbol Search failed to load: ' + E.Message);
  end;
end;

procedure TDragLintDockFrame.HandlePageChange(Sender: TObject);
begin
  { Re-read the active editor file whenever the Structure tab comes forward. }
  if (FPages.ActivePage = FTabStruct) and (FStructure <> nil) then
    RefreshEmbeddedStructure(FStructure);
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
