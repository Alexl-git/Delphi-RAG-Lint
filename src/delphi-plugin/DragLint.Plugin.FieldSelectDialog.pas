unit DragLint.Plugin.FieldSelectDialog;

{ drag-lint 1.54 -- lane TT-DIALOG: the field dialogs of the IDE plugin (FR-2 and section 3 of the design
  2026-11-22-field-repository-v2-design.md): pick a dataset, select its fields, confirm a change set. The logic is in
  DragLint.Plugin.FieldSelectModel.

  Code-built forms, no .dfm: CreateScaledNew skips the streaming that would raise EResNotFound and starts at the PPI of
  the screen, so every measure goes through ScaleValue. The theme is passed in: with ToolsAPI in this unit
  tests\plugin\fieldselect\FieldSelectForms.dpr could not build it. }

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Vcl.Forms,
  DragLint.Plugin.FieldSelectModel;

type
  /// <summary>Gives a form the colours of the IDE (DragLint.Plugin.Theme.ApplyIdeTheme).</summary>
  /// <param name="pForm">The form.</param>
  /// <param name="pClass">Its class.</param>
  TFsTheme = procedure(pForm: TCustomForm; pClass: TCustomFormClass);

  /// <summary>A resizable dialog: a list that fills it, a status line, a row of buttons.</summary>
  /// <remarks>Main thread only.</remarks>
  TFsListForm = class(TForm)
  strict private
    FList: TListView;
    FStatus: TLabel;
    FButtons: TPanel;
    FHint: TLabel;
  strict protected
    /// <summary>True while the form itself changes the list.</summary>
    FUpdating: Boolean;
    /// <summary>Adds a column.</summary>
    /// <param name="pCaption">Caption.</param>
    /// <param name="pWidth">Width at 96 PPI.</param>
    procedure AddColumn(const pCaption: string; pWidth: Integer);
    /// <summary>Adds a row.</summary>
    /// <param name="pCells">Its texts, one per column.</param>
    procedure AddRow(const pCells: TArray<string>);
    /// <summary>Adds a button to the row of buttons.</summary>
    /// <param name="pCaption">Caption.</param>
    /// <param name="pAlign">alLeft = right of the left ones; alRight = left of the right ones.</param>
    /// <param name="pClick">Click handler.</param>
    /// <returns>The button, owned by the form.</returns>
    function AddButton(const pCaption: string; pAlign: TAlign; pClick: TNotifyEvent): TButton;
    /// <summary>Adds a read-only text between the list and the status line.</summary>
    /// <param name="pText">The text.</param>
    /// <returns>The memo, owned by the form.</returns>
    function AddBottomMemo(const pText: string): TMemo;
    /// <summary>Closes with mrCancel.</summary>
    /// <param name="pSender">The button.</param>
    procedure CancelClick(pSender: TObject);
  public
    /// <summary>Builds the empty form.</summary>
    /// <param name="pTitle">Caption.</param>
    /// <param name="pHint">Text above the list; may hold line breaks.</param>
    /// <param name="pPpi">PPI to build for; 0 = that of the screen.</param>
    constructor CreateFor(const pTitle, pHint: string; pPpi: Integer);
    /// <summary>The list.</summary>
    property List: TListView read FList;
    /// <summary>The status line.</summary>
    property Status: TLabel read FStatus;
  end;

  /// <summary>Picks one dataset of a form.</summary>
  TFsDatasetForm = class(TFsListForm)
  strict private
    procedure PickClick(pSender: TObject);
  public
    /// <summary>Builds the form.</summary>
    /// <param name="pTitle">Caption.</param>
    /// <param name="pDatasets">The datasets.</param>
    /// <param name="pPpi">PPI to build for; 0 = that of the screen.</param>
    constructor CreateFor(const pTitle: string; const pDatasets: TArray<TFsDataset>; pPpi: Integer);
  end;

  /// <summary>Selects the fields of one dataset.</summary>
  TFsFieldsForm = class(TFsListForm)
  strict private
    FSelection: TFieldSelection;
    FUsageIcons: TImageList;
    procedure BuildUsageIcons;
    procedure ItemChecked(pSender: TObject; pItem: TListItem);
    procedure SelectAllClick(pSender: TObject);
    procedure UnselectAllClick(pSender: TObject);
    procedure PreviewClick(pSender: TObject);
    procedure ShowState(const pMessage: string);
  public
    /// <summary>Builds the form.</summary>
    /// <param name="pTitle">Caption.</param>
    /// <param name="pSelection">The selection; the caller owns it and it outlives the form.</param>
    /// <param name="pPpi">PPI to build for; 0 = that of the screen.</param>
    constructor CreateFor(const pTitle: string; pSelection: TFieldSelection; pPpi: Integer);
  end;

  /// <summary>Confirms a change set.</summary>
  TFsChangesForm = class(TFsListForm)
  strict private
    FPlan: TFsPlan;
    FApply: TButton;
    procedure ItemChecked(pSender: TObject; pItem: TListItem);
    procedure CheckAllClick(pSender: TObject);
    procedure UncheckAllClick(pSender: TObject);
    procedure ApplyClick(pSender: TObject);
    procedure ShowState(const pMessage: string);
  public
    /// <summary>Builds the form.</summary>
    /// <param name="pTitle">Caption.</param>
    /// <param name="pPlan">The dry run.</param>
    /// <param name="pPpi">PPI to build for; 0 = that of the screen.</param>
    constructor CreateFor(const pTitle: string; const pPlan: TFsPlan; pPpi: Integer);
    /// <summary>The plan with the checks the user left.</summary>
    property Plan: TFsPlan read FPlan;
  end;

/// <summary>Asks for one dataset of a form.</summary>
/// <param name="pTitle">Caption.</param>
/// <param name="pDatasets">The datasets.</param>
/// <param name="pTheme">Theme of the IDE.</param>
/// <param name="pIndex">The picked dataset.</param>
/// <returns>False = cancelled.</returns>
/// <remarks>Modal. Main thread only.</remarks>
function PickDataset(const pTitle: string; const pDatasets: TArray<TFsDataset>; pTheme: TFsTheme; out pIndex: Integer): Boolean;

/// <summary>Lets the user select the fields of a dataset.</summary>
/// <param name="pTitle">Caption.</param>
/// <param name="pSelection">The selection; holds what the user selected.</param>
/// <param name="pTheme">Theme of the IDE.</param>
/// <returns>False = cancelled.</returns>
/// <remarks>Modal. Main thread only.</remarks>
function SelectFields(const pTitle: string; pSelection: TFieldSelection; pTheme: TFsTheme): Boolean;

/// <summary>Lets the user confirm a change set.</summary>
/// <param name="pTitle">Caption.</param>
/// <param name="pPlan">The dry run; holds the checks the user left.</param>
/// <param name="pTheme">Theme of the IDE.</param>
/// <returns>False = cancelled; nothing may be written.</returns>
/// <remarks>Modal. Main thread only.</remarks>
function ConfirmChanges(const pTitle: string; var pPlan: TFsPlan; pTheme: TFsTheme): Boolean;

implementation

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  Vcl.Graphics,
  DRagLint.FieldRepo.Kinds;

const
  FORM_WIDTH = 760;
  FORM_HEIGHT = 520;
  FORM_MIN_WIDTH = 480;
  FORM_MIN_HEIGHT = 300;
  SPACING = 8;
  BUTTON_WIDTH = 100;
  BUTTON_HEIGHT = 26;
  MEMO_HEIGHT = 90;
  ICON_SIZE = 16;
  COL_NARROW = 70;
  COL_NAME = 150;
  COL_KIND = 90;
  COL_OLD = 100;
  COL_TARGET = 180;
  COL_WIDE = 220;
  HINT_DATASETS = 'Choose the dataset.';
  HINT_FIELDS = 'Checked fields become persistent fields of the dataset. A calculated field or a lookup adds the fields it needs.' +
    sLineBreak + 'Preview shows every change; nothing is written before you apply it.';
  HINT_CHANGES = 'Only the checked changes are written. A blocked change cannot be written.';
  CAPTION_CANCEL = 'Cancel';
  NOTE_BLOCKED = 'BLOCKED: ';

{ ---- base ---- }

constructor TFsListForm.CreateFor(const pTitle, pHint: string; pPpi: Integer);
begin
  inherited CreateScaledNew(nil, pPpi);
  Caption := pTitle;
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu, biMaximize];
  Position := poScreenCenter;
  ClientWidth := ScaleValue(FORM_WIDTH);
  ClientHeight := ScaleValue(FORM_HEIGHT);
  Constraints.MinWidth := ScaleValue(FORM_MIN_WIDTH);
  Constraints.MinHeight := ScaleValue(FORM_MIN_HEIGHT);
  Padding.SetBounds(ScaleValue(SPACING), ScaleValue(SPACING), ScaleValue(SPACING), ScaleValue(SPACING));

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.Align := alTop;
  FHint.WordWrap := True;
  FHint.ShowAccelChar := False;
  FHint.Caption := pHint;

  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FButtons.BevelOuter := bvNone;
  FButtons.ShowCaption := False;
  FButtons.Height := ScaleValue(BUTTON_HEIGHT);

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AlignWithMargins := True;
  FStatus.WordWrap := True;
  FStatus.ShowAccelChar := False;
  FStatus.Caption := ' ';
  FStatus.Top := 0; // above the buttons

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(0, ScaleValue(SPACING), 0, ScaleValue(SPACING));
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ShowHint := True;
  ActiveControl := FList;
end;

procedure TFsListForm.AddColumn(const pCaption: string; pWidth: Integer);
var
  VColumn: TListColumn;
begin
  VColumn := FList.Columns.Add;
  VColumn.Caption := pCaption;
  VColumn.Width := ScaleValue(pWidth);
end;

procedure TFsListForm.AddRow(const pCells: TArray<string>);
var
  VItem: TListItem;
  VI: Integer;
begin
  VItem := FList.Items.Add;
  VItem.Caption := pCells[0];
  for VI := 1 to High(pCells) do
    VItem.SubItems.Add(pCells[VI]);
end;

function TFsListForm.AddButton(const pCaption: string; pAlign: TAlign; pClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FButtons;
  Result.Caption := pCaption;
  Result.Width := ScaleValue(BUTTON_WIDTH);
  { alRight: each new one goes to the left of those before it; alLeft: to the right of them }
  Result.Left := if pAlign = alRight then 0 else FButtons.ClientWidth;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(if pAlign = alRight then ScaleValue(SPACING) else 0, 0,
    if pAlign = alRight then 0 else ScaleValue(SPACING), 0);
  Result.Align := pAlign;
  Result.OnClick := pClick;
end;

function TFsListForm.AddBottomMemo(const pText: string): TMemo;
begin
  Result := TMemo.Create(Self);
  Result.Parent := Self;
  Result.Align := alBottom;
  Result.Height := ScaleValue(MEMO_HEIGHT);
  Result.ReadOnly := True;
  Result.ScrollBars := ssVertical;
  Result.Lines.Text := pText;
  Result.Top := 0; // above the status line
end;

procedure TFsListForm.CancelClick(pSender: TObject);
begin
  ModalResult := mrCancel;
end;

{ ---- datasets ---- }

constructor TFsDatasetForm.CreateFor(const pTitle: string; const pDatasets: TArray<TFsDataset>; pPpi: Integer);
var
  VDataset: TFsDataset;
begin
  inherited CreateFor(pTitle, HINT_DATASETS, pPpi);
  AddColumn('Dataset', COL_WIDE);
  AddColumn('Table', COL_NAME);
  AddColumn('Note', COL_WIDE);
  for VDataset in pDatasets do
    AddRow([VDataset.Caption, VDataset.TableName, VDataset.Unresolved]);
  List.OnDblClick := PickClick;
  if List.Items.Count > 0 then
    List.ItemIndex := 0;
  AddButton(CAPTION_CANCEL, alRight, CancelClick).Cancel := True;
  AddButton('OK', alRight, PickClick).Default := True;
end;

procedure TFsDatasetForm.PickClick(pSender: TObject);
begin
  if List.ItemIndex >= 0 then
    ModalResult := mrOk;
end;

{ ---- fields ---- }

constructor TFsFieldsForm.CreateFor(const pTitle: string; pSelection: TFieldSelection; pPpi: Integer);
var
  VI: Integer;
begin
  inherited CreateFor(pTitle, HINT_FIELDS, pPpi);
  FSelection := pSelection;
  List.Checkboxes := True;
  BuildUsageIcons;
  AddColumn('Field', COL_NAME);
  AddColumn('Kind', COL_KIND);
  AddColumn('Used in', COL_NAME);
  AddColumn('In the form', COL_NAME);
  AddColumn('Note', COL_WIDE);
  FUpdating := True;
  try
    for VI := 0 to FSelection.Count - 1 do
    begin
      AddRow([FSelection[VI].Name, FrKindName(FSelection[VI].Kind), UsageText(FSelection[VI].Used),
        FSelection[VI].Component, FSelection[VI].Locked]);
      List.Items[VI].ImageIndex := UsageIcon(FSelection[VI].Used);
    end;
  finally
    FUpdating := False;
  end;
  List.OnItemChecked := ItemChecked;
  AddButton('Select all', alLeft, SelectAllClick);
  AddButton('Unselect all', alLeft, UnselectAllClick);
  AddButton(CAPTION_CANCEL, alRight, CancelClick).Cancel := True;
  AddButton('Preview...', alRight, PreviewClick).Default := True;
  ShowState(FSelection.MissingNote);
end;

{ One flat icon per set of use kinds (UsageIcon 0 .. USAGE_ICON_COUNT - 1): a 2 x 2 block of squares, one per kind,
  drawn only when the kind is in the set; no animation, no resource file, scaled to the PPI of the form. }
procedure TFsFieldsForm.BuildUsageIcons;
const
  KIND_COLORS: array[TFsUseKind] of TColor = ($C07020, $40A040, $2080E0, $808080);
  MASK_COLOR = clFuchsia;
var
  VSize, VHalf, VIcon: Integer;
  VKind: TFsUseKind;
  VBitmap: TBitmap;
begin
  VSize := ScaleValue(ICON_SIZE);
  VHalf := VSize div 2;
  FUsageIcons := TImageList.Create(Self);
  FUsageIcons.Width := VSize;
  FUsageIcons.Height := VSize;
  for VIcon := 0 to USAGE_ICON_COUNT - 1 do
  begin
    VBitmap := TBitmap.Create;
    try
      VBitmap.SetSize(VSize, VSize);
      VBitmap.Canvas.Brush.Color := MASK_COLOR;
      VBitmap.Canvas.FillRect(Rect(0, 0, VSize, VSize));
      for VKind := Low(TFsUseKind) to High(TFsUseKind) do
        if VIcon and (1 shl Ord(VKind)) <> 0 then
        begin
          VBitmap.Canvas.Brush.Color := KIND_COLORS[VKind];
          VBitmap.Canvas.FillRect(Rect((Ord(VKind) mod 2) * VHalf + 1, (Ord(VKind) div 2) * VHalf + 1,
            (Ord(VKind) mod 2 + 1) * VHalf - 1, (Ord(VKind) div 2 + 1) * VHalf - 1));
        end;
      FUsageIcons.AddMasked(VBitmap, MASK_COLOR);
    finally
      VBitmap.Free;
    end;
  end;
  List.SmallImages := FUsageIcons;
end;

{ The check marks and the status line of the selection. }
procedure TFsFieldsForm.ShowState(const pMessage: string);
var
  VI: Integer;
begin
  FUpdating := True;
  try
    for VI := 0 to FSelection.Count - 1 do
      if List.Items[VI].Checked <> FSelection[VI].Checked then
        List.Items[VI].Checked := FSelection[VI].Checked;
  finally
    FUpdating := False;
  end;
  Status.Caption := FSelection.Summary + (if pMessage = '' then '' else sLineBreak + pMessage);
end;

procedure TFsFieldsForm.ItemChecked(pSender: TObject; pItem: TListItem);
var
  VMessage: string;
begin
  if FUpdating or (pItem.Checked = FSelection[pItem.Index].Checked) then
    Exit;
  FSelection.SetChecked(pItem.Index, pItem.Checked, VMessage);
  ShowState(VMessage);
end;

procedure TFsFieldsForm.SelectAllClick(pSender: TObject);
begin
  FSelection.SetAll(True);
  ShowState('');
end;

procedure TFsFieldsForm.UnselectAllClick(pSender: TObject);
begin
  FSelection.SetAll(False);
  ShowState('');
end;

procedure TFsFieldsForm.PreviewClick(pSender: TObject);
begin
  if FSelection.Refusal = '' then
    ModalResult := mrOk
  else
    ShowState(FSelection.Refusal);
end;

{ ---- changes ---- }

constructor TFsChangesForm.CreateFor(const pTitle: string; const pPlan: TFsPlan; pPpi: Integer);
var
  VChange: TFsChange;
begin
  inherited CreateFor(pTitle, HINT_CHANGES, pPpi);
  FPlan := pPlan;
  List.Checkboxes := True;
  AddColumn('Change', COL_NARROW);
  AddColumn('Target', COL_TARGET);
  AddColumn('Property', COL_KIND);
  AddColumn('Old', COL_OLD);
  AddColumn('New', COL_NAME);
  AddColumn('Note', COL_NAME);
  FUpdating := True;
  try
    for VChange in FPlan.Changes do
      AddRow([VChange.Op, VChange.Target, VChange.Prop, VChange.OldText, VChange.NewText,
        if VChange.Blocked = '' then '' else NOTE_BLOCKED + VChange.Blocked]);
  finally
    FUpdating := False;
  end;
  List.OnItemChecked := ItemChecked;
  if Length(FPlan.Warnings) > 0 then
    AddBottomMemo(string.Join(sLineBreak, FPlan.Warnings));
  AddButton('Check all', alLeft, CheckAllClick);
  AddButton('Uncheck all', alLeft, UncheckAllClick);
  AddButton(CAPTION_CANCEL, alRight, CancelClick).Cancel := True;
  FApply := AddButton('Apply', alRight, ApplyClick);
  ShowState('');
end;

procedure TFsChangesForm.ShowState(const pMessage: string);
var
  VI: Integer;
begin
  FUpdating := True;
  try
    for VI := 0 to High(FPlan.Changes) do
      if List.Items[VI].Checked <> FPlan.Changes[VI].Checked then
        List.Items[VI].Checked := FPlan.Changes[VI].Checked;
  finally
    FUpdating := False;
  end;
  FApply.Enabled := FPlan.CheckedCount > 0;
  Status.Caption := Format('%d of %d changes checked', [FPlan.CheckedCount, Length(FPlan.Changes)]) +
    (if pMessage = '' then '' else sLineBreak + pMessage);
end;

procedure TFsChangesForm.ItemChecked(pSender: TObject; pItem: TListItem);
var
  VBlocked: string;
begin
  if FUpdating or (pItem.Checked = FPlan.Changes[pItem.Index].Checked) then
    Exit;
  VBlocked := FPlan.Changes[pItem.Index].Blocked;
  FPlan.Changes[pItem.Index].Checked := pItem.Checked and (VBlocked = '');
  ShowState(if VBlocked = '' then '' else NOTE_BLOCKED + VBlocked);
end;

procedure TFsChangesForm.CheckAllClick(pSender: TObject);
begin
  FPlan.SetAll(True);
  ShowState('');
end;

procedure TFsChangesForm.UncheckAllClick(pSender: TObject);
begin
  FPlan.SetAll(False);
  ShowState('');
end;

procedure TFsChangesForm.ApplyClick(pSender: TObject);
begin
  ModalResult := mrOk;
end;

{ ---- the dialogs ---- }

function RunForm(pForm: TFsListForm; pTheme: TFsTheme): Boolean;
begin
  if Assigned(pTheme) then
    pTheme(pForm, TCustomFormClass(pForm.ClassType));
  Result := pForm.ShowModal = mrOk;
end;

function PickDataset(const pTitle: string; const pDatasets: TArray<TFsDataset>; pTheme: TFsTheme; out pIndex: Integer): Boolean;
var
  VForm: TFsDatasetForm;
begin
  VForm := TFsDatasetForm.CreateFor(pTitle, pDatasets, 0);
  try
    Result := RunForm(VForm, pTheme);
    pIndex := VForm.List.ItemIndex;
  finally
    VForm.Free;
  end;
end;

function SelectFields(const pTitle: string; pSelection: TFieldSelection; pTheme: TFsTheme): Boolean;
var
  VForm: TFsFieldsForm;
begin
  VForm := TFsFieldsForm.CreateFor(pTitle, pSelection, 0);
  try
    Result := RunForm(VForm, pTheme);
  finally
    VForm.Free;
  end;
end;

function ConfirmChanges(const pTitle: string; var pPlan: TFsPlan; pTheme: TFsTheme): Boolean;
var
  VForm: TFsChangesForm;
begin
  VForm := TFsChangesForm.CreateFor(pTitle, pPlan, 0);
  try
    Result := RunForm(VForm, pTheme);
    if Result then
      pPlan := VForm.Plan;
  finally
    VForm.Free;
  end;
end;

end.
