unit ConvRules.WorkListTab;

{ The Work list tab (editor-1270 Task 3, owner ruling 2026-10-11: a NEW tab
  beside Convert): what a Convert run's converted units still use from the old
  components (apply/1 pas_uses[], engine 1.27.0). A code-built VCL panel, no
  .dfm. Every decision -- parsing, filter, sort, cells, summary, the
  double-click outcome -- lives in ConvRules.WorkList (pure, pinned by
  ConvRulesModelTests); this unit only renders and wires them. Editor-only: it
  is NOT in the tests' compile closure. }

interface

uses
  System.SysUtils
  , System.Classes
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.CheckLst
  , Vcl.ComCtrls
  , Vcl.ExtCtrls
  , ConvRules.WorkList  // dl:unit ConvRules.WorkList accepted -- WORK_NO_RUN is the tab's initial summary, the text WorkListSummary returns for wlsNoRun
  ;

type
  /// <summary>The Work list tab: a status filter, a unit filter, a text filter,
  /// the rows of the LAST Convert run and its summary line.</summary>
  /// <remarks>Rows arrive through ShowRun, on the UI thread, once per finished run;
  /// a new run REPLACES the list (MergeRun keyed by run id), never mixes with it.
  /// A double-click copies '&lt;file&gt;(&lt;line&gt;)' to the clipboard and says so on
  /// the status line (WorkGoTo); it opens nothing.</remarks>
  TWorkListTab = class(TPanel)
  private
    FSetStatus: TProc<string, Boolean>;
    FRun      : TWorkRun;
    FShown    : TArray<TPasUseRow>;
    FStatuses : TCheckListBox;
    FUnits    : TComboBox;
    FText     : TEdit;
    FSummary  : TLabel;
    FGrid     : TListView;
    procedure BuildFilters;
    procedure BuildGrid;
    procedure FilterChanged(Sender: TObject);
    procedure GridDblClick(Sender: TObject);
    procedure GridCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    function CurrentFilter: TWorkFilter;
    procedure RefreshUnits;
    procedure RefreshGrid;
  protected
    /// <summary>Fills the status filter (work statuses checked) and the unit filter
    /// the first time the tab gets a window.</summary>
    procedure CreateWnd; override;
  public
    /// <summary>Builds the tab; it shows WORK_NO_RUN until the first ShowRun.</summary>
    /// <param name="AOwner">The owning component (the main form).</param>
    /// <param name="ASetStatus">Writes the host's status line: (text, is-error); must
    /// not be nil.</param>
    constructor Create(AOwner: TComponent; const ASetStatus: TProc<string, Boolean>); reintroduce;
    /// <summary>Replaces the list with a finished run's Work list.</summary>
    /// <param name="ARun">The run (ConvRules.ConvertRunner.WorkRunOf).</param>
    /// <remarks>Filters are kept; the unit filter falls back to All when its unit is
    /// not in the new run.</remarks>
    procedure ShowRun(const ARun: TWorkRun);
    /// <summary>The summary line (WorkListSummary of the shown run) plus the shown
    /// row count when the filter hides rows.</summary>
    /// <returns>The text the tab's summary label shows.</returns>
    function SummaryText: string;
  end;

implementation

uses
  System.IOUtils
  , System.StrUtils  // MatchText: the default status checks
  , System.UITypes  // TFontStyles / TColors: GridCustomDrawItem's font
  , Vcl.Graphics
  , Vcl.Clipbrd
  ;

const
  FILTER_HEIGHT   = 30;
  STATUS_LIST_W   = 640;
  UNIT_COMBO_W    = 200;
  TEXT_EDIT_W     = 160;
  LABEL_GAP       = 6;
  UNIT_ALL        = '(all units)';
  SHOWN_FMT       = '%s; %d shown';
  COL_WIDTHS: array[0..7] of Integer = (120, 100, 170, 140, 70, 110, 80, 200);

constructor TWorkListTab.Create(AOwner: TComponent; const ASetStatus: TProc<string, Boolean>);
begin
  inherited Create(AOwner);
  FSetStatus:= ASetStatus;
  BevelOuter:= bvNone;
  Caption   := '';
  FRun      := Default(TWorkRun);
  FRun.State:= wlsNoRun;
  BuildFilters;
  BuildGrid;
end;

procedure TWorkListTab.BuildFilters;
var
  LRow  : TPanel;
  LLabel: TLabel;
begin
  LRow:= TPanel.Create(Self);
  LRow.Parent    := Self;
  LRow.Align     := alTop;
  LRow.Height    := FILTER_HEIGHT;
  LRow.BevelOuter:= bvNone;

  // Six statuses and '(other)' side by side; the work statuses and '(other)' start checked (DefaultWorkFilter).
  FStatuses:= TCheckListBox.Create(Self);
  FStatuses.Parent          := LRow;
  FStatuses.Align           := alLeft;
  FStatuses.AlignWithMargins:= True;
  FStatuses.Width           := STATUS_LIST_W;
  FStatuses.Columns         := Length(WorkFilterEntries);
  FStatuses.OnClickCheck    := FilterChanged; // the items need a window: CreateWnd fills them

  FUnits:= TComboBox.Create(Self);
  FUnits.Parent          := LRow;
  FUnits.Left            := High(Word); // right of the status list
  FUnits.Align           := alLeft;
  FUnits.AlignWithMargins:= True;
  FUnits.Width           := UNIT_COMBO_W;
  FUnits.Style           := csDropDownList;
  FUnits.OnChange        := FilterChanged;

  LLabel:= TLabel.Create(Self);
  LLabel.Parent          := LRow;
  LLabel.Left            := High(Word);
  LLabel.Align           := alLeft;
  LLabel.AlignWithMargins:= True;
  LLabel.Margins.Left    := LABEL_GAP;
  LLabel.Layout          := tlCenter;
  LLabel.Caption         := 'Member / instance:';

  FText:= TEdit.Create(Self);
  FText.Parent          := LRow;
  FText.Left            := High(Word);
  FText.Align           := alLeft;
  FText.AlignWithMargins:= True;
  FText.Width           := TEXT_EDIT_W;
  FText.OnChange        := FilterChanged;

  FSummary:= TLabel.Create(Self);
  FSummary.Parent          := Self;
  FSummary.Name            := 'LblWorkSummary';
  FSummary.Align           := alTop;
  FSummary.Top             := LRow.Top + LRow.Height; // below the filter row
  FSummary.AlignWithMargins:= True;
  FSummary.Caption         := WORK_NO_RUN;
end;

procedure TWorkListTab.CreateWnd;
begin
  inherited CreateWnd;
  // A list box's / combo box's items live in its window, which does not exist while the
  // constructor runs (the host sets Parent after Create). Filled ONCE: a VCL style switch
  // recreates the windows and VCL carries the items (and their checks) across.
  if FStatuses.Items.Count > 0 then
    Exit;
  for var LStatus: string in WorkFilterEntries do
    FStatuses.Checked[FStatuses.Items.Add(LStatus)]:= MatchText(LStatus, DefaultWorkFilter.Statuses);
  RefreshUnits;
end;

procedure TWorkListTab.BuildGrid;
var
  LCaptions: TArray<string>;
begin
  FGrid:= TListView.Create(Self);
  FGrid.Parent          := Self;
  FGrid.Align           := alClient;
  FGrid.AlignWithMargins:= True;
  FGrid.ViewStyle       := vsReport;
  FGrid.ReadOnly        := True;
  FGrid.RowSelect       := True;
  FGrid.HideSelection   := False;
  LCaptions:= WorkColumns;
  for var I: Integer:= 0 to High(LCaptions) do
  begin
    var LCol: TListColumn:= FGrid.Columns.Add;
    LCol.Caption:= LCaptions[I];
    LCol.Width  := COL_WIDTHS[I];
  end;
  FGrid.OnDblClick      := GridDblClick;
  FGrid.OnCustomDrawItem:= GridCustomDrawItem;
end;

function TWorkListTab.CurrentFilter: TWorkFilter;
var
  LChecked: TArray<string>;
  LUnit   : string;
begin
  LChecked:= nil;
  for var I: Integer:= 0 to FStatuses.Items.Count - 1 do
    if FStatuses.Checked[I] then
      LChecked:= LChecked + [FStatuses.Items[I]];
  LUnit:= if FUnits.ItemIndex > 0 then FUnits.Items[FUnits.ItemIndex] else '';
  // WorkFilterOf: nothing checked shows nothing; '(other)' covers unknown statuses.
  Result:= WorkFilterOf(LChecked, LUnit, FText.Text);
end;

procedure TWorkListTab.RefreshUnits;
var
  LKeep: string;
begin
  LKeep:= if FUnits.ItemIndex > 0 then FUnits.Items[FUnits.ItemIndex] else '';
  FUnits.Items.BeginUpdate;
  try
    FUnits.Items.Clear;
    FUnits.Items.Add(UNIT_ALL);
    for var LUnit: string in WorkUnits(FRun.Rows) do
      FUnits.Items.Add(LUnit);
  finally
    FUnits.Items.EndUpdate;
  end; // try
  FUnits.ItemIndex:= FUnits.Items.IndexOf(LKeep);
  if FUnits.ItemIndex < 0 then
    FUnits.ItemIndex:= 0;
end;

procedure TWorkListTab.RefreshGrid;
var
  LCells: TArray<string>;
  LItem : TListItem;
begin
  FShown:= FilterRows(FRun.Rows, CurrentFilter);
  SortRows(FShown);
  FGrid.Items.BeginUpdate;
  try
    FGrid.Items.Clear;
    for var LRow: TPasUseRow in FShown do
    begin
      LCells:= RowDisplay(LRow);
      LItem:= FGrid.Items.Add;
      LItem.Caption:= LCells[0];
      for var I: Integer:= 1 to High(LCells) do
        LItem.SubItems.Add(LCells[I]);
    end;
  finally
    FGrid.Items.EndUpdate;
  end; // try
  FSummary.Caption:= SummaryText;
end;

function TWorkListTab.SummaryText: string;
begin
  Result:= WorkListSummary(FRun.Rows, FRun.State);
  if (FRun.State = wlsRows) and (Length(FShown) <> Length(FRun.Rows)) then
    Result:= Format(SHOWN_FMT, [Result, Length(FShown)]);
end;

procedure TWorkListTab.ShowRun(const ARun: TWorkRun);
begin
  var LRows: TArray<TPasUseRow>:= MergeRun(FRun.Rows, ARun.Rows, ARun.RunId); // only this run's rows, ever
  FRun:= ARun;
  FRun.Rows:= LRows;
  RefreshUnits;
  RefreshGrid;
end;

procedure TWorkListTab.FilterChanged(Sender: TObject);
begin
  RefreshGrid;
end;

procedure TWorkListTab.GridCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw:= True;
  if (Item = nil) or (Item.Index > High(FShown)) then
    Exit;
  case WorkStyleOf(FShown[Item.Index].Status) of
    wsBoldRed:
      begin
        Sender.Canvas.Font.Style:= [fsBold];
        // SetError's colour (clRed in both themes); a selected row keeps the selection colour.
        if not (cdsSelected in State) then
          Sender.Canvas.Font.Color:= clRed;
      end;
    wsBold:
      Sender.Canvas.Font.Style:= [fsBold];
    wsPlain:
      Sender.Canvas.Font.Style:= [];
  end;
end;

procedure TWorkListTab.GridDblClick(Sender: TObject);
var
  LRow  : TPasUseRow;
  LCount: Integer;
  LGoTo : TWorkGoTo;
begin
  if (FGrid.Selected = nil) or (FGrid.Selected.Index > High(FShown)) then
    Exit;
  LRow  := FShown[FGrid.Selected.Index];
  LCount:= 0;
  try
    if TFile.Exists(LRow.UnitPas) then
      LCount:= Length(TFile.ReadAllLines(LRow.UnitPas));
  except
    on E: EInOutError do
    begin
      FSetStatus(LRow.UnitPas + ' could not be read: ' + E.Message, True);
      Exit;
    end;
    on E: EFileStreamError do
    begin
      FSetStatus(LRow.UnitPas + ' could not be read: ' + E.Message, True);
      Exit;
    end;
  end; // try
  LGoTo:= WorkGoTo(LRow, TFile.Exists(LRow.UnitPas), LCount);
  if not LGoTo.Ok then
  begin
    FSetStatus(LGoTo.Status, True);
    Exit;
  end;
  try
    Clipboard.AsText:= LGoTo.Clip;
  except
    on E: EClipboardException do
    begin
      FSetStatus(LGoTo.Clip + ' was not copied -- another program has the clipboard open (' + E.Message + ')', True);
      Exit;
    end;
  end; // try
  FSetStatus(LGoTo.Status, False);
end;

end.
