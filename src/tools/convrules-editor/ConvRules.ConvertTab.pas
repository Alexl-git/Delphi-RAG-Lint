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
  , System.UITypes // TMsgDlgType: AskBlockingDrops's signature; also MessageDlg's inline expansion, mrYes
  , System.Generics.Collections
  , Winapi.Windows // TOwnerDrawState / odSelected: SourcesDrawItem's signature
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.CheckLst
  , Vcl.ComCtrls
  , Vcl.ExtCtrls
  , ConvRules.Engine  // dl:unit ConvRules.Engine accepted -- CAPABILITY_INHERITED_INSTANCES / _RETYPE are the engine contract the tab gates E10 and the N2 warnings on, so they travel with the adapter
  , ConvRules.EngineProgress  // dl:unit ConvRules.EngineProgress accepted -- ENGINE_OUTCOME_CANCELLED is the long-call runner's cancel contract the analysis work returns and reads back, so it travels with the runner
  , ConvRules.ConvertRun
  , ConvRules.ConvertRunner
  , ConvRules.Inheritance  // dl:unit ConvRules.Inheritance accepted -- ANALYSIS_CANCELLED is the analysis's own cancel text, reused for a reindex skipped by the same cancel
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
    /// <summary>Runs a long engine call behind the host's cancellable progress window
    /// (the main form's wrapper around RunWithProgressDialog); may be nil = the call
    /// runs inline on the UI thread, with no window and no cancel.</summary>
    RunLongCall   : TLongCallRunner;
    /// <summary>Called on the UI thread after the tab's own analysis reindexed the
    /// project (the stale retry, through FEngineProbe); may be nil. The host drops what
    /// it cached from the old index -- the main adapter's class resolutions -- as it
    /// does when a run ends.</summary>
    ProjectReindexed: TProc;
    /// <summary>The editor's resolved casts.castlib path; '' when none. Read on the UI
    /// thread when Convert is pressed; the run passes and reports it only when the
    /// file exists (ExistingCastLib).</summary>
    GetCastLib    : TFunc<string>;
  end;

  /// <summary>The Convert tab: a checklist of rule books, a list of source
  /// units, Convert / Cancel, progress and a results grid.</summary>
  /// <remarks>
  /// A run executes on an anonymous worker thread with its OWN TEngineAdapter;
  /// the worker reaches the controls only through TThread.Queue.
  /// FEngineProbe (capability probe, project-unit listing, the C8 inherited-instance
  /// check) is used by ONE thread at a time: the UI thread, or the progress window's
  /// worker while Analyze runs. That holds only because the runner (RunLongCall,
  /// RunWithProgressDialog) is MODAL -- the UI takes no input that could reach the
  /// probe until the worker has finished -- and because a drop, which OLE can still
  /// deliver, is refused while FAnalyzing (and while FPrompting, see SourcesAddRefusal).
  /// A non-modal runner would break it.
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
      FGlyphOk        : Boolean;            // engine reports glyph_stitch
      FProbed         : Boolean;            // FUnitRulesOk / FGlyphOk have been asked this session
      FRunning        : Boolean;
      FCancelRequested: Boolean;            // written on the UI thread, polled by the worker
      FNotes          : TArray<string>;     // the current run's pre-flight notes (for the report)
      FRunRows        : TArray<TConvertRow>;// the current run's rows as they arrived
      FRunRulesFolder : string;             // the rules folder when Convert was pressed: the report goes THERE
      FRunCastLib     : string;             // the castlib the run passed ('' = none): ExistingCastLib, captured when Convert was pressed
      FIndexed        : TArray<string>;     // file paths in the project index (valid while FIndexKnown)
      FIndexKnown     : Boolean;            // False = the index could not be read: flag nothing
      FInheritedOk    : Boolean;            // engine reports inherited_instances (C8 E10/E11)
      FRunInheritedOk : Boolean;            // FInheritedOk when Convert was pressed: the report follows the run
      FRetypeOk       : Boolean;            // engine reports inherited_retype (C8 N2): the notes stop warning that a descendant breaks
      FRunRetypeOk    : Boolean;            // FRetypeOk when Convert was pressed
      FInherit        : TDictionary<string, TUnitInheritance>; // C8 analyses, by upper-cased path
      FPairsKey       : string;             // the checked pairs FInherit was computed with
      FInheritError   : string;             // '' or why some unit could not be checked (status line)
      FAnalyzing      : Boolean;            // an analysis is running behind the progress window
      FAnalysisCancelled: Boolean;          // the last Analyze ended with ENGINE_OUTCOME_CANCELLED
      FPrompting      : Boolean;            // a C8 prompt (E6 offer, gate, E7) is up: drops are refused
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
      /// <summary>Convert's C8 steps after Preflight: the forced re-analysis, the gate
      /// (InheritanceGate: cancelled = stop; unchecked units = ask once), the E10 refusal
      /// notes and the E7 order warning (asked once, never a refusal).</summary>
      /// <param name="AUnits">The units the run would convert, run order.</param>
      /// <returns>False = stop; the status line already says why.</returns>
      function InheritanceChecksPass(const AUnits: TArray<string>): Boolean;
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
      /// <summary>The status line for the source list: SourcesSummary, or, when some
      /// unit could not be checked for inherited instances, that reason as an error.</summary>
      procedure ShowSourcesStatus;
      /// <summary>The checked books' #convert pairs (C8 E3 input).</summary>
      /// <param name="AError">'' or the unreadable books, each with its error.</param>
      /// <returns>Bare From / To names, book order.</returns>
      function CheckedPairs(out AError: string): TArray<TTypePair>;
      /// <summary>Analyses APaths against APairs (C8 E1-E3, E2b) and stores the results;
      /// behind the host's progress window, cancellable. A stale index is refreshed ONCE
      /// (the editor's own project) and the stale units retried once.</summary>
      /// <param name="APaths">Listed .pas paths.</param>
      /// <param name="APairs">The checked books' pairs (CheckedPairs).</param>
      /// <returns>False when the pass did not complete: cancelled (FAnalysisCancelled,
      /// from the work's ENGINE_OUTCOME_CANCELLED) or stopped on an exception.</returns>
      /// <remarks>Appends to FInheritError (callers clear it). Units that cannot be
      /// decided (index failure, cancel) are stored not-Known: no row note.</remarks>
      function Analyze(const APaths: TArray<string>; const APairs: TArray<TTypePair>): Boolean;
      /// <summary>Re-analyses the whole list when the checked pairs changed since the
      /// last COMPLETED analysis, or always when AForce. Resets FInheritError for the
      /// pass; leaves it alone when nothing runs.</summary>
      /// <param name="AForce">True after the index or the files may have changed.</param>
      /// <returns>True when an analysis ran.</returns>
      function ReanalyzeAll(AForce: Boolean): Boolean;
      /// <summary>The stored analysis of AUnitPas; an empty, not-Known record when none.</summary>
      /// <param name="AUnitPas">A listed .pas.</param>
      /// <returns>The analysis.</returns>
      function InheritanceOf(const AUnitPas: string): TUnitInheritance;
      /// <summary>The stored analyses of AUnits, in order.</summary>
      /// <param name="AUnits">Listed .pas paths.</param>
      /// <returns>One record per unit.</returns>
      function InheritanceOfAll(const AUnits: TArray<string>): TArray<TUnitInheritance>;
      /// <summary>C8 E6: for each just-added descendant whose ancestor chain is not all
      /// listed, asks 'Add &lt;missing chain&gt; ahead of &lt;unit&gt;?' (mirrored on the
      /// status line); Yes inserts them (InsertAncestors).</summary>
      /// <param name="AAdded">The units this add listed.</param>
      /// <param name="APairs">The pairs AAdded was analysed with.</param>
      procedure OfferAncestors(const AAdded: TArray<string>; const APairs: TArray<TTypePair>);
      /// <summary>Replaces the source list's items with AList, in order.</summary>
      /// <param name="AList">.pas paths.</param>
      procedure SetSources(const AList: TArray<string>);
      /// <summary>MessageDlg with FPrompting set for its lifetime: a drop OLE delivers
      /// inside the dialog's modal loop is then refused (SourcesAddRefusal), so the list
      /// the prompt was built from is still the list its answer acts on.</summary>
      /// <param name="AText">The question.</param>
      /// <param name="AType">The dialog's icon.</param>
      /// <returns>The MessageDlg result.</returns>
      function AskBlockingDrops(const AText: string; AType: TMsgDlgType): Integer;
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
  , ConvRules.InheritanceEngine
  , ConvRules.Glyph
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
  // The project index without its project file: the run refuses, the stale retry skips its reindex.
  NO_PROJECT_FILE_FMT   = 'the project index %s has no project file on disk -- expected %s';
  NO_PROJECT_FILE_GUESS = '<Project>.dproj beside its _D-RAG folder (the DB is not in one)';
  PAIRS_KEY_NONE        = '|none|'; // FPairsKey after a pass that did not complete: never equals a real key
  INHERIT_FAIL_FMT      = '%s Inherited instances could not be checked for every unit -- %s';

{ TConvertTab }

constructor TConvertTab.Create(AOwner: TComponent; const AHost: TConvertHost);
begin
  inherited Create(AOwner);
  FHost:= AHost;
  BevelOuter:= bvNone;
  Caption   := '';
  FEngineProbe:= TEngineAdapter.Create(FHost.ExePath, FHost.GetDbs());
  FInherit    := TDictionary<string, TUnitInheritance>.Create;
  BuildBooks;
  BuildRun;
  BuildSources;
  OnResize:= PanelResize;
end;

destructor TConvertTab.Destroy;
begin
  if FRunning then
    FCancelRequested:= True; // see the class remarks: the host refuses to close mid-run
  FInherit.Free;
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

  // Kind AND HasGlyph from one read, for a kept entry and a new one alike: a
  // HasGlyph set on one path only would leave the glyph_stitch gate inert.
  function Classify(var AEntry: TBookEntry): Boolean;
  begin
    try
      AEntry:= ClassifiedEntry(AEntry, TFile.ReadAllText(AEntry.Path));
      Result:= True;
    except
      on E: Exception do
      begin
        Errs:= Errs + [ExtractFileName(AEntry.Path) + ': ' + E.Message];
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
    // ONE info call for every key (each HasCapability is its own info call).
    var LCaps: TArray<string>:= FEngineProbe.CapabilityNames;
    FUnitRulesOk:= MatchText(CAPABILITY_UNIT_RULES, LCaps);
    FInheritedOk:= MatchText(CAPABILITY_INHERITED_INSTANCES, LCaps);
    FRetypeOk   := MatchText(CAPABILITY_INHERITED_RETYPE, LCaps);
    FGlyphOk    := MatchText(CAPABILITY_GLYPH_STITCH, LCaps);
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
      if Classify(E) then
        Next:= Next + [E];
    end;
  for var LFile: string in Files do
    if not Listed(LFile) then
    begin
      var E: TBookEntry:= Default(TBookEntry); // HasGlyph must not be stack garbage (C10 Task 4)
      E.Path   := LFile;
      E.Checked:= False;
      if Classify(E) then
        Next:= Next + [E];
    end;
  FEntries:= Next;
  ShowBooks;
  var LRan: Boolean:= ReanalyzeAll(False); // the checks may have changed (a book gone, a unit-rules book unchecked)
  if Length(Errs) > 0 then
    FHost.SetStatus(Format('%d rule book(s) could not be read and are not listed: %s', [Length(Errs), string.Join(' | ', Errs)]), True)
  else if LRan then
    ShowSourcesStatus;
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
      var LEnabled: Boolean;
      var LSuffix : string := BookListSuffix(FEntries[I], FUnitRulesOk, FGlyphOk, LEnabled);
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
  if ReanalyzeAll(False) then
    ShowSourcesStatus;
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
  if ReanalyzeAll(False) then
    ShowSourcesStatus;
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
  // running conversion misreports what ran (drops arrive whatever is enabled); a drop
  // can also arrive while the C8 check holds the progress window or one of its prompts.
  var LRefusal: string:= SourcesAddRefusal(FRunning, FAnalyzing or FPrompting);
  if LRefusal <> '' then
  begin
    FHost.SetStatus(LRefusal, True);
    Exit;
  end;
  Added:= ExpandSources(APaths, Errs);
  for var LPath: string in Added do
    if FSources.Items.IndexOf(LPath) < 0 then  // TListBox.IndexOf is case-insensitive
      FSources.Items.Add(LPath);
  FInheritError:= '';
  if Length(Added) > 0 then
  begin
    FHost.FeedHarvest(Added);
    var LPairsErr: string;
    var LPairs: TArray<TTypePair>:= CheckedPairs(LPairsErr);
    FInheritError:= LPairsErr;
    Analyze(Added, LPairs);        // C8 E1-E3, E2b
    OfferAncestors(Added, LPairs); // C8 E6
  end;
  var LIndexErr: string;
  var LIndexOk: Boolean:= (FSources.Count = 0) or ReadIndex(LIndexErr);
  if FInheritError <> '' then
    FHost.SetStatus(Format(INHERIT_FAIL_FMT, [SourcesSummary, FInheritError]), True)
  else if Length(Errs) > 0 then
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
  // C8 E5 / E8: the row notes, readable on the status bar (the list is owner-drawn).
  for var LPath: string in FSources.Items do
  begin
    var LNote: string:= InheritanceRowNote(InheritanceOf(LPath), FRetypeOk);
    if LNote <> '' then
      Result:= Result + ' | ' + ExtractFileName(LPath) + ': ' + LNote;
  end;
end;

procedure TConvertTab.ShowSourcesStatus;
begin
  if FInheritError <> '' then
    FHost.SetStatus(Format(INHERIT_FAIL_FMT, [SourcesSummary, FInheritError]), True)
  else
    FHost.SetStatus(SourcesSummary, False);
end;

function TConvertTab.CheckedPairs(out AError: string): TArray<TTypePair>;
begin
  Result:= nil;
  AError:= '';
  for var LEntry: TBookEntry in FEntries do
    if LEntry.Checked then
      try
        Result:= Result + TypePairsOfText(TFile.ReadAllText(LEntry.Path));
      except
        on E: Exception do
          AError:= AError + ExtractFileName(LEntry.Path) + ': ' + E.Message + ' ';
      end; // try
end;

function TConvertTab.Analyze(const APaths: TArray<string>; const APairs: TArray<TTypePair>): Boolean;
var
  LPairs  : TArray<TTypePair>;
  LDb     : string;
  LProject: string;
  LPaths  : TArray<string>;
  LUnits  : TArray<TUnitInheritance>;
  LWork   : TStreamingWork;
  LText   : string;
  LCode   : Integer;
  LReindexed: Boolean;
begin
  Result:= True;
  FAnalysisCancelled:= False;
  LReindexed:= False;
  if Length(APaths) = 0 then
    Exit;
  LPairs:= APairs;
  LUnits:= nil;
  if Length(LPairs) > 0 then
  begin
    LDb     := FHost.GetProjectDb();
    LProject:= FHost.GetProjectFile();
    LPaths  := APaths;
    // Runs on the progress window's worker thread; see the class remarks for why
    // FEngineProbe may be used there. Only the PROJECT DB is asked (authority).
    LWork:= function(const AOnProgress: TProgressProc; const ACancel: TCancelToken): Integer
      var
        LCancelled: TFunc<Boolean>;
      begin
        LCancelled:= function: Boolean
          begin
            Result:= ACancel.IsCancelled;
          end;
        LUnits:= AnalyzeRetryingStale(LPaths,
          function(const AThese: TArray<string>): TArray<TUnitInheritance>
          var
            LCache: TDictionary<string, TClassInfo>;
          begin
            // Per pass: a retry after a reindex asks afresh.
            LCache:= TDictionary<string, TClassInfo>.Create;
            try
              Result:= AnalyzeUnits(AThese, LPairs,
                CachingLookup(CancellableLookup(EngineClassLookup(FEngineProbe, LDb, LPairs), LCancelled), LCache),
                DiskTextReader(), CancellableCodeUses(EngineCodeUses(FEngineProbe, LDb), LCancelled));
            finally
              LCache.Free;
            end;
          end,
          function(out AError: string): Boolean
          var
            LOut: string;
          begin
            Result:= False;
            if LCancelled() then
              AError:= ANALYSIS_CANCELLED
            else if (LProject = '') or not TFile.Exists(LProject) then
              AError:= Format(NO_PROJECT_FILE_FMT, [LDb, if LProject = '' then NO_PROJECT_FILE_GUESS else LProject])
            else
            begin
              // The editor's OWN project (ProjectFileForDb), as the runner reindexes it.
              // Even a failed reindex may have rewritten part of the DB.
              LReindexed:= True;
              Result:= FEngineProbe.IndexProject(LProject, LDb, LOut) = 0;
              AError:= if Result then '' else Copy(Trim(LOut), 1, PROBLEM_HEAD);
            end;
          end);
        Result:= if ACancel.IsCancelled then ENGINE_OUTCOME_CANCELLED else 0;
      end;
    FAnalyzing:= True;
    try
      try
        if Assigned(FHost.RunLongCall) then
          LCode:= FHost.RunLongCall(Format('Checking %d source unit(s) for inherited instances', [Length(APaths)]), LWork)
        else
        begin
          var LToken: TCancelToken:= TCancelToken.Create;
          try
            LCode:= LWork(nil, LToken);
          finally
            LToken.Free;
          end; // try
        end;
        FAnalysisCancelled:= LCode = ENGINE_OUTCOME_CANCELLED;
        Result:= not FAnalysisCancelled;
      except
        on E: Exception do
        begin
          LUnits:= nil;
          Result:= False;
          FInheritError:= FInheritError + 'the inherited-instance check stopped on an error: ' + E.Message + ' ';
        end;
      end; // try
    finally
      FAnalyzing:= False;
      // The main form's adapter cached class resolutions from the old index (C6 clears
      // them after a run for the same reason). Read only here, after the modal wait.
      if LReindexed and Assigned(FHost.ProjectReindexed) then
        FHost.ProjectReindexed();
    end; // try
  end;
  for var LPath: string in APaths do
    FInherit.Remove(UpperCase(LPath));
  for var LUnit: TUnitInheritance in LUnits do
    FInherit.AddOrSetValue(UpperCase(LUnit.UnitPas), LUnit);
  LText:= UnknownUnitsText(LUnits);
  if LText <> '' then
    FInheritError:= FInheritError + LText;
  FSources.Invalidate;
end;

function TConvertTab.ReanalyzeAll(AForce: Boolean): Boolean;
var
  LKey   : string;
  LPairs : TArray<TTypePair>;
  LErr   : string;
begin
  LPairs:= CheckedPairs(LErr);
  LKey  := '';
  for var LPair: TTypePair in LPairs do
    LKey:= LKey + LPair.FromType + '>' + LPair.ToType + ';';
  Result:= AForce or not SameText(LKey, FPairsKey);
  if not Result then
    Exit;
  FInheritError:= LErr;
  FInherit.Clear;
  // Committed only for a completed pass: a cancelled one is redone on the next trigger.
  if Analyze(FSources.Items.ToStringArray, LPairs) then
    FPairsKey:= LKey
  else
    FPairsKey:= PAIRS_KEY_NONE;
end;

function TConvertTab.InheritanceOf(const AUnitPas: string): TUnitInheritance;
begin
  if not FInherit.TryGetValue(UpperCase(AUnitPas), Result) then
  begin
    Result:= Default(TUnitInheritance);
    Result.UnitPas:= AUnitPas;
  end;
end;

function TConvertTab.InheritanceOfAll(const AUnits: TArray<string>): TArray<TUnitInheritance>;
begin
  Result:= nil;
  for var LPath: string in AUnits do
    Result:= Result + [InheritanceOf(LPath)];
end;

procedure TConvertTab.SetSources(const AList: TArray<string>);
begin
  FSources.Items.BeginUpdate;
  try
    FSources.Items.Clear;
    for var LPath: string in AList do
      FSources.Items.Add(LPath);
  finally
    FSources.Items.EndUpdate;
  end; // try
end;

function TConvertTab.AskBlockingDrops(const AText: string; AType: TMsgDlgType): Integer;
begin
  FPrompting:= True;
  try
    Result:= MessageDlg(AText, AType, [mbYes, mbNo], 0);
  finally
    FPrompting:= False;
  end; // try
end;

procedure TConvertTab.OfferAncestors(const AAdded: TArray<string>; const APairs: TArray<TTypePair>);
var
  LChain  : TArray<string>;
  LList   : TArray<string>;
  LMissing: TArray<string>;
  LPrompt : string;
begin
  for var LPath: string in AAdded do
  begin
    LChain  := AncestorChain(InheritanceOf(LPath));
    LList   := FSources.Items.ToStringArray;
    LMissing:= MissingAncestors(LChain, LList);
    if Length(LMissing) = 0 then
      Continue;
    LPrompt:= OfferText(LMissing, LPath, UnconvertedTypes(InheritanceOf(LPath)), FRetypeOk);
    // Mirrored on the status line: a TMessageForm's text is a TLabel with no window,
    // so the GUI driver reads the status bar while the dialog is up.
    FHost.SetStatus(LPrompt, False);
    if AskBlockingDrops(LPrompt, mtConfirmation) <> mrYes then
      Continue;
    SetSources(InsertAncestors(LList, LPath, LChain));
    FHost.FeedHarvest(LMissing);
    Analyze(LMissing, APairs);
  end;
end;

procedure TConvertTab.SourcesDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  LFlagged: Boolean;
  LText   : string;
begin
  // The item string stays the raw path (the job and Preflight read it); only
  // the display carries the flag.
  LText:= SourceRowText(FSources.Items[Index], FIndexed, FIndexKnown, LFlagged);
  // C8 E5 / E8: what the unit inherits; italic, not red -- it is advice, not a refusal.
  var LNote: string:= InheritanceRowNote(InheritanceOf(FSources.Items[Index]), FRetypeOk);
  if LNote <> '' then
    LText:= LText + ' -- ' + LNote;
  FSources.Canvas.FillRect(Rect);
  // Every row sets its own font state, flagged or not. The colour a clean or
  // selected row needs is already on the canvas: TCustomListBox.CNDrawItem
  // copies Font and then the THEMED list-item colour (normal / selected) before
  // each row, so it is kept as is rather than re-derived here -- only a flagged,
  // unselected row overrides it.
  if LFlagged then
    FSources.Canvas.Font.Style:= [fsBold]
  else if LNote <> '' then
    FSources.Canvas.Font.Style:= [fsItalic]
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
  LRow: TConvertRow;
begin
  LRow:= ARow;
  // C8 E10, editor side: E2b code uses the run left, from the analysis taken BEFORE
  // the run (RunFinished reanalyses only after every row is in). An ancestor this run
  // converted earlier converted them too (R4).
  if CodeUseNoteDue(LRow, FRunRows) then
  begin
    var LLeft: string:= CodeUseLeftNote(InheritanceOf(LRow.UnitPas), UnitsConvertedIn(FRunRows));
    if LLeft <> '' then
      LRow.Note:= LRow.Note + '; ' + LLeft;
  end;
  FRunRows:= FRunRows + [LRow];
  // Edit counts belong to a book that actually changed the unit.
  LRan:= LRow.Status in [csConverted, csRolledBack];
  AddResultRow([ExtractFileName(LRow.Book), ExtractFileName(LRow.UnitPas), ConvertStatusText(LRow.Status),
    if LRan then IntToStr(LRow.Apply.EditsCount) else '',
    if LRan then IntToStr(Length(LRow.Apply.Remainder)) else '',
    ExtractFileName(LRow.Backup), ExtractFileName(LRow.BackupDfm), LRow.Note]);
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

function TConvertTab.InheritanceChecksPass(const AUnits: TArray<string>): Boolean;
begin
  Result:= True;
  // C8: the files and the index may have moved since the units were added. Only now,
  // after Preflight: a refused run must not first pay N x ~2 s of analysis.
  ReanalyzeAll(True);
  var LQuestion: string;
  case InheritanceGate(FAnalysisCancelled, InheritanceOfAll(AUnits), FInheritError, LQuestion) of
    igCancelled:
    begin
      FHost.SetStatus(GATE_CANCELLED_TEXT, False);
      Exit(False);
    end;
    igAsk:
    begin
      // Mirrored with the reason (a TMessageForm's text has no window); asked once, never a refusal (E9).
      FHost.SetStatus(LQuestion + ' Reason: ' + FInheritError, True);
      if AskBlockingDrops(LQuestion, mtWarning) <> mrYes then
      begin
        FHost.SetStatus(InheritanceGateStopText(FInheritError), True);
        Exit(False);
      end;
    end;
    igProceed: ; // nothing to ask
  end; // case
  var LRefusals: TArray<string>:= EngineRefusalNotes(InheritanceOfAll(AUnits), FInheritedOk);
  FNotes:= FNotes + LRefusals;
  for var LNote: string in LRefusals do
    AddResultRow(['', '', 'note', '', '', '', '', LNote]);
  // C8 E7: a descendant listed above an unconverted ancestor converts without its
  // inherited instances. Warn once; never block (E9).
  var LWarn: TArray<string>:= OrderWarnings(AUnits, InheritanceOfAll(AUnits), FRetypeOk);
  if Length(LWarn) > 0 then
  begin
    var LText: string:= OrderWarningText(LWarn, FRetypeOk);
    FHost.SetStatus(StringReplace(LText, sLineBreak, ' ', [rfReplaceAll]), False); // mirrored for the GUI driver: a TMessageForm's text has no window
    if AskBlockingDrops(LText, mtWarning) <> mrYes then
    begin
      FHost.SetStatus(OrderCancelledText(FRetypeOk), False);
      Exit(False);
    end;
  end;
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
  // The open book on disk is what runs: make the user decide about unsaved edits first.
  var LOpen: string:= FHost.GetOpenBook();
  for var E: TBookEntry in FEntries do
    if E.Checked and (LOpen <> '') and SameText(ExpandFileName(E.Path), ExpandFileName(LOpen)) then
    begin
      if not FHost.ConfirmOpenBookSaved() then
        Exit;
      Break;
    end;
  // The save may have changed what a checked book IS (a G-link just added): classify
  // the checked books afresh from disk, so ShowBooks greys one the engine cannot run
  // yet instead of handing it to the run. A checked book that cannot be read stops the
  // Convert with the reason, as RefreshBooks would not list it.
  for var I: Integer:= 0 to High(FEntries) do
    if FEntries[I].Checked then
      try
        FEntries[I]:= ClassifiedEntry(FEntries[I], TFile.ReadAllText(FEntries[I].Path));
      except
        on E: Exception do
        begin
          FHost.SetStatus(Format('Convert refused: rule book %s could not be read: %s', [ExtractFileName(FEntries[I].Path), E.Message]), True);
          Exit;
        end;
      end; // try
  ShowBooks;
  // Read AFTER that prompt: OLE delivers drops inside its modal loop too.
  Units:= FSources.Items.ToStringArray;
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
  Pre:= Preflight(FEntries, Units, Idx, FUnitRulesOk, FGlyphOk);
  FResults.Items.Clear;
  FRunRows:= nil;
  FNotes  := Pre.Notes;
  for var LNote: string in FNotes do
    AddResultRow(['', '', 'note', '', '', '', '', LNote]);
  if not Pre.Ok then
  begin
    FHost.SetStatus('Convert refused: ' + string.Join(' ', Pre.Problems), True);
    Exit;
  end;
  Job.ProjectDb  := FHost.GetProjectDb();
  Job.ProjectFile:= FHost.GetProjectFile();
  // Every unit and every book is followed by `index --project` on the DB's OWN
  // project file: without it each apply would "fail" and every unit would be
  // restored; another project's file would re-scope the DB. Checked BEFORE the C8
  // checks: a refused run must not first ask its questions (or pay its analysis).
  if (Job.ProjectFile = '') or not TFile.Exists(Job.ProjectFile) then
  begin
    FHost.SetStatus('Convert refused: ' + Format(NO_PROJECT_FILE_FMT, [Job.ProjectDb, if Job.ProjectFile = '' then NO_PROJECT_FILE_GUESS else Job.ProjectFile]) + '.', True);
    Exit;
  end;
  // C8: re-check, gate, refusal notes and the E7 order warning (after Preflight).
  if not InheritanceChecksPass(Units) then
    Exit;
  Job.Books      := Pre.Runnable;
  Job.Units      := Units;
  Job.Dbs        := FHost.GetDbs();
  Job.InheritedSupported:= FInheritedOk;
  Job.RetypeSupported   := FRetypeOk;
  LExe:= FHost.ExePath;
  // Captured now: the user may open or start another book mid-run, which moves
  // the live rules folder; the report belongs beside the books that ran.
  FRunRulesFolder:= FHost.GetRulesFolder();
  FRunInheritedOk:= FInheritedOk;
  FRunRetypeOk   := FRetypeOk;
  // The worker builds its own adapter: the castlib is read HERE, on the UI thread,
  // and only an existing file is passed and named in the report.
  FRunCastLib:= ExistingCastLib(FHost.GetCastLib());
  var LCastLib: string:= FRunCastLib;
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
          LEng.CastLibFile:= LCastLib;
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
    for var I: Integer:= 0 to High(FRunRows) do
    begin
      var LRow: TConvertRow:= FRunRows[I];
      var LRan: Boolean:= LRow.Status in [csConverted, csRolledBack];
      LLines.Add(string.Join(#9, [LRow.Book, LRow.UnitPas, ConvertStatusText(LRow.Status),
        if LRan then IntToStr(LRow.Apply.EditsCount) else '',
        if LRan then IntToStr(Length(LRow.Apply.Remainder)) else '',
        LRow.Backup, LRow.BackupDfm, LRow.Note]));
      // C8 E10: one line per instance the engine says the converted unit left (unfiltered, ruling M4).
      for var LLine: string in InheritedReportLines(LRow, FRunInheritedOk, FRunRetypeOk) do
        LLines.Add(LLine);
      // C10 E13: one 8-column line per glyph outcome, converted rows only.
      for var LLine: string in GlyphReportLines(LRow) do
        LLines.Add(LLine);
    end;
    for var LUnit: string in ANotReached do
      LLines.Add(string.Join(#9, ['', LUnit, STATUS_NOT_REACHED, '', '', '', '', '']));
    LLines.Add('');
    if FCancelRequested then
      LLines.Add(Format('Run'#9'cancelled -- %d unit(s) not reached', [Length(ANotReached)]))
    else
      LLines.Add('Run'#9'completed');
    LLines.Add('Castlib'#9 + (if FRunCastLib = '' then '(none)' else FRunCastLib));
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
  Refused   : Integer;
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
  Refused   := 0;
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
      csRefused       : Inc(Refused);
    end; // case
  Msg:= Format('Converted %d of %d unit x book pair(s); %d failed and were restored.', [Converted, Length(AJob.Books) * Length(AJob.Units), Restored]);
  if Refused > 0 then
    Msg:= Msg + Format(' %d unit(s) refused by the engine and left unchanged (a known limitation -- see each row''s note).', [Refused]);
  // After the refused sentence: a roll-back follows a failure OR a refusal, and
  // "rolled back with them" right after "0 failed" named the wrong cause.
  if RolledBack > 0 then
    Msg:= Msg + Format(' %d earlier conversion(s) on those units were rolled back by a later failure or refusal.', [RolledBack]);
  if BookSkips > 0 then
    Msg:= Msg + Format(' %d book(s) failed the engine''s validation and were skipped.', [BookSkips]);
  if UnitSkips > 0 then
    Msg:= Msg + Format(' %d unit(s) skipped.', [UnitSkips]);
  if FCancelRequested then
    Msg:= Msg + Format(' Cancelled: %d unit(s) not reached.', [Length(NotReached)]);
  // The most severe outcome leads: a unit that may be half-converted; glyph to-dos
  // (spec E14, counted per UNIT -- R5) come next: converted, but each such unit's
  // implementation section starts with a to-do line the user must act on.
  var LGlyphSummary: string:= GlyphRunSummary(GlyphTodoUnitCount(FRunRows));
  Msg:= RunStatusLead(NotRestored, LGlyphSummary, Msg);
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
  // C8: converted ancestors now answer differently -- after every row is in (AddRow
  // read the pre-run analysis).
  ReanalyzeAll(True);
  if FInheritError <> '' then
    Msg:= Msg + ' Inherited instances could not be re-checked: ' + FInheritError;
  // Re-harvest the converted code so the Unit Rules MISSING list is current.
  FHost.FeedHarvest(AJob.Units);
  // Red when the run went wrong, a re-read after it failed (C8), or units hold glyph to-dos (C10).
  var LRunProblem : Boolean:= (Restored + BookSkips + UnitSkips + Length(NotRestored) > 0) or (AProblem <> '') or (RepErr <> '');
  var LReadProblem: Boolean:= (LIndexErr <> '') or (FInheritError <> '');
  FHost.SetStatus(Msg, LRunProblem or LReadProblem or (LGlyphSummary <> ''));
end;

end.
