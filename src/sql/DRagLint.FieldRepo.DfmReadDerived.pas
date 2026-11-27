unit DRagLint.FieldRepo.DfmReadDerived;

{ drag-lint 1.56 -- lane LIN-2: read-dfm marks a field derived and proposes its DL_FIELD_INPUTS rows as UNCHECKED
  change-set rows (design 2026-11-27-derived-field-lineage-design.md sections 3.1, 3.2, 3.3).
  The unit registers ONE planner extension (RegisterDfmrPlanExtension, the call line of lane GCR-2 in
  DRagLint.FieldRepo.DfmReadPlan): after the planner's own changes are planned it asks the lineage model
  (DRagLint.FieldRepo.Lineage, lane LIN-1) about every persistent DATA field for which the read found no table
  column, and for a field code fills from other fields it adds
    insert DL_FIELDS_INFO  HOME|FIELD   FIELD_KIND 1, DERIVED_KIND, the lineage block in NOTES
    insert DL_FIELD_INPUTS HOME|FIELD||ALIAS   one per other table an input sits in, when exactly one path is chosen
  all UNCHECKED. It only reads: the index, the repository (SELECT) and the plan.
  The 1.56 cut: the home table is the table of the field's own dataset (`by dataset`); home by grid, the ladder for a
  dataset without a table, override bindings, the editor display and the `repo check` codes are 1.57.
  Nothing is proposed for a field of kind unknown, for a unit the index does not hold and for a unit that changed
  after it was indexed (a warning line each: no guess).
  The project index is the value of `--db` on the command line of `repo read-dfm`; without it the read says
  `lineage: skipped (no index)` and is the read of 1.55. The unit has no public surface: its initialization registers
  the extension. }

interface

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.Schema,  // dl:ok uses-global-census -- the named constants are the whole contract this unit draws; the unit pair travels together
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DfmRead,
  DRagLint.FieldRepo.DfmReadPlan,
  DRagLint.FieldRepo.RelationGraph,
  DRagLint.FieldRepo.RelationRepo,
  DRagLint.FieldRepo.Lineage;  // dl:ok uses-global-census -- the named constants are the whole contract this unit draws; the unit pair travels together

const
  NO_INDEX_LINE = 'lineage: skipped (no index)'; // the one line of a read that was given no project index
  BLOCK_OPEN = '[dl:lineage 1]'; // first line of the machine-owned lineage block of NOTES (design 3.2)
  BLOCK_CLOSE = '[/dl:lineage]';
  INDEX_FLAG = '--db';
  UNIT_EXT = '.pas';
  LINE_BREAK = #13#10;
  NONE_TEXT = '-';
  LIST_SEP = ', ';
  REASON_SEP = '; ';
  MAX_WRITES = 5; // writing sites listed in a block; the rest is counted in `more:` (design 3.2)
  LAST_ASCII = #126;
  NOT_ASCII = '?';
  COL_KIND = 'FIELD_KIND';
  COL_TABLE = 'TABLE_NAME';
  COL_FIELD = 'FIELD_NAME';
  COL_BINDING = 'BINDING';
  COL_ALIAS = 'ALIAS';
  COL_PATH = 'PATH';
  COL_TARGET = 'TARGET_TABLE';
  SQL_FIELD_ROW = 'SELECT "FIELD_KIND", "DERIVED_KIND", "NOTES" FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME" = :T ' +
    'AND "FIELD_NAME" = :F';
  SQL_INPUT_ALIASES = 'SELECT "ALIAS" FROM "DL_FIELD_INPUTS" WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F ' +
    'AND "BINDING" = ''''';
  MSG_SKIPPED = 'lineage: skipped (%s)';
  MSG_OLD_SCHEMA = 'lineage: skipped (the repository is schema %d: derived fields need schema %d; run repo migrate --apply)';
  SCHEMA_WITH_DERIVED = 5; // DL_FIELDS_INFO.DERIVED_KIND exists (GC-S)
  MSG_PREFIX = 'lineage: '; // ELineageError messages start with it
  MSG_NOT_INDEXED = 'lineage: %s is not in the index: its %d fields without a table column are not looked at';
  MSG_STALE = 'lineage: %s: nothing proposed for its %d fields without a table column (reindex, then read again)';
  MSG_NO_INPUT = '%s %s %s: no table: written in code, no field input';
  MSG_UNKNOWN = '%s %s %s: derived(unknown): %s: nothing proposed';
  MSG_NO_HOME = '%s %s %s: no table: derived(%s) (inputs %s): the dataset has no table, nothing proposed';
  MSG_PLAIN_ROW = '%s.%s: derived(%s) by %s %s, but the repository has the field as a plain field: not marked';
  MSG_BROKEN_BLOCK = '%s.%s: the lineage block in NOTES is broken (no %s): NOTES not changed';
  MSG_UNPLACED = '%s.%s input %s: %s: no DL_FIELD_INPUTS row proposed';
  WHY_NO_DATASET = 'not a field of a dataset of the form';
  WHY_NO_TABLE = 'dataset of input %s has no table';
  WHY_NO_PATH = 'no path %s -> %s';
  WHY_PATHS = '%d paths to %s, none chosen';
  NEW_ROW_TEXT = 'derived(%s); inputs %s';
  NEW_INPUT_TEXT = 'PATH=%s; TARGET_TABLE=%s (rule %s)';
  NOTES_OLD_TEXT = '(lineage block)';
  NOTES_NEW_TEXT = 'lineage block: derived(%s); inputs %s';
  HOME_TEXT = '%s by dataset %s.%s';
  WRITE_TEXT = '%s:%d';
  EVENT_TEXT = ' event %s';
  LOOP_TEXT = '%s (%s)';
  MACRO_OWN = '{{%s}}';
  MACRO_OTHER = '{{%s.%s}}';
  RX_WORD = '\b%s\b';

type
  { One input of a derived field, placed or not. }
  TPlacedInput = record
    Display: string; // the input as the model names it
    Component: string; // persistent field component, '' = read by name
    Macro: string; // {{F}} or {{ALIAS.F}}; '' = unplaced
    Why: string; // why it is unplaced
    Table: string; // the input's table; '' = not known
    Alias: string; // '' = the home table
    Path: string;
    Rule: string;
  end;

  { The derived fields of one read. Lives for one call of the extension. }
  TDerivedPlanner = class  // dl:ok high-response@dde6 -- REVIEWED 2026-11-27 LIN-2: one private planner object for one call of the extension -- it joins the plan host, the lineage model, the repository rows and the relation graph by design; splitting it would only pass the same four references around
  private
    FHost: TDfmrPlanHost;
    FModel: TFieldLineageModel;
    FQuery: TFDQuery;
    FGraph: TFrRelationGraph;
    function Graph: TFrRelationGraph;
    function DatasetTable(const pReport: TDfmrDatasetReport; const pDataset, pField: string): string;
    function Place(const pReport: TDfmrDatasetReport; const pHome: string; const pInput: TLineageInput): TPlacedInput;
    function PlaceAll(const pReport: TDfmrDatasetReport; const pHome: string;
      const pInputs: TArray<TLineageInput>): TArray<TPlacedInput>;
    function Block(const pReport: TDfmrDatasetReport; const pHome: string; const pField: TLineageField;
      const pPlaced: TArray<TPlacedInput>): string;
    function StoredAliases(const pHome, pFieldName: string): TArray<string>;
    procedure PlanInputs(const pHome, pFieldName: string; const pPlaced: TArray<TPlacedInput>);
    procedure PlanField(const pReport: TDfmrDatasetReport; const pRef: TDfmrFieldRef; const pField: TLineageField);
    procedure ReadDataset(const pReport: TDfmrDatasetReport);
  public
    constructor Create(pHost: TDfmrPlanHost; pModel: TFieldLineageModel);
    destructor Destroy; override;
    procedure Run;
  end;

{ The project index of the read: the value of `--db` on the command line; '' = none given. }
function IndexDb: string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 1 to ParamCount - 1 do
    if SameText(ParamStr(VI), INDEX_FLAG) then
      Exit(ParamStr(VI + 1));
end;

function Pair(const pName, pValue: string): TDfmrPair;
begin
  Result.Name := pName;
  Result.Value := pValue;
end;

function Ascii(const pText: string): string;
var
  VI: Integer;
begin
  Result := pText;
  for VI := 1 to Length(Result) do
    if Result[VI] > LAST_ASCII then
      Result[VI] := NOT_ASCII;
end;

function ListOrNone(const pItems: TArray<string>; const pSeparator: string): string;
begin
  Result := if Length(pItems) = 0 then NONE_TEXT else string.Join(pSeparator, pItems);
end;

function AddOnce(const pList: TArray<string>; const pItem: string): TArray<string>;
begin
  Result := pList;
  if not MatchText(pItem, pList) then
    Result := Result + [pItem];
end;

function FindPlaced(const pPlaced: TArray<TPlacedInput>; const pDisplay: string; out pFound: TPlacedInput): Boolean;
var
  VPlaced: TPlacedInput;
begin
  pFound := Default(TPlacedInput);
  for VPlaced in pPlaced do
    if SameText(VPlaced.Display, pDisplay) then
    begin
      pFound := VPlaced;
      Exit(True);
    end;
  Result := False;
end;

function Macros(const pPlaced: TArray<TPlacedInput>; const pInputs: TArray<TLineageInput>): TArray<string>;
var
  VInput: TLineageInput;
  VPlaced: TPlacedInput;
begin
  Result := nil;
  for VInput in pInputs do
    if FindPlaced(pPlaced, VInput.DisplayName, VPlaced) and (VPlaced.Macro <> '') then
      Result := AddOnce(Result, VPlaced.Macro);
end;

function Unplaced(const pPlaced: TArray<TPlacedInput>; const pInputs: TArray<TLineageInput>): TArray<string>;
var
  VInput: TLineageInput;
  VPlaced: TPlacedInput;
begin
  Result := nil;
  for VInput in pInputs do
    if FindPlaced(pPlaced, VInput.DisplayName, VPlaced) and (VPlaced.Macro = '') then
      Result := AddOnce(Result, VPlaced.Display + ': ' + VPlaced.Why);
end;

{ The statement text with the field components of the written field and of the placed inputs as macros (design
  DL-5); an access by name stays as written. }
function WithMacros(const pText, pOwnComponent, pOwnField: string; const pPlaced: TArray<TPlacedInput>): string;
var
  VPlaced: TPlacedInput;
begin
  Result := pText;
  if pOwnComponent <> '' then
    Result := TRegEx.Replace(Result, Format(RX_WORD, [TRegEx.Escape(pOwnComponent)]), Format(MACRO_OWN, [pOwnField]),
      [roIgnoreCase]);
  for VPlaced in pPlaced do
    if (VPlaced.Component <> '') and (VPlaced.Macro <> '') then
      Result := TRegEx.Replace(Result, Format(RX_WORD, [TRegEx.Escape(VPlaced.Component)]), VPlaced.Macro,
        [roIgnoreCase]);
  Result := Ascii(Result);
end;

{ pNotes with its lineage block replaced by pBlock; a cell without a block gets it appended after one empty line.
  pBroken: an opening line without the closing one; the text is returned unchanged then. }
function WithBlock(const pNotes, pBlock: string; out pBroken: Boolean): string;
var
  VOpen, VClose: Integer;
begin
  pBroken := False;
  VOpen := Pos(BLOCK_OPEN, pNotes);
  if VOpen = 0 then
    Exit(if pNotes = '' then pBlock else pNotes + LINE_BREAK + LINE_BREAK + pBlock);
  VClose := PosEx(BLOCK_CLOSE, pNotes, VOpen);
  pBroken := VClose = 0;
  if pBroken then
    Exit(pNotes);
  Result := Copy(pNotes, 1, VOpen - 1) + pBlock + Copy(pNotes, VClose + Length(BLOCK_CLOSE), MaxInt);
end;

{ ---- TDerivedPlanner ---- }

constructor TDerivedPlanner.Create(pHost: TDfmrPlanHost; pModel: TFieldLineageModel);
begin
  inherited Create;
  FHost := pHost;
  FModel := pModel;
  FQuery := TFDQuery.Create(nil);
  FQuery.Connection := pHost.Repo;
end;

destructor TDerivedPlanner.Destroy;
begin
  FGraph.Free;
  FQuery.Free;
  inherited;
end;

function TDerivedPlanner.Graph: TFrRelationGraph;
var
  VSkipped: TArray<string>;
begin
  if FGraph = nil then
    FGraph := LoadRelationGraph(FHost.Repo, VSkipped);
  Result := FGraph;
end;

{ The table a field of a dataset of the form belongs to: what the read found for the persistent field, else the one
  table of the dataset; '' = none (a join, a dataset without a table, no such dataset). }
function TDerivedPlanner.DatasetTable(const pReport: TDfmrDatasetReport; const pDataset, pField: string): string;
var
  VReport: TDfmrDatasetReport;
  VRef: TDfmrFieldRef;
  VDataset: TDfmrDataset;
begin
  for VReport in FHost.Datasets do
    if SameText(VReport.DfmFile, pReport.DfmFile) and SameText(VReport.Dataset, pDataset) then
    begin
      for VRef in VReport.Fields do
        if SameText(VRef.FieldName, pField) and (VRef.TableName <> '') then
          Exit(VRef.TableName);
      Exit(VReport.TableName);
    end;
  for VDataset in FHost.FormOf(pReport.DfmFile).Datasets do // a read of one dataset (--dataset) reports only that one
    if SameText(VDataset.Name, pDataset) then
      Exit(SourceOf(VDataset).TableName);
  Result := '';
end;

function TDerivedPlanner.Place(const pReport: TDfmrDatasetReport; const pHome: string;
  const pInput: TLineageInput): TPlacedInput;
var
  VChoice: TFrPathChoice;
  VStep: TFrRelation;
begin
  Result := Default(TPlacedInput);
  Result.Display := pInput.DisplayName;
  Result.Component := pInput.Component;
  if (pInput.Dataset = '') or (pInput.FieldName = '') then
  begin
    Result.Why := WHY_NO_DATASET;
    Exit;
  end;
  Result.Table := DatasetTable(pReport, pInput.Dataset, pInput.FieldName);
  if Result.Table = '' then
  begin
    Result.Why := Format(WHY_NO_TABLE, [pInput.Dataset]);
    Exit;
  end;
  if SameText(Result.Table, pHome) then
  begin
    Result.Macro := Format(MACRO_OWN, [UpperCase(pInput.FieldName)]);
    Exit;
  end;
  VChoice := Graph.Choose(pHome, Result.Table, '', nil);
  if VChoice.Chosen < 0 then
  begin
    Result.Why := if Length(VChoice.Paths) = 0 then Format(WHY_NO_PATH, [pHome, Result.Table])
      else Format(WHY_PATHS, [Length(VChoice.Paths), Result.Table]);
    Exit;
  end;
  Result.Path := VChoice.Paths[VChoice.Chosen].Text;
  for VStep in VChoice.Paths[VChoice.Chosen].Steps do
    FHost.AddRelationChange(VStep, False); // neither stored nor planned: proposed UNCHECKED, with the input row
  Result.Alias := DefaultInputAlias(UpperCase(Result.Table), 1);
  Result.Rule := PathRuleName(VChoice.Rule);
  Result.Macro := Format(MACRO_OTHER, [Result.Alias, UpperCase(pInput.FieldName)]);
end;

function TDerivedPlanner.PlaceAll(const pReport: TDfmrDatasetReport; const pHome: string;
  const pInputs: TArray<TLineageInput>): TArray<TPlacedInput>;
var
  VInput: TLineageInput;
  VFound: TPlacedInput;
begin
  Result := nil;
  for VInput in pInputs do
    if not FindPlaced(Result, VInput.DisplayName, VFound) then
      Result := Result + [Place(pReport, pHome, VInput)];
end;

{ The lineage block of design 3.2: kind and home once, then one group of lines per writing site. }
function TDerivedPlanner.Block(const pReport: TDfmrDatasetReport; const pHome: string; const pField: TLineageField;
  const pPlaced: TArray<TPlacedInput>): string;
var
  VLines: TStringList;
  VWrite: TLineageWrite;
  VVia: string;
  VI: Integer;
begin
  VLines := TStringList.Create;
  try
    VLines.LineBreak := LINE_BREAK;
    VLines.TrailingLineBreak := False;
    VLines.Add(BLOCK_OPEN);
    VLines.Add('kind: ' + pField.Kind);
    VLines.Add('home: ' + Format(HOME_TEXT, [pHome, FHost.FormOf(pReport.DfmFile).FormName, pReport.Dataset]));
    for VI := 0 to High(pField.Writes) do
    begin
      if VI = MAX_WRITES then
      begin
        VLines.Add('more: ' + IntToStr(Length(pField.Writes) - MAX_WRITES));
        Break;
      end;
      VWrite := pField.Writes[VI];
      VLines.Add('write: ' + Format(WRITE_TEXT, [VWrite.Routine, VWrite.Line])
        + (if VWrite.Event = '' then '' else Format(EVENT_TEXT, [VWrite.Event])));
      VLines.Add('inputs: ' + ListOrNone(Macros(pPlaced, VWrite.Inputs), LIST_SEP));
      VLines.Add('expr: ' + WithMacros(VWrite.ExprText, pField.Component, UpperCase(pField.FieldName), pPlaced));
      for VVia in VWrite.Via do
        VLines.Add('via: ' + WithMacros(VVia, pField.Component, UpperCase(pField.FieldName), pPlaced));
      if VWrite.LoopText <> '' then
        VLines.Add('loop: ' + Format(LOOP_TEXT, [Ascii(VWrite.LoopText),
          DatasetTable(pReport, VWrite.LoopDataset, '')]));
      VLines.Add('unknown: ' + ListOrNone(VWrite.Unknown, REASON_SEP));
      VLines.Add('unplaced: ' + ListOrNone(Unplaced(pPlaced, VWrite.Inputs), REASON_SEP));
    end;
    VLines.Add(BLOCK_CLOSE);
    Result := VLines.Text;
  finally
    VLines.Free;
  end;
end;

{ The aliases the repository has for the field's default binding. }
function TDerivedPlanner.StoredAliases(const pHome, pFieldName: string): TArray<string>;
begin
  Result := nil;
  FQuery.Open(SQL_INPUT_ALIASES, [pHome, pFieldName]);
  try
    while not FQuery.Eof do
    begin
      Result := Result + [FQuery.Fields[0].AsString];
      FQuery.Next;
    end;
  finally
    FQuery.Close;
  end;
end;

{ One insert per input alias the repository does not have; an unplaced input is a warning. }
procedure TDerivedPlanner.PlanInputs(const pHome, pFieldName: string; const pPlaced: TArray<TPlacedInput>);
var
  VPlaced: TPlacedInput;
  VSeen: TArray<string>;
begin
  VSeen := StoredAliases(pHome, pFieldName);
  for VPlaced in pPlaced do
  begin
    if VPlaced.Macro = '' then
      FHost.Warn(Format(MSG_UNPLACED, [pHome, pFieldName, VPlaced.Display, VPlaced.Why]));
    if (VPlaced.Alias = '') or MatchText(VPlaced.Alias, VSeen) then
      Continue;
    VSeen := VSeen + [VPlaced.Alias];
    FHost.AddRowChange(fcoInsert, REPO_TABLE_FIELD_INPUTS, pHome + '|' + pFieldName + '||' + VPlaced.Alias, '', '',
      Format(NEW_INPUT_TEXT, [VPlaced.Path, UpperCase(VPlaced.Table), VPlaced.Rule]),
      [Pair(COL_TABLE, pHome), Pair(COL_FIELD, pFieldName), Pair(COL_BINDING, ''), Pair(COL_ALIAS, VPlaced.Alias),
      Pair(COL_PATH, VPlaced.Path), Pair(COL_TARGET, UpperCase(VPlaced.Table))], False);
  end;
end;

{ A derived field with a known kind and a home table: its row (insert, or the cells that differ) and its inputs. }
procedure TDerivedPlanner.PlanField(const pReport: TDfmrDatasetReport; const pRef: TDfmrFieldRef;
  const pField: TLineageField);
var
  VHome, VName, VBlock, VNotes, VNewNotes, VOldKind, VInputs: string;
  VPlaced: TArray<TPlacedInput>;
  VExists, VBroken: Boolean;
begin
  VHome := UpperCase(pReport.TableName);
  VName := UpperCase(pRef.FieldName);
  VPlaced := PlaceAll(pReport, VHome, pField.Inputs);
  VBlock := Block(pReport, VHome, pField, VPlaced);
  VInputs := ListOrNone(Macros(VPlaced, pField.Inputs), LIST_SEP);
  FQuery.Open(SQL_FIELD_ROW, [VHome, VName]);
  try
    VExists := not FQuery.Eof;
    VOldKind := if VExists then FQuery.Fields[1].AsString else '';
    VNotes := if VExists then FQuery.Fields[2].AsString else '';
  finally
    FQuery.Close;
  end;
  if VExists and (VOldKind = '') then
  begin
    FHost.Warn(Format(MSG_PLAIN_ROW, [VHome, VName, pField.Kind, pReport.DfmName, pReport.Dataset]));
    Exit;
  end;
  VNewNotes := WithBlock(VNotes, VBlock, VBroken);
  if not VExists then
    FHost.AddFieldChange(fcoInsert, VHome, VName, '', '', Format(NEW_ROW_TEXT, [pField.Kind, VInputs]),
      [Pair(COL_KIND, IntToStr(FrKindToCode(frkData))), Pair(REPO_COL_DERIVED_KIND, pField.Kind),
      Pair(REPO_COL_NOTES, VNewNotes)], False)
  else
  begin
    if VOldKind <> pField.Kind then
      FHost.AddFieldChange(fcoUpdate, VHome, VName, REPO_COL_DERIVED_KIND, VOldKind, pField.Kind, nil, False);
    if VBroken then
      FHost.Warn(Format(MSG_BROKEN_BLOCK, [VHome, VName, BLOCK_CLOSE]))
    else if VNewNotes <> VNotes then
      FHost.AddFieldChange(fcoUpdate, VHome, VName, REPO_COL_NOTES, NOTES_OLD_TEXT,
        Format(NOTES_NEW_TEXT, [pField.Kind, VInputs]), [Pair(REPO_COL_NOTES, VNewNotes)], False);
  end;
  PlanInputs(VHome, VName, VPlaced);
end;

{ The persistent data fields of one dataset the read found no table column for. }
procedure TDerivedPlanner.ReadDataset(const pReport: TDfmrDatasetReport);
var
  VCandidates: TArray<TDfmrFieldRef>;
  VRef: TDfmrFieldRef;
  VUnit: TLineageUnit;
  VField: TLineageField;
begin
  VCandidates := nil;
  for VRef in pReport.Fields do
    if (VRef.Kind = frkData) and (VRef.TableName = '') then
      VCandidates := VCandidates + [VRef];
  if Length(VCandidates) = 0 then
    Exit;
  VUnit := FModel.ReadUnit(TPath.GetFullPath(ChangeFileExt(pReport.DfmFile, UNIT_EXT)));
  if not VUnit.Indexed then
  begin
    FHost.Warn(Format(MSG_NOT_INDEXED, [ChangeFileExt(pReport.DfmName, UNIT_EXT), Length(VCandidates)]));
    Exit;
  end;
  if VUnit.Stale then
  begin
    FHost.Warn(Format(MSG_STALE, [VUnit.StaleReason, Length(VCandidates)]));
    Exit;
  end;
  for VRef in VCandidates do
  begin
    VUnit.Find(pReport.Dataset, VRef.FieldName, VField);
    if (not VField.Derived) and (VField.WritesWithoutFieldInput > 0) then
      FHost.Warn(Format(MSG_NO_INPUT, [pReport.DfmName, pReport.Dataset, VRef.FieldName]));
    if not VField.Derived then
      Continue;
    if VField.Kind = LINEAGE_KIND_UNKNOWN then
      FHost.Warn(Format(MSG_UNKNOWN, [pReport.DfmName, pReport.Dataset, VRef.FieldName,
        ListOrNone(VField.Unknown, REASON_SEP)]))
    else if pReport.TableName = '' then
      FHost.Warn(Format(MSG_NO_HOME, [pReport.DfmName, pReport.Dataset, VRef.FieldName, VField.Kind,
        ListOrNone(Macros(PlaceAll(pReport, '', VField.Inputs), VField.Inputs), LIST_SEP)]))
    else
      PlanField(pReport, VRef, VField);
  end;
end;

procedure TDerivedPlanner.Run;
var
  VReport: TDfmrDatasetReport;
begin
  for VReport in FHost.Datasets do
    ReadDataset(VReport);
end;

{ True when a dataset of the read has a persistent data field with no table column (the ones the lineage looks at). }
function HasCandidates(pHost: TDfmrPlanHost): Boolean;
var
  VReport: TDfmrDatasetReport;
  VRef: TDfmrFieldRef;
begin
  for VReport in pHost.Datasets do
    for VRef in VReport.Fields do
      if (VRef.Kind = frkData) and (VRef.TableName = '') then
        Exit(True);
  Result := False;
end;

{ The planner extension (TDfmrPlanExtension): adds the derived-field changes of a read to its plan. Only UNCHECKED
  changes and warning lines; writes nothing. An index that does not open, or has no lineage facts, is one
  `lineage: skipped (...)` line, never an exception. }
procedure PlanDerivedFields(pHost: TDfmrPlanHost);
var
  VIndex: string;
  VModel: TFieldLineageModel;
  VPlanner: TDerivedPlanner;
begin
  VIndex := IndexDb;
  if VIndex = '' then
  begin
    // a note about work NOT done: said only when a dataset has a field the lineage would have looked at
    if HasCandidates(pHost) then
      pHost.Warn(NO_INDEX_LINE);
    Exit;
  end;
  if RepoSchemaVersion(pHost.Repo) < SCHEMA_WITH_DERIVED then
  begin
    // DERIVED_KIND is not a column of a schema-4 repository: say so once, read nothing (no exception)
    if HasCandidates(pHost) then
      pHost.Warn(Format(MSG_OLD_SCHEMA, [RepoSchemaVersion(pHost.Repo), SCHEMA_WITH_DERIVED]));
    Exit;
  end;
  try
    VModel := TFieldLineageModel.Create(VIndex);
  except
    on E: ELineageError do
    begin
      pHost.Warn(Format(MSG_SKIPPED, [if E.Message.StartsWith(MSG_PREFIX) then E.Message.Substring(Length(MSG_PREFIX)) else E.Message]));
      Exit;
    end;
  end;
  try
    VPlanner := TDerivedPlanner.Create(pHost, VModel);
    try
      VPlanner.Run;
    finally
      VPlanner.Free;
    end;
  finally
    VModel.Free;
  end;
end;

initialization
  RegisterDfmrPlanExtension(PlanDerivedFields);

end.
