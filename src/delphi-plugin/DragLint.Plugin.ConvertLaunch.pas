unit DragLint.Plugin.ConvertLaunch;

/// <summary>drag-lint > Convert Components: hands the designer's selection to
/// ConvRulesEditor (C12 plugin side, spec N1 + N2).</summary>
/// <remarks>Order of the hand-off: read the selection; find the editor; probe it once per
/// IDE session; ask to save a modified unit; refuse while an earlier editor lives; write
/// the request; close the unit; start the editor; reopen the unit when it exits. The
/// editor never runs a conversion by itself. All routines here run on the main thread;
/// the only other thread waits on the child, in bounded slices, and queues the reopen.
/// Contract: docs\superpowers\specs\2026-10-06-c12-ide-convert-menu-design.md.</remarks>

interface

/// <summary>Enables the three items of the submenu for what is current now. Assigned to
/// the submenu's OnClick; cheap OTA calls only.</summary>
/// <param name="Sender">The submenu (TMenuItem); its children carry the CONVERT_TAG_ values.</param>
/// <remarks>Only a convenience: where the IDE does not fire it, a click on an item with
/// nothing to act on says so.</remarks>
procedure UpdateConvertComponentsMenu(Sender: TObject);

/// <summary>Opens the editor with the selected components as a `selected` request.</summary>
/// <param name="Sender">The menu item.</param>
procedure InvokeConvertSelectedComponents(Sender: TObject);

/// <summary>Opens the editor with a `form` request: every instance on the form of the
/// selected components' types. The editor expands it; the plugin never walks the .dfm.</summary>
/// <param name="Sender">The menu item.</param>
procedure InvokeConvertAllOfTypeOnForm(Sender: TObject);

/// <summary>Opens the editor on the current unit with no request; the unit stays open.</summary>
/// <param name="Sender">The menu item.</param>
procedure InvokeOpenConversionEditor(Sender: TObject);

/// <summary>Stops watching a running editor, on plugin unload. The editor is NOT killed
/// and the unit is not reopened. Returns within one wait slice.</summary>
procedure ShutdownConvertLaunch;

const
  /// <summary>Tag of 'Convert Selected Component(s)...' and of 'Convert All of This Type...'.</summary>
  CONVERT_TAG_SELECTION = 1;
  /// <summary>Tag of 'Open Conversion Editor...'.</summary>
  CONVERT_TAG_OPEN = 2;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.UITypes
  , Winapi.Windows
  , Vcl.Dialogs
  , Vcl.Menus
  , ToolsAPI
  , DragLint.Plugin.CliAsync
  , DragLint.Plugin.ConvertRequest
  , DragLint.Plugin.DbResolver
  , DragLint.Plugin.ExeResolver
  , DragLint.Plugin.JobQueue
  , DragLint.Plugin.Settings
  , DragLint.Plugin.Telemetry
  ;

const
  EDITOR_EXE = 'ConvRulesEditor.exe';
  SCOPE_SELECTED = 'selected';
  SCOPE_FORM = 'form';
  { The contract's probe budget: an older editor opens its window instead of answering. }
  PROBE_BUDGET_MS = 5000;
  REQUEST_KEEP_DAYS = 7;
  WAIT_SLICE_MS = 500;
  PAS_EXT = '.pas';
  LOG_TOPIC = 'convert';

type
  /// <summary>What the current module offers a conversion.</summary>
  TConvertSelection = record
    /// <summary>The unit's .pas.</summary>
    Pas       : string;
    /// <summary>The root component's class.</summary>
    FormClass : string;
    /// <summary>The selection without the root.</summary>
    Components: TArray<TConvertComponent>;
  end;

  /// <summary>Waits for the editor to exit, then reopens the unit on the main thread.</summary>
  /// <remarks>Owns AProcess. Freed by the next launch or ShutdownConvertLaunch, never by
  /// itself; TThread's destructor drops a queued reopen, so none runs after unload.</remarks>
  TConvertChildWaiter = class(TThread)
    private
      FProcess: THandle;
      procedure ChildExited;
    protected
      procedure Execute; override;
    public
      constructor Create(AProcess: THandle);
      destructor Destroy; override;
  end;

var
  GWaiter    : TConvertChildWaiter = nil;   { the last editor's; finished when GChildUnit = '' }
  GChildUnit : string = '';                 { what the living editor was opened on; '' = none }
  GReopenPas : string = '';                 { the unit to reopen; '' for a launch with no request }
  GChildDb   : string = '';                 { the DB the queue holds while the editor lives (C12 N6); '' = none }
  GCapability: Integer = -1;                { -1 not probed; else the editor's convert_request }
  GProbing   : Boolean = False;

{ ---- OTA reads ---- }

function CurrentModule: IOTAModule;
var
  MS: IOTAModuleServices;
begin
  Result:= nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then Result:= MS.CurrentModule;
end;

function FormEditorOf(const pModule: IOTAModule): IOTAFormEditor;
begin
  Result:= nil;
  if pModule = nil then Exit;
  for var I:= 0 to pModule.ModuleFileCount - 1 do
    if Supports(pModule.ModuleFileEditors[I], IOTAFormEditor, Result) then Exit;
end;

{ The designer holds real components in this process, so the handle is the component.
  The contract's GetPropValueByName is the fallback for a handle that is none. }
function ComponentName(const pComp: IOTAComponent): string;
var
  Obj: TObject;
begin
  Result:= '';
  Obj:= TObject(pComp.GetComponentHandle);
  if Obj is TComponent then Result:= TComponent(Obj).Name
  else pComp.GetPropValueByName('Name', Result);
end;

function ReadSelection(out pSel: TConvertSelection): Boolean;
var
  Module: IOTAModule    ;
  FormEd: IOTAFormEditor;
  Root  : IOTAComponent ;
  All   : TArray<TConvertComponent>;
  C     : TConvertComponent;
begin
  Result:= False;
  pSel:= Default(TConvertSelection);
  Module:= CurrentModule;
  FormEd:= FormEditorOf(Module);
  if FormEd = nil then Exit;
  Root:= FormEd.GetRootComponent;
  if Root = nil then Exit;
  for var I:= 0 to FormEd.GetSelCount - 1 do
  begin
    var Comp: IOTAComponent:= FormEd.GetSelComponent(I);
    C.Name    := ComponentName(Comp);
    C.TypeName:= Comp.GetComponentType;
    All:= All + [C];
  end;
  pSel.Pas       := ChangeFileExt(Module.FileName, PAS_EXT);
  pSel.FormClass := Root.GetComponentType;
  pSel.Components:= SelectionWithoutRoot(All, ComponentName(Root));
  Result:= Length(pSel.Components) > 0;
end;

function ModuleIsDirty(const pModule: IOTAModule): Boolean;
begin
  Result:= False;
  for var I:= 0 to pModule.ModuleFileCount - 1 do
    if pModule.ModuleFileEditors[I].Modified then Exit(True);
end;

function FindModuleOf(const pPas: string): IOTAModule;
var
  MS: IOTAModuleServices;
begin
  Result:= nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then Result:= MS.FindModule(pPas);
end;

procedure ReopenUnit(const pPas: string);
var
  MS    : IOTAModuleServices;
  Module: IOTAModule        ;
  FormEd    : IOTAFormEditor    ;
begin
  try
    if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
    Module:= MS.OpenModule(pPas);
    FormEd:= FormEditorOf(Module);
    if FormEd <> nil then FormEd.Show
    else if Module <> nil then Module.Show;
  except
    on E: Exception do DLT(LOG_TOPIC, 'reopen failed: ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ ---- the child ---- }

{ Lifts the queue hold StartChild placed; held reindex / lint-all jobs then run. }
procedure ReleaseChildDb;
begin
  if GChildDb = '' then Exit;
  JobQueue.ReleaseDb(GChildDb);
  GChildDb:= '';
end;

constructor TConvertChildWaiter.Create(AProcess: THandle);
begin
  FProcess:= AProcess;
  inherited Create(False);
end;

destructor TConvertChildWaiter.Destroy;
begin
  inherited Destroy;
  CloseHandle(FProcess);
end;

procedure TConvertChildWaiter.Execute;
begin
  try
    while not Terminated do
      if WaitForSingleObject(FProcess, WAIT_SLICE_MS) = WAIT_OBJECT_0 then
      begin
        Queue(ChildExited);
        Exit;
      end;
  except
    on E: Exception do DLT(LOG_TOPIC, 'waiter: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TConvertChildWaiter.ChildExited;
var
  Pas: string;
begin
  Pas:= GReopenPas;
  GChildUnit:= '';
  GReopenPas:= '';
  ReleaseChildDb;
  if Pas <> '' then ReopenUnit(Pas);
end;

function RefusedForLivingChild: Boolean;
begin
  Result:= GChildUnit <> '';
  if Result then
    ShowMessage('The conversion editor is already open for ' + ExtractFileName(GChildUnit) + ' -- close it first.');
end;

{ False with nothing started. The handle goes to the waiter; a failed start tells the caller.
  pDb (may be '') is held in the job queue until the child exits: a save-triggered reindex
  or lint-all on it would collide with the editor's reindex-before-apply (C12 N6). }
function StartChild(const pCmd, pUnit, pReopen, pDb: string): Boolean;
var
  SI : TStartupInfoW      ;
  PI : TProcessInformation;
  Buf: string             ;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb:= SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
  Buf:= pCmd;
  UniqueString(Buf);
  DLT(LOG_TOPIC, 'launch: ' + pCmd);
  Result:= CreateProcessW(nil, PWideChar(Buf), nil, nil, False, DETACHED_PROCESS, nil, nil, SI, PI);  // dl:ok taint-command-injection@edd6 -- the exe is the user's own Options override, beside which the editor is looked up; the arguments are quoted paths from the IDE
  if not Result then Exit;
  CloseHandle(PI.hThread);
  FreeAndNil(GWaiter); { the previous editor's: it ended (RefusedForLivingChild), so this is quick }
  GChildUnit:= pUnit;
  GReopenPas:= pReopen;
  GChildDb:= pDb;
  if pDb <> '' then JobQueue.HoldDb(pDb);
  GWaiter:= TConvertChildWaiter.Create(PI.hProcess);
end;

{ ---- the editor ---- }

function FindEditor(out pEditor: string): Boolean;
var
  Exe: string;
begin
  pEditor:= '';
  Result:= RequireEngine(Exe);
  if not Result then
  begin
    ShowMessage('drag-lint: ' + ENGINE_NOT_FOUND_MSG);
    Exit;
  end;
  pEditor:= ExtractFilePath(Exe) + EDITOR_EXE;
  Result:= FileExists(pEditor);
  if not Result then
    ShowMessage(EDITOR_EXE + ' is not beside the engine (' + pEditor + ') -- install the release pack.');
end;

function RequestsFolder: string;
begin
  Result:= ConvertRequestsFolder(GetEnvironmentVariable('LOCALAPPDATA'));
end;

procedure TellNoCapability;
begin
  ShowMessage(EDITOR_EXE + ' beside the engine does not support --convert-request (older build)');
end;

{ Runs pThen once the editor is known to take a request. Never at IDE start: the first
  click pays, off the main thread, and an older editor's window is killed by the budget. }
procedure WithProbedEditor(const pEditor: string; const pThen: TProc);
var
  Caps: string;
begin
  if GCapability >= 1 then
  begin
    pThen();
    Exit;
  end;
  if GCapability = 0 then
  begin
    TellNoCapability;
    Exit;
  end;
  if GProbing then Exit;
  Caps:= TPath.Combine(RequestsFolder, 'caps-' + IntToStr(GetCurrentProcessId) + '.txt');
  TDirectory.CreateDirectory(RequestsFolder);
  GProbing:= True;
  RunCliAsync(Format('"%s" --write-capabilities "%s"', [pEditor, Caps]),
    procedure(AExitCode: Integer; const AOutput: string)
    begin
      GProbing:= False;
      GCapability:= 0;
      try
        { No file is an answer too: an older editor opened its window instead. }
        GCapability:= ParseEditorCapabilities(TFile.ReadAllText(Caps, TEncoding.UTF8));
        TFile.Delete(Caps);
      except
        on E: Exception do DLT(LOG_TOPIC, 'probe: ' + E.ClassName + ': ' + E.Message);
      end;
      DLT(LOG_TOPIC, Format('probe: exit=%d capability=%d', [AExitCode, GCapability]));
      if GCapability >= 1 then pThen()
      else TellNoCapability;
    end,
    PROBE_BUDGET_MS);
end;

{ ---- the hand-off ---- }

{ A unit whose buffer differs from disk is never converted. }
function SavedOrClean(const pModule: IOTAModule; const pPas: string): Boolean;
begin
  Result:= not ModuleIsDirty(pModule);
  if Result then Exit;
  if MessageDlg(ExtractFileName(pPas) + ' has unsaved changes. Save it and continue?',
    mtConfirmation, [mbYes, mbCancel], 0) = mrYes then Result:= pModule.Save(False, True);
end;

{ Past the probe; the selection was read at the click. The module is looked up again:
  the probe gave the user a moment to close it. }
procedure HandOff(const pScope, pEditor: string; const pSel: TConvertSelection);
var
  Module  : IOTAModule;
  Proj    : string    ;
  Db      : string    ;
  Plat    : string    ;
  Json    : string    ;
  ReqPath : string    ;
  Fields  : TConvertRequestFields;
begin
  Module:= FindModuleOf(pSel.Pas);
  if Module = nil then Exit;
  Proj:= GetActiveProjectFilePath;
  Db:= if Proj <> '' then PrimaryDbForProject(Proj, LoadSettings) else '';
  if Db = '' then
  begin
    ShowMessage('drag-lint: the active project has no index -- build it first (Index && Maintenance).');
    Exit;
  end;
  if (not SavedOrClean(Module, pSel.Pas)) or RefusedForLivingChild then Exit;

  Plat:= GetActivePlatformForLibrary;
  Fields:= Default(TConvertRequestFields);
  Fields.Scope      := pScope;
  Fields.ProjectFile:= Proj;
  Fields.ProjectDb  := Db;
  Fields.Platform   := Plat;
  Fields.Pas        := pSel.Pas;
  Fields.FormClass  := pSel.FormClass;
  Fields.Components := pSel.Components;
  Fields.IdePid     := GetCurrentProcessId;
  Fields.Written    := Now;
  Json:= BuildConvertRequestJson(Fields);
  TDirectory.CreateDirectory(RequestsFolder);
  PruneConvertRequests(RequestsFolder, REQUEST_KEEP_DAYS, Now);
  ReqPath:= TPath.Combine(RequestsFolder, ConvertRequestFileName(Now, GetCurrentProcessId));
  TFile.WriteAllText(ReqPath, Json, TUTF8Encoding.Create(False));

  { The request stays on disk through every failure below: it is the diagnostic. }
  if not Module.Close then
  begin
    ShowMessage('Could not close ' + ExtractFileName(pSel.Pas) + ' in the IDE');
    Exit;
  end;
  Module:= nil;
  if not StartChild(ConvertLaunchCommand(pEditor, ReqPath, pSel.Pas, Db, Plat), pSel.Pas, pSel.Pas, Db) then
  begin
    ShowMessage('Could not start ' + pEditor + ': ' + SysErrorMessage(GetLastError));
    ReopenUnit(pSel.Pas);
  end;
end;

procedure StartConversion(const pScope: string);
var
  Sel   : TConvertSelection;
  Editor: string;
begin
  if not ReadSelection(Sel) then
  begin
    ShowMessage('Select one or more components on the form first.');
    Exit;
  end;
  if not FindEditor(Editor) then Exit;
  if RefusedForLivingChild then Exit;
  WithProbedEditor(Editor,
    procedure
    begin
      HandOff(pScope, Editor, Sel);
    end);
end;

procedure InvokeConvertSelectedComponents(Sender: TObject);
begin
  StartConversion(SCOPE_SELECTED);
end;

procedure InvokeConvertAllOfTypeOnForm(Sender: TObject);
begin
  StartConversion(SCOPE_FORM);
end;

procedure InvokeOpenConversionEditor(Sender: TObject);
var
  Module: IOTAModule;
  Pas   : string    ;
  Editor: string    ;
  Proj  : string    ;
  Db    : string    ;
begin
  Module:= CurrentModule;
  if Module = nil then
  begin
    ShowMessage('drag-lint: open a unit first.');
    Exit;
  end;
  Pas:= ChangeFileExt(Module.FileName, PAS_EXT);
  if not FindEditor(Editor) then Exit;
  if RefusedForLivingChild then Exit;
  Proj:= GetActiveProjectFilePath;
  Db:= if Proj <> '' then PrimaryDbForProject(Proj, LoadSettings) else '';
  { No request, so no probe: every editor that ships takes --form. }
  if not StartChild(ConvertLaunchCommand(Editor, '', Pas, Db, GetActivePlatformForLibrary), Pas, '', Db) then
    ShowMessage('Could not start ' + Editor + ': ' + SysErrorMessage(GetLastError));
end;

procedure UpdateConvertComponentsMenu(Sender: TObject);
var
  Sel    : TConvertSelection;
  HasSel : Boolean;
  Module : IOTAModule;
  HasUnit: Boolean;
begin
  if Sender is not TMenuItem then Exit;
  try
    HasSel := ReadSelection(Sel);
    Module := CurrentModule;
    HasUnit:= (Module <> nil) and SameText(ExtractFileExt(ChangeFileExt(Module.FileName, PAS_EXT)), PAS_EXT) and FileExists(ChangeFileExt(Module.FileName, PAS_EXT));
    for var I:= 0 to TMenuItem(Sender).Count - 1 do
    begin
      var Item: TMenuItem:= TMenuItem(Sender).Items[I];
      if Item.Tag = CONVERT_TAG_SELECTION then Item.Enabled:= HasSel
      else if Item.Tag = CONVERT_TAG_OPEN then Item.Enabled:= HasUnit;
    end;
  except
    on E: Exception do DLT(LOG_TOPIC, 'menu update: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure ShutdownConvertLaunch;
begin
  GReopenPas:= '';
  FreeAndNil(GWaiter);
  { Unload: the queue is torn down too; touching JobQueue here could re-create it. }
  GChildDb:= '';
end;

end.