program LineageTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.56 lane LIN-1 -- console tests for the read-only lineage model DRagLint.FieldRepo.Lineage
  (design 2026-11-27-derived-field-lineage-design.md sections 2, 3.1, 5.2; owner answers DL-1 .. DL-6).

  Usage: LineageTests <index.sqlite> <fixture folder>
  The runner tests\autotest\run_v156_LIN1.ps1 copies tests\fixtures\v156\LIN1 to a scratch folder, indexes the
  COPY with the engine and passes both. The last test CHANGES a fixture file of that copy (stale index).
  Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M". Exit code 0 only when fail=0. }

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  DRagLint.FieldRepo.Lineage in '..\..\src\sql\DRagLint.FieldRepo.Lineage.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;
  GModel: TFieldLineageModel;

procedure Check(const pName: string; pOk: Boolean; const pDetail: string = '');
begin
  if pOk then
  begin
    Inc(GPass);
    Writeln('PASS ', pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, '  ', pDetail);
  end;
end;

procedure CheckEq(const pName, pExpected, pActual: string);
begin
  Check(pName, pExpected = pActual, Format('expected [%s] actual [%s]', [pExpected, pActual]));
end;

function UnitPath(const pUnit: string): string;
begin
  Result := TPath.Combine(GDir, pUnit + '.pas');
end;

{ 1-based line of the fixture line that carries the marker comment. }
function MarkerLine(const pUnit, pMarker: string): Integer;
var
  Lines: TArray<string>;
  I: Integer;
begin
  Result := 0;
  Lines := TFile.ReadAllLines(UnitPath(pUnit));
  for I := 0 to High(Lines) do
    if ContainsStr(Lines[I], '{ ' + pMarker + ' }') then
      Result := I + 1;
end;

function InputsText(const pInputs: TArray<TLineageInput>): string;
var
  Names: TStringList;
  Input: TLineageInput;
begin
  Names := TStringList.Create;
  try
    for Input in pInputs do
      Names.Add(Input.DisplayName);
    Names.Sort;
    Names.Delimiter := ',';
    Names.StrictDelimiter := True;
    Result := Names.DelimitedText;
  finally
    Names.Free;
  end;
end;

function Field(const pUnit, pDataset, pFieldName: string): TLineageField;
begin
  Result := GModel.FieldLineage(UnitPath(pUnit), pDataset, pFieldName);
end;

{ LIN-1.1: M.X := Q.A * Q.B through persistent field components. }
procedure TestSimple;
var
  F: TLineageField;
begin
  F := Field('uLinDirect', 'tblM', 'X');
  Check('T1 simple: X is derived', F.Derived);
  CheckEq('T1 simple: kind', LINEAGE_KIND_DIRECT, F.Kind);
  CheckEq('T1 simple: inputs', 'qryQ.A,qryQ.B', InputsText(F.Inputs));
  CheckEq('T1 simple: component', 'tblMX', F.Component);
  Check('T1 simple: one write', Length(F.Writes) = 1, IntToStr(Length(F.Writes)));
  if Length(F.Writes) = 1 then
  begin
    CheckEq('T1 simple: expression text', 'tblMX.AsFloat := qryQA.AsFloat * qryQB.AsFloat;', F.Writes[0].ExprText);
    CheckEq('T1 simple: routine', 'uLinDirect.TfLinDirect.FillX', F.Writes[0].Routine);
    CheckEq('T1 simple: no event', '', F.Writes[0].Event);
    Check('T1 simple: line', F.Writes[0].Line = MarkerLine('uLinDirect', 'M-SIMPLE'), IntToStr(F.Writes[0].Line));
    Check('T1 simple: no via, no loop, no reason',
      (Length(F.Writes[0].Via) = 0) and (F.Writes[0].LoopText = '') and (Length(F.Unknown) = 0));
  end;
end;

{ DL-1 A (a local on the path), DL-3 (event), DL-5 (text); NOT MARKED: STAMP (no field input), IDLE (no write). }
procedure TestDirect;
var
  F: TLineageField;
  U: TLineageUnit;
begin
  F := Field('uLinDirect', 'tblOrders', 'TOTAL');
  CheckEq('T2 TOTAL: kind', LINEAGE_KIND_DIRECT, F.Kind);
  CheckEq('T2 TOTAL: inputs', 'qryCust.DISCOUNT,tblOrders.PRICE,tblOrders.QTY', InputsText(F.Inputs));
  Check('T2 TOTAL: one write', Length(F.Writes) = 1, IntToStr(Length(F.Writes)));
  if Length(F.Writes) = 1 then
  begin
    CheckEq('T2 TOTAL: event', 'tblOrders.AfterOpen', F.Writes[0].Event);
    CheckEq('T2 TOTAL: expression text',
      'tblOrdersTOTAL.AsFloat := d * (1 - qryCust.FieldByName(''DISCOUNT'').AsFloat);', F.Writes[0].ExprText);
    CheckEq('T2 TOTAL: via', Format('d := tblOrdersQTY.AsFloat * tblOrdersPRICE.AsFloat;  (line %d)',
      [MarkerLine('uLinDirect', 'M-VIA')]), string.Join(' | ', F.Writes[0].Via));
  end;
  F := Field('uLinDirect', 'tblOrders', 'STAMP');
  Check('T3 STAMP (:= Now): not derived', not F.Derived and (F.Kind = LINEAGE_KIND_NONE), F.Kind);
  Check('T3 STAMP: counted as a write without field input', F.WritesWithoutFieldInput = 1,
    IntToStr(F.WritesWithoutFieldInput));
  F := Field('uLinDirect', 'tblOrders', 'IDLE');
  Check('T3 IDLE (never written): not derived, no write',
    not F.Derived and (F.WritesWithoutFieldInput = 0) and (Length(F.Writes) = 0));
  U := GModel.ReadUnit(UnitPath('uLinDirect'));
  Check('T3 unit: indexed, not stale, 3 written fields', U.Indexed and not U.Stale and (Length(U.Fields) = 3),
    IntToStr(Length(U.Fields)));
end;

{ DL-1 A boundary: a project routine and a parameter are not followed; an RTL routine is part of the expression. }
procedure TestCalls;
var
  F: TLineageField;
begin
  F := Field('uLinCalls', 'tblOrders', 'RATE2');
  CheckEq('T4 RATE2: kind', LINEAGE_KIND_UNKNOWN, F.Kind);
  CheckEq('T4 RATE2: reason', 'result of CalcRate (calls are not followed)', string.Join(' | ', F.Unknown));
  CheckEq('T4 RATE2: no input', '', InputsText(F.Inputs));
  F := Field('uLinCalls', 'tblOrders', 'R3');
  CheckEq('T4 R3 (Round): kind', LINEAGE_KIND_DIRECT, F.Kind);
  CheckEq('T4 R3: inputs', 'tblOrders.QTY', InputsText(F.Inputs));
  CheckEq('T4 R3: no reason', '', string.Join(' | ', F.Unknown));
  F := Field('uLinCalls', 'tblOrders', 'P4');
  CheckEq('T4 P4: kind', LINEAGE_KIND_UNKNOWN, F.Kind);
  CheckEq('T4 P4: reason', 'value of parameter pV', string.Join(' | ', F.Unknown));
  Check('T4 P4: derived', F.Derived);
end;

{ DL-2 A: in / after a loop over another dataset = aggregate; a loop over the own dataset = direct. }
procedure TestLoop;
var
  F: TLineageField;
begin
  F := Field('uLinLoop', 'tblOrders', 'TOTAL');
  CheckEq('T5 TOTAL (after the loop, through vSum): kind', LINEAGE_KIND_AGGREGATE, F.Kind);
  CheckEq('T5 TOTAL: inputs', 'qryLines.AMOUNT,qryLines.QTY', InputsText(F.Inputs));
  if Length(F.Writes) = 1 then
  begin
    CheckEq('T5 TOTAL: loop text', 'while not qryLines.Eof', F.Writes[0].LoopText);
    CheckEq('T5 TOTAL: loop dataset', 'qryLines', F.Writes[0].LoopDataset);
    CheckEq('T5 TOTAL: expression text', 'tblOrdersTOTAL.AsFloat := vSum;', F.Writes[0].ExprText);
    CheckEq('T5 TOTAL: via', Format('vSum := vSum + qryLinesAMOUNT.AsFloat * qryLinesQTY.AsInteger;  (line %d)',
      [MarkerLine('uLinLoop', 'M-ACC')]), string.Join(' | ', F.Writes[0].Via));
    CheckEq('T5 TOTAL: event', 'tblOrders.AfterOpen', F.Writes[0].Event);
  end
  else
    Check('T5 TOTAL: one write', False, IntToStr(Length(F.Writes)));
  F := Field('uLinLoop', 'tblOrders', 'COUNT2');
  CheckEq('T5 COUNT2 (inside the loop): kind', LINEAGE_KIND_AGGREGATE, F.Kind);
  CheckEq('T5 COUNT2: inputs (not itself)', 'qryLines.QTY', InputsText(F.Inputs));
  F := Field('uLinLoop', 'tblOrders', 'SEQ');
  CheckEq('T6 SEQ (loop over its own dataset): kind', LINEAGE_KIND_DIRECT, F.Kind);
  CheckEq('T6 SEQ: inputs', 'tblOrders.QTY', InputsText(F.Inputs));
  Check('T6 SEQ: no loop text', (Length(F.Writes) = 1) and (F.Writes[0].LoopText = ''));
end;

{ DL-6 A: a name built at run time marks no field; Lookup; `with` over two datasets. }
procedure TestUnknown;
var
  F: TLineageField;
  U: TLineageUnit;
begin
  U := GModel.ReadUnit(UnitPath('uLinUnknown'));
  Check('T7 U1: one run-time-name write', Length(U.RuntimeNameWrites) = 1, IntToStr(Length(U.RuntimeNameWrites)));
  if Length(U.RuntimeNameWrites) = 1 then
  begin
    CheckEq('T7 U1: dataset', 'tblOrders', U.RuntimeNameWrites[0].Dataset);
    CheckEq('T7 U1: name text', 'vName', U.RuntimeNameWrites[0].NameText);
    Check('T7 U1: line', U.RuntimeNameWrites[0].Line = MarkerLine('uLinUnknown', 'M-U1'));
  end;
  Check('T7 U1: marks no field (3 written fields: U1B, U2, U3)', Length(U.Fields) = 3, IntToStr(Length(U.Fields)));
  F := Field('uLinUnknown', 'tblOrders', 'U1B');
  CheckEq('T7 U1B (literal name, same right side): kind', LINEAGE_KIND_DIRECT, F.Kind);
  CheckEq('T7 U1B: inputs', 'tblOrders.QTY', InputsText(F.Inputs));
  F := Field('uLinUnknown', 'tblOrders', 'U2');
  CheckEq('T7 U2 (Lookup): kind', LINEAGE_KIND_UNKNOWN, F.Kind);
  CheckEq('T7 U2: reason', LINEAGE_REASON_VARIANT, string.Join(' | ', F.Unknown));
  F := Field('uLinUnknown', 'tblOrders', 'U3');
  CheckEq('T7 U3 (with tblOrders, qryCust): kind', LINEAGE_KIND_UNKNOWN, F.Kind);
  CheckEq('T7 U3: reason', 'inside with over 2 datasets', string.Join(' | ', F.Unknown));
  F := Field('uLinUnknown', 'qryCust', 'U3');
  Check('T7 U3: found under either dataset of the with', F.Derived);
end;

{ DL-3 A: a write in another unit does not mark the field; a plain private method does, with no event. }
procedure TestWhere;
var
  F: TLineageField;
begin
  F := Field('uLinWhere', 'tblOrders', 'Y');
  CheckEq('T8 Y (private method): kind', LINEAGE_KIND_DIRECT, F.Kind);
  Check('T8 Y: no event', (Length(F.Writes) = 1) and (F.Writes[0].Event = ''));
  F := Field('uLinWhere', 'tblOrders', 'X');
  Check('T8 X (written only by uLinOther.Poke): not derived', not F.Derived);
  CheckEq('T8 X: external writers', 'uLinOther.Poke',
    string.Join(',', GModel.ExternalWriters(UnitPath('uLinWhere'), 'tblOrdersX')));
  CheckEq('T8 Y: no external writer', '',
    string.Join(',', GModel.ExternalWriters(UnitPath('uLinWhere'), 'tblOrdersY')));
end;

{ Edges: a unit the index does not hold; an index without the facts; a unit changed after indexing. }
procedure TestEdges(const pIndexDb: string);
var
  U: TLineageUnit;
  F: TLineageField;
  Fresh: TFieldLineageModel;
  Raised: Boolean;
begin
  U := GModel.ReadUnit(UnitPath('uNoSuchUnit'));
  Check('T9 unknown unit: not indexed, no field', not U.Indexed and (Length(U.Fields) = 0));
  Raised := False;
  try
    Fresh := TFieldLineageModel.Create(TPath.Combine(GDir, 'no-such-index.sqlite'));
    Fresh.Free;
  except
    on E: ELineageError do
      Raised := True;
  end;
  Check('T9 missing index: ELineageError', Raised);
  { stale: the copy of uLinDirect.pas changes after it was indexed; a NEW model (no cache) must not guess }
  TFile.AppendAllText(UnitPath('uLinDirect'), sLineBreak + '{ changed after indexing }' + sLineBreak);
  Fresh := TFieldLineageModel.Create(pIndexDb);
  try
    U := Fresh.ReadUnit(UnitPath('uLinDirect'));
    Check('T10 stale: flagged, no field', U.Indexed and U.Stale and (Length(U.Fields) = 0));
    CheckEq('T10 stale: reason', 'index stale for uLinDirect', U.StaleReason);
    F := Fresh.FieldLineage(UnitPath('uLinDirect'), 'tblM', 'X');
    Check('T10 stale: the field is not guessed', not F.Derived and (Length(F.Unknown) = 1) and
      (F.Unknown[0] = 'index stale for uLinDirect'));
    U := Fresh.ReadUnit(UnitPath('uLinLoop'));
    Check('T10 stale: an unchanged unit of the same index still answers', not U.Stale and (Length(U.Fields) = 3),
      IntToStr(Length(U.Fields)));
  finally
    Fresh.Free;
  end;
end;

begin
  try
    if ParamCount < 2 then
    begin
      Writeln('usage: LineageTests <index.sqlite> <fixture folder>');
      Halt(2);
    end;
    GDir := ExcludeTrailingPathDelimiter(ParamStr(2));
    GModel := TFieldLineageModel.Create(ParamStr(1));
    try
      TestSimple;
      TestDirect;
      TestCalls;
      TestLoop;
      TestUnknown;
      TestWhere;
      TestEdges(ParamStr(1));
    finally
      GModel.Free;
    end;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unexpected ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln(Format('SUMMARY pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    Halt(1);
end.
