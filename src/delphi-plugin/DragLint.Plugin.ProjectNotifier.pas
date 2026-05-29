unit DragLint.Plugin.ProjectNotifier;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  ToolsAPI,
  DragLint.Plugin.Settings,
  DRagLint.Workspace.Config;

type
  TDragLintProjectNotifier = class(TInterfacedObject, IOTAIDENotifier)
  private
    class procedure SpawnIndexer(const AExePath, AProjDir,
      ADbPath: string); static;
    class function ResolveExePath(const ACfgExePath: string): string; static;
  public
    { IOTANotifier }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { IOTAIDENotifier }
    procedure FileNotification(NotifyCode: TOTAFileNotification;
      const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject;
      var Cancel: Boolean);
    procedure AfterCompile(Succeeded: Boolean);
  end;

procedure RegisterProjectNotifier;
procedure UnregisterProjectNotifier;

implementation

uses
  Winapi.Windows,
  DragLint.Plugin.SaveNotifier;

{ ---- IOTANotifier stubs ---- }

procedure TDragLintProjectNotifier.AfterSave;
begin
end;

procedure TDragLintProjectNotifier.BeforeSave;
begin
end;

procedure TDragLintProjectNotifier.Destroyed;
begin
end;

procedure TDragLintProjectNotifier.Modified;
begin
end;

{ ---- IOTAIDENotifier stubs ---- }

procedure TDragLintProjectNotifier.BeforeCompile(const Project: IOTAProject;
  var Cancel: Boolean);
begin
end;

procedure TDragLintProjectNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ ---- async indexer spawn ---- }

class procedure TDragLintProjectNotifier.SpawnIndexer(
  const AExePath, AProjDir, ADbPath: string);
var
  CmdLine: string;
  SI: TStartupInfoW;
  PI: TProcessInformation;
  CmdLineBuf: array[0..2047] of WideChar;
  Cfg: TDragLintSettings;
  WsRoot: string;
  WsCfgPath: string;
  WsCfg: TWorkspaceConfig;
  WsDbPath: string;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
  Cfg := LoadSettings;

  // v0.34: workspace mode -- if workspace config found walking up from
  // the project dir, use "workspace index --config" instead.
  if Cfg.EnableWorkspaceMode then
  begin
    WsRoot := TWorkspaceConfigIO.FindWorkspaceRoot(AProjDir);
    if WsRoot <> '' then
    begin
      WsCfgPath := TPath.Combine(WsRoot, WORKSPACE_FILENAME);
      try
        WsCfg := TWorkspaceConfigIO.LoadFromFile(WsCfgPath);
        WsDbPath := TPath.Combine(WsRoot, WsCfg.SharedDb);
        CmdLine := Format('"%s" workspace index --config "%s"',
          [AExePath, WsCfgPath]);
        // Also update the session DB reference for save-notifier
        GLastProjectDb := WsDbPath;
        StrPCopy(CmdLineBuf, CmdLine);
        if CreateProcessW(nil, CmdLineBuf, nil, nil, False,
          CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI) then
        begin
          CloseHandle(PI.hProcess);
          CloseHandle(PI.hThread);
        end;
        Exit;
      except
        // Malformed workspace config: fall through to per-project index
      end;
    end;
  end;

  if Cfg.ScanLibraries then
    CmdLine := Format('"%s" index "%s" --scan-libraries --db "%s"',
      [AExePath, AProjDir, ADbPath])
  else
    CmdLine := Format('"%s" index "%s" --db "%s"',
      [AExePath, AProjDir, ADbPath]);
  StrPCopy(CmdLineBuf, CmdLine);
  if CreateProcessW(nil, CmdLineBuf, nil, nil, False,
    CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI) then
  begin
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  end;
end;

class function TDragLintProjectNotifier.ResolveExePath(
  const ACfgExePath: string): string;
begin
  Result := ACfgExePath;
  if (Result = '') or (Result = 'drag-lint.exe') then
  begin
    Result := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
    if not FileExists(Result) then
      Result := 'drag-lint.exe';
  end;
end;

{ ---- FileNotification ---- }

const
  REINDEX_EXTS: array[0..4] of string = (
    '.pas', '.dpr', '.dpk', '.inc', '.dfm');

function IsDelphiSourceExt(const AExt: string): Boolean;
var
  I:        Integer;
  LowerExt: string;
begin
  LowerExt := LowerCase(AExt);
  Result   := False;
  for I := Low(REINDEX_EXTS) to High(REINDEX_EXTS) do
    if REINDEX_EXTS[I] = LowerExt then
    begin
      Result := True;
      Break;
    end;
end;

procedure TDragLintProjectNotifier.FileNotification(
  NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  ProjDir:  string;
  DbPath:   string;
  ExePath:  string;
  ProjName: string;
  Cfg:      TDragLintSettings;
  Module:   IOTAModule;
  ModSvcs:  IOTAModuleServices;
begin
  if NotifyCode <> ofnFileOpened then Exit;

  { --- Register a save-notifier on every Delphi source file that opens --- }
  if IsDelphiSourceExt(ExtractFileExt(FileName)) then
  begin
    if Supports(BorlandIDEServices, IOTAModuleServices, ModSvcs) then
    begin
      Module := ModSvcs.FindModule(FileName);
      RegisterSaveNotifierForModule(Module);
    end;
  end;

  { --- Only auto-index when a .dproj is opened --- }
  if LowerCase(ExtractFileExt(FileName)) <> '.dproj' then Exit;

  Cfg := LoadSettings;

  { Honor AutoIndex setting — skip spawning when disabled }
  if not Cfg.AutoIndex then Exit;

  ProjDir  := ExtractFilePath(FileName);
  ProjName := ChangeFileExt(ExtractFileName(FileName), '');

  { Resolve DB path from template and cache it for later save events }
  DbPath := ResolveDbPath(Cfg.DbPathTemplate, ProjDir);
  GLastProjectDb := DbPath;

  ExePath := ResolveExePath(Cfg.ExePath);

  { Post "indexing..." message to IDE Messages pane from main thread }
  TThread.Queue(nil,
    procedure
    var
      Svc: IOTAMessageServices;
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
        Svc.AddTitleMessage(
          Format('drag-lint: indexing project %s...', [ProjName]));
    end);

  SpawnIndexer(ExePath, ProjDir, DbPath);
end;

{ ---- registration ---- }

var
  GNotifierIndex: Integer = -1;
  GNotifier:      TDragLintProjectNotifier = nil;

procedure RegisterProjectNotifier;
var
  Svcs: IOTAServices;
begin
  if not Supports(BorlandIDEServices, IOTAServices, Svcs) then Exit;
  GNotifier      := TDragLintProjectNotifier.Create;
  GNotifierIndex := Svcs.AddNotifier(GNotifier);
end;

procedure UnregisterProjectNotifier;
var
  Svcs: IOTAServices;
begin
  if GNotifierIndex < 0 then Exit;
  if Supports(BorlandIDEServices, IOTAServices, Svcs) then
    Svcs.RemoveNotifier(GNotifierIndex);
  GNotifierIndex := -1;
  GNotifier      := nil;  { interface ref auto-freed }
end;

end.
