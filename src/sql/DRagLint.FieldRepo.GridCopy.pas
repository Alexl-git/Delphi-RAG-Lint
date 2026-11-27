unit DRagLint.FieldRepo.GridCopy;

{ drag-lint 1.56 -- lane GCP-M: the grid copy model. Copies the events of a DevExpress grid view, its columns and
  their events to another view of the same form, whatever the two view types are (table, banded table, card, layout;
  data-bound or not), or copies ONE event. Used by DRagLint.CLI.RepoGridCopy and the IDE command.

  The model reads the bytes of a text DFM (and of its unit), makes a plan of numbered changes, and renders the new
  bytes of the chosen changes with the byte-level editors of DRagLint.FieldRepo.DfmWrite: every byte outside a change
  is copied unchanged. It writes no file (the caller passes the outputs to WriteOutputs).

  A copied event points the target at the SAME handler method; no method is written. Whether an event of one view or
  column class exists on another is decided by the table GC_CLASSES below, taken from the published sections of the
  ExpressQuantumGrid sources (cxGridCustomView, cxGridCustomTableView, cxGridTableView, cxGridBandedTableView,
  cxGridCardView, cxGridLayoutView, cxGridDBDataDefinitions). }

interface

uses
  System.SysUtils,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.DfmWrite;

type
  /// <summary>Raised when a copy cannot be planned or applied (unknown view, view class, event, change id).</summary>
  /// <remarks>Nothing has been changed then. A DFM or unit this model cannot read raises EDfmWriteError instead.</remarks>
  EGridCopyError = class(Exception);

  /// <summary>The form the two views are in: the bytes of its text DFM and of its unit.</summary>
  TGridCopyForm = record
    /// <summary>Path of the DFM; its file name is the first word of every change target.</summary>
    DfmFile: string;
    /// <summary>The DFM's bytes as read from disk.</summary>
    DfmBytes: TBytes;
    /// <summary>Path of the unit; '' when there is none.</summary>
    UnitFile: string;
    /// <summary>The unit's bytes; nil = no unit. Without a unit no column can be added (it needs its declaration)
    /// and no handler body is checked.</summary>
    UnitBytes: TBytes;
  end;

  /// <summary>What to copy.</summary>
  TGridCopyRequest = record
    /// <summary>Component name of the view the events and columns are read from.</summary>
    SourceView: string;
    /// <summary>Component name of the view that gets them.</summary>
    TargetView: string;
    /// <summary>'' = every event, every column and every event of a column; else the ONE event to copy, as the DFM
    /// writes it: OnCustomDrawCell, DataController.OnCompare, Styles.OnGetContentStyle.</summary>
    EventName: string;
    /// <summary>One event only: '' = an event of the view itself; else the source column that has the event.</summary>
    SourceColumn: string;
    /// <summary>One event of a column only: the target column; '' = the column of the target view that shows the same
    /// field (DataBinding.FieldName, case-insensitive).</summary>
    TargetColumn: string;
    /// <summary>The request "copy everything".</summary>
    /// <param name="pSourceView">Source view.</param>
    /// <param name="pTargetView">Target view.</param>
    /// <returns>The request.</returns>
    class function Everything(const pSourceView, pTargetView: string): TGridCopyRequest; static;
    /// <summary>The request "copy one event".</summary>
    /// <param name="pSourceView">Source view.</param>
    /// <param name="pTargetView">Target view; the source view itself to copy between two columns of one view.</param>
    /// <param name="pEvent">The event as the DFM writes it.</param>
    /// <param name="pSourceColumn">'' = an event of the view; else the column that has it.</param>
    /// <param name="pTargetColumn">'' = the column showing the same field.</param>
    /// <returns>The request.</returns>
    class function OneEvent(const pSourceView, pTargetView, pEvent: string; const pSourceColumn: string = '';
      const pTargetColumn: string = ''): TGridCopyRequest; static;
  end;

  /// <summary>What a step of a plan does to the DFM.</summary>
  TGridCopyStepKind = (gskSetProp, gskInsertColumn);

  /// <summary>How ApplyGridCopy carries out one change. Made by PlanGridCopy; read-only for callers.</summary>
  TGridCopyStep = record
    /// <summary>Id of the change this step belongs to.</summary>
    ChangeId: Integer;
    /// <summary>Set a property of an object, or add a column.</summary>
    Kind: TGridCopyStepKind;
    /// <summary>Index in TDfmDocument.Objects: the object whose property is set, or the view that gets the column;
    /// -1 = a property of a column this plan adds (DependsOn names it).</summary>
    ObjectIndex: Integer;
    /// <summary>Id of the change that adds the column this property belongs to; 0 = none.</summary>
    DependsOn: Integer;
    /// <summary>gskSetProp: property name and DFM text of its value (lines separated by CRLF).</summary>
    Prop: string;
    Value: string;
    /// <summary>gskInsertColumn: component name and class of the new column.</summary>
    Name: string;
    ItemClass: string;
    /// <summary>gskInsertColumn: the property lines of the block in the order of the source column, indented relative
    /// to its `object` line; an entry is one property (CRLF between the lines of a value of several lines). An entry
    /// `@N` stands for the event of change N: its line is written when N is chosen.</summary>
    Lines: TArray<string>;
  end;

  /// <summary>The plan of one copy.</summary>
  /// <remarks>A value: it owns nothing but its arrays. The same form bytes and request always give the same change
  /// ids and the same PlanId.</remarks>
  TGridCopyPlan = record
    /// <summary>The form the plan was made from.</summary>
    Form: TGridCopyForm;
    /// <summary>The request the plan was made for.</summary>
    Request: TGridCopyRequest;
    /// <summary>Class names of the two views.</summary>
    SourceClass: string;
    TargetClass: string;
    /// <summary>The changes in id order (ids 1..n). Target = `FILE.dfm Component`, Prop = the event ('' for a new
    /// column), OldValue = the handler the target has now, NewValue = the handler it gets. Blocked = why it can never
    /// be applied; Checked = False for a blocked change and for one the user has to look at (Notes says why).</summary>
    Changes: TArray<TFrChange>;
    /// <summary>One entry per change, same index: why it is unchecked or what is left out; '' = nothing to say.</summary>
    Notes: TArray<string>;
    /// <summary>The columns the plan adds to the target view, as rows of the repository column model
    /// (TableName stays ''; Properties holds the copied `Properties.*` lines).</summary>
    Columns: TArray<TFrGridColumn>;
    /// <summary>Remarks about the whole plan, e.g. why it has no change.</summary>
    Remarks: TArray<string>;
    /// <summary>How the changes are applied, in order.</summary>
    Steps: TArray<TGridCopyStep>;
    /// <summary>16 hex digits naming the form bytes, the request and the changes; a --select file names it.</summary>
    PlanId: string;
  end;

  /// <summary>One grid view of a form.</summary>
  TGridCopyViewInfo = record
    /// <summary>Component name and class.</summary>
    Name: string;
    ViewClass: string;
    /// <summary>Class of its columns (rows, items).</summary>
    ItemClass: string;
    /// <summary>Number of columns the DFM has for it.</summary>
    ColumnCount: Integer;
  end;

  /// <summary>One event a view or one of its columns has a handler for.</summary>
  TGridCopyEvent = record
    /// <summary>Component name and class of the view or column.</summary>
    Component: string;
    ComponentClass: string;
    /// <summary>True for a column.</summary>
    IsColumn: Boolean;
    /// <summary>The event as the DFM writes it and its handler method.</summary>
    Event: string;
    Handler: string;
  end;

/// <summary>The grid views of a form that this model can copy from and to.</summary>
/// <param name="pForm">The form; only the DFM is read.</param>
/// <returns>The views in file order; views of a class the model does not know (chart views) are left out.</returns>
/// <exception cref="EDfmWriteError">The DFM is binary or cannot be read.</exception>
function GridCopyViews(const pForm: TGridCopyForm): TArray<TGridCopyViewInfo>;

/// <summary>The events of a view and of its columns that have a handler: what "copy one event" can name.</summary>
/// <param name="pForm">The form; only the DFM is read.</param>
/// <param name="pView">Component name of the view.</param>
/// <returns>The view's events, then those of each column, in file order.</returns>
/// <exception cref="EGridCopyError">The form has no such view, or its class is not a grid view this model knows.</exception>
/// <exception cref="EDfmWriteError">The DFM is binary or cannot be read.</exception>
function GridCopyEvents(const pForm: TGridCopyForm; const pView: string): TArray<TGridCopyEvent>;

/// <summary>The columns of a view as rows of the repository column model.</summary>
/// <param name="pForm">The form; only the DFM is read.</param>
/// <param name="pView">Component name of the view.</param>
/// <returns>One row per column in file order: FormName = the DFM's root component, ColumnIndex = 0-based position,
/// FieldName = DataBinding.FieldName, PropertiesClassName and Properties (the `Properties.*` lines, CRLF between
/// them, the indentation of the property removed) as the DFM has them; TableName = ''.</returns>
/// <exception cref="EGridCopyError">The form has no such view, or its class is not a grid view this model knows.</exception>
/// <exception cref="EDfmWriteError">The DFM is binary or cannot be read.</exception>
function GridViewColumns(const pForm: TGridCopyForm; const pView: string): TArray<TFrGridColumn>;  // dl:ok unused-public-symbol@f56d -- REVIEWED LINTFIX-B 2026-11-27: public so tests\fieldrepo\GridCopyTests.dpr calls it directly (unit test surface)

/// <summary>Plans a copy; nothing is written.</summary>
/// <param name="pForm">The form: DFM bytes, and the unit's bytes when there is a unit.</param>
/// <param name="pRequest">What to copy.</param>
/// <returns>The plan. One event: one change, or none when the target already has that handler (Remarks says so).
/// Everything: the events of the view; then per source column, in order: its events onto the target column that shows
/// the same field (DataBinding.FieldName, case-insensitive; a target column is used once), else a new column (an
/// insert with Prop = '', NewValue = `CLASS FIELD`) followed by one change per event of it. The new column is named
/// after the target view (source view name replaced, else prefixed; a number is added until no component and no
/// identifier of the unit has the name) and declared in the form class after the view's columns. Its properties are
/// copied as the source DFM has them, except: `Position.*` only between views of one layout, `DataBinding.*` only
/// between two data-bound or two unbound views, and between different kinds of view (table or banded table / card)
/// only the properties every column kind has (caption, binding, editor, visibility, sorting, the common options);
/// Notes lists what was not copied. A banded target without bands gets, before its first new column, a change that
/// adds the source's bands, else one band; a column from a view that is not banded goes to band 0.
/// A change is BLOCKED when the target's class has no such event, when a `Properties.*` event goes to a column
/// with another editor class, and for a new column: without a unit that declares the form class, in a layout view
/// (its items need layout items), with nested objects or with text that is not 7-bit ASCII. It is UNCHECKED when the
/// target already has another handler (an update), when the two classes declare the event separately or the model
/// does not know the event, and when the handler's body names the source view or one of its columns.</returns>
/// <exception cref="EGridCopyError">A view is missing, is not a grid view this model knows, or lives in a frame
/// instance; source and target are the same component; one event: the source has no handler for the named event, or
/// no target column shows the source column's field.</exception>
/// <exception cref="EDfmWriteError">The DFM is binary or cannot be read.</exception>
/// <remarks>Both views are in ONE form. An event is a property whose last name part is On + a capital letter and
/// whose value is one identifier.</remarks>
function PlanGridCopy(const pForm: TGridCopyForm; const pRequest: TGridCopyRequest): TGridCopyPlan;

/// <summary>The ids of the changes a plan applies by default: checked and not blocked.</summary>
/// <param name="pPlan">The plan.</param>
/// <returns>The ids in order.</returns>
function GridCopyDefaultIds(const pPlan: TGridCopyPlan): TArray<Integer>;

/// <summary>Resolves the lines of a --select file against a plan.</summary>
/// <param name="pPlan">The plan.</param>
/// <param name="pLines">One id per line, or `all` (every change that is not blocked); blank lines and lines starting
/// `#` are ignored, except `# plan ID`, which must name this plan.</param>
/// <returns>The chosen ids in order, without duplicates.</returns>
/// <exception cref="EGridCopyError">A `# plan` line names another plan.</exception>
/// <exception cref="EFrChangeSetError">An unknown id, a bad line, or a blocked change named by id.</exception>
function SelectGridCopy(const pPlan: TGridCopyPlan; const pLines: TArray<string>): TArray<Integer>;

/// <summary>The new bytes of the files a plan changes; no file is written.</summary>
/// <param name="pPlan">A plan of PlanGridCopy.</param>
/// <param name="pIds">The ids of the changes to apply (GridCopyDefaultIds, SelectGridCopy).</param>
/// <returns>One output per changed file (the DFM; the unit when a column is added), OldBytes = the plan's bytes;
/// empty when pIds is empty. Pass it to WriteOutputs.</returns>
/// <exception cref="EGridCopyError">An id the plan does not have, a blocked change, or an event of a new column
/// chosen without the column.</exception>
/// <exception cref="EDfmWriteError">The text around a change is not one item per line, or the RTL cannot convert the
/// new DFM text to binary (the new bytes are checked before they are returned).</exception>
function ApplyGridCopy(const pPlan: TGridCopyPlan; const pIds: TArray<Integer>): TArray<TDfmwOutput>;

/// <summary>A plan as ASCII text.</summary>
/// <param name="pPlan">The plan.</param>
/// <returns>`# plan ID`, then `copy SRC (CLASS) -> DST (CLASS) in FILE: N changes, B blocked, U unchecked`, then per
/// change the lines of RenderChangeSetText (`[id] op target prop: old -> new`, `  BLOCKED: reason`, `  (unchecked)`)
/// followed by `  NOTE: text` when the change has a note, then one `NOTE: text` line per remark.</returns>
function RenderGridCopyText(const pPlan: TGridCopyPlan): TArray<string>;

/// <summary>A plan as JSON.</summary>
/// <param name="pPlan">The plan.</param>
/// <returns>`{"plan","file","source","source_class","target","target_class","event","count","blocked","unchecked",
/// "changes":[{"id","op","target","prop","old","new","checked","blocked","note"}],"remarks":[..]}` on one line.</returns>
function RenderGridCopyJson(const pPlan: TGridCopyPlan): string;

implementation

uses
  System.StrUtils,
  System.Hash,
  System.JSON,
  System.RegularExpressions;

type
  TGcLayout = (gclTable, gclBanded, gclCard, gclLayout);

  TGcView = record
    ViewClass: string;
    ItemClass: string;
    Layout: TGcLayout;
    DataBound: Boolean;
  end;

  TGcClass = record
    Name: string;
    Ancestor: string;
    Events: string; // the events the class itself publishes, blank-separated; `Styles.` events included
  end;

  TGcVerdict = (gvOk, gvUnchecked, gvBlocked);

  { One end of an event copy: the class of the view or column, whether its view is data-bound, its editor class. }
  TGcSide = record
    ObjClass: string;
    Bound: Boolean;
    Editor: string;
  end;

const
  CRLF = #13#10;
  LAST_ASCII = #127;
  BYTE_LF = 10;
  BYTE_CR = 13;
  PLAN_ID_LENGTH = 16;
  EVENT_PREFIX = 'On';
  EVENT_PREFIX_LENGTH = 2;
  PROP_FIELD_NAME = 'DataBinding.FieldName';
  PROP_EDITOR_CLASS = 'PropertiesClassName';
  PREFIX_EDITOR = 'Properties.';
  PREFIX_DATA_CONTROLLER = 'DataController.';
  KIND_INLINE = 'inline';
  ROOT_ITEM_CLASS = 'TcxCustomGridTableItem';
  PROP_BANDS = 'Bands';
  PREFIX_POSITION = 'Position.';
  PREFIX_BINDING = 'DataBinding.';
  STEP = '  ';
  EVENT_MARK = '@';
  BANDS_ONE = '<' + CRLF + '    item' + CRLF + '    end>';
  { What a column of every kind of view has (TcxCustomGridTableItem and its options); `Properties.*`, `Position.*`
    and `DataBinding.*` have rules of their own. }
  COMMON_ITEM_PROPS: array[0..14] of string = ('Caption', 'PropertiesClassName', 'RepositoryItem', 'Visible', 'Tag',
    'SortIndex', 'SortOrder', 'BestFitMaxWidth', 'DateTimeGrouping', 'Options.Editing', 'Options.Filtering',
    'Options.Focusing', 'Options.IncSearch', 'Options.ShowEditButtons', 'Styles.Content');
  OP_NAMES: array[TFrChangeOp] of string = ('insert', 'update', 'delete');

  GC_VIEWS: array[0..7] of TGcView = (
    (ViewClass: 'TcxGridDBTableView'; ItemClass: 'TcxGridDBColumn'; Layout: gclTable; DataBound: True),
    (ViewClass: 'TcxGridDBBandedTableView'; ItemClass: 'TcxGridDBBandedColumn'; Layout: gclBanded; DataBound: True),
    (ViewClass: 'TcxGridDBCardView'; ItemClass: 'TcxGridDBCardViewRow'; Layout: gclCard; DataBound: True),
    (ViewClass: 'TcxGridDBLayoutView'; ItemClass: 'TcxGridDBLayoutViewItem'; Layout: gclLayout; DataBound: True),
    (ViewClass: 'TcxGridTableView'; ItemClass: 'TcxGridColumn'; Layout: gclTable; DataBound: False),
    (ViewClass: 'TcxGridBandedTableView'; ItemClass: 'TcxGridBandedColumn'; Layout: gclBanded; DataBound: False),
    (ViewClass: 'TcxGridCardView'; ItemClass: 'TcxGridCardViewRow'; Layout: gclCard; DataBound: False),
    (ViewClass: 'TcxGridLayoutView'; ItemClass: 'TcxGridLayoutViewItem'; Layout: gclLayout; DataBound: False));

  { Published events per class, ancestors before descendants. The data controller is not here: see DC_*. }
  GC_CLASSES: array[0..19] of TGcClass = (
    (Name: 'TcxCustomGridView'; Ancestor: '';
      Events: 'OnDblClick OnDragDrop OnDragOver OnEndDrag OnKeyDown OnKeyPress OnKeyUp OnMouseDown OnMouseEnter '
        + 'OnMouseLeave OnMouseMove OnMouseUp OnMouseWheel OnMouseWheelDown OnMouseWheelUp OnStartDrag '
        + 'OnGetStoredProperties OnGetStoredPropertyValue OnSetStoredPropertyValue'),
    (Name: 'TcxCustomGridTableView'; Ancestor: 'TcxCustomGridView';
      Events: 'OnCanFocusRecord OnCanSelectRecord OnCellClick OnCellDblClick OnCustomDrawCell '
        + 'OnCustomDrawPartBackground OnEditing OnEditChanged OnEditDblClick OnEditKeyDown OnEditKeyPress '
        + 'OnEditKeyUp OnEditValueChanged OnFilterControlDialogShow OnFilterCustomization OnFilterDialogShow '
        + 'OnFindPanelVisibilityChanged OnFocusedItemChanged OnFocusedRecordChanged OnGetCellHeight '
        + 'OnPopulateCustomScrollbarAnnotationRowIndexList OnGetDragDropText OnGetScrollbarAnnotationHint '
        + 'OnInitEdit OnInitEditValue OnInitFilteringDateRanges OnInitStoredObject OnSelectionChanged '
        + 'OnTopRecordIndexChanged OnUpdateEdit '
        + 'Styles.OnGetContentStyle Styles.OnGetInactiveStyle Styles.OnGetSelectionStyle'),
    (Name: 'TcxGridTableView'; Ancestor: 'TcxCustomGridTableView';
      Events: 'OnColumnHeaderClick OnColumnPosChanged OnColumnSizeChanged OnCustomDrawColumnHeader '
        + 'OnCustomDrawFooterCell OnCustomDrawGroupCell OnCustomDrawGroupSummaryCell OnCustomDrawIndicatorCell '
        + 'OnCustomization OnGroupRowCollapsed OnGroupRowCollapsing OnGroupRowExpanded OnGroupRowExpanding '
        + 'OnDetachedEditFormInitialize OnGetUnmergeableColumns OnInitGroupingDateRanges OnLeftPosChanged '
        + 'Styles.OnGetFooterStyle Styles.OnGetFooterStyleEx Styles.OnGetFooterSummaryStyle Styles.OnGetGroupStyle '
        + 'Styles.OnGetGroupSummaryStyle Styles.OnGetHeaderStyle Styles.OnGetHotTrackStyle '
        + 'Styles.OnGetInplaceEditFormGroupStyle Styles.OnGetInplaceEditFormItemStyle Styles.OnGetPreviewStyle'),
    (Name: 'TcxGridBandedTableView'; Ancestor: 'TcxGridTableView';
      Events: 'OnBandPosChanged OnBandSizeChanged OnCustomDrawBandHeader OnQuickCustomizationColumnCompare '
        + 'Styles.OnGetBandHeaderStyle'),
    (Name: 'TcxGridDBTableView'; Ancestor: 'TcxGridTableView'; Events: ''),
    (Name: 'TcxGridDBBandedTableView'; Ancestor: 'TcxGridBandedTableView'; Events: ''),
    (Name: 'TcxGridCustomLayoutView'; Ancestor: 'TcxCustomGridTableView'; Events: ''),
    (Name: 'TcxGridCardView'; Ancestor: 'TcxGridCustomLayoutView';
      Events: 'OnCustomization OnRowCollapsed OnRowCollapsing OnRowExpanded OnRowExpanding OnRowPosChanged '
        + 'Styles.OnGetCaptionRowStyle Styles.OnGetCardBorderStyle Styles.OnGetCategoryRowStyle '
        + 'Styles.OnGetRowCaptionStyle'),
    (Name: 'TcxGridDBCardView'; Ancestor: 'TcxGridCardView'; Events: ''),
    (Name: 'TcxGridLayoutView'; Ancestor: 'TcxGridCustomLayoutView';
      Events: 'OnCustomization OnCustomDrawRecordCaption Styles.OnGetGroupStyle Styles.OnGetItemStyle '
        + 'Styles.OnGetRecordBorderStyle Styles.OnGetRecordCaptionStyle'),
    (Name: 'TcxGridDBLayoutView'; Ancestor: 'TcxGridLayoutView'; Events: ''),
    (Name: ROOT_ITEM_CLASS; Ancestor: '';
      Events: 'OnCustomDrawCell OnGetCellHint OnGetDataText OnGetDisplayText OnGetFilterDisplayText '
        + 'OnGetFilterImages OnGetFilterValues OnGetProperties OnGetPropertiesForEdit OnGetStoredProperties '
        + 'OnGetStoredPropertyValue OnInitFilteringDateRanges OnSetStoredPropertyValue OnUserFiltering '
        + 'OnUserFilteringEx OnValidateDrawValue Styles.OnGetContentStyle'),
    (Name: 'TcxGridColumn'; Ancestor: ROOT_ITEM_CLASS;
      Events: 'OnCompareRowValuesForCellMerging OnCompareValuesForCellMerging OnCustomDrawFooterCell '
        + 'OnCustomDrawGroupSummaryCell OnCustomDrawHeader OnHeaderClick OnInitGroupingDateRanges '
        + 'Styles.OnGetFooterStyle Styles.OnGetFooterStyleEx Styles.OnGetFooterSummaryStyle '
        + 'Styles.OnGetGroupSummaryStyle Styles.OnGetHeaderStyle'),
    (Name: 'TcxGridBandedColumn'; Ancestor: 'TcxGridColumn'; Events: ''),
    (Name: 'TcxGridDBColumn'; Ancestor: 'TcxGridColumn'; Events: ''),
    (Name: 'TcxGridDBBandedColumn'; Ancestor: 'TcxGridBandedColumn'; Events: ''),
    (Name: 'TcxGridCardViewRow'; Ancestor: ROOT_ITEM_CLASS;
      Events: 'Styles.OnGetCaptionRowStyle Styles.OnGetCaptionStyle Styles.OnGetCategoryRowStyle'),
    (Name: 'TcxGridDBCardViewRow'; Ancestor: 'TcxGridCardViewRow'; Events: ''),
    (Name: 'TcxGridLayoutViewItem'; Ancestor: ROOT_ITEM_CLASS; Events: ''),
    (Name: 'TcxGridDBLayoutViewItem'; Ancestor: 'TcxGridLayoutViewItem'; Events: ''));

  { Events of `DataController.`: TcxGridDBDataController (data-bound views) and TcxGridDataController publish
    different sets, and a data-bound view class descends from the unbound one, so the class table cannot hold them. }
  DC_COMMON = 'OnCanSelectRecord OnCompare OnDataChanged OnDetailCollapsing OnDetailCollapsed OnDetailExpanding '
    + 'OnDetailExpanded OnFilterRecord OnFindCriteriaBeforeChange OnFindCriteriaChanged OnGroupingChanged '
    + 'OnSortingChanged';
  DC_BOUND_ONLY = 'OnDetailHasChildren';
  DC_UNBOUND_ONLY = 'OnAfterCancel OnAfterDelete OnAfterInsert OnAfterPost OnBeforeCancel OnBeforeDelete '
    + 'OnBeforeInsert OnBeforePost OnNewRecord OnRecordChanged';
  DC_ORIGIN_COMMON = 'data controller';
  DC_ORIGIN_BOUND = 'data-bound data controller';
  DC_ORIGIN_UNBOUND = 'unbound data controller';

{ ---- the class tables ---- }

function ViewIndex(const pClass: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := Low(GC_VIEWS) to High(GC_VIEWS) do
    if SameText(GC_VIEWS[VI].ViewClass, pClass) then
      Exit(VI);
end;

function ClassIndex(const pClass: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  if pClass = '' then
    Exit;
  for VI := Low(GC_CLASSES) to High(GC_CLASSES) do
    if SameText(GC_CLASSES[VI].Name, pClass) then
      Exit(VI);
end;

function HasWord(const pWords, pWord: string): Boolean;
begin
  Result := MatchText(pWord, pWords.Split([' ']));
end;

{ The class that publishes the event for pClass; '' = pClass does not have it (or the table does not know it). }
function EventOrigin(const pClass, pPath: string): string;
var
  VI: Integer;
begin
  VI := ClassIndex(pClass);
  while VI >= 0 do
  begin
    if HasWord(GC_CLASSES[VI].Events, pPath) then
      Exit(GC_CLASSES[VI].Name);
    VI := ClassIndex(GC_CLASSES[VI].Ancestor);
  end;
  Result := '';
end;

function InheritsClass(const pClass, pAncestor: string): Boolean;
var
  VI: Integer;
begin
  VI := ClassIndex(pClass);
  while VI >= 0 do
  begin
    if SameText(GC_CLASSES[VI].Name, pAncestor) then
      Exit(True);
    VI := ClassIndex(GC_CLASSES[VI].Ancestor);
  end;
  Result := False;
end;

function IsItemClass(const pClass: string): Boolean;
begin
  Result := InheritsClass(pClass, ROOT_ITEM_CLASS);
end;

function DataControllerOrigin(const pPath: string; pBound: Boolean): string;
var
  VName: string;
begin
  VName := pPath.Substring(Length(PREFIX_DATA_CONTROLLER));
  if HasWord(DC_COMMON, VName) then
    Exit(DC_ORIGIN_COMMON);
  if pBound and HasWord(DC_BOUND_ONLY, VName) then
    Exit(DC_ORIGIN_BOUND);
  if (not pBound) and HasWord(DC_UNBOUND_ONLY, VName) then
    Exit(DC_ORIGIN_UNBOUND);
  Result := '';
end;

{ May the handler of event pPath of pSrc serve the same event of pDst? pWhy says why not. }
function EventVerdict(const pSrc, pDst: TGcSide; const pPath: string; out pWhy: string): TGcVerdict;
var
  VSrcOrigin, VDstOrigin: string;
begin
  pWhy := '';
  Result := gvOk;
  if StartsText(PREFIX_EDITOR, pPath) then
  begin
    if not SameText(pSrc.Editor, pDst.Editor) then
    begin
      pWhy := 'the target column has the editor ' + (if pDst.Editor = '' then '(none)' else pDst.Editor) + ', not '
        + (if pSrc.Editor = '' then '(none)' else pSrc.Editor);
      Result := gvBlocked;
    end;
    Exit;
  end;
  if SameText(pSrc.ObjClass, pDst.ObjClass) then
    Exit;
  if StartsText(PREFIX_DATA_CONTROLLER, pPath) then
  begin
    VSrcOrigin := DataControllerOrigin(pPath, pSrc.Bound);
    VDstOrigin := DataControllerOrigin(pPath, pDst.Bound);
  end
  else
  begin
    if InheritsClass(pDst.ObjClass, pSrc.ObjClass) then
      Exit;
    VSrcOrigin := EventOrigin(pSrc.ObjClass, pPath);
    VDstOrigin := EventOrigin(pDst.ObjClass, pPath);
  end;
  if VSrcOrigin = '' then
  begin
    pWhy := 'drag-lint does not know the event ' + pPath + ' of ' + pSrc.ObjClass + ': check that ' + pDst.ObjClass
      + ' has it with the same parameters';
    Exit(gvUnchecked);
  end;
  if VDstOrigin = '' then
  begin
    pWhy := pDst.ObjClass + ' has no event ' + pPath;
    Exit(gvBlocked);
  end;
  if not SameText(VSrcOrigin, VDstOrigin) then
  begin
    pWhy := pSrc.ObjClass + ' and ' + pDst.ObjClass + ' declare ' + pPath
      + ' separately: compare the handler''s parameters';
    Result := gvUnchecked;
  end;
end;

function IndexOfId(const pIds: TArray<Integer>; pId: Integer): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(pIds) do
    if pIds[VI] = pId then
      Exit(VI);
end;

{ ---- the planner ---- }

type
  TGridCopyPlanner = class  // dl:ok god-class@43e5, high-response@43e5 -- GCP-M: one planner per copy: reader of the DFM, the plan under construction and its naming state; a split would pass all three around; GCP-M: the planner is the only caller of the DFM reader in this unit; see god-class
  strict private
    FForm: TGridCopyForm;
    FDoc: TDfmDocument;
    FUnitText: string;
    FFormClass: string;
    FPlan: TGridCopyPlan;
    FSrc: Integer;
    FDst: Integer;
    FSrcView: TGcView;
    FDstView: TGcView;
    FSourceNames: TArray<string>;
    FUnitDoc: TDfmUnitDocument;
    FUnitChecked: Boolean;
    FUnitProblem: string;
    FTaken: TArray<string>;
    FUsedTargets: TArray<Integer>;
    FBandsDone: Boolean;
    FNextColumn: Integer;
    function UnitProblem: string;
    function NameTaken(const pName: string): Boolean;
    function NewColumnName(const pSourceName: string): string;
    function KeepsProp(const pName: string): Boolean;
    function PropLines(const pProp: TDfmwProp): TArray<string>;
    function EditorLines(pItem: Integer): string;
    function ColumnBlocked(pItem: Integer): string;
    procedure EnsureBands;
    procedure AddColumn(pItem: Integer);
    procedure PlanEverything;
    function Raw(pFrom, pTo: Integer): string;
    function IndentOf(pPos: Integer): string;
    function TargetOf(const pComponent: string): string;
    function ViewOf(const pName: string; out pView: TGcView): Integer;
    function IsEvent(const pProp: TDfmwProp; out pHandler: string): Boolean;
    function FieldOf(pObject: Integer): string;
    function EditorOf(pObject: Integer): string;
    function ItemByField(pView: Integer; const pField: string): Integer;
    function SideOf(pObject: Integer; pBound: Boolean): TGcSide;
    function HandlerNamesSource(const pHandler: string): string;
    function AddChange(pOp: TFrChangeOp; const pComponent, pProp, pOld, pNew: string): Integer;
    function AddEventChange(const pSrc, pDst: TGcSide; const pStep: TGridCopyStep; const pComponent, pOld: string): Integer;
    procedure AddEvent(pSrcObject, pDstObject: Integer; const pPath, pHandler: string);
    procedure PlanOneEvent;
    procedure Seal;
  public
    constructor Create(const pForm: TGridCopyForm);
    destructor Destroy; override;
    function Items(pView: Integer): TArray<Integer>;
    function View(const pName: string; out pView: TGcView): Integer;
    function Events(pView: Integer): TArray<TGridCopyEvent>;
    function Columns(pView: Integer): TArray<TFrGridColumn>;
    function Plan(const pRequest: TGridCopyRequest): TGridCopyPlan;
    property Doc: TDfmDocument read FDoc;
  end;

function BytesText(const pBytes: TBytes; pFrom, pTo: Integer): string;
var
  VI: Integer;
begin
  SetLength(Result, pTo - pFrom);
  for VI := pFrom to pTo - 1 do
    Result[VI - pFrom + 1] := Char(pBytes[VI]);
end;

constructor TGridCopyPlanner.Create(const pForm: TGridCopyForm);
begin
  inherited Create;
  FForm := pForm;
  FDoc := TDfmDocument.Create(pForm.DfmBytes, pForm.DfmFile);
  if Length(FDoc.Objects) > 0 then
    FFormClass := FDoc.Objects[0].ObjClass;
  FUnitText := BytesText(pForm.UnitBytes, 0, Length(pForm.UnitBytes));
end;

destructor TGridCopyPlanner.Destroy;
begin
  FUnitDoc.Free;
  FDoc.Free;
  inherited;
end;

function TGridCopyPlanner.Raw(pFrom, pTo: Integer): string;
begin
  Result := BytesText(FForm.DfmBytes, pFrom, pTo);
end;

{ The blanks before the text at pPos on its line. }
function TGridCopyPlanner.IndentOf(pPos: Integer): string;
var
  VStart: Integer;
begin
  VStart := pPos;
  while (VStart > 0) and (FForm.DfmBytes[VStart - 1] not in [BYTE_LF, BYTE_CR]) do
    Dec(VStart);
  Result := Raw(VStart, pPos);
end;

function TGridCopyPlanner.TargetOf(const pComponent: string): string;
begin
  Result := ExtractFileName(FForm.DfmFile) + ' ' + pComponent;
end;

function TGridCopyPlanner.ViewOf(const pName: string; out pView: TGcView): Integer;
var
  VIdx, VParent: Integer;
begin
  pView := Default(TGcView);
  Result := if pName = '' then -1 else FDoc.FindObject(pName, '');
  if Result < 0 then
    raise EGridCopyError.Create(FForm.DfmFile + ': no grid view ' + pName);
  VIdx := ViewIndex(FDoc.Objects[Result].ObjClass);
  if VIdx < 0 then
    raise EGridCopyError.Create(FForm.DfmFile + ': ' + pName + ' is a ' + FDoc.Objects[Result].ObjClass
      + ', not a grid view the copy knows (table, banded table, card or layout view)');
  pView := GC_VIEWS[VIdx];
  VParent := FDoc.Objects[Result].Parent;
  while VParent > 0 do
  begin
    if SameText(FDoc.Objects[VParent].Kind, KIND_INLINE) then
      raise EGridCopyError.Create(FForm.DfmFile + ': ' + pName + ' belongs to the frame instance '
        + FDoc.Objects[VParent].Name + ': copy in the DFM of the frame');
    VParent := FDoc.Objects[VParent].Parent;
  end;
end;

function TGridCopyPlanner.View(const pName: string; out pView: TGcView): Integer;
begin
  Result := ViewOf(pName, pView);
end;

function TGridCopyPlanner.Items(pView: Integer): TArray<Integer>;
var
  VI: Integer;
begin
  Result := nil;
  for VI := pView + 1 to High(FDoc.Objects) do
    if (FDoc.Objects[VI].Parent = pView) and IsItemClass(FDoc.Objects[VI].ObjClass) then
      Result := Result + [VI];
end;

function TGridCopyPlanner.IsEvent(const pProp: TDfmwProp; out pHandler: string): Boolean;
var
  VLast: string;
begin
  VLast := pProp.Name.Substring(pProp.Name.LastIndexOf('.') + 1);
  pHandler := Raw(pProp.ValueStart, pProp.ValueEnd).Trim;
  Result := (Length(VLast) > EVENT_PREFIX_LENGTH) and VLast.StartsWith(EVENT_PREFIX)
    and CharInSet(VLast[EVENT_PREFIX_LENGTH + 1], ['A'..'Z']) and IsValidIdent(pHandler)
    and not MatchText(pHandler, ['True', 'False', 'nil']);
end;

function TGridCopyPlanner.FieldOf(pObject: Integer): string;
begin
  FDoc.TryProp(pObject, PROP_FIELD_NAME, Result);
end;

function TGridCopyPlanner.EditorOf(pObject: Integer): string;
begin
  FDoc.TryProp(pObject, PROP_EDITOR_CLASS, Result);
end;

function TGridCopyPlanner.SideOf(pObject: Integer; pBound: Boolean): TGcSide;
begin
  Result.ObjClass := FDoc.Objects[pObject].ObjClass;
  Result.Bound := pBound;
  Result.Editor := EditorOf(pObject);
end;

function TGridCopyPlanner.ItemByField(pView: Integer; const pField: string): Integer;
var
  VItem: Integer;
begin
  Result := -1;
  if pField = '' then
    Exit;
  for VItem in Items(pView) do
    if SameText(FieldOf(VItem), pField) then
      Exit(VItem);
end;

function TGridCopyPlanner.Events(pView: Integer): TArray<TGridCopyEvent>;
var
  VObjects: TArray<Integer>;
  VObject: Integer;
  VProp: TDfmwProp;
  VEvent: TGridCopyEvent;
begin
  Result := nil;
  VObjects := [pView] + Items(pView);
  for VObject in VObjects do
    for VProp in FDoc.Objects[VObject].Props do
      if IsEvent(VProp, VEvent.Handler) then
      begin
        VEvent.Component := FDoc.Objects[VObject].Name;
        VEvent.ComponentClass := FDoc.Objects[VObject].ObjClass;
        VEvent.IsColumn := VObject <> pView;
        VEvent.Event := VProp.Name;
        Result := Result + [VEvent];
      end;
end;

function TGridCopyPlanner.Columns(pView: Integer): TArray<TFrGridColumn>;
var
  VItem: Integer;
  VColumn: TFrGridColumn;
begin
  Result := nil;
  for VItem in Items(pView) do
  begin
    VColumn := Default(TFrGridColumn);
    VColumn.FormName := FDoc.Objects[0].Name;
    VColumn.ViewName := FDoc.Objects[pView].Name;
    VColumn.ColumnName := FDoc.Objects[VItem].Name;
    VColumn.FieldName := FieldOf(VItem);
    VColumn.ColumnIndex := Length(Result);
    VColumn.PropertiesClassName := EditorOf(VItem);
    VColumn.Properties := EditorLines(VItem);
    Result := Result + [VColumn];
  end;
end;

{ The lines of a property without the indentation of its first line; the first line starts at the name. }
function TGridCopyPlanner.PropLines(const pProp: TDfmwProp): TArray<string>;
var
  VLine, VIndent: string;
begin
  Result := nil;
  VIndent := IndentOf(pProp.Start);
  for VLine in Raw(pProp.Start, pProp.ValueEnd).Split([#10]) do
    Result := Result + [(if VLine.StartsWith(VIndent) then VLine.Substring(Length(VIndent)) else VLine).TrimRight([#13])];
end;

function TGridCopyPlanner.EditorLines(pItem: Integer): string;
var
  VProp: TDfmwProp;
begin
  Result := '';
  for VProp in FDoc.Objects[pItem].Props do
    if StartsText(PREFIX_EDITOR, VProp.Name) then
      Result := Result + (if Result = '' then '' else CRLF) + string.Join(CRLF, PropLines(VProp));
end;

{ Why no column can be declared; '' = the unit declares the form class. Opens the unit once. }
function TGridCopyPlanner.UnitProblem: string;
begin
  if not FUnitChecked then
  begin
    FUnitChecked := True;
    if Length(FForm.UnitBytes) = 0 then
      FUnitProblem := 'no unit: a new column needs its declaration in the form class'
    else
      try
        FUnitDoc := TDfmUnitDocument.Create(FForm.UnitBytes, FForm.UnitFile);
        FUnitDoc.Declarations(FFormClass);
      except  // dl:ok try-except-swallowed@4259 -- GCP-M: not swallowed -- the message becomes the Blocked reason of every new column of the plan (UnitProblem)
        on E: EDfmWriteError do
          FUnitProblem := E.Message;
      end;
  end;
  Result := FUnitProblem;
end;

function TGridCopyPlanner.NameTaken(const pName: string): Boolean;
var
  VObject: TDfmwObject;
begin
  Result := MatchText(pName, FTaken) or ((FUnitDoc <> nil) and (FUnitDoc.Mentions(pName) > 0));
  if not Result then
    for VObject in FDoc.Objects do
      if SameText(VObject.Name, pName) then
        Exit(True);
end;

function TGridCopyPlanner.NewColumnName(const pSourceName: string): string;
var
  VBase, VSource, VTarget: string;
  VNumber: Integer;
begin
  VSource := FDoc.Objects[FSrc].Name;
  VTarget := FDoc.Objects[FDst].Name;
  VBase := VTarget + (if StartsText(VSource, pSourceName) then pSourceName.Substring(Length(VSource)) else pSourceName);
  Result := VBase;
  VNumber := 0;
  while NameTaken(Result) do
  begin
    Inc(VNumber);
    Result := VBase + VNumber.ToString;
  end;
  FTaken := FTaken + [Result];
end;

{ Does a property of a source column (not an event) go to a column of the target view? }
function TGridCopyPlanner.KeepsProp(const pName: string): Boolean;
begin
  if StartsText(PREFIX_POSITION, pName) then
    Exit(FSrcView.Layout = FDstView.Layout);
  if StartsText(PREFIX_BINDING, pName) then
    Exit(FSrcView.DataBound = FDstView.DataBound);
  Result := ((FSrcView.Layout in [gclTable, gclBanded]) and (FDstView.Layout in [gclTable, gclBanded]))
    or (FSrcView.Layout = FDstView.Layout) or StartsText(PREFIX_EDITOR, pName) or MatchText(pName, COMMON_ITEM_PROPS);
end;

function TGridCopyPlanner.ColumnBlocked(pItem: Integer): string;
var
  VI: Integer;
  VChar: Char;
begin
  if FDstView.Layout = gclLayout then
    Exit('an item of a layout view needs its layout item: add the item in the designer, then copy its events');
  for VI := pItem + 1 to High(FDoc.Objects) do
    if FDoc.Objects[VI].Parent = pItem then
      Exit(FDoc.Objects[pItem].Name + ' has a nested object (' + FDoc.Objects[VI].Name + ')');
  for VChar in Raw(FDoc.Objects[pItem].Start, FDoc.Objects[pItem].Finish) do
    if VChar > LAST_ASCII then
      Exit(FDoc.Objects[pItem].Name + ' has text that is not ASCII');
  Result := UnitProblem;
end;

{ Before the first new column of a banded target that has no bands: the source's bands, else one band. }
procedure TGridCopyPlanner.EnsureBands;
var
  VOld, VValue, VNew, VIndent, VLine: string;
  VProp: TDfmwProp;
  VStep: TGridCopyStep;
  VChar: Char;
  VAscii: Boolean;
begin
  if FBandsDone or (FDstView.Layout <> gclBanded) then
    Exit;
  FBandsDone := True;
  if FDoc.TryProp(FDst, PROP_BANDS, VOld) then
    Exit;
  VValue := BANDS_ONE;
  VNew := 'one band';
  if FSrcView.Layout = gclBanded then
    for VProp in FDoc.Objects[FSrc].Props do
      if SameText(VProp.Name, PROP_BANDS) then
      begin
        VAscii := True;
        for VChar in Raw(VProp.ValueStart, VProp.ValueEnd) do
          VAscii := VAscii and (VChar <= LAST_ASCII);
        if not VAscii then
          Continue;
        VIndent := IndentOf(FDoc.Objects[FSrc].Start);
        VValue := '';
        for VLine in Raw(VProp.ValueStart, VProp.ValueEnd).Split([#10]) do
          VValue := VValue + (if VValue = '' then '' else CRLF)
            + (if VLine.StartsWith(VIndent) then VLine.Substring(Length(VIndent)) else VLine).TrimRight([#13]);
        VNew := 'the bands of ' + FDoc.Objects[FSrc].Name;
      end;
  VStep := Default(TGridCopyStep);
  VStep.ChangeId := FPlan.Changes[AddChange(fcoInsert, FDoc.Objects[FDst].Name, PROP_BANDS, '', VNew)].Id;
  VStep.Kind := gskSetProp;
  VStep.ObjectIndex := FDst;
  VStep.Prop := PROP_BANDS;
  VStep.Value := VValue;
  FPlan.Steps := FPlan.Steps + [VStep];
end;

{ A source column no target column stands for: a new column and its events. }
procedure TGridCopyPlanner.AddColumn(pItem: Integer);
var
  VSource: TDfmwObject;
  VProp: TDfmwProp;
  VBlocked, VDropped, VHandler, VField: string;
  VIdx, VEvent, VStepIndex: Integer;
  VStep, VEventStep: TGridCopyStep;
  VColumn: TFrGridColumn;
  VTarget: TGcSide;
begin
  VSource := FDoc.Objects[pItem];
  VBlocked := ColumnBlocked(pItem);
  if VBlocked = '' then
    EnsureBands;
  VStep := Default(TGridCopyStep);
  VStep.Kind := gskInsertColumn;
  VStep.ObjectIndex := FDst;
  VStep.Name := NewColumnName(VSource.Name);
  VStep.ItemClass := FDstView.ItemClass;
  VField := if FSrcView.DataBound = FDstView.DataBound then FieldOf(pItem) else '';
  VIdx := AddChange(fcoInsert, VStep.Name, '', '', VStep.ItemClass + (if VField = '' then '' else ' ' + VField));
  VStep.ChangeId := FPlan.Changes[VIdx].Id;
  FPlan.Changes[VIdx].Blocked := VBlocked;
  FPlan.Changes[VIdx].Checked := VBlocked = '';
  if VBlocked <> '' then
    Exit;
  FPlan.Steps := FPlan.Steps + [VStep];
  VStepIndex := High(FPlan.Steps);
  VTarget.ObjClass := VStep.ItemClass;
  VTarget.Bound := FDstView.DataBound;
  VTarget.Editor := EditorOf(pItem);
  VDropped := '';
  for VProp in VSource.Props do
    if IsEvent(VProp, VHandler) then
    begin
      VEventStep := Default(TGridCopyStep);
      VEventStep.Kind := gskSetProp;
      VEventStep.ObjectIndex := -1;
      VEventStep.DependsOn := VStep.ChangeId;
      VEventStep.Prop := VProp.Name;
      VEventStep.Value := VHandler;
      VEvent := AddEventChange(SideOf(pItem, FSrcView.DataBound), VTarget, VEventStep, VStep.Name, '');
      if FPlan.Changes[VEvent].Blocked = '' then
        VStep.Lines := VStep.Lines + [EVENT_MARK + FPlan.Changes[VEvent].Id.ToString];
    end
    else if KeepsProp(VProp.Name) then
      VStep.Lines := VStep.Lines + [STEP + string.Join(CRLF + STEP, PropLines(VProp))]
    else
      VDropped := VDropped + (if VDropped = '' then '' else ', ') + VProp.Name;
  if (FDstView.Layout = gclBanded) and (FSrcView.Layout <> gclBanded) then
    VStep.Lines := VStep.Lines + [STEP + 'Position.BandIndex = 0', STEP + 'Position.ColIndex = ' + FNextColumn.ToString,
      STEP + 'Position.RowIndex = 0'];
  FPlan.Steps[VStepIndex] := VStep;
  if VDropped <> '' then
    FPlan.Notes[VIdx] := 'not copied: ' + VDropped;
  VColumn := Default(TFrGridColumn);
  VColumn.FormName := FDoc.Objects[0].Name;
  VColumn.ViewName := FDoc.Objects[FDst].Name;
  VColumn.ColumnName := VStep.Name;
  VColumn.FieldName := VField;
  VColumn.ColumnIndex := FNextColumn;
  VColumn.PropertiesClassName := VTarget.Editor;
  VColumn.Properties := EditorLines(pItem);
  FPlan.Columns := FPlan.Columns + [VColumn];
  Inc(FNextColumn);
end;

procedure TGridCopyPlanner.PlanEverything;
var
  VProp: TDfmwProp;
  VHandler: string;
  VItem, VMatch, VTarget: Integer;
begin
  if FSrc = FDst then
    raise EGridCopyError.Create(FForm.DfmFile + ': source and target are the same view ' + FDoc.Objects[FSrc].Name);
  UnitProblem;
  FNextColumn := Length(Items(FDst));
  for VProp in FDoc.Objects[FSrc].Props do
    if IsEvent(VProp, VHandler) then
      AddEvent(FSrc, FDst, VProp.Name, VHandler);
  for VItem in Items(FSrc) do
  begin
    VMatch := -1;
    if FieldOf(VItem) <> '' then
      for VTarget in Items(FDst) do
        if (VMatch < 0) and SameText(FieldOf(VTarget), FieldOf(VItem)) and (IndexOfId(FUsedTargets, VTarget) < 0) then
          VMatch := VTarget;
    if VMatch < 0 then
    begin
      AddColumn(VItem);
      Continue;
    end;
    FUsedTargets := FUsedTargets + [VMatch];
    for VProp in FDoc.Objects[VItem].Props do
      if IsEvent(VProp, VHandler) then
        AddEvent(VItem, VMatch, VProp.Name, VHandler);
  end;
  if Length(FPlan.Changes) = 0 then
    FPlan.Remarks := [FDoc.Objects[FDst].Name + ' has every event and column of ' + FDoc.Objects[FSrc].Name + ' already'];
end;

{ The first name of the source view (the view, its columns) that the body of the handler mentions; '' = none, no
  unit, or the method is not in the unit. The body ends at the next routine that starts in column 1. }
function TGridCopyPlanner.HandlerNamesSource(const pHandler: string): string;
var
  VHead, VNext: TMatch;
  VBody, VName: string;
begin
  Result := '';
  if (FUnitText = '') or (FFormClass = '') then
    Exit;
  VHead := TRegEx.Match(FUnitText, '^[ \t]*(procedure|function)[ \t]+' + TRegEx.Escape(FFormClass) + '\.'
    + TRegEx.Escape(pHandler) + '\b', [roIgnoreCase, roMultiLine]);
  if not VHead.Success then
    Exit;
  VBody := FUnitText.Substring(VHead.Index - 1 + VHead.Length);
  VNext := TRegEx.Match(VBody,
    '^(procedure|function|constructor|destructor|class[ \t]+(procedure|function)|initialization|finalization|end\.)',
    [roIgnoreCase, roMultiLine]);
  if VNext.Success then
    VBody := VBody.Substring(0, VNext.Index - 1);
  for VName in FSourceNames do
    if TRegEx.IsMatch(VBody, '\b' + TRegEx.Escape(VName) + '\b', [roIgnoreCase]) then
      Exit(VName);
end;

function TGridCopyPlanner.AddChange(pOp: TFrChangeOp; const pComponent, pProp, pOld, pNew: string): Integer;
var
  VChange: TFrChange;
begin
  VChange := Default(TFrChange);
  VChange.Id := Length(FPlan.Changes) + 1;
  VChange.Op := pOp;
  VChange.Target := TargetOf(pComponent);
  VChange.Prop := pProp;
  VChange.OldValue := pOld;
  VChange.NewValue := pNew;
  VChange.Checked := True;
  FPlan.Changes := FPlan.Changes + [VChange];
  FPlan.Notes := FPlan.Notes + [''];
  Result := High(FPlan.Changes);
end;

{ The change and the step of one event (pStep: Prop = the event, Value = the handler, the target); the index of the
  change. pOld = the handler the target component pComponent has now. }
function TGridCopyPlanner.AddEventChange(const pSrc, pDst: TGcSide; const pStep: TGridCopyStep;
  const pComponent, pOld: string): Integer;
var
  VWhy, VNamed, VNote: string;
  VStep: TGridCopyStep;
begin
  Result := AddChange(if pOld = '' then fcoInsert else fcoUpdate, pComponent, pStep.Prop, pOld, pStep.Value);
  VNote := '';
  case EventVerdict(pSrc, pDst, pStep.Prop, VWhy) of
    gvBlocked:
      FPlan.Changes[Result].Blocked := VWhy;
    gvUnchecked:
      VNote := VWhy;
  end;
  if pOld <> '' then
    VNote := VNote + (if VNote = '' then '' else '; ') + 'replaces the handler ' + pOld;
  VNamed := HandlerNamesSource(pStep.Value);
  if VNamed <> '' then
    VNote := VNote + (if VNote = '' then '' else '; ') + 'the handler names ' + VNamed + ' of the source';
  FPlan.Notes[Result] := VNote;
  FPlan.Changes[Result].Checked := (FPlan.Changes[Result].Blocked = '') and (VNote = '');
  VStep := pStep;
  VStep.ChangeId := FPlan.Changes[Result].Id;
  FPlan.Steps := FPlan.Steps + [VStep];
end;

{ One event of an existing source object to an existing target object. }
procedure TGridCopyPlanner.AddEvent(pSrcObject, pDstObject: Integer; const pPath, pHandler: string);
var
  VOld: string;
  VStep: TGridCopyStep;
begin
  FDoc.TryProp(pDstObject, pPath, VOld);
  if SameText(VOld, pHandler) then
  begin
    if FPlan.Request.EventName <> '' then
      FPlan.Remarks := FPlan.Remarks + [FDoc.Objects[pDstObject].Name + '.' + pPath + ' is ' + pHandler + ' already'];
    Exit;
  end;
  VStep := Default(TGridCopyStep);
  VStep.Kind := gskSetProp;
  VStep.ObjectIndex := pDstObject;
  VStep.Prop := pPath;
  VStep.Value := pHandler;
  AddEventChange(SideOf(pSrcObject, FSrcView.DataBound), SideOf(pDstObject, FDstView.DataBound), VStep,
    FDoc.Objects[pDstObject].Name, VOld);
end;

procedure TGridCopyPlanner.PlanOneEvent;
var
  VSrcObject, VDstObject: Integer;
  VProp: TDfmwProp;
  VHandler, VFound: string;
  VRequest: TGridCopyRequest;
begin
  VRequest := FPlan.Request;
  VSrcObject := FSrc;
  VDstObject := FDst;
  if VRequest.SourceColumn <> '' then
  begin
    VSrcObject := FDoc.FindObject(VRequest.SourceColumn, VRequest.SourceView);
    if (VSrcObject < 0) or not IsItemClass(FDoc.Objects[VSrcObject].ObjClass) then
      raise EGridCopyError.Create(FForm.DfmFile + ': ' + VRequest.SourceView + ' has no column '
        + VRequest.SourceColumn);
    if VRequest.TargetColumn <> '' then
    begin
      VDstObject := FDoc.FindObject(VRequest.TargetColumn, VRequest.TargetView);
      if (VDstObject < 0) or not IsItemClass(FDoc.Objects[VDstObject].ObjClass) then
        raise EGridCopyError.Create(FForm.DfmFile + ': ' + VRequest.TargetView + ' has no column '
          + VRequest.TargetColumn);
    end
    else
    begin
      VDstObject := ItemByField(FDst, FieldOf(VSrcObject));
      if (VDstObject < 0) or (VDstObject = VSrcObject) then
        raise EGridCopyError.Create(FForm.DfmFile + ': no column of ' + VRequest.TargetView + ' shows the field '
          + (if FieldOf(VSrcObject) = '' then '(none)' else FieldOf(VSrcObject)) + ' of ' + VRequest.SourceColumn
          + ': name the target column, or copy the column first');
    end;
  end
  else if VRequest.TargetColumn <> '' then
    raise EGridCopyError.Create('an event of a view cannot go to the column ' + VRequest.TargetColumn);
  if VSrcObject = VDstObject then
    raise EGridCopyError.Create(FForm.DfmFile + ': source and target are the same component '
      + FDoc.Objects[VSrcObject].Name);
  if FSrc = FDst then
    FSourceNames := [FDoc.Objects[VSrcObject].Name];
  VFound := '';
  for VProp in FDoc.Objects[VSrcObject].Props do
    if SameText(VProp.Name, VRequest.EventName) and IsEvent(VProp, VHandler) then
      VFound := VHandler;
  if VFound = '' then
    raise EGridCopyError.Create(FForm.DfmFile + ': ' + FDoc.Objects[VSrcObject].Name + ' has no handler for the event '
      + VRequest.EventName);
  AddEvent(VSrcObject, VDstObject, VRequest.EventName, VFound);
end;

{ The plan id: the form bytes, the request and the changes. }
procedure TGridCopyPlanner.Seal;
var
  VText: string;
begin
  VText := THashSHA2.GetHashString(Raw(0, Length(FForm.DfmBytes))) + #10 + THashSHA2.GetHashString(FUnitText) + #10
    + FPlan.Request.SourceView + #10 + FPlan.Request.TargetView + #10 + FPlan.Request.EventName + #10
    + FPlan.Request.SourceColumn + #10 + FPlan.Request.TargetColumn + #10;
  FPlan.PlanId := '';
  FPlan.PlanId := THashSHA2.GetHashString(VText + RenderGridCopyJson(FPlan)).Substring(0, PLAN_ID_LENGTH);
end;

function TGridCopyPlanner.Plan(const pRequest: TGridCopyRequest): TGridCopyPlan;
var
  VItem: Integer;
begin
  FPlan := Default(TGridCopyPlan);
  FPlan.Form := FForm;
  FPlan.Request := pRequest;
  FSrc := ViewOf(pRequest.SourceView, FSrcView);
  FDst := ViewOf(pRequest.TargetView, FDstView);
  FPlan.SourceClass := FDoc.Objects[FSrc].ObjClass;
  FPlan.TargetClass := FDoc.Objects[FDst].ObjClass;
  FSourceNames := [FDoc.Objects[FSrc].Name];
  for VItem in Items(FSrc) do
    FSourceNames := FSourceNames + [FDoc.Objects[VItem].Name];
  if pRequest.EventName <> '' then
    PlanOneEvent
  else
    PlanEverything;
  Seal;
  Result := FPlan;
end;

{ ---- the public functions ---- }

class function TGridCopyRequest.Everything(const pSourceView, pTargetView: string): TGridCopyRequest;
begin
  Result := Default(TGridCopyRequest);
  Result.SourceView := pSourceView;
  Result.TargetView := pTargetView;
end;

class function TGridCopyRequest.OneEvent(const pSourceView, pTargetView, pEvent, pSourceColumn,
  pTargetColumn: string): TGridCopyRequest;
begin
  Result := Everything(pSourceView, pTargetView);
  Result.EventName := pEvent;
  Result.SourceColumn := pSourceColumn;
  Result.TargetColumn := pTargetColumn;
end;

function GridCopyViews(const pForm: TGridCopyForm): TArray<TGridCopyViewInfo>;
var
  VPlanner: TGridCopyPlanner;
  VI, VIdx: Integer;
  VInfo: TGridCopyViewInfo;
begin
  Result := nil;
  VPlanner := TGridCopyPlanner.Create(pForm);
  try
    for VI := 0 to High(VPlanner.Doc.Objects) do
    begin
      VIdx := ViewIndex(VPlanner.Doc.Objects[VI].ObjClass);
      if (VIdx < 0) or (VPlanner.Doc.Objects[VI].Name = '') then
        Continue;
      VInfo.Name := VPlanner.Doc.Objects[VI].Name;
      VInfo.ViewClass := VPlanner.Doc.Objects[VI].ObjClass;
      VInfo.ItemClass := GC_VIEWS[VIdx].ItemClass;
      VInfo.ColumnCount := Length(VPlanner.Items(VI));
      Result := Result + [VInfo];
    end;
  finally
    VPlanner.Free;
  end;
end;

function GridCopyEvents(const pForm: TGridCopyForm; const pView: string): TArray<TGridCopyEvent>;
var
  VPlanner: TGridCopyPlanner;
  VView: TGcView;
begin
  VPlanner := TGridCopyPlanner.Create(pForm);
  try
    Result := VPlanner.Events(VPlanner.View(pView, VView));
  finally
    VPlanner.Free;
  end;
end;

function GridViewColumns(const pForm: TGridCopyForm; const pView: string): TArray<TFrGridColumn>;
var
  VPlanner: TGridCopyPlanner;
  VView: TGcView;
begin
  VPlanner := TGridCopyPlanner.Create(pForm);
  try
    Result := VPlanner.Columns(VPlanner.View(pView, VView));
  finally
    VPlanner.Free;
  end;
end;

function PlanGridCopy(const pForm: TGridCopyForm; const pRequest: TGridCopyRequest): TGridCopyPlan;
var
  VPlanner: TGridCopyPlanner;
begin
  VPlanner := TGridCopyPlanner.Create(pForm);
  try
    Result := VPlanner.Plan(pRequest);
  finally
    VPlanner.Free;
  end;
end;

function GridCopyDefaultIds(const pPlan: TGridCopyPlan): TArray<Integer>;
var
  VChange: TFrChange;
begin
  Result := nil;
  for VChange in pPlan.Changes do
    if VChange.Checked and (VChange.Blocked = '') then
      Result := Result + [VChange.Id];
end;

function SelectGridCopy(const pPlan: TGridCopyPlan; const pLines: TArray<string>): TArray<Integer>;
var
  VSet: TFrChangeSet;
  VLine: string;
  VMatch: TMatch;
  VChange: TFrChange;
begin
  Result := nil;
  for VLine in pLines do
  begin
    VMatch := TRegEx.Match(VLine, '^#\s*plan\s+(\S+)\s*$');
    if VMatch.Success and not SameText(VMatch.Groups[1].Value, pPlan.PlanId) then
      raise EGridCopyError.Create('the selection is of plan ' + VMatch.Groups[1].Value + ', this is plan '
        + pPlan.PlanId + ': make the selection from a new dry run');
  end;
  VSet.Direction := fdRepoToDfm; // SelectChanges does not read it
  VSet.Changes := pPlan.Changes;
  for VChange in SelectChanges(VSet, pLines) do
    Result := Result + [VChange.Id];
end;

procedure CheckIds(const pPlan: TGridCopyPlan; const pIds: TArray<Integer>);
var
  VId: Integer;
  VStep: TGridCopyStep;
begin
  for VId in pIds do
  begin
    if (VId < 1) or (VId > Length(pPlan.Changes)) then
      raise EGridCopyError.CreateFmt('the plan has no change %d', [VId]);
    if pPlan.Changes[VId - 1].Blocked <> '' then
      raise EGridCopyError.CreateFmt('change %d is blocked: %s', [VId, pPlan.Changes[VId - 1].Blocked]);
  end;
  for VStep in pPlan.Steps do
    if (VStep.DependsOn <> 0) and (IndexOfId(pIds, VStep.ChangeId) >= 0) and (IndexOfId(pIds, VStep.DependsOn) < 0) then
      raise EGridCopyError.CreateFmt('change %d is an event of the column that change %d adds: choose both',
        [VStep.ChangeId, VStep.DependsOn]);
end;

{ The block of a new column: its lines, the events among them only when their change is chosen. }
function ColumnBlock(const pPlan: TGridCopyPlan; const pColumn: TGridCopyStep; const pIds: TArray<Integer>): TArray<string>;
var
  VLine: string;
  VStep: TGridCopyStep;
  VId: Integer;
begin
  Result := ['object ' + pColumn.Name + ': ' + pColumn.ItemClass];
  for VLine in pColumn.Lines do
    if not VLine.StartsWith(EVENT_MARK) then
      Result := Result + VLine.Split([CRLF])
    else
    begin
      VId := VLine.Substring(Length(EVENT_MARK)).ToInteger;
      if IndexOfId(pIds, VId) >= 0 then
        for VStep in pPlan.Steps do
          if VStep.ChangeId = VId then
            Result := Result + [STEP + VStep.Prop + ' = ' + VStep.Value];
    end;
  Result := Result + ['end'];
end;

{ The new columns of the chosen changes: their blocks after the view's columns, their declarations after them too. }
function InsertColumns(const pPlan: TGridCopyPlan; const pIds: TArray<Integer>; pDoc: TDfmDocument;
  pUnit: TDfmUnitDocument): Boolean;
var
  VStep: TGridCopyStep;
  VSiblings: TArray<string>;
  VI: Integer;
begin
  Result := False;
  for VStep in pPlan.Steps do
    if (VStep.Kind = gskInsertColumn) and (IndexOfId(pIds, VStep.ChangeId) >= 0) then
    begin
      VSiblings := nil;
      for VI := VStep.ObjectIndex + 1 to High(pDoc.Objects) do
        if (pDoc.Objects[VI].Parent = VStep.ObjectIndex) and IsItemClass(pDoc.Objects[VI].ObjClass) then
          VSiblings := VSiblings + [pDoc.Objects[VI].Name];
      pDoc.InsertChild(VStep.ObjectIndex, ColumnBlock(pPlan, VStep, pIds), VSiblings);
      pUnit.AddField(pDoc.Objects[0].ObjClass, VStep.Name, VStep.ItemClass,
        VSiblings + [pDoc.Objects[VStep.ObjectIndex].Name]);
      Result := True;
    end;
end;

function ApplyGridCopy(const pPlan: TGridCopyPlan; const pIds: TArray<Integer>): TArray<TDfmwOutput>;
var
  VDoc: TDfmDocument;
  VUnit: TDfmUnitDocument;
  VStep: TGridCopyStep;
  VOutput, VUnitOutput: TDfmwOutput;
  VColumns: Boolean;
begin
  Result := nil;
  CheckIds(pPlan, pIds);
  if Length(pIds) = 0 then
    Exit;
  VUnit := nil;
  VDoc := TDfmDocument.Create(pPlan.Form.DfmBytes, pPlan.Form.DfmFile);
  try
    if Length(pPlan.Form.UnitBytes) > 0 then
      VUnit := TDfmUnitDocument.Create(pPlan.Form.UnitBytes, pPlan.Form.UnitFile);
    for VStep in pPlan.Steps do
      if (VStep.Kind = gskSetProp) and (VStep.ObjectIndex >= 0) and (IndexOfId(pIds, VStep.ChangeId) >= 0) then
        VDoc.SetProp(VStep.ObjectIndex, VStep.Prop, VStep.Value, nil);
    VColumns := InsertColumns(pPlan, pIds, VDoc, VUnit);
    VOutput.FileName := pPlan.Form.DfmFile;
    VOutput.OldBytes := pPlan.Form.DfmBytes;
    VOutput.NewBytes := VDoc.Output;
    VUnitOutput.FileName := pPlan.Form.UnitFile;
    VUnitOutput.OldBytes := pPlan.Form.UnitBytes;
    if VColumns then
      VUnitOutput.NewBytes := VUnit.Output;
  finally
    VUnit.Free;
    VDoc.Free;
  end;
  DfmTextToBinary(VOutput.NewBytes);
  Result := [VOutput];
  if VColumns then
    Result := Result + [VUnitOutput];
end;

function CountOf(const pPlan: TGridCopyPlan; pBlocked: Boolean): Integer;
var
  VChange: TFrChange;
begin
  Result := 0;
  for VChange in pPlan.Changes do
    if (pBlocked = (VChange.Blocked <> '')) and (pBlocked or not VChange.Checked) then
      Inc(Result);
end;

function RenderGridCopyText(const pPlan: TGridCopyPlan): TArray<string>;
var
  VI, VLine: Integer;
  VOne: TFrChangeSet;
  VLines: TArray<string>;
  VRemark: string;
begin
  Result := ['# plan ' + pPlan.PlanId,
    Format('copy %s (%s) -> %s (%s) in %s: %d changes, %d blocked, %d unchecked', [pPlan.Request.SourceView,
      pPlan.SourceClass, pPlan.Request.TargetView, pPlan.TargetClass, ExtractFileName(pPlan.Form.DfmFile),
      Length(pPlan.Changes), CountOf(pPlan, True), CountOf(pPlan, False)])];
  VOne.Direction := fdRepoToDfm; // only the change lines are taken
  for VI := 0 to High(pPlan.Changes) do
  begin
    VOne.Changes := [pPlan.Changes[VI]];
    VLines := RenderChangeSetText(VOne);
    for VLine := 1 to High(VLines) do
      Result := Result + [VLines[VLine]];
    if pPlan.Notes[VI] <> '' then
      Result := Result + ['  NOTE: ' + pPlan.Notes[VI]];
  end;
  for VRemark in pPlan.Remarks do
    Result := Result + ['NOTE: ' + VRemark];
end;

function RenderGridCopyJson(const pPlan: TGridCopyPlan): string;
var
  VRoot, VItem: TJSONObject;
  VChanges, VRemarks: TJSONArray;
  VI: Integer;
  VRemark: string;
begin
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair('plan', pPlan.PlanId);
    VRoot.AddPair('file', ExtractFileName(pPlan.Form.DfmFile));
    VRoot.AddPair('source', pPlan.Request.SourceView);
    VRoot.AddPair('source_class', pPlan.SourceClass);
    VRoot.AddPair('target', pPlan.Request.TargetView);
    VRoot.AddPair('target_class', pPlan.TargetClass);
    VRoot.AddPair('event', pPlan.Request.EventName);
    VRoot.AddPair('count', TJSONNumber.Create(Length(pPlan.Changes)));
    VRoot.AddPair('blocked', TJSONNumber.Create(CountOf(pPlan, True)));
    VRoot.AddPair('unchecked', TJSONNumber.Create(CountOf(pPlan, False)));
    VChanges := TJSONArray.Create;
    VRoot.AddPair('changes', VChanges);
    for VI := 0 to High(pPlan.Changes) do
    begin
      VItem := TJSONObject.Create;
      VChanges.AddElement(VItem);
      VItem.AddPair('id', TJSONNumber.Create(pPlan.Changes[VI].Id));
      VItem.AddPair('op', OP_NAMES[pPlan.Changes[VI].Op]);
      VItem.AddPair('target', pPlan.Changes[VI].Target);
      VItem.AddPair('prop', pPlan.Changes[VI].Prop);
      VItem.AddPair('old', pPlan.Changes[VI].OldValue);
      VItem.AddPair('new', pPlan.Changes[VI].NewValue);
      VItem.AddPair('checked', TJSONBool.Create(pPlan.Changes[VI].Checked));
      VItem.AddPair('blocked', pPlan.Changes[VI].Blocked);
      VItem.AddPair('note', pPlan.Notes[VI]);
    end;
    VRemarks := TJSONArray.Create;
    VRoot.AddPair('remarks', VRemarks);
    for VRemark in pPlan.Remarks do
      VRemarks.Add(VRemark);
    Result := VRoot.ToJSON;
  finally
    VRoot.Free;
  end;
end;

end.
