unit ConvRules.ConvertBatch;

{ Pure decisions behind the Convert runner's batch mode (plan 2026-10-23, B4 / A9): when a
  run goes through ONE convert-apply per book over many units (apply-batch/1), how the
  units are chunked, how long a chunk may take, and whether the engine's answer lines up
  with the units asked for. No UI and no engine calls -- ConvRules.ConvertRunner executes,
  ConvRulesModelTests.dpr pins every rule here. Split out of ConvRules.ConvertRun, which is
  at its size marker (decision D10). }

interface

uses
  System.SysUtils
  , ConvRules.ConvertRun;

const
  /// <summary>Units per convert-apply call in batch mode (decision D2): bounds the worst
  /// call (BatchTimeoutMs) and the work lost to one killed call.</summary>
  BATCH_MAX_UNITS = 8;
  /// <summary>Extra watchdog time per unit beyond the first in one batch call, in ms
  /// (decision D5; measured marginal cost per unit is 3-5 s, so this is generous).</summary>
  BATCH_UNIT_EXTRA_MS = 120000;
  /// <summary>Note prefix of a chunk the runner does not trust (see BatchUntrustedNote).</summary>
  BATCH_UNTRUSTED_PREFIX = 'batch apply not trusted: ';
  /// <summary>Format of the row note when the ONE reindex after a chunk failed; %s = the
  /// reindex error.</summary>
  BATCH_REINDEX_FAILED_FMT = 'reindex after batch apply failed: %s';
  /// <summary>Format of the row note of a unit whose entry in a configuration-stopped chunk
  /// says it may have been written (ConfigStopMayHaveWritten); %s = the backup it is
  /// restored from.</summary>
  CONFIG_STOP_WROTE_FMT = 'the run stopped (cast library unusable) but the engine reported this unit written -- restored from this run''s backup %s';
  /// <summary>Format of the row note of a unit in a configuration-stopped chunk whose answer
  /// does not line up with the --unit list; %s = the error read, %s = the backup it is restored from.</summary>
  CONFIG_STOP_UNREAD_FMT = 'the run stopped (cast library unusable: %s) and the answer could not be read per unit -- restored from this run''s backup %s';
  /// <summary>Format of the note on a converted row that a cancel between batch chunks undid
  /// (R4: a unit gets every book or none); %s = the backup it was restored from.</summary>
  BATCH_CANCEL_UNDONE_FMT = 'undone: the run was cancelled before every book reached this unit; restored from %s';
  /// <summary>As BATCH_CANCEL_UNDONE_FMT, for a configuration stop (exit ENGINE_EXIT_CONFIG).</summary>
  BATCH_STOP_UNDONE_FMT = 'undone: the run stopped (cast library unusable) before every book reached this unit; restored from %s';
  /// <summary>Format of the unit-level row when that restore failed; %s = 'was cancelled' or
  /// 'stopped (cast library unusable)', %s = the error, %s = the backups.</summary>
  BATCH_PARTIAL_RESTORE_FAILED_FMT = 'the run %s before every book reached this unit and the restore failed: %s; the unit may be half-converted -- backup at %s';

/// <summary>PURE: True when the answer of one batch call lines up with the units asked for.</summary>
/// <param name="ABatch">ParseApplyBatchJson's reading.</param>
/// <param name="AUnits">The --unit paths of the call, in call order.</param>
/// <returns>True when ABatch is Valid, Length(Units) and UnitsCount both equal
/// Length(AUnits), and every units[i].UnitPath is either absent ('') or the same file as
/// AUnits[i] (ExpandFileName, case-insensitive). False for a short, long, reordered or
/// invalid answer -- the runner then trusts none of the chunk.</returns>
function BatchUnitsMatch(const ABatch: TApplyBatch; const AUnits: TArray<string>): Boolean;

/// <summary>PURE: True when the run converts through apply-batch/1 calls.</summary>
/// <param name="ACapBatch">The engine reports the batch_units capability.</param>
/// <param name="AWholeUnitScope">The run is unscoped; a scoped (IDE request) run keeps the
/// per-unit path because --only binds every unit of a batch (decision D1).</param>
/// <param name="AUnitCount">Units in the run; a single unit is answered with a bare
/// apply/1, so it runs per-unit (decision D9).</param>
/// <param name="AOverride">CONVRULES_BATCH; 'off' (any case) forces the per-unit path
/// (decision D6), any other value is ignored.</param>
/// <returns>ACapBatch and AWholeUnitScope and (AUnitCount >= 2) and not 'off'.</returns>
function BatchModeFor(ACapBatch, AWholeUnitScope: Boolean; AUnitCount: Integer; const AOverride: string): Boolean;

/// <summary>PURE: splits the active units into batch calls.</summary>
/// <param name="AUnits">Unit paths in run order.</param>
/// <param name="AMax">Units per call; 0 or less = one chunk.</param>
/// <returns>Chunks of at most AMax units, order kept, the last one shorter; [] for no
/// units.</returns>
function BatchChunks(const AUnits: TArray<string>; AMax: Integer): TArray<TArray<string>>;

/// <summary>PURE: the watchdog of one batch call.</summary>
/// <param name="ABaseMs">The per-unit watchdog (the adapter passes CONVERT_TIMEOUT_MS).</param>
/// <param name="AUnits">Units in the call.</param>
/// <returns>ABaseMs for one unit or fewer, else ABaseMs + (AUnits - 1) * BATCH_UNIT_EXTRA_MS.</returns>
function BatchTimeoutMs(ABaseMs, AUnits: Integer): Integer;

/// <summary>PURE: the row note of a chunk the runner restored because it could not trust it.</summary>
/// <param name="AWhy">What broke (unparseable output, missing units, contract breach).</param>
/// <returns>BATCH_UNTRUSTED_PREFIX + AWhy.</returns>
function BatchUntrustedNote(const AWhy: string): string;

/// <summary>PURE: the answer of a ONE-unit chunk, read as a one-unit apply-batch/1. The
/// engine answers a single --unit with a bare apply/1 (CONVERSION-RULES.md "Batch
/// (1.23.0)"), and a batch run meets one-unit chunks: the rest of BatchChunks, or the one
/// unit still active in a later book.</summary>
/// <param name="AJson">The engine's output for the one --unit.</param>
/// <param name="ACode">The call's exit code; it becomes ExitCode.</param>
/// <param name="AFeatures">As for ParseApplyJson.</param>
/// <returns>ParseApplyBatchJson(AJson) when that is Valid. Else, when AJson holds an apply/1
/// object that names its unit: Valid, Units = [that reading], UnitsCount 1, ExitCode =
/// ACode, Ok = its ok, and one of OkCount (ok), RefusedCount (a refusal or an edit-set
/// refusal) or FailedCount set to 1 -- so BatchContractBroken says what ApplyExitBroken
/// says for a single apply. Else not Valid.</returns>
function BatchOfSingle(const AJson: string; ACode: Integer; AFeatures: TApplyFeatures): TApplyBatch;

/// <summary>PURE (R5): why the per-entry exit_code of a batch answer is not trusted; ''
/// when it is. Engine 1.33.0 (G3): each units[] entry carries THAT unit's code (0 ok, 1
/// refused, 2 write failure, 6 configuration), the batch's exit_code is the worst unit's.</summary>
/// <param name="ABatch">ParseApplyBatchJson's (or BatchOfSingle's) reading.</param>
/// <returns>'' when every entry's ExitCode is APPLY_EXIT_ABSENT (an older engine) or agrees
/// with its ok flag (0 exactly when ok) and is no worse than ABatch.ExitCode (not compared
/// when that is APPLY_EXIT_ABSENT). Else
/// 'units[I] exit_code E contradicts ok=true|false' or 'units[I] exit_code E exceeds the
/// batch exit_code X', for the first such entry (I zero-based).</returns>
function BatchEntryExitBroken(const ABatch: TApplyBatch): string;

/// <summary>PURE (R1): whether one entry of a configuration-stopped chunk (exit
/// ENGINE_EXIT_CONFIG) may have written its unit. The engine's 1.33.1 contract says a
/// top-level exit 6 touched no unit -- every entry refused, exit_code 6 -- and the runner
/// then drops the unit's unneeded backup; an entry that says otherwise is not believed.</summary>
/// <param name="AEntry">The entry, read like a single apply/1.</param>
/// <returns>True when AEntry is ok, half written (ApplyHalfWritten) or has exit_code 2 (a
/// write failure, possibly a failed rollback); False for a refusal, an exit_code of 1 or 6,
/// or a failure without exit_code (an engine before 1.33.0).</returns>
function ConfigStopMayHaveWritten(const AEntry: TApplyRow): Boolean;

implementation

function BatchOfSingle(const AJson: string; ACode: Integer; AFeatures: TApplyFeatures): TApplyBatch;
var
  LRow: TApplyRow;
begin
  Result:= ParseApplyBatchJson(AJson, AFeatures);
  if Result.Valid then
    Exit;
  LRow:= ParseApplyJson(AJson, AFeatures);
  if LRow.Unparsed or (LRow.UnitPath = '') then
    Exit;
  Result.Valid     := True;
  Result.Ok        := LRow.Ok;
  Result.ExitCode  := ACode;
  Result.UnitsCount:= 1;
  Result.Units     := [LRow];
  if LRow.Ok then
    Result.OkCount:= 1
  else if LRow.Refused or ApplyEditSetRefused(LRow) then
    Result.RefusedCount:= 1
  else
    Result.FailedCount:= 1;
end;

function BatchUnitsMatch(const ABatch: TApplyBatch; const AUnits: TArray<string>): Boolean;
begin
  Result:= ABatch.Valid and (Length(ABatch.Units) = Length(AUnits)) and (ABatch.UnitsCount = Length(AUnits));
  if not Result then
    Exit;
  for var LIdx:= 0 to High(AUnits) do
    if (ABatch.Units[LIdx].UnitPath <> '')
      and not SameText(ExpandFileName(ABatch.Units[LIdx].UnitPath), ExpandFileName(AUnits[LIdx])) then
      Exit(False);
end;

function BatchModeFor(ACapBatch, AWholeUnitScope: Boolean; AUnitCount: Integer; const AOverride: string): Boolean;
begin
  Result:= ACapBatch and AWholeUnitScope and (AUnitCount >= 2) and not SameText(AOverride, 'off');
end;

function BatchChunks(const AUnits: TArray<string>; AMax: Integer): TArray<TArray<string>>;
var
  LStart: Integer;
begin
  Result:= nil;
  if Length(AUnits) = 0 then
    Exit;
  if AMax <= 0 then
    AMax:= Length(AUnits);
  LStart:= 0;
  while LStart < Length(AUnits) do
  begin
    Result:= Result + [Copy(AUnits, LStart, AMax)];
    Inc(LStart, AMax);
  end;
end;

function BatchTimeoutMs(ABaseMs, AUnits: Integer): Integer;
begin
  Result:= if AUnits <= 1 then ABaseMs else ABaseMs + (AUnits - 1) * BATCH_UNIT_EXTRA_MS;
end;

function BatchUntrustedNote(const AWhy: string): string;
begin
  Result:= BATCH_UNTRUSTED_PREFIX + AWhy;
end;

function BatchEntryExitBroken(const ABatch: TApplyBatch): string;
var
  LEntry: TApplyRow;
begin
  for var I: Integer:= 0 to High(ABatch.Units) do
  begin
    LEntry:= ABatch.Units[I];
    if LEntry.ExitCode = APPLY_EXIT_ABSENT then
      Continue;
    if LEntry.Ok <> (LEntry.ExitCode = 0) then
      Exit(Format('units[%d] exit_code %d contradicts ok=%s', [I, LEntry.ExitCode, if LEntry.Ok then 'true' else 'false']));
    if (ABatch.ExitCode <> APPLY_EXIT_ABSENT) and (LEntry.ExitCode > ABatch.ExitCode) then
      Exit(Format('units[%d] exit_code %d exceeds the batch exit_code %d', [I, LEntry.ExitCode, ABatch.ExitCode]));
  end;
  Result:= '';
end;

function ConfigStopMayHaveWritten(const AEntry: TApplyRow): Boolean;
const
  EXIT_WRITE_FAILED = 2; // the engine's per-unit code for a write failure or rollback
begin
  Result:= AEntry.Ok or ApplyHalfWritten(AEntry) or (AEntry.ExitCode = EXIT_WRITE_FAILED);
end;

end.