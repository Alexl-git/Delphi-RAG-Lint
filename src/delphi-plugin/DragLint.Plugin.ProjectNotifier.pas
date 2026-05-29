unit DragLint.Plugin.ProjectNotifier;

interface

uses
  System.SysUtils, System.Classes,
  ToolsAPI;

type
  TDragLintProjectNotifier = class(TInterfacedObject, IOTAIDENotifier)
  private
    class procedure SpawnIndexer(const AExePath, AProjDir,
      ADbPath: string); static;
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
  Winapi.Windows;

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
  CmdLineBuf: array[0..1023] of WideChar;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
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

{ ---- FileNotification ---- }

procedure TDragLintProjectNotifier.FileNotification(
  NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  ProjDir: string;
  DbPath: string;
  ExePath: string;
  ProjName: string;
begin
  if NotifyCode <> ofnFileOpened then Exit;
  if LowerCase(ExtractFileExt(FileName)) <> '.dproj' then Exit;

  ProjDir  := ExtractFilePath(FileName);
  DbPath   := ProjDir + '.drag-lint.sqlite';
  ProjName := ChangeFileExt(ExtractFileName(FileName), '');

  { Resolve drag-lint.exe: next to BPL, else rely on PATH }
  ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

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
  GNotifier: TDragLintProjectNotifier = nil;

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
