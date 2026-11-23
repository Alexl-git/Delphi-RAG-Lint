unit DRagLint.FieldRepo.DbProvider;

{ drag-lint 1.54 -- lane TT-ALTER: the database side of the per-table ALTER, vendor-neutral
  (design 2026-11-22-field-repository-v2-design.md section 9). Fact records of ONE table, the SQL text
  generator (IFrDbDialect, pure: no connection) and the connection (IFrDbProvider). Firebird lives in
  DRagLint.FieldRepo.DbProviderFb; another database plugs in by implementing the two interfaces. }

interface

uses
  System.SysUtils;

type
  /// <summary>Raised when a provider cannot read or is asked something it does not support.</summary>
  EFrDbProviderError = class(Exception);

  /// <summary>The data type of a column or domain, in RDB$ codes.</summary>
  TFrTypeFacts = record
    /// <summary>RDB$FIELDS.RDB$FIELD_TYPE.</summary>
    FieldType: Integer;
    /// <summary>RDB$FIELD_SUB_TYPE (0 when NULL).</summary>
    SubType: Integer;
    /// <summary>Byte length.</summary>
    ByteLength: Integer;
    /// <summary>Declared character length; 0 = not a character type or unknown.</summary>
    CharLength: Integer;
    /// <summary>RDB$FIELD_SCALE (zero or negative).</summary>
    Scale: Integer;
    /// <summary>Declared precision; 0 = unknown (the repository does not hold it for columns).</summary>
    Precision: Integer;
    /// <summary>Character set; '' = the database default or unknown.</summary>
    Charset: string;
    /// <summary>Collation; '' = the default of the character set or unknown.</summary>
    Collation: string;
  end;

  /// <summary>One user domain.</summary>
  TFrDomainFacts = record
    Name: string;
    DataType: TFrTypeFacts;
    NotNull: Boolean;
    DefaultSource: string;
    CheckSource: string;
  end;

  /// <summary>One live column.</summary>
  TFrColumnFacts = record
    Name: string;
    /// <summary>0-based position in the table.</summary>
    Position: Integer;
    /// <summary>The user domain; '' for an inline type.</summary>
    DomainName: string;
    DataType: TFrTypeFacts;
    /// <summary>NOT NULL declared on the column itself.</summary>
    ColumnNotNull: Boolean;
    /// <summary>NOT NULL that comes from the domain.</summary>
    DomainNotNull: Boolean;
    /// <summary>Column-level default, e.g. 'DEFAULT 0'; '' when none.</summary>
    DefaultSource: string;
    /// <summary>COMPUTED BY source; '' for a stored column.</summary>
    ComputedSource: string;
    IsIdentity: Boolean;
    HasColumnGrants: Boolean;
    Description: string;
    /// <summary>True when the column cannot hold NULL, whatever the reason.</summary>
    /// <returns>Column-level or domain-level NOT NULL.</returns>
    function NotNull: Boolean;
  end;

  /// <summary>What kind of object depends on a column.</summary>
  TFrDependencyKind = (fdkObject, fdkCheck, fdkComputed, fdkExpressionIndex);

  /// <summary>One object that depends on one column.</summary>
  TFrDependency = record
    ColumnName: string;
    DependentName: string;
    Kind: TFrDependencyKind;
    /// <summary>Readable object type: view, trigger, procedure, ...</summary>
    KindText: string;
  end;

  /// <summary>One key constraint or plain index with its columns.</summary>
  TFrKeyFacts = record
    Name: string;
    /// <summary>'PK', 'UNIQUE', 'FK' or 'INDEX'.</summary>
    Kind: string;
    Columns: TArray<string>;
  end;

  /// <summary>Everything the diff engine needs about one live table.</summary>
  TFrTableFacts = record
    TableName: string;
    /// <summary>False = no such table (the other fields are then empty).</summary>
    Exists: Boolean;
    /// <summary>Non-empty = the relation is not a persistent table (view, GTT, external): not altered.</summary>
    NotPlainTable: string;
    /// <summary>In position order.</summary>
    Columns: TArray<TFrColumnFacts>;
    Domains: TArray<TFrDomainFacts>;
    Keys: TArray<TFrKeyFacts>;
    Dependencies: TArray<TFrDependency>;
    /// <summary>Active user triggers that fire on UPDATE.</summary>
    UpdateTriggers: TArray<string>;
    /// <summary>Finds a column (case-insensitive).</summary>
    /// <param name="pName">Column name.</param>
    /// <param name="pColumn">The column; empty when not found.</param>
    /// <returns>True when found.</returns>
    function FindColumn(const pName: string; out pColumn: TFrColumnFacts): Boolean;
    /// <summary>Finds a domain (case-insensitive).</summary>
    /// <param name="pName">Domain name.</param>
    /// <param name="pDomain">The domain; empty when not found.</param>
    /// <returns>True when found.</returns>
    function FindDomain(const pName: string; out pDomain: TFrDomainFacts): Boolean;
    /// <summary>True when the column is in the primary key.</summary>
    /// <param name="pName">Column name.</param>
    /// <returns>True for a primary key column.</returns>
    function IsPrimaryKey(const pName: string): Boolean;
  end;

  /// <summary>What a database can do; a missing capability turns the change into BLOCKED.</summary>
  TFrDbCapability = (fdcSetNotNull, fdcColumnPosition, fdcSafePath);

  /// <summary>What a database can do.</summary>
  TFrDbCapabilities = set of TFrDbCapability;

  /// <summary>SQL text of one database product. Pure: no connection, no state.</summary>
  IFrDbDialect = interface
    ['{4A7E0C55-6E0F-4C0E-9B7B-0E4A7D8C1F01}']
    /// <summary>Product name for reports.</summary>
    /// <returns>For example 'Firebird'.</returns>
    function Name: string;
    /// <summary>What the product can do.</summary>
    /// <returns>The capability set.</returns>
    function Capabilities: TFrDbCapabilities;
    /// <summary>Longest identifier.</summary>
    /// <returns>Characters.</returns>
    function MaxIdentifier: Integer;
    /// <summary>Quotes an identifier.</summary>
    /// <param name="pName">The name.</param>
    /// <returns>The quoted name.</returns>
    function QuoteIdent(const pName: string): string;
    /// <summary>Type text, e.g. VARCHAR(20).</summary>
    /// <param name="pType">The type.</param>
    /// <param name="pWithCharset">Adds CHARACTER SET when known.</param>
    /// <returns>The text; '' when the type cannot be written.</returns>
    function TypeClause(const pType: TFrTypeFacts; pWithCharset: Boolean): string;
    /// <summary>CREATE DOMAIN statement.</summary>
    /// <param name="pDomain">The domain.</param>
    /// <returns>The statement.</returns>
    function CreateDomain(const pDomain: TFrDomainFacts): string;
    /// <summary>ADD column statement.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">New column.</param>
    /// <param name="pDefinition">Type or quoted domain plus DEFAULT / NOT NULL / COLLATE.</param>
    /// <returns>The statement.</returns>
    function AddColumn(const pTable, pColumn, pDefinition: string): string;
    /// <summary>DROP column statement.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <returns>The statement.</returns>
    function DropColumn(const pTable, pColumn: string): string;
    /// <summary>Rename statement.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pOld">Current name.</param>
    /// <param name="pNew">New name.</param>
    /// <returns>The statement.</returns>
    function RenameColumn(const pTable, pOld, pNew: string): string;
    /// <summary>Type change statement.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <param name="pTypeText">Type text or quoted domain.</param>
    /// <returns>The statement.</returns>
    function AlterType(const pTable, pColumn, pTypeText: string): string;
    /// <summary>SET / DROP NOT NULL statement.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <param name="pNotNull">True = SET.</param>
    /// <returns>The statement.</returns>
    function SetNotNull(const pTable, pColumn: string; pNotNull: Boolean): string;
    /// <summary>Column default statement.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <param name="pDefaultSource">'DEFAULT x'.</param>
    /// <returns>The statement.</returns>
    function SetDefault(const pTable, pColumn, pDefaultSource: string): string;
    /// <summary>Position statement.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <param name="pPosition">1-based.</param>
    /// <returns>The statement.</returns>
    function SetPosition(const pTable, pColumn: string; pPosition: Integer): string;
    /// <summary>Column description statement.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <param name="pText">The description.</param>
    /// <returns>The statement.</returns>
    function CommentColumn(const pTable, pColumn, pText: string): string;
    /// <summary>UPDATE that fills a column from another one with a CAST.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pFrom">Source column.</param>
    /// <param name="pTo">Target column.</param>
    /// <param name="pType">Target type.</param>
    /// <returns>The statement.</returns>
    function CopyColumn(const pTable, pFrom, pTo: string; const pType: TFrTypeFacts): string;
    /// <summary>Row count query.</summary>
    /// <param name="pTable">Table.</param>
    /// <returns>A one-value query.</returns>
    function CountRows(const pTable: string): string;
    /// <summary>NULL count query.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <returns>A one-value query.</returns>
    function CountNulls(const pTable, pColumn: string): string;
    /// <summary>Non-NULL count query.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <returns>A one-value query.</returns>
    function CountValues(const pTable, pColumn: string): string;
    /// <summary>Counts the rows whose CAST to the new type raises an error.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <param name="pNew">Target type.</param>
    /// <returns>A one-value query; it writes nothing.</returns>
    function CountCastFailures(const pTable, pColumn: string; const pNew: TFrTypeFacts): string;
    /// <summary>Counts the rows whose CAST succeeds but changes the value.</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pColumn">Column.</param>
    /// <param name="pOld">Current type.</param>
    /// <param name="pNew">Target type.</param>
    /// <returns>A one-value query; it writes nothing.</returns>
    function CountLosses(const pTable, pColumn: string; const pOld, pNew: TFrTypeFacts): string;
    /// <summary>Counts the rows where a filled copy does not match its source (run before the source is dropped).</summary>
    /// <param name="pTable">Table.</param>
    /// <param name="pFrom">Source column.</param>
    /// <param name="pCopy">Filled copy.</param>
    /// <param name="pOld">Source type.</param>
    /// <param name="pNew">Copy type.</param>
    /// <returns>A one-value query.</returns>
    function CountMismatches(const pTable, pFrom, pCopy: string; const pOld, pNew: TFrTypeFacts): string;
  end;

  /// <summary>One open connection to one database.</summary>
  /// <remarks>Reads run in read-only transactions. Writes need BeginWrite; the only caller is
  /// DRagLint.FieldRepo.AlterApply, which refuses without a pre-check ticket of the same session.</remarks>
  IFrDbProvider = interface
    ['{9C9B0D57-4B0B-4E6B-8B44-6B8F2D6C7A02}']
    /// <summary>The SQL generator.</summary>
    /// <returns>The dialect.</returns>
    function Dialect: IFrDbDialect;
    /// <summary>The Database value of the connection; never a password.</summary>
    /// <returns>The name.</returns>
    function DatabaseName: string;
    /// <summary>Unique per opened connection.</summary>
    /// <returns>An opaque id.</returns>
    function SessionId: string;
    /// <summary>Reads the facts of one table.</summary>
    /// <param name="pTable">Table name (upper-case).</param>
    /// <returns>The facts; Exists = False when there is no such table.</returns>
    function ReadTable(const pTable: string): TFrTableFacts;
    /// <summary>Runs a one-value query in a read-only transaction.</summary>
    /// <param name="pSql">The query.</param>
    /// <returns>The value (0 for NULL).</returns>
    function ReadScalar(const pSql: string): Int64;
    /// <summary>Starts a write transaction.</summary>
    /// <param name="pLockTable">Non-empty = reserve this table against other writers for the whole transaction.</param>
    procedure BeginWrite(const pLockTable: string);
    /// <summary>Runs a statement in the write transaction.</summary>
    /// <param name="pSql">The statement.</param>
    procedure Execute(const pSql: string);
    /// <summary>Runs a one-value query in the write transaction.</summary>
    /// <param name="pSql">The query.</param>
    /// <returns>The value (0 for NULL).</returns>
    function WriteScalar(const pSql: string): Int64;
    /// <summary>Commits the write transaction.</summary>
    procedure Commit;
    /// <summary>Rolls the write transaction back; no-op when none is open.</summary>
    procedure Rollback;
  end;

implementation

function TFrColumnFacts.NotNull: Boolean;
begin
  Result := ColumnNotNull or DomainNotNull;
end;

function TFrTableFacts.FindColumn(const pName: string; out pColumn: TFrColumnFacts): Boolean;
var
  VItem: TFrColumnFacts;
begin
  Result := False;
  pColumn := Default(TFrColumnFacts);
  for VItem in Columns do
    if SameText(VItem.Name, pName) then
    begin
      pColumn := VItem;
      Exit(True);
    end;
end;

function TFrTableFacts.FindDomain(const pName: string; out pDomain: TFrDomainFacts): Boolean;
var
  VItem: TFrDomainFacts;
begin
  Result := False;
  pDomain := Default(TFrDomainFacts);
  for VItem in Domains do
    if SameText(VItem.Name, pName) then
    begin
      pDomain := VItem;
      Exit(True);
    end;
end;

function TFrTableFacts.IsPrimaryKey(const pName: string): Boolean;
var
  VKey: TFrKeyFacts;
  VColumn: string;
begin
  Result := False;
  for VKey in Keys do
    if VKey.Kind = 'PK' then
      for VColumn in VKey.Columns do
        if SameText(VColumn, pName) then
          Exit(True);
end;

end.
