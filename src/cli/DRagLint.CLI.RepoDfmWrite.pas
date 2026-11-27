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
/// gets a backup beside it. The BDE policy (project setting fieldrepo.bde) is read PER FORM: from --project, else the
/// first folder at or above the form that holds _D-RAG, else the first one at or above the repository file; no project
/// folder at all = full. The plan names the policy of every form and where it is from (text: a `bde policy` line; --json:
/// `bde`). A fieldrepo.bde value that is not one of the three strings is exit 1. With readonly or none the BDE classes
/// are the built-in names and the descendants of them found in the project's index (_D-RAG\*.sqlite, read only).</remarks>
function RunRepoDfmWriteVerb(const pSub, pPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.JSON,
  System.StrUtils,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  DRagLint.Core.Model, // dl:unit DRagLint.Core.Model accepted -- drag_home_dir names the _D-RAG folder the project indexes live in; the model unit owns that name
  DRagLint.Core.Interfaces,
  DRagLint.CLI.Common,
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DfmReadPlan,
  DRagLint.FieldRepo.DfmReadSelection,
  DRagLint.FieldRepo.DfmWrite,
  DRagLint.FieldRepo.DfmWritePlan,
  DRagLint.Project.Settings;

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;
  EXIT_USAGE = 2;
  SUB_WRITE_DFM = 'write-dfm';
  PLAN_MARK = '# plan ';
  BDE_KEY = 'fieldrepo.bde';
  BDE_POLICY_TEXT: array[TDfmwBdePolicy] of string = ('full', 'readonly', 'none');
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

  { The BDE policy of one form and where it is from. }
  TBdeFilePolicy = record
    DfmName: string;
    Anchor: string;
    Policy: TDfmwBdePolicy;
    Source: string;
  end;

  { What a run did. }
  TRunResult = record
    Bde: TArray<TBdeFilePolicy>;
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
  VBde: TBdeFilePolicy;
begin
  for VBde in pRun.Bde do
    Writeln('bde policy ', BDE_POLICY_TEXT[VBde.Policy], ' for ', ExtractFileName(VBde.DfmName), ': ', VBde.Source);
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

function BdeJson(const pRun: TRunResult): TJSONArray;
var
  VBde: TBdeFilePolicy;
  VItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for VBde in pRun.Bde do
  begin
    VItem := TJSONObject.Create;
    Result.AddElement(VItem);
    VItem.AddPair('dfm', VBde.DfmName);
    VItem.AddPair('policy', BDE_POLICY_TEXT[VBde.Policy]);
    VItem.AddPair('source', VBde.Source);
  end;
end;

procedure PrintJson(const pRun: TRunResult);
var
  VRoot: TJSONObject;
begin
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair('bde', BdeJson(pRun));
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

{ A lookup of the policy by the full path of a form; a form that is not listed is closed (dbpNone), never open. }
function PolicyLookup(const pPolicies: TArray<TPair<string, TDfmwBdePolicy>>): TFunc<string, TDfmwBdePolicy>;
begin
  Result :=
    function(pFile: string): TDfmwBdePolicy
    var
      VPair: TPair<string, TDfmwBdePolicy>;
    begin
      Result := dbpNone;
      for VPair in pPolicies do
        if VPair.Key = AnsiLowerCase(TPath.GetFullPath(pFile)) then
          Exit(VPair.Value);
    end;
end;

{ The fieldrepo.bde of a settings file as a policy. A value that is not a JSON string is refused: read as '' it would
  mean full, the policy that closes nothing. }
function SettingPolicy(const pValue: TSettingValue; const pAnchor: string): TDfmwBdePolicy;
var
  VJson: TJSONValue;
begin
  VJson := TJSONObject.ParseJSONValue(pValue.ValueJson);
  try
    if (VJson is not TJSONString) or (VJson is TJSONNumber) or (VJson is TJSONBool) or (Trim(TJSONString(VJson).Value) = '') then
      raise EDfmWriteError.CreateFmt('project setting %s of %s: %s is not "full", "readonly" or "none" (a string)',
        [BDE_KEY, pAnchor, pValue.ValueJson]);
    Result := BdePolicyOf(TJSONString(VJson).Value);
  finally
    VJson.Free;
  end;
end;

{ The project folders that can hold the setting of a form, in order: --project, the first folder at or above the form
  that holds _D-RAG, the first one at or above the repository file. A drive root is no project folder (a stray C:\_D-RAG
  would make every form of the drive part of one "project", and TProjectSettings reads a bare `C:` as the current folder). }
function PolicyAnchors(const pFile, pRepoPath: string): TArray<string>;
const
  DRIVE_ROOT_LENGTH = 3;
var
  VAnchor: string;
begin
  Result := nil;
  for VAnchor in [TProjectSettings.ResolveAnchor(CommandLineValue('--project'), '', '', ''), TProjectSettings.ResolveAnchor('', pFile, '', ''),
    TProjectSettings.ResolveAnchor('', pRepoPath, '', '')] do
    if (Length(VAnchor) > DRIVE_ROOT_LENGTH) and not MatchText(VAnchor, Result) then
      Result := Result + [VAnchor];
end;

{ The policy of one form: the fieldrepo.bde of the first of its project folders (PolicyAnchors) that sets it; none sets
  it, or there is no project folder = full, and the source says which of the two. }
function FileBdePolicy(const pFile, pRepoPath: string): TBdeFilePolicy;
var
  VSettings: TProjectSettings;
  VValue: TSettingValue;
  VAnchor: string;
  VAnchors: TArray<string>;
begin
  Result := Default(TBdeFilePolicy);
  Result.DfmName := TPath.GetFullPath(pFile);
  Result.Policy := dbpFull;
  VAnchors := PolicyAnchors(pFile, pRepoPath);
  Result.Source := if Length(VAnchors) = 0 then 'default: no project folder (no --project, and no ' + DRAG_HOME_DIR + ' at or above the form or the repository)'
    else 'default: no ' + BDE_KEY + ' in ' + string.Join(', ', VAnchors);
  for VAnchor in VAnchors do
  begin
    VSettings := TProjectSettings.Create(VAnchor);
    try
      VValue := VSettings.Get(BDE_KEY);
      if VValue.Source = ssDefault then
        Continue;
      Result.Anchor := VAnchor;
      Result.Policy := SettingPolicy(VValue, VAnchor);
      Result.Source := BDE_KEY + ' of ' + TPath.Combine(VAnchor, DRAG_HOME_DIR);
      Exit;
    finally
      VSettings.Free;
    end;
  end;
end;
{ The classes the index of a project folder (every _D-RAG\*.sqlite that opens read-only) knows to descend from a BDE
  dataset class; pDbs = the file names of the indexes that answered. }
function IndexedBdeClasses(const pAnchor: string; out pDbs: string): TArray<string>;
var
  VDb, VRoot: string;
  VRoots: TArray<string>;
  VStore: ISymbolStore;
  VOk: Boolean;
  VNames: TStringList;
begin
  pDbs := '';
  VRoots := BdeDatasetRoots;
  VNames := TStringList.Create(dupIgnore, True, False);
  try
    for VDb in TDirectory.GetFiles(TPath.Combine(pAnchor, DRAG_HOME_DIR), '*.sqlite') do
    begin
      VStore := OpenReadOnlyStore(VDb, VOk, True);
      if not VOk then
        Continue;
      pDbs := pDbs + (if pDbs = '' then '' else ', ') + ExtractFileName(VDb);
      for VRoot in VRoots do
        VNames.AddStrings(VStore.FindDescendantNames(VRoot));
      VStore := nil;
    end;
    Result := VNames.ToStringArray;
  finally
    VNames.Free;
  end;
end;

{ The rules of a run: the policy of every form, and for the projects that close BDE the classes their index adds. Each
  source says which classes count, so that a run without an index does not read as a checked one. }
function BdeRulesOf(const pOptions: TRunOptions; const pRepoPath: string; out pFiles: TArray<TBdeFilePolicy>): TDfmwBdeRules;
var
  VFile, VDbs: string;
  VOne: TBdeFilePolicy;
  VPolicies: TDictionary<string, TDfmwBdePolicy>;
  VFound: TArray<string>;
  VI: Integer;
begin
  Result := Default(TDfmwBdeRules);
  pFiles := nil;
  VPolicies := TDictionary<string, TDfmwBdePolicy>.Create;
  try
    for VFile in pOptions.Files do
    begin
      VOne := FileBdePolicy(VFile, pRepoPath);
      if VPolicies.ContainsKey(AnsiLowerCase(VOne.DfmName)) then
        Continue;
      VPolicies.Add(AnsiLowerCase(VOne.DfmName), VOne.Policy);
      pFiles := pFiles + [VOne];
    end;
    for VI := 0 to High(pFiles) do
      if pFiles[VI].Policy <> dbpFull then
      begin
        VFound := IndexedBdeClasses(pFiles[VI].Anchor, VDbs);
        Result.Classes := Result.Classes + VFound;
        pFiles[VI].Source := pFiles[VI].Source + (if VDbs = '' then '; BDE classes: by name only (no project index in ' +
          TPath.Combine(pFiles[VI].Anchor, DRAG_HOME_DIR) + ': a descendant of a BDE dataset class is not recognised)'
          else Format('; BDE classes: by name and %d descendant(s) from %s', [Length(VFound), VDbs]));
      end;
    Result.PolicyOf := PolicyLookup(VPolicies.ToArray);
  finally
    VPolicies.Free;
  end;
end;

function RunOnRepo(const pPath: string; const pOptions: TRunOptions): TRunResult;
var
  VRepo: TFDConnection;
  VChosen: TArray<TFrChange>;
  VRules: TDfmwBdeRules;
begin
  Result := Default(TRunResult);
  VRules := BdeRulesOf(pOptions, pPath, Result.Bde);
  VRepo := OpenRepository(pPath, True);
  try
    Result.Plan := PlanDfmWriteWithRules(VRepo, pOptions.Files, pOptions.Dataset, pOptions.Fields, VRules);
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
  Result.Fields := CommandLineList('--names', ',');  // dl:ok duplicate-code@0d02 -- REVIEWED 2026-11-24 INT-W2: twin of read-dfm: same flags, other plan types
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
