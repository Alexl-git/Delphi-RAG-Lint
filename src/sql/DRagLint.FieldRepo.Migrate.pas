unit DRagLint.FieldRepo.Migrate;

{ drag-lint 1.53 -- lane FR-MODEL, 1.54 -- lane EVCOLS, 1.55 -- lane XTABLE, 1.56 -- lane GC-S: `repo migrate`, a repository
  file of schema 1, 2, 3 or 4 to the current schema 5 (design 2026-11-22-field-repository-v2-design.md section 4.7, rulings
  2026-11-23 R2 / R5 / R6; schema 4: 2026-11-26-cross-table-fields-design.md 2.3; schema 5: plan 2026-11-27-v156-plan.md
  GRIDCOL2 and 2026-11-27-derived-field-lineage-design.md section 3).
  No table, column or value is dropped or renamed; event code of layout type Field moves into the event columns. }

interface

type
  /// <summary>What a migration did (or, for a dry run, would do).</summary>
  TFrMigrateResult = record
    /// <summary>True when the file was at the current schema already; nothing else is set then.</summary>
    AlreadyCurrent: Boolean;
    /// <summary>ISCALCULATED rows whose FIELD_KIND is NULL or 1; they get FIELD_KIND 2. Schema 1 only, else 0.</summary>
    CalcRows: Integer;
    /// <summary>Rows with ALIGNMENT -2 (TableTools: not set); they get NULL.</summary>
    AlignmentRows: Integer;
    /// <summary>DL_LAYOUT_EVENTS rows of layout type Field that move into the event columns.</summary>
    EventRows: Integer;
    /// <summary>True when the change was written (apply), False for a dry run.</summary>
    Applied: Boolean;
    /// <summary>The before-migrate backup file written by an apply; '' otherwise.</summary>
    BackupFile: string;
    /// <summary>The plan line of the dry run (also set after an apply).</summary>
    Plan: string;
  end;

/// <summary>Plans or applies the migration of a repository file to REPO_SCHEMA_VERSION.</summary>
/// <param name="pFileName">Repository file.</param>
/// <param name="pApply">False = dry run (the file is opened read-only and not a byte changes); True = write.</param>
/// <returns>The result; Plan reads `v4 -> v5: add DL_FIELDS_INFO.NOTES, DERIVED_KIND, add DL_GRID_COLUMNS.PROPERTIES_CLASS_NAME,
/// PROPERTIES, ALIGNMENT -2 to NULL in N rows, user_version 5`; from schema 3 also `create DL_RELATIONS, DL_RELATION_COLUMNS,
/// DL_FIELD_INPUTS`; from schema 2 also the event columns, `create DL_GRID_COLUMNS, ...` (a table the old schema lacks is
/// created whole, never altered) and `move N Field events into columns`; from schema 1 also the schema-2 tables and
/// columns and FIELD_KIND 2. One `add` per table that gets columns, in table order; `create` is left out when no table
/// is new.</returns>
/// <exception cref="ERepoError">The file is missing.</exception>
/// <exception cref="ERepoSchemaError">The file is not a repository of a known schema.</exception>
/// <remarks>An apply first writes `&lt;repo&gt;.before-migrate-&lt;yyyymmdd-hhnnss&gt;.txt` (the text backup in the file's old
/// schema), then runs ONE transaction: every ALTER TABLE ADD COLUMN and CREATE TABLE, the row updates, user_version and
/// DL_META schema_version; a failure rolls everything back. A Field event whose field row does not exist, or whose event
/// has no column, stays in DL_LAYOUT_EVENTS (`repo check` reports it).</remarks>
function MigrateRepository(const pFileName: string; pApply: Boolean): TFrMigrateResult;

implementation

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.TextBackup;

const
  KIND_VERSION = 2; // the schema that introduced FIELD_KIND 2 for ISCALCULATED rows
  EVENTS_VERSION = 3; // the schema whose event columns took the Field events of DL_LAYOUT_EVENTS

{ New columns and tables are derived from the two table sets, so one that a lane adds to a schema migrates with no edit
  here. }
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

{ The tables schema pFrom already has that get columns: each with ONLY the columns the current schema adds, in the
  table order of the current schema. }
function AlteredTables(pFrom: Integer): TArray<TRepoTable>;
var
  VCol, VOldCol: TRepoColumn;
  VNew, VOld, VAdd: TRepoTable;
  VOldTables: TArray<TRepoTable>;
begin
  Result := nil;
  VOldTables := RepoTablesFor(pFrom);
  for VNew in RepoTablesFor(REPO_SCHEMA_VERSION) do
  begin
    if not FindTable(VOldTables, VNew.Name, VOld) then
      Continue;
    VAdd := VNew;
    VAdd.Columns := nil;
    for VCol in VNew.Columns do
      if not VOld.FindColumn(VCol.Name, VOldCol) then
        VAdd.Columns := VAdd.Columns + [VCol];
    if VAdd.Columns <> nil then
      Result := Result + [VAdd];
  end;
end;

function NewTables(pFrom: Integer): TArray<TRepoTable>;
var
  VTable, VOld: TRepoTable;
begin
  Result := nil;
  for VTable in RepoTablesFor(REPO_SCHEMA_VERSION) do
    if not FindTable(RepoTablesFor(pFrom), VTable.Name, VOld) then
      Result := Result + [VTable];
end;

procedure ApplyMigration(pConn: TFDConnection; pFrom: Integer);
var
  VTable: TRepoTable;
  VCol: TRepoColumn;
begin
  pConn.StartTransaction;
  try
    for VTable in AlteredTables(pFrom) do
      for VCol in VTable.Columns do
        pConn.ExecSQL('ALTER TABLE ' + QuoteRepoIdent(VTable.Name) + ' ADD COLUMN ' + ColumnDdl(VCol, False));
    for VTable in NewTables(pFrom) do
      pConn.ExecSQL(RepoTableDdl(VTable));
    MigrateRepoRows(pConn, pFrom);
    pConn.ExecSQL('PRAGMA user_version = ' + IntToStr(REPO_SCHEMA_VERSION));
    pConn.Commit;
  except
    pConn.Rollback;
    raise;
  end;
end;

function PlanText(pFrom: Integer; const pResult: TFrMigrateResult): string;
var
  VCol: TRepoColumn;
  VTable: TRepoTable;
  VColumns, VTables: TArray<string>;
begin
  Result := Format('v%d -> v%d: ', [pFrom, REPO_SCHEMA_VERSION]);
  for VTable in AlteredTables(pFrom) do
  begin
    VColumns := nil;
    for VCol in VTable.Columns do
      VColumns := VColumns + [VCol.Name];
    Result := Result + Format('add %s.%s, ', [VTable.Name, string.Join(', ', VColumns)]);  // dl:ok concat-in-loop@00a4 -- REVIEWED 2026-11-26 GC-S: one piece per altered table (two in schema 5); a TStringBuilder adds nothing
  end;
  VTables := nil;
  for VTable in NewTables(pFrom) do
    VTables := VTables + [VTable.Name];
  if VTables <> nil then
    Result := Result + Format('create %s, ', [string.Join(', ', VTables)]);
  if pFrom < KIND_VERSION then
    Result := Result + Format('FIELD_KIND 2 for %d ISCALCULATED rows, ', [pResult.CalcRows]);
  Result := Result + Format('ALIGNMENT -2 to NULL in %d rows, ', [pResult.AlignmentRows]);
  if (pFrom >= KIND_VERSION) and (pFrom < EVENTS_VERSION) then
    Result := Result + Format('move %d Field events into columns, ', [pResult.EventRows]);
  Result := Result + Format('user_version %d', [REPO_SCHEMA_VERSION]);
end;

function MigrateRepository(const pFileName: string; pApply: Boolean): TFrMigrateResult;
var
  VConn: TFDConnection;
  VFrom: Integer;
  VRows: TRepoRowChanges;
begin
  Result := Default(TFrMigrateResult);
  VConn := OpenRepository(pFileName, not pApply);
  try
    VFrom := RepoSchemaVersion(VConn);
    if VFrom >= REPO_SCHEMA_VERSION then
    begin
      Result.AlreadyCurrent := True;
      Exit;
    end;
    VRows := CountRepoRowChanges(VConn, VFrom);
    Result.CalcRows := VRows.CalcRows;
    Result.AlignmentRows := VRows.AlignmentRows;
    Result.EventRows := VRows.EventRows;
    Result.Plan := PlanText(VFrom, Result);
    if not pApply then
      Exit;
    Result.BackupFile := pFileName + '.before-migrate-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.txt';
    BackupRepository(VConn, Result.BackupFile);
    ApplyMigration(VConn, VFrom);
    Result.Applied := True;
  finally
    VConn.Free;
  end;
end;

end.
