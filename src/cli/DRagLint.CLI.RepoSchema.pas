unit DRagLint.CLI.RepoSchema;

{ drag-lint 1.53 -- lane FR-SCHEMA: `repo seed-fb` and `repo refresh-schema` as a change-set producer
  (design 2026-11-22-field-repository-v2-design.md sections 3 and 5). DRagLint.CLI.Repo resolves the repository
  path and dispatches here in ONE line; the flags (--apply, --select, --ddl, --json) are read from the command line
  (ParseArgs only has to accept them). Firebird is only READ. }

interface

/// <summary>True for the sub-verbs this unit runs: seed-fb, refresh-schema.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>True when RunRepoSchemaVerb handles it.</returns>
function IsRepoSchemaSub(const pSub: string): Boolean;

/// <summary>Runs `repo seed-fb` or `repo refresh-schema`: reads the schema, prints the change set, writes on request.</summary>
/// <param name="pSub">seed-fb or refresh-schema.</param>
/// <param name="pPath">The repository file (already resolved from --repo / --project).</param>
/// <param name="pConnection">--connection (live Firebird, read only); '' when --ddl is used.</param>
/// <param name="pJson">--json: print the change set as JSON instead of text.</param>
/// <returns>0 = ok (a dry run included); 1 = no source, both sources, a missing repository, a failed read or apply.</returns>
/// <exception cref="ERepoError">Not raised: every failure is printed on stderr and returned as 1.</exception>
/// <remarks>The default is a DRY RUN: the change set is printed and no byte of the repository changes. `--apply`
/// writes the checked changes; `--select &lt;file&gt;` writes exactly the ids the file names (it replaces the default
/// checks, so it is how a vanished row is deleted). A connection string's password never reaches the output, not even
/// inside a driver error message. seed-fb on a missing repository creates it, but only when a write is requested.</remarks>
function RunRepoSchemaVerb(const pSub, pPath, pConnection: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.DateUtils,
  System.TimeSpan,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.SchemaSeed,
  DRagLint.FieldRepo.FbSchemaRead,
  DRagLint.FieldRepo.FbDdl,
  DRagLint.FieldRepo.FbImport;

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;
  SUB_SEED = 'seed-fb';
  SUB_REFRESH = 'refresh-schema';
  MASK = '***';
  SECRET_KEYS: array[0..1] of string = ('Password', 'Pwd');

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

function IsRepoSchemaSub(const pSub: string): Boolean;
begin
  Result := MatchText(pSub, [SUB_SEED, SUB_REFRESH]);
end;

{ Every password value of the connection string, replaced by MASK in pText. }
function ScrubSecrets(const pText, pConnection: string): string;
var
  VPair, VKey, VValue: string;
  VEq: Integer;
begin
  Result := pText;
  for VPair in pConnection.Split([';'], TStringSplitOptions.ExcludeEmpty) do
  begin
    VEq := Pos('=', VPair);
    if VEq <= 1 then
      Continue;
    VKey := Trim(Copy(VPair, 1, VEq - 1));
    VValue := Trim(Copy(VPair, VEq + 1, MaxInt));
    if (VValue <> '') and MatchText(VKey, SECRET_KEYS) then
      Result := StringReplace(Result, VValue, MASK, [rfReplaceAll, rfIgnoreCase]);
  end;
end;

{ The schema from --ddl or --connection; pWarnings gets the DDL statements the subset parser did not know. }
function ReadModel(const pConnection, pDdl: string; out pWarnings: TArray<string>): TFbSchemaModel;
var
  VDdl: TFbDdlResult;
  VUnknown: TFbDdlUnknown;
  VFb: TFDConnection;
  VSources: TFbSchemaSources;
  VDatabase: string;
begin
  pWarnings := nil;
  if pDdl <> '' then
  begin
    VDdl := ReadDdlFiles(pDdl.Split([';'], TStringSplitOptions.ExcludeEmpty));
    for VUnknown in VDdl.Unknown do
      pWarnings := pWarnings + [Format('unknown statement %s(%d): %s', [VUnknown.FileName, VUnknown.Line, VUnknown.Text])];
    Exit(VDdl.Model);
  end;
  VFb := OpenSourceConnection(pConnection, VDatabase);
  try
    VSources := OpenFbSchemaSources(VFb);
    try
      Result := ReadSchemaModel(VSources, 'live', DatabaseOfConnection(pConnection));
    finally
      FreeFbSchemaSources(VSources);
    end;
  finally
    VFb.Free;
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

procedure PrintApplied(const pRes: TSchemaApplyResult; pSeed: Boolean);
var
  VLine: string;
begin
  for VLine in pRes.Log do
    Writeln(VLine);
  Writeln('applied: ', pRes.Applied, ' changes', IfThen(pSeed, ' (seed)', ''));
  Writeln('datasets inserted: ', pRes.DatasetsInserted, ', updated: ', pRes.DatasetsUpdated,
    ', skipped: ', pRes.DatasetsSkipped);
  for VLine in pRes.Warnings do
    Writeln('warning: ', VLine);
end;

function SyncOnRepo(const pSub, pPath: string; const pModel: TFbSchemaModel; pWrite, pJson: Boolean;
  const pSelectFile: string; const pWarnings: TArray<string>): Integer;
var
  VRepo: TFDConnection;
  VMode: TSchemaSeedMode;
  VSet: TFrChangeSet;
  VWarn: TArray<string>;
  VChosen: TArray<TFrChange>;
  VRes: TSchemaApplyResult;
  VLine: string;
begin
  VMode := if SameText(pSub, SUB_SEED) then ssmSeed else ssmRefresh;
  if (not TFile.Exists(pPath)) and (not pWrite) then
  begin
    Writeln(ErrOutput, 'repo ', pSub, ': the repository does not exist (run repo init first): ', pPath);
    Exit(EXIT_FAIL);
  end;
  if (VMode = ssmRefresh) and (not TFile.Exists(pPath)) then
  begin
    Writeln(ErrOutput, 'repo ', pSub, ': the repository does not exist: ', pPath);
    Exit(EXIT_FAIL);
  end;
  if not TFile.Exists(pPath) then
    CreateRepository(pPath);
  VRepo := OpenRepository(pPath, not pWrite);
  try
    VSet := PlanSchemaChanges(VRepo, pModel, VMode, VWarn);
    if pJson then
      Writeln(RenderChangeSetJson(VSet))
    else
      for VLine in RenderChangeSetText(VSet) do
        Writeln(VLine);
    for VLine in pWarnings + VWarn do
      Writeln('warning: ', VLine);
    if not pWrite then
    begin
      Writeln('dry run: nothing written (add --apply, or --select <file>, to write)');
      Exit(EXIT_OK);
    end;
    VChosen := ChosenChanges(VSet, pSelectFile);
    VRes := ApplySchemaChanges(VRepo, pModel, VMode, VChosen, TTimeZone.Local.ToUniversalTime(Now));
    if (VMode = ssmSeed) and (pModel.Source = 'live') then
      SetRepoMeta(VRepo, 'source_database', pModel.Database);
    PrintApplied(VRes, VMode = ssmSeed);
  finally
    VRepo.Free;
  end;
  Result := EXIT_OK;
end;

function RunRepoSchemaVerb(const pSub, pPath, pConnection: string; pJson: Boolean): Integer;
var
  VDdl, VSelect: string;
  VModel: TFbSchemaModel;
  VWarnings: TArray<string>;
begin
  VDdl := CommandLineValue('--ddl');
  VSelect := CommandLineValue('--select');
  if (pConnection = '') = (VDdl = '') then
  begin
    Writeln(ErrOutput, 'repo ', pSub, ': give exactly one source: --connection "Database=...;User=...;Password=..." or --ddl <file.sql>[;...]');
    Exit(EXIT_FAIL);
  end;
  if (VSelect <> '') and (not TFile.Exists(VSelect)) then
  begin
    Writeln(ErrOutput, 'repo ', pSub, ': the --select file does not exist: ', VSelect);
    Exit(EXIT_FAIL);
  end;
  try
    VModel := ReadModel(pConnection, VDdl, VWarnings);
    Result := SyncOnRepo(pSub, pPath, VModel, (CommandLineFlag('--apply') or (VSelect <> '')) and not CommandLineFlag('--dry-run'), pJson, VSelect, VWarnings);
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'repo ', pSub, ': ', ScrubSecrets(E.Message, pConnection));
      Result := EXIT_FAIL;
    end;
  end;
end;

end.
