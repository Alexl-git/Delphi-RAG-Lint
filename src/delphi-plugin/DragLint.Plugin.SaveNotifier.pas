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
  System.SysUtils, System.Classes,
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

constructor TDragLintSaveNotifier.Create(const AModule: IOTAModule);
begin
  inherited Create;
  FModule        := AModule;
  FNotifierIndex := AModule.AddNotifier(Self);
end;

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

procedure TDragLintSaveNotifier.Destroyed;
begin
  { Module is going away - drop reference so we don't access freed memory }
  FModule        := nil;
  FNotifierIndex := -1;
end;

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

procedure RegisterSaveNotifierForModule(const AModule: IOTAModule);
begin
  if AModule = nil then Exit;
  { Constructor registers itself via IOTAModule.AddNotifier;
    the module's notifier list holds the interface ref. }
  TDragLintSaveNotifier.Create(AModule);
end;

end.
