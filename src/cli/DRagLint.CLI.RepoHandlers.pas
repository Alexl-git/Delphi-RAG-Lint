unit DRagLint.CLI.RepoHandlers;

{ drag-lint 1.54 -- lane TT-HANDLERS: `repo gen-handlers`, `repo gen-maxlen` and `repo renumber-regions` (design
  2026-11-22-field-repository-v2-design.md section 9). DRagLint.CLI.Repo resolves the repository path and dispatches here
  in ONE line; the flags are read from the command line (ParseArgs only has to accept them). Nothing is written without
  --apply; every unit is planned once, and written as a whole or not at all. A unit that cannot be written stops no other
  one and is reported like the ones that were. }

interface

const
  /// <summary>This unit's part of the `repo` sub-verb list in the "use one of" message.</summary>
  /// <remarks>Starts with ', ' (', name').</remarks>
  REPO_HANDLERS_SUBS = ', gen-handlers, gen-maxlen, renumber-regions';

/// <summary>True for a sub-verb this unit runs: gen-handlers, gen-maxlen, renumber-regions.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>False for any other name.</returns>
function IsRepoHandlersSub(const pSub: string): Boolean;

/// <summary>Runs `repo gen-handlers --dfm FILE[;...] [--dataset NAME]`, `repo gen-maxlen --code-dir DIR [--table T,...]`
/// or `repo renumber-regions (--code-dir DIR | --in FILE[;...])`, each with [--apply] [--dry-run] [--json].</summary>
/// <param name="pSub">The sub-verb, IsRepoHandlersSub(pSub) is True.</param>
/// <param name="pPath">The repository file (already resolved from --repo / --project); renumber-regions does not read it.</param>
/// <param name="pJson">--json.</param>
/// <returns>0 = ok; 1 = failure, at least one region / unit refused (hand-edited, not ASCII, ...) or not written; 2 = usage error.</returns>
/// <remarks>A refused region or a unit that cannot be written does not stop the others. --dry-run wins over --apply.</remarks>
function RunRepoHandlersVerb(const pSub, pPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.SchemaFacts,
  DRagLint.FieldRepo.OrmGen,
  DRagLint.FieldRepo.Handlers,
  DRagLint.FieldRepo.HandlersRegions;

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;
  EXIT_USAGE = 2;
  SUB_GEN_HANDLERS = 'gen-handlers';
  SUB_GEN_MAXLEN = 'gen-maxlen';
  SUB_RENUMBER = 'renumber-regions';
  DRY_RUN_LINE = 'dry run: nothing written (add --apply to write)';
  PAS_MASK = '*.pas';
  PAS_EXT = '.pas';
  DB_RAD = 'DB-RAD';
  NOT_READ = 'repo update-orm would not read the renamed regions';
  STATE_NAMES: array[TFrhState] of string = ('unchanged', 'inserted', 'updated', 'skipped', 'REFUSED');
  SQL_TABLES = 'SELECT DISTINCT "TABLE_NAME" FROM "DL_FIELDS_INFO" ORDER BY "TABLE_NAME"';

type
  TRunOptions = record
    Files: TArray<string>;
    CodeDir: string;
    Dataset: string;
    Tables: TArray<string>;
    Write: Boolean;
    Json: Boolean;
  end;

  { Plans of one run. }
  TPlans = TArray<TFrhPlan>;

  { A plan and what became of it. }
  TOutcome = record
    Plan: TFrhPlan;
    Written: Boolean;
    Error: string; // '' or why the changed unit was not written
  end;

  { One per plan. }
  TOutcomes = TArray<TOutcome>;

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

function ListValue(const pFlag: string; pSeparator: Char): TArray<string>;
var
  VItem: string;
begin
  Result := nil;
  for VItem in CommandLineValue(pFlag).Split([pSeparator]) do
    if Trim(VItem) <> '' then
      Result := Result + [Trim(VItem)];
end;

function IsRepoHandlersSub(const pSub: string): Boolean;
begin
  Result := SameText(pSub, SUB_GEN_HANDLERS) or SameText(pSub, SUB_GEN_MAXLEN) or SameText(pSub, SUB_RENUMBER);
end;

{ ---- plans ---- }

function RefusedPlan(const pFile, pReason: string): TFrhPlan;
var
  VItem: TFrhItem;
begin
  Result := Default(TFrhPlan);
  Result.FileName := pFile;
  VItem := Default(TFrhItem);
  VItem.Target := ExtractFileName(pFile);
  VItem.State := fhsRefused;
  VItem.Reason := pReason;
  Result.Items := [VItem];
end;

{ Full paths, each file once. }
function UniqueFiles(const pFiles: TArray<string>): TArray<string>;
var
  VFile: string;
begin
  Result := nil;
  for VFile in pFiles do
    if not MatchText(ExpandFileName(VFile), Result) then
      Result := Result + [ExpandFileName(VFile)];
end;

function PlanForms(pRepo: TFDConnection; const pOptions: TRunOptions): TPlans;
var
  VFile: string;
begin
  Result := nil;
  for VFile in UniqueFiles(pOptions.Files) do
    try
      Result := Result + [PlanHandlers(pRepo, VFile, pOptions.Dataset)];
    except
      on E: ERepoError do
        raise; // says nothing about this form
      on E: Exception do
        Result := Result + [RefusedPlan(ChangeFileExt(VFile, PAS_EXT), E.Message)];
    end;
end;

function RepositoryTables(pRepo: TFDConnection): TArray<string>;
var
  VQuery: TFDQuery;
begin
  Result := nil;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_TABLES);
    while not VQuery.Eof do
    begin
      Result := Result + [VQuery.Fields[0].AsString];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function InterfaceUnit(const pOptions: TRunOptions; const pTable: string): string;
begin
  Result := TPath.Combine(pOptions.CodeDir, 'i' + pTable.ToUpper.Replace('$', '_') + PAS_EXT);
end;

{ The tables of the repository whose interface unit is that file, comma-separated (A$B and A_B share one). }
function TablesOfUnit(const pOptions: TRunOptions; const pTables: TArray<string>; const pFile: string): string;
var
  VTable: string;
begin
  Result := '';
  for VTable in pTables do
    if SameText(InterfaceUnit(pOptions, VTable), pFile) then
      Result := Result + (if Result = '' then '' else ', ') + VTable;
end;

{ Interface units of the tables. A table without a unit is planned only when it was named. }
function PlanLengths(pRepo: TFDConnection; const pOptions: TRunOptions): TPlans;
var
  VAll, VSeen: TArray<string>;
  VTable, VFile: string;
begin
  if not HasSchema(pRepo) then
    raise ERepoError.Create('the repository has no schema facts (run repo refresh-schema first)');
  Result := nil;
  VSeen := nil;
  VAll := RepositoryTables(pRepo);
  for VTable in if Length(pOptions.Tables) > 0 then pOptions.Tables else VAll do
  begin
    VFile := InterfaceUnit(pOptions, VTable);
    if MatchText(VFile, VSeen) or not (TFile.Exists(VFile) or (Length(pOptions.Tables) > 0)) then
      Continue;
    VSeen := VSeen + [VFile];
    try
      Result := Result + [if TablesOfUnit(pOptions, VAll, VFile).Contains(',') then
        RefusedPlan(VFile, 'the unit belongs to more than one table: ' + TablesOfUnit(pOptions, VAll, VFile)) else
        PlanMaxLen(pRepo, VFile, VTable.ToUpper)];
    except
      on E: Exception do
        Result := Result + [RefusedPlan(VFile, E.Message)];
    end;
  end;
end;

{ True when update-orm regenerates the same regions before and after, or refuses the unit already. }
function ReadsTheSame(const pOld, pNew: string): Boolean;
var
  VOld: string;
begin
  try
    VOld := string.Join(',', OrmRegionIds(pOld));
  except
    on E: EOrmRegionError do
      Exit(True);
  end;
  try
    Result := VOld = string.Join(',', OrmRegionIds(pNew));
  except
    on E: EOrmRegionError do
      Result := False;
  end;
end;

{ The plan of one unit; no items = the unit names no region to rename. }
function PlanRenumber(const pFile: string): TFrhPlan;
var
  VNew: TDlfrRenumber;
  VItem: TFrhItem;
begin
  Result := Default(TFrhPlan);
  Result.FileName := pFile;
  Result.OldText := LoadAsciiUnit(pFile);
  VNew := RenumberRegions(Result.OldText);
  if (VNew.Refused = '') and not ReadsTheSame(Result.OldText, VNew.NewText) then
    VNew.Refused := NOT_READ;
  Result.NewText := if VNew.Refused = '' then VNew.NewText else Result.OldText;
  VItem := Default(TFrhItem);
  VItem.Target := Format('%d regions', [VNew.Count]);
  VItem.Reason := VNew.Refused;
  VItem.Notes := VNew.Notes;
  VItem.State := if VNew.Refused <> '' then fhsRefused else if VNew.Count > 0 then fhsUpdated else fhsUnchanged;
  if (VItem.State <> fhsUnchanged) or (Length(VItem.Notes) > 0) then
    Result.Items := [VItem];
end;

function PlanUnits(const pOptions: TRunOptions): TPlans;
var
  VFile: string;
  VPlan: TFrhPlan;
begin
  Result := nil;
  for VFile in UniqueFiles(if pOptions.CodeDir = '' then pOptions.Files else TDirectory.GetFiles(pOptions.CodeDir, PAS_MASK)) do
  begin
    try
      VPlan := if ContainsText(TEncoding.ANSI.GetString(TFile.ReadAllBytes(VFile)), DB_RAD) then PlanRenumber(VFile) else Default(TFrhPlan);
    except
      on E: Exception do
        VPlan := RefusedPlan(VFile, E.Message);
    end;
    if Length(VPlan.Items) > 0 then
      Result := Result + [VPlan];
  end;
end;

{ ---- output ---- }

function CountState(const pPlans: TPlans; pState: TFrhState): Integer;
var
  VPlan: TFrhPlan;
  VItem: TFrhItem;
begin
  Result := 0;
  for VPlan in pPlans do
    for VItem in VPlan.Items do
      if VItem.State = pState then
        Inc(Result);
end;

function ChangedUnits(const pPlans: TPlans): Integer;
var
  VPlan: TFrhPlan;
begin
  Result := 0;
  for VPlan in pPlans do
    if VPlan.OldText <> VPlan.NewText then
      Inc(Result);
end;

function CountWritten(const pOutcomes: TOutcomes): Integer;
var
  VOutcome: TOutcome;
begin
  Result := 0;
  for VOutcome in pOutcomes do
    if VOutcome.Written then
      Inc(Result);
end;

function CountFailed(const pOutcomes: TOutcomes): Integer;
var
  VOutcome: TOutcome;
begin
  Result := 0;
  for VOutcome in pOutcomes do
    if VOutcome.Error <> '' then
      Inc(Result);
end;

{ The units that were and that were not written. }
procedure PrintOutcomes(const pOutcomes: TOutcomes);
var
  VOutcome: TOutcome;
begin
  for VOutcome in pOutcomes do
    if VOutcome.Written then
      Writeln('  written ', VOutcome.Plan.FileName)
    else if VOutcome.Error <> '' then
      Writeln('  NOT WRITTEN ', VOutcome.Plan.FileName, ': ', VOutcome.Error);
  Writeln(Format('written: %d units', [CountWritten(pOutcomes)]),
    if CountFailed(pOutcomes) > 0 then Format(', NOT WRITTEN: %d units', [CountFailed(pOutcomes)]) else '');
end;

procedure PrintText(const pPlans: TPlans);
var
  VPlan: TFrhPlan;
  VItem: TFrhItem;
  VNote: string;
  VState: TFrhState;
begin
  for VPlan in pPlans do
  begin
    Writeln(VPlan.FileName);
    for VItem in VPlan.Items do
    begin
      Writeln('  ', STATE_NAMES[VItem.State], ' ', if VItem.RegionId = '' then VItem.Target else VItem.RegionId + ' (' + VItem.Target + ')',
        if VItem.Reason = '' then '' else ': ' + VItem.Reason);
      for VNote in VItem.Notes do
        Writeln('    note: ', VNote);
    end;
  end;
  Write(Format('%d units, %d to write', [Length(pPlans), ChangedUnits(pPlans)]));
  for VState := Low(TFrhState) to High(TFrhState) do
    Write(Format(', %d %s', [CountState(pPlans, VState), STATE_NAMES[VState].ToLower]));
  Writeln;
end;

function ItemJson(const pItem: TFrhItem): TJSONObject;
var
  VNotes: TJSONArray;
  VNote: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('region', pItem.RegionId);
  Result.AddPair('target', pItem.Target);
  Result.AddPair('state', STATE_NAMES[pItem.State].ToLower);
  Result.AddPair('reason', pItem.Reason);
  VNotes := TJSONArray.Create;
  Result.AddPair('notes', VNotes);
  for VNote in pItem.Notes do
    VNotes.Add(VNote);
end;

procedure PrintJson(const pOutcomes: TOutcomes; pRefused: Integer);
var
  VRoot, VUnit: TJSONObject;
  VUnits, VItems: TJSONArray;
  VOutcome: TOutcome;
  VItem: TFrhItem;
begin
  VRoot := TJSONObject.Create;
  try
    VUnits := TJSONArray.Create;
    VRoot.AddPair('units', VUnits);
    for VOutcome in pOutcomes do
    begin
      VUnit := TJSONObject.Create;
      VUnits.AddElement(VUnit);
      VUnit.AddPair('file', VOutcome.Plan.FileName);
      VUnit.AddPair('changed', TJSONBool.Create(VOutcome.Plan.OldText <> VOutcome.Plan.NewText));
      VUnit.AddPair('written', TJSONBool.Create(VOutcome.Written));
      VUnit.AddPair('error', VOutcome.Error);
      VItems := TJSONArray.Create;
      VUnit.AddPair('regions', VItems);
      for VItem in VOutcome.Plan.Items do
        VItems.AddElement(ItemJson(VItem));
    end;
    VRoot.AddPair('refused', TJSONNumber.Create(pRefused));
    VRoot.AddPair('written', TJSONNumber.Create(CountWritten(pOutcomes)));
    VRoot.AddPair('not_written', TJSONNumber.Create(CountFailed(pOutcomes)));
    Writeln(VRoot.ToJSON);
  finally
    VRoot.Free;
  end;
end;

{ ---- run ---- }

function ReadOptions(const pSub: string; pJson: Boolean; out pError: string): TRunOptions;
begin
  pError := '';
  Result := Default(TRunOptions);
  Result.Json := pJson;
  Result.Files := ListValue(if SameText(pSub, SUB_GEN_HANDLERS) then '--dfm' else '--in', ';');
  Result.CodeDir := CommandLineValue('--code-dir');
  Result.Dataset := CommandLineValue('--dataset');
  Result.Tables := ListValue('--table', ',');
  Result.Write := CommandLineFlag('--apply') and not CommandLineFlag('--dry-run');
  if SameText(pSub, SUB_GEN_HANDLERS) then
  begin
    if Length(Result.Files) = 0 then
      pError := 'give the form: --dfm <file.dfm>[;...]';
  end
  else if (Result.CodeDir = '') and (SameText(pSub, SUB_GEN_MAXLEN) or (Length(Result.Files) = 0)) then
    pError := 'give the folder of the units: --code-dir <folder>' + (if SameText(pSub, SUB_RENUMBER) then ', or --in <file.pas>[;...]' else '')
  else if (Result.CodeDir <> '') and not TDirectory.Exists(Result.CodeDir) then
    pError := 'the folder does not exist: ' + Result.CodeDir
  else if Result.CodeDir <> '' then
    Result.CodeDir := ExpandFileName(Result.CodeDir);
end;

function MakePlans(const pSub, pPath: string; const pOptions: TRunOptions): TPlans;
var
  VRepo: TFDConnection;
begin
  if SameText(pSub, SUB_RENUMBER) then
    Exit(PlanUnits(pOptions));
  if not TFile.Exists(pPath) then
    raise ERepoError.Create('the repository does not exist (run repo init first): ' + pPath);
  VRepo := OpenRepository(pPath, True);
  try
    Result := if SameText(pSub, SUB_GEN_HANDLERS) then PlanForms(VRepo, pOptions) else PlanLengths(VRepo, pOptions);
  finally
    VRepo.Free;
  end;
end;

function RunPlans(const pPlans: TPlans; pWrite: Boolean): TOutcomes;
var
  VPlan: TFrhPlan;
  VOutcome: TOutcome;
begin
  Result := nil;
  for VPlan in pPlans do
  begin
    VOutcome := Default(TOutcome);
    VOutcome.Plan := VPlan;
    try
      VOutcome.Written := pWrite and SaveAsciiUnit(VPlan.FileName, VPlan.OldText, VPlan.NewText);
    except
      on E: Exception do
        VOutcome.Error := E.Message;
    end;
    Result := Result + [VOutcome];
  end;
end;

function RunSub(const pSub, pPath: string; const pOptions: TRunOptions): Integer;
var
  VPlans: TPlans;
  VOutcomes: TOutcomes;
begin
  VPlans := MakePlans(pSub, pPath, pOptions);
  VOutcomes := RunPlans(VPlans, pOptions.Write);
  if pOptions.Json then
    PrintJson(VOutcomes, CountState(VPlans, fhsRefused))
  else
  begin
    PrintText(VPlans);
    if pOptions.Write then
      PrintOutcomes(VOutcomes)
    else
      Writeln(DRY_RUN_LINE);
  end;
  Result := if CountState(VPlans, fhsRefused) + CountFailed(VOutcomes) > 0 then EXIT_FAIL else EXIT_OK;
end;

function RunRepoHandlersVerb(const pSub, pPath: string; pJson: Boolean): Integer;
var
  VOptions: TRunOptions;
  VError: string;
begin
  VOptions := ReadOptions(pSub, pJson, VError);
  Result := EXIT_USAGE;
  if VError = '' then
    try
      Result := RunSub(pSub, pPath, VOptions);
    except
      on E: Exception do
      begin
        VError := E.Message;
        Result := EXIT_FAIL;
      end;
    end;
  if VError <> '' then
    Writeln(ErrOutput, 'repo ', pSub, ': ', VError);
end;

end.
