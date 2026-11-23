unit DRagLint.FieldRepo.AlterFacts;

{ drag-lint 1.54 -- lane TT-ALTER: the repository side of one table for the per-table ALTER. Read-only. }

interface

uses
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Alter;

/// <summary>Reads what the repository holds about one table.</summary>
/// <param name="pRepo">An open repository connection.</param>
/// <param name="pTable">Table name (case-insensitive).</param>
/// <returns>The facts; Found = False when no data column row exists.</returns>
/// <exception cref="EFrAlterError">The repository is schema 1 or holds no schema facts.</exception>
/// <remarks>Data columns are the rows with FIELD_KIND NULL / 1 that are neither calculated nor lookup. CHAR_LENGTH is
/// the length of a character column; STRING_SIZE stands in when CHAR_LENGTH is NULL; two different values mark the
/// row inconsistent.</remarks>
function ReadRepoTable(pRepo: TFDConnection; const pTable: string): TFrRepoTable;

implementation

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Stan.Param,
  DRagLint.FieldRepo.DbProvider,
  DRagLint.FieldRepo.SchemaFacts;

const
  F_NAME = 0;
  F_DOMAIN = 1;
  F_TYPE = 2;
  F_SUB = 3;
  F_LENGTH = 4;
  F_SCALE = 5;
  F_CHARS = 6;
  F_STRING_SIZE = 7;
  F_NULL_FLAG = 8;
  F_DEFAULT = 9;
  F_IS_DATA = 10;
  SQL_COLUMNS =
    'SELECT TRIM("FIELD_NAME"), TRIM(COALESCE("DOMAIN_NAME", '''')), "FIELD_TYPE", COALESCE("FIELD_SUBTYPE", 0), ' +
    'COALESCE("FIELD_LENGTH", 0), COALESCE("FIELD_SCALE", 0), COALESCE("CHAR_LENGTH", 0), COALESCE("STRING_SIZE", 0), ' +
    'COALESCE("NULL_FLAG", 0), COALESCE("DEFAULTVAL", ''''), ' +
    'CASE WHEN ("FIELD_KIND" IS NULL OR "FIELD_KIND" = 1) AND "ISCALCULATED" = 0 AND "ISLOOKUP" = 0 THEN 1 ELSE 0 END ' +
    'FROM "DL_FIELDS_INFO" WHERE UPPER(TRIM("TABLE_NAME")) = :T ORDER BY "FIELD_NAME"';
  D_NAME = 0;
  D_TYPE = 1;
  D_SUB = 2;
  D_LENGTH = 3;
  D_CHARS = 4;
  D_SCALE = 5;
  D_PRECISION = 6;
  D_NULL_FLAG = 7;
  D_DEFAULT = 8;
  D_CHECK = 9;
  D_CHARSET = 10;
  SQL_DOMAINS =
    'SELECT TRIM("DOMAIN_NAME"), "FIELD_TYPE", COALESCE("FIELD_SUBTYPE", 0), COALESCE("FIELD_LENGTH", 0), ' +
    'COALESCE("CHAR_LENGTH", 0), COALESCE("FIELD_SCALE", 0), COALESCE("FIELD_PRECISION", 0), COALESCE("NULL_FLAG", 0), ' +
    'COALESCE("DEFAULT_SOURCE", ''''), COALESCE("CHECK_SOURCE", ''''), COALESCE("CHARSET", '''') ' +
    'FROM "DL_DOMAINS" ORDER BY 1';

function ReadColumn(pQuery: TFDQuery): TFrRepoColumn;
var
  VChars, VStringSize: Integer;
begin
  Result := Default(TFrRepoColumn);
  Result.Name := pQuery.Fields[F_NAME].AsString.ToUpper;
  Result.DomainName := pQuery.Fields[F_DOMAIN].AsString;
  Result.DataType.FieldType := pQuery.Fields[F_TYPE].AsInteger;
  Result.DataType.SubType := pQuery.Fields[F_SUB].AsInteger;
  Result.DataType.ByteLength := pQuery.Fields[F_LENGTH].AsInteger;
  Result.DataType.Scale := pQuery.Fields[F_SCALE].AsInteger;
  VChars := pQuery.Fields[F_CHARS].AsInteger;
  VStringSize := pQuery.Fields[F_STRING_SIZE].AsInteger;
  Result.DataType.CharLength := if VChars > 0 then VChars else VStringSize;
  if (VChars > 0) and (VStringSize > 0) and (VChars <> VStringSize) then
    Result.Inconsistent := Format('CHAR_LENGTH %d and STRING_SIZE %d disagree', [VChars, VStringSize]);
  Result.NotNull := pQuery.Fields[F_NULL_FLAG].AsInteger <> 0;
  Result.DefaultValue := Trim(pQuery.Fields[F_DEFAULT].AsString);
end;

function ReadDomains(pRepo: TFDConnection): TArray<TFrDomainFacts>;
var
  VQuery: TFDQuery;
  VItem: TFrDomainFacts;
begin
  Result := nil;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_DOMAINS);
    while not VQuery.Eof do
    begin
      VItem := Default(TFrDomainFacts);
      VItem.Name := VQuery.Fields[D_NAME].AsString;
      VItem.DataType.FieldType := VQuery.Fields[D_TYPE].AsInteger;
      VItem.DataType.SubType := VQuery.Fields[D_SUB].AsInteger;
      VItem.DataType.ByteLength := VQuery.Fields[D_LENGTH].AsInteger;
      VItem.DataType.CharLength := VQuery.Fields[D_CHARS].AsInteger;
      VItem.DataType.Scale := VQuery.Fields[D_SCALE].AsInteger;
      VItem.DataType.Precision := VQuery.Fields[D_PRECISION].AsInteger;
      VItem.DataType.Charset := Trim(VQuery.Fields[D_CHARSET].AsString);
      VItem.NotNull := VQuery.Fields[D_NULL_FLAG].AsInteger <> 0;
      VItem.DefaultSource := Trim(VQuery.Fields[D_DEFAULT].AsString);
      VItem.CheckSource := Trim(VQuery.Fields[D_CHECK].AsString);
      Result := Result + [VItem];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function ReadRepoTable(pRepo: TFDConnection; const pTable: string): TFrRepoTable;
var
  VQuery: TFDQuery;
  VColumn: TFrRepoColumn;
begin
  if not HasSchema(pRepo) then
    raise EFrAlterError.Create('the repository holds no schema facts (run repo migrate / repo refresh-schema first)');
  Result := Default(TFrRepoTable);
  Result.TableName := pTable.ToUpper;
  Result.SchemaReadAtUtc := SchemaInfo(pRepo).ReadAtUtc;
  Result.SchemaDatabase := SchemaInfo(pRepo).Database;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_COLUMNS, [Result.TableName]);
    while not VQuery.Eof do
    begin
      VColumn := ReadColumn(VQuery);
      if VQuery.Fields[F_IS_DATA].AsInteger = 1 then
        Result.Columns := Result.Columns + [VColumn]
      else
        Result.OtherRows := Result.OtherRows + [VColumn.Name];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
  Result.Found := Length(Result.Columns) > 0;
  Result.Domains := ReadDomains(pRepo);
end;

end.
