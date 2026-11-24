unit DRagLint.CLI.RepoAlter;

{ drag-lint 1.54 -- lane TT-ALTER: `repo alter-table` (plan 2026-11-23-fr-alter-table.md). DRagLint.CLI.Repo resolves
  the repository path and dispatches here in ONE line; the verb's own flags are read from the command line (ParseArgs
  only has to accept them). A dry run unless --apply is given. }

interface

/// <summary>Runs `repo alter-table --table T --direction repo-to-db --connection "..."`.</summary>
/// <param name="pPath">The repository file (already resolved from --repo / --project); opened read-only.</param>
/// <param name="pConnection">--connection.</param>
/// <param name="pJson">--json: one JSON object on stdout.</param>
/// <returns>0 = ok (a dry run included, and an apply with nothing to do); 1 = bad arguments, no such table, a refused or
/// failed apply (the report is still printed when groups ran).</returns>
/// <remarks>An apply first makes a verified backup of the database (DRagLint.CLI.RepoBackup: --backup-dir, --verify
/// full|quick; --project names the project whose setting gives the folder); when that fails nothing is changed.
/// DRY RUN unless --apply is on the command line; --select &lt;file&gt; only chooses, it does not write (with --apply
/// it must hold the "plan &lt;hash&gt;" line of the dry run its ids come from; another plan is refused);
/// --dry-run wins over --apply. The --connection keys are checked before anything is opened. The pre-checks run in the same call, on the same connection, before any write. A
/// password of the connection string is masked in every message. Other flags: --safe-path, --rename OLD=NEW[,..],
/// --order A,B, --hook NAME.</remarks>
function RunRepoAlterTable(const pPath, pConnection: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  FireDAC.Comp.Client,
  DRagLint.Sql.FbConnString,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DbProvider,
  DRagLint.FieldRepo.DbProviderFb,
  DRagLint.FieldRepo.Alter,
  DRagLint.FieldRepo.AlterFacts,
  DRagLint.FieldRepo.AlterApply,
  DRagLint.FieldRepo.AlterReport,  // dl:ok uses-global-census@ef16 -- REVIEWED 2026-11-24 INT-W2: PLAN_PREFIX is the plan line the report writes and --select reads
  DRagLint.FieldRepo.FbBackup,  // dl:ok uses-global-census@a247 -- REVIEWED 2026-11-24 INT-W2: FB_IDENTITY_SQL is the one query that names a database
  DRagLint.FieldRepo.SchemaHook,
  DRagLint.CLI.RepoBackup,
  DRagLint.FieldRepo.SchemaHookMicronite; // registers --hook micronite

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;

type
  { What the command line asks for. }
  TAlterArgs = record
    Table: string;
    Direction: string;
    SelectFile: string;
    Hook: string;
    Apply: Boolean;
    Options: TFrAlterOptions;
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

function ReadArgs: TAlterArgs;
var
  VName: string;
begin
  Result := Default(TAlterArgs);
  Result.Table := CommandLineValue('--table').Trim.ToUpper;
  Result.Direction := CommandLineValue('--direction');
  Result.SelectFile := CommandLineValue('--select');
  Result.Hook := CommandLineValue('--hook');
  Result.Apply := CommandLineFlag('--apply') and not CommandLineFlag('--dry-run');
  Result.Options.SafePath := CommandLineFlag('--safe-path');
  Result.Options.Renames := ParseRenames(CommandLineValue('--rename'));
  for VName in CommandLineValue('--order').Split([','], TStringSplitOptions.ExcludeEmpty) do
    Result.Options.Order := Result.Options.Order + [VName.Trim.ToUpper];
end;

{ '' = usable; else what is wrong with the arguments. }
function ArgsProblem(const pArgs: TAlterArgs; const pPath, pConnection: string): string;
begin
  Result := '';
  if (pArgs.Table = '') or pArgs.Table.Contains(',') then
    Result := 'give exactly one table: --table <T>'
  else if not SameText(pArgs.Direction, FrDirectionName(fdRepoToDb)) then
    Result := 'give the direction: --direction repo-to-db (there is no default)'
  else if pConnection = '' then
    Result := 'give --connection "Database=...;User=...;Password=..."'
  else if not TFile.Exists(pPath) then
    Result := 'the repository does not exist: ' + pPath
  else if (pArgs.SelectFile <> '') and not TFile.Exists(pArgs.SelectFile) then
    Result := 'the --select file does not exist: ' + pArgs.SelectFile
  else
    Result := BackupArgsProblem;
end;

function ReadRepository(const pPath, pTable: string): TFrRepoTable;
var
  VRepo: TFDConnection;
begin
  VRepo := OpenRepository(pPath, True);
  try
    Result := ReadRepoTable(VRepo, pTable);
  finally
    VRepo.Free;
  end;
end;

{ Ids are positions in one plan: a file written for another one could name a drop instead of an add. So the file says
  which plan it means. Returns the remaining lines. }
function SelectLines(const pPlan: TFrAlterPlan; const pSelectFile: string; pApply: Boolean): TArray<string>;
var
  VLine, VPlan: string;
begin
  Result := nil;
  VPlan := '';
  for VLine in TFile.ReadAllLines(pSelectFile) do
    if VLine.TrimLeft.StartsWith(PLAN_PREFIX, True) then
      VPlan := Trim(Copy(VLine.TrimLeft, Length(PLAN_PREFIX) + 1, MaxInt))
    else
      Result := Result + [VLine];
  if pApply and (VPlan = '') then
    raise EFrAlterRefused.Create('the --select file needs the line "plan <hash>" the dry run printed: nothing applied');
  if (VPlan <> '') and not SameText(VPlan, pPlan.Hash) then
    raise EFrAlterRefused.Create('the plan changed since the --select file was written: nothing applied, make a new dry run');
end;

function ChosenIds(const pPlan: TFrAlterPlan; const pSelectFile: string; pApply: Boolean): TArray<Integer>;
var
  VChange: TFrChange;
begin
  if pSelectFile <> '' then
    Exit(SelectAlterIds(pPlan, SelectLines(pPlan, pSelectFile, pApply)));
  Result := nil;
  for VChange in pPlan.ChangeSet.Changes do
    if VChange.Checked and (VChange.Blocked = '') then
      Result := Result + [VChange.Id];
end;

procedure PrintReport(const pReport: TFrAlterReport; pJson: Boolean);
var
  VLine: string;
begin
  if pJson then
    Writeln(RenderAlterJson(pReport))
  else
    for VLine in RenderAlterText(pReport) do
      Writeln(VLine);
end;

procedure ScrubOutcome(var pOutcome: TFrAlterOutcome; const pConnection: string);
var
  VI: Integer;
begin
  for VI := 0 to High(pOutcome.Groups) do
    pOutcome.Groups[VI].Error := ScrubSecrets(pOutcome.Groups[VI].Error, pConnection);
  for VI := 0 to High(pOutcome.Problems) do
    pOutcome.Problems[VI] := ScrubSecrets(pOutcome.Problems[VI], pConnection);
end;

function AlterTable(const pArgs: TAlterArgs; const pPath, pConnection: string; pJson: Boolean): Integer;
var
  VRepo: TFrRepoTable;
  VProvider: IFrDbProvider;
  VHook: IFrSchemaHook;
  VTicket: TFrPrecheckTicket;
  VReport: TFrAlterReport;
  VIds: TArray<Integer>;
  VLine: string;
begin
  Result := EXIT_OK;
  VReport := Default(TFrAlterReport);
  VHook := SchemaHook(pArgs.Hook);
  VRepo := ReadRepository(pPath, pArgs.Table);
  VProvider := OpenFirebirdProvider(pConnection);
  VReport.Plan := PlanAlter(VRepo, VProvider.ReadTable(pArgs.Table), pArgs.Options, VProvider.Dialect);
  VReport.Plan.DatabaseName := VProvider.DatabaseName;
  VReport.HookName := VHook.Name;
  VReport.RepoPath := pPath;
  VReport.SchemaReadAtUtc := VRepo.SchemaReadAtUtc;
  VReport.SchemaDatabase := VRepo.SchemaDatabase;
  VReport.DryRun := not pArgs.Apply;
  ApplySchemaHook(VHook, VProvider.Dialect, VReport.Plan);
  VTicket := RunPrechecks(VProvider, VReport.Plan);
  if not SameText(VRepo.SchemaDatabase, VReport.Plan.DatabaseName) then
    VReport.Plan.Notes := VReport.Plan.Notes + [Format('the repository schema was read from another database: %s', [VRepo.SchemaDatabase])];
  { the selection is resolved in a dry run too: a bad --select file must not wait for --apply to be found }
  VIds := ChosenIds(VReport.Plan, pArgs.SelectFile, pArgs.Apply);
  if pArgs.Apply then
  begin
    try
      VReport.Outcome := ApplyAlterPlan(VProvider, VReport.Plan, VTicket, VIds,
        procedure
        begin
          VReport.Backup := BackupBeforeApply(pConnection, pArgs.Table, VProvider.ReadScalar(FB_IDENTITY_SQL));
        end);
    except
      { refused after the backup was made (the table changed meanwhile): there is no report, the file is named here }
      if VReport.Backup.FileName <> '' then
        for VLine in RenderBackupText(VReport.Backup) do
          Writeln(ErrOutput, VLine);
      raise;
    end;
    ScrubOutcome(VReport.Outcome, pConnection);
    VReport.HasOutcome := True;
    Result := if VReport.Outcome.Success then EXIT_OK else EXIT_FAIL;
  end;
  PrintReport(VReport, pJson);
end;

function RunRepoAlterTable(const pPath, pConnection: string; pJson: Boolean): Integer;
var
  VArgs: TAlterArgs;
  VProblem: string;
begin
  Result := EXIT_FAIL;
  try
    VArgs := ReadArgs;
    VProblem := ArgsProblem(VArgs, pPath, pConnection);
    if VProblem <> '' then
      Writeln(ErrOutput, 'repo alter-table: ', VProblem)
    else
    begin
      RequireFbConnectionSafe(pConnection);
      if VArgs.Apply then
        RequireLocalFbServer(pConnection); // a backup is not possible: found before anything is opened
      Result := AlterTable(VArgs, pPath, pConnection, pJson);
    end;
  except
    on E: Exception do
      Writeln(ErrOutput, 'repo alter-table: ', ScrubSecrets(E.Message, pConnection));
  end;
end;

end.
