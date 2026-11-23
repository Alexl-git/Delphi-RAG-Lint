unit DRagLint.FieldRepo.Check;

{ drag-lint 1.53 -- lane FR-MODEL: `repo check`, the read-only consistency check of a repository
  (design 2026-11-22-field-repository-v2-design.md section 4.6): kind / flag consistency (4.1), lookup wiring
  (4.2), calc macro targets and dependency cycles (4.3), layout-event rows. The 1.54 editor calls the same
  function to warn early at save (Q13). }

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
    /// layout-event-unknown-field.</summary>
    Code: string;
    /// <summary>Where: `TABLE.FIELD`, or `layout TYPE TABLE.FIELD EVENT` for a layout-event row.</summary>
    Where: string;
    /// <summary>Human-readable explanation, ASCII.</summary>
    Message: string;
  end;

/// <summary>Checks a repository (schema 1 or 2); never writes.</summary>
/// <param name="pConn">Open repository connection (read-only is enough).</param>
/// <returns>Every finding, in the order kind/flag, lookup wiring, calc bodies, cycles, layout events; empty = clean.</returns>
/// <remarks>A schema-1 file has no CALC_BODY and no layout-event table: those checks are skipped. FIELD_KIND NULL
/// reads as data (so a legacy ISCALCULATED row with a NULL kind is a kind/flag mismatch until `repo migrate`).
/// A cycle is named once, rotated to start at its alphabetically first field: `A -> B -> A`.</remarks>
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
  DRagLint.FieldRepo.Kinds;

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
    VQuery.Open('SELECT "TABLE_NAME", "FIELD_NAME", "FIELD_KIND", "ISCALCULATED", "ISLOOKUP", "PRIMARY_KEY", ' +
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

{ Dependency edges of every body field; macro errors and unknown targets are findings. }
procedure CheckBodies(const pRows: TArray<TFieldRow>; pFields: TDictionary<string, string>;
  pEdges: TDictionary<string, TArray<string>>; var pOut: TArray<TFrCheckFinding>);
var
  VRow: TFieldRow;
  VDeps, VKept: TArray<string>;
  VDep: string;
begin
  for VRow in pRows do
  begin
    if not (FrKindCodeKnown(VRow.KindCode) and FrKindHasBody(FrKindFromCode(VRow.KindCode))) then
      Continue;
    if VRow.Body = '' then
      Continue;
    try
      VDeps := CalcDependencies(VRow.Body, VRow.FieldName);
    except
      on E: EFrKindError do
      begin
        Add(pOut, fcsError, 'calc-macro-error', VRow.TableName + '.' + VRow.FieldName, E.Message);
        Continue;
      end;
    end;
    VKept := nil;
    for VDep in VDeps do
      if pFields.ContainsKey(Key(VRow.TableName, VDep)) then
        VKept := VKept + [VDep]
      else
        Add(pOut, fcsError, 'calc-unknown-field', VRow.TableName + '.' + VRow.FieldName,
          'macro {{' + VDep + '}} names no field of ' + VRow.TableName);
    pEdges.AddOrSetValue(Key(VRow.TableName, VRow.FieldName), VKept);
  end;
end;

{ Rotates a cycle (node names without the closing repeat) to start at its smallest name. }
function CycleText(const pNodes: TArray<string>): string;
var
  VStart, VI: Integer;
begin
  Result := '';
  if Length(pNodes) = 0 then
    Exit;
  VStart := 0;
  for VI := 1 to High(pNodes) do
    if CompareText(pNodes[VI], pNodes[VStart]) < 0 then
      VStart := VI;
  Result := '';
  for VI := 0 to High(pNodes) do
    Result := Result + pNodes[(VStart + VI) mod Length(pNodes)] + ' -> ';
  Result := Result + pNodes[VStart];
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
    VDep: string;
    VCycle: TArray<string>;
    VI, VFrom: Integer;
    VColorOf: TCycleColor;
    VTable: string;
  begin
    VColor.AddOrSetValue(pKey, ccGrey);
    VStack.Add(pKey);
    VTable := Copy(pKey, 1, Pos('.', pKey) - 1);
    if pEdges.ContainsKey(pKey) then
      for VDep in pEdges[pKey] do
      begin
        VNextKey := VTable + '.' + UpperCase(VDep);
        if not VColor.TryGetValue(VNextKey, VColorOf) then
          VColorOf := ccWhite;
        if VColorOf = ccGrey then
        begin
          VFrom := VStack.IndexOf(VNextKey);
          VCycle := nil;
          for VI := VFrom to VStack.Count - 1 do
          begin
            if not pFields.TryGetValue(VStack[VI], VDisplay) then
              VDisplay := VStack[VI];
            VCycle := VCycle + [Copy(VDisplay, Pos('.', VDisplay) + 1, MaxInt)];
          end;
          if not pFields.TryGetValue(pKey, VDisplay) then
            VDisplay := pKey;
          VTableName := Copy(VDisplay, 1, Pos('.', VDisplay) - 1);
          VText := CycleText(VCycle);
          if VReported.IndexOf(VTable + '|' + VText) < 0 then
          begin
            VReported.Add(VTable + '|' + VText);
            Add(pOut, fcsError, 'calc-cycle', VTableName + '.' + VCycle[0],
              'calc dependency cycle in ' + VTableName + ': ' + VText);
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

procedure CheckLayoutEvents(pConn: TFDConnection; pFields: TDictionary<string, string>; var pOut: TArray<TFrCheckFinding>);
var
  VQuery: TFDQuery;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pConn;
    VQuery.Open('SELECT "TABLE_NAME", "FIELD_NAME", "LAYOUT_TYPE", "EVENT_NAME" FROM "DL_LAYOUT_EVENTS" ' +
      'ORDER BY "TABLE_NAME", "FIELD_NAME", "LAYOUT_TYPE", "EVENT_NAME"');
    while not VQuery.Eof do
    begin
      if not pFields.ContainsKey(Key(Trim(VQuery.Fields[0].AsString), Trim(VQuery.Fields[1].AsString))) then
        Add(pOut, fcsError, 'layout-event-unknown-field',
          'layout ' + VQuery.Fields[2].AsString + ' ' + VQuery.Fields[0].AsString + '.' + VQuery.Fields[1].AsString
          + ' ' + VQuery.Fields[3].AsString,
          'the event code belongs to a field that is not in DL_FIELDS_INFO');
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;
function CheckRepository(pConn: TFDConnection): TArray<TFrCheckFinding>;
var
  VHasV2: Boolean;
  VRows: TArray<TFieldRow>;
  VFields: TDictionary<string, string>;
  VEdges: TDictionary<string, TArray<string>>;
  VRow: TFieldRow;
begin
  Result := nil;
  VHasV2 := RepoSchemaVersion(pConn) >= 2;
  VRows := LoadRows(pConn, VHasV2);
  VFields := TDictionary<string, string>.Create;
  VEdges := TDictionary<string, TArray<string>>.Create;
  try
    for VRow in VRows do
      VFields.AddOrSetValue(Key(VRow.TableName, VRow.FieldName), VRow.TableName + '.' + VRow.FieldName);
    CheckKindFlags(VRows, Result);
    CheckLookups(VRows, VFields, Result);
    CheckBodies(VRows, VFields, VEdges, Result);
    CheckCycles(VEdges, VFields, Result);
    if VHasV2 then
      CheckLayoutEvents(pConn, VFields, Result);
  finally
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
