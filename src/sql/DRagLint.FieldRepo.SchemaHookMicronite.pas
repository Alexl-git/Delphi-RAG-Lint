unit DRagLint.FieldRepo.SchemaHookMicronite;

{ drag-lint 1.54 -- lane TT-ALTER: the Micronite rules of a per-table ALTER (owner answer FU-2). Registers itself;
  selected with --hook micronite. Conservative: it refuses and reminds, it adds no statement. }

interface

const
  /// <summary>What --hook takes.</summary>
  HOOK_MICRONITE = 'micronite';

implementation

uses
  System.SysUtils,
  DRagLint.FieldRepo.Alter,
  DRagLint.FieldRepo.SchemaHook;

const
  REGISTRY_PREFIX = 'FIB$';

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

initialization
  RegisterSchemaHook(TFrSchemaHookMicronite.Create);

end.
