unit DragLint.Plugin.Cmd.GridCopy;

{ 1.56 command unit, lane GCP-P: drag-lint > Field Repository > Copy Grid Columns...
  Copies the events of one grid view of the form in the editor, its columns and their events to another view of the same
  form (`repo copy-grid`, model DRagLint.FieldRepo.GridCopy). Same shape as the 1.54 field commands: a --list run, two
  picks (from view, to view; then everything or one event), a dry run, the list of changes to check
  (DragLint.Plugin.FieldSelectDialog.ConfirmChanges), one run with the --select file, reload of the form.

  The menu row is registered in DragLint.Plugin.Cmd.FieldRepo (RegisterCommands), so the full menu path stays in one
  place. Everything above the not-CONSOLE conditional is pure (no VCL, no ToolsAPI, no I/O):
  tests\plugin\gridcopy\GridCopyCmdTests.dpr pins it on what a real engine printed for the fixture form. }

interface

uses
  DragLint.Plugin.FieldSelectModel;

const
  /// <summary>Command id of the grid-copy row in the 1.52 command table.</summary>
  GRID_COPY_CMD_ID = 'field-repository-10-grid-copy';

type
  /// <summary>One grid view of the form, as `repo copy-grid --list --json` prints it.</summary>
  TGcpView = record
    /// <summary>Component name and class.</summary>
    Name: string;
    ViewClass: string;
    /// <summary>Columns the DFM has for it.</summary>
    Columns: Integer;
  end;

  /// <summary>One event a view or one of its columns has a handler for.</summary>
  TGcpEvent = record
    /// <summary>Component (the view or the column) and the event as the DFM writes it.</summary>
    Component: string;
    Event: string;
    /// <summary>The handler method.</summary>
    Handler: string;
    /// <summary>True for a column.</summary>
    IsColumn: Boolean;
  end;

  /// <summary>What the user asked for.</summary>
  TGcpRequest = record
    /// <summary>The form's .dfm on disk; the unit is the .pas beside it.</summary>
    Dfm: string;
    /// <summary>Source and target view.</summary>
    Source: string;
    Target: string;
    /// <summary>One event to copy; '' = everything.</summary>
    Event: string;
    /// <summary>The source column that has the event; '' = the view itself.</summary>
    SourceColumn: string;
  end;

  /// <summary>Which run a command line is for.</summary>
  TGcpRun = (grPlan, grApply);

/// <summary>The arguments of `repo copy-grid --list`.</summary>
/// <param name="pDfm">The form's .dfm.</param>
/// <param name="pFromView">View whose events are wanted; '' = the views only.</param>
/// <returns>`--dfm "..." --list [--from V] --json`.</returns>
function GridCopyListArgs(const pDfm, pFromView: string): string;

/// <summary>Reads what `repo copy-grid --list --json` printed.</summary>
/// <param name="pOutput">The run's output; the one line that is a JSON object counts.</param>
/// <param name="pViews">The views, in file order.</param>
/// <param name="pEvents">The events of the --from view; empty without --from.</param>
/// <param name="pError">Why there is no result; '' when there is one.</param>
/// <returns>True when the output holds a views list.</returns>
function ParseGridCopyList(const pOutput: string; out pViews: TArray<TGcpView>; out pEvents: TArray<TGcpEvent>;
  out pError: string): Boolean;

/// <summary>The arguments of the dry run or of the write run.</summary>
/// <param name="pRequest">The copy.</param>
/// <param name="pRun">grPlan: `--dry-run --json`. grApply: exactly the ids of the select file.</param>
/// <param name="pSelectFile">The --select file; used for grApply only.</param>
/// <returns>The arguments after `repo copy-grid --project "..."`.</returns>
function GridCopyArgs(const pRequest: TGcpRequest; pRun: TGcpRun; const pSelectFile: string): string;

/// <summary>Reads the plan of a dry run with --json.</summary>
/// <param name="pOutput">The run's output.</param>
/// <param name="pPlan">Plan id, changes and remarks; a change is checked when the engine checks it and it is not blocked.</param>
/// <param name="pError">Why there is no plan; '' when there is one.</param>
/// <returns>True when the output holds a plan, an empty one too.</returns>
/// <remarks>pPlan.SelectFileText is the --select file of the checked changes, with the plan line.</remarks>
function ParseGridCopyPlan(const pOutput: string; out pPlan: TFsPlan; out pError: string): Boolean;

/// <summary>The view a command works on when nobody has to be asked.</summary>
/// <param name="pViews">The views of the form.</param>
/// <param name="pSelected">Names of the components selected in the designer.</param>
/// <param name="pNot">A view that does not count; '' for none.</param>
/// <returns>The index of the one selected view, else -1 = ask.</returns>
function GridCopyViewToUse(const pViews: TArray<TGcpView>; const pSelected: TArray<string>; const pNot: string): Integer;

/// <summary>The views as a list the dataset picker can show.</summary>
/// <param name="pViews">The views of the form.</param>
/// <param name="pNot">A view left out; '' for none.</param>
/// <param name="pIndexes">Index in pViews of each entry.</param>
/// <returns>One entry per view: Name = view, DatasetClass = view class.</returns>
function GridCopyViewPicks(const pViews: TArray<TGcpView>; const pNot: string; out pIndexes: TArray<Integer>): TArray<TFsDataset>;

/// <summary>What can be copied, as a list the dataset picker can show.</summary>
/// <param name="pEvents">The events of the source view.</param>
/// <returns>Entry 0 = everything; then one entry per event: Name = event, DatasetClass = component and handler.</returns>
function GridCopyEventPicks(const pEvents: TArray<TGcpEvent>): TArray<TFsDataset>;

/// <summary>Puts the pick of GridCopyEventPicks in the request.</summary>
/// <param name="pRequest">The request; Event and SourceColumn are set.</param>
/// <param name="pEvents">The events of the source view.</param>
/// <param name="pPick">Index of the pick; 0 = everything.</param>
procedure GridCopyApplyEventPick(var pRequest: TGcpRequest; const pEvents: TArray<TGcpEvent>; pPick: Integer);

/// <summary>Click handler of drag-lint > Field Repository > Copy Grid Columns...</summary>
/// <param name="pSender">The clicked menu item; unused.</param>
/// <remarks>Call from the IDE main thread only (menu click). In a CONSOLE build, which has no IDE, it shows the
/// "not yet available" message of the command table.</remarks>
procedure InvokeGridCopy(pSender: TObject);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Classes,
  {$IFNDEF CONSOLE}
  System.IOUtils,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Forms,
  ToolsAPI,
  DragLint.Plugin.CliAsync,
  DragLint.Plugin.ExeResolver,
  DragLint.Plugin.ProcRun,
  DragLint.Plugin.Telemetry,
  DragLint.Plugin.Theme,
  DragLint.Plugin.FieldSelectDialog,
  {$ENDIF}
  DragLint.Plugin.Cmd152;

const
  KEY_CHANGES = 'changes';
  EVERYTHING_NAME = '(everything)';
  EVERYTHING_CLASS = 'all events of the view, its columns and their events';

{ ---- the engine's output ---- }

{ The one line that is a JSON object; nil = none. }
function ObjectOf(const pOutput: string): TJSONObject;
var
  VLine: string;
  VValue: TJSONValue;
begin
  Result:= nil;
  for VLine in pOutput.Split([#13, #10]) do
    if VLine.StartsWith('{') then
    begin
      VValue:= TJSONObject.ParseJSONValue(VLine);
      if VValue is TJSONObject then Exit(TJSONObject(VValue));
      VValue.Free;
    end;
end;

function TextOf(pItem: TJSONValue; const pName: string): string;
begin
  if not pItem.TryGetValue<string>(pName, Result) then Result:= '';
end;

function ArrayOf(pItem: TJSONValue; const pName: string): TJSONArray;
begin
  if not pItem.TryGetValue<TJSONArray>(pName, Result) then Result:= nil;
end;

function NoObjectError(const pOutput: string): string;
begin
  Result:= 'the engine printed no result: ' + Trim(pOutput);
end;

function GridCopyListArgs(const pDfm, pFromView: string): string;
begin
  Result:= '--dfm "' + pDfm + '" --list' + (if pFromView = '' then '' else ' --from ' + pFromView) + ' --json';
end;

function ParseGridCopyList(const pOutput: string; out pViews: TArray<TGcpView>; out pEvents: TArray<TGcpEvent>;
  out pError: string): Boolean;
var
  VRoot: TJSONObject;
  VList: TJSONArray;
  VItem: TJSONValue;
  VView: TGcpView;
  VEvent: TGcpEvent;
begin
  pViews:= nil;
  pEvents:= nil;
  pError:= NoObjectError(pOutput);
  VRoot:= ObjectOf(pOutput);
  try
    if VRoot = nil then Exit(False);
    VList:= ArrayOf(VRoot, 'views');
    Result:= VList <> nil;
    if not Result then Exit;
    pError:= '';
    for VItem in VList do
    begin
      VView.Name:= TextOf(VItem, 'name');
      VView.ViewClass:= TextOf(VItem, 'class');
      if not VItem.TryGetValue<Integer>('columns', VView.Columns) then VView.Columns:= 0;
      pViews:= pViews + [VView];
    end;
    VList:= ArrayOf(VRoot, 'events');
    if VList <> nil then
      for VItem in VList do
      begin
        VEvent.Component:= TextOf(VItem, 'component');
        VEvent.Event:= TextOf(VItem, 'event');
        VEvent.Handler:= TextOf(VItem, 'handler');
        VEvent.IsColumn:= VItem.GetValue<Boolean>('column', False);
        pEvents:= pEvents + [VEvent];
      end;
  finally
    VRoot.Free;
  end;
end;

function GridCopyArgs(const pRequest: TGcpRequest; pRun: TGcpRun; const pSelectFile: string): string;
begin
  Result:= '--dfm "' + pRequest.Dfm + '" --from ' + pRequest.Source + ' --to ' + pRequest.Target;
  if pRequest.Event <> '' then Result:= Result + ' --event ' + pRequest.Event;
  if (pRequest.Event <> '') and (pRequest.SourceColumn <> '') then Result:= Result + ' --from-column ' + pRequest.SourceColumn;
  Result:= Result + (if pRun = grPlan then ' --dry-run --json' else ' --select "' + pSelectFile + '"');
end;

function ChangeOf(pItem: TJSONValue): TFsChange;
begin
  Result:= Default(TFsChange);
  if not pItem.TryGetValue<Integer>('id', Result.Id) then Result.Id:= 0;
  Result.Op:= TextOf(pItem, 'op');
  Result.Target:= TextOf(pItem, 'target');
  Result.Prop:= TextOf(pItem, 'prop');
  Result.OldText:= TextOf(pItem, 'old');
  Result.NewText:= TextOf(pItem, 'new');
  Result.Blocked:= TextOf(pItem, 'blocked');
  Result.Checked:= pItem.GetValue<Boolean>('checked', False) and (Result.Blocked = '');
end;

function ParseGridCopyPlan(const pOutput: string; out pPlan: TFsPlan; out pError: string): Boolean;
var
  VRoot: TJSONObject;
  VList: TJSONArray;
  VItem: TJSONValue;
begin
  pPlan:= Default(TFsPlan);
  pError:= NoObjectError(pOutput);
  VRoot:= ObjectOf(pOutput);
  try
    Result:= (VRoot <> nil) and (ArrayOf(VRoot, KEY_CHANGES) <> nil);
    if not Result then Exit;
    pError:= '';
    pPlan.PlanId:= TextOf(VRoot, 'plan');
    pPlan.Fingerprint:= VRoot.ToJSON;
    for VItem in ArrayOf(VRoot, KEY_CHANGES) do pPlan.Changes:= pPlan.Changes + [ChangeOf(VItem)];
    VList:= ArrayOf(VRoot, 'remarks');
    if VList <> nil then
      for VItem in VList do pPlan.Warnings:= pPlan.Warnings + [VItem.Value];
  finally
    VRoot.Free;
  end;
end;

{ ---- the picks ---- }

function GridCopyViewToUse(const pViews: TArray<TGcpView>; const pSelected: TArray<string>; const pNot: string): Integer;
var
  VI: Integer;
begin
  Result:= -1;
  for VI:= 0 to High(pViews) do
    if MatchText(pViews[VI].Name, pSelected) and not SameText(pViews[VI].Name, pNot) then
    begin
      if Result >= 0 then Exit(-1);
      Result:= VI;
    end;
end;

function GridCopyViewPicks(const pViews: TArray<TGcpView>; const pNot: string; out pIndexes: TArray<Integer>): TArray<TFsDataset>;
var
  VI: Integer;
  VPick: TFsDataset;
begin
  Result:= nil;
  pIndexes:= nil;
  for VI:= 0 to High(pViews) do
  begin
    if SameText(pViews[VI].Name, pNot) then Continue;
    VPick:= Default(TFsDataset);
    VPick.Name:= pViews[VI].Name;
    VPick.DatasetClass:= pViews[VI].ViewClass;
    Result:= Result + [VPick];
    pIndexes:= pIndexes + [VI];
  end;
end;

function GridCopyEventPicks(const pEvents: TArray<TGcpEvent>): TArray<TFsDataset>;
var
  VEvent: TGcpEvent;
  VPick: TFsDataset;
begin
  VPick:= Default(TFsDataset);
  VPick.Name:= EVERYTHING_NAME;
  VPick.DatasetClass:= EVERYTHING_CLASS;
  Result:= [VPick];
  for VEvent in pEvents do
  begin
    VPick:= Default(TFsDataset);
    VPick.Name:= VEvent.Event;
    VPick.DatasetClass:= VEvent.Component + ' = ' + VEvent.Handler;
    Result:= Result + [VPick];
  end;
end;

procedure GridCopyApplyEventPick(var pRequest: TGcpRequest; const pEvents: TArray<TGcpEvent>; pPick: Integer);
begin
  pRequest.Event:= '';
  pRequest.SourceColumn:= '';
  if (pPick < 1) or (pPick > Length(pEvents)) then Exit;
  pRequest.Event:= pEvents[pPick - 1].Event;
  if pEvents[pPick - 1].IsColumn then pRequest.SourceColumn:= pEvents[pPick - 1].Component;
end;

{$IFDEF CONSOLE}

procedure InvokeGridCopy(pSender: TObject);  // dl:ok unused-parameter@1fb2 -- TCmd152Click signature; a console build has no IDE
begin
  Cmd152NotYetAvailable(GRID_COPY_CMD_ID);
end;

{$ELSE}

{ ---- the IDE ---- }

const
  PLAN_TITLE = 'Copy Grid Columns';
  STALL_MS = 300000;
  SUMMARY_LINES = 40;

type
  { What a step needs: the engine, the project and the saved form in the editor. }
  TGcpContext = record
    Exe: string;
    Project: string;
    Request: TGcpRequest;
    Selected: TArray<string>;
    Views: TArray<TGcpView>;
    Events: TArray<TGcpEvent>;
  end;

  TGcpStep = reference to procedure(const pOutput: string);

function ActiveProjectFile: string;
var
  VServices: IOTAModuleServices;
  VGroup: IOTAProjectGroup;
begin
  Result:= '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, VServices) then Exit;
  VGroup:= VServices.MainProjectGroup;
  if (VGroup <> nil) and (VGroup.ActiveProject <> nil) then Result:= VGroup.ActiveProject.FileName;
end;

function OpenModuleOf(const pDfm: string): IOTAModule;
var
  VServices: IOTAModuleServices;
begin
  Result:= nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, VServices) then Result:= VServices.FindModule(ChangeFileExt(pDfm, '.pas'));
end;

function ModuleIsDirty(const pModule: IOTAModule): Boolean;
var
  VI: Integer;
begin
  Result:= False;
  if pModule = nil then Exit;
  for VI:= 0 to pModule.ModuleFileCount - 1 do
    if pModule.ModuleFileEditors[VI].Modified then Exit(True);
end;

{ The engine reads the form from disk. }
function SavedOrClean(const pModule: IOTAModule): Boolean;
begin
  Result:= not ModuleIsDirty(pModule);
  if Result then Exit;
  if MessageDlg(ExtractFileName(pModule.FileName) + ' has unsaved changes. Save it and continue?',
    mtConfirmation, [mbYes, mbCancel], 0) = mrYes then Result:= pModule.Save(False, True);
end;

{ The designer holds real components in this process, so the handle is the component. }
function SelectedComponents(const pModule: IOTAModule): TArray<string>;
var
  VDesigner: IOTAFormEditor;
  VObj: TObject;
  VI, VJ: Integer;
begin
  Result:= nil;
  for VI:= 0 to pModule.ModuleFileCount - 1 do
  begin
    if not Supports(pModule.ModuleFileEditors[VI], IOTAFormEditor, VDesigner) then Continue;
    for VJ:= 0 to VDesigner.GetSelCount - 1 do
    begin
      VObj:= TObject(VDesigner.GetSelComponent(VJ).GetComponentHandle);
      if VObj is TComponent then Result:= Result + [TComponent(VObj).Name];
    end;
  end;
end;

procedure Say(const pText: string);
begin
  ShowMessage('drag-lint: ' + PLAN_TITLE + sLineBreak + sLineBreak + pText);
end;

{ Engine, project and the saved form in the editor, or False after telling the user why not. }
function ResolveContext(out pContext: TGcpContext): Boolean;
var
  VServices: IOTAModuleServices;
  VModule: IOTAModule;
begin
  pContext:= Default(TGcpContext);
  Result:= RequireEngine(pContext.Exe);
  if not Result then
  begin
    ReportEngineMissing;
    Exit;
  end;
  pContext.Project:= ActiveProjectFile;
  if pContext.Project = '' then
  begin
    Say('open a project first; the field repository belongs to the active project.');
    Exit(False);
  end;
  VModule:= nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, VServices) then VModule:= VServices.CurrentModule;
  if VModule <> nil then
  begin
    pContext.Request.Dfm:= ChangeFileExt(VModule.FileName, '.dfm');
    pContext.Selected:= SelectedComponents(VModule);
    if FileExists(pContext.Request.Dfm) then Exit(SavedOrClean(VModule));
  end;
  Say('open the form first; its grids are read from the .dfm on disk.');
  Result:= False;
end;

function CommandLine(const pContext: TGcpContext; const pArgs: string): string;
begin
  Result:= '"' + pContext.Exe + '" repo copy-grid --project "' + pContext.Project + '" ' + pArgs;
end;

{ One `repo copy-grid` run off the main thread; pNext gets the output of a run that succeeded. }
procedure RunStep(const pContext: TGcpContext; const pArgs: string; const pNext: TGcpStep);
var
  VNext: TGcpStep;
begin
  VNext:= pNext;
  RunCliAsync(CommandLine(pContext, pArgs),
    procedure(pExitCode: Integer; const pOutput: string)
    begin
      try
        if pExitCode = 0 then VNext(pOutput)
        else Say('exit ' + IntToStr(pExitCode) + sLineBreak + sLineBreak + ApplyLog(pOutput, SUMMARY_LINES));
      except
        on E: EAbort do DLT('field-repository', PLAN_TITLE + ': ' + E.Message);
        on E: Exception do
        begin
          DLT('field-repository', PLAN_TITLE + ': ' + E.ClassName + ': ' + E.Message);
          Say('this step failed: ' + E.ClassName + ': ' + E.Message);
        end;
      end;
    end, STALL_MS);
end;

{ The one the user means: the selected view, else a pick. }
function ChooseView(const pContext: TGcpContext; const pPrompt, pNot: string; out pName: string): Boolean;
var
  VIndex: Integer;
  VIndexes: TArray<Integer>;
  VPicks: TArray<TFsDataset>;
begin
  pName:= '';
  VIndex:= GridCopyViewToUse(pContext.Views, pContext.Selected, pNot);
  if VIndex >= 0 then
  begin
    pName:= pContext.Views[VIndex].Name;
    Exit(True);
  end;
  VPicks:= GridCopyViewPicks(pContext.Views, pNot, VIndexes);
  Result:= False;
  if (VPicks = nil) or not PickDataset(PLAN_TITLE + ' -- ' + pPrompt, VPicks, ApplyIdeTheme, VIndex) then Exit;
  if (VIndex < 0) or (VIndex >= Length(VPicks)) then Exit;
  pName:= VPicks[VIndex].Name;
  Result:= True;
end;

{ The form after the write run: reloaded when it has no unsaved changes. }
procedure ReloadAfter(const pDfm: string);
var
  VModule: IOTAModule;
  VError: string;
begin
  VModule:= OpenModuleOf(pDfm);
  if (VModule = nil) or ModuleIsDirty(VModule) then Exit;
  VError:= '';
  try
    VModule.Refresh(True);
  except
    on E: Exception do VError:= E.ClassName + ': ' + E.Message;
  end;
  Say(ApplyNotice(if VError = '' then frReload else frFailed, ExtractFileName(pDfm), VError));
end;

{ The run that writes exactly the checked changes. }
procedure ApplyPlan(const pContext: TGcpContext; const pPlan: TFsPlan);
var
  VSelectFile: string;
  VContext: TGcpContext;
begin
  VContext:= pContext;
  VSelectFile:= TPath.Combine(TPath.GetTempPath, 'drag-lint-select-' + TGUID.NewGuid.ToString + '.txt');
  TFile.WriteAllText(VSelectFile, pPlan.SelectFileText);
  RunCliAsync(CommandLine(VContext, GridCopyArgs(VContext.Request, grApply, VSelectFile)),
    procedure(pExitCode: Integer; const pOutput: string)
    begin
      System.SysUtils.DeleteFile(VSelectFile);
      if pExitCode = 0 then ReloadAfter(VContext.Request.Dfm);
      Say((if pExitCode = 0 then 'done' else 'exit ' + IntToStr(pExitCode)) + sLineBreak + sLineBreak + ApplyLog(pOutput, SUMMARY_LINES));
    end, STALL_MS);
end;

{ Dry run, the changes to check, then the write run. }
procedure ConfirmAndApply(const pContext: TGcpContext);
var
  VContext: TGcpContext;
begin
  VContext:= pContext;
  RunStep(VContext, GridCopyArgs(VContext.Request, grPlan, ''),
    procedure(const pOutput: string)
    var
      VPlan: TFsPlan;
      VError: string;
    begin
      if not ParseGridCopyPlan(pOutput, VPlan, VError) then
        Say(VError)
      else if Length(VPlan.Changes) = 0 then
        Say('nothing to copy' + sLineBreak + string.Join(sLineBreak, VPlan.Warnings))
      else if ConfirmChanges(PLAN_TITLE, VPlan, ApplyIdeTheme) and (VPlan.CheckedCount > 0) then
        ApplyPlan(VContext, VPlan);
    end);
end;

{ The events of the source view: everything, or one of them. }
procedure ChooseWhat(const pContext: TGcpContext);
var
  VContext: TGcpContext;
begin
  VContext:= pContext;
  RunStep(VContext, GridCopyListArgs(VContext.Request.Dfm, VContext.Request.Source),
    procedure(const pOutput: string)
    var
      VViews: TArray<TGcpView>;
      VPick: Integer;
      VError: string;
    begin
      if not ParseGridCopyList(pOutput, VViews, VContext.Events, VError) then
      begin
        Say(VError);
        Exit;
      end;
      VPick:= 0;
      if (VContext.Events <> nil) and not PickDataset(PLAN_TITLE + ' -- what to copy', GridCopyEventPicks(VContext.Events), ApplyIdeTheme, VPick) then Exit;
      GridCopyApplyEventPick(VContext.Request, VContext.Events, VPick);
      ConfirmAndApply(VContext);
    end);
end;

procedure InvokeGridCopy(pSender: TObject);  // dl:ok unused-parameter@1fb2 -- TCmd152Click signature
var
  VContext: TGcpContext;
begin
  if not ResolveContext(VContext) then Exit;
  RunStep(VContext, GridCopyListArgs(VContext.Request.Dfm, ''),
    procedure(const pOutput: string)
    var
      VEvents: TArray<TGcpEvent>;
      VError, VFrom, VTo: string;
    begin
      if not ParseGridCopyList(pOutput, VContext.Views, VEvents, VError) then
        Say(VError)
      else if Length(VContext.Views) < 2 then
        Say('the form has fewer than two grid views; there is nothing to copy between.')
      else if ChooseView(VContext, 'copy from', '', VFrom) and ChooseView(VContext, 'copy to', VFrom, VTo) then
      begin
        VContext.Request.Source:= VFrom;
        VContext.Request.Target:= VTo;
        ChooseWhat(VContext);
      end;
    end);
end;

{$ENDIF}

end.
