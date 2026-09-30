unit ConvRules.ConvertTab;

{ The Convert tab (spec 2026-09-29, part 2): the checked rule books, in list
  order, applied in place to a list of source units, each unit backed up once
  to .BCK<N> first. A code-built VCL panel, no .dfm. The decisions live in
  ConvRules.ConvertRun (pure, pinned by ConvRulesModelTests) and the execution
  in ConvRules.ConvertRunner (on a worker thread); this unit only renders and
  wires them. The main form parents it on its own tab sheet and supplies a
  TConvertHost. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Types
  , Winapi.Windows // TOwnerDrawState / odSelected: SourcesDrawItem's signature
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.CheckLst
  , Vcl.ComCtrls
  , Vcl.ExtCtrls
  , ConvRules.Engine
  , ConvRules.ConvertRun
  , ConvRules.ConvertRunner
  ;

type
  /// <summary>What the Convert tab needs from the window that hosts it.</summary>
  /// <remarks>Every callback is invoked on the UI thread only; the worker
  /// thread sees nothing of the host but ExePath and the values copied into
  /// its TConvertJob before it starts.</remarks>
  TConvertHost = record
    /// <summary>The drag-lint.exe the conversion runs.</summary>
    ExePath       : string;
    /// <summary>The --db list: project DB FIRST (the engine's primary), then
    /// the libraries.</summary>
    GetDbs        : TFunc<TArray<string>>;
    /// <summary>The project index the units must be in, reindexed before each
    /// unit and after each book.</summary>
    GetProjectDb  : TFunc<string>;
    /// <summary>The .dproj that owns the project index -- ProjectFileForDb of
    /// it, NEVER the Unit Rules Destination (an `index --project` of another
    /// project would re-scope the editor's project DB). Convert refuses when
    /// the file does not exist.</summary>
    GetProjectFile: TFunc<string>;
    /// <summary>The folder whose *.rules files are the book list.</summary>
    GetRulesFolder: TFunc<string>;
    /// <summary>The path of the book open in the editor ('' = none saved yet).</summary>
    GetOpenBook   : TFunc<string>;
    /// <summary>The unsaved-changes guard; False = the user cancelled.</summary>
    ConfirmOpenBookSaved: TFunc<Boolean>;
    /// <summary>Feeds .pas paths to the Unit Rules harvest without switching tabs.</summary>
    FeedHarvest   : TProc<TArray<string>>;
    /// <summary>Writes the status line: (text, is-error).</summary>
    SetStatus     : TProc<string, Boolean>;
    /// <summary>Called with True when a run starts and False when its results
    /// are in; may be nil. The host disables what must not change mid-run
    /// (File > Save / Save As / Curate).</summary>
    RunStateChanged: TProc<Boolean>;
  end;

  /// <summary>The Convert tab: a checklist of rule books, a list of source
  /// units, Convert / Cancel, progress and a results grid.</summary>
  /// <remarks>
  /// A run executes on an anonymous worker thread with its OWN TEngineAdapter;
  /// FEngineProbe (capability probe, project-unit listing) is used on the UI
  /// thread only. The worker reaches the controls only through TThread.Queue.
  /// Cancel is honoured between units (never mid-unit). The host must not
  /// close while Running is True: destroying the tab mid-run only raises the
  /// cancel flag -- the worker then reads freed memory for its cancel poll and
  /// its queued updates target freed controls, which is why the main form
  /// refuses to close while a run is in progress rather than relying on this.
  /// </remarks>
  TConvertTab = class(TPanel)  // dl:ok god-class@0c2d, high-response@0c2d -- REVIEWED 2026-09-29 a code-built panel: most methods are one control's builder or click handler; the decisions live in ConvRules.ConvertRun / ConvertRunner
    private
      FHost           : TConvertHost;
      FEngineProbe    : TEngineAdapter;
      FEntries        : TArray<TBookEntry>; // the book checklist, application order
      FUnitRulesOk    : Boolean;            // engine reports apply_unit_rules
      FProbed         : Boolean;            // FUnitRulesOk has been asked this session
      FRunning        : Boolean;
      FCancelRequested: Boolean;            // written on the UI thread, polled by the worker
      FNotes          : TArray<string>;     // the current run's pre-flight notes (for the report)
      FRunRows        : TArray<TConvertRow>;// the current run's rows as they arrived
      FRunRulesFolder : string;             // the rules folder when Convert was pressed: the report goes THERE
      FIndexed        : TArray<string>;     // file paths in the project index (valid while FIndexKnown)
      FIndexKnown     : Boolean;            // False = the index could not be read: flag nothing
      FLockable       : TArray<TControl>;   // disabled while a run is in progress
      FTopPanel       : TPanel;
      FBottomPanel    : TPanel;
      FBooks          : TCheckListBox;
      FSources        : TListBox;
      FBtnConvert     : TButton;
      FBtnCancel      : TButton;
      FProgress       : TProgressBar;
      FResults        : TListView;
      function NewButton(AParent: TWinControl; const ACaption: string; AAlign: TAlign; AOnClick: TNotifyEvent): TButton;
      procedure BuildBooks;
      procedure BuildSources;
      procedure BuildRun;
      procedure PanelResize(Sender: TObject);
      /// <summary>Repaints FBooks from FEntries. A unit-rules-only book the
      /// engine cannot apply is shown disabled and is never left checked.</summary>
      procedure ShowBooks;
      procedure BooksClickCheck(Sender: TObject);
      procedure MoveBook(ADelta: Integer);
      procedure MoveUpClick(Sender: TObject);
      procedure MoveDownClick(Sender: TObject);
      procedure CheckAll(AChecked: Boolean);
      procedure CheckAllClick(Sender: TObject);
      procedure CheckNoneClick(Sender: TObject);
      procedure RefreshClick(Sender: TObject);
      procedure AddClick(Sender: TObject);
      procedure DeleteClick(Sender: TObject);
      procedure ConvertClick(Sender: TObject);
      procedure CancelClick(Sender: TObject);
      procedure SetRunning(ARunning: Boolean);
      /// <summary>Appends one results-grid row.</summary>
      /// <param name="ACells">Book, Unit, Status, Edits, Remaining, Backup, Backup .dfm, Note -- the grid's columns in order.</param>
      procedure AddResultRow(const ACells: array of string);
      procedure AddRow(const ARow: TConvertRow);
      /// <summary>Worker thread: hands one finished row to the UI thread.</summary>
      /// <param name="ARow">The row, copied into the queued call.</param>
      /// <param name="ADone">Rows so far; becomes the progress position.</param>
      procedure QueueRow(const ARow: TConvertRow; ADone: Integer);
      /// <summary>UI thread, after the worker ends: report file, re-harvest,
      /// summary status.</summary>
      /// <param name="AJob">The job that ran (books x units, for the totals).</param>
      /// <param name="AProblem">'' or what went wrong outside the rows.</param>
      /// <param name="AStopAt">Index into AJob.Units of the first unit a cancel
      /// kept from running; -1 when every unit was reached.</param>
      /// <param name="AFinalIndex">The closing reindex: 'ok', 'FAILED: ...', or
      /// 'not run' when the worker stopped before it.</param>
      procedure RunFinished(const AJob: TConvertJob; const AProblem: string; AStopAt: Integer; const AFinalIndex: string);
      /// <summary>Writes the run report (UTF-8, no BOM) beside the books that ran.</summary>
      /// <param name="ANotReached">Units a cancel kept from running.</param>
      /// <param name="AFinalIndex">The closing reindex's outcome (see RunFinished).</param>
      /// <param name="APath">The report's path.</param>
      /// <param name="AError">'' or why it was not written.</param>
      /// <returns>True when written.</returns>
      function WriteReport(const ANotReached: TArray<string>; const AFinalIndex: string; out APath, AError: string): Boolean;
      /// <summary>Re-reads the project index's file paths into FIndexed and
      /// repaints the source list.</summary>
      /// <param name="AError">'' on success, else why the index could not be read.</param>
      /// <returns>False = FIndexKnown is now False and no row is flagged.</returns>
      function ReadIndex(out AError: string): Boolean;
      /// <summary>Draws a source row: an unindexed unit in SetError's red, bold,
      /// with ' -- not in the project index' appended to the DISPLAYED text.</summary>
      /// <param name="Control">FSources.</param>
      /// <param name="Index">The row.</param>
      /// <param name="Rect">The row's client rectangle.</param>
      /// <param name="State">Selected / focused state.</param>
      procedure SourcesDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
      /// <summary>The source-list status line: count, and how many are not indexed.</summary>
      /// <returns>The status text.</returns>
      function SourcesSummary: string;
    public
      /// <summary>Builds the tab's controls; nothing is listed until RefreshBooks.</summary>
      /// <param name="AOwner">Owner (the main form).</param>
      /// <param name="AHost">The host callbacks; copied.</param>
      constructor Create(AOwner: TComponent; const AHost: TConvertHost); reintroduce;
      /// <summary>Raises the cancel flag of a run still in progress, frees the probe.</summary>
      destructor Destroy; override;
      /// <summary>Re-reads the *.rules files of the host's rules folder into the
      /// checklist, keeping the user's order and checks for books still there
      /// (new books are appended unchecked). Does nothing while a run is in
      /// progress.</summary>
      /// <remarks>The engine capability probe (~0.5 s) runs on the first call
      /// only; the Refresh button re-probes.</remarks>
      procedure RefreshBooks;
      /// <summary>Adds the .pas files APaths stand for (see ExpandSources) to the
      /// source list, once each, and feeds them to the Unit Rules harvest.
      /// Refused, with an error status, while a run is in progress.</summary>
      /// <param name="APaths">Dropped or picked .pas / .dpr / .dproj / folder paths.</param>
      procedure AddSources(const APaths: TArray<string>);
      /// <summary>Re-reads which listed units are in the project index and
      /// repaints the flags; a failure goes to the status line and flags nothing.</summary>
      /// <remarks>One engine call (~0.9 s); skipped while the list is empty.</remarks>
      procedure RefreshIndex;
      /// <summary>True from Convert until the worker's results are in.</summary>
      property Running: Boolean read FRunning;
  end;

implementation

uses
  System.IOUtils
  , System.StrUtils
  , Vcl.Dialogs
  , Vcl.Graphics
  ;

const
  // 45/40 (the plan's split) left the source list 0 px high in a 720 px window.
  TOP_PERCENT     = 40;   // books pane: share of the tab's height
  BOTTOM_PERCENT  = 30;   // run pane: share of the tab's height
  PERCENT         = 100;
  BTN_COL_WIDTH   = 84;   // the books' button column
  BTN_WIDTH       = 75;
  CANCEL_WIDTH    = 170;  // fits 'Cancelling after this unit...'
  ROW_HEIGHT      = 31;   // a one-button row
  COL_BOOK_W      = 110;
  COL_UNIT_W      = 110;
  COL_STATUS_W    = 120;
  COL_NUMBER_W    = 50;
  COL_BACKUP_W    = 120;  // Backup and Backup .dfm
  COL_NOTE_W      = 300;
  PROBLEM_HEAD    = 200;  // chars of engine output quoted in a status line
  TEXT_INSET_X    = 2;    // source row text inset, px
  CAP_CANCEL      = 'Cancel';
  CAP_CANCELLING  = 'Cancelling after this unit...';
  STATUS_NOT_REACHED = 'not reached (cancelled)'; // a unit a cancel kept from running
  CAPABILITY_UNIT_RULES = 'apply_unit_rules';

{ TConvertTab }

constructor TConvertTab.Create(AOwner: TComponent; const AHost: TConvertHost);
begin
  inherited Create(AOwner);
  FHost:= AHost;
  BevelOuter:= bvNone;
  Caption   := '';
  FEngineProbe:= TEngineAdapter.Create(FHost.ExePath, FHost.GetDbs());
  BuildBooks;
  BuildRun;
  BuildSources;
  OnResize:= PanelResize;
end;

destructor TConvertTab.Destroy;
begin
  if FRunning then
    FCancelRequested:= True; // see the class remarks: the host refuses to close mid-run
  FEngineProbe.Free;
  inherited Destroy;
end;

function TConvertTab.NewButton(AParent: TWinControl; const ACaption: string; AAlign: TAlign; AOnClick: TNotifyEvent): TButton;
begin
  Result:= TButton.Create(Self);
  Result.Parent          := AParent;
  Result.Caption         := ACaption;
  Result.Width           := BTN_WIDTH;
  // Beyond every sibling BEFORE aligning: VCL orders same-align controls by
  // position, so a default 0 would stack each new button in front of the last.
  Result.SetBounds(High(Word), High(Word), BTN_WIDTH, Result.Height);
  Result.Align           := AAlign;
  Result.AlignWithMargins:= True;
  Result.OnClick         := AOnClick;
  FLockable:= FLockable + [Result];
end;

procedure TConvertTab.BuildBooks;
var
  LLabel: TLabel;
  LCol  : TPanel;
begin
  FTopPanel:= TPanel.Create(Self);
  FTopPanel.Parent    := Self;
  FTopPanel.Align     := alTop;
  FTopPanel.BevelOuter:= bvNone;

  LLabel:= TLabel.Create(Self);
  LLabel.Parent          := FTopPanel;
  LLabel.Align           := alTop;
  LLabel.AlignWithMargins:= True;
  LLabel.Transparent     := True; // TGraphicControl: opaque, it paints clBtnFace under a dark style
  LLabel.Caption         := 'Rule books (checked = applied, top to bottom)';

  LCol:= TPanel.Create(Self);
  LCol.Parent    := FTopPanel;
  LCol.Align     := alRight;
  LCol.Width     := BTN_COL_WIDTH;
  LCol.BevelOuter:= bvNone;
  NewButton(LCol, 'Move up'   , alTop, MoveUpClick);
  NewButton(LCol, 'Move down' , alTop, MoveDownClick);
  NewButton(LCol, 'Check all' , alTop, CheckAllClick);
  NewButton(LCol, 'Check none', alTop, CheckNoneClick);
  NewButton(LCol, 'Refresh'   , alTop, RefreshClick);

  FBooks:= TCheckListBox.Create(Self);
  FBooks.Parent          := FTopPanel;
  FBooks.Align           := alClient;
  FBooks.AlignWithMargins:= True;
  FBooks.OnClickCheck    := BooksClickCheck;
  FLockable:= FLockable + [FBooks];
end;

procedure TConvertTab.BuildSources;
var
  LMid  : TPanel;
  LLabel: TLabel;
  LRow  : TPanel;
begin
  LMid:= TPanel.Create(Self);
  LMid.Parent    := Self;
  LMid.Align     := alClient;
  LMid.BevelOuter:= bvNone;

  LLabel:= TLabel.Create(Self);
  LLabel.Parent          := LMid;
  LLabel.Align           := alTop;
  LLabel.AlignWithMargins:= True;
  LLabel.Transparent     := True; // TGraphicControl: opaque, it paints clBtnFace under a dark style
  LLabel.Caption         := 'Source units -- drop .pas / .dpr / .dproj / folders here, or Add...';

  LRow:= TPanel.Create(Self);
  LRow.Parent    := LMid;
  LRow.Align     := alBottom;
  LRow.Height    := ROW_HEIGHT;
  LRow.BevelOuter:= bvNone;
  NewButton(LRow, 'Add...', alLeft, AddClick);
  NewButton(LRow, 'Delete', alLeft, DeleteClick);

  FSources:= TListBox.Create(Self);
  FSources.Parent          := LMid;
  FSources.Align           := alClient;
  FSources.AlignWithMargins:= True;
  FSources.MultiSelect     := True;
  FSources.Style           := lbOwnerDrawFixed; // flags unindexed units (SourcesDrawItem)
  FSources.OnDrawItem      := SourcesDrawItem;
  FLockable:= FLockable + [FSources];
end;

procedure TConvertTab.BuildRun;
var
  LRow: TPanel;
begin
  FBottomPanel:= TPanel.Create(Self);
  FBottomPanel.Parent    := Self;
  FBottomPanel.Align     := alBottom;
  FBottomPanel.BevelOuter:= bvNone;

  LRow:= TPanel.Create(Self);
  LRow.Parent    := FBottomPanel;
  LRow.Align     := alTop;
  LRow.Height    := ROW_HEIGHT;
  LRow.BevelOuter:= bvNone;
  FBtnConvert:= NewButton(LRow, 'Convert', alLeft, ConvertClick);
  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent          := LRow;
  FBtnCancel.SetBounds(High(Word), 0, CANCEL_WIDTH, FBtnCancel.Height); // right of Convert (see NewButton)
  FBtnCancel.Align           := alLeft;
  FBtnCancel.AlignWithMargins:= True;
  FBtnCancel.Caption         := CAP_CANCEL;
  FBtnCancel.Enabled         := False;
  FBtnCancel.OnClick         := CancelClick;
  FProgress:= TProgressBar.Create(Self);
  FProgress.Parent          := LRow;
  FProgress.Align           := alClient;
  FProgress.AlignWithMargins:= True;

  FResults:= TListView.Create(Self);
  FResults.Parent          := FBottomPanel;
  FResults.Align           := alClient;
  FResults.AlignWithMargins:= True;
  FResults.ViewStyle       := vsReport;
  FResults.ReadOnly        := True;
  FResults.RowSelect       := True;
  FResults.HideSelection   := False;
  FResults.Columns.Add.Caption:= 'Book';
  FResults.Columns[0].Width   := COL_BOOK_W;
  FResults.Columns.Add.Caption:= 'Unit';
  FResults.Columns[1].Width   := COL_UNIT_W;
  var LCol: TListColumn:= FResults.Columns.Add;
  LCol.Caption:= 'Status';
  LCol.Width  := COL_STATUS_W;
  LCol:= FResults.Columns.Add;
  LCol.Caption:= 'Edits';
  LCol.Width  := COL_NUMBER_W;
  LCol:= FResults.Columns.Add;
  LCol.Caption:= 'Remaining';
  LCol.Width  := COL_NUMBER_W;
  LCol:= FResults.Columns.Add;
  LCol.Caption:= 'Backup';
  LCol.Width  := COL_BACKUP_W;
  LCol:= FResults.Columns.Add;
  LCol.Caption:= 'Backup .dfm';
  LCol.Width  := COL_BACKUP_W;
  LCol:= FResults.Columns.Add;
  LCol.Caption:= 'Note';
  LCol.Width  := COL_NOTE_W;
end;

procedure TConvertTab.PanelResize(Sender: TObject);
begin
  FTopPanel.Height   := ClientHeight * TOP_PERCENT div PERCENT;
  FBottomPanel.Height:= ClientHeight * BOTTOM_PERCENT div PERCENT;
end;

procedure TConvertTab.RefreshBooks;
var
  Folder: string;
  Files : TArray<string>;
  Next  : TArray<TBookEntry>;
  Errs  : TArray<string>;

  function KindOf(const APath: string; out AKind: TBookKind): Boolean;
  begin
    try
      AKind:= BookKindOfText(TFile.ReadAllText(APath));
      Result:= True;
    except
      on E: Exception do
      begin
        Errs:= Errs + [ExtractFileName(APath) + ': ' + E.Message];
        Result:= False;
      end;
    end; // try
  end;

  function Listed(const APath: string): Boolean;
  begin
    Result:= False;
    for var LEntry: TBookEntry in Next do
      if SameText(LEntry.Path, APath) then
        Exit(True);
  end;

begin
  if FRunning then
    Exit; // the run holds its own copy of the books; keep the list it started from
  if not FProbed then
  begin
    FUnitRulesOk:= FEngineProbe.HasCapability(CAPABILITY_UNIT_RULES);
    FProbed     := True;
  end;
  Folder:= FHost.GetRulesFolder();
  Files := nil;
  if (Folder <> '') and TDirectory.Exists(Folder) then
    Files:= TDirectory.GetFiles(Folder, '*.rules');
  Next:= nil;
  Errs:= nil;
  // The user's order and checks survive a refresh, keyed by path: list order IS
  // application order, so a tab switch must not quietly reorder the run.
  for var LOld: TBookEntry in FEntries do
    if MatchText(LOld.Path, Files) then
    begin
      var E: TBookEntry:= LOld;
      if KindOf(E.Path, E.Kind) then
        Next:= Next + [E];
    end;
  for var LFile: string in Files do
    if not Listed(LFile) then
    begin
      var E: TBookEntry;
      E.Path   := LFile;
      E.Checked:= False;
      if KindOf(LFile, E.Kind) then
        Next:= Next + [E];
    end;
  FEntries:= Next;
  ShowBooks;
  if Length(Errs) > 0 then
    FHost.SetStatus(Format('%d rule book(s) could not be read and are not listed: %s', [Length(Errs), string.Join(' | ', Errs)]), True);
end;

procedure TConvertTab.ShowBooks;
var
  LSel: Integer;
begin
  LSel:= FBooks.ItemIndex;
  FBooks.Items.BeginUpdate;
  try
    FBooks.Items.Clear;
    for var I: Integer:= 0 to High(FEntries) do
    begin
      var LSuffix : string := '';
      var LEnabled: Boolean:= True;
      case FEntries[I].Kind of
        bkEmpty:
          LSuffix:= '  (empty)';
        bkUnitsOnly:
          if not FUnitRulesOk then
          begin
            LSuffix := '  (unit rules: engine support pending)';
            LEnabled:= False;
          end;
        bkMixed:
          if not FUnitRulesOk then
            LSuffix:= '  (unit rules not applied: engine)';
      end; // case
      if not LEnabled then
        FEntries[I].Checked:= False;
      FBooks.Items.Add(ExtractFileName(FEntries[I].Path) + LSuffix);
      FBooks.Checked[I]    := FEntries[I].Checked;
      FBooks.ItemEnabled[I]:= LEnabled;
    end;
  finally
    FBooks.Items.EndUpdate;
  end; // try
  if LSel < FBooks.Count then
    FBooks.ItemIndex:= LSel;
end;

procedure TConvertTab.BooksClickCheck(Sender: TObject);
begin
  for var I: Integer:= 0 to FBooks.Count - 1 do
    if I <= High(FEntries) then
      FEntries[I].Checked:= FBooks.Checked[I];
end;

procedure TConvertTab.MoveBook(ADelta: Integer);
var
  LIdx: Integer;
  LNew: Integer;
begin
  LIdx:= FBooks.ItemIndex;
  if (LIdx < 0) or (LIdx > High(FEntries)) then
    Exit;
  LNew:= LIdx + ADelta;
  if (LNew < 0) or (LNew > High(FEntries)) then
    LNew:= LIdx; // MoveEntry leaves an out-of-range move alone
  FEntries:= MoveEntry(FEntries, LIdx, ADelta);
  ShowBooks;
  FBooks.ItemIndex:= LNew;
end;

procedure TConvertTab.MoveUpClick(Sender: TObject);
begin
  MoveBook(-1);
end;

procedure TConvertTab.MoveDownClick(Sender: TObject);
begin
  MoveBook(1);
end;

procedure TConvertTab.CheckAll(AChecked: Boolean);
begin
  for var I: Integer:= 0 to High(FEntries) do
    FEntries[I].Checked:= AChecked;
  ShowBooks; // unchecks again what the engine cannot run
end;

procedure TConvertTab.CheckAllClick(Sender: TObject);
begin
  CheckAll(True);
end;

procedure TConvertTab.CheckNoneClick(Sender: TObject);
begin
  CheckAll(False);
end;

procedure TConvertTab.RefreshClick(Sender: TObject);
begin
  FProbed:= False; // an explicit Refresh also re-asks the engine what it can apply
  RefreshBooks;
end;

procedure TConvertTab.AddSources(const APaths: TArray<string>);
var
  Errs : TArray<string>;
  Added: TArray<string>;
begin
  // The job holds its own copy of the units, but a list that changes under a
  // running conversion misreports what ran (drops arrive whatever is enabled).
  if FRunning then
  begin
    FHost.SetStatus('A conversion is running -- sources cannot be added until it finishes.', True);
    Exit;
  end;
  Added:= ExpandSources(APaths, Errs);
  for var LPath: string in Added do
    if FSources.Items.IndexOf(LPath) < 0 then  // TListBox.IndexOf is case-insensitive
      FSources.Items.Add(LPath);
  if Length(Added) > 0 then
    FHost.FeedHarvest(Added);
  var LIndexErr: string;
  var LIndexOk: Boolean:= (FSources.Count = 0) or ReadIndex(LIndexErr);
  if Length(Errs) > 0 then
    FHost.SetStatus(Format('%d source(s) added; %d problem(s): %s', [Length(Added), Length(Errs), string.Join(' | ', Errs)]), True)
  else if not LIndexOk then
    FHost.SetStatus(Format('%d source unit(s) listed; cannot read the project index, so unindexed units are not flagged: %s', [FSources.Count, LIndexErr]), True)
  else
    FHost.SetStatus(SourcesSummary, False);
end;

procedure TConvertTab.RefreshIndex;
var
  LErr: string;
begin
  if FSources.Count = 0 then
    Exit;
  if not ReadIndex(LErr) then
    FHost.SetStatus('Cannot read the project index, so unindexed units are not flagged: ' + LErr, True);
end;

function TConvertTab.ReadIndex(out AError: string): Boolean;
var
  LNames: TArray<string>;
begin
  // By PATH: convert-apply finds the .dfm through the files table (UnitInIndex).
  Result:= FEngineProbe.ListIndexedFiles([FHost.GetProjectDb()], LNames, AError);
  // Unknown is never "indexed": on failure nothing is flagged, and says so.
  FIndexKnown:= Result;
  FIndexed   := if Result then LNames else nil;
  FSources.Invalidate;
end;

function TConvertTab.SourcesSummary: string;
var
  LFlagged: Boolean;
  LCount  : Integer;
begin
  LCount:= 0;
  for var LPath: string in FSources.Items do
  begin
    SourceRowText(LPath, FIndexed, FIndexKnown, LFlagged);
    if LFlagged then
      Inc(LCount);
  end;
  Result:= Format('%d source unit(s) listed.', [FSources.Count]);
  if LCount > 0 then
    Result:= Result + Format(' %d NOT in the project index (red) -- Convert will refuse until they are indexed.', [LCount]);
end;

procedure TConvertTab.SourcesDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  LFlagged: Boolean;
  LText   : string;
begin
  // The item string stays the raw path (the job and Preflight read it); only
  // the display carries the flag.
  LText:= SourceRowText(FSources.Items[Index], FIndexed, FIndexKnown, LFlagged);
  FSources.Canvas.FillRect(Rect);
  // Every row sets its own font state, flagged or not. The colour a clean or
  // selected row needs is already on the canvas: TCustomListBox.CNDrawItem
  // copies Font and then the THEMED list-item colour (normal / selected) before
  // each row, so it is kept as is rather than re-derived here -- only a flagged,
  // unselected row overrides it.
  if LFlagged then
    FSources.Canvas.Font.Style:= [fsBold]
  else
    FSources.Canvas.Font.Style:= [];
  // SetError's colour (MainForm.RefreshStatusColor: clRed in both themes); a
  // selected flagged row keeps the selection text colour so it stays readable.
  if LFlagged and not (odSelected in State) then
    FSources.Canvas.Font.Color:= clRed;
  FSources.Canvas.TextOut(Rect.Left + TEXT_INSET_X, Rect.Top, LText);
end;

procedure TConvertTab.AddClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg:= TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Delphi units and projects (*.pas;*.dpr;*.dproj)|*.pas;*.dpr;*.dproj';
    Dlg.Options:= Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    if Dlg.Execute then
      AddSources(Dlg.Files.ToStringArray);
  finally
    Dlg.Free;
  end; // try
end;

procedure TConvertTab.DeleteClick(Sender: TObject);
begin
  FSources.DeleteSelected;
  FHost.SetStatus(SourcesSummary, False);
end;

procedure TConvertTab.AddResultRow(const ACells: array of string);
var
  LItem: TListItem;
begin
  LItem:= FResults.Items.Add;
  LItem.Caption:= ACells[0];
  for var I: Integer:= 1 to High(ACells) do
    LItem.SubItems.Add(ACells[I]);
end;

procedure TConvertTab.AddRow(const ARow: TConvertRow);
var
  LRan: Boolean;
begin
  FRunRows:= FRunRows + [ARow];
  // Edit counts belong to a book that actually changed the unit.
  LRan:= ARow.Status in [csConverted, csRolledBack];
  AddResultRow([ExtractFileName(ARow.Book), ExtractFileName(ARow.UnitPas), ConvertStatusText(ARow.Status),
    if LRan then IntToStr(ARow.Apply.EditsCount) else '',
    if LRan then IntToStr(Length(ARow.Apply.Remainder)) else '',
    ExtractFileName(ARow.Backup), ExtractFileName(ARow.BackupDfm), ARow.Note]);
end;

procedure TConvertTab.QueueRow(const ARow: TConvertRow; ADone: Integer);
var
  LRow : TConvertRow;
  LDone: Integer;
begin
  LRow := ARow;
  LDone:= ADone;
  TThread.Queue(nil,
    procedure
    begin
      AddRow(LRow);
      FProgress.Position:= LDone;
    end);
end;

procedure TConvertTab.SetRunning(ARunning: Boolean);
begin
  FRunning:= ARunning;
  for var LCtl: TControl in FLockable do
    LCtl.Enabled:= not ARunning;
  FBtnCancel.Caption:= CAP_CANCEL;
  FBtnCancel.Enabled:= ARunning;
  if Assigned(FHost.RunStateChanged) then
    FHost.RunStateChanged(ARunning);
end;

procedure TConvertTab.CancelClick(Sender: TObject);
begin
  FCancelRequested  := True;
  FBtnCancel.Caption:= CAP_CANCELLING;
  FBtnCancel.Enabled:= False;
end;

procedure TConvertTab.ConvertClick(Sender: TObject);
var
  Units: TArray<string>;
  Pre  : TPreflight;
  Job  : TConvertJob;
  Idx  : TArray<string>;
  Err  : string;
  LExe : string;
begin
  Units:= FSources.Items.ToStringArray;
  // The open book on disk is what runs: make the user decide about unsaved edits first.
  var LOpen: string:= FHost.GetOpenBook();
  for var E: TBookEntry in FEntries do
    if E.Checked and (LOpen <> '') and SameText(ExpandFileName(E.Path), ExpandFileName(LOpen)) then
    begin
      if not FHost.ConfirmOpenBookSaved() then
        Exit;
      Break;
    end;
  if not FEngineProbe.ListIndexedFiles([FHost.GetProjectDb()], Idx, Err) then
  begin
    FIndexKnown:= False;
    FIndexed   := nil;
    FSources.Invalidate;
    FHost.SetStatus('Cannot read the project index: ' + Err, True);
    Exit;
  end;
  // The answer Preflight gets is also what the rows show.
  FIndexKnown:= True;
  FIndexed   := Idx;
  FSources.Invalidate;
  Pre:= Preflight(FEntries, Units, Idx, FUnitRulesOk);
  FResults.Items.Clear;
  FRunRows:= nil;
  FNotes  := Pre.Notes;
  for var LNote: string in Pre.Notes do
    AddResultRow(['', '', 'note', '', '', '', '', LNote]);
  if not Pre.Ok then
  begin
    FHost.SetStatus('Convert refused: ' + string.Join(' ', Pre.Problems), True);
    Exit;
  end;
  Job.Books      := Pre.Runnable;
  Job.Units      := Units;
  Job.Dbs        := FHost.GetDbs();
  Job.ProjectDb  := FHost.GetProjectDb();
  Job.ProjectFile:= FHost.GetProjectFile();
  // Every unit and every book is followed by `index --project` on the DB's OWN
  // project file: without it each apply would "fail" and every unit would be
  // restored; another project's file would re-scope the DB.
  if (Job.ProjectFile = '') or not TFile.Exists(Job.ProjectFile) then
  begin
    FHost.SetStatus(Format('Convert refused: the project index %s has no project file on disk -- expected %s.',
      [Job.ProjectDb, if Job.ProjectFile = '' then '<Project>.dproj beside its _D-RAG folder (the DB is not in one)' else Job.ProjectFile]), True);
    Exit;
  end;
  LExe:= FHost.ExePath;
  // Captured now: the user may open or start another book mid-run, which moves
  // the live rules folder; the report belongs beside the books that ran.
  FRunRulesFolder:= FHost.GetRulesFolder();
  FCancelRequested:= False;
  SetRunning(True);
  FProgress.Max     := Length(Job.Books) * Length(Job.Units);
  FProgress.Position:= 0;
  FHost.SetStatus(Format('Converting %d unit(s) with %d book(s)...', [Length(Job.Units), Length(Job.Books)]), False);
  TThread.CreateAnonymousThread(
    procedure
    var
      LEng    : TEngineAdapter;
      LOut    : string;
      LProblem: string;
      LPolls  : Integer;
      LStopAt : Integer;
      LFinal  : string;
    begin
      LProblem:= '';
      LPolls  := 0;
      LStopAt := -1;
      LFinal  := 'not run';
      // Defence in depth: RunConversion reports its own failures as rows, but
      // anything that still escapes must reach the UI, not end the thread silently.
      try
        // The worker's OWN adapter: FEngineProbe belongs to the UI thread.
        LEng:= TEngineAdapter.Create(LExe, Job.Dbs);
        try
          RunConversion(Job, LEng,
            procedure(const ARow: TConvertRow; ADone, ATotal: Integer)
            begin
              QueueRow(ARow, ADone);
            end,
            function: Boolean
            begin
              // Polled once per unit, just before it (RunConversionUnits): the
              // poll that first answers True names the first unit never reached.
              Result:= FCancelRequested;
              if Result and (LStopAt < 0) then
                LStopAt:= LPolls;
              Inc(LPolls);
            end);
          // Final refresh: restored units are back to their old text.
          if LEng.IndexProject(Job.ProjectFile, Job.ProjectDb, LOut) = 0 then
            LFinal:= 'ok'
          else
          begin
            LFinal  := 'FAILED: ' + Copy(Trim(LOut), 1, PROBLEM_HEAD);
            LProblem:= 'the final reindex failed: ' + Copy(Trim(LOut), 1, PROBLEM_HEAD);
          end;
        finally
          LEng.Free;
        end;
      except  // dl:ok try-except-swallowed@e073 -- REVIEWED 2026-09-29 not swallowed: the message becomes LProblem, which RunFinished puts on the error status line
        on E: Exception do
          LProblem:= 'the run stopped on an error: ' + E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          RunFinished(Job, LProblem, LStopAt, LFinal);
        end);
    end).Start;
end;

function TConvertTab.WriteReport(const ANotReached: TArray<string>; const AFinalIndex: string; out APath, AError: string): Boolean;
var
  LLines: TStringList;
begin
  APath := '';
  AError:= '';
  var LFolder: string:= FRunRulesFolder;
  if LFolder = '' then
  begin
    AError:= 'no rules folder';
    Exit(False);
  end;
  APath:= TPath.Combine(LFolder, Format('convert-run-%s.txt', [FormatDateTime('yyyymmdd-hhnnss', Now)]));
  LLines:= TStringList.Create;
  try
    LLines.Add(string.Join(#9, ['Book', 'Unit', 'Status', 'Edits', 'Remaining', 'Backup', 'Backup .dfm', 'Note']));
    for var LNote: string in FNotes do
      LLines.Add(string.Join(#9, ['', '', 'note', '', '', '', '', LNote]));
    for var LRow: TConvertRow in FRunRows do
    begin
      var LRan: Boolean:= LRow.Status in [csConverted, csRolledBack];
      LLines.Add(string.Join(#9, [LRow.Book, LRow.UnitPas, ConvertStatusText(LRow.Status),
        if LRan then IntToStr(LRow.Apply.EditsCount) else '',
        if LRan then IntToStr(Length(LRow.Apply.Remainder)) else '',
        LRow.Backup, LRow.BackupDfm, LRow.Note]));
    end;
    for var LUnit: string in ANotReached do
      LLines.Add(string.Join(#9, ['', LUnit, STATUS_NOT_REACHED, '', '', '', '', '']));
    LLines.Add('');
    if FCancelRequested then
      LLines.Add(Format('Run'#9'cancelled -- %d unit(s) not reached', [Length(ANotReached)]))
    else
      LLines.Add('Run'#9'completed');
    LLines.Add('Final reindex'#9 + AFinalIndex);
    try
      // UTF-8 without a BOM: engine text (a rule error, a path) may be non-ASCII,
      // and an ASCII write would turn it into '?'.
      TFile.WriteAllBytes(APath, TEncoding.UTF8.GetBytes(LLines.Text));
      Result:= True;
    except
      on E: Exception do
      begin
        AError:= E.Message;
        Result:= False;
      end;
    end; // try
  finally
    LLines.Free;
  end; // try
end;

procedure TConvertTab.RunFinished(const AJob: TConvertJob; const AProblem: string; AStopAt: Integer; const AFinalIndex: string);
var
  Converted : Integer;
  Restored  : Integer;
  RolledBack: Integer;
  BookSkips : Integer;
  UnitSkips : Integer;
  NotRestored: TArray<string>;
  NotReached: TArray<string>;
  Msg       : string;
  Report    : string;
  RepErr    : string;
begin
  SetRunning(False);
  FProgress.Position:= FProgress.Max;
  Converted := 0;
  Restored  := 0;
  RolledBack:= 0;
  BookSkips := 0;
  UnitSkips := 0;
  NotRestored:= nil;
  NotReached := nil;
  if (AStopAt >= 0) and (AStopAt < Length(AJob.Units)) then
    NotReached:= Copy(AJob.Units, AStopAt, Length(AJob.Units) - AStopAt);
  for var LUnit: string in NotReached do
    AddResultRow(['', ExtractFileName(LUnit), STATUS_NOT_REACHED, '', '', '', '', '']);
  for var LRow: TConvertRow in FRunRows do
    case LRow.Status of
      csConverted     : Inc(Converted);
      csFailedRestored: Inc(Restored);
      csRolledBack    : Inc(RolledBack);
      csBookSkipped   : Inc(BookSkips);
      csUnitSkipped   : Inc(UnitSkips);
      csRestoreFailed : NotRestored:= NotRestored + [ExtractFileName(LRow.UnitPas)];
    end; // case
  Msg:= Format('Converted %d of %d unit x book pair(s); %d failed and were restored.', [Converted, Length(AJob.Books) * Length(AJob.Units), Restored]);
  if RolledBack > 0 then
    Msg:= Msg + Format(' %d earlier conversion(s) were rolled back with them.', [RolledBack]);
  if BookSkips > 0 then
    Msg:= Msg + Format(' %d book(s) failed the engine''s validation and were skipped.', [BookSkips]);
  if UnitSkips > 0 then
    Msg:= Msg + Format(' %d unit(s) skipped.', [UnitSkips]);
  if FCancelRequested then
    Msg:= Msg + Format(' Cancelled: %d unit(s) not reached.', [Length(NotReached)]);
  // The most severe outcome leads: a unit that may be half-converted.
  if Length(NotRestored) > 0 then
    Msg:= Format('RESTORE FAILED for %s -- may be half-converted; restore by hand from the backups its row names. ', [string.Join(', ', NotRestored)]) + Msg;
  if AProblem <> '' then
    Msg:= Msg + ' Also: ' + AProblem + '.';
  if WriteReport(NotReached, AFinalIndex, Report, RepErr) then
    Msg:= Msg + ' Report: ' + Report
  else
    Msg:= Msg + ' Report NOT written (' + RepErr + ').';
  // Restored / converted units may have left or entered the index.
  var LIndexErr: string;
  if not ReadIndex(LIndexErr) then
    Msg:= Msg + ' The project index could not be re-read, so unindexed units are not flagged: ' + LIndexErr;
  // Re-harvest the converted code so the Unit Rules MISSING list is current.
  FHost.FeedHarvest(AJob.Units);
  FHost.SetStatus(Msg, (Restored + BookSkips + UnitSkips + Length(NotRestored) > 0) or (AProblem <> '') or (RepErr <> '') or (LIndexErr <> ''));
end;

end.
