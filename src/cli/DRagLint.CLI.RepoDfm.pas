unit DRagLint.CLI.RepoDfm;

{ drag-lint 1.54 -- lane TT-DFMREAD: `repo read-dfm`, the DFM -> field repository change set (design
  2026-11-22-field-repository-v2-design.md sections 3 and 9). DRagLint.CLI.Repo resolves the repository path and
  dispatches here in ONE line; the flags are read from the command line (ParseArgs only has to accept them). The DFMs
  and their units are only READ. }

interface

/// <summary>True for the sub-verb this unit runs: read-dfm.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>True when RunRepoDfmVerb handles it.</returns>
function IsRepoDfmSub(const pSub: string): Boolean;

/// <summary>Runs `repo read-dfm --dfm FILE[;...] [--dataset NAME] --direction dfm-to-repo [--apply | --select FILE]`.</summary>
/// <param name="pPath">The repository file (already resolved from --repo / --project).</param>
/// <param name="pJson">--json: one JSON object (datasets, totals, changeSet, warnings, applied) instead of text.</param>
/// <returns>0 = ok (a dry run included); 1 = a missing repository, a failed read or apply; 2 = a usage error: no --dfm,
/// --direction missing or not dfm-to-repo, a bad --select file (nothing is applied).</returns>
/// <remarks>The default is a DRY RUN: no byte of the repository changes. --apply writes the checked changes, --select
/// exactly the ids its file names; --dry-run wins over both.</remarks>
function RunRepoDfmVerb(const pPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DfmRead,
  DRagLint.FieldRepo.DfmReadPlan;

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;
  EXIT_USAGE = 2;
  SUB_READ_DFM = 'read-dfm';
  DRY_RUN_LINE = 'dry run: nothing written (add --apply, or --select <file>, to write)';

type
  TRunOptions = record
    Files: TArray<string>;
    Dataset: string;
    SelectFile: string;
    Write: Boolean;
    Json: Boolean;
  end;

  TTotals = record
    Unresolved: Integer;
    Unattributed: Integer;
    BodyOk: Integer;
    BodyBlocked: Integer;
    BodyNone: Integer;
    Counts: TDfmrKindCounts;
    procedure Add(const pReport: TDfmrDatasetReport);
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

function IsRepoDfmSub(const pSub: string): Boolean;
begin
  Result := SameText(pSub, SUB_READ_DFM);
end;

procedure TTotals.Add(const pReport: TDfmrDatasetReport);
var
  VKind: TFrFieldKind;
begin
  if pReport.TableName = '' then
    Inc(Unresolved);
  Inc(Unattributed, Length(pReport.Unattributed));
  Inc(BodyOk, pReport.BodyOk);
  Inc(BodyBlocked, pReport.BodyBlocked);
  Inc(BodyNone, pReport.BodyNone);
  for VKind := Low(TFrFieldKind) to High(TFrFieldKind) do
    Inc(Counts[VKind], pReport.Counts[VKind]);
end;

{ `12 data, 2 calc, ...` without the graphical kind: a DFM has no such field. }
function CountsText(const pCounts: TDfmrKindCounts): string;
var
  VKind: TFrFieldKind;
begin
  Result := '';
  for VKind := frkData to frkAggregate do
    Result := Result + (if VKind = frkData then '' else ', ') + IntToStr(pCounts[VKind]) + ' ' + FrKindName(VKind);
end;

function TotalsOf(const pPlan: TDfmrPlan): TTotals;
var
  VReport: TDfmrDatasetReport;
begin
  Result := Default(TTotals);
  for VReport in pPlan.Datasets do
    Result.Add(VReport);
end;

procedure PrintText(const pPlan: TDfmrPlan);
var
  VReport: TDfmrDatasetReport;
  VTotals: TTotals;
  VLine: string;
begin
  for VReport in pPlan.Datasets do
  begin
    Writeln('dataset ', VReport.DfmName, ' ', VReport.Dataset, ' (', VReport.DatasetClass, ') -> ',
      if VReport.TableName = '' then 'UNRESOLVED (' + VReport.Unresolved + ')' else VReport.TableName, ': ',
      CountsText(VReport.Counts));
    if Length(VReport.Unattributed) > 0 then
      Writeln('  no table column: ', string.Join(', ', VReport.Unattributed));
  end;
  VTotals := TotalsOf(pPlan);
  Writeln(Format('total %d datasets, %d unresolved; %s; %d without a table column', [Length(pPlan.Datasets), VTotals.Unresolved,
    CountsText(VTotals.Counts), VTotals.Unattributed]));
  Writeln(Format('calc bodies: %d read, %d blocked, %d none', [VTotals.BodyOk, VTotals.BodyBlocked, VTotals.BodyNone]));
  for VLine in RenderChangeSetText(pPlan.ChangeSet) do
    Writeln(VLine);
  for VLine in pPlan.Warnings do
    Writeln('warning: ', VLine);
end;

function CountsJson(const pCounts: TDfmrKindCounts): TJSONObject;
var
  VKind: TFrFieldKind;
begin
  Result := TJSONObject.Create;
  for VKind := frkData to frkAggregate do
    Result.AddPair(FrKindName(VKind), TJSONNumber.Create(pCounts[VKind]));
end;

function StringsJson(const pLines: TArray<string>): TJSONArray;
var
  VLine: string;
begin
  Result := TJSONArray.Create;
  for VLine in pLines do
    Result.Add(VLine);
end;

function DatasetsJson(const pPlan: TDfmrPlan): TJSONArray;
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
    VItem.AddPair('fields', CountsJson(VReport.Counts));
    VItem.AddPair('noColumn', StringsJson(VReport.Unattributed));
  end;
end;

function TotalsJson(const pPlan: TDfmrPlan): TJSONObject;
var
  VTotals: TTotals;
begin
  VTotals := TotalsOf(pPlan);
  Result := TJSONObject.Create;
  Result.AddPair('datasets', TJSONNumber.Create(Length(pPlan.Datasets)));
  Result.AddPair('unresolved', TJSONNumber.Create(VTotals.Unresolved));
  Result.AddPair('fields', CountsJson(VTotals.Counts));
  Result.AddPair('noColumn', TJSONNumber.Create(VTotals.Unattributed));
  Result.AddPair('bodiesRead', TJSONNumber.Create(VTotals.BodyOk));
  Result.AddPair('bodiesBlocked', TJSONNumber.Create(VTotals.BodyBlocked));
  Result.AddPair('bodiesNone', TJSONNumber.Create(VTotals.BodyNone));
end;

procedure PrintJson(const pPlan: TDfmrPlan; pApplied: Integer);
var
  VRoot: TJSONObject;
begin
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair('datasets', DatasetsJson(pPlan));
    VRoot.AddPair('totals', TotalsJson(pPlan));
    VRoot.AddPair('changeSet', TJSONObject.ParseJSONValue(RenderChangeSetJson(pPlan.ChangeSet)));
    VRoot.AddPair('warnings', StringsJson(pPlan.Warnings));
    VRoot.AddPair('applied', TJSONNumber.Create(pApplied));
    Writeln(VRoot.ToJSON);
  finally
    VRoot.Free;
  end;
end;

function ChosenChanges(const pSet: TFrChangeSet; const pSelectFile: string): TArray<TFrChange>;
var
  VChange: TFrChange;
begin
  if pSelectFile <> '' then
    Exit(SelectChanges(pSet, TFile.ReadAllLines(pSelectFile)));
  Result := nil;
  for VChange in pSet.Changes do
    if VChange.Checked and (VChange.Blocked = '') then
      Result := Result + [VChange];
end;

procedure ReadOnRepo(const pPath: string; const pOptions: TRunOptions);
var
  VRepo: TFDConnection;
  VPlan: TDfmrPlan;
  VLog: TArray<string>;
  VLine: string;
begin
  VLog := nil;
  VRepo := OpenRepository(pPath, not pOptions.Write);
  try
    VPlan := PlanDfmRead(VRepo, pOptions.Files, pOptions.Dataset);
    if not pOptions.Json then
      PrintText(VPlan);
    if pOptions.Write then
      VLog := ApplyDfmRead(VRepo, VPlan, ChosenChanges(VPlan.ChangeSet, pOptions.SelectFile));
  finally
    VRepo.Free;
  end;
  if pOptions.Json then
  begin
    PrintJson(VPlan, Length(VLog));
    Exit;
  end;
  for VLine in VLog do
    Writeln(VLine);
  Writeln(if pOptions.Write then 'applied: ' + IntToStr(Length(VLog)) + ' changes' else DRY_RUN_LINE);
end;

function ReadOptions(pJson: Boolean; out pError: string): TRunOptions;
var
  VDirection: string;
begin
  pError := '';
  Result.Json := pJson;
  Result.Files := CommandLineValue('--dfm').Split([';'], TStringSplitOptions.ExcludeEmpty);
  Result.Dataset := CommandLineValue('--dataset');
  Result.SelectFile := CommandLineValue('--select');
  Result.Write := (CommandLineFlag('--apply') or (Result.SelectFile <> '')) and not CommandLineFlag('--dry-run');
  VDirection := CommandLineValue('--direction');
  if Length(Result.Files) = 0 then
    pError := 'give the form: --dfm <file.dfm>[;...]'
  else if not SameText(VDirection, FrDirectionName(fdDfmToRepo)) then
    pError := 'give --direction ' + FrDirectionName(fdDfmToRepo) + ' (there is no default direction)'
  else if (Result.SelectFile <> '') and (not TFile.Exists(Result.SelectFile)) then
    pError := 'the --select file does not exist: ' + Result.SelectFile;
end;

function RunRepoDfmVerb(const pPath: string; pJson: Boolean): Integer;
var
  VOptions: TRunOptions;
  VError: string;
begin
  VOptions := ReadOptions(pJson, VError);
  Result := EXIT_USAGE;
  if VError = '' then
    try
      if TFile.Exists(pPath) then
        ReadOnRepo(pPath, VOptions)
      else
        VError := 'the repository does not exist (run repo init first): ' + pPath;
      Result := if VError = '' then EXIT_OK else EXIT_FAIL;
    except
      on E: Exception do
      begin
        VError := E.Message;
        Result := if E is EFrChangeSetError then EXIT_USAGE else EXIT_FAIL;
      end;
    end;
  if VError <> '' then
    Writeln(ErrOutput, 'repo ', SUB_READ_DFM, ': ', VError);
end;

end.
