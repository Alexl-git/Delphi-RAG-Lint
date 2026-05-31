unit DragLint.Plugin.SaveNotifier;
{
  Background reindex on file save - Feature 3 of v0.23.

  Registers a TDragLintSaveNotifier (IOTAModuleNotifier) on every module
  opened in the IDE.  When AfterSave fires for a .pas/.dpr/.dpk/.inc/.dfm
  module and AutoReindexOnSave is enabled, spawns:

    drag-lint.exe index "<file>" --db "<projdb>"

  asynchronously via CreateProcessW (detached, no window).

  The project DB path is read from the GLastProjectDb cache, which is
  written by TDragLintProjectNotifier when a .dproj is opened.  If no
  project has been opened yet GLastProjectDb is empty and the save event
  is silently skipped.

  Registration:
    Call RegisterSaveNotifierForModule(AModule) from FileNotification
    (ofnFileOpened) in TDragLintProjectNotifier for every source file.
    The notifier self-clears its module reference in Destroyed.
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  ToolsAPI,
  DragLint.Plugin.Settings;

type
  TDragLintSaveNotifier = class(TInterfacedObject,
    IOTANotifier, IOTAModuleNotifier)
  private
    FModule:        IOTAModule;
    FNotifierIndex: Integer;
    class procedure SpawnIndexerFile(const AExePath, AFilePath,
      ADbPath: string); static;
  public
    constructor Create(const AModule: IOTAModule);
    { IOTANotifier }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { IOTAModuleNotifier }
    function  CheckOverwrite: Boolean;
    procedure ModuleRenamed(const NewName: string);
  end;

procedure RegisterSaveNotifierForModule(const AModule: IOTAModule);

{ v0.40: explicit teardown of every notifier we registered, so the
  IDE's module notifier lists don't end up holding interface pointers
  whose vtable lives in our BPL after the package unloads. Without this,
  any later access — e.g., File > Exit > AllowSave — AVs in @IntfCopy. }
procedure UnregisterAllSaveNotifiers;

{ v0.40: detach our notifier from a single module that the IDE is closing
  (called from ProjectNotifier on ofnFileClosing). Idempotent. }
procedure UnregisterSaveNotifierForModule(const AModule: IOTAModule);

{ Written by TDragLintProjectNotifier when a .dproj is opened;
  read by TDragLintSaveNotifier.AfterSave to resolve the project DB path. }
var
  GLastProjectDb: string;

implementation

uses
  Winapi.Windows;

{ ---- helpers ---- }

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

{ ---- SpawnIndexerFile ---- }

class procedure TDragLintSaveNotifier.SpawnIndexerFile(
  const AExePath, AFilePath, ADbPath: string);
var
  CmdLine:    string;
  SI:         TStartupInfoW;
  PI:         TProcessInformation;
  CmdLineBuf: array[0..1023] of WideChar;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
  CmdLine := Format('"%s" index "%s" --db "%s"',
    [AExePath, AFilePath, ADbPath]);
  StrPCopy(CmdLineBuf, CmdLine);
  if CreateProcessW(nil, CmdLineBuf, nil, nil, False,
    CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI) then
  begin
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  end;
end;

{ ---- TDragLintSaveNotifier ---- }
{ Constructor defined further down (after registration tracker globals) }

procedure TDragLintSaveNotifier.AfterSave;
var
  FileName:  string;
  FileExt:   string;
  DbPath:    string;
  ExePath:   string;
  Cfg:       TDragLintSettings;
  SavedFile: string;
begin
  if FModule = nil then Exit;

  Cfg := LoadSettings;
  if not Cfg.AutoReindexOnSave then Exit;

  FileName := FModule.FileName;
  FileExt  := ExtractFileExt(FileName);
  if not IsDelphiSourceExt(FileExt) then Exit;

  DbPath := GLastProjectDb;
  if DbPath = '' then Exit;

  { Resolve drag-lint.exe: configured path, then next to BPL, then PATH }
  ExePath := Cfg.ExePath;
  if (ExePath = '') or (ExePath = 'drag-lint.exe') then
  begin
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
    if not FileExists(ExePath) then
      ExePath := 'drag-lint.exe';
  end;

  SavedFile := FileName;

  { Post status message to IDE Messages pane from main thread }
  TThread.Queue(nil,
    procedure
    var
      Svc: IOTAMessageServices;
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
        Svc.AddTitleMessage(
          Format('drag-lint: reindexing %s...', [ExtractFileName(SavedFile)]));
    end);

  SpawnIndexerFile(ExePath, SavedFile, DbPath);
end;

procedure TDragLintSaveNotifier.BeforeSave;
begin
end;

{ Destroyed defined further down — needs access to GRegistrations }

procedure TDragLintSaveNotifier.Modified;
begin
end;

function TDragLintSaveNotifier.CheckOverwrite: Boolean;
begin
  Result := True;
end;

procedure TDragLintSaveNotifier.ModuleRenamed(const NewName: string);
begin
end;

{ ---- registration ---- }

type
  TSavedRegistration = record
    Module: IOTAModule;
    Index:  Integer;
  end;

var
  GRegistrations: TList<TSavedRegistration> = nil;
  GRegLock:       TObject = nil;

constructor TDragLintSaveNotifier.Create(const AModule: IOTAModule);
var
  Reg: TSavedRegistration;
begin
  inherited Create;
  FModule        := AModule;
  FNotifierIndex := AModule.AddNotifier(Self);

  { Track for explicit teardown in UnregisterAllSaveNotifiers }
  if GRegistrations = nil then
    GRegistrations := TList<TSavedRegistration>.Create;
  Reg.Module := AModule;
  Reg.Index  := FNotifierIndex;
  TMonitor.Enter(GRegLock);
  try
    GRegistrations.Add(Reg);
  finally
    TMonitor.Exit(GRegLock);
  end;
end;

procedure RegisterSaveNotifierForModule(const AModule: IOTAModule);
var
  I:        Integer;
  Existing: TSavedRegistration;
begin
  if AModule = nil then Exit;

  { v0.40: dedupe — if FileNotification fires twice for the same module
    (project reload, etc.), don't accumulate duplicate notifiers. }
  if (GRegistrations <> nil) and (GRegLock <> nil) then
  begin
    TMonitor.Enter(GRegLock);
    try
      for I := 0 to GRegistrations.Count - 1 do
      begin
        Existing := GRegistrations[I];
        if Existing.Module = AModule then Exit;
      end;
    finally
      TMonitor.Exit(GRegLock);
    end;
  end;

  TDragLintSaveNotifier.Create(AModule);
end;

procedure UnregisterAllSaveNotifiers;
var
  I:     Integer;
  Reg:   TSavedRegistration;
begin
  if GRegistrations = nil then Exit;
  TMonitor.Enter(GRegLock);
  try
    for I := GRegistrations.Count - 1 downto 0 do
    begin
      Reg := GRegistrations[I];
      try
        if Reg.Module <> nil then
          Reg.Module.RemoveNotifier(Reg.Index);
      except
        { Swallow — module may already be partially destroyed. The point
          is to detach our entry before the BPL unloads. }
      end;
    end;
    GRegistrations.Clear;
  finally
    TMonitor.Exit(GRegLock);
  end;
end;

procedure UnregisterSaveNotifierForModule(const AModule: IOTAModule);
var
  I:   Integer;
  Reg: TSavedRegistration;
begin
  if AModule = nil then Exit;
  if (GRegistrations = nil) or (GRegLock = nil) then Exit;
  TMonitor.Enter(GRegLock);
  try
    for I := GRegistrations.Count - 1 downto 0 do
    begin
      Reg := GRegistrations[I];
      if Reg.Module = AModule then
      begin
        try
          AModule.RemoveNotifier(Reg.Index);
        except
          { Swallow — module is already on the way out }
        end;
        GRegistrations.Delete(I);
      end;
    end;
  finally
    TMonitor.Exit(GRegLock);
  end;
end;

procedure TDragLintSaveNotifier.Destroyed;
var
  I: Integer;
begin
  { Module is going away. Drop our tracking entry for it. }
  if (GRegistrations <> nil) and (GRegLock <> nil) then
  begin
    TMonitor.Enter(GRegLock);
    try
      for I := GRegistrations.Count - 1 downto 0 do
        if GRegistrations[I].Module = FModule then
        begin
          GRegistrations.Delete(I);
          Break;
        end;
    finally
      TMonitor.Exit(GRegLock);
    end;
  end;

  FModule        := nil;
  FNotifierIndex := -1;
end;

initialization
  GRegLock := TObject.Create;

finalization
  UnregisterAllSaveNotifiers;
  if GRegistrations <> nil then
    FreeAndNil(GRegistrations);
  if GRegLock <> nil then
    FreeAndNil(GRegLock);

end.
