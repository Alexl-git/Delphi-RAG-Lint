unit DRagLint.FieldRepo.Check;

{ drag-lint 1.53 -- lane FR-MODEL: `repo check`, the read-only consistency check of a repository
  (design 2026-11-22-field-repository-v2-design.md section 4.6): kind / flag consistency (4.1), lookup wiring
  (4.2), calc macro targets and dependency cycles (4.3), layout-event rows; 1.54 (rulings 2026-11-23): event bodies,
  ALIGNMENT, grid column rows. The 1.54 editor calls the same function to warn early at save (Q13). 1.55 (lane XTABLE,
  design 2026-11-26-cross-table-fields-design.md 2.3): input aliases, their paths, relations and their parent keys. }

interface

uses
  FireDAC.Comp.Client;

type
  /// <summary>How serious a finding is; both make `repo check` exit 1.</summary>
  TFrCheckSeverity = (fcsError, fcsWarn);

  /// <summary>One finding of `repo check`.</summary>
  TFrCheckFinding = record
    /// <summary>fcsError or fcsWarn.</summary>
    Severity: TFrCheckSeverity;
    /// <summary>Stable code: kind-flag-mismatch, unknown-kind, lookup-incomplete, lookup-unknown-table,
    /// lookup-unknown-value, lookup-key-not-pk, calc-macro-error, calc-unknown-field, calc-cycle,
    /// event-macro-error, event-unknown-field, alignment-invalid, layout-event-unknown-field, layout-event-field-type,
    /// grid-column-unknown-field; schema 4: input-alias-undeclared, input-unknown-field, input-no-field-row,
    /// input-path-broken, input-target-mismatch, binding-no-default, binding-alias-set, relation-source-invalid,
    /// relation-no-columns, relation-two-defaults, relation-key-unknown (WARN), relation-key-not-unique, relation-fk-missing,
    /// relation-fk-gone (WARN), relation-fk-mismatch.</summary>
    Code: string;
    /// <summary>Where: `TABLE.FIELD`, `TABLE.FIELD COLUMN` for an event body, `layout TYPE TABLE.FIELD EVENT` for a
    /// layout-event row, `grid FORM.VIEW.COLUMN` for a grid column row, `input TABLE.FIELD [BINDING] ALIAS` for an input row,
    /// `relation NAME` for a relation.</summary>
    Where: string;
    /// <summary>Human-readable explanation, ASCII.</summary>
    Message: string;
  end;

/// <summary>Checks a repository (any schema version); never writes.</summary>
/// <param name="pConn">Open repository connection (read-only is enough).</param>
/// <returns>Every finding, in the order kind/flag, lookup wiring, calc bodies, cycles, layout events, event bodies,
/// alignment, grid columns; empty = clean.</returns>
/// <remarks>A schema-1 file has no CALC_BODY and no layout-event table, a schema-2 file no event columns and no grid
/// columns: those checks are skipped. A view-level layout event (FIELD_NAME '') needs no field row. An internal-calc field
/// may read its own stored value. FIELD_KIND NULL
/// reads as data (so a legacy ISCALCULATED row with a NULL kind is a kind/flag mismatch until `repo migrate`).
/// A cycle is named once, rotated to start at its alphabetically first field: `A -> B -> A`; a cycle through input aliases
/// names every node `TABLE.FIELD` (`calc dependency cycle across tables`). Schema 4: a body may use `{{ALIAS.FIELD}}`
/// when the field declares ALIAS in its default binding; the alias's TARGET_TABLE must have FIELD.</remarks>
function CheckRepository(pConn: TFDConnection): TArray<TFrCheckFinding>;

/// <summary>Renders findings as text lines plus a summary line.</summary>
/// <param name="pFindings">The findings from CheckRepository.</param>
/// <returns>One line per finding `ERROR|WARN code where: message`, then `check: clean` or
/// `check: N findings (E errors, W warnings)`.</returns>
function RenderCheckText(const pFindings: TArray<TFrCheckFinding>): TArray<string>;

/// <summary>Renders findings as one JSON object.</summary>
/// <param name="pFindings">The findings from CheckRepository.</param>
/// <returns>`{"findings":[{"severity","code","where","message"}],"errors":E,"warnings":W}`.</returns>
function RenderCheckJson(const pFindings: TArray<TFrCheckFinding>): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.StrUtils,
  System.Variants,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.Kinds, // dl:unit DRagLint.FieldRepo.Kinds accepted -- fr_event_columns is the event column list the kinds unit owns; Check reads nothing else of it
  DRagLint.FieldRepo.CrossTable;

const
  VERSION_MODEL = 2;
  VERSION_EVENT_COLUMNS = 3;
  VERSION_CROSS_TABLE = 4;
  CODE_ALIAS_UNDECLARED = 'input-alias-undeclared';
  CODE_KEY_NOT_UNIQUE = 'relation-key-not-unique';
  CODE_FK_MISMATCH = 'relation-fk-mismatch';
  CODE_PATH_BROKEN = 'input-path-broken';

type
  TFieldRow = record
    TableName: string;
    FieldName: string;
    KindCode: Variant;
    IsCalc: Boolean;
    IsLookup: Boolean;
    IsPk: Boolean;
    DestTable: string;
    DestKey: string;
    DestValue: string;
    Body: string;
  end;

  TCycleColor = (ccWhite, ccGrey, ccBlack);

  { Schema 4: the declared aliases of each field (default binding; nil below schema 4) and each alias's target table. }
  TInputMaps = record
    Aliases: TDictionary<string, TArray<string>>;
    Targets: TDictionary<string, string>;
  end;

function Key(const pTable, pField: string): string;
begin
  Result := UpperCase(pTable) + '.' + UpperCase(pField);
end;

procedure Add(var pList: TArray<TFrCheckFinding>; pSeverity: TFrCheckSeverity; const pCode, pWhere, pMessage: string);
var
  VFinding: TFrCheckFinding;
begin
  VFinding.Severity := pSeverity;
  VFinding.Code := pCode;
  VFinding.Where := pWhere;
  VFinding.Message := pMessage;
  pList := pList + [VFinding];
end;

function LoadRows(pConn: TFDConnection; pHasBody: Boolean): TArray<TFieldRow>;
var
  VQuery: TFDQuery;
  VRow: TFieldRow;
  VBodyCol: string;
begin
  Result := nil;
  VBodyCol := if pHasBody then '"CALC_BODY"' else 'NULL';
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pConn;
    VQuery.Open('SELECT "TABLE_NAME", "FIELD_NAME", "FIELD_KIND", "ISCALCULATED", "ISLOOKUP", "PRIMARY_KEY", ' +  // dl:ok path-traversal@5054 -- REVIEWED 2026-11-23: SQL text, not a path -- TFDQuery.Open of a constant SELECT; the only variable part is a fixed NULL / column-name literal chosen by a Boolean
      '"DESTTABLE", "DESTKEY", "DESTVALUE", ' + VBodyCol + ' FROM "DL_FIELDS_INFO" ORDER BY "TABLE_NAME", "FIELD_NAME"');
    while not VQuery.Eof do
    begin
      VRow.TableName := Trim(VQuery.Fields[0].AsString);
      VRow.FieldName := Trim(VQuery.Fields[1].AsString);
      VRow.KindCode := VQuery.Fields[2].Value;
      VRow.IsCalc := VQuery.Fields[3].AsBoolean;
      VRow.IsLookup := VQuery.Fields[4].AsBoolean;
      VRow.IsPk := VQuery.Fields[5].AsBoolean;
      VRow.DestTable := Trim(VQuery.Fields[6].AsString);
      VRow.DestKey := Trim(VQuery.Fields[7].AsString);
      VRow.DestValue := Trim(VQuery.Fields[8].AsString);
      VRow.Body := VQuery.Fields[9].AsString;
      Result := Result + [VRow];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ Sorted, upper-cased, ';'-separated key list -> normal form for comparing key sets. }
function NormalKeys(const pKeys: string): string;
var
  VList: TStringList;
  VPart: string;
begin
  VList := TStringList.Create;
  try
    for VPart in pKeys.Split([';', ',']) do
      if Trim(VPart) <> '' then
        VList.Add(UpperCase(Trim(VPart)));
    VList.Sort;
    VList.Delimiter := ';';
    VList.StrictDelimiter := True;
    Result := VList.DelimitedText;
  finally
    VList.Free;
  end;
end;

procedure CheckKindFlags(const pRows: TArray<TFieldRow>; var pOut: TArray<TFrCheckFinding>);
var
  VRow: TFieldRow;
  VKind: TFrFieldKind;
  VWantCalc, VWantLookup: Boolean;
begin
  for VRow in pRows do
  begin
    if not FrKindCodeKnown(VRow.KindCode) then
    begin
      Add(pOut, fcsError, 'unknown-kind', VRow.TableName + '.' + VRow.FieldName,
        'FIELD_KIND ' + VarToStr(VRow.KindCode) + ' is not a known kind (1, 2, 3, 4, 5, 10 or NULL)');
      Continue;
    end;
    VKind := FrKindFromCode(VRow.KindCode);
    VWantCalc := VKind in [frkCalc, frkInternalCalc];
    VWantLookup := VKind = frkLookup;
    if (VRow.IsCalc <> VWantCalc) or (VRow.IsLookup <> VWantLookup) then
      Add(pOut, fcsError, 'kind-flag-mismatch', VRow.TableName + '.' + VRow.FieldName,
        Format('FIELD_KIND is %s (%d) but ISCALCULATED=%s ISLOOKUP=%s (expected ISCALCULATED=%s ISLOOKUP=%s)',
          [FrKindName(VKind), FrKindToCode(VKind), BoolToStr(VRow.IsCalc, True), BoolToStr(VRow.IsLookup, True),
           BoolToStr(VWantCalc, True), BoolToStr(VWantLookup, True)]));
  end;
end;

procedure CheckLookups(const pRows: TArray<TFieldRow>; pFields: TDictionary<string, string>;
  var pOut: TArray<TFrCheckFinding>);
var
  VRow, VOther: TFieldRow;
  VWhere, VPk: string;
  VTableKnown: Boolean;
begin
  for VRow in pRows do
  begin
    if not (FrKindCodeKnown(VRow.KindCode) and (FrKindFromCode(VRow.KindCode) = frkLookup)) then
      Continue;
    VWhere := VRow.TableName + '.' + VRow.FieldName;
    if (VRow.DestTable = '') or (VRow.DestValue = '') then
    begin
      Add(pOut, fcsError, 'lookup-incomplete', VWhere,
        'lookup wiring needs DESTTABLE and DESTVALUE (missing: ' +
        IfThen(VRow.DestTable = '', 'DESTTABLE', '') + IfThen((VRow.DestTable = '') and (VRow.DestValue = ''), ', ', '') +
        IfThen(VRow.DestValue = '', 'DESTVALUE', '') + ')');
      Continue;
    end;
    VTableKnown := False;
    for VOther in pRows do
      if SameText(VOther.TableName, VRow.DestTable) then
      begin
        VTableKnown := True;
        Break;
      end;
    if not VTableKnown then
    begin
      Add(pOut, fcsError, 'lookup-unknown-table', VWhere, 'DESTTABLE ' + VRow.DestTable + ' is not a repository table');
      Continue;
    end;
    if not pFields.ContainsKey(Key(VRow.DestTable, VRow.DestValue)) then
      Add(pOut, fcsError, 'lookup-unknown-value', VWhere,
        'DESTVALUE ' + VRow.DestTable + '.' + VRow.DestValue + ' is not a field of the lookup table');
    if VRow.DestKey <> '' then
    begin
      VPk := '';
      for VOther in pRows do
        if SameText(VOther.TableName, VRow.DestTable) and VOther.IsPk then
          VPk := VPk + IfThen(VPk = '', '', ';') + VOther.FieldName;
      if (VPk <> '') and (NormalKeys(VRow.DestKey) <> NormalKeys(VPk)) then
        Add(pOut, fcsWarn, 'lookup-key-not-pk', VWhere,
          'DESTKEY ' + VRow.DestKey + ' is not the primary key of ' + VRow.DestTable + ' (' + VPk + ')');
    end;
  end;
end;

{ Key of an input alias in the targets map. }
function AliasKey(const pTable, pField, pAlias: string): string;
begin
  Result := Key(pTable, pField) + '|' + UpperCase(pAlias);
end;

{ The inputs of one body of the field pKey (Key(table, field)). pAliases nil = schema below 4: the 1.53 grammar (an ALIAS.FIELD
  macro is the reserved error). pSelf <> '' = a calc body owned by pSelf, whose own write is not an input (CalcDependencies);
  '' = an event body. A malformed macro is a finding, Result False. }
function BodyInputs(const pKey, pSelf, pBody: string; pAliases: TDictionary<string, TArray<string>>; const pWhere: string;
  out pInputs: TArray<TFrInput>; var pOut: TArray<TFrCheckFinding>): Boolean;
var
  VDeclared, VNames: TArray<string>;
  VName: string;
  VInput: TFrInput;
  VMacro: TFrMacro;
  VIsCalc: Boolean;
begin
  Result := True;
  pInputs := nil;
  VIsCalc := pSelf <> '';
  try
    if pAliases = nil then
    begin
      if VIsCalc then
        VNames := CalcDependencies(pBody, pSelf)
      else
      begin
        VNames := nil;
        for VMacro in ParseMacros(pBody) do
          if not MatchText(VMacro.Name, VNames) then
            VNames := VNames + [VMacro.Name];
      end;
      for VName in VNames do
      begin
        VInput.Alias := '';
        VInput.Field := VName;
        pInputs := pInputs + [VInput];
      end;
    end
    else
    begin
      if not pAliases.TryGetValue(pKey, VDeclared) then
        VDeclared := nil;
      pInputs := CalcInputs(pBody, pSelf, VDeclared);
    end;
  except
    on E: EFrAliasError do
    begin
      Add(pOut, fcsError, CODE_ALIAS_UNDECLARED, pWhere, E.Message);
      Result := False;
    end;
    on E: EFrKindError do
    begin
      Add(pOut, fcsError, if VIsCalc then 'calc-macro-error' else 'event-macro-error', pWhere, E.Message);
      Result := False;
    end;
  end;
end;

{ The field key an aliased input names, '' (and a finding) when the target table has no such field. }
function ForeignTarget(const pTable, pField, pWhere: string; const pInput: TFrInput; pFields: TDictionary<string, string>;
  pTargets: TDictionary<string, string>; var pOut: TArray<TFrCheckFinding>): string;
var
  VTarget: string;
begin
  Result := '';
  if not pTargets.TryGetValue(AliasKey(pTable, pField, pInput.Alias), VTarget) then
    Exit;
  if pFields.ContainsKey(Key(VTarget, pInput.Field)) then
    Result := Key(VTarget, pInput.Field)
  else
    Add(pOut, fcsError, 'input-unknown-field', pWhere, 'macro {{' + pInput.Alias + '.' + pInput.Field + '}} names no field of ' +
      VTarget);
end;

{ Dependency edges (full TABLE.FIELD keys) of every body field; macro errors and unknown targets are findings. }
procedure CheckBodies(const pRows: TArray<TFieldRow>; pFields: TDictionary<string, string>;
  pAliases: TDictionary<string, TArray<string>>; pTargets: TDictionary<string, string>;
  pEdges: TDictionary<string, TArray<string>>; var pOut: TArray<TFrCheckFinding>);
var
  VRow: TFieldRow;
  VKept: TArray<string>;
  VInputs: TArray<TFrInput>;
  VInput: TFrInput;
  VWhere, VTarget: string;
begin
  for VRow in pRows do
  begin
    if not (FrKindCodeKnown(VRow.KindCode) and FrKindHasBody(FrKindFromCode(VRow.KindCode))) then
      Continue;
    if VRow.Body = '' then
      Continue;
    VWhere := VRow.TableName + '.' + VRow.FieldName;
    if not BodyInputs(Key(VRow.TableName, VRow.FieldName), VRow.FieldName, VRow.Body, pAliases, VWhere, VInputs, pOut) then
      Continue;
    VKept := nil;
    for VInput in VInputs do
      if VInput.Alias <> '' then
      begin
        VTarget := ForeignTarget(VRow.TableName, VRow.FieldName, VWhere, VInput, pFields, pTargets, pOut);
        if VTarget <> '' then
          VKept := VKept + [VTarget];
      end
      else if SameText(VInput.Field, VRow.FieldName) and (FrKindFromCode(VRow.KindCode) = frkInternalCalc) then
        Continue
      else if pFields.ContainsKey(Key(VRow.TableName, VInput.Field)) then
        VKept := VKept + [Key(VRow.TableName, VInput.Field)]
      else
        Add(pOut, fcsError, 'calc-unknown-field', VWhere, 'macro {{' + VInput.Field + '}} names no field of ' + VRow.TableName);
    pEdges.AddOrSetValue(Key(VRow.TableName, VRow.FieldName), VKept);
  end;
end;

{ Rotates a cycle (node names without the closing repeat) to start at its smallest name. }
function CycleText(const pNodes: TArray<string>): string;
var
  VStart, VI: Integer;
  VSmallest: string;
begin
  Result := '';
  if Length(pNodes) = 0 then
    Exit;
  VStart := 0;
  VSmallest := pNodes[0];
  for VI := 1 to High(pNodes) do
    if CompareText(pNodes[VI], VSmallest) < 0 then
    begin
      VStart := VI;
      VSmallest := pNodes[VI];
    end;
  for VI := 0 to High(pNodes) do
    Result := Result + pNodes[(VStart + VI) mod Length(pNodes)] + ' -> ';
  Result := Result + VSmallest;
end;

procedure CheckCycles(pEdges: TDictionary<string, TArray<string>>; pFields: TDictionary<string, string>;
  var pOut: TArray<TFrCheckFinding>);
var
  VColor: TDictionary<string, TCycleColor>;
  VStack: TList<string>;
  VReported: TStringList;
  VKeys: TArray<string>;
  VNode: string;

  procedure Visit(const pKey: string);
  var
    VNextKey, VText, VTableName, VDisplay: string;
    VDeps: TArray<string>;
    VCycle: TArray<string>;
    VI, VFrom: Integer;
    VColorOf: TCycleColor;
    VTable: string;
    VSameTable: Boolean;
  begin
    VColor.AddOrSetValue(pKey, ccGrey);
    VStack.Add(pKey);
    VTable := Copy(pKey, 1, Pos('.', pKey) - 1);
    if pEdges.TryGetValue(pKey, VDeps) then
      for VNextKey in VDeps do
      begin
        if not VColor.TryGetValue(VNextKey, VColorOf) then
          VColorOf := ccWhite;
        if VColorOf = ccGrey then
        begin
          VFrom := VStack.IndexOf(VNextKey);
          VCycle := nil;
          VSameTable := True;
          for VI := VFrom to VStack.Count - 1 do
          begin
            if not pFields.TryGetValue(VStack[VI], VDisplay) then
              VDisplay := VStack[VI];
            VCycle := VCycle + [VDisplay];
            VSameTable := VSameTable and SameText(Copy(VStack[VI], 1, Pos('.', VStack[VI]) - 1), VTable);
          end;
          if not pFields.TryGetValue(pKey, VDisplay) then
            VDisplay := pKey;
          VTableName := Copy(VDisplay, 1, Pos('.', VDisplay) - 1);
          if VSameTable then
            for VI := 0 to High(VCycle) do
              VCycle[VI] := Copy(VCycle[VI], Pos('.', VCycle[VI]) + 1, MaxInt);
          VText := CycleText(VCycle);
          if VReported.IndexOf(VTable + '|' + VText) < 0 then
          begin
            VReported.Add(VTable + '|' + VText);
            if VSameTable then
              Add(pOut, fcsError, 'calc-cycle', VTableName + '.' + VCycle[0], 'calc dependency cycle in ' + VTableName + ': ' + VText)
            else
              Add(pOut, fcsError, 'calc-cycle', VCycle[0], 'calc dependency cycle across tables: ' + VText);
          end;
        end
        else if VColorOf = ccWhite then
          Visit(VNextKey);
      end;
    VStack.Delete(VStack.Count - 1);
    VColor.AddOrSetValue(pKey, ccBlack);
  end;

begin
  VColor := TDictionary<string, TCycleColor>.Create;
  VStack := TList<string>.Create;
  VReported := TStringList.Create;
  try
    VKeys := pEdges.Keys.ToArray;
    TArray.Sort<string>(VKeys);
    for VNode in VKeys do
      if (not VColor.ContainsKey(VNode)) then
        Visit(VNode);
  finally
    VReported.Free;
    VStack.Free;
    VColor.Free;
  end;
end;

{ An open query; the caller frees it. }
function OpenQuery(pConn: TFDConnection; const pSql: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := pConn;
    Result.SQL.Text := pSql;
    Result.Open;  // dl:ok dataset-open-without-close@f8d5 -- REVIEWED 2026-11-23 EVCOLS: the query is returned open; every caller frees it in finally
  except
    Result.Free;
    raise;
  end;
end;

{ The macros of one event body: well formed, each own one a field of the table, each aliased one (schema 4) a field of
  its alias's target table. }
procedure CheckEventBody(const pTable, pField, pWhere, pBody: string; pFields: TDictionary<string, string>; const pMaps: TInputMaps;
  var pOut: TArray<TFrCheckFinding>);
var
  VInputs: TArray<TFrInput>;
  VInput: TFrInput;
begin
  if not BodyInputs(Key(pTable, pField), '', pBody, pMaps.Aliases, pWhere, VInputs, pOut) then
    Exit;
  for VInput in VInputs do
    if VInput.Alias <> '' then
      ForeignTarget(pTable, pField, pWhere, VInput, pFields, pMaps.Targets, pOut)
    else if not pFields.ContainsKey(Key(pTable, VInput.Field)) then
      Add(pOut, fcsError, 'event-unknown-field', pWhere, 'macro {{' + VInput.Field + '}} names no field of ' + pTable);
end;

procedure CheckLayoutEvents(pConn: TFDConnection; pHasColumns: Boolean; pFields: TDictionary<string, string>; const pMaps: TInputMaps;
  var pOut: TArray<TFrCheckFinding>);
var
  VQuery: TFDQuery;
  VTable, VField, VLayout, VWhere: string;
begin
  VQuery := OpenQuery(pConn, 'SELECT "TABLE_NAME", "FIELD_NAME", "LAYOUT_TYPE", "EVENT_NAME", "EVENT_CODE" FROM "DL_LAYOUT_EVENTS" ' +
    'ORDER BY "TABLE_NAME", "FIELD_NAME", "LAYOUT_TYPE", "EVENT_NAME"');
  try
    while not VQuery.Eof do
    begin
      VTable := Trim(VQuery.Fields[0].AsString);
      VField := Trim(VQuery.Fields[1].AsString);
      VLayout := VQuery.Fields[2].AsString;
      VWhere := 'layout ' + VLayout + ' ' + VTable + '.' + VField + ' ' + VQuery.Fields[3].AsString;
      if (VField <> '') and not pFields.ContainsKey(Key(VTable, VField)) then
        Add(pOut, fcsError, 'layout-event-unknown-field', VWhere, 'the event code belongs to a field that is not in DL_FIELDS_INFO')
      else if pHasColumns and (VField <> '') and SameText(VLayout, REPO_LAYOUT_FIELD) then
        Add(pOut, fcsError, 'layout-event-field-type', VWhere, 'a TField event belongs in its DL_FIELDS_INFO column');
      CheckEventBody(VTable, VField, VWhere, VQuery.Fields[4].AsString, pFields, pMaps, pOut);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ One event column of the field rows. }
procedure CheckEventColumn(pConn: TFDConnection; const pColumn: string; pFields: TDictionary<string, string>; const pMaps: TInputMaps;
  var pOut: TArray<TFrCheckFinding>);
var
  VQuery: TFDQuery;
  VTable, VField: string;
begin
  VQuery := OpenQuery(pConn, 'SELECT "TABLE_NAME", "FIELD_NAME", ' + QuoteRepoIdent(pColumn) + ' FROM "DL_FIELDS_INFO" WHERE ' +
    QuoteRepoIdent(pColumn) + ' IS NOT NULL ORDER BY "TABLE_NAME", "FIELD_NAME"');
  try
    while not VQuery.Eof do
    begin
      VTable := Trim(VQuery.Fields[0].AsString);
      VField := Trim(VQuery.Fields[1].AsString);
      CheckEventBody(VTable, VField, VTable + '.' + VField + ' ' + pColumn, VQuery.Fields[2].AsString, pFields, pMaps, pOut);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ ALIGNMENT is NULL or Ord(TAlignment) (ruling R5). }
procedure CheckAlignment(pConn: TFDConnection; var pOut: TArray<TFrCheckFinding>);
var
  VQuery: TFDQuery;
begin
  VQuery := OpenQuery(pConn, 'SELECT "TABLE_NAME", "FIELD_NAME", "ALIGNMENT" FROM "DL_FIELDS_INFO" WHERE "ALIGNMENT" NOT IN (0, 1, 2) ' +
    'ORDER BY "TABLE_NAME", "FIELD_NAME"');
  try
    while not VQuery.Eof do
    begin
      Add(pOut, fcsWarn, 'alignment-invalid', Trim(VQuery.Fields[0].AsString) + '.' + Trim(VQuery.Fields[1].AsString),
        'ALIGNMENT ' + VQuery.Fields[2].AsString + ' is none of NULL (the default), 0 left, 1 right, 2 center');
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ A grid column that names a table names a field of it. }
procedure CheckGridColumns(pConn: TFDConnection; pFields: TDictionary<string, string>; var pOut: TArray<TFrCheckFinding>);
var
  VQuery: TFDQuery;
begin
  VQuery := OpenQuery(pConn, 'SELECT "TABLE_NAME", "FIELD_NAME", "FORM_NAME", "VIEW_NAME", "COLUMN_NAME" FROM "DL_GRID_COLUMNS" ' +
    'WHERE "TABLE_NAME" IS NOT NULL ORDER BY "FORM_NAME", "VIEW_NAME", "COLUMN_INDEX", "COLUMN_NAME"');
  try
    while not VQuery.Eof do
    begin
      if not pFields.ContainsKey(Key(Trim(VQuery.Fields[0].AsString), Trim(VQuery.Fields[1].AsString))) then
        Add(pOut, fcsWarn, 'grid-column-unknown-field', 'grid ' + string.Join('.', [VQuery.Fields[2].AsString,
          VQuery.Fields[3].AsString, VQuery.Fields[4].AsString]), Trim(VQuery.Fields[0].AsString) + '.' +
          Trim(VQuery.Fields[1].AsString) + ' is not in DL_FIELDS_INFO');
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

type
  { One DL_RELATIONS row with its column pairs (';'-joined in POSITION order). }
  TRelationRow = record
    Name: string;
    Child: string;
    Parent: string;
    Source: string;
    ConstraintName: string;
    ParentKey: string;
    IsDefault: Boolean;
    ChildColumns: string;
    ParentColumns: string;
  end;

  { One DL_CONSTRAINTS row with its columns (';'-joined in POSITION order). }
  TConstraintRow = record
    TableName: string;
    Kind: string;
    RefTable: string;
    Columns: string;
  end;

function LoadInputs(pConn: TFDConnection): TArray<TFrFieldInput>;
var
  VQuery: TFDQuery;
  VInput: TFrFieldInput;
begin
  Result := nil;
  VQuery := OpenQuery(pConn, 'SELECT "TABLE_NAME", "FIELD_NAME", "BINDING", "ALIAS", "PATH", "TARGET_TABLE" FROM "DL_FIELD_INPUTS" ' +
    'ORDER BY "TABLE_NAME", "FIELD_NAME", "BINDING", "ALIAS"');
  try
    while not VQuery.Eof do
    begin
      VInput.TableName := Trim(VQuery.Fields[0].AsString);
      VInput.FieldName := Trim(VQuery.Fields[1].AsString);
      VInput.Binding := Trim(VQuery.Fields[2].AsString);
      VInput.Alias := Trim(VQuery.Fields[3].AsString);
      VInput.Path := Trim(VQuery.Fields[4].AsString);
      VInput.TargetTable := Trim(VQuery.Fields[5].AsString);
      Result := Result + [VInput];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ Name -> ';'-joined column list of one key table (RELATION_NAME / CONSTRAINT_NAME, POSITION, columns). }
procedure LoadColumnLists(pConn: TFDConnection; const pSql: string; pChild, pParent: TDictionary<string, string>);
var
  VQuery: TFDQuery;
  VName, VOld: string;
begin
  VQuery := OpenQuery(pConn, pSql);
  try
    while not VQuery.Eof do
    begin
      VName := UpperCase(Trim(VQuery.Fields[0].AsString));
      if not pChild.TryGetValue(VName, VOld) then
        VOld := '';
      pChild.AddOrSetValue(VName, VOld + IfThen(VOld = '', '', ';') + Trim(VQuery.Fields[1].AsString));
      if pParent <> nil then
      begin
        if not pParent.TryGetValue(VName, VOld) then
          VOld := '';
        pParent.AddOrSetValue(VName, VOld + IfThen(VOld = '', '', ';') + Trim(VQuery.Fields[2].AsString));
      end;
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure LoadRelations(pConn: TFDConnection; pOut: TDictionary<string, TRelationRow>);
var
  VQuery: TFDQuery;
  VRel: TRelationRow;
  VChild, VParent: TDictionary<string, string>;
begin
  VChild := TDictionary<string, string>.Create;
  VParent := TDictionary<string, string>.Create;
  VQuery := nil;
  try
    LoadColumnLists(pConn, 'SELECT "RELATION_NAME", "CHILD_COLUMN", "PARENT_COLUMN" FROM "DL_RELATION_COLUMNS" ' +
      'ORDER BY "RELATION_NAME", "POSITION"', VChild, VParent);
    VQuery := OpenQuery(pConn, 'SELECT "RELATION_NAME", "CHILD_TABLE", "PARENT_TABLE", "SOURCE", "CONSTRAINT_NAME", "PARENT_KEY", ' +
      '"IS_DEFAULT" FROM "DL_RELATIONS" ORDER BY "RELATION_NAME"');
    while not VQuery.Eof do
    begin
      VRel.Name := Trim(VQuery.Fields[0].AsString);
      VRel.Child := Trim(VQuery.Fields[1].AsString);
      VRel.Parent := Trim(VQuery.Fields[2].AsString);
      VRel.Source := Trim(VQuery.Fields[3].AsString);
      VRel.ConstraintName := Trim(VQuery.Fields[4].AsString);
      VRel.ParentKey := Trim(VQuery.Fields[5].AsString);
      VRel.IsDefault := VQuery.Fields[6].AsBoolean;
      if not VChild.TryGetValue(UpperCase(VRel.Name), VRel.ChildColumns) then
        VRel.ChildColumns := '';
      if not VParent.TryGetValue(UpperCase(VRel.Name), VRel.ParentColumns) then
        VRel.ParentColumns := '';
      pOut.AddOrSetValue(UpperCase(VRel.Name), VRel);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
    VParent.Free;
    VChild.Free;
  end;
end;

procedure LoadConstraints(pConn: TFDConnection; pOut: TDictionary<string, TConstraintRow>);
var
  VQuery: TFDQuery;
  VRow: TConstraintRow;
  VColumns: TDictionary<string, string>;
  VName: string;
begin
  VColumns := TDictionary<string, string>.Create;
  VQuery := nil;
  try
    LoadColumnLists(pConn, 'SELECT "CONSTRAINT_NAME", "COLUMN_NAME" FROM "DL_CONSTRAINT_COLUMNS" ORDER BY "CONSTRAINT_NAME", "POSITION"',
      VColumns, nil);
    VQuery := OpenQuery(pConn, 'SELECT "CONSTRAINT_NAME", "TABLE_NAME", "KIND", "REF_TABLE" FROM "DL_CONSTRAINTS"');
    while not VQuery.Eof do
    begin
      VName := UpperCase(Trim(VQuery.Fields[0].AsString));
      VRow.TableName := Trim(VQuery.Fields[1].AsString);
      VRow.Kind := Trim(VQuery.Fields[2].AsString);
      VRow.RefTable := Trim(VQuery.Fields[3].AsString);
      if not VColumns.TryGetValue(VName, VRow.Columns) then
        VRow.Columns := '';
      pOut.AddOrSetValue(VName, VRow);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
    VColumns.Free;
  end;
end;

{ Design 2.3: SOURCE, columns, one default per pair, the parent key is a PK / UNIQUE on exactly the parent columns, an FK
  relation's constraint still says so. }
procedure CheckRelations(pRelations: TDictionary<string, TRelationRow>; pConstraints: TDictionary<string, TConstraintRow>;
  var pOut: TArray<TFrCheckFinding>);
var
  VNames: TArray<string>;
  VName, VWhere, VPair: string;
  VRel: TRelationRow;
  VCon: TConstraintRow;
  VDefaults: TDictionary<string, Integer>;
  VCount: Integer;
begin
  VNames := pRelations.Keys.ToArray;
  TArray.Sort<string>(VNames);
  VDefaults := TDictionary<string, Integer>.Create;
  try
    for VName in VNames do
    begin
      VRel := pRelations[VName];
      VWhere := 'relation ' + VRel.Name;
      if not MatchText(VRel.Source, [REPO_RELATION_FK, REPO_RELATION_FORM, REPO_RELATION_HAND]) then
        Add(pOut, fcsError, 'relation-source-invalid', VWhere, 'SOURCE ' + VRel.Source + ' is none of FK, FORM, HAND');
      if VRel.ChildColumns = '' then
        Add(pOut, fcsError, 'relation-no-columns', VWhere, 'the relation has no DL_RELATION_COLUMNS rows')
      else if not pConstraints.TryGetValue(UpperCase(VRel.ParentKey), VCon) then
        Add(pOut, fcsWarn, 'relation-key-unknown', VWhere, 'PARENT_KEY ' + VRel.ParentKey +
          ' is not in the schema facts (DL_CONSTRAINTS): run repo refresh-schema')
      else if not (MatchText(VCon.Kind, ['PK', 'UNIQUE']) and SameText(VCon.TableName, VRel.Parent) and
        (NormalKeys(VCon.Columns) = NormalKeys(VRel.ParentColumns))) then
        Add(pOut, fcsError, CODE_KEY_NOT_UNIQUE, VWhere, Format('PARENT_KEY %s is %s %s (%s), not a PK / UNIQUE of %s on %s',
          [VRel.ParentKey, VCon.Kind, VCon.TableName, VCon.Columns, VRel.Parent, VRel.ParentColumns]));
      if SameText(VRel.Source, REPO_RELATION_FK) then
      begin
        if VRel.ConstraintName = '' then
          Add(pOut, fcsError, 'relation-fk-missing', VWhere, 'SOURCE FK needs CONSTRAINT_NAME')
        else if not pConstraints.TryGetValue(UpperCase(VRel.ConstraintName), VCon) then
          Add(pOut, fcsWarn, 'relation-fk-gone', VWhere, 'the foreign key ' + VRel.ConstraintName +
            ' is not in the schema facts (dropped, or the schema was not read)')
        else if not (SameText(VCon.Kind, REPO_RELATION_FK) and SameText(VCon.TableName, VRel.Child) and
          SameText(VCon.RefTable, VRel.Parent) and (NormalKeys(VCon.Columns) = NormalKeys(VRel.ChildColumns))) then
          Add(pOut, fcsError, CODE_FK_MISMATCH, VWhere, Format('the constraint %s is %s %s -> %s (%s), the relation says %s -> %s (%s)',
            [VRel.ConstraintName, VCon.Kind, VCon.TableName, VCon.RefTable, VCon.Columns, VRel.Child, VRel.Parent, VRel.ChildColumns]));
      end;
      if VRel.IsDefault then
      begin
        VPair := UpperCase(VRel.Child) + ' -> ' + UpperCase(VRel.Parent);
        if not VDefaults.TryGetValue(VPair, VCount) then
          VCount := 0;
        VDefaults.AddOrSetValue(VPair, VCount + 1);
        if VCount = 1 then
          Add(pOut, fcsError, 'relation-two-defaults', 'relation pair ' + VPair, 'more than one relation is IS_DEFAULT for ' + VPair);
      end;
    end;
  finally
    VDefaults.Free;
  end;
end;

{ Design 2.3: the field row exists; PATH chains from the home table through DL_RELATIONS and ends at TARGET_TABLE; an
  override binding has a default binding with the same alias set. }
procedure CheckInputs(const pInputs: TArray<TFrFieldInput>; pRelations: TDictionary<string, TRelationRow>;
  pFields: TDictionary<string, string>; var pOut: TArray<TFrCheckFinding>);
var
  VInput: TFrFieldInput;
  VWhere, VAt, VStep, VSetKey, VOld, VDefault: string;
  VRel: TRelationRow;
  VBroken: Boolean;
  VSets: TDictionary<string, string>;
begin
  VSets := TDictionary<string, string>.Create;
  try
    for VInput in pInputs do
    begin
      VWhere := 'input ' + VInput.TableName + '.' + VInput.FieldName + IfThen(VInput.Binding = '', '', ' [' + VInput.Binding + ']') +
        ' ' + VInput.Alias;
      VSetKey := Key(VInput.TableName, VInput.FieldName) + '|' + UpperCase(VInput.Binding);
      if not VSets.TryGetValue(VSetKey, VOld) then
        VOld := '';
      VSets.AddOrSetValue(VSetKey, VOld + ';' + VInput.Alias);
      if not pFields.ContainsKey(Key(VInput.TableName, VInput.FieldName)) then
        Add(pOut, fcsError, 'input-no-field-row', VWhere, 'the input belongs to a field that is not in DL_FIELDS_INFO');
      VAt := VInput.TableName;
      VBroken := False;
      for VStep in SplitInputPath(VInput.Path) do
        if not pRelations.TryGetValue(UpperCase(VStep), VRel) then
        begin
          Add(pOut, fcsError, CODE_PATH_BROKEN, VWhere, 'PATH step ' + VStep + ' is no relation in DL_RELATIONS');
          VBroken := True;
          Break;
        end
        else if not SameText(VRel.Child, VAt) then
        begin
          Add(pOut, fcsError, CODE_PATH_BROKEN, VWhere, 'PATH step ' + VStep + ' starts at ' + VRel.Child + ', not at ' + VAt);
          VBroken := True;
          Break;
        end
        else
          VAt := VRel.Parent;
      if (not VBroken) and not SameText(VAt, VInput.TargetTable) then
        Add(pOut, fcsError, 'input-target-mismatch', VWhere, 'PATH ends at ' + VAt + ', TARGET_TABLE says ' + VInput.TargetTable);
    end;
    for VInput in pInputs do
    begin
      if VInput.Binding = '' then
        Continue;
      VSetKey := Key(VInput.TableName, VInput.FieldName) + '|';
      VWhere := 'input ' + VInput.TableName + '.' + VInput.FieldName + ' [' + VInput.Binding + ']';
      if not VSets.TryGetValue(VSetKey, VDefault) then
        Add(pOut, fcsError, 'binding-no-default', VWhere, 'an override binding needs the default binding (BINDING '''')')
      else if NormalKeys(VDefault) <> NormalKeys(VSets[VSetKey + UpperCase(VInput.Binding)]) then
        Add(pOut, fcsError, 'binding-alias-set', VWhere, 'the aliases (' + NormalKeys(VSets[VSetKey + UpperCase(VInput.Binding)]) +
          ') differ from the default binding''s (' + NormalKeys(VDefault) + ')')
      else
        Continue;
      VSets.AddOrSetValue(VSetKey + UpperCase(VInput.Binding), VDefault);
    end;
  finally
    VSets.Free;
  end;
end;

function CheckRepository(pConn: TFDConnection): TArray<TFrCheckFinding>;
var
  VVersion: Integer;
  VRows: TArray<TFieldRow>;
  VFields: TDictionary<string, string>;
  VEdges: TDictionary<string, TArray<string>>;
  VAliases: TDictionary<string, TArray<string>>;
  VTargets: TDictionary<string, string>;
  VRelations: TDictionary<string, TRelationRow>;
  VConstraints: TDictionary<string, TConstraintRow>;
  VInputs: TArray<TFrFieldInput>;
  VInput: TFrFieldInput;
  VDeclared: TArray<string>;
  VRow: TFieldRow;
  VEvent: TFrEventColumn;
  VMaps: TInputMaps;
begin
  Result := nil;
  VVersion := RepoSchemaVersion(pConn);
  VRows := LoadRows(pConn, VVersion >= VERSION_MODEL);
  VFields := TDictionary<string, string>.Create;
  VEdges := TDictionary<string, TArray<string>>.Create;
  VAliases := nil;
  VTargets := TDictionary<string, string>.Create;
  VRelations := TDictionary<string, TRelationRow>.Create;
  VConstraints := TDictionary<string, TConstraintRow>.Create;
  try
    for VRow in VRows do
      VFields.AddOrSetValue(Key(VRow.TableName, VRow.FieldName), VRow.TableName + '.' + VRow.FieldName);
    VInputs := nil;
    if VVersion >= VERSION_CROSS_TABLE then
    begin
      VAliases := TDictionary<string, TArray<string>>.Create;
      VInputs := LoadInputs(pConn);
      for VInput in VInputs do
        if VInput.Binding = '' then
        begin
          if not VAliases.TryGetValue(Key(VInput.TableName, VInput.FieldName), VDeclared) then
            VDeclared := nil;
          VAliases.AddOrSetValue(Key(VInput.TableName, VInput.FieldName), VDeclared + [VInput.Alias]);
          VTargets.AddOrSetValue(AliasKey(VInput.TableName, VInput.FieldName, VInput.Alias), VInput.TargetTable);
        end;
    end;
    VMaps.Aliases := VAliases;
    VMaps.Targets := VTargets;
    CheckKindFlags(VRows, Result);
    CheckLookups(VRows, VFields, Result);
    CheckBodies(VRows, VFields, VAliases, VTargets, VEdges, Result);
    CheckCycles(VEdges, VFields, Result);
    if VVersion >= VERSION_MODEL then
      CheckLayoutEvents(pConn, VVersion >= VERSION_EVENT_COLUMNS, VFields, VMaps, Result);
    if VVersion >= VERSION_EVENT_COLUMNS then
    begin
      for VEvent in FR_EVENT_COLUMNS do
        CheckEventColumn(pConn, VEvent.Column, VFields, VMaps, Result);
      CheckAlignment(pConn, Result);
      CheckGridColumns(pConn, VFields, Result);
    end;
    if VVersion >= VERSION_CROSS_TABLE then
    begin
      LoadRelations(pConn, VRelations);
      LoadConstraints(pConn, VConstraints);
      CheckInputs(VInputs, VRelations, VFields, Result);
      CheckRelations(VRelations, VConstraints, Result);
    end;
  finally
    VConstraints.Free;
    VRelations.Free;
    VTargets.Free;
    VAliases.Free;
    VEdges.Free;
    VFields.Free;
  end;
end;

function SeverityName(pSeverity: TFrCheckSeverity): string;
begin
  Result := if pSeverity = fcsError then 'ERROR' else 'WARN';
end;

function RenderCheckText(const pFindings: TArray<TFrCheckFinding>): TArray<string>;
var
  VFinding: TFrCheckFinding;
  VErrors, VWarns: Integer;
begin
  Result := nil;
  VErrors := 0;
  VWarns := 0;
  for VFinding in pFindings do
  begin
    Result := Result + [Format('%s %s %s: %s', [SeverityName(VFinding.Severity), VFinding.Code, VFinding.Where,
      VFinding.Message])];
    if VFinding.Severity = fcsError then
      Inc(VErrors)
    else
      Inc(VWarns);
  end;
  Result := Result + [if Length(pFindings) = 0 then 'check: clean'
    else Format('check: %d findings (%d errors, %d warnings)', [Length(pFindings), VErrors, VWarns])];
end;

function RenderCheckJson(const pFindings: TArray<TFrCheckFinding>): string;
var
  VRoot, VItem: TJSONObject;
  VList: TJSONArray;
  VFinding: TFrCheckFinding;
  VErrors, VWarns: Integer;
begin
  VErrors := 0;
  VWarns := 0;
  VRoot := TJSONObject.Create;
  try
    VList := TJSONArray.Create;
    VRoot.AddPair('findings', VList);
    for VFinding in pFindings do
    begin
      VItem := TJSONObject.Create;
      VItem.AddPair('severity', LowerCase(SeverityName(VFinding.Severity)));
      VItem.AddPair('code', VFinding.Code);
      VItem.AddPair('where', VFinding.Where);
      VItem.AddPair('message', VFinding.Message);
      VList.AddElement(VItem);
      if VFinding.Severity = fcsError then
        Inc(VErrors)
      else
        Inc(VWarns);
    end;
    VRoot.AddPair('errors', TJSONNumber.Create(VErrors));
    VRoot.AddPair('warnings', TJSONNumber.Create(VWarns));
    Result := VRoot.ToJSON;
  finally
    VRoot.Free;
  end;
end;

end.
