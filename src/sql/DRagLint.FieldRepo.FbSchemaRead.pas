unit DRagLint.FieldRepo.FbSchemaRead;

{ drag-lint 1.53 -- lane FR-SCHEMA: the schema model of a Firebird database (domains, columns, constraints,
  generators) and its LIVE reader (design 2026-11-22-field-repository-v2-design.md section 5).

  The five RDB$ result sets arrive as datasets (TFbSchemaSources), so the reader runs on TFDMemTable in the
  tests and on live queries (OpenFbSchemaSources) in the CLI. Firebird is only READ: the live queries run in
  a read-only transaction. The offline twin that fills the same model from a DDL file is DRagLint.FieldRepo.FbDdl. }

interface

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client;

type
  /// <summary>One user domain (RDB$FIELDS row whose name is not RDB$-generated).</summary>
  TFbDomain = record
    Name: string;
    FieldType: Integer;
    SubType: Integer;
    FieldLength: Integer;
    /// <summary>Declared character length; 0 when the type is not a character type.</summary>
    CharLength: Integer;
    Scale: Integer;
    Precision: Integer;
    NullFlag: Integer;
    DefaultSource: string;
    CheckSource: string;
    Charset: string;
  end;

  /// <summary>One column of a user table.</summary>
  TFbColumn = record
    TableName: string;
    ColumnName: string;
    /// <summary>The user domain the column is declared with; '' for an inline type.</summary>
    DomainName: string;
    FieldType: Integer;
    SubType: Integer;
    FieldLength: Integer;
    /// <summary>Declared character length; 0 when the type is not a character type.</summary>
    CharLength: Integer;
    Scale: Integer;
    NullFlag: Integer;
    /// <summary>Firebird's source text, e.g. 'DEFAULT 0'; '' when none.</summary>
    DefaultSource: string;
  end;

  /// <summary>One PRIMARY KEY / UNIQUE / FOREIGN KEY / CHECK constraint with its ordered columns.</summary>
  TFbConstraint = record
    Name: string;
    TableName: string;
    /// <summary>'PK', 'UNIQUE', 'FK' or 'CHECK'.</summary>
    Kind: string;
    RefTable: string;
    RefConstraint: string;
    UpdateRule: string;
    DeleteRule: string;
    /// <summary>Key columns in key order (position 1 first).</summary>
    Columns: TArray<string>;
  end;

  /// <summary>Everything the repository stores about a database's schema.</summary>
  TFbSchemaModel = record
    /// <summary>'live' or 'ddl'.</summary>
    Source: string;
    /// <summary>The Database value of the connection, or the DDL file list; never a password.</summary>
    Database: string;
    Domains: TArray<TFbDomain>;
    Columns: TArray<TFbColumn>;
    Constraints: TArray<TFbConstraint>;
    Generators: TArray<string>;
  end;

  /// <summary>The five result sets the live reader consumes; column names in the unit remarks.</summary>
  TFbSchemaSources = record
    Domains: TDataSet;
    Columns: TDataSet;
    Constraints: TDataSet;
    ConstraintColumns: TDataSet;
    Generators: TDataSet;
  end;

  /// <summary>Raised when a result set lacks a column the reader needs.</summary>
  EFbSchemaReadError = class(Exception);

/// <summary>Builds the schema model from the five result sets.</summary>
/// <param name="pSources">Datasets with these columns. Domains: DOMAIN_NAME, FIELD_TYPE, FIELD_SUB_TYPE,
/// FIELD_LENGTH, CHAR_LENGTH, FIELD_SCALE, FIELD_PRECISION, NULL_FLAG, DEFAULT_SOURCE, CHECK_SOURCE, CHARSET.
/// Columns: TABLE_NAME, FIELD_NAME, DOMAIN_NAME, FIELD_TYPE, FIELD_SUB_TYPE, FIELD_LENGTH, CHARACTER_LEN,
/// FIELD_SCALE, NULL_FLAG, DEFAULT_SOURCE. Constraints: CONSTRAINT_NAME, TABLE_NAME, KIND, REF_TABLE,
/// REF_CONSTRAINT, UPDATE_RULE, DELETE_RULE. ConstraintColumns: CONSTRAINT_NAME, POSITION, COLUMN_NAME.
/// Generators: GENERATOR_NAME.</param>
/// <param name="pSource">The Source value to stamp ('live').</param>
/// <param name="pDatabase">The Database value to stamp; the caller strips any password.</param>
/// <returns>The model, every list sorted by name (columns by table then name) so the result is deterministic.</returns>
/// <exception cref="EFbSchemaReadError">A dataset is nil or lacks a named column.</exception>
/// <remarks>Names are trimmed (RDB$ names are CHAR-padded). Datasets are read once, front to back.</remarks>
function ReadSchemaModel(const pSources: TFbSchemaSources; const pSource, pDatabase: string): TFbSchemaModel;

/// <summary>Sorts every list of a model by name (columns by table, then name) so two reads of the same schema compare equal.</summary>
/// <param name="pModel">The model to sort in place.</param>
procedure SortSchemaModel(var pModel: TFbSchemaModel);

/// <summary>The Database value of a FireDAC-style connection string: the only part of it that is ever stored.</summary>
/// <param name="pConnection">'Database=..;User_Name=..;Password=..' pairs separated by ';'.</param>
/// <returns>The Database value, trimmed; '' when the string has none. User, password and every other pair are dropped.</returns>
function DatabaseOfConnection(const pConnection: string): string;

/// <summary>Opens the five result sets on a live Firebird connection, read only.</summary>
/// <param name="pFb">An open Firebird connection; its transaction is switched to read only.</param>
/// <returns>Open, fully fetched datasets; release with FreeFbSchemaSources.</returns>
function OpenFbSchemaSources(pFb: TFDConnection): TFbSchemaSources;

/// <summary>Frees the datasets of a TFbSchemaSources.</summary>
/// <param name="pSources">The record to release; its fields are nil afterwards.</param>
procedure FreeFbSchemaSources(var pSources: TFbSchemaSources);

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  FireDAC.Stan.Option;

const
  SQL_DOMAINS =
    'SELECT TRIM(F.RDB$FIELD_NAME) AS DOMAIN_NAME, F.RDB$FIELD_TYPE AS FIELD_TYPE, ' +
    'F.RDB$FIELD_SUB_TYPE AS FIELD_SUB_TYPE, F.RDB$FIELD_LENGTH AS FIELD_LENGTH, ' +
    'F.RDB$CHARACTER_LENGTH AS "CHAR_LENGTH", F.RDB$FIELD_SCALE AS FIELD_SCALE, ' +
    'F.RDB$FIELD_PRECISION AS FIELD_PRECISION, F.RDB$NULL_FLAG AS NULL_FLAG, ' +
    'F.RDB$DEFAULT_SOURCE AS DEFAULT_SOURCE, F.RDB$VALIDATION_SOURCE AS CHECK_SOURCE, ' +
    'TRIM(CS.RDB$CHARACTER_SET_NAME) AS CHARSET ' +
    'FROM RDB$FIELDS F LEFT JOIN RDB$CHARACTER_SETS CS ON CS.RDB$CHARACTER_SET_ID = F.RDB$CHARACTER_SET_ID ' +
    'WHERE F.RDB$FIELD_NAME NOT STARTING WITH ''RDB$'' AND (F.RDB$SYSTEM_FLAG IS NULL OR F.RDB$SYSTEM_FLAG = 0) ' +
    'ORDER BY 1';
  { identical column list to the TableTools field query (DRagLint.FieldRepo.SchemaSeed), plus DOMAIN_NAME }
  SQL_COLUMNS =
    'SELECT TRIM(F.RDB$RELATION_NAME) AS TABLE_NAME, TRIM(F.RDB$FIELD_NAME) AS FIELD_NAME, ' +
    'CASE WHEN F.RDB$FIELD_SOURCE STARTING WITH ''RDB$'' THEN '''' ELSE TRIM(F.RDB$FIELD_SOURCE) END AS DOMAIN_NAME, ' +
    'COALESCE(F.RDB$DEFAULT_SOURCE, L.RDB$DEFAULT_SOURCE) AS DEFAULT_SOURCE, L.RDB$FIELD_LENGTH AS FIELD_LENGTH, ' +
    'L.RDB$FIELD_TYPE AS FIELD_TYPE, L.RDB$FIELD_SUB_TYPE AS FIELD_SUB_TYPE, ' +
    'CASE WHEN F.RDB$NULL_FLAG = 1 OR L.RDB$NULL_FLAG = 1 THEN 1 ELSE 0 END AS NULL_FLAG, L.RDB$CHARACTER_LENGTH AS CHARACTER_LEN, ' +
    'L.RDB$FIELD_SCALE AS FIELD_SCALE ' +
    'FROM RDB$RELATION_FIELDS F ' +
    'INNER JOIN RDB$RELATIONS R ON F.RDB$RELATION_NAME = R.RDB$RELATION_NAME ' +
    'AND R.RDB$VIEW_BLR IS NULL AND (R.RDB$SYSTEM_FLAG IS NULL OR R.RDB$SYSTEM_FLAG = 0) ' +
    'INNER JOIN RDB$FIELDS L ON L.RDB$FIELD_NAME = F.RDB$FIELD_SOURCE ' +
    'ORDER BY 1, F.RDB$FIELD_POSITION';
  SQL_CONSTRAINTS =
    'SELECT TRIM(RC.RDB$CONSTRAINT_NAME) AS CONSTRAINT_NAME, TRIM(RC.RDB$RELATION_NAME) AS TABLE_NAME, ' +
    'CASE RC.RDB$CONSTRAINT_TYPE WHEN ''PRIMARY KEY'' THEN ''PK'' WHEN ''UNIQUE'' THEN ''UNIQUE'' ' +
    'WHEN ''FOREIGN KEY'' THEN ''FK'' ELSE ''CHECK'' END AS KIND, ' +
    '(SELECT TRIM(U.RDB$RELATION_NAME) FROM RDB$RELATION_CONSTRAINTS U ' +
    'WHERE U.RDB$CONSTRAINT_NAME = RF.RDB$CONST_NAME_UQ) AS REF_TABLE, ' +
    'TRIM(RF.RDB$CONST_NAME_UQ) AS REF_CONSTRAINT, TRIM(RF.RDB$UPDATE_RULE) AS UPDATE_RULE, ' +
    'TRIM(RF.RDB$DELETE_RULE) AS DELETE_RULE ' +
    'FROM RDB$RELATION_CONSTRAINTS RC ' +
    'LEFT JOIN RDB$REF_CONSTRAINTS RF ON RF.RDB$CONSTRAINT_NAME = RC.RDB$CONSTRAINT_NAME ' +
    'WHERE RC.RDB$CONSTRAINT_TYPE IN (''PRIMARY KEY'', ''UNIQUE'', ''FOREIGN KEY'', ''CHECK'') ' +
    'AND RC.RDB$RELATION_NAME NOT STARTING WITH ''RDB$'' AND RC.RDB$RELATION_NAME NOT STARTING WITH ''MON$'' ' +
    'AND RC.RDB$RELATION_NAME NOT STARTING WITH ''SEC$'' ORDER BY 1';
  SQL_CONSTRAINT_COLUMNS =
    'SELECT TRIM(RC.RDB$CONSTRAINT_NAME) AS CONSTRAINT_NAME, SG.RDB$FIELD_POSITION + 1 AS "POSITION", ' +
    'TRIM(SG.RDB$FIELD_NAME) AS COLUMN_NAME ' +
    'FROM RDB$RELATION_CONSTRAINTS RC INNER JOIN RDB$INDEX_SEGMENTS SG ON SG.RDB$INDEX_NAME = RC.RDB$INDEX_NAME ' +
    'WHERE RC.RDB$CONSTRAINT_TYPE IN (''PRIMARY KEY'', ''UNIQUE'', ''FOREIGN KEY'') ORDER BY 1, 2';
  SQL_GENERATORS =
    'SELECT TRIM(RDB$GENERATOR_NAME) AS GENERATOR_NAME FROM RDB$GENERATORS ' +
    'WHERE RDB$SYSTEM_FLAG IS NULL OR RDB$SYSTEM_FLAG = 0 ORDER BY 1';

type
  TKeyColumn = record
    Position: Integer;
    Name: string;
  end;

procedure RequireColumns(pData: TDataSet; const pRole: string; const pNames: array of string);
var
  VMissing, VName: string;
begin
  if pData = nil then
    raise EFbSchemaReadError.CreateFmt('Schema source %s is missing', [pRole]);
  VMissing := '';
  for VName in pNames do
    if pData.FindField(VName) = nil then
      VMissing := VMissing + (if VMissing = '' then '' else ', ') + VName;
  if VMissing <> '' then
    raise EFbSchemaReadError.CreateFmt('Schema source %s lacks column(s): %s', [pRole, VMissing]);
end;

function Txt(pField: TField): string;
begin
  Result := Trim(pField.AsString);
end;

function Num(pField: TField): Integer;
begin
  Result := pField.AsInteger;
end;

function ReadDomains(pData: TDataSet): TArray<TFbDomain>;
var
  VColDomainName: TField;
  VColFieldType: TField;
  VColFieldSubType: TField;
  VColFieldLength: TField;
  VColCharLength: TField;
  VColFieldScale: TField;
  VColFieldPrecision: TField;
  VColNullFlag: TField;
  VColDefaultSource: TField;
  VColCheckSource: TField;
  VColCharset: TField;
  VItem: TFbDomain;
  VList: TList<TFbDomain>;
begin
  RequireColumns(pData, 'Domains', ['DOMAIN_NAME', 'FIELD_TYPE', 'FIELD_SUB_TYPE', 'FIELD_LENGTH', 'CHAR_LENGTH',
    'FIELD_SCALE', 'FIELD_PRECISION', 'NULL_FLAG', 'DEFAULT_SOURCE', 'CHECK_SOURCE', 'CHARSET']);
  VColDomainName := pData.FieldByName('DOMAIN_NAME');
  VColFieldType := pData.FieldByName('FIELD_TYPE');
  VColFieldSubType := pData.FieldByName('FIELD_SUB_TYPE');
  VColFieldLength := pData.FieldByName('FIELD_LENGTH');
  VColCharLength := pData.FieldByName('CHAR_LENGTH');
  VColFieldScale := pData.FieldByName('FIELD_SCALE');
  VColFieldPrecision := pData.FieldByName('FIELD_PRECISION');
  VColNullFlag := pData.FieldByName('NULL_FLAG');
  VColDefaultSource := pData.FieldByName('DEFAULT_SOURCE');
  VColCheckSource := pData.FieldByName('CHECK_SOURCE');
  VColCharset := pData.FieldByName('CHARSET');
  VList := TList<TFbDomain>.Create;
  try
    pData.First;
    while not pData.Eof do
    begin
      VItem := Default(TFbDomain);
      VItem.Name := Txt(VColDomainName);
      VItem.FieldType := Num(VColFieldType);
      VItem.SubType := Num(VColFieldSubType);
      VItem.FieldLength := Num(VColFieldLength);
      VItem.CharLength := Num(VColCharLength);
      VItem.Scale := Num(VColFieldScale);
      VItem.Precision := Num(VColFieldPrecision);
      VItem.NullFlag := Num(VColNullFlag);
      VItem.DefaultSource := Trim(VColDefaultSource.AsString);
      VItem.CheckSource := Trim(VColCheckSource.AsString);
      VItem.Charset := Txt(VColCharset);
      VList.Add(VItem);
      pData.Next;
    end;
    Result := VList.ToArray;
  finally
    VList.Free;
  end;
end;

function ReadColumns(pData: TDataSet): TArray<TFbColumn>;
var
  VColTableName: TField;
  VColFieldName: TField;
  VColDomainName: TField;
  VColFieldType: TField;
  VColFieldSubType: TField;
  VColFieldLength: TField;
  VColCharacterLen: TField;
  VColFieldScale: TField;
  VColNullFlag: TField;
  VColDefaultSource: TField;
  VItem: TFbColumn;
  VList: TList<TFbColumn>;
begin
  RequireColumns(pData, 'Columns', ['TABLE_NAME', 'FIELD_NAME', 'DOMAIN_NAME', 'FIELD_TYPE', 'FIELD_SUB_TYPE',
    'FIELD_LENGTH', 'CHARACTER_LEN', 'FIELD_SCALE', 'NULL_FLAG', 'DEFAULT_SOURCE']);
  VColTableName := pData.FieldByName('TABLE_NAME');
  VColFieldName := pData.FieldByName('FIELD_NAME');
  VColDomainName := pData.FieldByName('DOMAIN_NAME');
  VColFieldType := pData.FieldByName('FIELD_TYPE');
  VColFieldSubType := pData.FieldByName('FIELD_SUB_TYPE');
  VColFieldLength := pData.FieldByName('FIELD_LENGTH');
  VColCharacterLen := pData.FieldByName('CHARACTER_LEN');
  VColFieldScale := pData.FieldByName('FIELD_SCALE');
  VColNullFlag := pData.FieldByName('NULL_FLAG');
  VColDefaultSource := pData.FieldByName('DEFAULT_SOURCE');
  VList := TList<TFbColumn>.Create;
  try
    pData.First;
    while not pData.Eof do
    begin
      VItem := Default(TFbColumn);
      VItem.TableName := Txt(VColTableName);
      VItem.ColumnName := Txt(VColFieldName);
      VItem.DomainName := Txt(VColDomainName);
      VItem.FieldType := Num(VColFieldType);
      VItem.SubType := Num(VColFieldSubType);
      VItem.FieldLength := Num(VColFieldLength);
      VItem.CharLength := Num(VColCharacterLen);
      VItem.Scale := Num(VColFieldScale);
      VItem.NullFlag := Num(VColNullFlag);
      VItem.DefaultSource := VColDefaultSource.AsString;
      VList.Add(VItem);
      pData.Next;
    end;
    Result := VList.ToArray;
  finally
    VList.Free;
  end;
end;

{ key columns per constraint name, ordered by POSITION }
function ReadKeyColumns(pData: TDataSet): TObjectDictionary<string, TList<TKeyColumn>>;
var
  VColConstraintName: TField;
  VColPosition: TField;
  VColColumnName: TField;
  VKey: TKeyColumn;
  VName: string;
  VList: TList<TKeyColumn>;
begin
  RequireColumns(pData, 'ConstraintColumns', ['CONSTRAINT_NAME', 'POSITION', 'COLUMN_NAME']);
  VColConstraintName := pData.FieldByName('CONSTRAINT_NAME');
  VColPosition := pData.FieldByName('POSITION');
  VColColumnName := pData.FieldByName('COLUMN_NAME');
  Result := TObjectDictionary<string, TList<TKeyColumn>>.Create([doOwnsValues]);
  try
    pData.First;
    while not pData.Eof do
    begin
      VName := Txt(VColConstraintName);
      VKey.Position := Num(VColPosition);
      VKey.Name := Txt(VColColumnName);
      if not Result.TryGetValue(VName, VList) then
      begin
        VList := TList<TKeyColumn>.Create;
        Result.Add(VName, VList);
      end;
      VList.Add(VKey);
      pData.Next;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function ReadConstraints(pData, pKeyData: TDataSet): TArray<TFbConstraint>;
var
  VColConstraintName: TField;
  VColTableName: TField;
  VColKind: TField;
  VColRefTable: TField;
  VColRefConstraint: TField;
  VColUpdateRule: TField;
  VColDeleteRule: TField;
  VItem: TFbConstraint;
  VList: TList<TFbConstraint>;
  VKeys: TObjectDictionary<string, TList<TKeyColumn>>;
  VCols: TList<TKeyColumn>;
  VCol: TKeyColumn;
begin
  RequireColumns(pData, 'Constraints', ['CONSTRAINT_NAME', 'TABLE_NAME', 'KIND', 'REF_TABLE', 'REF_CONSTRAINT',
    'UPDATE_RULE', 'DELETE_RULE']);
  VColConstraintName := pData.FieldByName('CONSTRAINT_NAME');
  VColTableName := pData.FieldByName('TABLE_NAME');
  VColKind := pData.FieldByName('KIND');
  VColRefTable := pData.FieldByName('REF_TABLE');
  VColRefConstraint := pData.FieldByName('REF_CONSTRAINT');
  VColUpdateRule := pData.FieldByName('UPDATE_RULE');
  VColDeleteRule := pData.FieldByName('DELETE_RULE');
  VKeys := ReadKeyColumns(pKeyData);
  VList := TList<TFbConstraint>.Create;
  try
    pData.First;
    while not pData.Eof do
    begin
      VItem := Default(TFbConstraint);
      VItem.Name := Txt(VColConstraintName);
      VItem.TableName := Txt(VColTableName);
      VItem.Kind := Txt(VColKind);
      VItem.RefTable := Txt(VColRefTable);
      VItem.RefConstraint := Txt(VColRefConstraint);
      VItem.UpdateRule := Txt(VColUpdateRule);
      VItem.DeleteRule := Txt(VColDeleteRule);
      if VKeys.TryGetValue(VItem.Name, VCols) then
      begin
        VCols.Sort(TComparer<TKeyColumn>.Construct(
          function(const pLeft, pRight: TKeyColumn): Integer
          begin
            Result := pLeft.Position - pRight.Position;
          end));
        for VCol in VCols do
          VItem.Columns := VItem.Columns + [VCol.Name];
      end;
      VList.Add(VItem);
      pData.Next;
    end;
    Result := VList.ToArray;
  finally
    VList.Free;
    VKeys.Free;
  end;
end;

function ReadGenerators(pData: TDataSet): TArray<string>;
var
  VColGeneratorName: TField;
  VList: TList<string>;
begin
  RequireColumns(pData, 'Generators', ['GENERATOR_NAME']);
  VColGeneratorName := pData.FieldByName('GENERATOR_NAME');
  VList := TList<string>.Create;
  try
    pData.First;
    while not pData.Eof do
    begin
      VList.Add(Txt(VColGeneratorName));
      pData.Next;
    end;
    Result := VList.ToArray;
  finally
    VList.Free;
  end;
end;

procedure SortSchemaModel(var pModel: TFbSchemaModel);
begin
  TArray.Sort<TFbDomain>(pModel.Domains, TComparer<TFbDomain>.Construct(
    function(const pLeft, pRight: TFbDomain): Integer
    begin
      Result := CompareStr(pLeft.Name, pRight.Name);
    end));
  TArray.Sort<TFbColumn>(pModel.Columns, TComparer<TFbColumn>.Construct(
    function(const pLeft, pRight: TFbColumn): Integer
    begin
      Result := CompareStr(pLeft.TableName, pRight.TableName);
      if Result = 0 then
        Result := CompareStr(pLeft.ColumnName, pRight.ColumnName);
    end));
  TArray.Sort<TFbConstraint>(pModel.Constraints, TComparer<TFbConstraint>.Construct(
    function(const pLeft, pRight: TFbConstraint): Integer
    begin
      Result := CompareStr(pLeft.Name, pRight.Name);
    end));
  TArray.Sort<string>(pModel.Generators);
end;

function ReadSchemaModel(const pSources: TFbSchemaSources; const pSource, pDatabase: string): TFbSchemaModel;
begin
  Result := Default(TFbSchemaModel);
  Result.Source := pSource;
  Result.Database := pDatabase;
  Result.Domains := ReadDomains(pSources.Domains);
  Result.Columns := ReadColumns(pSources.Columns);
  Result.Constraints := ReadConstraints(pSources.Constraints, pSources.ConstraintColumns);
  Result.Generators := ReadGenerators(pSources.Generators);
  SortSchemaModel(Result);
end;

function DatabaseOfConnection(const pConnection: string): string;
var
  VPair: string;
  VEq: Integer;
begin
  Result := '';
  for VPair in pConnection.Split([';'], TStringSplitOptions.ExcludeEmpty) do
  begin
    VEq := Pos('=', VPair);
    if (VEq > 0) and SameText(Trim(Copy(VPair, 1, VEq - 1)), 'Database') then
      Exit(Trim(Copy(VPair, VEq + 1, MaxInt)));
  end;
end;

function OpenFbSchemaSources(pFb: TFDConnection): TFbSchemaSources;

  function OpenQuery(const pSql: string): TFDQuery;
  begin
    Result := TFDQuery.Create(nil);
    try
      Result.Connection := pFb;
      Result.FetchOptions.Unidirectional := False;
      Result.Open(pSql);  // dl:ok dataset-open-without-close@9c7f -- the open dataset IS the result; FreeFbSchemaSources releases it
      Result.FetchAll;
    except
      Result.Free;
      raise;
    end;
  end;

begin
  Result := Default(TFbSchemaSources);
  { Firebird is only READ: a read-only transaction makes the server refuse any write }
  pFb.TxOptions.ReadOnly := True;
  try
    Result.Domains := OpenQuery(SQL_DOMAINS);
    Result.Columns := OpenQuery(SQL_COLUMNS);
    Result.Constraints := OpenQuery(SQL_CONSTRAINTS);
    Result.ConstraintColumns := OpenQuery(SQL_CONSTRAINT_COLUMNS);
    Result.Generators := OpenQuery(SQL_GENERATORS);
  except
    FreeFbSchemaSources(Result);
    raise;
  end;
end;

procedure FreeFbSchemaSources(var pSources: TFbSchemaSources);
begin
  FreeAndNil(pSources.Domains);
  FreeAndNil(pSources.Columns);
  FreeAndNil(pSources.Constraints);
  FreeAndNil(pSources.ConstraintColumns);
  FreeAndNil(pSources.Generators);
end;

end.
