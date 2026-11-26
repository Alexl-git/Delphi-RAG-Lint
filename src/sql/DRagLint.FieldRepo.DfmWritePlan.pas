unit DRagLint.FieldRepo.DfmWritePlan;  // dl:ok unit-too-large@fa17 -- REVIEWED 2026-11-26 DFMWRITE2: planner and applier of one change set share private helpers; the split is the god-class design change already deferred (INT-W2)

{ drag-lint 1.54 -- lane TT-DFMWRITE: the repository -> DFM change set of a form and its applier (design
  2026-11-22-field-repository-v2-design.md sections 3, 4.4 and 9).

  The datasets and persistent fields come from the read side (DfmRead); a field's table column is found by the same
  rules as DfmReadPlan (UpdateTableName, TableName, the SELECT). Property changes: the repository wins; a value the
  repository does not hold changes nothing. Fields are added and removed only for an explicit selection of one
  dataset, and then in the unit too (the published field is what lets Delphi find the class when the form loads).
  Calc code is never written here. A field event the repository holds and the form lacks gets a new handler (1.55, Q1 A),
  and the grid and layout items bound to a removed field are removed with it (Q3(2)). A graphical row whose column the
  form lacks becomes a TcxGridDBColumn with its GRID_* handlers, unchecked (Q3(1)). }

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DfmReadPlan,
  DRagLint.FieldRepo.DfmWrite;

type
  /// <summary>Raised for a selection that cannot be planned: no dataset, an unresolved one, an unknown field.</summary>
  EDfmWriteSelection = class(EDfmWriteError);

  /// <summary>What repo write-dfm may do to a BDE dataset (TTable, TQuery, TStoredProc, TBDE*): the project setting
  /// fieldrepo.bde.</summary>
  /// <remarks>dbpFull: the same as any other dataset (the default). dbpReadOnly: no field insert, no new event handler,
  /// no grid or layout item removal. dbpNone: the project allows no BDE at all; the same three are refused.</remarks>
  TDfmwBdePolicy = (dbpFull, dbpReadOnly, dbpNone);

  /// <summary>What a change does to the DFM text.</summary>
  TDfmwAction = (dwaSet, dwaRemove, dwaKind, dwaInsert, dwaDelete, dwaEvent);

  /// <summary>One change; parallel to the change set.</summary>
  TDfmwItem = record
    /// <summary>Index in Files.</summary>
    FileIndex: Integer;
    /// <summary>What to do.</summary>
    Action: TDfmwAction;
    /// <summary>Dataset and field component names; a grid column (Q3(1)) and its handlers: the grid view and the column.</summary>
    Dataset: string;
    Component: string;
    /// <summary>dwaDelete: FieldName of the removed field; dwaEvent: FieldName of the field the handler is for; a grid
    /// column: FIELD_NAME of its graphical row.</summary>
    FieldName: string;
    /// <summary>Class of the field (its declaration in the unit, the order of its properties).</summary>
    FieldClass: string;
    /// <summary>dwaSet, dwaRemove: the property; dwaSet: its DFM literal.</summary>
    PropName: string;
    Literal: string;
    /// <summary>dwaKind: the new kind.</summary>
    Kind: TFrFieldKind;
    /// <summary>dwaInsert: the block's lines.</summary>
    Block: TArray<string>;
    /// <summary>Component names of the dataset's fields (where a new one goes).</summary>
    Siblings: TArray<string>;
    /// <summary>Ids of changes that must be applied with this one.</summary>
    Requires: TArray<Integer>;
    /// <summary>dwaEvent: parameter list of the new handler (PropName = the event, Literal = the handler name).</summary>
    MethodParams: string;
    /// <summary>dwaEvent: the lines between begin and end of the new handler (a DLFR region), CRLF.</summary>
    MethodBody: string;
  end;

  /// <summary>A form to write: the bytes the plan was made from.</summary>
  TDfmwFile = record
    /// <summary>Path of the DFM and its bytes.</summary>
    DfmName: string;
    DfmBytes: TBytes;
    /// <summary>Path of the unit beside it ('' = none) and its bytes.</summary>
    PasName: string;
    PasBytes: TBytes;
    /// <summary>Class of the root object.</summary>
    FormClass: string;
  end;

  /// <summary>A planned write.</summary>
  TDfmwPlan = record
    /// <summary>Direction repo-to-dfm.</summary>
    ChangeSet: TFrChangeSet;
    /// <summary>Items[i] belongs to ChangeSet.Changes[i].</summary>
    Items: TArray<TDfmwItem>;
    /// <summary>The forms.</summary>
    Files: TArray<TDfmwFile>;
    /// <summary>One report per dataset, in DFM order.</summary>
    Datasets: TArray<TDfmrDatasetReport>;
    /// <summary>Everything the repository holds that is not written, and every fact to look at.</summary>
    Warnings: TArray<string>;
    /// <summary>Hash of the bytes of every DFM and unit that was read, of the repository's fields, domains and
    /// constraints, and of the change list: two plans with one id mean the same by every change id.</summary>
    PlanId: string;
  end;

/// <summary>Plans the changes that bring DFMs in line with the repository.</summary>
/// <param name="pRepo">Open repository connection, schema 2; only SELECTs run.</param>
/// <param name="pFiles">Text DFM files.</param>
/// <param name="pDataset">Dataset component name (case-insensitive); '' = every dataset of every file.</param>
/// <param name="pFields">Field selection of the one dataset: FIELD_NAMEs or `all`; nil = no field is added or
/// removed. ExpandSelection adds what the selected fields depend on.</param>
/// <returns>The plan. Checked: property changes and added fields. Unchecked: removed fields, the grid and layout items bound
/// to a removed field (the field's removal Requires them), new field-event handlers for code the repository holds (one of an
/// added field Requires its insert), a new TcxGridDBColumn for a graphical row whose column the form lacks and its
/// OnGetDisplayText / OnCustomDrawCell handlers (each Requires the column; the column goes where DL_GRID_COLUMNS puts it,
/// else into the only TcxGridDBTableView of the dataset), hidden fields, changed kinds and the first persistent fields of a dataset. Blocked: everything that cannot be written so that the form still loads, a
/// lookup whose current dataset has no known table, and a removed field that the form or its unit names.</returns>
/// <exception cref="EDfmWriteError">A binary DFM, or one that Delphi or the readers do not understand.</exception>
/// <exception cref="EDfmWriteSelection">pFields without exactly one dataset with a table.</exception>
/// <exception cref="EDfmReadError">A file or the dataset does not exist.</exception>
/// <exception cref="ERepoError">The repository is schema 1 (run repo migrate first).</exception>
/// <remarks>Ids are 1-based in plan order: the same DFMs and repository always give the same ids and the same PlanId. A
/// file given twice is planned once. A file that is open in the IDE is read from disk. An unknown field in pFields ends in
/// the EFrSelectionError of ExpandSelection. pBde (the project's fieldrepo.bde) blocks, on a BDE dataset only, the field
/// inserts, new event handlers and grid / layout item removals: `BDE dataset: read only (project policy)` or
/// `BDE not allowed in this project`.</remarks>
function PlanDfmWrite(pRepo: TFDConnection; const pFiles: TArray<string>; const pDataset: string;
  const pFields: TArray<string>; pBde: TDfmwBdePolicy = dbpFull): TDfmwPlan;

/// <summary>The policy a fieldrepo.bde value names.</summary>
/// <param name="pText">`full`, `readonly` or `none` (case-insensitive); '' = full.</param>
/// <returns>The policy.</returns>
/// <exception cref="EDfmWriteError">Any other value; the message names the key and the three values.</exception>
function BdePolicyOf(const pText: string): TDfmwBdePolicy;

/// <summary>Applies chosen changes to the plan's bytes in memory.</summary>
/// <param name="pPlan">The plan.</param>
/// <param name="pChosen">Changes to apply.</param>
/// <returns>Only the files whose bytes change. Every new DFM was converted to binary by the RTL and read again.</returns>
/// <exception cref="EDfmWriteError">A chosen change is blocked, or the result does not read back as planned.</exception>
/// <exception cref="EDfmWriteSelection">A chosen change needs one that was not chosen, or names a field that another one
/// deletes.</exception>
/// <remarks>No file is read or written: the applier for an open designer uses this too.</remarks>
function RenderDfmWrite(const pPlan: TDfmwPlan; const pChosen: TArray<TFrChange>): TArray<TDfmwOutput>;  // dl:ok unused-public-symbol@ad3b -- REVIEWED 2026-11-23 DFMWFIX: the in-memory half for the open designer (plan 1.54 lane TT-OTA)

/// <summary>Writes chosen changes, with a backup of every changed file beside it.</summary>
/// <param name="pPlan">The plan.</param>
/// <param name="pChosen">Changes to apply.</param>
/// <returns>One `replacing OLD with NEW` line per change, then one `backup FILE` line per changed file.</returns>
/// <exception cref="EDfmWriteError">As RenderDfmWrite; a file changed since the plan; a file cannot be written (the
/// files written before it are restored).</exception>
/// <remarks>Everything is computed and checked before the first byte is written. Backup name:
/// `FILE.before-write-dfm-yyyymmdd-hhnnss`, never an existing file. A file is replaced by a complete new one, never
/// written in place.</remarks>
function ApplyDfmWrite(const pPlan: TDfmwPlan; const pChosen: TArray<TFrChange>): TArray<string>;

/// <summary>The TField class a repository field gets in a new persistent field.</summary>
/// <param name="pFieldType">FIELD_TYPE (RDB$FIELD_TYPE), 0 = not a column.</param>
/// <param name="pSubType">FIELD_SUBTYPE.</param>
/// <param name="pScale">FIELD_SCALE (zero or negative).</param>
/// <param name="pAsType">FIELD_AS_TYPE, used when there is no FIELD_TYPE.</param>
/// <param name="pVarType">VAR_TYPE, tells a memo from a string.</param>
/// <returns>A class name, '' = unknown.</returns>
/// <remarks>String classes are the narrow ones; the planner widens them to match the dataset.</remarks>
function FieldClassForRow(pFieldType, pSubType, pScale: Integer; const pAsType, pVarType: string): string;  // dl:ok unused-public-symbol@7924 -- REVIEWED 2026-11-23 DFMWFIX: tests/fieldrepo/DfmWriteTests.dpr calls it; outside this project index

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.Hash,
  System.TypInfo,
  System.RegularExpressions,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.SchemaFacts,
  DRagLint.FieldRepo.DfmRead,
  DRagLint.FieldRepo.DfmReadSql,
  DRagLint.FieldRepo.DfmReadSelection,
  DRagLint.FieldRepo.Handlers;

const
  SCHEMA_WITH_BODIES = 2;
  ALL_FIELDS = 'all';
  MULTI_FIELD = ';';
  DFM_EXT = '.dfm';
  PAS_EXT = '.pas';
  OBJECT_KIND = 'object';
  UNIT_DB = 'Data.DB';
  UNIT_OLD_DB = 'DB';
  PROP_LABEL = 'DisplayLabel';
  PLAN_ID_LENGTH = 16; // hex digits
  PROP_FIELD_NAME = 'FieldName';
  PROP_BINDING = 'DataBinding.FieldName'; // a grid column, card row, layout item or tree-list column
  PROP_DATASOURCE = 'DataController.DataSource';
  CX_PREFIX = 'Tcx';
  EVENT_PREFIX = 'On';
  EVENT_GET_TEXT = 'OnGetText';
  EVENT_SET_TEXT = 'OnSetText';
  EVENT_GET_DISPLAY_TEXT = 'OnGetDisplayText';
  PROP_CAPTION = 'Caption';
  CLASS_GRID_COLUMN = 'TcxGridDBColumn';
  { units a new grid column and its handlers are declared with }
  UNIT_CX_DB_TABLE = 'cxGridDBTableView';
  UNIT_CX_TABLE = 'cxGridCustomTableView';
  UNIT_CX_GRAPHICS = 'cxGraphics';
  SCHEMA_WITH_GRID = 3; // DL_GRID_COLUMNS
  SQL_GRID_PLACES = 'SELECT "VIEW_NAME", "COLUMN_NAME", "COLUMN_INDEX" FROM "DL_GRID_COLUMNS" WHERE UPPER("FORM_NAME") = UPPER(:F) ' +
    'AND UPPER("TABLE_NAME") = UPPER(:T) AND UPPER("FIELD_NAME") = UPPER(:N) ORDER BY "VIEW_NAME", "COLUMN_INDEX", "COLUMN_NAME"';
  { strings that are read by people or declare columns, not by-name bindings }
  UNBOUND_PROPS: array[0..4] of string = ('Caption', 'Hint', PROP_LABEL, 'Lines', 'FieldDefs');
  { tables the plan is made from }
  PLAN_TABLES: array[0..3] of string = ('DL_FIELDS_INFO', 'DL_DOMAINS', 'DL_CONSTRAINTS', 'DL_CONSTRAINT_COLUMNS');
  PROP_FORMAT = 'DisplayFormat';
  PROP_EDIT_FORMAT = 'EditFormat';
  PROP_WIDTH = 'DisplayWidth';
  PROP_VISIBLE = 'Visible';
  PROP_ALIGNMENT = 'Alignment';
  PROP_SIZE = 'Size';
  PROP_KIND = 'FieldKind';
  PROP_CALCULATED = 'Calculated'; // streamed by TField.DefineProperties for fkCalculated
  PROP_LOOKUP_DATASET = 'LookupDataSet';
  CLASS_STRING = 'TStringField';
  CLASS_WIDE_STRING = 'TWideStringField';
  CLASS_MEMO = 'TMemoField';
  CLASS_WIDE_MEMO = 'TWideMemoField';
  CLASS_AGGREGATE = 'TAggregateField';
  CLASS_BCD = 'TBCDField';
  CLASS_FMTBCD = 'TFMTBCDField';
  DEFAULT_STRING_SIZE = 20; // TStringField.Size
  MAX_BCD_SCALE = 4; // FireDAC maps more decimals to TFMTBCDField
  UNICODE_CHARSETS: array[0..1] of string = ('UTF8', 'UNICODE_FSS');
  BDE_CLASSES: array[0..2] of string = ('TTable', 'TQuery', 'TStoredProc');
  BDE_CLASS_PREFIX = 'TBDE';
  BDE_POLICY_NAMES: array[TDfmwBdePolicy] of string = ('full', 'readonly', 'none');
  BDE_POLICY_REASONS: array[TDfmwBdePolicy] of string = ('', 'BDE dataset: read only (project policy)',
    'BDE not allowed in this project');
  MAX_ALIGNMENT = Ord(High(TAlignment));
  KIND_NAMES: array[TFrFieldKind] of string = ('fkData', 'fkCalculated', 'fkLookup', 'fkInternalCalc', 'fkAggregate', '');
  SQL_ROWS = 'SELECT F.*, D."CHARSET" AS "DOMAIN_CHARSET" FROM "DL_FIELDS_INFO" F LEFT JOIN "DL_DOMAINS" D ' +
    'ON D."DOMAIN_NAME" = F."DOMAIN_NAME" ORDER BY F."TABLE_NAME", F."FIELD_NAME"';

  FB_SHORT = 7;
  FB_LONG = 8;
  FB_FLOAT = 10;
  FB_DATE = 12;
  FB_TIME = 13;
  FB_CHAR = 14;
  FB_INT64 = 16;
  FB_BOOLEAN = 23;
  FB_DEC16 = 24;
  FB_DEC34 = 25;
  FB_INT128 = 26;
  FB_DOUBLE = 27;
  FB_TIME_TZ = 28;
  FB_TIMESTAMP_TZ = 29;
  FB_TIMESTAMP = 35;
  FB_VARCHAR = 37;
  FB_BLOB = 261;
  SUBTYPE_TEXT_BLOB = 1;
  SUBTYPE_OCTETS = 1;

  { Every class a new field can get, and every class whose properties and defaults are known from the class itself. }
  KNOWN_CLASSES: array[0..32] of TFieldClass = (TIntegerField, TSmallintField, TShortintField, TByteField, TWordField,
    TAutoIncField, TLongWordField, TLargeintField, TFloatField, TCurrencyField, TSingleField, TExtendedField, TBCDField,
    TFMTBCDField, TStringField, TWideStringField, TGuidField, TMemoField, TWideMemoField, TBooleanField, TDateField,
    TTimeField, TDateTimeField, TSQLTimeStampField, TSQLTimeStampOffsetField, TBlobField, TGraphicField, TBinaryField,
    TBytesField, TVarBytesField, TVariantField, TAggregateField, TFDAutoIncField);

  { FIELD_AS_TYPE -> class, for a field that is not a column. }
  ACCESSOR_CLASSES: array[0..11] of array[0..1] of string = (('AsInteger', 'TIntegerField'), ('AsLongWord', 'TLongWordField'),
    ('AsLargeInt', 'TLargeintField'), ('AsFloat', 'TFloatField'), ('AsSingle', 'TSingleField'),
    ('AsExtended', 'TExtendedField'), ('AsCurrency', CLASS_BCD), ('AsBCD', CLASS_FMTBCD), ('AsBoolean', 'TBooleanField'),
    ('AsDateTime', 'TDateTimeField'), ('AsSQLTimeStamp', 'TSQLTimeStampField'),
    ('AsSQLTimeStampOffset', 'TSQLTimeStampOffsetField'));

type
  TRepoField = record
    TableName: string;
    FieldName: string;
    Kind: TFrFieldKind;
    KindKnown: Boolean;
    FieldType: Integer;
    SubType: Integer;
    Scale: Integer;
    Charset: string;
    AsType: string;
    VarType: string;
    StringSize: Integer;
    DisplayLabel: string;
    DisplayFormat: string;
    EditFormat: string;
    DisplayWidth: Integer;
    HasVisible: Boolean;
    Visible: Boolean;
    Alignment: Integer; // -1 = none
    SourceKey: string;
    DestTable: string;
    DestKey: string;
    DestValue: string;
    Body: string;
    Events: TArray<string>; // per FR_EVENT_COLUMNS: the stored body, '' = none
  end;

  { Where a dataset's fields come from (the rules of DfmReadPlan). }
  TSource = record
    TableName: string;
    Sql: TDfmrSqlSource;
    HasSql: Boolean;
    Reason: string;
  end;

  { A field that is or will be in the dataset. }
  TPlannedField = record
    Column: string;
    Name: string;
    ChangeId: Integer; // 0 = already there
  end;

  { Where a new grid column goes (Q3(1)). }
  TGridPlace = record
    View: TDfmrGridView;
    Column: string;
    Index: Integer; // -1 = after the last column
  end;

  { A lookup's dataset. }
  TLookupTarget = record
    RefName: string; // as the DFM names it: `tblTools`, `dmMain.tblTools`, `Frame1.tblTools`
    Refusal: string; // it holds only some rows of its table: no target at all; '' = no reason
    Doubt: string; // why it is no new target and why changes of a lookup that has it are unchecked; '' = none
    InFrame: Boolean; // no new target; an existing lookup into it stays
    Dataset: TDfmrDataset;
    Source: TSource;
  end;

  TDfmWritePlanner = class  // dl:ok god-class@e649, high-response@e649 -- REVIEWED 2026-11-24 INT-W2: one planner over one plan; splitting it is a design change for a later release
  strict private
    FRepo: TFDConnection;
    FBde: TDfmwBdePolicy;
    FPlan: TDfmwPlan;
    FRows: TDictionary<string, TRepoField>;
    FOrder: TList<TRepoField>;
    FSamples: TObjectDictionary<string, TField>;
    FWarnings: TStringList;
    FChanges: TList<TFrChange>;
    FItems: TList<TDfmwItem>;
    { the form being planned }
    FFileIndex: Integer;
    FForm: TDfmrForm;
    FDoc: TDfmDocument;
    FUnit: TDfmUnitDocument;
    { the dataset being planned }
    FDataset: TDfmrDataset;
    FSource: TSource;
    FPlanned: TList<TPlannedField>;
    FNewNames: TStringList;
    FModuleTargets: TArray<TLookupTarget>;
    FModulesRead: Boolean;
    FReads: TStringList; // file=hash of everything read from disk
    FGridTable: Boolean; // the repository has DL_GRID_COLUMNS
    procedure LoadRows;
    procedure NoteRead(const pFile: string; const pBytes: TBytes);
    function PlanId: string;
    procedure OpenForm(const pFile: string);
    procedure CloseForm;
    procedure CheckReaders;
    function Sample(const pClass: string): TField;
    function Where(const pField: TDfmrField): string;
    procedure PlanDataset(const pFields: TArray<string>);
    procedure Report;
    procedure TryPlanField(const pField: TDfmrField; const pRow: TRepoField);
    procedure PlanField(const pField: TDfmrField; const pRow: TRepoField);
    procedure PlanText(const pField: TDfmrField; const pProp, pDefault, pWant: string);
    procedure PlanValue(const pField: TDfmrField; const pProp, pDefault, pWant: string; pRemovable: Boolean);
    procedure PlanWidthAndSize(const pField: TDfmrField; const pRow: TRepoField);
    procedure PlanVisible(const pField: TDfmrField; const pRow: TRepoField);
    procedure PlanKind(const pField: TDfmrField; const pRow: TRepoField);
    procedure PlanLookup(const pField: TDfmrField; const pRow: TRepoField);
    procedure PlanWiring(const pField: TDfmrField; const pRow: TRepoField);
    procedure JoinWiring(pFirst: Integer);
    procedure UncheckDoubted(pFirst: Integer; const pField: TDfmrField; const pRow: TRepoField);
    procedure PlanSelection(const pFields: TArray<string>);
    procedure PlanInsert(const pRow: TRepoField);
    procedure UncheckFirstFields(pFirst: Integer);
    procedure PlanDelete(const pField: TDfmrField);
    function Stated(const pField: TDfmrField; const pProp: string; out pText: string): Boolean;
    function IsOwn(const pField: TDfmrField): Boolean;
    function AddItem(const pItem: TDfmwItem; pOp: TFrChangeOp; const pOld, pNew: string): Integer;
    procedure Block(pIndex: Integer; const pReason: string);
    function NewItem(pAction: TDfmwAction; const pComponent, pClass: string): TDfmwItem;
    procedure SetItem(const pField: TDfmrField; const pProp, pOld, pNew, pLiteral, pBlocked: string);
    function ColumnOf(const pDataset: TDfmrDataset; const pSource: TSource; const pName: string): string;
    function NameOf(const pDataset: TDfmrDataset; const pSource: TSource; const pColumn: string; out pBlocked: string): string;
    function PlannedName(const pColumn: string; out pId: Integer): string;
    function TryCurrentTarget(const pName: string; out pTarget: TLookupTarget): Boolean;
    function TargetOfLookup(const pField: TDfmrField; const pRow: TRepoField; out pTarget: TLookupTarget): string;
    function TargetsOf(const pTable: string): TArray<TLookupTarget>;
    procedure AddModule(const pFile: string);
    function ModuleTargets: TArray<TLookupTarget>;
    function LookupNamesReason(const pRow: TRepoField; const pTarget: TLookupTarget; pField: TField): string;
    function LookupBlock(const pRow: TRepoField; pField: TField; out pRequires: TArray<Integer>): string;
    function InsertBlockReason(const pRow: TRepoField; const pClass: string): string;
    function ClassOfRow(const pRow: TRepoField): string;
    function SizeOfRow(const pRow: TRepoField): Integer;
    function NewComponentName(const pField: string): string;
    function DeleteBlockReason(const pField: TDfmrField; const pItems: TArray<string>): string;
    function ItemDeleteReason(const pName: string): string;
    function BoundItems(const pFieldName: string): TArray<Integer>;
    function HandlerFields: TArray<TFrhField>;
    procedure PlanEvents(const pComponent, pFieldClass: string; const pHandlers: TArray<TDfmrPair>; const pRow: TRepoField;
      const pRequires: TArray<Integer>);
    procedure TryEvent(const pItem: TDfmwItem);
    function HandlerClash(pIndex: Integer): string;
    function BdeBlockReason: string;
    function MissingUnit(const pUnits: TArray<string>): string;
    function GridViewsOf: TArray<TDfmrGridView>;
    function GridPlaces(const pRow: TRepoField; const pViews: TArray<TDfmrGridView>): TArray<TGridPlace>;
    procedure PlanColumnEvents(const pColumn: TDfmwItem; const pRow: TRepoField; pColumnId: Integer);
    procedure PlanGridColumn(const pRow: TRepoField; const pPlace: TGridPlace);
    procedure PlanGridColumns;
  public
    constructor Create(pRepo: TFDConnection; pBde: TDfmwBdePolicy);
    destructor Destroy; override;
    function Execute(const pFiles: TArray<string>; const pDataset: string; const pFields: TArray<string>): TDfmwPlan;
  end;

function KeyOf(const pTable, pField: string): string;
begin
  Result := UpperCase(pTable) + '|' + UpperCase(pField);
end;

{ ---- field classes ---- }

function FindClassByName(const pName: string): TFieldClass;
var
  VClass: TFieldClass;
begin
  Result := nil;
  for VClass in KNOWN_CLASSES do
    if SameText(VClass.ClassName, pName) then
      Exit(VClass);
end;

function ExactNumericClass(const pPlain: string; pScale: Integer): string;
begin
  Result := if pScale = 0 then pPlain else if -pScale > MAX_BCD_SCALE then CLASS_FMTBCD else CLASS_BCD;
end;

{ The class of a column; '' = unknown type code. }
function ClassOfColumn(pFieldType, pSubType, pScale: Integer): string;
begin
  case pFieldType of
    FB_SHORT: Result := ExactNumericClass('TSmallintField', pScale);
    FB_LONG: Result := ExactNumericClass('TIntegerField', pScale);
    FB_INT64: Result := ExactNumericClass('TLargeintField', pScale);
    FB_FLOAT: Result := 'TSingleField';
    FB_DOUBLE: Result := 'TFloatField';
    FB_DATE: Result := 'TDateField';
    FB_TIME: Result := 'TTimeField';
    FB_TIMESTAMP: Result := 'TSQLTimeStampField';
    FB_TIME_TZ, FB_TIMESTAMP_TZ: Result := 'TSQLTimeStampOffsetField';
    FB_BOOLEAN: Result := 'TBooleanField';
    FB_DEC16, FB_DEC34, FB_INT128: Result := CLASS_FMTBCD;
    FB_CHAR: Result := if pSubType = SUBTYPE_OCTETS then 'TBytesField' else CLASS_STRING;
    FB_VARCHAR: Result := if pSubType = SUBTYPE_OCTETS then 'TVarBytesField' else CLASS_STRING;
    FB_BLOB: Result := if pSubType = SUBTYPE_TEXT_BLOB then CLASS_MEMO else 'TBlobField';
  else
    Result := '';
  end;
end;

function FieldClassForRow(pFieldType, pSubType, pScale: Integer; const pAsType, pVarType: string): string;
var
  VI: Integer;
begin
  if pFieldType <> 0 then
    Exit(ClassOfColumn(pFieldType, pSubType, pScale));
  if SameText(pAsType, 'AsString') then
    Exit(if SameText(pVarType, 'TStringList') then CLASS_MEMO else CLASS_STRING);
  Result := '';
  for VI := 0 to High(ACCESSOR_CLASSES) do
    if SameText(ACCESSOR_CLASSES[VI][0], pAsType) then
      Result := ACCESSOR_CLASSES[VI][1];
end;
{ True when the class is known and publishes the property. }
function HasProp(const pClass, pProp: string): Boolean;
var
  VClass: TFieldClass;
begin
  VClass := FindClassByName(pClass);
  Result := (VClass <> nil) and IsPublishedProp(VClass, pProp);
end;

{ Published properties of a TField class in streaming order. }
function StreamOrder(const pClass: string): TArray<string>;
var
  VClass: TFieldClass;
  VList: PPropList;
  VCount, VI: Integer;
begin
  Result := nil;
  VClass := FindClassByName(pClass);
  if VClass = nil then
    VClass := TField;
  VCount := GetPropList(PTypeInfo(VClass.ClassInfo), VList);
  if VCount > 0 then
    try
      for VI := 0 to VCount - 1 do
        Result := Result + [GetPropName(VList^[VI])];
    finally
      FreeMem(VList);
    end;
end;

{ ---- sources (the rules of DfmReadPlan.SourceOf / FieldSource) ---- }

function SourceOf(const pDataset: TDfmrDataset): TSource;  // dl:ok duplicate-code@9fe4 -- REVIEWED 2026-11-24 INT-W2: twin of the read planner: same walk, other target
begin
  Result := Default(TSource);
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
    Result.Reason := Format('the SQL reads %d tables', [Length(Result.Sql.Tables)]);
end;

{ The table and column of a persistent field; False = the DFM does not state it. }
function FieldSource(const pSource: TSource; const pField: TDfmrField; out pTable, pColumn: string): Boolean;
var
  VReason: string;
begin
  pTable := pSource.TableName;
  pColumn := UpperCase(Trim(pField.FieldName));
  if (pField.Kind = frkData) and pSource.HasSql and (pSource.Sql.Reason = '') then
    Exit(SqlFieldColumn(pSource.Sql, pField.FieldName, pField.Origin, pTable, pColumn, VReason));
  Result := pTable <> '';
end;

{ The name a column has in the dataset; '' = the SELECT does not return it. }
function ResultName(const pSource: TSource; const pColumn: string): string;
var
  VItem: TDfmrSqlItem;
  VTable, VColumn, VReason: string;
begin
  if not pSource.HasSql then
    Exit(pColumn);
  Result := '';
  if pSource.Sql.Reason <> '' then
    Exit;
  for VItem in pSource.Sql.Items do
    if VItem.Plain and (VItem.OutName <> '') and SqlFieldColumn(pSource.Sql, VItem.OutName, '', VTable, VColumn, VReason)
      and SameText(VTable, pSource.TableName) and SameText(VColumn, pColumn) then
      Exit(VItem.OutName);
  if SqlFieldColumn(pSource.Sql, pColumn, '', VTable, VColumn, VReason) and SameText(VTable, pSource.TableName)
    and SameText(VColumn, pColumn) then
    Result := pColumn;
end;

{ ---- items ---- }

procedure ApplyKind(pDoc: TDfmDocument; pObject: Integer; const pItem: TDfmwItem);
var
  VOrder: TArray<string>;
begin
  VOrder := StreamOrder(pItem.FieldClass);
  if pItem.Kind = frkData then
    pDoc.RemoveProp(pObject, PROP_KIND)
  else
    pDoc.SetProp(pObject, PROP_KIND, KIND_NAMES[pItem.Kind], VOrder);
  if pItem.Kind = frkCalc then
    pDoc.SetProp(pObject, PROP_CALCULATED, 'True', VOrder)
  else
    pDoc.RemoveProp(pObject, PROP_CALCULATED);
end;

{ Records one change; pUnit may be nil when no field is added or removed. }
procedure ApplyItem(pDoc: TDfmDocument; pUnit: TDfmUnitDocument; const pFormClass: string; const pItem: TDfmwItem);
var
  VObject: Integer;
begin
  VObject := if pItem.Action = dwaInsert then pDoc.FindObject(pItem.Dataset, '') else pDoc.FindObject(pItem.Component, pItem.Dataset);
  if VObject < 0 then
    raise EDfmWriteError.CreateFmt('%s.%s is not in the DFM', [pItem.Dataset, pItem.Component]);
  if pItem.Action = dwaInsert then
  begin
    pDoc.InsertChild(VObject, pItem.Block, pItem.Siblings);
    pUnit.AddField(pFormClass, pItem.Component, pItem.FieldClass, pItem.Siblings + [pItem.Dataset]);
    Exit;
  end;
  case pItem.Action of
    dwaSet: pDoc.SetProp(VObject, pItem.PropName, pItem.Literal, StreamOrder(pItem.FieldClass));
    dwaRemove: pDoc.RemoveProp(VObject, pItem.PropName);
    dwaKind: ApplyKind(pDoc, VObject, pItem);
    dwaEvent:
      begin
        pDoc.SetProp(VObject, pItem.PropName, pItem.Literal, StreamOrder(pItem.FieldClass));
        pUnit.AddMethod(pFormClass, pItem.Literal, pItem.MethodParams, pItem.MethodBody);
      end;
  else
    pDoc.RemoveObject(VObject);
    pUnit.RemoveField(pFormClass, pItem.Component);
  end;
end;

{ The new bytes of a form and its unit. Events go in a second pass over the bytes of the first, so that a new field gets
  its event and a handler is declared after every new field. Result: the unit changes. }
function RenderBytes(const pFile: TDfmwFile; const pItems: TArray<TDfmwItem>; out pDfm, pPas: TBytes): Boolean;
var
  VDoc: TDfmDocument;
  VUnit: TDfmUnitDocument;
  VItem: TDfmwItem;
  VEvents: Boolean;
begin
  Result := False;
  pDfm := pFile.DfmBytes;
  pPas := pFile.PasBytes;
  for VEvents := False to True do
  begin
    if VEvents and not Result then
      Break;
    VUnit := nil;
    VDoc := TDfmDocument.Create(pDfm, ExtractFileName(pFile.DfmName));
    try
      if pFile.PasName <> '' then
        VUnit := TDfmUnitDocument.Create(pPas, ExtractFileName(pFile.PasName));
      for VItem in pItems do
        if (VItem.Action = dwaEvent) = VEvents then
          ApplyItem(VDoc, VUnit, pFile.FormClass, VItem);
      pDfm := VDoc.Output;
      if VUnit <> nil then
        pPas := VUnit.Output;
    finally
      VUnit.Free;
      VDoc.Free;
    end;
    for VItem in pItems do
      Result := Result or (VItem.Action in [dwaInsert, dwaDelete, dwaEvent]);
  end;
end;

{ TDfmWritePlanner }

constructor TDfmWritePlanner.Create(pRepo: TFDConnection; pBde: TDfmwBdePolicy);
begin
  inherited Create;
  FRepo := pRepo;
  FBde := pBde;
  FRows := TDictionary<string, TRepoField>.Create;
  FOrder := TList<TRepoField>.Create;
  FSamples := TObjectDictionary<string, TField>.Create([doOwnsValues]);
  FWarnings := TStringList.Create(dupIgnore, False, False);
  FChanges := TList<TFrChange>.Create;
  FItems := TList<TDfmwItem>.Create;
  FPlanned := TList<TPlannedField>.Create;
  FNewNames := TStringList.Create;
  FReads := TStringList.Create(dupIgnore, True, False);
end;

function BdePolicyOf(const pText: string): TDfmwBdePolicy;
var
  VPolicy: TDfmwBdePolicy;
begin
  if Trim(pText) = '' then
    Exit(dbpFull);
  for VPolicy := Low(TDfmwBdePolicy) to High(TDfmwBdePolicy) do
    if SameText(Trim(pText), BDE_POLICY_NAMES[VPolicy]) then
      Exit(VPolicy);
  raise EDfmWriteError.CreateFmt('project setting fieldrepo.bde: %s is not full, readonly or none', [QuotedStr(pText)]);
end;

{ THE BDE check (owner 2026-11-26): '' unless the dataset being planned is a BDE one and the project's fieldrepo.bde
  is not full. Every BDE refusal of the planner asks here, so that a later opt-in changes one place. }
function TDfmWritePlanner.BdeBlockReason: string;
begin
  Result := '';
  if MatchText(FDataset.DatasetClass, BDE_CLASSES) or StartsText(BDE_CLASS_PREFIX, FDataset.DatasetClass) then
    Result := BDE_POLICY_REASONS[FBde];
end;

destructor TDfmWritePlanner.Destroy;
begin
  CloseForm;
  FReads.Free;
  FNewNames.Free;
  FPlanned.Free;
  FItems.Free;
  FChanges.Free;
  FWarnings.Free;
  FSamples.Free;
  FOrder.Free;
  FRows.Free;
  inherited;
end;

{ A column row nobody edited: the DB -> repository read writes VISIBLE False into every new row, which says nothing. }
function IsNewRow(const pRow: TRepoField): Boolean;
begin
  Result := (pRow.Kind = frkData) and (pRow.DisplayLabel + pRow.DisplayFormat + pRow.EditFormat = '')
    and (pRow.DisplayWidth = 0) and (pRow.Alignment < 0);
end;

function ReadRow(pQuery: TFDQuery): TRepoField;
begin
  Result := Default(TRepoField);
  Result.TableName := pQuery.FieldByName('TABLE_NAME').AsString;
  Result.FieldName := pQuery.FieldByName('FIELD_NAME').AsString;
  Result.KindKnown := FrKindCodeKnown(pQuery.FieldByName('FIELD_KIND').Value);
  if Result.KindKnown then
    Result.Kind := FrKindFromCode(pQuery.FieldByName('FIELD_KIND').Value);
  Result.FieldType := pQuery.FieldByName('FIELD_TYPE').AsInteger;
  Result.SubType := pQuery.FieldByName('FIELD_SUBTYPE').AsInteger;
  Result.Scale := pQuery.FieldByName('FIELD_SCALE').AsInteger;
  Result.Charset := Trim(pQuery.FieldByName('DOMAIN_CHARSET').AsString);
  Result.AsType := pQuery.FieldByName('FIELD_AS_TYPE').AsString;
  Result.VarType := pQuery.FieldByName('VAR_TYPE').AsString;
  Result.StringSize := pQuery.FieldByName('STRING_SIZE').AsInteger;
  Result.DisplayLabel := pQuery.FieldByName('DISPLAY_LABEL').AsString;
  Result.DisplayFormat := pQuery.FieldByName('DISPLAY_FORMAT').AsString;
  Result.EditFormat := pQuery.FieldByName('EDIT_FORMAT').AsString;
  Result.DisplayWidth := pQuery.FieldByName('DISPLAY_WIDTH').AsInteger;
  Result.Visible := pQuery.FieldByName('VISIBLE').AsBoolean;
  Result.Alignment := if pQuery.FieldByName('ALIGNMENT').IsNull then -1 else pQuery.FieldByName('ALIGNMENT').AsInteger;
  Result.HasVisible := (not pQuery.FieldByName('VISIBLE').IsNull) and (Result.Visible or not IsNewRow(Result));
  Result.SourceKey := pQuery.FieldByName('SOURCEKEY').AsString;
  Result.DestTable := pQuery.FieldByName('DESTTABLE').AsString;
  Result.DestKey := pQuery.FieldByName('DESTKEY').AsString;
  Result.DestValue := pQuery.FieldByName('DESTVALUE').AsString;
  Result.Body := pQuery.FieldByName('CALC_BODY').AsString;
  SetLength(Result.Events, Length(FR_EVENT_COLUMNS));
  for var VI := 0 to High(FR_EVENT_COLUMNS) do
  begin
    var VBody := pQuery.FindField(FR_EVENT_COLUMNS[VI].Column);
    if VBody <> nil then
      Result.Events[VI] := VBody.AsString;
  end;
end;

procedure TDfmWritePlanner.LoadRows;
var
  VQuery: TFDQuery;
  VRow: TRepoField;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := FRepo;
    VQuery.Open(SQL_ROWS);
    while not VQuery.Eof do
    begin
      VRow := ReadRow(VQuery);
      FRows.AddOrSetValue(KeyOf(VRow.TableName, VRow.FieldName), VRow);
      FOrder.Add(VRow);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure TDfmWritePlanner.NoteRead(const pFile: string; const pBytes: TBytes);
var
  VHash: THashSHA2;
begin
  VHash := THashSHA2.Create;  // dl:ok object-leak@1695 -- REVIEWED 2026-11-23 DFMWFIX: THashSHA2 is a record
  VHash.Update(pBytes);
  FReads.Add(LowerCase(pFile) + '=' + VHash.HashAsString);
end;

{ Every value of a table, in row order. }
function TableText(pRepo: TFDConnection; const pTable: string): string;
var
  VQuery: TFDQuery;
  VText: TStringBuilder;
  VI: Integer;
begin
  VText := TStringBuilder.Create(pTable);
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open('SELECT * FROM ' + QuoteRepoIdent(pTable) + ' ORDER BY 1, 2');  // dl:ok path-traversal@1c5d -- REVIEWED 2026-11-23 DFMWFIX: SQL text, not a path: a constant table name through QuoteRepoIdent
    while not VQuery.Eof do
    begin
      VText.AppendLine;
      for VI := 0 to VQuery.FieldCount - 1 do
        VText.Append(if VQuery.Fields[VI].IsNull then '-' else '=' + VQuery.Fields[VI].AsString).Append(#9);
      VQuery.Next;
    end;
    Result := VText.ToString;
  finally
    VQuery.Free;
    VText.Free;
  end;
end;

function TDfmWritePlanner.PlanId: string;
var
  VText, VTable: string;
begin
  VText := FReads.Text;
  for VTable in PLAN_TABLES do
    VText := VText + THashSHA2.GetHashString(TableText(FRepo, VTable)) + #10;
  if FGridTable then
    VText := VText + THashSHA2.GetHashString(TableText(FRepo, REPO_TABLE_GRID_COLUMNS)) + #10;
  Result := THashSHA2.GetHashString(VText + RenderChangeSetJson(FPlan.ChangeSet)).Substring(0, PLAN_ID_LENGTH);
end;

{ An instance of the class: its defaults and its published properties; nil = class not linked. }
function TDfmWritePlanner.Sample(const pClass: string): TField;
var
  VClass: TFieldClass;
begin
  if FSamples.TryGetValue(LowerCase(pClass), Result) then
    Exit;
  VClass := FindClassByName(pClass);
  Result := nil;
  if VClass <> nil then
    Result := VClass.Create(nil);
  FSamples.Add(LowerCase(pClass), Result);
end;

procedure TDfmWritePlanner.CloseForm;
begin
  FreeAndNil(FUnit);
  FreeAndNil(FDoc);
end;

{ The byte-level reader and the reader of the index must see the same components. }
procedure TDfmWritePlanner.CheckReaders;
var
  VI: Integer;
  VName: string;
begin
  if Length(FForm.Diagnostics) > 0 then
    raise EDfmWriteError.Create(ExtractFileName(FForm.FileName) + ': ' + FForm.Diagnostics[0]);
  if Length(FDoc.Objects) <> Length(FForm.Components) + 1 then
    raise EDfmWriteError.CreateFmt('%s: the two DFM readers disagree (%d and %d components)',
      [ExtractFileName(FForm.FileName), Length(FDoc.Objects) - 1, Length(FForm.Components)]);
  for VI := 0 to High(FForm.Components) do
  begin
    VName := FDoc.Objects[VI + 1].Name;
    if VName = '' then
      VName := FDoc.Objects[VI + 1].ObjClass; // `object TOvcTabPage`: the index names it by its class
    if not SameText(FForm.Components[VI], VName) then
      raise EDfmWriteError.CreateFmt('%s: the two DFM readers disagree (%s and %s)', [ExtractFileName(FForm.FileName), VName,
        FForm.Components[VI]]);
  end;
end;

procedure TDfmWritePlanner.OpenForm(const pFile: string);
var
  VFile: TDfmwFile;
  VPas: string;
begin
  CloseForm;
  VFile := Default(TDfmwFile);
  VFile.DfmName := TPath.GetFullPath(pFile);
  if not TFile.Exists(VFile.DfmName) then
    raise EDfmReadError.CreateFmt('the DFM does not exist: %s', [pFile]);
  VFile.DfmBytes := TFile.ReadAllBytes(VFile.DfmName);
  NoteRead(VFile.DfmName, VFile.DfmBytes);
  FDoc := TDfmDocument.Create(VFile.DfmBytes, ExtractFileName(VFile.DfmName));
  FForm := LoadDfmForm(VFile.DfmName);
  CheckReaders;
  VFile.FormClass := FForm.FormClass;
  VPas := ChangeFileExt(VFile.DfmName, PAS_EXT);
  if TFile.Exists(VPas) then
  begin
    VFile.PasName := VPas;
    VFile.PasBytes := TFile.ReadAllBytes(VPas);
    NoteRead(VPas, VFile.PasBytes);
    FUnit := TDfmUnitDocument.Create(VFile.PasBytes, ExtractFileName(VPas));
  end;
  FFileIndex := Length(FPlan.Files);
  FPlan.Files := FPlan.Files + [VFile];
  FNewNames.Clear;
  FModuleTargets := nil;
  FModulesRead := False;
end;

function TDfmWritePlanner.Where(const pField: TDfmrField): string;
begin
  Result := ExtractFileName(FForm.FileName) + ' ' + pField.CompName;
end;

function TDfmWritePlanner.Stated(const pField: TDfmrField; const pProp: string; out pText: string): Boolean;
begin
  Result := FDoc.TryProp(FDoc.FindObject(pField.CompName, FDataset.Name), pProp, pText);
end;

{ True for a field this DFM declares; an inherited one states only what it overrides. }
function TDfmWritePlanner.IsOwn(const pField: TDfmrField): Boolean;
begin
  Result := FDoc.Objects[FDoc.FindObject(pField.CompName, FDataset.Name)].Kind = OBJECT_KIND;
end;

{ ---- changes ---- }

function TDfmWritePlanner.NewItem(pAction: TDfmwAction; const pComponent, pClass: string): TDfmwItem;
var
  VField: TDfmrField;
begin
  Result := Default(TDfmwItem);
  Result.FileIndex := FFileIndex;
  Result.Action := pAction;
  Result.Dataset := FDataset.Name;
  Result.Component := pComponent;
  Result.FieldClass := pClass;
  for VField in FDataset.Fields do
    Result.Siblings := Result.Siblings + [VField.CompName];
end;

procedure TDfmWritePlanner.Block(pIndex: Integer; const pReason: string);
begin
  if pReason = '' then
    Exit;
  FChanges.List[pIndex].Blocked := pReason;
  FChanges.List[pIndex].Checked := False;
end;

procedure CheckUnit(const pBytes: TBytes; const pFile: TDfmwFile; const pItems: TArray<TDfmwItem>); forward;
procedure CheckDfm(const pBytes: TBytes; const pFile: TDfmwFile; const pItems: TArray<TDfmwItem>); forward;

{ Adds a change and tries it alone: one that cannot be written is blocked with the reason. }
function TDfmWritePlanner.AddItem(const pItem: TDfmwItem; pOp: TFrChangeOp; const pOld, pNew: string): Integer;
var
  VChange: TFrChange;
begin
  Result := FChanges.Count;
  VChange := Default(TFrChange);
  VChange.Id := Result + 1;
  VChange.Op := pOp;
  VChange.Target := ExtractFileName(FForm.FileName) + ' ' + pItem.Component;
  VChange.Prop := pItem.PropName;
  VChange.OldValue := pOld;
  VChange.NewValue := pNew;
  VChange.Checked := True;
  FChanges.Add(VChange);
  FItems.Add(pItem);
  if (FUnit = nil) and (pItem.Action in [dwaInsert, dwaDelete, dwaEvent]) then
  begin
    Block(Result, if pItem.Action = dwaEvent then 'no unit beside the DFM to write the handler in' else 'no unit beside the DFM to declare the field in');
    Exit;
  end;
  FDoc.ClearEdits;
  if FUnit <> nil then
    FUnit.ClearEdits;
  try
    if pItem.Action = dwaEvent then
    begin
      TryEvent(pItem);
      Exit;
    end;
    ApplyItem(FDoc, FUnit, FForm.FormClass, pItem);
    FDoc.Output;
    if pItem.Action in [dwaInsert, dwaDelete] then
      CheckUnit(FUnit.Output, FPlan.Files[FFileIndex], [pItem]);
  except
    on E: EDfmWriteError do
      Block(Result, E.Message);
  end;
end;

procedure TDfmWritePlanner.SetItem(const pField: TDfmrField; const pProp, pOld, pNew, pLiteral, pBlocked: string);
var
  VItem: TDfmwItem;
begin
  VItem := NewItem(if pLiteral = '' then dwaRemove else dwaSet, pField.CompName, pField.FieldClass);
  VItem.PropName := pProp;
  VItem.Literal := pLiteral;
  Block(AddItem(VItem, fcoUpdate, pOld, pNew), pBlocked);
end;

{ A property that is not a string. pDefault = its value when the DFM does not state it. }
procedure TDfmWritePlanner.PlanValue(const pField: TDfmrField; const pProp, pDefault, pWant: string; pRemovable: Boolean);
var
  VOld: string;
  VStated, VOwn: Boolean;
begin
  VStated := Stated(pField, pProp, VOld);
  VOwn := IsOwn(pField);
  if not VStated then
    VOld := pDefault;
  if SameText(VOld, pWant) or not (VStated or VOwn) then
    Exit;
  SetItem(pField, pProp, VOld, pWant, if pRemovable and VStated and VOwn and SameText(pWant, pDefault) then '' else pWant, '');
end;

{ A string property; '' in the repository states nothing. }
procedure TDfmWritePlanner.PlanText(const pField: TDfmrField; const pProp, pDefault, pWant: string);
var
  VOld, VBlocked: string;
  VStated, VOwn: Boolean;
begin
  VStated := Stated(pField, pProp, VOld);
  VOwn := IsOwn(pField);
  if not VStated then
    VOld := pDefault;
  if (pWant = '') or (VOld = pWant) or not (VStated or VOwn) then
    Exit;
  VBlocked := '';
  if not (VStated or HasProp(pField.FieldClass, pProp)) then
    VBlocked := pField.FieldClass + ' has no property ' + pProp + ' that drag-lint knows of';
  SetItem(pField, pProp, VOld, pWant, if VStated and VOwn and (pWant = pDefault) then '' else DfmStringLiteral(pWant), VBlocked);
end;

procedure TDfmWritePlanner.PlanWidthAndSize(const pField: TDfmrField; const pRow: TRepoField);
var
  VSample: TField;
  VText: string;
  VSize, VLength: Integer;
begin
  VSample := Sample(pField.FieldClass);
  VSize := 0;
  if MatchText(pField.FieldClass, [CLASS_STRING, CLASS_WIDE_STRING]) then
  begin
    VSize := if Stated(pField, PROP_SIZE, VText) then StrToIntDef(VText, 0) else DEFAULT_STRING_SIZE;
    VSample.Size := VSize;
  end;
  if pRow.DisplayWidth > 0 then
    PlanValue(pField, PROP_WIDTH, if VSample = nil then '' else IntToStr(VSample.DisplayWidth), IntToStr(pRow.DisplayWidth), False);
  if (VSize = 0) or (pField.Kind <> frkData) or (pRow.Kind <> frkData) or (BdeBlockReason <> '') then
    Exit;
  VLength := ColumnCharLength(FRepo, pRow.TableName, pRow.FieldName);
  if VLength > 0 then
    PlanValue(pField, PROP_SIZE, IntToStr(VSize), IntToStr(VLength), False);
end;

{ Hiding a field is never checked: False is also the repository's new-row value. }
procedure TDfmWritePlanner.PlanVisible(const pField: TDfmrField; const pRow: TRepoField);
var
  VFirst, VI: Integer;
begin
  { TAggregateField.Visible defaults to False; a stored True may be the default of a new repository row }
  if (not pRow.HasVisible) or ((pField.Kind = frkAggregate) and pRow.Visible) then
    Exit;
  VFirst := FChanges.Count;
  PlanValue(pField, PROP_VISIBLE, if pField.Kind = frkAggregate then 'False' else 'True', BoolToStr(pRow.Visible, True), True);
  for VI := VFirst to FChanges.Count - 1 do
    FChanges.List[VI].Checked := FChanges.List[VI].Checked and pRow.Visible;
end;

{ A changed kind is never checked: the form's code may assign the field. }
procedure TDfmWritePlanner.PlanKind(const pField: TDfmrField; const pRow: TRepoField);
var
  VItem: TDfmwItem;
  VIndex: Integer;
begin
  VItem := NewItem(dwaKind, pField.CompName, pField.FieldClass);
  VItem.PropName := PROP_KIND;
  VItem.Kind := pRow.Kind;
  VIndex := AddItem(VItem, fcoUpdate, KIND_NAMES[pField.Kind], KIND_NAMES[pRow.Kind]);
  FChanges.List[VIndex].Checked := False;
  if ([pField.Kind, pRow.Kind] * [frkLookup, frkAggregate]) <> [] then
    Block(VIndex, 'a lookup or aggregate field is another component: remove the field and add it again')
  else if not IsOwn(pField) then
    Block(VIndex, 'the field is declared in the ancestor''s DFM');
end;

{ The column behind a dataset field; '' = the dataset does not state it. }
function TDfmWritePlanner.ColumnOf(const pDataset: TDfmrDataset; const pSource: TSource; const pName: string): string;
var
  VField, VNamed: TDfmrField;
  VTable: string;
begin
  VNamed := Default(TDfmrField);
  VNamed.FieldName := Trim(pName);
  for VField in pDataset.Fields do
    if SameText(VField.FieldName, Trim(pName)) then
      VNamed := VField;
  if not (FieldSource(pSource, VNamed, VTable, Result) and SameText(VTable, pSource.TableName)) then
    Result := '';
end;

function TDfmWritePlanner.PlannedName(const pColumn: string; out pId: Integer): string;
var
  VField: TPlannedField;
begin
  Result := '';
  pId := 0;
  for VField in FPlanned do
    if SameText(VField.Column, pColumn) then
    begin
      pId := VField.ChangeId;
      Exit(VField.Name);
    end;
end;

{ The name of a column in a dataset as it is at run time: with persistent fields only those exist. }
function TDfmWritePlanner.NameOf(const pDataset: TDfmrDataset; const pSource: TSource; const pColumn: string;
  out pBlocked: string): string;
var
  VField: TDfmrField;
  VTable, VColumn: string;
begin
  pBlocked := '';
  for VField in pDataset.Fields do
    if FieldSource(pSource, VField, VTable, VColumn) and SameText(VTable, pSource.TableName) and SameText(VColumn, pColumn) then
      Exit(VField.FieldName);
  Result := '';
  if (Length(pDataset.Fields) = 0) and (Length(pDataset.InheritedFields) = 0) then
    Result := ResultName(pSource, pColumn);
  if Result = '' then
    pBlocked := Format('%s has no field for %s.%s', [pDataset.Name, pSource.TableName, pColumn]);
end;

{ ---- lookups ---- }

{ A SQL text without strings, quoted names and comments. }
function BareSql(const pSql: string): string;
begin
  Result := TRegEx.Replace(pSql, '''[^'']*''|"[^"]*"|/\*.*?\*/|--[^\r\n]*', ' ', [roSingleLine]);
end;

{ Why a SELECT of the DFM may not return every row of the dataset's table; '' = it does. }
function SelectDoubt(const pSql: string; const pSource: TSource): string;
var
  VMatch: TMatch;
begin
  if TRegEx.IsMatch(BareSql(pSql), '[&!]\s*[A-Za-z_]') then
    Exit('has SQL macros');
  if pSource.Sql.Reason <> '' then
    Exit('has a SELECT that is not understood: ' + pSource.Sql.Reason);
  if (Length(pSource.Sql.Tables) <> 1) or not SameText(pSource.Sql.Tables[0].Name, pSource.TableName) then
    Exit('has a SELECT that does not read ' + pSource.TableName + ' alone');
  VMatch := TRegEx.Match(BareSql(pSql), '\b(WHERE|HAVING|FIRST|SKIP|ROWS|FETCH|OFFSET)\b', [roIgnoreCase]);
  Result := if VMatch.Success then 'has a SELECT that may not return all rows (' + UpperCase(VMatch.Value) + ')' else '';
end;

{ Why the DFM does not show that a dataset holds every row of its table; '' = it does. }
function TargetDoubt(const pDataset: TDfmrDataset; const pSource: TSource; pDoc: TDfmDocument; pObject: Integer): string;
var
  VText: string;
begin
  Result := '';
  if pDataset.ObjKind <> OBJECT_KIND then
    Result := 'is inherited: the ancestor may limit its rows'
  else if pDoc.TryProp(pObject, 'Filtered', VText) and SameText(VText, 'True') then
    Result := 'is filtered (Filtered = True)'
  else if pSource.HasSql then
    Result := SelectDoubt(pDataset.Sql, pSource)
  else if pDataset.TableName = '' then
    Result := 'has no SELECT in the DFM: its rows are set in code';
end;

{ Why a dataset is no lookup target at all: it holds the rows of a parameter or of a master record. }
function TargetRefusal(const pDataset: TDfmrDataset; pDoc: TDfmDocument; pObject: Integer): string;
const
  MASTER_PROPS: array[0..3] of string = ('MasterSource', 'MasterFields', 'DataSource', 'DataSetField');
var
  VProp, VText: string;
begin
  Result := '';
  if TRegEx.IsMatch(BareSql(pDataset.Sql), ':\s*[A-Za-z_]') then
    Exit('has SQL parameters');
  for VProp in MASTER_PROPS do
    if pDoc.TryProp(pObject, VProp, VText) then
      Exit('is bound to a master (' + VProp + ')');
end;

{ The datasets of a form; both readers list them in DFM order. One that is not a child of the root is in a frame. }
function DatasetTargets(const pForm: TDfmrForm; pDoc: TDfmDocument; const pPrefix: string): TArray<TLookupTarget>;
var
  VTarget: TLookupTarget;
  VDataset: TDfmrDataset;
  VNext, VParent: Integer;
begin
  Result := nil;
  VNext := 1;
  for VDataset in pForm.Datasets do
  begin
    while (VNext < Length(pDoc.Objects)) and not (SameText(pDoc.Objects[VNext].Name, VDataset.Name)
      and SameText(pDoc.Objects[VNext].ObjClass, VDataset.DatasetClass)) do
      Inc(VNext);
    if VNext >= Length(pDoc.Objects) then
      raise EDfmWriteError.Create(ExtractFileName(pForm.FileName) + ': the two DFM readers disagree about ' + VDataset.Name);
    VParent := pDoc.Objects[VNext].Parent;
    VTarget.RefName := pPrefix + (if VParent > 0 then pDoc.Objects[VParent].Name + '.' else '') + VDataset.Name;
    VTarget.InFrame := VParent > 0;
    VTarget.Dataset := VDataset;
    VTarget.Source := SourceOf(VDataset);
    VTarget.Refusal := TargetRefusal(VDataset, pDoc, VNext);
    VTarget.Doubt := TargetDoubt(VDataset, VTarget.Source, pDoc, VNext);
    Result := Result + [VTarget];
    Inc(VNext);
  end;
end;

{ Adds the datasets of another form or data module; a binary DFM is reported. }
procedure TDfmWritePlanner.AddModule(const pFile: string);
var
  VBytes: TBytes;
  VDoc: TDfmDocument;
  VForm: TDfmrForm;
begin
  VDoc := nil;
  try
    try
      VBytes := TFile.ReadAllBytes(pFile);
      NoteRead(pFile, VBytes);
      VForm := LoadDfmForm(pFile);
      VDoc := TDfmDocument.Create(VBytes, ExtractFileName(pFile));
      FModuleTargets := FModuleTargets + DatasetTargets(VForm, VDoc, VForm.FormName + '.');
    except
      on E: EDfmReadError do
        FWarnings.Add('lookup datasets: ' + E.Message);
      on E: EDfmWriteError do
        FWarnings.Add('lookup datasets: ' + E.Message);
    end;
  finally
    VDoc.Free;
  end;
end;

{ The datasets of the other forms / data modules of the folder that the form's unit names. }
function TDfmWritePlanner.ModuleTargets: TArray<TLookupTarget>;
var
  VFile, VUnit: string;
begin
  if (FUnit <> nil) and not FModulesRead then
    for VFile in TDirectory.GetFiles(ExtractFilePath(FForm.FileName), '*' + DFM_EXT) do
    begin
      VUnit := TPath.GetFileNameWithoutExtension(VFile);
      if (not SameText(VFile, FForm.FileName)) and (FUnit.Mentions(VUnit.Substring(VUnit.LastIndexOf('.') + 1)) > 0) then
        AddModule(VFile);
    end;
  FModulesRead := True;
  Result := FModuleTargets;
end;
{ The datasets a lookup into pTable can use: this form's, or else those of the modules its unit names. }
function TDfmWritePlanner.TargetsOf(const pTable: string): TArray<TLookupTarget>;
var
  VTarget: TLookupTarget;
begin
  Result := nil;
  for VTarget in DatasetTargets(FForm, FDoc, '') do
    if SameText(VTarget.Source.TableName, pTable) and (not SameText(VTarget.Dataset.Name, FDataset.Name)) then
      Result := Result + [VTarget];
  if Length(Result) > 0 then
    Exit;
  for VTarget in ModuleTargets do
    if SameText(VTarget.Source.TableName, pTable) then
      Result := Result + [VTarget];
end;

function TDfmWritePlanner.TryCurrentTarget(const pName: string; out pTarget: TLookupTarget): Boolean;
var
  VTargets: TArray<TLookupTarget>;
  VTarget: TLookupTarget;
begin
  VTargets := DatasetTargets(FForm, FDoc, '');
  if pName.Contains('.') then
    VTargets := VTargets + ModuleTargets;
  pTarget := Default(TLookupTarget);
  Result := False;
  for VTarget in VTargets do
    if SameText(VTarget.RefName, pName) then
    begin
      pTarget := VTarget;
      Exit(True);
    end;
end;
function TargetNames(const pTargets: TArray<TLookupTarget>): string;
var
  VTarget: TLookupTarget;
  VNames: TArray<string>;
begin
  VNames := nil;
  for VTarget in pTargets do
    VNames := VNames + [VTarget.RefName];
  Result := string.Join(' ', VNames);
end;
{ Why a dataset cannot become the target of a lookup; '' = it can. }
function NewTargetReason(const pTarget: TLookupTarget): string;
begin
  Result := if pTarget.Refusal <> '' then pTarget.Refusal else if pTarget.InFrame then 'is inside a frame' else pTarget.Doubt;
end;

{ '' when the table has exactly one dataset to look up in. }
function TargetReason(const pTargets: TArray<TLookupTarget>; const pTable: string): string;
begin
  Result := '';
  if Length(pTargets) = 0 then
    Result := 'no dataset of the form (or of a module its unit names) reads ' + pTable
  else if Length(pTargets) > 1 then
    Result := Format('%d datasets read %s: %s', [Length(pTargets), pTable, TargetNames(pTargets)])
  else if NewTargetReason(pTargets[0]) <> '' then
    Result := Format('the only dataset that reads %s, %s, %s', [pTable, pTargets[0].RefName, NewTargetReason(pTargets[0])]);
end;

{ The key column of the lookup table: DESTKEY, or its one-column primary key. }
function LookupKeyColumn(pRepo: TFDConnection; const pRow: TRepoField): string;
var
  VPk: TArray<string>;
begin
  Result := pRow.DestKey;
  if Result <> '' then
    Exit;
  VPk := PrimaryKey(pRepo, pRow.DestTable);
  if Length(VPk) = 1 then
    Result := VPk[0];
end;

{ The dataset of a lookup after the plan: the current one, or the one that reads DESTTABLE. Returns why it is not
  settled: a current dataset without a known table may be the right one, so it is never replaced. }
function TDfmWritePlanner.TargetOfLookup(const pField: TDfmrField; const pRow: TRepoField; out pTarget: TLookupTarget): string;
var
  VFound: Boolean;
  VTargets: TArray<TLookupTarget>;
begin
  Result := '';
  VFound := TryCurrentTarget(pField.LookupDataSet, pTarget);
  if VFound and SameText(pTarget.Source.TableName, pRow.DestTable) then
  begin
    if pTarget.Refusal <> '' then
      Result := Format('the current lookup dataset %s %s', [pTarget.RefName, pTarget.Refusal]);
    Exit;
  end;
  if VFound and (pTarget.Source.TableName = '') then
    Exit(Format('the table of the current lookup dataset %s is not known: %s', [pField.LookupDataSet, pTarget.Source.Reason]));
  if (pField.LookupDataSet <> '') and not VFound then
    Exit(Format('the current lookup dataset %s is not in the form or in a module its unit names: its table is not known',
      [pField.LookupDataSet]));
  VTargets := TargetsOf(pRow.DestTable);
  Result := TargetReason(VTargets, pRow.DestTable);
  if Result = '' then
    pTarget := VTargets[0]; // TargetReason is '' for exactly one target
end;

procedure TDfmWritePlanner.PlanWiring(const pField: TDfmrField; const pRow: TRepoField);
var
  VTarget: TLookupTarget;
  VReason: string;
  VMoves: Boolean;

  { An inherited field states only what it overrides. }
  function IsHere(const pProp: string): Boolean;
  var
    VText: string;
  begin
    Result := IsOwn(pField) or Stated(pField, pProp, VText);
  end;

  { Compares in column space: the DFM names dataset fields, the repository columns. With pAll (another dataset) a part
    that is not settled counts too: what an ancestor states is made for the old dataset. }
  procedure PlanColumnName(const pProp, pCurrent, pColumn: string; const pDataset: TDfmrDataset; const pSource: TSource; pAll: Boolean);
  var
    VName, VBlocked: string;
    VHere: Boolean;
  begin
    VHere := IsHere(pProp) and (pColumn <> '');
    if (VHere and SameText(ColumnOf(pDataset, pSource, pCurrent), pColumn)) or not (VHere or pAll) then
      Exit;
    VName := if pColumn = '' then '' else NameOf(pDataset, pSource, pColumn, VBlocked);
    if pColumn = '' then
      VBlocked := 'the repository does not hold it'
    else if pCurrent.Contains(MULTI_FIELD) then
      VBlocked := 'multi-field lookup key'
    else if VReason <> '' then
      VBlocked := VReason;
    SetItem(pField, pProp, pCurrent, if VName = '' then pColumn else VName, DfmStringLiteral(VName), VBlocked);
  end;

begin
  VReason := '';
  VTarget := Default(TLookupTarget);
  if (pRow.DestTable <> '') and IsHere(PROP_LOOKUP_DATASET) then
    VReason := TargetOfLookup(pField, pRow, VTarget);
  VMoves := (pRow.DestTable <> '') and SameText(VTarget.Source.TableName, pRow.DestTable) and not SameText(VTarget.RefName, pField.LookupDataSet);
  { with an unsettled dataset no part of the wiring changes }
  PlanColumnName('KeyFields', pField.KeyFields, pRow.SourceKey, FDataset, FSource, VMoves);
  if (pRow.DestTable = '') or not IsHere(PROP_LOOKUP_DATASET) then
    Exit;
  if not SameText(VTarget.Source.TableName, pRow.DestTable) then
  begin
    SetItem(pField, PROP_LOOKUP_DATASET, pField.LookupDataSet, pRow.DestTable, pRow.DestTable, VReason);
    Exit;
  end;
  if VMoves then
    SetItem(pField, PROP_LOOKUP_DATASET, pField.LookupDataSet, VTarget.RefName, VTarget.RefName, '');
  PlanColumnName('LookupKeyFields', pField.LookupKeyFields, LookupKeyColumn(FRepo, pRow), VTarget.Dataset, VTarget.Source, VMoves);
  PlanColumnName('LookupResultField', pField.LookupResult, pRow.DestValue, VTarget.Dataset, VTarget.Source, VMoves);
end;

{ The changes from pFirst on are of a lookup whose dataset may hold only some rows: none is checked. }
procedure TDfmWritePlanner.UncheckDoubted(pFirst: Integer; const pField: TDfmrField; const pRow: TRepoField);
var
  VI: Integer;
  VTarget: TLookupTarget;
begin
  if (pFirst = FChanges.Count) or not TryCurrentTarget(pField.LookupDataSet, VTarget) or (VTarget.Doubt = '')
    or not SameText(VTarget.Source.TableName, pRow.DestTable) then
    Exit;
  FWarnings.Add(Format('%s: the lookup changes are unchecked: the current lookup dataset %s %s', [Where(pField), VTarget.RefName, VTarget.Doubt]));
  for VI := pFirst to FChanges.Count - 1 do
    FChanges.List[VI].Checked := False;
end;

{ The changes from pFirst on are one wiring: each needs all others, and one blocked part blocks them all. }
procedure TDfmWritePlanner.JoinWiring(pFirst: Integer);
var
  VI, VJ, VBlocked: Integer;
begin
  VBlocked := -1;
  for VI := pFirst to FChanges.Count - 1 do
    if (VBlocked < 0) and (FChanges[VI].Blocked <> '') then
      VBlocked := VI;
  for VI := pFirst to FChanges.Count - 1 do
  begin
    if (VBlocked >= 0) and (FChanges[VI].Blocked = '') then
      Block(VI, Format('part of a lookup wiring that is blocked (change %d)', [VBlocked + 1]));
    for VJ := pFirst to FChanges.Count - 1 do
      if VJ <> VI then
        FItems.List[VI].Requires := FItems.List[VI].Requires + [VJ + 1];
  end;
end;

{ FieldKind is no part: a changed kind of a lookup is always blocked, a new lookup is one block. }
procedure TDfmWritePlanner.PlanLookup(const pField: TDfmrField; const pRow: TRepoField);
var
  VFirst: Integer;
begin
  VFirst := FChanges.Count;
  PlanWiring(pField, pRow);
  UncheckDoubted(VFirst, pField, pRow);
  JoinWiring(VFirst);
end;
{ ---- existing fields ---- }

procedure TDfmWritePlanner.PlanField(const pField: TDfmrField; const pRow: TRepoField);
var
  VSample: TField;
begin
  if not pRow.KindKnown then
    Exit;
  if pRow.Kind <> pField.Kind then
  begin
    if pRow.Kind = frkGraphical then
      FWarnings.Add(Where(pField) + ': the repository has a graphical column, the DFM a persistent field')
    else
      PlanKind(pField, pRow);
    Exit;
  end;
  VSample := Sample(pField.FieldClass);
  if InRange(pRow.Alignment, 0, MAX_ALIGNMENT) and (VSample <> nil) then
    PlanValue(pField, PROP_ALIGNMENT, GetEnumName(TypeInfo(TAlignment), Ord(VSample.Alignment)),
      GetEnumName(TypeInfo(TAlignment), pRow.Alignment), True);
  PlanText(pField, PROP_LABEL, pField.FieldName, pRow.DisplayLabel);
  PlanWidthAndSize(pField, pRow);
  PlanVisible(pField, pRow);
  PlanText(pField, PROP_FORMAT, '', pRow.DisplayFormat);
  PlanText(pField, PROP_EDIT_FORMAT, '', pRow.EditFormat);
  if pRow.Kind = frkLookup then
    PlanLookup(pField, pRow);
  if (pRow.Kind = frkAggregate) and SameText(pField.FieldClass, CLASS_AGGREGATE) then
    PlanText(pField, 'Expression', '', pRow.Body);
end;

{ A field the byte-level reader cannot tell from another one (two frames with one dataset) is reported. }
procedure TDfmWritePlanner.TryPlanField(const pField: TDfmrField; const pRow: TRepoField);
begin
  try
    PlanField(pField, pRow);
  except
    on E: EDfmWriteError do
      FWarnings.Add(Where(pField) + ': not written: ' + E.Message);
  end;
end;

{ ---- new fields ---- }

{ Wide or narrow strings: as the dataset's first string column, else as the column's character set. }
function IsWideDataset(const pDataset: TDfmrDataset; const pCharset: string): Boolean;
var
  VField: TDfmrField;
begin
  Result := MatchText(pCharset, UNICODE_CHARSETS);
  for VField in pDataset.Fields do
    if (VField.Kind = frkData) and MatchText(VField.FieldClass, [CLASS_STRING, CLASS_WIDE_STRING]) then
      Exit(SameText(VField.FieldClass, CLASS_WIDE_STRING));
end;

function TDfmWritePlanner.ClassOfRow(const pRow: TRepoField): string;
var
  VDest: TRepoField;
begin
  if pRow.Kind = frkAggregate then
    Exit(CLASS_AGGREGATE);
  Result := FieldClassForRow(pRow.FieldType, pRow.SubType, pRow.Scale, pRow.AsType, pRow.VarType);
  if (pRow.Kind = frkLookup) and FRows.TryGetValue(KeyOf(pRow.DestTable, pRow.DestValue), VDest) and (VDest.FieldType <> 0) then
    Result := FieldClassForRow(VDest.FieldType, VDest.SubType, VDest.Scale, '', '');
  if MatchText(Result, [CLASS_STRING, CLASS_MEMO]) and IsWideDataset(FDataset, pRow.Charset) then
    Result := if Result = CLASS_STRING then CLASS_WIDE_STRING else CLASS_WIDE_MEMO;
end;

{ Length of a string field, 0 = the repository does not know it. }
function TDfmWritePlanner.SizeOfRow(const pRow: TRepoField): Integer;
begin
  Result := if pRow.Kind = frkLookup then ColumnCharLength(FRepo, pRow.DestTable, pRow.DestValue)
    else ColumnCharLength(FRepo, pRow.TableName, pRow.FieldName);
  if Result <= 0 then
    Result := pRow.StringSize;
end;

{ Dataset name + field name, as the IDE does; a name the form or its unit uses gets a number. }
function TDfmWritePlanner.NewComponentName(const pField: string): string;
var
  VBase: string;
  VNumber: Integer;
begin
  VBase := FDataset.Name + TRegEx.Replace(pField, '[^A-Za-z0-9_]', '');
  Result := VBase;
  VNumber := 0;
  while (FDoc.FindObject(Result, '') >= 0) or (FNewNames.IndexOf(Result) >= 0)
    or ((FUnit <> nil) and (FUnit.Mentions(Result) > 0)) do
  begin
    Inc(VNumber);
    Result := VBase + IntToStr(VNumber);
  end;
  FNewNames.Add(Result);
end;

{ Gives a field a lookup dataset that streams as pRefName: a stand-in the field owns. }
procedure SetLookupStandIn(pField: TField; const pRefName: string);
var
  VOwner: TComponent;
  VDataset: TDataSet;
  VDot: Integer;
begin
  VOwner := pField;
  VDot := pRefName.IndexOf('.');
  if VDot > 0 then
  begin
    VOwner := TComponent.Create(pField);
    VOwner.Name := pRefName.Substring(0, VDot);
  end;
  VDataset := TFDMemTable.Create(VOwner);
  VDataset.Name := pRefName.Substring(VDot + 1);
  pField.LookupDataSet := VDataset;
end;

{ Sets the key and result field of a new lookup; returns why the target dataset has none. }
function TDfmWritePlanner.LookupNamesReason(const pRow: TRepoField; const pTarget: TLookupTarget; pField: TField): string;
var
  VKey: string;
begin
  VKey := LookupKeyColumn(FRepo, pRow);
  if VKey = '' then
    Exit('no lookup key: DESTKEY is empty and ' + pRow.DestTable + ' has no one-column primary key');
  pField.LookupKeyFields := NameOf(pTarget.Dataset, pTarget.Source, VKey, Result);
  if Result = '' then
    pField.LookupResultField := NameOf(pTarget.Dataset, pTarget.Source, pRow.DestValue, Result);
end;

{ Sets the wiring of a new lookup field; returns why it cannot be wired. }
function TDfmWritePlanner.LookupBlock(const pRow: TRepoField; pField: TField; out pRequires: TArray<Integer>): string;
var
  VTargets: TArray<TLookupTarget>;
  VKey: string;
  VId: Integer;
begin
  pRequires := nil;
  if (pRow.SourceKey = '') or (pRow.DestTable = '') or (pRow.DestValue = '') then
    Exit('the lookup wiring in the repository is incomplete');
  VKey := PlannedName(pRow.SourceKey, VId);
  if VKey = '' then
    Exit(Format('%s has no field for %s', [FDataset.Name, pRow.SourceKey]));
  if VId > 0 then
    pRequires := [VId];
  pField.KeyFields := VKey;
  VTargets := TargetsOf(pRow.DestTable);
  Result := TargetReason(VTargets, pRow.DestTable);
  if Result = '' then
    Result := LookupNamesReason(pRow, VTargets[0], pField);
  if Result = '' then
    SetLookupStandIn(pField, VTargets[0].RefName);
end;
function TDfmWritePlanner.InsertBlockReason(const pRow: TRepoField; const pClass: string): string;
begin
  Result := '';
  if not pRow.KindKnown then
    Result := 'unknown FIELD_KIND'
  else if BdeBlockReason <> '' then
    Result := BdeBlockReason
  else if FDataset.ObjKind <> OBJECT_KIND then
    Result := 'the dataset is inherited: its fields are in the ancestor''s DFM'
  else if FindClassByName(pClass) = nil then
    Result := 'the repository does not say which TField class it is (FIELD_TYPE / FIELD_AS_TYPE)'
  else if (pRow.Kind = frkData) and MatchText(pClass, [CLASS_STRING, CLASS_WIDE_STRING]) and (SizeOfRow(pRow) <= 0) then
    Result := 'the repository does not know its length'
  else if (pRow.Kind = frkAggregate) and not (FDataset.DatasetClass.StartsWith('TFD') or SameText(FDataset.DatasetClass, 'TClientDataSet')) then
    Result := FDataset.DatasetClass + ' has no aggregate fields'
  else if (pRow.Kind = frkAggregate) and (pRow.Body = '') then
    Result := 'the repository has no aggregate expression (CALC_BODY)'
  else if (pRow.Kind = frkData) and (ResultName(FSource, pRow.FieldName) = '') then
    Result := 'the SQL does not return it'
  else if (FUnit <> nil) and not FUnit.UsesAny([UNIT_DB, UNIT_OLD_DB]) then
    Result := 'the interface section of the unit does not use Data.DB';
end;

procedure SetTextProp(pField: TField; const pName, pValue: string);
begin
  if (pValue <> '') and IsPublishedProp(pField, pName) then
    SetStrProp(pField, pName, pValue);
end;

{ Everything but the lookup wiring. }
procedure FillField(pField: TField; const pRow: TRepoField; pSize: Integer);
begin
  if pRow.Kind = frkAggregate then
    SetTextProp(pField, 'Expression', pRow.Body)
  else
    pField.FieldKind := TFieldKind(GetEnumValue(TypeInfo(TFieldKind), KIND_NAMES[pRow.Kind]));
  if pField is TStringField then
    pField.Size := if pSize > 0 then pSize else pField.Size
  else if ((pField is TBCDField) or (pField is TFMTBCDField)) and (pRow.Scale < 0) then
    pField.Size := -pRow.Scale;
  if not SameStr(pRow.DisplayLabel, pField.FieldName) then
    SetTextProp(pField, PROP_LABEL, pRow.DisplayLabel);
  SetTextProp(pField, PROP_FORMAT, pRow.DisplayFormat);
  SetTextProp(pField, PROP_EDIT_FORMAT, pRow.EditFormat);
  if pRow.DisplayWidth > 0 then
    pField.DisplayWidth := pRow.DisplayWidth;
  { a column's False may be the new-row value: it stays a change of its own, unchecked }
  if pRow.HasVisible and (pRow.Visible or (pRow.Kind <> frkData)) then
    pField.Visible := pRow.Visible;
  if InRange(pRow.Alignment, 0, MAX_ALIGNMENT) then
    pField.Alignment := TAlignment(pRow.Alignment);
end;

function StreamBlock(pField: TField): TArray<string>;
var
  VStream: TBytesStream;
begin
  VStream := TBytesStream.Create;
  try
    VStream.WriteComponent(pField);
    Result := DfmBlockOfStream(Copy(VStream.Bytes, 0, VStream.Size));
  finally
    VStream.Free;
  end;
end;

{ `TIntegerField; FieldName = 'QTY'`: the block without its frame. }
function BlockSummary(const pClass: string; const pBlock: TArray<string>): string;
var
  VI: Integer;
begin
  Result := pClass;
  for VI := 1 to High(pBlock) - 1 do
    Result := Result + '; ' + Trim(pBlock[VI]);
end;

procedure TDfmWritePlanner.PlanInsert(const pRow: TRepoField);
var
  VItem: TDfmwItem;
  VField: TField;
  VReason, VClass: string;
  VPlanned: TPlannedField;
  VIndex: Integer;
begin
  VClass := ClassOfRow(pRow);
  VReason := InsertBlockReason(pRow, VClass);
  VItem := NewItem(dwaInsert, NewComponentName(pRow.FieldName), VClass);
  if FindClassByName(VClass) <> nil then
  begin
    VField := FindClassByName(VClass).Create(nil);
    try
      VField.Name := VItem.Component;
      VField.FieldName := if (pRow.Kind = frkData) and (VReason = '') then ResultName(FSource, pRow.FieldName) else pRow.FieldName;
      FillField(VField, pRow, SizeOfRow(pRow));
      if (pRow.Kind = frkLookup) and (VReason = '') then
        VReason := LookupBlock(pRow, VField, VItem.Requires);
      VItem.Block := StreamBlock(VField);
      VPlanned.Name := VField.FieldName;
    finally
      VField.Free;
    end;
  end;
  VIndex := AddItem(VItem, fcoInsert, '', BlockSummary(VClass, VItem.Block));
  Block(VIndex, VReason);
  if FChanges[VIndex].Blocked <> '' then
    Exit;
  VPlanned.Column := pRow.FieldName;
  VPlanned.ChangeId := VIndex + 1;
  FPlanned.Add(VPlanned);
  if (pRow.Kind in [frkCalc, frkInternalCalc]) and (pRow.Body <> '') then
    FWarnings.Add(FChanges[VIndex].Target + ': its calc code is not written (handler code is generated separately)');
end;

{ ---- new event handlers (Q1 A, 1.55) ---- }

{ The parameters of a TField event: TFieldGetTextEvent, TFieldSetTextEvent, else TFieldNotifyEvent. }
function FieldEventSignature(const pEvent: string): string;
begin
  if SameText(pEvent, EVENT_GET_TEXT) then
    Result := 'Sender: TField; var Text: string; DisplayText: Boolean'
  else if SameText(pEvent, EVENT_SET_TEXT) then
    Result := 'Sender: TField; const Text: string'
  else
    Result := 'Sender: TField';
end;

{ <Dataset><Field><Event without On>: the identifier characters of the field name only. }
function HandlerName(const pDataset, pFieldName, pEvent: string): string;
begin
  Result := pDataset + TRegEx.Replace(pFieldName, '[^A-Za-z0-9_]', '') + Copy(pEvent, Length(EVENT_PREFIX) + 1, MaxInt);
end;

{ The persistent fields a macro can name: those of the dataset and those the plan adds. }
function TDfmWritePlanner.HandlerFields: TArray<TFrhField>;
var
  VField: TDfmrField;
  VPlanned: TPlannedField;
  VOne: TFrhField;
  VTable, VColumn: string;
begin
  Result := nil;
  for VField in FDataset.Fields do
  begin
    VOne := Default(TFrhField);
    VOne.CompName := VField.CompName;
    if FieldSource(FSource, VField, VTable, VColumn) and SameText(VTable, FSource.TableName) then
      VOne.Column := VColumn;
    Result := Result + [VOne];
  end;
  for VPlanned in FPlanned do
    if VPlanned.ChangeId > 0 then
    begin
      VOne := Default(TFrhField);
      VOne.Column := VPlanned.Column;
      VOne.CompName := FItems[VPlanned.ChangeId - 1].Component;
      Result := Result + [VOne];
    end;
end;

{ Renders the event with the changes it needs, as the applier will; raises EDfmWriteError when it cannot be written. }
procedure TDfmWritePlanner.TryEvent(const pItem: TDfmwItem);
var
  VTrial: TArray<TDfmwItem>;
  VId: Integer;
  VDfm, VPas: TBytes;
begin
  VTrial := nil;
  for VId in pItem.Requires do
    VTrial := VTrial + [FItems[VId - 1]];
  VTrial := VTrial + [pItem];
  RenderBytes(FPlan.Files[FFileIndex], VTrial, VDfm, VPas);
  CheckDfm(VDfm, FPlan.Files[FFileIndex], VTrial);
  CheckUnit(VPas, FPlan.Files[FFileIndex], VTrial);
end;

{ The reason when an earlier planned handler has the same name (the names keep only identifier characters, so ORDER-NO and
  ORDERNO meet); the apply would fail on the second one. A name the unit already has is found by TryEvent. }
function TDfmWritePlanner.HandlerClash(pIndex: Integer): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 0 to pIndex - 1 do
    if (FItems[VI].Action = dwaEvent) and (FItems[VI].FileIndex = FItems[pIndex].FileIndex) and SameText(FItems[VI].Literal, FItems[pIndex].Literal) then
      Exit('handler ' + FItems[pIndex].Literal + ' is the name of two fields: ' + FItems[VI].FieldName + ' and ' + FItems[pIndex].FieldName);
end;

{ One unchecked change per TField event the repository holds code for and the field has no handler for. }
procedure TDfmWritePlanner.PlanEvents(const pComponent, pFieldClass: string; const pHandlers: TArray<TDfmrPair>;
  const pRow: TRepoField; const pRequires: TArray<Integer>);
var
  VI, VIndex: Integer;
  VEvent, VReason: string;
  VItem: TDfmwItem;
  VPair: TDfmrPair;
  VAssigned: Boolean;
begin
  for VI := 0 to Min(High(FR_EVENT_COLUMNS), High(pRow.Events)) do
  begin
    VEvent := FR_EVENT_COLUMNS[VI].Event;
    if FR_EVENT_COLUMNS[VI].IsGrid or (Trim(pRow.Events[VI]) = '') then
      Continue;
    VAssigned := False;
    for VPair in pHandlers do
      VAssigned := VAssigned or (SameText(VPair.Name, VEvent) and (VPair.Value <> ''));
    if VAssigned then
      Continue;
    VItem := NewItem(dwaEvent, pComponent, pFieldClass);
    VItem.PropName := VEvent;
    VItem.Literal := HandlerName(FDataset.Name, pRow.FieldName, VEvent);
    VItem.FieldName := pRow.FieldName;
    VItem.MethodParams := FieldEventSignature(VEvent);
    VItem.Requires := pRequires;
    if not NewHandlerRegion(HandlerFields, pComponent, VEvent, pRow.Events[VI], sLineBreak, VItem.MethodBody, VReason) then
      VItem.MethodBody := '';
    VIndex := AddItem(VItem, fcoInsert, '', VItem.Literal);
    FChanges.List[VIndex].Checked := False;
    Block(VIndex, BdeBlockReason);
    if FChanges.List[VIndex].Blocked = '' then
      Block(VIndex, HandlerClash(VIndex));
    if VItem.MethodBody = '' then
      Block(VIndex, VReason);
  end;
end;

{ ---- grid columns that are not fields (Q3(1), 1.55) ---- }

{ The parameters of a TcxGridColumn event: TcxGridGetDisplayTextEvent, else TcxGridTableDataCellCustomDrawEvent. }
function GridEventSignature(const pEvent: string): string;
begin
  Result := if SameText(pEvent, EVENT_GET_DISPLAY_TEXT) then 'Sender: TcxCustomGridTableItem; ARecord: TcxCustomGridRecord; var AText: string'
    else 'Sender: TcxCustomGridTableView; ACanvas: TcxCanvas; AViewInfo: TcxGridTableDataCellViewInfo; var ADone: Boolean';
end;

{ Why the unit cannot compile a declaration that needs pUnits; '' = it uses them all. }
function TDfmWritePlanner.MissingUnit(const pUnits: TArray<string>): string;
var
  VUnit: string;
begin
  Result := '';
  if FUnit <> nil then
    for VUnit in pUnits do
      if not FUnit.UsesAny([VUnit]) then
        Exit('the interface section of the unit does not use ' + VUnit);
end;

{ The table views of the form whose data source is one of this form for the dataset. }
function TDfmWritePlanner.GridViewsOf: TArray<TDfmrGridView>;
var
  VView: TDfmrGridView;
  VPair: TDfmrPair;
begin
  Result := nil;
  for VView in FForm.Views do
    if VView.Kind = dvkTable then
      for VPair in FForm.DataSources do
        if SameText(VPair.Name, VView.DataSource) and SameText(VPair.Value, FDataset.Name) then
          Result := Result + [VView];
end;

function ViewNames(const pViews: TArray<TDfmrGridView>): string;
var
  VView: TDfmrGridView;
begin
  Result := '';
  for VView in pViews do
    Result := Result + (if Result = '' then '' else ', ') + VView.Name;
end;

{ Where a graphical row's columns go: the DL_GRID_COLUMNS rows of this form, else the only view of the dataset. }
function TDfmWritePlanner.GridPlaces(const pRow: TRepoField; const pViews: TArray<TDfmrGridView>): TArray<TGridPlace>;
var
  VQuery: TFDQuery;
  VPlace: TGridPlace;
  VView: TDfmrGridView;
  VNamed, VFound: Boolean;
  VViewName, VColumnName, VColumnIndex: TField;
begin
  Result := nil;
  VNamed := False;
  if FGridTable then
  begin
    VQuery := TFDQuery.Create(nil);
    try
      VQuery.Connection := FRepo;
      VQuery.Open(SQL_GRID_PLACES, [FForm.FormName, pRow.TableName, pRow.FieldName]);
      VViewName := VQuery.FieldByName('VIEW_NAME');
      VColumnName := VQuery.FieldByName('COLUMN_NAME');
      VColumnIndex := VQuery.FieldByName('COLUMN_INDEX');
      while not VQuery.Eof do
      begin
        VNamed := True;
        VPlace.Column := VColumnName.AsString;
        VPlace.Index := if VColumnIndex.IsNull then -1 else VColumnIndex.AsInteger;
        VFound := False;
        for VView in pViews do
          if SameText(VView.Name, VViewName.AsString) then
          begin
            VPlace.View := VView;
            VFound := True;
          end;
        if VFound then
          Result := Result + [VPlace]
        else
          FWarnings.Add(Format('%s %s: graphical column %s not written: DL_GRID_COLUMNS puts it in %s, no TcxGridDBTableView of the dataset',
            [ExtractFileName(FForm.FileName), FDataset.Name, pRow.FieldName, VViewName.AsString]));
        VQuery.Next;
      end;
    finally
      VQuery.Free;
    end;
  end;
  if VNamed then
    Exit;
  if Length(pViews) = 1 then
  begin
    VPlace.View := pViews[0];
    VPlace.Column := pViews[0].Name + TRegEx.Replace(pRow.FieldName, '[^A-Za-z0-9_]', '');
    VPlace.Index := -1;
    Result := [VPlace];
  end
  else if Length(pViews) > 1 then
    FWarnings.Add(Format('%s %s: graphical column %s not written: %d grid views show the dataset (%s) and DL_GRID_COLUMNS names none',
      [ExtractFileName(FForm.FileName), FDataset.Name, pRow.FieldName, Length(pViews), ViewNames(pViews)]));
end;

{ One unchecked change per grid event the row holds code for; each needs the column. }
procedure TDfmWritePlanner.PlanColumnEvents(const pColumn: TDfmwItem; const pRow: TRepoField; pColumnId: Integer);
var
  VI, VIndex: Integer;
  VEvent, VReason: string;
  VItem: TDfmwItem;
  VUnits: TArray<string>;
begin
  for VI := 0 to Min(High(FR_EVENT_COLUMNS), High(pRow.Events)) do
  begin
    VEvent := FR_EVENT_COLUMNS[VI].Event;
    if not FR_EVENT_COLUMNS[VI].IsGrid or (Trim(pRow.Events[VI]) = '') then
      Continue;
    VItem := NewItem(dwaEvent, pColumn.Component, CLASS_GRID_COLUMN);
    VItem.Dataset := pColumn.Dataset;
    VItem.PropName := VEvent;
    VItem.Literal := pColumn.Component + Copy(VEvent, Length(EVENT_PREFIX) + 1, MaxInt);
    VItem.FieldName := pRow.FieldName;
    VItem.MethodParams := GridEventSignature(VEvent);
    VItem.Requires := [pColumnId];
    if not NewHandlerRegion(HandlerFields, pColumn.Component, VEvent, pRow.Events[VI], sLineBreak, VItem.MethodBody, VReason) then
      VItem.MethodBody := '';
    VIndex := AddItem(VItem, fcoInsert, '', VItem.Literal);
    FChanges.List[VIndex].Checked := False;
    if FChanges.List[VIndex].Blocked = '' then
      Block(VIndex, HandlerClash(VIndex));
    VUnits := [UNIT_CX_TABLE];
    if not SameText(VEvent, EVENT_GET_DISPLAY_TEXT) then
      VUnits := VUnits + [UNIT_CX_GRAPHICS];
    if FChanges.List[VIndex].Blocked = '' then
      Block(VIndex, MissingUnit(VUnits));
    if VItem.MethodBody = '' then
      Block(VIndex, VReason);
  end;
end;

{ A new TcxGridDBColumn for a graphical row, unchecked: the owner's second confirmation is its id in a --select file. }
procedure TDfmWritePlanner.PlanGridColumn(const pRow: TRepoField; const pPlace: TGridPlace);
var
  VColumn: TDfmrGridColumn;
  VItem: TDfmwItem;
  VIndex, VAt, VI: Integer;
  VReason: string;
begin
  for VColumn in pPlace.View.Columns do
    if SameText(VColumn.FieldName, pRow.FieldName) or SameText(VColumn.Name, pPlace.Column) then
      Exit;
  VAt := if (pPlace.Index < 0) or (pPlace.Index > Length(pPlace.View.Columns)) then Length(pPlace.View.Columns) else pPlace.Index;
  VItem := NewItem(dwaInsert, pPlace.Column, CLASS_GRID_COLUMN);
  VItem.Dataset := pPlace.View.Name;
  VItem.FieldName := pRow.FieldName;
  VItem.Siblings := nil;
  for VI := 0 to VAt - 1 do
    VItem.Siblings := VItem.Siblings + [pPlace.View.Columns[VI].Name];
  VItem.Block := ['object ' + pPlace.Column + ': ' + CLASS_GRID_COLUMN];
  if pRow.DisplayLabel <> '' then
    VItem.Block := VItem.Block + ['  ' + PROP_CAPTION + ' =' + DfmStringLiteral(pRow.DisplayLabel)];
  VItem.Block := VItem.Block + ['  ' + PROP_BINDING + ' =' + DfmStringLiteral(pRow.FieldName), 'end'];
  if pPlace.View.ObjKind <> OBJECT_KIND then
    VReason := 'the grid view is inherited: its columns are in the ancestor''s DFM'
  else if (FDoc.FindObject(pPlace.Column, '') >= 0) or (FNewNames.IndexOf(pPlace.Column) >= 0) then
    VReason := 'the form has another component named ' + pPlace.Column
  else if (FUnit <> nil) and (FUnit.Mentions(pPlace.Column) > 0) then
    VReason := ExtractFileName(FPlan.Files[FFileIndex].PasName) + ': the unit already has ' + pPlace.Column
  else
    VReason := MissingUnit([UNIT_CX_DB_TABLE]);
  FNewNames.Add(pPlace.Column);
  VIndex := AddItem(VItem, fcoInsert, '', BlockSummary(CLASS_GRID_COLUMN + '; ' + pPlace.View.Name + ' index ' + IntToStr(VAt), VItem.Block));
  FChanges.List[VIndex].Checked := False;
  Block(VIndex, VReason);
  if FChanges[VIndex].Blocked = '' then
    PlanColumnEvents(VItem, pRow, VIndex + 1);
end;

{ Every graphical row of the dataset's table whose column the form lacks. }
procedure TDfmWritePlanner.PlanGridColumns;
var
  VViews: TArray<TDfmrGridView>;
  VRow: TRepoField;
  VPlace: TGridPlace;
begin
  if FSource.TableName = '' then
    Exit;
  VViews := GridViewsOf;
  for VRow in FOrder do
    if (VRow.Kind = frkGraphical) and SameText(VRow.TableName, FSource.TableName) then
      for VPlace in GridPlaces(VRow, VViews) do
        PlanGridColumn(VRow, VPlace);
end;

{ ---- removed fields ---- }

{ True when a string of the DFM names a field: the name as a word (a `;` list, an expression, a filter). In a SQL text
  only a parameter of that name counts: it is filled from the field of a master dataset. }
function NamesField(const pString: TDfmwString; const pFieldName: string): Boolean;
var
  VName, VProp: string;
begin
  if MatchText(pString.Prop, UNBOUND_PROPS) then
    Exit(False);
  for VProp in pString.ItemProp.Split(['.']) do
    if MatchText(VProp, UNBOUND_PROPS) then
      Exit(False);
  VName := TRegEx.Escape(pFieldName) + '(?!\w)';
  VName := (if ContainsText(pString.ItemProp, 'SQL') or ContainsText(pString.ItemProp, 'CommandText') then ':(OLD_|NEW_)?' else '(?<!\w)') + VName;
  Result := TRegEx.IsMatch(pString.Text, VName, [roIgnoreCase]);
end;

{ Every place of the form that binds the field by its name. A persistent field of another dataset only has the same name. }
function BindingsIn(pDoc: TDfmDocument; const pComponent, pFieldName: string; const pSkip: TArray<string>): string;
var
  VString: TDfmwString;
  VObject: TDfmwObject;
  VPlaces: TArray<string>;
begin
  VPlaces := nil;
  for VString in pDoc.Strings do
  begin
    VObject := pDoc.Objects[VString.ObjectIndex];
    { a grid item that is removed with the field }
    if MatchText(VObject.Name, pSkip) and SameText(VString.ItemProp, PROP_BINDING) then
      Continue;
    if SameText(VObject.Name, pComponent) or (EndsText('Field', VObject.ObjClass)
      and MatchText(VString.ItemProp, [PROP_FIELD_NAME, 'Origin'])) or not NamesField(VString, pFieldName) then
      Continue;
    VPlaces := VPlaces + [VObject.Name + '.' + VString.ItemProp];
  end;
  Result := string.Join(', ', VPlaces);
end;

{ Why the form or its unit still needs the component. }
function TDfmWritePlanner.DeleteBlockReason(const pField: TDfmrField; const pItems: TArray<string>): string;
var
  VRefs: TArray<string>;
  VDeclared: Integer;
begin
  Result := '';
  if not IsOwn(pField) then
    Exit('the field is declared in the ancestor''s DFM');
  VRefs := FDoc.ReferencesTo(pField.CompName);
  if Length(VRefs) > 0 then
    Exit('used in the DFM: ' + string.Join(', ', VRefs));
  Result := BindingsIn(FDoc, pField.CompName, pField.FieldName, pItems);
  if Result <> '' then
    Exit('the DFM names ' + QuotedStr(pField.FieldName) + ': ' + Result);
  if FUnit = nil then
    Exit;
  VDeclared := if IndexOfDecl(FUnit.Declarations(FForm.FormClass), pField.CompName) >= 0 then 1 else 0;
  if FUnit.Mentions(pField.CompName) > VDeclared then
    Result := 'used in the code of the unit'
  else if FUnit.NamesInString(pField.FieldName) then
    Result := 'the unit names ' + QuotedStr(pField.FieldName);
end;

{ Why the form or its unit still needs a grid or layout item. }
function TDfmWritePlanner.ItemDeleteReason(const pName: string): string;
var
  VRefs: TArray<string>;
  VDeclared: Integer;
begin
  Result := '';
  VRefs := FDoc.ReferencesTo(pName);
  if Length(VRefs) > 0 then
    Exit('used in the DFM: ' + string.Join(', ', VRefs));
  if FUnit = nil then
    Exit;
  VDeclared := if IndexOfDecl(FUnit.Declarations(FForm.FormClass), pName) >= 0 then 1 else 0;
  if FUnit.Mentions(pName) > VDeclared then
    Result := 'used in the code of the unit';
end;

{ The DevExpress grid and layout items bound to a field of the dataset: DataBinding.FieldName = the field, inside an
  object whose DataController.DataSource is a data source of the dataset (a view, a tree list). }
function TDfmWritePlanner.BoundItems(const pFieldName: string): TArray<Integer>;
var
  VSources: TArray<string>;
  VI, VParent: Integer;
  VText: string;
begin
  Result := nil;
  VSources := nil;
  for VI := 0 to High(FDoc.Objects) do
    if FDoc.TryProp(VI, 'DataSet', VText) and SameText(VText, FDataset.Name) then
      VSources := VSources + [FDoc.Objects[VI].Name];
  for VI := 0 to High(FDoc.Objects) do
    if StartsText(CX_PREFIX, FDoc.Objects[VI].ObjClass) and FDoc.TryProp(VI, PROP_BINDING, VText) and SameText(VText, pFieldName) then
    begin
      VParent := FDoc.Objects[VI].Parent;
      while VParent >= 0 do
        if FDoc.TryProp(VParent, PROP_DATASOURCE, VText) and MatchText(VText, VSources) then
        begin
          Result := Result + [VI];
          Break;
        end
        else
          VParent := FDoc.Objects[VParent].Parent;
    end;
end;

{ A removed field takes its grid and layout items with it (Q3(2), 1.55): each is an unchecked delete of its own that the
  field's delete needs; one that cannot go blocks the field. }
procedure TDfmWritePlanner.PlanDelete(const pField: TDfmrField);
var
  VItem, VBound: TDfmwItem;
  VIndex, VObject, VId: Integer;
  VReason, VItemReason: string;
  VNames: TArray<string>;
begin
  VNames := nil;
  VItemReason := '';
  VItem := NewItem(dwaDelete, pField.CompName, pField.FieldClass);
  VItem.FieldName := pField.FieldName;
  for VObject in BoundItems(pField.FieldName) do
  begin
    VBound := NewItem(dwaDelete, FDoc.Objects[VObject].Name, FDoc.Objects[VObject].ObjClass);
    VBound.Dataset := FDoc.Objects[FDoc.Objects[VObject].Parent].Name;
    VBound.Siblings := nil;
    try
      VReason := BdeBlockReason;
      if VReason = '' then
        VReason := ItemDeleteReason(VBound.Component);
    except
      on E: EDfmWriteError do
        VReason := E.Message;
    end;
    VId := AddItem(VBound, fcoDelete, VBound.FieldClass + '; ' + PROP_BINDING + ' = ' + QuotedStr(pField.FieldName), '');
    FChanges.List[VId].Checked := False;
    Block(VId, VReason);
    if (FChanges[VId].Blocked <> '') and (VItemReason = '') then
      VItemReason := 'its grid item ' + VBound.Component + ' cannot be removed: ' + FChanges[VId].Blocked;
    VItem.Requires := VItem.Requires + [VId + 1];
    VNames := VNames + [VBound.Component];
  end;
  try
    VReason := if VItemReason <> '' then VItemReason else DeleteBlockReason(pField, VNames);
  except
    on E: EDfmWriteError do
      VReason := E.Message;
  end;
  VIndex := AddItem(VItem, fcoDelete, pField.FieldClass + '; FieldName = ' + QuotedStr(pField.FieldName), '');
  FChanges.List[VIndex].Checked := False;

  Block(VIndex, VReason);
end;

procedure TDfmWritePlanner.PlanSelection(const pFields: TArray<string>);
var
  VAll: TArray<TFrSelectionField>;
  VItem: TFrSelectionField;
  VRow: TRepoField;
  VWanted: TArray<string>;
  VField: TDfmrField;
  VTable, VColumn: string;
  VId: Integer;
  VPass: Boolean;
  VPlanned: TPlannedField;
begin
  VAll := nil;
  for VRow in FOrder do
    if SameText(VRow.TableName, FSource.TableName) and (VRow.Kind <> frkGraphical) then
    begin
      VItem.Name := VRow.FieldName;
      VItem.Kind := VRow.Kind;
      VItem.SourceKey := VRow.SourceKey;
      VItem.Body := VRow.Body;
      VAll := VAll + [VItem];
    end;
  VWanted := nil;
  if (Length(pFields) = 1) and SameText(pFields[0], ALL_FIELDS) then
    for VItem in VAll do
      VWanted := VWanted + [VItem.Name]
  else
    VWanted := ExpandSelection(pFields, VAll);
  { lookups last: they need the field names of their keys }
  for VPass := False to True do
    for VRow in FOrder do
      if SameText(VRow.TableName, FSource.TableName) and MatchText(VRow.FieldName, VWanted)
        and ((VRow.Kind = frkLookup) = VPass) and (PlannedName(VRow.FieldName, VId) = '') then
        PlanInsert(VRow);
  { a field the selection adds brings its events (Q1 A) }
  for VPlanned in FPlanned.ToArray do
    if (VPlanned.ChangeId > 0) and FRows.TryGetValue(KeyOf(FSource.TableName, VPlanned.Column), VRow) then
      PlanEvents(FItems[VPlanned.ChangeId - 1].Component, FItems[VPlanned.ChangeId - 1].FieldClass, nil, VRow, [VPlanned.ChangeId]);
  for VField in FDataset.Fields do
    if FieldSource(FSource, VField, VTable, VColumn) and SameText(VTable, FSource.TableName) and (not MatchText(VColumn, VWanted)) then
      PlanDelete(VField);
end;

{ ---- datasets ---- }

procedure TDfmWritePlanner.Report;
var
  VReport: TDfmrDatasetReport;
  VField: TDfmrField;
  VTable, VColumn: string;
begin
  VReport := Default(TDfmrDatasetReport);
  VReport.DfmName := ExtractFileName(FForm.FileName);
  VReport.Dataset := FDataset.Name;
  VReport.DatasetClass := FDataset.DatasetClass;
  VReport.TableName := FSource.TableName;
  if FSource.TableName = '' then
    VReport.Unresolved := FSource.Reason;
  for VField in FDataset.Fields do
  begin
    Inc(VReport.Counts[VField.Kind]);
    if not FieldSource(FSource, VField, VTable, VColumn) then
      VReport.Unattributed := VReport.Unattributed + [VField.FieldName]
    else if not FRows.ContainsKey(KeyOf(VTable, VColumn)) then
      FWarnings.Add(Where(VField) + ': ' + VTable + '.' + VColumn + ' is not in the repository');
  end;
  if Length(FDataset.InheritedFields) > 0 then
    FWarnings.Add(Format('%s %s: %d inherited fields not written (FieldName is in the ancestor''s DFM): %s',
      [VReport.DfmName, FDataset.Name, Length(FDataset.InheritedFields), string.Join(', ', FDataset.InheritedFields)]));
  FPlan.Datasets := FPlan.Datasets + [VReport];
end;

{ The first persistent field of a dataset is never checked: from then on only persistent fields exist at run time. }
procedure TDfmWritePlanner.UncheckFirstFields(pFirst: Integer);
var
  VI: Integer;
  VAny: Boolean;
begin
  VAny := False;
  for VI := pFirst to FChanges.Count - 1 do
    if (FItems[VI].Action = dwaInsert) and (FChanges[VI].Blocked = '') then
    begin
      FChanges.List[VI].Checked := False;
      VAny := True;
    end;
  if VAny then
    FWarnings.Add(Format('%s %s: has no persistent field. With the first one only persistent fields exist at run time: the other ' +
      'dynamic fields vanish, code and controls that name them fail. The added fields are unchecked',
      [ExtractFileName(FForm.FileName), FDataset.Name]));
end;

procedure TDfmWritePlanner.PlanDataset(const pFields: TArray<string>);
var
  VField: TDfmrField;
  VRow: TRepoField;
  VPlanned: TPlannedField;
  VTable, VColumn: string;
  VFirst, VI: Integer;
begin
  FSource := SourceOf(FDataset);
  FPlanned.Clear;
  Report;
  VPlanned.ChangeId := 0;
  for VField in FDataset.Fields do
    if FieldSource(FSource, VField, VTable, VColumn) then
    begin
      if SameText(VTable, FSource.TableName) then
      begin
        VPlanned.Column := VColumn;
        VPlanned.Name := VField.FieldName;
        FPlanned.Add(VPlanned);
      end;
      if FRows.TryGetValue(KeyOf(VTable, VColumn), VRow) then
      begin
        TryPlanField(VField, VRow);
        PlanEvents(VField.CompName, VField.FieldClass, VField.Events, VRow, nil);
      end;
    end;
  PlanGridColumns;
  if Length(pFields) = 0 then
    Exit;
  if FSource.TableName = '' then
    raise EDfmWriteSelection.CreateFmt('%s has no table: %s', [FDataset.Name, FSource.Reason]);
  VFirst := FChanges.Count;
  PlanSelection(pFields);
  if (Length(FDataset.Fields) = 0) and (Length(FDataset.InheritedFields) = 0) then
    UncheckFirstFields(VFirst);
  { a field that would be removed gets no property changes }
  for VI := VFirst to FChanges.Count - 1 do
    if FItems[VI].Action = dwaDelete then
      for var VJ := 0 to VFirst - 1 do
        if SameText(FItems[VJ].Component, FItems[VI].Component) and (FItems[VJ].FileIndex = FFileIndex)
          and SameText(FItems[VJ].Dataset, FDataset.Name) then
          Block(VJ, 'the field is not in the selection');
end;

{ Full paths; a file given twice stays once. }
function UniquePaths(const pFiles: TArray<string>): TArray<string>;
var
  VFile: string;
begin
  Result := nil;
  for VFile in pFiles do
    if not MatchText(TPath.GetFullPath(VFile), Result) then
      Result := Result + [TPath.GetFullPath(VFile)];
end;

function TDfmWritePlanner.Execute(const pFiles: TArray<string>; const pDataset: string; const pFields: TArray<string>): TDfmwPlan;
var
  VFile: string;
  VDataset: TDfmrDataset;
begin
  FPlan := Default(TDfmwPlan);
  FPlan.ChangeSet.Direction := fdRepoToDfm;
  if (Length(pFields) > 0) and ((pDataset = '') or (Length(pFiles) <> 1)) then
    raise EDfmWriteSelection.Create('a field selection needs one form and one dataset');
  LoadRows;
  FGridTable := RepoSchemaVersion(FRepo) >= SCHEMA_WITH_GRID;
  for VFile in UniquePaths(pFiles) do
  begin
    OpenForm(VFile);
    for VDataset in FForm.Datasets do
      if (pDataset = '') or SameText(pDataset, VDataset.Name) then
      begin
        FDataset := VDataset;
        PlanDataset(pFields);
      end;
  end;
  if (pDataset <> '') and (Length(FPlan.Datasets) = 0) then
    raise EDfmReadError.CreateFmt('no dataset %s in the DFM', [pDataset]);
  FPlan.ChangeSet.Changes := FChanges.ToArray;
  FPlan.Items := FItems.ToArray;
  FPlan.Warnings := FWarnings.ToStringArray;
  FPlan.PlanId := PlanId;
  Result := FPlan;
end;

function PlanDfmWrite(pRepo: TFDConnection; const pFiles: TArray<string>; const pDataset: string;
  const pFields: TArray<string>; pBde: TDfmwBdePolicy): TDfmwPlan;
var
  VPlanner: TDfmWritePlanner;
begin
  if RepoSchemaVersion(pRepo) < SCHEMA_WITH_BODIES then
    raise ERepoError.Create('the repository is schema 1: run repo migrate first');
  VPlanner := TDfmWritePlanner.Create(pRepo, pBde);
  try
    Result := VPlanner.Execute(pFiles, pDataset, pFields);
  finally
    VPlanner.Free;
  end;
end;

{ ---- render ---- }

function IdChosen(const pChosen: TArray<TFrChange>; pId: Integer): Boolean;
var
  VChange: TFrChange;
begin
  Result := False;
  for VChange in pChosen do
    if VChange.Id = pId then
      Exit(True);
end;

{ Refuses a blocked change, one chosen twice, and one whose needed change is not chosen. }
procedure CheckChosen(const pPlan: TDfmwPlan; const pChosen: TArray<TFrChange>);
var
  VChange: TFrChange;
  VNeeded: Integer;
  VMissing: TArray<string>;
  VSeen: TDictionary<Integer, Boolean>;
begin
  VSeen := TDictionary<Integer, Boolean>.Create;
  try
    for VChange in pChosen do
    begin
      if pPlan.ChangeSet.Changes[VChange.Id - 1].Blocked <> '' then
        raise EDfmWriteError.CreateFmt('change %d is blocked: %s', [VChange.Id, pPlan.ChangeSet.Changes[VChange.Id - 1].Blocked]);
      if not VSeen.TryAdd(VChange.Id, True) then
        raise EDfmWriteError.CreateFmt('change %d is chosen twice', [VChange.Id]);
      VMissing := nil;
      for VNeeded in pPlan.Items[VChange.Id - 1].Requires do
        if not IdChosen(pChosen, VNeeded) then
          VMissing := VMissing + [IntToStr(VNeeded)];
      if Length(VMissing) > 0 then
        raise EDfmWriteSelection.CreateFmt(if Length(VMissing) = 1 then 'change %d needs change %s (select it too)'
          else 'change %d needs changes %s (select them too)', [VChange.Id, string.Join(', ', VMissing)]);
    end;
  finally
    VSeen.Free;
  end;
end;

{ A deleted field was bound nowhere before: a binding in the new text is from a change of the same selection. }
procedure CheckDeleted(pDoc: TDfmDocument; const pFile: TDfmwFile; const pItem: TDfmwItem);
var
  VPlaces: string;
begin
  VPlaces := if pItem.FieldName = '' then '' else BindingsIn(pDoc, pItem.Component, pItem.FieldName, nil);
  if VPlaces <> '' then
    raise EDfmWriteSelection.CreateFmt('%s: the selection deletes %s, but the form would still name %s: %s',
      [ExtractFileName(pFile.DfmName), pItem.Component, QuotedStr(pItem.FieldName), VPlaces]);
end;

{ Reads the new DFM back: the RTL converts it and every planned change is there. }
procedure CheckDfm(const pBytes: TBytes; const pFile: TDfmwFile; const pItems: TArray<TDfmwItem>);
var
  VDoc: TDfmDocument;
  VItem: TDfmwItem;
  VObject: Integer;
  VText: string;
  VOk: Boolean;
begin
  VDoc := TDfmDocument.Create(pBytes, ExtractFileName(pFile.DfmName) + ' (as it would be written)');
  try
    for VItem in pItems do
    begin
      VObject := VDoc.FindObject(VItem.Component, VItem.Dataset);
      VOk := (VObject >= 0) <> (VItem.Action = dwaDelete);
      if VOk and (VItem.Action in [dwaSet, dwaEvent]) then
        VOk := VDoc.TryProp(VObject, VItem.PropName, VText) and (VText = DfmLiteralText(VItem.Literal))
      else if VOk and (VItem.Action = dwaRemove) then
        VOk := not VDoc.TryProp(VObject, VItem.PropName, VText);
      if not VOk then
        raise EDfmWriteError.CreateFmt('%s: the change of %s does not read back', [ExtractFileName(pFile.DfmName), VItem.Component]);
      if VItem.Action = dwaDelete then
        CheckDeleted(VDoc, pFile, VItem);
    end;
  finally
    VDoc.Free;
  end;
end;

{ Reads the new unit back: every added field is declared, every removed one is not. }
procedure CheckUnit(const pBytes: TBytes; const pFile: TDfmwFile; const pItems: TArray<TDfmwItem>);
var
  VUnit: TDfmUnitDocument;
  VItem: TDfmwItem;
  VDecls: TArray<TDfmwDecl>;
begin
  VUnit := TDfmUnitDocument.Create(pBytes, ExtractFileName(pFile.PasName) + ' (as it would be written)');
  try
    VDecls := VUnit.Declarations(pFile.FormClass);
    for VItem in pItems do
      if (VItem.Action in [dwaInsert, dwaDelete]) and ((IndexOfDecl(VDecls, VItem.Component) >= 0) <> (VItem.Action = dwaInsert)) then
        raise EDfmWriteError.CreateFmt('%s: the declaration of %s does not read back', [ExtractFileName(pFile.PasName), VItem.Component])
      else if (VItem.Action = dwaEvent) and (VUnit.Mentions(VItem.Literal) < 2) then
        raise EDfmWriteError.CreateFmt('%s: the handler %s does not read back', [ExtractFileName(pFile.PasName), VItem.Literal]);
  finally
    VUnit.Free;
  end;
end;

procedure AddOutput(var pOutputs: TArray<TDfmwOutput>; const pFileName: string; const pOld, pNew: TBytes);
var
  VOutput: TDfmwOutput;
begin
  VOutput.FileName := pFileName;
  VOutput.OldBytes := pOld;
  VOutput.NewBytes := pNew;
  pOutputs := pOutputs + [VOutput];
end;

procedure RenderFile(const pFile: TDfmwFile; const pItems: TArray<TDfmwItem>; var pOutputs: TArray<TDfmwOutput>);
var
  VDfm, VPas: TBytes;
  VUnitChanges: Boolean;
begin
  VUnitChanges := RenderBytes(pFile, pItems, VDfm, VPas);
  CheckDfm(VDfm, pFile, pItems);
  AddOutput(pOutputs, pFile.DfmName, pFile.DfmBytes, VDfm);
  if not VUnitChanges then
    Exit;
  CheckUnit(VPas, pFile, pItems);
  AddOutput(pOutputs, pFile.PasName, pFile.PasBytes, VPas);
end;

function RenderDfmWrite(const pPlan: TDfmwPlan; const pChosen: TArray<TFrChange>): TArray<TDfmwOutput>;
var
  VI: Integer;
  VChange: TFrChange;
  VItems: TArray<TDfmwItem>;
begin
  Result := nil;
  CheckChosen(pPlan, pChosen);
  for VI := 0 to High(pPlan.Files) do
  begin
    VItems := nil;
    for VChange in pChosen do
      if pPlan.Items[VChange.Id - 1].FileIndex = VI then
        VItems := VItems + [pPlan.Items[VChange.Id - 1]];
    if Length(VItems) > 0 then
      RenderFile(pPlan.Files[VI], VItems, Result);
  end;
end;

{ ---- write ---- }

function ApplyDfmWrite(const pPlan: TDfmwPlan; const pChosen: TArray<TFrChange>): TArray<string>;
var
  VChange: TFrChange;
  VBackup: string;
  VBackups: TArray<string>;
begin
  Result := nil;
  VBackups := WriteOutputs(RenderDfmWrite(pPlan, pChosen));
  for VChange in pChosen do
    Result := Result + [ApplyLogLine(VChange)];
  for VBackup in VBackups do
    Result := Result + ['backup ' + VBackup];
end;

end.
