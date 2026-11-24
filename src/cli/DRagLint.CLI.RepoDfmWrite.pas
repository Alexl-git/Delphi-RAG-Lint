unit DRagLint.CLI.RepoDfmWrite;

{ drag-lint 1.54 -- lane TT-DFMWRITE: `repo write-dfm`, the field repository -> DFM change set (design
  2026-11-22-field-repository-v2-design.md sections 3 and 9). DRagLint.CLI.Repo resolves the repository path and
  dispatches here in ONE line; the flags are read from the command line (ParseArgs only has to accept them). The
  repository is only READ. }

interface

const
  /// <summary>This unit's part of the `repo` sub-verb list in the "use one of" message.</summary>
  /// <remarks>Starts with ', '.</remarks>
  REPO_DFMWRITE_SUBS = ', write-dfm';

/// <summary>True for the sub-verb this unit runs: write-dfm.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>True when RunRepoDfmWriteVerb handles it.</returns>
function IsRepoDfmWriteSub(const pSub: string): Boolean;

/// <summary>Runs `repo write-dfm --dfm FILE[;...] [--dataset NAME [--names A,B|all]] --direction repo-to-dfm
/// [--apply | --select FILE]`.</summary>
/// <param name="pSub">The sub-verb, for messages.</param>
/// <param name="pPath">The repository file (already resolved from --repo / --project); opened read-only.</param>
/// <param name="pJson">--json: one JSON object (datasets, changeSet, warnings, applied, log) instead of text.</param>
/// <returns>0 = ok (a dry run included); 1 = a missing repository, a DFM that cannot be planned or written; 2 = a usage
/// error: no --dfm, --direction missing or not repo-to-dfm, a bad --names selection or --select file (nothing is
/// written).</returns>
/// <remarks>The default is a DRY RUN: no file changes. --apply writes the checked changes, --select exactly the ids
/// its file names; --dry-run wins over both. The --select file must hold the line `# plan ID` of the dry run its ids are
/// from: without it exit 2, with another id than the plan now has exit 1; nothing is written then. Every changed file
/// gets a backup beside it.</remarks>
function RunRepoDfmWriteVerb(const pSub, pPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DfmReadPlan,
  DRagLint.FieldRepo.DfmReadSelection,
  DRagLint.FieldRepo.DfmWrite,
  DRagLint.FieldRepo.DfmWritePlan;

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;
  EXIT_USAGE = 2;
  SUB_WRITE_DFM = 'write-dfm';
  PLAN_MARK = '# plan ';
  DRY_RUN_LINE = 'dry run: nothing written (add --apply, or --select <file> with the # plan line and the ids, to write)';

type
  TRunOptions = record
    Files: TArray<string>;
    Dataset: string;
    Fields: TArray<string>;
    SelectFile: string;
    Write: Boolean;
    Json: Boolean;
  end;

  { What a run did. }
  TRunResult = record
    Plan: TDfmwPlan;
    Applied: Integer;
    Log: TArray<string>;
  end;

function IsRepoDfmWriteSub(const pSub: string): Boolean;
begin
  Result := SameText(pSub, SUB_WRITE_DFM);
end;

function CommandLineFlag(const pFlag: string): Boolean;
var
  VI: Integer;
begin
  Result := False;
  for VI := 1 to ParamCount do
    if SameText(ParamStr(VI), pFlag) then
      Exit(True);
end;

function CommandLineValue(const pFlag: string): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 1 to ParamCount - 1 do
    if SameText(ParamStr(VI), pFlag) then
      Exit(ParamStr(VI + 1));
end;

{ A list flag, its entries trimmed, empty ones dropped. }
function CommandLineList(const pFlag: string; pSeparator: Char): TArray<string>;
var
  VPart: string;
begin
  Result := nil;
  for VPart in CommandLineValue(pFlag).Split([pSeparator]) do
    if Trim(VPart) <> '' then
      Result := Result + [Trim(VPart)];
end;

function CountsText(const pCounts: TDfmrKindCounts): string;
var
  VKind: TFrFieldKind;
begin
  Result := '';
  for VKind := frkData to frkAggregate do
    Result := Result + (if VKind = frkData then '' else ', ') + IntToStr(pCounts[VKind]) + ' ' + FrKindName(VKind);
end;

procedure PrintText(const pRun: TRunResult; pWrite: Boolean);
var
  VReport: TDfmrDatasetReport;
  VLine: string;
begin
  for VReport in pRun.Plan.Datasets do
  begin
    Writeln('dataset ', VReport.DfmName, ' ', VReport.Dataset, ' (', VReport.DatasetClass, ') <- ',
      if VReport.TableName = '' then 'UNRESOLVED (' + VReport.Unresolved + ')' else VReport.TableName, ': ',
      CountsText(VReport.Counts));
    if Length(VReport.Unattributed) > 0 then
      Writeln('  no table column: ', string.Join(', ', VReport.Unattributed));
  end;
  for VLine in RenderChangeSetText(pRun.Plan.ChangeSet) do
    Writeln(VLine);
  Writeln(PLAN_MARK, pRun.Plan.PlanId);
  for VLine in pRun.Plan.Warnings do
    Writeln('warning: ', VLine);
  for VLine in pRun.Log do
    Writeln(VLine);
  Writeln(if pWrite then 'applied: ' + IntToStr(pRun.Applied) + ' changes' else DRY_RUN_LINE);
end;

function StringsJson(const pLines: TArray<string>): TJSONArray;
var
  VLine: string;
begin
  Result := TJSONArray.Create;
  for VLine in pLines do
    Result.Add(VLine);
end;

function DatasetsJson(const pPlan: TDfmwPlan): TJSONArray;
var
  VReport: TDfmrDatasetReport;
  VItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for VReport in pPlan.Datasets do
  begin
    VItem := TJSONObject.Create;
    Result.AddElement(VItem);
    VItem.AddPair('dfm', VReport.DfmName);
    VItem.AddPair('dataset', VReport.Dataset);
    VItem.AddPair('class', VReport.DatasetClass);
    VItem.AddPair('table', VReport.TableName);
    VItem.AddPair('unresolved', VReport.Unresolved);
    VItem.AddPair('noColumn', StringsJson(VReport.Unattributed));
  end;
end;

procedure PrintJson(const pRun: TRunResult);
var
  VRoot: TJSONObject;
begin
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair('datasets', DatasetsJson(pRun.Plan));
    VRoot.AddPair('changeSet', TJSONObject.ParseJSONValue(RenderChangeSetJson(pRun.Plan.ChangeSet)));
    VRoot.AddPair('plan', pRun.Plan.PlanId);
    VRoot.AddPair('warnings', StringsJson(pRun.Plan.Warnings));
    VRoot.AddPair('applied', TJSONNumber.Create(pRun.Applied));
    VRoot.AddPair('log', StringsJson(pRun.Log));
    Writeln(VRoot.ToJSON);
  finally
    VRoot.Free;
  end;
end;

{ Ids say nothing without the plan they were read from. }
procedure CheckPlanLine(const pLines: TArray<string>; const pPlanId: string);
var
  VLine: string;
  VFound: Boolean;
begin
  VFound := False;
  for VLine in pLines do
    if Trim(VLine).StartsWith(PLAN_MARK, True) then
    begin
      VFound := True;
      if not SameText(Trim(Trim(VLine).Substring(Length(PLAN_MARK))), pPlanId) then
        raise EDfmWriteError.Create('the --select file has ' + QuotedStr(Trim(VLine)) + ', the plan is now ' + pPlanId +
          ': a form, its unit, the repository or the selection changed since the dry run. Nothing written: run it again and choose again');
    end;
  if not VFound then
    raise EFrChangeSetError.Create('the --select file has no line ' + QuotedStr(PLAN_MARK + '<id>') +
      ': copy it from the dry run the ids are from. Nothing written');
end;

function ChosenChanges(const pPlan: TDfmwPlan; const pSelectFile: string): TArray<TFrChange>;
var
  VChange: TFrChange;
  VLines: TArray<string>;
begin
  if pSelectFile <> '' then
  begin
    VLines := TFile.ReadAllLines(pSelectFile);
    CheckPlanLine(VLines, pPlan.PlanId);
    Exit(SelectChanges(pPlan.ChangeSet, VLines));
  end;
  Result := nil;
  for VChange in pPlan.ChangeSet.Changes do
    if VChange.Checked and (VChange.Blocked = '') then
      Result := Result + [VChange];
end;

function RunOnRepo(const pPath: string; const pOptions: TRunOptions): TRunResult;
var
  VRepo: TFDConnection;
  VChosen: TArray<TFrChange>;
begin
  Result := Default(TRunResult);
  VRepo := OpenRepository(pPath, True);
  try
    Result.Plan := PlanDfmWrite(VRepo, pOptions.Files, pOptions.Dataset, pOptions.Fields);
  finally
    VRepo.Free;
  end;
  if not pOptions.Write then
    Exit;
  VChosen := ChosenChanges(Result.Plan, pOptions.SelectFile);
  Result.Log := ApplyDfmWrite(Result.Plan, VChosen);
  Result.Applied := Length(VChosen);
end;

function ReadOptions(pJson: Boolean; out pError: string): TRunOptions;
var
  VDirection: string;
begin
  pError := '';
  Result.Json := pJson;
  Result.Files := CommandLineList('--dfm', ';');
  Result.Dataset := CommandLineValue('--dataset');
  Result.Fields := CommandLineList('--names', ',');
  Result.SelectFile := CommandLineValue('--select');
  Result.Write := (CommandLineFlag('--apply') or (Result.SelectFile <> '')) and not CommandLineFlag('--dry-run');
  VDirection := CommandLineValue('--direction');
  if Length(Result.Files) = 0 then
    pError := 'give the form: --dfm <file.dfm>[;...]'
  else if not SameText(VDirection, FrDirectionName(fdRepoToDfm)) then
    pError := 'give --direction ' + FrDirectionName(fdRepoToDfm) + ' (there is no default direction)'
  else if (Result.SelectFile <> '') and (not TFile.Exists(Result.SelectFile)) then
    pError := 'the --select file does not exist: ' + Result.SelectFile;
end;

{ 2 for a bad selection or --select file, 1 for everything that failed while planning or writing. }
function ExitCodeOf(pError: Exception): Integer;
begin
  Result := if (pError is EFrChangeSetError) or (pError is EDfmWriteSelection) or (pError is EFrSelectionError)
    then EXIT_USAGE else EXIT_FAIL;
end;

function RunOptionsOnRepo(const pSub, pPath: string; const pOptions: TRunOptions): Integer;
var
  VRun: TRunResult;
begin
  try
    if not TFile.Exists(pPath) then
      raise ERepoError.Create('the repository does not exist (run repo init first): ' + pPath);
    VRun := RunOnRepo(pPath, pOptions);
    if pOptions.Json then
      PrintJson(VRun)
    else
      PrintText(VRun, pOptions.Write);
    Result := EXIT_OK;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'repo ', pSub, ': ', E.Message);
      Result := ExitCodeOf(E);
    end;
  end;
end;

function RunRepoDfmWriteVerb(const pSub, pPath: string; pJson: Boolean): Integer;
var
  VOptions: TRunOptions;
  VError: string;
begin
  VOptions := ReadOptions(pJson, VError);
  if VError = '' then
    Exit(RunOptionsOnRepo(pSub, pPath, VOptions));
  Writeln(ErrOutput, 'repo ', pSub, ': ', VError);
  Result := EXIT_USAGE;
end;

end.
