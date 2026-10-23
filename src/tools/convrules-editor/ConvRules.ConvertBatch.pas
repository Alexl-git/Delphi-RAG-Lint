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

/// <summary>PURE: True when the answer of one batch call lines up with the units asked for.</summary>
/// <param name="ABatch">ParseApplyBatchJson's reading.</param>
/// <param name="AUnits">The --unit paths of the call, in call order.</param>
/// <returns>True when ABatch is Valid, Length(Units) and UnitsCount both equal
/// Length(AUnits), and every units[i].UnitPath is either absent ('') or the same file as
/// AUnits[i] (ExpandFileName, case-insensitive). False for a short, long, reordered or
/// invalid answer -- the runner then trusts none of the chunk.</returns>
function BatchUnitsMatch(const ABatch: TApplyBatch; const AUnits: TArray<string>): Boolean;  // dl:ok unused-public-symbol@391a -- REVIEWED 2026-10-23 pure batch decision pinned by the model tests (a separate project); the batch runner wires it in B4 Task 4 (plan 2026-10-23-converter-b4-batch-mode)

/// <summary>PURE: True when the run converts through apply-batch/1 calls.</summary>
/// <param name="ACapBatch">The engine reports the batch_units capability.</param>
/// <param name="AWholeUnitScope">The run is unscoped; a scoped (IDE request) run keeps the
/// per-unit path because --only binds every unit of a batch (decision D1).</param>
/// <param name="AUnitCount">Units in the run; a single unit is answered with a bare
/// apply/1, so it runs per-unit (decision D9).</param>
/// <param name="AOverride">CONVRULES_BATCH; 'off' (any case) forces the per-unit path
/// (decision D6), any other value is ignored.</param>
/// <returns>ACapBatch and AWholeUnitScope and (AUnitCount >= 2) and not 'off'.</returns>
function BatchModeFor(ACapBatch, AWholeUnitScope: Boolean; AUnitCount: Integer; const AOverride: string): Boolean;  // dl:ok unused-public-symbol@ae59 -- REVIEWED 2026-10-23 pure batch decision pinned by the model tests (a separate project); the batch runner wires it in B4 Task 4 (plan 2026-10-23-converter-b4-batch-mode)

/// <summary>PURE: splits the active units into batch calls.</summary>
/// <param name="AUnits">Unit paths in run order.</param>
/// <param name="AMax">Units per call; 0 or less = one chunk.</param>
/// <returns>Chunks of at most AMax units, order kept, the last one shorter; [] for no
/// units.</returns>
function BatchChunks(const AUnits: TArray<string>; AMax: Integer): TArray<TArray<string>>;  // dl:ok unused-public-symbol@ad56 -- REVIEWED 2026-10-23 pure batch decision pinned by the model tests (a separate project); the batch runner wires it in B4 Task 4 (plan 2026-10-23-converter-b4-batch-mode)

/// <summary>PURE: the watchdog of one batch call.</summary>
/// <param name="ABaseMs">The per-unit watchdog (the adapter passes CONVERT_TIMEOUT_MS).</param>
/// <param name="AUnits">Units in the call.</param>
/// <returns>ABaseMs for one unit or fewer, else ABaseMs + (AUnits - 1) * BATCH_UNIT_EXTRA_MS.</returns>
function BatchTimeoutMs(ABaseMs, AUnits: Integer): Integer;  // dl:ok unused-public-symbol@10e3 -- REVIEWED 2026-10-23 pure batch decision pinned by the model tests (a separate project); the batch runner wires it in B4 Task 4 (plan 2026-10-23-converter-b4-batch-mode)

/// <summary>PURE: the row note of a chunk the runner restored because it could not trust it.</summary>
/// <param name="AWhy">What broke (unparseable output, missing units, contract breach).</param>
/// <returns>BATCH_UNTRUSTED_PREFIX + AWhy.</returns>
function BatchUntrustedNote(const AWhy: string): string;  // dl:ok unused-public-symbol@99ec -- REVIEWED 2026-10-23 pure batch decision pinned by the model tests (a separate project); the batch runner wires it in B4 Task 4 (plan 2026-10-23-converter-b4-batch-mode)

implementation

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

end.