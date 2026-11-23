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
  /// <summary>Schema version a NEW repository is created with; mirrored in PRAGMA user_version and DL_META.
  /// Version 2 (1.53) adds DL_FIELDS_INFO.CALC_BODY, DL_LAYOUT_EVENTS and DL_EXCEPTIONS.</summary>
  REPO_SCHEMA_VERSION = 2;
  /// <summary>Oldest schema version OpenRepository still accepts (1 = the 1.52 five-table layout).</summary>
  REPO_SCHEMA_MIN_VERSION = 1;
  /// <summary>Name of the layout event code table (schema 2): event code of non-DBTable layouts.</summary>
  REPO_TABLE_LAYOUT_EVENTS = 'DL_LAYOUT_EVENTS';
  /// <summary>Name of the lint exception table (schema 2).</summary>
  REPO_TABLE_EXCEPTIONS = 'DL_EXCEPTIONS';
  /// <summary>Schema-fact tables (schema 2, FR-SCHEMA): written only by the DB-to-repository change set.</summary>
  REPO_TABLE_DOMAINS = 'DL_DOMAINS';
  REPO_TABLE_CONSTRAINTS = 'DL_CONSTRAINTS';
  REPO_TABLE_CONSTRAINT_COLUMNS = 'DL_CONSTRAINT_COLUMNS';
  REPO_TABLE_GENERATORS = 'DL_GENERATORS';
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
function RepoTables: TArray<TRepoTable>;  // dl:ok unused-public-symbol@15fa -- REVIEWED 2026-11-22 FR-SCHEMA: public API of the schema-in-repository feature: used by the CLI / tests / lane FR-LINT, outside this project index

/// <summary>The table set of one schema version: v1 = the five 1.52 tables; v2 = the same order with
/// DL_FIELDS_INFO.CALC_BODY appended as its last column, then DL_LAYOUT_EVENTS and DL_EXCEPTIONS.
/// RepoTables is RepoTablesFor(REPO_SCHEMA_VERSION).</summary>
/// <param name="pVersion">1 or 2.</param>
/// <returns>A fresh array of table descriptions.</returns>
/// <exception cref="ERepoError">The version is outside REPO_SCHEMA_MIN_VERSION..REPO_SCHEMA_VERSION.</exception>
function RepoTablesFor(pVersion: Integer): TArray<TRepoTable>;

/// <summary>Reads PRAGMA user_version of an open repository connection.</summary>
/// <param name="pConnection">A connected SQLite connection.</param>
/// <returns>The schema version stored in the file.</returns>
function RepoSchemaVersion(pConnection: TFDConnection): Integer;

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
function FindRepoTable(const pName: string; out pTable: TRepoTable): Boolean;

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
function QuoteRepoIdent(const pName: string): string;

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
function RepoTableDdl(const pTable: TRepoTable): string;

/// <summary>The column definition of one column, as used inside CREATE TABLE and ALTER TABLE ADD COLUMN.</summary>
/// <param name="pCol">The column.</param>
/// <param name="pInlinePk">True to append an inline PRIMARY KEY (single-column keys only).</param>
/// <returns>E.g. "DOMAIN_NAME" VARCHAR(68) CHECK (length("DOMAIN_NAME") &lt;= 68).</returns>
function ColumnDdl(const pCol: TRepoColumn; pInlinePk: Boolean): string;

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
function DefaultRepoPath(const pProjectFile: string): string;

/// <summary>Creates a new repository file with every table of the given schema version.</summary>
/// <param name="pFileName">Target file; its folder is created.</param>
/// <param name="pVersion">Schema version to create; default REPO_SCHEMA_VERSION (2). 1 exists for
/// restoring a `#DLREPO 1` backup into a missing file and for tests.</param>
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
procedure CreateRepository(const pFileName: string; pVersion: Integer = REPO_SCHEMA_VERSION);

/// <summary>Opens an existing repository and validates it against the table set of ITS OWN
/// schema version (1 or 2).</summary>
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
function OpenRepository(const pFileName: string; pReadOnly: Boolean): TFDConnection;

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
function RepoRowCount(pConnection: TFDConnection; const pTableName: string): Integer;

/// <summary>True when every repository table except DL_META, DL_LAYOUT_EVENTS and DL_EXCEPTIONS
/// has no rows (the two schema-2 tables are user data a seed / import never writes, so they do not
/// make a repository "non-empty"). Counts only the tables of the file's own schema version.</summary>
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
function RepoIsEmpty(pConnection: TFDConnection): Boolean;

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
procedure SetRepoMeta(pConnection: TFDConnection; const pKey, pValue: string);

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
function GetRepoMeta(pConnection: TFDConnection; const pKey: string): string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
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

function FieldsInfoTable(pVersion: Integer): TRepoTable;
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
  if pVersion >= 2 then
    Result.Columns := Result.Columns + [Txt('CALC_BODY'), Str('DOMAIN_NAME', 68),  // dl:ok large-magic-number@660f, magic-literal@660f
      Col('CHAR_LENGTH', rckInteger, 0, False, '', 0)];
end;

function DomainsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_DOMAINS, '', [
    Str('DOMAIN_NAME', 68, True, 1),  // dl:ok large-magic-number@2380, magic-literal@2380
    Small('FIELD_TYPE'), Small('FIELD_SUBTYPE'), Small('FIELD_LENGTH'),
    Col('CHAR_LENGTH', rckInteger, 0, False, '', 0),
    Small('FIELD_SCALE'), Small('FIELD_PRECISION'), Small('NULL_FLAG'),
    Txt('DEFAULT_SOURCE'), Txt('CHECK_SOURCE'), Str('CHARSET', 63)]);  // dl:ok large-magic-number@6836, magic-literal@6836
end;

function ConstraintsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_CONSTRAINTS, '', [
    Str('CONSTRAINT_NAME', 68, True, 1),  // dl:ok large-magic-number@3079, magic-literal@3079
    Str('TABLE_NAME', 68, True),  // dl:ok large-magic-number@8300, magic-literal@8300
    Str('KIND', 10, True),  // dl:ok magic-literal@d647
    Str('REF_TABLE', 68),  // dl:ok large-magic-number@0f40, magic-literal@0f40
    Str('REF_CONSTRAINT', 68),  // dl:ok large-magic-number@9139, magic-literal@9139
    Str('UPDATE_RULE', 11),  // dl:ok magic-literal@941e
    Str('DELETE_RULE', 11)]);  // dl:ok magic-literal@cbf5
end;

function ConstraintColumnsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_CONSTRAINT_COLUMNS, '', [
    Str('CONSTRAINT_NAME', 68, True, 1),  // dl:ok large-magic-number@3079, magic-literal@3079
    Col('POSITION', rckInteger, 0, True, '', 2),
    Str('COLUMN_NAME', 68, True)]);  // dl:ok large-magic-number@bb5d, magic-literal@bb5d
end;

function GeneratorsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_GENERATORS, '', [Str('GENERATOR_NAME', 68, True, 1)]);  // dl:ok large-magic-number@5823, magic-literal@5823
end;

function LayoutEventsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_LAYOUT_EVENTS, '', [
    Str('TABLE_NAME', 68, True, 1),  // dl:ok large-magic-number@fcb2, magic-literal@fcb2 -- REVIEWED 2026-11-22 FR-SCHEMA: column width of a schema table definition, named by the column beside it
    Str('FIELD_NAME', 68, True, 2),  // dl:ok large-magic-number@b55c, magic-literal@b55c -- REVIEWED 2026-11-22 FR-SCHEMA: column width of a schema table definition, named by the column beside it
    Str('LAYOUT_TYPE', 40, True, 3),  // dl:ok large-magic-number@146b, magic-literal@146b -- REVIEWED 2026-11-22 FR-SCHEMA: column width of a schema table definition, named by the column beside it
    Str('EVENT_NAME', 63, True, 4),  // dl:ok large-magic-number@9b9c, magic-literal@9b9c -- REVIEWED 2026-11-22 FR-SCHEMA: column width of a schema table definition, named by the column beside it
    Txt('EVENT_CODE')]);
end;

function ExceptionsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_EXCEPTIONS, '', [
    Col('RULE_ID', rckString, 63, True, '', 1),  // dl:ok large-magic-number@a7be, magic-literal@a7be -- REVIEWED 2026-11-22 FR-SCHEMA: column width of a schema table definition, named by the column beside it
    Col('DATASET_KEY', rckString, 255, True, '''''', 2),  // dl:ok magic-literal@d044 -- REVIEWED 2026-11-22 FR-SCHEMA: column width / type code of a schema table definition, named by the column beside it
    Col('TABLE_NAME', rckString, 68, True, '''''', 3),  // dl:ok large-magic-number@c1a7, magic-literal@c1a7 -- REVIEWED 2026-11-22 FR-SCHEMA: column width of a schema table definition, named by the column beside it
    Col('FIELD_NAME', rckString, 68, True, '''''', 4),  // dl:ok large-magic-number@c92f, magic-literal@c92f -- REVIEWED 2026-11-22 FR-SCHEMA: column width of a schema table definition, named by the column beside it
    Col('PROP', rckString, 63, True, '''''', 5),  // dl:ok large-magic-number@6727, magic-literal@6727 -- REVIEWED 2026-11-22 FR-SCHEMA: column width of a schema table definition, named by the column beside it
    Str('REASON', 220, True)]);  // dl:ok large-magic-number@4ec3, magic-literal@4ec3 -- REVIEWED 2026-11-22 FR-SCHEMA: column width of a schema table definition, named by the column beside it
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

function RepoTablesFor(pVersion: Integer): TArray<TRepoTable>;
begin
  if (pVersion < REPO_SCHEMA_MIN_VERSION) or (pVersion > REPO_SCHEMA_VERSION) then
    raise ERepoError.CreateFmt('Unknown repository schema version %d', [pVersion]);
  Result := [MetaTable, FieldsInfoTable(pVersion), DatasetsInfoTable, EnumValuesTable, ErrorMessagesTable];
  if pVersion >= 2 then
    Result := Result + [LayoutEventsTable, ExceptionsTable, DomainsTable, ConstraintsTable,
      ConstraintColumnsTable, GeneratorsTable];
end;

function RepoTables: TArray<TRepoTable>;
begin
  Result := RepoTablesFor(REPO_SCHEMA_VERSION);
end;

function RepoSchemaVersion(pConnection: TFDConnection): Integer;
begin
  Result := pConnection.ExecSQLScalar('PRAGMA user_version');
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
  except
    Result.Free;
    raise;
  end;
end;

procedure CreateRepository(const pFileName: string; pVersion: Integer);
var
  Conn: TFDConnection;
  Tab: TRepoTable;
  Tables: TArray<TRepoTable>;
begin
  Tables := RepoTablesFor(pVersion);
  if TFile.Exists(pFileName) then
    raise ERepoError.CreateFmt('Repository already exists: %s', [pFileName]);
  TDirectory.CreateDirectory(ExtractFilePath(ExpandFileName(pFileName)));
  Conn := NewConnection(pFileName, 'CreateUTF8');
  try
    Conn.ExecSQL('PRAGMA application_id = ' + IntToStr(REPO_APPLICATION_ID));
    Conn.ExecSQL('PRAGMA user_version = ' + IntToStr(pVersion));
    Conn.ExecSQLScalar('PRAGMA journal_mode = DELETE');
    Conn.StartTransaction;
    try
      for Tab in Tables do
        Conn.ExecSQL(RepoTableDdl(Tab));
      SetRepoMeta(Conn, 'schema_version', IntToStr(pVersion));
      Conn.Commit;
    except
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
  if (Ver < REPO_SCHEMA_MIN_VERSION) or (Ver > REPO_SCHEMA_VERSION) then
    raise ERepoSchemaError.CreateFmt('Unsupported repository schema: user_version is %d, expected %d..%d',
      [Ver, REPO_SCHEMA_MIN_VERSION, REPO_SCHEMA_VERSION]);
  for Tab in RepoTablesFor(Ver) do
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
  except
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
  for Tab in RepoTablesFor(RepoSchemaVersion(pConnection)) do
    if (not SameText(Tab.Name, REPO_META_TABLE)) and (not SameText(Tab.Name, REPO_TABLE_LAYOUT_EVENTS))  // dl:ok boolean-expression-complexity@dcf7 -- REVIEWED 2026-11-22 FR-SCHEMA: one token-class test of the DDL grammar, kept whole so the accepted forms read in one place
      and (not SameText(Tab.Name, REPO_TABLE_EXCEPTIONS)) and (not SameText(Tab.Name, REPO_TABLE_DOMAINS))
      and (not SameText(Tab.Name, REPO_TABLE_CONSTRAINTS)) and (not SameText(Tab.Name, REPO_TABLE_CONSTRAINT_COLUMNS))
      and (not SameText(Tab.Name, REPO_TABLE_GENERATORS)) and (RepoRowCount(pConnection, Tab.Name) > 0) then
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
