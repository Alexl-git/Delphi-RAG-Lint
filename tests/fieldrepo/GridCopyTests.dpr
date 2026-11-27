program GridCopyTests;

{ Self-contained console test runner (no DUnitX) for the grid copy model of lane GCP-M (drag-lint 1.56):
  DRagLint.FieldRepo.GridCopy on the bytes of tests\fixtures\fieldrepo\gridcopy (a form with a table view, a banded
  table view and a card view). Every applied plan is compared byte for byte with the fixture plus the expected lines
  and is converted to a binary DFM by the RTL. One PASS/FAIL line per case, a summary line, exit code 1 on any
  failure. Usage: GridCopyTests.exe [fixture folder]  |  GridCopyTests.exe --apply DIR SOURCEVIEW TARGETVIEW. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  DRagLint.FieldRepo.ChangeSet in '..\..\src\sql\DRagLint.FieldRepo.ChangeSet.pas',
  DRagLint.FieldRepo.Kinds in '..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.DfmWrite in '..\..\src\sql\DRagLint.FieldRepo.DfmWrite.pas',
  DRagLint.FieldRepo.GridCopy in '..\..\src\sql\DRagLint.FieldRepo.GridCopy.pas';

const
  NL = #13#10;
  PLAN_ID_LENGTH = 16;
  APPLY_SWITCH_AT = 1;
  APPLY_DIR_AT = 2;
  APPLY_SOURCE_AT = 3;
  APPLY_TARGET_AT = 4;
  CODE_COLUMN_CHANGE = 7; // ids in the plan EVERYTHING_TEXT
  CODE_EVENT_CHANGE = 8;
  VIEW_COUNT = 3;
  TV_COLUMNS = 3;
  TV_EVENTS = 12;
  BAND_ANCHOR = '      DataController.Summary.SummaryGroups = <>' + NL + '      object bvMainNAME';
  BAND_COLUMN_ANCHOR = '        Position.RowIndex = -1' + NL;
  UNBOUND = 'object F: TF' + NL +
    '  object G: TcxGrid' + NL +
    '    object uv: TcxGridTableView' + NL +
    '      DataController.OnAfterPost = uvAfterPost' + NL +
    '      DataController.OnCompare = uvCompare' + NL +
    '      OnMystery = uvMystery' + NL +
    '      OnKeyDown = ''text''' + NL +
    '      Online = uvOnline' + NL +
    '    end' + NL +
    '    object dv: TcxGridDBTableView' + NL +
    '    end' + NL +
    '    object ch: TcxGridDBChartView' + NL +
    '    end' + NL +
    '    inline fr: TFrame1' + NL +
    '      object fv: TcxGridDBTableView' + NL +
    '      end' + NL +
    '    end' + NL +
    '  end' + NL +
    'end' + NL;

var
  GPass, GFail: Integer;
  GFixtures: string;

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

function Fixture: TGridCopyForm;
begin
  Result.DfmFile := TPath.Combine(GFixtures, 'uCopy.dfm');
  Result.DfmBytes := TFile.ReadAllBytes(Result.DfmFile);
  Result.UnitFile := TPath.Combine(GFixtures, 'uCopy.pas');
  Result.UnitBytes := TFile.ReadAllBytes(Result.UnitFile);
end;

function TextForm(const pDfm: string): TGridCopyForm;
begin
  Result := Default(TGridCopyForm);
  Result.DfmFile := 'F.dfm';
  Result.DfmBytes := ToBytes(pDfm);
end;

function FixtureText: string;
begin
  Result := ToText(Fixture.DfmBytes);
end;

function One(const pEvent: string; const pTarget: string = 'bvMain'; const pSourceColumn: string = '';
  const pTargetColumn: string = ''): TGridCopyPlan;
begin
  Result := PlanGridCopy(Fixture, TGridCopyRequest.OneEvent('tvMain', pTarget, pEvent, pSourceColumn, pTargetColumn));
end;

{ The new DFM text of the chosen changes; the RTL must be able to read it. }
function Applied(const pPlan: TGridCopyPlan; const pIds: TArray<Integer>): string;
var
  VOut: TArray<TDfmwOutput>;
begin
  VOut := ApplyGridCopy(pPlan, pIds);
  if Length(VOut) = 0 then
    Exit('(no output)');
  if (Length(VOut) <> 1) or (VOut[0].FileName <> pPlan.Form.DfmFile)
    or (ToText(VOut[0].OldBytes) <> ToText(pPlan.Form.DfmBytes)) then
    Exit('(wrong outputs)');
  if Length(DfmTextToBinary(VOut[0].NewBytes)) = 0 then
    Exit('(the RTL gives no binary)');
  Result := ToText(VOut[0].NewBytes);
end;

function Raises(const pProc: TProc; pClass: ExceptClass; const pPart: string): string;
begin
  try
    pProc();
    Result := 'no exception';
  except
    on E: Exception do
      Result := if (E.ClassType = pClass) and ((pPart = '') or E.Message.Contains(pPart)) then ''
        else E.ClassName + ': ' + E.Message;
  end;
end;

procedure CheckRaises(const pName: string; const pProc: TProc; pClass: ExceptClass; const pPart: string);
var
  VGot: string;
begin
  VGot := Raises(pProc, pClass, pPart);
  Check(pName, VGot = '', VGot + ' (want ' + pClass.ClassName + ' with <' + pPart + '>)');
end;

function Describe(const pPlan: TGridCopyPlan): string;
begin
  Result := string.Join('|', RenderGridCopyText(pPlan));
end;

procedure TestLists;
var
  VViews: TArray<TGridCopyViewInfo>;
  VEvents: TArray<TGridCopyEvent>;
  VColumns: TArray<TFrGridColumn>;
begin
  VViews := GridCopyViews(Fixture);
  Check('L1 the three views', (Length(VViews) = VIEW_COUNT) and (VViews[0].Name = 'tvMain')
    and (VViews[0].ViewClass = 'TcxGridDBTableView') and (VViews[0].ItemClass = 'TcxGridDBColumn')
    and (VViews[0].ColumnCount = TV_COLUMNS) and (VViews[1].Name = 'bvMain') and (VViews[1].ColumnCount = 1)
    and (VViews[2].Name = 'cvMain') and (VViews[2].ItemClass = 'TcxGridDBCardViewRow') and (VViews[2].ColumnCount = 0));
  VViews := GridCopyViews(TextForm(UNBOUND));
  Check('L2 a chart view is not listed, a view of a frame instance is', (Length(VViews) = VIEW_COUNT)
    and (VViews[0].Name = 'uv') and (VViews[1].Name = 'dv') and (VViews[2].Name = 'fv'));
  VEvents := GridCopyEvents(Fixture, 'tvMain');
  Check('L3 the events of a view and its columns', (Length(VEvents) = TV_EVENTS) and (VEvents[0].Component = 'tvMain')
    and (VEvents[0].Event = 'OnCellDblClick') and (VEvents[0].Handler = 'tvMainCellDblClick') and not VEvents[0].IsColumn
    and (VEvents[2].Event = 'DataController.OnCompare') and (VEvents[High(VEvents)].Component = 'tvMainQTY')
    and (VEvents[High(VEvents)].ComponentClass = 'TcxGridDBColumn') and VEvents[High(VEvents)].IsColumn
    and (VEvents[High(VEvents)].Handler = 'tvMainCODEGetDisplayText'), Length(VEvents).ToString);
  VEvents := GridCopyEvents(TextForm(UNBOUND), 'uv');
  Check('L4 an event is On + capital with one identifier', (Length(VEvents) = VIEW_COUNT)
    and (VEvents[2].Event = 'OnMystery'), Length(VEvents).ToString);
  VColumns := GridViewColumns(Fixture, 'tvMain');
  Check('L5 the columns as repository rows', (Length(VColumns) = TV_COLUMNS) and (VColumns[0].FormName = 'frmCopy')
    and (VColumns[0].ViewName = 'tvMain') and (VColumns[0].ColumnName = 'tvMainCODE') and (VColumns[0].FieldName = 'CODE')
    and (VColumns[0].TableName = '') and (VColumns[0].ColumnIndex = 0) and VColumns[0].HasEditor
    and (VColumns[0].PropertiesClassName = 'TcxComboBoxProperties') and (VColumns[2].ColumnIndex = 2)
    and not VColumns[2].HasEditor and (VColumns[2].Properties = ''));
  CheckText('L6 the editor lines of a column', VColumns[0].Properties, 'Properties.Items.Strings = (' + NL + '  ''A'''
    + NL + '  ''B'')' + NL + 'Properties.OnChange = tvMainCODEPropertiesChange');
  CheckRaises('L7 no such view', procedure begin GridCopyEvents(Fixture, 'nope'); end, EGridCopyError, 'no grid view nope');
  CheckRaises('L8 not a grid view', procedure begin GridViewColumns(Fixture, 'cxGrid1'); end, EGridCopyError,
    'cxGrid1 is a TcxGrid');
end;

procedure TestOneEvent;
var
  VPlan: TGridCopyPlan;
  VText: string;
  VForm: TGridCopyForm;
begin
  VPlan := One('OnCustomDrawCell');
  Check('E1 a view event: one checked insert', (Length(VPlan.Changes) = 1) and (VPlan.Changes[0].Id = 1)
    and (VPlan.Changes[0].Op = fcoInsert) and (VPlan.Changes[0].Target = 'uCopy.dfm bvMain')
    and (VPlan.Changes[0].Prop = 'OnCustomDrawCell') and (VPlan.Changes[0].OldValue = '')
    and (VPlan.Changes[0].NewValue = 'tvMainCustomDrawCell') and VPlan.Changes[0].Checked
    and (VPlan.Changes[0].Blocked = '') and (VPlan.Notes[0] = '') and (VPlan.SourceClass = 'TcxGridDBTableView')
    and (VPlan.TargetClass = 'TcxGridDBBandedTableView'), Describe(VPlan));
  VText := Applied(VPlan, GridCopyDefaultIds(VPlan));
  CheckText('E1b the bytes: one line after the view''s last property, nothing else', VText,
    FixtureText.Replace(BAND_ANCHOR, '      DataController.Summary.SummaryGroups = <>' + NL
      + '      OnCustomDrawCell = tvMainCustomDrawCell' + NL + '      object bvMainNAME'));
  Check('E1c the anchor of E1b is in the fixture once', Length(FixtureText.Split([BAND_ANCHOR])) = 2);
  VForm := Fixture;
  VForm.DfmBytes := ToBytes(VText);
  VPlan := PlanGridCopy(VForm, TGridCopyRequest.OneEvent('tvMain', 'bvMain', 'OnCustomDrawCell'));
  Check('E1d round trip: the written bytes need no change', (Length(VPlan.Changes) = 0) and (Length(VPlan.Remarks) = 1)
    and (VPlan.Remarks[0] = 'bvMain.OnCustomDrawCell is tvMainCustomDrawCell already'), Describe(VPlan));
  Check('E1e nothing chosen, nothing made', Length(ApplyGridCopy(VPlan, nil)) = 0);

  VPlan := One('OnHeaderClick', 'bvMain', 'tvMainNAME');
  Check('E2 a column event goes to the column of the same field (case-insensitive)', (Length(VPlan.Changes) = 1)
    and (VPlan.Changes[0].Target = 'uCopy.dfm bvMainNAME') and (VPlan.Changes[0].Op = fcoInsert)
    and VPlan.Changes[0].Checked, Describe(VPlan));
  CheckText('E2b the bytes', Applied(VPlan, [1]), FixtureText.Replace(BAND_COLUMN_ANCHOR, BAND_COLUMN_ANCHOR
    + '        OnHeaderClick = tvMainNAMEHeaderClick' + NL));

  VPlan := One('OnGetDisplayText', 'bvMain', 'tvMainNAME');
  Check('E3 another handler on the target: an unchecked update', (Length(VPlan.Changes) = 1)
    and (VPlan.Changes[0].Op = fcoUpdate) and (VPlan.Changes[0].OldValue = 'bvMainNAMEGetDisplayText')
    and (VPlan.Changes[0].NewValue = 'tvMainNAMEGetDisplayText') and not VPlan.Changes[0].Checked
    and (VPlan.Changes[0].Blocked = '') and (VPlan.Notes[0] = 'replaces the handler bvMainNAMEGetDisplayText')
    and (Length(GridCopyDefaultIds(VPlan)) = 0), Describe(VPlan));
  CheckText('E3b chosen by id it replaces the value only', Applied(VPlan, [1]),
    FixtureText.Replace('OnGetDisplayText = bvMainNAMEGetDisplayText', 'OnGetDisplayText = tvMainNAMEGetDisplayText'));

  VPlan := One('OnCellDblClick');
  Check('E4 the same handler already: no change, a remark', (Length(VPlan.Changes) = 0)
    and (VPlan.Remarks[0] = 'bvMain.OnCellDblClick is tvMainCellDblClick already'), Describe(VPlan));

  VPlan := One('OnColumnHeaderClick', 'cvMain');
  Check('E5 an event the target class does not have is blocked', (Length(VPlan.Changes) = 1)
    and (VPlan.Changes[0].Blocked = 'TcxGridDBCardView has no event OnColumnHeaderClick')
    and not VPlan.Changes[0].Checked and (Length(GridCopyDefaultIds(VPlan)) = 0), Describe(VPlan));
  CheckRaises('E5b a blocked change is never applied', procedure begin ApplyGridCopy(VPlan, [1]); end, EGridCopyError,
    'change 1 is blocked');
  CheckRaises('E5c an id the plan does not have', procedure begin ApplyGridCopy(VPlan, [2]); end, EGridCopyError,
    'no change 2');
  VPlan := One('OnColumnHeaderClick');
  Check('E5d control: the same event to a banded table view is a checked insert', (Length(VPlan.Changes) = 1)
    and VPlan.Changes[0].Checked and (VPlan.Changes[0].Blocked = ''), Describe(VPlan));

  VPlan := One('OnCustomization', 'cvMain');
  Check('E6 an event both classes declare separately is unchecked', (Length(VPlan.Changes) = 1)
    and (VPlan.Changes[0].Blocked = '') and not VPlan.Changes[0].Checked
    and VPlan.Notes[0].Contains('declare OnCustomization separately'), Describe(VPlan));
  VPlan := One('Styles.OnGetContentStyle', 'cvMain');
  Check('E6b an event of the common ancestor goes to a card view', (Length(VPlan.Changes) = 1)
    and VPlan.Changes[0].Checked and (VPlan.Changes[0].Prop = 'Styles.OnGetContentStyle'), Describe(VPlan));
  VPlan := One('DataController.OnCompare', 'cvMain');
  Check('E6c a data controller event both data controllers have', (Length(VPlan.Changes) = 1)
    and VPlan.Changes[0].Checked, Describe(VPlan));

  VPlan := One('OnCustomDrawCell', 'bvMain', 'tvMainQTY', 'bvMainNAME');
  Check('E7 a handler whose body names a source column is unchecked', (Length(VPlan.Changes) = 1)
    and not VPlan.Changes[0].Checked and (VPlan.Changes[0].Blocked = '')
    and (VPlan.Notes[0] = 'the handler names tvMainQTY of the source'), Describe(VPlan));
  VForm := Fixture;
  VForm.UnitBytes := nil;
  VPlan := PlanGridCopy(VForm, TGridCopyRequest.OneEvent('tvMain', 'bvMain', 'OnCustomDrawCell', 'tvMainQTY', 'bvMainNAME'));
  Check('E7b without the unit the body is not read', (Length(VPlan.Changes) = 1) and VPlan.Changes[0].Checked,
    Describe(VPlan));

  VPlan := One('Properties.OnChange', 'bvMain', 'tvMainCODE', 'bvMainNAME');
  Check('E8 an editor event needs the same editor class', (Length(VPlan.Changes) = 1)
    and (VPlan.Changes[0].Blocked = 'the target column has the editor (none), not TcxComboBoxProperties'),
    Describe(VPlan));

  VPlan := PlanGridCopy(Fixture, TGridCopyRequest.OneEvent('tvMain', 'tvMain', 'OnHeaderClick', 'tvMainNAME', 'tvMainQTY'));
  Check('E9 between two columns of one view', (Length(VPlan.Changes) = 1) and VPlan.Changes[0].Checked
    and (VPlan.Changes[0].Target = 'uCopy.dfm tvMainQTY'), Describe(VPlan));
  CheckText('E9b the bytes', Applied(VPlan, [1]), FixtureText.Replace(
    '        OnGetDisplayText = tvMainCODEGetDisplayText' + NL + '      end',
    '        OnGetDisplayText = tvMainCODEGetDisplayText' + NL + '        OnHeaderClick = tvMainNAMEHeaderClick' + NL
    + '      end'));

  VForm := Fixture;
  VForm.DfmBytes := ToBytes(FixtureText.Replace(NL, #10));
  VPlan := PlanGridCopy(VForm, TGridCopyRequest.OneEvent('tvMain', 'bvMain', 'OnCustomDrawCell'));
  CheckText('E10 a DFM with LF line ends keeps them', Applied(VPlan, [1]),
    FixtureText.Replace(BAND_ANCHOR, '      DataController.Summary.SummaryGroups = <>' + NL
      + '      OnCustomDrawCell = tvMainCustomDrawCell' + NL + '      object bvMainNAME').Replace(NL, #10));
end;

procedure TestRefusals;
var
  VPlan: TGridCopyPlan;
begin
  CheckRaises('R1 the source has no handler for the event', procedure begin One('OnKeyDown'); end, EGridCopyError,
    'tvMain has no handler for the event OnKeyDown');
  CheckRaises('R2 no target view', procedure begin One('OnCustomDrawCell', 'nope'); end, EGridCopyError,
    'no grid view nope');
  CheckRaises('R3 the target is not a grid view', procedure begin One('OnCustomDrawCell', 'cxGrid1'); end,
    EGridCopyError, 'cxGrid1 is a TcxGrid');
  CheckRaises('R4 no target column shows the field', procedure begin One('OnCustomDrawCell', 'bvMain', 'tvMainQTY'); end,
    EGridCopyError, 'no column of bvMain shows the field QTY of tvMainQTY');
  CheckRaises('R5 source and target are one component', procedure begin One('OnCustomDrawCell', 'tvMain'); end,
    EGridCopyError, 'the same component tvMain');
  CheckRaises('R6 no such source column', procedure begin One('OnCustomDrawCell', 'bvMain', 'bvMainNAME'); end,
    EGridCopyError, 'tvMain has no column bvMainNAME');
  CheckRaises('R7 no such target column', procedure begin One('OnHeaderClick', 'bvMain', 'tvMainNAME', 'tvMainQTY'); end,
    EGridCopyError, 'bvMain has no column tvMainQTY');
  CheckRaises('R8 a view event cannot go to a column', procedure begin One('OnCustomDrawCell', 'bvMain', '', 'bvMainNAME'); end,
    EGridCopyError, 'cannot go to the column bvMainNAME');
  CheckRaises('R9 a view of a frame instance', procedure
    begin
      PlanGridCopy(TextForm(UNBOUND), TGridCopyRequest.OneEvent('uv', 'fv', 'OnMystery'));
    end, EGridCopyError, 'fv belongs to the frame instance fr');
  CheckRaises('R10 a chart view', procedure
    begin
      PlanGridCopy(TextForm(UNBOUND), TGridCopyRequest.OneEvent('uv', 'ch', 'OnMystery'));
    end, EGridCopyError, 'ch is a TcxGridDBChartView');
  CheckRaises('R11 a binary DFM', procedure
    begin
      PlanGridCopy(TextForm('TPF0'#4'TFrm'#0#0), TGridCopyRequest.OneEvent('a', 'b', 'OnX'));
    end, EDfmWriteError, '');
  VPlan := PlanGridCopy(TextForm(UNBOUND), TGridCopyRequest.OneEvent('uv', 'dv', 'DataController.OnAfterPost'));
  Check('R12 an event of the unbound data controller only is blocked on a data-bound view', (Length(VPlan.Changes) = 1)
    and (VPlan.Changes[0].Blocked = 'TcxGridDBTableView has no event DataController.OnAfterPost'), Describe(VPlan));
  VPlan := PlanGridCopy(TextForm(UNBOUND), TGridCopyRequest.OneEvent('uv', 'dv', 'DataController.OnCompare'));
  Check('R12b control: a common data controller event is checked', (Length(VPlan.Changes) = 1)
    and VPlan.Changes[0].Checked, Describe(VPlan));
  VPlan := PlanGridCopy(TextForm(UNBOUND), TGridCopyRequest.OneEvent('uv', 'dv', 'OnMystery'));
  Check('R13 an event the table does not know goes to a descendant class', (Length(VPlan.Changes) = 1)
    and VPlan.Changes[0].Checked, Describe(VPlan));
  VPlan := PlanGridCopy(TextForm(UNBOUND.Replace('dv: TcxGridDBTableView', 'dv: TcxGridDBCardView')),
    TGridCopyRequest.OneEvent('uv', 'dv', 'OnMystery'));
  Check('R13b and is unchecked for an unrelated class', (Length(VPlan.Changes) = 1) and not VPlan.Changes[0].Checked
    and (VPlan.Changes[0].Blocked = '') and VPlan.Notes[0].Contains('does not know the event OnMystery'), Describe(VPlan));
  CheckRaises('R14 a string value is not a handler', procedure
    begin
      PlanGridCopy(TextForm(UNBOUND), TGridCopyRequest.OneEvent('uv', 'dv', 'OnKeyDown'));
    end, EGridCopyError, 'no handler for the event OnKeyDown');
end;

const
  EVERYTHING_TEXT =
    'copy tvMain (TcxGridDBTableView) -> bvMain (TcxGridDBBandedTableView) in uCopy.dfm: 14 changes, 0 blocked, 2 unchecked'
    + '|[1] insert uCopy.dfm bvMain OnCustomDrawCell:  -> tvMainCustomDrawCell'
    + '|[2] insert uCopy.dfm bvMain DataController.OnCompare:  -> tvMainDataControllerCompare'
    + '|[3] insert uCopy.dfm bvMain OnColumnHeaderClick:  -> tvMainColumnHeaderClick'
    + '|[4] insert uCopy.dfm bvMain OnCustomization:  -> tvMainCustomization'
    + '|[5] insert uCopy.dfm bvMain Styles.OnGetContentStyle:  -> tvMainStylesGetContentStyle'
    + '|[6] insert uCopy.dfm bvMain Bands:  -> one band'
    + '|[7] insert uCopy.dfm bvMainCODE:  -> TcxGridDBBandedColumn CODE'
    + '|[8] insert uCopy.dfm bvMainCODE Properties.OnChange:  -> tvMainCODEPropertiesChange'
    + '|[9] insert uCopy.dfm bvMainCODE OnGetDisplayText:  -> tvMainCODEGetDisplayText'
    + '|[10] update uCopy.dfm bvMainNAME OnGetDisplayText: bvMainNAMEGetDisplayText -> tvMainNAMEGetDisplayText'
    + '|  (unchecked)|  NOTE: replaces the handler bvMainNAMEGetDisplayText'
    + '|[11] insert uCopy.dfm bvMainNAME OnHeaderClick:  -> tvMainNAMEHeaderClick'
    + '|[12] insert uCopy.dfm bvMainQTY:  -> TcxGridDBBandedColumn QTY'
    + '|[13] insert uCopy.dfm bvMainQTY OnCustomDrawCell:  -> tvMainQTYCustomDrawCell'
    + '|  (unchecked)|  NOTE: the handler names tvMainQTY of the source'
    + '|[14] insert uCopy.dfm bvMainQTY OnGetDisplayText:  -> tvMainCODEGetDisplayText';
  BAND_OLD =
    '      DataController.Summary.SummaryGroups = <>' + NL +
    '      object bvMainNAME: TcxGridDBBandedColumn' + NL +
    '        DataBinding.FieldName = ''Name''' + NL +
    '        OnGetDisplayText = bvMainNAMEGetDisplayText' + NL +
    '        Position.BandIndex = -1' + NL +
    '        Position.ColIndex = -1' + NL +
    '        Position.RowIndex = -1' + NL +
    '      end' + NL;
  BAND_NEW =
    '      DataController.Summary.SummaryGroups = <>' + NL +
    '      OnCustomDrawCell = tvMainCustomDrawCell' + NL +
    '      DataController.OnCompare = tvMainDataControllerCompare' + NL +
    '      OnColumnHeaderClick = tvMainColumnHeaderClick' + NL +
    '      OnCustomization = tvMainCustomization' + NL +
    '      Styles.OnGetContentStyle = tvMainStylesGetContentStyle' + NL +
    '      Bands = <' + NL +
    '        item' + NL +
    '        end>' + NL +
    '      object bvMainNAME: TcxGridDBBandedColumn' + NL +
    '        DataBinding.FieldName = ''Name''' + NL +
    '        OnGetDisplayText = bvMainNAMEGetDisplayText' + NL +
    '        Position.BandIndex = -1' + NL +
    '        Position.ColIndex = -1' + NL +
    '        Position.RowIndex = -1' + NL +
    '        OnHeaderClick = tvMainNAMEHeaderClick' + NL +
    '      end' + NL +
    '      object bvMainCODE: TcxGridDBBandedColumn' + NL +
    '        Caption = ''Code''' + NL +
    '        DataBinding.FieldName = ''CODE''' + NL +
    '        PropertiesClassName = ''TcxComboBoxProperties''' + NL +
    '        Properties.Items.Strings = (' + NL +
    '          ''A''' + NL +
    '          ''B'')' + NL +
    '        Properties.OnChange = tvMainCODEPropertiesChange' + NL +
    '        OnGetDisplayText = tvMainCODEGetDisplayText' + NL +
    '        Width = 80' + NL +
    '        Position.BandIndex = 0' + NL +
    '        Position.ColIndex = 1' + NL +
    '        Position.RowIndex = 0' + NL +
    '      end' + NL +
    '      object bvMainQTY: TcxGridDBBandedColumn' + NL +
    '        Caption = ''Quantity''' + NL +
    '        DataBinding.FieldName = ''QTY''' + NL +
    '        OnGetDisplayText = tvMainCODEGetDisplayText' + NL +
    '        Position.BandIndex = 0' + NL +
    '        Position.ColIndex = 2' + NL +
    '        Position.RowIndex = 0' + NL +
    '      end' + NL;
  UNIT_OLD = '    bvMainNAME: TcxGridDBBandedColumn;' + NL;
  UNIT_NEW = UNIT_OLD + '    bvMainCODE: TcxGridDBBandedColumn;' + NL + '    bvMainQTY: TcxGridDBBandedColumn;' + NL;
  CARD_OLD = '      DataController.Summary.SummaryGroups = <>' + NL + '    end' + NL + '    object cxGrid1Level1';
  CARD_NEW =
    '      DataController.Summary.SummaryGroups = <>' + NL +
    '      OnCellDblClick = tvMainCellDblClick' + NL +
    '      OnCustomDrawCell = tvMainCustomDrawCell' + NL +
    '      DataController.OnCompare = tvMainDataControllerCompare' + NL +
    '      Styles.OnGetContentStyle = tvMainStylesGetContentStyle' + NL +
    '      object cvMainCODE: TcxGridDBCardViewRow' + NL +
    '        Caption = ''Code''' + NL +
    '        DataBinding.FieldName = ''CODE''' + NL +
    '        PropertiesClassName = ''TcxComboBoxProperties''' + NL +
    '        Properties.Items.Strings = (' + NL +
    '          ''A''' + NL +
    '          ''B'')' + NL +
    '        Properties.OnChange = tvMainCODEPropertiesChange' + NL +
    '        OnGetDisplayText = tvMainCODEGetDisplayText' + NL +
    '      end' + NL +
    '      object cvMainNAME: TcxGridDBCardViewRow' + NL +
    '        DataBinding.FieldName = ''NAME''' + NL +
    '        OnGetDisplayText = tvMainNAMEGetDisplayText' + NL +
    '      end' + NL +
    '      object cvMainQTY: TcxGridDBCardViewRow' + NL +
    '        Caption = ''Quantity''' + NL +
    '        DataBinding.FieldName = ''QTY''' + NL +
    '        OnGetDisplayText = tvMainCODEGetDisplayText' + NL +
    '      end' + NL +
    '    end' + NL + '    object cxGrid1Level1';
  MIXED = 'object F: TF' + NL +
    '  object G: TcxGrid' + NL +
    '    object bv: TcxGridDBBandedTableView' + NL +
    '      Bands = <' + NL +
    '        item' + NL +
    '          Caption = ''One''' + NL +
    '        end' + NL +
    '        item' + NL +
    '          Caption = ''Two''' + NL +
    '        end>' + NL +
    '      object bvA: TcxGridDBBandedColumn' + NL +
    '        DataBinding.FieldName = ''A''' + NL +
    '        Width = 50' + NL +
    '        OnGetDisplayText = bvAGetDisplayText' + NL +
    '        Position.BandIndex = 1' + NL +
    '        Position.ColIndex = 0' + NL +
    '        Position.RowIndex = 0' + NL +
    '      end' + NL +
    '      object bvA2: TcxGridDBBandedColumn' + NL +
    '        DataBinding.FieldName = ''A''' + NL +
    '      end' + NL +
    '    end' + NL +
    '    object tv: TcxGridDBTableView' + NL +
    '    end' + NL +
    '    object b2: TcxGridDBBandedTableView' + NL +
    '    end' + NL +
    '    object uv: TcxGridTableView' + NL +
    '    end' + NL +
    '    object lv: TcxGridDBLayoutView' + NL +
    '    end' + NL +
    '  end' + NL +
    '  object tvA: TDataSource' + NL +
    '  end' + NL +
    'end' + NL;
  MIXED_UNIT = 'unit F;' + NL + 'interface' + NL + 'uses Vcl.Forms;' + NL + 'type' + NL +
    '  TF = class(TForm)' + NL +
    '    bv: TcxGridDBBandedTableView;' + NL +
    '    bvA: TcxGridDBBandedColumn;' + NL +
    '    tv: TcxGridDBTableView;' + NL +
    '    tvA: TDataSource;' + NL +
    '    procedure bvAGetDisplayText(Sender: TObject);' + NL +
    '  end;' + NL + 'implementation' + NL +
    'procedure TF.bvAGetDisplayText(Sender: TObject);' + NL + 'begin' + NL + '  tvA1 := nil;' + NL + 'end;' + NL + 'end.' + NL;

function MixedForm(const pDfm: string = MIXED): TGridCopyForm;
begin
  Result := TextForm(pDfm);
  Result.UnitFile := 'F.pas';
  Result.UnitBytes := ToBytes(MIXED_UNIT);
end;

function Everything(const pForm: TGridCopyForm; const pSource, pTarget: string): TGridCopyPlan;
begin
  Result := PlanGridCopy(pForm, TGridCopyRequest.Everything(pSource, pTarget));
end;

{ Both new texts of an applied plan: DFM, then unit ('' = the unit is not changed). }
procedure ApplyBoth(const pPlan: TGridCopyPlan; const pIds: TArray<Integer>; out pDfm, pUnit: string);
var
  VOut: TArray<TDfmwOutput>;
begin
  pDfm := '';
  pUnit := '';
  VOut := ApplyGridCopy(pPlan, pIds);
  if Length(VOut) > 0 then
  begin
    pDfm := ToText(VOut[0].NewBytes);
    DfmTextToBinary(VOut[0].NewBytes);
  end;
  if (Length(VOut) > 1) and (VOut[1].FileName = pPlan.Form.UnitFile)
    and (ToText(VOut[1].OldBytes) = ToText(pPlan.Form.UnitBytes)) then
    pUnit := ToText(VOut[1].NewBytes);
end;

function Block(const pDfm, pView: string): string;
var
  VStart, VEnd: Integer;
begin
  VStart := pDfm.IndexOf('    object ' + pView + ':');
  if VStart < 0 then
    Exit('(no block)');
  VEnd := pDfm.IndexOf(NL + '    end' + NL, VStart);
  Result := if VEnd < 0 then '(no end)' else pDfm.Substring(VStart, VEnd - VStart).Replace(NL, '|');
end;

function PlanLines(const pPlan: TGridCopyPlan): string;
begin
  Result := string.Join('|', Copy(RenderGridCopyText(pPlan), 1, MaxInt));
end;

procedure TestEverything;
var
  VPlan, VAgain: TGridCopyPlan;
  VForm: TGridCopyForm;
  VDfm, VUnit, VDfm2, VUnit2: string;
begin
  VPlan := Everything(Fixture, 'tvMain', 'bvMain');
  CheckText('A1 table view -> banded table view: the plan', PlanLines(VPlan), EVERYTHING_TEXT);
  Check('A1b the columns the plan adds, as repository rows', (Length(VPlan.Columns) = 2)
    and (VPlan.Columns[0].FormName = 'frmCopy') and (VPlan.Columns[0].ViewName = 'bvMain')
    and (VPlan.Columns[0].ColumnName = 'bvMainCODE') and (VPlan.Columns[0].FieldName = 'CODE')
    and (VPlan.Columns[0].ColumnIndex = 1) and (VPlan.Columns[0].PropertiesClassName = 'TcxComboBoxProperties')
    and VPlan.Columns[0].Properties.StartsWith('Properties.Items.Strings = (') and (VPlan.Columns[1].ColumnName = 'bvMainQTY')
    and (VPlan.Columns[1].ColumnIndex = 2) and not VPlan.Columns[1].HasEditor);
  ApplyBoth(VPlan, GridCopyDefaultIds(VPlan), VDfm, VUnit);
  CheckText('A2 the DFM bytes of the default choice', VDfm, FixtureText.Replace(BAND_OLD, BAND_NEW));
  Check('A2b the anchors of A2 and A2c are in the fixture once', (Length(FixtureText.Split([BAND_OLD])) = 2)
    and (Length(ToText(Fixture.UnitBytes).Split([UNIT_OLD])) = 2));
  CheckText('A2c the unit bytes: the two declarations after the view''s last column', VUnit,
    ToText(Fixture.UnitBytes).Replace(UNIT_OLD, UNIT_NEW));
  VForm := Fixture;
  VForm.DfmBytes := ToBytes(VDfm);
  VForm.UnitBytes := ToBytes(VUnit);
  VAgain := Everything(VForm, 'tvMain', 'bvMain');
  CheckText('A3 round trip: only the two unchecked changes are left', PlanLines(VAgain),
    'copy tvMain (TcxGridDBTableView) -> bvMain (TcxGridDBBandedTableView) in uCopy.dfm: 2 changes, 0 blocked, 2 unchecked'
    + '|[1] update uCopy.dfm bvMainNAME OnGetDisplayText: bvMainNAMEGetDisplayText -> tvMainNAMEGetDisplayText'
    + '|  (unchecked)|  NOTE: replaces the handler bvMainNAMEGetDisplayText'
    + '|[2] insert uCopy.dfm bvMainQTY OnCustomDrawCell:  -> tvMainQTYCustomDrawCell'
    + '|  (unchecked)|  NOTE: the handler names tvMainQTY of the source');
  ApplyBoth(VAgain, [1, 2], VDfm2, VUnit2);
  ApplyBoth(VPlan, SelectGridCopy(VPlan, ['all']), VDfm, VUnit);
  Check('A3b every change at once has the unchecked event in its source place; two runs end with the same lines',
    (VUnit2 = '') and VDfm.Contains('        DataBinding.FieldName = ''QTY''' + NL
    + '        OnCustomDrawCell = tvMainQTYCustomDrawCell' + NL + '        OnGetDisplayText = tvMainCODEGetDisplayText' + NL)
    and VDfm2.Contains('        Position.RowIndex = 0' + NL + '        OnCustomDrawCell = tvMainQTYCustomDrawCell' + NL
    + '      end') and (Length(VDfm) = Length(VDfm2)), Block(VDfm, 'bvMain') + ' <> ' + Block(VDfm2, 'bvMain'));
  VForm.DfmBytes := ToBytes(VDfm);
  VAgain := Everything(VForm, 'tvMain', 'bvMain');
  Check('A3c after everything nothing is left', (Length(VAgain.Changes) = 0) and (Length(VAgain.Remarks) = 1)
    and (VAgain.Remarks[0] = 'bvMain has every event and column of tvMain already'), Describe(VAgain));

  ApplyBoth(VPlan, [CODE_COLUMN_CHANGE], VDfm, VUnit);
  Check('A4 a column without its events and without the band', VDfm.Contains('          ''B'')' + NL + '        Width = 80' + NL
    + '        Position.BandIndex = 0') and not VDfm.Contains('Bands = <') and not VDfm.Contains('bvMainQTY')
    and VUnit.Contains('    bvMainCODE: TcxGridDBBandedColumn;' + NL) and not VUnit.Contains('bvMainQTY'), Block(VDfm, 'bvMain'));
  CheckRaises('A4b an event of a new column without the column', procedure begin ApplyGridCopy(VPlan, [CODE_EVENT_CHANGE]); end,
    EGridCopyError, 'change 8 is an event of the column that change 7 adds');
  ApplyBoth(VPlan, [1], VDfm, VUnit);
  Check('A4c events only: the unit is not an output', (VUnit = '') and (Length(ApplyGridCopy(VPlan, [1])) = 1));

  VPlan := Everything(Fixture, 'tvMain', 'cvMain');
  CheckText('A5 table view -> card view: the plan', PlanLines(VPlan),
    'copy tvMain (TcxGridDBTableView) -> cvMain (TcxGridDBCardView) in uCopy.dfm: 15 changes, 2 blocked, 2 unchecked'
    + '|[1] insert uCopy.dfm cvMain OnCellDblClick:  -> tvMainCellDblClick'
    + '|[2] insert uCopy.dfm cvMain OnCustomDrawCell:  -> tvMainCustomDrawCell'
    + '|[3] insert uCopy.dfm cvMain DataController.OnCompare:  -> tvMainDataControllerCompare'
    + '|[4] insert uCopy.dfm cvMain OnColumnHeaderClick:  -> tvMainColumnHeaderClick'
    + '|  BLOCKED: TcxGridDBCardView has no event OnColumnHeaderClick'
    + '|[5] insert uCopy.dfm cvMain OnCustomization:  -> tvMainCustomization'
    + '|  (unchecked)|  NOTE: TcxGridDBTableView and TcxGridDBCardView declare OnCustomization separately: compare the handler''s parameters'
    + '|[6] insert uCopy.dfm cvMain Styles.OnGetContentStyle:  -> tvMainStylesGetContentStyle'
    + '|[7] insert uCopy.dfm cvMainCODE:  -> TcxGridDBCardViewRow CODE|  NOTE: not copied: Width'
    + '|[8] insert uCopy.dfm cvMainCODE Properties.OnChange:  -> tvMainCODEPropertiesChange'
    + '|[9] insert uCopy.dfm cvMainCODE OnGetDisplayText:  -> tvMainCODEGetDisplayText'
    + '|[10] insert uCopy.dfm cvMainNAME:  -> TcxGridDBCardViewRow NAME|  NOTE: not copied: Width'
    + '|[11] insert uCopy.dfm cvMainNAME OnGetDisplayText:  -> tvMainNAMEGetDisplayText'
    + '|[12] insert uCopy.dfm cvMainNAME OnHeaderClick:  -> tvMainNAMEHeaderClick'
    + '|  BLOCKED: TcxGridDBCardViewRow has no event OnHeaderClick'
    + '|[13] insert uCopy.dfm cvMainQTY:  -> TcxGridDBCardViewRow QTY'
    + '|[14] insert uCopy.dfm cvMainQTY OnCustomDrawCell:  -> tvMainQTYCustomDrawCell'
    + '|  (unchecked)|  NOTE: the handler names tvMainQTY of the source'
    + '|[15] insert uCopy.dfm cvMainQTY OnGetDisplayText:  -> tvMainCODEGetDisplayText');
  ApplyBoth(VPlan, GridCopyDefaultIds(VPlan), VDfm, VUnit);
  CheckText('A5b the DFM bytes', VDfm, FixtureText.Replace(CARD_OLD, CARD_NEW));
  Check('A5c the anchor of A5b is in the fixture once', Length(FixtureText.Split([CARD_OLD])) = 2);
  CheckText('A5d the unit bytes: after the view when it has no column', VUnit, ToText(Fixture.UnitBytes).Replace(
    '    cvMain: TcxGridDBCardView;' + NL, '    cvMain: TcxGridDBCardView;' + NL + '    cvMainCODE: TcxGridDBCardViewRow;' + NL
    + '    cvMainNAME: TcxGridDBCardViewRow;' + NL + '    cvMainQTY: TcxGridDBCardViewRow;' + NL));

  VPlan := Everything(MixedForm, 'bv', 'tv');
  CheckText('A6 banded -> table: two columns of one field, a taken name', PlanLines(VPlan),
    'copy bv (TcxGridDBBandedTableView) -> tv (TcxGridDBTableView) in F.dfm: 3 changes, 0 blocked, 0 unchecked'
    + '|[1] insert F.dfm tvA2:  -> TcxGridDBColumn A|  NOTE: not copied: Position.BandIndex, Position.ColIndex, Position.RowIndex'
    + '|[2] insert F.dfm tvA2 OnGetDisplayText:  -> bvAGetDisplayText'
    + '|[3] insert F.dfm tvA21:  -> TcxGridDBColumn A');
  ApplyBoth(VPlan, GridCopyDefaultIds(VPlan), VDfm, VUnit);
  CheckText('A6b the block', Block(VDfm, 'tv'), '    object tv: TcxGridDBTableView|      object tvA2: TcxGridDBColumn'
    + '|        DataBinding.FieldName = ''A''|        Width = 50|        OnGetDisplayText = bvAGetDisplayText|      end'
    + '|      object tvA21: TcxGridDBColumn|        DataBinding.FieldName = ''A''|      end');
  Check('A6c declared after the view', VUnit.Contains('    tv: TcxGridDBTableView;' + NL + '    tvA2: TcxGridDBColumn;' + NL
    + '    tvA21: TcxGridDBColumn;' + NL + '    tvA: TDataSource;'), VUnit);

  VPlan := Everything(MixedForm(MIXED.Replace('    object tv: TcxGridDBTableView' + NL, '    object tv: TcxGridDBTableView' + NL
    + '      object tvX: TcxGridDBColumn' + NL + '        DataBinding.FieldName = ''a''' + NL + '      end' + NL)), 'bv', 'tv');
  CheckText('A6d a target column stands for ONE source column: the second of the field is added', PlanLines(VPlan),
    'copy bv (TcxGridDBBandedTableView) -> tv (TcxGridDBTableView) in F.dfm: 2 changes, 0 blocked, 0 unchecked'
    + '|[1] insert F.dfm tvX OnGetDisplayText:  -> bvAGetDisplayText'
    + '|[2] insert F.dfm tvA2:  -> TcxGridDBColumn A');

  VPlan := Everything(MixedForm, 'bv', 'b2');
  ApplyBoth(VPlan, GridCopyDefaultIds(VPlan), VDfm, VUnit);
  CheckText('A7 banded -> banded without bands: the source''s bands, the positions kept', Block(VDfm, 'b2'),
    '    object b2: TcxGridDBBandedTableView|      Bands = <|        item|          Caption = ''One''|        end|        item'
    + '|          Caption = ''Two''|        end>|      object b2A: TcxGridDBBandedColumn|        DataBinding.FieldName = ''A'''
    + '|        Width = 50|        OnGetDisplayText = bvAGetDisplayText|        Position.BandIndex = 1|        Position.ColIndex = 0'
    + '|        Position.RowIndex = 0|      end|      object b2A2: TcxGridDBBandedColumn|        DataBinding.FieldName = ''A''|      end');
  Check('A7b the band change says where the bands are from', VPlan.Changes[0].NewValue = 'the bands of bv', Describe(VPlan));

  VPlan := Everything(MixedForm, 'bv', 'uv');
  ApplyBoth(VPlan, GridCopyDefaultIds(VPlan), VDfm, VUnit);
  Check('A8 to an unbound view the data binding is not copied', (VPlan.Changes[0].NewValue = 'TcxGridColumn')
    and VPlan.Notes[0].StartsWith('not copied: DataBinding.FieldName, Position.BandIndex')
    and (VPlan.Columns[0].FieldName = '') and Block(VDfm, 'uv').StartsWith(
    '    object uv: TcxGridTableView|      object uvA: TcxGridColumn|        Width = 50|        OnGetDisplayText'),
    Describe(VPlan) + Block(VDfm, 'uv'));

  VPlan := Everything(MixedForm, 'bv', 'lv');
  Check('A9 a layout view gets no item', (Length(VPlan.Changes) = 2) and VPlan.Changes[0].Blocked.Contains('layout item')
    and VPlan.Changes[1].Blocked.Contains('layout item') and (Length(VPlan.Columns) = 0), Describe(VPlan));

  VPlan := Everything(TextForm(MIXED), 'bv', 'tv');
  Check('A10 without a unit a column is blocked', (Length(VPlan.Changes) = 2)
    and VPlan.Changes[0].Blocked.StartsWith('no unit'), Describe(VPlan));
  VForm := MixedForm;
  VForm.UnitBytes := ToBytes(MIXED_UNIT.Replace('TF = class', 'TOther = class'));
  VPlan := Everything(VForm, 'bv', 'tv');
  Check('A10b a unit without the form class blocks it too', (Length(VPlan.Changes) = 2)
    and VPlan.Changes[0].Blocked.Contains('TF'), Describe(VPlan));

  VPlan := Everything(MixedForm(MIXED.Replace('Width = 50', 'Hint = ''' + #233 + '''')), 'bv', 'tv');
  Check('A11 a column with text that is not ASCII is blocked, the next one is not', (Length(VPlan.Changes) = 2)
    and VPlan.Changes[0].Blocked.Contains('not ASCII') and (VPlan.Changes[1].Blocked = ''), Describe(VPlan));
  VPlan := Everything(MixedForm(MIXED.Replace('        Position.RowIndex = 0' + NL, '        Position.RowIndex = 0' + NL
    + '        object X: TThing' + NL + '        end' + NL)), 'bv', 'tv');
  Check('A11b a column with a nested object is blocked', VPlan.Changes[0].Blocked.Contains('nested object'), Describe(VPlan));

  CheckRaises('A12 a view onto itself', procedure begin Everything(Fixture, 'tvMain', 'tvMain'); end, EGridCopyError,
    'the same view tvMain');
end;

procedure TestRendering;
var
  VPlan, VOther: TGridCopyPlan;
  VLines: TArray<string>;
  VIds: TArray<Integer>;
  VJson: string;
begin
  VPlan := One('OnCustomDrawCell');
  VLines := RenderGridCopyText(VPlan);
  Check('T1 the plan id is 16 hex digits and stable', (Length(VPlan.PlanId) = PLAN_ID_LENGTH)
    and (VPlan.PlanId = One('OnCustomDrawCell').PlanId), VPlan.PlanId);
  VOther := One('OnColumnHeaderClick');
  Check('T2 another request, another plan id', VOther.PlanId <> VPlan.PlanId);
  CheckText('T3 text', string.Join('|', VLines), '# plan ' + VPlan.PlanId
    + '|copy tvMain (TcxGridDBTableView) -> bvMain (TcxGridDBBandedTableView) in uCopy.dfm: 1 changes, 0 blocked, 0 unchecked'
    + '|[1] insert uCopy.dfm bvMain OnCustomDrawCell:  -> tvMainCustomDrawCell');
  VOther := One('OnGetDisplayText', 'bvMain', 'tvMainNAME');
  CheckText('T4 text of an unchecked change with its note', string.Join('|', Copy(RenderGridCopyText(VOther), 1, MaxInt)),
    'copy tvMain (TcxGridDBTableView) -> bvMain (TcxGridDBBandedTableView) in uCopy.dfm: 1 changes, 0 blocked, 1 unchecked'
    + '|[1] update uCopy.dfm bvMainNAME OnGetDisplayText: bvMainNAMEGetDisplayText -> tvMainNAMEGetDisplayText'
    + '|  (unchecked)|  NOTE: replaces the handler bvMainNAMEGetDisplayText');
  VOther := One('OnColumnHeaderClick', 'cvMain');
  CheckText('T5 text of a blocked change', string.Join('|', Copy(RenderGridCopyText(VOther), 1, MaxInt)),
    'copy tvMain (TcxGridDBTableView) -> cvMain (TcxGridDBCardView) in uCopy.dfm: 1 changes, 1 blocked, 0 unchecked'
    + '|[1] insert uCopy.dfm cvMain OnColumnHeaderClick:  -> tvMainColumnHeaderClick'
    + '|  BLOCKED: TcxGridDBCardView has no event OnColumnHeaderClick');
  CheckText('T6 text of a plan without changes', string.Join('|', Copy(RenderGridCopyText(One('OnCellDblClick')), 1, MaxInt)),
    'copy tvMain (TcxGridDBTableView) -> bvMain (TcxGridDBBandedTableView) in uCopy.dfm: 0 changes, 0 blocked, 0 unchecked'
    + '|NOTE: bvMain.OnCellDblClick is tvMainCellDblClick already');
  VJson := RenderGridCopyJson(VPlan);
  CheckText('T7 JSON', VJson, '{"plan":"' + VPlan.PlanId + '","file":"uCopy.dfm","source":"tvMain",'
    + '"source_class":"TcxGridDBTableView","target":"bvMain","target_class":"TcxGridDBBandedTableView",'
    + '"event":"OnCustomDrawCell","count":1,"blocked":0,"unchecked":0,"changes":[{"id":1,"op":"insert",'
    + '"target":"uCopy.dfm bvMain","prop":"OnCustomDrawCell","old":"","new":"tvMainCustomDrawCell","checked":true,'
    + '"blocked":"","note":""}],"remarks":[]}');
  VIds := SelectGridCopy(VPlan, ['# plan ' + VPlan.PlanId, '', '# a comment', '1']);
  Check('T8 a selection file of this plan', (Length(VIds) = 1) and (VIds[0] = 1));
  CheckRaises('T9 a selection of another plan', procedure begin SelectGridCopy(VPlan, ['# plan 0123456789abcdef', '1']); end,
    EGridCopyError, 'the selection is of plan 0123456789abcdef');
  Check('T10 `all` leaves a blocked change out', Length(SelectGridCopy(VOther, ['all'])) = 0);
  CheckRaises('T11 a blocked change named by id', procedure begin SelectGridCopy(VOther, ['1']); end, EFrChangeSetError, '');
  VOther := One('OnGetDisplayText', 'bvMain', 'tvMainNAME');
  VIds := SelectGridCopy(VOther, ['all']);
  Check('T12 `all` takes an unchecked change', (Length(VIds) = 1) and (VIds[0] = 1));
end;

{ `--apply DIR SOURCE TARGET`: writes every change that is not blocked into DIR\uCopy.dfm and DIR\uCopy.pas (with
  backups), for the compiled-form part of run_v156_GCPM.ps1. }
procedure ApplyTo(const pDir, pSource, pTarget: string);
var
  VPlan: TGridCopyPlan;
  VLine: string;
begin
  GFixtures := pDir;
  try
    VPlan := PlanGridCopy(Fixture, TGridCopyRequest.Everything(pSource, pTarget));
    for VLine in RenderGridCopyText(VPlan) do
      Writeln(VLine);
    Writeln('WRITTEN ', Length(WriteOutputs(ApplyGridCopy(VPlan, SelectGridCopy(VPlan, ['all'])))));
  except
    on E: Exception do
    begin
      Writeln('FAILED ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end;

begin
  if (ParamCount = APPLY_TARGET_AT) and (ParamStr(APPLY_SWITCH_AT) = '--apply') then
  begin
    ApplyTo(ParamStr(APPLY_DIR_AT), ParamStr(APPLY_SOURCE_AT), ParamStr(APPLY_TARGET_AT));
    Exit;
  end;
  GFixtures := if ParamCount >= 1 then ParamStr(1)
    else TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\fixtures\fieldrepo\gridcopy'));
  try
    TestLists;
    TestOneEvent;
    TestRefusals;
    TestRendering;
    TestEverything;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unexpected ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln(Format('SUMMARY pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
