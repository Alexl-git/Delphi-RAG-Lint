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

/// <summary>Shows the drag-lint dock and selects the Lint Options tab. Used by the
/// Project Manager "Project Rules..." action so a right-click lands on rules.</summary>
procedure ShowDragLintDockLintOptions;

/// <summary>Shows the drag-lint dock and fills the Call Graph (butterfly) tab from
/// two reverse-calltree/1 JSON documents (see TDragLintDockFrame.PopulateButterfly).
/// Editor.pas's InvokeButterfly/ShowButterflyForQName call this instead of touching
/// GDockFrame directly, since TDragLintDockFrame is declared in this unit's
/// implementation section and is not visible from Editor.pas. No-op if the dock
/// frame is unavailable (mirrors ShowDragLintDockLintOptions's nil guard).</summary>
procedure ShowDragLintDockButterfly(const AQName, ACallersJson, ACalleesJson: string);

{ Batch E Task 3: cross-file "open at file:line" nav for butterfly tree nodes.
  Editor.pas's DLNavigateToSource is what we need (opens ANY file's source
  view, not just the current module), but Editor.pas already uses DockForm
  in its implementation section, so DockForm cannot uses-import Editor back
  (and DLNavigateToSource is implementation-private there anyway). Same hook
  pattern as SaveNotifier.GAfterSaveDiagHook: Editor.RegisterDragLintMenu
  assigns this to DLNavigateToSource during wizard init. Declared here in the
  interface section so Editor.pas (which does uses DockForm) can assign it. }
var
  GButterflyNav: procedure(const AFile: string; ALine: Integer) = nil;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IniFiles
  , System.Actions
  , System.JSON
  , System.Generics.Collections
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
  , DragLint.Plugin.LintOptionsFrame
  , DragLint.Plugin.ExeResolver
  ;

{$R *.dfm}

type
  { Batch E Task 3: attached via TTreeNode.Data (AddChildObject) so a
    double-click can jump straight to the caller/callee's source location
    without re-parsing the node caption. Owned by FNavList (OwnsObjects=True)
    -- never freed individually. }
  TNav = class
    FFile: string;
    FLine: Integer;
    constructor Create(const AFile: string; ALine: Integer);
  end;

{ v0.42: the dock panel hosts a tabbed view of the drag-lint tools:
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
      FTabLintOptions     : TTabSheet   ;
      FTabButterfly  : TTabSheet   ; { Batch E Task 3: Call Graph (butterfly) tab }
      FButterflyTree : TTreeView   ;
      FNavList       : TObjectList<TNav>; { owns TNav nodes attached to FButterflyTree.Items[].Data }
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
      procedure ButterflyTreeDblClick(Sender: TObject);
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      /// <summary>Selects the Lint Options tab, if the page control and tab exist.
      /// Public so external callers (e.g. the Project Manager "Project Rules..."
      /// action) can jump straight to it without touching private frame internals.</summary>
      procedure SelectLintOptionsTab;
      /// <summary>Fills the Call Graph (butterfly) tab from two reverse-calltree/1
      /// JSON documents -- ACallersJson (who calls AQName) under a "Callers of
      /// AQName (N)" root and ACalleesJson (what AQName calls) under a
      /// "Callees of AQName (N)" root -- then selects the tab. Empty/failed
      /// JSON yields a "(0)" root, never an error. Double-clicking a node with
      /// a file jumps to file:line.</summary>
      procedure PopulateButterfly(const AQName, ACallersJson, ACalleesJson: string);
      /// <summary>Brings the Call Graph tab to the front.</summary>
      procedure SelectButterflyTab;
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
  GDockFrame : TDragLintDockFrame     = nil            ; { v0.94: captured in FrameCreated so ShowDragLintDockLintOptions can reach FPages/FTabLintOptions without breaking the frame's encapsulation }

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
  Result:= DragLintExe;
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
  FTabLintOptions  := AddTab('Lint Options'   );
  { v0.46: the Graph tab was removed -- the graph is now its own dockable tool
    window (View > Tool Windows > drag-lint Graph), so the in-dock launcher tab
    was just stale clutter. }

  { Batch E Task 3: butterfly Call Graph tab -- callers + callees TTreeView,
    filled later via PopulateButterfly (Task 4 shells the CLI and calls it). }
  FNavList:= TObjectList<TNav>.Create(True);
  FTabButterfly := AddTab('Call Graph');
  FButterflyTree := TTreeView.Create(Self);
  FButterflyTree.Parent        := FTabButterfly;
  FButterflyTree.Align         := alClient;
  FButterflyTree.ReadOnly      := True;
  FButterflyTree.ShowLines     := True;
  FButterflyTree.HideSelection := False;
  FButterflyTree.OnDblClick    := ButterflyTreeDblClick;

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

destructor TDragLintDockFrame.Destroy;
begin
  { v0.94: secondary net alongside TFormWatch.Notification -- guard with
    identity check in case a second frame instance was created meanwhile. }
  if GDockFrame = Self then GDockFrame:= nil;
  FNavList.Free; { Batch E Task 3: frees every TNav attached to FButterflyTree nodes }
  inherited;
end;

procedure TDragLintDockFrame.SelectLintOptionsTab;
begin
  if (FPages <> nil) and (FTabLintOptions <> nil) then FPages.ActivePage:= FTabLintOptions;
end;

{ ---- TNav ----------------------------------------------------------------- }

constructor TNav.Create(const AFile: string; ALine: Integer);
begin
  inherited Create;
  FFile:= AFile;
  FLine:= ALine;
end;

{ ---- butterfly Call Graph tab ---------------------------------------------
  Batch E Task 3: renders two reverse-calltree/1 JSON documents (callers of
  AQName, callees of AQName) into one TTreeView under "Callers (N)" / "Callees
  (N)" roots. Task 4 shells the CLI and calls PopulateButterfly; this unit only
  owns the tab, the tree, and the JSON walk. }

procedure TDragLintDockFrame.PopulateButterfly(const AQName, ACallersJson, ACalleesJson: string);

  procedure WalkArray(const AArr: TJSONArray; AParent: TTreeNode);
  var
    i    : Integer    ;
    Obj  : TJSONObject;
    QN, F: string      ;
    Ln   : Integer     ;
    Cyc  : Boolean     ;
    Node : TTreeNode   ;
    Nav  : TNav        ;
    Kids : TJSONArray  ;
  begin
    if AArr = nil then Exit;
    for i:= 0 to AArr.Count - 1 do
    begin
      if not (AArr.Items[i] is TJSONObject) then Continue;
      Obj:= AArr.Items[i] as TJSONObject;
      QN := Obj.GetValue<string>('qname', '');
      F  := Obj.GetValue<string>('file', '');
      Ln := Obj.GetValue<Integer>('line', 0);
      Cyc:= False; Obj.TryGetValue<Boolean>('cycle', Cyc);
      if Cyc then QN:= QN + ' (cycle)';
      Nav := TNav.Create(F, Ln); FNavList.Add(Nav);
      Node:= FButterflyTree.Items.AddChildObject(AParent, QN, Nav);
      if (not Cyc) and Obj.TryGetValue<TJSONArray>('callers', Kids) then
        WalkArray(Kids, Node);
    end;
  end;

var
  CallersV, CalleesV      : TJSONValue  ;
  CallersRoot, CalleesRoot: TJSONObject ;
  RootCallers, RootCallees: TTreeNode   ;
  Arr                     : TJSONArray  ;
  NC, NF                  : Integer     ;
begin
  FButterflyTree.Items.BeginUpdate;
  try
    FButterflyTree.Items.Clear;
    FNavList.Clear; { frees prior TNav objects (OwnsObjects=True) }

    CallersV:= nil; CalleesV:= nil;
    try CallersV:= TJSONObject.ParseJSONValue(ACallersJson); except CallersV:= nil; end;
    try CalleesV:= TJSONObject.ParseJSONValue(ACalleesJson); except CalleesV:= nil; end;
    try
      CallersRoot:= nil; CalleesRoot:= nil;
      if CallersV is TJSONObject then TJSONObject(CallersV).TryGetValue<TJSONObject>('root', CallersRoot);
      if CalleesV is TJSONObject then TJSONObject(CalleesV).TryGetValue<TJSONObject>('root', CalleesRoot);

      NC:= 0;
      if (CallersRoot <> nil) and CallersRoot.TryGetValue<TJSONArray>('callers', Arr) then NC:= Arr.Count;
      RootCallers:= FButterflyTree.Items.Add(nil, Format('Callers of %s (%d)', [AQName, NC]));
      if (CallersRoot <> nil) and CallersRoot.TryGetValue<TJSONArray>('callers', Arr) then WalkArray(Arr, RootCallers);

      NF:= 0;
      if (CalleesRoot <> nil) and CalleesRoot.TryGetValue<TJSONArray>('callers', Arr) then NF:= Arr.Count;
      RootCallees:= FButterflyTree.Items.Add(nil, Format('Callees of %s (%d)', [AQName, NF]));
      if (CalleesRoot <> nil) and CalleesRoot.TryGetValue<TJSONArray>('callers', Arr) then WalkArray(Arr, RootCallees);

      RootCallers.Expand(True);
      RootCallees.Expand(True);
    finally
      CallersV.Free;
      CalleesV.Free;
    end;
  finally
    FButterflyTree.Items.EndUpdate;
  end;
  SelectButterflyTab;
end; // procedure

procedure TDragLintDockFrame.SelectButterflyTab;
begin
  if (FPages <> nil) and (FTabButterfly <> nil) then FPages.ActivePage:= FTabButterfly;
end;

procedure TDragLintDockFrame.ButterflyTreeDblClick(Sender: TObject);
var
  N  : TTreeNode;
  Nav: TNav     ;
begin
  N:= FButterflyTree.Selected;
  if N = nil then Exit;
  if not (TObject(N.Data) is TNav) then Exit;
  Nav:= TNav(N.Data);
  if (Nav.FFile <> '') and (Nav.FLine > 0) and Assigned(GButterflyNav) then
    GButterflyNav(Nav.FFile, Nav.FLine);
end;

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
  { CLOSING THE LAST EDITOR IS A FILE CHANGE TOO.

    This used to read `(CurFile <> '') and not SameText(...)`, so the one
    transition it never noticed was the transition to NOTHING. After File >
    Close All the panel went on showing the last file's diagnostics and code
    elements indefinitely -- stale data that looks exactly like current data.
    Reported from a live IDE, 2026-08-27.

    The clearing code already existed and was simply never reached:
    TDragLintStructureForm.RefreshForFile('') empties both lists and captions
    the panel '(no active editor)'. The guard was the whole bug.

    Startup is unaffected: FLastStructFile starts empty too, so SameText('','')
    is True and no refresh fires until something actually opens. }
  if not SameText(CurFile, FLastStructFile) then
  begin
    FLastStructFile:= CurFile;
    if CurFile <> '' then FLastDiagCount:= Length(Cache.GetForFile(CurFile))
    else                  FLastDiagCount:= 0;
    if CurFile <> '' then
      DLT('dock', Format('watch: file change -> %s (full structure refresh)', [ExtractFileName(CurFile)]))
    else
      DLT('dock', 'watch: no editor left open -> clearing the structure panel');
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

  try
    CreateEmbeddedLintOptions(Self, FTabLintOptions);
  except
    on E: Exception do AddPlaceholder(FTabLintOptions, 'Lint Options failed to load: ' + E.Message);
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
  if (Operation = opRemove) and (AComponent = GForm) then
  begin
    GForm:= nil;
    GDockFrame:= nil; { v0.94: the frame is owned by GForm and dies with it }
  end;
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
  { v0.94: capture the frame instance so ShowDragLintDockLintOptions can select
    its Lint Options tab later without a module-level ref to private fields. }
  if AFrame is TDragLintDockFrame then GDockFrame:= TDragLintDockFrame(AFrame);
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

procedure ShowDragLintDockLintOptions;
begin
  ShowDragLintDock;
  if GDockFrame <> nil then GDockFrame.SelectLintOptionsTab;
end;

procedure ShowDragLintDockButterfly(const AQName, ACallersJson, ACalleesJson: string);
begin
  ShowDragLintDock;
  if GDockFrame <> nil then GDockFrame.PopulateButterfly(AQName, ACallersJson, ACalleesJson);
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
      GRegistered:= False;
    end;
  end;
  GForm     := nil; { owned/freed by the IDE }
  GDockFrame:= nil; { owned by GForm, dies alongside it }
  GDockable := nil;
  FreeAndNil(GWatch);
end;

initialization

finalization
try UnregisterDragLintDock; except end;

end.
