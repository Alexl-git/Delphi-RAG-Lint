unit DRagLint.FieldRepo.AlterReport;

{ drag-lint 1.54 -- lane TT-ALTER: text and JSON of a per-table ALTER plan and its outcome. The text starts with the
  shared change-set rendering (DRagLint.FieldRepo.ChangeSet), so `--select` ids read the same everywhere. }

interface

uses
  DRagLint.FieldRepo.Alter,
  DRagLint.FieldRepo.AlterApply;

type
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
  end;

/// <summary>Renders a report as text lines.</summary>
/// <param name="pReport">The report.</param>
/// <returns>The change set, per change its statements / pre-checks / notes, then the outcome.</returns>
function RenderAlterText(const pReport: TFrAlterReport): TArray<string>;

/// <summary>Renders a report as one JSON object.</summary>
/// <param name="pReport">The report.</param>
/// <returns>direction, table, database, dialect, hook, repository, dry_run, count, blocked, changes[id, op, kind,
/// target, prop, old, new, checked, blocked, depends_on[], ddl[], safe{}, prechecks[], notes[]], hook_before[],
/// hook_after[], notes[], outcome{success, groups[], problems[]}.</returns>
function RenderAlterJson(const pReport: TFrAlterReport): string;

implementation

uses
  System.SysUtils,
  System.JSON,
  DRagLint.FieldRepo.ChangeSet;

const
  KIND_NAMES: array[TFrAlterKind] of string = ('create-domain', 'rename', 'type', 'nullability', 'add', 'drop', 'safe-type', 'order');
  INDENT = '    ';

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
  VRoot: TJSONObject;
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
    if pReport.HasOutcome then
      VRoot.AddPair('outcome', JsonOutcome(pReport.Outcome));
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
begin
  Result := [Format('table %s, database %s (%s), hook %s', [pReport.Plan.TableName, pReport.Plan.DatabaseName,
    pReport.Plan.DialectName, pReport.HookName])] + RenderChangeSetText(pReport.Plan.ChangeSet);
  for VChange in pReport.Plan.Changes do
    if VChange.Change.Blocked = '' then
    begin
      Result := Result + [Format('[%d] statements', [VChange.Change.Id])] + Prefixed(INDENT, VChange.Ddl);
      if VChange.Safe.AddSql <> '' then
        Result := Result + Prefixed(INDENT, [VChange.Safe.AddSql, VChange.Safe.CopySql, VChange.Safe.MismatchSql] + VChange.Safe.SwapSql);
      Result := Result + PrecheckLines(VChange) + Prefixed(INDENT + 'note: ', VChange.Notes);
    end;
  Result := Result + Prefixed('hook before: ', pReport.Plan.HookBefore) + Prefixed('hook after: ', pReport.Plan.HookAfter) +
    Prefixed('note: ', pReport.Plan.Notes);
  if pReport.HasOutcome then
    Result := Result + OutcomeLines(pReport.Outcome);
  if pReport.DryRun then
    Result := Result + ['dry run: nothing written (add --apply to write)'];
end;

end.
