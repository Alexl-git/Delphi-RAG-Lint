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

procedure ShowDragLintGraph;        { open / focus the dockable graph window }
procedure UnregisterDragLintGraph;  { idempotent teardown }

implementation

uses
  System.SysUtils, System.Classes, System.IniFiles, System.Actions,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.ActnList, Vcl.ImgList, Vcl.Menus,
  DesignIntf,   { TEditState / TEditAction }
  ToolsAPI,
  DragLint.Plugin.DbResolver,
  DragLint.Plugin.Settings;

type
  TDragLintGraphFrame = class(TCustomFrame)
  private
    FStatus:     TLabel;
    FInitTimer:  TTimer;     { defers the launch off the ctor (handle stable) }
    FPollTimer:  TTimer;     { waits for the viewer's child window to appear }
    FInited:     Boolean;
    FHasProc:    Boolean;
    FProcInfo:   TProcessInformation;
    FViewerHwnd: HWND;
    FPollCount:  Integer;
    procedure HandleInitTimer(Sender: TObject);
    procedure HandlePollTimer(Sender: TObject);
    procedure HandleResize(Sender: TObject);
    function  ResolveDbArgs: string;
    function  FindViewerExe: string;
    procedure LaunchViewer;
    procedure SizeViewer;
    procedure KillViewer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

  TDragLintGraphDockable = class(TInterfacedObject, INTACustomDockableForm)
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

  TGraphFormWatch = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent;
      Operation: TOperation); override;
  end;

const
  GRAPH_IDENTIFIER = 'DragLintGraphDockable';

var
  GGraphDockable:   INTACustomDockableForm = nil;
  GGraphForm:       TCustomForm = nil;
  GGraphRegistered: Boolean = False;
  GGraphWatch:      TGraphFormWatch = nil;

{ ---- frame -------------------------------------------------------------- }

constructor TDragLintGraphFrame.Create(AOwner: TComponent);
begin
  inherited;
  FViewerHwnd := 0;
  FHasProc := False;

  FStatus := TLabel.Create(Self);
  FStatus.Parent     := Self;
  FStatus.Align      := alClient;
  FStatus.Alignment  := taCenter;
  FStatus.Layout     := tlCenter;
  FStatus.WordWrap   := True;
  FStatus.Caption    := 'Launching graph viewer...';

  OnResize := HandleResize;

  { Defer the launch one message turn -- the frame needs a stable window
    handle to host the viewer as a child (mirrors the dock panel). }
  FInitTimer := TTimer.Create(Self);
  FInitTimer.Interval := 50;
  FInitTimer.OnTimer  := HandleInitTimer;
  FInitTimer.Enabled  := True;
end;

destructor TDragLintGraphFrame.Destroy;
begin
  KillViewer;
  inherited;
end;

function TDragLintGraphFrame.ResolveDbArgs: string;
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

function TDragLintGraphFrame.FindViewerExe: string;
const
  NAMES: array[0..1] of string = ('drag_lint_graph.exe', 'DragLintGraphViewer.exe');
var
  Dirs: array[0..1] of string;
  Dir, N, ExeSetting: string;
begin
  Result := '';
  Dirs[0] := ExtractFilePath(GetModuleName(HInstance));   { next to the BPL }
  ExeSetting := LoadSettings.ExePath;                     { next to drag-lint.exe }
  if ExeSetting <> '' then
    Dirs[1] := ExtractFilePath(ExeSetting)
  else
    Dirs[1] := Dirs[0];
  for Dir in Dirs do
    for N in NAMES do
      if FileExists(Dir + N) then
        Exit(Dir + N);
end;

procedure TDragLintGraphFrame.LaunchViewer;
var
  Exe, CmdLine: string;
  StartInfo: TStartupInfo;
begin
  Exe := FindViewerExe;
  if Exe = '' then
  begin
    FStatus.Caption :=
      'drag_lint_graph.exe not found next to the plugin.'#13#10 +
      'Build Delphi-RAG-Lint-Graph and deploy it beside the BPL.';
    Exit;
  end;

  CmdLine := Format('"%s" --parent-hwnd %d%s',
    [Exe, Self.Handle, ResolveDbArgs]);
  UniqueString(CmdLine);   { CreateProcessW may write into the buffer }

  FillChar(StartInfo, SizeOf(StartInfo), 0);
  StartInfo.cb := SizeOf(StartInfo);

  if CreateProcess(nil, PChar(CmdLine), nil, nil, False,
                   0, nil, PChar(ExtractFilePath(Exe)), StartInfo, FProcInfo) then
  begin
    FHasProc := True;
    FPollCount := 0;
    FPollTimer := TTimer.Create(Self);
    FPollTimer.Interval := 150;
    FPollTimer.OnTimer  := HandlePollTimer;
    FPollTimer.Enabled  := True;
  end
  else
    FStatus.Caption := 'Failed to launch graph viewer (error ' +
      IntToStr(GetLastError) + ').';
end;

procedure TDragLintGraphFrame.SizeViewer;
begin
  if FViewerHwnd <> 0 then
    MoveWindow(FViewerHwnd, 0, 0, Self.ClientWidth, Self.ClientHeight, True);
end;

procedure TDragLintGraphFrame.HandleInitTimer(Sender: TObject);
begin
  FInitTimer.Enabled := False;
  if FInited then Exit;
  FInited := True;
  LaunchViewer;
end;

procedure TDragLintGraphFrame.HandlePollTimer(Sender: TObject);
begin
  Inc(FPollCount);
  if FViewerHwnd = 0 then
    FViewerHwnd := FindWindowEx(Self.Handle, 0, nil, nil);  { the only child }

  if FViewerHwnd <> 0 then
  begin
    SizeViewer;
    FStatus.Visible := False;
    FPollTimer.Enabled := False;
  end
  else if FPollCount > 80 then   { ~12 s; give up gracefully }
  begin
    FPollTimer.Enabled := False;
    FStatus.Caption := 'Graph viewer started but did not embed. '
      + 'It may have opened as a separate window.';
  end;
end;

procedure TDragLintGraphFrame.HandleResize(Sender: TObject);
begin
  SizeViewer;
end;

procedure TDragLintGraphFrame.KillViewer;
begin
  if FHasProc then
  begin
    try TerminateProcess(FProcInfo.hProcess, 0); except end;
    try CloseHandle(FProcInfo.hThread);  except end;
    try CloseHandle(FProcInfo.hProcess); except end;
    FHasProc := False;
  end;
  FViewerHwnd := 0;
end;

{ ---- free watcher ------------------------------------------------------- }

procedure TGraphFormWatch.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = GGraphForm) then
    GGraphForm := nil;
end;

{ ---- INTACustomDockableForm -------------------------------------------- }

function TDragLintGraphDockable.GetCaption: string;
begin
  Result := 'drag-lint Graph';
end;

function TDragLintGraphDockable.GetIdentifier: string;
begin
  Result := GRAPH_IDENTIFIER;
end;

function TDragLintGraphDockable.GetFrameClass: TCustomFrameClass;
begin
  Result := TDragLintGraphFrame;
end;

procedure TDragLintGraphDockable.FrameCreated(AFrame: TCustomFrame);
begin
end;

function TDragLintGraphDockable.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TDragLintGraphDockable.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TDragLintGraphDockable.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TDragLintGraphDockable.GetToolBarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TDragLintGraphDockable.GetToolBarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TDragLintGraphDockable.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TDragLintGraphDockable.SaveWindowState(Desktop: TCustomIniFile;
  const Section: string; IsProject: Boolean);
begin
end;

procedure TDragLintGraphDockable.LoadWindowState(Desktop: TCustomIniFile;
  const Section: string);
begin
end;

function TDragLintGraphDockable.GetEditState: TEditState;
begin
  Result := [];
end;

function TDragLintGraphDockable.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

{ ---- show / teardown ---------------------------------------------------- }

procedure ShowDragLintGraph;
var
  NTA: INTAServices;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTA) then Exit;

  if GGraphWatch = nil then
    GGraphWatch := TGraphFormWatch.Create(nil);

  if GGraphDockable = nil then
    GGraphDockable := TDragLintGraphDockable.Create;
  if not GGraphRegistered then
  begin
    NTA.RegisterDockableForm(GGraphDockable);
    GGraphRegistered := True;
  end;

  if GGraphForm = nil then
  begin
    GGraphForm := NTA.CreateDockableForm(GGraphDockable);
    if GGraphForm <> nil then
      GGraphForm.FreeNotification(GGraphWatch);
  end;

  if GGraphForm <> nil then
  begin
    if GGraphForm.WindowState = wsMinimized then
      GGraphForm.WindowState := wsNormal;
    GGraphForm.Show;
  end;
end;

procedure UnregisterDragLintGraph;
var
  NTA: INTAServices;
begin
  if Supports(BorlandIDEServices, INTAServices, NTA) then
  begin
    if GGraphRegistered and (GGraphDockable <> nil) then
    begin
      try NTA.UnregisterDockableForm(GGraphDockable); except end;
      GGraphRegistered := False;
    end;
  end;
  GGraphForm := nil;        { owned/freed by the IDE (frame dtor kills viewer) }
  GGraphDockable := nil;
  FreeAndNil(GGraphWatch);
end;

initialization

finalization
  try UnregisterDragLintGraph; except end;

end.
