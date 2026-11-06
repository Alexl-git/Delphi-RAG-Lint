unit DragLint.Plugin.ProjectNotifier;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , ToolsAPI
  , DragLint.Plugin   .Settings
  , DragLint.Plugin   .DbResolver
  , DragLint.Workspace.Config
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.ProjectNotifier.pas) ?, DragLint.Plugin.ProjectNotifier.RegisterProjectNotifier (DragLint.Plugin.ProjectNotifier.pas)</para>
  /// <para>Used in units: DragLint.Plugin.ProjectNotifier</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintProjectNotifier = class(TInterfacedObject, IOTAIDENotifier)
    private
      /// <summary><!-- drag-lint:auto sum -->---- async indexer spawn ----</summary>
      /// <param name="AExePath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AProjFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ADbPath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.FileNotification (DragLint.Plugin.ProjectNotifier.pas)</para>
      /// <para>Calls: CloseHandle, CreateProcessW, DragLint.Plugin.IndexJob.BuildProjectIndexCmdLine, DragLint.Plugin.Settings.LoadSettings, DRagLint.Workspace.Config.TWorkspaceConfigIO.FindWorkspaceRoot, DRagLint.Workspace.Config.TWorkspaceConfigIO.LoadFromFile, ExtractFilePath, FillChar, Format, StrPCopy</para>
      /// <para>Catches: Exception (empty)</para>
      /// <para>Touches: file system</para>
      /// <para>Directives: static</para>
      /// <seealso cref="DragLint.Plugin.IndexJob.BuildProjectIndexCmdLine"/>
      /// <seealso cref="DragLint.Plugin.Settings.LoadSettings"/>
      /// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.FindWorkspaceRoot"/>
      /// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.LoadFromFile"/>
      /// <seealso cref="DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.AfterCompile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class procedure SpawnIndexer(const AExePath, AProjFile, ADbPath: string); static;
      /// <param name="ACfgExePath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: EngineExeOrEmpty.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.FileNotification (DragLint.Plugin.ProjectNotifier.pas)</para>
      /// <para>Calls: DragLint.Plugin.ExeResolver.EngineExeOrEmpty</para>
      /// <para>Effect-free (proven)</para>
      /// <para>Directives: static</para>
      /// <seealso cref="DragLint.Plugin.ExeResolver.EngineExeOrEmpty"/>
      /// <seealso cref="DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.AfterCompile"/>
      /// <seealso cref="DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.AfterSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.BeforeCompile"/>
      /// <seealso cref="DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.BeforeSave"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function ResolveExePath(const ACfgExePath: string): string; static;
    public
      { IOTANotifier }
      procedure AfterSave;
      procedure BeforeSave;
      procedure Destroyed;
      procedure Modified;
      { IOTAIDENotifier }
      /// <summary><!-- drag-lint:auto sum -->IOTAIDENotifier</summary>
      /// <param name="NotifyCode"><!-- drag-lint:auto type -->TOTAFileNotification</param>
      /// <param name="FileName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="Cancel"><!-- drag-lint:auto type -->var Boolean</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ChangeFileExt, DragLint.Plugin.DbResolver.ManifestDbForFile, DragLint.Plugin.Editor.RunGhostRecoverForProject, DragLint.Plugin.Editor.TriggerProjectCompile, DragLint.Plugin.LiveDiagnostics.NotifyEditDirty, DragLint.Plugin.ProjectNotifier.IsDelphiSourceExt, DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.ResolveExePath, DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.SpawnIndexer, DragLint.Plugin.SaveNotifier.RegisterSaveNotifierForModule, DragLint.Plugin.SaveNotifier.UnregisterSaveNotifierForModule (+8 more)</para>
      /// <para>Complexity: 15 (cyclomatic, outer body), 83 lines (full implementation)</para>
      /// <para>Catches: Exception (empty)</para>
      /// <seealso cref="DragLint.Plugin.DbResolver.ManifestDbForFile"/>
      /// <seealso cref="DragLint.Plugin.Editor.RunGhostRecoverForProject"/>
      /// <seealso cref="DragLint.Plugin.Editor.TriggerProjectCompile"/>
      /// <seealso cref="DragLint.Plugin.LiveDiagnostics.NotifyEditDirty"/>
      /// <seealso cref="DragLint.Plugin.ProjectNotifier.IsDelphiSourceExt"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
      procedure AfterCompile(Succeeded: Boolean);
  end;

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.RegisterDragLintMenu (DragLint.Plugin.Editor.pas)</para>
/// <para>Calls: Supports</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RegisterProjectNotifier;
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.UnregisterDragLintMenu (DragLint.Plugin.Editor.pas), DragLint.Plugin.Wizard.TDragLintWizard.Destroyed (DragLint.Plugin.Wizard.pas)</para>
/// <para>Calls: Supports</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure UnregisterProjectNotifier;

implementation

uses
  Winapi.Windows
  , DragLint.Plugin.SaveNotifier
  , DragLint.Plugin.LiveDiagnostics
  , DragLint.Plugin.Editor
  , DragLint.Plugin.ExeResolver
  , DragLint.Plugin.IndexJob
  ;

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

procedure TDragLintProjectNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TDragLintProjectNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ ---- async indexer spawn ---- }

class procedure TDragLintProjectNotifier.SpawnIndexer( const AExePath, AProjFile, ADbPath: string);
var
  CmdLine   : string                    ;
  SI        : TStartupInfoW             ;
  PI        : TProcessInformation       ;
  CmdLineBuf: array[0..2047] of WideChar;
  Cfg       : TDragLintSettings         ;
  WsRoot    : string                    ;
  WsCfgPath : string                    ;
  WsCfg     : TWorkspaceConfig          ;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb:= SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
  Cfg:= LoadSettings;

  // v0.34: workspace mode -- if workspace config found walking up from
  // the project dir, use "workspace index --config" instead.
  if Cfg.EnableWorkspaceMode then
  begin
    WsRoot:= TWorkspaceConfigIO.FindWorkspaceRoot(ExtractFilePath(AProjFile));
    if WsRoot <> '' then
    begin
      WsCfgPath:= TPath.Combine(WsRoot, WORKSPACE_FILENAME);
      try
        WsCfg:= TWorkspaceConfigIO.LoadFromFile(WsCfgPath);
        CmdLine:= Format('"%s" workspace index --config "%s"', [AExePath, WsCfgPath]);
        StrPCopy(CmdLineBuf, CmdLine);
        if CreateProcessW(nil, CmdLineBuf, nil, nil, False, CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI) then
        begin
          CloseHandle(PI.hProcess);
          CloseHandle(PI.hThread );
        end;
        Exit;
      except
        // Malformed workspace config: fall through to per-project index
      end; // try
    end; // if
  end; // if

  { The PROJECT form, never `index <dir> --db <projectDb>`: a folder target adds
    every loose .pas under the directory and then adopts that widened set as the
    DB's scope (DataCopy 39 -> 72 files, 2026-09-02), and the engine refuses it
    outright against a DB stamped as a project index. --scan-libraries is NOT
    carried over: it is a separate LIBRARY scan of the Delphi Library/Browsing
    paths, and a project index excludes exactly those units -- so the setting
    no longer affects this spawn. }
  CmdLine:= BuildProjectIndexCmdLine(AExePath, AProjFile, ADbPath, '');
  StrPCopy(CmdLineBuf, CmdLine);
  if CreateProcessW(nil, CmdLineBuf, nil, nil, False, CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI) then
  begin
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  end;
end; // procedure

class function TDragLintProjectNotifier.ResolveExePath( const ACfgExePath: string): string;
begin
  { v0.86: ACfgExePath is ignored in favor of the shared resolver -- its value
    came from the same Settings the shared unit already reads, and centralizing
    keeps ONE Win64-default policy for every spawn site. }
  Result:= EngineExeOrEmpty;
end;

{ ---- FileNotification ---- }

const
  REINDEX_EXTS: array[0..4] of string = ( '.pas', '.dpr', '.dpk', '.inc', '.dfm');

function IsDelphiSourceExt(const AExt: string): Boolean;
var
  I       : Integer;
  LowerExt: string ;
begin
  LowerExt:= LowerCase(AExt);
  Result:= False;
  for I:= Low(REINDEX_EXTS) to High(REINDEX_EXTS) do
    if REINDEX_EXTS[I] = LowerExt then
    begin
      Result:= True;
      Break;
    end;
end;

procedure TDragLintProjectNotifier.FileNotification( NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
var
  ProjDir : string            ;
  DbPath  : string            ;
  ExePath : string            ;
  ProjName: string            ;
  Cfg     : TDragLintSettings ;
  Module  : IOTAModule        ;
  ModSvcs : IOTAModuleServices;
begin
  { v0.40: When the IDE closes a module (including during IDE Exit, before
    BPL unload), drop our save-notifier from that module's notifier list.
    Otherwise the next AllowSave / @IntfCopy walks a dangling pointer
    once the BPL code segment is unloaded. }
  if NotifyCode = ofnFileClosing then
  begin
    if IsDelphiSourceExt(ExtractFileExt(FileName)) then
    begin
      if Supports(BorlandIDEServices, IOTAModuleServices, ModSvcs) then
      begin
        Module:= ModSvcs.FindModule(FileName);
        if Module <> nil then UnregisterSaveNotifierForModule(Module);
      end;
    end;
    Exit;
  end;

  if NotifyCode <> ofnFileOpened then Exit;

  { --- Register a save-notifier on every Delphi source file that opens --- }
  if IsDelphiSourceExt(ExtractFileExt(FileName)) then
  begin
    if Supports(BorlandIDEServices, IOTAModuleServices, ModSvcs) then
    begin
      Module:= ModSvcs.FindModule(FileName);
      RegisterSaveNotifierForModule(Module);
    end;
    { v0.46: kick the live-diagnostics runner when a .pas opens so findings
      (unused locals/H2164, syntax, lint) appear on VIEW -- not only after the
      first edit/save. The runner debounces + lints the active buffer. }
    if SameText(ExtractFileExt(FileName), '.pas') then
    try NotifyEditDirty; except end;
  end;

  { --- Only auto-index when a .dproj is opened --- }
  if not SameText(ExtractFileExt(FileName), '.dproj') then Exit;

  { v0.47: now that a project is actually loaded, recover any file left overlaid
    on disk by a ghost-check that was interrupted (IDE crash) in a PRIOR session.
    Runs independently of AutoIndex; no-ops cheaply when nothing is pending. }
  try RunGhostRecoverForProject(FileName); except end;

  Cfg:= LoadSettings;

  { v0.48: startup compile -- surface compiler errors right when the project opens,
    even if nothing is modified yet. Independent of AutoIndex. }
  if Cfg.AutoCompileOnStartup then
  try TriggerProjectCompile(FileName); except end;

  { Honor AutoIndex setting -- skip spawning when disabled }
  if not Cfg.AutoIndex then Exit;

  ProjDir:= ExtractFilePath(FileName);
  ProjName:= ChangeFileExt(ExtractFileName(FileName), '');

  { v0.46: prefer the manifest section DB that covers this project, so auto-index
    + save-reindex write into the SAME clean DB the manifest builds (and the
    resolver reads) -- not a stale per-.dproj sibling DB. Fall back to the
    template only when no manifest section covers it. }
  DbPath:= ManifestDbForFile(FileName);
  if DbPath = '' then DbPath:= ResolveDbPath(Cfg.DbPathTemplate, ProjDir, ProjName);

  ExePath:= ResolveExePath(Cfg.ExePath);
  if ExePath = '' then Exit; { no usable engine: ENGINE_NOT_FOUND_MSG; nothing to spawn }

  { Post "indexing..." message to IDE Messages pane from main thread }
  TThread.Queue(
    nil,
    procedure var Svc: IOTAMessageServices; begin if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then Svc.AddTitleMessage( Format('drag-lint: indexing project %s...',
          [ProjName])); end
  );

  SpawnIndexer(ExePath, FileName, DbPath);
end; // procedure

{ ---- registration ---- }

var
  GNotifierIndex: Integer                  = -1                  ;
  GNotifier     : TDragLintProjectNotifier = nil;

procedure RegisterProjectNotifier;
var
  Svcs: IOTAServices;
begin
  if not Supports(BorlandIDEServices, IOTAServices, Svcs) then Exit;
  GNotifier:= TDragLintProjectNotifier.Create;
  GNotifierIndex:= Svcs.AddNotifier(GNotifier);
end;

procedure UnregisterProjectNotifier;
var
  Svcs: IOTAServices;
begin
  if GNotifierIndex < 0 then Exit;
  if Supports(BorlandIDEServices, IOTAServices, Svcs) then Svcs.RemoveNotifier(GNotifierIndex);
  GNotifierIndex:= -1;
  GNotifier:= nil; { interface ref auto-freed }
end;

end.
