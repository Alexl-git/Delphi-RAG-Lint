unit DragLint.Plugin.GraphWindow;

{ v0.43: a dedicated, dockable "drag-lint Graph" tool window.

  Unlike the tabbed dock panel (DragLint.Plugin.DockForm), this is its OWN
  INTACustomDockableForm so it can sit open beside the Structure window -- both
  visible at once, the way the user works.

  It hosts the standalone graph viewer (drag_lint_graph.exe) IN-PLACE: the
  viewer is launched with `--parent-hwnd <thisFrameHwnd>`, which makes its main
  window a WS_CHILD of this frame (see MainForm.CreateParams in the viewer
  project). We then size that child to fill the frame on every resize, and
  terminate the viewer process when the window is destroyed. Jump-to-source
  keeps working through the existing named-pipe contract. }

interface

procedure ShowDragLintGraph; { open / focus the dockable graph window }
procedure RegisterDragLintGraphDockable; { register at startup so the IDE restores a saved docked instance }
procedure UnregisterDragLintGraph; { idempotent teardown }

{ v0.48 editor-sync: when the active editor unit changes, the edit-view notifier
  calls this so the embedded graph viewer follows the editor. No-op unless the
  graph window is open AND its viewer child has embedded; safe to call always.
  AUnitName is the bare unit name (file name without extension), which the viewer
  resolves to a graph node and centers (recording nav history). }
procedure DragLintGraphNotifyActiveUnit(const AUnitName: string);

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IniFiles
  , System.Actions
  , System.Win.Registry
  , Winapi.Windows
  , Winapi.Messages
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.ComCtrls
  , Vcl.ActnList
  , Vcl.ImgList
  , Vcl.Menus
  , DesignIntf
  , { TEditState / TEditAction }
    ToolsAPI
  , DragLint.Plugin.DbResolver
  , DRagLint.Core.JobObject
  , DragLint.Plugin.Settings
  ;

{ A minimal .dfm resource is REQUIRED: TCustomFrame.Create (invoked by the IDE's
  OTADockableForm.EmbedFrame) calls InitInheritedComponent, which raises
  "Resource TDragLintGraphFrame not found" without it. The frame builds its own
  controls in the constructor; the .dfm is an empty shell (mirrors DockForm). }
{$R *.dfm}

type
  TDragLintGraphFrame = class(TCustomFrame)
    private
      FStatus    : TLabel             ;
      FInitTimer : TTimer             ; { defers the launch off the ctor (handle stable) }
      FPollTimer : TTimer             ; { waits for the viewer's child window to appear }
      FInited    : Boolean            ;
      FHasProc   : Boolean            ;
      FProcInfo  : TProcessInformation;
      FViewerHwnd: HWND               ;
      FPollCount : Integer            ;
      procedure HandleInitTimer(Sender: TObject);
      procedure HandlePollTimer(Sender: TObject);
      procedure HandleResize   (Sender: TObject);
      function ResolveDbArgs: string;
      function FindViewerExe: string;
      procedure LaunchViewer;
      procedure SizeViewer;
      procedure KillViewer;
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
  end;

  TDragLintGraphDockable = class(TInterfacedObject, INTACustomDockableForm)
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

  TGraphFormWatch = class(TComponent)
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

const
  GRAPH_IDENTIFIER = 'DragLintGraphDockable';

  { v0.48 editor-sync: WM_COPYDATA magic the viewer expects in
    COPYDATASTRUCT.dwData (must match MainForm.CD_CENTER_SYMBOL in the viewer). }
  CD_CENTER_SYMBOL = $DA61C000;

var
  GGraphDockable  : INTACustomDockableForm = nil;
  GGraphForm      : TCustomForm            = nil           ;
  GGraphRegistered: Boolean                = False             ;
  GGraphWatch     : TGraphFormWatch        = nil       ;
  GGraphFrame     : TDragLintGraphFrame    = nil   ; { live frame (holds viewer hwnd) }
  GLastSyncedUnit : string                 = ''                 ; { de-dup repeated tab activations }

  { ---- frame -------------------------------------------------------------- }

constructor TDragLintGraphFrame.Create(AOwner: TComponent);
begin
  inherited;
  FViewerHwnd:= 0;
  FHasProc   := False;

  FStatus:= TLabel.Create(Self);
  FStatus.Parent   := Self;
  FStatus.Align    := alClient;
  FStatus.Alignment:= taCenter;
  FStatus.Layout   := tlCenter;
  FStatus.WordWrap := True;
  FStatus.Caption  := 'Launching graph viewer...';

  OnResize:= HandleResize;

  { Defer the launch one message turn -- the frame needs a stable window
    handle to host the viewer as a child (mirrors the dock panel). }
  FInitTimer:= TTimer.Create(Self);
  FInitTimer.Interval:= 50;
  FInitTimer.OnTimer := HandleInitTimer;
  FInitTimer.Enabled := True;

  GGraphFrame    := Self; { v0.48: expose to the editor-sync notifier }
  GLastSyncedUnit:= '';
end; // constructor

destructor TDragLintGraphFrame.Destroy;
begin
  if GGraphFrame = Self then { v0.48: stop editor-sync from targeting a dead frame }
  begin
    GGraphFrame:= nil;
    GLastSyncedUnit:= '';
  end;
  KillViewer;
  inherited;
end;

function TDragLintGraphFrame.ResolveDbArgs: string;
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

function TDragLintGraphFrame.FindViewerExe: string;
const
  NAMES: array[0..1] of string = ('drag_lint_graph.exe', 'DragLintGraphViewer.exe');
var
  Dirs      : array[0..1] of string;
  Dir       : string               ;
  N         : string               ;
  ExeSetting: string               ;
begin
  Result:= '';
  Dirs[0]:= ExtractFilePath(GetModuleName(HInstance)); { next to the BPL }
  ExeSetting:= LoadSettings.ExePath; { next to drag-lint.exe }
  if ExeSetting <> '' then Dirs[1]:= ExtractFilePath(ExeSetting)
  else Dirs[1]:= Dirs[0];
  for Dir in Dirs  do
  for N   in NAMES do
      if FileExists(Dir + N) then Exit(Dir + N);
end;

procedure TDragLintGraphFrame.LaunchViewer;
var
  Exe      : string      ;
  CmdLine  : string      ;
  StartInfo: TStartupInfo;
begin
  Exe:= FindViewerExe;
  if Exe = '' then
  begin
    FStatus.Caption:= 'drag_lint_graph.exe not found next to the plugin.'#13#10 + 'Build Delphi-RAG-Lint-Graph and deploy it beside the BPL.';
    Exit;
  end;

  { v0.47: --parent-pid lets the viewer self-exit if the IDE dies (belt-and-
    suspenders to the kill-on-close job object the child is assigned to below). }
  CmdLine:= Format('"%s" --parent-hwnd %d --parent-pid %d%s', [Exe, Self.Handle, GetCurrentProcessId, ResolveDbArgs]);
  UniqueString(CmdLine); { CreateProcessW may write into the buffer }

  FillChar(StartInfo, SizeOf(StartInfo), 0);
  StartInfo.cb:= SizeOf(StartInfo);

  if CreateProcess(nil, PChar(CmdLine), nil, nil, False, 0, nil, PChar(ExtractFilePath(Exe)), StartInfo, FProcInfo) then
  begin
    FHasProc:= True;
    { v0.47: OS force-kills the viewer when the IDE process dies (crash/kill too). }
    AssignToDragLintJob(FProcInfo.hProcess);
    FPollCount:= 0;
    FPollTimer:= TTimer.Create(Self);
    FPollTimer.Interval:= 150;
    FPollTimer.OnTimer := HandlePollTimer;
    FPollTimer.Enabled := True;
  end
  else FStatus.Caption:= 'Failed to launch graph viewer (error ' + IntToStr(GetLastError) + ').';
end; // procedure

procedure TDragLintGraphFrame.SizeViewer;
begin
  if FViewerHwnd <> 0 then MoveWindow(FViewerHwnd, 0, 0, Self.ClientWidth, Self.ClientHeight, True);
end;

procedure TDragLintGraphFrame.HandleInitTimer(Sender: TObject);
begin
  FInitTimer.Enabled:= False;
  if FInited then Exit;
  FInited:= True;
  LaunchViewer;
end;

procedure TDragLintGraphFrame.HandlePollTimer(Sender: TObject);
begin
  Inc(FPollCount);
  if FViewerHwnd = 0 then FViewerHwnd:= FindWindowEx(Self.Handle, 0, nil, nil); { the only child }

  if FViewerHwnd <> 0 then
  begin
    SizeViewer;
    FStatus   .Visible:= False;
    FPollTimer.Enabled:= False;
  end
  else if FPollCount > 80 then { ~12 s; give up gracefully }
  begin
    FPollTimer.Enabled:= False;
    FStatus.Caption:= 'Graph viewer started but did not embed. ' + 'It may have opened as a separate window.';
  end;
end; // procedure

procedure TDragLintGraphFrame.HandleResize(Sender: TObject);
begin
  SizeViewer;
end;

procedure TDragLintGraphFrame.KillViewer;
begin
  if FHasProc then
  begin
    try TerminateProcess(FProcInfo.hProcess, 0); except end;
    try CloseHandle(FProcInfo.hThread); except end;
    try CloseHandle(FProcInfo.hProcess); except end;
    FHasProc:= False;
  end;
  FViewerHwnd:= 0;
end;

{ ---- free watcher ------------------------------------------------------- }

procedure TGraphFormWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = GGraphForm) then GGraphForm:= nil;
end;

{ ---- INTACustomDockableForm -------------------------------------------- }

function TDragLintGraphDockable.GetCaption: string;
begin
  Result:= 'drag-lint Graph';
end;

function TDragLintGraphDockable.GetIdentifier: string;
begin
  Result:= GRAPH_IDENTIFIER;
end;

function TDragLintGraphDockable.GetFrameClass: TCustomFrameClass;
begin
  Result:= TDragLintGraphFrame;
end;

procedure TDragLintGraphDockable.FrameCreated(AFrame: TCustomFrame);
begin
end;

function TDragLintGraphDockable.GetMenuActionList: TCustomActionList;
begin
  Result:= nil;
end;

function TDragLintGraphDockable.GetMenuImageList: TCustomImageList;
begin
  Result:= nil;
end;

procedure TDragLintGraphDockable.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TDragLintGraphDockable.GetToolBarActionList: TCustomActionList;
begin
  Result:= nil;
end;

function TDragLintGraphDockable.GetToolBarImageList: TCustomImageList;
begin
  Result:= nil;
end;

procedure TDragLintGraphDockable.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TDragLintGraphDockable.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TDragLintGraphDockable.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TDragLintGraphDockable.GetEditState: TEditState;
begin
  Result:= [];
end;

function TDragLintGraphDockable.EditAction(Action: TEditAction): Boolean;
begin
  Result:= False;
end;

{ ---- show / teardown ---------------------------------------------------- }

procedure RegisterDragLintGraphDockable;
{ Registering the dockable form at plugin startup (from the wizard's Register)
  is what lets the IDE recreate a saved/docked instance when it restores the
  desktop. Registering only inside ShowDragLintGraph (on menu click) is too late
  for desktop restore. Idempotent. }
var
  NTA: INTAServices;
begin
  if GGraphRegistered then Exit;
  if not Supports(BorlandIDEServices, INTAServices, NTA) then Exit;
  if GGraphWatch    = nil then GGraphWatch:= TGraphFormWatch.Create(nil);
  if GGraphDockable = nil then GGraphDockable:= TDragLintGraphDockable.Create;
  NTA.RegisterDockableForm(GGraphDockable);
  GGraphRegistered:= True;
end;

procedure ShowDragLintGraph;
var
  NTA: INTAServices;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTA) then Exit;

  RegisterDragLintGraphDockable;

  if GGraphForm = nil then
  begin
    GGraphForm:= NTA.CreateDockableForm(GGraphDockable);
    if GGraphForm <> nil then GGraphForm.FreeNotification(GGraphWatch);
  end;

  if GGraphForm <> nil then
  begin
    if GGraphForm.WindowState = wsMinimized then GGraphForm.WindowState:= wsNormal;
    GGraphForm.Show;
  end;
end; // procedure

procedure UnregisterDragLintGraph;
var
  NTA: INTAServices;
begin
  if Supports(BorlandIDEServices, INTAServices, NTA) then
  begin
    if GGraphRegistered and (GGraphDockable <> nil) then
    begin
      try NTA.UnregisterDockableForm(GGraphDockable); except end;
      GGraphRegistered:= False;
    end;
  end;
  GGraphForm    := nil; { owned/freed by the IDE (frame dtor kills viewer) }
  GGraphDockable:= nil;
  FreeAndNil(GGraphWatch);
end;

{ ---- editor-sync (IDE -> viewer) --------------------------------------- }

function ResolveViewerHwnd: HWND;
{ The viewer to sync, or 0 when none is running (-> editor-sync idles). Prefers a
  registry-published viewer (covers a STANDALONE viewer the plugin did not spawn),
  then the embedded dock's viewer child. Every handle is IsWindow-validated so a
  stale registry entry is ignored. }
var
  Reg: TRegistry;
  H  : HWND      ;
begin
  Result:= 0;
  try
    Reg:= TRegistry.Create(KEY_READ);
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly('Software\DragLint') and Reg.ValueExists('GraphViewerHwnd') then
      begin
        H:= HWND(Reg.ReadInteger('GraphViewerHwnd'));
        if (H <> 0) and IsWindow(H) then Result:= H;
      end;
    finally
      Reg.Free;
    end;
  except
  end;
  if (Result = 0) and (GGraphFrame <> nil) and (GGraphFrame.FViewerHwnd <> 0)
     and IsWindow(GGraphFrame.FViewerHwnd) then
    Result:= GGraphFrame.FViewerHwnd;
end;

procedure DragLintGraphNotifyActiveUnit(const AUnitName: string);
var
  CDS  : TCopyDataStruct;
  A    : AnsiString     ;
  Res  : NativeInt      ;
  Wnd  : HWND           ;
begin
  if AUnitName = '' then Exit;
  if SameText(AUnitName, GLastSyncedUnit) then Exit;   { same tab refocused -> skip }
  Wnd:= ResolveViewerHwnd;
  if Wnd = 0 then Exit;   { no viewer running (standalone or embedded) -> idle }

  A:= AnsiString(AUnitName); { viewer expects 7-bit ANSI }
  CDS.dwData:= CD_CENTER_SYMBOL;
  CDS.cbData:= Length(A); { bytes, no trailing NUL }
  if CDS.cbData = 0 then Exit;
  CDS.lpData:= PAnsiChar(A);

  { SendMessageTimeout (not Post): WM_COPYDATA must be synchronous so the buffer
    stays valid while the viewer copies it. The timeout + ABORTIFHUNG keeps the
    IDE thread from stalling if the viewer is busy. Cross-bitness (Win32 plugin ->
    Win64 viewer) is marshaled by the OS. }
  if SendMessageTimeout(Wnd, WM_COPYDATA, 0, LPARAM(@CDS), SMTO_ABORTIFHUNG or SMTO_NORMAL, 1000, @Res) <> 0 then GLastSyncedUnit:= AUnitName;
end; // procedure

initialization

finalization
try UnregisterDragLintGraph; except end;

end.
