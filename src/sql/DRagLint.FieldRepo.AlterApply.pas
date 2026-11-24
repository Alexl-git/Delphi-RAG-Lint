unit DRagLint.FieldRepo.AlterApply;

{ drag-lint 1.54 -- lane TT-ALTER: pre-checks and the grouped apply of a per-table ALTER plan.

  Firebird commits DDL per transaction and a column added in a transaction cannot be filled in the same one, so a
  plan is NOT atomic as a whole. It is atomic per group: hook-before, direct (one transaction), one group per
  safe-path change (ADD tx, COPY tx, verify + SWAP tx; a failure before the swap commits drops the copy again),
  drop, order, hook-after. The first failing group stops the run; the outcome names the state of every group.
  Drops come after everything that could fail or that counts column positions. }

interface

uses
  System.SysUtils,
  DRagLint.FieldRepo.Alter,
  DRagLint.FieldRepo.DbProvider;

type
  /// <summary>The apply was refused before anything was executed.</summary>
  EFrAlterRefused = class(Exception);

  /// <summary>Proof that the pre-checks ran on this connection for this plan.</summary>
  TFrPrecheckTicket = record
    /// <summary>IFrDbProvider.SessionId of the checked connection.</summary>
    SessionId: string;
    /// <summary>TFrAlterPlan.Hash of the checked plan.</summary>
    PlanHash: string;
  end;

  /// <summary>How a group ended.</summary>
  /// <remarks>fgsLeftover = the group failed AND its clean-up failed: the temporary column is still there (the old
  /// column is intact). fgsUnknown = the rollback failed (the connection is gone): look at the table before anything
  /// else.</remarks>
  TFrGroupState = (fgsNotRun, fgsCommitted, fgsRolledBack, fgsCompensated, fgsLeftover, fgsUnknown);

  /// <summary>One executed (or skipped) group.</summary>
  TFrGroupOutcome = record
    Name: string;
    ChangeIds: TArray<Integer>;
    /// <summary>Statements of the group in order.</summary>
    Statements: TArray<string>;
    State: TFrGroupState;
    /// <summary>'' unless the group failed; never holds a password (the provider's message, scrubbed by the caller).</summary>
    Error: string;
  end;

  /// <summary>What an apply did.</summary>
  TFrAlterOutcome = record
    Groups: TArray<TFrGroupOutcome>;
    /// <summary>Verification problems found after the last commit.</summary>
    Problems: TArray<string>;
    /// <summary>True when every group committed and the verification found nothing.</summary>
    /// <returns>Success.</returns>
    function Success: Boolean;
  end;

const
  /// <summary>Names of TFrGroupState in reports.</summary>
  GROUP_STATE_NAMES: array[TFrGroupState] of string = ('not-run', 'committed', 'rolled-back', 'compensated', 'leftover', 'unknown');

/// <summary>Runs every pre-check of the plan (read only) and blocks the changes that fail one.</summary>
/// <param name="pProvider">The connection the apply will use.</param>
/// <param name="pPlan">The plan; counts, Blocked and Checked are set in place.</param>
/// <returns>The ticket ApplyAlterPlan asks for.</returns>
/// <remarks>Scans the table once per pre-check. A blocked change keeps its earlier reason and is not scanned.</remarks>
function RunPrechecks(const pProvider: IFrDbProvider; var pPlan: TFrAlterPlan): TFrPrecheckTicket;

/// <summary>Resolves the lines of a --select file against a plan.</summary>
/// <param name="pPlan">The plan (after the pre-checks).</param>
/// <param name="pLines">One id per line, or 'all'; blank lines and lines starting with # are ignored.</param>
/// <returns>The ids in plan order. 'all' takes every change that is not blocked EXCEPT a DROP COLUMN: a drop needs its
/// own id (beside 'all' or alone).</returns>
/// <exception cref="EFrChangeSetError">An unknown id, a blocked change named by id, or a line that is neither an id nor
/// 'all'.</exception>
function SelectAlterIds(const pPlan: TFrAlterPlan; const pLines: TArray<string>): TArray<Integer>;

/// <summary>Executes the chosen changes of a plan.</summary>
/// <param name="pProvider">The connection the pre-checks ran on.</param>
/// <param name="pPlan">The pre-checked plan.</param>
/// <param name="pTicket">The ticket of RunPrechecks.</param>
/// <param name="pIds">Ids to apply.</param>
/// <param name="pBeforeWrite">Runs once, after every refusal check and before the first write, when there is something to
/// apply (the backup of ruling R9). An exception of it goes to the caller and nothing is executed.</param>
/// <returns>The state of every group; a failure inside a group is reported there, not raised.</returns>
/// <exception cref="EFrAlterRefused">Nothing was executed: no ticket, a ticket of another connection or plan, the
/// table changed since the plan was made (asked again after pBeforeWrite), an unknown or blocked id, or a missing
/// prerequisite.</exception>
/// <remarks>A backup takes time: what changed in the DATA meanwhile is not scanned again. Firebird itself refuses a NOT
/// NULL that has NULLs by then, and the safe path compares every row in its swap transaction.</remarks>
function ApplyAlterPlan(const pProvider: IFrDbProvider; const pPlan: TFrAlterPlan; const pTicket: TFrPrecheckTicket;
  const pIds: TArray<Integer>; const pBeforeWrite: TProc = nil): TFrAlterOutcome;

implementation

uses
  System.Generics.Collections,
  DRagLint.FieldRepo.ChangeSet;

const
  GROUP_BEFORE = 'hook-before';
  GROUP_DIRECT = 'direct';
  GROUP_SAFE = 'safe';
  GROUP_DROP = 'drop';
  GROUP_ORDER = 'order';
  GROUP_AFTER = 'hook-after';

type
  { One group to run; Safe.AddSql <> '' = a safe-path group. }
  TGroup = record
    Outcome: TFrGroupOutcome;
    Safe: TFrSafeSteps;
  end;

function TFrAlterOutcome.Success: Boolean;
var
  VGroup: TFrGroupOutcome;
begin
  Result := Length(Problems) = 0;
  for VGroup in Groups do
    Result := Result and (VGroup.State = fgsCommitted);
end;

function RunPrechecks(const pProvider: IFrDbProvider; var pPlan: TFrAlterPlan): TFrPrecheckTicket;
var
  i, j: Integer;
  VCheck: TFrPrecheck;
begin
  for i := 0 to High(pPlan.Changes) do
  begin
    if pPlan.Changes[i].Change.Blocked <> '' then
      Continue;
    for j := 0 to High(pPlan.Changes[i].Prechecks) do
    begin
      VCheck := pPlan.Changes[i].Prechecks[j];
      VCheck.Count := pProvider.ReadScalar(VCheck.Sql);
      pPlan.Changes[i].Prechecks[j] := VCheck;
      if (VCheck.Count = 0) or (VCheck.Code = '') then
        Continue;
      if pPlan.Changes[i].Change.Blocked <> '' then
        pPlan.Changes[i].Change.Blocked := pPlan.Changes[i].Change.Blocked + '; ';
      pPlan.Changes[i].Change.Blocked := pPlan.Changes[i].Change.Blocked + VCheck.Code + ': ' + Format(VCheck.Text, [VCheck.Count]);
      pPlan.Changes[i].Change.Checked := False;
    end;
  end;
  Result.SessionId := pProvider.SessionId;
  Result.PlanHash := pPlan.Hash;
end;

function SelectAlterIds(const pPlan: TFrAlterPlan; const pLines: TArray<string>): TArray<Integer>;
const
  SELECT_ALL = 'all';
var
  VLine: string;
  VNamed: TArray<string>;
  VPicked: TArray<Integer>;
  VAll: Boolean;
  VChange: TFrChange;
  VPlanned: TFrAlterChange;
begin
  VNamed := nil;
  VAll := False;
  for VLine in pLines do
    if SameText(Trim(VLine), SELECT_ALL) then
      VAll := True
    else
      VNamed := VNamed + [VLine];
  VPicked := nil;
  for VChange in SelectChanges(pPlan.ChangeSet, VNamed) do
    VPicked := VPicked + [VChange.Id];
  Result := nil;
  for VPlanned in pPlan.Changes do
    if TArray.Contains<Integer>(VPicked, VPlanned.Change.Id) or
      (VAll and (VPlanned.Kind <> fakDrop) and (VPlanned.Change.Blocked = '')) then
      Result := Result + [VPlanned.Change.Id];
end;

function FindPlanned(const pPlan: TFrAlterPlan; pId: Integer; out pChange: TFrAlterChange): Boolean;
var
  VChange: TFrAlterChange;
begin
  Result := False;
  pChange := Default(TFrAlterChange);
  for VChange in pPlan.Changes do
    if VChange.Change.Id = pId then
    begin
      pChange := VChange;
      Exit(True);
    end;
end;

procedure CheckSelection(const pPlan: TFrAlterPlan; const pIds: TArray<Integer>);
var
  VId, VNeed: Integer;
  VChange: TFrAlterChange;
begin
  for VId in pIds do
  begin
    if not FindPlanned(pPlan, VId, VChange) then
      raise EFrAlterRefused.CreateFmt('unknown change id %d', [VId]);
    if VChange.Change.Blocked <> '' then
      raise EFrAlterRefused.CreateFmt('change %d is blocked: %s', [VId, VChange.Change.Blocked]);
    for VNeed in VChange.DependsOn do
      if not TArray.Contains<Integer>(pIds, VNeed) then
        raise EFrAlterRefused.CreateFmt('change %d needs change %d, which is not selected', [VId, VNeed]);
  end;
end;

procedure CheckTicket(const pProvider: IFrDbProvider; const pPlan: TFrAlterPlan; const pTicket: TFrPrecheckTicket);
begin
  if pTicket.SessionId = '' then
    raise EFrAlterRefused.Create('the pre-checks were not run: nothing applied');
  if pTicket.SessionId <> pProvider.SessionId then
    raise EFrAlterRefused.Create('the pre-checks ran on another connection: nothing applied');
  if pTicket.PlanHash <> pPlan.Hash then
    raise EFrAlterRefused.Create('the pre-checks ran for another plan: nothing applied');
  if LiveFingerprint(pProvider.ReadTable(pPlan.TableName)) <> pPlan.LiveFingerprint then
    raise EFrAlterRefused.CreateFmt('table %s changed since the plan was made: nothing applied', [pPlan.TableName]);
end;

function PlainGroup(const pName: string): TGroup;
begin
  Result := Default(TGroup);
  Result.Outcome.Name := pName;
end;

function BuildGroups(const pPlan: TFrAlterPlan; const pIds: TArray<Integer>): TArray<TGroup>;
var
  VBefore, VDirect, VDrop, VOrder, VAfter, VSafe: TGroup;
  VSafes, VAll: TArray<TGroup>;
  VGroup: TGroup;
  VChange: TFrAlterChange;
begin
  VBefore := PlainGroup(GROUP_BEFORE);
  VDirect := PlainGroup(GROUP_DIRECT);
  VDrop := PlainGroup(GROUP_DROP);
  VOrder := PlainGroup(GROUP_ORDER);
  VAfter := PlainGroup(GROUP_AFTER);
  VSafes := nil;
  for VChange in pPlan.Changes do
    if TArray.Contains<Integer>(pIds, VChange.Change.Id) then
      case VChange.Kind of
        fakSafeType:
          begin
            VSafe := PlainGroup(GROUP_SAFE + ' ' + VChange.Column);
            VSafe.Outcome.ChangeIds := [VChange.Change.Id];
            VSafe.Outcome.Statements := [VChange.Safe.AddSql, VChange.Safe.CopySql, VChange.Safe.MismatchSql] + VChange.Safe.SwapSql;
            VSafe.Safe := VChange.Safe;
            VSafes := VSafes + [VSafe];
          end;
        fakDrop:
          begin
            VDrop.Outcome.ChangeIds := VDrop.Outcome.ChangeIds + [VChange.Change.Id];
            VDrop.Outcome.Statements := VDrop.Outcome.Statements + VChange.Ddl;
          end;
        fakOrder:
          begin
            VOrder.Outcome.ChangeIds := [VChange.Change.Id];
            VOrder.Outcome.Statements := VChange.Ddl;
          end;
      else
        VDirect.Outcome.ChangeIds := VDirect.Outcome.ChangeIds + [VChange.Change.Id];
        VDirect.Outcome.Statements := VDirect.Outcome.Statements + VChange.Ddl;
      end;
  VBefore.Outcome.Statements := pPlan.HookBefore;
  VAfter.Outcome.Statements := pPlan.HookAfter;
  VAll := [VBefore, VDirect] + VSafes + [VDrop, VOrder, VAfter];
  Result := nil;
  for VGroup in VAll do
    if Length(VGroup.Outcome.Statements) > 0 then
      Result := Result + [VGroup];
end;

{ Rolls back whatever is open; a rollback that fails itself (lost connection) must not hide the first error. }
procedure TryRollback(const pProvider: IFrDbProvider; var pOutcome: TFrGroupOutcome);
begin
  try
    pProvider.Rollback;
    pOutcome.State := fgsRolledBack;
  except
    on E: Exception do
    begin
      pOutcome.State := fgsUnknown;
      pOutcome.Error := pOutcome.Error + ' (rollback: ' + E.Message + ')';
    end;
  end;
end;

procedure RunPlain(const pProvider: IFrDbProvider; var pOutcome: TFrGroupOutcome);
var
  VSql: string;
begin
  try
    pProvider.BeginWrite('');
    for VSql in pOutcome.Statements do
      pProvider.Execute(VSql);
    pProvider.Commit;
    pOutcome.State := fgsCommitted;
  except
    on E: Exception do
    begin
      pOutcome.Error := E.Message;
      TryRollback(pProvider, pOutcome);
    end;
  end;
end;

procedure RunOne(const pProvider: IFrDbProvider; const pSql: string);
begin
  pProvider.BeginWrite('');
  pProvider.Execute(pSql);
  pProvider.Commit;
end;

{ ADD, COPY, verify + SWAP. Until the swap commits the old column is untouched and only the copy has to go. }
procedure RunSafe(const pProvider: IFrDbProvider; const pTable: string; var pGroup: TGroup);
var
  VAdded: Boolean;
  VBad: Int64;
  VSql: string;
begin
  VAdded := False;
  try
    RunOne(pProvider, pGroup.Safe.AddSql);
    VAdded := True;
    RunOne(pProvider, pGroup.Safe.CopySql);
    pProvider.BeginWrite(pTable);
    VBad := pProvider.WriteScalar(pGroup.Safe.MismatchSql);
    if VBad <> 0 then
      raise EFrAlterError.CreateFmt('%d row(s) of the copy differ from column %s', [VBad, pGroup.Safe.Column]);
    for VSql in pGroup.Safe.SwapSql do
      pProvider.Execute(VSql);
    pProvider.Commit;
    pGroup.Outcome.State := fgsCommitted;
  except
    on E: Exception do
    begin
      pGroup.Outcome.Error := E.Message;
      TryRollback(pProvider, pGroup.Outcome);
      if VAdded and (pGroup.Outcome.State = fgsRolledBack) then
        try
          RunOne(pProvider, pGroup.Safe.CleanupSql);
          pGroup.Outcome.State := fgsCompensated;
        except
          on F: Exception do
          begin
            pGroup.Outcome.Error := pGroup.Outcome.Error + Format('; the clean-up failed too, column %s is left: ',
              [pGroup.Safe.TempColumn]) + F.Message;
            TryRollback(pProvider, pGroup.Outcome);
            if pGroup.Outcome.State = fgsRolledBack then
              pGroup.Outcome.State := fgsLeftover;
          end;
        end;
    end;
  end;
end;

function VerifyColumn(const pLive: TFrTableFacts; const pChange: TFrAlterChange): string;
var
  VCol: TFrColumnFacts;
begin
  Result := '';
  if not pLive.FindColumn(pChange.Column, VCol) then
    Exit(Format('change %d: column %s is missing', [pChange.Change.Id, pChange.Column]));
  if (pChange.ExpectType.FieldType <> 0) and not SameType(VCol.DataType, pChange.ExpectType) then
    Result := Format('change %d: column %s has not the planned type', [pChange.Change.Id, pChange.Column])
  else if (pChange.Kind = fakNullability) and (VCol.NotNull <> (pChange.Change.NewValue = 'NOT NULL')) then
    Result := Format('change %d: column %s has not the planned nullability', [pChange.Change.Id, pChange.Column]);
end;

{ The listed columns (one POSITION statement each) must be the first ones of the table. }
function VerifyOrder(const pLive: TFrTableFacts; const pChange: TFrAlterChange): string;
var
  VWanted: TArray<string>;
  i: Integer;
begin
  Result := '';
  VWanted := pChange.Change.NewValue.Split([',']);
  for i := 0 to High(pChange.Ddl) do
    if (i > High(pLive.Columns)) or (i > High(VWanted)) or not SameText(pLive.Columns[i].Name, VWanted[i]) then
      Exit(Format('change %d: the columns are not in the planned order', [pChange.Change.Id]));
end;

function Verify(const pProvider: IFrDbProvider; const pPlan: TFrAlterPlan; const pIds: TArray<Integer>): TArray<string>;
var
  VLive: TFrTableFacts;
  VChange: TFrAlterChange;
  VCol: TFrColumnFacts;
  VDomain: TFrDomainFacts;
  VProblem: string;
begin
  Result := nil;
  VLive := pProvider.ReadTable(pPlan.TableName);
  for VChange in pPlan.Changes do
  begin
    if not TArray.Contains<Integer>(pIds, VChange.Change.Id) then
      Continue;
    VProblem := '';
    case VChange.Kind of
      fakCreateDomain:
        if not VLive.FindDomain(VChange.Column, VDomain) then
          VProblem := Format('change %d: domain %s is missing', [VChange.Change.Id, VChange.Column]);
      fakDrop:
        if VLive.FindColumn(VChange.Column, VCol) then
          VProblem := Format('change %d: column %s is still there', [VChange.Change.Id, VChange.Column]);
      fakOrder: VProblem := VerifyOrder(VLive, VChange);
    else
      VProblem := VerifyColumn(VLive, VChange);
    end;
    if VProblem <> '' then
      Result := Result + [VProblem];
  end;
end;

function ApplyAlterPlan(const pProvider: IFrDbProvider; const pPlan: TFrAlterPlan; const pTicket: TFrPrecheckTicket;
  const pIds: TArray<Integer>; const pBeforeWrite: TProc): TFrAlterOutcome;
var
  VGroups: TArray<TGroup>;
  VFailed: Boolean;
  i: Integer;
begin
  Result := Default(TFrAlterOutcome);
  CheckTicket(pProvider, pPlan, pTicket);
  CheckSelection(pPlan, pIds);
  if Length(pIds) = 0 then
    Exit;
  if Assigned(pBeforeWrite) then
  begin
    pBeforeWrite();
    CheckTicket(pProvider, pPlan, pTicket);
  end;
  VGroups := BuildGroups(pPlan, pIds);
  VFailed := False;
  for i := 0 to High(VGroups) do
  begin
    if not VFailed then
    begin
      if VGroups[i].Safe.AddSql <> '' then
        RunSafe(pProvider, pPlan.TableName, VGroups[i])
      else
        RunPlain(pProvider, VGroups[i].Outcome);
      VFailed := VGroups[i].Outcome.State <> fgsCommitted;
    end;
    Result.Groups := Result.Groups + [VGroups[i].Outcome];
  end;
  if VFailed then
    Exit;
  try
    Result.Problems := Verify(pProvider, pPlan, pIds);
  except
    on E: Exception do
      Result.Problems := ['verification failed: ' + E.Message];
  end;
end;

end.
