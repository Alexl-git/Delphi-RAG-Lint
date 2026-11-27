program HandlersTests;

{ Self-contained console test runner (no DUnitX) for the pure parts of lane TT-HANDLERS (drag-lint 1.54):
  HandlersRegions (Pascal scanner, DLFR region hash, DB-RAD n -> DLFR n, ASCII guard) and Handlers (calc region text,
  insertion at the end of a handler, hand-edit refusal, MAXLEN region). One PASS/FAIL line per case, a summary line,
  exit code 1 on any failure. The CLI, the compiler and the running form are run_fieldrepo_handlers.ps1. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  DRagLint.FieldRepo.Kinds in '..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.HandlersRegions in '..\..\src\sql\DRagLint.FieldRepo.HandlersRegions.pas',
  DRagLint.FieldRepo.Handlers in '..\..\src\sql\DRagLint.FieldRepo.Handlers.pas';

const
  NL = #13#10;

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

function L(const pLines: array of string): string;
var
  VLine: string;
begin
  Result := '';
  for VLine in pLines do
    Result := Result + VLine + NL;
end;

{ ---- scanner ---- }

function DirectiveNames(const pText: string): string;
var
  VDirective: TPasDirective;
begin
  Result := '';
  for VDirective in ScanPascal(pText).Directives do
    Result := Result + VDirective.Text + '/' + IntToStr(VDirective.IfDepth) + ';';
end;

procedure TestScan;
begin
  CheckText('S1 plain directive', DirectiveNames('{$REGION ''a''} x {$ENDREGION}'), 'REGION ''a''/0;ENDREGION/0;');
  CheckText('S2 paren directive', DirectiveNames('(*$REGION ''a''*)'), 'REGION ''a''/0;');
  CheckText('S3 a marker after // is not a directive', DirectiveNames('// {$REGION ''a''}' + NL + '{$R x}'), 'R x/0;');
  CheckText('S4 a marker in a (* *) comment is not one', DirectiveNames('(* {$REGION ''a''} *)'), '');
  CheckText('S5 a marker in a brace comment is not one', DirectiveNames('{ old: (*$REGION ''a''*) }'), '');
  CheckText('S6 a marker in a string is not one', DirectiveNames('s := ''{$REGION ''''a''''}'';'), '');
  CheckText('S7 a marker in a multi-line string is not one',
    DirectiveNames('s := ''''''' + NL + '  {$REGION ''a''}' + NL + '  '''''';' + NL + '{$R y}'), 'R y/0;');
  CheckText('S8 two quotes are an empty string', DirectiveNames('s := ''''; {$R y}'), 'R y/0;');
  CheckText('S9 four quotes are one quote character', DirectiveNames('s := ''''''''; {$R y}'), 'R y/0;');
  CheckText('S10 conditional depth', DirectiveNames('{$IFDEF A}{$R x}{$ELSE}{$R z}{$ENDIF}{$R y}'), 'IFDEF A/0;R x/1;ELSE/1;R z/1;ENDIF/1;R y/0;');
  Check('S11 an unterminated comment is a problem', ScanPascal('a { b').Problem <> '');
  Check('S12 a // brace is none', ScanPascal('a // { b').Problem = '');
  Check('S13 a string left open is counted', ScanPascal('s := ''abc' + NL + 'x').OpenStrings = 1);
  CheckText('S14 code only: same length, comments strings directives blanked', ScanPascal('a{b}''c''//d').Code, 'a         ');
  Check('S15 inside a comment', ScanPascal('ab{cd}ef').IsInside(5) and not ScanPascal('ab{cd}ef').IsInside(3) and not ScanPascal('ab{cd}ef').IsInside(7));
  CheckText('S16 a // line in a brace comment does not hide its end', DirectiveNames('{ x' + NL + '// }' + NL + '{$R y}'), 'R y/0;');
end;

{ ---- regions ---- }

const
  REGION_ID = 'tblA.OnCalcFields';

function Unit1(const pRegion: string): string;
begin
  Result := L(['unit u1;', 'interface', 'implementation', 'begin']) + pRegion + L(['end.']);
end;

function FindState(const pText: string; const pId: string = REGION_ID): string;
var
  VRegion: TDlfrRegion;
  VReason: string;
begin
  case FindDlfrRegion(pText, pId, VRegion, VReason) of
    drsAbsent: Result := 'absent';
    drsIntact: Result := 'intact';
    drsEdited: Result := 'edited: ' + VReason;
  else
    Result := 'unusable: ' + VReason;
  end;
end;

procedure TestRegions;
var
  VGood, VText, VReason: string;
  VRegion: TDlfrRegion;
begin
  VGood := RenderDlfrRegion(REGION_ID, '  x := 1;' + NL, '  ', NL);
  Check('R1 marker lines', VGood.StartsWith('  {$REGION ''DLFR tblA.OnCalcFields hash=') and
    VGood.EndsWith('  {$ENDREGION ''DLFR tblA.OnCalcFields''}' + NL), VGood);
  CheckText('R2 a fresh region is intact', FindState(Unit1(VGood)), 'intact');
  CheckText('R3 none is absent', FindState(Unit1('')), 'absent');
  CheckText('R4 the id is compared case-insensitively', FindState(Unit1(VGood), 'TBLa.oncalcfields'), 'intact');
  CheckText('R5 another id is absent', FindState(Unit1(VGood), 'tblB.OnCalcFields'), 'absent');
  Check('R6 one character changed = edited', FindState(Unit1(VGood.Replace('x := 1', 'x := 2'))).StartsWith('edited'));
  Check('R7 a line added = edited', FindState(Unit1(VGood.Replace('x := 1;', 'x := 1;' + NL + 'y;'))).StartsWith('edited'));
  Check('R8 the hash changed = edited', FindState(Unit1(VGood.Replace('hash=', 'hash=0'))).StartsWith('edited'));
  Check('R9 no hash = edited', FindState(Unit1(L(['  {$REGION ''DLFR tblA.OnCalcFields''}', 'x', '  {$ENDREGION ''DLFR tblA.OnCalcFields''}']))).StartsWith('edited'));
  CheckText('R10 LF line ends do not change the hash', FindState(Unit1(VGood).Replace(#13, '')), 'intact');
  CheckText('R11 a commented-out copy above is not the region', FindState(Unit1(L(['(*']) + VGood.Replace('x := 1', 'old') + L(['*)']) + VGood)), 'intact');
  CheckText('R12 only a commented-out copy = absent', FindState(Unit1(L(['(*']) + VGood + L(['*)']))), 'absent');
  CheckText('R13 only a line-commented copy = absent', FindState(Unit1('//' + VGood.TrimRight.Replace(NL, NL + '//') + NL)), 'absent');
  CheckText('R14 only a copy in a multi-line string = absent', FindState(Unit1(L(['s := ''''''']) + VGood + L(['  '''''';']))), 'absent');
  Check('R15 twice = unusable', FindState(Unit1(VGood + VGood)).StartsWith('unusable'));
  Check('R16 the end marker is missing = unusable',
    FindState(Unit1(VGood.Replace('  {$ENDREGION ''DLFR tblA.OnCalcFields''}' + NL, ''))).StartsWith('unusable'));
  Check('R17 a commented-out end marker is no end = unusable',
    FindState(Unit1(VGood.Replace('{$ENDREGION', '// {$ENDREGION'))).StartsWith('unusable'));
  Check('R18 the end marker of another region = unusable',
    FindState(Unit1(VGood.Replace('{$ENDREGION ''DLFR tblA', '{$ENDREGION ''DLFR tblB'))).StartsWith('unusable'));
  Check('R19 inside {$IFDEF} = unusable', FindState(Unit1(L(['{$IFDEF X}']) + VGood + L(['{$ENDIF}']))).StartsWith('unusable'));
  Check('R20 code behind the start marker = unusable', FindState(Unit1(VGood.Replace('''}' + NL + '  x', '''} z;' + NL + '  x'))).StartsWith('unusable'));
  Check('R21 code before the end marker = unusable', FindState(Unit1(VGood.Replace('  {$ENDREGION', 'z; {$ENDREGION'))).StartsWith('unusable'));
  Check('R22 an unterminated comment = unusable', FindState(Unit1(VGood) + '{ x').StartsWith('unusable'));

  VText := Unit1(VGood);
  Check('R23 found', FindDlfrRegion(VText, REGION_ID, VRegion, VReason) = drsIntact);
  CheckText('R24 content', VRegion.Content(VText), '  x := 1;' + NL);
  CheckText('R25 the same content changes nothing', ReplaceDlfrContent(VText, VRegion, '  x := 1;' + NL), VText);
  CheckText('R26 new content: the region only, hash renewed', ReplaceDlfrContent(VText, VRegion, '  x := 3;' + NL),
    Unit1(RenderDlfrRegion(REGION_ID, '  x := 3;' + NL, '  ', NL)));
  CheckText('R27 the replaced region is intact', FindState(ReplaceDlfrContent(VText, VRegion, '  x := 3;' + NL)), 'intact');
  VText := Unit1(L(['  {$REGION ''Documentation''}', '  {$ENDREGION}']) + VGood + L(['  {$REGION ''b''}', '  {$ENDREGION}']));
  CheckText('R28 other regions around it', FindState(VText), 'intact');
end;

{ ---- renumbering ---- }

procedure TestRenumber;
const
  MARKED = '{$REGION ''DB-RAD 1''}|x|{$ENDREGION ''DB-RAD 1''}|';
var
  VPlan: TDlfrRenumber;
  VText: string;

  function Renumber(const pText: string): TDlfrRenumber;
  begin
    Result := RenumberRegions(pText.Replace('|', NL));
  end;

  function NewText(const pText: string): string;
  begin
    Result := Renumber(pText).NewText.Replace(NL, '|');
  end;

  procedure Refused(const pName, pText: string);
  begin
    VPlan := Renumber(pText);
    Check(pName, (VPlan.Refused <> '') and (VPlan.NewText = pText.Replace('|', NL)) and (VPlan.Count = 0), VPlan.NewText);
  end;

begin
  CheckText('N1 both markers', NewText(MARKED), '{$REGION ''DLFR 1''}|x|{$ENDREGION ''DLFR 1''}|');
  CheckText('N2 letters and CL ids', NewText('{$REGION ''DB-RAD 1A''}|{$ENDREGION ''DB-RAD 1A''}|{$region ''DB-RAD CL-KEY''}|{$endregion ''DB-RAD CL-KEY''}|'),
    '{$REGION ''DLFR 1A''}|{$ENDREGION ''DLFR 1A''}|{$region ''DLFR CL-KEY''}|{$endregion ''DLFR CL-KEY''}|');
  CheckText('N3 the DB-RADa spelling', NewText('{$REGION ''DB-RADa 2''}|{$ENDREGION ''DB-RAD 2''}|'), '{$REGION ''DLFR 2''}|{$ENDREGION ''DLFR 2''}|');
  VText := '{$REGION ''MicStream -- not DB-RAD''}|{$ENDREGION ''MicStream -- not DB-RAD''}|';
  CheckText('N4 a hand-written region that only names DB-RAD', NewText(VText), VText);
  VText := '// {$REGION ''DB-RAD 1''}|s := ''{$REGION ''''DB-RAD 1''''}'';|(* {$REGION ''DB-RAD 1''} *)|';
  CheckText('N5 comments and strings stay', NewText(VText + MARKED), VText + '{$REGION ''DLFR 1''}|x|{$ENDREGION ''DLFR 1''}|');
  Check('N6 counts regions', Renumber(MARKED + MARKED.Replace('1', '3')).Count = 2);
  CheckText('N7 nested Documentation regions', NewText('{$REGION ''DB-RAD 2''}|{$REGION ''Documentation''}|{$ENDREGION}|{$ENDREGION ''DB-RAD 2''}|'),
    '{$REGION ''DLFR 2''}|{$REGION ''Documentation''}|{$ENDREGION}|{$ENDREGION ''DLFR 2''}|');
  VPlan := Renumber(NewText(MARKED));
  Check('N8 a second run writes nothing', (VPlan.Count = 0) and (VPlan.Refused = ''));
  Refused('N9 an unnamed end marker: the unit stays', '{$REGION ''DB-RAD 1''}|x|{$ENDREGION}|' + MARKED);
  Refused('N10 the end marker of another id: the unit stays', '{$REGION ''DB-RAD 1''}|{$ENDREGION ''DB-RAD 2''}|');
  Refused('N11 no end marker: the unit stays', MARKED + '{$REGION ''DB-RAD 2''}|x|');
  Refused('N12 the end marker is commented out: the unit stays', '{$REGION ''DB-RAD 1''}|// {$ENDREGION ''DB-RAD 1''}|');
  Refused('N13 the id exists as DLFR already: the unit stays', MARKED + '{$REGION ''DLFR 1''}|{$ENDREGION ''DLFR 1''}|');
  VText := '{$REGION ''DB-RAD notes''}|{$ENDREGION ''DB-RAD notes''}|';
  CheckText('N14 not an id of the generator', NewText(VText), VText);
  Check('N15 ... and reported', Length(Renumber(VText).Notes) = 1);
  Refused('N16 an unterminated comment: the unit stays', MARKED + '{ x');
  Refused('N17 an end marker without a region: the unit stays', MARKED + '{$ENDREGION ''DB-RAD 3''}|');
  CheckText('N18 OrmRegionId reads both spellings', OrmRegionId('DB-RAD 1a') + ',' + OrmRegionId('DLFR 1A') + ',' + OrmRegionId('db-rad CL-key'), '1A,1A,CL-KEY');
  CheckText('N19 ... and neither a handler nor the MAXLEN region nor a text',
    OrmRegionId('DLFR tblA.OnCalcFields hash=0123456789abcdef') + OrmRegionId('DLFR 2a hash=0123456789abcdef') + OrmRegionId('DLFR 2a') +
    OrmRegionId('DB-RAD notes') + OrmRegionId('not DB-RAD 1') + OrmRegionId('DB-RAD'), '');
  Refused('N21 the end marker of a hand region names an id: the unit stays', '{$REGION ''notes''}|x|{$ENDREGION ''DB-RAD 2''}|' + MARKED);
  Refused('N22 a half-renamed region: the unit stays', '{$REGION ''DLFR 2''}|x|{$ENDREGION ''DB-RAD 2''}|' + MARKED);
  Refused('N20 a string left open could hide a marker: the unit stays', 'x := ''a|' + MARKED);
end;

{ ---- calc region text ---- }

function Fld(const pColumn, pComp: string; const pBody: string = ''): TFrhField;
begin
  Result.Column := pColumn;
  Result.CompName := pComp;
  Result.IsCalc := pBody <> '';
  Result.Body := pBody;
end;

function CalcText(const pFields: TArray<TFrhField>): string;
var
  VContent, VReason: string;
begin
  if CalcRegionContent(pFields, VContent, VReason) then
    Result := VContent.Replace(NL, '|')
  else
    Result := '!' + VReason;
end;

procedure Refuses(const pName: string; const pFields: TArray<TFrhField>; const pReason: string);
begin
  Check(pName, CalcText(pFields).StartsWith('!') and ((pReason = '') or ContainsText(CalcText(pFields), pReason)), CalcText(pFields));
end;

function Deps(const pBody, pSelf: string): string;
begin
  try
    Result := string.Join(',', CalcDependencies(pBody, pSelf));
  except
    on E: EFrKindError do
      Result := E.Message;
  end;
end;

procedure TestCalc;
var
  VContent, VReason: string;
begin
  CheckText('C1 a macro is the component, the body carries the member',
    CalcText([Fld('QTY', 'tQ'), Fld('P', 'tP'), Fld('TOTAL', 'tT', 'if not {{P}}.IsNull then {{TOTAL}}.AsFloat := {{QTY}}.Value * {{p}}.AsFloat;')]),
    'begin // TOTAL|  if not tP.IsNull then tT.AsFloat := tQ.Value * tP.AsFloat;|end;|');
  CheckText('C2 a field is calculated after the ones it reads',
    CalcText([Fld('C', 'tC', '{{C}}.AsFloat := {{B}}.AsFloat;'), Fld('B', 'tB', '{{B}}.AsFloat := {{A}}.AsFloat;'), Fld('A', 'tA', '{{A}}.AsFloat := 1;')]),
    'begin // A|  tA.AsFloat := 1;|end;|begin // B|  tB.AsFloat := tA.AsFloat;|end;|begin // C|  tC.AsFloat := tB.AsFloat;|end;|');
  CheckText('C3 no dependency: the order of the DFM', CalcText([Fld('B', 'tB', '{{B}}.AsFloat := 2;'), Fld('A', 'tA', '{{A}}.AsFloat := 1;')]),
    'begin // B|  tB.AsFloat := 2;|end;|begin // A|  tA.AsFloat := 1;|end;|');
  Refuses('C4 a cycle is refused and named', [Fld('A', 'tA', '{{A}}.AsFloat := {{B}}.AsFloat;'), Fld('B', 'tB', '{{B}}.AsFloat := {{A}}.AsFloat;')], 'calc cycle A -> B -> A');
  Refuses('C5 a field the dataset does not have is refused', [Fld('A', 'tA', '{{A}}.AsFloat := {{NOPE}}.AsFloat;')], 'NOPE');
  CheckText('C6 a field may read and clear itself', CalcText([Fld('A', 'tA', '{{A}}.Clear; if {{A}}.IsNull then {{A}}.AsFloat := 1;')]),
    'begin // A|  tA.Clear; if tA.IsNull then tA.AsFloat := 1;|end;|');
  Refuses('C7 a broken macro is refused', [Fld('A', 'tA', '{{A.AsFloat := 1;')], '');
  Refuses('C7b TABLE.FIELD is refused', [Fld('A', 'tA', '{{A}}.AsFloat := {{T.A}}.AsFloat;')], '');
  Refuses('C8 a comment left open is refused', [Fld('A', 'tA', '{{A}}.AsFloat := 1; { x')], 'no end');
  Refuses('C9 a string left open is refused', [Fld('A', 'tA', '{{A}}.AsString := ''x;')], 'quote');
  Refuses('C10 a region marker in a body is refused', [Fld('A', 'tA', '{$ENDREGION}' + NL + '{{A}}.AsFloat := 1;')], 'directive');
  Refuses('C11 a conditional in a body is refused', [Fld('A', 'tA', '{$IFDEF X}{{A}}.AsFloat := 1;{$ENDIF}')], 'directive');
  Refuses('C12 non-ASCII text in a body is refused', [Fld('A', 'tA', '{{A}}.AsString := ''' + Char($E9) + ''';')], 'ASCII');
  CheckText('C13 a // comment as the last line does not swallow the end', CalcText([Fld('A', 'tA', '{{A}}.AsFloat := 1; // one')]),
    'begin // A|  tA.AsFloat := 1; // one|end;|');
  CheckText('C14 fields without a body give nothing', CalcText([Fld('A', 'tA'), Fld('Q', 'tQ')]), '');
  Refuses('C15 two components of one column, used in a macro: refused', [Fld('Q', 'tQ'), Fld('Q', 'tQ2'), Fld('A', 'tA', '{{A}}.AsFloat := {{Q}}.AsFloat;')], 'more than one');
  Check('C16 event code', EventRegionContent([Fld('Q', 'tQ')], 'Text := {{Q}}.AsString;', VContent, VReason));
  CheckText('C16 text', VContent.Replace(NL, '|'), 'begin|  Text := tQ.AsString;|end;|');
  Check('C17 event code with an unknown field is refused', not EventRegionContent([Fld('Q', 'tQ')], 'Text := {{Z}}.AsString;', VContent, VReason) and (VReason <> ''));
  Check('C18 OnGetText parameters', FieldEventParams('OnGetText') = 'Sender,Text,DisplayText');
  Check('C19 the other events', (FieldEventParams('OnSetText') = 'Sender,Text') and (FieldEventParams('OnValidate') = 'Sender') and (FieldEventParams('OnChange') = 'Sender') and (FieldEventParams('OnClick') = ''));
  CheckText('C20 a macro in a string is text', CalcText([Fld('QTY', 'tQ'), Fld('A', 'tA', '{{A}}.AsString := ''it''''s {{QTY}}'' + {{QTY}}.AsString;')]),
    'begin // A|  tA.AsString := ''it''''s {{QTY}}'' + tQ.AsString;|end;|');
  CheckText('C21 a macro in a comment is text', CalcText([Fld('A', 'tA', '(* {{NOPE}} *) {{A}}.AsInteger := 1; // {{NOPE}}')]),
    'begin // A|  (* {{NOPE}} *) tA.AsInteger := 1; // {{NOPE}}|end;|');
  CheckText('C22 a macro in a multi-line string is text', CalcText([Fld('A', 'tA', '{{A}}.AsString := ''''''' + NL + '  {{NOPE}}' + NL + '  '''''' + {{A}}.AsString;')]),
    'begin // A|  tA.AsString := ''''''|    {{NOPE}}|    '''''' + tA.AsString;|end;|');
  CheckText('C23 no dependency in a string or comment', Deps('{{A}} := ''{{B}}''; { {{C} // {{D', 'A'), '');
  CheckText('C23b ... a real one behind them is', Deps('{{A}} := ''{{B}}'' { x } + {{C}};', 'A'), 'C');
  Refuses('C24 Exit in a body with bodies behind it', [Fld('A', 'tA', 'if {{A}}.IsNull then Exit;'), Fld('B', 'tB', '{{B}}.AsInteger := 1;')], 'Exit');
  CheckText('C25 Exit in the last body', CalcText([Fld('A', 'tA', '{{A}}.AsInteger := 1;'), Fld('B', 'tB', 'exit;')]), 'begin // A|  tA.AsInteger := 1;|end;|begin // B|  exit;|end;|');
  CheckText('C26 a member named Exit, and the word in a string', CalcText([Fld('A', 'tA', '{{A}}.AsInteger := x.Exit; s := ''Exit'';'), Fld('B', 'tB', 'b;')]),
    'begin // A|  tA.AsInteger := x.Exit; s := ''Exit'';|end;|begin // B|  b;|end;|');
  CheckText('C27 a lone CR ends a line', CalcText([Fld('A', 'tA', '// one' + #13 + '{{A}}.AsInteger := 1;')]), 'begin // A|  // one|  tA.AsInteger := 1;|end;|');
end;
{ ---- handlers ---- }

const
  CALC_A = 'begin // A' + NL + '  tA.AsFloat := 1;' + NL + 'end;' + NL;

function FormUnit(const pBody: string; const pAfter: string = ''): string;
begin
  Result := L(['unit u1;', '', 'interface', '', 'type', '  TfrmA = class(TForm)', '    procedure tblACalcFields(DataSet: TDataSet);', '  end;', '', 'implementation', '']) +
    'procedure TfrmA.tblACalcFields(DataSet: TDataSet);' + NL + pBody + NL + pAfter + 'end.' + NL;
end;

function Job(const pContent: string = CALC_A): TFrhJob;
begin
  Result.RegionId := REGION_ID;
  Result.Method := 'TfrmA.tblACalcFields';
  Result.StdParams := ['DataSet'];
  Result.Content := pContent;
end;

function Indented(const pContent: string): string;
begin
  Result := '  ' + pContent.TrimRight.Replace(NL, NL + '  ') + NL;
end;

var
  GNotes: string; // of the last Apply

function Apply(const pText: string; const pJob: TFrhJob; out pState: TFrhState; out pReason: string): string;
var
  VItem: TFrhItem;
begin
  Result := ApplyHandlerJob(pText, 'u1.pas', pJob, VItem);
  GNotes := string.Join('|', VItem.Notes);
  pState := VItem.State;
  pReason := VItem.Reason;
end;

procedure TestHandlers;
var
  VState: TFrhState;
  VReason, VOut, VIn, VRegion, VEdited: string;
  VJob: TFrhJob;

  procedure Inserted(const pName, pText, pWant: string);
  begin
    VOut := Apply(pText, Job, VState, VReason);
    Check(pName + ' state', VState = fhsInserted, VReason);
    CheckText(pName, VOut, pWant);
    CheckText(pName + ', second run', Apply(pWant, Job, VState, VReason), pWant);
    Check(pName + ', second run state', VState = fhsUnchanged, VReason);
  end;

  procedure Refused(const pName, pText: string; const pJob: TFrhJob; const pReason: string);
  begin
    VOut := Apply(pText, pJob, VState, VReason);
    Check(pName, (VState = fhsRefused) and (VOut = pText) and (VReason <> '') and ((pReason = '') or ContainsText(VReason, pReason)), VReason);
  end;

begin
  VRegion := RenderDlfrRegion(REGION_ID, Indented(CALC_A), '  ', NL);
  Inserted('H1 an empty handler', FormUnit(L(['begin', 'end;'])), FormUnit(L(['begin']) + VRegion + L(['end;'])));
  Inserted('H2 at the END of a handler', FormUnit(L(['begin', '  x := 1;', '  if y then begin', '    z;', '  end;', 'end;'])),
    FormUnit(L(['begin', '  x := 1;', '  if y then begin', '    z;', '  end;']) + VRegion + L(['end;'])));
  Inserted('H3 one line', FormUnit('begin x := 1; end;' + NL), FormUnit('begin x := 1; ' + NL + VRegion + 'end;' + NL));
  Inserted('H4 a comment before the end', FormUnit(L(['begin', '  x; // end;', '  { end;', '  }', 'end;'])),
    FormUnit(L(['begin', '  x; // end;', '  { end;', '  }']) + VRegion + L(['end;'])));
  Inserted('H5 a comment that ends on the line of the end', FormUnit(L(['begin', '  x; { a', '  b } end;'])),
    FormUnit(L(['begin', '  x; { a']) + '  b } ' + NL + RenderDlfrRegion(REGION_ID, Indented(Indented(CALC_A)), '    ', NL) + L(['end;'])));
  Inserted('H6 the last statement has no semicolon', FormUnit(L(['begin', '  x := ''a''', 'end;'])),
    FormUnit(L(['begin', '  x := ''a''']) + RenderDlfrRegion(REGION_ID, '  ;' + NL + Indented(CALC_A), '  ', NL) + L(['end;'])));
  VIn := FormUnit(L(['var', '  i: Integer;', '  procedure Nested;', '  begin', '  end;', 'begin', '  Nested;', 'end;']));
  Inserted('H7 a nested procedure', VIn, VIn.Replace('  Nested;' + NL + 'end;', '  Nested;' + NL + VRegion + 'end;'));
  VIn := FormUnit(L(['begin', 'end;']), L(['procedure TfrmA.Other;', 'begin', '  x;', 'end;']));
  Inserted('H8 another method after it stays', VIn, FormUnit(L(['begin']) + VRegion + L(['end;']), L(['procedure TfrmA.Other;', 'begin', '  x;', 'end;'])));
  VIn := FormUnit(L(['begin', 'end;'])).Replace(#13, '');
  VOut := Apply(VIn, Job, VState, VReason);
  Check('H9 an LF unit gets LF lines', (VState = fhsInserted) and not VOut.Contains(#13), VReason);
  VIn := FormUnit(L(['begin', 'end;'])).Replace('implementation' + NL,
    'implementation' + NL + '(*' + NL + 'procedure TfrmA.tblACalcFields(DataSet: TDataSet);' + NL + 'begin' + NL + VRegion + 'end;' + NL + '*)' + NL);
  VOut := Apply(VIn, Job, VState, VReason);
  Check('H10 a commented-out copy of the handler with its region is not touched',
    (VState = fhsInserted) and (VOut = VIn.Replace('procedure TfrmA.tblACalcFields(DataSet: TDataSet);' + NL + 'begin' + NL + 'end;',
    'procedure TfrmA.tblACalcFields(DataSet: TDataSet);' + NL + 'begin' + NL + VRegion + 'end;')), VReason);
  VIn := FormUnit(L(['const', '  OLD = ''''''']) + VRegion + L(['  '''''';', 'begin', '  s := OLD;', 'end;']));
  VOut := Apply(VIn, Job, VState, VReason);
  Check('H11 a string copy of the region is not touched', (VState = fhsInserted) and (VOut = VIn.Replace('  s := OLD;' + NL, '  s := OLD;' + NL + VRegion)), VReason);

  VIn := FormUnit(L(['begin', '  a;']) + VRegion + L(['  tA.AsFloat := 0;', 'end;']));
  CheckText('H12 same content: nothing to write', Apply(VIn, Job, VState, VReason), VIn);
  Check('H12 state', VState = fhsUnchanged, VReason);
  VOut := Apply(VIn, Job(CALC_A.Replace('1', '2')), VState, VReason);
  CheckText('H13 new content: the region only; code before and after it survives', VOut,
    FormUnit(L(['begin', '  a;']) + RenderDlfrRegion(REGION_ID, Indented(CALC_A.Replace('1', '2')), '  ', NL) +
    L(['  tA.AsFloat := 0;', 'end;'])));
  Check('H13 state', VState = fhsUpdated, VReason);
  VEdited := VIn.Replace('tA.AsFloat := 1;', 'tA.AsFloat := 5;');
  Refused('H14 a hand-edited region is never overwritten', VEdited, Job(CALC_A.Replace('1', '2')), 'hand-edited');
  Refused('H15 ... also when the repository wants what is there now', VEdited, Job(CALC_A.Replace('1', '5')), 'hand-edited');
  Refused('H16 the region in another method', FormUnit(L(['begin', 'end;']), L(['procedure TfrmA.Other;', 'begin']) + VRegion + L(['end;'])), Job, 'not inside');
  Refused('H17 no such handler', FormUnit(L(['begin', 'end;'])).Replace('procedure TfrmA.tblACalcFields', 'procedure TfrmA.Else1'), Job, 'is not in the unit');
  Refused('H18 the handler twice', FormUnit(L(['begin', 'end;']), L(['procedure TfrmA.tblACalcFields(DataSet: TDataSet);', 'begin', 'end;'])), Job, 'more than once');
  Refused('H19 the handler inside {$IFDEF}', FormUnit(L(['begin', 'end;'])).Replace('procedure TfrmA', '{$IFDEF X}' + NL + 'procedure TfrmA').Replace(NL + 'end.', NL + '{$ENDIF}' + NL + 'end.'), Job, 'conditional');
  Refused('H20 an asm body', FormUnit(L(['asm', '  nop', 'end;'])), Job, 'has no begin');
  Refused('H21 content that leaves the handler', FormUnit(L(['begin', 'end;'])), Job(L(['end;', 'procedure P;', 'begin'])), 'does not stay inside');
  Refused('H22 content that does not parse', FormUnit(L(['begin', 'end;'])), Job(L(['x := := 1;'])), 'does not parse');
  Refused('H23 another parameter name than the content uses', FormUnit(L(['begin', 'end;'])).Replace('(DataSet:', '(ADs:'), Job(L(['DataSet.Tag := 1;'])), 'DataSet');
  VOut := Apply(FormUnit(L(['begin', 'end;'])).Replace('(DataSet:', '(ADs:'), Job, VState, VReason);
  Check('H24 another parameter name the content does not use', VState = fhsInserted, VReason);
  Refused('H25 nothing to generate, a region is there: reported, left', VIn, Job(''), 'nothing');
  VOut := Apply(FormUnit(L(['begin', 'end;'])), Job(''), VState, VReason);
  Check('H26 nothing to generate, no region', (VState = fhsUnchanged) and (VOut = FormUnit(L(['begin', 'end;']))), VReason);
  Refused('H27 the insertion point is conditional', FormUnit(L(['begin', '{$IFDEF X}', '  a;', 'end;', '{$ELSE}', 'end;', '{$ENDIF}'])), Job, 'inside a conditional');
  Refused('H28 non-ASCII unit text', FormUnit(L(['begin', '  s := ''' + Char($E9) + ''';', 'end;'])), Job, 'ASCII');
  Refused('H29 the end marker is commented out', VIn.Replace('  {$ENDREGION ''DLFR tblA.OnCalcFields''}', '  // {$ENDREGION ''DLFR tblA.OnCalcFields''}'), Job, 'region without an end marker');
  VIn := FormUnit(L(['begin', '  a;', '  tA.AsFloat := 1; // one', '  if b then', '    tB.AsFloat := 2;', '  {$IFDEF X}', '  tC.AsFloat := 3;', '  {$ENDIF}', '  // tD.AsFloat := 4;', 'end;']));
  Check('H31 the handler holds the code by hand', HandlerHoldsCode(VIn, 'u1.pas', Job, 'tA.AsFloat  := 1;'));
  Check('H32 ... over several statements', HandlerHoldsCode(VIn, 'u1.pas', Job, 'a;' + NL + 'tA.AsFloat := 1'));
  Check('H33 ... not inside another statement', not HandlerHoldsCode(VIn, 'u1.pas', Job, 'tB.AsFloat := 2;'));
  Check('H34 ... not inside a conditional', not HandlerHoldsCode(VIn, 'u1.pas', Job, 'tC.AsFloat := 3;'));
  Check('H35 ... not in a comment', not HandlerHoldsCode(VIn, 'u1.pas', Job, 'tD.AsFloat := 4;'));
  Check('H36 ... not in the region itself', not HandlerHoldsCode(FormUnit(L(['begin', '  a;']) + VRegion + L(['end;'])), 'u1.pas', Job, 'begin tA.AsFloat := 1; end;'));
  Check('H37 ... another string', not HandlerHoldsCode(FormUnit(L(['begin', '  s := ''a'';', 'end;'])), 'u1.pas', Job, 's := ''b'';'));
  Check('H38 ... the same string', HandlerHoldsCode(FormUnit(L(['begin', '  s := ''a'';', 'end;'])), 'u1.pas', Job, 's := ''a'';'));
  Check('H39 ... not a string that differs in blanks only', not HandlerHoldsCode(FormUnit(L(['begin', '  s := ''a  b'';', 'end;'])), 'u1.pas', Job, 's := ''a b'';'));
  VIn := FormUnit(L(['begin', '  a;']) + Indented(CALC_A) + L(['end;']));
  Check('H40 the region without its markers is the same code by hand', HandlerHoldsCode(VIn, 'u1.pas', Job, 'tA.AsFloat := 1;'));
  Check('H40b ... not when it was edited', not HandlerHoldsCode(VIn.Replace(':= 1', ':= 5'), 'u1.pas', Job, 'tA.AsFloat := 1;'));
  VJob := Job;
  VJob.Assigns := ['tA'];
  Refused('H41 an edited block without its markers, calc', VIn.Replace(':= 1', ':= 5'), VJob, 'markers');
  Refused('H41b ... event', VIn.Replace(':= 1', ':= 5'), Job, 'markers');
  VOut := Apply(VIn.Replace('tA', 'tZ').Replace('// A', '// Z'), VJob, VState, VReason);
  Check('H41c a block of another field is hand code', VState = fhsInserted, VReason);
  VOut := Apply(FormUnit(L(['begin', '  if b then', '  begin', '    tA.AsFloat := 5;', '  end;', 'end;'])), VJob, VState, VReason);
  Check('H41d a block of a statement is hand code, noted', (VState = fhsInserted) and ContainsText(GNotes, 'assigns tA'), VReason + GNotes);
  VIn := FormUnit(L(['begin', '{$IFDEF X}', '  a;', '{$ELSE}', '  begin // A', '    tA.AsFloat := 5;', '  end;', '{$ENDIF}', 'end;']));
  Refused('H41e ... in the else branch of a conditional, calc', VIn, VJob, 'markers');
  Refused('H41f ... event', VIn, Job, 'markers');
  VOut := Apply(VIn.Replace('tA', 'tZ').Replace('// A', '// Z'), VJob, VState, VReason);
  Check('H41g ... of another field: hand code', VState = fhsInserted, VReason);
  VJob := Job('begin' + NL + '  if b then Exit;' + NL + 'end;' + NL);
  VOut := Apply(FormUnit(L(['begin', 'end;'])), VJob, VState, VReason);
  Check('H42 Exit in the region, nothing behind it: no note', (VState = fhsInserted) and (GNotes = ''), GNotes);
  VOut := Apply(VOut.Replace('OnCalcFields''}' + NL + 'end;', 'OnCalcFields''}' + NL + '  ; c;' + NL + 'end;'), VJob, VState, VReason);
  Check('H42b ... hand code behind it: noted', (VState = fhsUnchanged) and ContainsText(GNotes, 'behind'), VReason + GNotes);
  VOut := Apply(FormUnit(L(['begin', '{$IFDEF X}', '  a', '{$ELSE}', '  b;', '{$ENDIF}', 'end;'])), Job, VState, VReason);
  Check('H43 the last statement is conditional: a semicolon comes first', (VState = fhsInserted) and VOut.Contains('''}' + NL + '  ;' + NL + '  begin // A'), VReason);
  VJob := Job;
  VJob.Components := ['tA'];
  Refused('H44 a local variable hides the component', FormUnit(L(['var', '  n, tA, k: Integer;', 'begin', 'end;'])), VJob, 'local name');
  Refused('H45 ... a parameter', FormUnit(L(['begin', 'end;'])).Replace('(DataSet: TDataSet)', '(DataSet: TDataSet; tA: Integer)'), VJob, 'local name');
  Refused('H46 ... an inline variable', FormUnit(L(['begin', '  var k, tA: Integer;', 'end;'])), VJob, 'local name');
  VOut := Apply(FormUnit(L(['var', '  tAB: Integer;', '  procedure N;', '  begin', '    tA.Tag := 1;', '    if x then tA := nil;', '  end;', 'begin', 'end;'])), VJob, VState, VReason);
  Check('H47 ... not a use of it', VState = fhsInserted, VReason);
  VJob.Content := 'begin' + NL + '  var tA := 1;' + NL + 'end;' + NL;
  Refused('H48 ... a name of the content itself', FormUnit(L(['begin', 'end;'])), VJob, 'local name');
  Refused('H30 the region only in a comment, its end marker real', FormUnit(L(['begin']) + '//' + VRegion + L(['end;'])), Job, 'end marker without a region');
end;

{ ---- MAXLEN ---- }

function IUnit(const pAfterEnd: string; const pMarker: string = 'DB-RAD'): string;
begin
  Result := L(['unit iORD;', 'interface', 'type', '  ImcORD = interface', '{$REGION ''' + pMarker + ' 2''}', '    function GetA: string;', '{$ENDREGION ''' + pMarker + ' 2''}', '  end;']) + pAfterEnd;
end;

procedure TestMaxLen;
var
  VItem: TFrhItem;
  VIn, VOut, VRegion: string;

  function Put(const pText: string; const pCols: TArray<TFrhLength>): string;
  begin
    Result := ApplyMaxLen(pText, 'ORD', pCols, VItem);
  end;

  function Len(const pColumn: string; pLength: Integer): TFrhLength;
  begin
    Result.Column := pColumn;
    Result.Length := pLength;
  end;

begin
  VRegion := RenderDlfrRegion('2a', L(['const', '  /// <summary>Declared length of ORD.A in characters.</summary>', '  ORD_A_MAXLEN = 10;']), '', NL);
  VIn := IUnit(L(['', 'implementation', 'end.']));
  VOut := Put(VIn, [Len('A', 10)]);
  CheckText('M1 after the interface type', VOut, IUnit(VRegion + L(['', 'implementation', 'end.'])));
  Check('M1 state', VItem.State = fhsInserted, VItem.Reason);
  CheckText('M2 second run', Put(VOut, [Len('A', 10)]), VOut);
  Check('M2 state', VItem.State = fhsUnchanged, VItem.Reason);
  CheckText('M3 a length changed', Put(VOut, [Len('A', 12)]), VOut.Replace(VRegion, RenderDlfrRegion('2a',
    L(['const', '  /// <summary>Declared length of ORD.A in characters.</summary>', '  ORD_A_MAXLEN = 12;']), '', NL)));
  VIn := VOut.Replace('= 10', '= 11');
  Check('M4 a hand-edited region is never overwritten', (Put(VIn, [Len('A', 12)]) = VIn) and
    (VItem.State = fhsRefused) and ContainsText(VItem.Reason, 'hand-edited'), VItem.Reason);
  Check('M5 a renumbered unit', Put(IUnit(L(['', 'implementation', 'end.']), 'DLFR'), [Len('A', 10)]).Contains(VRegion), VItem.Reason);
  VIn := IUnit(L(['const', '  ORD_A_MAXLEN = 9;', 'implementation', 'end.']));
  VOut := Put(VIn, [Len('A', 10)]);
  Check('M6 a hand-kept constant is not declared again, the difference is noted', (VOut = VIn) and (Length(VItem.Notes) = 1) and ContainsText(VItem.Notes[0], '9'), VItem.Reason);
  VOut := Put(VIn, [Len('A', 10), Len('B', 5)]);
  Check('M7 ... the others are generated', VOut.Contains('ORD_B_MAXLEN = 5;') and not VOut.Contains('ORD_A_MAXLEN = 10'));
  VIn := IUnit(L(['// ORD_A_MAXLEN = 9;', 'implementation', 'end.']));
  Check('M8 a commented-out constant is none', Put(VIn, [Len('A', 10)]).Contains('ORD_A_MAXLEN = 10;'));
  VIn := IUnit(L(['  TOther = class end;', 'implementation', 'end.']));
  Check('M9 another type follows in the same section: refused', (Put(VIn, [Len('A', 10)]) = VIn) and (VItem.State = fhsRefused), VItem.Reason);
  VIn := L(['unit iORD;', 'interface', '// {$REGION ''DB-RAD 2''}', '// {$ENDREGION ''DB-RAD 2''}', '// end;', 'implementation', 'end.']);
  Check('M10 section 2 only in comments: refused', (Put(VIn, [Len('A', 10)]) = VIn) and (VItem.State = fhsRefused), VItem.Reason);
  VIn := IUnit(L(['implementation', 'end.']));
  Check('M11 no string column: nothing', (Put(VIn, []) = VIn) and (VItem.State = fhsUnchanged));
  VIn := IUnit(L(['', 'implementation', 'end.'])).Replace('  end;' + NL, '  end; { a' + NL + ' b }' + NL);
  Check('M12 a comment that starts behind the end: refused', (Put(VIn, [Len('A', 10)]) = VIn) and (VItem.State = fhsRefused), VItem.Reason);
  Check('M13 a name with $', Put(IUnit(L(['', 'implementation', 'end.'])), [Len('F$X', 10)]).Contains('ORD_F_X_MAXLEN = 10;'));
  VIn := IUnit(L(['', 'implementation', 'end.'])).Replace('type' + NL, '{$IFDEF X}' + NL + 'type' + NL).Replace('  end;' + NL, '  end;' + NL + '{$ENDIF}' + NL);
  Check('M14 section 2 inside {$IFDEF}: refused', (Put(VIn, [Len('A', 10)]) = VIn) and (VItem.State = fhsRefused), VItem.Reason);
  VIn := IUnit(L(['', 'implementation', 'function B(N: Integer): Boolean;', 'begin', '  Result := ORD_A_MAXLEN = 9;', 'end;', 'end.']));
  Check('M16 a comparison is no constant', Put(VIn, [Len('A', 10)]).Contains('ORD_A_MAXLEN = 10;') and (Length(VItem.Notes) = 0), VItem.Reason);
  VIn := L(['unit iORD;', 'interface', 'type', '  TX = class', '  const', '    ORD_A_MAXLEN = 9;', '  end;', '  ImcORD = interface', '{$REGION ''DB-RAD 2''}', '{$ENDREGION ''DB-RAD 2''}', '  end;', 'implementation', 'end.']);
  Check('M17 a class constant is another name', Put(VIn, [Len('A', 10)]).Contains(NL + '  ORD_A_MAXLEN = 10;') and (Length(VItem.Notes) = 0), VItem.Reason);
  VIn := IUnit(L(['', 'implementation', '{$IFDEF X}', 'const', '  ORD_A_MAXLEN = 10;', '{$ENDIF}', 'end.']));
  Check('M18 a constant inside a conditional: left out and noted', (Put(VIn, [Len('A', 10)]) = VIn) and (Length(VItem.Notes) = 1) and ContainsText(VItem.Notes[0], 'conditional'), VItem.Reason);
  VIn := L(['unit iORD;', 'interface', 'type', '  TORD = class', '  type', '    TR = record', '{$REGION ''DB-RAD 2''}', '    A: Integer;', '{$ENDREGION ''DB-RAD 2''}', '    end;', '    procedure P;', '  end;', 'implementation', 'end.']);
  Check('M19 the constants would go into a class: refused', (Put(VIn, [Len('A', 10)]) = VIn) and (VItem.State = fhsRefused) and (VItem.Reason <> ''), VItem.Reason);
  VIn := IUnit(L(['', 'implementation', 'procedure X; begin := end;', 'end.']));
  Check('M20 a unit that does not parse: refused', (Put(VIn, [Len('A', 10)]) = VIn) and (VItem.State = fhsRefused) and ContainsText(VItem.Reason, 'parse'), VItem.Reason);
  VIn := IUnit(L(['', 'implementation', 'end.'])).Replace('{$REGION', '{$IFDEF X}' + NL + '{$REGION').Replace('  end;' + NL, '{$ENDIF}' + NL + '  end;' + NL);
  Check('M15 only section 2 inside {$IFDEF}: refused', (Put(VIn, [Len('A', 10)]) = VIn) and (VItem.State = fhsRefused), VItem.Reason);
end;

{ ---- ASCII ---- }

function SaveError(const pFile, pOld, pNew: string): string;
begin
  Result := '';
  try
    if not SaveAsciiUnit(pFile, pOld, pNew) then
      Result := 'not written';
  except
    on E: EDlfrError do
      Result := 'EDlfrError ' + E.Message;
    on E: Exception do
      Result := E.ClassName + ' ' + E.Message;
  end;
end;

procedure TestSave;
var
  VDir, VFile: string;
begin
  VDir := TPath.Combine(TPath.GetTempPath, 'dl-handlers-' + TPath.GetRandomFileName);
  TDirectory.CreateDirectory(VDir);
  try
    VFile := TPath.Combine(VDir, 'u1.pas');
    TFile.WriteAllText(VFile, 'old', TEncoding.ASCII);
    CheckText('W1 the same text is not written', SaveError(VFile, 'old', 'old'), 'not written');
    CheckText('W2 written', SaveError(VFile, 'old', 'new') + TFile.ReadAllText(VFile), 'new');
    Check('W3 the file changed meanwhile: EDlfrError, kept', SaveError(VFile, 'old', 'x').StartsWith('EDlfrError the file changed') and (TFile.ReadAllText(VFile) = 'new'));
    Check('W4 new text that is not ASCII: EDlfrError, kept', SaveError(VFile, 'new', Char($E9)).StartsWith('EDlfrError the new text') and (TFile.ReadAllText(VFile) = 'new'));
    CheckText('W2b the name on disk keeps its letter case', SaveError(VFile.ToUpper, 'new', 'new2') + SaveError(VFile, 'new2', 'new') + ExtractFileName(TDirectory.GetFiles(VDir)[0]), 'u1.pas');
    SaveError(VFile.ToUpper, 'new', 'new2');
    CheckText('W2c', ExtractFileName(TDirectory.GetFiles(VDir)[0]), 'u1.pas');
    SaveError(VFile.ToUpper, 'new2', 'new');
    TFile.SetAttributes(VFile, [TFileAttribute.faReadOnly]);
    Check('W5 a read-only unit: EDlfrError, kept', SaveError(VFile, 'new', 'x').StartsWith('EDlfrError cannot replace') and (TFile.ReadAllText(VFile) = 'new'));
    TFile.SetAttributes(VFile, [TFileAttribute.faNormal]);
    Check('W6 no temporary file is left', Length(TDirectory.GetFiles(VDir)) = 1);
    TDirectory.CreateDirectory(VFile + '.dlfr-tmp');
    Check('W7 the temporary file cannot be written: EDlfrError, kept', SaveError(VFile, 'new', 'x').StartsWith('EDlfrError cannot write') and (TFile.ReadAllText(VFile) = 'new'), SaveError(VFile, 'new', 'x'));
  finally
    TDirectory.Delete(VDir, True);
  end;
end;

procedure TestMissingGridEvents;
var
  VRow: TArray<string>;
  VMissing: TArray<string>;
begin
  VRow := ['x', '', '', '', 'AText := ''a'';', 'ADone := True;'];
  VMissing := MissingGridEvents(VRow, []);
  Check('M1 both grid events missing, TField events never listed', (Length(VMissing) = 2) and (VMissing[0] = 'OnGetDisplayText') and (VMissing[1] = 'OnCustomDrawCell'));
  VMissing := MissingGridEvents(VRow, ['onGetDisplayText']);
  Check('M2 an assigned event (any case) is not missing', (Length(VMissing) = 1) and (VMissing[0] = 'OnCustomDrawCell'));
  Check('M3 both assigned: nothing missing', Length(MissingGridEvents(VRow, ['OnGetDisplayText', 'OnCustomDrawCell'])) = 0);
  VRow := ['', '', '', '', '   ', ''];
  Check('M4 a blank stored body is not code: nothing missing', Length(MissingGridEvents(VRow, [])) = 0);
  Check('M5 a short or empty row is safe', (Length(MissingGridEvents([], [])) = 0) and (Length(MissingGridEvents(['a', 'b'], [])) = 0));
  Check('M6 TField event bodies alone list nothing', Length(MissingGridEvents(['a', 'b', 'c', 'd', '', ''], [])) = 0);
end;

procedure TestAscii;
begin
  Check('A1 ASCII', FirstNonAscii([65, 13, 10]) = -1);
  Check('A2 a byte above 127', FirstNonAscii([65, $E9]) = 1);
  Check('A3 a BOM is not ASCII', FirstNonAscii([$EF, $BB, $BF, 65]) = 0);
end;

procedure Run(const pTests: array of TProc);
var
  VTest: TProc;
begin
  for VTest in pTests do
    try
      VTest();
    except
      on E: Exception do
        Check('no exception', False, E.ClassName + ': ' + E.Message);
    end;
end;

begin
  Run([TestScan, TestRegions, TestRenumber, TestCalc, TestHandlers, TestMaxLen, TestMissingGridEvents, TestAscii, TestSave]);
  Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    Halt(1);
end.
