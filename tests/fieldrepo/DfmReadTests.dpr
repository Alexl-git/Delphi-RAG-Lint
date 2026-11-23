program DfmReadTests;

{ Self-contained console test runner (no DUnitX) for the pure units of lane TT-DFMREAD (drag-lint 1.54):
  DfmReadSelection (ExpandSelection S1 / S2 / S3 / S5), DfmReadSql (tables and columns of a SELECT), DfmReadCalc
  (handler slices and field macros). One PASS/FAIL line per case, a summary line, exit code 1 on any failure.
  The CLI (DFM files, change set, apply) is run_fieldrepo_dfmread.ps1. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DRagLint.FieldRepo.Kinds in '..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.DfmReadSelection in '..\..\src\sql\DRagLint.FieldRepo.DfmReadSelection.pas',
  DRagLint.FieldRepo.DfmReadSql in '..\..\src\sql\DRagLint.FieldRepo.DfmReadSql.pas',
  DRagLint.FieldRepo.DfmReadCalc in '..\..\src\sql\DRagLint.FieldRepo.DfmReadCalc.pas';

var
  GPass, GFail: Integer;

procedure Check(const pName: string; pOk: Boolean; const pDetail: string = '');
begin
  if pOk then
    Inc(GPass)
  else
    Inc(GFail);
  Writeln(if pOk then 'PASS ' else 'FAIL ', pName, if pOk or (pDetail = '') then '' else ' -- ' + pDetail);
end;

procedure CheckText(const pName, pGot, pWant: string);
begin
  Check(pName, pGot = pWant, 'got <' + pGot.Replace(#13#10, '|') + '> want <' + pWant.Replace(#13#10, '|') + '>');
end;

{ ---- selection ---- }

function SelField(const pName: string; pKind: TFrFieldKind; const pBody: string = ''; const pKey: string = ''): TFrSelectionField;
begin
  Result.Name := pName;
  Result.Kind := pKind;
  Result.Body := pBody;
  Result.SourceKey := pKey;
end;

function Fields: TArray<TFrSelectionField>;
begin
  Result := [SelField('ID', frkData), SelField('QTY', frkData), SelField('PRICE', frkData), SelField('TOOL_ID', frkData),
    SelField('TOTAL', frkCalc, '{{TOTAL}} := {{QTY}} * {{PRICE}};'), SelField('VAT', frkInternalCalc, '{{VAT}} := {{TOTAL}} * 0.2;'),
    SelField('TOOL', frkLookup, '', 'TOOL_ID'), SelField('A', frkCalc, '{{A}} := {{B}};'), SelField('B', frkCalc, '{{B}} := {{A}};'),
    SelField('BAD', frkCalc, '{{BAD}} := {{NOPE}};')];
end;

function Expand(const pSel: TArray<string>): string;
begin
  try
    Result := string.Join(',', ExpandSelection(pSel, Fields));
  except
    on E: EFrSelectionError do
      Result := 'error: ' + E.Message;
  end;
end;

procedure TestSelection;
begin
  CheckText('S0 data field alone', Expand(['QTY']), 'QTY');
  CheckText('S1 calc adds its fields', Expand(['TOTAL']), 'QTY,PRICE,TOTAL');
  CheckText('S1 transitive', Expand(['vat']), 'QTY,PRICE,TOTAL,VAT');
  CheckText('S1 lookup adds its key', Expand(['TOOL']), 'TOOL_ID,TOOL');
  CheckText('S1 a cycle ends', Expand(['A']), 'A,B');
  CheckText('S2 the rest stays', Expand(['ID', 'TOTAL']), 'ID,QTY,PRICE,TOTAL');
  CheckText('S3 idempotent', Expand(ExpandSelection(['VAT'], Fields)), Expand(['VAT']));
  CheckText('S5 unknown field', Expand(['ZZZ']), 'error: unknown field: ZZZ');
  CheckText('S5 unknown macro field', Expand(['BAD']), 'error: unknown field: NOPE');
  CheckText('empty selection', Expand([]), '');
end;

{ ---- SQL ---- }

function Col(const pSql, pField: string; const pOrigin: string = ''): string;
var
  VSource: TDfmrSqlSource;
  VTable, VColumn, VReason: string;
begin
  VSource := ReadSelectSource(pSql);
  if VSource.Reason <> '' then
    Exit('!' + VSource.Reason);
  if SqlFieldColumn(VSource, pField, pOrigin, VTable, VColumn, VReason) then
    Result := VTable + '.' + VColumn
  else
    Result := '?' + VReason;
end;

function Tables(const pSql: string): string;
var
  VTable: TDfmrSqlTable;
begin
  Result := '';
  for VTable in ReadSelectSource(pSql).Tables do
    Result := Result + VTable.Name + ';';
end;

procedure TestSql;
const
  JOIN_SQL = 'SELECT F.WarnFlag, G.Tag1 AS Tool, F.Qty * 2 AS Dbl, Loose FROM "ToolFldr.DB" F ' +
    'LEFT OUTER JOIN "ToolGR12.DB" G ON F.ToolID = G.ID, MachPos WHERE F.ID > 0';
begin
  CheckText('CleanTableName', CleanTableName(':MIC:data\Tools.db'), 'TOOLS');
  CheckText('CleanTableName keeps a dotted non-extension', CleanTableName('A.B'), 'A.B');
  CheckText('star of one table', Col('select * from Orders', 'qty'), 'ORDERS.QTY');
  CheckText('unquoted Paradox name', Col('select * from Tools.db where x = 1', 'Tag'), 'TOOLS.TAG');
  CheckText('join tables', Tables(JOIN_SQL), 'TOOLFLDR;TOOLGR12;MACHPOS;');
  CheckText('qualified', Col(JOIN_SQL, 'WarnFlag'), 'TOOLFLDR.WARNFLAG');
  CheckText('alias is the column behind it', Col(JOIN_SQL, 'Tool'), 'TOOLGR12.TAG1');
  CheckText('expression', Col(JOIN_SQL, 'Dbl'), '?computed by the SQL');
  CheckText('unqualified in a join', Col(JOIN_SQL, 'Loose'), '?the SQL does not say which table it comes from');
  CheckText('Origin of a FROM table', Col(JOIN_SQL, 'Loose', '"MachPos.DB".Loose'), 'MACHPOS.LOOSE');
  CheckText('Origin of another table', Col(JOIN_SQL, 'Loose', '"Other.DB".Loose'), '?the SQL does not say which table it comes from');
  CheckText('aggregate of one table', Col('SELECT COUNT(*) AS N FROM T', 'N'), '?computed by the SQL');
  CheckText('not in the list, no star', Col('SELECT A FROM T', 'B'), '?the SQL does not say which table it comes from');
  CheckText('comments and strings', Col('/* from X */ SELECT ''from Y'' as S, A -- FROM Z'#13#10'FROM T', 'A'), 'T.A');
  CheckText('union', Col('SELECT A FROM T UNION SELECT A FROM U', 'A'), '!the SQL is a UNION');
  CheckText('derived table', Col('SELECT A FROM (SELECT A FROM U) V', 'A'), '!the SQL reads a derived table');
  CheckText('macro table', Col('SELECT A FROM &TBL', 'A'), '!the SQL names its table by a macro or an expression');
  CheckText('stored procedure', Col('SELECT A FROM P(1)', 'A'), '!the SQL selects from a stored procedure');
  CheckText('update', Col('UPDATE T SET A = 1', 'A'), '!the SQL is not a plain SELECT');
  CheckText('empty', Col('', 'A'), '!the SQL is empty in the DFM');
  CheckText('a literal is not a column', Col('SELECT T.*, 0 AS EXTRA FROM T', 'EXTRA'), '?computed by the SQL');
  CheckText('a decimal is not a qualified column', Col('SELECT A, 1.5 AS X FROM T', 'X'), '?computed by the SQL');
  CheckText('NULL is not a column', Col('SELECT A, NULL AS X FROM T', 'X'), '?computed by the SQL');
  CheckText('CURRENT_DATE is not a column', Col('SELECT A, CURRENT_DATE X FROM T', 'X'), '?computed by the SQL');
  CheckText('a quoted name is a column', Col('SELECT "NULL" AS X FROM T', 'X'), 'T.NULL');
  CheckText('FIRST in parentheses', Col('SELECT FIRST (10) SKIP (2) A B FROM T', 'B'), 'T.A');
  CheckText('FIRST with a parameter', Col('SELECT FIRST :N ID, NAME FROM T', 'ID'), 'T.ID');
  CheckText('FIRST with a parameter makes no column', Col('SELECT FIRST :N ID, NAME FROM T', 'N'), '?the SQL does not say which table it comes from');
  CheckText('schema-qualified table', Col('SELECT A FROM dbo.Tools', 'A'), '!the SQL qualifies its table name');
  CheckText('the last operand of an expression is no alias', Col('SELECT A || B, B FROM T', 'B'), 'T.B');
  CheckText('expression alias', Col('SELECT A || B AB FROM T', 'AB'), '?computed by the SQL');
  CheckText('FIRST n and semicolon', Col('SELECT FIRST 1 A FROM T;', 'A'), 'T.A');
end;

{ ---- handler code ---- }

const
  UNIT_HEAD = 'unit U;'#13#10'interface'#13#10'implementation'#13#10;

function CodeField(const pComp, pData, pAccessor: string; pCalc: Boolean): TDfmrCodeField;
begin
  Result.CompName := pComp;
  Result.DataName := pData;
  Result.MacroName := UpperCase(pData);
  Result.Accessor := pAccessor;
  Result.IsCalc := pCalc;
end;

function Ctx: TDfmrCodeContext;
begin
  Result.FormClass := 'TForm1';
  Result.Dataset := 'T1';
  Result.Components := ['T1', 'T1QTY', 'T1PRICE', 'T1TOTAL', 'T1NAME', 'T1NOTE', 'Edit1', 'T2'];
  Result.Fields := [CodeField('T1QTY', 'Qty', 'AsInteger', False), CodeField('T1PRICE', 'Price', 'AsFloat', False),
    CodeField('T1TOTAL', 'Total', 'AsFloat', True), CodeField('T1NAME', 'Name', 'AsString', True),
    CodeField('T1NOTE', 'Note', 'AsString', True)];
end;

function Handler(const pDecls, pBody: string; const pParam: string = 'DataSet'): string;
begin
  Result := UNIT_HEAD + 'procedure TForm1.T1CalcFields(' + pParam + ': TDataSet);'#13#10 + pDecls + 'begin'#13#10 + pBody
    + #13#10'end;'#13#10'end.'#13#10;
end;

function Body(const pText, pField: string): string;
var
  VUnit: TDfmrUnit;
  VBody: TDfmrBody;
begin
  VUnit := TDfmrUnit.CreateFromText(pText, 'U.pas');
  try
    VBody := VUnit.CalcBody(Ctx, 'T1CalcFields', pField);
  finally
    VUnit.Free;
  end;
  Result := (if VBody.Blocked = '' then '' else '!' + VBody.Blocked + '! ') + VBody.Text;
  if Length(VBody.FormNames) > 0 then
    Result := Result + ' {form: ' + string.Join(',', VBody.FormNames) + '}';
end;

procedure TestCalc;
const
  TWO = '  T1TOTAL.Value := T1QTY.Value * T1PRICE.AsFloat; // sum'#13#10'  T1NAME.AsString := ''x'';';
  SPLIT = '  if T1QTY.Value > 0 then'#13#10'  begin'#13#10'    T1TOTAL.Value := 1;'#13#10'    T1NAME.Value := ''a'';'#13#10 +
    '  end'#13#10'  else'#13#10'    T1NAME.Value := ''b'';';
  LOCALS = '  I := T1QTY.Value;'#13#10'  S := ''x'';'#13#10'  T1TOTAL.Value := I * 2;'#13#10'  T1NAME.Value := S;';
begin
  CheckText('C1 macros, trailing comment kept, other field dropped', Body(Handler('', TWO), 'T1TOTAL'),
    '{{TOTAL}} := {{QTY}} * {{PRICE}}; // sum');
  CheckText('C1b the other field', Body(Handler('', TWO), 'T1NAME'), '{{NAME}} := ''x'';');
  CheckText('C2 shared if: the other assignment is cut', Body(Handler('', SPLIT), 'T1TOTAL'),
    'if {{QTY}} > 0 then'#13#10'begin'#13#10'  {{TOTAL}} := 1;'#13#10'end'#13#10'else'#13#10'  ;');
  CheckText('C2b shared if: kept in both branches', Body(Handler('', SPLIT), 'T1NAME'),
    'if {{QTY}} > 0 then'#13#10'begin'#13#10'  {{NAME}} := ''a'';'#13#10'end'#13#10'else'#13#10'  {{NAME}} := ''b'';');
  CheckText('C3 only the locals it needs, declared inline', Body(Handler('var'#13#10'  I: Integer;'#13#10'  S: string;'#13#10, LOCALS), 'T1TOTAL'),
    'var I: Integer;'#13#10'I := {{QTY}};'#13#10'{{TOTAL}} := I * 2;');
  CheckText('C4 an unknown effect before it is kept, form name noted',
    Body(Handler('', '  T2.Locate(''ID'', 1, []);'#13#10'  T1NAME.Value := Edit1.Text;'#13#10'  Beep;'), 'T1NAME'),
    'T2.Locate(''ID'', 1, []);'#13#10'{{NAME}} := Edit1.Text; {form: Edit1,T2}');
  CheckText('C5 FieldByName, subscript target, renamed parameter', Body(Handler('',
    '  DS.FieldByName(''Total'').AsFloat := DS.FieldByName(''Qty'').AsInteger;'#13#10'  if DS.State = dsBrowse then DS[''Name''] := ''x'';', 'DS'), 'T1NAME'),
    'if DataSet.State = dsBrowse then {{NAME}} := ''x'';');
  CheckText('C5b FieldByName typed accessor', Body(Handler('', '  DataSet.FieldByName(''Total'').AsFloat := T1.FieldByName(''Qty'').AsInteger;'), 'T1TOTAL'),
    '{{TOTAL}} := {{QTY}};');
  CheckText('C6 IsNull blocks', Body(Handler('', '  if not T1QTY.IsNull then T1TOTAL.Value := 1;'), 'T1TOTAL'),
    '!T1QTY.IsNull is not its typed accessor (AsInteger)! if not T1QTY.IsNull then {{TOTAL}} := 1;');
  CheckText('C7 another accessor blocks', Body(Handler('', '  T1NAME.Value := T1QTY.AsString;'), 'T1NAME'),
    '!T1QTY.AsString is not its typed accessor (AsInteger)! {{NAME}} := T1QTY.AsString;');
  CheckText('C8 Variant read blocks', Body(Handler('', '  T1TOTAL.Value := DataSet[''Qty''];'), 'T1TOTAL'),
    '!reads the Variant DataSet[''Qty'']! {{TOTAL}} := DataSet[''Qty''];');
  CheckText('C9 an Exit guard becomes a block', Body(Handler('', '  if T1QTY.Value = 0 then'#13#10#9'exit;'#13#10'  if T1PRICE.Value = 0 then begin Exit; end;'#13#10 +
    '  T1TOTAL.Value :='#13#10'    1;'), 'T1TOTAL'),
    'if not ({{QTY}} = 0) then'#13#10'begin'#13#10'  if not ({{PRICE}} = 0) then'#13#10'  begin'#13#10'    {{TOTAL}} :='#13#10'      1;'#13#10'  end;'#13#10'end;');
  Check('C9b any other Exit blocks', Body(Handler('', '  if T1QTY.Value = 0 then'#13#10'  begin'#13#10'    T1TOTAL.Value := 0;'#13#10#9'Exit;'#13#10'  end;'#13#10'  T1TOTAL.Value := 1;'), 'T1TOTAL')
    .StartsWith('!Exit would skip'));
  Check('C9c a guard with else blocks', Body(Handler('', '  if T1QTY.Value = 0 then Exit else Beep;'#13#10'  T1TOTAL.Value := 1;'), 'T1TOTAL').StartsWith('!Exit would skip'));
  Check('C10 with blocks', Body(Handler('', '  with T1 do T1TOTAL.Value := 1;'), 'T1TOTAL').StartsWith('!a with statement!'));
  Check('C11 a directive blocks', Body(Handler('', '  {$IFDEF X}'#13#10'  T1TOTAL.Value := 1;'#13#10'  {$ENDIF}'#13#10'  T1TOTAL.Value := 2;'), 'T1TOTAL').Contains('compiler directives'));
  CheckText('C12 a handler that does not assign it', Body(Handler('', '  Beep;'), 'T1TOTAL'), '');
  CheckText('C13 handler missing', Body(UNIT_HEAD + 'end.', 'T1TOTAL'), '!TForm1.T1CalcFields is not in the unit! ');
  CheckText('C14 inherited is dropped, comment above kept', Body(Handler('', '  inherited;'#13#10'  // total'#13#10'  T1TOTAL.Value := 1'), 'T1TOTAL'),
    '// total'#13#10'{{TOTAL}} := 1;');
  Check('C15 a nested routine blocks', Body(Handler('procedure P; begin end;'#13#10, '  T1TOTAL.Value := 1;'), 'T1TOTAL').Contains('declares'));
  Check('C16 the component itself blocks', Body(Handler('', '  T1TOTAL.Value := Calc(T1QTY);'), 'T1TOTAL').Contains('the field component T1QTY itself is used'));
  CheckText('C17 a // comment inside a guard condition ends at its line', Body(Handler('', '  if (T1QTY.Value = 0) // none'#13#10'    or (T1PRICE.Value = 0) then Exit;'#13#10'  T1TOTAL.Value := 1;'), 'T1TOTAL'),
    'if not (({{QTY}} = 0) // none'#13#10'    or ({{PRICE}} = 0)) then'#13#10'begin'#13#10'  {{TOTAL}} := 1;'#13#10'end;');
  CheckText('C17b a comment before the guard condition', Body(Handler('', '  if { none } T1QTY.Value = 0 then Exit;'#13#10'  T1TOTAL.Value := 1;'), 'T1TOTAL'),
    'if not ({{QTY}} = 0) then'#13#10'begin'#13#10'  {{TOTAL}} := 1;'#13#10'end;');
  Check('C18 macro braces in the code block', Body(Handler('', '  T1NAME.Value := ''{{QTY}}'';'), 'T1NAME').StartsWith('!'), Body(Handler('', '  T1NAME.Value := ''{{QTY}}'';'), 'T1NAME'));
  Check('C18b macro braces in a comment block', Body(Handler('', '  {{ note }'#13#10'  T1NAME.Value := ''x'';'), 'T1NAME').StartsWith('!'));
  CheckText('C18c end, quotes and nested comments in the code are text', Body(Handler('', '  T1NAME.Value := ''it''''s the end; { // '' + ''(*''; (* { end; *)'#13#10'  // begin end;'#13#10'  T1TOTAL.Value := 1;'), 'T1NAME'),
    '{{NAME}} := ''it''''s the end; { // '' + ''(*''; (* { end; *)');
  CheckText('C19 a constant another constant needs', Body(Handler('const'#13#10'  A = 1;'#13#10'  B = A + 1;'#13#10'  C = 3;'#13#10, '  T1TOTAL.Value := B;'), 'T1TOTAL'),
    'const A = 1;'#13#10'const B = A + 1;'#13#10'{{TOTAL}} := B;');
  CheckText('C20 a cursor move inside another field''s assignment is kept',
    Body(Handler('', '  T1TOTAL.Value := Ord(T2.Locate(''ID'', 1, []));'#13#10'  T1NAME.Value := Edit1.Text;'), 'T1NAME'),
    '{{TOTAL}} := Ord(T2.Locate(''ID'', 1, []));'#13#10'{{NAME}} := Edit1.Text; {form: Edit1,T2}');
  CheckText('C20b a cursor move whose result goes to an unused local is kept',
    Body(Handler('var Ok: Boolean;'#13#10, '  Ok := T2.FindKey([1]);'#13#10'  T1NAME.Value := Edit1.Text;'), 'T1NAME'),
    'var Ok: Boolean;'#13#10'Ok := T2.FindKey([1]);'#13#10'{{NAME}} := Edit1.Text; {form: Edit1,T2}');
  Check('C21 a local set by a statement left out blocks', Body(Handler('var S: string;'#13#10, '  T1TOTAL.Value := Split(T1QTY.Value, S);'#13#10'  T1NAME.Value := S;'), 'T1NAME')
    .StartsWith('!the local S may be set by a statement left out'), Body(Handler('var S: string;'#13#10, '  T1TOTAL.Value := Split(T1QTY.Value, S);'#13#10'  T1NAME.Value := S;'), 'T1NAME'));
  CheckText('C21b a local read by a statement left out does not', Body(Handler('var S: string;'#13#10, '  S := ''a'';'#13#10'  T1TOTAL.Value := Length(S);'#13#10'  T1NAME.Value := S;'), 'T1NAME'),
    'var S: string;'#13#10'S := ''a'';'#13#10'{{NAME}} := S;');
  Check('C22 a calc field that changes after it was read blocks', Body(Handler('', '  T1NOTE.Value := ''a'';'#13#10'  T1NAME.Value := T1NOTE.Value;'#13#10'  T1NOTE.Value := ''b'';'), 'T1NAME')
    .StartsWith('!T1NOTE changes after this body reads it'), Body(Handler('', '  T1NOTE.Value := ''a'';'#13#10'  T1NAME.Value := T1NOTE.Value;'#13#10'  T1NOTE.Value := ''b'';'), 'T1NAME'));
  CheckText('C22b fields set together, then one again, do not', Body(Handler('', '  if T1QTY.Value > 0 then begin T1NOTE.Value := ''a''; T1NAME.Value := ''a''; end;'#13#10'  T1NOTE.Value := ''b'';'), 'T1NAME'),
    'if {{QTY}} > 0 then begin ; {{NAME}} := ''a''; end;');
end;

procedure TestEvent;
var
  VUnit: TDfmrUnit;
  VBody: TDfmrBody;
begin
  VUnit := TDfmrUnit.CreateFromText(UNIT_HEAD + 'procedure TForm1.T1QTYGetText(Sender: TField; var AText: string; DisplayText: Boolean);'#13#10 +
    'var S: string;'#13#10'begin'#13#10'  S := Sender.AsString;'#13#10'  if T1NAME.Value = '''' then Exit;'#13#10'  AText := S;'#13#10'end;'#13#10'end.', 'U.pas');
  try
    VBody := VUnit.EventBody(Ctx, 'T1QTYGetText', ['Sender', 'Text', 'DisplayText']);
  finally
    VUnit.Free;
  end;
  CheckText('E1 whole handler, macros, parameter renamed, Exit allowed', VBody.Text,
    'var S: string;'#13#10'S := Sender.AsString;'#13#10'if {{NAME}} = '''' then Exit;'#13#10'Text := S;');
  CheckText('E1b not blocked', VBody.Blocked, '');
end;

begin
  try
    TestSelection;
    TestSql;
    TestCalc;
    TestEvent;
  except
    on E: Exception do
      Check('no exception', False, E.ClassName + ': ' + E.Message);
  end;
  Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
