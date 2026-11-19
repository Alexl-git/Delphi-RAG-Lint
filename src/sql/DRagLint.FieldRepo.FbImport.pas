unit DRagLint.FieldRepo.FbImport;

{ drag-lint 1.52 -- lane TTB: Firebird import core.
  Copies the FIB$ registry tables of a Firebird database into a field repository
  (DRagLint.FieldRepo.Schema). Read-only against Firebird; never writes a password. }

interface

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema;

type
  /// <summary>Per-table result of an import.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.FbImport.pas), DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.FbImport.ImportFromFirebird (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.FbImport.ImportOneTable (DRagLint.FieldRepo.FbImport.pas)</para>
  /// <para>Used in units: DRagLint.CLI.Repo, DRagLint.FieldRepo.FbImport</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRepoImportStat = record
    /// <summary>The DL_ repository table name.</summary>
    TableName: string;
    /// <summary>Rows in the Firebird source; -1 when the source table does not exist.</summary>
    SourceRows: Integer;
    /// <summary>Rows copied into the repository.</summary>
    CopiedRows: Integer;
  end;

/// <summary>Compares the field names of a source dataset with the columns of a repository table.</summary>
/// <param name="pSource">The source dataset (open or with field defs); must not be nil.</param>
/// <param name="pTable">The repository table definition.</param>
/// <param name="pExtra">Source fields the repository table does not have.</param>
/// <param name="pMissing">Repository columns the source does not have.</param>
/// <remarks>
/// Names compare case-insensitively. FIB$VERSION is ignored in the source
/// (owner ruling A4: the version column is not migrated).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.FbImport.ImportTableFromDataSet (DRagLint.FieldRepo.FbImport.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.TRepoTable.FindColumn, SameText</para>
/// <para>Mutates: pExtra (out), pMissing (out)</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.TRepoTable.FindColumn"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure CheckSourceColumns(pSource: TDataSet; const pTable: TRepoTable;  // dl:ok unused-public-symbol@4a7c -- public API; callers arrive with lane TTE (repo import-fb)
  out pExtra, pMissing: TArray<string>);

/// <summary>Copies every row of a source dataset into a repository table.</summary>
/// <param name="pSource">The source dataset; must not be nil. Its cursor is moved.</param>
/// <param name="pTarget">An open read-write repository connection.</param>
/// <param name="pTable">The repository table to fill.</param>
/// <returns>The number of rows copied.</returns>
/// <exception cref="ERepoError">Raised, naming the fields, when the source has extra or missing columns; nothing is written.</exception>
/// <remarks>
/// NULL stays NULL, '' stays '', text is never trimmed. Starts and commits no
/// transaction: the caller owns it. A duplicate key raises the driver's exception.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.FbImport.ImportOneTable (DRagLint.FieldRepo.FbImport.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.FbImport.BindRow, DRagLint.FieldRepo.FbImport.CheckSourceColumns, DRagLint.FieldRepo.FbImport.InsertSql, DRagLint.FieldRepo.FbImport.JoinNames, DRagLint.FieldRepo.FbImport.PrepareParams</para>
/// <seealso cref="DRagLint.FieldRepo.FbImport.BindRow"/>
/// <seealso cref="DRagLint.FieldRepo.FbImport.CheckSourceColumns"/>
/// <seealso cref="DRagLint.FieldRepo.FbImport.InsertSql"/>
/// <seealso cref="DRagLint.FieldRepo.FbImport.JoinNames"/>
/// <seealso cref="DRagLint.FieldRepo.FbImport.PrepareParams"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ImportTableFromDataSet(pSource: TDataSet; pTarget: TFDConnection;  // dl:ok unused-public-symbol@7726 -- public API; callers arrive with lane TTE (repo import-fb)
  const pTable: TRepoTable): Integer;

/// <summary>Imports the FIB$ registry tables of a Firebird database into a repository.</summary>
/// <param name="pConnectionString">FireDAC-style 'Database=..;User=..;Password=..' list separated by ';'.</param>
/// <param name="pTarget">An open read-write repository connection.</param>
/// <param name="pReplace">True to delete the existing rows first; False requires an empty repository.</param>
/// <returns>One stat per data table (DL_FIELDS_INFO, DL_DATASETS_INFO, DL_ENUMVALUES, DL_ERROR_MESSAGES).</returns>
/// <exception cref="ERepoError">Raised when the repository is not empty and pReplace is False (nothing changed), or on a column mismatch.</exception>
/// <remarks>
/// One repository transaction; any exception rolls the whole import back. A source
/// table missing in RDB$RELATIONS gives SourceRows = -1. DL_META gets source_database
/// (the Database value only, never the password), imported_at_utc and fb_field_info_version.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas)</para>
/// <para>Calls: DateToISO8601, DRagLint.FieldRepo.FbImport.FieldInfoVersion, DRagLint.FieldRepo.FbImport.ImportOneTable, DRagLint.FieldRepo.FbImport.OpenSourceConnection, DRagLint.FieldRepo.Schema.FindRepoTable, DRagLint.FieldRepo.Schema.QuoteRepoIdent, DRagLint.FieldRepo.Schema.RepoIsEmpty, DRagLint.FieldRepo.Schema.SetRepoMeta</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>Transaction: starts, commits, rolls back</para>
/// <seealso cref="DRagLint.FieldRepo.FbImport.FieldInfoVersion"/>
/// <seealso cref="DRagLint.FieldRepo.FbImport.ImportOneTable"/>
/// <seealso cref="DRagLint.FieldRepo.FbImport.OpenSourceConnection"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.FindRepoTable"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.QuoteRepoIdent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ImportFromFirebird(const pConnectionString: string; pTarget: TFDConnection;  // dl:ok unused-public-symbol@2f94 -- public API; callers arrive with lane TTE (repo import-fb)
  pReplace: Boolean): TArray<TRepoImportStat>;

/// <summary>Opens a Firebird connection from a 'Key=Value;...' string.</summary>
/// <param name="pConnectionString">FireDAC-style list separated by ';'; DriverID=FB and
/// CharacterSet=UTF8 are added when absent.</param>
/// <param name="pDatabase">Receives the Database value only (never the password).</param>
/// <returns>An OPEN connection; the caller owns Close/Free.</returns>
/// <exception cref="EFDDBEngineException">The server refuses the connection (the half-made connection is freed).</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoSeed (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.FbImport.ImportFromFirebird (DRagLint.FieldRepo.FbImport.pas)</para>
/// <para>Calls: Copy, Pos, Trim</para>
/// <para>Returns: TFDConnection.Create(nil)</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>Mutates: pDatabase (out)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OpenSourceConnection(const pConnectionString: string; out pDatabase: string): TFDConnection;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Variants,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,  // dl:ok unused-unit-in-uses@bef0 -- FireDAC driver registration
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,  // dl:ok unused-unit-in-uses@55fa
  FireDAC.Phys.FB,  // dl:ok unused-unit-in-uses@17cb
  FireDAC.DApt;

const
  FIB_VERSION_COLUMN = 'FIB$VERSION';
  DATA_TABLES: array[0..3] of string = ('DL_FIELDS_INFO', 'DL_DATASETS_INFO', 'DL_ENUMVALUES', 'DL_ERROR_MESSAGES');

function JoinNames(const pNames: TArray<string>): string;
begin
  Result := string.Join(', ', pNames);
end;

procedure CheckSourceColumns(pSource: TDataSet; const pTable: TRepoTable;
  out pExtra, pMissing: TArray<string>);
var
  Extra, Missing: TArray<string>;
  Col: TRepoColumn;
  I: Integer;
  Name: string;
begin
  Extra := nil;
  Missing := nil;
  for I := 0 to pSource.FieldCount - 1 do
  begin
    Name := pSource.Fields[I].FieldName;
    if SameText(Name, FIB_VERSION_COLUMN) then
      Continue;
    if not pTable.FindColumn(Name, Col) then
      Extra := Extra + [Name];
  end;
  for Col in pTable.Columns do
    if pSource.FindField(Col.Name) = nil then
      Missing := Missing + [Col.Name];
  pExtra := Extra;
  pMissing := Missing;
end;

function InsertSql(const pTable: TRepoTable): string;
var
  Names, Params: TArray<string>;
  I: Integer;
begin
  SetLength(Names, Length(pTable.Columns));
  SetLength(Params, Length(pTable.Columns));
  for I := 0 to High(pTable.Columns) do
  begin
    Names[I] := QuoteRepoIdent(pTable.Columns[I].Name);
    Params[I] := ':p' + IntToStr(I);
  end;
  Result := 'INSERT INTO ' + QuoteRepoIdent(pTable.Name) + ' (' + string.Join(', ', Names)
    + ') VALUES (' + string.Join(', ', Params) + ')';
end;

function ByteOfField(pField: TField): Integer;
var
  Bytes: TBytes;
  Text: string;
begin
  Result := 0;
  if pField.DataType in [ftBytes, ftVarBytes] then
  begin
    Bytes := pField.AsBytes;
    if Length(Bytes) > 0 then
      Result := Bytes[0];
  end
  else if pField is TNumericField then
    Result := pField.AsInteger
  else
  begin
    Text := pField.AsWideString;
    if Text <> '' then
      Result := Ord(Text[1]);
  end;
end;

procedure BindRow(pQuery: TFDQuery; const pFields: TArray<TField>; const pTable: TRepoTable);
var
  I: Integer;
  Field: TField;
  Param: TFDParam;
begin
  for I := 0 to High(pTable.Columns) do
  begin
    Field := pFields[I];
    Param := pQuery.Params[I];
    if Field.IsNull then
      Param.Clear
    else
      case pTable.Columns[I].Kind of
        rckString: Param.AsWideString := Field.AsWideString;
        rckText: Param.AsWideMemo := Field.AsWideString;
        rckBoolean: Param.AsBoolean := Field.AsBoolean;
        rckByte: Param.AsInteger := ByteOfField(Field);
      else
        Param.AsInteger := Field.AsInteger;
      end;
  end;
end;

procedure PrepareParams(pQuery: TFDQuery; const pTable: TRepoTable);
var
  I: Integer;
begin
  for I := 0 to High(pTable.Columns) do
    case pTable.Columns[I].Kind of
      rckString: pQuery.Params[I].DataType := ftWideString;
      rckText: pQuery.Params[I].DataType := ftWideMemo;
      rckBoolean: pQuery.Params[I].DataType := ftBoolean;
    else
      pQuery.Params[I].DataType := ftInteger;
    end;
end;

function ImportTableFromDataSet(pSource: TDataSet; pTarget: TFDConnection;
  const pTable: TRepoTable): Integer;
var
  Extra, Missing: TArray<string>;
  Query: TFDQuery;
  Fields: TArray<TField>;
  I: Integer;
begin
  CheckSourceColumns(pSource, pTable, Extra, Missing);
  if (Length(Extra) > 0) or (Length(Missing) > 0) then
    raise ERepoError.CreateFmt('Source of %s does not match the repository table. Extra: [%s]; missing: [%s]',
      [pTable.Name, JoinNames(Extra), JoinNames(Missing)]);
  Result := 0;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := pTarget;
    Query.FormatOptions.StrsTrim := False;
    Query.SQL.Text := InsertSql(pTable);
    PrepareParams(Query, pTable);
    SetLength(Fields, Length(pTable.Columns));
    for I := 0 to High(Fields) do
      Fields[I] := pSource.FieldByName(pTable.Columns[I].Name);  // dl:ok field-by-name-in-loop@0e05 -- this IS the loop that builds the TField cache, run once per import
    pSource.First;
    while not pSource.Eof do
    begin
      BindRow(Query, Fields, pTable);
      Query.ExecSQL;
      Inc(Result);
      pSource.Next;
    end;
  finally
    Query.Free;
  end;
end;

function OpenSourceConnection(const pConnectionString: string; out pDatabase: string): TFDConnection;
var
  Params: TStringList;
  Pair: string;
  EqPos: Integer;
begin
  Result := TFDConnection.Create(nil);
  try
    Params := TStringList.Create;
    try
      for Pair in pConnectionString.Split([';'], TStringSplitOptions.ExcludeEmpty) do
      begin
        EqPos := Pos('=', Pair);
        if EqPos > 0 then
          Params.Add(Trim(Copy(Pair, 1, EqPos - 1)) + '=' + Trim(Copy(Pair, EqPos + 1, MaxInt)));
      end;
      if Params.IndexOfName('DriverID') = -1 then
        Params.Add('DriverID=FB');
      if Params.IndexOfName('CharacterSet') = -1 then
        Params.Add('CharacterSet=UTF8');
      pDatabase := Params.Values['Database'];
      Result.Params.Assign(Params);
    finally
      Params.Free;
    end;
    Result.LoginPrompt := False;
    Result.Open;  // dl:ok dataset-open-without-close@f8d5 -- returns the OPEN connection; the caller owns Close/Free
  except  // dl:ok bare-except@041e -- frees the connection and re-raises the original exception
    Result.Free;
    raise;
  end;
end;

function SourceTableExists(pSource: TFDConnection; const pName: string): Boolean;
begin
  Result := Integer(pSource.ExecSQLScalar(
    'SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = :n', [pName])) > 0;
end;

function ImportOneTable(pSource: TFDConnection; pTarget: TFDConnection;
  const pTable: TRepoTable): TRepoImportStat;
var
  Query: TFDQuery;
begin
  Result.TableName := pTable.Name;
  Result.SourceRows := -1;
  Result.CopiedRows := 0;
  if not SourceTableExists(pSource, pTable.SourceName) then
    Exit;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := pSource;
    Query.FormatOptions.StrsTrim := False;
    Query.Open('SELECT * FROM ' + QuoteRepoIdent(pTable.SourceName));  // dl:ok path-traversal@83c8 -- SQL text; identifier quoted
    Result.CopiedRows := ImportTableFromDataSet(Query, pTarget, pTable);
    Result.SourceRows := Result.CopiedRows;
  finally
    Query.Free;
  end;
end;

function FieldInfoVersion(pSource: TFDConnection): string;
begin
  try
    Result := VarToStr(pSource.ExecSQLScalar('SELECT GEN_ID(FIB$FIELD_INFO_VERSION, 0) FROM RDB$DATABASE'));
  except
    on EFDDBEngineException do
      Result := '';
  end;
end;

function ImportFromFirebird(const pConnectionString: string; pTarget: TFDConnection;
  pReplace: Boolean): TArray<TRepoImportStat>;
var
  Source: TFDConnection;
  Database: string;
  Table: TRepoTable;
  Name: string;
begin
  if (not pReplace) and (not RepoIsEmpty(pTarget)) then
    raise ERepoError.Create('The repository is not empty; use replace to overwrite it.');
  Source := OpenSourceConnection(pConnectionString, Database);
  try
    Result := nil;
    pTarget.StartTransaction;
    try
      for Name in DATA_TABLES do
        pTarget.ExecSQL('DELETE FROM ' + QuoteRepoIdent(Name));
      for Name in DATA_TABLES do
      begin
        FindRepoTable(Name, Table);
        Result := Result + [ImportOneTable(Source, pTarget, Table)];
      end;
      SetRepoMeta(pTarget, 'source_database', Database);
      SetRepoMeta(pTarget, 'imported_at_utc', DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True));
      SetRepoMeta(pTarget, 'fb_field_info_version', FieldInfoVersion(Source));
      pTarget.Commit;
    except  // dl:ok bare-except@46a7 -- rolls the transaction back and re-raises the original exception
      pTarget.Rollback;
      raise;
    end;
  finally
    Source.Free;
  end;
end;

end.
