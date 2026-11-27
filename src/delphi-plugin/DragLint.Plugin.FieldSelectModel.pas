unit DragLint.Plugin.FieldSelectModel;

{ drag-lint 1.54 -- lane TT-DIALOG: the logic of the field dialogs (design 2026-11-22-field-repository-v2-design.md
  sections 3, 4.4 and 9): what `repo read-dfm --json` / `repo write-dfm --json` print, the field selection of one
  dataset, the --select file. The rules are the engine's own (ExpandSelection).

  No VCL, no ToolsAPI, no I/O: tests\plugin\fieldselect\FieldSelectTests.dpr pins it. }

interface

uses
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.DfmReadSelection;

const
  /// <summary>Number of usage icons: one per set of use kinds (UsageIcon is 0 .. USAGE_ICON_COUNT - 1).</summary>
  USAGE_ICON_COUNT = 16;

type
  /// <summary>How a field is used in the project (lane UI-M, DRagLint.FieldRepo.FieldUsage); same four kinds, in the
  /// same order, so the caller maps one onto the other by Ord. Kept here so the plugin needs no FireDAC.</summary>
  TFsUseKind = (
    /// <summary>A data-aware edit control in a DFM (DataField).</summary>
    fuDfmControl,
    /// <summary>A grid column.</summary>
    fuGridColumn,
    /// <summary>A lookup key / list / result field.</summary>
    fuLookup,
    /// <summary>Code (a FieldByName / Fields access).</summary>
    fuCode);

  /// <summary>A set of use kinds; empty = unused.</summary>
  TFsUseKinds = set of TFsUseKind;

  /// <summary>One persistent field of a dataset, as the DFM holds it.</summary>
  TFsPersistent = record
    /// <summary>FieldName property.</summary>
    FieldName: string;
    /// <summary>Component name.</summary>
    Component: string;
    /// <summary>Field kind.</summary>
    Kind: TFrFieldKind;
    /// <summary>Table and column the field belongs to; '' = the DFM does not state them.</summary>
    TableName: string;
    Column: string;
  end;

  /// <summary>One dataset of a form.</summary>
  TFsDataset = record
    /// <summary>Component name and class.</summary>
    Name: string;
    DatasetClass: string;
    /// <summary>Its table; '' = unknown, Unresolved says why.</summary>
    TableName: string;
    Unresolved: string;
    /// <summary>The persistent fields, in DFM order; only of a read of one dataset.</summary>
    Persistent: TArray<TFsPersistent>;
    /// <summary>The fields the repository has for TableName; only of a read of one dataset.</summary>
    TableFields: TArray<TFrSelectionField>;
    /// <summary>Text of the dataset in a list.</summary>
    /// <returns>`qryOrders (TFDQuery)`.</returns>
    function Caption: string;
  end;

  /// <summary>One row of the field-selection dialog.</summary>
  TFsRow = record
    /// <summary>Repository field name; the FieldName of a field the repository does not have.</summary>
    Name: string;
    /// <summary>Field kind.</summary>
    Kind: TFrFieldKind;
    /// <summary>Component of the persistent field; '' = not in the form.</summary>
    Component: string;
    /// <summary>Why the row cannot be changed; '' = it can.</summary>
    Locked: string;
    /// <summary>In the selection.</summary>
    Checked: Boolean;
    /// <summary>The kinds in which the project uses the field; empty until SetUsage.</summary>
    Used: TFsUseKinds;
  end;

  /// <summary>The field selection of one dataset (FR-2).</summary>
  /// <remarks>Rows: the repository's fields of the table, then the persistent fields that are none of them (locked,
  /// kept). At first exactly the persistent fields of the DFM are checked. Not thread-safe.</remarks>
  TFieldSelection = class
  strict private
    FFields: TArray<TFrSelectionField>;
    FRows: TArray<TFsRow>;
    FNoTable: string;
    FMissingNote: string;
    procedure AddRepositoryRow(const pField: TFrSelectionField; const pDataset: TFsDataset);
    procedure AddOtherRows(const pDataset: TFsDataset);
    function IndexOf(const pName: string): Integer;
    function CheckedNames: TArray<string>;
    function Expand(const pNames: TArray<string>; out pError: string): TArray<string>;
    function Unchecked(const pNames: TArray<string>; pCheck: Boolean): string;
    function CheckRow(const pName: string; out pMessage: string): Boolean;
    function NeededBy(const pName: string): string;
    function MissingFields: string;
    function GetRows(pIndex: Integer): TFsRow;
  public
    /// <summary>Starts with the selection the DFM holds.</summary>
    /// <param name="pDataset">A dataset read alone (Persistent and TableFields are filled).</param>
    constructor Create(const pDataset: TFsDataset);
    /// <summary>True when the dataset has a table and the repository has fields of it.</summary>
    /// <returns>False = there is nothing to select; Refusal says why.</returns>
    function HasTable: Boolean;
    /// <summary>Number of rows.</summary>
    /// <returns>Rows of the repository and other rows.</returns>
    function Count: Integer;
    /// <summary>Checks or unchecks one row.</summary>
    /// <param name="pIndex">Row index.</param>
    /// <param name="pValue">The new state.</param>
    /// <param name="pMessage">What else changed, or why nothing did; '' = nothing to say.</param>
    /// <returns>False = the row keeps its state: it is locked, a checked field needs it, what it needs is not in the
    /// repository, or there is no such row.</returns>
    /// <remarks>Checking adds what the field needs (ExpandSelection S1); unchecking removes nothing else (S2).</remarks>
    function SetChecked(pIndex: Integer; pValue: Boolean; out pMessage: string): Boolean;
    /// <summary>Checks or unchecks every row that can be changed.</summary>
    /// <param name="pValue">The new state; a field whose needs are not in the repository is not checked.</param>
    procedure SetAll(pValue: Boolean);
    /// <summary>Records in which kinds the project uses a field.</summary>
    /// <param name="pName">Field name, case-insensitive; a name that is no row is ignored.</param>
    /// <param name="pKinds">The kinds; replaces what the row had.</param>
    procedure SetUsage(const pName: string; pKinds: TFsUseKinds);
    /// <summary>The names of every row, for `repo field-usage --fields`.</summary>
    /// <returns>Comma-separated, in row order; '' when there are no rows.</returns>
    function FieldList: string;
    /// <summary>Takes the usage the engine reported (`repo field-usage --json`) into the rows.</summary>
    /// <param name="pOutput">The engine output; the first line that is a JSON object is read:
    /// {"usage":[{"field":"ID","kinds":["dfm","grid","lookup","code"]}]}. An unknown kind word and an unknown field are ignored.</param>
    /// <returns>False = no usage object in the output; the rows keep what they had.</returns>
    function ApplyUsage(const pOutput: string): Boolean;
    /// <summary>The value of write-dfm --names.</summary>
    /// <returns>The checked repository fields and what they need, comma-separated; '' when none is checked.</returns>
    /// <exception cref="EFrSelectionError">As ExpandSelection.</exception>
    /// <remarks>A malformed macro in a body raises EFrKindError (ExpandSelection). Ask Refusal first.</remarks>
    function Names: string;
    /// <summary>Why the selection cannot be written.</summary>
    /// <returns>'' = it can. An empty selection is refused: --names without a name means "no selection".</returns>
    function Refusal: string;
    /// <summary>Components of the persistent fields the user unchecked.</summary>
    /// <returns>Component names.</returns>
    function RemovedComponents: TArray<string>;
    /// <summary>The selection in one line.</summary>
    /// <returns>How many fields are selected, added and removed.</returns>
    function Summary: string;
    /// <summary>The rows; an empty record for an index out of range.</summary>
    property Rows[pIndex: Integer]: TFsRow read GetRows; default;
    /// <summary>What the fields of the form need and the form does not have, as a sentence; '' = nothing.</summary>
    property MissingNote: string read FMissingNote;
  end;

  /// <summary>One change of a dry run.</summary>
  TFsChange = record
    /// <summary>Id of the change in its plan.</summary>
    Id: Integer;
    /// <summary>insert, update or delete.</summary>
    Op: string;
    /// <summary>What it changes, and the property; '' = the whole object.</summary>
    Target: string;
    Prop: string;
    /// <summary>Values before and after.</summary>
    OldText: string;
    NewText: string;
    /// <summary>Why it cannot be applied; '' = it can.</summary>
    Blocked: string;
    /// <summary>To be applied.</summary>
    Checked: Boolean;
  end;

  /// <summary>A dry run.</summary>
  TFsPlan = record
    /// <summary>Plan id; '' for a verb without one (read-dfm).</summary>
    PlanId: string;
    /// <summary>The changes in id order.</summary>
    Changes: TArray<TFsChange>;
    /// <summary>Warnings of the engine.</summary>
    Warnings: TArray<string>;
    /// <summary>The change set as the engine printed it: two dry runs with one text have the same ids.</summary>
    Fingerprint: string;
    /// <summary>Number of checked changes.</summary>
    /// <returns>The count.</returns>
    function CheckedCount: Integer;
    /// <summary>Checks or unchecks every change that is not blocked.</summary>
    /// <param name="pValue">The new state.</param>
    procedure SetAll(pValue: Boolean);
    /// <summary>Blocks the removal of every field the user did not uncheck (a field the repository does not know).</summary>
    /// <param name="pComponents">Components that may be removed.</param>
    procedure KeepAllBut(const pComponents: TArray<string>);
    /// <summary>The --select file.</summary>
    /// <returns>The plan line when there is a plan id, then the ids of the checked changes; '' when no change is checked.</returns>
    function SelectFileText: string;
  end;

/// <summary>Index of the icon of a set of use kinds in the dialog's image strip.</summary>
/// <param name="pKinds">The kinds.</param>
/// <returns>0 = unused (blank); otherwise the sum of 1 shl Ord(kind), so one kind gives 1, 2, 4 or 8 and all four 15.</returns>
function UsageIcon(pKinds: TFsUseKinds): Integer;

/// <summary>The kinds of a set as words, for a tooltip or a column.</summary>
/// <param name="pKinds">The kinds.</param>
/// <returns>`edit control, grid column, lookup, code` in that order, comma-separated; '' = unused.</returns>
function UsageText(pKinds: TFsUseKinds): string;

/// <summary>The datasets of a `repo read-dfm --json` run.</summary>
/// <param name="pOutput">Output of the run; lines that are not the JSON object are ignored.</param>
/// <param name="pDatasets">The datasets in DFM order.</param>
/// <param name="pError">Why there are none; '' on success.</param>
/// <returns>True when the output holds the object.</returns>
function ParseDatasets(const pOutput: string; out pDatasets: TArray<TFsDataset>; out pError: string): Boolean;

/// <summary>The change set of a `repo read-dfm --json` or `repo write-dfm --json` dry run.</summary>
/// <param name="pOutput">Output of the run; lines that are not the JSON object are ignored.</param>
/// <param name="pPlan">The plan, each change checked as the engine proposes it.</param>
/// <param name="pError">Why there is none; '' on success.</param>
/// <returns>True when the output holds the object.</returns>
function ParsePlan(const pOutput: string; out pPlan: TFsPlan; out pError: string): Boolean;

/// <summary>The dataset a command works on when nobody has to be asked.</summary>
/// <param name="pDatasets">The datasets of the form.</param>
/// <param name="pSelected">Names of the components selected in the designer.</param>
/// <returns>The index of the one selected dataset, or of the only dataset; -1 = ask.</returns>
function DatasetToUse(const pDatasets: TArray<TFsDataset>; const pSelected: TArray<string>): Integer;

/// <summary>The arguments of `repo read-dfm`.</summary>
/// <param name="pDfm">The form.</param>
/// <param name="pDataset">--dataset; '' = all datasets.</param>
/// <param name="pTail">--json, or SelectArg.</param>
/// <returns>The arguments, the file name quoted.</returns>
function ReadDfmArgs(const pDfm, pDataset, pTail: string): string;

/// <summary>The arguments of `repo write-dfm`.</summary>
/// <param name="pDfm">The form.</param>
/// <param name="pDataset">--dataset.</param>
/// <param name="pNames">--names, see TFieldSelection.Names.</param>
/// <param name="pTail">--json, or SelectArg.</param>
/// <returns>The arguments, the file name quoted.</returns>
function WriteDfmArgs(const pDfm, pDataset, pNames, pTail: string): string;

/// <summary>The tail that applies a --select file.</summary>
/// <param name="pFile">The file.</param>
/// <returns>`--select "FILE"`.</returns>
function SelectArg(const pFile: string): string;

/// <summary>The lines of an apply run worth showing: what was replaced, the backups, the count, the refusals.</summary>
/// <param name="pOutput">Output of the run.</param>
/// <param name="pMaxLines">Most lines kept, the last one always; the rest is counted.</param>
/// <returns>The kept lines joined with line breaks; the whole output when it has no such line.</returns>
function ApplyLog(const pOutput: string; pMaxLines: Integer): string;

type
  /// <summary>What becomes of the form in the editor after a run that writes it: nothing to do, reload it, ask first (the run
  /// failed), leave it because it has unsaved changes, the reload raised.</summary>
  TFsReload = (frNone, frReload, frAsk, frDirty, frFailed);

/// <summary>What to do with the open form after a write run.</summary>
/// <param name="pExitCode">Exit code of the run.</param>
/// <param name="pOpen">The form is open in the IDE.</param>
/// <param name="pDirty">It has unsaved changes now.</param>
/// <param name="pChanged">Its files on disk are not those from before the run.</param>
/// <returns>frNone, frReload, frAsk or frDirty.</returns>
/// <remarks>A failed run can have changed a file: write-dfm says so when it could not restore one.</remarks>
function ReloadStep(pExitCode: Integer; pOpen, pDirty, pChanged: Boolean): TFsReload;

/// <summary>What the user must know about the form in the editor after a write run.</summary>
/// <param name="pReload">What happened; frAsk = the user did not want the reload.</param>
/// <param name="pFile">Name of the form file.</param>
/// <param name="pError">Why the reload failed; used for frFailed only.</param>
/// <returns>One line; '' when the editor holds what is on disk.</returns>
function ApplyNotice(pReload: TFsReload; const pFile, pError: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON;

const
  KEY_DATASETS = 'datasets';
  KEY_CHANGE_SET = 'changeSet';
  KEY_FIELD = 'field';
  KEY_TABLE = 'table';
  LIST_SEPARATOR = ', ';
  PLAN_LINE = '# plan ';
  OP_DELETE = 'delete';
  LOCK_GRAPHICAL = 'a grid column, no field';
  LOCK_FOREIGN = 'kept: a field of ';
  LOCK_UNKNOWN = 'kept: not a field of the repository';
  KEPT_FIELD = 'kept: you did not unselect it';
  LOG_STARTS: array[0..3] of string = ('replacing ', 'backup ', 'applied:', 'repo ');

{ ---- the engine's output ---- }

{ The one line that is a JSON object; nil = none. }
function ObjectOf(const pOutput: string): TJSONObject;
var
  VLine: string;
  VValue: TJSONValue;
begin
  Result := nil;
  for VLine in pOutput.Split([#13, #10]) do
    if VLine.StartsWith('{') then
    begin
      VValue := TJSONObject.ParseJSONValue(VLine);
      if VValue is TJSONObject then
        Exit(TJSONObject(VValue));
      VValue.Free;
    end;
end;

function TextOf(pItem: TJSONValue; const pName: string): string;
begin
  if not pItem.TryGetValue<string>(pName, Result) then
    Result := '';
end;

{ The array of that name; nil = none. }
function ArrayOf(pItem: TJSONValue; const pName: string): TJSONArray;
begin
  if not pItem.TryGetValue<TJSONArray>(pName, Result) then
    Result := nil;
end;

{ Every kind name of the engine; another one is data. }
function KindOf(pItem: TJSONValue): TFrFieldKind;
var
  VKind: TFrFieldKind;
begin
  Result := frkData;
  for VKind := Low(TFrFieldKind) to High(TFrFieldKind) do
    if SameText(FrKindName(VKind), TextOf(pItem, 'kind')) then
      Exit(VKind);
end;

function PersistentOf(pItem: TJSONValue): TFsPersistent;
begin
  Result.FieldName := TextOf(pItem, KEY_FIELD);
  Result.Component := TextOf(pItem, 'component');
  Result.Kind := KindOf(pItem);
  Result.TableName := TextOf(pItem, KEY_TABLE);
  Result.Column := TextOf(pItem, 'column');
end;

function TableFieldOf(pItem: TJSONValue): TFrSelectionField;
begin
  Result.Name := TextOf(pItem, KEY_FIELD);
  Result.Kind := KindOf(pItem);
  Result.SourceKey := TextOf(pItem, 'sourceKey');
  Result.Body := TextOf(pItem, 'body');
end;

function DatasetOf(pItem: TJSONValue): TFsDataset;
var
  VList: TJSONArray;
  VItem: TJSONValue;
begin
  Result := Default(TFsDataset);
  Result.Name := TextOf(pItem, 'dataset');
  Result.DatasetClass := TextOf(pItem, 'class');
  Result.TableName := TextOf(pItem, KEY_TABLE);
  Result.Unresolved := TextOf(pItem, 'unresolved');
  VList := ArrayOf(pItem, 'persistent');
  if VList <> nil then
    for VItem in VList do
      Result.Persistent := Result.Persistent + [PersistentOf(VItem)];
  VList := ArrayOf(pItem, 'tableFields');
  if VList <> nil then
    for VItem in VList do
      Result.TableFields := Result.TableFields + [TableFieldOf(VItem)];
end;

function ChangeOf(pItem: TJSONValue): TFsChange;
begin
  if not pItem.TryGetValue<Integer>('id', Result.Id) then
    Result.Id := 0;
  Result.Op := TextOf(pItem, 'op');
  Result.Target := TextOf(pItem, 'target');
  Result.Prop := TextOf(pItem, 'prop');
  Result.OldText := TextOf(pItem, 'old');
  Result.NewText := TextOf(pItem, 'new');
  Result.Blocked := TextOf(pItem, 'blocked');
  Result.Checked := pItem.GetValue<Boolean>('checked', False) and (Result.Blocked = '');
end;

function NoObjectError(const pOutput: string): string;
begin
  Result := 'the engine printed no result: ' + Trim(pOutput);
end;

function ParseDatasets(const pOutput: string; out pDatasets: TArray<TFsDataset>; out pError: string): Boolean;
var
  VRoot: TJSONObject;
  VList: TJSONArray;
  VItem: TJSONValue;
begin
  pDatasets := nil;
  pError := NoObjectError(pOutput);
  VRoot := ObjectOf(pOutput);
  try
    if VRoot = nil then
      Exit(False);
    VList := ArrayOf(VRoot, KEY_DATASETS);
    Result := VList <> nil;
    if not Result then
      Exit;
    pError := '';
    for VItem in VList do
      pDatasets := pDatasets + [DatasetOf(VItem)];
  finally
    VRoot.Free;
  end;
end;

function ParsePlan(const pOutput: string; out pPlan: TFsPlan; out pError: string): Boolean;
var
  VRoot, VSet: TJSONObject;
  VList: TJSONArray;
  VItem: TJSONValue;
begin
  pPlan := Default(TFsPlan);
  pError := NoObjectError(pOutput);
  VRoot := ObjectOf(pOutput);
  try
    Result := (VRoot <> nil) and VRoot.TryGetValue<TJSONObject>(KEY_CHANGE_SET, VSet) and (ArrayOf(VSet, 'changes') <> nil);
    if not Result then
      Exit;
    pError := '';
    pPlan.PlanId := TextOf(VRoot, 'plan');
    pPlan.Fingerprint := VSet.ToJSON;
    for VItem in ArrayOf(VSet, 'changes') do
      pPlan.Changes := pPlan.Changes + [ChangeOf(VItem)];
    VList := ArrayOf(VRoot, 'warnings');
    if VList <> nil then
      for VItem in VList do
        pPlan.Warnings := pPlan.Warnings + [VItem.Value];
  finally
    VRoot.Free;
  end;
end;

function TFsDataset.Caption: string;
begin
  Result := Name + ' (' + DatasetClass + ')';
end;

function DatasetToUse(const pDatasets: TArray<TFsDataset>; const pSelected: TArray<string>): Integer;
var
  VI: Integer;
begin
  Result := -1;
  if Length(pDatasets) = 1 then
    Exit(0);
  for VI := 0 to High(pDatasets) do
    if MatchText(pDatasets[VI].Name, pSelected) then
    begin
      if Result >= 0 then
        Exit(-1);
      Result := VI;
    end;
end;

{ ---- the selection ---- }

constructor TFieldSelection.Create(const pDataset: TFsDataset);
var
  VField: TFrSelectionField;
begin
  inherited Create;
  if pDataset.TableName = '' then
    FNoTable := pDataset.Name + ' has no table: ' + pDataset.Unresolved
  else if Length(pDataset.TableFields) = 0 then
    FNoTable := 'the repository has no field of ' + pDataset.TableName;
  for VField in pDataset.TableFields do
    AddRepositoryRow(VField, pDataset);
  AddOtherRows(pDataset);
  FMissingNote := MissingFields;
end;

procedure TFieldSelection.AddRepositoryRow(const pField: TFrSelectionField; const pDataset: TFsDataset);
var
  VRow: TFsRow;
  VPersistent: TFsPersistent;
begin
  VRow := Default(TFsRow);
  VRow.Name := pField.Name;
  VRow.Kind := pField.Kind;
  for VPersistent in pDataset.Persistent do
    if SameText(VPersistent.TableName, pDataset.TableName) and SameText(VPersistent.Column, pField.Name) then
    begin
      VRow.Component := VPersistent.Component;
      VRow.Checked := True;
      Break;
    end;
  if pField.Kind = frkGraphical then
    VRow.Locked := LOCK_GRAPHICAL
  else
    FFields := FFields + [pField];
  FRows := FRows + [VRow];
end;

{ The persistent fields that are no field of the table in the repository. }
procedure TFieldSelection.AddOtherRows(const pDataset: TFsDataset);
var
  VRow: TFsRow;
  VPersistent: TFsPersistent;
begin
  for VPersistent in pDataset.Persistent do
  begin
    if SameText(VPersistent.TableName, pDataset.TableName) and (IndexOf(VPersistent.Column) >= 0) then
      Continue;
    VRow := Default(TFsRow);
    VRow.Name := VPersistent.FieldName;
    VRow.Kind := VPersistent.Kind;
    VRow.Component := VPersistent.Component;
    VRow.Checked := True;
    VRow.Locked := if (VPersistent.TableName = '') or SameText(VPersistent.TableName, pDataset.TableName)
      then LOCK_UNKNOWN else LOCK_FOREIGN + VPersistent.TableName;
    FRows := FRows + [VRow];
  end;
end;

function UsageIcon(pKinds: TFsUseKinds): Integer;
var
  VKind: TFsUseKind;
begin
  Result := 0;
  for VKind := Low(TFsUseKind) to High(TFsUseKind) do
    if VKind in pKinds then
      Inc(Result, 1 shl Ord(VKind));
end;

function UsageText(pKinds: TFsUseKinds): string;
const
  WORDS: array[TFsUseKind] of string = ('edit control', 'grid column', 'lookup', 'code');
var
  VKind: TFsUseKind;
begin
  Result := '';
  for VKind := Low(TFsUseKind) to High(TFsUseKind) do
    if VKind in pKinds then
      Result := Result + (if Result = '' then '' else ', ') + WORDS[VKind];
end;

function TFieldSelection.FieldList: string;
var
  VRow: TFsRow;
begin
  Result := '';
  for VRow in FRows do
    Result := Result + (if Result = '' then '' else ',') + VRow.Name;
end;

function TFieldSelection.ApplyUsage(const pOutput: string): Boolean;
const
  KIND_WORDS: array[TFsUseKind] of string = ('dfm', 'grid', 'lookup', 'code');
var
  VRoot: TJSONObject;
  VItem, VKindItem: TJSONValue;
  VKinds: TFsUseKinds;
  VKind: TFsUseKind;
begin
  VRoot := ObjectOf(pOutput);
  Result := (VRoot <> nil) and (ArrayOf(VRoot, 'usage') <> nil);
  try
    if not Result then
      Exit;
    for VItem in ArrayOf(VRoot, 'usage') do
    begin
      VKinds := [];
      if (VItem is TJSONObject) and (TJSONObject(VItem).GetValue('kinds') is TJSONArray) then
        for VKindItem in TJSONArray(TJSONObject(VItem).GetValue('kinds')) do
          for VKind := Low(TFsUseKind) to High(TFsUseKind) do
            if SameText(VKindItem.Value, KIND_WORDS[VKind]) then
              Include(VKinds, VKind);
      SetUsage(TextOf(VItem, 'field'), VKinds);
    end;
  finally
    VRoot.Free;
  end;
end;

procedure TFieldSelection.SetUsage(const pName: string; pKinds: TFsUseKinds);
var
  VIndex: Integer;
begin
  VIndex := IndexOf(pName);
  if VIndex >= 0 then
    FRows[VIndex].Used := pKinds;
end;

function TFieldSelection.GetRows(pIndex: Integer): TFsRow;
begin
  Result := Default(TFsRow);
  if (pIndex >= 0) and (pIndex < Length(FRows)) then
    Result := FRows[pIndex];
end;

function TFieldSelection.HasTable: Boolean;
begin
  Result := FNoTable = '';
end;

function TFieldSelection.Count: Integer;
begin
  Result := Length(FRows);
end;

{ Index of the row of a repository field; those come before all others. }
function TFieldSelection.IndexOf(const pName: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(FRows) do
    if SameText(FRows[VI].Name, pName) then
      Exit(VI);
end;

function TFieldSelection.CheckedNames: TArray<string>;
var
  VRow: TFsRow;
begin
  Result := nil;
  for VRow in FRows do
    if VRow.Checked and (VRow.Locked = '') then
      Result := Result + [VRow.Name];
end;

{ ExpandSelection; pError = why it is not possible, '' = it is. }
function TFieldSelection.Expand(const pNames: TArray<string>; out pError: string): TArray<string>;
begin
  Result := nil;
  pError := '';
  try
    Result := ExpandSelection(pNames, FFields);
  except
    on E: EFrSelectionError do
      pError := E.Message;
    on E: EFrKindError do
      pError := E.Message;
  end;
end;

{ Those of the fields that are not checked, as a list; pCheck checks them. }
function TFieldSelection.Unchecked(const pNames: TArray<string>; pCheck: Boolean): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 0 to High(FRows) do
    if not FRows[VI].Checked and (FRows[VI].Locked = '') and MatchText(FRows[VI].Name, pNames) then
    begin
      Result := Result + (if Result = '' then '' else LIST_SEPARATOR) + FRows[VI].Name;
      FRows[VI].Checked := pCheck;
    end;
end;

{ The first checked field that needs the field; '' = none. Refusal names a field whose needs are unknown. }
function TFieldSelection.NeededBy(const pName: string): string;
var
  VName, VError: string;
begin
  Result := '';
  for VName in CheckedNames do
    if not SameText(VName, pName) and MatchText(pName, Expand([VName], VError)) then
      Exit(VName);
end;

function TFieldSelection.CheckRow(const pName: string; out pMessage: string): Boolean;
var
  VNeeded: TArray<string>;
  VError, VAdded: string;
begin
  VNeeded := Expand([pName], VError);
  Result := VError = '';
  if not Result then
  begin
    pMessage := pName + ' cannot be selected: ' + VError;
    Exit;
  end;
  Unchecked([pName], True);
  VAdded := Unchecked(VNeeded, True);
  pMessage := if VAdded = '' then '' else pName + ' needs ' + VAdded + ': added';
end;

function TFieldSelection.SetChecked(pIndex: Integer; pValue: Boolean; out pMessage: string): Boolean;
var
  VRow: TFsRow;
  VNeeded: string;
begin
  pMessage := '';
  if (pIndex < 0) or (pIndex >= Length(FRows)) then
    Exit(False);
  VRow := FRows[pIndex];
  if VRow.Checked = pValue then
    Exit(True);
  if VRow.Locked <> '' then
  begin
    pMessage := VRow.Name + ': ' + VRow.Locked;
    Exit(False);
  end;
  if pValue then
    Exit(CheckRow(VRow.Name, pMessage));
  VNeeded := NeededBy(VRow.Name);
  Result := VNeeded = '';
  if Result then
    FRows[pIndex].Checked := False
  else
    pMessage := VRow.Name + ' stays: ' + VNeeded + ' needs it';
end;

procedure TFieldSelection.SetAll(pValue: Boolean);
var
  VI: Integer;
  VMessage: string;
begin
  for VI := 0 to High(FRows) do
    if FRows[VI].Locked = '' then
      if pValue then
        SetChecked(VI, True, VMessage)
      else
        FRows[VI].Checked := False;
end;

function TFieldSelection.Names: string;
begin
  Result := string.Join(',', ExpandSelection(CheckedNames, FFields));
end;

function TFieldSelection.MissingFields: string;
var
  VAll: TArray<string>;
  VError: string;
begin
  VAll := Expand(CheckedNames, VError);
  if VError <> '' then
    Exit(VError);
  Result := Unchecked(VAll, False);
  if Result <> '' then
    Result := 'the selected fields also need ' + Result + ': added on OK';
end;

function TFieldSelection.Refusal: string;
begin
  Result := FNoTable;
  if (Result = '') and (Length(Expand(CheckedNames, Result)) = 0) and (Result = '') then
    Result := 'select at least one field (the persistent fields can be deleted in the form designer)';
end;

function TFieldSelection.RemovedComponents: TArray<string>;
var
  VRow: TFsRow;
begin
  Result := nil;
  for VRow in FRows do
    if (VRow.Component <> '') and not VRow.Checked then
      Result := Result + [VRow.Component];
end;

function TFieldSelection.Summary: string;
var
  VRow: TFsRow;
  VAll, VAdded: Integer;
begin
  VAll := 0;
  VAdded := 0;
  for VRow in FRows do
    if VRow.Locked = '' then
    begin
      Inc(VAll);
      if VRow.Checked and (VRow.Component = '') then
        Inc(VAdded);
    end;
  Result := Format('%d of %d fields selected: %d to add, %d to remove', [Length(CheckedNames), VAll, VAdded,
    Length(RemovedComponents)]);
end;

{ ---- the plan ---- }

function TFsPlan.CheckedCount: Integer;
var
  VChange: TFsChange;
begin
  Result := 0;
  for VChange in Changes do
    if VChange.Checked then
      Inc(Result);
end;

procedure TFsPlan.SetAll(pValue: Boolean);
var
  VI: Integer;
begin
  for VI := 0 to High(Changes) do
    Changes[VI].Checked := pValue and (Changes[VI].Blocked = '');
end;

{ The component of a target `uOrders.dfm qryOrdersQTY`. }
function LastWord(const pText: string): string;
var
  VWord: string;
begin
  Result := '';
  for VWord in pText.Split([' ']) do
    Result := VWord;
end;

procedure TFsPlan.KeepAllBut(const pComponents: TArray<string>);
var
  VI: Integer;
begin
  for VI := 0 to High(Changes) do
    if (Changes[VI].Op = OP_DELETE) and (Changes[VI].Blocked = '')
      and not MatchText(LastWord(Changes[VI].Target), pComponents) then
    begin
      Changes[VI].Blocked := KEPT_FIELD;
      Changes[VI].Checked := False;
    end;
end;

function TFsPlan.SelectFileText: string;
var
  VChange: TFsChange;
begin
  Result := '';
  for VChange in Changes do
    if VChange.Checked then
      Result := Result + IntToStr(VChange.Id) + sLineBreak;
  if (Result <> '') and (PlanId <> '') then
    Result := PLAN_LINE + PlanId + sLineBreak + Result;
end;

{ ---- command lines ---- }

function DfmArgs(const pDfm, pDataset: string): string;
begin
  Result := '--dfm "' + pDfm + '"' + (if pDataset = '' then '' else ' --dataset ' + pDataset);
end;

function ReadDfmArgs(const pDfm, pDataset, pTail: string): string;
begin
  Result := DfmArgs(pDfm, pDataset) + ' --direction dfm-to-repo ' + pTail
end;

function WriteDfmArgs(const pDfm, pDataset, pNames, pTail: string): string;
begin
  Result := DfmArgs(pDfm, pDataset) + ' --names "' + pNames + '" --direction repo-to-dfm ' + pTail;
end;

function SelectArg(const pFile: string): string;
begin
  Result := '--select "' + pFile + '"';
end;

function ApplyLog(const pOutput: string; pMaxLines: Integer): string;
var
  VLine: string;
  VKept, VShown: TArray<string>;
  VI: Integer;
begin
  VKept := nil;
  for VLine in pOutput.Split([#13, #10]) do
    if StartsText(LOG_STARTS[0], VLine) or StartsText(LOG_STARTS[1], VLine) or StartsText(LOG_STARTS[2], VLine)
      or StartsText(LOG_STARTS[3], VLine) then
      VKept := VKept + [VLine];
  if Length(VKept) = 0 then
    Exit(Trim(pOutput));
  if Length(VKept) <= pMaxLines then
    Exit(string.Join(sLineBreak, VKept));
  VShown := nil;
  for VI := 0 to pMaxLines - 2 do
    VShown := VShown + [VKept[VI]];
  VShown := VShown + [Format('... %d more lines', [Length(VKept) - pMaxLines]), VKept[High(VKept)]];
  Result := string.Join(sLineBreak, VShown);
end;

{ ---- after a write ---- }

function ReloadStep(pExitCode: Integer; pOpen, pDirty, pChanged: Boolean): TFsReload;
begin
  if not (pOpen and pChanged) then
    Result := frNone
  else if pDirty then
    Result := frDirty
  else
    Result := if pExitCode = 0 then frReload else frAsk;
end;

function ApplyNotice(pReload: TFsReload; const pFile, pError: string): string;
const
  WRITTEN = ' was written to disk, NOT reloaded';
  OLDER = ': your editor buffer is older.';
begin
  case pReload of
    frDirty:
      Result := pFile + WRITTEN + OLDER + ' Saving it overwrites what was written; close the form without saving to get the written one.';
    frFailed:
      Result := pFile + WRITTEN + ' (' + pError + ')' + OLDER;
    frAsk:
      Result := pFile + ' was changed on disk by a run that failed, NOT reloaded' + OLDER;
  else
    Result := '';
  end;
end;

end.
