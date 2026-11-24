program FieldSelectForms;

{ Smoke test of the field dialogs of the IDE plugin (drag-lint 1.54, lane TT-DIALOG). The forms are built and shown
  OUTSIDE the desktop without taking the focus, driven through their own controls, and freed: nothing modal, nothing to
  close by hand. A watchdog thread ends the process after 60 s. One PASS/FAIL line per case, a summary line, exit code 1
  on any failure. FieldSelectForms --png FOLDER also writes a picture of each form.

  Every case that looks at a message also checks that another one is there before it: an empty status line would pass. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  Winapi.Messages,
  Winapi.CommCtrl,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.UITypes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  DRagLint.FieldRepo.Kinds in '..\..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.DfmReadSelection in '..\..\..\src\sql\DRagLint.FieldRepo.DfmReadSelection.pas',
  DragLint.Plugin.FieldSelectModel in '..\..\..\src\delphi-plugin\DragLint.Plugin.FieldSelectModel.pas',
  DragLint.Plugin.FieldSelectDialog in '..\..\..\src\delphi-plugin\DragLint.Plugin.FieldSelectDialog.pas';

const
  OFF_SCREEN = -30000;
  WATCHDOG_MS = 60000;
  PPI_100 = 96;
  PPI_200 = 192;
  NAME_COLUMN = 150;
  ROW_QTY = 1;
  ROW_PRICE = 2;
  ROW_TOTAL = 3;
  ROW_BAR = 4;

var
  GPass, GFail: Integer;
  GThemed: string;

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
  Check(pName, pGot = pWant, 'got <' + pGot.Replace(sLineBreak, '|') + '> want <' + pWant.Replace(sLineBreak, '|') + '>');
end;

{ Shown where nobody sees it, without activation. }
procedure ShowHidden(pForm: TCustomForm);
begin
  TForm(pForm).Position := poDesigned;
  TForm(pForm).Scaled := False; // a 200 % form stays one on a 100 % screen
  pForm.SetBounds(OFF_SCREEN, OFF_SCREEN, pForm.Width, pForm.Height);
  ShowWindow(pForm.Handle, SW_SHOWNOACTIVATE);
  TForm(pForm).Visible := True;
  Application.ProcessMessages;
end;

procedure SavePicture(pForm: TCustomForm; const pName: string);
var
  VBitmap: TBitmap;
  VPng: TPngImage;
begin
  if ParamStr(1) <> '--png' then
    Exit;
  VBitmap := TBitmap.Create;
  VPng := TPngImage.Create;
  try
    VBitmap.SetSize(pForm.Width, pForm.Height);
    TForm(pForm).PaintTo(VBitmap.Canvas.Handle, 0, 0);
    VPng.Assign(VBitmap);
    VPng.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(2)) + pName + '.png');
  finally
    VPng.Free;
    VBitmap.Free;
  end;
end;

function ButtonOf(pForm: TComponent; const pCaption: string): TButton;
var
  VI: Integer;
begin
  Result := nil;
  for VI := 0 to pForm.ComponentCount - 1 do
    if (pForm.Components[VI] is TButton) and (TButton(pForm.Components[VI]).Caption = pCaption) then
      Exit(TButton(pForm.Components[VI]));
end;

{ What a click on the check box does. }
procedure ClickBox(pList: TListView; pRow: Integer);
begin
  ListView_SetCheckState(pList.Handle, pRow, not pList.Items[pRow].Checked);
  Application.ProcessMessages;
end;

function ChecksOf(pList: TListView): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 0 to pList.Items.Count - 1 do
    Result := Result + (if ListView_GetCheckState(pList.Handle, VI) <> 0 then '+' else '-');
end;

function Field(const pName: string; pKind: TFrFieldKind; const pBody: string = ''): TFrSelectionField;
begin
  Result.Name := pName;
  Result.Kind := pKind;
  Result.SourceKey := '';
  Result.Body := pBody;
end;

function Dataset: TFsDataset;
var
  VPersistent: TFsPersistent;
begin
  Result := Default(TFsDataset);
  Result.Name := 'qryOrders';
  Result.DatasetClass := 'TFDQuery';
  Result.TableName := 'ORDERS';
  Result.TableFields := [Field('ID', frkData), Field('QTY', frkData), Field('PRICE', frkData),
    Field('TOTAL', frkCalc, '{{TOTAL}}.Value := {{QTY}}.Value * {{PRICE}}.Value;'), Field('BAR', frkGraphical)];
  VPersistent.FieldName := 'ID';
  VPersistent.Component := 'qryOrdersID';
  VPersistent.Kind := frkData;
  VPersistent.TableName := 'ORDERS';
  VPersistent.Column := 'ID';
  Result.Persistent := [VPersistent];
end;

{ Every control lies inside its parent and no button hides another: the layout of a PPI. }
function LayoutProblem(pForm: TCustomForm): string;
var
  VI, VJ: Integer;
  VFirst, VOther: TControl;
  VRect: TRect;
begin
  Result := '';
  for VI := 0 to pForm.ComponentCount - 1 do
    if pForm.Components[VI] is TControl then
    begin
      VFirst := TControl(pForm.Components[VI]);
      if (VFirst.Parent <> nil) and not VFirst.Parent.ClientRect.Contains(VFirst.BoundsRect) then
        Exit(VFirst.ClassName + ' is outside of its parent');
      for VJ := VI + 1 to pForm.ComponentCount - 1 do
        if pForm.Components[VJ] is TControl then
        begin
          VOther := TControl(pForm.Components[VJ]);
          if (VOther.Parent = VFirst.Parent) and IntersectRect(VRect, VFirst.BoundsRect, VOther.BoundsRect) then
            Exit(VFirst.ClassName + ' overlaps ' + VOther.ClassName);
        end;
    end;
end;

procedure TestFields(pPpi: Integer);
var
  VSelection: TFieldSelection;
  VForm: TFsFieldsForm;
  VName: string;
begin
  VName := 'F' + IntToStr(pPpi);
  VSelection := TFieldSelection.Create(Dataset);
  VForm := TFsFieldsForm.CreateFor('drag-lint: Select Fields of qryOrders', VSelection, pPpi);
  try
    ShowHidden(VForm);
    CheckText(VName + ' layout', LayoutProblem(VForm), '');
    Check(VName + ' scaled', (VForm.CurrentPPI = pPpi) and (VForm.List.Columns[0].Width = MulDiv(NAME_COLUMN, pPpi, PPI_100)),
      Format('%d %d', [VForm.CurrentPPI, VForm.List.Columns[0].Width]));
    CheckText(VName + ' pre-checked', ChecksOf(VForm.List), '+----');
    CheckText(VName + ' status', VForm.Status.Caption, '1 of 4 fields selected: 0 to add, 0 to remove');
    SavePicture(VForm, 'fields-' + IntToStr(pPpi));
    ClickBox(VForm.List, ROW_TOTAL);
    CheckText(VName + ' a calc field adds what it needs', ChecksOf(VForm.List), '++++-');
    CheckText(VName + ' and says so', VForm.Status.Caption,
      '4 of 4 fields selected: 3 to add, 0 to remove' + sLineBreak + 'TOTAL needs QTY, PRICE: added');
    ClickBox(VForm.List, ROW_QTY);
    CheckText(VName + ' a needed field stays', ChecksOf(VForm.List), '++++-');
    Check(VName + ' and says so', ContainsText(VForm.Status.Caption, 'QTY stays: TOTAL needs it'), VForm.Status.Caption);
    ClickBox(VForm.List, ROW_BAR);
    CheckText(VName + ' a locked row stays', ChecksOf(VForm.List), '++++-');
    ClickBox(VForm.List, ROW_TOTAL);
    ClickBox(VForm.List, ROW_PRICE);
    CheckText(VName + ' uncheck', ChecksOf(VForm.List), '++---');
    ButtonOf(VForm, 'Unselect all').Click;
    CheckText(VName + ' unselect all', ChecksOf(VForm.List), '-----');
    ButtonOf(VForm, 'Preview...').Click;
    Check(VName + ' an empty selection is refused', (VForm.ModalResult = mrNone) and ContainsText(VForm.Status.Caption, 'at least one'),
      VForm.Status.Caption);
    ButtonOf(VForm, 'Select all').Click;
    CheckText(VName + ' select all', ChecksOf(VForm.List), '++++-');
    ButtonOf(VForm, 'Preview...').Click;
    Check(VName + ' preview closes', VForm.ModalResult = mrOk);
    CheckText(VName + ' names', VSelection.Names, 'ID,QTY,PRICE,TOTAL');
    Check(VName + ' Esc and Enter', ButtonOf(VForm, 'Cancel').Cancel and ButtonOf(VForm, 'Preview...').Default);
  finally
    VForm.Free;
    VSelection.Free;
  end;
end;

function Change(pId: Integer; const pOp, pBlocked: string; pChecked: Boolean): TFsChange;
begin
  Result.Id := pId;
  Result.Op := pOp;
  Result.Target := 'uOrders.dfm qryOrdersX' + IntToStr(pId);
  Result.Prop := '';
  Result.OldText := 'old';
  Result.NewText := 'new';
  Result.Blocked := pBlocked;
  Result.Checked := pChecked;
end;

procedure TestChanges(pPpi: Integer; pWarnings: Boolean);
const
  ID_BLOCKED = 3;
var
  VPlan: TFsPlan;
  VForm: TFsChangesForm;
  VName: string;
begin
  VName := 'C' + IntToStr(pPpi) + (if pWarnings then 'w' else '');
  VPlan := Default(TFsPlan);
  VPlan.PlanId := 'abc';
  VPlan.Changes := [Change(1, 'insert', '', True), Change(2, 'delete', '', False), Change(ID_BLOCKED, 'delete', 'used', False)];
  if pWarnings then
    VPlan.Warnings := ['one', 'two'];
  VForm := TFsChangesForm.CreateFor('drag-lint: Select Fields -- changes', VPlan, pPpi);
  try
    ShowHidden(VForm);
    CheckText(VName + ' layout', LayoutProblem(VForm), '');
    CheckText(VName + ' defaults', ChecksOf(VForm.List), '+--');
    CheckText(VName + ' status', VForm.Status.Caption, '1 of 3 changes checked');
    SavePicture(VForm, 'changes-' + VName);
    ClickBox(VForm.List, ID_BLOCKED - 1);
    CheckText(VName + ' a blocked change stays', ChecksOf(VForm.List), '+--');
    Check(VName + ' and says why', ContainsText(VForm.Status.Caption, 'BLOCKED: used'), VForm.Status.Caption);
    ButtonOf(VForm, 'Uncheck all').Click;
    Check(VName + ' nothing to apply', (ChecksOf(VForm.List) = '---') and not ButtonOf(VForm, 'Apply').Enabled);
    ButtonOf(VForm, 'Check all').Click;
    CheckText(VName + ' check all', ChecksOf(VForm.List), '++-');
    ButtonOf(VForm, 'Apply').Click;
    Check(VName + ' apply closes', VForm.ModalResult = mrOk);
    CheckText(VName + ' the plan holds the checks', VForm.Plan.SelectFileText, '# plan abc'#13#10'1'#13#10'2'#13#10);
    Check(VName + ' Enter never writes', not ButtonOf(VForm, 'Apply').Default and ButtonOf(VForm, 'Cancel').Cancel);
  finally
    VForm.Free;
  end;
end;

procedure TestDatasets(pPpi: Integer);
var
  VForm: TFsDatasetForm;
  VOther: TFsDataset;
  VName: string;
begin
  VName := 'D' + IntToStr(pPpi);
  VOther := Dataset;
  VOther.Name := 'qryJoin';
  VOther.TableName := '';
  VOther.Unresolved := 'the SQL reads 2 tables: ORDERS TOOLS';
  VForm := TFsDatasetForm.CreateFor('drag-lint: Read Fields from Dataset', [Dataset, VOther], pPpi);
  try
    ShowHidden(VForm);
    CheckText(VName + ' layout', LayoutProblem(VForm), '');
    SavePicture(VForm, 'datasets-' + IntToStr(pPpi));
    Check(VName + ' rows', (VForm.List.Items.Count = 2) and (VForm.List.Items[1].SubItems[1] = VOther.Unresolved));
    VForm.List.ItemIndex := 1;
    ButtonOf(VForm, 'OK').Click;
    Check(VName + ' OK', (VForm.ModalResult = mrOk) and (VForm.List.ItemIndex = 1));
    VForm.ModalResult := mrNone;
    VForm.List.ItemIndex := -1;
    ButtonOf(VForm, 'OK').Click;
    Check(VName + ' nothing picked', VForm.ModalResult = mrNone);
  finally
    VForm.Free;
  end;
end;

{ The dialogs as the plugin calls them: modal, closed by the theme callback's timer message. }
procedure CancelSoon(pForm: TCustomForm; pClass: TCustomFormClass);
var
  VClose: TThreadProcedure;
begin
  GThemed := GThemed + pClass.ClassName + ' ';
  TForm(pForm).Position := poDesigned;
  pForm.SetBounds(OFF_SCREEN, OFF_SCREEN, pForm.Width, pForm.Height);
  VClose := procedure
    begin
      pForm.ModalResult := mrCancel;
    end;
  TThread.ForceQueue(nil, VClose);
end;

procedure TestModal;
var
  VSelection: TFieldSelection;
  VPlan: TFsPlan;
  VIndex: Integer;
begin
  VPlan := Default(TFsPlan);
  VPlan.Changes := [Change(1, 'insert', '', True)];
  VSelection := TFieldSelection.Create(Dataset);
  try
    Check('M1 cancelled', not PickDataset('x', [Dataset], CancelSoon, VIndex) and not SelectFields('x', VSelection, CancelSoon)
      and not ConfirmChanges('x', VPlan, CancelSoon));
  finally
    VSelection.Free;
  end;
  CheckText('M2 each form is themed as its own class', GThemed, 'TFsDatasetForm TFsFieldsForm TFsChangesForm ');
end;

begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(WATCHDOG_MS);
      ExitProcess(2);
    end).Start;
  try
    Application.Initialize;
    TestFields(PPI_100);
    TestFields(PPI_200);
    TestChanges(PPI_100, False);
    TestChanges(PPI_100, True);
    TestChanges(PPI_200, True);
    TestDatasets(PPI_100);
    TestDatasets(PPI_200);
    TestModal;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('EXCEPTION ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
  Flush(Output);
  ExitProcess(if GFail > 0 then 1 else 0);
end.
