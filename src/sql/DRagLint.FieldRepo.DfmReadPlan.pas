unit DRagLint.FieldRepo.DfmReadPlan;

(* drag-lint 1.54 -- lane TT-DFMREAD: the DFM -> repository change set and its applier (design
  2026-11-22-field-repository-v2-design.md sections 3, 4 and 9; plan 2026-11-23-fr-dfmread.md).

  Facts of every read dataset are collected per repository field, then compared with the repository. A dataset's
  table comes from UpdateOptions.UpdateTableName, TableName or a SELECT over one table; otherwise the dataset is
  reported unresolved and gives no change. Two datasets that disagree give one unchecked change per alternative.
  Only what the DFM states makes a change; a read never deletes a field.

  EVCOLS (rulings 2026-11-23): the TField events and the column events of a DBTable view become event columns of the
  field row (R2); the columns of every table / banded view become DL_GRID_COLUMNS rows (R6), where a column that is gone
  from the form is an unchecked delete.

  1.56 GC-R (GRIDCOL2): a DL_GRID_COLUMNS row also holds the column's in-place editor, PROPERTIES_CLASS_NAME and
  PROPERTIES (TDfmrGridColumn.PropertiesClassName / Properties), in a repository of schema 5; an older repository is
  read as before, with one warning that counts the columns whose editor was left out. *)

interface

uses
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Kinds,  // dl:ok uses-global-census@5f7a -- REVIEWED 2026-11-24 INT-W2: FR_EVENT_COLUMNS is the one list of event columns
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DfmReadSelection,
  DRagLint.FieldRepo.DfmRead;

type
  /// <summary>Number of persistent fields per kind.</summary>
  TDfmrKindCounts = array[TFrFieldKind] of Integer;

  /// <summary>One persistent field and the column it belongs to.</summary>
  TDfmrFieldRef = record
    /// <summary>FieldName property, component name and class.</summary>
    FieldName: string;
    CompName: string;
    FieldClass: string;
    /// <summary>Field kind.</summary>
    Kind: TFrFieldKind;
    /// <summary>Table and column; '' = the DFM does not state them.</summary>
    TableName: string;
    Column: string;
  end;

  /// <summary>What was read from one dataset.</summary>
  TDfmrDatasetReport = record
    /// <summary>DFM file name without folder.</summary>
    DfmName: string;
    /// <summary>Dataset component and its class.</summary>
    Dataset: string;
    DatasetClass: string;
    /// <summary>Resolved table; '' = unresolved.</summary>
    TableName: string;
    /// <summary>Why the dataset has no table; '' when it has one.</summary>
    Unresolved: string;
    /// <summary>Persistent fields by kind, attributed or not.</summary>
    Counts: TDfmrKindCounts;
    /// <summary>Persistent fields that belong to no table the DFM states.</summary>
    Unattributed: TArray<string>;
    /// <summary>The persistent fields in DFM order, attributed or not.</summary>
    Fields: TArray<TDfmrFieldRef>;
    /// <summary>Calc / internal-calc fields with a storable body, with a blocked body, without a body.</summary>
    BodyOk: Integer;
    BodyBlocked: Integer;
    BodyNone: Integer;
    /// <summary>The FROM tables of a join (a SELECT over several tables), in order; empty = no join. A join has no
    /// TableName and is not unresolved: each field has its own table (design 2026-11-26-join-field-origin).</summary>
    JoinTables: TArray<string>;
    /// <summary>Fields of a join without a table: Name = FieldName, Value = why (never a guess).</summary>
    NoTable: TArray<TDfmrPair>;
    /// <summary>The links followed to the dataset's source (design 2026-11-26-cross-table-fields 3.1), e.g.
    /// `AttachedTo memA > AttachedTo tblChart`; '' = none.</summary>
    Via: string;
    /// <summary>Kind of the first link (AttachedTo, AttachTable, CloneCursor, CopyDataSet, CopyData, AppendData, Data);
    /// '' = the dataset has no link or the link gives no source.</summary>
    LinkKind: string;
    /// <summary>True when the dataset has a link that gives no source (cycle, two sources, no such dataset).</summary>
    LinkFailed: Boolean;
  end;

  /// <summary>Calc fields of joins that read several tables (design 2026-11-26-cross-table-fields 3.1 CHILD END).</summary>
  TDfmrCrossTotals = record
    /// <summary>Placed: a home table and a chosen path to every other table they read.</summary>
    Placed: Integer;
    /// <summary>Not placed: no child end, two child ends, a table joined twice, a path not chosen.</summary>
    Unresolved: Integer;
    /// <summary>Distinct DL_FIELD_INPUTS rows (table, field, alias) the placed fields need.</summary>
    Inputs: Integer;
    /// <summary>Distinct FK relations the inputs' paths use.</summary>
    FkUsed: Integer;
    /// <summary>FORM relations offered (a form's join on a parent key with no FK, ruling XQ6).</summary>
    Offered: Integer;
  end;

  /// <summary>What one change writes; parallel to the change set.</summary>
  TDfmrChangeItem = record
    /// <summary>Key of a DL_FIELDS_INFO change.</summary>
    TableName: string;
    FieldName: string;
    /// <summary>Key of a DL_GRID_COLUMNS change; FormName '' = a DL_FIELDS_INFO change.</summary>
    FormName: string;
    ViewName: string;
    ColumnName: string;
    /// <summary>Columns to write.</summary>
    Columns: TArray<TDfmrPair>;
    /// <summary>DL_RELATIONS or DL_FIELD_INPUTS for a cross-table change (schema 4); '' = a field or grid change.</summary>
    RowTable: string;
    /// <summary>DL_RELATIONS only: the DL_RELATION_COLUMNS rows, Name = CHILD_COLUMN, Value = PARENT_COLUMN, in
    /// position order.</summary>
    SubColumns: TArray<TDfmrPair>;
  end;

  /// <summary>A planned read.</summary>
  TDfmrPlan = record
    /// <summary>Direction dfm-to-repo.</summary>
    ChangeSet: TFrChangeSet;
    /// <summary>Items[i] belongs to ChangeSet.Changes[i].</summary>
    Items: TArray<TDfmrChangeItem>;
    /// <summary>One report per read dataset, in DFM order.</summary>
    Datasets: TArray<TDfmrDatasetReport>;
    /// <summary>Everything read but not turned into a change, and every fact to look at.</summary>
    Warnings: TArray<string>;
    /// <summary>Calc fields of joins over several tables.</summary>
    CrossTable: TDfmrCrossTotals;
  end;

/// <summary>Reads DFMs and plans the changes that bring the repository in line with them.</summary>
/// <param name="pRepo">Open repository connection, schema 4; only SELECTs run.</param>
/// <param name="pFiles">DFM files; the unit of the same name is read for handler code when it exists.</param>
/// <param name="pDataset">Dataset component name (case-insensitive); '' = every dataset of every file.</param>
/// <returns>The plan. Every change is checked, except alternatives that contradict each other, a data field the
/// repository knows as calc / lookup, a body or lookup wiring of a field that does not become that kind, and the delete
/// of a grid column that is gone from the form; a value that cannot be stored is blocked.</returns>
/// <exception cref="EDfmReadError">A file cannot be read, or no file holds the dataset.</exception>
/// <exception cref="ERepoError">The repository is schema 1, 2 or 3 (run repo migrate first).</exception>
/// <remarks>Ids are 1-based in plan order: the same DFMs and repository always give the same ids.
/// <para>Cross-table (design 2026-11-26-cross-table-fields 3.1, 3.2; X3): a dataset without a table or SQL takes the
/// source of its AttachedTo (DFM) or of a literal AttachTable / CloneCursor / CopyDataSet / CopyData / AppendData /
/// `Data :=` in its unit, transitively; a cycle, or two different sources, is unresolved. A copied data field the unit
/// also writes has no table. A join calc field reading several tables is placed in the CHILD END (the one table from
/// which every other one is reached up the relation graph); every other table becomes an input alias (ruling XQ2: the
/// table name) whose path is chosen by design 3.2 rules 1-5, with the form's ON / WHERE equalities as rule 2. The
/// plan then inserts the DL_FIELD_INPUTS rows (checked) and the DL_RELATIONS rows their paths need: an FK step
/// checked, a FORM relation offered for a join on a parent key without an FK unchecked (ruling XQ6), and an input that
/// goes through an offered relation unchecked.</para></remarks>
function PlanDfmRead(pRepo: TFDConnection; const pFiles: TArray<string>; const pDataset: string): TDfmrPlan;

/// <summary>The fields the repository has for a table, as the field selection of a dataset sees them.</summary>
/// <param name="pRepo">Open repository connection, schema 3; only a SELECT runs.</param>
/// <param name="pTable">Table name (case-insensitive).</param>
/// <returns>One record per DL_FIELDS_INFO row, in FIELD_NAME order, graphical columns included; a row with an unknown
/// FIELD_KIND counts as data.</returns>
function TableFieldsOf(pRepo: TFDConnection; const pTable: string): TArray<TFrSelectionField>;

/// <summary>Applies chosen changes of a plan in one transaction.</summary>
/// <param name="pRepo">Open read-write repository connection, the one the plan was made from.</param>
/// <param name="pPlan">The plan.</param>
/// <param name="pChosen">Changes to apply (the checked ones, or those a --select file named).</param>
/// <returns>One `replacing OLD with NEW` line per applied change.</returns>
/// <exception cref="ERepoError">Two chosen changes set the same value, a chosen change is blocked, or it needs a row
/// whose insert was not chosen (a DL_FIELD_INPUTS row needs its DL_FIELDS_INFO row and every DL_RELATIONS row of its
/// PATH); nothing is written.</exception>
function ApplyDfmRead(pRepo: TFDConnection; const pPlan: TDfmrPlan; const pChosen: TArray<TFrChange>): TArray<string>;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Variants,
  System.Generics.Collections,
  System.Generics.Defaults,
  Data.DB,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  DRagLint.FieldRepo.Schema,  // dl:ok uses-global-census@9edb -- REVIEWED 2026-11-23 TT-DFMREAD: the unit is used for its record types and functions; one table-name constant is what it needs
  DRagLint.FieldRepo.SchemaFacts,
  DRagLint.FieldRepo.DfmReadSql,
  DRagLint.FieldRepo.DfmReadCalc,
  DRagLint.FieldRepo.DfmReadLinks,
  DRagLint.FieldRepo.RelationGraph,
  DRagLint.FieldRepo.RelationRepo,
  DRagLint.FieldRepo.CrossTable;

const
  FIELDS_TABLE = 'DL_FIELDS_INFO';
  SCHEMA_WITH_INPUTS = 4; // X3 writes DL_FIELD_INPUTS / DL_RELATIONS rows (design 2.3)
  SCHEMA_WITH_EDITORS = 5; // DL_GRID_COLUMNS has PROPERTIES_CLASS_NAME / PROPERTIES (1.56 GC-R)
  BOOL_FALSE = 'False';
  COL_IS_DEFAULT = 'IS_DEFAULT';
  COL_RELATION = 'RELATION_NAME';
  COL_BINDING = 'BINDING';
  COL_ALIAS = 'ALIAS';
  COL_PATH = 'PATH';
  SQL_RELATION_ROW = 'SELECT * FROM "DL_RELATIONS" WHERE "RELATION_NAME" = :N';
  SQL_RELATION_COLUMNS = 'SELECT * FROM "DL_RELATION_COLUMNS" WHERE "RELATION_NAME" = :N';
  SQL_INPUT_ROW = 'SELECT * FROM "DL_FIELD_INPUTS" WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F AND "BINDING" = :B ' +
    'AND "ALIAS" = :A';
  SQL_STORED_INPUTS = 'SELECT "TABLE_NAME", "FIELD_NAME", "ALIAS", "PATH" FROM "DL_FIELD_INPUTS" WHERE "BINDING" = ''''';
  COL_TABLE = 'TABLE_NAME';
  COL_FIELD = 'FIELD_NAME';
  COL_KIND = 'FIELD_KIND';
  COL_IS_CALC = 'ISCALCULATED';
  COL_IS_LOOKUP = 'ISLOOKUP';
  COL_BODY = 'CALC_BODY';
  COL_SOURCE_KEY = 'SOURCEKEY';
  COL_DEST_TABLE = 'DESTTABLE';
  COL_DEST_KEY = 'DESTKEY';
  COL_DEST_VALUE = 'DESTVALUE';
  COL_VISIBLE = 'VISIBLE';
  COL_FORM = 'FORM_NAME';
  COL_VIEW = 'VIEW_NAME';
  COL_COLUMN = 'COLUMN_NAME';
  COL_INDEX = 'COLUMN_INDEX';
  OBJECT_KIND = 'object';
  SQL_FIELD_ROW = 'SELECT * FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F';
  SQL_TABLE_FIELDS = 'SELECT "FIELD_NAME", "FIELD_KIND", "SOURCEKEY", "CALC_BODY" FROM "DL_FIELDS_INFO" ' +
    'WHERE UPPER("TABLE_NAME") = UPPER(:T) ORDER BY "FIELD_NAME"';
  SQL_GRID_ROW = 'SELECT * FROM "DL_GRID_COLUMNS" WHERE "FORM_NAME" = :F AND "VIEW_NAME" = :V AND "COLUMN_NAME" = :C';
  SQL_GRID_FORM = 'SELECT * FROM "DL_GRID_COLUMNS" WHERE UPPER("FORM_NAME") = UPPER(:F) ORDER BY "VIEW_NAME", "COLUMN_INDEX", "COLUMN_NAME"';
  MULTI_FIELD = ';';
  WARN_VALUE_LEN = 60; // a warning shows the start of a value; the change set has all of it
  { Columns the schema owns: written with a new row, never updated from a DFM. }
  INSERT_ONLY: array[0..2] of string = ('FIELD_AS_TYPE', 'VAR_TYPE', 'STRING_SIZE');

type
  { One value a dataset states for a column. }
  TFactValue = record
    Value: string;
    Blocked: string;
    Source: string;
  end;

  { Everything the read datasets state about one column (or event) of a field. }
  TFactColumn = record
    Name: string;
    Values: TArray<TFactValue>;
    procedure Add(const pValue, pBlocked, pSource: string);
    function Good: TArray<TFactValue>;
  end;

  TFieldFacts = class
    TableName: string;
    FieldName: string;
    Columns: TArray<TFactColumn>;
    procedure Add(const pColumn, pValue, pBlocked, pSource: string);
    function Kinds: TArray<TFactValue>;
  end;

  { A DL_FIELDS_INFO row the repository has. }
  TRepoRow = record
    TableName: string;
    FieldName: string;
    IsColumn: Boolean; // the schema read has a type for it
    Kind: TFrFieldKind;
  end;

  { A column of a grid view, read or stored. }
  TGridRow = record
    FormName: string;
    ViewName: string;
    ColumnName: string;
    Values: TArray<TDfmrPair>; // TABLE_NAME, FIELD_NAME, COLUMN_INDEX, then in a schema-5 repository PROPERTIES_CLASS_NAME, PROPERTIES; '' = NULL
    function Key: string;
    function Text: string;
  end;

  { Where a dataset's fields come from. }
  TDatasetSource = record
    TableName: string;  // table of calc / lookup fields, and of data fields without a SELECT
    Sql: TDfmrSqlSource;
    HasSql: Boolean;
    Reason: string;
    IsJoin: Boolean;              // a SELECT over several tables: every field has its own table
    Columns: TDfmrColumnCheck;    // schema facts for unqualified columns; nil = none
    Via: string;                  // links followed to the source: `AttachedTo memA > CopyDataSet tblX`; '' = none
    LinkKind: string;             // kind of the first link; '' = none
    Linked: Boolean;              // the dataset has a link (followed or not)
    Written: TArray<TDfmrPair>;   // copied data fields the unit writes: upper FieldName -> `Unit.pas:line`
  end;

  { A DL_FIELD_INPUTS row a placed cross-table calc field needs (design 2.2, default binding). }
  TPlannedInput = record
    TableName: string;
    FieldName: string;
    Alias: string;
    Target: string;
    Rule: string;
    Source: string;
    Steps: TArray<TFrRelation>;
    function Path: string;
  end;

  { The table and column of one field of a join; Table '' = none, Why says why. }
  TFieldOrigin = record
    Table: string;
    Column: string;
    Why: string;
  end;

  TOrigins = TDictionary<string, TFieldOrigin>; // lower-case component name -> origin

  { The dataset behind a grid view. }
  TViewSource = record
    Found: Boolean;
    Local: Boolean; // the dataset is on the form of the view
    Form: TDfmrForm;
    Dataset: TDfmrDataset;
    Source: TDatasetSource;
    Context: TDfmrCodeContext;
  end;

  TDfmRead = class  // dl:ok high-response@c61e -- REVIEWED 2026-11-23 TT-DFMREAD: one read = collect facts + compare; private to the unit, its response set is FireDAC, dictionary and string calls
  strict private
    FRepo: TFDConnection;
    FPlan: TDfmrPlan;
    FWarnings: TStringList;
    FRows: TDictionary<string, TRepoRow>;
    FSchemaTables: TDictionary<string, Boolean>;
    FForms: TDictionary<string, TDfmrForm>;
    FRoots: TDictionary<string, string>; // `folder|root object` -> DFM; `folder|` = the folder was listed
    FUnits: TObjectDictionary<string, TDfmrUnit>;
    FFacts: TObjectDictionary<string, TFieldFacts>;
    FOrder: TList<TFieldFacts>;
    FGridRows: TList<TGridRow>;
    FGridSeen: TDictionary<string, Boolean>; // key of every row of FGridRows
    FEditors: Boolean;        // the repository has the editor columns of DL_GRID_COLUMNS (schema 5)
    FEditorsLeftOut: Integer; // read columns with an editor that an older repository cannot hold
    FChanges: TList<TFrChange>;
    FItems: TList<TDfmrChangeItem>;
    FColumns: TDfmrColumnCheck; // the repository's schema facts, for SqlFieldColumn
    FGraph: TFrRelationGraph;                      // the repository's relation graph (design 3.2)
    FBaseRelations: TArray<TFrRelation>;           // FGraph's edges, to copy it with a form's offers
    FKeys: TArray<TFrTableKey>;                    // PK / UNIQUE constraints of the schema facts
    FStoredRelations: TArray<string>;              // upper-case DL_RELATIONS names
    FStoredInputs: TDictionary<string, string>;    // TABLE|FIELD|ALIAS (default binding, upper) -> PATH
    FOffers: TDictionary<string, TFrRelation>;     // upper name -> offered FORM relation
    FOfferOrder: TList<TFrRelation>;
    FInputs: TList<TPlannedInput>;
    FUnitTexts: TDictionary<string, string>;       // lower-case .pas path -> source ('' = none)
    FUnitLinks: TDictionary<string, TArray<TDfmrLink>>;
    FCross: TDfmrCrossTotals;
    FUnchecked: TDictionary<string, string>;      // KeyOf(table, field) of a placed field whose input needs an offer -> why
    procedure LoadRows;
    procedure LoadCrossTable;
    function UnitText(const pFile: string): string;
    function CodeLinksTo(const pForm: TDfmrForm; const pDataset: TDfmrDataset): TArray<TDfmrLink>;
    function LinkedSource(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pChain, pNames: TArray<string>): TDatasetSource;
    function KeyOfTable(const pTable: string; const pColumns: TArray<string>): string;
    function OfferFor(const pChild, pParent, pKey: string; const pChildColumns, pParentColumns: TArray<string>): TFrRelation;
    function DatasetGraph(const pSource: TDatasetSource; out pFormRelations: TArray<string>): TFrRelationGraph;
    function PlaceSeveral(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pSource: TDatasetSource;
      const pContext: TDfmrCodeContext; pOrigins: TOrigins; pBodies: TDictionary<string, TDfmrBody>; const pKey: string;
      pGraph: TFrRelationGraph; const pFormRelations: TArray<string>; out pWhy: string): Boolean;
    procedure PlaceAllSeveral(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pSource: TDatasetSource;
      const pContext: TDfmrCodeContext; pOrigins: TOrigins; pBodies: TDictionary<string, TDfmrBody>; pSeveral: TList<string>);
    function AddRowChange(pOp: TFrChangeOp; const pTable, pKey, pProp, pOld, pNew: string;
      const pColumns: TArray<TDfmrPair>; pChecked: Boolean): Integer;
    procedure PlanRelations;
    procedure PlanInputs;
    procedure UncheckOffered;
    function HasSchemaColumn(const pTable, pColumn: string; out pKnown: Boolean): Boolean;
    function CalcBodyOf(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pContext: TDfmrCodeContext;
      const pField: TDfmrField): TDfmrBody;
    procedure JoinOrigins(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pSource: TDatasetSource;
      const pContext: TDfmrCodeContext; pOrigins: TOrigins; pBodies: TDictionary<string, TDfmrBody>);
    function Form(const pFile: string): TDfmrForm;
    function UnitOf(const pFile: string): TDfmrUnit;
    function SiblingForm(const pFile, pRoot: string): string;
    function FactsOf(const pTable, pField: string): TFieldFacts;
    function LookupTarget(const pForm: TDfmrForm; const pName: string; out pDataset: TDfmrDataset): Boolean;
    procedure ReadDataset(const pForm: TDfmrForm; const pDataset: TDfmrDataset);
    procedure ReadField(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pOwnerSource: TDatasetSource;
      const pField: TDfmrField; const pTable, pColumn: string);
    procedure ReadLookup(const pForm: TDfmrForm; const pOwner: TDfmrDataset; const pOwnerSource: TDatasetSource;
      const pField: TDfmrField; pFacts: TFieldFacts; const pSource: string);
    procedure ReadCalc(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pBody: TDfmrBody;
      const pField: TDfmrField; pFacts: TFieldFacts; var pReport: TDfmrDatasetReport);
    procedure ReadEvents(const pForm: TDfmrForm; const pContext: TDfmrCodeContext; const pEvents: TArray<TDfmrPair>;
      const pOwner: string; pFacts: TFieldFacts; pOrigins: TOrigins = nil);
    function OwnerForm(const pForm: TDfmrForm; const pName: string; out pOwner: TDfmrForm; out pLocal: string): Boolean;
    function ViewSource(const pForm: TDfmrForm; const pView: TDfmrGridView): TViewSource;
    procedure ReadView(const pForm: TDfmrForm; const pView: TDfmrGridView; const pDataset: string);
    procedure ReadColumn(const pForm: TDfmrForm; const pView: TDfmrGridView; const pSource: TViewSource; pIndex: Integer);
    procedure ReadColumnEvents(const pForm: TDfmrForm; const pView: TDfmrGridView; const pSource: TViewSource;
      const pColumn: TDfmrGridColumn; const pTable, pField: string);
    procedure WarnEvents(const pWhere, pWhy: string; const pEvents: TArray<TDfmrPair>);
    procedure PlanGridForm(const pForm: string; pDeletes: Boolean);
    procedure PlanGridRow(const pRow: TGridRow; pOld: TDictionary<string, TGridRow>);
    function AddGridChange(pOp: TFrChangeOp; const pRow: TGridRow; const pProp, pOldValue, pNewValue: string): Integer;
    procedure WarnForm(const pWhere: string; const pBody: TDfmrBody);
    function AddChange(pOp: TFrChangeOp; const pFacts: TFieldFacts; const pProp, pOld, pNew: string): Integer;
    procedure WarnNoRow(pFacts: TFieldFacts);
    procedure PlanNew(pFacts: TFieldFacts);
    procedure PlanExisting(pFacts: TFieldFacts; const pRow: TRepoRow);
    procedure ListRoots(const pFolder: string);
    function PlanKind(pFacts: TFieldFacts; const pRow: TRepoRow; pQuery: TFDQuery): TFrFieldKind;
    procedure PlanColumn(pFacts: TFieldFacts; const pColumn: TFactColumn; const pOld: string);
    function NewRowBlock(pFacts: TFieldFacts): string;
    procedure PlanAll(const pFiles: TArray<string>; pDeletes: Boolean);
  public
    constructor Create(pRepo: TFDConnection);
    destructor Destroy; override;
    function Execute(const pFiles: TArray<string>; const pDataset: string): TDfmrPlan;
  end;

function KeyOf(const pTable, pField: string): string;
begin
  Result := UpperCase(pTable) + '|' + UpperCase(pField);
end;

function MakePair(const pName, pValue: string): TDfmrPair;
begin
  Result.Name := pName;
  Result.Value := pValue;
end;

function SameValue(const pA, pB: string): Boolean;
begin
  Result := pA.Replace(#13#10, #10) = pB.Replace(#13#10, #10);
end;

{ TFactColumn }

procedure TFactColumn.Add(const pValue, pBlocked, pSource: string);
var
  VValue: TFactValue;
begin
  for VValue in Values do
    if SameValue(VValue.Value, pValue) and (VValue.Blocked = pBlocked) then
      Exit;
  VValue.Value := pValue;
  VValue.Blocked := pBlocked;
  VValue.Source := pSource;
  Values := Values + [VValue];
end;

{ The storable values; every value when none is storable. }
function TFactColumn.Good: TArray<TFactValue>;
var
  VValue: TFactValue;
begin
  Result := nil;
  for VValue in Values do
    if VValue.Blocked = '' then
      Result := Result + [VValue];
  if Length(Result) = 0 then
    Result := Values;
end;

{ TFieldFacts }

procedure AddFact(var pList: TArray<TFactColumn>; const pColumn, pValue, pBlocked, pSource: string);
var
  VI: Integer;
  VColumn: TFactColumn;
begin
  for VI := 0 to High(pList) do
    if SameText(pList[VI].Name, pColumn) then
    begin
      pList[VI].Add(pValue, pBlocked, pSource);
      Exit;
    end;
  VColumn := Default(TFactColumn);
  VColumn.Name := pColumn;
  VColumn.Add(pValue, pBlocked, pSource);
  pList := pList + [VColumn];
end;

procedure TFieldFacts.Add(const pColumn, pValue, pBlocked, pSource: string);
var
  VTable: TRepoTable;
  VColumn: TRepoColumn;
  VBlocked: string;
begin
  VBlocked := pBlocked;
  if (VBlocked = '') and FindRepoTable(FIELDS_TABLE, VTable) and VTable.FindColumn(pColumn, VColumn)
    and (VColumn.MaxLen > 0) and (Length(pValue) > VColumn.MaxLen) then
    VBlocked := Format('longer than %s(%d)', [pColumn, VColumn.MaxLen]);
  AddFact(Columns, pColumn, pValue, VBlocked, pSource);
end;

function TFieldFacts.Kinds: TArray<TFactValue>;
var
  VColumn: TFactColumn;
begin
  Result := nil;
  for VColumn in Columns do
    if VColumn.Name = COL_KIND then
      Exit(VColumn.Good);
end;

{ ---- sources ---- }

function SourceOf(const pDataset: TDfmrDataset; const pColumns: TDfmrColumnCheck = nil): TDatasetSource;
var
  VTable: TDfmrSqlTable;
begin
  Result := Default(TDatasetSource);
  Result.Columns := pColumns;
  Result.HasSql := (pDataset.TableName = '') and (pDataset.Sql <> '');
  if Result.HasSql then
    Result.Sql := ReadSelectSource(pDataset.Sql);
  if pDataset.UpdateTableName <> '' then
    Result.TableName := CleanTableName(pDataset.UpdateTableName)
  else if pDataset.TableName <> '' then
    Result.TableName := CleanTableName(pDataset.TableName)
  else if not Result.HasSql then
    Result.Reason := 'no TableName and no SQL in the DFM'
  else if Result.Sql.Reason <> '' then
    Result.Reason := Result.Sql.Reason
  else if Length(Result.Sql.Tables) = 1 then
    Result.TableName := Result.Sql.Tables[0].Name
  else
  begin
    Result.IsJoin := True;
    Result.Reason := Format('the SQL reads %d tables:', [Length(Result.Sql.Tables)]);
    for VTable in Result.Sql.Tables do
      Result.Reason := Result.Reason + ' ' + VTable.Name;
  end;
end;

{ The table and column of a persistent field; False = the DFM does not state it. A calc / lookup field of a join gets
  its table from TDfmRead.JoinOrigins, not here. }
function FieldSource(const pSource: TDatasetSource; const pField: TDfmrField; out pTable, pColumn, pReason: string): Boolean;
var
  VWrite: TDfmrPair;
begin
  pTable := pSource.TableName;
  pColumn := UpperCase(Trim(pField.FieldName));
  pReason := pSource.Reason;
  if pField.Kind = frkData then
    for VWrite in pSource.Written do
      if SameText(VWrite.Name, pColumn) then
      begin
        pTable := '';
        pReason := 'written in code after the copy (' + VWrite.Value + ')';
        Exit(False);
      end;
  if (pField.Kind = frkData) and pSource.HasSql and (pSource.Sql.Reason = '') then
    Exit(SqlFieldColumn(pSource.Sql, pField.FieldName, pField.Origin, pSource.Columns, pTable, pColumn, pReason));
  Result := pTable <> '';
end;

{ The macro a field gets in handler code: the column of its own table. In a join every field with a table has one (the
  table of the whole body is checked afterwards); a calc or lookup field of a join is named by its FieldName. }
function CodeContext(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pSource: TDatasetSource): TDfmrCodeContext;
var
  VField: TDfmrField;
  VCode: TDfmrCodeField;
  VTable, VColumn, VReason: string;
begin
  Result := Default(TDfmrCodeContext);
  Result.FormClass := pForm.FormClass;
  Result.Dataset := pDataset.Name;
  Result.Components := pForm.Components;
  for VField in pDataset.Fields do
  begin
    VCode.CompName := VField.CompName;
    VCode.DataName := VField.FieldName;
    VCode.IsCalc := VField.Kind in [frkCalc, frkInternalCalc];
    VCode.MacroName := '';
    if pSource.IsJoin and (VField.Kind in [frkCalc, frkInternalCalc, frkLookup]) then
      VColumn := UpperCase(Trim(VField.FieldName))
    else if (not FieldSource(pSource, VField, VTable, VColumn, VReason)) or ((not pSource.IsJoin) and (VTable <> pSource.TableName)) then
      VColumn := '';
    if IsValidIdent(VColumn) then
      VCode.MacroName := VColumn;
    Result.Fields := Result.Fields + [VCode];
  end;
end;

{ TGridRow }

function TGridRow.Key: string;
begin
  Result := UpperCase(FormName + '|' + ViewName + '|' + ColumnName);
end;

{ The stored values, NULLs left out. }
function TGridRow.Text: string;
var
  VPair: TDfmrPair;
begin
  Result := '';
  for VPair in Values do
    if VPair.Value <> '' then
      Result := Result + (if Result = '' then '' else '; ') + VPair.Name + '=' + VPair.Value;
end;

{ The persistent field of a dataset by its FieldName; a data field of that name when it has none. }
function NamedField(const pDataset: TDfmrDataset; const pName: string): TDfmrField;
var
  VField: TDfmrField;
begin
  Result := Default(TDfmrField);
  Result.FieldName := pName;
  for VField in pDataset.Fields do
    if SameText(VField.FieldName, Trim(pName)) then
      Exit(VField);
end;

{ TDfmRead }

constructor TDfmRead.Create(pRepo: TFDConnection);
begin
  inherited Create;
  FRepo := pRepo;
  FWarnings := TStringList.Create(dupIgnore, False, False);
  FRows := TDictionary<string, TRepoRow>.Create;
  FSchemaTables := TDictionary<string, Boolean>.Create;
  FForms := TDictionary<string, TDfmrForm>.Create;
  FRoots := TDictionary<string, string>.Create;
  FUnits := TObjectDictionary<string, TDfmrUnit>.Create([doOwnsValues]);
  FFacts := TObjectDictionary<string, TFieldFacts>.Create([doOwnsValues]);
  FOrder := TList<TFieldFacts>.Create;
  FGridRows := TList<TGridRow>.Create;
  FGridSeen := TDictionary<string, Boolean>.Create;
  FEditors := RepoSchemaVersion(pRepo) >= SCHEMA_WITH_EDITORS;
  FChanges := TList<TFrChange>.Create;
  FItems := TList<TDfmrChangeItem>.Create;
  FColumns := HasSchemaColumn;
  FStoredInputs := TDictionary<string, string>.Create;
  FOffers := TDictionary<string, TFrRelation>.Create;
  FOfferOrder := TList<TFrRelation>.Create;
  FInputs := TList<TPlannedInput>.Create;
  FUnitTexts := TDictionary<string, string>.Create;
  FUnitLinks := TDictionary<string, TArray<TDfmrLink>>.Create;
  FUnchecked := TDictionary<string, string>.Create;
end;

function TDfmRead.HasSchemaColumn(const pTable, pColumn: string; out pKnown: Boolean): Boolean;
var
  VRow: TRepoRow;
begin
  pKnown := FSchemaTables.ContainsKey(UpperCase(pTable));
  Result := pKnown and FRows.TryGetValue(KeyOf(pTable, pColumn), VRow) and VRow.IsColumn;
end;

destructor TDfmRead.Destroy;
begin
  FUnchecked.Free;
  FUnitLinks.Free;
  FUnitTexts.Free;
  FInputs.Free;
  FOfferOrder.Free;
  FOffers.Free;
  FStoredInputs.Free;
  FGraph.Free;
  FItems.Free;
  FChanges.Free;
  FGridSeen.Free;
  FGridRows.Free;
  FOrder.Free;
  FFacts.Free;
  FUnits.Free;
  FRoots.Free;
  FForms.Free;
  FSchemaTables.Free;
  FRows.Free;
  FWarnings.Free;
  inherited;
end;

procedure TDfmRead.LoadRows;
var
  VQuery: TFDQuery;
  VTable, VField, VType, VKind: TField;
  VRow: TRepoRow;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := FRepo;
    VQuery.Open('SELECT "TABLE_NAME", "FIELD_NAME", "FIELD_TYPE", "FIELD_KIND" FROM "DL_FIELDS_INFO"');
    VTable := VQuery.FieldByName(COL_TABLE);
    VField := VQuery.FieldByName(COL_FIELD);
    VType := VQuery.FieldByName('FIELD_TYPE');
    VKind := VQuery.FieldByName(COL_KIND);
    while not VQuery.Eof do
    begin
      VRow.TableName := VTable.AsString;
      VRow.FieldName := VField.AsString;
      VRow.IsColumn := VType.AsInteger <> 0;
      VRow.Kind := if FrKindCodeKnown(VKind.Value) then FrKindFromCode(VKind.Value) else frkData;
      FRows.AddOrSetValue(KeyOf(VRow.TableName, VRow.FieldName), VRow);
      if VRow.IsColumn then
        FSchemaTables.AddOrSetValue(UpperCase(VRow.TableName), True);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ ---- cross-table (design 2026-11-26-cross-table-fields 3.1, 3.2) ---- }

{ pTables in the order of the FROM clause. }
function InFromOrder(const pSource: TDatasetSource; const pTables: TArray<string>): TArray<string>;
var
  VTable: TDfmrSqlTable;
begin
  Result := nil;
  for VTable in pSource.Sql.Tables do
    if MatchText(VTable.Name, pTables) and (not MatchText(VTable.Name, Result)) then
      Result := Result + [VTable.Name];
end;

function TPlannedInput.Path: string;
var
  VStep: TFrRelation;
begin
  Result := '';
  for VStep in Steps do
    Result := Result + (if Result = '' then '' else REPO_PATH_SEPARATOR) + VStep.Name;
end;

function InputKey(const pTable, pField, pAlias: string): string;
begin
  Result := UpperCase(pTable + '|' + pField + '|' + pAlias);
end;

procedure TDfmRead.LoadCrossTable;
var
  VSkipped: TArray<string>;
  VQuery: TFDQuery;
begin
  FGraph := LoadRelationGraph(FRepo, VSkipped);
  FBaseRelations := FGraph.Relations;
  FKeys := LoadTableKeys(FRepo);
  FStoredRelations := LoadStoredRelationNames(FRepo);
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := FRepo;
    VQuery.Open(SQL_STORED_INPUTS);
    while not VQuery.Eof do
    begin
      FStoredInputs.AddOrSetValue(InputKey(VQuery.Fields[0].AsString, VQuery.Fields[1].AsString, VQuery.Fields[2].AsString),
        VQuery.Fields[3].AsString);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ The source of a form's unit, '' when there is none (cached: links and writes are read from it). }
function TDfmRead.UnitText(const pFile: string): string;
var
  VPas: string;
begin
  VPas := LowerCase(ChangeFileExt(pFile, '.pas'));
  if FUnitTexts.TryGetValue(VPas, Result) then
    Exit;
  Result := if TFile.Exists(VPas) then TFile.ReadAllText(VPas) else '';
  FUnitTexts.Add(VPas, Result);
end;

{ The literal links of the form's unit whose receiver is the dataset (`X`, `Self.X`). }
function TDfmRead.CodeLinksTo(const pForm: TDfmrForm; const pDataset: TDfmrDataset): TArray<TDfmrLink>;
var
  VKey: string;
  VAll: TArray<TDfmrLink>;
  VLink: TDfmrLink;
begin
  VKey := LowerCase(pForm.FileName);
  if not FUnitLinks.TryGetValue(VKey, VAll) then
  begin
    VAll := ReadCodeLinks(UnitText(pForm.FileName));
    FUnitLinks.Add(VKey, VAll);
  end;
  Result := nil;
  for VLink in VAll do
    if SameText(VLink.Target, pDataset.Name) then
      Result := Result + [VLink];
end;

{ The source of a dataset, through AttachedTo and the literal link calls of its unit when it has no table and no SQL
  (design 3.1). pChain holds `file|dataset` of the datasets already on the way (cycle guard), pNames their names. }
function TDfmRead.LinkedSource(const pForm: TDfmrForm; const pDataset: TDfmrDataset;  // dl:ok too-many-exit-points@edb2 -- REVIEWED 2026-11-26 XTABLE X3: each Exit is one reason a link gives no source (none, two sources, no dataset, cycle, source without table, not a copy); guard clauses read in rule order
  const pChain, pNames: TArray<string>): TDatasetSource;
var
  VLinks: TArray<TDfmrLink>;
  VLink: TDfmrLink;
  VSources, VWhere: TArray<string>;
  VOwner: TDfmrForm;
  VSource, VCandidate: TDfmrDataset;
  VSub: TDatasetSource;
  VLocal, VKey, VKind, VPas: string;
  VFound: Boolean;
  VFields, VWrites: TArray<TDfmrPair>;
  VField: TDfmrField;
  VPair: TDfmrPair;
begin
  Result := SourceOf(pDataset, FColumns);
  if (Result.TableName <> '') or Result.HasSql then
    Exit;
  VLinks := CodeLinksTo(pForm, pDataset);
  VPas := ExtractFileName(ChangeFileExt(pForm.FileName, '.pas'));
  if pDataset.AttachedTo <> '' then
  begin
    VLink.Kind := dlkAttachedTo;
    VLink.Target := pDataset.Name;
    VLink.Source := pDataset.AttachedTo;
    VLink.Line := 0;
    VLinks := [VLink] + VLinks;
  end;
  if Length(VLinks) = 0 then
    Exit;
  Result.Linked := True;
  VSources := nil;
  VWhere := nil;
  for VLink in VLinks do
    if not MatchText(VLink.Source, VSources) then
    begin
      VSources := VSources + [VLink.Source];
      VWhere := VWhere + [DfmrLinkKindName(VLink.Kind) + ' ' + VLink.Source + ' (' + (if VLink.Line = 0
        then ExtractFileName(pForm.FileName) else VPas + ':' + IntToStr(VLink.Line)) + ')'];
    end;
  if Length(VSources) > 1 then
  begin
    Result.Reason := Format('linked to %d sources: %s', [Length(VSources), string.Join(', ', VWhere)]);
    Exit;
  end;
  VLink := VLinks[0];
  VKind := DfmrLinkKindName(VLink.Kind);
  VFound := False;
  VSource := Default(TDfmrDataset);
  if OwnerForm(pForm, VLink.Source, VOwner, VLocal) then
    for VCandidate in VOwner.Datasets do
      if SameText(VCandidate.Name, VLocal) then
      begin
        VSource := VCandidate;
        VFound := True;
        Break;
      end;
  if not VFound then
  begin
    Result.Reason := Format('linked to %s (%s), which is no dataset of the form or of a module beside it', [VLink.Source, VKind]);
    Exit;
  end;
  VKey := LowerCase(VOwner.FileName + '|' + VSource.Name);
  if MatchText(VKey, pChain) then
  begin
    Result.Reason := 'the links ' + string.Join(' > ', pNames) + ' > ' + VSource.Name + ' are a cycle';
    Exit;
  end;
  VSub := LinkedSource(VOwner, VSource, pChain + [VKey], pNames + [VSource.Name]);
  if (VSub.TableName = '') and (not VSub.IsJoin) then
  begin
    Result.Reason := if VSub.Linked then VSub.Reason
      else Format('linked to %s (%s), which has no table: %s', [VLink.Source, VKind, VSub.Reason]);
    Exit;
  end;
  Result := VSub;
  Result.Linked := True;
  Result.LinkKind := VKind;
  Result.Via := VKind + ' ' + VLink.Source + (if VSub.Via = '' then '' else ' > ' + VSub.Via);
  Result.Written := nil;
  if not DfmrLinkIsCopy(VLink.Kind) then
    Exit;
  VFields := nil;
  for VField in pDataset.Fields do
    if VField.Kind = frkData then
      VFields := VFields + [MakePair(VField.CompName, VField.FieldName)];
  VWrites := ReadFieldWrites(UnitText(pForm.FileName), pDataset.Name, VFields);
  for VPair in VWrites do
    Result.Written := Result.Written + [MakePair(VPair.Name, VPas + ':' + VPair.Value)];
end;

{ The PK / UNIQUE constraint of pTable on exactly pColumns (any order); '' = none. }
function TDfmRead.KeyOfTable(const pTable: string; const pColumns: TArray<string>): string;
var
  VKey: TFrTableKey;
  VLeft, VRight: TArray<string>;
begin
  Result := '';
  VLeft := Copy(pColumns);
  TArray.Sort<string>(VLeft, TIStringComparer.Ordinal);
  for VKey in FKeys do
    if SameText(VKey.TableName, pTable) then
    begin
      VRight := Copy(VKey.Columns);
      TArray.Sort<string>(VRight, TIStringComparer.Ordinal);
      if (Length(VLeft) > 0) and SameText(string.Join(',', VLeft), string.Join(',', VRight)) then
        Exit(VKey.ConstraintName);
    end;
end;

{ A FORM relation for a join on a parent key (ruling XQ6): the one already offered for the same child, parent and
  columns, else a new one named `CHILD_PARENT` (`_2`, ... on a clash). }
function TDfmRead.OfferFor(const pChild, pParent, pKey: string; const pChildColumns, pParentColumns: TArray<string>): TFrRelation;
var
  VRel: TFrRelation;
  VBase: string;
  VN: Integer;

  function Taken(const pName: string): Boolean;
  var
    VBaseRel: TFrRelation;
  begin
    Result := FOffers.ContainsKey(UpperCase(pName)) or MatchText(pName, FStoredRelations);
    for VBaseRel in FBaseRelations do
      Result := Result or SameText(VBaseRel.Name, pName);
  end;

begin
  for VRel in FOfferOrder do
    if SameText(VRel.ChildTable, pChild) and SameText(VRel.ParentTable, pParent)
      and SameText(string.Join(',', VRel.ChildColumns), string.Join(',', pChildColumns))
      and SameText(string.Join(',', VRel.ParentColumns), string.Join(',', pParentColumns)) then
      Exit(VRel);
  Result := Default(TFrRelation);
  VBase := UpperCase(pChild + '_' + pParent);
  Result.Name := VBase;
  VN := 1;
  while Taken(Result.Name) do
  begin
    Inc(VN);
    Result.Name := VBase + '_' + IntToStr(VN);
  end;
  Result.ChildTable := pChild;
  Result.ParentTable := pParent;
  Result.Source := REPO_RELATION_FORM;
  Result.ParentKey := pKey;
  Result.ChildColumns := pChildColumns;
  Result.ParentColumns := pParentColumns;
  FOffers.Add(UpperCase(Result.Name), Result);
  FOfferOrder.Add(Result);
end;

function SamePairs(const pChildA, pParentA, pChildB, pParentB: TArray<string>): Boolean;
var
  VA, VB: TArray<string>;
  VI: Integer;
begin
  Result := (Length(pChildA) = Length(pChildB)) and (Length(pChildA) = Length(pParentA)) and
    (Length(pChildB) = Length(pParentB));
  if not Result then
    Exit;
  VA := nil;
  VB := nil;
  for VI := 0 to High(pChildA) do  // dl:ok index-possibly-out-of-range@c1ec -- REVIEWED 2026-11-26 XTABLE X3: the four lengths are compared equal before the loop (Exit otherwise)
  begin
    VA := VA + [UpperCase(pChildA[VI] + '=' + pParentA[VI])];
    VB := VB + [UpperCase(pChildB[VI] + '=' + pParentB[VI])];
  end;
  TArray.Sort<string>(VA);
  TArray.Sort<string>(VB);
  Result := string.Join(',', VA) = string.Join(',', VB);
end;

{ The relations the form's own joins use (design 3.2 rule 2): the equalities between two FROM entries, grouped per
  entry pair, matched to the graph's one-step relations column for column; a group that matches none and ends on a
  parent key is offered as a FORM relation (XQ6). Returns FGraph, or a copy of it with this dataset's offers (the
  caller frees a copy): an offer is no edge for another dataset. }
function TDfmRead.DatasetGraph(const pSource: TDatasetSource; out pFormRelations: TArray<string>): TFrRelationGraph;
type
  TJoinGroup = record
    ATable, BTable, AAlias, BAlias: string;
    ACols, BCols: TArray<string>;
  end;
var
  VGroups: TArray<TJoinGroup>;
  VGroup: TJoinGroup;
  VJoin: TDfmrSqlJoin;
  VI: Integer;
  VFound, VMatched: Boolean;
  VPath: TFrRelationPath;
  VRel: TFrRelation;
  VOffers: TArray<TFrRelation>;
  VKeyA, VKeyB: string;
begin
  pFormRelations := nil;
  VGroups := nil;
  VOffers := nil;
  for VJoin in pSource.Sql.Joins do
  begin
    if SameText(VJoin.LeftTable, VJoin.RightTable) then
      Continue;
    VGroup := Default(TJoinGroup);
    if CompareText(VJoin.LeftAlias, VJoin.RightAlias) <= 0 then
    begin
      VGroup.ATable := VJoin.LeftTable;
      VGroup.AAlias := VJoin.LeftAlias;
      VGroup.BTable := VJoin.RightTable;
      VGroup.BAlias := VJoin.RightAlias;
      VGroup.ACols := [VJoin.LeftColumn];
      VGroup.BCols := [VJoin.RightColumn];
    end
    else
    begin
      VGroup.ATable := VJoin.RightTable;
      VGroup.AAlias := VJoin.RightAlias;
      VGroup.BTable := VJoin.LeftTable;
      VGroup.BAlias := VJoin.LeftAlias;
      VGroup.ACols := [VJoin.RightColumn];
      VGroup.BCols := [VJoin.LeftColumn];
    end;
    VFound := False;
    for VI := 0 to High(VGroups) do
      if SameText(VGroups[VI].AAlias, VGroup.AAlias) and SameText(VGroups[VI].BAlias, VGroup.BAlias) then
      begin
        VGroups[VI].ACols := VGroups[VI].ACols + VGroup.ACols;
        VGroups[VI].BCols := VGroups[VI].BCols + VGroup.BCols;
        VFound := True;
      end;
    if not VFound then
      VGroups := VGroups + [VGroup];
  end;
  for VGroup in VGroups do
  begin
    VMatched := False;
    for VPath in FGraph.FindPaths(VGroup.ATable, VGroup.BTable, 1) do
      if SamePairs(VPath.Steps[0].ChildColumns, VPath.Steps[0].ParentColumns, VGroup.ACols, VGroup.BCols) then
      begin
        pFormRelations := pFormRelations + [VPath.Steps[0].Name];
        VMatched := True;
      end;
    for VPath in FGraph.FindPaths(VGroup.BTable, VGroup.ATable, 1) do
      if SamePairs(VPath.Steps[0].ChildColumns, VPath.Steps[0].ParentColumns, VGroup.BCols, VGroup.ACols) then
      begin
        pFormRelations := pFormRelations + [VPath.Steps[0].Name];
        VMatched := True;
      end;
    if VMatched then
      Continue;
    VKeyA := KeyOfTable(VGroup.ATable, VGroup.ACols);
    VKeyB := KeyOfTable(VGroup.BTable, VGroup.BCols);
    if (VKeyB <> '') and (VKeyA = '') then
      VRel := OfferFor(VGroup.ATable, VGroup.BTable, VKeyB, VGroup.ACols, VGroup.BCols)
    else if (VKeyA <> '') and (VKeyB = '') then
      VRel := OfferFor(VGroup.BTable, VGroup.ATable, VKeyA, VGroup.BCols, VGroup.ACols)
    else
      Continue;
    VOffers := VOffers + [VRel];
    pFormRelations := pFormRelations + [VRel.Name];
  end;
  if Length(VOffers) = 0 then
    Exit(FGraph);
  Result := TFrRelationGraph.Create;
  for VRel in FBaseRelations do
    Result.AddRelation(VRel);
  for VRel in VOffers do
    Result.AddRelation(VRel);
end;

{ Places a join calc field that reads several tables (design 3.1 CHILD END, 3.2 rules 1-5): the tables of the fields
  its code reads directly; the home is the one of them from which every other is reached; every other table is an
  input alias (XQ2: the table name) with the chosen path; the body is read again with ALIAS.COLUMN macros. False with
  pWhy when it cannot be placed (never a pick). }
function TDfmRead.PlaceSeveral(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pSource: TDatasetSource;  // dl:ok too-many-parameters@8c40 -- REVIEWED 2026-11-26 XTABLE X3: private step of JoinOrigins; the parameters are its per-dataset state (form, dataset, source, context, origins, bodies, field, graph, form relations, reason)
  const pContext: TDfmrCodeContext; pOrigins: TOrigins; pBodies: TDictionary<string, TDfmrBody>; const pKey: string;
  pGraph: TFrRelationGraph; const pFormRelations: TArray<string>; out pWhy: string): Boolean;
var
  VUsed, VTable, VOther, VHome, VField, VPrefix, VStored: string;
  VTables, VHomes, VOrdered: TArray<string>;
  VOrigin: TFieldOrigin;
  VSqlTable: TDfmrSqlTable;
  VCount, VI: Integer;
  VReaches: Boolean;
  VChoice: TFrPathChoice;
  VInput: TPlannedInput;
  VInputs: TArray<TPlannedInput>;
  VContext: TDfmrCodeContext;
  VDfmField: TDfmrField;
  VStep: TFrRelation;
begin
  Result := False;
  pWhy := '';
  VTables := nil;
  VField := '';
  for VDfmField in pDataset.Fields do
    if SameText(VDfmField.CompName, pKey) then
      VField := UpperCase(Trim(VDfmField.FieldName));
  for VUsed in pBodies[pKey].FieldsUsed do
  begin
    if VUsed = pKey then
      Continue;
    if pOrigins.TryGetValue(VUsed, VOrigin) and (VOrigin.Table <> '') then
    begin
      if not MatchText(VOrigin.Table, VTables) then
        VTables := VTables + [VOrigin.Table];
    end
    else
    begin
      for VDfmField in pDataset.Fields do
        if SameText(VDfmField.CompName, VUsed) then
          pWhy := Format('the calc code reads %s, which has no table of its own', [VDfmField.FieldName]);
      Exit;
    end;
  end;
  VOrdered := InFromOrder(pSource, VTables);
  if Length(VOrdered) < 2 then
    Exit;
  VPrefix := Format('the calc code reads %d tables: %s', [Length(VOrdered), string.Join(' ', VOrdered)]);
  for VTable in VOrdered do
  begin
    VCount := 0;
    for VSqlTable in pSource.Sql.Tables do
      if SameText(VSqlTable.Name, VTable) then
        Inc(VCount);
    if VCount > 1 then
    begin
      pWhy := Format('%s; %s is in the FROM %d times', [VPrefix, VTable, VCount]);
      Exit;
    end;
  end;
  VHomes := nil;
  for VTable in VOrdered do
  begin
    VReaches := True;
    for VOther in VOrdered do
      if (not SameText(VOther, VTable)) and (Length(pGraph.FindPaths(VTable, VOther)) = 0) then
        VReaches := False;
    if VReaches then
      VHomes := VHomes + [VTable];
  end;
  if Length(VHomes) = 0 then
    pWhy := Format('%s; no table of %s reaches all the others', [VPrefix, string.Join(' ', VOrdered)])
  else if Length(VHomes) > 1 then
    pWhy := Format('%s; %s each reach all the others (a 1:1 pair)', [VPrefix, string.Join(' ', VHomes)]);
  if pWhy <> '' then
    Exit;
  VHome := VHomes[0];
  VInputs := nil;
  for VOther in VOrdered do
  begin
    if SameText(VOther, VHome) then
      Continue;
    VInput := Default(TPlannedInput);
    VInput.TableName := VHome;
    VInput.FieldName := VField;
    VInput.Alias := DefaultInputAlias(VOther, 1);
    VInput.Target := VOther;
    VInput.Source := ExtractFileName(pForm.FileName) + ' ' + pDataset.Name;
    if not FStoredInputs.TryGetValue(InputKey(VHome, VField, VInput.Alias), VStored) then
      VStored := '';
    VChoice := pGraph.Choose(VHome, VOther, VStored, pFormRelations);
    if VChoice.Chosen < 0 then
    begin
      pWhy := Format('%s; home %s; %d paths to %s, none chosen (asked once)', [VPrefix, VHome, Length(VChoice.Paths), VOther]);
      Exit;
    end;
    VInput.Steps := VChoice.Paths[VChoice.Chosen].Steps;
    VInput.Rule := PathRuleName(VChoice.Rule);
    VInputs := VInputs + [VInput];
  end;
  VContext := pContext;
  VContext.Fields := Copy(pContext.Fields);
  for VI := 0 to High(VContext.Fields) do
    if pOrigins.TryGetValue(LowerCase(VContext.Fields[VI].CompName), VOrigin) and (VOrigin.Table <> '')
      and (not SameText(VOrigin.Table, VHome)) and MatchText(VOrigin.Table, VOrdered) then
      VContext.Fields[VI].MacroName := DefaultInputAlias(VOrigin.Table, 1) + '.' + VOrigin.Column;
  for VDfmField in pDataset.Fields do
    if SameText(VDfmField.CompName, pKey) then
      pBodies[pKey] := CalcBodyOf(pForm, pDataset, VContext, VDfmField);
  VOrigin := Default(TFieldOrigin);
  VOrigin.Table := VHome;
  VOrigin.Column := VField;
  pOrigins.AddOrSetValue(pKey, VOrigin);
  for VInput in VInputs do
  begin
    FInputs.Add(VInput);
    for VStep in VInput.Steps do
      if FOffers.ContainsKey(UpperCase(VStep.Name)) then
        FUnchecked.AddOrSetValue(KeyOf(VHome, VField), Format('its input %s goes through the offered relation %s: ' +
          'choose the relation, the input and the field together', [VInput.Alias, VStep.Name]));
  end;
  Result := True;
end;

{ Every join calc field of pSeveral (pass 1 found several tables), in DFM order, until none more is placed: a field
  placed may let a field that reads it be placed. Offers of the dataset's joins are made even when no field needs them. }
procedure TDfmRead.PlaceAllSeveral(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pSource: TDatasetSource;
  const pContext: TDfmrCodeContext; pOrigins: TOrigins; pBodies: TDictionary<string, TDfmrBody>; pSeveral: TList<string>);
var
  VGraph: TFrRelationGraph;
  VFormRelations, VOrder: TArray<string>;
  VField: TDfmrField;
  VKey, VWhy: string;
  VPlaced: TDictionary<string, string>; // key -> '' placed, else why not
  VChanged: Boolean;
  VOrigin: TFieldOrigin;
begin
  VGraph := DatasetGraph(pSource, VFormRelations);
  VPlaced := TDictionary<string, string>.Create;
  try
    VOrder := nil;
    for VField in pDataset.Fields do
      if pSeveral.Contains(LowerCase(VField.CompName)) then
        VOrder := VOrder + [LowerCase(VField.CompName)];
    repeat
      VChanged := False;
      for VKey in VOrder do
        if not (VPlaced.TryGetValue(VKey, VWhy) and (VWhy = '')) then
          if PlaceSeveral(pForm, pDataset, pSource, pContext, pOrigins, pBodies, VKey, VGraph, VFormRelations, VWhy) then
          begin
            VPlaced.AddOrSetValue(VKey, '');
            VChanged := True;
          end
          else
            VPlaced.AddOrSetValue(VKey, if VWhy = '' then '-' else VWhy);
    until not VChanged;
    for VKey in VOrder do
      if VPlaced[VKey] = '' then
        Inc(FCross.Placed)
      else
      begin
        Inc(FCross.Unresolved);
        if (VPlaced[VKey] <> '-') and pOrigins.TryGetValue(VKey, VOrigin) then
        begin
          VOrigin.Why := VPlaced[VKey];
          pOrigins.AddOrSetValue(VKey, VOrigin);
        end;
      end;
  finally
    VPlaced.Free;
    if VGraph <> FGraph then
      VGraph.Free;
  end;
end;

function TDfmRead.Form(const pFile: string): TDfmrForm;
var
  VText: string;
begin
  if FForms.TryGetValue(LowerCase(pFile), Result) then
    Exit;
  Result := LoadDfmForm(pFile);
  for VText in Result.Diagnostics do
    FWarnings.Add(ExtractFileName(pFile) + ': ' + VText);
  FForms.Add(LowerCase(pFile), Result);
end;

{ The parsed unit of a form, nil when there is no .pas beside the DFM. }
function TDfmRead.UnitOf(const pFile: string): TDfmrUnit;
var
  VPas: string;
begin
  VPas := ChangeFileExt(pFile, '.pas');
  if FUnits.TryGetValue(LowerCase(VPas), Result) then
    Exit;
  Result := nil;
  if TFile.Exists(VPas) then
    Result := TDfmrUnit.Create(VPas)
  else
    FWarnings.Add(ExtractFileName(pFile) + ': no unit beside the DFM, handler code not read');
  FUnits.Add(LowerCase(VPas), Result);
end;

{ Root objects of the DFMs of a folder; a DFM that cannot be read is a warning. }
procedure TDfmRead.ListRoots(const pFolder: string);
var
  VFile, VRoot: string;
begin
  for VFile in TDirectory.GetFiles(pFolder, '*.dfm') do
    try
      VRoot := LowerCase(pFolder + '|' + DfmRootName(VFile));
      FRoots.AddOrSetValue(VRoot, if FRoots.ContainsKey(VRoot) then '' else VFile);
    except
      on E: EDfmReadError do
        FWarnings.Add('lookup datasets: ' + E.Message);
    end;
end;

{ The one DFM of the same folder whose root object is pRoot; '' = none or more than one. }
function TDfmRead.SiblingForm(const pFile, pRoot: string): string;
var
  VFolder: string;
begin
  VFolder := TPath.GetDirectoryName(TPath.GetFullPath(pFile));
  if FRoots.TryAdd(LowerCase(VFolder) + '|', '') then
    ListRoots(VFolder);
  if not FRoots.TryGetValue(LowerCase(VFolder + '|' + pRoot), Result) then
    Result := '';
end;

function TDfmRead.FactsOf(const pTable, pField: string): TFieldFacts;
begin
  if FFacts.TryGetValue(KeyOf(pTable, pField), Result) then
    Exit;
  Result := TFieldFacts.Create;
  FFacts.Add(KeyOf(pTable, pField), Result);
  Result.TableName := pTable;
  Result.FieldName := pField;
  FOrder.Add(Result);
end;

{ The form that owns `Name` (this one) or `Module.Name` (a form of the same folder), and the name there. }
function TDfmRead.OwnerForm(const pForm: TDfmrForm; const pName: string; out pOwner: TDfmrForm; out pLocal: string): Boolean;
var
  VFile: string;
  VDot: Integer;
begin
  pOwner := pForm;
  pLocal := pName;
  VDot := pName.IndexOf('.');
  if VDot <= 0 then
    Exit(True);
  VFile := SiblingForm(pForm.FileName, pName.Substring(0, VDot));
  Result := VFile <> '';
  if not Result then
    Exit;
  pOwner := Form(VFile);
  pLocal := pName.Substring(VDot + 1);
end;

{ The dataset `Name` of this form or `Module.Name` of a form of the same folder. }
function TDfmRead.LookupTarget(const pForm: TDfmrForm; const pName: string; out pDataset: TDfmrDataset): Boolean;
var
  VForm: TDfmrForm;
  VDataset: TDfmrDataset;
  VName: string;
begin
  pDataset := Default(TDfmrDataset);
  Result := False;
  if OwnerForm(pForm, pName, VForm, VName) then
    for VDataset in VForm.Datasets do
      if SameText(VDataset.Name, VName) then
      begin
        pDataset := VDataset;
        Exit(True);
      end;
end;

{ The column behind a dataset field a lookup names; pBlocked = why it is none of the dataset's table. An unresolved dataset
  states nothing: the name as written. }
function LookupColumn(const pDataset: TDfmrDataset; const pSource: TDatasetSource; const pName: string;
  out pBlocked: string): string;
var
  VTable, VColumn: string;
begin
  pBlocked := '';
  Result := UpperCase(Trim(pName));
  if pSource.TableName = '' then
    Exit;
  if FieldSource(pSource, NamedField(pDataset, pName), VTable, VColumn, pBlocked) and SameText(VTable, pSource.TableName) then
    Exit(VColumn);
  pBlocked := Format('%s is not a column of %s (%s)', [Result, pSource.TableName,
    if pBlocked = '' then 'it comes from ' + VTable else pBlocked]);
end;

procedure TDfmRead.ReadLookup(const pForm: TDfmrForm; const pOwner: TDfmrDataset; const pOwnerSource: TDatasetSource;
  const pField: TDfmrField; pFacts: TFieldFacts; const pSource: string);
var
  VDataset: TDfmrDataset;
  VSource: TDatasetSource;
  VMulti, VBlocked, VTable, VKey, VResult: string;
  VPk: TArray<string>;
begin
  VSource := Default(TDatasetSource);
  if not LookupTarget(pForm, pField.LookupDataSet, VDataset) then
    VSource.Reason := 'not found in the DFMs of this folder'
  else
    VSource := SourceOf(VDataset, FColumns);
  VTable := VSource.TableName;
  VMulti := if pField.KeyFields.Contains(MULTI_FIELD) or pField.LookupKeyFields.Contains(MULTI_FIELD)
    then 'multi-field lookup key' else '';
  if pField.KeyFields <> '' then
  begin
    VKey := LookupColumn(pOwner, pOwnerSource, pField.KeyFields, VBlocked);
    pFacts.Add(COL_SOURCE_KEY, VKey, if VMulti = '' then VBlocked else VMulti, pSource);
  end;
  VKey := LookupColumn(VDataset, VSource, pField.LookupKeyFields, VBlocked);
  if pField.LookupKeyFields <> '' then
    pFacts.Add(COL_DEST_KEY, VKey, if VMulti = '' then VBlocked else VMulti, pSource);
  if pField.LookupResult <> '' then
  begin
    VResult := LookupColumn(VDataset, VSource, pField.LookupResult, VBlocked);
    pFacts.Add(COL_DEST_VALUE, VResult, VBlocked, pSource);
  end;
  if VTable <> '' then
    pFacts.Add(COL_DEST_TABLE, VTable, '', pSource)
  else if pField.LookupDataSet <> '' then
    pFacts.Add(COL_DEST_TABLE, pField.LookupDataSet, 'unresolved lookup dataset ' + pField.LookupDataSet + ': ' + VSource.Reason, pSource)
  else
    FWarnings.Add(pSource + ': lookup field without LookupDataSet');
  if (VTable = '') or (pField.LookupKeyFields = '') then
    Exit;
  VPk := PrimaryKey(FRepo, VTable);
  if (Length(VPk) > 0) and ((Length(VPk) > 1) or (not SameText(VPk[0], VKey))) then
    FWarnings.Add(Format('%s: lookup key %s is not the primary key of %s (%s)', [pSource, pField.LookupKeyFields, VTable,
      string.Join(',', VPk)]));
end;

procedure TDfmRead.WarnForm(const pWhere: string; const pBody: TDfmrBody);
begin
  if (pBody.Blocked = '') and (Length(pBody.FormNames) > 0) then
    FWarnings.Add(pWhere + ': the code names form components: ' + string.Join(', ', pBody.FormNames));
end;

{ The slice of the dataset's OnCalcFields that computes pField; empty when there is no handler or no unit. }
function TDfmRead.CalcBodyOf(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pContext: TDfmrCodeContext;
  const pField: TDfmrField): TDfmrBody;
var
  VUnit: TDfmrUnit;
begin
  Result := Default(TDfmrBody);
  VUnit := UnitOf(pForm.FileName);
  if (pDataset.OnCalcFields <> '') and (VUnit <> nil) then
    Result := VUnit.CalcBody(pContext, pDataset.OnCalcFields, pField.CompName);
end;

procedure TDfmRead.ReadCalc(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pBody: TDfmrBody;
  const pField: TDfmrField; pFacts: TFieldFacts; var pReport: TDfmrDatasetReport);
var
  VUnit: TDfmrUnit;
  VBody: TDfmrBody;
  VWhere: string;
begin
  VWhere := pReport.DfmName + ' ' + pField.CompName;
  VBody := pBody;
  VUnit := UnitOf(pForm.FileName);
  if VBody.Text = '' then
  begin
    Inc(pReport.BodyNone);
    if VBody.Blocked <> '' then
      FWarnings.Add(VWhere + ': no CALC_BODY: ' + VBody.Blocked)
    else if pDataset.OnCalcFields = '' then
      FWarnings.Add(VWhere + ': no CALC_BODY: the dataset has no OnCalcFields')
    else if VUnit <> nil then
      FWarnings.Add(VWhere + ': no CALC_BODY: ' + pDataset.OnCalcFields + ' does not assign it');
    Exit;
  end;
  if VBody.Blocked = '' then
    Inc(pReport.BodyOk)
  else
    Inc(pReport.BodyBlocked);
  pFacts.Add(COL_BODY, VBody.Text, VBody.Blocked, VWhere);
  WarnForm(VWhere, VBody);
end;

{ The code of assigned events (pOwner = component) as facts of the field's event columns. }
{ Join fields the code names that are not of pTable: `OQ (ORDERS)`, `Dbl (no table)`; '' = none. }
function OtherTableFields(const pContext: TDfmrCodeContext; const pUsed: TArray<string>; pOrigins: TOrigins;
  const pTable: string): string;
var
  VUsed: string;
  VCode: TDfmrCodeField;
  VOrigin: TFieldOrigin;
begin
  Result := '';
  for VUsed in pUsed do
  begin
    if not pOrigins.TryGetValue(VUsed, VOrigin) then
      VOrigin := Default(TFieldOrigin);
    if SameText(VOrigin.Table, pTable) then
      Continue;
    for VCode in pContext.Fields do
      if SameText(VCode.CompName, VUsed) then
        Result := Result + (if Result = '' then '' else ', ') + VCode.DataName + ' ('
          + (if VOrigin.Table = '' then 'no table' else VOrigin.Table) + ')';
  end;
end;

procedure TDfmRead.ReadEvents(const pForm: TDfmrForm; const pContext: TDfmrCodeContext; const pEvents: TArray<TDfmrPair>;
  const pOwner: string; pFacts: TFieldFacts; pOrigins: TOrigins);
var
  VEvent: TDfmrPair;
  VColumn: TFrEventColumn;
  VUnit: TDfmrUnit;
  VBody: TDfmrBody;
  VWhere, VOther: string;
begin
  if Length(pEvents) = 0 then
    Exit;
  VUnit := UnitOf(pForm.FileName);
  if VUnit = nil then
    Exit;
  for VEvent in pEvents do
    for VColumn in FR_EVENT_COLUMNS do
      if VColumn.Event = VEvent.Name then
      begin
        VWhere := ExtractFileName(pForm.FileName) + ' ' + pOwner + '.' + VEvent.Name;
        VBody := VUnit.EventBody(pContext, VEvent.Value, VColumn.Params.Split([',']));
        VOther := if (pOrigins = nil) or (VBody.Text = '') then ''
          else OtherTableFields(pContext, VBody.FieldsUsed, pOrigins, pFacts.TableName);
        if VOther <> '' then
          VBody.Blocked := VBody.Blocked + (if VBody.Blocked = '' then '' else '; ')
            + 'the code reads fields of another table: ' + VOther;
        if VBody.Text = '' then
          FWarnings.Add(VWhere + ': not read: ' + (if VBody.Blocked = '' then 'the handler is empty' else VBody.Blocked))
        else
          pFacts.Add(VColumn.Column, VBody.Text, VBody.Blocked, VWhere);
        WarnForm(VWhere, VBody);
      end;
end;

procedure TDfmRead.ReadField(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pOwnerSource: TDatasetSource;
  const pField: TDfmrField; const pTable, pColumn: string);
var
  VFacts: TFieldFacts;
  VPair: TDfmrPair;
  VSource: string;
begin
  VSource := ExtractFileName(pForm.FileName) + ' ' + pField.CompName;
  VFacts := FactsOf(pTable, pColumn);
  VFacts.Add(COL_KIND, IntToStr(FrKindToCode(pField.Kind)), '', VSource);
  for VPair in pField.Stated do
    VFacts.Add(VPair.Name, VPair.Value, '', VSource);
  for VPair in pField.Typed do
    VFacts.Add(VPair.Name, VPair.Value, '', VSource);
  if pField.Kind = frkLookup then
    ReadLookup(pForm, pDataset, pOwnerSource, pField, VFacts, VSource);
  if (pField.Kind = frkAggregate) and (pField.Expression <> '') then
    VFacts.Add(COL_BODY, pField.Expression, '', VSource);
end;

{ The table of a lookup field of a join: the one table of its key fields. }
function LookupOrigin(const pDataset: TDfmrDataset; const pSource: TDatasetSource; const pField: TDfmrField): TFieldOrigin;
var
  VKey, VTable, VColumn, VReason: string;
  VTables: TArray<string>;
begin
  Result := Default(TFieldOrigin);
  VTables := nil;
  if Trim(pField.KeyFields) = '' then
    Result.Why := 'the lookup has no KeyFields';
  for VKey in pField.KeyFields.Split([MULTI_FIELD], TStringSplitOptions.ExcludeEmpty) do
    if not FieldSource(pSource, NamedField(pDataset, VKey), VTable, VColumn, VReason) then
    begin
      Result.Why := Format('the key field %s has no table: %s', [Trim(VKey), VReason]);
      Exit;
    end
    else if not MatchText(VTable, VTables) then
      VTables := VTables + [VTable];
  if Length(VTables) > 1 then
    Result.Why := Format('the key fields come from %d tables: %s', [Length(VTables), string.Join(' ', InFromOrder(pSource, VTables))])
  else if Length(VTables) = 1 then
  begin
    Result.Table := VTables[0];
    Result.Column := UpperCase(Trim(pField.FieldName));
  end;
end;

{ Origins of every field of a join (design 2026-11-26-join-field-origin 2.1-2.3): data fields from the SELECT, lookups from
  their key fields, calc fields from the table fields their code reads, also through other calc fields. pBodies receives
  the calc bodies, keyed like pOrigins. }
procedure TDfmRead.JoinOrigins(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pSource: TDatasetSource;
  const pContext: TDfmrCodeContext; pOrigins: TOrigins; pBodies: TDictionary<string, TDfmrBody>);
var
  VField: TDfmrField;
  VOrigin, VUsedOrigin: TFieldOrigin;
  VBody: TDfmrBody;
  VKey, VUsed, VMissing, VName: string;
  VTables, VCalcs: TArray<string>;
  VI: Integer;
  VNames: TDictionary<string, string>;
  VResults: TOrigins;
  VQueue, VSeveral: TList<string>;
begin
  VNames := TDictionary<string, string>.Create;
  try
    for VField in pDataset.Fields do
    begin
      VKey := LowerCase(VField.CompName);
      VNames.AddOrSetValue(VKey, VField.FieldName);
      VOrigin := Default(TFieldOrigin);
      case VField.Kind of
        frkData:
          if not FieldSource(pSource, VField, VOrigin.Table, VOrigin.Column, VOrigin.Why) then
            VOrigin.Table := '';
        frkLookup:
          VOrigin := LookupOrigin(pDataset, pSource, VField);
        frkCalc, frkInternalCalc:
          begin
            pBodies.AddOrSetValue(VKey, CalcBodyOf(pForm, pDataset, pContext, VField));
            Continue;
          end;
      else
        VOrigin.Why := 'a field of this kind in a join is not placed';
      end;
      pOrigins.AddOrSetValue(VKey, VOrigin);
    end;
    { A calc field gets the tables of the table fields its code reads, directly or through other calc fields of the
      dataset (breadth first; a calc field already visited adds nothing, so a cycle is no error). }
    VResults := TOrigins.Create;
    VQueue := TList<string>.Create;
    VSeveral := TList<string>.Create;
    try
      for VKey in pBodies.Keys do
      begin
        VOrigin := Default(TFieldOrigin);
        VTables := nil;
        VMissing := '';
        VCalcs := nil;
        VQueue.Clear;
        VQueue.Add(VKey);
        VI := 0;
        while VI < VQueue.Count do
        begin
          VBody := pBodies[VQueue[VI]];
          if (VI > 0) and (VBody.Text = '') and (VMissing = '') then
            VMissing := VNames[VQueue[VI]];
          for VUsed in VBody.FieldsUsed do
            if VQueue.Contains(VUsed) then
              Continue
            else if pBodies.ContainsKey(VUsed) then
            begin
              VQueue.Add(VUsed);
              if VI = 0 then
                VCalcs := VCalcs + [VNames[VUsed]];
            end
            else if pOrigins.TryGetValue(VUsed, VUsedOrigin) and (VUsedOrigin.Table <> '') then
            begin
              if not MatchText(VUsedOrigin.Table, VTables) then
                VTables := VTables + [VUsedOrigin.Table];
            end
            else if (VMissing = '') and VNames.TryGetValue(VUsed, VName) then
              VMissing := VName;
          Inc(VI);
        end;
        VBody := pBodies[VKey];
        if (VBody.Text <> '') and (VMissing = '') and (Length(VTables) = 1) then
        begin
          VOrigin.Table := VTables[0];
          VOrigin.Column := UpperCase(Trim(VNames[VKey]));
        end
        else if VBody.Text = '' then
          VOrigin.Why := 'no calc code: ' + (if VBody.Blocked <> '' then VBody.Blocked
            else if pDataset.OnCalcFields = '' then 'the dataset has no OnCalcFields'
            else pDataset.OnCalcFields + ' does not assign it')
        else if VMissing <> '' then
          VOrigin.Why := Format('the calc code reads %s, which has no table', [VMissing])
        else if Length(VTables) > 1 then
        begin
          VOrigin.Why := Format('the calc code reads %d tables: %s', [Length(VTables), string.Join(' ', InFromOrder(pSource, VTables))]);
          VSeveral.Add(VKey);
        end
        else if Length(VCalcs) > 0 then
          VOrigin.Why := 'the calc code reads no table field, only calc fields: ' + string.Join(', ', VCalcs)
        else
          VOrigin.Why := 'the calc code reads no field of the dataset';
        VResults.Add(VKey, VOrigin);
      end;
      for VKey in VResults.Keys do
        pOrigins.AddOrSetValue(VKey, VResults[VKey]);
      PlaceAllSeveral(pForm, pDataset, pSource, pContext, pOrigins, pBodies, VSeveral);
    finally
      VSeveral.Free;
      VQueue.Free;
      VResults.Free;
    end;
  finally
    VNames.Free;
  end;
end;

procedure TDfmRead.ReadDataset(const pForm: TDfmrForm; const pDataset: TDfmrDataset);
var
  VReport: TDfmrDatasetReport;
  VSource, VHome: TDatasetSource;
  VContext: TDfmrCodeContext;
  VField: TDfmrField;
  VRef: TDfmrFieldRef;
  VSqlTable: TDfmrSqlTable;
  VTable, VColumn, VReason: string;
  VFound: Boolean;
  VOrigin: TFieldOrigin;
  VOrigins: TOrigins;
  VBodies: TDictionary<string, TDfmrBody>;
  VBody: TDfmrBody;
begin
  VSource := LinkedSource(pForm, pDataset, [LowerCase(pForm.FileName + '|' + pDataset.Name)], [pDataset.Name]);
  VContext := CodeContext(pForm, pDataset, VSource);
  VReport := Default(TDfmrDatasetReport);
  VReport.DfmName := ExtractFileName(pForm.FileName);
  VReport.Dataset := pDataset.Name;
  VReport.DatasetClass := pDataset.DatasetClass;
  VReport.TableName := VSource.TableName;
  VReport.Via := VSource.Via;
  VReport.LinkKind := VSource.LinkKind;
  VReport.LinkFailed := VSource.Linked and (VSource.Via = '');
  if VSource.IsJoin then
    for VSqlTable in VSource.Sql.Tables do
      if not MatchText(VSqlTable.Name, VReport.JoinTables) then
        VReport.JoinTables := VReport.JoinTables + [VSqlTable.Name];
  if (VSource.TableName = '') and (not VSource.IsJoin) then
    VReport.Unresolved := VSource.Reason + (if pDataset.ObjKind = 'object' then '' else ' (' + pDataset.ObjKind
      + ': its own properties are in the ancestor''s DFM)');
  VOrigins := nil;
  VBodies := nil;
  if VSource.IsJoin then
  begin
    VOrigins := TOrigins.Create;
    VBodies := TDictionary<string, TDfmrBody>.Create;
  end;
  try
    if VSource.IsJoin then
      JoinOrigins(pForm, pDataset, VSource, VContext, VOrigins, VBodies);
    for VField in pDataset.Fields do
    begin
      Inc(VReport.Counts[VField.Kind]);
      VRef := Default(TDfmrFieldRef);
      VRef.FieldName := VField.FieldName;
      VRef.CompName := VField.CompName;
      VRef.FieldClass := VField.FieldClass;
      VRef.Kind := VField.Kind;
      if VSource.IsJoin then
      begin
        VOrigins.TryGetValue(LowerCase(VField.CompName), VOrigin);
        VTable := VOrigin.Table;
        VColumn := VOrigin.Column;
        VReason := VOrigin.Why;
        VFound := VTable <> '';
        if not VFound then
          VReport.NoTable := VReport.NoTable + [MakePair(VField.FieldName, VReason)];
      end
      else
      begin
        VFound := FieldSource(VSource, VField, VTable, VColumn, VReason);
        if (not VFound) and VReason.StartsWith('conflict') then
          FWarnings.Add(Format('%s %s %s: %s', [VReport.DfmName, pDataset.Name, VField.FieldName, VReason]))
        else if (not VFound) and VReason.StartsWith('written in code') then
          FWarnings.Add(Format('%s %s %s: no table: %s', [VReport.DfmName, pDataset.Name, VField.FieldName, VReason]));
      end;
      if VFound then
      begin
        VRef.TableName := VTable;
        VRef.Column := VColumn;
      end;
      VReport.Fields := VReport.Fields + [VRef];
      if VRef.TableName = '' then
      begin
        VReport.Unattributed := VReport.Unattributed + [VField.FieldName];
        Continue;
      end;
      VHome := VSource;
      VHome.TableName := VTable;
      ReadField(pForm, pDataset, VHome, VField, VTable, VColumn);
      if VField.Kind in [frkCalc, frkInternalCalc] then
      begin
        if (VBodies = nil) or (not VBodies.TryGetValue(LowerCase(VField.CompName), VBody)) then
          VBody := CalcBodyOf(pForm, pDataset, VContext, VField);
        ReadCalc(pForm, pDataset, VBody, VField, FactsOf(VTable, VColumn), VReport);
      end;
      ReadEvents(pForm, VContext, VField.Events, VField.CompName, FactsOf(VTable, VColumn), VOrigins);
    end;
  finally
    VBodies.Free;
    VOrigins.Free;
  end;
  if Length(pDataset.InheritedFields) > 0 then
    FWarnings.Add(Format('%s %s: %d inherited fields not read (FieldName is in the ancestor''s DFM): %s', [VReport.DfmName,
      pDataset.Name, Length(pDataset.InheritedFields), string.Join(', ', pDataset.InheritedFields)]));
  FPlan.Datasets := FPlan.Datasets + [VReport];
end;

{ ---- grid views ---- }

procedure TDfmRead.WarnEvents(const pWhere, pWhy: string; const pEvents: TArray<TDfmrPair>);
var
  VEvent: TDfmrPair;
begin
  for VEvent in pEvents do
    FWarnings.Add(Format('%s.%s = %s: not stored (%s)', [pWhere, VEvent.Name, VEvent.Value, pWhy]));
end;

{ The dataset behind the data source of a view. Event code names the fields of a dataset on another form by that form, so
  the context has no fields then. }
function TDfmRead.ViewSource(const pForm: TDfmrForm; const pView: TDfmrGridView): TViewSource;
var
  VName: string;
  VPair: TDfmrPair;
  VOwner: TDfmrForm;
begin
  Result := Default(TViewSource);
  Result.Context.FormClass := pForm.FormClass;
  Result.Context.Components := pForm.Components;
  if (pView.DataSource = '') or not OwnerForm(pForm, pView.DataSource, VOwner, VName) then
    Exit;
  for VPair in VOwner.DataSources do
    if SameText(VPair.Name, VName) and (VPair.Value <> '') then
    begin
      Result.Found := LookupTarget(VOwner, VPair.Value, Result.Dataset);
      Result.Local := SameText(VOwner.FileName, pForm.FileName) and not VPair.Value.Contains('.');
    end;
  if not Result.Found then
    Exit;
  Result.Source := SourceOf(Result.Dataset, FColumns);
  if Result.Local then
    Result.Context := CodeContext(pForm, Result.Dataset, Result.Source);
end;

procedure TDfmRead.ReadColumnEvents(const pForm: TDfmrForm; const pView: TDfmrGridView; const pSource: TViewSource;
  const pColumn: TDfmrGridColumn; const pTable, pField: string);
var
  VWhere: string;
begin
  VWhere := ExtractFileName(pForm.FileName) + ' ' + pColumn.Name;
  if pView.Kind <> dvkTable then
    WarnEvents(VWhere, 'a column event is stored for a TcxGridDBTableView only', pColumn.Events)
  else if pField = '' then
    WarnEvents(VWhere, 'the column has no field', pColumn.Events)
  else if pTable = '' then
    WarnEvents(VWhere, 'the column has no table', pColumn.Events)
  else if Length(pColumn.Events) > 0 then
    ReadEvents(pForm, pSource.Context, pColumn.Events, pColumn.Name, FactsOf(pTable, pField));
end;

procedure TDfmRead.ReadColumn(const pForm: TDfmrForm; const pView: TDfmrGridView; const pSource: TViewSource; pIndex: Integer);
var
  VColumn: TDfmrGridColumn;
  VRow: TGridRow;
  VTable, VField, VReason: string;
begin
  VColumn := pView.Columns[pIndex];
  VTable := '';
  VField := UpperCase(VColumn.FieldName);
  if pSource.Found and (VField <> '')
    and not FieldSource(pSource.Source, NamedField(pSource.Dataset, VColumn.FieldName), VTable, VField, VReason) then
  begin
    VTable := '';
    VField := UpperCase(VColumn.FieldName);
  end;
  VRow.FormName := pForm.FormName;
  VRow.ViewName := pView.Name;
  VRow.ColumnName := VColumn.Name;
  VRow.Values := [MakePair(COL_TABLE, VTable), MakePair(COL_FIELD, VField), MakePair(COL_INDEX, IntToStr(pIndex))];
  if FEditors then
    VRow.Values := VRow.Values + [MakePair(REPO_COL_PROPERTIES_CLASS_NAME, VColumn.PropertiesClassName),
      MakePair(REPO_COL_PROPERTIES, VColumn.Properties)]
  else if (VColumn.PropertiesClassName <> '') or (VColumn.Properties <> '') then
    Inc(FEditorsLeftOut);
  if VColumn.Name = '' then
    FWarnings.Add(Format('%s %s: column %d has no name: not stored', [ExtractFileName(pForm.FileName), pView.Name, pIndex]))
  else if FGridSeen.TryAdd(VRow.Key, True) then
    FGridRows.Add(VRow)
  else
    FWarnings.Add(Format('%s %s.%s: another DFM with the form name %s has this column: not stored', [ExtractFileName(pForm.FileName),
      pView.Name, VColumn.Name, pForm.FormName]));
  ReadColumnEvents(pForm, pView, pSource, VColumn, VTable, VField);
end;

procedure TDfmRead.ReadView(const pForm: TDfmrForm; const pView: TDfmrGridView; const pDataset: string);
var
  VSource: TViewSource;
  VWhere: string;
  VI: Integer;
begin
  VWhere := ExtractFileName(pForm.FileName) + ' ' + pView.Name;
  VSource := ViewSource(pForm, pView);
  if (pDataset <> '') and not (VSource.Local and SameText(VSource.Dataset.Name, pDataset)) then
    Exit;
  if pView.ObjKind <> OBJECT_KIND then
    FWarnings.Add(VWhere + ': inherited grid view not read (its own properties are in the ancestor''s DFM)')
  else if pView.Kind = dvkOther then
    FWarnings.Add(VWhere + ' (' + pView.ViewClass + '): column order not read')
  else
  begin
    if not VSource.Found then
      FWarnings.Add(VWhere + ': the dataset of its data source ' + pView.DataSource + ' is not found: no table for its columns');
    for VI := 0 to High(pView.Columns) do
      ReadColumn(pForm, pView, VSource, VI);
  end;
end;

{ ---- change set ---- }

function TDfmRead.AddChange(pOp: TFrChangeOp; const pFacts: TFieldFacts; const pProp, pOld, pNew: string): Integer;
var
  VChange: TFrChange;
  VItem: TDfmrChangeItem;
begin
  Result := FChanges.Count;
  VChange := Default(TFrChange);
  VChange.Id := Result + 1;
  VChange.Op := pOp;
  VChange.Target := FIELDS_TABLE + ' ' + pFacts.TableName + '|' + pFacts.FieldName;
  VChange.Prop := pProp;
  VChange.OldValue := pOld;
  VChange.NewValue := pNew;
  VChange.Checked := True;
  VItem := Default(TDfmrChangeItem);
  VItem.TableName := pFacts.TableName;
  VItem.FieldName := pFacts.FieldName;
  if pProp <> '' then
    VItem.Columns := [MakePair(pProp, pNew)];
  FChanges.Add(VChange);
  FItems.Add(VItem);
end;

{ One change per value the datasets state for a column: checked when there is one, unchecked alternatives otherwise. }
procedure TDfmRead.PlanColumn(pFacts: TFieldFacts; const pColumn: TFactColumn; const pOld: string);
var
  VValues: TArray<TFactValue>;
  VValue: TFactValue;
  VI: Integer;
begin
  VValues := pColumn.Good;
  if (Length(VValues) = 1) and SameValue(VValues[0].Value, pOld) then
    Exit;
  for VValue in VValues do
  begin
    if SameValue(VValue.Value, pOld) and (VValue.Blocked = '') then
      Continue;
    VI := AddChange(fcoUpdate, pFacts, pColumn.Name, pOld, VValue.Value);
    FChanges.List[VI].Blocked := VValue.Blocked;
    FChanges.List[VI].Checked := (Length(VValues) = 1) and (VValue.Blocked = '');
  end;
  if Length(VValues) > 1 then
    for VValue in VValues do
      FWarnings.Add(Format('%s.%s %s: datasets disagree: %s says %s', [pFacts.TableName, pFacts.FieldName, pColumn.Name,
        VValue.Source, Copy(VValue.Value.Replace(#13#10, ' '), 1, WARN_VALUE_LEN)]));
end;

{ Why a field row the repository does not have cannot be inserted. }
function TDfmRead.NewRowBlock(pFacts: TFieldFacts): string;
var
  VKinds: TArray<TFactValue>;
  VKind: TFactValue;
  VTable: TRepoTable;
  VColumn: TRepoColumn;
begin
  Result := '';
  VKinds := pFacts.Kinds;
  if Length(VKinds) > 1 then
  begin
    Result := 'datasets disagree about the kind:';
    for VKind in VKinds do
      Result := Result + ' ' + VKind.Source + ' = ' + FrKindName(FrKindFromCode(StrToInt(VKind.Value)));
  end
  else if (Length(VKinds) = 1) and (VKinds[0].Value = IntToStr(FrKindToCode(frkData)))
    and FSchemaTables.ContainsKey(UpperCase(pFacts.TableName)) then
    Result := 'not a column of ' + pFacts.TableName + ' in the repository schema facts'
  else if FindRepoTable(FIELDS_TABLE, VTable) and VTable.FindColumn(COL_FIELD, VColumn)
    and ((Length(pFacts.FieldName) > VColumn.MaxLen) or (Length(pFacts.TableName) > VColumn.MaxLen)) then
    Result := 'name too long';
end;

{ Facts without a persistent field: code of a grid column whose field the repository does not have. }
procedure TDfmRead.WarnNoRow(pFacts: TFieldFacts);
var
  VColumn: TFactColumn;
begin
  for VColumn in pFacts.Columns do
    FWarnings.Add(Format('%s.%s %s: not stored: the repository has no row for the field (%s)', [pFacts.TableName, pFacts.FieldName,
      VColumn.Name, VColumn.Values[0].Source]));
end;

{ A new row: the storable agreed values travel with the insert, the rest follows as its own changes. }
procedure TDfmRead.PlanNew(pFacts: TFieldFacts);
var
  VColumn: TFactColumn;
  VValues: TArray<TFactValue>;
  VCols: TArray<TDfmrPair>;
  VPair: TDfmrPair;
  VSummary, VBlock: string;
  VI: Integer;
begin
  if Length(pFacts.Kinds) = 0 then
  begin
    WarnNoRow(pFacts);
    Exit;
  end;
  VCols := nil;
  VSummary := '';
  for VColumn in pFacts.Columns do
  begin
    VValues := VColumn.Good;
    if (Length(VValues) = 1) and (VValues[0].Blocked = '') then
      VCols := VCols + [MakePair(VColumn.Name, VValues[0].Value)];
  end;
  for VPair in VCols do
    VSummary := VSummary + (if VSummary = '' then '' else '; ') + VPair.Name + '=' + VPair.Value;
  VI := AddChange(fcoInsert, pFacts, '', '', VSummary);
  FItems.List[VI].Columns := VCols;
  VBlock := NewRowBlock(pFacts);
  FChanges.List[VI].Blocked := VBlock;
  FChanges.List[VI].Checked := VBlock = '';
  if VBlock <> '' then
    Exit;
  for VColumn in pFacts.Columns do
  begin
    VValues := VColumn.Good;
    if (Length(VValues) > 1) or (VValues[0].Blocked <> '') then
      PlanColumn(pFacts, VColumn, '');
  end;
end;

{ A kind change of an existing row; FIELD_KIND carries ISCALCULATED and ISLOOKUP with it. Returns the kind the row has
  when the checked changes are applied. }
function TDfmRead.PlanKind(pFacts: TFieldFacts; const pRow: TRepoRow; pQuery: TFDQuery): TFrFieldKind;
var
  VKind: TFactValue;
  VNew: TFrFieldKind;
  VI, VCount: Integer;
begin
  Result := pRow.Kind;
  VCount := Length(pFacts.Kinds);
  for VKind in pFacts.Kinds do
  begin
    VNew := FrKindFromCode(StrToInt(VKind.Value));
    if VNew = pRow.Kind then
      Continue;
    VI := AddChange(fcoUpdate, pFacts, COL_KIND, pQuery.FieldByName(COL_KIND).AsString, VKind.Value);
    if pRow.IsColumn and (pRow.Kind = frkData) then
      FChanges.List[VI].Blocked := Format('%s is a real column of %s; %s makes it %s',
        [pFacts.FieldName, pFacts.TableName, VKind.Source, FrKindName(VNew)]);
    FChanges.List[VI].Checked := (VCount = 1) and (VNew <> frkData) and (FChanges.List[VI].Blocked = '');
    if FChanges.List[VI].Checked then
      Result := VNew;
  end;
end;

{ True when a field of a kind has the column: a body or lookup wiring means nothing on a data field. }
function KindHasColumn(pKind: TFrFieldKind; const pColumn: string): Boolean;
begin
  Result := True;
  if pColumn = COL_BODY then
    Result := FrKindHasBody(pKind)
  else if MatchText(pColumn, [COL_SOURCE_KEY, COL_DEST_TABLE, COL_DEST_KEY, COL_DEST_VALUE]) then
    Result := pKind = frkLookup;
end;

procedure TDfmRead.PlanExisting(pFacts: TFieldFacts; const pRow: TRepoRow);
var
  VQuery: TFDQuery;
  VColumn: TFactColumn;
  VKind: TFrFieldKind;
  VI, VFirst: Integer;
begin
  pFacts.TableName := pRow.TableName;
  pFacts.FieldName := pRow.FieldName;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := FRepo;
    VQuery.Open(SQL_FIELD_ROW, [pRow.TableName, pRow.FieldName]);
    VKind := PlanKind(pFacts, pRow, VQuery);
    VFirst := FChanges.Count;
    for VColumn in pFacts.Columns do
      if (VColumn.Name <> COL_KIND) and (not MatchText(VColumn.Name, INSERT_ONLY)) then
        PlanColumn(pFacts, VColumn, VQuery.FieldByName(VColumn.Name).AsString);
    for VI := VFirst to FChanges.Count - 1 do
      FChanges.List[VI].Checked := FChanges.List[VI].Checked and KindHasColumn(VKind, FChanges.List[VI].Prop);
  finally
    VQuery.Free;
  end;
end;

function TDfmRead.AddGridChange(pOp: TFrChangeOp; const pRow: TGridRow; const pProp, pOldValue, pNewValue: string): Integer;
var
  VChange: TFrChange;
  VItem: TDfmrChangeItem;
begin
  Result := FChanges.Count;
  VChange := Default(TFrChange);
  VChange.Id := Result + 1;
  VChange.Op := pOp;
  VChange.Target := REPO_TABLE_GRID_COLUMNS + ' ' + pRow.FormName + '|' + pRow.ViewName + '|' + pRow.ColumnName;
  VChange.Prop := pProp;
  VChange.OldValue := pOldValue;
  VChange.NewValue := pNewValue;
  VChange.Checked := pOp <> fcoDelete;
  VItem := Default(TDfmrChangeItem);
  VItem.FormName := pRow.FormName;
  VItem.ViewName := pRow.ViewName;
  VItem.ColumnName := pRow.ColumnName;
  if pProp <> '' then
    VItem.Columns := [MakePair(pProp, pNewValue)]
  else if pOp = fcoInsert then
    VItem.Columns := pRow.Values;
  FChanges.Add(VChange);
  FItems.Add(VItem);
end;

{ Why a grid row cannot be stored. }
function GridRowBlock(const pRow: TGridRow): string;
var
  VTable: TRepoTable;
  VColumn: TRepoColumn;
  VPair: TDfmrPair;
begin
  Result := '';
  if not FindRepoTable(REPO_TABLE_GRID_COLUMNS, VTable) then
    Exit;
  for VPair in pRow.Values + [MakePair(COL_FORM, pRow.FormName), MakePair(COL_VIEW, pRow.ViewName), MakePair(COL_COLUMN, pRow.ColumnName)] do
    if VTable.FindColumn(VPair.Name, VColumn) and (VColumn.MaxLen > 0) and (Length(VPair.Value) > VColumn.MaxLen) then
      Exit(Format('longer than %s(%d)', [VPair.Name, VColumn.MaxLen]));
end;

{ One read column against its stored row, which is taken out of pOld. }
procedure TDfmRead.PlanGridRow(const pRow: TGridRow; pOld: TDictionary<string, TGridRow>);
var
  VOld: TGridRow;
  VI, VChange: Integer;
  VBlock: string;
begin
  VBlock := GridRowBlock(pRow);
  if not pOld.TryGetValue(pRow.Key, VOld) then
  begin
    VChange := AddGridChange(fcoInsert, pRow, '', '', pRow.Text);
    FChanges.List[VChange].Blocked := VBlock;
    FChanges.List[VChange].Checked := VBlock = '';
    Exit;
  end;
  pOld.Remove(pRow.Key);
  for VI := 0 to High(pRow.Values) do
    if pRow.Values[VI].Value <> VOld.Values[VI].Value then
    begin
      VChange := AddGridChange(fcoUpdate, VOld, pRow.Values[VI].Name, VOld.Values[VI].Value, pRow.Values[VI].Value);
      FChanges.List[VChange].Blocked := VBlock;
      FChanges.List[VChange].Checked := VBlock = '';
    end;
end;

{ The columns of one form; with pDeletes the stored columns the form no longer has. }
procedure TDfmRead.PlanGridForm(const pForm: string; pDeletes: Boolean);
var
  VQuery: TFDQuery;
  VForm, VView, VColumn, VTable, VField, VIndex, VClass, VProps: TField;
  VOld: TDictionary<string, TGridRow>;
  VOrder: TArray<TGridRow>;
  VRow: TGridRow;
begin
  VOld := TDictionary<string, TGridRow>.Create;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := FRepo;
    VQuery.Open(SQL_GRID_FORM, [pForm]);
    VForm := VQuery.FieldByName(COL_FORM);
    VView := VQuery.FieldByName(COL_VIEW);
    VColumn := VQuery.FieldByName(COL_COLUMN);
    VTable := VQuery.FieldByName(COL_TABLE);
    VField := VQuery.FieldByName(COL_FIELD);
    VIndex := VQuery.FieldByName(COL_INDEX);
    VClass := if FEditors then VQuery.FieldByName(REPO_COL_PROPERTIES_CLASS_NAME) else nil;
    VProps := if FEditors then VQuery.FieldByName(REPO_COL_PROPERTIES) else nil;
    VOrder := nil;
    while not VQuery.Eof do
    begin
      VRow.FormName := VForm.AsString;
      VRow.ViewName := VView.AsString;
      VRow.ColumnName := VColumn.AsString;
      VRow.Values := [MakePair(COL_TABLE, VTable.AsString), MakePair(COL_FIELD, VField.AsString), MakePair(COL_INDEX, VIndex.AsString)];
      if FEditors then
        VRow.Values := VRow.Values + [MakePair(REPO_COL_PROPERTIES_CLASS_NAME, VClass.AsString),
          MakePair(REPO_COL_PROPERTIES, VProps.AsString)];
      VOld.AddOrSetValue(VRow.Key, VRow);
      VOrder := VOrder + [VRow];
      VQuery.Next;
    end;
    for VRow in FGridRows do
      if SameText(VRow.FormName, pForm) then
        PlanGridRow(VRow, VOld);
    if pDeletes then
      for VRow in VOrder do
        if VOld.ContainsKey(VRow.Key) then
          AddGridChange(fcoDelete, VRow, '', VRow.Text, '');
  finally
    VQuery.Free;
    VOld.Free;
  end;
end;

procedure TDfmRead.PlanAll(const pFiles: TArray<string>; pDeletes: Boolean);
var
  VFacts: TFieldFacts;
  VRow: TRepoRow;
  VFile: string;
  VForms: TArray<string>;
begin
  for VFacts in FOrder do
    if FRows.TryGetValue(KeyOf(VFacts.TableName, VFacts.FieldName), VRow) then
      PlanExisting(VFacts, VRow)
    else
      PlanNew(VFacts);
  VForms := nil;
  for VFile in pFiles do
    if not MatchText(Form(VFile).FormName, VForms) then
    begin
      VForms := VForms + [Form(VFile).FormName];
      PlanGridForm(Form(VFile).FormName, pDeletes);
    end;
  PlanRelations;
  PlanInputs;
end;

function TDfmRead.AddRowChange(pOp: TFrChangeOp; const pTable, pKey, pProp, pOld, pNew: string;  // dl:ok too-many-parameters@e000 -- REVIEWED 2026-11-26 XTABLE X3: private: one change = op, table, key, prop, old, new, columns, checked, as TFrChange and TDfmrChangeItem hold them
  const pColumns: TArray<TDfmrPair>; pChecked: Boolean): Integer;
var
  VChange: TFrChange;
  VItem: TDfmrChangeItem;
begin
  Result := FChanges.Count;
  VChange := Default(TFrChange);
  VChange.Id := Result + 1;
  VChange.Op := pOp;
  VChange.Target := pTable + ' ' + pKey;
  VChange.Prop := pProp;
  VChange.OldValue := pOld;
  VChange.NewValue := pNew;
  VChange.Checked := pChecked;
  VItem := Default(TDfmrChangeItem);
  VItem.RowTable := pTable;
  VItem.Columns := pColumns;
  FChanges.Add(VChange);
  FItems.Add(VItem);
end;

{ A placed field whose input goes through an offered FORM relation is stored only together with that relation and the
  input: its own changes are unchecked too (otherwise repo check finds an undeclared alias). }
procedure TDfmRead.UncheckOffered;
var
  VI: Integer;
  VWhy: string;
begin
  for VI := 0 to FItems.Count - 1 do
    if (FItems[VI].RowTable = '') and (FItems[VI].FormName = '') and FChanges[VI].Checked
      and FUnchecked.TryGetValue(KeyOf(FItems[VI].TableName, FItems[VI].FieldName), VWhy) then
    begin
      FChanges.List[VI].Checked := False;
      FWarnings.Add(Format('%s.%s: unchecked: %s', [FItems[VI].TableName, FItems[VI].FieldName, VWhy]));
    end;
end;

{ The DL_RELATIONS rows the planned inputs need (design 2.3: an FK step gets its row when a binding first uses it;
  checked) and every offered FORM relation (XQ6: unchecked, confirmed once by choosing it). }
procedure TDfmRead.PlanRelations;
var
  VInput: TPlannedInput;
  VStep: TFrRelation;
  VNeeded: TList<TFrRelation>;
  VSeen, VFk: TDictionary<string, Boolean>;
  VCols, VSub: TArray<TDfmrPair>;
  VPairs, VText: string;
  VI, VId: Integer;
begin
  VNeeded := TList<TFrRelation>.Create;
  VSeen := TDictionary<string, Boolean>.Create;
  VFk := TDictionary<string, Boolean>.Create;
  try
    for VInput in FInputs do
      for VStep in VInput.Steps do
      begin
        if SameText(VStep.Source, REPO_RELATION_FK) then
          VFk.AddOrSetValue(UpperCase(VStep.Name), True);
        if (not MatchText(VStep.Name, FStoredRelations)) and VSeen.TryAdd(UpperCase(VStep.Name), True) then
          VNeeded.Add(VStep);
      end;
    for VStep in FOfferOrder do
      if VSeen.TryAdd(UpperCase(VStep.Name), True) then
        VNeeded.Add(VStep);
    FCross.FkUsed := VFk.Count;
    FCross.Offered := FOfferOrder.Count;
    for VStep in VNeeded do
    begin
      VPairs := '';
      VSub := nil;
      for VI := 0 to High(VStep.ChildColumns) do
      begin
        VPairs := VPairs + (if VI = 0 then '' else ',') + VStep.ChildColumns[VI] + '=' + VStep.ParentColumns[VI];
        VSub := VSub + [MakePair(VStep.ChildColumns[VI], VStep.ParentColumns[VI])];
      end;
      VCols := [MakePair(COL_RELATION, VStep.Name), MakePair('CHILD_TABLE', VStep.ChildTable),
        MakePair('PARENT_TABLE', VStep.ParentTable), MakePair('SOURCE', VStep.Source),
        MakePair('CONSTRAINT_NAME', VStep.ConstraintName), MakePair('PARENT_KEY', VStep.ParentKey),
        MakePair(COL_IS_DEFAULT, BOOL_FALSE)];
      VText := VStep.ChildTable + ' > ' + VStep.ParentTable + '; SOURCE=' + VStep.Source +
        (if VStep.ConstraintName = '' then '' else '; CONSTRAINT_NAME=' + VStep.ConstraintName) +
        '; PARENT_KEY=' + VStep.ParentKey + '; IS_DEFAULT=' + BOOL_FALSE + '; COLUMNS=' + VPairs;
      VId := AddRowChange(fcoInsert, REPO_TABLE_RELATIONS, VStep.Name, '', '', VText, VCols,
        SameText(VStep.Source, REPO_RELATION_FK));
      FItems.List[VId].SubColumns := VSub;
    end;
  finally
    VFk.Free;
    VSeen.Free;
    VNeeded.Free;
  end;
end;

{ One DL_FIELD_INPUTS change per (table, field, alias) of the default binding whose path is new or changed: an
  insert is checked unless its path goes through an offered relation; a changed path, and datasets that disagree,
  are unchecked alternatives. }
procedure TDfmRead.PlanInputs;
var
  VKeys: TList<string>;
  VByKey: TObjectDictionary<string, TList<TPlannedInput>>;
  VList: TList<TPlannedInput>;
  VInput, VOther: TPlannedInput;
  VKey, VOld, VKeyText: string;
  VStored, VOffered, VSeen: Boolean;
  VStep: TFrRelation;
  VCols: TArray<TDfmrPair>;
begin
  VKeys := TList<string>.Create;
  VByKey := TObjectDictionary<string, TList<TPlannedInput>>.Create([doOwnsValues]);
  try
    for VInput in FInputs do
    begin
      VKey := InputKey(VInput.TableName, VInput.FieldName, VInput.Alias);
      if not VByKey.TryGetValue(VKey, VList) then
      begin
        VList := TList<TPlannedInput>.Create;
        VByKey.Add(VKey, VList);
        VKeys.Add(VKey);
      end;
      VSeen := False;
      for VOther in VList do
        VSeen := VSeen or SameText(VOther.Path, VInput.Path);
      if not VSeen then
        VList.Add(VInput);
    end;
    FCross.Inputs := VKeys.Count;
    for VKey in VKeys do
    begin
      VList := VByKey[VKey];
      VStored := FStoredInputs.TryGetValue(VKey, VOld);
      if (VList.Count = 1) and VStored and SameText(VOld, VList[0].Path) then
        Continue;
      for VInput in VList do
      begin
        VOffered := False;
        for VStep in VInput.Steps do
          VOffered := VOffered or FOffers.ContainsKey(UpperCase(VStep.Name));
        VKeyText := VInput.TableName + '|' + VInput.FieldName + '||' + VInput.Alias;
        VCols := [MakePair(COL_TABLE, VInput.TableName), MakePair(COL_FIELD, VInput.FieldName), MakePair(COL_BINDING, ''),
          MakePair(COL_ALIAS, VInput.Alias), MakePair(COL_PATH, VInput.Path), MakePair('TARGET_TABLE', VInput.Target)];
        if VStored then
          AddRowChange(fcoUpdate, REPO_TABLE_FIELD_INPUTS, VKeyText, COL_PATH, VOld, VInput.Path, VCols, False)
        else
          AddRowChange(fcoInsert, REPO_TABLE_FIELD_INPUTS, VKeyText, '', '', Format('PATH=%s; TARGET_TABLE=%s (rule %s)',
            [VInput.Path, VInput.Target, VInput.Rule]), VCols, (VList.Count = 1) and not VOffered);
        if VList.Count > 1 then
          FWarnings.Add(Format('%s.%s input %s: datasets disagree: %s says %s', [VInput.TableName, VInput.FieldName,
            VInput.Alias, VInput.Source, VInput.Path]));
      end;
    end;
  finally
    VByKey.Free;
    VKeys.Free;
  end;
end;

function TDfmRead.Execute(const pFiles: TArray<string>; const pDataset: string): TDfmrPlan;
var
  VFile: string;
  VForm: TDfmrForm;
  VDataset: TDfmrDataset;
  VView: TDfmrGridView;
begin
  FPlan := Default(TDfmrPlan);
  FPlan.ChangeSet.Direction := fdDfmToRepo;
  LoadRows;
  LoadCrossTable;
  for VFile in pFiles do
  begin
    VForm := Form(VFile);
    for VDataset in VForm.Datasets do
      if (pDataset = '') or SameText(pDataset, VDataset.Name) then
        ReadDataset(VForm, VDataset);
    for VView in VForm.Views do
      ReadView(VForm, VView, pDataset);
    FUnits.Clear;
  end;
  if FEditorsLeftOut > 0 then
    FWarnings.Add(Format('the repository is schema %d: the editor properties of %d grid columns are not read (run repo migrate --apply)',
      [RepoSchemaVersion(FRepo), FEditorsLeftOut]));
  if (pDataset <> '') and (Length(FPlan.Datasets) = 0) then
    raise EDfmReadError.CreateFmt('no dataset %s in the DFM', [pDataset]);
  PlanAll(pFiles, pDataset = '');
  UncheckOffered;
  FPlan.ChangeSet.Changes := FChanges.ToArray;
  FPlan.Items := FItems.ToArray;
  FPlan.Warnings := FWarnings.ToStringArray;
  FPlan.CrossTable := FCross;
  Result := FPlan;
end;

function PlanDfmRead(pRepo: TFDConnection; const pFiles: TArray<string>; const pDataset: string): TDfmrPlan;
var
  VRead: TDfmRead;
begin
  if RepoSchemaVersion(pRepo) < SCHEMA_WITH_INPUTS then
    raise ERepoError.CreateFmt('the repository is schema %d: run repo migrate first', [RepoSchemaVersion(pRepo)]);
  VRead := TDfmRead.Create(pRepo);
  try
    Result := VRead.Execute(pFiles, pDataset);
  finally
    VRead.Free;
  end;
end;

function TableFieldsOf(pRepo: TFDConnection; const pTable: string): TArray<TFrSelectionField>;
var
  VQuery: TFDQuery;
  VName, VKind, VKey, VBody: TField;
  VItem: TFrSelectionField;
begin
  Result := nil;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_TABLE_FIELDS, [pTable]);
    VName := VQuery.FieldByName(COL_FIELD);
    VKind := VQuery.FieldByName(COL_KIND);
    VKey := VQuery.FieldByName(COL_SOURCE_KEY);
    VBody := VQuery.FieldByName(COL_BODY);
    while not VQuery.Eof do
    begin
      VItem.Name := VName.AsString;
      VItem.Kind := if FrKindCodeKnown(VKind.Value) then FrKindFromCode(VKind.Value) else frkData;
      VItem.SourceKey := VKey.AsString;
      VItem.Body := VBody.AsString;
      Result := Result + [VItem];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ ---- apply ---- }

procedure SetColumn(pQuery: TFDQuery; const pName, pValue: string);
begin
  if pValue = '' then
    pQuery.FieldByName(pName).Clear
  else
    pQuery.FieldByName(pName).AsString := pValue;
end;

procedure SetKind(pQuery: TFDQuery; pKind: TFrFieldKind);
begin
  pQuery.FieldByName(COL_IS_CALC).AsBoolean := pKind in [frkCalc, frkInternalCalc];
  pQuery.FieldByName(COL_IS_LOOKUP).AsBoolean := pKind = frkLookup;
end;

procedure WriteColumns(pQuery: TFDQuery; const pItem: TDfmrChangeItem);
var
  VPair: TDfmrPair;
begin
  for VPair in pItem.Columns do
  begin
    SetColumn(pQuery, VPair.Name, VPair.Value);
    if VPair.Name = COL_KIND then
      SetKind(pQuery, FrKindFromCode(StrToInt(VPair.Value)));
  end;
end;

procedure ApplyField(pQuery: TFDQuery; const pChange: TFrChange; const pItem: TDfmrChangeItem);
begin
  pQuery.Open(SQL_FIELD_ROW, [pItem.TableName, pItem.FieldName]);  // dl:ok dataset-open-without-close@70c8 -- REVIEWED 2026-11-23 TT-DFMREAD: the caller ApplyDfmRead owns the query: closes it per change and on an exception, frees it in finally
  if (pChange.Op = fcoInsert) <> pQuery.Eof then
    raise ERepoError.CreateFmt('change %d: the row of %s %s', [pChange.Id, pChange.Target,
      if pQuery.Eof then 'does not exist (select its insert too)' else 'already exists']);
  if pChange.Op = fcoInsert then
  begin
    pQuery.Append;
    pQuery.FieldByName(COL_TABLE).AsString := pItem.TableName;
    pQuery.FieldByName(COL_FIELD).AsString := pItem.FieldName;
    pQuery.FieldByName(COL_VISIBLE).AsBoolean := True; // TField.Visible defaults to True
  end
  else
    pQuery.Edit;
  WriteColumns(pQuery, pItem);
  pQuery.Post;
end;

procedure ApplyGrid(pQuery: TFDQuery; const pChange: TFrChange; const pItem: TDfmrChangeItem);
begin
  pQuery.Open(SQL_GRID_ROW, [pItem.FormName, pItem.ViewName, pItem.ColumnName]);  // dl:ok dataset-open-without-close@5642 -- REVIEWED 2026-11-23 EVCOLS: the caller ApplyDfmRead owns the query: closes it per change and on an exception, frees it in finally
  if (pChange.Op = fcoInsert) <> pQuery.Eof then
    raise ERepoError.CreateFmt('change %d: the row of %s %s', [pChange.Id, pChange.Target,
      if pQuery.Eof then 'does not exist' else 'already exists']);
  if pChange.Op = fcoDelete then
  begin
    pQuery.Delete;
    Exit;
  end;
  if pChange.Op = fcoInsert then
  begin
    pQuery.Append;
    pQuery.FieldByName(COL_FORM).AsString := pItem.FormName;
    pQuery.FieldByName(COL_VIEW).AsString := pItem.ViewName;
    pQuery.FieldByName(COL_COLUMN).AsString := pItem.ColumnName;
  end
  else
    pQuery.Edit;
  WriteColumns(pQuery, pItem);
  pQuery.Post;
end;

procedure ApplyRelation(pQuery: TFDQuery; const pChange: TFrChange; const pItem: TDfmrChangeItem);
var
  VPair: TDfmrPair;
  VName: string;
  VI: Integer;
  VRel, VPos, VChild, VParent: TField;
begin
  VName := pItem.Columns[0].Value;
  pQuery.Open(SQL_RELATION_ROW, [VName]);  // dl:ok dataset-open-without-close@85d7 -- REVIEWED 2026-11-26 XTABLE X3: the caller ApplyDfmRead owns the query: closes it per change and on an exception, frees it in finally
  if not pQuery.Eof then
    raise ERepoError.CreateFmt('change %d: the row of %s already exists', [pChange.Id, pChange.Target]);
  pQuery.Append;
  for VPair in pItem.Columns do
    if VPair.Name = COL_IS_DEFAULT then
      pQuery.FieldByName(VPair.Name).AsBoolean := SameText(VPair.Value, 'True')
    else
      SetColumn(pQuery, VPair.Name, VPair.Value);
  pQuery.Post;
  pQuery.Close;
  pQuery.Open(SQL_RELATION_COLUMNS, [VName]);
  VRel := pQuery.FieldByName(COL_RELATION);
  VPos := pQuery.FieldByName('POSITION');
  VChild := pQuery.FieldByName('CHILD_COLUMN');
  VParent := pQuery.FieldByName('PARENT_COLUMN');
  for VI := 0 to High(pItem.SubColumns) do
  begin
    pQuery.Append;
    VRel.AsString := VName;
    VPos.AsInteger := VI + 1;
    VChild.AsString := pItem.SubColumns[VI].Name;
    VParent.AsString := pItem.SubColumns[VI].Value;
    pQuery.Post;
  end;
end;

function ItemValue(const pItem: TDfmrChangeItem; const pName: string): string;
var
  VPair: TDfmrPair;
begin
  Result := '';
  for VPair in pItem.Columns do
    if VPair.Name = pName then
      Exit(VPair.Value);
end;

{ A DL_FIELD_INPUTS row; its field row and every relation of its PATH must be in the repository by then. }
procedure ApplyInput(pQuery: TFDQuery; const pChange: TFrChange; const pItem: TDfmrChangeItem);
var
  VPair: TDfmrPair;
  VStep, VTable, VField: string;
begin
  VTable := ItemValue(pItem, COL_TABLE);
  VField := ItemValue(pItem, COL_FIELD);
  pQuery.Open(SQL_FIELD_ROW, [VTable, VField]);  // dl:ok dataset-open-without-close@16d4 -- REVIEWED 2026-11-26 XTABLE X3: the caller ApplyDfmRead owns the query: closes it per change and on an exception, frees it in finally
  if pQuery.Eof then
    raise ERepoError.CreateFmt('change %d: %s needs the row DL_FIELDS_INFO %s|%s (select its insert too)',
      [pChange.Id, pChange.Target, VTable, VField]);
  pQuery.Close;
  for VStep in SplitInputPath(ItemValue(pItem, COL_PATH)) do
  begin
    pQuery.Open(SQL_RELATION_ROW, [VStep]);  // dl:ok query-in-loop@1321 -- REVIEWED 2026-11-26 loop runs over the few steps of one relation path
    if pQuery.Eof then
      raise ERepoError.CreateFmt('change %d: %s needs the relation %s in DL_RELATIONS (select its insert too)',
        [pChange.Id, pChange.Target, VStep]);
    pQuery.Close;
  end;
  pQuery.Open(SQL_INPUT_ROW, [VTable, VField, ItemValue(pItem, COL_BINDING), ItemValue(pItem, COL_ALIAS)]);
  if (pChange.Op = fcoInsert) <> pQuery.Eof then
    raise ERepoError.CreateFmt('change %d: the row of %s %s', [pChange.Id, pChange.Target,
      if pQuery.Eof then 'does not exist' else 'already exists']);
  if pChange.Op = fcoInsert then
    pQuery.Append
  else
    pQuery.Edit;
  for VPair in pItem.Columns do
    pQuery.FieldByName(VPair.Name).AsString := VPair.Value; // BINDING '' is the default binding, not NULL
  pQuery.Post;
end;

{ Refuses a blocked change and two changes of one value. }
procedure CheckChosen(const pChosen: TArray<TFrChange>);
var
  VChange: TFrChange;
  VSeen: TDictionary<string, Integer>;
begin
  VSeen := TDictionary<string, Integer>.Create;
  try
    for VChange in pChosen do
    begin
      if VChange.Blocked <> '' then
        raise ERepoError.CreateFmt('change %d is blocked: %s', [VChange.Id, VChange.Blocked]);
      if not VSeen.TryAdd(VChange.Target + ' ' + VChange.Prop, VChange.Id) then
        raise ERepoError.CreateFmt('changes %d and %d set the same value (%s %s): select one',
          [VSeen[VChange.Target + ' ' + VChange.Prop], VChange.Id, VChange.Target, VChange.Prop]);
    end;
  finally
    VSeen.Free;
  end;
end;

function ApplyDfmRead(pRepo: TFDConnection; const pPlan: TDfmrPlan; const pChosen: TArray<TFrChange>): TArray<string>;
var
  VChange: TFrChange;
  VQuery: TFDQuery;
begin
  Result := nil;
  CheckChosen(pChosen);
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.UpdateOptions.CheckRequired := False; // a NOT NULL column that is not set takes its SQL default
    pRepo.StartTransaction;
    try
      for VChange in pChosen do
      begin
        if pPlan.Items[VChange.Id - 1].RowTable = REPO_TABLE_RELATIONS then
          ApplyRelation(VQuery, VChange, pPlan.Items[VChange.Id - 1])
        else if pPlan.Items[VChange.Id - 1].RowTable = REPO_TABLE_FIELD_INPUTS then
          ApplyInput(VQuery, VChange, pPlan.Items[VChange.Id - 1])
        else if pPlan.Items[VChange.Id - 1].FormName = '' then
          ApplyField(VQuery, VChange, pPlan.Items[VChange.Id - 1])
        else
          ApplyGrid(VQuery, VChange, pPlan.Items[VChange.Id - 1]);
        VQuery.Close;
        Result := Result + [ApplyLogLine(VChange)];
      end;
      pRepo.Commit;
    except
      VQuery.Close;
      pRepo.Rollback;
      raise;
    end;
  finally
    VQuery.Free;
  end;
end;

end.
