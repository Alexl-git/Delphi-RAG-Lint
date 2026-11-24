program DfmWriteTests;

{ Self-contained console test runner (no DUnitX) for the byte-level editors of lane TT-DFMWRITE (drag-lint 1.54):
  TDfmDocument, TDfmUnitDocument, ApplyDfmWrite on files (backup, undo), the RTL-made literals and the field class of a repository row. One PASS/FAIL line per
  case, a summary line, exit code 1 on any failure. The CLI (repository, the compiled form) is
  run_fieldrepo_dfmwrite.ps1. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  DRagLint.FieldRepo.ChangeSet in '..\..\src\sql\DRagLint.FieldRepo.ChangeSet.pas',
  DRagLint.FieldRepo.Kinds in '..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.DfmRead in '..\..\src\sql\DRagLint.FieldRepo.DfmRead.pas',
  DRagLint.FieldRepo.DfmWrite in '..\..\src\sql\DRagLint.FieldRepo.DfmWrite.pas',
  DRagLint.FieldRepo.DfmWritePlan in '..\..\src\sql\DRagLint.FieldRepo.DfmWritePlan.pas';

const
  NL = #13#10;
  FB_INTEGER = 8;
  FB_INT64 = 16;
  FB_VARCHAR = 37;
  FB_BLOB = 261;
  FB_UNKNOWN = 999;
  TWO_DECIMALS = -2;
  SIX_DECIMALS = -6;
  NEAR_LINE_LENGTH = 63; // one less than the RTL's line of a string
  LONG_REST = 80;
  QUOTE_CASES = 3;
  LITERAL_LEAD = 3;
  FORM_OBJECTS = 5;
  FORM_TA = 2;
  ORDER: array[0..2] of string = ('DisplayLabel', 'FieldName', 'Visible');
  FORM = 'object F: TF' + NL +
    '  Caption = ''It''''s "end" ''#39''x'' +' + NL +
    '    '' end''' + NL +
    '  object T: TFDQuery' + NL +
    '    SQL.Strings = (' + NL +
    '      ''SELECT 1''' + NL +
    '      ''end'')' + NL +
    '    Items = <' + NL +
    '      item' + NL +
    '        Ref = TA' + NL +
    '        Sub = <' + NL +
    '          item' + NL +
    '            A = ''>''' + NL +
    '          end>' + NL +
    '      end>' + NL +
    '    Data = {' + NL +
    '      00FF}' + NL +
    '    Style = [fsBold, fsItalic]' + NL +
    '    Left = -11' + NL +
    '    object TA: TIntegerField' + NL +
    '      FieldName = ''A''' + NL +
    '    end' + NL +
    '    object TB: TIntegerField' + NL +
    '      DisplayLabel = ''Old''' + NL +
    '      FieldName = ''B''   ' + NL +
    '      Visible = False' + NL +
    '    end' + NL +
    '    object Other: TThing' + NL +
    '    end' + NL +
    '  end' + NL +
    'end' + NL;

type
  TEditProc = reference to procedure(pDoc: TDfmDocument);
  TUnitProc = reference to procedure(pUnit: TDfmUnitDocument);

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
  Check(pName, pGot = pWant, 'got <' + pGot.Replace(#13, '\r').Replace(#10, '\n') + '> want <'
    + pWant.Replace(#13, '\r').Replace(#10, '\n') + '>');
end;

{ One character per byte both ways, so a test sees every byte. }
function ToBytes(const pText: string): TBytes;
var
  VI: Integer;
begin
  SetLength(Result, Length(pText));
  for VI := 1 to Length(pText) do
    Result[VI - 1] := Byte(Ord(pText[VI]));
end;

function ToText(const pBytes: TBytes): string;
var
  VI: Integer;
begin
  SetLength(Result, Length(pBytes));
  for VI := 0 to High(pBytes) do
    Result[VI + 1] := Char(pBytes[VI]);
end;

function Edited(const pText: string; const pProc: TEditProc): string;
var
  VDoc: TDfmDocument;
begin
  try
    VDoc := TDfmDocument.Create(ToBytes(pText), 'f.dfm');
    try
      pProc(VDoc);
      Result := ToText(VDoc.Output);
      DfmTextToBinary(ToBytes(Result));
    finally
      VDoc.Free;
    end;
  except
    on E: EDfmWriteError do
      Result := '!' + E.Message;
  end;
end;

function EditedUnit(const pText: string; const pProc: TUnitProc): string;
var
  VUnit: TDfmUnitDocument;
begin
  try
    VUnit := TDfmUnitDocument.Create(ToBytes(pText), 'u.pas');
    try
      pProc(VUnit);
      Result := ToText(VUnit.Output);
    finally
      VUnit.Free;
    end;
  except
    on E: EDfmWriteError do
      Result := '!' + E.Message;
  end;
end;

{ Reads a text: a callback that did not run is a failure, not a skipped test. }
procedure Inspect(const pName, pText: string; const pProc: TEditProc);
var
  VGot: string;
begin
  VGot := Edited(pText, pProc);
  Check(pName + ' ran', not VGot.StartsWith('!'), VGot);
end;

procedure InspectUnit(const pName, pText: string; const pProc: TUnitProc);
var
  VGot: string;
begin
  VGot := EditedUnit(pText, pProc);
  Check(pName + ' ran', not VGot.StartsWith('!'), VGot);
end;

function SetOn(const pText, pComp, pProp, pLiteral: string): string;
begin
  Result := Edited(pText,
    procedure(pDoc: TDfmDocument)
    begin
      pDoc.SetProp(pDoc.FindObject(pComp, 'T'), pProp, pLiteral, [ORDER[0], ORDER[1], ORDER[2]]);
    end);
end;

{ ---- literals ---- }

procedure TestLiterals;
var
  VLong, VText: string;
  VI: Integer;
begin
  CheckText('L1 plain', DfmStringLiteral('abc'), ' ''abc''');
  CheckText('L2 quote and non-ASCII are #nnn', DfmStringLiteral('It''s '#233), ' ''It''#39''s ''#233');
  CheckText('L3 empty', DfmStringLiteral(''), ' ''''');
  CheckText('L4 the word end', DfmStringLiteral('the end'), ' ''the end''');
  VLong := StringOfChar('x', NEAR_LINE_LENGTH) + '''' + StringOfChar('y', LONG_REST);
  VText := DfmStringLiteral(VLong);
  Check('L5 a long string is continued on lines of at most 64 characters', VText.Contains(' +' + NL + '    ''') and (VText.IndexOf(NL) < LITERAL_LEAD), VText);
  { every literal reads back through the RTL and through TryProp }
  VText := SetOn(FORM, 'TB', 'DisplayLabel', VText);
  Check('L6 a long label is written', VText.Contains('DisplayLabel = ' + NL + '        ''xxx'), VText);
  Inspect('L7', VText,
    procedure(pDoc: TDfmDocument)
    var
      VGot: string;
    begin
      pDoc.TryProp(pDoc.FindObject('TB', 'T'), 'displaylabel', VGot);
      CheckText('L7 and reads back', VGot, VLong);
    end);
  for VI := 1 to QUOTE_CASES do
  begin
    VLong := StringOfChar('''', VI) + 'a' + StringOfChar('''', VI - 1);
    VText := SetOn(FORM, 'TB', 'DisplayLabel', '''' + VLong.Replace('''', '''''') + '''');
    Inspect('L8', VText,
      procedure(pDoc: TDfmDocument)
      var
        VGot: string;
      begin
        pDoc.TryProp(pDoc.FindObject('TB', 'T'), 'DisplayLabel', VGot);
        CheckText('L8 doubled quotes decode ' + IntToStr(VI), VGot, VLong);
      end);
  end;
end;

{ ---- DFM ---- }

procedure TestDfmEdits;
begin
  CheckText('D1 no edit = the same bytes', Edited(FORM, procedure(pDoc: TDfmDocument) begin end), FORM);
  CheckText('D2 replace a value: the rest is byte for byte', SetOn(FORM, 'TB', 'DisplayLabel', DfmStringLiteral('New')),
    FORM.Replace('''Old''', '''New'''));
  CheckText('D3 add a property in streaming order', SetOn(FORM, 'TA', 'DisplayLabel', DfmStringLiteral('New')),
    FORM.Replace('TIntegerField' + NL + '      FieldName = ''A''', 'TIntegerField' + NL + '      DisplayLabel = ''New''' + NL + '      FieldName = ''A'''));
  CheckText('D4 add a property after the others', SetOn(FORM, 'TA', 'Zzz', 'True'),
    FORM.Replace('''A''' + NL, '''A''' + NL + '      Zzz = True' + NL));
  CheckText('D5 remove a property', Edited(FORM,
    procedure(pDoc: TDfmDocument)
    begin
      pDoc.RemoveProp(pDoc.FindObject('TB', 'T'), 'Visible');
      pDoc.RemoveProp(pDoc.FindObject('TB', 'T'), 'NotThere');
    end), FORM.Replace('      Visible = False' + NL, ''));
  CheckText('D6 remove a property and add one at the same place', Edited(FORM,
    procedure(pDoc: TDfmDocument)
    begin
      pDoc.RemoveProp(pDoc.FindObject('TB', 'T'), 'Visible');
      pDoc.SetProp(pDoc.FindObject('TB', 'T'), 'Zzz', 'True', [ORDER[0], ORDER[1], ORDER[2]]);
    end), FORM.Replace('      Visible = False' + NL, '      Zzz = True' + NL));
  CheckText('D7 add a child after the last named sibling', Edited(FORM,
    procedure(pDoc: TDfmDocument)
    begin
      pDoc.InsertChild(pDoc.FindObject('T', ''), ['object TC: TX', '  P = 1', 'end'], ['TA', 'TB']);
    end), FORM.Replace('    object Other', '    object TC: TX' + NL + '      P = 1' + NL + '    end' + NL + '    object Other'));
  CheckText('D8 add a child before the first one', Edited(FORM,
    procedure(pDoc: TDfmDocument)
    begin
      pDoc.InsertChild(pDoc.FindObject('T', ''), ['object TC: TX', 'end'], []);
    end), FORM.Replace('    object TA', '    object TC: TX' + NL + '    end' + NL + '    object TA'));
  CheckText('D9 add a child to an object without children', Edited(FORM,
    procedure(pDoc: TDfmDocument)
    begin
      pDoc.InsertChild(pDoc.FindObject('Other', ''), ['object TC: TX', 'end'], []);
    end), FORM.Replace('TThing' + NL, 'TThing' + NL + '      object TC: TX' + NL + '      end' + NL));
  CheckText('D10 remove an object and add one in its place', Edited(FORM,
    procedure(pDoc: TDfmDocument)
    begin
      pDoc.RemoveObject(pDoc.FindObject('TA', 'T'));
      pDoc.InsertChild(pDoc.FindObject('T', ''), ['object TC: TX', 'end'], ['TA']);
    end), FORM.Replace('    object TA: TIntegerField' + NL + '      FieldName = ''A''' + NL + '    end' + NL, '    object TC: TX' + NL + '    end' + NL));
  Check('D11 two edits of one text are refused', Edited(FORM,
    procedure(pDoc: TDfmDocument)
    begin
      pDoc.RemoveObject(pDoc.FindObject('TB', 'T'));
      pDoc.SetProp(pDoc.FindObject('TB', 'T'), 'Visible', 'True', []);
    end).Contains('two changes edit the same text'));
end;

procedure TestDfmTexts;
const
  LF_FORM = 'object F: TF'#10'  object T: TT'#10#9'object A: TA'#10#9'  P = 1'#10#9'end'#10'  end'#10'end';
  ANSI_FORM = 'object F: TF'#13#10'  object T: TT'#13#10'    Hint = ''caf'#233''''#13#10'    object A: TA'#13#10'      P = 1'#13#10'    end'#13#10'  end'#13#10'end'#13#10;
  ONE_LINE = 'object F: TF object T: TT object A: TA P = 1 Q = 2 end end end'#13#10;
begin
  CheckText('T1 LF line ends, a tab indent and a missing last line end stay', SetOn(LF_FORM, 'A', 'Q', 'True'),
    LF_FORM.Replace('P = 1'#10, 'P = 1'#10#9'  Q = True'#10));
  CheckText('T2 an ANSI byte stays', SetOn(ANSI_FORM, 'A', 'P', '2'), ANSI_FORM.Replace('P = 1', 'P = 2'));
  CheckText('T3 a UTF-8 BOM stays', SetOn(#$EF#$BB#$BF + FORM, 'TB', 'Visible', 'True'), #$EF#$BB#$BF + FORM.Replace('False', 'True'));
  CheckText('T4 a value in a one-line form is replaced', SetOn(ONE_LINE, 'A', 'P', '7'), ONE_LINE.Replace('P = 1', 'P = 7'));
  Check('T5 a property is not added to a one-line form', SetOn(ONE_LINE, 'A', 'R', '7').Contains('shares its line'));
  Check('T6 nor removed from it', Edited(ONE_LINE, procedure(pDoc: TDfmDocument) begin pDoc.RemoveProp(pDoc.FindObject('A', ''), 'P'); end).Contains('shares its line'));
  Check('T7 a binary DFM is refused', Edited('TPF0'#2'TF', procedure(pDoc: TDfmDocument) begin end).Contains('binary DFM is not written'));
  Check('T8 a resource DFM is refused', Edited(#$FF#10#0, procedure(pDoc: TDfmDocument) begin end).Contains('binary DFM is not written'));
  Check('T9 UTF-16 is refused', Edited(#$FF#$FE'o'#0, procedure(pDoc: TDfmDocument) begin end).StartsWith('!'));
  Check('T10 a text Delphi cannot read is refused', Edited('object F: TF' + NL + '  P = ' + NL + 'end', procedure(pDoc: TDfmDocument) begin end).Contains('Delphi cannot read the DFM text'));
  Check('T11 an incomplete DFM is refused', Edited('object F: TF' + NL, procedure(pDoc: TDfmDocument) begin end).StartsWith('!'));
  Check('T12 one component name twice is refused', Edited(
    'object F: TF' + NL + 'object A: TX' + NL + 'end' + NL + 'object A: TX' + NL + 'end' + NL + 'end' + NL,
    procedure(pDoc: TDfmDocument) begin pDoc.FindObject('A', ''); end).Contains('more than one component A'));
  Inspect('T13', FORM,
    procedure(pDoc: TDfmDocument)
    var
      VText: string;
    begin
      Check('T13 objects', (Length(pDoc.Objects) = FORM_OBJECTS) and (pDoc.Objects[FORM_TA].Name = 'TA') and (pDoc.Objects[FORM_TA].Parent = 1) and (Length(pDoc.Objects[1].Props) = FORM_OBJECTS));
      pDoc.TryProp(0, 'Caption', VText);
      CheckText('T14 a continued string decodes', VText, 'It''s "end" ''x end');
      Check('T15 references are found in collections, not in strings', string.Join(',', pDoc.ReferencesTo('TA')) = 'T.Items');
      Check('T16 no reference', Length(pDoc.ReferencesTo('TB')) = 0);
    end);
  Inspect('T17', ANSI_FORM,
    procedure(pDoc: TDfmDocument)
    var
      VText: string;
    begin
      pDoc.TryProp(1, 'Hint', VText);
      CheckText('T17 an ANSI string decodes', VText, 'caf'#233);
    end);
  Inspect('T18', ANSI_FORM.Replace(#233, #$C3#$A9),
    procedure(pDoc: TDfmDocument)
    var
      VText: string;
    begin
      pDoc.TryProp(1, 'Hint', VText);
      CheckText('T18 UTF-8 bytes without a BOM are ANSI, as Delphi reads them', VText, 'caf'#$C3#$A9);
    end);
  Check('T18 the RTL reads the same', ToText(DfmTextToBinary(ToBytes(ANSI_FORM.Replace(#233, #$C3#$A9)))) = ToText(DfmTextToBinary(ToBytes(ANSI_FORM.Replace('caf'#233'''', 'caf''#195#169')))));
  Inspect('T19', #$EF#$BB#$BF + ANSI_FORM.Replace(#233, #$C3#$A9),
    procedure(pDoc: TDfmDocument)
    var
      VText: string;
    begin
      pDoc.TryProp(1, 'Hint', VText);
      CheckText('T19 a UTF-8 string after a BOM decodes', VText, 'caf'#233);
    end);
  Check('T20 a text that is not ASCII is not written', SetOn(FORM, 'TA', 'Zzz', 'Caf'#233).Contains('not ASCII'));
end;

{ ---- unit ---- }

const
  CODE = 'unit U;' + NL + 'interface' + NL + '{ uses DB; }' + NL + 'uses Vcl.Forms, Data.DB;' + NL + 'type' + NL +
    '  TFoo = class end;' + NL + '  TF = class;' + NL + '  TF = class sealed (TForm, IFoo)' + NL + '    T: TFDQuery;' + NL +
    '    A, B: TIntegerField;' + NL + '    C: TIntegerField; // C; D' + NL + '    D: TIntegerField; procedure X;' + NL +
    '    procedure Y;' + NL + '  public' + NL + '    P: Integer;' + NL + '  end;' + NL + 'implementation' + NL +
    'uses System.SysUtils;' + NL + '(* B *) // C' + NL + 'const S = ''C''; M = ''''''' + NL + '  C := ''x''' + NL + '  '''''';' + NL +
    'procedure TF.X; begin C.Clear; end;' + NL + 'end.' + NL;

procedure TestUnits;
begin
  InspectUnit('U1', CODE,
    procedure(pUnit: TDfmUnitDocument)
    var
      VNames: string;
      VDecl: TDfmwDecl;
    begin
      for VDecl in pUnit.Declarations('tf') do
        VNames := VNames + VDecl.Name + ':' + VDecl.DeclClass + (if VDecl.Grouped then '*' else '') + ' ';
      CheckText('U1 declarations', VNames, 'T:TFDQuery A:TIntegerField* B:TIntegerField* C:TIntegerField D:TIntegerField ');
      Check('U2 interface uses', pUnit.UsesAny(['Data.DB']) and (not pUnit.UsesAny(['DB'])) and (not pUnit.UsesAny(['System.SysUtils'])));
      Check('U3 mentions: code only', (pUnit.Mentions('c') = 2) and (pUnit.Mentions('B') = 1) and (pUnit.Mentions('''C''') = 1), IntToStr(pUnit.Mentions('c')));
    end);
  CheckText('U4 a declaration after its neighbour, the comment stays', EditedUnit(CODE,
    procedure(pUnit: TDfmUnitDocument) begin pUnit.AddField('TF', 'N', 'TX', ['T', 'C']); end),
    CODE.Replace('// C; D' + NL, '// C; D' + NL + '    N: TX;' + NL));
  Check('U5 not beside other code', EditedUnit(CODE,
    procedure(pUnit: TDfmUnitDocument) begin pUnit.AddField('TF', 'N', 'TX', ['D']); end).Contains('shares its line with other code'));
  CheckText('U6 remove a declaration', EditedUnit(CODE.Replace('; // C; D', ';'),
    procedure(pUnit: TDfmUnitDocument)
    begin
      pUnit.RemoveField('TF', 'C');
      pUnit.RemoveField('TF', 'Nope');
    end),
    CODE.Replace('    C: TIntegerField; // C; D' + NL, ''));
  Check('U7 a grouped one is not removed', EditedUnit(CODE, procedure(pUnit: TDfmUnitDocument) begin pUnit.RemoveField('TF', 'A'); end).Contains('shares its type'));
  Check('U8 nor one with a comment beside it', EditedUnit(CODE, procedure(pUnit: TDfmUnitDocument) begin pUnit.RemoveField('TF', 'C'); end).Contains('shares its line'));
  Check('U9 an unknown class', EditedUnit(CODE, procedure(pUnit: TDfmUnitDocument) begin pUnit.Declarations('TZ'); end).Contains('is not declared'));
  CheckText('U10 an empty class', EditedUnit('unit U; interface' + NL + 'type' + NL + '  TF = class(TFrm)' + NL + '  end;' + NL + 'implementation' + NL + 'end.',
    procedure(pUnit: TDfmUnitDocument) begin pUnit.AddField('TF', 'N', 'TX', []); end),
    'unit U; interface' + NL + 'type' + NL + '  TF = class(TFrm)' + NL + '    N: TX;' + NL + '  end;' + NL + 'implementation' + NL + 'end.');
end;

{ ---- conditional compilation ---- }

{ A unit whose form class has these lines. }
function ClassUnit(const pHeader: string; const pLines: array of string): string;
var
  VLine: string;
begin
  Result := 'unit U;' + NL + 'interface' + NL + 'type' + NL + pHeader + NL;
  for VLine in pLines do
    Result := Result + VLine + NL;
  Result := Result + '  end;' + NL + 'implementation' + NL + 'end.' + NL;
end;

function AddN(const pText: string; const pAfter: TArray<string>): string;
begin
  Result := EditedUnit(pText, procedure(pUnit: TDfmUnitDocument) begin pUnit.AddField('TF', 'N', 'TX', pAfter); end);
end;

{ The new line goes after pLine. }
procedure CheckAdded(const pName, pText: string; const pAfter: TArray<string>; const pLine: string);
begin
  CheckText(pName, AddN(pText, pAfter), pText.Replace(pLine + NL, pLine + NL + '    N: TX;' + NL));
end;

procedure TestConditionals;
const
  HEADER = '  TF = class(TForm)';
  PRIVATE_PART = '  private';
  NOT_SAFE = 'conditional';
begin
  CheckAdded('I1 the last sibling is inside $IFDEF: after the one before it',
    ClassUnit(HEADER, ['    T: TQ;', '    {$IFDEF DEMO}', '    C: TX;', '    {$ENDIF}', PRIVATE_PART]), ['T', 'C'], '    T: TQ;');
  CheckAdded('I2 an anchor line that opens a conditional: after another declaration',
    ClassUnit(HEADER, ['    T: TQ; {$IFDEF X}', '    C: TX;', '    {$ENDIF}', '    E: TX;', PRIVATE_PART]), ['T'], '    E: TX;');
  CheckAdded('I3 every declaration is inside a conditional: after the class header',
    ClassUnit(HEADER, ['{$IF X}', '    T: TQ;', '{$IFEND}', PRIVATE_PART]), ['T'], HEADER);
  Check('I4 no safe place: refused', AddN(ClassUnit(HEADER + ' {$IFNDEF X}', ['    T: TQ;', '    {$ENDIF}', PRIVATE_PART]), ['T']).Contains(NOT_SAFE));
  Check('I5 the class twice', AddN(ClassUnit('{$IFDEF A}' + NL + HEADER + NL + '    T: TQ;' + NL + '  end;' + NL + '{$ELSE}' + NL + HEADER,
    ['    T: TQ;', '  end;', '{$ENDIF}', '  TG = class']), ['T']).Contains('more than once'));
  CheckAdded('I6 a conditional around the whole class is no obstacle',
    ClassUnit('{$IFDEF A}' + NL + HEADER, ['    T: TQ;', PRIVATE_PART, '  end;', '{$ENDIF}', '  TG = class']), ['T'], '    T: TQ;');
  Check('I7 the section ends inside a conditional', AddN(ClassUnit(HEADER, ['    T: TQ;', '{$IFDEF X}', PRIVATE_PART, '{$ENDIF}', '    C: TX;']), ['T']).Contains(NOT_SAFE));
  Check('I8 the header is inside a conditional that ends in the section',
    AddN(ClassUnit('{$IFDEF X}' + NL + HEADER + NL + '{$ENDIF}', ['    T: TQ;', PRIVATE_PART]), ['T']).Contains(NOT_SAFE));
  CheckAdded('I9 an $ELSE branch and the (*$ form',
    ClassUnit(HEADER, ['(*$IFOPT D+*)', '    T: TQ;', '{$ELSE}', '    C: TX;', '(*$ENDIF*)', '    E: TX;', PRIVATE_PART]), ['T', 'C'], '    E: TX;');
  CheckAdded('I10 other directives and comments are no obstacle',
    ClassUnit(HEADER, ['{$REGION ''R''}', '    T: TQ; { IFDEF }', '{$ENDREGION}', '    E: TX;', PRIVATE_PART]), ['T'], '    T: TQ; { IFDEF }');
  CheckAdded('I11 a comment that goes on on the next line: after another declaration',
    ClassUnit(HEADER, ['    E: TX;', '    T: TQ; { note', '      goes on }', PRIVATE_PART]), ['T'], '    E: TX;');
  CheckAdded('I12 closed conditionals before the class do not count',
    ClassUnit('{$IFDEF A}' + NL + '  TE = class end;' + NL + '{$ENDIF}' + NL + HEADER, ['    T: TQ;', PRIVATE_PART]), ['T'], '    T: TQ;');
  Check('I13 a declaration of a class declared twice is not removed', EditedUnit(ClassUnit('{$IFDEF A}' + NL + HEADER + NL + '    T: TQ;' + NL + '  end;' + NL + '{$ELSE}' + NL + HEADER,
    ['    T: TQ;', '  end;', '{$ENDIF}', '  TG = class']),
    procedure(pUnit: TDfmUnitDocument) begin pUnit.RemoveField('TF', 'T'); end).Contains('more than once'));
end;

{ ---- files ---- }

const
  WRITE_FORM = 'object F: TF' + NL + '  object T: TFDQuery' + NL + '    object TA: TIntegerField' + NL + '      FieldName = ''A''' + NL +
    '    end' + NL + '  end' + NL + 'end' + NL;
  WRITE_UNIT = 'unit U;' + NL + 'interface' + NL + 'type' + NL + '  TF = class(TForm)' + NL + '    T: TFDQuery;' + NL + '    TA: TIntegerField;' + NL +
    '  end;' + NL + 'implementation' + NL + 'end.' + NL;
  NEW_FORM = '    object TB: TIntegerField' + NL + '      FieldName = ''B''' + NL + '    end' + NL;
  NEW_DECL = '    TB: TIntegerField;' + NL;
  BACKUP_MARK = '.before-write-dfm-';
  FILES_OF_TWO = 4; // two forms with their units
  STAMP_SECONDS = 20; // the names a backup could get while the test runs
  SECONDS_PER_DAY = 86400;

var
  GWork: string;

function FileText(const pName: string): string;
begin
  Result := ToText(TFile.ReadAllBytes(TPath.Combine(GWork, pName)));
end;

procedure PutFile(const pName, pText: string);
begin
  TFile.WriteAllBytes(TPath.Combine(GWork, pName), ToBytes(pText));
end;

{ An empty folder for one case. }
procedure NewWork;
begin
  if (GWork <> '') and TDirectory.Exists(GWork) then
    TDirectory.Delete(GWork, True);
  GWork := TPath.Combine(TPath.GetTempPath, 'dl-dfmwrite-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(GWork);
end;

{ Every file of the folder but the forms and units themselves. }
function OtherFiles: TArray<string>;
var
  VFile: string;
begin
  Result := nil;
  for VFile in TDirectory.GetFiles(GWork) do
    if not (VFile.EndsWith('.dfm') or VFile.EndsWith('.pas')) then
      Result := Result + [VFile];
end;

{ Plans one added field in each of the forms a.dfm, b.dfm, whose units have the texts pUnits. }
function AddPlan(const pUnits: TArray<string>): TDfmwPlan;
var
  VI: Integer;
  VName: string;
  VFile: TDfmwFile;
  VItem: TDfmwItem;
  VChange: TFrChange;
begin
  Result := Default(TDfmwPlan);
  for VI := 0 to High(pUnits) do
  begin
    VName := Char(Ord('a') + VI);
    PutFile(VName + '.dfm', WRITE_FORM);
    PutFile(VName + '.pas', pUnits[VI]);
    VFile.DfmName := TPath.Combine(GWork, VName + '.dfm');
    VFile.DfmBytes := ToBytes(WRITE_FORM);
    VFile.PasName := TPath.Combine(GWork, VName + '.pas');
    VFile.PasBytes := ToBytes(pUnits[VI]);
    VFile.FormClass := 'TF';
    VItem := Default(TDfmwItem);
    VItem.FileIndex := VI;
    VItem.Action := dwaInsert;
    VItem.Dataset := 'T';
    VItem.Component := 'TB';
    VItem.FieldClass := 'TIntegerField';
    VItem.Block := ['object TB: TIntegerField', '  FieldName = ''B''', 'end'];
    VItem.Siblings := ['TA'];
    VChange := Default(TFrChange);
    VChange.Id := VI + 1;
    VChange.Checked := True;
    Result.Files := Result.Files + [VFile];
    Result.Items := Result.Items + [VItem];
    Result.ChangeSet.Changes := Result.ChangeSet.Changes + [VChange];
  end;
end;

{ '' or the message of the failure. }
function Applied(const pPlan: TDfmwPlan): string;
begin
  Result := '';
  try
    ApplyDfmWrite(pPlan, pPlan.ChangeSet.Changes);
  except
    on E: EDfmWriteError do
      Result := E.Message;
  end;
end;

function Added(const pUnit, pDecl: string): string;
begin
  Result := pUnit.Replace('    TA: TIntegerField;', '    TA: TIntegerField;' + pDecl);
end;

procedure CheckForm(const pName, pFile: string; pWritten: Boolean; const pUnit: string = WRITE_UNIT);
begin
  CheckText(pName + ' ' + pFile + '.dfm', FileText(pFile + '.dfm'),
    if pWritten then WRITE_FORM.Replace('  end' + NL + 'end', NEW_FORM + '  end' + NL + 'end') else WRITE_FORM);
  CheckText(pName + ' ' + pFile + '.pas', FileText(pFile + '.pas'),
    if pWritten then pUnit.Replace('    TA: TIntegerField;' + NL, '    TA: TIntegerField;' + NL + NEW_DECL) else pUnit);
end;

procedure TestTwoForms;
var
  VPlan: TDfmwPlan;
  VFile: string;
begin
  NewWork;
  VPlan := AddPlan([WRITE_UNIT, WRITE_UNIT]);
  CheckText('F1 two forms', Applied(VPlan), '');
  CheckForm('F1', 'a', True);
  CheckForm('F1', 'b', True);
  Check('F1 four backups, no other file', Length(OtherFiles) = FILES_OF_TWO);
  for VFile in OtherFiles do
    CheckText('F1 a backup holds the old bytes', FileText(ExtractFileName(VFile)), if VFile.Contains('.dfm.') then WRITE_FORM else WRITE_UNIT);
end;

procedure TestChangedFile;
var
  VPlan: TDfmwPlan;
begin
  NewWork;
  VPlan := AddPlan([WRITE_UNIT, WRITE_UNIT]);
  PutFile('b.pas', WRITE_UNIT + '{ saved meanwhile }' + NL);
  Check('F2 a file that changed since it was read is refused', Applied(VPlan).Contains('changed since it was read'));
  CheckForm('F2', 'a', False);
  CheckText('F2 the changed unit stays', FileText('b.pas'), WRITE_UNIT + '{ saved meanwhile }' + NL);
  Check('F2 no backup', Length(OtherFiles) = 0);
end;

{ The last file can be opened for writing but not replaced: the files written before it get their old bytes back. }
procedure TestRollback;
var
  VPlan: TDfmwPlan;
  VHold: TFileStream;
  VMessage: string;
begin
  NewWork;
  VPlan := AddPlan([WRITE_UNIT, WRITE_UNIT]);
  VHold := TFileStream.Create(TPath.Combine(GWork, 'b.pas'), fmOpenRead or fmShareDenyNone);
  try
    VMessage := Applied(VPlan);
  finally
    VHold.Free;
  end;
  Check('F3 a write that fails is undone', VMessage.Contains('undone'), VMessage);
  Check('F3 the message names the backups', VMessage.Contains('a.dfm' + BACKUP_MARK) and VMessage.Contains('b.pas' + BACKUP_MARK), VMessage);
  CheckForm('F3', 'a', False);
  CheckForm('F3', 'b', False);
  Check('F3 only the backups are left', Length(OtherFiles) = FILES_OF_TWO, string.Join(' ', OtherFiles));
end;

procedure TestBackupNames;
const
  TAKEN = 'an older backup';
var
  VPlan: TDfmwPlan;
  VI, VKept, VNumbered: Integer;
  VFile: string;
begin
  NewWork;
  VPlan := AddPlan([WRITE_UNIT]);
  for VI := 0 to STAMP_SECONDS do
    PutFile('a.dfm' + BACKUP_MARK + FormatDateTime('yyyymmdd-hhnnss', Now + VI / SECONDS_PER_DAY), TAKEN);
  CheckText('F4 applied', Applied(VPlan), '');
  VKept := 0;
  VNumbered := 0;
  for VFile in OtherFiles do
    if FileText(ExtractFileName(VFile)) = TAKEN then
      Inc(VKept)
    else if VFile.EndsWith('-1') and (FileText(ExtractFileName(VFile)) = WRITE_FORM) then
      Inc(VNumbered);
  Check('F4 no existing backup is overwritten', VKept = STAMP_SECONDS + 1, IntToStr(VKept));
  Check('F4 the new one gets a number', VNumbered = 1, IntToStr(VNumbered));
end;

procedure TestUnitBytes;
var
  VText: string;
begin
  NewWork;
  VText := WRITE_UNIT.Replace(NL, #10);
  CheckText('F5 LF unit', Applied(AddPlan([VText])), '');
  CheckText('F5 LF line ends stay', FileText('a.pas'), Added(VText, #10'    TB: TIntegerField;'));
  NewWork;
  VText := WRITE_UNIT.Replace('unit U;', 'unit U; // caf'#233#232);
  CheckText('F6 ANSI unit', Applied(AddPlan([VText])), '');
  CheckText('F6 high bytes stay', FileText('a.pas'), Added(VText, NL + '    TB: TIntegerField;'));
  NewWork;
  VText := #$EF#$BB#$BF + WRITE_UNIT.Replace('unit U;', 'unit U; // caf'#$C3#$A9);
  CheckText('F7 UTF-8 unit', Applied(AddPlan([VText])), '');
  CheckText('F7 the BOM and the UTF-8 bytes stay', FileText('a.pas'), Added(VText, NL + '    TB: TIntegerField;'));
  NewWork;
  VText := #$FF#$FE'u'#0;
  Check('F8 a UTF-16 unit is refused', Applied(AddPlan([VText])).Contains('UTF-16'));
  CheckForm('F8', 'a', False, VText);
  Check('F8 no backup', Length(OtherFiles) = 0);
end;

procedure TestFiles;
begin
  try
    TestTwoForms;
    TestChangedFile;
    TestRollback;
    TestBackupNames;
    TestUnitBytes;
  finally
    if TDirectory.Exists(GWork) then
      TDirectory.Delete(GWork, True);
  end;
end;

{ ---- classes ---- }

procedure TestClasses;
const
  ACCESSORS: array[0..12] of string = ('AsInteger', 'AsLongWord', 'AsLargeInt', 'AsFloat', 'AsSingle', 'AsExtended',
    'AsCurrency', 'AsBCD', 'AsString', 'AsBoolean', 'AsDateTime', 'AsSQLTimeStamp', 'AsSQLTimeStampOffset');
var
  VAccessor: string;
begin
  for VAccessor in ACCESSORS do
    CheckText('C1 the class of ' + VAccessor + ' has that accessor', FieldClassAccessor(FieldClassForRow(0, 0, 0, VAccessor, '')), VAccessor);
  CheckText('C2 integer', FieldClassForRow(FB_INTEGER, 0, 0, 'AsInteger', ''), 'TIntegerField');
  CheckText('C3 numeric(9,2)', FieldClassForRow(FB_INTEGER, 1, TWO_DECIMALS, 'AsBCD', ''), 'TBCDField');
  CheckText('C4 numeric with 6 decimals', FieldClassForRow(FB_INT64, 1, SIX_DECIMALS, '', ''), 'TFMTBCDField');
  CheckText('C5 text blob', FieldClassForRow(FB_BLOB, 1, 0, '', ''), 'TMemoField');
  CheckText('C6 varchar octets', FieldClassForRow(FB_VARCHAR, 1, 0, 'AsByte', ''), 'TVarBytesField');
  CheckText('C7 an unknown type code is not guessed from the accessor', FieldClassForRow(FB_UNKNOWN, 0, 0, 'AsInteger', ''), '');
  CheckText('C8 nothing known', FieldClassForRow(0, 0, 0, '', ''), '');
  CheckText('C9 a memo that is not a column', FieldClassForRow(0, 0, 0, 'AsString', 'TStringList'), 'TMemoField');
end;

begin
  try
    TestLiterals;
    TestDfmEdits;
    TestDfmTexts;
    TestUnits;
    TestConditionals;
    TestFiles;
    TestClasses;
  except
    on E: Exception do
      Check('unexpected ' + E.ClassName, False, E.Message);
  end;
  Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
