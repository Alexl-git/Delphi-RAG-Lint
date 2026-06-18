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

{ v0.42: set by Editor.RegisterDragLintMenu to Editor.TriggerDiagnosticsOnSave.
  Called from AfterSave (when AutoDiagnosticsOnSave is on) so saving a file
  republishes its syntax/lint diagnostics. A hook avoids a SaveNotifier->Editor
  unit dependency (Editor already depends on SaveNotifier). }
var
  GAfterSaveDiagHook: procedure(const AFile: string) = nil;

{ v0.47: set by Editor.RegisterDragLintMenu to Editor.TriggerCompileOnSave.
  Called from AfterSave (when AutoCompileOnSave is on) to kick off an
  out-of-process compile of the active project. }
var
  GAfterSaveCompileHook: procedure(const AFile: string) = nil;

implementation

uses
  Winapi.Windows;

{ ---- helpers ---- }

{ v0.42: per-file debounce. AfterSave can fire more than once for the same
  file in quick succession (Save All, designer + source both saving, IDE
  reentrancy). Reindexing the same file twice within a short window is wasted
  work, so we record the last reindex tick per file and skip a re-fire inside
  the window. Different files in a Save All each still reindex once -- they
  genuinely changed -- so the index stays fresh without a process storm. }
const
  REINDEX_DEBOUNCE_MS = 2000;

var
  GLastReindexTick: TDictionary<string, Cardinal> = nil;

function ShouldDebounceReindex(const AFile: string): Boolean;
var
  Key:  string;
  Last: Cardinal;
  Now:  Cardinal;
begin
  Result := False;
  if GLastReindexTick = nil then
    GLastReindexTick := TDictionary<string, Cardinal>.Create;
  Key := LowerCase(AFile);
  Now := GetTickCount;
  if GLastReindexTick.TryGetValue(Key, Last) and
     (Now - Last < REINDEX_DEBOUNCE_MS) then
    Exit(True);
  GLastReindexTick.AddOrSetValue(Key, Now);
end;

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
  { v0.42: --deep so a saved file keeps its identifier usage refs (Find-Usages).
    Without it, the per-save reindex would re-emit the file shallow and drop the
    read/write refs the project DB was built deep with. }
  CmdLine := Format('"%s" index "%s" --db "%s" --deep',
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
  { v0.40.3+: belt-and-suspenders try/except. The IDE's save flow (File >
    Save All) runs notifiers as part of a deep VCLFormDesigner / DocModul
    callchain. ANY exception propagating out of this method has been known
    to surface as a VCLFormDesigner AV at form-save time, even though the
    fault is actually here. Swallow everything; reindex is best-effort. }
  try
    if FModule = nil then Exit;

    Cfg := LoadSettings;
    if not Cfg.AutoReindexOnSave then Exit;

    FileName := FModule.FileName;
    FileExt  := ExtractFileExt(FileName);
    if not IsDelphiSourceExt(FileExt) then Exit;

    DbPath := GLastProjectDb;
    if DbPath = '' then Exit;

    { v0.42: coalesce rapid re-fires for the same file. }
    if ShouldDebounceReindex(FileName) then Exit;

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
        try
          if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
            Svc.AddTitleMessage(
              Format('drag-lint: reindexing %s...',
                [ExtractFileName(SavedFile)]));
        except
          { swallow }
        end;
      end);

    SpawnIndexerFile(ExePath, SavedFile, DbPath);

    { v0.42: republish diagnostics for the saved file (syntax errors + lint).
      The hook sends textDocument/didSave to the running LSP, which replies with
      publishDiagnostics -> markers. No-op if the LSP isn't running yet (the
      hook guards), so we never force a slow LSP init from the save path. }
    if Cfg.AutoDiagnosticsOnSave and Assigned(GAfterSaveDiagHook) then
      try GAfterSaveDiagHook(SavedFile); except end;

    { v0.47: out-of-process incremental compile of the active project -> surfaces
      real compiler errors (E2003 etc., which the tree-sitter lint cannot see)
      in the Diagnostics pane. Async; never blocks the save and cannot freeze
      the IDE the way in-process Error Insight can. }
    if Cfg.AutoCompileOnSave and Assigned(GAfterSaveCompileHook) then
      try GAfterSaveCompileHook(SavedFile); except end;
  except
    { Silent — never propagate into the IDE save path. }
  end;
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
  if GLastReindexTick <> nil then
    FreeAndNil(GLastReindexTick);

end.
