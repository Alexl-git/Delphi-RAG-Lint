unit DRagLint.CLI.RepoHandlers;

{ drag-lint 1.54 -- lane TT-HANDLERS: `repo gen-handlers`, `repo gen-maxlen` and `repo renumber-regions` (design
  2026-11-22-field-repository-v2-design.md section 9). DRagLint.CLI.Repo resolves the repository path and dispatches here
  in ONE line; the flags are read from the command line (ParseArgs only has to accept them). Nothing is written without
  --apply; every unit is written as a whole or not at all. }

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
/// <returns>0 = ok; 1 = failure, or at least one region / unit refused (hand-edited, not ASCII, ...); 2 = usage error.</returns>
/// <remarks>A refused region does not stop the others. --dry-run wins over --apply.</remarks>
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
  NEW_REGION_LINE = '{$REGION ''DLFR 2''}';
  NOT_READ_YET = 'repo update-orm of this build does not read DLFR regions: renumbering would make it skip the units. Nothing written';
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

function PlanForms(pRepo: TFDConnection; const pOptions: TRunOptions): TPlans;
var
  VFile: string;
begin
  Result := nil;
  for VFile in pOptions.Files do
    try
      Result := Result + [PlanHandlers(pRepo, ExpandFileName(VFile), pOptions.Dataset)];
    except
      on E: EDlfrError do
        Result := Result + [RefusedPlan(ChangeFileExt(ExpandFileName(VFile), PAS_EXT), E.Message)];
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

{ Interface units of the tables. A table without a unit is planned only when it was named. }
function PlanLengths(pRepo: TFDConnection; const pOptions: TRunOptions): TPlans;
var
  VTable, VFile: string;
begin
  if not HasSchema(pRepo) then
    raise ERepoError.Create('the repository has no schema facts (run repo refresh-schema first)');
  Result := nil;
  for VTable in if Length(pOptions.Tables) > 0 then pOptions.Tables else RepositoryTables(pRepo) do
  begin
    VFile := TPath.Combine(pOptions.CodeDir, 'i' + VTable.Replace('$', '_') + PAS_EXT);
    if TFile.Exists(VFile) or (Length(pOptions.Tables) > 0) then
      try
        Result := Result + [PlanMaxLen(pRepo, VFile, VTable.ToUpper)];
      except
        on E: EDlfrError do
          Result := Result + [RefusedPlan(VFile, E.Message)];
      end;
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
  Result.NewText := VNew.NewText;
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
  for VFile in if pOptions.CodeDir = '' then pOptions.Files else TDirectory.GetFiles(pOptions.CodeDir, PAS_MASK) do
    if ContainsText(TEncoding.ANSI.GetString(TFile.ReadAllBytes(VFile)), DB_RAD) then
    begin
      try
        VPlan := PlanRenumber(ExpandFileName(VFile));
      except
        on E: EDlfrError do
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

procedure PrintJson(const pPlans: TPlans; pWritten: Integer);
var
  VRoot, VUnit: TJSONObject;
  VUnits, VItems: TJSONArray;
  VPlan: TFrhPlan;
  VItem: TFrhItem;
begin
  VRoot := TJSONObject.Create;
  try
    VUnits := TJSONArray.Create;
    VRoot.AddPair('units', VUnits);
    for VPlan in pPlans do
    begin
      VUnit := TJSONObject.Create;
      VUnits.AddElement(VUnit);
      VUnit.AddPair('file', VPlan.FileName);
      VUnit.AddPair('changed', TJSONBool.Create(VPlan.OldText <> VPlan.NewText));
      VItems := TJSONArray.Create;
      VUnit.AddPair('regions', VItems);
      for VItem in VPlan.Items do
        VItems.AddElement(ItemJson(VItem));
    end;
    VRoot.AddPair('refused', TJSONNumber.Create(CountState(pPlans, fhsRefused)));
    VRoot.AddPair('written', TJSONNumber.Create(pWritten));
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

function WritePlans(const pPlans: TPlans): Integer;
var
  VPlan: TFrhPlan;
begin
  Result := 0;
  for VPlan in pPlans do
    if SaveAsciiUnit(VPlan.FileName, VPlan.OldText, VPlan.NewText) then
      Inc(Result);
end;

{ True when renumbering would leave units update-orm no longer reads. }
function WouldStrand(const pSub: string; const pPlans: TPlans): Boolean;
var
  VId: string;
begin
  Result := SameText(pSub, SUB_RENUMBER) and (ChangedUnits(pPlans) > 0) and not IsOrmRegionStart(NEW_REGION_LINE, VId);
end;

function RunSub(const pSub, pPath: string; const pOptions: TRunOptions): Integer;
var
  VPlans: TPlans;
  VWritten: Integer;
  VStrand: Boolean;
begin
  VPlans := MakePlans(pSub, pPath, pOptions);
  VStrand := WouldStrand(pSub, VPlans);
  VWritten := if pOptions.Write and not VStrand then WritePlans(VPlans) else 0;
  if pOptions.Json then
    PrintJson(VPlans, VWritten)
  else
  begin
    PrintText(VPlans);
    Writeln(if pOptions.Write then Format('written: %d units', [VWritten]) else DRY_RUN_LINE);
  end;
  if VStrand then
    Writeln(ErrOutput, 'repo ', pSub, ': ', NOT_READ_YET);
  Result := if (CountState(VPlans, fhsRefused) > 0) or (VStrand and pOptions.Write) then EXIT_FAIL else EXIT_OK;
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
