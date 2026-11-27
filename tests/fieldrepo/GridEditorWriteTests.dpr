program GridEditorWriteTests;

{ Self-contained console test runner (no DUnitX) for the grid column editor of lane GC-W (drag-lint 1.56):
  TDfmDocument.TryEditor / SetEditor, DfmEditorText and DfmEditorBlock on bytes. Every written text is read again and
  converted text -> binary -> text by the RTL. One PASS/FAIL line per case, a summary line, exit code 1 on any failure.
  The CLI (repository, the compiled form) is tests\autotest\run_v156_GCW.ps1. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  DRagLint.FieldRepo.DfmWrite in '..\..\src\sql\DRagLint.FieldRepo.DfmWrite.pas';

const
  NL = #13#10;
  COMBO = 'TcxComboBoxProperties';
  CURRENCY = 'TcxCurrencyEditProperties';
  COMBO_PROPS = 'Properties.DropDownListStyle = lsFixedList' + NL +
    'Properties.Items.Strings = (' + NL +
    '  ''one''' + NL +
    '  ''it''''s end'')' + NL +
    'Properties.Buttons = <' + NL +
    '  item' + NL +
    '    Default = True' + NL +
    '  end>';
  FORM = 'object F: TF' + NL +
    '  object V: TcxGridDBTableView' + NL +
    '    DataController.DataSource = ds' + NL +
    '    object colPlain: TcxGridDBColumn' + NL +
    '      Caption = ''Plain''' + NL +
    '      DataBinding.FieldName = ''A''' + NL +
    '      Width = 40' + NL +
    '    end' + NL +
    '    object colCombo: TcxGridDBColumn' + NL +
    '      DataBinding.FieldName = ''B''' + NL +
    '      PropertiesClassName = ''TcxComboBoxProperties''' + NL +
    '      Properties.DropDownListStyle = lsFixedList' + NL +
    '      Properties.Items.Strings = (' + NL +
    '        ''one''' + NL +
    '        ''it''''s end'')' + NL +
    '      Properties.Buttons = <' + NL +
    '        item' + NL +
    '          Default = True' + NL +
    '        end>' + NL +
    '      Width = 50' + NL +
    '    end' + NL +
    '    object colBare: TcxGridDBColumn' + NL +
    '    end' + NL +
    '    object colWidth: TcxGridDBColumn' + NL +
    '      Width = 7' + NL +
    '    end' + NL +
    '  end' + NL +
    'end' + NL;

type
  TEditProc = reference to procedure(pDoc: TDfmDocument);

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

function Edited(const pText: string; const pProc: TEditProc): string;
var
  VDoc: TDfmDocument;
begin
  VDoc := TDfmDocument.Create(TEncoding.ASCII.GetBytes(pText), 'f.dfm');
  try
    pProc(VDoc);
    Result := TEncoding.ASCII.GetString(VDoc.Output);
  finally
    VDoc.Free;
  end;
end;

{ `CLASS|PROPERTIES` of a column, `-` when the block states no editor. }
function EditorOf(const pText, pColumn: string): string;
var
  VDoc: TDfmDocument;
  VClass, VProperties: string;
begin
  VDoc := TDfmDocument.Create(TEncoding.ASCII.GetBytes(pText), 'f.dfm');
  try
    Result := if VDoc.TryEditor(VDoc.FindObject(pColumn, 'V'), VClass, VProperties) then VClass + '|' + VProperties else '-';
  finally
    VDoc.Free;
  end;
end;

{ The text the RTL makes of the text: text -> binary -> text. }
function ThroughBinary(const pText: string): string;
var
  VIn, VBinary, VOut: TBytesStream;
begin
  VIn := TBytesStream.Create(TEncoding.ASCII.GetBytes(pText));
  VBinary := TBytesStream.Create;
  VOut := TBytesStream.Create;
  try
    ObjectTextToBinary(VIn, VBinary);
    VBinary.Position := 0;
    ObjectBinaryToText(VBinary, VOut);
    Result := TEncoding.ASCII.GetString(VOut.Bytes, 0, VOut.Size);
  finally
    VOut.Free;
    VBinary.Free;
    VIn.Free;
  end;
end;

function Refused(const pText, pColumn, pClass, pProperties: string): string;
begin
  Result := '';
  try
    Edited(pText, procedure(pDoc: TDfmDocument)
      begin
        pDoc.SetEditor(pDoc.FindObject(pColumn, 'V'), pClass, pProperties);
      end);
  except
    on E: EDfmWriteError do
      Result := E.Message;
  end;
end;

function WithEditor(const pText, pColumn, pClass, pProperties: string): string;
begin
  Result := Edited(pText, procedure(pDoc: TDfmDocument)
    begin
      pDoc.SetEditor(pDoc.FindObject(pColumn, 'V'), pClass, pProperties);
    end);
end;

procedure TestRead;
begin
  CheckText('R1 a column without an editor', EditorOf(FORM, 'colPlain'), '-');
  CheckText('R2 class and lines: the property''s indentation is gone, the value''s own stays', EditorOf(FORM, 'colCombo'),
    COMBO + '|' + COMBO_PROPS);
  CheckText('R3 LF text and blanks at a line end read the same', EditorOf(FORM.Replace(NL, #10).Replace('lsFixedList', 'lsFixedList  '),
    'colCombo'), COMBO + '|' + COMBO_PROPS);
  CheckText('R4 DfmEditorText: CRLF, no blank at a line end, no empty last line', DfmEditorText('Properties.A = 1  '#10'Properties.B = 2'#13#10#10),
    'Properties.A = 1' + NL + 'Properties.B = 2');
  CheckText('R5 DfmEditorBlock: the class first', string.Join('/', DfmEditorBlock(CURRENCY, 'Properties.A = 1')),
    'PropertiesClassName = ''' + CURRENCY + '''/Properties.A = 1');
  Check('R6 DfmEditorBlock: no class, no lines: nothing', Length(DfmEditorBlock('', '')) = 0);
end;

procedure TestWrite;
var
  VText, VAgain: string;
begin
  VText := WithEditor(FORM, 'colPlain', CURRENCY, 'Properties.DisplayFormat = ''0.00''' + NL + 'Properties.Nullable = False');
  CheckText('W1 a new editor goes after Caption and DataBinding, the class first; no other byte changes', VText,
    FORM.Replace('      DataBinding.FieldName = ''A''' + NL, '      DataBinding.FieldName = ''A''' + NL +
    '      PropertiesClassName = ''' + CURRENCY + '''' + NL + '      Properties.DisplayFormat = ''0.00''' + NL +
    '      Properties.Nullable = False' + NL));
  CheckText('W2 it reads back', EditorOf(VText, 'colPlain'), CURRENCY + '|Properties.DisplayFormat = ''0.00''' + NL + 'Properties.Nullable = False');
  CheckText('W3 the other column is as it was', EditorOf(VText, 'colCombo'), COMBO + '|' + COMBO_PROPS);
  VAgain := ThroughBinary(VText);
  CheckText('W4 text -> binary -> text: Delphi reads the same editor', EditorOf(VAgain, 'colPlain'), EditorOf(VText, 'colPlain'));
  CheckText('W5 and writes the text it read', ThroughBinary(VAgain), VAgain);

  VText := WithEditor(FORM, 'colCombo', CURRENCY, 'Properties.DisplayFormat = ''0.00''');
  CheckText('W6 another editor takes the place of the stated one, lists and collections go whole', VText,
    FORM.Replace('      PropertiesClassName = ''TcxComboBoxProperties''' + NL + '      Properties.DropDownListStyle = lsFixedList' + NL +
    '      Properties.Items.Strings = (' + NL + '        ''one''' + NL + '        ''it''''s end'')' + NL +
    '      Properties.Buttons = <' + NL + '        item' + NL + '          Default = True' + NL + '        end>' + NL,
    '      PropertiesClassName = ''' + CURRENCY + '''' + NL + '      Properties.DisplayFormat = ''0.00''' + NL));
  CheckText('W7 the editor a column has, written again: the same bytes', WithEditor(FORM, 'colCombo', COMBO, COMBO_PROPS), FORM);
  VText := WithEditor(FORM, 'colPlain', COMBO, COMBO_PROPS);
  CheckText('W8 a list and a collection written to another column read back', EditorOf(VText, 'colPlain'), COMBO + '|' + COMBO_PROPS);
  CheckText('W9 and survive text -> binary -> text (the RTL writes a quote inside a string as #39)', EditorOf(ThroughBinary(VText), 'colPlain'),
    COMBO + '|' + COMBO_PROPS.Replace('''it''''s end''', '''it''#39''s end'''));
  CheckText('W10 a column without properties: after its header', WithEditor(FORM, 'colBare', CURRENCY, ''),
    FORM.Replace('    object colBare: TcxGridDBColumn' + NL, '    object colBare: TcxGridDBColumn' + NL +
    '      PropertiesClassName = ''' + CURRENCY + '''' + NL));
  CheckText('W11 a column with other properties only: before them', WithEditor(FORM, 'colWidth', CURRENCY, 'Properties.A = 1'),
    FORM.Replace('      Width = 7' + NL, '      PropertiesClassName = ''' + CURRENCY + '''' + NL + '      Properties.A = 1' + NL +
    '      Width = 7' + NL));
  CheckText('W12 no class and no lines: the stated editor goes', EditorOf(WithEditor(FORM, 'colCombo', '', ''), 'colCombo'), '-');
  CheckText('W13 an LF form keeps its line ends', WithEditor(FORM.Replace(NL, #10), 'colPlain', CURRENCY, 'Properties.A = 1' + NL + 'Properties.B = 2'),
    FORM.Replace('      DataBinding.FieldName = ''A''' + NL, '      DataBinding.FieldName = ''A''' + NL +
    '      PropertiesClassName = ''' + CURRENCY + '''' + NL + '      Properties.A = 1' + NL + '      Properties.B = 2' + NL).Replace(NL, #10));
  CheckText('W14 an editor stated out of order: every line of it goes, the new one takes the first place',
    WithEditor(FORM.Replace('      Width = 50' + NL, '      Width = 50' + NL + '      Properties.ReadOnly = True' + NL), 'colCombo', CURRENCY, ''),
    FORM.Replace('      PropertiesClassName = ''TcxComboBoxProperties''' + NL + '      Properties.DropDownListStyle = lsFixedList' + NL +
    '      Properties.Items.Strings = (' + NL + '        ''one''' + NL + '        ''it''''s end'')' + NL +
    '      Properties.Buttons = <' + NL + '        item' + NL + '          Default = True' + NL + '        end>' + NL,
    '      PropertiesClassName = ''' + CURRENCY + '''' + NL));
end;

procedure TestRefusals;
begin
  Check('X1 a line that is not a Properties line', Refused(FORM, 'colPlain', CURRENCY, 'Width = 9').Contains('not a line of Properties.*: Width = 9'),
    Refused(FORM, 'colPlain', CURRENCY, 'Width = 9'));
  Check('X2 an object smuggled in', Refused(FORM, 'colPlain', CURRENCY, 'Properties.A = 1' + NL + 'end' + NL + 'object X: TY').Contains('not a line of Properties.*: end'));
  Check('X3 an indented line with no property before it', Refused(FORM, 'colPlain', CURRENCY, '  ''one'')').Contains('not a line of Properties.*'));
  Check('X4 lines without a class', Refused(FORM, 'colPlain', '', 'Properties.A = 1').Contains('editor properties without PropertiesClassName'));
  Check('X5 a class name that is no identifier', Refused(FORM, 'colPlain', 'Tcx''; end', '').Contains('not an editor properties class name'));
  Check('X6 a stated editor line that shares its line', Refused(FORM.Replace('      PropertiesClassName = ''TcxComboBoxProperties''' + NL,
    '      PropertiesClassName = ''TcxComboBoxProperties'' '), 'colCombo', CURRENCY, '') <> '');
  Check('X7 the file name is in the message', Refused(FORM, 'colPlain', CURRENCY, 'Width = 9').StartsWith('f.dfm: '));
end;

begin
  try
    TestRead;
    TestWrite;
    TestRefusals;
  except
    on E: Exception do
      Check('unexpected ' + E.ClassName, False, E.Message);
  end;
  Writeln(Format('SUMMARY pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
