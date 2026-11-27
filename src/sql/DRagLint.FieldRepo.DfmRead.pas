unit DRagLint.FieldRepo.DfmRead;

{ drag-lint 1.54 -- lane TT-DFMREAD: the datasets, persistent fields, data sources and grid columns of one DFM as records (design
  2026-11-22-field-repository-v2-design.md section 9, plan 2026-11-23-fr-dfmread.md). The DFM is read with the
  producers of the index's dfm_objects / dfm_properties rows (DRagLint.Parser.DFM / DFMProps); a binary DFM is
  converted to text in memory first. Nothing is written and no repository is needed. }

interface

uses
  System.SysUtils,
  DRagLint.FieldRepo.Kinds;  // dl:ok uses-global-census@379a -- REVIEWED 2026-11-24 INT-W2: FR_EVENT_COLUMNS is the one list of event columns

type
  /// <summary>Raised when a DFM cannot be read (missing file, no object in it).</summary>
  EDfmReadError = class(Exception);

  /// <summary>A name and its text value.</summary>
  TDfmrPair = record
    /// <summary>Repository column or event name.</summary>
    Name: string;
    /// <summary>The value as the repository stores it, or the handler name of an event.</summary>
    Value: string;
  end;

  /// <summary>One persistent field.</summary>
  TDfmrField = record
    /// <summary>Component name, e.g. tblOrdersQTY.</summary>
    CompName: string;
    /// <summary>FieldName property as written.</summary>
    FieldName: string;
    /// <summary>Component class, e.g. TIntegerField.</summary>
    FieldClass: string;
    /// <summary>Kind from FieldKind (or the legacy Calculated / Lookup properties, or TAggregateField).</summary>
    Kind: TFrFieldKind;
    /// <summary>Lookup: KeyFields, LookupDataSet, LookupKeyFields, LookupResultField.</summary>
    KeyFields: string;
    LookupDataSet: string;
    LookupKeyFields: string;
    LookupResult: string;
    /// <summary>Aggregate expression (TAggregateField.Expression).</summary>
    Expression: string;
    /// <summary>Origin property; '' = none.</summary>
    Origin: string;
    /// <summary>Hand-kept DL_FIELDS_INFO columns the DFM states (DISPLAY_LABEL, VISIBLE, ...).</summary>
    Stated: TArray<TDfmrPair>;
    /// <summary>Schema-derived columns the class implies (FIELD_AS_TYPE, VAR_TYPE, STRING_SIZE): for a NEW row only.</summary>
    Typed: TArray<TDfmrPair>;
    /// <summary>Assigned field events: event name, handler name.</summary>
    Events: TArray<TDfmrPair>;
  end;

  /// <summary>One dataset component.</summary>
  TDfmrDataset = record
    /// <summary>Component name.</summary>
    Name: string;
    /// <summary>Component class, e.g. TTable, TQuery, TFDQuery.</summary>
    DatasetClass: string;
    /// <summary>object, inherited or inline.</summary>
    ObjKind: string;
    /// <summary>UpdateOptions.UpdateTableName; '' = none.</summary>
    UpdateTableName: string;
    /// <summary>TableName; '' = none.</summary>
    TableName: string;
    /// <summary>SQL.Strings joined; '' = none.</summary>
    Sql: string;
    /// <summary>OnCalcFields handler name; '' = none.</summary>
    OnCalcFields: string;
    /// <summary>kbmMemTable AttachedTo as written (the dataset whose data it shares); '' = none (design
    /// 2026-11-26-cross-table-fields 3.1).</summary>
    AttachedTo: string;
    /// <summary>Persistent fields in DFM order.</summary>
    Fields: TArray<TDfmrField>;
    /// <summary>Fields this DFM only overrides: their FieldName is in the ancestor's DFM, so they are not read.</summary>
    InheritedFields: TArray<string>;
  end;

  /// <summary>Family of a data-aware cxGrid view.</summary>
  /// <remarks>dvkTable = TcxGridDBTableView, dvkBanded = TcxGridDBBandedTableView, dvkOther = card, layout, ...</remarks>
  TDfmrViewKind = (dvkTable, dvkBanded, dvkOther);

  /// <summary>One column of a grid view.</summary>
  TDfmrGridColumn = record
    /// <summary>Component name.</summary>
    Name: string;
    /// <summary>DataBinding.FieldName as written; '' = unbound.</summary>
    FieldName: string;
    /// <summary>Assigned column events that have a repository column: event name, handler name.</summary>
    Events: TArray<TDfmrPair>;
    /// <summary>PropertiesClassName as written, without the quotes (TcxComboBoxProperties); '' = not stated.</summary>
    PropertiesClassName: string;
    /// <summary>The column's Properties.* lines as the text DFM has them (a binary DFM: as its text form has them), in
    /// DFM order, CRLF between lines, the indentation of the first line removed from every line; a value over several
    /// lines (collection, string list, continued string) is whole. '' = none. The format of TFrGridColumn.Properties.</summary>
    Properties: string;
  end;

  /// <summary>One data-aware cxGrid view.</summary>
  TDfmrGridView = record
    /// <summary>Component name and class.</summary>
    Name: string;
    ViewClass: string;
    /// <summary>Family; only table and banded views have Columns.</summary>
    Kind: TDfmrViewKind;
    /// <summary>object, inherited or inline.</summary>
    ObjKind: string;
    /// <summary>DataController.DataSource as written (dsX or dmX.dsX); '' = none.</summary>
    DataSource: string;
    /// <summary>Columns in item order: DFM order, a column that states Index moved there as it is when the form loads.</summary>
    Columns: TArray<TDfmrGridColumn>;
  end;

  /// <summary>One DFM.</summary>
  TDfmrForm = record
    /// <summary>Full path of the DFM.</summary>
    FileName: string;
    /// <summary>Root object name and class.</summary>
    FormName: string;
    FormClass: string;
    /// <summary>True when the file is a binary DFM.</summary>
    IsBinary: Boolean;
    /// <summary>Datasets in DFM order.</summary>
    Datasets: TArray<TDfmrDataset>;
    /// <summary>TDataSource components: component name, DataSet property as written.</summary>
    DataSources: TArray<TDfmrPair>;
    /// <summary>Data-aware cxGrid views in DFM order.</summary>
    Views: TArray<TDfmrGridView>;
    /// <summary>Every component name of the form (the persistent fields included).</summary>
    Components: TArray<string>;
    /// <summary>Parse problems; the rows around them may be missing.</summary>
    Diagnostics: TArray<string>;
  end;

/// <summary>Reads one DFM, text or binary.</summary>
/// <param name="pFile">Path of the DFM.</param>
/// <returns>The form.</returns>
/// <exception cref="EDfmReadError">The file does not exist, is an unreadable binary DFM, or holds no object.</exception>
/// <remarks>Read only.</remarks>
function LoadDfmForm(const pFile: string): TDfmrForm;

/// <summary>Root object name of a DFM without reading all of it ('' when there is none).</summary>
/// <param name="pFile">Path of an existing DFM.</param>
/// <returns>The root object name.</returns>
function DfmRootName(const pFile: string): string;

/// <summary>True for a dataset class read-dfm knows by name (TTable, TFDQuery, TClientDataSet, ...).</summary>
/// <param name="pClass">Component class name, case-insensitive.</param>
/// <returns>True when the class is in the list. A component of another class is still a dataset when it has a
/// persistent field child (IsPersistentFieldClass with pOwnerIsDataset False).</returns>
/// <remarks>1.56 GCR-2: the one list; the index (DRagLint.Index.RepoCopy) asks here.</remarks>
function IsDatasetClass(const pClass: string): Boolean;

/// <summary>True when a child object of that class is a persistent field.</summary>
/// <param name="pClass">Class name of the child object.</param>
/// <param name="pOwnerIsDataset">The parent has a known dataset class (IsDatasetClass).</param>
/// <returns>True for a class ending in `Field` that is a known TField class, or any class ending in `Field` under a
/// known dataset class.</returns>
function IsPersistentFieldClass(const pClass: string; pOwnerIsDataset: Boolean): Boolean;

/// <summary>The kind of a persistent field from what its DFM object states.</summary>
/// <param name="pFieldClass">Class name of the field object.</param>
/// <param name="pFieldKind">Its FieldKind property as written (fkData, fkLookup, ...); '' = not stated.</param>
/// <param name="pLookup">Its legacy Lookup property as written; '' = not stated.</param>
/// <param name="pCalculated">Its legacy Calculated property as written; '' = not stated.</param>
/// <returns>The kind FieldKind names; without one frkAggregate for TAggregateField, frkLookup for Lookup = True,
/// frkCalc for Calculated = True, else frkData.</returns>
function DfmFieldKind(const pFieldClass, pFieldKind, pLookup, pCalculated: string): TFrFieldKind;

/// <summary>The typed accessor of a TField class (AsInteger, AsString, ...).</summary>
/// <param name="pFieldClass">A TField class name.</param>
/// <returns>The accessor, '' for a class without one.</returns>
function FieldClassAccessor(const pFieldClass: string): string;  // dl:ok unused-public-symbol@bd89 -- REVIEWED 2026-11-23 EVCOLS: lane DFMWRITE checks its class map against it (tests/fieldrepo/DfmWriteTests.dpr); outside this project index

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Core.Encoding,
  DRagLint.Parser.DFM,
  DRagLint.Parser.DFMProps;

type
  TFieldClassInfo = record
    ClassName: string;
    Accessor: string;
    VarType: string;
  end;

  { The DFM rows plus the object each row belongs to. }
  TDfmRows = record
    Objects: TArray<TDfmObjectRow>;
    Props: TArray<TDfmPropertyRow>;
    { First property row of each object, -1 = none; an object's own rows are one run (a DFM streams the properties
      of an object before its child objects). }
    First: TArray<Integer>;
    { The lines of the DFM text the rows were read from, without their line ends; a row's StartLine is 1-based. }
    Lines: TArray<string>;
    procedure BuildFirst;
    function Prop(pObject: Integer; const pName: string): string;
    function ListText(pRow: Integer): string;
  end;

const
  SIGNATURE = 'TPF0';
  RESOURCE_BYTE = $FF; // first byte of the resource header a binary DFM may start with
  SIGNATURE_SCAN = 256; // a binary DFM resource header (class name included) is shorter than this
  KIND_LIST = 'list';
  FIELD_SUFFIX = 'Field';
  AGGREGATE_CLASS = 'TAggregateField';
  PROP_FIELD_NAME = 'FieldName';
  PROP_EDITOR_CLASS = 'PropertiesClassName';
  EDITOR_PREFIX = 'Properties.';
  VALUE_TRUE = 'True';
  LIST_BREAK = #13#10;

  DATASET_CLASSES: array[0..19] of string = ('TTable', 'TQuery', 'TStoredProc', 'TFDTable', 'TFDQuery', 'TFDMemTable',
    'TFDStoredProc', 'TClientDataSet', 'TdxMemData', 'TADOTable', 'TADOQuery', 'TADODataSet', 'TADOStoredProc',
    'TIBTable', 'TIBQuery', 'TIBDataSet', 'TSQLDataSet', 'TSQLQuery', 'TSQLTable', 'TSimpleDataSet');

  FIELD_CLASSES: array[0..32] of TFieldClassInfo = (
    (ClassName: 'TIntegerField'; Accessor: 'AsInteger'; VarType: 'integer'),
    (ClassName: 'TSmallintField'; Accessor: 'AsInteger'; VarType: 'integer'),
    (ClassName: 'TShortintField'; Accessor: 'AsInteger'; VarType: 'integer'),
    (ClassName: 'TByteField'; Accessor: 'AsInteger'; VarType: 'integer'),
    (ClassName: 'TWordField'; Accessor: 'AsInteger'; VarType: 'integer'),
    (ClassName: 'TAutoIncField'; Accessor: 'AsInteger'; VarType: 'integer'),
    (ClassName: 'TFDAutoIncField'; Accessor: 'AsInteger'; VarType: 'integer'),
    (ClassName: 'TLongWordField'; Accessor: 'AsLongWord'; VarType: 'Cardinal'),
    (ClassName: 'TLargeintField'; Accessor: 'AsLargeInt'; VarType: 'Int64'),
    (ClassName: 'TFloatField'; Accessor: 'AsFloat'; VarType: 'double'),
    (ClassName: 'TCurrencyField'; Accessor: 'AsFloat'; VarType: 'double'),
    (ClassName: 'TSingleField'; Accessor: 'AsSingle'; VarType: 'double'),
    (ClassName: 'TExtendedField'; Accessor: 'AsExtended'; VarType: 'Extended'),
    (ClassName: 'TBCDField'; Accessor: 'AsCurrency'; VarType: 'Currency'),
    (ClassName: 'TFMTBCDField'; Accessor: 'AsBCD'; VarType: 'TBCD'),
    (ClassName: 'TStringField'; Accessor: 'AsString'; VarType: 'string'),
    (ClassName: 'TWideStringField'; Accessor: 'AsString'; VarType: 'string'),
    (ClassName: 'TGuidField'; Accessor: 'AsString'; VarType: 'string'),
    (ClassName: 'TMemoField'; Accessor: 'AsString'; VarType: 'TStringList'),
    (ClassName: 'TWideMemoField'; Accessor: 'AsString'; VarType: 'TStringList'),
    (ClassName: 'TBooleanField'; Accessor: 'AsBoolean'; VarType: 'Boolean'),
    (ClassName: 'TDateField'; Accessor: 'AsDateTime'; VarType: 'TDateTime'),
    (ClassName: 'TTimeField'; Accessor: 'AsDateTime'; VarType: 'TDateTime'),
    (ClassName: 'TDateTimeField'; Accessor: 'AsDateTime'; VarType: 'TDateTime'),
    (ClassName: 'TSQLTimeStampField'; Accessor: 'AsSQLTimeStamp'; VarType: 'TSQLTimeStamp'),
    (ClassName: 'TSQLTimeStampOffsetField'; Accessor: 'AsSQLTimeStampOffset'; VarType: 'TSQLTimeStampOffset'),
    (ClassName: 'TBlobField'; Accessor: ''; VarType: ''),
    (ClassName: 'TGraphicField'; Accessor: ''; VarType: ''),
    (ClassName: 'TBinaryField'; Accessor: ''; VarType: ''),
    (ClassName: 'TBytesField'; Accessor: ''; VarType: ''),
    (ClassName: 'TVarBytesField'; Accessor: ''; VarType: ''),
    (ClassName: 'TVariantField'; Accessor: ''; VarType: ''),
    (ClassName: AGGREGATE_CLASS; Accessor: ''; VarType: ''));

  DATA_SOURCE_CLASS = 'TDataSource';
  VIEW_CLASS_PREFIX = 'TcxGridDB';
  VIEW_CLASS_SUFFIX = 'View';
  COLUMN_SUFFIX = 'Column';
  VIEW_CLASSES: array[dvkTable..dvkBanded] of string = ('TcxGridDBTableView', 'TcxGridDBBandedTableView');

  KIND_NAMES: array[TFrFieldKind] of string = ('fkData', 'fkCalculated', 'fkLookup', 'fkInternalCalc', 'fkAggregate', '');

  { TField property -> hand-kept DL_FIELDS_INFO column. ALIGNMENT holds Ord(TAlignment). }
  STATED_PROPS: array[0..5] of TDfmrPair = (
    (Name: 'DisplayLabel'; Value: 'DISPLAY_LABEL'), (Name: 'Visible'; Value: 'VISIBLE'),
    (Name: 'DisplayFormat'; Value: 'DISPLAY_FORMAT'), (Name: 'EditFormat'; Value: 'EDIT_FORMAT'),
    (Name: 'DisplayWidth'; Value: 'DISPLAY_WIDTH'), (Name: 'Alignment'; Value: 'ALIGNMENT'));
  ALIGNMENT_NAMES: array[0..2] of string = ('taLeftJustify', 'taRightJustify', 'taCenter');

procedure TDfmRows.BuildFirst;
var
  VI: Integer;
begin
  SetLength(First, Length(Objects));
  for VI := 0 to High(First) do
    First[VI] := -1;
  for VI := High(Props) downto 0 do
    if (Props[VI].ObjectOrdinal >= 0) and (Props[VI].ObjectOrdinal < Length(First)) then
      First[Props[VI].ObjectOrdinal] := VI;
end;

function TDfmRows.ListText(pRow: Integer): string;
var
  VI: Integer;
  VLines: TStringList;
begin
  VLines := TStringList.Create;
  try
    VLines.LineBreak := LIST_BREAK;
    VI := pRow + 1;
    while (VI < Length(Props)) and (Props[VI].Depth > Props[pRow].Depth) do
    begin
      if Props[VI].Parent = pRow then
        VLines.Add(Props[VI].ValueText);
      Inc(VI);
    end;
    Result := TrimRight(VLines.Text);
  finally
    VLines.Free;
  end;
end;

function TDfmRows.Prop(pObject: Integer; const pName: string): string;
var
  VI: Integer;
begin
  Result := '';
  VI := First[pObject];  // dl:ok index-possibly-out-of-range@e288 -- REVIEWED 2026-11-23 TT-DFMREAD: VI is tested against Length(Props) first; pRow / pObject are rows and object ordinals the caller enumerates (First has one entry per object)
  while (VI >= 0) and (VI < Length(Props)) and (Props[VI].ObjectOrdinal = pObject) do
  begin
    if (Props[VI].Depth = 0) and SameText(Props[VI].Name, pName) then
      Exit(if Props[VI].ValueKind = KIND_LIST then ListText(VI) else Props[VI].ValueText);
    Inc(VI);
  end;
end;

{ The bytes of a text DFM in UTF-8; a binary DFM is converted in memory. }
function DfmTextBytes(const pFile: string; out pBinary: Boolean): TBytes;
var
  VRaw: TBytes;
  VPos: Integer;
  VIn, VOut: TBytesStream;
begin
  if not TFile.Exists(pFile) then
    raise EDfmReadError.CreateFmt('the DFM does not exist: %s', [pFile]);
  VRaw := TFile.ReadAllBytes(pFile);
  pBinary := (Length(VRaw) > 0) and ((VRaw[0] = RESOURCE_BYTE) or (VRaw[0] = Ord(SIGNATURE[1])));
  if not pBinary then
    Exit(EnsureUtf8Bytes(VRaw));
  VPos := Pos(SIGNATURE, TEncoding.ASCII.GetString(VRaw, 0, Min(Length(VRaw), SIGNATURE_SCAN)));
  if VPos = 0 then
    raise EDfmReadError.CreateFmt('neither a text nor a binary DFM: %s', [pFile]);
  VIn := TBytesStream.Create(VRaw);
  VOut := TBytesStream.Create;
  try
    VIn.Position := VPos - 1;
    try
      ObjectBinaryToText(VIn, VOut);
    except
      on E: EStreamError do
        raise EDfmReadError.CreateFmt('unreadable binary DFM %s: %s', [pFile, E.Message]);
    end;
    Result := EnsureUtf8Bytes(Copy(VOut.Bytes, 0, VOut.Size));
  finally
    VOut.Free;
    VIn.Free;
  end;
end;

function LoadRows(const pFile: string; out pRows: TDfmRows; out pDiagnostics: TArray<string>): Boolean;
var
  VParser: TDFMParser;
  VResult: TParseResult;
  VBytes: TBytes;
  VText: string;
begin
  VBytes := DfmTextBytes(pFile, Result);
  VParser := TDFMParser.Create;
  try
    VResult := VParser.Parse(VBytes, pFile);
  finally
    VParser.Free;
  end;
  VText := TEncoding.UTF8.GetString(VBytes);
  pRows.Objects := VResult.DfmObjects;
  pRows.Props := ExtractDfmPropertyRows(pFile, VText, VResult.DfmObjects);
  pRows.Lines := VText.Replace(LIST_BREAK, #10).Split([#10]);
  pRows.BuildFirst;
  pDiagnostics := VResult.Diagnostics;
  if Length(pRows.Objects) = 0 then
    raise EDfmReadError.CreateFmt('no object in the DFM: %s', [pFile]);
end;

function FindFieldClass(const pFieldClass: string; out pInfo: TFieldClassInfo): Boolean;
var
  VInfo: TFieldClassInfo;
begin
  pInfo := Default(TFieldClassInfo);
  for VInfo in FIELD_CLASSES do
    if SameText(VInfo.ClassName, pFieldClass) then
    begin
      pInfo := VInfo;
      Exit(True);
    end;
  Result := False;
end;

function IsDatasetClass(const pClass: string): Boolean;
begin
  Result := MatchText(pClass, DATASET_CLASSES);
end;

function IsPersistentFieldClass(const pClass: string; pOwnerIsDataset: Boolean): Boolean;
var
  VInfo: TFieldClassInfo;
begin
  Result := EndsText(FIELD_SUFFIX, pClass) and (pOwnerIsDataset or FindFieldClass(pClass, VInfo));
end;

function FieldClassAccessor(const pFieldClass: string): string;
var
  VInfo: TFieldClassInfo;
begin
  FindFieldClass(pFieldClass, VInfo);
  Result := VInfo.Accessor;
end;

function DfmFieldKind(const pFieldClass, pFieldKind, pLookup, pCalculated: string): TFrFieldKind;
var
  VKind: TFrFieldKind;
begin
  for VKind := Low(TFrFieldKind) to High(TFrFieldKind) do
    if (pFieldKind <> '') and SameText(KIND_NAMES[VKind], pFieldKind) then
      Exit(VKind);
  Result := frkData;
  if SameText(pFieldClass, AGGREGATE_CLASS) then
    Result := frkAggregate
  else if SameText(pLookup, VALUE_TRUE) then
    Result := frkLookup
  else if SameText(pCalculated, VALUE_TRUE) then
    Result := frkCalc;
end;

function KindOf(const pRows: TDfmRows; pObject: Integer): TFrFieldKind;
begin
  Result := DfmFieldKind(pRows.Objects[pObject].ClassName, pRows.Prop(pObject, 'FieldKind'), pRows.Prop(pObject, 'Lookup'),
    pRows.Prop(pObject, 'Calculated'));
end;

procedure AddPair(var pList: TArray<TDfmrPair>; const pName, pValue: string);
var
  VPair: TDfmrPair;
begin
  VPair.Name := pName;
  VPair.Value := pValue;
  pList := pList + [VPair];
end;

function StatedPairs(const pRows: TDfmRows; pObject: Integer): TArray<TDfmrPair>;
var
  VPair: TDfmrPair;
  VText: string;
begin
  Result := nil;
  for VPair in STATED_PROPS do
  begin
    VText := pRows.Prop(pObject, VPair.Name);
    if (VText <> '') and (VPair.Value = 'ALIGNMENT') then
      VText := if MatchText(VText, ALIGNMENT_NAMES) then IntToStr(IndexText(VText, ALIGNMENT_NAMES)) else '';
    if VText <> '' then
      AddPair(Result, VPair.Value, VText);
  end;
end;

function TypedPairs(const pRows: TDfmRows; pObject: Integer): TArray<TDfmrPair>;
var
  VInfo: TFieldClassInfo;
  VSize: string;
begin
  Result := nil;
  if not FindFieldClass(pRows.Objects[pObject].ClassName, VInfo) then
    Exit;
  if VInfo.Accessor <> '' then
  begin
    AddPair(Result, 'FIELD_AS_TYPE', VInfo.Accessor);
    AddPair(Result, 'VAR_TYPE', VInfo.VarType);
  end;
  VSize := pRows.Prop(pObject, 'Size');
  if (VSize <> '') and (VInfo.Accessor = 'AsString') then
    AddPair(Result, 'STRING_SIZE', VSize);
end;

{ The assigned events that have a repository column. }
function ReadEvents(const pRows: TDfmRows; pObject: Integer; pGrid: Boolean): TArray<TDfmrPair>;
var
  VEvent: TFrEventColumn;
  VHandler: string;
begin
  Result := nil;
  for VEvent in FR_EVENT_COLUMNS do
  begin
    VHandler := if VEvent.IsGrid = pGrid then pRows.Prop(pObject, VEvent.Event) else '';
    if VHandler <> '' then
      AddPair(Result, VEvent.Event, VHandler);
  end;
end;

function ReadField(const pRows: TDfmRows; pObject: Integer): TDfmrField;
begin
  Result := Default(TDfmrField);
  Result.CompName := pRows.Objects[pObject].Name;
  Result.FieldClass := pRows.Objects[pObject].ClassName;
  Result.FieldName := pRows.Prop(pObject, PROP_FIELD_NAME);
  Result.Kind := KindOf(pRows, pObject);
  Result.KeyFields := pRows.Prop(pObject, 'KeyFields');
  Result.LookupDataSet := pRows.Prop(pObject, 'LookupDataSet');
  Result.LookupKeyFields := pRows.Prop(pObject, 'LookupKeyFields');
  Result.LookupResult := pRows.Prop(pObject, 'LookupResultField');
  Result.Expression := pRows.Prop(pObject, 'Expression');
  Result.Origin := pRows.Prop(pObject, 'Origin');
  Result.Stated := StatedPairs(pRows, pObject);
  Result.Typed := TypedPairs(pRows, pObject);
  Result.Events := ReadEvents(pRows, pObject, False);
end;

{ True when object pObject is a persistent field; pKnown = its parent has a known dataset class. }
function IsFieldObject(const pRows: TDfmRows; pObject: Integer; pKnown: Boolean): Boolean;
begin
  Result := IsPersistentFieldClass(pRows.Objects[pObject].ClassName, pKnown);
end;

procedure AddField(const pRows: TDfmRows; pObject: Integer; var pDataset: TDfmrDataset);
begin
  if pRows.Prop(pObject, PROP_FIELD_NAME) <> '' then
    pDataset.Fields := pDataset.Fields + [ReadField(pRows, pObject)]
  else if SameText(pRows.Objects[pObject].ObjKind, 'inherited') then
    pDataset.InheritedFields := pDataset.InheritedFields + [pRows.Objects[pObject].Name];
end;

function ReadDataset(const pRows: TDfmRows; pObject: Integer; out pIsDataset: Boolean): TDfmrDataset;
var
  VI: Integer;
  VKnown: Boolean;
begin
  Result := Default(TDfmrDataset);
  VKnown := IsDatasetClass(pRows.Objects[pObject].ClassName);
  VI := pObject + 1;
  while (VI < Length(pRows.Objects)) and (pRows.Objects[VI].Depth > pRows.Objects[pObject].Depth) do
  begin
    if (pRows.Objects[VI].Depth = pRows.Objects[pObject].Depth + 1) and IsFieldObject(pRows, VI, VKnown) then
      AddField(pRows, VI, Result);
    Inc(VI);
  end;
  pIsDataset := VKnown or (Length(Result.Fields) > 0);
  if not pIsDataset then
    Exit;
  Result.Name := pRows.Objects[pObject].Name;
  Result.DatasetClass := pRows.Objects[pObject].ClassName;
  Result.ObjKind := pRows.Objects[pObject].ObjKind;
  Result.UpdateTableName := pRows.Prop(pObject, 'UpdateOptions.UpdateTableName');
  Result.TableName := pRows.Prop(pObject, 'TableName');
  Result.Sql := pRows.Prop(pObject, 'SQL.Strings');
  Result.OnCalcFields := pRows.Prop(pObject, 'OnCalcFields');
  Result.AttachedTo := pRows.Prop(pObject, 'AttachedTo');
end;

{ pLine without its first pIndent characters, as far as they are blanks. }
function Dedent(const pLine: string; pIndent: Integer): string;
var
  VCut: Integer;
begin
  VCut := 0;
  while (VCut < pIndent) and (VCut < Length(pLine)) and (pLine.Chars[VCut] = ' ') do
    Inc(VCut);
  Result := pLine.Substring(VCut);
end;

{ The Properties.* lines of object pObject as the DFM text has them (TDfmrGridColumn.Properties). }
function EditorLines(const pRows: TDfmRows; pObject: Integer): string;
var
  VI, VLine, VIndent: Integer;
  VLines: TArray<string>;
begin
  VLines := nil;
  VIndent := -1;
  VI := pRows.First[pObject];
  while (VI >= 0) and (VI < Length(pRows.Props)) and (pRows.Props[VI].ObjectOrdinal = pObject) do
  begin
    if (pRows.Props[VI].Depth = 0) and StartsText(EDITOR_PREFIX, pRows.Props[VI].Name) then
      for VLine := Max(pRows.Props[VI].StartLine, 1) to Min(pRows.Props[VI].EndLine, Length(pRows.Lines)) do
      begin
        if VIndent < 0 then
          VIndent := Length(pRows.Lines[VLine - 1]) - Length(TrimLeft(pRows.Lines[VLine - 1]));
        VLines := VLines + [Dedent(pRows.Lines[VLine - 1], VIndent)];
      end;
    Inc(VI);
  end;
  Result := string.Join(LIST_BREAK, VLines);
end;

function ReadColumn(const pRows: TDfmRows; pObject: Integer): TDfmrGridColumn;
begin
  Result.Name := pRows.Objects[pObject].Name;
  Result.FieldName := Trim(pRows.Prop(pObject, 'DataBinding.FieldName'));
  Result.Events := ReadEvents(pRows, pObject, True);
  Result.PropertiesClassName := Trim(pRows.Prop(pObject, PROP_EDITOR_CLASS));
  Result.Properties := EditorLines(pRows, pObject);
end;

{ The grid streams its columns in item order; a stated Index is applied as the loader does, to the columns read so far. }
procedure AddColumn(const pRows: TDfmRows; pObject: Integer; var pColumns: TArray<TDfmrGridColumn>);
var
  VAt: Integer;
begin
  VAt := StrToIntDef(pRows.Prop(pObject, 'Index'), Length(pColumns));
  Insert([ReadColumn(pRows, pObject)], pColumns, EnsureRange(VAt, 0, Length(pColumns)));
end;

function IsView(const pClass: string): Boolean;
begin
  Result := StartsText(VIEW_CLASS_PREFIX, pClass) and EndsText(VIEW_CLASS_SUFFIX, pClass);
end;

function ReadView(const pRows: TDfmRows; pObject: Integer): TDfmrGridView;
var
  VI: Integer;
  VRow: TDfmObjectRow;
  VKind: TDfmrViewKind;
begin
  Result := Default(TDfmrGridView);
  VRow := pRows.Objects[pObject];
  Result.Name := VRow.Name;
  Result.ViewClass := VRow.ClassName;
  Result.ObjKind := VRow.ObjKind;
  Result.DataSource := pRows.Prop(pObject, 'DataController.DataSource');
  Result.Kind := dvkOther;
  for VKind := Low(VIEW_CLASSES) to High(VIEW_CLASSES) do
    if SameText(VIEW_CLASSES[VKind], VRow.ClassName) then
      Result.Kind := VKind;
  if Result.Kind = dvkOther then
    Exit;
  VI := pObject + 1;
  while (VI < Length(pRows.Objects)) and (pRows.Objects[VI].Depth > VRow.Depth) do
  begin
    if (pRows.Objects[VI].Depth = VRow.Depth + 1) and EndsText(COLUMN_SUFFIX, pRows.Objects[VI].ClassName) then
      AddColumn(pRows, VI, Result.Columns);
    Inc(VI);
  end;
end;

function LoadDfmForm(const pFile: string): TDfmrForm;
var
  VRows: TDfmRows;
  VI: Integer;
  VIsDataset: Boolean;
  VDataset: TDfmrDataset;
begin
  Result := Default(TDfmrForm);
  Result.FileName := pFile;
  Result.IsBinary := LoadRows(pFile, VRows, Result.Diagnostics);
  Result.FormName := VRows.Objects[0].Name;
  Result.FormClass := VRows.Objects[0].ClassName;
  for VI := 1 to High(VRows.Objects) do
  begin
    Result.Components := Result.Components + [VRows.Objects[VI].Name];
    VDataset := ReadDataset(VRows, VI, VIsDataset);
    if VIsDataset then
      Result.Datasets := Result.Datasets + [VDataset]
    else if SameText(VRows.Objects[VI].ClassName, DATA_SOURCE_CLASS) then
      AddPair(Result.DataSources, VRows.Objects[VI].Name, VRows.Prop(VI, 'DataSet'))
    else if IsView(VRows.Objects[VI].ClassName) then
      Result.Views := Result.Views + [ReadView(VRows, VI)];
  end;
end;

function DfmRootName(const pFile: string): string;
var
  VBinary: Boolean;
  VText: string;
  VParts: TArray<string>;
begin
  Result := '';
  VText := TEncoding.UTF8.GetString(DfmTextBytes(pFile, VBinary));
  VParts := VText.Substring(0, VText.IndexOf(#10)).Trim.Split([' ', ':'], TStringSplitOptions.ExcludeEmpty);
  if Length(VParts) >= 2 then
    Result := VParts[1];
end;

end.
