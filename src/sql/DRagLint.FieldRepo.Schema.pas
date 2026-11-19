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
  REPO_SCHEMA_VERSION = 1;
  /// <summary>SQLite application_id of a field repository ('DLFR').</summary>
  REPO_APPLICATION_ID = $444C4652;
  /// <summary>File extension of a repository file.</summary>
  REPO_FILE_EXT = '.dlrepo';
  /// <summary>Folder (next to the project file) that holds the default repository.</summary>
  REPO_FOLDER_NAME = '_DL-REPO';
  /// <summary>Name of the key/value table with repository metadata.</summary>
  REPO_META_TABLE = 'DL_META';

type
  /// <summary>Base class of every repository error (missing / existing file, unknown table).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.FieldRepo.FbImport.ImportFromFirebird (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.FbImport.ImportTableFromDataSet (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.Schema.CreateRepository (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.Schema.OpenRepository (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.Schema.RepoRowCount (DRagLint.FieldRepo.Schema.pas) (+9 more)</para>
  /// <para>Used in units: DRagLint.CLI.Repo, DRagLint.FieldRepo.DataServiceGen, DRagLint.FieldRepo.FbImport, DRagLint.FieldRepo.Schema, DRagLint.FieldRepo.SchemaSeed, DRagLint.FieldRepo.TextBackup</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  ERepoError = class(Exception);

  /// <summary>Raised when a file is not a repository of this schema version.
  /// The message names the cause (application_id, user_version, table, column).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.FieldRepo.Schema.ValidateColumns (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.Schema.ValidateRepository (DRagLint.FieldRepo.Schema.pas)</para>
  /// <para>Used in units: DRagLint.FieldRepo.Schema</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  ERepoSchemaError = class(ERepoError);

  /// <summary>Column kind; selects the SQLite declaration and the FireDAC TField class.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.Schema.Col (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.TextBackup.ParamFieldType (DRagLint.FieldRepo.TextBackup.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRepoColKind = (rckString, rckInteger, rckSmallint, rckBoolean, rckText, rckByte);

  /// <summary>One column of a repository table (design section 4).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.Schema.pas) ?, DRagLint.FieldRepo.FbImport.CheckSourceColumns (DRagLint.FieldRepo.FbImport.pas) ?, DRagLint.FieldRepo.Schema.Col (DRagLint.FieldRepo.Schema.pas) ?, DRagLint.FieldRepo.Schema.Str (DRagLint.FieldRepo.Schema.pas) ?, DRagLint.FieldRepo.Schema.TRepoTable.FindColumn (DRagLint.FieldRepo.Schema.pas) (+17 more)</para>
  /// <para>Used in units: DRagLint.FieldRepo.FbImport, DRagLint.FieldRepo.Schema, DRagLint.FieldRepo.SchemaSeed, DRagLint.FieldRepo.TextBackup</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.FbImport.pas) ?, DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas) ?, DRagLint.CLI.Repo.RepoInfo (DRagLint.CLI.Repo.pas) ?, DRagLint.FieldRepo.FbImport.CheckSourceColumns (DRagLint.FieldRepo.FbImport.pas) ?, DRagLint.FieldRepo.Schema.FindRepoTable (DRagLint.FieldRepo.Schema.pas) (+29 more)</para>
  /// <para>Used in units: DRagLint.CLI.Repo, DRagLint.FieldRepo.FbImport, DRagLint.FieldRepo.Schema, DRagLint.FieldRepo.SchemaSeed, DRagLint.FieldRepo.TextBackup</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRepoTable = record
    /// <summary>Table name, e.g. 'DL_FIELDS_INFO'.</summary>
    Name: string;
    /// <summary>Firebird source table, e.g. 'FIB$FIELDS_INFO'; '' for DL_META.</summary>
    SourceName: string;
    /// <summary>Columns in declaration order.</summary>
    Columns: TArray<TRepoColumn>;
    /// <summary>Key columns in PkOrder.</summary>
    /// <returns>The primary-key columns, ordered by PkOrder.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.Schema.RepoTableDdl (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.TextBackup.OrderByClause (DRagLint.FieldRepo.TextBackup.pas), DRagLint.FieldRepo.TextBackup.RecordHeader (DRagLint.FieldRepo.TextBackup.pas), DRagLint.FieldRepo.TextBackup.TBackupParser.ParseRecord (DRagLint.FieldRepo.TextBackup.pas)</para>
    /// <para>Returns: List.ToArray</para>
    /// <para>Reads: Columns</para>
    /// <seealso cref="DRagLint.FieldRepo.Schema.TRepoTable.FindColumn"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PkColumns: TArray<TRepoColumn>;
    /// <summary>Looks a column up by name, case-insensitively.</summary>
    /// <param name="pName">Column name.</param>
    /// <param name="pColumn">Receives the column when found.</param>
    /// <returns>True when the column exists.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.FbImport.CheckSourceColumns (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.Schema.ValidateColumns (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.SchemaSeed.TSeedRun.LoadColumnLimits (DRagLint.FieldRepo.SchemaSeed.pas)</para>
    /// <para>Calls: Default, SameText</para>
    /// <para>Returns: False; True</para>
    /// <para>Reads: Columns</para>
    /// <para>Mutates: pColumn (out)</para>
    /// <seealso cref="DRagLint.FieldRepo.Schema.TRepoTable.PkColumns"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindColumn(const pName: string; out pColumn: TRepoColumn): Boolean;
  end;

/// <summary>The five repository tables in the fixed order DL_META, DL_FIELDS_INFO,
/// DL_DATASETS_INFO, DL_ENUMVALUES, DL_ERROR_MESSAGES.</summary>
/// <returns>A fresh array of table descriptions.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoInfo (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.Schema.CreateRepository (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.Schema.FindRepoTable (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.Schema.RepoIsEmpty (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.Schema.ValidateRepository (DRagLint.FieldRepo.Schema.pas) (+2 more)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.DatasetsInfoTable, DRagLint.FieldRepo.Schema.EnumValuesTable, DRagLint.FieldRepo.Schema.ErrorMessagesTable, DRagLint.FieldRepo.Schema.FieldsInfoTable, DRagLint.FieldRepo.Schema.MetaTable</para>
/// <para>Returns: [MetaTable, FieldsInfoTable, DatasetsInfoTable, EnumValuesTable, ErrorMessagesTable]</para>
/// <para>Effect-free (proven)</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.DatasetsInfoTable"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.EnumValuesTable"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.ErrorMessagesTable"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.FieldsInfoTable"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.MetaTable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RepoTables: TArray<TRepoTable>;  // dl:ok unused-public-symbol@15fa

/// <summary>Looks a repository table up by name, case-insensitively.</summary>
/// <param name="pName">Table name.</param>
/// <param name="pTable">Receives the table when found.</param>
/// <returns>True when the table exists.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.FbImport.ImportFromFirebird (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.Schema.RepoRowCount (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.SchemaSeed.TSeedRun.LoadColumnLimits (DRagLint.FieldRepo.SchemaSeed.pas), DRagLint.FieldRepo.TextBackup.TBackupParser.ParseRecord (DRagLint.FieldRepo.TextBackup.pas)</para>
/// <para>Calls: Default, DRagLint.FieldRepo.Schema.RepoTables, SameText</para>
/// <para>Returns: False; True</para>
/// <para>Mutates: pTable (out)</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoTables"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindRepoTable(const pName: string; out pTable: TRepoTable): Boolean;  // dl:ok unused-public-symbol@c8d7

/// <summary>Quotes an identifier for SQLite with double quotes. Every SQL statement
/// of every lane quotes identifiers through this function.</summary>
/// <param name="pName">Unquoted identifier.</param>
/// <returns>The identifier in double quotes, embedded quotes doubled.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.FbImport.ImportFromFirebird (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.FbImport.ImportOneTable (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.FbImport.InsertSql (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.Schema.ColumnDdl (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.Schema.GetRepoMeta (DRagLint.FieldRepo.Schema.pas) (+11 more)</para>
/// <para>Returns: '"' + pName.Replace('"', '""') + '"'</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function QuoteRepoIdent(const pName: string): string;  // dl:ok unused-public-symbol@0e28

/// <summary>Builds the CREATE TABLE statement for a table: SQLite declared type per kind,
/// NOT NULL, DEFAULT, a length CHECK for strings, a 0..255 CHECK for bytes, and the primary
/// key (inline for a single integer key, table-level otherwise).</summary>
/// <param name="pTable">Table description.</param>
/// <returns>The DDL text.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.Schema.CreateRepository (DRagLint.FieldRepo.Schema.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.ColumnDdl, DRagLint.FieldRepo.Schema.QuoteRepoIdent, DRagLint.FieldRepo.Schema.TRepoTable.PkColumns</para>
/// <para>Returns: 'CREATE TABLE ' + QuoteRepoIdent(pTable.Name) + ' (' + sLineBreak + '  '</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.ColumnDdl"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.QuoteRepoIdent"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.TRepoTable.PkColumns"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RepoTableDdl(const pTable: TRepoTable): string;  // dl:ok unused-public-symbol@5822

/// <summary>Default repository path of a project: the project folder, then
/// REPO_FOLDER_NAME, then the project base name with REPO_FILE_EXT.</summary>
/// <param name="pProjectFile">Full path of the project file.</param>
/// <returns>For C:\P\App.dproj: C:\P\_DL-REPO\App.dlrepo.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.ResolveRepoPath (DRagLint.CLI.Repo.pas)</para>
/// <para>Calls: ExtractFilePath</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DefaultRepoPath(const pProjectFile: string): string;  // dl:ok unused-public-symbol@4257

/// <summary>Creates a new repository file with all five tables.</summary>
/// <param name="pFileName">Target file; its folder is created.</param>
/// <exception cref="ERepoError">The file already exists.</exception>
/// <remarks>
/// Sets application_id and user_version, journal_mode=DELETE, creates the tables
/// in one transaction and writes DL_META.schema_version.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.OpenOrCreateRepo (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoInit (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoRestore (DRagLint.CLI.Repo.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.NewConnection, DRagLint.FieldRepo.Schema.RepoTableDdl, DRagLint.FieldRepo.Schema.RepoTables, DRagLint.FieldRepo.Schema.SetRepoMeta, ExpandFileName, ExtractFilePath, IntToStr</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>Touches: file system</para>
/// <para>Transaction: starts, commits, rolls back</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.NewConnection"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoTableDdl"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoTables"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.SetRepoMeta"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure CreateRepository(const pFileName: string);  // dl:ok unused-public-symbol@3469

/// <summary>Opens an existing repository and validates it.</summary>
/// <param name="pFileName">Repository file.</param>
/// <param name="pReadOnly">True opens with OpenMode=ReadOnly.</param>
/// <returns>A connected connection; the caller frees it. Its FormatOptions.StrsTrim is
/// False, so every dataset on it keeps trailing blanks.</returns>
/// <exception cref="ERepoError">The file is missing (it is never created).</exception>
/// <exception cref="ERepoSchemaError">The file is not a repository of this version.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.OpenOrCreateRepo (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoBackup (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoInfo (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoRestore (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.DataServiceGen.RunOrmGenVerb (DRagLint.FieldRepo.DataServiceGen.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.NewConnection, DRagLint.FieldRepo.Schema.ValidateRepository</para>
/// <para>Returns: NewConnection(pFileName, if pReadOnly then 'ReadOnly' else 'ReadWrite')</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.NewConnection"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.ValidateRepository"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OpenRepository(const pFileName: string; pReadOnly: Boolean): TFDConnection;  // dl:ok unused-public-symbol@f329

/// <summary>Checks application_id, user_version, every table and every column.</summary>
/// <param name="pConnection">A connected SQLite connection.</param>
/// <exception cref="ERepoSchemaError">Names the first mismatch found.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.Schema.OpenRepository (DRagLint.FieldRepo.Schema.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.RepoTables, DRagLint.FieldRepo.Schema.ValidateColumns</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoTables"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.ValidateColumns"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ValidateRepository(pConnection: TFDConnection);  // dl:ok unused-public-symbol@83e8

/// <summary>Number of rows of a repository table.</summary>
/// <param name="pConnection">An open repository connection.</param>
/// <param name="pTableName">A repository table name.</param>
/// <returns>The row count.</returns>
/// <exception cref="ERepoError">The table is not a repository table.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoInfo (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.Schema.RepoIsEmpty (DRagLint.FieldRepo.Schema.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.FindRepoTable, DRagLint.FieldRepo.Schema.QuoteRepoIdent</para>
/// <para>Returns: pConnection.ExecSQLScalar('SELECT COUNT(*) FROM ' + QuoteRepoIdent(Tab.Name))</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.FindRepoTable"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.QuoteRepoIdent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RepoRowCount(pConnection: TFDConnection; const pTableName: string): Integer;  // dl:ok unused-public-symbol@9768

/// <summary>True when every repository table except DL_META has no rows.</summary>
/// <param name="pConnection">An open repository connection.</param>
/// <returns>True for a freshly created repository.</returns>
/// <exception cref="ERepoError"><!-- drag-lint:auto exc -->via DRagLint.FieldRepo.Schema.RepoRowCount: Not a repository table: %s</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.FbImport.ImportFromFirebird (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.SchemaSeed.RunSchemaSeed (DRagLint.FieldRepo.SchemaSeed.pas), DRagLint.FieldRepo.TextBackup.RestoreRepositoryFromStrings (DRagLint.FieldRepo.TextBackup.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.RepoRowCount, DRagLint.FieldRepo.Schema.RepoTables, SameText</para>
/// <para>Returns: True; False</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoRowCount"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoTables"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RepoIsEmpty(pConnection: TFDConnection): Boolean;  // dl:ok unused-public-symbol@370b

/// <summary>Writes (inserts or replaces) one DL_META value.</summary>
/// <param name="pConnection">A read-write repository connection.</param>
/// <param name="pKey">Meta key.</param>
/// <param name="pValue">Meta value.</param>
/// <remarks>
/// A read-only connection raises the driver's exception.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoSeed (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.FbImport.ImportFromFirebird (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.Schema.CreateRepository (DRagLint.FieldRepo.Schema.pas), DRagLint.FieldRepo.SchemaSeed.TSeedRun.Execute (DRagLint.FieldRepo.SchemaSeed.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.QuoteRepoIdent</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.QuoteRepoIdent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SetRepoMeta(pConnection: TFDConnection; const pKey, pValue: string);  // dl:ok unused-public-symbol@419a

/// <summary>Reads one DL_META value.</summary>
/// <param name="pConnection">An open repository connection.</param>
/// <param name="pKey">Meta key.</param>
/// <returns>The value, or '' when the key is absent.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DRagLint.FieldRepo.Schema.QuoteRepoIdent</para>
/// <para>Returns: if Q.Eof then ''</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.QuoteRepoIdent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
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
  MAX_BYTE = 255;

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
  Result := MakeTable(REPO_META_TABLE, '', [
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
  List: TList<TRepoColumn>;
  ColItem: TRepoColumn;
  Order: Integer;
begin
  List := TList<TRepoColumn>.Create;
  try
    for Order := 1 to Length(Columns) do
      for ColItem in Columns do
        if ColItem.PkOrder = Order then
          List.Add(ColItem);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TRepoTable.FindColumn(const pName: string; out pColumn: TRepoColumn): Boolean;
var
  ColItem: TRepoColumn;
begin
  Result := False;
  pColumn := Default(TRepoColumn);
  for ColItem in Columns do
    if SameText(ColItem.Name, pName) then
    begin
      pColumn := ColItem;
      Exit(True);
    end;
end;

function FindRepoTable(const pName: string; out pTable: TRepoTable): Boolean;
var
  Tab: TRepoTable;
begin
  Result := False;
  pTable := Default(TRepoTable);
  for Tab in RepoTables do
    if SameText(Tab.Name, pName) then
    begin
      pTable := Tab;
      Exit(True);
    end;
end;

function QuoteRepoIdent(const pName: string): string;
begin
  Result := '"' + pName.Replace('"', '""') + '"';
end;

function ColumnDdl(const pCol: TRepoColumn; pInlinePk: Boolean): string;
var
  Q: string;
begin
  Q := QuoteRepoIdent(pCol.Name);
  case pCol.Kind of
    rckString:   Result := Q + ' VARCHAR(' + IntToStr(pCol.MaxLen) + ')';
    rckInteger:  Result := Q + ' INTEGER';
    rckSmallint: Result := Q + ' SMALLINT';
    rckBoolean:  Result := Q + ' BOOLEAN';
    rckText:     Result := Q + ' TEXT';
  else
    Result := Q + ' SMALLINT';
  end;
  if pCol.NotNull then
    Result := Result + ' NOT NULL';
  if pInlinePk then
    Result := Result + ' PRIMARY KEY';
  if pCol.DefaultSql <> '' then
    Result := Result + ' DEFAULT ' + pCol.DefaultSql;
  if pCol.Kind = rckString then
    Result := Result + ' CHECK (length(' + Q + ') <= ' + IntToStr(pCol.MaxLen) + ')';
  if pCol.Kind = rckByte then
    Result := Result + ' CHECK (' + Q + ' BETWEEN 0 AND ' + IntToStr(MAX_BYTE) + ')';
end;

function RepoTableDdl(const pTable: TRepoTable): string;
var
  Pk: TArray<TRepoColumn>;
  InlineVal: Boolean;
  ColItem: TRepoColumn;
  Parts: TStringList;
  Keys: string;
  I: Integer;
begin
  Pk := pTable.PkColumns;
  InlineVal := (Length(Pk) = 1) and (Pk[0].Kind = rckInteger);
  Parts := TStringList.Create;
  try
    for ColItem in pTable.Columns do
      Parts.Add(ColumnDdl(ColItem, InlineVal and (ColItem.PkOrder = 1)));
    if (Length(Pk) > 0) and not InlineVal then
    begin
      Keys := '';
      for I := 0 to High(Pk) do
        Keys := Keys + (if I > 0 then ', ' else '') + QuoteRepoIdent(Pk[I].Name);
      Parts.Add('PRIMARY KEY (' + Keys + ')');
    end;
    Result := 'CREATE TABLE ' + QuoteRepoIdent(pTable.Name) + ' (' + sLineBreak + '  '
      + string.Join(',' + sLineBreak + '  ', Parts.ToStringArray) + sLineBreak + ')';
  finally
    Parts.Free;
  end;
end;

function DefaultRepoPath(const pProjectFile: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ExtractFilePath(pProjectFile), REPO_FOLDER_NAME),
    TPath.GetFileNameWithoutExtension(pProjectFile) + REPO_FILE_EXT);
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
  except  // dl:ok bare-except@041e -- cleanup then re-raise, nothing swallowed
    Result.Free;
    raise;
  end;
end;

procedure CreateRepository(const pFileName: string);
var
  Conn: TFDConnection;
  Tab: TRepoTable;
begin
  if TFile.Exists(pFileName) then
    raise ERepoError.CreateFmt('Repository already exists: %s', [pFileName]);
  TDirectory.CreateDirectory(ExtractFilePath(ExpandFileName(pFileName)));
  Conn := NewConnection(pFileName, 'CreateUTF8');
  try
    Conn.ExecSQL('PRAGMA application_id = ' + IntToStr(REPO_APPLICATION_ID));
    Conn.ExecSQL('PRAGMA user_version = ' + IntToStr(REPO_SCHEMA_VERSION));
    Conn.ExecSQLScalar('PRAGMA journal_mode = DELETE');
    Conn.StartTransaction;
    try
      for Tab in RepoTables do
        Conn.ExecSQL(RepoTableDdl(Tab));
      SetRepoMeta(Conn, 'schema_version', IntToStr(REPO_SCHEMA_VERSION));
      Conn.Commit;
    except  // dl:ok bare-except@05ca -- cleanup then re-raise, nothing swallowed
      Conn.Rollback;
      raise;
    end;
  finally
    Conn.Free;
  end;
end;

procedure ValidateColumns(pConnection: TFDConnection; const pTable: TRepoTable);
var
  Q: TFDQuery;
  Seen: TStringList;
  ColItem: TRepoColumn;
  Name: string;
  NameField: TField;
begin
  Seen := TStringList.Create;
  Q := TFDQuery.Create(nil);
  try
    Seen.CaseSensitive := False;
    Q.Connection := pConnection;
    Q.Open('PRAGMA table_info(' + QuoteRepoIdent(pTable.Name) + ')');  // dl:ok path-traversal@de2f -- SQL text, not a path: the identifier goes through QuoteRepoIdent
    NameField := Q.FieldByName('name');
    while not Q.Eof do
    begin
      Name := NameField.AsString;
      Seen.Add(Name);
      if not pTable.FindColumn(Name, ColItem) then
        raise ERepoSchemaError.CreateFmt('Unexpected column %s.%s', [pTable.Name, Name]);
      Q.Next;
    end;
    if Seen.Count = 0 then
      raise ERepoSchemaError.CreateFmt('Missing table %s', [pTable.Name]);
    for ColItem in pTable.Columns do
      if Seen.IndexOf(ColItem.Name) < 0 then
        raise ERepoSchemaError.CreateFmt('Missing column %s.%s', [pTable.Name, ColItem.Name]);
  finally
    Q.Free;
    Seen.Free;
  end;
end;

procedure ValidateRepository(pConnection: TFDConnection);
var
  Id, Ver: Integer;
  Tab: TRepoTable;
begin
  Id := pConnection.ExecSQLScalar('PRAGMA application_id');
  if Id <> REPO_APPLICATION_ID then
    raise ERepoSchemaError.CreateFmt('Not a field repository: application_id is %d, expected %d',
      [Id, REPO_APPLICATION_ID]);
  Ver := pConnection.ExecSQLScalar('PRAGMA user_version');
  if Ver <> REPO_SCHEMA_VERSION then
    raise ERepoSchemaError.CreateFmt('Unsupported repository schema: user_version is %d, expected %d',
      [Ver, REPO_SCHEMA_VERSION]);
  for Tab in RepoTables do
    ValidateColumns(pConnection, Tab);
end;

function OpenRepository(const pFileName: string; pReadOnly: Boolean): TFDConnection;
begin
  if not TFile.Exists(pFileName) then
    raise ERepoError.CreateFmt('Repository not found: %s', [pFileName]);
  Result := NewConnection(pFileName, if pReadOnly then 'ReadOnly' else 'ReadWrite');
  try
    // Repository text is byte-exact (trailing blanks are data): every dataset on this
    // connection inherits StrsTrim = False, so readers need not set it per query.
    Result.FormatOptions.StrsTrim := False;
    ValidateRepository(Result);
  except  // dl:ok bare-except@041e -- cleanup then re-raise, nothing swallowed
    Result.Free;
    raise;
  end;
end;

function RepoRowCount(pConnection: TFDConnection; const pTableName: string): Integer;
var
  Tab: TRepoTable;
begin
  if not FindRepoTable(pTableName, Tab) then
    raise ERepoError.CreateFmt('Not a repository table: %s', [pTableName]);
  Result := pConnection.ExecSQLScalar('SELECT COUNT(*) FROM ' + QuoteRepoIdent(Tab.Name));
end;

function RepoIsEmpty(pConnection: TFDConnection): Boolean;
var
  Tab: TRepoTable;
begin
  Result := True;
  for Tab in RepoTables do
    if (not SameText(Tab.Name, REPO_META_TABLE)) and (RepoRowCount(pConnection, Tab.Name) > 0) then
      Exit(False);
end;

procedure SetRepoMeta(pConnection: TFDConnection; const pKey, pValue: string);
begin
  pConnection.ExecSQL('INSERT OR REPLACE INTO ' + QuoteRepoIdent(REPO_META_TABLE)
    + ' ("META_KEY", "META_VALUE") VALUES (:k, :v)', [pKey, pValue]);
end;

function GetRepoMeta(pConnection: TFDConnection; const pKey: string): string;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := pConnection;
    Q.Open('SELECT "META_VALUE" FROM ' + QuoteRepoIdent(REPO_META_TABLE) + ' WHERE "META_KEY" = :k', [pKey]);  // dl:ok path-traversal@7615 -- SQL text, not a path: the identifier goes through QuoteRepoIdent
    Result := if Q.Eof then '' else Q.Fields[0].AsString;
  finally
    Q.Free;
  end;
end;

end.
