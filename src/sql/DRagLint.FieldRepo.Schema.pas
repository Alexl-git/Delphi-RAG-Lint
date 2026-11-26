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
  /// Version 2 (1.53) adds DL_FIELDS_INFO.CALC_BODY, DL_LAYOUT_EVENTS and DL_EXCEPTIONS; version 3 (1.54) the six event
  /// columns of DL_FIELDS_INFO and DL_GRID_COLUMNS; version 4 (1.55) DL_RELATIONS, DL_RELATION_COLUMNS and
  /// DL_FIELD_INPUTS (design 2026-11-26-cross-table-fields-design.md 2.2).</summary>
  REPO_SCHEMA_VERSION = 4;
  /// <summary>Oldest schema version OpenRepository still accepts (1 = the 1.52 five-table layout).</summary>
  REPO_SCHEMA_MIN_VERSION = 1;
  /// <summary>Name of the layout event code table (schema 2): event code of non-DBTable layouts and of views (FIELD_NAME '').</summary>
  REPO_TABLE_LAYOUT_EVENTS = 'DL_LAYOUT_EVENTS';
  /// <summary>Name of the lint exception table (schema 2).</summary>
  REPO_TABLE_EXCEPTIONS = 'DL_EXCEPTIONS';
  /// <summary>Name of the grid column order table (schema 3): one row per form + grid view + column.</summary>
  REPO_TABLE_GRID_COLUMNS = 'DL_GRID_COLUMNS';
  /// <summary>LAYOUT_TYPE 1.54 development builds gave a TField event in DL_LAYOUT_EVENTS. The event columns of schema 3
  /// replaced it: migration moves such rows, `repo check` reports one that is left.</summary>
  REPO_LAYOUT_FIELD = 'Field';
  /// <summary>Schema-fact tables (schema 2, FR-SCHEMA): written only by the DB-to-repository change set.</summary>
  REPO_TABLE_DOMAINS = 'DL_DOMAINS';
  REPO_TABLE_CONSTRAINTS = 'DL_CONSTRAINTS';
  REPO_TABLE_CONSTRAINT_COLUMNS = 'DL_CONSTRAINT_COLUMNS';
  REPO_TABLE_GENERATORS = 'DL_GENERATORS';
  /// <summary>Cross-table tables (schema 4): one N:1 step from a child row to ONE parent row, its column pairs,
  /// and the input aliases of a field (`{{ALIAS.FIELD}}`) with the path each one follows.</summary>
  REPO_TABLE_RELATIONS = 'DL_RELATIONS';
  REPO_TABLE_RELATION_COLUMNS = 'DL_RELATION_COLUMNS';
  REPO_TABLE_FIELD_INPUTS = 'DL_FIELD_INPUTS';
  /// <summary>DL_RELATIONS.SOURCE values: a declared foreign key, a join found in a form and confirmed, added by hand.</summary>
  REPO_RELATION_FK = 'FK';
  REPO_RELATION_FORM = 'FORM';
  REPO_RELATION_HAND = 'HAND';
  /// <summary>Separator of the relation names in DL_FIELD_INPUTS.PATH.</summary>
  REPO_PATH_SEPARATOR = '>';
  /// <summary>SQLite application_id of a field repository ('DLFR').</summary>
  REPO_APPLICATION_ID = $444C4652;
  /// <summary>File extension of a repository file.</summary>
  REPO_FILE_EXT = '.dlrepo';
  /// <summary>Folder (next to the project file) that holds the default repository.</summary>
  REPO_FOLDER_NAME = '_DL-REPO';
  /// <summary>Name of the key/value table with repository metadata.</summary>
  REPO_META_TABLE = 'DL_META';

type
  /// <summary>Number of rows each data step of a migration changes.</summary>
  TRepoRowChanges = record
    /// <summary>ISCALCULATED rows whose FIELD_KIND is NULL or 1.</summary>
    CalcRows: Integer;
    /// <summary>Rows with ALIGNMENT -2.</summary>
    AlignmentRows: Integer;
    /// <summary>DL_LAYOUT_EVENTS rows of layout type Field that have an event column and a field row.</summary>
    EventRows: Integer;
  end;

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
/// DL_FIELDS_INFO.CALC_BODY appended as its last column, then DL_LAYOUT_EVENTS and DL_EXCEPTIONS; v3 = v2 with the six
/// event columns appended to DL_FIELDS_INFO, then DL_GRID_COLUMNS; v4 = v3, then DL_RELATIONS, DL_RELATION_COLUMNS and
/// DL_FIELD_INPUTS. RepoTables is RepoTablesFor(REPO_SCHEMA_VERSION).</summary>
/// <param name="pVersion">1, 2, 3 or 4.</param>
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
/// <param name="pVersion">Schema version to create; default REPO_SCHEMA_VERSION (3). 1 and 2 exist for
/// restoring an older backup into a missing file and for tests.</param>
/// <exception cref="ERepoError">The file already exists.</exception>
/// <remarks>
/// Sets application_id and user_version, journal_mode=DELETE, creates the tables
/// in one transaction and writes DL_META.schema_version.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.OpenOrCreateRepo (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoInit (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoRestore (DRagLint.CLI.Repo.pas), DRagLint.CLI.RepoSchema.SyncOnRepo (DRagLint.CLI.RepoSchema.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.NewConnection, DRagLint.FieldRepo.Schema.RepoTableDdl, DRagLint.FieldRepo.Schema.RepoTablesFor, DRagLint.FieldRepo.Schema.SetRepoMeta, ExpandFileName, ExtractFilePath, IntToStr</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>Touches: file system</para>
/// <para>Transaction: starts, commits, rolls back</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.NewConnection"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoTableDdl"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoTablesFor"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.SetRepoMeta"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure CreateRepository(const pFileName: string; pVersion: Integer = REPO_SCHEMA_VERSION);

/// <summary>Opens an existing repository and validates it against the table set of ITS OWN
/// schema version (1 to 4).</summary>
/// <param name="pFileName">Repository file.</param>
/// <param name="pReadOnly">True opens with OpenMode=ReadOnly.</param>
/// <returns>A connected connection; the caller frees it. Its FormatOptions.StrsTrim is
/// False, so every dataset on it keeps trailing blanks.</returns>
/// <exception cref="ERepoError">The file is missing (it is never created).</exception>
/// <exception cref="ERepoSchemaError">The file is not a repository of this version.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.OpenOrCreateRepo (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoBackup (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoInfo (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoRestore (DRagLint.CLI.Repo.pas), DRagLint.CLI.RepoConstGen.CheckUnitFile (DRagLint.CLI.RepoConstGen.pas) (+6 more)</para>
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
/// <para>Called from: DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas), DRagLint.CLI.Repo.RepoInfo (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.ConstGen.CountConstRows (DRagLint.FieldRepo.ConstGen.pas), DRagLint.FieldRepo.ConstMark.ConstTableMarks (DRagLint.FieldRepo.ConstMark.pas), DRagLint.FieldRepo.Schema.RepoIsEmpty (DRagLint.FieldRepo.Schema.pas) (+1 more)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.FindRepoTable, DRagLint.FieldRepo.Schema.QuoteRepoIdent</para>
/// <para>Returns: pConnection.ExecSQLScalar('SELECT COUNT(*) FROM ' + QuoteRepoIdent(Tab.Name))</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.FindRepoTable"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.QuoteRepoIdent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RepoRowCount(pConnection: TFDConnection; const pTableName: string): Integer;

/// <summary>True when every repository table except DL_META, DL_LAYOUT_EVENTS, DL_EXCEPTIONS, DL_GRID_COLUMNS and the
/// schema-fact tables has no rows (those are data a seed / import of the field registry never writes, so they do not
/// make a repository "non-empty"). Counts only the tables of the file's own schema version.</summary>
/// <param name="pConnection">An open repository connection.</param>
/// <returns>True for a freshly created repository.</returns>
/// <exception cref="ERepoError"><!-- drag-lint:auto exc -->via DRagLint.FieldRepo.Schema.RepoRowCount: Not a repository table: %s; via DRagLint.FieldRepo.Schema.RepoTablesFor: Unknown repository schema version %d</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoImportFb (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.FbImport.ImportFromFirebird (DRagLint.FieldRepo.FbImport.pas), DRagLint.FieldRepo.SchemaSeed.ApplySchemaChanges (DRagLint.FieldRepo.SchemaSeed.pas), DRagLint.FieldRepo.SchemaSeed.PlanSchemaChanges (DRagLint.FieldRepo.SchemaSeed.pas), DRagLint.FieldRepo.SchemaSeed.RunSchemaSeed (DRagLint.FieldRepo.SchemaSeed.pas) (+1 more)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.RepoRowCount, DRagLint.FieldRepo.Schema.RepoSchemaVersion, DRagLint.FieldRepo.Schema.RepoTablesFor, MatchText</para>
/// <para>Returns: True; False</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoRowCount"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoSchemaVersion"/>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoTablesFor"/>
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

/// <summary>Counts the rows MigrateRepoRows changes.</summary>
/// <param name="pConnection">Open repository connection.</param>
/// <param name="pFrom">Schema version the rows were written with.</param>
/// <returns>The counts; a step that schema does not need counts 0.</returns>
function CountRepoRowChanges(pConnection: TFDConnection; pFrom: Integer): TRepoRowChanges;

/// <summary>Brings rows of an older schema to schema pTo: FIELD_KIND 2 for ISCALCULATED rows (from schema 1),
/// Field events into the event columns (from schema 2 or older, when pTo is 3 or later), ALIGNMENT -2 to NULL (pTo 3 or
/// later), DL_META schema_version = pTo. Schema 4 adds tables only: no row step of its own.</summary>
/// <param name="pConnection">Open read-write connection whose tables have the columns of schema pTo.</param>
/// <param name="pFrom">Schema version the rows were written with, below pTo.</param>
/// <param name="pTo">The file's schema: REPO_SCHEMA_VERSION for a migration, the target file's own schema for a restore
/// (an old backup restored into an older, non-current file is still migrated up to that file's schema).</param>
/// <remarks>Runs in the caller's transaction, for a migrated file and for an older text backup that is restored.</remarks>
procedure MigrateRepoRows(pConnection: TFDConnection; pFrom: Integer; pTo: Integer = REPO_SCHEMA_VERSION);

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.DApt,
  DRagLint.FieldRepo.Kinds;  // dl:ok uses-global-census@379a -- REVIEWED 2026-11-24 INT-W2: FR_EVENT_COLUMNS is the one list of event columns

const
  MAX_BYTE = 255;
  COMPONENT_NAME_LEN = 128;
  VERSION_MODEL = 2;
  VERSION_EVENT_COLUMNS = 3;
  VERSION_CROSS_TABLE = 4;
  { column widths of the schema-4 tables }
  TABLE_NAME_LEN = 68;
  IDENT_LEN = 63;
  SOURCE_LEN = 10;
  BINDING_LEN = 160;
  PATH_LEN = 1000;
  { Tables a seed or an import of the field registry never writes. }
  SIDE_TABLES: array[0..10] of string = (REPO_META_TABLE, REPO_TABLE_LAYOUT_EVENTS, REPO_TABLE_EXCEPTIONS,
    REPO_TABLE_DOMAINS, REPO_TABLE_CONSTRAINTS, REPO_TABLE_CONSTRAINT_COLUMNS, REPO_TABLE_GENERATORS,
    REPO_TABLE_GRID_COLUMNS, REPO_TABLE_RELATIONS, REPO_TABLE_RELATION_COLUMNS, REPO_TABLE_FIELD_INPUTS);
  META_SCHEMA_VERSION = 'schema_version';
  WHERE_CALC = ' WHERE "ISCALCULATED" = 1 AND ("FIELD_KIND" IS NULL OR "FIELD_KIND" = 1)';
  WHERE_ALIGNMENT = ' WHERE "ALIGNMENT" = -2';
  SELECT_COUNT = 'SELECT COUNT(*) FROM ';
  FIELDS_SQL = '"DL_FIELDS_INFO"';
  EVENTS_SQL = '"DL_LAYOUT_EVENTS"';
  { A Field event of one kind that has its field row; %s = event name. }
  WHERE_EVENT = ' WHERE "LAYOUT_TYPE" = ''' + REPO_LAYOUT_FIELD + ''' AND "EVENT_NAME" = ''%s'' AND EXISTS (SELECT 1 FROM ' +
    FIELDS_SQL + ' F WHERE F."TABLE_NAME" = ' + EVENTS_SQL + '."TABLE_NAME" AND F."FIELD_NAME" = ' + EVENTS_SQL + '."FIELD_NAME")';
  DELETE_EVENT = 'DELETE FROM ' + EVENTS_SQL + WHERE_EVENT;  // dl:ok sql-injection-concat@e420 -- REVIEWED 2026-11-23 EVCOLS: a constant made of constants, formatted with the event names of FR_EVENT_COLUMNS
  { %0:s = column, %1:s = event name. }
  MOVE_EVENT = 'UPDATE ' + FIELDS_SQL + ' SET "%0:s" = (SELECT E."EVENT_CODE" FROM ' + EVENTS_SQL + ' E WHERE E."TABLE_NAME" = ' +
    FIELDS_SQL + '."TABLE_NAME" AND E."FIELD_NAME" = ' + FIELDS_SQL + '."FIELD_NAME" AND E."LAYOUT_TYPE" = ''' + REPO_LAYOUT_FIELD +
    ''' AND E."EVENT_NAME" = ''%1:s'') WHERE EXISTS (SELECT 1 FROM ' + EVENTS_SQL + ' E WHERE E."TABLE_NAME" = ' + FIELDS_SQL +
    '."TABLE_NAME" AND E."FIELD_NAME" = ' + FIELDS_SQL + '."FIELD_NAME" AND E."LAYOUT_TYPE" = ''' + REPO_LAYOUT_FIELD +
    ''' AND E."EVENT_NAME" = ''%1:s'')';

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
  if pVersion >= VERSION_EVENT_COLUMNS then
    Result.Columns := Result.Columns + [Txt('ONGETTEXT_BODY'), Txt('ONSETTEXT_BODY'), Txt('ONVALIDATE_BODY'),
      Txt('ONCHANGE_BODY'), Txt('GRID_DISPLAYTEXT_BODY'), Txt('GRID_DRAWCELL_BODY')];
end;

function GridColumnsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_GRID_COLUMNS, '', [
    Str('FORM_NAME', COMPONENT_NAME_LEN, True, 1),
    Str('VIEW_NAME', COMPONENT_NAME_LEN, True, 2),
    Str('COLUMN_NAME', COMPONENT_NAME_LEN, True, 3),  // dl:ok magic-literal@1732 -- REVIEWED 2026-11-23 EVCOLS: position in the primary key, named by its neighbours
    Str('TABLE_NAME', 68),  // dl:ok large-magic-number@1b56, magic-literal@1b56 -- REVIEWED 2026-11-23 EVCOLS: column width of a schema table definition, named by the column beside it
    Str('FIELD_NAME', 68),  // dl:ok large-magic-number@0f83, magic-literal@0f83 -- REVIEWED 2026-11-23 EVCOLS: column width of a schema table definition, named by the column beside it
    Col('COLUMN_INDEX', rckInteger, 0, True, '', 0)]);
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

{ Design 2026-11-26-cross-table-fields 2.2: one N:1 step, child row to ONE parent row. }
function RelationsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_RELATIONS, '', [
    Str('RELATION_NAME', IDENT_LEN, True, 1),
    Str('CHILD_TABLE', TABLE_NAME_LEN, True),
    Str('PARENT_TABLE', TABLE_NAME_LEN, True),
    Str('SOURCE', SOURCE_LEN, True),
    Str('CONSTRAINT_NAME', TABLE_NAME_LEN),
    Str('PARENT_KEY', TABLE_NAME_LEN, True),
    Bool('IS_DEFAULT', '0')]);
end;

function RelationColumnsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_RELATION_COLUMNS, '', [
    Str('RELATION_NAME', IDENT_LEN, True, 1),
    Col('POSITION', rckInteger, 0, True, '', 2),
    Str('CHILD_COLUMN', TABLE_NAME_LEN, True),
    Str('PARENT_COLUMN', TABLE_NAME_LEN, True)]);
end;

function FieldInputsTable: TRepoTable;
begin
  Result := MakeTable(REPO_TABLE_FIELD_INPUTS, '', [
    Str('TABLE_NAME', TABLE_NAME_LEN, True, 1),
    Str('FIELD_NAME', TABLE_NAME_LEN, True, 2),
    Col('BINDING', rckString, BINDING_LEN, True, '''''', 3),  // dl:ok magic-literal@f8cb -- REVIEWED 2026-11-26 XTABLE: position in the primary key, named by its neighbours
    Str('ALIAS', IDENT_LEN, True, 4),  // dl:ok magic-literal@4794 -- REVIEWED 2026-11-26 XTABLE: position in the primary key, named by its neighbours
    Col('PATH', rckString, PATH_LEN, True, '''''', 0),
    Str('TARGET_TABLE', TABLE_NAME_LEN, True)]);
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
  if pVersion >= VERSION_MODEL then
    Result := Result + [LayoutEventsTable, ExceptionsTable, DomainsTable, ConstraintsTable,
      ConstraintColumnsTable, GeneratorsTable];
  if pVersion >= VERSION_EVENT_COLUMNS then
    Result := Result + [GridColumnsTable];
  if pVersion >= VERSION_CROSS_TABLE then
    Result := Result + [RelationsTable, RelationColumnsTable, FieldInputsTable];
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
      SetRepoMeta(Conn, META_SCHEMA_VERSION, IntToStr(pVersion));
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
    if (not MatchText(Tab.Name, SIDE_TABLES)) and (RepoRowCount(pConnection, Tab.Name) > 0) then
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

{ One row change per step; CountRepoRowChanges and MigrateRepoRows use the same conditions. }
function CountRows(pConn: TFDConnection; const pFromWhere: string): Integer;
begin
  Result := Integer(pConn.ExecSQLScalar(SELECT_COUNT + pFromWhere));
end;

function CountEvents(pConn: TFDConnection): Integer;
var
  VEvent: TFrEventColumn;
begin
  Result := 0;
  for VEvent in FR_EVENT_COLUMNS do
    if not VEvent.IsGrid then
      Inc(Result, CountRows(pConn, EVENTS_SQL + Format(WHERE_EVENT, [VEvent.Event])));
end;

procedure MoveEvents(pConn: TFDConnection);
var
  VEvent: TFrEventColumn;
begin
  for VEvent in FR_EVENT_COLUMNS do
    if not VEvent.IsGrid then
    begin
      pConn.ExecSQL(Format(MOVE_EVENT, [VEvent.Column, VEvent.Event]));
      pConn.ExecSQL(Format(DELETE_EVENT, [VEvent.Event]));
    end;
end;

function CountRepoRowChanges(pConnection: TFDConnection; pFrom: Integer): TRepoRowChanges;
begin
  Result := Default(TRepoRowChanges);
  Result.AlignmentRows := CountRows(pConnection, FIELDS_SQL + WHERE_ALIGNMENT);
  if pFrom < VERSION_MODEL then
    Result.CalcRows := CountRows(pConnection, FIELDS_SQL + WHERE_CALC)
  else if pFrom < VERSION_EVENT_COLUMNS then
    Result.EventRows := CountEvents(pConnection);
end;

procedure MigrateRepoRows(pConnection: TFDConnection; pFrom: Integer; pTo: Integer);
begin
  if pFrom < VERSION_MODEL then
    pConnection.ExecSQL('UPDATE ' + FIELDS_SQL + ' SET "FIELD_KIND" = 2' + WHERE_CALC)
  else if (pFrom < VERSION_EVENT_COLUMNS) and (pTo >= VERSION_EVENT_COLUMNS) then
    MoveEvents(pConnection);
  if pTo >= VERSION_EVENT_COLUMNS then
    pConnection.ExecSQL('UPDATE ' + FIELDS_SQL + ' SET "ALIGNMENT" = NULL' + WHERE_ALIGNMENT);
  SetRepoMeta(pConnection, META_SCHEMA_VERSION, IntToStr(pTo));
end;

end.
