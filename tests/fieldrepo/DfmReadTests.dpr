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
  CheckText('macro after the table', Col('SELECT A FROM T &JOINS', 'A'), '!the SQL has a macro');
  CheckText('macro with an exclamation mark', Col('SELECT A FROM T !JOINS WHERE B = 1', 'A'), '!the SQL has a macro');
  CheckText('macro row count', Col('SELECT FIRST &N NAME FROM T', 'NAME'), '!the SQL has a macro');
  CheckText('macro item', Col('SELECT A, &MORE FROM T', 'A'), '!the SQL has a macro');
  CheckText('a macro of the WHERE clause says nothing about a column', Col('SELECT A FROM T WHERE &COND', 'A'), 'T.A');
  CheckText('!= is an operator', Col('SELECT A, B != C AS X FROM T', 'A'), 'T.A');
  CheckText('a macro in a text or a comment', Col('SELECT A, ''&X'' AS S /* &Y */ FROM T', 'A'), 'T.A');
  CheckText('NOT is an operator', Col('SELECT NOT ACTIVE FROM T', 'ACTIVE'), '?computed by the SQL');
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

function CodeField(const pComp, pData: string; pCalc: Boolean): TDfmrCodeField;
begin
  Result.CompName := pComp;
  Result.DataName := pData;
  Result.MacroName := UpperCase(pData);
  Result.IsCalc := pCalc;
end;

function Ctx: TDfmrCodeContext;
begin
  Result.FormClass := 'TForm1';
  Result.Dataset := 'T1';
  Result.Components := ['T1', 'T1QTY', 'T1PRICE', 'T1TOTAL', 'T1NAME', 'T1NOTE', 'Edit1', 'T2'];
  Result.Fields := [CodeField('T1QTY', 'Qty', False), CodeField('T1PRICE', 'Price', False), CodeField('T1TOTAL', 'Total', True),
    CodeField('T1NAME', 'Name', True), CodeField('T1NOTE', 'Note', True)];
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
    '{{TOTAL}}.Value := {{QTY}}.Value * {{PRICE}}.AsFloat; // sum');
  CheckText('C1b the other field', Body(Handler('', TWO), 'T1NAME'), '{{NAME}}.AsString := ''x'';');
  CheckText('C2 shared if: the other assignment is cut', Body(Handler('', SPLIT), 'T1TOTAL'),
    'if {{QTY}}.Value > 0 then'#13#10'begin'#13#10'  {{TOTAL}}.Value := 1;'#13#10'end'#13#10'else'#13#10'  ;');
  CheckText('C2b shared if: kept in both branches', Body(Handler('', SPLIT), 'T1NAME'),
    'if {{QTY}}.Value > 0 then'#13#10'begin'#13#10'  {{NAME}}.Value := ''a'';'#13#10'end'#13#10'else'#13#10'  {{NAME}}.Value := ''b'';');
  CheckText('C3 only the locals it needs, declared inline', Body(Handler('var'#13#10'  I: Integer;'#13#10'  S: string;'#13#10, LOCALS), 'T1TOTAL'),
    'var I: Integer;'#13#10'I := {{QTY}}.Value;'#13#10'{{TOTAL}}.Value := I * 2;');
  CheckText('C4 an unknown effect before it is kept, form name noted',
    Body(Handler('', '  T2.Locate(''ID'', 1, []);'#13#10'  T1NAME.Value := Edit1.Text;'#13#10'  Beep;'), 'T1NAME'),
    'T2.Locate(''ID'', 1, []);'#13#10'{{NAME}}.Value := Edit1.Text; {form: Edit1,T2}');
  CheckText('C5 FieldByName, subscript target, renamed parameter', Body(Handler('',
    '  DS.FieldByName(''Total'').AsFloat := DS.FieldByName(''Qty'').AsInteger;'#13#10'  if DS.State = dsBrowse then DS[''Name''] := ''x'';', 'DS'), 'T1NAME'),
    'if DataSet.State = dsBrowse then {{NAME}}.AsVariant := ''x'';');
  CheckText('C5b FieldByName typed accessor', Body(Handler('', '  DataSet.FieldByName(''Total'').AsFloat := T1.FieldByName(''Qty'').AsInteger;'), 'T1TOTAL'),
    '{{TOTAL}}.AsFloat := {{QTY}}.AsInteger;');
  CheckText('C5c FieldByName(..).Value is a Variant', Body(Handler('', '  DataSet.FieldByName(''Total'').Value := T1.FieldByName(''Qty'').Value;'), 'T1TOTAL'),
    '{{TOTAL}}.AsVariant := {{QTY}}.AsVariant;');
  CheckText('C5d a field the dataset does not have blocks', Body(Handler('', '  T1TOTAL.Value := DataSet.FieldByName(''Nope'').AsInteger;'), 'T1TOTAL'),
    '!FieldByName(''Nope'') has no persistent field! {{TOTAL}}.Value := DataSet.FieldByName(''Nope'').AsInteger;');
  CheckText('C6 IsNull', Body(Handler('', '  if not T1QTY.IsNull then T1TOTAL.Value := 1;'), 'T1TOTAL'),
    'if not {{QTY}}.IsNull then {{TOTAL}}.Value := 1;');
  CheckText('C7 another accessor', Body(Handler('', '  T1NAME.Value := T1QTY.AsString;'), 'T1NAME'),
    '{{NAME}}.Value := {{QTY}}.AsString;');
  CheckText('C7b a chained member, Self', Body(Handler('', '  T1NAME.Value := Self.T1QTY.DisplayText.Trim;'), 'T1NAME'),
    '{{NAME}}.Value := {{QTY}}.DisplayText.Trim;');
  CheckText('C8 a Variant read', Body(Handler('', '  T1TOTAL.Value := DataSet[''Qty''];'), 'T1TOTAL'),
    '{{TOTAL}}.Value := {{QTY}}.AsVariant;');
  CheckText('C8b a Variant read of an unknown field blocks', Body(Handler('', '  T1TOTAL.Value := DataSet[''Nope''];'), 'T1TOTAL'),
    '!DataSet[''Nope''] has no persistent field! {{TOTAL}}.Value := DataSet[''Nope''];');
  CheckText('C9 an Exit guard becomes a block', Body(Handler('', '  if T1QTY.Value = 0 then'#13#10#9'exit;'#13#10'  if T1PRICE.Value = 0 then begin Exit; end;'#13#10 +
    '  T1TOTAL.Value :='#13#10'    1;'), 'T1TOTAL'),
    'if not ({{QTY}}.Value = 0) then'#13#10'begin'#13#10'  if not ({{PRICE}}.Value = 0) then'#13#10'  begin'#13#10'    {{TOTAL}}.Value :='#13#10'      1;'#13#10'  end;'#13#10'end;');
  Check('C9b any other Exit blocks', Body(Handler('', '  if T1QTY.Value = 0 then'#13#10'  begin'#13#10'    T1TOTAL.Value := 0;'#13#10#9'Exit;'#13#10'  end;'#13#10'  T1TOTAL.Value := 1;'), 'T1TOTAL')
    .StartsWith('!Exit would skip'));
  Check('C9c a guard with else blocks', Body(Handler('', '  if T1QTY.Value = 0 then Exit else Beep;'#13#10'  T1TOTAL.Value := 1;'), 'T1TOTAL').StartsWith('!Exit would skip'));
  Check('C10 with blocks', Body(Handler('', '  with T1 do T1TOTAL.Value := 1;'), 'T1TOTAL').StartsWith('!a with statement!'));
  Check('C11 a directive blocks', Body(Handler('', '  {$IFDEF X}'#13#10'  T1TOTAL.Value := 1;'#13#10'  {$ENDIF}'#13#10'  T1TOTAL.Value := 2;'), 'T1TOTAL').Contains('compiler directives'));
  CheckText('C12 a handler that does not assign it', Body(Handler('', '  Beep;'), 'T1TOTAL'), '');
  CheckText('C13 handler missing', Body(UNIT_HEAD + 'end.', 'T1TOTAL'), '!TForm1.T1CalcFields is not in the unit! ');
  CheckText('C14 inherited is dropped, comment above kept', Body(Handler('', '  inherited;'#13#10'  // total'#13#10'  T1TOTAL.Value := 1'), 'T1TOTAL'),
    '// total'#13#10'{{TOTAL}}.Value := 1;');
  Check('C15 a nested routine blocks', Body(Handler('procedure P; begin end;'#13#10, '  T1TOTAL.Value := 1;'), 'T1TOTAL').Contains('declares'));
  CheckText('C16 the component of a data field itself', Body(Handler('', '  T1TOTAL.Value := Calc(T1QTY, T1.FieldByName(''Price''), Self.T1QTY);'), 'T1TOTAL'),
    '{{TOTAL}}.Value := Calc({{QTY}}, {{PRICE}}, {{QTY}});');
  CheckText('C16b a calculated field''s component itself blocks: the called code may change it', Body(Handler('', '  T1TOTAL.Value := Calc(T1NOTE);'), 'T1TOTAL'),
    '!the field component T1NOTE itself is used! {{TOTAL}}.Value := Calc({{NOTE}});');
  CheckText('C16c ... also in a statement left out', Body(Handler('', '  T1TOTAL.Value := 1;'#13#10'  Fix(T1TOTAL);'), 'T1TOTAL'),
    '!the field component T1TOTAL itself is used! {{TOTAL}}.Value := 1;');
  CheckText('C16d a method call on a calculated field belongs to that field', Body(Handler('', '  T1TOTAL.Assign(T1QTY);'#13#10'  T1NAME.Value := ''x'';'), 'T1TOTAL'), '{{TOTAL}}.Assign({{QTY}});');
  CheckText('C16e ... and is left out of the others', Body(Handler('', '  T1TOTAL.Assign(T1QTY);'#13#10'  T1NAME.Value := ''x'';'), 'T1NAME'), '{{NAME}}.Value := ''x'';');
  CheckText('C16f control: a data field''s component in another statement does not block', Body(Handler('', '  T1TOTAL.Value := 1;'#13#10'  Fix(T1QTY);'), 'T1TOTAL'), '{{TOTAL}}.Value := 1;');
  CheckText('C17 a // comment inside a guard condition ends at its line', Body(Handler('', '  if (T1QTY.Value = 0) // none'#13#10'    or (T1PRICE.Value = 0) then Exit;'#13#10'  T1TOTAL.Value := 1;'), 'T1TOTAL'),
    'if not (({{QTY}}.Value = 0) // none'#13#10'    or ({{PRICE}}.Value = 0)) then'#13#10'begin'#13#10'  {{TOTAL}}.Value := 1;'#13#10'end;');
  CheckText('C17b a comment before the guard condition', Body(Handler('', '  if { none } T1QTY.Value = 0 then Exit;'#13#10'  T1TOTAL.Value := 1;'), 'T1TOTAL'),
    'if not ({{QTY}}.Value = 0) then'#13#10'begin'#13#10'  {{TOTAL}}.Value := 1;'#13#10'end;');
  Check('C18 macro braces in the code block', Body(Handler('', '  T1NAME.Value := ''{{QTY}}'';'), 'T1NAME').StartsWith('!'), Body(Handler('', '  T1NAME.Value := ''{{QTY}}'';'), 'T1NAME'));
  Check('C18b macro braces in a comment block', Body(Handler('', '  {{ note }'#13#10'  T1NAME.Value := ''x'';'), 'T1NAME').StartsWith('!'));
  CheckText('C18c end, quotes and nested comments in the code are text', Body(Handler('', '  T1NAME.Value := ''it''''s the end; { // '' + ''(*''; (* { end; *)'#13#10'  // begin end;'#13#10'  T1TOTAL.Value := 1;'), 'T1NAME'),
    '{{NAME}}.Value := ''it''''s the end; { // '' + ''(*''; (* { end; *)');
  CheckText('C19 a constant another constant needs', Body(Handler('const'#13#10'  A = 1;'#13#10'  B = A + 1;'#13#10'  C = 3;'#13#10, '  T1TOTAL.Value := B;'), 'T1TOTAL'),
    'const A = 1;'#13#10'const B = A + 1;'#13#10'{{TOTAL}}.Value := B;');
  CheckText('C20 a cursor move inside another field''s assignment is kept',
    Body(Handler('', '  T1TOTAL.Value := Ord(T2.Locate(''ID'', 1, []));'#13#10'  T1NAME.Value := Edit1.Text;'), 'T1NAME'),
    '{{TOTAL}}.Value := Ord(T2.Locate(''ID'', 1, []));'#13#10'{{NAME}}.Value := Edit1.Text; {form: Edit1,T2}');
  CheckText('C20b a cursor move whose result goes to an unused local is kept',
    Body(Handler('var Ok: Boolean;'#13#10, '  Ok := T2.FindKey([1]);'#13#10'  T1NAME.Value := Edit1.Text;'), 'T1NAME'),
    'var Ok: Boolean;'#13#10'Ok := T2.FindKey([1]);'#13#10'{{NAME}}.Value := Edit1.Text; {form: Edit1,T2}');
  Check('C21 a local set by a statement left out blocks', Body(Handler('var S: string;'#13#10, '  T1TOTAL.Value := Split(T1QTY.Value, S);'#13#10'  T1NAME.Value := S;'), 'T1NAME')
    .StartsWith('!the local S may be set by a statement left out'), Body(Handler('var S: string;'#13#10, '  T1TOTAL.Value := Split(T1QTY.Value, S);'#13#10'  T1NAME.Value := S;'), 'T1NAME'));
  CheckText('C21b a local read by a statement left out does not', Body(Handler('var S: string;'#13#10, '  S := ''a'';'#13#10'  T1TOTAL.Value := Length(S);'#13#10'  T1NAME.Value := S;'), 'T1NAME'),
    'var S: string;'#13#10'S := ''a'';'#13#10'{{NAME}}.Value := S;');
  Check('C22 a calc field that changes after it was read blocks', Body(Handler('', '  T1NOTE.Value := ''a'';'#13#10'  T1NAME.Value := T1NOTE.Value;'#13#10'  T1NOTE.Value := ''b'';'), 'T1NAME')
    .StartsWith('!T1NOTE changes after this body reads it'), Body(Handler('', '  T1NOTE.Value := ''a'';'#13#10'  T1NAME.Value := T1NOTE.Value;'#13#10'  T1NOTE.Value := ''b'';'), 'T1NAME'));
  CheckText('C22b fields set together, then one again, do not', Body(Handler('', '  if T1QTY.Value > 0 then begin T1NOTE.Value := ''a''; T1NAME.Value := ''a''; end;'#13#10'  T1NOTE.Value := ''b'';'), 'T1NAME'),
    'if {{QTY}}.Value > 0 then begin ; {{NAME}}.Value := ''a''; end;');
end;

{ The body read from an OnGetText handler; pBefore = statements of the calc handler above it. }
function Event(const pBody: string; const pBefore: string = ''): string;
var
  VUnit: TDfmrUnit;
  VBody: TDfmrBody;
begin
  VUnit := TDfmrUnit.CreateFromText(UNIT_HEAD + 'procedure TForm1.T1CalcFields(DataSet: TDataSet);'#13#10'begin'#13#10 + pBefore +
    'end;'#13#10'procedure TForm1.T1QTYGetText(Sender: TField; var AText: string; DisplayText: Boolean);'#13#10'begin'#13#10 + pBody +
    #13#10'end;'#13#10'end.', 'U.pas');
  try
    VBody := VUnit.EventBody(Ctx, 'T1QTYGetText', ['Sender', 'Text', 'DisplayText']);
  finally
    VUnit.Free;
  end;
  Result := (if VBody.Blocked = '' then '' else '!' + VBody.Blocked + '! ') + VBody.Text;
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
    'var S: string;'#13#10'S := Sender.AsString;'#13#10'if {{NAME}}.Value = '''' then Exit;'#13#10'Text := S;');
  CheckText('E1b not blocked', VBody.Blocked, '');
  CheckText('E2 the component itself in an event', Event('  if Sender = T1NAME then AText := T1NOTE.DisplayText;'),
    'if Sender = {{NAME}} then Text := {{NOTE}}.DisplayText;');
end;

{ The code of generated regions is not read back. }
procedure TestRegions;
const
  REGION = '  {$REGION ''DLFR T1.OnCalcFields hash=0123456789abcdef''}'#13#10'  begin // TOTAL'#13#10'    T1TOTAL.Value := 5;'#13#10'  end;'#13#10 +
    '  {$ENDREGION ''DLFR T1.OnCalcFields''}'#13#10;
  REGION2 = '  {$REGION ''DLFR T1QTY.OnGetText hash=0123456789abcdef''}'#13#10'  begin'#13#10'    AText := ''g'';'#13#10'  end;'#13#10 +
    '  {$ENDREGION ''DLFR T1QTY.OnGetText''}'#13#10;
begin
  CheckText('R1 a field the region assigns is not read', Body(Handler('', '  T1TOTAL.Value := 1;'#13#10 + REGION), 'T1TOTAL'), '!its code is in the generated region DLFR T1.OnCalcFields! ');
  CheckText('R2 hand code beside the region is read', Body(Handler('', '  T1NAME.Value := ''caf'#233''';'#13#10 + REGION), 'T1NAME'), '{{NAME}}.Value := ''caf'#233''';');
  CheckText('R3 a region that is not closed blocks', Body(Handler('', '  T1NAME.Value := ''x'';'#13#10'  {$REGION ''DLFR T1.OnCalcFields hash=0123456789abcdef''}'), 'T1NAME'),
    '!the handler holds compiler directives! {{NAME}}.Value := ''x'';');
  CheckText('R6 the semicolon a region ends the code before it with stays', Body(Handler('', '  T1NAME.Value := ''x'''#13#10 +
    REGION.Replace('  begin // TOTAL', '  ;'#13#10'  begin // TOTAL') + '  if T1QTY.Value = 0 then T1NAME.Value := ''y'';'), 'T1NAME'),
    '{{NAME}}.Value := ''x'';'#13#10'if {{QTY}}.Value = 0 then {{NAME}}.Value := ''y'';');
  Check('R7 a handler that does not parse blocks, the kept statement is fine or not', Body(Handler('', '  T1NAME.Value := ''x'''#13#10 +
    '  if T1QTY.Value = 0 then T1NAME.Value := ''y'';'), 'T1NAME').StartsWith('!the handler does not parse'));
  CheckText('R4 an event handler with a region is not read', Event('  AText := ''h'';'#13#10 + REGION2), '!its code is in the generated region DLFR T1QTY.OnGetText! ');
  CheckText('R5 control: a region of another handler does not count', Event('  AText := ''h'';', REGION), 'Text := ''h'';');
end;

begin
  try
    TestSelection;
    TestSql;
    TestCalc;
    TestEvent;
    TestRegions;
  except
    on E: Exception do
      Check('no exception', False, E.ClassName + ': ' + E.Message);
  end;
  Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
