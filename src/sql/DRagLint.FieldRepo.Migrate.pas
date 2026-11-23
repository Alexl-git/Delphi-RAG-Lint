unit DRagLint.FieldRepo.Migrate;

{ drag-lint 1.53 -- lane FR-MODEL: `repo migrate`, schema 1 -> 2 of a repository file (design
  2026-11-22-field-repository-v2-design.md section 4.6). Nothing is dropped or renamed. }

interface

type
  /// <summary>What a migration did (or, for a dry run, would do).</summary>
  TFrMigrateResult = record
    /// <summary>True when the file was at schema 2 already; nothing else is set then.</summary>
    AlreadyCurrent: Boolean;
    /// <summary>ISCALCULATED rows whose FIELD_KIND is NULL or 1; they get FIELD_KIND 2.</summary>
    CalcRows: Integer;
    /// <summary>True when the change was written (apply), False for a dry run.</summary>
    Applied: Boolean;
    /// <summary>The before-migrate backup file written by an apply; '' otherwise.</summary>
    BackupFile: string;
    /// <summary>The plan line of the dry run (also set after an apply).</summary>
    Plan: string;
  end;

/// <summary>Plans or applies the schema 1 -> 2 migration of a repository file.</summary>
/// <param name="pFileName">Repository file.</param>
/// <param name="pApply">False = dry run (the file is opened read-only and not a byte changes); True = write.</param>
/// <returns>The result; Plan reads `v1 -> v2: add DL_FIELDS_INFO.CALC_BODY, create DL_LAYOUT_EVENTS,
/// create DL_EXCEPTIONS, FIELD_KIND 2 for N ISCALCULATED rows, user_version 2`.</returns>
/// <exception cref="ERepoError">The file is missing.</exception>
/// <exception cref="ERepoSchemaError">The file is not a schema-1 or schema-2 repository.</exception>
/// <remarks>An apply first writes `&lt;repo&gt;.before-migrate-&lt;yyyymmdd-hhnnss&gt;.txt` (the schema-1 text
/// backup), then runs ONE transaction: ALTER TABLE ADD COLUMN CALC_BODY, the two CREATE TABLEs, the FIELD_KIND
/// update, user_version 2 and DL_META schema_version 2; a failure rolls everything back.</remarks>
function MigrateRepository(const pFileName: string; pApply: Boolean): TFrMigrateResult;

implementation

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.TextBackup;

const
  PLAN_FMT = 'v1 -> v2: add DL_FIELDS_INFO.CALC_BODY, DOMAIN_NAME, CHAR_LENGTH, create DL_LAYOUT_EVENTS, ' +
    'DL_EXCEPTIONS, DL_DOMAINS, DL_CONSTRAINTS, DL_CONSTRAINT_COLUMNS, DL_GENERATORS, ' +
    'FIELD_KIND 2 for %d ISCALCULATED rows, user_version 2';
  CALC_ROWS_SQL = 'SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "ISCALCULATED" = 1 AND ("FIELD_KIND" IS NULL OR "FIELD_KIND" = 1)';

{ The v2-only columns of DL_FIELDS_INFO and the v2-only tables are derived from the two table sets, so a column
  or table a lane adds to v2 (FR-SCHEMA: DOMAIN_NAME, CHAR_LENGTH, the four schema tables) migrates with no edit here. }
function FindTable(const pTables: TArray<TRepoTable>; const pName: string; out pTable: TRepoTable): Boolean;
var
  VTable: TRepoTable;
begin
  for VTable in pTables do
    if SameText(VTable.Name, pName) then
    begin
      pTable := VTable;
      Exit(True);
    end;
  pTable := Default(TRepoTable);
  Result := False;
end;

procedure AddV2Columns(pConn: TFDConnection);
var
  VCol, VOldCol: TRepoColumn;
  VNew, VOld: TRepoTable;
begin
  FindTable(RepoTablesFor(2), 'DL_FIELDS_INFO', VNew);
  FindTable(RepoTablesFor(1), 'DL_FIELDS_INFO', VOld);
  for VCol in VNew.Columns do
    if not VOld.FindColumn(VCol.Name, VOldCol) then
      pConn.ExecSQL('ALTER TABLE "DL_FIELDS_INFO" ADD COLUMN ' + ColumnDdl(VCol, False));
end;

procedure ApplyMigration(pConn: TFDConnection);
var
  VTable, VOld: TRepoTable;
begin
  pConn.StartTransaction;
  try
    AddV2Columns(pConn);
    for VTable in RepoTablesFor(2) do
      if not FindTable(RepoTablesFor(1), VTable.Name, VOld) then
        pConn.ExecSQL(RepoTableDdl(VTable));
    pConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "FIELD_KIND" = 2 WHERE "ISCALCULATED" = 1 AND ("FIELD_KIND" IS NULL OR "FIELD_KIND" = 1)');
    SetRepoMeta(pConn, 'schema_version', '2');
    pConn.ExecSQL('PRAGMA user_version = 2');
    pConn.Commit;
  except
    pConn.Rollback;
    raise;
  end;
end;

function MigrateRepository(const pFileName: string; pApply: Boolean): TFrMigrateResult;
var
  VConn: TFDConnection;
begin
  Result := Default(TFrMigrateResult);
  VConn := OpenRepository(pFileName, not pApply);
  try
    if RepoSchemaVersion(VConn) >= 2 then
    begin
      Result.AlreadyCurrent := True;
      Exit;
    end;
    Result.CalcRows := Integer(VConn.ExecSQLScalar(CALC_ROWS_SQL));
    Result.Plan := Format(PLAN_FMT, [Result.CalcRows]);
    if not pApply then
      Exit;
    Result.BackupFile := pFileName + '.before-migrate-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.txt';
    BackupRepository(VConn, Result.BackupFile);
    ApplyMigration(VConn);
    Result.Applied := True;
  finally
    VConn.Free;
  end;
end;

end.
