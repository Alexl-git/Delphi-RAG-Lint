unit DRagLint.FieldRepo.SchemaHookMicronite;

{ drag-lint 1.54 -- lane TT-ALTER: the Micronite rules of a per-table ALTER (owner answer FU-2). Registers itself;
  selected with --hook micronite. Conservative: it refuses and reminds, it adds no statement. }

interface

uses
  System.Classes,
  DRagLint.FieldRepo.DataServiceGen;

const
  /// <summary>What --hook takes.</summary>
  HOOK_MICRONITE = 'micronite';

type
  /// <summary>Runs one ORM generator verb the way RunOrmGenVerb does; a test seam of MicroniteOrmFollowUp.</summary>
  TOrmDryRun = reference to function(const pOptions: TOrmVerbOptions; pOut: TStrings): Integer;

/// <summary>The follow-up of a successful 'repo alter-table --apply --hook micronite' (owner Q-ALTER-3 = B): 'repo update-orm'
/// as a DRY RUN for the altered table, reported as the ORM units that would change.</summary>
/// <param name="pHook">The --hook value; anything but micronite gives no follow-up.</param>
/// <param name="pApplied">True only when the apply succeeded; a failed or refused apply gives no follow-up.</param>
/// <param name="pRepo">The repository file (the same one the alter used).</param>
/// <param name="pTable">The altered table.</param>
/// <param name="pCodeDir">--code-dir, folder of the i/u units.</param>
/// <param name="pServerDir">--server-dir ('' = not given).</param>
/// <param name="pClientDir">--client-dir ('' = not given).</param>
/// <param name="pRun">The generator; nil = RunOrmGenVerb.</param>
/// <returns>The lines to print: a summary with the count and one line per unit that is new or would change; a unit the
/// generator REFUSED (a hand-edited region, markers that cannot be trusted) is counted in the summary and named too, so that
/// "0 unit(s) would change" never hides one; or a "warning:" line when the dry run failed (a missing --code-dir included).
/// nil when there is no follow-up.</returns>
/// <remarks>Never writes: Apply is forced to False. A failure only warns; the caller's result and exit code stay as the apply
/// left them. Never raises.</remarks>
function MicroniteOrmFollowUp(const pHook: string; pApplied: Boolean; const pRepo, pTable, pCodeDir, pServerDir, pClientDir: string;
  const pRun: TOrmDryRun = nil): TArray<string>;
implementation

uses
  System.SysUtils,
  DRagLint.FieldRepo.Alter,
  DRagLint.FieldRepo.SchemaHook;

const
  REGISTRY_PREFIX = 'FIB$';
  REFUSED_MARK = ': REFUSED'; // DRagLint.FieldRepo.OrmGen: a unit or a region the generator leaves as it is

type
  TFrSchemaHookMicronite = class(TFrSchemaHook)
  public
    function Name: string; override;
    function TableVeto(const pTable: string): string; override;
    function Notes(const pPlan: TFrAlterPlan): TArray<string>; override;
  end;

function TFrSchemaHookMicronite.Name: string;
begin
  Result := HOOK_MICRONITE;
end;

{ TT-Q05: the FIB$ registry must not be touched or modified once DL is on line. }
function TFrSchemaHookMicronite.TableVeto(const pTable: string): string;
begin
  Result := '';
  if pTable.StartsWith(REGISTRY_PREFIX, True) then
    Result := 'a FIB$ registry table is never changed';
end;

function TFrSchemaHookMicronite.Notes(const pPlan: TFrAlterPlan): TArray<string>;
begin
  Result := nil;
  if Length(pPlan.Changes) > 0 then
    Result := [Format('Micronite: regenerate the ORM unit afterwards (drag-lint repo update-orm --table %s)', [pPlan.TableName]),
      'Micronite: the FIB$ registry rows of these columns are not changed'];
end;

function MicroniteOrmFollowUp(const pHook: string; pApplied: Boolean; const pRepo, pTable, pCodeDir, pServerDir, pClientDir: string;  // dl:ok too-many-parameters@173e -- REVIEWED 2026-11-26 v155 INT: the alter-table verb options passed straight through (hook, apply, repo, table, three folders, output); a record would only move the same list
  const pRun: TOrmDryRun): TArray<string>;
var
  VOptions: TOrmVerbOptions;
  VLines: TStringList;
  VLine, VUnits: string;
  VCount, VRefused: Integer;
begin
  Result := nil;
  if not SameText(pHook, HOOK_MICRONITE) or not pApplied then
    Exit;
  VOptions := Default(TOrmVerbOptions);
  VOptions.Sub := 'update-orm';
  VOptions.RepoPath := pRepo;
  VOptions.CodeDir := pCodeDir;
  VOptions.ServerDir := pServerDir;
  VOptions.ClientDir := pClientDir;
  VOptions.Tables := pTable;
  VOptions.Apply := False;
  VLines := TStringList.Create;
  try
    try
      if (if Assigned(pRun) then pRun(VOptions, VLines) else RunOrmGenVerb(VOptions, VLines)) <> 0 then
      begin
        Result := ['warning: the update-orm dry run after the alter failed, nothing was written: ' + Trim(VLines.Text) +
          ' (run: drag-lint repo update-orm --table ' + pTable + ' --code-dir <folder>)'];
        Exit;
      end;
    except
      on E: Exception do
      begin
        Result := ['warning: the update-orm dry run after the alter failed, nothing was written: ' + E.Message];
        Exit;
      end;
    end;
    VCount := 0;
    VRefused := 0;
    VUnits := '';
    for VLine in VLines do
      if VLine.StartsWith('changed ') or VLine.StartsWith('new ') then
      begin
        Inc(VCount);
        VUnits := VUnits + 'orm unit: ' + VLine + sLineBreak;
      end
      else if VLine.StartsWith('skipped ') and VLine.Contains(REFUSED_MARK) then
      begin
        Inc(VRefused);
        VUnits := VUnits + 'orm unit: ' + VLine + sLineBreak;
      end;
    Result := [Format('orm follow-up (repo update-orm --table %s, dry run, nothing written): %d unit(s) would change%s', [pTable, VCount,
      if VRefused > 0 then Format(', %d REFUSED (not regenerated until its region is settled)', [VRefused]) else ''])];
    for VLine in VUnits.Split([sLineBreak], TStringSplitOptions.ExcludeEmpty) do
      Result := Result + [VLine];
    if VCount > 0 then
      Result := Result + ['apply them with: drag-lint repo update-orm --table ' + pTable + ' --apply (same --code-dir)'];
  finally
    VLines.Free;
  end;
end;

initialization
  RegisterSchemaHook(TFrSchemaHookMicronite.Create);

end.
