unit DRagLint.FieldRepo.AlterReport;

{ drag-lint 1.54 -- lane TT-ALTER: text and JSON of a per-table ALTER plan and its outcome. The text starts with the
  shared change-set rendering (DRagLint.FieldRepo.ChangeSet), so `--select` ids read the same everywhere. }

interface

uses
  System.JSON,
  DRagLint.FieldRepo.Alter,
  DRagLint.FieldRepo.AlterApply;  // dl:ok uses-global-census@95f9 -- REVIEWED 2026-11-24 INT-W2: the report prints the state names the apply step defines

const
  /// <summary>Starts the line of a report (and of a --select file) that holds the plan hash.</summary>
  PLAN_PREFIX = 'plan ';

type
  /// <summary>The backup an apply made before its first write.</summary>
  TFrAlterBackup = record
    /// <summary>'' = no backup was made.</summary>
    FileName: string;
    Size: Int64;
    /// <summary>'full' or 'quick'.</summary>
    Verified: string;
    /// <summary>Tables and views compared, rows of the altered table compared (-1 = not compared).</summary>
    Tables: Integer;
    Rows: Int64;
    /// <summary>All recorded backups that are still on disk.</summary>
    TotalFiles: Integer;
    TotalSize: Int64;
    /// <summary>A temporary database that could not be removed; '' = none.</summary>
    Leftover: string;
    /// <summary>The server host when the backup is on another machine's disk (FileName is then a path there); '' = this machine.</summary>
    Host: string;
  end;

  /// <summary>What the report says beside the plan.</summary>
  TFrAlterReport = record
    Plan: TFrAlterPlan;
    HookName: string;
    RepoPath: string;
    SchemaReadAtUtc: string;
    SchemaDatabase: string;
    /// <summary>True when nothing was written.</summary>
    DryRun: Boolean;
    /// <summary>Set when an apply ran.</summary>
    HasOutcome: Boolean;
    Outcome: TFrAlterOutcome;
    Backup: TFrAlterBackup;
  end;

/// <summary>Renders a backup as text lines.</summary>
/// <param name="pBackup">The backup.</param>
/// <returns>The file with size and verification, then the total of all recorded backups.</returns>
function RenderBackupText(const pBackup: TFrAlterBackup): TArray<string>;

/// <summary>Renders a backup as a JSON object.</summary>
/// <param name="pBackup">The backup.</param>
/// <returns>file, size, verified, tables, rows, leftover, host ('' = this machine), total_files, total_size; the caller frees it.</returns>
function BackupToJson(const pBackup: TFrAlterBackup): TJSONObject;

/// <summary>Renders a report as text lines.</summary>
/// <param name="pReport">The report.</param>
/// <returns>The change set, per change its statements / pre-checks / notes, then the outcome.</returns>
function RenderAlterText(const pReport: TFrAlterReport): TArray<string>;

/// <summary>Renders a report as one JSON object.</summary>
/// <param name="pReport">The report.</param>
/// <returns>direction, table, database, dialect, hook, repository, dry_run, count, blocked, changes[id, op, kind,
/// target, prop, old, new, checked, blocked, depends_on[], ddl[], safe{}, prechecks[], notes[], dependents[]], hook_before[],
/// hook_after[], notes[], plan_hash, backup{file, host, size, verified, tables, rows, leftover, total_files, total_size}, outcome{success, groups[], problems[], not_applied[]}. plan_hash is what a --select
/// file names in its "plan" line.</returns>
function RenderAlterJson(const pReport: TFrAlterReport): string;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.FieldRepo.ChangeSet;

const
  KIND_NAMES: array[TFrAlterKind] of string = ('create-domain', 'rename', 'type', 'nullability', 'add', 'drop', 'safe-type', 'order');
  INDENT = '    ';

function RenderBackupText(const pBackup: TFrAlterBackup): TArray<string>;
var
  VCompared: string;
begin
  VCompared := if pBackup.Tables > 0 then Format(': %d table(s) and view(s) compared', [pBackup.Tables]) else '';
  if pBackup.Rows >= 0 then
    VCompared := VCompared + Format(', %d row(s)', [pBackup.Rows]);
  Result := [Format('backup: %s (%d bytes, %s%s)', [pBackup.FileName, pBackup.Size, if pBackup.Verified.Contains('not verified') then 'NOT verified: ' + pBackup.Verified else 'verified ' + pBackup.Verified, VCompared]),
    Format('backups on disk: %d file(s), %d bytes in total (repo backup purge --keep N)', [pBackup.TotalFiles, pBackup.TotalSize])];
  if pBackup.Host <> '' then
    Result := Result + [Format('server: %s -- the backup file is on the server''s disk (path above), not on this machine; its space was not checked, it was not restore-tested, and purge never deletes it', [pBackup.Host])];
  if pBackup.Leftover <> '' then
    Result := Result + ['the temporary database of the verification could not be removed: ' + pBackup.Leftover];
end;

function BackupToJson(const pBackup: TFrAlterBackup): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', pBackup.FileName);
  Result.AddPair('size', TJSONNumber.Create(pBackup.Size));
  Result.AddPair('verified', pBackup.Verified);
  Result.AddPair('tables', TJSONNumber.Create(pBackup.Tables));
  Result.AddPair('rows', TJSONNumber.Create(pBackup.Rows));
  Result.AddPair('leftover', pBackup.Leftover);
  Result.AddPair('host', pBackup.Host);
  Result.AddPair('total_files', TJSONNumber.Create(pBackup.TotalFiles));
  Result.AddPair('total_size', TJSONNumber.Create(pBackup.TotalSize));
end;

function JsonStrings(const pItems: TArray<string>): TJSONArray;
var
  VItem: string;
begin
  Result := TJSONArray.Create;
  for VItem in pItems do
    Result.Add(VItem);
end;

function JsonInts(const pItems: TArray<Integer>): TJSONArray;
var
  VItem: Integer;
begin
  Result := TJSONArray.Create;
  for VItem in pItems do
    Result.Add(VItem);
end;

function JsonPrechecks(const pItems: TArray<TFrPrecheck>): TJSONArray;
var
  VItem: TFrPrecheck;
  VObject: TJSONObject;
begin
  Result := TJSONArray.Create;
  for VItem in pItems do
  begin
    VObject := TJSONObject.Create;
    VObject.AddPair('code', VItem.Code);
    VObject.AddPair('sql', VItem.Sql);
    VObject.AddPair('count', TJSONNumber.Create(VItem.Count));
    Result.AddElement(VObject);
  end;
end;

function JsonSafe(const pSteps: TFrSafeSteps): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('temp_column', pSteps.TempColumn);
  Result.AddPair('add', pSteps.AddSql);
  Result.AddPair('copy', pSteps.CopySql);
  Result.AddPair('verify', pSteps.MismatchSql);
  Result.AddPair('swap', JsonStrings(pSteps.SwapSql));
  Result.AddPair('cleanup', pSteps.CleanupSql);
end;

function JsonChange(const pChange: TFrAlterChange): TJSONObject;
const
  OP_NAMES: array[TFrChangeOp] of string = ('insert', 'update', 'delete');
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(pChange.Change.Id));
  Result.AddPair('op', OP_NAMES[pChange.Change.Op]);
  Result.AddPair('kind', KIND_NAMES[pChange.Kind]);
  Result.AddPair('target', pChange.Change.Target);
  Result.AddPair('prop', pChange.Change.Prop);
  Result.AddPair('old', pChange.Change.OldValue);
  Result.AddPair('new', pChange.Change.NewValue);
  Result.AddPair('checked', TJSONBool.Create(pChange.Change.Checked and (pChange.Change.Blocked = '')));
  Result.AddPair('blocked', pChange.Change.Blocked);
  Result.AddPair('depends_on', JsonInts(pChange.DependsOn));
  Result.AddPair('ddl', JsonStrings(pChange.Ddl));
  if pChange.Safe.AddSql <> '' then
    Result.AddPair('safe', JsonSafe(pChange.Safe));
  Result.AddPair('prechecks', JsonPrechecks(pChange.Prechecks));
  Result.AddPair('notes', JsonStrings(pChange.Notes));
  Result.AddPair('dependents', JsonStrings(pChange.Dependents));
end;

{ Ids of the plan that no committed group holds: not chosen, blocked, or in a group that failed or did not run. }
function NotApplied(const pReport: TFrAlterReport): TArray<Integer>;
var
  VChange: TFrAlterChange;
  VGroup: TFrGroupOutcome;
  VDone: Boolean;
begin
  Result := nil;
  for VChange in pReport.Plan.Changes do
  begin
    VDone := False;
    for VGroup in pReport.Outcome.Groups do
      VDone := VDone or ((VGroup.State = fgsCommitted) and TArray.Contains<Integer>(VGroup.ChangeIds, VChange.Change.Id));
    if not VDone then
      Result := Result + [VChange.Change.Id];
  end;
end;

function JsonOutcome(const pOutcome: TFrAlterOutcome): TJSONObject;
var
  VGroup: TFrGroupOutcome;
  VGroups: TJSONArray;
  VObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('success', TJSONBool.Create(pOutcome.Success));
  VGroups := TJSONArray.Create;
  Result.AddPair('groups', VGroups);
  for VGroup in pOutcome.Groups do
  begin
    VObject := TJSONObject.Create;
    VObject.AddPair('name', VGroup.Name);
    VObject.AddPair('state', GROUP_STATE_NAMES[VGroup.State]);
    VObject.AddPair('changes', JsonInts(VGroup.ChangeIds));
    VObject.AddPair('statements', JsonStrings(VGroup.Statements));
    VObject.AddPair('error', VGroup.Error);
    VGroups.AddElement(VObject);
  end;
  Result.AddPair('problems', JsonStrings(pOutcome.Problems));
end;

function RenderAlterJson(const pReport: TFrAlterReport): string;
var
  VRoot, VOutcome: TJSONObject;
  VList: TJSONArray;
  VChange: TFrAlterChange;
  VBlocked: Integer;
begin
  VRoot := TJSONObject.Create;
  try
    VBlocked := 0;
    VList := TJSONArray.Create;
    for VChange in pReport.Plan.Changes do
    begin
      VList.AddElement(JsonChange(VChange));
      if VChange.Change.Blocked <> '' then
        Inc(VBlocked);
    end;
    VRoot.AddPair('direction', FrDirectionName(fdRepoToDb));
    VRoot.AddPair('table', pReport.Plan.TableName);
    VRoot.AddPair('database', pReport.Plan.DatabaseName);
    VRoot.AddPair('dialect', pReport.Plan.DialectName);
    VRoot.AddPair('hook', pReport.HookName);
    VRoot.AddPair('repository', pReport.RepoPath);
    VRoot.AddPair('schema_read_at_utc', pReport.SchemaReadAtUtc);
    VRoot.AddPair('schema_database', pReport.SchemaDatabase);
    VRoot.AddPair('dry_run', TJSONBool.Create(pReport.DryRun));
    VRoot.AddPair('count', TJSONNumber.Create(Length(pReport.Plan.Changes)));
    VRoot.AddPair('blocked', TJSONNumber.Create(VBlocked));
    VRoot.AddPair('changes', VList);
    VRoot.AddPair('hook_before', JsonStrings(pReport.Plan.HookBefore));
    VRoot.AddPair('hook_after', JsonStrings(pReport.Plan.HookAfter));
    VRoot.AddPair('notes', JsonStrings(pReport.Plan.Notes));
    VRoot.AddPair('plan_hash', pReport.Plan.Hash);
    if pReport.Backup.FileName <> '' then
      VRoot.AddPair('backup', BackupToJson(pReport.Backup));
    if pReport.HasOutcome then
    begin
      VOutcome := JsonOutcome(pReport.Outcome);
      VOutcome.AddPair('not_applied', JsonInts(NotApplied(pReport)));
      VRoot.AddPair('outcome', VOutcome);
    end;
    Result := VRoot.ToJSON;
  finally
    VRoot.Free;
  end;
end;

function Prefixed(const pPrefix: string; const pItems: TArray<string>): TArray<string>;
var
  VItem: string;
begin
  Result := nil;
  for VItem in pItems do
    Result := Result + [pPrefix + VItem];
end;

function PrecheckLines(const pChange: TFrAlterChange): TArray<string>;
var
  VCheck: TFrPrecheck;
begin
  Result := nil;
  for VCheck in pChange.Prechecks do
    if VCheck.Count >= 0 then
      Result := Result + [INDENT + 'pre-check: ' + Format(VCheck.Text, [VCheck.Count])];
end;

function IdText(const pIds: TArray<Integer>): string;
var
  VId: Integer;
begin
  Result := '';
  for VId in pIds do
    Result := Result + (if Result = '' then '' else ', ') + IntToStr(VId);
end;

function OutcomeLines(const pOutcome: TFrAlterOutcome): TArray<string>;
var
  VGroup: TFrGroupOutcome;
begin
  Result := nil;
  for VGroup in pOutcome.Groups do
  begin
    Result := Result + [Format('group %s: %s', [VGroup.Name, GROUP_STATE_NAMES[VGroup.State]])];
    if VGroup.Error <> '' then
      Result := Result + [INDENT + 'error: ' + VGroup.Error];
  end;
  Result := Result + Prefixed('problem: ', pOutcome.Problems);
end;

function RenderAlterText(const pReport: TFrAlterReport): TArray<string>;
var
  VChange: TFrAlterChange;
  VLeft: TArray<Integer>;
begin
  Result := [Format('table %s, database %s (%s), hook %s', [pReport.Plan.TableName, pReport.Plan.DatabaseName,
    pReport.Plan.DialectName, pReport.HookName])] + RenderChangeSetText(pReport.Plan.ChangeSet);
  for VChange in pReport.Plan.Changes do
    if VChange.Change.Blocked = '' then
    begin
      Result := Result + [Format('[%d] statements', [VChange.Change.Id])] + Prefixed(INDENT, VChange.Ddl);
      if VChange.Safe.AddSql <> '' then
        Result := Result + Prefixed(INDENT, [VChange.Safe.AddSql, VChange.Safe.CopySql, VChange.Safe.MismatchSql] + VChange.Safe.SwapSql);
      Result := Result + PrecheckLines(VChange) + Prefixed(INDENT + 'dependent: ', VChange.Dependents) + Prefixed(INDENT + 'note: ', VChange.Notes);
    end;
  Result := Result + Prefixed('hook before: ', pReport.Plan.HookBefore) + Prefixed('hook after: ', pReport.Plan.HookAfter) +
    Prefixed('note: ', pReport.Plan.Notes) + [PLAN_PREFIX + pReport.Plan.Hash];
  if pReport.Backup.FileName <> '' then
    Result := Result + RenderBackupText(pReport.Backup);
  if pReport.HasOutcome then
  begin
    Result := Result + OutcomeLines(pReport.Outcome);
    VLeft := NotApplied(pReport);
    if Length(VLeft) > 0 then
      Result := Result + ['not applied: ' + IdText(VLeft)];
  end;
  if pReport.DryRun then
    Result := Result + ['dry run: nothing written (add --apply to write)'];
end;

end.
