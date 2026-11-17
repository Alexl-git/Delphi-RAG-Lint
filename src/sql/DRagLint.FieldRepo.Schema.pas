unit DRagLint.FieldRepo.Schema;

{ drag-lint 1.52 -- lane TTA: field repository schema core.

  A field repository is one SQLite file (".dlrepo") holding the five DL_ tables that
  replace the Firebird FIB$ registry (design 2026-11-16-tabletools-into-dl-design.md
  section 4). Lanes TTB / TTC / TTD / TTS / TTE compile against the interface below.
  Owner ruling A4: the FIB$VERSION column is NOT carried (column counts
  2 / 40 / 12 / 6 / 3); a schema migration re-adds it if a use appears. }

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client;

const
  /// <summary>Schema version of the repository; mirrored in PRAGMA user_version and DL_META.</summary>
  cRepoSchemaVersion = 1;  // dl:ok const-casing@35cd
  /// <summary>SQLite application_id of a field repository ('DLFR').</summary>
  cRepoApplicationId = $444C4652;  // dl:ok const-casing@510d
  /// <summary>File extension of a repository file.</summary>
  cRepoFileExt = '.dlrepo';  // dl:ok const-casing@3824
  /// <summary>Folder (next to the project file) that holds the default repository.</summary>
  cRepoFolderName = '_DL-REPO';  // dl:ok const-casing@1611
  /// <summary>Name of the key/value table with repository metadata.</summary>
  cRepoMetaTable = 'DL_META';  // dl:ok const-casing@79ca

type
  /// <summary>Base class of every repository error (missing / existing file, unknown table).</summary>
  ERepoError = class(Exception);

  /// <summary>Raised when a file is not a repository of this schema version.
  /// The message names the cause (application_id, user_version, table, column).</summary>
  ERepoSchemaError = class(ERepoError);

  /// <summary>Column kind; selects the SQLite declaration and the FireDAC TField class.</summary>
  TRepoColKind = (rckString, rckInteger, rckSmallint, rckBoolean, rckText, rckByte);

  /// <summary>One column of a repository table (design section 4).</summary>
  TRepoColumn = record
    /// <summary>Exact column name, e.g. 'TABLE_NAME'.</summary>
    Name: string;
    /// <summary>Column kind.</summary>
    Kind: TRepoColKind;
    /// <summary>Maximum length; rckString only, else 0.</summary>
    MaxLen: Integer;
    /// <summary>True for NOT NULL.</summary>
    NotNull: Boolean;
    /// <summary>SQL literal ('0', '1', '''UNIQUE'''); '' means no default.</summary>
    DefaultSql: string;
    /// <summary>1-based position in the primary key; 0 = not a key column.</summary>
    PkOrder: Integer;
  end;

  /// <summary>One repository table: name, Firebird source name and ordered columns.</summary>
  TRepoTable = record
    /// <summary>Table name, e.g. 'DL_FIELDS_INFO'.</summary>
    Name: string;
    /// <summary>Firebird source table, e.g. 'FIB$FIELDS_INFO'; '' for DL_META.</summary>
    SourceName: string;
    /// <summary>Columns in declaration order.</summary>
    Columns: TArray<TRepoColumn>;
    /// <summary>Key columns in PkOrder.</summary>
    /// <returns>The primary-key columns, ordered by PkOrder.</returns>
    function PkColumns: TArray<TRepoColumn>;
    /// <summary>Looks a column up by name, case-insensitively.</summary>
    /// <param name="pName">Column name.</param>
    /// <param name="pColumn">Receives the column when found.</param>
    /// <returns>True when the column exists.</returns>
    function FindColumn(const pName: string; out pColumn: TRepoColumn): Boolean;
  end;

/// <summary>The five repository tables in the fixed order DL_META, DL_FIELDS_INFO,
/// DL_DATASETS_INFO, DL_ENUMVALUES, DL_ERROR_MESSAGES.</summary>
/// <returns>A fresh array of table descriptions.</returns>
function RepoTables: TArray<TRepoTable>;  // dl:ok unused-public-symbol@15fa

/// <summary>Looks a repository table up by name, case-insensitively.</summary>
/// <param name="pName">Table name.</param>
/// <param name="pTable">Receives the table when found.</param>
/// <returns>True when the table exists.</returns>
function FindRepoTable(const pName: string; out pTable: TRepoTable): Boolean;  // dl:ok unused-public-symbol@c8d7

/// <summary>Quotes an identifier for SQLite with double quotes. Every SQL statement
/// of every lane quotes identifiers through this function.</summary>
/// <param name="pName">Unquoted identifier.</param>
/// <returns>The identifier in double quotes, embedded quotes doubled.</returns>
function QuoteRepoIdent(const pName: string): string;  // dl:ok unused-public-symbol@0e28

/// <summary>Builds the CREATE TABLE statement for a table: SQLite declared type per kind,
/// NOT NULL, DEFAULT, a length CHECK for strings, a 0..255 CHECK for bytes, and the primary
/// key (inline for a single integer key, table-level otherwise).</summary>
/// <param name="pTable">Table description.</param>
/// <returns>The DDL text.</returns>
function RepoTableDdl(const pTable: TRepoTable): string;  // dl:ok unused-public-symbol@5822

/// <summary>Default repository path of a project: the project folder, then
/// cRepoFolderName, then the project base name with cRepoFileExt.</summary>
/// <param name="pProjectFile">Full path of the project file.</param>
/// <returns>For C:\P\App.dproj: C:\P\_DL-REPO\App.dlrepo.</returns>
function DefaultRepoPath(const pProjectFile: string): string;  // dl:ok unused-public-symbol@4257

/// <summary>Creates a new repository file with all five tables.</summary>
/// <param name="pFileName">Target file; its folder is created.</param>
/// <exception cref="ERepoError">The file already exists.</exception>
/// <remarks>Sets application_id and user_version, journal_mode=DELETE, creates the tables
/// in one transaction and writes DL_META.schema_version.</remarks>
procedure CreateRepository(const pFileName: string);  // dl:ok unused-public-symbol@3469

/// <summary>Opens an existing repository and validates it.</summary>
/// <param name="pFileName">Repository file.</param>
/// <param name="pReadOnly">True opens with OpenMode=ReadOnly.</param>
/// <returns>A connected connection; the caller frees it.</returns>
/// <exception cref="ERepoError">The file is missing (it is never created).</exception>
/// <exception cref="ERepoSchemaError">The file is not a repository of this version.</exception>
function OpenRepository(const pFileName: string; pReadOnly: Boolean): TFDConnection;  // dl:ok unused-public-symbol@f329

/// <summary>Checks application_id, user_version, every table and every column.</summary>
/// <param name="pConnection">A connected SQLite connection.</param>
/// <exception cref="ERepoSchemaError">Names the first mismatch found.</exception>
procedure ValidateRepository(pConnection: TFDConnection);  // dl:ok unused-public-symbol@83e8

/// <summary>Number of rows of a repository table.</summary>
/// <param name="pConnection">An open repository connection.</param>
/// <param name="pTableName">A repository table name.</param>
/// <returns>The row count.</returns>
/// <exception cref="ERepoError">The table is not a repository table.</exception>
function RepoRowCount(pConnection: TFDConnection; const pTableName: string): Integer;  // dl:ok unused-public-symbol@9768

/// <summary>True when every repository table except DL_META has no rows.</summary>
/// <param name="pConnection">An open repository connection.</param>
/// <returns>True for a freshly created repository.</returns>
function RepoIsEmpty(pConnection: TFDConnection): Boolean;  // dl:ok unused-public-symbol@370b

/// <summary>Writes (inserts or replaces) one DL_META value.</summary>
/// <param name="pConnection">A read-write repository connection.</param>
/// <param name="pKey">Meta key.</param>
/// <param name="pValue">Meta value.</param>
/// <remarks>A read-only connection raises the driver's exception.</remarks>
procedure SetRepoMeta(pConnection: TFDConnection; const pKey, pValue: string);  // dl:ok unused-public-symbol@419a

/// <summary>Reads one DL_META value.</summary>
/// <param name="pConnection">An open repository connection.</param>
/// <param name="pKey">Meta key.</param>
/// <returns>The value, or '' when the key is absent.</returns>
function GetRepoMeta(pConnection: TFDConnection; const pKey: string): string;  // dl:ok unused-public-symbol@3149

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Stan.Def,  // dl:ok unused-unit-in-uses@bef0
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,  // dl:ok unused-unit-in-uses@55fa
  FireDAC.Phys.SQLite,  // dl:ok unused-unit-in-uses@87f1
  FireDAC.DApt;

const
  cMaxByte = 255;  // dl:ok const-casing@1455

function Col(const pName: string; pKind: TRepoColKind; pMaxLen: Integer; pNotNull: Boolean;
  const pDefault: string; pPk: Integer): TRepoColumn;
begin
  Result.Name := pName;
  Result.Kind := pKind;
  Result.MaxLen := pMaxLen;
  Result.NotNull := pNotNull;
  Result.DefaultSql := pDefault;
  Result.PkOrder := pPk;
end;

function Str(const pName: string; pLen: Integer; pNotNull: Boolean = False; pPk: Integer = 0): TRepoColumn;
begin
  Result := Col(pName, rckString, pLen, pNotNull, '', pPk);
end;

function Bool(const pName: string; const pDefault: string): TRepoColumn;
begin
  Result := Col(pName, rckBoolean, 0, True, pDefault, 0);
end;

function Small(const pName: string; const pDefault: string = ''): TRepoColumn;
begin
  Result := Col(pName, rckSmallint, 0, False, pDefault, 0);
end;

function Txt(const pName: string; const pDefault: string = ''): TRepoColumn;
begin
  Result := Col(pName, rckText, 0, False, pDefault, 0);
end;

function MakeTable(const pName, pSource: string; const pCols: TArray<TRepoColumn>): TRepoTable;
begin
  Result.Name := pName;
  Result.SourceName := pSource;
  Result.Columns := pCols;
end;

function MetaTable: TRepoTable;
begin
  Result := MakeTable(cRepoMetaTable, '', [
    Str('META_KEY', 63, True, 1),  // dl:ok large-magic-number@d89d, magic-literal@d89d
    Str('META_VALUE', 1000)]);  // dl:ok magic-literal@cc89
end;

function FieldsInfoTable: TRepoTable;
begin
  Result := MakeTable('DL_FIELDS_INFO', 'FIB$FIELDS_INFO', [
    Str('TABLE_NAME', 68, True, 1),  // dl:ok large-magic-number@fcb2, magic-literal@fcb2
    Str('FIELD_NAME', 68, True, 2),  // dl:ok large-magic-number@b55c, magic-literal@b55c
    Str('DISPLAY_LABEL', 40),  // dl:ok large-magic-number@50b4, magic-literal@50b4
    Bool('VISIBLE', '1'),
    Str('DISPLAY_FORMAT', 20),  // dl:ok magic-literal@abb9
    Str('EDIT_FORMAT', 20),  // dl:ok magic-literal@3610
    Bool('TRIGGERED', '0'),
    Col('DISPLAY_WIDTH', rckInteger, 0, False, '0', 0),
    Str('FIELD_AS_TYPE', 20),  // dl:ok magic-literal@543f
    Str('VAR_TYPE', 20),  // dl:ok magic-literal@42e6
    Bool('BG_COLOR', '0'),
    Bool('FG_COLOR', '0'),
    Small('ALIGNMENT'),
    Str('DEFAULTVAL', 50),  // dl:ok magic-literal@617e
    Small('FIELD_SIZE'),
    Small('STRING_SIZE'),
    Small('NULL_FLAG'),
    Bool('UNIQUE_FLAG', '0'),
    Small('FIELD_KIND'),
    Bool('PRIMARY_KEY', '0'),
    Str('SEQUENCE_NAME', 35),  // dl:ok large-magic-number@5d8e, magic-literal@5d8e
    Bool('CUSTOM_TYPE', '0'),
    Bool('ISCALCULATED', '0'),
    Bool('ISLOOKUP', '0'),
    Bool('ISENUM', '0'),
    Str('DESTTABLE', 35),  // dl:ok large-magic-number@5817, magic-literal@5817
    Str('SOURCEKEY', 35),  // dl:ok large-magic-number@dfde, magic-literal@dfde
    Str('DESTKEY', 35),  // dl:ok large-magic-number@dc1a, magic-literal@dc1a
    Str('DESTVALUE', 35),  // dl:ok large-magic-number@c3c7, magic-literal@c3c7
    Txt('DOC_SUMMARY', '''Summary here'''),
    Txt('DOC_REMARKS', '''Remarks here'''),
    Str('ENUMTYPE', 25),  // dl:ok large-magic-number@b633, magic-literal@b633
    Str('DOCUMENTATION', 220),  // dl:ok large-magic-number@7465, magic-literal@7465
    Str('LOADFIELD', 50),  // dl:ok magic-literal@55c4
    Str('SAVEFIELD', 50),  // dl:ok magic-literal@b931
    Small('FIELD_TYPE'),
    Small('FIELD_SUBTYPE'),
    Small('FIELD_LENGTH'),
    Small('FIELD_SCALE'),
    Small('UI_TAG', '0')]);
end;

function DatasetsInfoTable: TRepoTable;
begin
  Result := MakeTable('DL_DATASETS_INFO', 'FIB$DATASETS_INFO', [
    Col('DS_ID', rckInteger, 0, True, '', 1),
    Str('DESCRIPTION', 220),  // dl:ok large-magic-number@83e5, magic-literal@83e5
    Txt('SELECT_SQL'),
    Txt('UPDATE_SQL'),
    Txt('INSERT_SQL'),
    Txt('DELETE_SQL'),
    Txt('REFRESH_SQL'),
    Str('NAME_GENERATOR', 68),  // dl:ok large-magic-number@6a14, magic-literal@6a14
    Str('KEY_FIELD', 68),  // dl:ok large-magic-number@c652, magic-literal@c652
    Str('UPDATE_TABLE_NAME', 68),  // dl:ok large-magic-number@84dd, magic-literal@84dd
    Bool('UPDATE_ONLY_MODIFIED_FIELDS', '1'),
    Txt('CONDITIONS')]);
end;

function EnumValuesTable: TRepoTable;
begin
  Result := MakeTable('DL_ENUMVALUES', 'FIB$ENUMVALUES', [
    Str('ENUMTYPE', 15, True, 1),  // dl:ok magic-literal@9df7
    Col('EORDER', rckInteger, 0, True, '', 2),
    Str('NAME', 20, True),  // dl:ok magic-literal@e074
    Str('ESTRING', 50, True),  // dl:ok magic-literal@3eb3
    Str('DOCUMENTATION', 220),  // dl:ok large-magic-number@7465, magic-literal@7465
    Col('EVALUE', rckByte, 0, False, '0', 0)]);
end;

function ErrorMessagesTable: TRepoTable;
begin
  Result := MakeTable('DL_ERROR_MESSAGES', 'FIB$ERROR_MESSAGES', [
    Str('CONSTRAINT_NAME', 68, True, 1),  // dl:ok large-magic-number@3079, magic-literal@3079
    Str('MESSAGE_STRING', 220),  // dl:ok large-magic-number@cb9e, magic-literal@cb9e
    Col('CONSTR_TYPE', rckString, 15, True, '''UNIQUE''', 0)]);  // dl:ok magic-literal@2a00
end;

function RepoTables: TArray<TRepoTable>;
begin
  Result := [MetaTable, FieldsInfoTable, DatasetsInfoTable, EnumValuesTable, ErrorMessagesTable];
end;

function TRepoTable.PkColumns: TArray<TRepoColumn>;
var
  vList: TList<TRepoColumn>;  // dl:ok local-var-casing@3c54
  vCol: TRepoColumn;  // dl:ok local-var-casing@9a72
  vOrder: Integer;  // dl:ok local-var-casing@331f
begin
  vList := TList<TRepoColumn>.Create;
  try
    for vOrder := 1 to Length(Columns) do
      for vCol in Columns do
        if vCol.PkOrder = vOrder then
          vList.Add(vCol);
    Result := vList.ToArray;
  finally
    vList.Free;
  end;
end;

function TRepoTable.FindColumn(const pName: string; out pColumn: TRepoColumn): Boolean;
var
  vCol: TRepoColumn;  // dl:ok local-var-casing@9a72
begin
  Result := False;
  pColumn := Default(TRepoColumn);
  for vCol in Columns do
    if SameText(vCol.Name, pName) then
    begin
      pColumn := vCol;
      Exit(True);
    end;
end;

function FindRepoTable(const pName: string; out pTable: TRepoTable): Boolean;
var
  vTab: TRepoTable;  // dl:ok local-var-casing@6bed
begin
  Result := False;
  pTable := Default(TRepoTable);
  for vTab in RepoTables do
    if SameText(vTab.Name, pName) then
    begin
      pTable := vTab;
      Exit(True);
    end;
end;

function QuoteRepoIdent(const pName: string): string;
begin
  Result := '"' + pName.Replace('"', '""') + '"';
end;

function ColumnDdl(const pCol: TRepoColumn; pInlinePk: Boolean): string;
var
  vQ: string;  // dl:ok local-var-casing@3f14
begin
  vQ := QuoteRepoIdent(pCol.Name);
  case pCol.Kind of
    rckString:   Result := vQ + ' VARCHAR(' + IntToStr(pCol.MaxLen) + ')';
    rckInteger:  Result := vQ + ' INTEGER';
    rckSmallint: Result := vQ + ' SMALLINT';
    rckBoolean:  Result := vQ + ' BOOLEAN';
    rckText:     Result := vQ + ' TEXT';
  else
    Result := vQ + ' SMALLINT';
  end;
  if pCol.NotNull then
    Result := Result + ' NOT NULL';
  if pInlinePk then
    Result := Result + ' PRIMARY KEY';
  if pCol.DefaultSql <> '' then
    Result := Result + ' DEFAULT ' + pCol.DefaultSql;
  if pCol.Kind = rckString then
    Result := Result + ' CHECK (length(' + vQ + ') <= ' + IntToStr(pCol.MaxLen) + ')';
  if pCol.Kind = rckByte then
    Result := Result + ' CHECK (' + vQ + ' BETWEEN 0 AND ' + IntToStr(cMaxByte) + ')';
end;

function RepoTableDdl(const pTable: TRepoTable): string;
var
  vPk: TArray<TRepoColumn>;  // dl:ok local-var-casing@34ef
  vInline: Boolean;  // dl:ok local-var-casing@a011
  vCol: TRepoColumn;  // dl:ok local-var-casing@9a72
  vParts: TStringList;  // dl:ok local-var-casing@f49c
  vKeys: string;  // dl:ok local-var-casing@2d73
  vI: Integer;  // dl:ok local-var-casing@5821
begin
  vPk := pTable.PkColumns;
  vInline := (Length(vPk) = 1) and (vPk[0].Kind = rckInteger);
  vParts := TStringList.Create;
  try
    for vCol in pTable.Columns do
      vParts.Add(ColumnDdl(vCol, vInline and (vCol.PkOrder = 1)));
    if (Length(vPk) > 0) and not vInline then
    begin
      vKeys := '';
      for vI := 0 to High(vPk) do
        vKeys := vKeys + (if vI > 0 then ', ' else '') + QuoteRepoIdent(vPk[vI].Name);
      vParts.Add('PRIMARY KEY (' + vKeys + ')');
    end;
    Result := 'CREATE TABLE ' + QuoteRepoIdent(pTable.Name) + ' (' + sLineBreak + '  '
      + string.Join(',' + sLineBreak + '  ', vParts.ToStringArray) + sLineBreak + ')';
  finally
    vParts.Free;
  end;
end;

function DefaultRepoPath(const pProjectFile: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ExtractFilePath(pProjectFile), cRepoFolderName),
    TPath.GetFileNameWithoutExtension(pProjectFile) + cRepoFileExt);
end;

function NewConnection(const pFileName, pOpenMode: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.LoginPrompt := False;
    Result.Params.Values['DriverID'] := 'SQLite';
    Result.Params.Values['Database'] := pFileName;
    Result.Params.Values['OpenMode'] := pOpenMode;
    Result.Params.Values['LockingMode'] := 'Normal';
    Result.Params.Values['Synchronous'] := 'Full';
    Result.Params.Values['ForeignKeys'] := 'On';
    Result.Params.Values['StringFormat'] := 'Unicode';
    Result.Connected := True;
  except  // dl:ok bare-except@041e
    Result.Free;
    raise;
  end;
end;

procedure CreateRepository(const pFileName: string);
var
  vConn: TFDConnection;  // dl:ok local-var-casing@d2a6
  vTab: TRepoTable;  // dl:ok local-var-casing@6bed
begin
  if TFile.Exists(pFileName) then
    raise ERepoError.CreateFmt('Repository already exists: %s', [pFileName]);
  TDirectory.CreateDirectory(ExtractFilePath(ExpandFileName(pFileName)));
  vConn := NewConnection(pFileName, 'CreateUTF8');
  try
    vConn.ExecSQL('PRAGMA application_id = ' + IntToStr(cRepoApplicationId));
    vConn.ExecSQL('PRAGMA user_version = ' + IntToStr(cRepoSchemaVersion));
    vConn.ExecSQLScalar('PRAGMA journal_mode = DELETE');
    vConn.StartTransaction;
    try
      for vTab in RepoTables do
        vConn.ExecSQL(RepoTableDdl(vTab));
      SetRepoMeta(vConn, 'schema_version', IntToStr(cRepoSchemaVersion));
      vConn.Commit;
    except  // dl:ok bare-except@72e8
      vConn.Rollback;
      raise;
    end;
  finally
    vConn.Free;
  end;
end;

procedure ValidateColumns(pConnection: TFDConnection; const pTable: TRepoTable);
var
  vQ: TFDQuery;  // dl:ok local-var-casing@25c6
  vSeen: TStringList;  // dl:ok local-var-casing@62f3
  vCol: TRepoColumn;  // dl:ok local-var-casing@9a72
  vName: string;  // dl:ok local-var-casing@2388
  vNameField: TField;  // dl:ok local-var-casing@47b2
begin
  vSeen := TStringList.Create;
  vQ := TFDQuery.Create(nil);
  try
    vSeen.CaseSensitive := False;
    vQ.Connection := pConnection;
    vQ.Open('PRAGMA table_info(' + QuoteRepoIdent(pTable.Name) + ')');  // dl:ok path-traversal@8fac
    vNameField := vQ.FieldByName('name');
    while not vQ.Eof do
    begin
      vName := vNameField.AsString;
      vSeen.Add(vName);
      if not pTable.FindColumn(vName, vCol) then
        raise ERepoSchemaError.CreateFmt('Unexpected column %s.%s', [pTable.Name, vName]);
      vQ.Next;
    end;
    if vSeen.Count = 0 then
      raise ERepoSchemaError.CreateFmt('Missing table %s', [pTable.Name]);
    for vCol in pTable.Columns do
      if vSeen.IndexOf(vCol.Name) < 0 then
        raise ERepoSchemaError.CreateFmt('Missing column %s.%s', [pTable.Name, vCol.Name]);
  finally
    vQ.Free;
    vSeen.Free;
  end;
end;

procedure ValidateRepository(pConnection: TFDConnection);
var
  vId, vVer: Integer;  // dl:ok local-var-casing@be7e
  vTab: TRepoTable;  // dl:ok local-var-casing@6bed
begin
  vId := pConnection.ExecSQLScalar('PRAGMA application_id');
  if vId <> cRepoApplicationId then
    raise ERepoSchemaError.CreateFmt('Not a field repository: application_id is %d, expected %d',
      [vId, cRepoApplicationId]);
  vVer := pConnection.ExecSQLScalar('PRAGMA user_version');
  if vVer <> cRepoSchemaVersion then
    raise ERepoSchemaError.CreateFmt('Unsupported repository schema: user_version is %d, expected %d',
      [vVer, cRepoSchemaVersion]);
  for vTab in RepoTables do
    ValidateColumns(pConnection, vTab);
end;

function OpenRepository(const pFileName: string; pReadOnly: Boolean): TFDConnection;
begin
  if not TFile.Exists(pFileName) then
    raise ERepoError.CreateFmt('Repository not found: %s', [pFileName]);
  Result := NewConnection(pFileName, if pReadOnly then 'ReadOnly' else 'ReadWrite');
  try
    ValidateRepository(Result);
  except  // dl:ok bare-except@041e
    Result.Free;
    raise;
  end;
end;

function RepoRowCount(pConnection: TFDConnection; const pTableName: string): Integer;
var
  vTab: TRepoTable;  // dl:ok local-var-casing@6bed
begin
  if not FindRepoTable(pTableName, vTab) then
    raise ERepoError.CreateFmt('Not a repository table: %s', [pTableName]);
  Result := pConnection.ExecSQLScalar('SELECT COUNT(*) FROM ' + QuoteRepoIdent(vTab.Name));
end;

function RepoIsEmpty(pConnection: TFDConnection): Boolean;
var
  vTab: TRepoTable;  // dl:ok local-var-casing@6bed
begin
  Result := True;
  for vTab in RepoTables do
    if (not SameText(vTab.Name, cRepoMetaTable)) and (RepoRowCount(pConnection, vTab.Name) > 0) then
      Exit(False);
end;

procedure SetRepoMeta(pConnection: TFDConnection; const pKey, pValue: string);
begin
  pConnection.ExecSQL('INSERT OR REPLACE INTO ' + QuoteRepoIdent(cRepoMetaTable)
    + ' ("META_KEY", "META_VALUE") VALUES (:k, :v)', [pKey, pValue]);
end;

function GetRepoMeta(pConnection: TFDConnection; const pKey: string): string;
var
  vQ: TFDQuery;  // dl:ok local-var-casing@25c6
begin
  vQ := TFDQuery.Create(nil);
  try
    vQ.Connection := pConnection;
    vQ.Open('SELECT "META_VALUE" FROM ' + QuoteRepoIdent(cRepoMetaTable) + ' WHERE "META_KEY" = :k', [pKey]);  // dl:ok path-traversal@9483
    Result := if vQ.Eof then '' else vQ.Fields[0].AsString;
  finally
    vQ.Free;
  end;
end;

end.
