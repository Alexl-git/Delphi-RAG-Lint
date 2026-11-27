unit DRagLint.CLI.RepoGridCopy;

{ drag-lint 1.56 -- lane GCP-C: `repo copy-grid`, the sub-verb that copies the events of a grid view, its
  columns and their events to another view of the same form (any of table / banded table / card / layout
  view), or ONE event (the copy model is DRagLint.FieldRepo.GridCopy). DRagLint.CLI.Repo resolves the
  repository path and dispatches here in ONE line; the flags are read from the command line (ParseArgs only
  has to accept them). The repository itself is NOT opened: the copy works on the form's DFM and unit, and
  --repo / --project are only what `repo` needs to dispatch. }

interface

const
  /// <summary>This unit's part of the `repo` sub-verb list in the "use one of" message.</summary>
  /// <remarks>Starts with ', '.</remarks>
  REPO_GRIDCOPY_SUBS = ', copy-grid';

/// <summary>True for the sub-verb this unit runs: copy-grid.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>True when RunRepoGridCopyVerb handles it.</returns>
function IsRepoGridCopySub(const pSub: string): Boolean;

/// <summary>Runs `repo copy-grid --dfm FILE [--unit FILE] --from VIEW --to VIEW [--event NAME [--from-column COL
/// [--to-column COL]]] [--apply | --select FILE] [--dry-run]`, or `repo copy-grid --dfm FILE --list [--from VIEW]`.</summary>
/// <param name="pSub">The sub-verb, for messages.</param>
/// <param name="pPath">The repository file (already resolved from --repo / --project); not opened.</param>
/// <param name="pJson">--json: one JSON object (the plan of RenderGridCopyJson plus mode, applied, written, backups;
/// with --list: views and events) instead of text.</param>
/// <returns>0 = ok (a dry run and a plan without changes included); 1 = a form that cannot be read, a view or event
/// the form does not have, a plan the --select file does not belong to, a file that cannot be written; 2 = a usage
/// error: no --dfm, no --from / --to (without --list), a --from-column / --to-column flag without --event, a
/// --select file that does not exist, has no `# plan ID` line or names an unknown or blocked id (nothing is
/// written).</returns>
/// <remarks>--unit defaults to the .pas beside the DFM (none = no unit: no column can be added). The default is a
/// DRY RUN: no file changes. --apply writes the checked, not blocked changes, --select exactly the ids its file names
/// (one id per line, or `all`; the file must hold the `# plan ID` line of the dry run); --dry-run wins over both.
/// Every changed file gets a backup beside it. Not thread-safe; reads ParamStr.</remarks>
function RunRepoGridCopyVerb(const pSub, pPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DfmWrite,
  DRagLint.FieldRepo.GridCopy;

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;
  EXIT_USAGE = 2;
  SUB_COPY_GRID = 'copy-grid';
  PLAN_MARK = '# plan ';
  DRY_RUN_LINE = 'dry run: nothing written (add --apply, or --select <file> with the # plan line and the ids, to write)';

type
  TRunOptions = record
    DfmFile: string;
    UnitFile: string;
    Request: TGridCopyRequest;
    SelectFile: string;
    List: Boolean;
    Write: Boolean;
    Json: Boolean;
  end;

function IsRepoGridCopySub(const pSub: string): Boolean;
begin
  Result:= SameText(pSub, SUB_COPY_GRID);
end;

function CommandLineFlag(const pFlag: string): Boolean;
var
  VI: Integer;
begin
  Result:= False;
  for VI:= 1 to ParamCount do
    if SameText(ParamStr(VI), pFlag) then Exit(True);
end;

function CommandLineValue(const pFlag: string): string;
var
  VI: Integer;
begin
  Result:= '';
  for VI:= 1 to ParamCount - 1 do
    if SameText(ParamStr(VI), pFlag) then Exit(ParamStr(VI + 1));
end;

{ The names the model wants, from the flags; '' when a name is not given. }
function ReadOptions(pJson: Boolean; out pError: string): TRunOptions;
begin
  pError:= '';
  Result:= Default(TRunOptions);
  Result.Json:= pJson;
  Result.DfmFile:= CommandLineValue('--dfm');
  Result.UnitFile:= CommandLineValue('--unit');
  Result.SelectFile:= CommandLineValue('--select');
  Result.List:= CommandLineFlag('--list');
  Result.Write:= (CommandLineFlag('--apply') or (Result.SelectFile <> '')) and not CommandLineFlag('--dry-run');
  Result.Request.SourceView:= CommandLineValue('--from');
  Result.Request.TargetView:= CommandLineValue('--to');
  Result.Request.EventName:= CommandLineValue('--event');
  Result.Request.SourceColumn:= CommandLineValue('--from-column');
  Result.Request.TargetColumn:= CommandLineValue('--to-column');
  if Result.DfmFile = '' then
    pError:= 'give the form: --dfm <file.dfm>'
  else if (not Result.List) and ((Result.Request.SourceView = '') or (Result.Request.TargetView = '')) then
    pError:= 'give the two views: --from <view> --to <view> (--list shows the views of the form)'
  else if (Result.Request.EventName = '') and ((Result.Request.SourceColumn <> '') or (Result.Request.TargetColumn <> '')) then
    pError:= '--from-column / --to-column name the column of ONE event: add --event <name>'
  else if (Result.SelectFile <> '') and (not TFile.Exists(Result.SelectFile)) then
    pError:= 'the --select file does not exist: ' + Result.SelectFile;
end;

function LoadForm(const pOptions: TRunOptions): TGridCopyForm;
var
  VUnit: string;
begin
  if not TFile.Exists(pOptions.DfmFile) then
    raise EGridCopyError.Create('the DFM does not exist: ' + pOptions.DfmFile);
  Result:= Default(TGridCopyForm);
  Result.DfmFile:= ExpandFileName(pOptions.DfmFile);
  Result.DfmBytes:= TFile.ReadAllBytes(Result.DfmFile);
  VUnit:= if pOptions.UnitFile <> '' then ExpandFileName(pOptions.UnitFile) else ChangeFileExt(Result.DfmFile, '.pas');
  if TFile.Exists(VUnit) then
  begin
    Result.UnitFile:= VUnit;
    Result.UnitBytes:= TFile.ReadAllBytes(VUnit);
  end
  else if pOptions.UnitFile <> '' then
    raise EGridCopyError.Create('the unit does not exist: ' + pOptions.UnitFile);
end;

{ Ids say nothing without the plan they were read from. }
procedure CheckPlanLine(const pLines: TArray<string>);
var
  VLine: string;
begin
  for VLine in pLines do
    if Trim(VLine).StartsWith(PLAN_MARK, True) then Exit;
  raise EFrChangeSetError.Create('the --select file has no line ' + QuotedStr(PLAN_MARK + '<id>') +
    ': copy it from the dry run the ids are from. Nothing written');
end;

function ChosenIds(const pPlan: TGridCopyPlan; const pSelectFile: string): TArray<Integer>;
var
  VLines: TArray<string>;
begin
  if pSelectFile = '' then Exit(GridCopyDefaultIds(pPlan));
  VLines:= TFile.ReadAllLines(pSelectFile);
  CheckPlanLine(VLines);
  Result:= SelectGridCopy(pPlan, VLines);
end;

procedure PrintList(const pForm: TGridCopyForm; const pView: string; pJson: Boolean);
var
  VViews: TArray<TGridCopyViewInfo>;
  VEvents: TArray<TGridCopyEvent>;
  VView: TGridCopyViewInfo;
  VEvent: TGridCopyEvent;
  VRoot, VItem: TJSONObject;
  VViewList, VEventList: TJSONArray;
begin
  VViews:= GridCopyViews(pForm);
  VEvents:= nil;
  if pView <> '' then VEvents:= GridCopyEvents(pForm, pView);
  if not pJson then
  begin
    for VView in VViews do
      Writeln('view ', VView.Name, ' (', VView.ViewClass, ') items ', VView.ItemClass, ': ', VView.ColumnCount, ' columns');
    for VEvent in VEvents do
      Writeln('event ', VEvent.Component, ' (', VEvent.ComponentClass, ') ', VEvent.Event, ' = ', VEvent.Handler);
    Exit;
  end;
  VRoot:= TJSONObject.Create;
  try
    VViewList:= TJSONArray.Create;
    VRoot.AddPair('views', VViewList);
    for VView in VViews do
    begin
      VItem:= TJSONObject.Create;
      VItem.AddPair('name', VView.Name).AddPair('class', VView.ViewClass).AddPair('item_class', VView.ItemClass)
        .AddPair('columns', TJSONNumber.Create(VView.ColumnCount));
      VViewList.AddElement(VItem);
    end;
    VEventList:= TJSONArray.Create;
    VRoot.AddPair('events', VEventList);
    for VEvent in VEvents do
    begin
      VItem:= TJSONObject.Create;
      VItem.AddPair('component', VEvent.Component).AddPair('class', VEvent.ComponentClass)
        .AddPair('column', TJSONBool.Create(VEvent.IsColumn)).AddPair('event', VEvent.Event).AddPair('handler', VEvent.Handler);
      VEventList.AddElement(VItem);
    end;
    Writeln(VRoot.ToJSON);
  finally
    VRoot.Free;
  end;
end;

procedure PrintResult(const pPlan: TGridCopyPlan; const pOptions: TRunOptions; pApplied: Integer;
  const pOutputs: TArray<TDfmwOutput>; const pBackups: TArray<string>);
var
  VLine, VBackup: string;
  VRoot: TJSONObject;
  VWritten, VBackupList: TJSONArray;
  VOutput: TDfmwOutput;
begin
  if not pOptions.Json then
  begin
    for VLine in RenderGridCopyText(pPlan) do Writeln(VLine);
    if not pOptions.Write then Writeln(DRY_RUN_LINE)
    else
    begin
      Writeln('WRITTEN ', Length(pOutputs));
      for VBackup in pBackups do Writeln('backup ', VBackup);
    end;
    Exit;
  end;
  VRoot:= TJSONObject.ParseJSONValue(RenderGridCopyJson(pPlan)) as TJSONObject;
  try
    VRoot.AddPair('mode', if pOptions.Write then 'apply' else 'dry-run');
    VRoot.AddPair('applied', TJSONNumber.Create(pApplied));
    VWritten:= TJSONArray.Create;
    VRoot.AddPair('written', VWritten);
    for VOutput in pOutputs do VWritten.Add(VOutput.FileName);
    VBackupList:= TJSONArray.Create;
    VRoot.AddPair('backups', VBackupList);
    for VBackup in pBackups do VBackupList.Add(VBackup);
    Writeln(VRoot.ToJSON);
  finally
    VRoot.Free;
  end;
end;

{ 2 for a bad selection, 1 for everything that failed while planning or writing. }
function ExitCodeOf(pError: Exception): Integer;
begin
  Result:= if pError is EFrChangeSetError then EXIT_USAGE else EXIT_FAIL;
end;

function RunOptions(const pOptions: TRunOptions): Integer;
var
  VForm: TGridCopyForm;
  VPlan: TGridCopyPlan;
  VIds: TArray<Integer>;
  VOutputs: TArray<TDfmwOutput>;
  VBackups: TArray<string>;
begin
  VForm:= LoadForm(pOptions);
  if pOptions.List then
  begin
    PrintList(VForm, pOptions.Request.SourceView, pOptions.Json);
    Exit(EXIT_OK);
  end;
  VPlan:= PlanGridCopy(VForm, pOptions.Request);
  VIds:= nil;
  VOutputs:= nil;
  VBackups:= nil;
  if pOptions.Write then
  begin
    VIds:= ChosenIds(VPlan, pOptions.SelectFile);
    VOutputs:= ApplyGridCopy(VPlan, VIds);
    VBackups:= WriteOutputs(VOutputs);
  end;
  PrintResult(VPlan, pOptions, Length(VIds), VOutputs, VBackups);
  Result:= EXIT_OK;
end;

function RunRepoGridCopyVerb(const pSub, pPath: string; pJson: Boolean): Integer; // dl:ok unused-parameter@ed7d -- the `repo` dispatch signature is shared by every lane sub-verb; this verb works on the form, not the repository
var
  VOptions: TRunOptions;
  VError: string;
begin
  VOptions:= ReadOptions(pJson, VError);
  if VError <> '' then
  begin
    Writeln(ErrOutput, 'repo ', pSub, ': ', VError);
    Exit(EXIT_USAGE);
  end;
  try
    Result:= RunOptions(VOptions);
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'repo ', pSub, ': ', E.Message);
      Result:= ExitCodeOf(E);
    end;
  end;
end;

end.
