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

procedure ShowDragLintDock; { open / focus the dockable panel }
procedure RegisterDragLintDockable; { register at startup so the IDE restores a saved docked instance }
procedure UnregisterDragLintDock; { idempotent teardown }

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IniFiles
  , System.Actions
  , Winapi.Windows
  , Winapi.ShellAPI
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.ComCtrls
  , Vcl.ActnList
  , Vcl.ImgList
  , Vcl.Menus
  , Vcl.ExtCtrls
  , DesignIntf
  , { TEditState / TEditAction }
    ToolsAPI
  , DragLint.Plugin.StructureForm
  , DragLint.Plugin.DiagnosticCache
  , DragLint.Plugin.Telemetry
  , { TEMP debug telemetry }
    DragLint.Plugin.UsagesForm
  , DragLint.Plugin.SearchForm
  , DragLint.Plugin.GraphWindow
  , DragLint.Plugin.DbResolver
  , DragLint.Plugin.EditViewNotifier
  , { v0.47: ForceGutterRepaint }
    DragLint.Plugin.Settings
  , DragLint.Plugin.JobQueue
  , DragLint.Plugin.StatusBar
  ;

{$R *.dfm}

type { v0.42: the dock panel hosts a tabbed view of the drag-lint tools:
    Structure, Search (no grep), and Find Usages. The form-reparent embeds
    (Structure, Find Usages) are built in HandleInitTimer, one message turn
    after construction, because reparenting a TForm while the IDE is still
    constructing the dock host AV'd. }
  TDragLintDockFrame = class(TCustomFrame)
    private
      FPages         : TPageControl;
      FStatusBar     : TDragLintStatusBar; { v0.65.1: R2 job-queue status strip (alBottom) }
      FStructure     : TForm       ; { embedded TDragLintStructureForm }
      FTabStruct          : TTabSheet   ;
      FTabUnifiedSearch   : TTabSheet   ;
      FTabUsages          : TTabSheet   ;
      FTabGraph           : TTabSheet   ;
      FInited        : Boolean     ;
      FInitTimer     : TTimer      ; { v0.42: defers the embed off the ctor }
      FWatchTimer    : TTimer      ; { v0.46: auto-refresh Structure on code-tab switch }
      FLastStructFile: string      ;
      FLastDiagCount : Integer     ; { v0.46: refresh Diagnostics node when cache changes }
      procedure HandlePageChange(Sender: TObject);
      procedure HandleInitTimer (Sender: TObject);
      procedure HandleWatchTimer(Sender: TObject);
      procedure HandleOpenGraph (Sender: TObject);
      function AddTab(const ACaption: string): TTabSheet;
      procedure AddPlaceholder(ATab: TTabSheet; const AText: string);
      function ResolveExe   : string;
      function ResolveDbArgs: string;
      procedure BuildGraphTab(ATab: TTabSheet);
    public
      constructor Create(AOwner: TComponent); override;
  end;

  TDragLintDockable = class(TInterfacedObject, INTACustomDockableForm)
    public
      function GetCaption   : string;
      function GetIdentifier: string;
      function GetFrameClass: TCustomFrameClass;
      procedure FrameCreated(AFrame: TCustomFrame);
      function GetMenuActionList: TCustomActionList;
      function GetMenuImageList : TCustomImageList;
      procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
      function GetToolBarActionList: TCustomActionList;
      function GetToolBarImageList : TCustomImageList;
      procedure CustomizeToolBar(ToolBar: TToolBar);
      procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
      procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
      function GetEditState: TEditState                ;
      function EditAction(Action: TEditAction): Boolean;
  end;

  { Nils GForm when the IDE frees the panel, so a later Show cannot touch a
    dangling pointer.  (Replaces the older RegisterFieldAddress mechanism.) }
  TFormWatch = class(TComponent)
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

const
  DOCK_IDENTIFIER = 'DragLintDockable';

var
  GDockable  : INTACustomDockableForm = nil;
  GForm      : TCustomForm            = nil           ;
  GRegistered: Boolean                = False             ;
  GWatch     : TFormWatch             = nil            ;

  { ---- frame (placeholder content) ---------------------------------------- }

function TDragLintDockFrame.AddTab(const ACaption: string): TTabSheet;
begin
  Result:= TTabSheet.Create(FPages);
  Result.PageControl:= FPages;
  Result.Caption    := ACaption;
end;

procedure TDragLintDockFrame.AddPlaceholder(ATab: TTabSheet; const AText: string);
var
  L: TLabel;
begin
  L:= TLabel.Create(ATab);
  L.Parent   := ATab;
  L.Align    := alClient;
  L.Alignment:= taCenter;
  L.Layout   := tlCenter;
  L.WordWrap := True;
  L.Caption  := AText;
end;

function TDragLintDockFrame.ResolveExe: string;
begin
  Result:= LoadSettings.ExePath;
  if (Result = '') or not FileExists(Result) then Result:= ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(Result) then Result:= 'drag-lint.exe';
end;

function TDragLintDockFrame.ResolveDbArgs: string;
var
  Dbs: TArray<string>;
  P  : string        ;
begin
  Result:= '';
  try
    Dbs:= ResolveActiveIndexDbs(LoadSettings);
  except
    SetLength(Dbs, 0);
  end;
  for P in Dbs do
    if P <> '' then Result:= Result + Format(' --db "%s"', [P]);
end;

procedure TDragLintDockFrame.HandleOpenGraph(Sender: TObject);
begin
  { v0.43: the graph now lives in its own dockable tool window so it can sit
    open beside Structure. Open that instead of launching a floating exe. }
  ShowDragLintGraph;
end;

procedure TDragLintDockFrame.BuildGraphTab(ATab: TTabSheet);
var
  Btn: TButton;
  L  : TLabel ;
begin
  L:= TLabel.Create(ATab);
  L.Parent  := ATab;
  L.Align   := alTop;
  L.WordWrap:= True;
  L.Caption:= ' The graph is a dedicated, dockable tool window (View > Tool ' + 'Windows > drag-lint Graph) so it can sit open beside Structure. Open it:';
  L.Height:= 48;

  Btn:= TButton.Create(ATab);
  Btn.Parent := ATab;
  Btn.Align  := alTop;
  Btn.Height := 30;
  Btn.Caption:= 'Open Graph Window';
  Btn.OnClick:= HandleOpenGraph;
end; // procedure

constructor TDragLintDockFrame.Create(AOwner: TComponent);
begin
  inherited;

  { v0.65.1: R2 job-queue status strip along the bottom, visible across all tabs.
    Created before the page control so the alClient pages fill the area above it. }
  FStatusBar:= TDragLintStatusBar.Create(Self);
  FStatusBar.Parent:= Self;

  FPages:= TPageControl.Create(Self);
  FPages.Parent  := Self;
  FPages.Align   := alClient;
  FPages.OnChange:= HandlePageChange;

  { Tabs are created here (empty); the form-reparent embeds (Structure,
    Find Usages) are filled in HandleInitTimer, one message turn later, because
    reparenting a TForm during the IDE's dock construction AV'd. }
  FTabStruct       := AddTab('Structure'      );
  FTabUnifiedSearch:= AddTab('Search (no grep)');
  FTabUsages       := AddTab('Find Usages'    );
  { v0.46: the Graph tab was removed -- the graph is now its own dockable tool
    window (View > Tool Windows > drag-lint Graph), so the in-dock launcher tab
    was just stale clutter. }

  FPages.ActivePage:= FTabStruct;

  FInitTimer:= TTimer.Create(Self);
  FInitTimer.Interval:= 50;
  FInitTimer.OnTimer := HandleInitTimer;
  FInitTimer.Enabled := True;

  { v0.46: auto-refresh the Structure tab when the active code unit changes
    (switching editor tabs), not only when the Structure tab is re-selected. }
  FWatchTimer:= TTimer.Create(Self);
  FWatchTimer.Interval:= 400;
  FWatchTimer.OnTimer := HandleWatchTimer;
  FWatchTimer.Enabled := True;
end; // constructor

procedure TDragLintDockFrame.HandleWatchTimer(Sender: TObject);
var
  ES     : IOTAEditorServices;
  Buf    : IOTAEditBuffer    ;
  CurFile: string            ;
begin
  if (FStructure = nil) or (FPages = nil) then Exit;
  if FPages.ActivePage <> FTabStruct then Exit; { only when Structure is shown }
  CurFile:= '';
  try
    if Supports(BorlandIDEServices, IOTAEditorServices, ES) and (ES <> nil) then
    begin
      Buf:= ES.TopBuffer;
      if Buf <> nil then CurFile:= Buf.FileName;
    end;
  except
    Exit;
  end;
  if (CurFile <> '') and not SameText(CurFile, FLastStructFile) then
  begin
    FLastStructFile:= CurFile;
    FLastDiagCount:= Length(Cache.GetForFile(CurFile));
    DLT('dock', Format('watch: file change -> %s (full structure refresh)', [ExtractFileName(CurFile)]));
    try RefreshEmbeddedStructure(FStructure); except end;
    Exit;
  end;

  { v0.46: same file, but the lint may have populated the cache AFTER the last
    full refresh -> update just the Diagnostics node when the count changes.
    Fixes "Diagnostics (0)" while the gutter already shows the markers. }
  if CurFile <> '' then
  begin
    var DiagN: Integer:= Length(Cache.GetForFile(CurFile));
    if DiagN <> FLastDiagCount then
    begin
      DLT('dock', Format('watch: diag count %d -> %d for %s (diag-only refresh)', [FLastDiagCount, DiagN, ExtractFileName(CurFile)]));
      FLastDiagCount:= DiagN;
      try RefreshEmbeddedStructureDiagnostics(FStructure); except end;
      { v0.47: the diagnostic cache changed -> also force the editor gutter to
        redraw from this reliable 400ms timer context, as a fallback in case a
        path's immediate ForceGutterRepaint was missed. }
      try ForceGutterRepaint; except end;
    end;
  end;

  { v0.48: a compile just pushed findings -> auto-scroll the embedded Structure to
    the Diagnostics section (if it has any), once. The flag is set by the compile
    and consumed here regardless of whether the diag count changed, so even a
    same-count refresh still jumps. Honors AutoJumpToDiagnostics. }
  if GScrollStructureToDiagPending then
  begin
    GScrollStructureToDiagPending:= False;
    if LoadSettings.AutoJumpToDiagnostics then
    begin
      try RefreshEmbeddedStructureDiagnostics(FStructure); except end;
      try ScrollEmbeddedStructureToDiagnostics(FStructure); except end;
    end;
  end;
end; // procedure

procedure TDragLintDockFrame.HandleInitTimer(Sender: TObject);
begin
  FInitTimer.Enabled:= False;
  if FInited then Exit;
  FInited:= True;

  try
    FStructure:= CreateEmbeddedStructure(Self, FTabStruct);
  except
    on E: Exception do
    begin
      FStructure:= nil;
      AddPlaceholder(FTabStruct, 'Structure failed to load: ' + E.Message);
    end;
  end;

  try
    CreateEmbeddedSearch(Self, FTabUnifiedSearch);
  except
    on E: Exception do AddPlaceholder(FTabUnifiedSearch, 'Search failed to load: ' + E.Message);
  end;

  try
    CreateEmbeddedUsages(Self, FTabUsages);
  except
    on E: Exception do AddPlaceholder(FTabUsages, 'Find Usages failed to load: ' + E.Message);
  end;
end; // procedure

procedure TDragLintDockFrame.HandlePageChange(Sender: TObject);
begin
  { Re-read the active editor file whenever the Structure tab comes forward. }
  if (FPages.ActivePage = FTabStruct) and (FStructure <> nil) then RefreshEmbeddedStructure(FStructure);
end;

{ ---- free watcher -------------------------------------------------------- }

procedure TFormWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = GForm) then GForm:= nil;
end;

{ ---- INTACustomDockableForm --------------------------------------------- }

function TDragLintDockable.GetCaption: string;
begin
  Result:= 'drag-lint';
end;

function TDragLintDockable.GetIdentifier: string;
begin
  Result:= DOCK_IDENTIFIER;
end;

function TDragLintDockable.GetFrameClass: TCustomFrameClass;
begin
  Result:= TDragLintDockFrame;
end;

procedure TDragLintDockable.FrameCreated(AFrame: TCustomFrame);
begin
end;

function TDragLintDockable.GetMenuActionList: TCustomActionList;
begin
  Result:= nil;
end;

function TDragLintDockable.GetMenuImageList: TCustomImageList;
begin
  Result:= nil;
end;

procedure TDragLintDockable.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TDragLintDockable.GetToolBarActionList: TCustomActionList;
begin
  Result:= nil;
end;

function TDragLintDockable.GetToolBarImageList: TCustomImageList;
begin
  Result:= nil;
end;

procedure TDragLintDockable.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TDragLintDockable.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TDragLintDockable.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TDragLintDockable.GetEditState: TEditState;
begin
  Result:= [];
end;

function TDragLintDockable.EditAction(Action: TEditAction): Boolean;
begin
  Result:= False;
end;

{ ---- show / teardown ----------------------------------------------------- }

procedure RegisterDragLintDockable;
{ Register at plugin startup (from the wizard's Register) so the IDE can restore
  a saved docked instance when it reloads the desktop. Registering only inside
  ShowDragLintDock (on menu click) is too late for desktop restore. Idempotent. }
var
  NTA: INTAServices;
begin
  if GRegistered then Exit;
  if not Supports(BorlandIDEServices, INTAServices, NTA) then Exit;
  if GWatch    = nil then GWatch:= TFormWatch.Create(nil);
  if GDockable = nil then GDockable:= TDragLintDockable.Create;
  NTA.RegisterDockableForm(GDockable);
  GRegistered:= True;
end;

procedure ShowDragLintDock;
var
  NTA: INTAServices;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTA) then Exit;

  RegisterDragLintDockable;

  if GForm = nil then
  begin
    GForm:= NTA.CreateDockableForm(GDockable);
    if GForm <> nil then GForm.FreeNotification(GWatch);
  end;

  if GForm <> nil then
  begin
    if GForm.WindowState = wsMinimized then GForm.WindowState:= wsNormal;
    GForm.Show;
  end;
end; // procedure

procedure UnregisterDragLintDock;
var
  NTA: INTAServices;
begin
  if Supports(BorlandIDEServices, INTAServices, NTA) then
  begin
    if GRegistered and (GDockable <> nil) then
    begin
      try NTA.UnregisterDockableForm(GDockable); except end;
      GRegistered:= False;
    end;
  end;
  GForm    := nil; { owned/freed by the IDE }
  GDockable:= nil;
  FreeAndNil(GWatch);
end;

initialization

finalization
try UnregisterDragLintDock; except end;

end.
