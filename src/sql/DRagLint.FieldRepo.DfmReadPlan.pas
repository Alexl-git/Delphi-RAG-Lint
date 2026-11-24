unit DRagLint.FieldRepo.DfmReadPlan;

(* drag-lint 1.54 -- lane TT-DFMREAD: the DFM -> repository change set and its applier (design
  2026-11-22-field-repository-v2-design.md sections 3, 4 and 9; plan 2026-11-23-fr-dfmread.md).

  Facts of every read dataset are collected per repository field, then compared with the repository. A dataset's
  table comes from UpdateOptions.UpdateTableName, TableName or a SELECT over one table; otherwise the dataset is
  reported unresolved and gives no change. Two datasets that disagree give one unchecked change per alternative.
  Only what the DFM states makes a change; a read never deletes a field.

  EVCOLS (rulings 2026-11-23): the TField events and the column events of a DBTable view become event columns of the
  field row (R2); the columns of every table / banded view become DL_GRID_COLUMNS rows (R6), where a column that is gone
  from the form is an unchecked delete. *)

interface

uses
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DfmRead;

type
  /// <summary>Number of persistent fields per kind.</summary>
  TDfmrKindCounts = array[TFrFieldKind] of Integer;

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
    /// <summary>Calc / internal-calc fields with a storable body, with a blocked body, without a body.</summary>
    BodyOk: Integer;
    BodyBlocked: Integer;
    BodyNone: Integer;
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
  end;

/// <summary>Reads DFMs and plans the changes that bring the repository in line with them.</summary>
/// <param name="pRepo">Open repository connection, schema 3; only SELECTs run.</param>
/// <param name="pFiles">DFM files; the unit of the same name is read for handler code when it exists.</param>
/// <param name="pDataset">Dataset component name (case-insensitive); '' = every dataset of every file.</param>
/// <returns>The plan. Every change is checked, except alternatives that contradict each other, a data field the
/// repository knows as calc / lookup, a body or lookup wiring of a field that does not become that kind, and the delete
/// of a grid column that is gone from the form; a value that cannot be stored is blocked.</returns>
/// <exception cref="EDfmReadError">A file cannot be read, or no file holds the dataset.</exception>
/// <exception cref="ERepoError">The repository is schema 1 or 2 (run repo migrate first).</exception>
/// <remarks>Ids are 1-based in plan order: the same DFMs and repository always give the same ids.</remarks>
function PlanDfmRead(pRepo: TFDConnection; const pFiles: TArray<string>; const pDataset: string): TDfmrPlan;

/// <summary>Applies chosen changes of a plan in one transaction.</summary>
/// <param name="pRepo">Open read-write repository connection, the one the plan was made from.</param>
/// <param name="pPlan">The plan.</param>
/// <param name="pChosen">Changes to apply (the checked ones, or those a --select file named).</param>
/// <returns>One `replacing OLD with NEW` line per applied change.</returns>
/// <exception cref="ERepoError">Two chosen changes set the same value, a chosen change is blocked, or it needs a row
/// whose insert was not chosen; nothing is written.</exception>
function ApplyDfmRead(pRepo: TFDConnection; const pPlan: TDfmrPlan; const pChosen: TArray<TFrChange>): TArray<string>;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Variants,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  DRagLint.FieldRepo.Schema,  // dl:ok uses-global-census@9edb -- REVIEWED 2026-11-23 TT-DFMREAD: the unit is used for its record types and functions; one table-name constant is what it needs
  DRagLint.FieldRepo.SchemaFacts,
  DRagLint.FieldRepo.DfmReadSql,
  DRagLint.FieldRepo.DfmReadCalc;

const
  FIELDS_TABLE = 'DL_FIELDS_INFO';
  SCHEMA_WITH_EVENTS = 3;
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
    Values: TArray<TDfmrPair>; // TABLE_NAME, FIELD_NAME, COLUMN_INDEX; '' = NULL
    function Key: string;
    function Text: string;
  end;

  { Where a dataset's fields come from. }
  TDatasetSource = record
    TableName: string;  // table of calc / lookup fields, and of data fields without a SELECT
    Sql: TDfmrSqlSource;
    HasSql: Boolean;
    Reason: string;
  end;

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
    FChanges: TList<TFrChange>;
    FItems: TList<TDfmrChangeItem>;
    procedure LoadRows;
    function Form(const pFile: string): TDfmrForm;
    function UnitOf(const pFile: string): TDfmrUnit;
    function SiblingForm(const pFile, pRoot: string): string;
    function FactsOf(const pTable, pField: string): TFieldFacts;
    function LookupTarget(const pForm: TDfmrForm; const pName: string; out pDataset: TDfmrDataset): Boolean;
    procedure ReadDataset(const pForm: TDfmrForm; const pDataset: TDfmrDataset);
    procedure ReadField(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pField: TDfmrField;
      const pTable, pColumn: string);
    procedure ReadLookup(const pForm: TDfmrForm; const pOwner: TDfmrDataset; const pField: TDfmrField; pFacts: TFieldFacts;
      const pSource: string);
    procedure ReadCalc(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pContext: TDfmrCodeContext;
      const pField: TDfmrField; pFacts: TFieldFacts; var pReport: TDfmrDatasetReport);
    procedure ReadEvents(const pForm: TDfmrForm; const pContext: TDfmrCodeContext; const pEvents: TArray<TDfmrPair>;
      const pOwner: string; pFacts: TFieldFacts);
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

function SourceOf(const pDataset: TDfmrDataset): TDatasetSource;
var
  VTable: TDfmrSqlTable;
begin
  Result := Default(TDatasetSource);
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
    Result.Reason := Format('the SQL reads %d tables:', [Length(Result.Sql.Tables)]);
    for VTable in Result.Sql.Tables do
      Result.Reason := Result.Reason + ' ' + VTable.Name;
  end;
end;

{ The table and column of a persistent field; False = the DFM does not state it. }
function FieldSource(const pSource: TDatasetSource; const pField: TDfmrField; out pTable, pColumn, pReason: string): Boolean;
begin
  pTable := pSource.TableName;
  pColumn := UpperCase(Trim(pField.FieldName));
  pReason := pSource.Reason;
  if (pField.Kind = frkData) and pSource.HasSql and (pSource.Sql.Reason = '') then
    Exit(SqlFieldColumn(pSource.Sql, pField.FieldName, pField.Origin, pTable, pColumn, pReason));
  Result := pTable <> '';
end;

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
    if FieldSource(pSource, VField, VTable, VColumn, VReason) and (VTable = pSource.TableName) and IsValidIdent(VColumn) then
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
  FChanges := TList<TFrChange>.Create;
  FItems := TList<TDfmrChangeItem>.Create;
end;

destructor TDfmRead.Destroy;
begin
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

procedure TDfmRead.ReadLookup(const pForm: TDfmrForm; const pOwner: TDfmrDataset; const pField: TDfmrField;
  pFacts: TFieldFacts; const pSource: string);
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
    VSource := SourceOf(VDataset);
  VTable := VSource.TableName;
  VMulti := if pField.KeyFields.Contains(MULTI_FIELD) or pField.LookupKeyFields.Contains(MULTI_FIELD)
    then 'multi-field lookup key' else '';
  if pField.KeyFields <> '' then
  begin
    VKey := LookupColumn(pOwner, SourceOf(pOwner), pField.KeyFields, VBlocked);
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

procedure TDfmRead.ReadCalc(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pContext: TDfmrCodeContext;
  const pField: TDfmrField; pFacts: TFieldFacts; var pReport: TDfmrDatasetReport);
var
  VUnit: TDfmrUnit;
  VBody: TDfmrBody;
  VWhere: string;
begin
  VWhere := pReport.DfmName + ' ' + pField.CompName;
  VBody := Default(TDfmrBody);
  VUnit := UnitOf(pForm.FileName);
  if (pDataset.OnCalcFields <> '') and (VUnit <> nil) then
    VBody := VUnit.CalcBody(pContext, pDataset.OnCalcFields, pField.CompName);
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
procedure TDfmRead.ReadEvents(const pForm: TDfmrForm; const pContext: TDfmrCodeContext; const pEvents: TArray<TDfmrPair>;
  const pOwner: string; pFacts: TFieldFacts);
var
  VEvent: TDfmrPair;
  VColumn: TFrEventColumn;
  VUnit: TDfmrUnit;
  VBody: TDfmrBody;
  VWhere: string;
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
        if VBody.Text = '' then
          FWarnings.Add(VWhere + ': not read: ' + (if VBody.Blocked = '' then 'the handler is empty' else VBody.Blocked))
        else
          pFacts.Add(VColumn.Column, VBody.Text, VBody.Blocked, VWhere);
        WarnForm(VWhere, VBody);
      end;
end;

procedure TDfmRead.ReadField(const pForm: TDfmrForm; const pDataset: TDfmrDataset; const pField: TDfmrField;
  const pTable, pColumn: string);
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
    ReadLookup(pForm, pDataset, pField, VFacts, VSource);
  if (pField.Kind = frkAggregate) and (pField.Expression <> '') then
    VFacts.Add(COL_BODY, pField.Expression, '', VSource);
end;

procedure TDfmRead.ReadDataset(const pForm: TDfmrForm; const pDataset: TDfmrDataset);
var
  VReport: TDfmrDatasetReport;
  VSource: TDatasetSource;
  VContext: TDfmrCodeContext;
  VField: TDfmrField;
  VTable, VColumn, VReason: string;
begin
  VSource := SourceOf(pDataset);
  VContext := CodeContext(pForm, pDataset, VSource);
  VReport := Default(TDfmrDatasetReport);
  VReport.DfmName := ExtractFileName(pForm.FileName);
  VReport.Dataset := pDataset.Name;
  VReport.DatasetClass := pDataset.DatasetClass;
  VReport.TableName := VSource.TableName;
  if VSource.TableName = '' then
    VReport.Unresolved := VSource.Reason + (if pDataset.ObjKind = 'object' then '' else ' (' + pDataset.ObjKind
      + ': its own properties are in the ancestor''s DFM)');
  for VField in pDataset.Fields do
  begin
    Inc(VReport.Counts[VField.Kind]);
    if not FieldSource(VSource, VField, VTable, VColumn, VReason) then
    begin
      VReport.Unattributed := VReport.Unattributed + [VField.FieldName];
      Continue;
    end;
    ReadField(pForm, pDataset, VField, VTable, VColumn);
    if VField.Kind in [frkCalc, frkInternalCalc] then
      ReadCalc(pForm, pDataset, VContext, VField, FactsOf(VTable, VColumn), VReport);
    ReadEvents(pForm, VContext, VField.Events, VField.CompName, FactsOf(VTable, VColumn));
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
  Result.Source := SourceOf(Result.Dataset);
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
  VForm, VView, VColumn, VTable, VField, VIndex: TField;
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
    VOrder := nil;
    while not VQuery.Eof do
    begin
      VRow.FormName := VForm.AsString;
      VRow.ViewName := VView.AsString;
      VRow.ColumnName := VColumn.AsString;
      VRow.Values := [MakePair(COL_TABLE, VTable.AsString), MakePair(COL_FIELD, VField.AsString), MakePair(COL_INDEX, VIndex.AsString)];
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
  if (pDataset <> '') and (Length(FPlan.Datasets) = 0) then
    raise EDfmReadError.CreateFmt('no dataset %s in the DFM', [pDataset]);
  PlanAll(pFiles, pDataset = '');
  FPlan.ChangeSet.Changes := FChanges.ToArray;
  FPlan.Items := FItems.ToArray;
  FPlan.Warnings := FWarnings.ToStringArray;
  Result := FPlan;
end;

function PlanDfmRead(pRepo: TFDConnection; const pFiles: TArray<string>; const pDataset: string): TDfmrPlan;
var
  VRead: TDfmRead;
begin
  if RepoSchemaVersion(pRepo) < SCHEMA_WITH_EVENTS then
    raise ERepoError.CreateFmt('the repository is schema %d: run repo migrate first', [RepoSchemaVersion(pRepo)]);
  VRead := TDfmRead.Create(pRepo);
  try
    Result := VRead.Execute(pFiles, pDataset);
  finally
    VRead.Free;
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
        if pPlan.Items[VChange.Id - 1].FormName = '' then
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
