unit DRagLint.FieldRepo.DfmReadPlan;

(* drag-lint 1.54 -- lane TT-DFMREAD: the DFM -> repository change set and its applier (design
  2026-11-22-field-repository-v2-design.md sections 3, 4 and 9; plan 2026-11-23-fr-dfmread.md).

  Facts of every read dataset are collected per repository field, then compared with the repository. A dataset's
  table comes from UpdateOptions.UpdateTableName, TableName or a SELECT over one table; otherwise the dataset is
  reported unresolved and gives no change. Two datasets that disagree give one unchecked change per alternative.
  Only what the DFM states makes a change; a read never deletes. *)

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
    /// <summary>Repository key.</summary>
    TableName: string;
    FieldName: string;
    /// <summary>'' = a DL_FIELDS_INFO change, else the event of a DL_LAYOUT_EVENTS change.</summary>
    EventName: string;
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

const
  /// <summary>LAYOUT_TYPE of a TField event stored in DL_LAYOUT_EVENTS (the v2 model has no column for it).</summary>
  LAYOUT_TYPE_FIELD = 'Field';

/// <summary>Reads DFMs and plans the changes that bring the repository in line with them.</summary>
/// <param name="pRepo">Open repository connection, schema 2; only SELECTs run.</param>
/// <param name="pFiles">DFM files; the unit of the same name is read for handler code when it exists.</param>
/// <param name="pDataset">Dataset component name (case-insensitive); '' = every dataset of every file.</param>
/// <returns>The plan. Every change is checked, except alternatives that contradict each other, a data field the
/// repository knows as calc / lookup, and a body or lookup wiring of a field that does not become that kind; a value that cannot be stored is blocked.</returns>
/// <exception cref="EDfmReadError">A file cannot be read, or no file holds the dataset.</exception>
/// <exception cref="ERepoError">The repository is schema 1 (run repo migrate first).</exception>
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
  SCHEMA_WITH_BODIES = 2;
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
  COL_ALIGNMENT = 'ALIGNMENT';
  COL_VISIBLE = 'VISIBLE';
  COL_EVENT_CODE = 'EVENT_CODE';
  COL_LAYOUT = 'LAYOUT_TYPE';
  COL_EVENT = 'EVENT_NAME';
  EVENT_GET_TEXT = 'OnGetText';
  ALIGNMENT_UNSET = '-2'; // TableTools' new-row value
  SQL_FIELD_ROW = 'SELECT * FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F';
  SQL_EVENT_ROW = 'SELECT * FROM "DL_LAYOUT_EVENTS" WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F AND "LAYOUT_TYPE" = :L ' +
    'AND "EVENT_NAME" = :E';
  MULTI_FIELD = ';';
  WARN_VALUE_LEN = 60; // a warning shows the start of a value; the change set has all of it
  { Columns the schema owns: written with a new row, never updated from a DFM. }
  INSERT_ONLY: array[0..2] of string = ('FIELD_AS_TYPE', 'VAR_TYPE', 'STRING_SIZE');
  GET_TEXT_PARAMS: array[0..2] of string = ('Sender', 'Text', 'DisplayText');

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
    Events: TArray<TFactColumn>;
    procedure Add(const pColumn, pValue, pBlocked, pSource: string);
    procedure AddEvent(const pEvent: string; const pBody: TDfmrBody; const pSource: string);
    function Kinds: TArray<TFactValue>;
  end;

  { A DL_FIELDS_INFO row the repository has. }
  TRepoRow = record
    TableName: string;
    FieldName: string;
    IsColumn: Boolean; // the schema read has a type for it
    Kind: TFrFieldKind;
  end;

  { Where a dataset's fields come from. }
  TDatasetSource = record
    TableName: string;  // table of calc / lookup fields, and of data fields without a SELECT
    Sql: TDfmrSqlSource;
    HasSql: Boolean;
    Reason: string;
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
    procedure ReadEvents(const pForm: TDfmrForm; const pContext: TDfmrCodeContext; const pField: TDfmrField;
      pFacts: TFieldFacts);
    procedure WarnForm(const pWhere: string; const pBody: TDfmrBody);
    function AddChange(pOp: TFrChangeOp; const pFacts: TFieldFacts; const pProp, pOld, pNew: string): Integer;
    procedure PlanNew(pFacts: TFieldFacts);
    procedure PlanExisting(pFacts: TFieldFacts; const pRow: TRepoRow);
    procedure ListRoots(const pFolder: string);
    function PlanKind(pFacts: TFieldFacts; const pRow: TRepoRow; pQuery: TFDQuery): TFrFieldKind;
    procedure PlanColumn(pFacts: TFieldFacts; const pColumn: TFactColumn; const pOld: string);
    procedure PlanEvents(pFacts: TFieldFacts);
    function NewRowBlock(pFacts: TFieldFacts): string;
    procedure PlanAll;
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

procedure TFieldFacts.AddEvent(const pEvent: string; const pBody: TDfmrBody; const pSource: string);
begin
  AddFact(Events, pEvent, pBody.Text, pBody.Blocked, pSource);
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
    VCode.Accessor := FieldClassAccessor(VField.FieldClass);
    VCode.IsCalc := VField.Kind in [frkCalc, frkInternalCalc];
    VCode.MacroName := '';
    if FieldSource(pSource, VField, VTable, VColumn, VReason) and (VTable = pSource.TableName) and IsValidIdent(VColumn) then
      VCode.MacroName := VColumn;
    Result.Fields := Result.Fields + [VCode];
  end;
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
  FChanges := TList<TFrChange>.Create;
  FItems := TList<TDfmrChangeItem>.Create;
end;

destructor TDfmRead.Destroy;
begin
  FItems.Free;
  FChanges.Free;
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

{ The dataset `Name` of this form or `Module.Name` of a form of the same folder. }
function TDfmRead.LookupTarget(const pForm: TDfmrForm; const pName: string; out pDataset: TDfmrDataset): Boolean;
var
  VForm: TDfmrForm;
  VDataset: TDfmrDataset;
  VName, VFile: string;
  VDot: Integer;
begin
  pDataset := Default(TDfmrDataset);
  VForm := pForm;
  VName := pName;
  VDot := pName.IndexOf('.');
  if VDot > 0 then
  begin
    VFile := SiblingForm(pForm.FileName, pName.Substring(0, VDot));
    if VFile = '' then
      Exit(False);
    VForm := Form(VFile);
    VName := pName.Substring(VDot + 1);
  end;
  Result := False;
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
  VField, VNamed: TDfmrField;
  VTable, VColumn: string;
begin
  pBlocked := '';
  Result := UpperCase(Trim(pName));
  if pSource.TableName = '' then
    Exit;
  VNamed := Default(TDfmrField);
  VNamed.FieldName := pName;
  for VField in pDataset.Fields do
    if SameText(VField.FieldName, Trim(pName)) then
    begin
      VNamed := VField;
      Break;
    end;
  if FieldSource(pSource, VNamed, VTable, VColumn, pBlocked) and SameText(VTable, pSource.TableName) then
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

procedure TDfmRead.ReadEvents(const pForm: TDfmrForm; const pContext: TDfmrCodeContext; const pField: TDfmrField;
  pFacts: TFieldFacts);
var
  VEvent: TDfmrPair;
  VUnit: TDfmrUnit;
  VBody: TDfmrBody;
  VWhere: string;
  VParams: TArray<string>;
  VI: Integer;
begin
  for VI := 0 to High(GET_TEXT_PARAMS) do
    VParams := VParams + [GET_TEXT_PARAMS[VI]];
  for VEvent in pField.Events do
  begin
    VWhere := ExtractFileName(pForm.FileName) + ' ' + pField.CompName + '.' + VEvent.Name;
    if VEvent.Name <> EVENT_GET_TEXT then
    begin
      FWarnings.Add(VWhere + ' = ' + VEvent.Value + ': not stored (the repository keeps OnGetText only)');
      Continue;
    end;
    VUnit := UnitOf(pForm.FileName);
    if VUnit = nil then
      Continue;
    VBody := VUnit.EventBody(pContext, VEvent.Value, VParams);
    if VBody.Text = '' then
      FWarnings.Add(VWhere + ': not read: ' + (if VBody.Blocked = '' then 'the handler is empty' else VBody.Blocked))
    else
      pFacts.AddEvent(VEvent.Name, VBody, VWhere);
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
    ReadEvents(pForm, VContext, VField, FactsOf(VTable, VColumn));
  end;
  if Length(pDataset.InheritedFields) > 0 then
    FWarnings.Add(Format('%s %s: %d inherited fields not read (FieldName is in the ancestor''s DFM): %s', [VReport.DfmName,
      pDataset.Name, Length(pDataset.InheritedFields), string.Join(', ', pDataset.InheritedFields)]));
  FPlan.Datasets := FPlan.Datasets + [VReport];
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
  PlanEvents(pFacts);
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
  PlanEvents(pFacts);
end;

procedure TDfmRead.PlanEvents(pFacts: TFieldFacts);
var
  VEvent: TFactColumn;
  VValue: TFactValue;
  VOld: Variant;
  VI: Integer;
  VText: string;
begin
  for VEvent in pFacts.Events do
  begin
    VOld := FRepo.ExecSQLScalar('SELECT "EVENT_CODE" FROM "DL_LAYOUT_EVENTS" WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F ' +
      'AND "LAYOUT_TYPE" = :L AND "EVENT_NAME" = :E', [pFacts.TableName, pFacts.FieldName, LAYOUT_TYPE_FIELD, VEvent.Name]);
    VText := VarToStr(VOld);
    for VValue in VEvent.Good do
    begin
      if SameValue(VText, VValue.Value) then
        Continue;
      VI := AddChange(if VText = '' then fcoInsert else fcoUpdate, pFacts, COL_EVENT_CODE, VText, VValue.Value);
      FChanges.List[VI].Target := REPO_TABLE_LAYOUT_EVENTS + ' ' + pFacts.TableName + '|' + pFacts.FieldName + '|'
        + LAYOUT_TYPE_FIELD + '|' + VEvent.Name;
      FChanges.List[VI].Blocked := VValue.Blocked;
      FChanges.List[VI].Checked := (Length(VEvent.Good) = 1) and (VValue.Blocked = '');
      FItems.List[VI].EventName := VEvent.Name;
    end;
  end;
end;

procedure TDfmRead.PlanAll;
var
  VFacts: TFieldFacts;
  VRow: TRepoRow;
begin
  for VFacts in FOrder do
    if FRows.TryGetValue(KeyOf(VFacts.TableName, VFacts.FieldName), VRow) then
      PlanExisting(VFacts, VRow)
    else
      PlanNew(VFacts);
end;

function TDfmRead.Execute(const pFiles: TArray<string>; const pDataset: string): TDfmrPlan;
var
  VFile: string;
  VForm: TDfmrForm;
  VDataset: TDfmrDataset;
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
    FUnits.Clear;
  end;
  if (pDataset <> '') and (Length(FPlan.Datasets) = 0) then
    raise EDfmReadError.CreateFmt('no dataset %s in the DFM', [pDataset]);
  PlanAll;
  FPlan.ChangeSet.Changes := FChanges.ToArray;
  FPlan.Items := FItems.ToArray;
  FPlan.Warnings := FWarnings.ToStringArray;
  Result := FPlan;
end;

function PlanDfmRead(pRepo: TFDConnection; const pFiles: TArray<string>; const pDataset: string): TDfmrPlan;
var
  VRead: TDfmRead;
begin
  if RepoSchemaVersion(pRepo) < SCHEMA_WITH_BODIES then
    raise ERepoError.Create('the repository is schema 1: run repo migrate first');
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
    pQuery.FieldByName(COL_ALIGNMENT).AsString := ALIGNMENT_UNSET;
  end
  else
    pQuery.Edit;
  WriteColumns(pQuery, pItem);
  pQuery.Post;
end;

procedure ApplyEvent(pRepo: TFDConnection; pQuery: TFDQuery; const pChange: TFrChange; const pItem: TDfmrChangeItem);
begin
  if Integer(pRepo.ExecSQLScalar('SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F',
    [pItem.TableName, pItem.FieldName])) = 0 then
    raise ERepoError.CreateFmt('change %d: the field row of %s does not exist (select its insert too)', [pChange.Id, pChange.Target]);
  pQuery.Open(SQL_EVENT_ROW, [pItem.TableName, pItem.FieldName, LAYOUT_TYPE_FIELD, pItem.EventName]);  // dl:ok dataset-open-without-close@49ef -- REVIEWED 2026-11-23 TT-DFMREAD: the caller ApplyDfmRead owns the query: closes it per change and on an exception, frees it in finally
  if pQuery.Eof then
  begin
    pQuery.Append;
    pQuery.FieldByName(COL_TABLE).AsString := pItem.TableName;
    pQuery.FieldByName(COL_FIELD).AsString := pItem.FieldName;
    pQuery.FieldByName(COL_LAYOUT).AsString := LAYOUT_TYPE_FIELD;
    pQuery.FieldByName(COL_EVENT).AsString := pItem.EventName;
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
        if pPlan.Items[VChange.Id - 1].EventName = '' then
          ApplyField(VQuery, VChange, pPlan.Items[VChange.Id - 1])
        else
          ApplyEvent(pRepo, VQuery, VChange, pPlan.Items[VChange.Id - 1]);
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
