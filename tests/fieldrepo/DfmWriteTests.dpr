program DfmWriteTests;

{ Self-contained console test runner (no DUnitX) for the byte-level editors of lane TT-DFMWRITE (drag-lint 1.54):
  TDfmDocument, TDfmUnitDocument, the RTL-made literals and the field class of a repository row. One PASS/FAIL line per
  case, a summary line, exit code 1 on any failure. The CLI (repository, files, backup, the compiled form) is
  run_fieldrepo_dfmwrite.ps1. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
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
  Edited(VText,
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
    Edited(VText,
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
  Edited(FORM,
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
  Edited(ANSI_FORM,
    procedure(pDoc: TDfmDocument)
    var
      VText: string;
    begin
      pDoc.TryProp(1, 'Hint', VText);
      CheckText('T17 an ANSI string decodes', VText, 'caf'#233);
    end);
  Edited(ANSI_FORM.Replace(#233, #$C3#$A9),
    procedure(pDoc: TDfmDocument)
    var
      VText: string;
    begin
      pDoc.TryProp(1, 'Hint', VText);
      CheckText('T18 a UTF-8 string decodes', VText, 'caf'#233);
    end);
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
  EditedUnit(CODE,
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
    TestClasses;
  except
    on E: Exception do
      Check('unexpected ' + E.ClassName, False, E.Message);
  end;
  Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
