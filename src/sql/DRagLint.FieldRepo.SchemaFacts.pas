unit DRagLint.FieldRepo.SchemaFacts;

{ drag-lint 1.53 -- lane FR-SCHEMA: read API over the schema facts a field repository holds
  (design 2026-11-22-field-repository-v2-design.md section 5). Used by schema-aware lint and the
  generators. Read-only: nothing here writes; the facts are written by the DB-to-repository
  change set (DRagLint.FieldRepo.SchemaSeed). API FROZEN in the first FR-SCHEMA commit. }

interface

uses
  FireDAC.Comp.Client;

type
  /// <summary>Where and when the schema facts of a repository were read.</summary>
  TSchemaInfo = record
    /// <summary>UTC ISO-8601 time of the last applied schema read; '' when none.</summary>
    ReadAtUtc: string;
    /// <summary>'live' (Firebird RDB$ tables) or 'ddl' (offline DDL file); '' when none.</summary>
    Source: string;
    /// <summary>The Database value of the source connection (never a password); '' when none.</summary>
    Database: string;
  end;

/// <summary>True when schema facts were ever applied to the repository.</summary>
/// <param name="pRepo">An open repository connection (any schema version).</param>
/// <returns>False on a schema-1 repository and on a v2 repository that never had a schema read applied.</returns>
/// <remarks>Read-only; the test is DL_META schema_read_at_utc, so a repository whose schema read legitimately
/// found zero tables still reports True.</remarks>
function HasSchema(pRepo: TFDConnection): Boolean;

/// <summary>The provenance of the schema facts.</summary>
/// <param name="pRepo">An open repository connection.</param>
/// <returns>A record with empty strings when no schema was applied.</returns>
function SchemaInfo(pRepo: TFDConnection): TSchemaInfo;

/// <summary>Declared character length of a column.</summary>
/// <param name="pRepo">An open repository connection.</param>
/// <param name="pTable">Table name (case-insensitive).</param>
/// <param name="pColumn">Column name (case-insensitive).</param>
/// <returns>The field's own CHAR_LENGTH, else its domain's CHAR_LENGTH, else -1 (unknown, or not a
/// character column, or no schema facts).</returns>
function ColumnCharLength(pRepo: TFDConnection; const pTable, pColumn: string): Integer;

/// <summary>Primary key columns of a table, in key order.</summary>
/// <param name="pRepo">An open repository connection.</param>
/// <param name="pTable">Table name (case-insensitive).</param>
/// <returns>The column names; an empty array when the table has no primary key or no schema facts.</returns>
function PrimaryKey(pRepo: TFDConnection; const pTable: string): TArray<string>;  // dl:ok unused-public-symbol@db9b -- REVIEWED 2026-11-22 FR-SCHEMA: public API of the schema-in-repository feature: used by the CLI / tests / lane FR-LINT, outside this project index

implementation

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Stan.Param,
  DRagLint.FieldRepo.Schema;

const
  META_READ_AT = 'schema_read_at_utc';
  META_SOURCE = 'schema_source';
  META_DATABASE = 'schema_database';
  CHAR_LENGTH_UNKNOWN = -1;
  SQL_FIELD_LEN =
    'SELECT F."CHAR_LENGTH", D."CHAR_LENGTH" FROM "DL_FIELDS_INFO" F ' +
    'LEFT JOIN "DL_DOMAINS" D ON D."DOMAIN_NAME" = F."DOMAIN_NAME" ' +
    'WHERE UPPER(F."TABLE_NAME") = UPPER(:T) AND UPPER(F."FIELD_NAME") = UPPER(:F)';
  SQL_PK =
    'SELECT CC."COLUMN_NAME" FROM "DL_CONSTRAINTS" C ' +
    'JOIN "DL_CONSTRAINT_COLUMNS" CC ON CC."CONSTRAINT_NAME" = C."CONSTRAINT_NAME" ' +
    'WHERE UPPER(C."TABLE_NAME") = UPPER(:T) AND C."KIND" = ''PK'' ORDER BY CC."POSITION"';

function IsV2(pRepo: TFDConnection): Boolean;
begin
  Result := RepoSchemaVersion(pRepo) >= 2;
end;

function HasSchema(pRepo: TFDConnection): Boolean;
begin
  Result := IsV2(pRepo) and (GetRepoMeta(pRepo, META_READ_AT) <> '');
end;

function SchemaInfo(pRepo: TFDConnection): TSchemaInfo;
begin
  Result := Default(TSchemaInfo);
  if not IsV2(pRepo) then
    Exit;
  Result.ReadAtUtc := GetRepoMeta(pRepo, META_READ_AT);
  Result.Source := GetRepoMeta(pRepo, META_SOURCE);
  Result.Database := GetRepoMeta(pRepo, META_DATABASE);
end;

function ColumnCharLength(pRepo: TFDConnection; const pTable, pColumn: string): Integer;
var
  VQuery: TFDQuery;
begin
  Result := CHAR_LENGTH_UNKNOWN;
  if not IsV2(pRepo) then
    Exit;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_FIELD_LEN, [pTable, pColumn]);
    if VQuery.Eof then
      Exit;
    if not VQuery.Fields[0].IsNull then
      Result := VQuery.Fields[0].AsInteger
    else if not VQuery.Fields[1].IsNull then
      Result := VQuery.Fields[1].AsInteger;
  finally
    VQuery.Free;
  end;
end;

function PrimaryKey(pRepo: TFDConnection; const pTable: string): TArray<string>;
var
  VQuery: TFDQuery;
begin
  Result := nil;
  if not IsV2(pRepo) then
    Exit;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_PK, [pTable]);
    while not VQuery.Eof do
    begin
      Result := Result + [VQuery.Fields[0].AsString];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

end.
