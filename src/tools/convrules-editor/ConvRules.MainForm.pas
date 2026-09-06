unit ConvRules.MainForm;

{ ConvRulesEditor main window -- built entirely in code (no .dfm), plain VCL, no
  DevExpress. This is the v1 core loop:

    Load a conversion.rules file  ->  see its #convert rules in a library list with
    a % complete column  ->  select one to load the 3-column mapping grid (From /
    To-assigned / To-unassigned pool)  ->  assign/unassign properties  ->  Save
    (writes a .bak backup, re-emits canonical DSL, runs convert-validate).

  The property trees behind the grid come from the engine adapter (drag-lint
  proptree). All model edits go through TRuleBook so the DSL file stays the single
  source of truth. Directive tabs + a raw-DSL view expose the full grammar. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.ExtCtrls, Vcl.Grids, Vcl.Dialogs, Vcl.Menus, Vcl.Graphics, Vcl.Themes,
  ConvRules.Model, ConvRules.Casts, ConvRules.Engine, ConvRules.Platform,
  DRagLint.Convert.CastLib, ConvRules.Theme, ConvRules.OpenSourceClient,
  ConvRules.Mappings, ConvRules.MappingForm,
  ConvRules.FormTypes, ConvRules.RuleCatalog;

const
  /// <summary>HKCU key holding this editor's per-user settings.</summary>
  EDITOR_REG_KEY = 'Software\DragLint\ConvRulesEditor';
  /// <summary>Value under EDITOR_REG_KEY holding the theme preference token
  /// (see ConvRules.Theme.ThemePrefToStr). The .dpr reads it at start-up; the
  /// View &gt; Theme menu writes it back.</summary>
  EDITOR_REG_THEME = 'Theme';
  /// <summary>Value under EDITOR_REG_KEY holding the folder the form-file Open
  /// dialog last started in, so browsing resumes where the user left off rather
  /// than at the process working directory.</summary>
  /// <remarks>Seeded by --form on the command line, then updated by every
  /// successful browse. A missing or stale folder is harmless: TOpenDialog falls
  /// back on its own when InitialDir does not exist.</remarks>
  EDITOR_REG_FORMDIR = 'LastFormDir';

type
  TConvRulesForm = class(TForm)
  private
    FBook     : TRuleBook;
    FEngine   : TEngineAdapter;
    FFilePath : string;
    FActiveHdr: Integer;              // index of the selected #convert node (-1 none)
    FFromTree : TProptree;            // active F property tree
    FToTree   : TProptree;            // active T property tree

    FFromClasses: TArray<string>;     // FROM picker: all TComponent descendants (Win32+Win64 union)
    FToClasses  : TArray<string>;     // TO picker: TControl descendants (target platform)
    FUnitsLoaded: Boolean;            // project-unit picker populated?

    FFromPlatform: TConvPlatform;     // FROM picker library platform
    FToPlatform  : TConvPlatform;     // TO picker library platform

    FThemeMode: TThemeMode;                       // mode currently applied (drives GridDrawCell)
    FMnuTheme : array[TThemePref] of TMenuItem;   // View > Theme radio items
    FStatusIsError: Boolean;                      // last status was SetError (red bold)

    // action toolbar -- ONE grouped TToolBar owns every action that used to be a
    // loose TButton scattered over the top panel, the pool panel, the grid filter
    // bar and the Unit Rules tab. Only the buttons UpdateToolbarEnabled gates, or
    // whose caption flips at runtime, need a field; the rest are wired and dropped.
    FToolbar     : TToolBar;
    FTbAssign    : TToolButton;       // mapping: assign the pool leaf to the grid row
    FTbUnassign  : TToolButton;       // mapping: drop the selected row's assignment
    FTbFindInFrom: TToolButton;       // mapping: select the same-named From row
    FTbOnlyType  : TToolButton;       // mapping: pool type-narrowing toggle (caption flips)
    FTbMappings  : TToolButton;       // mapping: open the conditional #mapping editor
    FTbExamine      : TToolButton;    // examine: pick .dfm/.pas, mark used From props
    FTbClearExamine : TToolButton;    // examine: drop the current examination
    FPanelTop : TPanel;
    FLblFile  : TLabel;
    FLblStatus: TLabel;
    FStatusBar: TStatusBar;           // bottom-of-form status (mirrors FLblStatus)
    // new-conversion row
    FCbFrom   : TComboBox;
    FCbTo     : TComboBox;
    FCbUnit   : TComboBox;            // From Unit picker (project units)
    FCbFromPlat: TComboBox;           // FROM platform (Win32/Win64/Both)
    FCbToPlat  : TComboBox;           // TO platform
    FCbSurface : TComboBox;           // target surface: DFM (published) | PAS (public + fields)
    FSurfaceMinVis: string;           // '' | 'published' | 'public' -- proptree --min-visibility
    FCastDefs : TArray<TCastDef>;     // shipped class-cast library (.castlib)
    // rules library
    FRules    : TListView;
    // grid
    FGrid     : TStringGrid;          // col0 From, col1 To-assigned, col2 cast
    FGridFindFrom: TEdit;             // grid filter: From column substring
    FGridFindTo  : TEdit;             // grid filter: To column substring
    FLblGridMatch: TLabel;            // "N of M" count shown while a grid filter is active
    FUsedProps  : TArray<string>;     // Examine result; empty = no examination active
    FUsedFiles  : TArray<string>;     // the examined file set, retained for the session
    FExamineInfo: string;             // status summary, re-shown when blocks change
    // Units harvested from the examined .pas files (ConvRules.Usage.ScanUsesClauses).
    // CANDIDATES ONLY -- never rules: RefreshUnitList shows them as extra rows under
    // the real #use/#unuse/#useswap ones and nothing here touches FBook, so an Examine
    // can never dirty the rule book. Filtered against the current rules at DISPLAY
    // time, so authoring a rule for one makes its candidate row go away by itself.
    FUnitCandidates: TArray<string>;
    // --- form-types panel (leftmost): what is ON the examined form(s) ---
    // FFormTypeRows is the decorated model the list paints; ScanDfmTypes fills
    // TypeName/Count and RefreshFormTypes applies Visual/Excluded/Ruled on top.
    // Reenabled is the user's per-row override and is preserved ACROSS a refilter,
    // which is the whole reason the override lives on the row and is not recomputed.
    FFormTypeList : TListBox;         // owner-drawn: [V] TOvcTable (28)
    FFormTypeRows : TFormTypeRows;
    FFilterMemo   : TMemo;            // one exclusion regex per line
    FChkStdCtrls  : TCheckBox;        // also exclude Vcl./FMX. declared types
    FLblFormTypes : TLabel;           // "N types, M shown"
    FFilterError  : string;           // first malformed regex, surfaced in the label
    FCatalog      : TRuleCatalog;     // every #convert the rules folder already has
    FRulesFolder  : string;           // scanned folder (registry-backed)
    FLastFormDir  : string;           // where the Open-form dialog resumes
    // Three descendant sets, fetched ONCE each (~1.5 s per call, measured against
    // the 3.4 GB Win32 library). They replace a per-type DeclaringUnitOf, which
    // costs 1.7 s PER TYPE and blocked the UI for ~78 s on VARINSP's 46 types.
    FVisualSet    : TStringList;      // TControl descendants    -> [V]
    FComponentSet : TStringList;      // TComponent descendants  -> [N] when not TControl
    FPersistentSet: TStringList;      // TPersistent descendants -> [N] (catches TField)
    FDeclUnits    : TDictionary<string, string>; // type -> declaring unit, memoised
    FPool     : TListBox;             // unassigned T pool
    FPoolFind : TEdit;
    // "Go to definition of <T>": ONE popup shared by the grid and the pool, because
    // both show cells in the same 'Path : Type' shape and TypeOfCell reads either.
    // PopupComponent tells the handler which control was clicked.
    FTypePopup : TPopupMenu;
    FMnuGotoDef: TMenuItem;
    FCtxType   : string;              // the type under the cursor when the menu opened
    FPoolTypeFilter: string;          // active pool type-narrowing ('' = off)
    // directives / raw
    FTabs     : TPageControl;
    FRaw      : TMemo;
    // unit rules tab + rules-library filter
    FUnitList   : TListView;
    FRulesFilter: TEdit;

    procedure BuildUI;
    { Builds the single top-aligned action toolbar. Called from BuildUI right after
      the menu, so its strip is claimed before the panels below take the client
      area. Every TToolButton.OnClick points at the SAME handler the loose TButton
      it replaced used -- no handler body was copied. }
    procedure BuildToolbar;
    { Enables only what the current selection supports; see the implementation for
      why the always-enabled-then-complain behaviour was worth replacing. }
    procedure UpdateToolbarEnabled;
    { FGrid.OnSelectCell -- re-gates the toolbar when the grid row changes. Never
      vetoes (CanSelect is left alone). }
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
    { FPool.OnClick -- re-gates the toolbar when the pool highlight changes. }
    procedure PoolSelectionChanged(Sender: TObject);
    procedure FormCloseHandler(Sender: TObject; var Action: TCloseAction);
    procedure DoLoad(Sender: TObject);
    /// <summary>Back the file up, write the canonical DSL, validate it and report.</summary>
    /// <returns>True when the file was written; False when nothing reached disk --
    /// the backup failed, or no target file was chosen. The status bar always
    /// carries the reason.</returns>
    /// <remarks>A Boolean, not a procedure, because DoCurate must NOT open the
    /// curation window (which reads the file from DISK and can later force a reload
    /// over the editor's buffer) after a save the user asked for and did not get.</remarks>
    function  DoSave(Sender: TObject): Boolean;
    /// <summary>OnClick shim for the Save button -- an event handler must be a
    /// procedure, so the result is dropped here and nowhere else.</summary>
    procedure DoSaveClick(Sender: TObject);
    procedure DoValidate(Sender: TObject);
    procedure DoCurate(Sender: TObject);
    procedure DoNewConversion(Sender: TObject);
    procedure DoAutoMatch(Sender: TObject);
    procedure RefreshRulesList;
    procedure RulesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure LoadGridForBlock(AHdrIdx: Integer);
    procedure RefreshGrid;
    procedure GridFilterChange(Sender: TObject);
    procedure DoClearGridFindFrom(Sender: TObject);
    procedure DoClearGridFindTo(Sender: TObject);
    /// <summary>Prompts for one or more .dfm/.pas files, scans them via
    /// ConvRules.Usage.ComputeUsage for the active rule's From class, and marks the
    /// used From properties green in the grid. No-op with a status message when no
    /// conversion is selected.</summary>
    /// <summary>Harvests the component types of the examined .dfm file(s) into the
    /// form-types panel.</summary>
    /// <param name="ADfmTexts">The .dfm contents Examine just read.</param>
    /// <remarks>Deliberately independent of FActiveHdr: the panel exists to CHOOSE
    /// a From class, so it must work before any conversion is selected. Manual
    /// re-enables are carried over by type name so a re-Examine of the same form
    /// does not silently undo them.</remarks>
    procedure HarvestFormTypes(const ADfmTexts: TArray<string>);
    /// <summary>Re-applies Visual/Excluded/Ruled decoration and repaints the list.</summary>
    /// <remarks>Cheap and idempotent -- called on every filter keystroke.</remarks>
    procedure RefreshFormTypes;
    /// <summary>TNotifyEvent shim so the filter controls can re-run RefreshFormTypes.</summary>
    procedure FilterChanged(Sender: TObject);
    /// <summary>Rescans FRulesFolder into FCatalog and rewrites its index file.</summary>
    procedure RescanRulesFolder(Sender: TObject);
    /// <summary>Copies the clicked type into the From picker.</summary>
    /// <remarks>Fires whether the row is greyed or not, by design: a greyed row is
    /// a hint, never a prohibition.</remarks>
    procedure FormTypeClick(Sender: TObject);
    /// <summary>Toggles the selected row's manual re-enable override.</summary>
    procedure ToggleFormTypeReenable(Sender: TObject);
    /// <summary>Owner-draws one form-type row: V/N/? mark, name, count, why greyed.</summary>
    procedure FormTypeDrawItem(AControl: TWinControl; AIndex: Integer;
      ARect: TRect; AState: TOwnerDrawState);
    /// <summary>Bare names of every descendant of AAncestor, as a fast lookup set.</summary>
    /// <param name="AAncestor">e.g. 'TControl'. One engine call, ~1.5 s.</param>
    /// <returns>An owned list; EMPTY (never nil) when the engine cannot answer, so
    /// callers cannot mistake "no answer" for "not a descendant".</returns>
    function LoadDescendantSet(const AAncestor: string): TStringList;
    /// <summary>The declaring unit of ATypeName, memoised for the session.</summary>
    /// <returns>'' when the engine cannot resolve it -- which must NOT be read as
    /// "not a standard control".</returns>
    function DeclaringUnitCached(const ATypeName: string): string;
    /// <summary>Browses for form/source files, starting in the last-used folder.</summary>
    /// <param name="AFiles">Receives the chosen paths, sibling-expanded.</param>
    /// <returns>False when the user cancels; AFiles is then untouched.</returns>
    function PickFormFiles(out AFiles: TArray<string>): Boolean;
    /// <summary>Reads the given files, harvests their types, and -- only when a
    /// conversion is selected -- marks its used From properties.</summary>
    /// <param name="AFiles">Absolute paths; unreadable ones are reported, not fatal.</param>
    /// <remarks>The single load path. The toolbar's Examine, the panel's Open form
    /// button and --form all funnel through here, so none of them can drift.</remarks>
    procedure LoadFormFiles(const AFiles: TArray<string>);
    /// <summary>Adds each path's sibling .pas/.dfm when it exists.</summary>
    /// <param name="APaths">Chosen paths.</param>
    /// <returns>The input plus any siblings, de-duplicated.</returns>
    /// <remarks>A Delphi form IS the pair: the .dfm carries the component types and
    /// the .pas carries the uses clause and the property access sites. Opening one
    /// and silently ignoring the other would answer half of every question.</remarks>
    function ExpandUnitSiblings(const APaths: TArray<string>): TArray<string>;
    /// <summary>Records and persists the folder the Open dialog should start in.</summary>
    procedure SetLastFormDir(const ADir: string);
    /// <summary>Panel button: browse for a form, then load it.</summary>
    procedure DoOpenForm(Sender: TObject);
    procedure DoExamine(Sender: TObject);
    /// <summary>Drops the current examination (FUsedProps/FUsedFiles/FExamineInfo)
    /// and repaints the grid with no rows marked.</summary>
    procedure DoClearExamine(Sender: TObject);
    /// <summary>Shows a small read-only report window listing used property names
    /// that matched no From-tree leaf (ConvRules.Usage TUsageSet.Missing).</summary>
    procedure ShowUsageReport(const AMissing: TArray<string>);
    /// <summary>FGrid.OnDrawCell: paints a row green when its From path is used per
    /// the active examination (FUsedProps), else the normal fixed/selected/window
    /// colours. Every colour is resolved through StyleServices, so the grid follows
    /// the active VCL style. Requires FGrid.DefaultDrawing = False to own painting.</summary>
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect;
      State: TGridDrawState);
    { Builds the main menu (View > Theme). Called first from BuildUI so the menu bar
      is in place before the panels claim the client area. }
    procedure BuildMenu;
    { View > Theme item handler; the item's Tag is Ord(TThemePref). }
    procedure ThemeMenuClick(Sender: TObject);
    { Builds FTypePopup and hangs it on both the grid and the pool. Called from
      BuildUI after both controls exist. }
    procedure BuildTypePopup;
    { The type token of the grid or pool cell at client position APos, via
      TypeOfCell. '' when that position shows no type -- the header row, the cast
      column, blank space past the last row. ASender selects which control. }
    function  TypeAtPos(ASender: TObject; const APos: TPoint): string;
    { FGrid/FPool.OnContextPopup -- caches the type under the cursor and re-titles
      the item. Sets Handled (suppressing the menu ENTIRELY, rather than popping an
      empty frame with one hidden item) when the cell shows no type. }
    procedure GridPoolContextPopup(Sender: TObject; MousePos: TPoint;
      var Handled: Boolean);
    { FMnuGotoDef.OnClick -- resolves FCtxType and asks the running IDE to open it.
      Degrades to file:line in the status bar + on the clipboard when no IDE is
      listening; appends the member list when the type is an enum. }
    procedure DoGoToDefinition(Sender: TObject);
    procedure RefreshPool;
    procedure DoAssign(Sender: TObject);
    procedure DoUnassign(Sender: TObject);
    procedure PoolFilter(Sender: TObject);
    procedure DoFindInFrom(Sender: TObject);
    procedure DoOnlyType(Sender: TObject);
    /// <summary>Opens the conditional #mapping editor for one named mapping, splices the
    /// result back into the book and makes sure the active block #applies it.</summary>
    /// <remarks>Needs an active block: the live validation is done against that block's
    /// To tree and To class, and a mapping only reaches a block through an #apply.</remarks>
    procedure DoMappings(Sender: TObject);
    { The mapping names the ACTIVE block #applies; [] when no block is selected. }
    function  ActiveAppliedNames: TArray<string>;
    { The From paths those applied mappings decide conditionally, with a case count each.
      Recomputed per caller rather than cached: a mapping edit, a block switch and a raw
      tab edit would each have to invalidate a cache, and the node list is short. }
    function  ActiveConditionals: TArray<TConditionalFrom>;
    procedure SyncRawFromModel;
    procedure RefreshUnitList;
    procedure InsertUnitNode(ANode: TRuleNode);
    procedure DoAddSwap(Sender: TObject);
    procedure DoAddUse(Sender: TObject);
    procedure DoAddUnuse(Sender: TObject);
    procedure DoDeleteUnit(Sender: TObject);
    procedure DoDeriveUnits(Sender: TObject);
    procedure DoCheckUnits(Sender: TObject);
    procedure RulesFilterChange(Sender: TObject);
    procedure SetStatus(const S: string);
    procedure SetError(const S: string);
    { Re-applies FLblStatus's font for the kind of message currently shown. }
    procedure RefreshStatusColor;
    procedure LoadAllClasses;
    function  FromDbSet: TArray<string>;
    function  ToDbSet: TArray<string>;
    function  EngineDbSet: TArray<string>;
    procedure PlatformChanged(Sender: TObject);
    procedure SurfaceChanged(Sender: TObject);
    procedure CbLoadClasses(Sender: TObject);
    procedure CbLoadUnits(Sender: TObject);
    procedure DoLoadUnit(Sender: TObject);
    procedure AssignLink(const AFromPath, AToPath, AFromType, AToType: string);
    function  BlockPercent(AHdrIdx: Integer): Integer;
    function  ActiveLinks: TArray<TRuleNode>;
    function  FindLinkForFrom(const AFromPath: string): TRuleNode;
    function  LeafType(const ATree: TProptree; const APath: string): string;
    function  LeafWritable(const ATree: TProptree; const APath: string): Boolean;
    function  ClassCastName(const AFromType, AToType: string): string;
    function  CanCast(const AFromType, AToType: string): Boolean;
  public
    { Application.CreateForm calls this standard Create(AOwner); we route it to
      CreateNew (no .dfm) and build the UI in code. Being created via CreateForm
      makes this the Application.MainForm, which is what keeps Application.Run's
      message loop alive -- a manually-shown CreateNew form does not, and Run
      returns immediately. Engine/db config is read from the globals below. }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFile(const APath: string);

    /// <summary>Switches the application to the light or dark VCL style and
    /// repaints the owner-drawn grid in that mode.</summary>
    /// <param name="AMode">The mode to apply.</param>
    /// <param name="AInteractive">True when the user asked for this from the menu.
    ///   Only then is a fallback reported; start-up stays silent, because a modal or
    ///   an error banner before the window is even up helps nobody.</param>
    /// <remarks>Falls back to the built-in system style when the requested style is
    /// not linked into the executable (TStyleManager.TrySetStyle returns False) --
    /// the window then stays usable rather than half-themed. Records AMode either
    /// way, so GridDrawCell keeps tinting the Examine marking for the mode the user
    /// asked for. Does not persist anything; see SetThemePref.</remarks>
    procedure ApplyTheme(AMode: TThemeMode; AInteractive: Boolean = False);

    /// <summary>Records the user's theme preference, persists it under
    /// EDITOR_REG_KEY, and applies the mode it resolves to.</summary>
    /// <param name="APref">The new preference; tpFollowIde re-reads GEditorIdeTheme.</param>
    /// <remarks>A failed registry write is swallowed: the preference still takes
    /// effect for this session, it simply will not survive a restart. Also syncs the
    /// View &gt; Theme radio items, so it is safe to call from outside the menu.</remarks>
    procedure SetThemePref(APref: TThemePref);
  end;

var
  GEditorExe: string = '';
  { Library index directory + shared project DB. Each side's picker DB set is
    LibDbsFor(<side platform>, GEditorLibDir) + GEditorProjectDb -- the platform
    selects the library, the project DB is always-on and additive. }
  GEditorLibDir: string = '';
  GEditorProjectDb: string = '';
  { Path to the shipped class-cast library (.castlib); '' = class casts unavailable
    (scalar-only, today's behavior). Resolved + set by the .dpr before CreateForm. }
  GEditorCastLib: string = '';
  { A form (.dfm or .pas) to load at start-up, from --form on the command line.
    Exists so a debug run lands straight on the unit under study instead of
    browsing to it every time. Its FOLDER also seeds the Open dialog, so a browse
    from a --form session starts beside the unit that was passed. }
  GEditorFormPath: string = '';
  { Defaults come from ConvRules.Platform so the .dpr and this unit cannot drift
    apart; the .dpr overwrites both from --from-platform / --to-platform, which
    still accept win32|win64|both. FROM was cpBoth until 2026-07-29 -- see
    DEFAULT_FROM_PLATFORM for the measurements behind the change. }
  GEditorFromPlatform: TConvPlatform = DEFAULT_FROM_PLATFORM;
  GEditorToPlatform: TConvPlatform = DEFAULT_TO_PLATFORM;
  { Theme. Both are read from the registry and set by the .dpr before CreateForm;
    the constructor applies ResolveThemeMode(GEditorThemePref, GEditorIdeTheme).
    GEditorIdeTheme is the IDE's raw theme name -- kept (not pre-resolved) because
    switching back to "Follow IDE" at runtime has to re-resolve against it. }
  GEditorThemePref: TThemePref = tpFollowIde;
  GEditorIdeTheme: string = '';

implementation

uses
  System.StrUtils, System.Math, System.Win.Registry, Vcl.Clipbrd, ConvRules.Units,
  ConvRules.WorkingSet, ConvRules.CurationForm, ConvRules.Usage;

const
  { VCL style names as they are recorded INSIDE the .vsf files linked by
    ConvRulesEditorStyles.rc -- not the file names. Verified with
    TStyleManager.IsValidStyle; if the .rc ever swaps a style, these must follow. }
  STYLE_LIGHT = 'Windows11 Modern Light';
  STYLE_DARK  = 'Windows11 Modern Dark';

{ ---- helpers ---- }

{ The folder the Open-form dialog should start in, remembered from a previous
  session. '' when never set or unreadable -- TOpenDialog then uses its own
  default, which is the correct fallback rather than an error. }
function ReadLastFormDir: string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    try
      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly(EDITOR_REG_KEY) then
        if Reg.ValueExists(EDITOR_REG_FORMDIR) then
          Result := Reg.ReadString(EDITOR_REG_FORMDIR);
    except
      on E: ERegistryException do Result := '';
    end;
  finally
    Reg.Free;
  end;
end;

type
  { Scoped hourglass. Sets Screen.Cursor on create; restores the previous cursor
    when its last reference is released. Hold it in a local IInterface for the
    duration of a slow handler: `var LGuard: IInterface := HourGlass;`. }
  TCursorGuard = class(TInterfacedObject)
  private
    FPrev: TCursor;
  public
    constructor Create(ACursor: TCursor);
    destructor Destroy; override;
  end;

constructor TCursorGuard.Create(ACursor: TCursor);
begin
  inherited Create;
  FPrev := Screen.Cursor;
  Screen.Cursor := ACursor;
end;

destructor TCursorGuard.Destroy;
begin
  Screen.Cursor := FPrev;
  inherited;
end;

function HourGlass: IInterface;
begin
  Result := TCursorGuard.Create(crHourGlass);
end;

{ Forward-declared so RefreshGrid (below, well before the grid-cell helpers it
  shares this section with) can call it; implemented alongside PathOfGridCell /
  TypeOfCell / LeafNameOf. }
function GridRowMatchesFilter(const AFromCell, AToCell, AFromFilter, AToFilter: string): Boolean; forward;

{ TConvRulesForm }

constructor TConvRulesForm.Create(AOwner: TComponent);
begin
  // Route the standard constructor to CreateNew (no DFM); GlobalNameSpace-free.
  inherited CreateNew(AOwner);
  FBook := TRuleBook.Create;
  FFromPlatform := GEditorFromPlatform;
  FToPlatform   := GEditorToPlatform;
  FEngine := TEngineAdapter.Create(GEditorExe, EngineDbSet);
  FActiveHdr := -1;
  FSurfaceMinVis := 'published';   // default target surface = DFM-streamable
  FCastDefs := LoadCastLib(GEditorCastLib);   // [] when no .castlib is found
  BuildUI;
  // After BuildUI: ApplyTheme repaints FGrid, which BuildUI creates.
  ApplyTheme(ResolveThemeMode(GEditorThemePref, GEditorIdeTheme));
  OnClose := FormCloseHandler;
  Visible := True;  // ensure the CreateNew form is shown by Run

  // Where the Open-form dialog resumes. --form's own folder wins over the stored
  // one, so a debug run pointed at a different tree browses THERE, not wherever
  // the last interactive session happened to be.
  FLastFormDir := ReadLastFormDir;
  if GEditorFormPath <> '' then
    FLastFormDir := ExtractFileDir(GEditorFormPath);

  if GEditorFormPath <> '' then
  begin
    if TFile.Exists(GEditorFormPath) then
      LoadFormFiles(ExpandUnitSiblings([GEditorFormPath]))
    else
      SetError(Format('--form "%s" does not exist.', [GEditorFormPath]));
  end
  else
    SetStatus('Ready. Open a .rules file, or pick From/To classes and press '
      + '"+ New Conversion".');
end;

procedure TConvRulesForm.FormCloseHandler(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
  Application.Terminate;
end;

destructor TConvRulesForm.Destroy;
begin
  FEngine.Free;
  FBook.Free;
  // Both are lazily created (FVisualSet only if the engine answered, FDeclUnits on
  // the first lookup), so both can legitimately still be nil here.
  FVisualSet.Free;
  FComponentSet.Free;
  FPersistentSet.Free;
  FDeclUnits.Free;
  inherited;
end;

procedure TConvRulesForm.BuildMenu;
const
  { Indexed by TThemePref -- keep in step with ConvRules.Theme's declaration order. }
  CAPTIONS: array[TThemePref] of string = ('Follow &IDE', '&Light', '&Dark');
var
  LMenu : TMainMenu;
  LView : TMenuItem;
  LTheme: TMenuItem;
  P     : TThemePref;
begin
  LMenu := TMainMenu.Create(Self);

  LView := TMenuItem.Create(Self);
  LView.Caption := '&View';
  LMenu.Items.Add(LView);

  LTheme := TMenuItem.Create(Self);
  LTheme.Caption := '&Theme';
  LView.Add(LTheme);

  for P := Low(TThemePref) to High(TThemePref) do
  begin
    FMnuTheme[P] := TMenuItem.Create(Self);
    FMnuTheme[P].Caption   := CAPTIONS[P];
    FMnuTheme[P].RadioItem := True;
    FMnuTheme[P].Tag       := Ord(P);
    FMnuTheme[P].Checked   := (P = GEditorThemePref);
    FMnuTheme[P].OnClick   := ThemeMenuClick;
    LTheme.Add(FMnuTheme[P]);
  end;

  Menu := LMenu;
end;

procedure TConvRulesForm.ThemeMenuClick(Sender: TObject);
begin
  SetThemePref(TThemePref((Sender as TMenuItem).Tag));
end;

procedure TConvRulesForm.SetThemePref(APref: TThemePref);
var
  Reg: TRegistry;
  P  : TThemePref;
begin
  GEditorThemePref := APref;
  for P := Low(TThemePref) to High(TThemePref) do
    if FMnuTheme[P] <> nil then FMnuTheme[P].Checked := (P = APref);

  // Persist. A locked/denied HKCU is not worth an error dialog mid-session: the
  // preference still applies now, it just will not survive a restart.
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKey(EDITOR_REG_KEY, True) then
        Reg.WriteString(EDITOR_REG_THEME, ThemePrefToStr(APref));
    except
      on E: ERegistryException do
        SetStatus('Theme applied for this session, but could not be saved: ' + E.Message);
    end;
  finally
    Reg.Free;
  end;

  ApplyTheme(ResolveThemeMode(APref, GEditorIdeTheme), True);   // user-driven: report a fallback
end;

procedure TConvRulesForm.ApplyTheme(AMode: TThemeMode; AInteractive: Boolean = False);
var
  LStyle : string;
  LFailed: Boolean;
begin
  FThemeMode := AMode;
  if AMode = tmDark then LStyle := STYLE_DARK else LStyle := STYLE_LIGHT;
  // ShowErrorDialog=False: a missing style resource must not pop a modal at start-up.
  LFailed := not TStyleManager.TrySetStyle(LStyle, False);
  if LFailed then
    TStyleManager.TrySetStyle(TStyleManager.SystemStyleName, False);
  RefreshStatusColor;   // seFont is off there, so the style will not do it for us
  if FGrid <> nil then FGrid.Invalidate;
  // The user picked a mode and the window barely changed: say why, or the only clue
  // that STYLE_LIGHT/STYLE_DARK have drifted from ConvRulesEditorStyles.rc is that
  // nothing happens. Start-up keeps its silence.
  if LFailed and AInteractive then
    SetError('Theme style "' + LStyle + '" is not linked into this build -- '
      + 'fell back to the system style.');
end;

{ ONE grouped toolbar for every action in this window, in the order a session
  actually runs: file/working-set | mapping | examine | unit rules, each group
  closed by a tbsSeparator. It replaces 19 loose TButtons that were spread over
  four different parents (top panel, pool panel, grid filter bar, Unit Rules tab),
  where the same action's discoverability depended on which tab happened to be up.

  Every OnClick points at the handler the button it replaced already used -- no
  handler body was copied, so there is exactly one implementation of each action.

  Two buttons deliberately did NOT move: the grid filter bar's two "Clear"
  buttons. They are affordances of the TEdit they sit beside, not free-standing
  actions -- they belong to none of the four groups, and two toolbar buttons both
  captioned "Clear" would be unreadable.

  Layout notes that are easy to get wrong on a code-built TToolBar:
   * there is no Add method -- insertion order is decided by the button's Left/Top
     AT THE MOMENT Parent is assigned (TToolBar.ButtonIndex picks the row nearest
     Top, then the slot at Left). Both are therefore parked out past the strip so
     each new button appends to the end of the last row; the real bounds are
     overwritten by the toolbar immediately afterwards.
   * per-button AutoSize is REQUIRED: without it a text-only button keeps the
     toolbar's 23px ButtonWidth and the caption is clipped.
   * Wrapable + the toolbar's own AutoSize let a narrow window wrap to a second
     row and grow, rather than hiding the tail of the strip. }
procedure TConvRulesForm.BuildToolbar;
const
  PARK = 30000;   // past the right/bottom edge of any real strip -- see above

  function AddBtn(const ACaption, AHint: string;
    AHandler: TNotifyEvent): TToolButton;
  begin
    Result := TToolButton.Create(Self);
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
    if AHint <> '' then
    begin
      Result.Hint := AHint;
      Result.ShowHint := True;
    end;
    Result.Left := PARK; Result.Top := PARK;
    Result.Parent := FToolbar;
    Result.AutoSize := True;
  end;

  procedure AddSep;
  var
    LSep: TToolButton;
  begin
    LSep := TToolButton.Create(Self);
    LSep.Style := tbsSeparator;
    LSep.Width := 10;
    LSep.Left := PARK; LSep.Top := PARK;
    LSep.Parent := FToolbar;
  end;

begin
  FToolbar := TToolBar.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Top := 0;                 // sorts above FPanelTop in the alTop band
  FToolbar.Align := alTop;
  FToolbar.ShowCaptions := True;
  FToolbar.Wrapable := True;
  FToolbar.AutoSize := True;
  FToolbar.Flat := True;
  FToolbar.ShowHint := True;

  // --- file / working set ---
  AddBtn('Open...', 'Open a conversion .rules file', DoLoad);
  AddBtn('Save', 'Write the canonical DSL back (.bak backup, then validate)',
    DoSaveClick);
  AddBtn('Validate', 'Run convert-validate over the current model', DoValidate);
  AddBtn('Curate...', 'Split / copy / delete / merge blocks across several rule-books, '
    + 'or compose them into one file for the engine', DoCurate);
  AddSep;

  // --- mapping: acts on the top pickers, the selected grid row and the pool ---
  AddBtn('+ New Conversion',
    'Create a #convert block from the From/To pickers above', DoNewConversion);
  AddBtn('Fill From-classes',
    'Add a From-only conversion per component class on the picked unit''s form '
    + '(optional -- pick the unit in the "From Unit" box above first)', DoLoadUnit);
  AddBtn('Auto-Match', 'Assign every unambiguous, castable property pair',
    DoAutoMatch);
  FTbAssign := AddBtn('<- Assign',
    'Assign the highlighted To leaf (pool, right) to the selected From row',
    DoAssign);
  FTbUnassign := AddBtn('Unassign ->',
    'Drop the selected From row''s assignment', DoUnassign);
  FTbFindInFrom := AddBtn('Find in From',
    'Select the From-grid row whose property has the SAME name as the highlighted '
    + 'To leaf', DoFindInFrom);
  FTbOnlyType := AddBtn('Only this type',
    'Show only pool leaves whose TYPE matches the highlighted leaf (toggle)',
    DoOnlyType);
  FTbMappings := AddBtn('Mappings...',
    'Author a conditional #mapping -- one enum VALUE sets several target properties -- '
    + 'and #apply it to this conversion', DoMappings);
  AddSep;

  // --- examine ---
  FTbExamine := AddBtn('Examine...',
    'Pick .dfm/.pas files and mark the From properties they actually use (green)',
    DoExamine);
  FTbClearExamine := AddBtn('Clear marks',
    'Drop the current examination and unmark all rows', DoClearExamine);
  AddSep;

  // --- unit rules: the Unit Rules TAB keeps its list; only its buttons moved ---
  AddBtn('+ Swap', 'Add #useswap Old -> New1[, New2 ...]', DoAddSwap);
  AddBtn('+ Add unit', 'Add #use <unit> -- a unit to ADD to the uses clause',
    DoAddUse);
  AddBtn('+ Remove unit',
    'Add #unuse <unit> -- a unit to REMOVE from the uses clause', DoAddUnuse);
  AddBtn('Delete unit rule',
    'Delete the unit rule selected on the Unit Rules tab '
    + '(or dismiss the Examine candidate selected there)', DoDeleteUnit);
  AddBtn('Derive units',
    'Add #use/#unuse from every #convert To/From type (deduped)', DoDeriveUnits);
  AddBtn('Check units', 'Report #use/#unuse conflicts (ADD wins)', DoCheckUnits);
end;

{ Enables only what the current selection supports. Several actions were previously always
  enabled and reported an error only when pressed; that is a worse experience than a
  disabled button, and it hid which state each action actually requires. }
procedure TConvRulesForm.UpdateToolbarEnabled;
begin
  FTbAssign.Enabled     := (FActiveHdr >= 0) and (FGrid.Row > 0) and (FPool.ItemIndex >= 0);
  FTbUnassign.Enabled   := (FActiveHdr >= 0) and (FGrid.Row > 0);
  FTbFindInFrom.Enabled := (FActiveHdr >= 0) and (FPool.ItemIndex >= 0);
  FTbExamine.Enabled    := (FActiveHdr >= 0);
  FTbClearExamine.Enabled := (Length(FUsedProps) > 0) or (Length(FUnitCandidates) > 0);
  FTbMappings.Enabled   := (FActiveHdr >= 0);
end;

{ FGrid.OnSelectCell -- the grid row is half of the Assign/Unassign gate, so the
  toolbar has to be re-evaluated whenever it moves. CanSelect is left untouched:
  this hook only observes. }
procedure TConvRulesForm.GridSelectCell(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
begin
  UpdateToolbarEnabled;
end;

{ FPool.OnClick -- the pool highlight is the other half of the Assign gate (and
  all of the Find-in-From gate). }
procedure TConvRulesForm.PoolSelectionChanged(Sender: TObject);
begin
  UpdateToolbarEnabled;
end;

procedure TConvRulesForm.BuildUI;
var
  Split1: TSplitter;
  Split2: TSplitter;
  SplitForms: TSplitter;
  LeftPanel, GridPanel, PoolPanel, FormTypesPanel: TPanel;
  LblFormHdr, LblFilter: TLabel;
  BtnRescan, BtnReenable, BtnOpenForm: TButton;
  TabRules, TabRaw, TabUnits: TTabSheet;
begin
  Caption := 'ConvRulesEditor -- conversion rule-book editor';
  Width := 1600; Height := 720;
  Position := poScreenCenter;

  // Menu bar first: it takes its strip off the top of the client area before the
  // aligned panels below are laid out.
  BuildMenu;

  // --- bottom status bar (created first so it reserves the bottom edge; the top
  //     status label stays too, but this makes the current message visible even
  //     when the window is short and the top toolbar scrolls off) ---
  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.SimplePanel := True;
  FStatusBar.SimpleText := 'Ready.';

  // --- the one action toolbar (all four groups); claims its strip before the
  //     picker panel below it ---
  BuildToolbar;

  // --- top panel: status line / class builder / project-unit helper / path.
  //     Its four file-action buttons moved to the toolbar, so row 0 is now the
  //     status line alone and gets the full width. ---
  FPanelTop := TPanel.Create(Self);
  FPanelTop.Top := 200;   // sorts BELOW FToolbar in the alTop band
  FPanelTop.Parent := Self; FPanelTop.Align := alTop; FPanelTop.Height := 122;
  FPanelTop.BevelOuter := bvNone;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := FPanelTop; FLblStatus.SetBounds(8, 11, 1072, 15);
  // seFont off: with it on, the active style overrides Font.Color and SetError's
  // red would never show. SetStatus resolves its own colour via StyleServices.
  FLblStatus.StyleElements := FLblStatus.StyleElements - [seFont];

  // --- row 1: From Unit [v]  [Fill From-classes] -- pick a unit first, then its
  //     component classes drop into the rules library as From-only conversions ---
  var LblUnit: TLabel := TLabel.Create(Self);
  LblUnit.Parent := FPanelTop; LblUnit.SetBounds(8, 42, 58, 15); LblUnit.Caption := 'From Unit:';
  FCbUnit := TComboBox.Create(Self);
  FCbUnit.Parent := FPanelTop; FCbUnit.SetBounds(68, 39, 276, 23);
  FCbUnit.AutoComplete := True; FCbUnit.DropDownCount := 24;
  FCbUnit.Hint := 'Pick a project unit to add a From-only conversion per component class on its form (optional)';
  FCbUnit.ShowHint := True; FCbUnit.OnDropDown := CbLoadUnits;
  // Its "Fill From-classes" trigger is the toolbar button of that name.

  // Target surface: DFM = published props only; PAS = public props + public fields.
  // Selects proptree --min-visibility for the From/To trees (engine schema v17).
  var LblSurf: TLabel := TLabel.Create(Self);
  LblSurf.Parent := FPanelTop; LblSurf.SetBounds(520, 42, 58, 15); LblSurf.Caption := 'Surface:';
  FCbSurface := TComboBox.Create(Self);
  FCbSurface.Parent := FPanelTop; FCbSurface.SetBounds(580, 39, 190, 23);
  FCbSurface.Style := csDropDownList;
  FCbSurface.Items.Add('DFM (published props)');
  FCbSurface.Items.Add('PAS (public props + fields)');
  FCbSurface.ItemIndex := 0;
  FCbSurface.Hint := 'Target surface: DFM = published (DFM-streamable) only; '
    + 'PAS = public props + public fields. Read-only leaves are always hidden.';
  FCbSurface.ShowHint := True;
  FCbSurface.OnChange := SurfaceChanged;

  // --- row 2: From [v]  ->  To [v]  [New Conversion] ---
  // FROM holds all source components (TComponent desc, Win32+Win64 union); TO holds
  // target controls (TControl desc, target platform). See LoadAllClasses.
  var LblFrom: TLabel := TLabel.Create(Self);
  LblFrom.Parent := FPanelTop; LblFrom.SetBounds(8, 74, 34, 15); LblFrom.Caption := 'From:';
  FCbFrom := TComboBox.Create(Self);
  FCbFrom.Parent := FPanelTop; FCbFrom.SetBounds(44, 71, 300, 23);
  FCbFrom.AutoComplete := True; FCbFrom.DropDownCount := 24;
  FCbFrom.Hint := 'Source components (Win32+Win64) -- type to filter (TEdit, TOvcTable, TTable, ...)';
  FCbFrom.ShowHint := True; FCbFrom.OnDropDown := CbLoadClasses;

  var LblArrow: TLabel := TLabel.Create(Self);
  LblArrow.Parent := FPanelTop; LblArrow.SetBounds(350, 74, 20, 15); LblArrow.Caption := '->';
  var LblTo: TLabel := TLabel.Create(Self);
  LblTo.Parent := FPanelTop; LblTo.SetBounds(374, 74, 22, 15); LblTo.Caption := 'To:';
  FCbTo := TComboBox.Create(Self);
  FCbTo.Parent := FPanelTop; FCbTo.SetBounds(398, 71, 300, 23);
  FCbTo.AutoComplete := True; FCbTo.DropDownCount := 24;
  FCbTo.Hint := 'Target controls (Win64) -- type to filter (TcxTextEdit, TcxGrid, ...)';
  FCbTo.ShowHint := True; FCbTo.OnDropDown := CbLoadClasses;
  // The pair's trigger is the toolbar's "+ New Conversion" button.

  // --- platform selectors: FROM platform / TO platform (re-scope the pickers) ---
  // Combo item order (Win32,Win64,Both) matches TConvPlatform (cpWin32,cpWin64,
  // cpBoth) by ordinal, so ItemIndex <-> Ord(platform) round-trips.
  var LblFromPlat: TLabel := TLabel.Create(Self);
  LblFromPlat.Parent := FPanelTop; LblFromPlat.SetBounds(844, 74, 34, 15); LblFromPlat.Caption := 'FROM';
  FCbFromPlat := TComboBox.Create(Self);
  FCbFromPlat.Parent := FPanelTop; FCbFromPlat.SetBounds(882, 71, 80, 23);
  FCbFromPlat.Style := csDropDownList;
  FCbFromPlat.Items.Add('Win32'); FCbFromPlat.Items.Add('Win64'); FCbFromPlat.Items.Add('Both');
  FCbFromPlat.ItemIndex := Ord(FFromPlatform);
  FCbFromPlat.Hint := 'Library platform the FROM types come from'; FCbFromPlat.ShowHint := True;
  FCbFromPlat.OnChange := PlatformChanged;

  var LblToPlat: TLabel := TLabel.Create(Self);
  LblToPlat.Parent := FPanelTop; LblToPlat.SetBounds(968, 74, 22, 15); LblToPlat.Caption := 'TO';
  FCbToPlat := TComboBox.Create(Self);
  FCbToPlat.Parent := FPanelTop; FCbToPlat.SetBounds(994, 71, 80, 23);
  FCbToPlat.Style := csDropDownList;
  FCbToPlat.Items.Add('Win32'); FCbToPlat.Items.Add('Win64'); FCbToPlat.Items.Add('Both');
  FCbToPlat.ItemIndex := Ord(FToPlatform);
  FCbToPlat.Hint := 'Library platform the TO types come from'; FCbToPlat.ShowHint := True;
  FCbToPlat.OnChange := PlatformChanged;

  FLblFile := TLabel.Create(Self);
  FLblFile.Parent := FPanelTop; FLblFile.SetBounds(8, 101, 1080, 15);
  FLblFile.Caption := '(no file)';

  // --- leftmost: the types ON the examined form ---
  // Created BEFORE LeftPanel so it wins the leftmost alLeft slot: VCL orders same-
  // aligned siblings by creation, so swapping these two swaps the columns.
  FormTypesPanel := TPanel.Create(Self);
  FormTypesPanel.Parent := Self; FormTypesPanel.Align := alLeft; FormTypesPanel.Width := 300;
  FormTypesPanel.BevelOuter := bvNone;

  LblFormHdr := TLabel.Create(Self);
  LblFormHdr.Parent := FormTypesPanel; LblFormHdr.SetBounds(6, 8, 288, 15);
  LblFormHdr.Caption := 'Types on form (Examine to fill)';

  BtnOpenForm := TButton.Create(Self);
  BtnOpenForm.Parent := FormTypesPanel; BtnOpenForm.SetBounds(6, 26, 90, 23);
  BtnOpenForm.Caption := 'Open form...';
  BtnOpenForm.Hint := 'Browse for a .dfm/.pas; its sibling is loaded too';
  BtnOpenForm.ShowHint := True;
  BtnOpenForm.OnClick := DoOpenForm;

  BtnRescan := TButton.Create(Self);
  BtnRescan.Parent := FormTypesPanel; BtnRescan.SetBounds(102, 26, 92, 23);
  BtnRescan.Caption := 'Rescan rules';
  BtnRescan.Hint := 'Re-read the rules folder and rebuild the coverage index';
  BtnRescan.ShowHint := True;
  BtnRescan.OnClick := RescanRulesFolder;

  BtnReenable := TButton.Create(Self);
  BtnReenable.Parent := FormTypesPanel; BtnReenable.SetBounds(200, 26, 94, 23);
  BtnReenable.Caption := 'Re-enable';
  BtnReenable.Hint := 'Ignore the filter for the selected type (toggles)';
  BtnReenable.ShowHint := True;
  BtnReenable.OnClick := ToggleFormTypeReenable;

  FChkStdCtrls := TCheckBox.Create(Self);
  FChkStdCtrls.Parent := FormTypesPanel; FChkStdCtrls.SetBounds(6, 54, 288, 17);
  FChkStdCtrls.Caption := 'Exclude standard VCL / FMX controls';
  FChkStdCtrls.OnClick := FilterChanged;

  LblFilter := TLabel.Create(Self);
  LblFilter.Parent := FormTypesPanel; LblFilter.SetBounds(6, 76, 288, 15);
  LblFilter.Caption := 'Exclude (one regex per line, any match):';

  FFilterMemo := TMemo.Create(Self);
  FFilterMemo.Parent := FormTypesPanel; FFilterMemo.SetBounds(6, 94, 288, 60);
  FFilterMemo.ScrollBars := ssVertical;
  FFilterMemo.OnChange := FilterChanged;

  FLblFormTypes := TLabel.Create(Self);
  FLblFormTypes.Parent := FormTypesPanel; FLblFormTypes.SetBounds(6, 158, 288, 15);
  FLblFormTypes.Caption := '';

  FFormTypeList := TListBox.Create(Self);
  FFormTypeList.Parent := FormTypesPanel;
  FFormTypeList.SetBounds(6, 176, 288, 466);
  FFormTypeList.Anchors := [akLeft, akTop, akRight, akBottom];
  FFormTypeList.Style := lbOwnerDrawFixed;
  FFormTypeList.ItemHeight := 18;
  FFormTypeList.OnDrawItem := FormTypeDrawItem;
  FFormTypeList.OnClick := FormTypeClick;

  SplitForms := TSplitter.Create(Self);
  SplitForms.Parent := Self; SplitForms.Align := alLeft; SplitForms.Width := 4;

  // --- left: rules library + tabs ---
  LeftPanel := TPanel.Create(Self);
  LeftPanel.Parent := Self; LeftPanel.Align := alLeft; LeftPanel.Width := 380;
  LeftPanel.BevelOuter := bvNone;

  FTabs := TPageControl.Create(Self);
  FTabs.Parent := LeftPanel; FTabs.Align := alClient;

  TabRules := TTabSheet.Create(FTabs); TabRules.PageControl := FTabs;
  TabRules.Caption := 'Rules Library';
  FRulesFilter := TEdit.Create(Self);
  FRulesFilter.Parent := TabRules; FRulesFilter.Align := alTop;
  FRulesFilter.TextHint := 'filter rules (From/To contains)...';
  FRulesFilter.OnChange := RulesFilterChange;
  FRules := TListView.Create(Self);
  FRules.Parent := TabRules; FRules.Align := alClient;
  FRules.ViewStyle := vsReport; FRules.ReadOnly := True;
  FRules.RowSelect := True; FRules.HideSelection := False;
  FRules.Columns.Add.Caption := 'From';       FRules.Columns[0].Width := 150;
  FRules.Columns.Add.Caption := 'To';         FRules.Columns[1].Width := 150;
  FRules.Columns.Add.Caption := '%';          FRules.Columns[2].Width := 50;
  FRules.OnSelectItem := RulesSelectItem;

  TabRaw := TTabSheet.Create(FTabs); TabRaw.PageControl := FTabs;
  TabRaw.Caption := 'Raw DSL (all directives)';
  FRaw := TMemo.Create(Self);
  FRaw.Parent := TabRaw; FRaw.Align := alClient;
  FRaw.ScrollBars := ssBoth; FRaw.WordWrap := False;
  FRaw.Font.Name := 'Consolas'; FRaw.Font.Size := 9;

  // --- Unit Rules tab: #use / #unuse / #useswap authoring + derive/check ---
  TabUnits := TTabSheet.Create(FTabs); TabUnits.PageControl := FTabs;
  TabUnits.Caption := 'Unit Rules';
  // The six authoring buttons that used to sit on a 64px panel here are now the
  // toolbar's "unit rules" group; the tab keeps the list they act on.
  FUnitList := TListView.Create(Self);
  FUnitList.Parent := TabUnits; FUnitList.Align := alClient;
  FUnitList.ViewStyle := vsReport; FUnitList.ReadOnly := True;
  FUnitList.RowSelect := True; FUnitList.HideSelection := False;
  FUnitList.Columns.Add.Caption := 'Kind';   FUnitList.Columns[0].Width := 70;
  FUnitList.Columns.Add.Caption := 'Old';    FUnitList.Columns[1].Width := 110;
  FUnitList.Columns.Add.Caption := 'New(s)'; FUnitList.Columns[2].Width := 150;
  FUnitList.Columns.Add.Caption := 'Flag';   FUnitList.Columns[3].Width := 90;

  Split1 := TSplitter.Create(Self);
  Split1.Parent := Self; Split1.Align := alLeft; Split1.Left := LeftPanel.Width + 1;
  Split1.Width := 4;

  // --- right: 3-column grid (From | To-assigned | cast) + pool ---
  PoolPanel := TPanel.Create(Self);
  PoolPanel.Parent := Self; PoolPanel.Align := alRight; PoolPanel.Width := 400;
  PoolPanel.BevelOuter := bvNone;

  // Auto-Match / Find in From / Only this type / Assign / Unassign all moved to
  // the toolbar's "mapping" group; the pool keeps only its search box and list,
  // which is what the freed 140px of height goes to.
  var LblPool: TLabel := TLabel.Create(Self);
  LblPool.Parent := PoolPanel; LblPool.SetBounds(6, 8, 388, 15);
  LblPool.Caption := 'To (unassigned pool) -- search:';

  FPoolFind := TEdit.Create(Self);
  FPoolFind.Parent := PoolPanel; FPoolFind.SetBounds(6, 26, 388, 23);
  FPoolFind.Anchors := [akLeft, akTop, akRight];
  FPoolFind.OnChange := PoolFilter;

  FPool := TListBox.Create(Self);
  FPool.Parent := PoolPanel; FPool.SetBounds(6, 56, 388, 586);
  FPool.Anchors := [akLeft, akTop, akRight, akBottom];
  FPool.OnClick := PoolSelectionChanged;

  Split2 := TSplitter.Create(Self);
  Split2.Parent := Self; Split2.Align := alRight; Split2.Width := 4;

  GridPanel := TPanel.Create(Self);
  GridPanel.Parent := Self; GridPanel.Align := alClient; GridPanel.BevelOuter := bvNone;

  // --- grid filter bar: narrow the mapping grid to rows matching a From and/or a
  //     To substring (AND when both are set). Sits above the grid, which stays
  //     alClient beneath it. See RefreshGrid / GridRowMatchesFilter. ---
  var GridFilterPanel: TPanel := TPanel.Create(Self);
  GridFilterPanel.Parent := GridPanel; GridFilterPanel.Align := alTop;
  GridFilterPanel.Height := 36; GridFilterPanel.BevelOuter := bvNone;

  var LblGridFrom: TLabel := TLabel.Create(Self);
  LblGridFrom.Parent := GridFilterPanel; LblGridFrom.SetBounds(6, 9, 66, 15);
  LblGridFrom.Caption := 'Find in From:';

  FGridFindFrom := TEdit.Create(Self);
  FGridFindFrom.Parent := GridFilterPanel; FGridFindFrom.SetBounds(76, 6, 180, 23);
  FGridFindFrom.TextHint := 'filter From column...';
  FGridFindFrom.Hint := 'Show only grid rows whose From property contains this text (case-insensitive)';
  FGridFindFrom.ShowHint := True;
  FGridFindFrom.OnChange := GridFilterChange;

  var BtnClearGridFrom: TButton := TButton.Create(Self);
  BtnClearGridFrom.Parent := GridFilterPanel; BtnClearGridFrom.SetBounds(260, 5, 50, 25);
  BtnClearGridFrom.Caption := 'Clear'; BtnClearGridFrom.OnClick := DoClearGridFindFrom;

  var LblGridTo: TLabel := TLabel.Create(Self);
  LblGridTo.Parent := GridFilterPanel; LblGridTo.SetBounds(324, 9, 54, 15);
  LblGridTo.Caption := 'Find in To:';

  FGridFindTo := TEdit.Create(Self);
  FGridFindTo.Parent := GridFilterPanel; FGridFindTo.SetBounds(382, 6, 180, 23);
  FGridFindTo.TextHint := 'filter To column...';
  FGridFindTo.Hint := 'Show only grid rows whose assigned To property contains this text (case-insensitive)';
  FGridFindTo.ShowHint := True;
  FGridFindTo.OnChange := GridFilterChange;

  var BtnClearGridTo: TButton := TButton.Create(Self);
  BtnClearGridTo.Parent := GridFilterPanel; BtnClearGridTo.SetBounds(566, 5, 50, 25);
  BtnClearGridTo.Caption := 'Clear'; BtnClearGridTo.OnClick := DoClearGridFindTo;

  FLblGridMatch := TLabel.Create(Self);
  FLblGridMatch.Parent := GridFilterPanel; FLblGridMatch.SetBounds(626, 9, 160, 15);
  FLblGridMatch.Caption := '';

  // Examine / Clear marks moved to the toolbar's "examine" group; the second row
  // of this filter bar went with them.

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := GridPanel; FGrid.Align := alClient;
  // RowCount must stay > FixedRows: start at 2 (header + one blank data row).
  FGrid.ColCount := 3; FGrid.RowCount := 2; FGrid.FixedRows := 1; FGrid.FixedCols := 0;
  // goColSizing: the user can drag column borders to widen From/To to taste.
  FGrid.Options := FGrid.Options + [goRowSelect, goVertLine, goHorzLine, goColSizing];
  FGrid.DefaultRowHeight := 20;
  FGrid.Cells[0, 0] := 'From property (: type)';
  FGrid.Cells[1, 0] := 'To (assigned)';
  FGrid.Cells[2, 0] := 'cast';
  FGrid.ColWidths[0] := 330; FGrid.ColWidths[1] := 330; FGrid.ColWidths[2] := 110;
  // Hand painting entirely to GridDrawCell (header, selection and Examine's green
  // marking all go through it) -- required for OnDrawCell to own the cell colour.
  FGrid.DefaultDrawing := False;
  FGrid.OnDrawCell := GridDrawCell;
  FGrid.OnSelectCell := GridSelectCell;   // re-gates the toolbar as the row moves

  // Needs both FGrid and FPool, so it goes after the grid, not next to the pool.
  BuildTypePopup;

  // TLabel is a TGraphicControl, so no style hook reaches it: with Transparent
  // False it fills its own rectangle with Color, which ParentColor resolves to the
  // panel's *property* (clBtnFace, light) no matter how darkly the style PAINTS
  // that panel -- while the caption itself is styled light. Result under the dark
  // style: white text on a white box. Transparent drops the fill, leaving styled
  // text over the styled parent. Applied in one sweep so later labels inherit it.
  for var i := 0 to ComponentCount - 1 do
    if Components[i] is TLabel then TLabel(Components[i]).Transparent := True;

  // Nothing is selected yet: start the selection-dependent actions disabled
  // rather than enabled-and-complaining.
  UpdateToolbarEnabled;
end;

{ Re-assert FLblStatus's font for the current message kind. FLblStatus opts out of
  seFont (so SetError's red survives a style), which also means the style will never
  refresh it -- hence this is called on every message AND from ApplyTheme, or a
  status set under dark would keep its pale text after a switch to light. }
procedure TConvRulesForm.RefreshStatusColor;
begin
  if FLblStatus = nil then Exit;
  if FStatusIsError then
  begin
    FLblStatus.Font.Color := clRed;
    FLblStatus.Font.Style := [fsBold];
  end
  else
  begin
    FLblStatus.Font.Color := StyleServices.GetSystemColor(clWindowText);
    FLblStatus.Font.Style := [];
  end;
end;

procedure TConvRulesForm.SetStatus(const S: string);
begin
  FStatusIsError := False;
  RefreshStatusColor;
  FLblStatus.Caption := S;
  if FStatusBar <> nil then FStatusBar.SimpleText := S;
end;

{ Show a message in RED bold -- for blocked assignments and errors. }
procedure TConvRulesForm.SetError(const S: string);
begin
  FStatusIsError := True;
  RefreshStatusColor;
  FLblStatus.Caption := S;
  // The status bar has no per-message colour in SimplePanel mode; prefix so an
  // error still reads as one at the bottom of the form.
  if FStatusBar <> nil then FStatusBar.SimpleText := '[!] ' + S;
end;

{ Resolve a leaf's declared type from a proptree ('' if not found). }
function TConvRulesForm.LeafType(const ATree: TProptree; const APath: string): string;
var
  L: TPropLeaf;
begin
  Result := '';
  for L in ATree.Leaves do
    if SameText(L.Path, APath) then Exit(L.TypeName);
end;

{ Whether a leaf is a writable assignment target. Defaults True when the leaf is not
  found or the engine is proptree/1 (IsWritable defaults True) -- never block on
  missing data. }
function TConvRulesForm.LeafWritable(const ATree: TProptree; const APath: string): Boolean;
var
  L: TPropLeaf;
begin
  Result := True;
  for L in ATree.Leaves do
    if SameText(L.Path, APath) then Exit(L.IsWritable);
end;

{ The library class-cast name bridging AFromType -> AToType, or '' if none. }
function TConvRulesForm.ClassCastName(const AFromType, AToType: string): string;
begin
  Result := ClassCastFor(FCastDefs, AFromType, AToType);
end;

{ Castable when the scalar classifier allows it OR a library class cast bridges it. }
function TConvRulesForm.CanCast(const AFromType, AToType: string): Boolean;
begin
  Result := IsCastable(AFromType, AToType) or (ClassCastName(AFromType, AToType) <> '');
end;

{ Load the FROM and TO class pickers, once. They are deliberately DIFFERENT sets:

    FROM = all TComponent descendants of the FROM platform's library (default
           Win64) -- the source app has visual controls AND non-visual components
           (BDE TTable, datasets) plus legacy Orpheus TOvc* controls. A
           TControl-only filter (the v1 behaviour) hid all three; TComponent is
           the right superset, since every convertible source component descends
           from it. The default was Win32+Win64 as a "safety net" for components
           indexed under only one platform. Measured 2026-07-29, that net is
           empty: Win64 alone yields the same 6180 names as the union (Win32
           alone yields 3, all of them already in Win64), and TOvcTable is in
           Win64. Pick 'Both' in the FROM combo if a future library split
           reintroduces platform-only components.

    TO   = TControl descendants of the TARGET platform's library only (Win64) --
           conversions target visual controls on the platform being migrated to.

  Falls back to a tiny built-in set if either query yields nothing so the New
  Conversion flow always works. }
{ Each side's DB set = its platform's library index + the shared project DB
  (additive, so project-declared component types still resolve). }
function TConvRulesForm.FromDbSet: TArray<string>;
begin
  Result := LibDbsFor(FFromPlatform, GEditorLibDir) + [GEditorProjectDb];
end;

function TConvRulesForm.ToDbSet: TArray<string>;
begin
  Result := LibDbsFor(FToPlatform, GEditorLibDir) + [GEditorProjectDb];
end;

{ The engine's default DB set (proptree/scaffold/validate/qname-resolve) must
  resolve BOTH sides' types + project units -- the deduped union of both sides. }
function TConvRulesForm.EngineDbSet: TArray<string>;
var
  seen: TDictionary<string, Boolean>;
  src, db: string;
  arr: TArray<string>;
begin
  Result := [];
  seen := TDictionary<string, Boolean>.Create;
  try
    for src in ['from', 'to'] do
    begin
      if src = 'from' then arr := FromDbSet else arr := ToDbSet;
      for db in arr do
        if not seen.ContainsKey(LowerCase(db)) then
        begin
          seen.Add(LowerCase(db), True);
          Result := Result + [db];
        end;
    end;
  finally
    seen.Free;
  end;
end;

{ A platform dropdown changed: recompute both sides' platforms from the combos,
  update the engine's default DB set, clear the class caches, and reload the
  pickers so they now list the newly-selected platforms' types. }
procedure TConvRulesForm.PlatformChanged(Sender: TObject);
begin
  FFromPlatform := TConvPlatform(FCbFromPlat.ItemIndex);
  FToPlatform   := TConvPlatform(FCbToPlat.ItemIndex);
  FEngine.SetDbs(EngineDbSet);
  // Force LoadAllClasses to re-query (its guard exits when both caches are set).
  FFromClasses := [];
  FToClasses := [];
  FCbFrom.Items.Clear;
  FCbTo.Items.Clear;
  Screen.Cursor := crHourGlass;
  try
    LoadAllClasses;
    SetStatus(Format('Platforms: FROM=%s TO=%s -- %d source + %d target classes.',
      [PlatformToStr(FFromPlatform), PlatformToStr(FToPlatform),
       Length(FFromClasses), Length(FToClasses)]));
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TConvRulesForm.LoadAllClasses;
var
  FromNames, ToNames: TArray<string>;
  Err  : string;
begin
  if (Length(FFromClasses) > 0) and (Length(FToClasses) > 0) then Exit; // already loaded

  // FROM: TComponent descendants of the FROM platform's library (+ project).
  if not FEngine.ListDescendantsOf('TComponent', FromDbSet, FromNames, Err)
     or (Length(FromNames) = 0) then
    FromNames := ['TEdit', 'TMemo', 'TButton', 'TLabel', 'TCheckBox', 'TcxTextEdit',
                  'TOvcTable', 'TTable'];
  FFromClasses := FromNames;

  // TO: TControl descendants of the TO platform's library (+ project).
  if not FEngine.ListDescendantsOf('TControl', ToDbSet, ToNames, Err)
     or (Length(ToNames) = 0) then
    ToNames := ['TEdit', 'TMemo', 'TButton', 'TLabel', 'TCheckBox', 'TcxTextEdit',
                'TcxGrid'];
  FToClasses := ToNames;

  FCbFrom.Items.BeginUpdate; FCbTo.Items.BeginUpdate;
  try
    FCbFrom.Items.Clear; FCbTo.Items.Clear;
    for var N in FFromClasses do FCbFrom.Items.Add(N);
    for var N in FToClasses do FCbTo.Items.Add(N);
  finally
    FCbFrom.Items.EndUpdate; FCbTo.Items.EndUpdate;
  end;
end;

{ Lazy-load the class list the first time a picker is dropped down (enumerating
  every indexed class is slow, so we defer it until actually needed). }
procedure TConvRulesForm.CbLoadClasses(Sender: TObject);
begin
  if (Length(FFromClasses) > 0) and (Length(FToClasses) > 0) then Exit;
  Screen.Cursor := crHourGlass;
  SetStatus('Loading classes from the Library scan (first time only)...');
  try
    Application.ProcessMessages;
    LoadAllClasses;
    SetStatus(Format('%d source (From) + %d target (To) classes available. Type to filter.',
      [Length(FFromClasses), Length(FToClasses)]));
  finally
    Screen.Cursor := crDefault;
  end;
end;

{ Lazy-load the project unit list the first time the From-Unit picker drops. }
procedure TConvRulesForm.CbLoadUnits(Sender: TObject);
var
  Units: TArray<string>;
  Err  : string;
begin
  if FUnitsLoaded then Exit;
  Screen.Cursor := crHourGlass;
  SetStatus('Loading project units (first time only)...');
  try
    Application.ProcessMessages;
    if FEngine.ListProjectUnits(Units, Err) then
    begin
      FCbUnit.Items.BeginUpdate;
      try
        FCbUnit.Items.Clear;
        for var U in Units do FCbUnit.Items.Add(U);
      finally
        FCbUnit.Items.EndUpdate;
      end;
      FUnitsLoaded := True;
      SetStatus(Format('%d project units available.', [Length(Units)]));
    end
    else
      SetError('Could not list project units: ' + Err);
  finally
    Screen.Cursor := crDefault;
  end;
end;

{ "Fill From-classes": read the chosen unit's .dfm components and add one FROM-ONLY
  conversion row per distinct component CLASS to the rules library (To unassigned).
  These are CLASSES, not properties, so they go in the rules list -- NOT the grid's
  property column. Selecting a From-only row shows that class's flattened property
  list; assigning a To class then auto-matches. A row with no To (and no links) is
  scratch: SaveComplete drops it, so nothing is written until the user picks a To.
  Existing From classes are skipped (no duplicates). Best-effort: a non-form unit
  (no .dfm) adds nothing. }
procedure TConvRulesForm.DoLoadUnit(Sender: TObject);
var
  UnitName: string;
  Types   : TArray<string>;
  Err     : string;
  existing: TStringList;
  H       : Integer;
  added   : Integer;
  firstNew: Integer;
begin
  UnitName := Trim(FCbUnit.Text);
  if UnitName = '' then begin SetError('Pick a project unit first.'); Exit; end;
  Screen.Cursor := crHourGlass;
  try
    Application.ProcessMessages;
    // Reads the unit's .dfm and lists the components the designer placed on the
    // form. Not filtered by the picker class set -- legacy components (Orpheus/
    // Raize/DevExpress) are listed even when their ancestry is unresolved.
    if not FEngine.ListControlTypesInUnit(UnitName, nil, Types, Err) then
    begin
      SetError('Could not read unit ' + UnitName + ': ' + Err);
      Exit;
    end;
    if Length(Types) = 0 then
    begin
      SetError(Format('No form components found in %s. It may be a non-form unit '
        + '(no .dfm), or not indexed. Use the From/To pickers instead.', [UnitName]));
      Exit;
    end;

    // Skip classes already present as a From in the rules library.
    existing := TStringList.Create;
    try
      existing.CaseSensitive := False;
      for H in FBook.ConvertHeaders do
        existing.Add(FBook.Nodes[H].FromType);

      added := 0; firstNew := -1;
      for var C in Types do
      begin
        if existing.IndexOf(C) >= 0 then Continue;
        if FBook.Nodes.Count > 0 then
        begin
          var Blank: TRuleNode := TRuleNode.Create;
          Blank.Kind := rnkBlank; Blank.Raw := '';
          FBook.Add(Blank);
        end;
        var Hdr: TRuleNode := TRuleNode.Create;
        Hdr.Kind := rnkConvert;
        Hdr.FromType := C;
        Hdr.ToType := '';        // From-only -- user assigns a To next
        Hdr.Dirty := True;
        FBook.Add(Hdr);
        if firstNew < 0 then firstNew := FBook.Nodes.Count - 1;
        Inc(added);
        existing.Add(C);
      end;
    finally
      existing.Free;
    end;

    RefreshRulesList;
    SyncRawFromModel;
    // Select the first newly-added From-only rule so its property list loads.
    if firstNew >= 0 then
      for var k := 0 to FRules.Items.Count - 1 do
        if Integer(FRules.Items[k].Data) = firstNew then
        begin
          FRules.ItemIndex := k;
          FRules.Items[k].Selected := True;
          Break;
        end;

    if added = 0 then
      SetStatus(Format('All %d component class(es) from %s are already in the rules '
        + 'library.', [Length(Types), UnitName]))
    else
      SetStatus(Format('Added %d From-only conversion(s) from %s. Pick a To class for '
        + 'each you want to convert -- its properties auto-match.', [added, UnitName]));
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TConvRulesForm.DoLoad(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Conversion rules (*.rules;*.txt)|*.rules;*.txt|All files (*.*)|*.*';
    if Dlg.Execute then
      LoadFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TConvRulesForm.LoadFile(const APath: string);
begin
  if not TFile.Exists(APath) then
  begin
    SetStatus('File not found: ' + APath);
    Exit;
  end;
  FFilePath := APath;
  FBook.LoadFromString(TFile.ReadAllText(APath));
  FLblFile.Caption := APath;
  RefreshRulesList;
  RefreshUnitList;
  SyncRawFromModel;
  FActiveHdr := -1;
  FGrid.RowCount := 2;              // FixedRows(1) < RowCount; 2 = header + 1 blank
  FGrid.Cells[0, 1] := ''; FGrid.Cells[1, 1] := ''; FGrid.Cells[2, 1] := '';
  FPool.Clear;
  SetStatus(Format('Loaded %d line(s), %d rule(s). Select a rule to edit its mapping.',
    [FBook.Nodes.Count, Length(FBook.ConvertHeaders)]));
  // Re-gate BEFORE the auto-select below, not after: a file with no #convert rules
  // skips that branch entirely, so LoadGridForBlock's re-gate never runs and the
  // toolbar would still be showing the PREVIOUS file's enabled state over an empty
  // grid. When there IS a rule the auto-select re-gates again a moment later.
  UpdateToolbarEnabled;
  // Auto-select the first rule so the grid shows content immediately (also makes
  // the tool usable if a click ever fails to register). Selecting fires
  // OnSelectItem -> LoadGridForBlock.
  if FRules.Items.Count > 0 then
  begin
    FRules.ItemIndex := 0;
    FRules.Items[0].Selected := True;
    FRules.Items[0].Focused := True;
  end;
end;

procedure TConvRulesForm.RefreshRulesList;
var
  Heads: TArray<Integer>;
  H: Integer;
  Item: TListItem;
  Node: TRuleNode;
  flt : string;
begin
  FRules.Items.Clear;
  flt := '';
  if FRulesFilter <> nil then flt := LowerCase(Trim(FRulesFilter.Text));
  Heads := FBook.ConvertHeaders;
  for H in Heads do
  begin
    Node := FBook.Nodes[H];
    if (flt <> '') and (Pos(flt, LowerCase(Node.FromType + ' ' + Node.ToType)) = 0) then
      Continue;
    Item := FRules.Items.Add;
    Item.Caption := Node.FromType;
    Item.SubItems.Add(Node.ToType);
    Item.SubItems.Add(IntToStr(BlockPercent(H)) + '%');
    Item.Data := Pointer(H); // store header index
  end;
end;

function TConvRulesForm.BlockPercent(AHdrIdx: Integer): Integer;
var
  Nodes: TArray<TRuleNode>;
  N: TRuleNode;
  total, done: Integer;
begin
  // % = (links with a real From + ignores) / (links + ignores + unfilled ???)
  // A pragmatic proxy for "F leaves addressed": every #link and #ignore in the
  // block is one addressed F property; a #link still on '???' is not done.
  Nodes := FBook.NodesInBlock(AHdrIdx);
  total := 0; done := 0;
  for N in Nodes do
  begin
    if N.Kind = rnkLink then
    begin
      Inc(total);
      if (N.LinkFrom <> '') and (N.LinkFrom <> '???') then Inc(done);
    end
    else if N.Kind = rnkIgnore then
    begin
      Inc(total); Inc(done);
    end;
  end;
  if total = 0 then
  begin
    // Nothing countable. That is 0 % only if the block genuinely maps nothing --
    // an #apply-only block has no countable ROWS but is a finished rule, and
    // showing it as 0 % contradicted the save path, which keeps it. Both sides now
    // ask TRuleBook.BlockMapsSomething, so the list and the file cannot disagree.
    if TRuleBook.BlockMapsSomething(Nodes) then Exit(100);
    Exit(0);
  end;
  Result := Round(done * 100 / total);
end;

procedure TConvRulesForm.RulesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not Selected then Exit;
  if Item = nil then Exit;
  LoadGridForBlock(Integer(Item.Data));
end;

function TConvRulesForm.ActiveLinks: TArray<TRuleNode>;
begin
  if FActiveHdr < 0 then Exit(nil);
  Result := FBook.LinksForBlock(FActiveHdr);
end;

function TConvRulesForm.FindLinkForFrom(const AFromPath: string): TRuleNode;
var
  N: TRuleNode;
begin
  Result := nil;
  for N in ActiveLinks do
    if SameText(N.LinkFrom, AFromPath) then Exit(N);
end;

procedure TConvRulesForm.LoadGridForBlock(AHdrIdx: Integer);
var
  Node    : TRuleNode;
  Err     : string;
  FromNote: string;
  ToNote  : string;
  Notes   : string;
begin
  var LGuard: IInterface := HourGlass;
  FActiveHdr := AHdrIdx;
  // A fresh block: drop any pool type-narrowing carried over from the last selection.
  FPoolTypeFilter := '';
  if FTbOnlyType <> nil then FTbOnlyType.Caption := 'Only this type';
  Node := FBook.Nodes[AHdrIdx];
  // Mirror the rule's From/To into the top pickers, so a From-only rule can have a
  // To assigned there (there is otherwise no way to set the To for a picked rule).
  FCbFrom.Text := Node.FromType;
  FCbTo.Text := Node.ToType;
  SetStatus(Format('Loading property trees for %s -> %s ...', [Node.FromType, Node.ToType]));
  Application.ProcessMessages;

  // fetch F + T trees from the engine. The From tree always loads (a From-only
  // rule still shows its flattened property list); the To tree loads only once a
  // To class has been assigned.
  FromNote := ''; ToNote := '';
  if not FEngine.GetProptree(Node.FromType, FFromTree, Err, FromNote, FSurfaceMinVis) then
  begin
    SetStatus('From tree: ' + Err);
    FFromTree := Default(TProptree);
  end;
  if Trim(Node.ToType) = '' then
    FToTree := Default(TProptree)   // From-only rule: no To tree yet
  else if not FEngine.GetProptree(Node.ToType, FToTree, Err, ToNote, FSurfaceMinVis) then
  begin
    SetStatus('To tree: ' + Err);
    FToTree := Default(TProptree);
  end;
  // A bare class name that several units declare resolved by row order alone, so the
  // tree on screen may belong to the wrong framework. Say which one was used -- this
  // rides on the SUCCESS path, so it has to be carried down to the final SetStatus
  // rather than announced here, where the leaf-count message would erase it.
  Notes := '';
  if FromNote <> '' then Notes := Notes + '  ' + FromNote;
  if ToNote   <> '' then Notes := Notes + '  ' + ToNote;

  // Loading a different rule: a filter left over from the last selection would
  // silently narrow (or empty) the new grid and look like missing data, so clear
  // both grid filters the same way FPoolTypeFilter is auto-cleared above.
  FGridFindFrom.Text := '';
  FGridFindTo.Text := '';
  RefreshGrid;

  RefreshPool;
  // The examined file set is session state, not rule state (Task 4 brief): a block
  // switch must NOT clear FUsedProps, and GridDrawCell re-applies the marking to
  // the freshly-loaded rows on its own (it reads FUsedProps live at paint time).
  // Only the status line needs an explicit hand here, since the plain leaf-count
  // message below would otherwise silently replace the examination summary.
  if FExamineInfo <> '' then
    SetStatus(FExamineInfo + Notes)
  else
    SetStatus(Format('%s -> %s : %d From leaves, %d To leaves.',
      [Node.FromType, Node.ToType, Length(FFromTree.Leaves), Length(FToTree.Leaves)])
      + Notes);
  // A rule is now active: the actions that needed one become reachable. Every
  // "a rule was selected" path (RulesSelectItem, LoadFile's auto-select,
  // DoNewConversion, SurfaceChanged) lands here, so this is the single hook.
  UpdateToolbarEnabled;
end;

{ Refill the grid from FFromTree.Leaves, keeping only rows that pass the active
  From/To filter boxes (GridRowMatchesFilter; AND, case-insensitive substring,
  '' = no constraint on that side). Column 1 = the To assigned to that From leaf
  (from #link), column 2 = its cast, exactly as LoadGridForBlock used to fill
  them directly. Hiding rows only changes what is DISPLAYED -- DoAssign /
  DoUnassign / DoFindInFrom all read the SELECTED ROW'S CELL TEXT rather than
  indexing into FFromTree.Leaves by row number, so a filtered grid does not break
  them. Called once from LoadGridForBlock after the trees are (re)loaded, and
  again on every keystroke in either filter box via GridFilterChange.

  A From leaf with no #link may still be spoken for: an applied #mapping can decide it
  conditionally, and such a row shows '<conditional: N cases>' in the To column rather
  than reading as unassigned. The conditional list is built ONCE per refresh (the two
  passes below both consult it), because the alternative is rescanning every node for
  every leaf. }
procedure TConvRulesForm.RefreshGrid;
var
  i, r, matched: Integer;
  Leaf: TPropLeaf;
  Link: TRuleNode;
  fromCell, toCell: string;
  fromFilter, toFilter: string;
  conds: TArray<TConditionalFrom>;

  { The To cell for a From leaf: its #link target, else the conditional marker, else ''. }
  function ToCellFor(const APath: string; ALink: TRuleNode): string;
  var
    n: Integer;
  begin
    if ALink <> nil then
      Exit(PropCellText(ALink.LinkTo, LeafType(FToTree, ALink.LinkTo)));
    n := ConditionalCasesOf(conds, APath);
    if n > 0 then Result := Format('<conditional: %d cases>', [n])
    else          Result := '';
  end;

begin
  fromFilter := Trim(FGridFindFrom.Text);
  toFilter   := Trim(FGridFindTo.Text);
  conds      := ActiveConditionals;

  matched := 0;
  for i := 0 to High(FFromTree.Leaves) do
  begin
    Leaf := FFromTree.Leaves[i];
    fromCell := PropCellText(Leaf.Path, Leaf.TypeName);
    Link := FindLinkForFrom(Leaf.Path);
    toCell := ToCellFor(Leaf.Path, Link);
    if GridRowMatchesFilter(fromCell, toCell, fromFilter, toFilter) then
      Inc(matched);
  end;

  // RowCount must stay > FixedRows (1); a filter matching nothing still needs at
  // least one blank data row.
  FGrid.RowCount := Max(2, matched + 1);
  for r := 1 to FGrid.RowCount - 1 do
  begin
    FGrid.Cells[0, r] := ''; FGrid.Cells[1, r] := ''; FGrid.Cells[2, r] := '';
  end;

  r := 1;
  for i := 0 to High(FFromTree.Leaves) do
  begin
    Leaf := FFromTree.Leaves[i];
    fromCell := PropCellText(Leaf.Path, Leaf.TypeName);
    Link := FindLinkForFrom(Leaf.Path);
    toCell := ToCellFor(Leaf.Path, Link);
    if not GridRowMatchesFilter(fromCell, toCell, fromFilter, toFilter) then Continue;
    FGrid.Cells[0, r] := fromCell;
    // 'Path : Type' for a #link, '<conditional: N cases>' for a mapped leaf, '' for
    // an unassigned one. A conditional row has no cast: the mapping sets values, it
    // does not convert one.
    FGrid.Cells[1, r] := toCell;
    if Link <> nil then FGrid.Cells[2, r] := Link.Cast
    else                FGrid.Cells[2, r] := '';
    Inc(r);
  end;

  if FLblGridMatch <> nil then
    if (fromFilter <> '') or (toFilter <> '') then
      FLblGridMatch.Caption := Format('Showing %d of %d', [matched, Length(FFromTree.Leaves)])
    else
      FLblGridMatch.Caption := Format('%d row(s)', [Length(FFromTree.Leaves)]);
end;

{ Shared OnChange for both grid filter boxes -- narrows the grid to the current
  From/To substrings on every keystroke. Guarded like PoolFilter: no active block
  means no trees to filter yet. }
procedure TConvRulesForm.GridFilterChange(Sender: TObject);
begin
  if FActiveHdr >= 0 then RefreshGrid;
end;

{ Clear button for the From grid filter: empties only its own box and refreshes. }
procedure TConvRulesForm.DoClearGridFindFrom(Sender: TObject);
begin
  FGridFindFrom.Text := '';
  if FActiveHdr >= 0 then RefreshGrid;
end;

{ Clear button for the To grid filter: empties only its own box and refreshes. }
procedure TConvRulesForm.DoClearGridFindTo(Sender: TObject);
begin
  FGridFindTo.Text := '';
  if FActiveHdr >= 0 then RefreshGrid;
end;

procedure TConvRulesForm.RefreshPool;
var
  Assigned: TDictionary<string, Boolean>;
  Link: TRuleNode;
  Leaf: TPropLeaf;
  Filter: string;
  Target: string;
begin
  // pool = T leaves not currently assigned to any From (via #link ToPath)
  Assigned := TDictionary<string, Boolean>.Create;
  try
    for Link in ActiveLinks do
      if Link.LinkTo <> '' then Assigned.AddOrSetValue(LowerCase(Link.LinkTo), True);
    // A target an applied #mapping sets IS assigned -- by the mapping rather than by a
    // #link -- so a pool that still offered it would be lying about the block.
    for Target in MappedTargetPaths(FBook.Nodes.ToArray, ActiveAppliedNames) do
      Assigned.AddOrSetValue(LowerCase(Target), True);

    Filter := LowerCase(Trim(FPoolFind.Text));
    FPool.Items.BeginUpdate;
    try
      FPool.Items.Clear;
      for Leaf in FToTree.Leaves do
        if Leaf.IsWritable then                        // hide read-only (invalid) targets
        if not Assigned.ContainsKey(LowerCase(Leaf.Path)) then
          if (Filter = '') or (Pos(Filter, LowerCase(Leaf.Path)) > 0) then
            if (FPoolTypeFilter = '') or SameText(Leaf.TypeName, FPoolTypeFilter) then
            begin
              var disp: string := PropCellText(Leaf.Path, Leaf.TypeName);
              // public members are code-only -- tag so a DFM rule sees they won't
              // stream to a .dfm (published targets carry no tag).
              if SameText(Leaf.Visibility, 'public') then disp := disp + '   (PAS-only)';
              FPool.Items.Add(disp);
            end;
    finally
      FPool.Items.EndUpdate;
    end;
  finally
    Assigned.Free;
  end;
end;

procedure TConvRulesForm.PoolFilter(Sender: TObject);
begin
  if FActiveHdr >= 0 then RefreshPool;
end;

function PathOfGridCell(const S: string): string;
var p: Integer;
begin
  p := Pos(' : ', S);
  if p > 0 then Result := Copy(S, 1, p - 1) else Result := S;
end;

{ The type token of a 'Path : Type [tag]' grid/pool cell ('' when there is no ' : ').
  Takes only the first token after ' : ' so a trailing display tag (e.g. the
  '(PAS-only)' pool marker) does not corrupt a type comparison. }
function TypeOfCell(const S: string): string;
var p, sp: Integer;
begin
  Result := '';
  p := Pos(' : ', S);
  if p <= 0 then Exit;
  Result := Trim(Copy(S, p + 3, MaxInt));
  sp := Pos(' ', Result);
  if sp > 0 then Result := Copy(Result, 1, sp - 1);
end;

{ The last dotted segment of a property path ('Font.Color' -> 'Color'). }
function LeafNameOf(const APath: string): string;
var d: Integer;
begin
  Result := APath;
  d := LastDelimiter('.', Result);
  if d > 0 then Result := Copy(Result, d + 1, MaxInt);
end;

{ Whether one grid row passes the grid's two filter boxes. AND semantics: with
  both filters set, BOTH must match; an empty filter imposes no constraint on
  its side. Case-insensitive substring, consistent with the pool search
  (PoolFilter). The one place this comparison is defined -- RefreshGrid just
  calls it per row. }
function GridRowMatchesFilter(const AFromCell, AToCell, AFromFilter, AToFilter: string): Boolean;
begin
  Result := ((AFromFilter = '') or (Pos(LowerCase(AFromFilter), LowerCase(AFromCell)) > 0))
        and ((AToFilter = '') or (Pos(LowerCase(AToFilter), LowerCase(AToCell)) > 0));
end;

{ ---- Go to definition -------------------------------------------------------

  A cell in the grid or the pool reads 'Path : Type'. That Type is the one piece of
  the editor a user regularly needs to look AT rather than assign: what are the
  legal values of TabcButtonStyle, what is TdxAlignment really. Right-click resolves
  it through the engine and asks the RUNNING IDE to open the declaration, so the
  answer arrives in the editor already open rather than in a second bds.exe. }

procedure TConvRulesForm.BuildTypePopup;
begin
  FTypePopup := TPopupMenu.Create(Self);

  FMnuGotoDef := TMenuItem.Create(Self);
  // A placeholder: GridPoolContextPopup rewrites this with the actual type before
  // the menu is ever shown, and suppresses the menu when there is no type.
  FMnuGotoDef.Caption := 'Go to definition';
  FMnuGotoDef.OnClick := DoGoToDefinition;
  FTypePopup.Items.Add(FMnuGotoDef);

  // ONE popup on both controls: the cells share the 'Path : Type' shape, and
  // OnContextPopup's Sender tells the handler which one was clicked.
  FGrid.PopupMenu := FTypePopup;
  FPool.PopupMenu := FTypePopup;
  FGrid.OnContextPopup := GridPoolContextPopup;
  FPool.OnContextPopup := GridPoolContextPopup;
end;

function TConvRulesForm.TypeAtPos(ASender: TObject; const APos: TPoint): string;
var
  C, R: Integer;
  Idx : Integer;
begin
  Result := '';
  if ASender = FPool then
  begin
    // Existing=True: past the last item this returns -1 rather than the nearest row.
    Idx := FPool.ItemAtPos(APos, True);
    if (Idx >= 0) and (Idx < FPool.Items.Count) then
      Result := TypeOfCell(FPool.Items[Idx]);
  end
  else if ASender = FGrid then
  begin
    FGrid.MouseToCell(APos.X, APos.Y, C, R);
    // R = 0 is the header and R < 0 is off-grid; the cast column holds no ' : Type'
    // so TypeOfCell returns '' for it without a column test.
    if (C >= 0) and (R >= 1) then Result := TypeOfCell(FGrid.Cells[C, R]);
  end;
end;

procedure TConvRulesForm.GridPoolContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin
  FCtxType := TypeAtPos(Sender, MousePos);
  if FCtxType = '' then
  begin
    Handled := True;      // nothing to offer here -> show no menu at all
    Exit;
  end;
  FMnuGotoDef.Caption := 'Go to definition of ' + FCtxType;
end;

procedure TConvRulesForm.DoGoToDefinition(Sender: TObject);
var
  LFile   : string;
  LErr    : string;
  LWhere  : string;
  LMsg    : string;
  LLine   : Integer;
  LAmbig  : Integer;
  LMembers: TArray<string>;
begin
  if FCtxType = '' then Exit;
  // Both engine calls run on this thread (RunCapture drains here), so the window
  // is unresponsive for their duration -- say so with the cursor.
  var LGuard: IInterface := HourGlass;

  if not FEngine.ResolveTypeLocation(FCtxType, LFile, LLine, LErr, LAmbig) then
  begin
    SetError(LErr);
    Exit;
  end;
  LWhere := Format('%s:%d', [LFile, LLine]);
  LMsg   := FCtxType + ' -- ' + LWhere;

  // Several equally-ranked declarations carried this name and the engine's row order
  // picked one. That happens on types the grid shows constantly -- TAlignment has
  // three, TColor two -- so it is said out loud rather than presented as the answer.
  // The unit is the file's base name, which is what makes "opened System.Classes"
  // readable at a glance next to the full path.
  if LAmbig > 1 then
    LMsg := Format('%d declarations named %s; opened %s.  ',
      [LAmbig, FCtxType, ChangeFileExt(ExtractFileName(LFile), '')]) + LMsg;

  // For an enum the member list is usually the actual question ("what can Style
  // be?"), so it rides along. A failure here is NOT reported: the location is
  // still good, and most types are simply not enums.
  if FEngine.EnumMembersOf(FCtxType, LMembers, LErr) and (Length(LMembers) > 0) then
    LMsg := LMsg + '  (' + string.Join(', ', LMembers) + ')';

  if SendOpenSource(LFile, LLine) then
    SetStatus('Opened in the IDE: ' + LMsg)
  else
    // No plugin answered the pipe (no IDE running, or its BPL is not loaded).
    // Failing silently is the one unacceptable outcome, so hand over something
    // pasteable and say why.
    try
      Clipboard.AsText := LWhere;
      SetStatus('No IDE is listening -- copied to the clipboard: ' + LMsg);
    except
      on E: Exception do
        SetStatus('No IDE is listening, and the clipboard refused ('
          + E.Message + '): ' + LMsg);
    end;
end;

{ Examine: pick .dfm/.pas files and ask ConvRules.Usage.ComputeUsage which of the active
  rule's From properties they actually assign or reference, so the grid can be triaged
  down from thousands of leaves to the handful a real form touches. Read-only -- only
  TFile.ReadAllText is called on the chosen files, nothing is ever written. Requires a
  selected #convert rule (FActiveHdr >= 0); the From class comes from FBook, not the
  picker text, so it is always in sync with the grid currently on screen.

  The same .pas texts are also run through ScanUsesClauses, and the units they name
  become CANDIDATE rows on the Unit Rules tab -- a work list, not an edit. The rule
  book is not touched by any of this. }
function TConvRulesForm.DeclaringUnitCached(const ATypeName: string): string;
begin
  if FDeclUnits = nil then
    FDeclUnits := TDictionary<string, string>.Create;
  if FDeclUnits.TryGetValue(UpperCase(ATypeName), Result) then Exit;
  Result := FEngine.DeclaringUnitOf(ATypeName);
  FDeclUnits.AddOrSetValue(UpperCase(ATypeName), Result);
end;

procedure TConvRulesForm.HarvestFormTypes(const ADfmTexts: TArray<string>);
var
  Parts : TArray<TFormTypeRows>;
  Old   : TFormTypeRows;
  Txt   : string;
  Names : TArray<string>;
  Err   : string;
  N     : string;
  i, j  : Integer;
begin
  Old   := FFormTypeRows;
  Parts := nil;
  for Txt in ADfmTexts do
    Parts := Parts + [ScanDfmTypes(Txt)];
  FFormTypeRows := MergeFormTypes(Parts);

  // A manual re-enable is the user's decision about a TYPE, not about a scan, so it
  // survives re-Examining the same form. Without this, re-running Examine would
  // silently undo every override.
  for i := 0 to High(FFormTypeRows) do
    for j := 0 to High(Old) do
      if SameText(Old[j].TypeName, FFormTypeRows[i].TypeName) then
      begin
        FFormTypeRows[i].Reenabled := Old[j].Reenabled;
        Break;
      end;

  // Three descendant sets, once per session. Non-fatal: if the engine cannot
  // answer, rows stay '?' rather than being labelled non-visual on no evidence.
  if FVisualSet = nil then
  begin
    var LGuard: IInterface := HourGlass;
    FVisualSet     := LoadDescendantSet('TControl');
    FComponentSet  := LoadDescendantSet('TComponent');
    FPersistentSet := LoadDescendantSet('TPersistent');
  end;

  if Length(FCatalog) = 0 then RescanRulesFolder(nil);
  RefreshFormTypes;
end;

function TConvRulesForm.LoadDescendantSet(const AAncestor: string): TStringList;
var
  Names: TArray<string>;
  Err  : string;
  N    : string;
begin
  Result := TStringList.Create;
  Result.Sorted        := True;
  Result.Duplicates    := dupIgnore;
  Result.CaseSensitive := False;
  if not FEngine.ListDescendantsOf(AAncestor, Names, Err) then Exit;
  for N in Names do
    if Trim(N) <> '' then Result.Add(Trim(N));
end;

procedure TConvRulesForm.FilterChanged(Sender: TObject);
begin
  RefreshFormTypes;
end;

procedure TConvRulesForm.RefreshFormTypes;
var
  Pats  : TArray<string>;
  Err   : string;
  DeclU : string;
  Entry : TRuleCatalogEntry;
  i     : Integer;
  Active: Integer;
  Cold  : Integer;
begin
  if (FFormTypeList = nil) or (FFilterMemo = nil) then Exit;

  Pats := FFilterMemo.Lines.ToStringArray;
  FFilterError := '';
  Active := 0;

  // Resolving a declaring unit costs a process spawn against a multi-GB index
  // (measured 1.7 s each), so it happens ONLY when the standard-controls box is
  // ticked -- the one thing that needs it -- and the user is told what it costs
  // rather than watching a frozen window.
  if FChkStdCtrls.Checked then
  begin
    Cold := 0;
    for i := 0 to High(FFormTypeRows) do
      if (FDeclUnits = nil)
         or (not FDeclUnits.ContainsKey(UpperCase(FFormTypeRows[i].TypeName))) then
        Inc(Cold);
    if Cold > 0 then
    begin
      SetStatus(Format('Resolving declaring units for %d type(s) (~%d s) ...',
        [Cold, Round(Cold * 1.7)]));
      Application.ProcessMessages;
    end;
  end;

  for i := 0 to High(FFormTypeRows) do
  begin
    // Only the standard-controls test needs the unit. Everything else works off
    // the three cached descendant sets.
    if FChkStdCtrls.Checked then
      DeclU := DeclaringUnitCached(FFormTypeRows[i].TypeName)
    else
      DeclU := '';

    // '?' is NOT a synonym for non-visual. A type is only tvkNonVisual when the
    // index PLACES it (it descends from TComponent or TPersistent) and it is not a
    // TControl. TField and its kin come through TPersistent, not TComponent, which
    // is why both sets are consulted.
    if (FVisualSet <> nil) and (FVisualSet.IndexOf(FFormTypeRows[i].TypeName) >= 0) then
      FFormTypeRows[i].Visual := tvkVisual
    else if ((FComponentSet <> nil) and (FComponentSet.IndexOf(FFormTypeRows[i].TypeName) >= 0))
         or ((FPersistentSet <> nil) and (FPersistentSet.IndexOf(FFormTypeRows[i].TypeName) >= 0)) then
      FFormTypeRows[i].Visual := tvkNonVisual
    else
      FFormTypeRows[i].Visual := tvkUnknown;

    FFormTypeRows[i].Excluded := TypeIsExcluded(FFormTypeRows[i].TypeName, DeclU,
      Pats, FChkStdCtrls.Checked, Err);
    if (Err <> '') and (FFilterError = '') then FFilterError := Err;

    if FindRuleForType(FCatalog, FFormTypeRows[i].TypeName, Entry) then
    begin
      FFormTypeRows[i].Ruled   := True;
      FFormTypeRows[i].RuledBy := ExtractFileName(Entry.FilePath);
    end
    else
    begin
      FFormTypeRows[i].Ruled   := False;
      FFormTypeRows[i].RuledBy := '';
    end;

    if not RowIsGreyed(FFormTypeRows[i]) then Inc(Active);
  end;

  FFormTypeList.Items.BeginUpdate;
  try
    FFormTypeList.Items.Clear;
    for i := 0 to High(FFormTypeRows) do
      FFormTypeList.Items.Add(FFormTypeRows[i].TypeName);
  finally
    FFormTypeList.Items.EndUpdate;
  end;

  // A malformed pattern excludes nothing, so without this line the user would read
  // an un-greyed row as "my filter kept this" when the condition never ran at all.
  if FFilterError <> '' then
    FLblFormTypes.Caption := 'FILTER ERROR -- ' + FFilterError
  else
    FLblFormTypes.Caption := Format('%d type(s), %d active',
      [Length(FFormTypeRows), Active]);
end;

procedure TConvRulesForm.RescanRulesFolder(Sender: TObject);
var
  Errs  : TArray<string>;
  Folder: string;
begin
  Folder := Trim(FRulesFolder);
  if Folder = '' then Folder := ExtractFilePath(FFilePath);
  if Folder = '' then
  begin
    SetStatus('No rules folder yet -- open a rule book first, then Rescan rules.');
    Exit;
  end;

  FCatalog     := ScanRulesFolder(Folder, Errs);
  FRulesFolder := Folder;

  // The index is a CACHE of what the folder says; failing to write it must not
  // invalidate the catalog we just built in memory.
  try
    TFile.WriteAllText(TPath.Combine(Folder, CATALOG_INDEX_FILE),
      CatalogToIndexText(FCatalog));
  except
    on E: Exception do
      SetStatus('Catalog built, but its index could not be written: ' + E.Message);
  end;

  if Sender <> nil then
  begin
    RefreshFormTypes;
    if Length(Errs) > 0 then
      SetStatus(Format('%d conversion(s) catalogued from %s; %d file(s) unreadable: %s',
        [Length(FCatalog), Folder, Length(Errs), string.Join('; ', Errs)]))
    else
      SetStatus(Format('%d conversion(s) catalogued from %s.',
        [Length(FCatalog), Folder]));
  end;
end;

procedure TConvRulesForm.FormTypeClick(Sender: TObject);
var
  i: Integer;
begin
  i := FFormTypeList.ItemIndex;
  if (i < 0) or (i > High(FFormTypeRows)) then Exit;

  FCbFrom.Text := FFormTypeRows[i].TypeName;
  if FFormTypeRows[i].Ruled then
    SetStatus(Format('From set to %s -- already converted by %s. Pick a To class, ' +
      'then New conversion.', [FFormTypeRows[i].TypeName, FFormTypeRows[i].RuledBy]))
  else
    SetStatus(Format('From set to %s. Pick a To class, then New conversion.',
      [FFormTypeRows[i].TypeName]));
end;

procedure TConvRulesForm.ToggleFormTypeReenable(Sender: TObject);
var
  i: Integer;
begin
  i := FFormTypeList.ItemIndex;
  if (i < 0) or (i > High(FFormTypeRows)) then Exit;
  FFormTypeRows[i].Reenabled := not FFormTypeRows[i].Reenabled;
  RefreshFormTypes;
  FFormTypeList.ItemIndex := i;
end;

procedure TConvRulesForm.FormTypeDrawItem(AControl: TWinControl; AIndex: Integer;
  ARect: TRect; AState: TOwnerDrawState);
var
  LB  : TListBox;
  Row : TFormTypeRow;
  Mark: string;
  S   : string;
begin
  LB := TListBox(AControl);
  LB.Canvas.FillRect(ARect);
  if (AIndex < 0) or (AIndex > High(FFormTypeRows)) then Exit;
  Row := FFormTypeRows[AIndex];

  case Row.Visual of
    tvkVisual   : Mark := '[V]';
    tvkNonVisual: Mark := '[N]';
  else
    Mark := '[?]';
  end;

  S := Format('%s %s  (%d)', [Mark, Row.TypeName, Row.Count]);
  if Row.Ruled     then S := S + '  -- ' + Row.RuledBy;
  if Row.Reenabled then S := S + '  *';

  // Selection keeps the theme's highlight colours; only unselected greyed rows are
  // dimmed, so a greyed row stays readable when the user is on it.
  if RowIsGreyed(Row) and not (odSelected in AState) then
    LB.Canvas.Font.Color := clGrayText;

  LB.Canvas.TextOut(ARect.Left + 4, ARect.Top + 1, S);
end;

function TConvRulesForm.ExpandUnitSiblings(const APaths: TArray<string>): TArray<string>;
var
  Seen: TStringList;
  P, Sib, Ext: string;

  procedure Take(const APath: string);
  begin
    if (Trim(APath) = '') or (not TFile.Exists(APath)) then Exit;
    if Seen.IndexOf(APath) >= 0 then Exit;
    Seen.Add(APath);
    Result := Result + [APath];
  end;

begin
  Result := nil;
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := False;
    for P in APaths do
    begin
      Take(P);
      Ext := LowerCase(ExtractFileExt(P));
      if Ext = '.pas' then Sib := ChangeFileExt(P, '.dfm')
      else if Ext = '.dfm' then Sib := ChangeFileExt(P, '.pas')
      else Sib := '';
      Take(Sib);
    end;
  finally
    Seen.Free;
  end;
end;

procedure TConvRulesForm.SetLastFormDir(const ADir: string);
var
  Reg: TRegistry;
begin
  if Trim(ADir) = '' then Exit;
  FLastFormDir := ADir;
  // Same policy as the theme: a locked HKCU costs the NEXT session's convenience,
  // never this session's work, so it is not worth an error dialog.
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKey(EDITOR_REG_KEY, True) then
        Reg.WriteString(EDITOR_REG_FORMDIR, ADir);
    except
      // Same precedent as SetThemePref: say it once, do not raise. Callers set the
      // dir BEFORE loading a form, so the load's own status supersedes this line --
      // which is why it is safe to report here at all.
      on E: ERegistryException do
        SetStatus('Folder remembered for this session only, not saved: ' + E.Message);
    end;
  finally
    Reg.Free;
  end;
end;

function TConvRulesForm.PickFormFiles(out AFiles: TArray<string>): Boolean;
var
  Dlg: TOpenDialog;
begin
  Result := False;
  AFiles := nil;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Delphi form and source (*.dfm;*.pas)|*.dfm;*.pas|'
      + 'Form files (*.dfm)|*.dfm|Source (*.pas)|*.pas|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    // Resume where the user was: --form's folder on the first browse of a debug
    // run, otherwise wherever they browsed last. A folder that no longer exists is
    // ignored by TOpenDialog rather than being an error.
    if (FLastFormDir <> '') and TDirectory.Exists(FLastFormDir) then
      Dlg.InitialDir := FLastFormDir;
    if not Dlg.Execute then Exit;
    AFiles := ExpandUnitSiblings(Dlg.Files.ToStringArray);
    if Length(AFiles) > 0 then SetLastFormDir(ExtractFileDir(AFiles[0]));
    Result := Length(AFiles) > 0;
  finally
    Dlg.Free;
  end;
end;

procedure TConvRulesForm.DoOpenForm(Sender: TObject);
var
  Files: TArray<string>;
begin
  if PickFormFiles(Files) then LoadFormFiles(Files);
end;

procedure TConvRulesForm.DoExamine(Sender: TObject);
var
  Files: TArray<string>;
begin
  if PickFormFiles(Files) then LoadFormFiles(Files);
end;

procedure TConvRulesForm.LoadFormFiles(const AFiles: TArray<string>);
var
  Dfms, Pass: TArray<string>;
  Bad  : TArray<string>;
  Paths: TArray<string>;
  U    : TUsageSet;
  L    : TPropLeaf;
  F    : string;
  T    : string;
  UnitParts: TArray<TArray<string>>;
  FromBare: string;
  DotPos  : Integer;
begin
  // NO "select a conversion first" gate. The form-types panel exists to CHOOSE a
  // From class, so loading a form has to work before any rule is selected. Only
  // the property-usage half below needs an active rule; the type harvest does not.
  if Length(AFiles) = 0 then Exit;
  FUsedFiles := AFiles;

  // LGuard is scoped to this nested block only, so the wait cursor comes back down
  // before ShowUsageReport's modal report below -- that dialog waits on the user,
  // which is not what an hourglass should be shown over.
  begin
    var LGuard: IInterface := HourGlass;
    Dfms := nil; Pass := nil; Bad := nil;
    for F in FUsedFiles do
      try
        if SameText(ExtractFileExt(F), '.dfm') then
          Dfms := Dfms + [TFile.ReadAllText(F)]
        else
          Pass := Pass + [TFile.ReadAllText(F)];
      except
        on E: Exception do Bad := Bad + [ExtractFileName(F)];
      end;

    HarvestFormTypes(Dfms);
  end;

  if FActiveHdr < 0 then
  begin
    FExamineInfo := Format('Examined %d file(s): %d type(s) listed on the left. ' +
      'Select a conversion to also mark its used From properties.',
      [Length(FUsedFiles), Length(FFormTypeRows)]);
    if Length(Bad) > 0 then
      FExamineInfo := FExamineInfo + ' Unreadable: ' + string.Join(', ', Bad);
    SetStatus(FExamineInfo);
    Exit;
  end;

  Paths := nil;
  for L in FFromTree.Leaves do
    Paths := Paths + [L.Path];

  // A DFM always writes the BARE class name ('object X: TabcToggleBtn'), never a
  // unit-qualified one, but FBook's FromType may be qualified -- strip any prefix
  // up to and including the last '.' before handing it to ComputeUsage.
  FromBare := FBook.Nodes[FActiveHdr].FromType;
  DotPos := LastDelimiter('.', FromBare);
  if DotPos > 0 then FromBare := Copy(FromBare, DotPos + 1, MaxInt);

  begin
    var LUsageGuard: IInterface := HourGlass;
    U := ComputeUsage(Dfms, Pass, FromBare, Paths);
  end;

  FUsedProps := U.Names;

  // The same .pas texts also answer "which units does this form pull in" -- harvest
  // them into the Unit Rules tab as CANDIDATES. Deliberately additive: it never
  // creates, edits or deletes a rule, so Examine stays the read-only action it says
  // it is. RefreshUnitList does the "already has a rule" filtering.
  UnitParts := nil;
  for T in Pass do
    UnitParts := UnitParts + [ScanUsesClauses(T)];
  FUnitCandidates := MergeUsage(UnitParts);

  FExamineInfo := Format('Examined %d file(s): %d of %d From properties used; ' +
    '%d unit(s) offered on the Unit Rules tab.',
    [U.DfmCount + U.PasCount, Length(U.Names), Length(Paths),
     Length(FUnitCandidates)]);
  if Length(Bad) > 0 then
    FExamineInfo := FExamineInfo + ' Unreadable: ' + string.Join(', ', Bad);
  SetStatus(FExamineInfo);
  FGrid.Invalidate;
  RefreshUnitList;        // draws the harvested units as candidate rows
  UpdateToolbarEnabled;   // "Clear marks" is gated on there BEING an examination

  if Length(U.Missing) > 0 then
    ShowUsageReport(U.Missing);
end;

{ Drop the current examination -- the session-state fields only (green marks AND the
  harvested unit candidates); the rule model itself is untouched. }
procedure TConvRulesForm.DoClearExamine(Sender: TObject);
begin
  FUsedProps := nil;
  FUsedFiles := nil;
  FUnitCandidates := nil;
  FExamineInfo := '';
  FGrid.Invalidate;
  RefreshUnitList;        // takes the candidate rows back off the Unit Rules tab
  UpdateToolbarEnabled;   // nothing left to clear -> "Clear marks" goes back down
  SetStatus('Examination cleared.');
end;

{ Small read-only report window: used names the examined files reference that match
  no leaf of the active From tree -- expected to be rare, and worth surfacing since
  it usually means the indexer's proptree is missing something real. }
procedure TConvRulesForm.ShowUsageReport(const AMissing: TArray<string>);
var
  F   : TForm;
  Memo: TMemo;
  Btn : TButton;
  N   : string;
begin
  F := TForm.CreateNew(Self);
  try
    F.Caption     := 'Examine -- used names with no grid row';
    F.Width       := 520;
    F.Height      := 420;
    F.Position    := poOwnerFormCenter;
    F.BorderStyle := bsSizeable;

    Btn := TButton.Create(F);
    Btn.Parent := F; Btn.Align := alBottom;
    Btn.Caption := 'Close'; Btn.ModalResult := mrOk;

    Memo := TMemo.Create(F);
    Memo.Parent     := F;
    Memo.Align      := alClient;
    Memo.ReadOnly   := True;
    Memo.ScrollBars := ssBoth;
    Memo.WordWrap   := False;
    Memo.Font.Name  := 'Consolas';
    Memo.Font.Size  := 9;
    Memo.Lines.Add(Format('%d name(s) used in the examined files have no row in this grid:',
      [Length(AMissing)]));
    Memo.Lines.Add('');
    for N in AMissing do
      Memo.Lines.Add(N);

    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ FGrid.OnDrawCell -- owns ALL cell painting once FGrid.DefaultDrawing is False.
  A data row (ARow > 0) whose From path is in FUsedProps paints green, EXCEPT when
  it is the selected cell/row: selection must stay visible on a marked row, so
  gdSelected always wins and paints the normal highlight colour instead.

  Every colour goes through StyleServices.GetSystemColor rather than the raw cl*
  constant. DefaultDrawing = False keeps the style engine out of this canvas, so
  without that indirection the grid would keep painting the system light palette
  under a dark style. The marking itself is derived from the ACTIVE window colour
  (ConvRules.Theme.ExamineRowColor) so it stays a visible tint on either ground
  instead of a fixed pale green that vanishes on dark. }
procedure TConvRulesForm.GridDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
var
  Cv : TCanvas;
  Win: TColor;
begin
  Cv  := FGrid.Canvas;
  Win := StyleServices.GetSystemColor(clWindow);
  if (ARow > 0) and (gdSelected not in State)
     and (Length(FUsedProps) > 0)
     and IsRowUsed(PathOfGridCell(FGrid.Cells[0, ARow]), FUsedProps) then
    // ColorToRGB: under the system style GetSystemColor hands back the clWindow
    // CONSTANT ($FF0000xx), whose bytes are an index, not channels -- tinting that
    // would produce nonsense. Real styles already return RGB, where it is a no-op.
    Cv.Brush.Color := TColor(ExamineRowColor(Integer(ColorToRGB(Win)), FThemeMode))
  else if gdSelected in State then
    Cv.Brush.Color := StyleServices.GetSystemColor(clHighlight)
  else if gdFixed in State then
    Cv.Brush.Color := StyleServices.GetSystemColor(clBtnFace)
  else
    Cv.Brush.Color := Win;

  if gdSelected in State then Cv.Font.Color := StyleServices.GetSystemColor(clHighlightText)
  else Cv.Font.Color := StyleServices.GetSystemColor(clWindowText);

  Cv.FillRect(Rect);
  Cv.TextRect(Rect, Rect.Left + 2, Rect.Top + 2, FGrid.Cells[ACol, ARow]);
end;

{ Align the highlighted To leaf to the From side: select the From-grid row whose
  property has the SAME last-segment name (case-insensitive), so the two sides can
  be assigned by name. Reports when no From property carries that name. }
procedure TConvRulesForm.DoFindInFrom(Sender: TObject);
var
  toName: string;
  r     : Integer;
begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  if FPool.ItemIndex < 0 then
  begin SetStatus('Highlight a To leaf in the pool (right) first.'); Exit; end;
  toName := LeafNameOf(PathOfGridCell(FPool.Items[FPool.ItemIndex]));
  for r := 1 to FGrid.RowCount - 1 do
    if SameText(LeafNameOf(PathOfGridCell(FGrid.Cells[0, r])), toName) then
    begin
      FGrid.Row := r;   // the Row setter scrolls the cell into view
      SetStatus(Format('From row matching "%s": %s', [toName, FGrid.Cells[0, r]]));
      Exit;
    end;
  SetStatus(Format('No From property named "%s" in this rule.', [toName]));
end;

{ Toggle a pool type-narrowing: first press restricts the pool to leaves whose
  TYPE matches the highlighted leaf (e.g. only Boolean targets); a second press
  clears it. Cleared automatically when a different rule is loaded. }
procedure TConvRulesForm.DoOnlyType(Sender: TObject);
var
  t: string;
begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  if FPoolTypeFilter <> '' then
  begin
    FPoolTypeFilter := '';
    FTbOnlyType.Caption := 'Only this type';
    RefreshPool;
    SetStatus('Pool type filter cleared.');
    Exit;
  end;
  if FPool.ItemIndex < 0 then
  begin SetStatus('Highlight a To leaf whose type to filter by.'); Exit; end;
  t := TypeOfCell(FPool.Items[FPool.ItemIndex]);
  if t = '' then begin SetStatus('That leaf has no resolved type to filter by.'); Exit; end;
  FPoolTypeFilter := t;
  FTbOnlyType.Caption := 'Show all types';
  RefreshPool;
  SetStatus(Format('Pool narrowed to type "%s".', [t]));
end;

{ ---- conditional #mapping rules ---------------------------------------------

  A #mapping is FILE-scope and reaches a block only through an #apply, so both
  helpers below read the WHOLE book for the clauses but only the ACTIVE BLOCK for
  which mappings are in force. The folding itself lives in ConvRules.Mappings; this
  window just asks. }

function TConvRulesForm.ActiveAppliedNames: TArray<string>;
begin
  if FActiveHdr < 0 then Exit(nil);
  Result := AppliedMappingNames(FBook.NodesInBlock(FActiveHdr));
end;

function TConvRulesForm.ActiveConditionals: TArray<TConditionalFrom>;
begin
  if FActiveHdr < 0 then Exit(nil);
  Result := ConditionalFromPaths(FBook.Nodes.ToArray, ActiveAppliedNames);
end;

{ "Mappings..." -- open the conditional-mapping editor for ONE named #mapping and
  splice the result back into the book.

  The name is asked for with InputQuery rather than a second picker window: the
  file's existing names are listed in the prompt, so an unrecognised name reads as
  "create this one" instead of silently editing the wrong mapping.

  Three things happen on the way back in, and each of them is why this is not just
  a ShowModal call:
   * the mapping's OLD lines are replaced by the new ones, because the editor
     rewrites the whole mapping as one unit. The splice itself lives in
     TRuleBook.ReplaceMapping, which is where its rules (where a brand-new mapping
     lands, why the deletes run descending) are written down and tested.
   * FActiveHdr is re-derived from the header NODE, since inserting above it moves
     its index.
   * the #apply is added when it is missing. Without it the mapping is authored,
     validated and completely inert, and the grid would show nothing at all. }
procedure TConvRulesForm.DoMappings(Sender: TObject);
var
  Names  : TArray<string>;
  Name   : string;
  Prompt : string;
  Own    : TArray<TRuleNode>;
  Hdr    : TRuleNode;
  N      : TRuleNode;
  Applied: Boolean;
begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;

  Names := MappingNames(FBook.Nodes.ToArray);

  // Default to the mapping this block already applies, else the first one in the file.
  Name := '';
  for N in FBook.NodesInBlock(FActiveHdr) do
    if (N.Kind = rnkApply) and (N.ApplyName <> '') then begin Name := N.ApplyName; Break; end;
  if (Name = '') and (Length(Names) > 0) then Name := Names[0];

  Prompt := 'Mapping name -- an existing one, or a new name to create:';
  if Length(Names) > 0 then
    Prompt := Prompt + sLineBreak + 'In this file: ' + string.Join(', ', Names);
  if not InputQuery('Mappings', Prompt, Name) then Exit;
  Name := Trim(Name);
  if Name = '' then begin SetStatus('No mapping name given.'); Exit; end;

  // The mapping's lines as they stand -- borrowed, the book still owns them; they are
  // the editor's seed.
  Own := FBook.MappingNodesNamed(Name);

  Hdr := FBook.Nodes[FActiveHdr];
  if not TMappingForm.EditMapping(Self, Name, Own, FEngine, FToTree, Hdr.ToType) then
  begin
    SetStatus(Format('Mapping "%s" unchanged.', [Name]));
    Exit;
  end;
  // Own now holds FRESH nodes owned by this method until ReplaceMapping takes them.

  // The splice itself is the BOOK's job, not the window's: the index arithmetic (delete
  // descending, insert at the first freed slot, file scope for a brand-new mapping) is
  // model surgery, and the two data-loss bugs this feature shipped with were both in
  // exactly that seam.
  FBook.ReplaceMapping(Name, Own);

  // Inserting above the header moved it, so the index must be re-derived from the NODE.
  FActiveHdr := FBook.Nodes.IndexOf(Hdr);

  Applied := False;
  for N in FBook.NodesInBlock(FActiveHdr) do
    if (N.Kind = rnkApply) and SameText(N.ApplyName, Name) then
    begin Applied := True; Break; end;
  if not Applied then
  begin
    N := TRuleNode.Create;
    N.Kind      := rnkApply;
    N.ApplyName := Name;
    N.Dirty     := True;
    FBook.Nodes.Insert(FActiveHdr + 1, N);
  end;

  LoadGridForBlock(FActiveHdr);
  SyncRawFromModel;
  RefreshRulesList;
  SetStatus(Format('Mapping "%s": %d line(s) written%s.',
    [Name, Length(Own), IfThen(Applied, '', ' and #apply added to this conversion')]));
end;

{ Target surface changed (DFM published <-> PAS public+fields): remember the new
  --min-visibility and re-fetch the active rule's From/To trees at that surface. }
procedure TConvRulesForm.SurfaceChanged(Sender: TObject);
begin
  if FCbSurface.ItemIndex = 1 then FSurfaceMinVis := 'public'
  else FSurfaceMinVis := 'published';
  if FActiveHdr >= 0 then LoadGridForBlock(FActiveHdr);
  if FSurfaceMinVis = 'public' then
    SetStatus('Surface: PAS -- public props + public fields (public targets tagged PAS-only).')
  else
    SetStatus('Surface: DFM -- published (DFM-streamable) props only.');
end;

{ Create or update the #link mapping ToPath <- FromPath in the active block,
  choosing a default cast from the leaf types (identity when same type). Shared by
  the manual Assign and the Auto-Match pass. Does NOT touch the grid/UI -- callers
  refresh. Assumes CanCast(AFromType, AToType) was already checked. }
procedure TConvRulesForm.AssignLink(const AFromPath, AToPath, AFromType, AToType: string);
var
  Link    : TRuleNode;
  i       : Integer;
  insertAt: Integer;
  casts   : TCastFnSet;
  c       : TCastFn;
begin
  Link := FindLinkForFrom(AFromPath);
  if Link = nil then
  begin
    Link := TRuleNode.Create;
    Link.Kind := rnkLink;
    Link.LinkFrom := AFromPath;
    Link.Dirty := True;
    insertAt := FActiveHdr + 1;
    for i := FActiveHdr + 1 to FBook.Nodes.Count - 1 do
    begin
      if FBook.Nodes[i].Kind = rnkConvert then Break;
      insertAt := i + 1;
    end;
    FBook.Nodes.Insert(insertAt, Link);
  end;
  Link.LinkTo := AToPath;
  Link.Dirty := True;

  // identity (same family or same type) -> no cast; else the first valid cast
  if SameFamily(AFromType, AToType) or SameText(AFromType, AToType) then
    Link.Cast := ''
  else
  begin
    casts := ValidCasts(AFromType, AToType);
    Link.Cast := '';
    for c := Low(TCastFn) to High(TCastFn) do
      if c in casts then begin Link.Cast := CastFnName(c); Break; end;
    if Link.Cast = '' then
      Link.Cast := ClassCastName(AFromType, AToType);   // library class cast (e.g. AssignGraphic)
  end;
end;

procedure TConvRulesForm.DoAssign(Sender: TObject);
var
  FromPath, ToPath: string;
  row     : Integer;
  LCases  : Integer;
  fromType, toType: string;
begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  if FPool.ItemIndex < 0 then begin SetStatus('Pick a To property from the pool (right) first.'); Exit; end;
  row := FGrid.Row;
  if row < 1 then begin SetStatus('Pick a From row in the grid (left) first.'); Exit; end;

  FromPath := PathOfGridCell(FGrid.Cells[0, row]);
  ToPath   := PathOfGridCell(FPool.Items[FPool.ItemIndex]);
  if (FromPath = '') or (ToPath = '') then Exit;

  // Exactly the rule DoAutoMatch applies to the same rows: a From leaf an applied
  // #mapping already decides conditionally is spoken for, even though it has no #link.
  // Writing an unconditional #link beside it leaves TWO rules claiming one source
  // property, and nothing downstream catches that -- RefreshPool withholds its targets
  // and RefreshGrid labels it '<conditional: N cases>', but ValidateMappings is never
  // run over the whole book, so the clash would ship silently.
  LCases := ConditionalCasesOf(ActiveConditionals, FromPath);
  if LCases > 0 then
  begin
    SetError(Format('Blocked: %s is already decided by an applied #mapping (%d case(s)). '
      + 'Edit that mapping instead -- a #link here would claim the same source property '
      + 'a second time, unconditionally.', [FromPath, LCases]));
    Exit;
  end;

  fromType := LeafType(FFromTree, FromPath);
  toType   := LeafType(FToTree, ToPath);
  // If one side's type is unknown (inherited from an unresolved parent), infer it
  // from the other side -- a same-named property is the same inherited member.
  ResolveUnknownTypes(fromType, toType);

  if not LeafWritable(FToTree, ToPath) then
  begin
    SetError(Format('Blocked: %s is read-only -- not a valid assignment target.', [ToPath]));
    Exit;
  end;

  if not CanCast(fromType, toType) then
  begin
    SetError(Format('Blocked: cannot map %s (%s) to %s (%s) -- no known cast.',
      [FromPath, fromType, ToPath, toType]));
    Exit;
  end;

  AssignLink(FromPath, ToPath, fromType, toType);
  { toType is the RESOLVED type (ResolveUnknownTypes may have inferred it from the
    From side), so this cell can show a type where a bare FToTree lookup would not. }
  FGrid.Cells[1, row] := PropCellText(ToPath, toType);
  FGrid.Cells[2, row] := FindLinkForFrom(FromPath).Cast;
  RefreshPool;
  SyncRawFromModel;
  RefreshRulesList;
  // RefreshPool consumed the highlighted leaf, so FPool.ItemIndex is now -1 -- but
  // rebuilding the list does NOT fire FPool.OnClick, so nothing else re-gates and
  // "<- Assign" would stay enabled over a selection that no longer exists.
  UpdateToolbarEnabled;
  SetStatus(Format('Assigned %s <- %s%s', [ToPath, FromPath,
    IfThen(FindLinkForFrom(FromPath).Cast <> '', ' : ' + FindLinkForFrom(FromPath).Cast, '')]));
end;

{ Auto-Match: for every UNassigned From leaf, if exactly ONE unassigned To leaf
  matches by leaf-name (case-insensitive) AND is castable, create the #link. Skips
  ambiguous names (more than one candidate) so the user resolves those by hand. }
procedure TConvRulesForm.DoAutoMatch(Sender: TObject);
var
  fromLeaf, toLeaf: TPropLeaf;
  fromName, toName: string;
  candidate: TPropLeaf;
  nCand, nMatched: Integer;
  assignedTo: TDictionary<string, Boolean>;
  toNameCount: TDictionary<string, Integer>;
  cnt: Integer;
  L: TRuleNode;
  matchType: string;
  conds: TArray<TConditionalFrom>;

  function LeafName(const APath: string): string;
  begin
    Result := APath;
    if LastDelimiter('.', Result) > 0 then
      Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;

begin
  var LGuard: IInterface := HourGlass;
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  nMatched := 0;
  conds := ActiveConditionals;
  assignedTo := TDictionary<string, Boolean>.Create;
  toNameCount := TDictionary<string, Integer>.Create;
  try
    for L in ActiveLinks do
      if L.LinkTo <> '' then assignedTo.AddOrSetValue(LowerCase(L.LinkTo), True);
    // Count each To leaf's LAST-SEGMENT name across the WHOLE tree (global
    // uniqueness). A last-segment auto-match is only safe when the name is unique;
    // otherwise the greedy assigned-pool depletion below pairs infrastructure-noise
    // leaves (dozens of '.Components', '.Owner', ...) arbitrarily.
    for toLeaf in FToTree.Leaves do
    begin
      if not toLeaf.IsWritable then Continue;   // read-only leaves are never targets
      toName := LowerCase(LeafName(toLeaf.Path));
      if toNameCount.TryGetValue(toName, cnt) then toNameCount[toName] := cnt + 1
      else toNameCount.Add(toName, 1);
    end;

    for fromLeaf in FFromTree.Leaves do
    begin
      // skip From leaves already mapped
      if FindLinkForFrom(fromLeaf.Path) <> nil then Continue;
      // A leaf an applied #mapping decides conditionally is mapped too, just not by a
      // #link. Auto-matching one on top would add a second, UNCONDITIONAL answer for
      // the same source property -- the two rules would then both claim it.
      if ConditionalCasesOf(conds, fromLeaf.Path) > 0 then Continue;
      fromName := LowerCase(LeafName(fromLeaf.Path));

      // PASS 1 -- an EXACT full-path match (From.path == To.path) is unambiguous
      // even when the leaf NAME repeats in nested sub-objects. This is what makes
      // top-level AllowAllUp/Down/ShowHint auto-pick: TcxButton has 14 leaves whose
      // last segment is "AllowAllUp" (Colors.Button.AllowAllUp, ...), but only ONE
      // whose full path is exactly "AllowAllUp".
      nCand := 0; candidate := Default(TPropLeaf); matchType := '';
      for toLeaf in FToTree.Leaves do
      begin
        if not toLeaf.IsWritable then Continue;
        if assignedTo.ContainsKey(LowerCase(toLeaf.Path)) then Continue;
        if not SameText(toLeaf.Path, fromLeaf.Path) then Continue;
        var fT: string := fromLeaf.TypeName;
        var tT: string := toLeaf.TypeName;
        ResolveUnknownTypes(fT, tT);
        if CanCast(fT, tT) then
        begin
          Inc(nCand);
          candidate := toLeaf;
        end;
      end;

      // PASS 2 -- only when no exact-path match exists, fall back to matching by the
      // LAST path segment, still requiring a UNIQUE castable candidate.
      // PASS 2 fires ONLY when the From name is GLOBALLY UNIQUE among To
      // last-segments -- an ambiguous name (noise) is never auto-paired.
      if (nCand = 0) and toNameCount.TryGetValue(fromName, cnt) and (cnt = 1) then
        for toLeaf in FToTree.Leaves do
        begin
          if not toLeaf.IsWritable then Continue;
          if assignedTo.ContainsKey(LowerCase(toLeaf.Path)) then Continue;
          toName := LowerCase(LeafName(toLeaf.Path));
          if fromName <> toName then Continue;
          var fT: string := fromLeaf.TypeName;
          var tT: string := toLeaf.TypeName;
          ResolveUnknownTypes(fT, tT);
          if CanCast(fT, tT) then
          begin
            Inc(nCand);
            candidate := toLeaf;
          end;
        end;

      if nCand = 1 then
      begin
        var fT: string := fromLeaf.TypeName;
        var tT: string := candidate.TypeName;
        ResolveUnknownTypes(fT, tT);
        AssignLink(fromLeaf.Path, candidate.Path, fT, tT);
        assignedTo.AddOrSetValue(LowerCase(candidate.Path), True);
        Inc(nMatched);
      end;
    end;
  finally
    assignedTo.Free;
    toNameCount.Free;
  end;

  // reload the grid to reflect the new assignments
  LoadGridForBlock(FActiveHdr);
  SyncRawFromModel;
  RefreshRulesList;
  SetStatus(Format('Auto-Match: %d unambiguous assignment(s) created.', [nMatched]));
end;

{ New Conversion: read From/To from the pickers, verify both resolve to indexed
  classes, append a fresh #convert block, load it (populates the grid + To pool),
  then run Auto-Match so the obvious mappings are pre-filled. }
procedure TConvRulesForm.DoNewConversion(Sender: TObject);
var
  fromT, toT: string;
  tree: TProptree;
  err : string;
  fromNote, toNote, notes: string;
  hdr : TRuleNode;
  newHdrIdx: Integer;
begin
  var LGuard: IInterface := HourGlass;
  fromT := Trim(FCbFrom.Text);
  toT   := Trim(FCbTo.Text);
  if (fromT = '') or (toT = '') then
  begin
    SetError('Pick (or type) both a From and a To class in the top pickers.');
    Exit;
  end;

  SetStatus(Format('Resolving %s and %s ...', [fromT, toT]));
  Application.ProcessMessages;
  tree := Default(TProptree);
  if not FEngine.GetProptree(fromT, tree, err, fromNote) or (Length(tree.Leaves) = 0) then
  begin
    SetError(Format('From class "%s" is not indexed (no properties found). %s', [fromT, err]));
    Exit;
  end;
  if not FEngine.GetProptree(toT, tree, err, toNote) or (Length(tree.Leaves) = 0) then
  begin
    SetError(Format('To class "%s" is not indexed (no properties found). %s', [toT, err]));
    Exit;
  end;

  // If the SELECTED rule is a From-only stub whose From matches the picker, SET
  // ITS To in place (the "assign a To to a Fill From-classes row" flow) instead of
  // creating a duplicate. Otherwise append a fresh #convert block.
  if (FActiveHdr >= 0) and (FActiveHdr < FBook.Nodes.Count)
     and (FBook.Nodes[FActiveHdr].Kind = rnkConvert)
     and (Trim(FBook.Nodes[FActiveHdr].ToType) = '')
     and SameText(Trim(FBook.Nodes[FActiveHdr].FromType), fromT) then
  begin
    FBook.Nodes[FActiveHdr].ToType := toT;
    FBook.Nodes[FActiveHdr].Dirty := True;
    newHdrIdx := FActiveHdr;
  end
  else
  begin
    // append a blank line + a new #convert header at the end of the model
    if FBook.Nodes.Count > 0 then
    begin
      var Blank: TRuleNode := TRuleNode.Create; Blank.Kind := rnkBlank; Blank.Raw := '';
      FBook.Add(Blank);
    end;
    hdr := TRuleNode.Create;
    hdr.Kind := rnkConvert;
    hdr.FromType := fromT;
    hdr.ToType := toT;
    hdr.Dirty := True;
    FBook.Add(hdr);
    newHdrIdx := FBook.Nodes.Count - 1;
  end;

  RefreshRulesList;
  // select the target rule (also fires LoadGridForBlock)
  var sel: Integer := -1;
  for var k := 0 to FRules.Items.Count - 1 do
    if Integer(FRules.Items[k].Data) = newHdrIdx then begin sel := k; Break; end;
  if sel >= 0 then
  begin
    FRules.ItemIndex := sel;
    FRules.Items[sel].Selected := True;
  end
  else
    LoadGridForBlock(newHdrIdx);

  // pre-fill the obvious matches
  DoAutoMatch(nil);
  SyncRawFromModel;
  // This is where a bare class name typed into a picker is first resolved, so it is
  // also where an FMX-vs-VCL tie has to be said out loud -- the tree behind every
  // auto-match just made may belong to the other framework.
  notes := '';
  if fromNote <> '' then notes := notes + '  ' + fromNote;
  if toNote   <> '' then notes := notes + '  ' + toNote;
  SetStatus(Format('Conversion %s -> %s set and auto-matched. Review, then Save.',
    [fromT, toT]) + notes);
end;

procedure TConvRulesForm.DoUnassign(Sender: TObject);
var
  row: Integer;
  FromPath: string;
  Link: TRuleNode;
begin
  if FActiveHdr < 0 then Exit;
  row := FGrid.Row;
  if row < 1 then Exit;
  FromPath := PathOfGridCell(FGrid.Cells[0, row]);
  Link := FindLinkForFrom(FromPath);
  if Link = nil then begin SetStatus('That From row has no assignment.'); Exit; end;
  // remove the link node from the model
  FBook.Nodes.Remove(Link);
  FGrid.Cells[1, row] := '';
  FGrid.Cells[2, row] := '';
  RefreshPool;
  SyncRawFromModel;
  RefreshRulesList;
  UpdateToolbarEnabled;   // same reason as DoAssign: the pool list was rebuilt
  SetStatus('Unassigned ' + FromPath);
end;

procedure TConvRulesForm.SyncRawFromModel;
begin
  FRaw.Lines.Text := FBook.SaveToString;
end;

procedure TConvRulesForm.DoValidate(Sender: TObject);
var
  res: TValidateResult;
  Node: TRuleNode;
  fromT, toT: string;
begin
  var LGuard: IInterface := HourGlass;
  if FFilePath = '' then begin SetStatus('Load a file first.'); Exit; end;
  fromT := ''; toT := '';
  if FActiveHdr >= 0 then
  begin
    Node := FBook.Nodes[FActiveHdr];
    fromT := Node.FromType; toT := Node.ToType;
  end;
  res := FEngine.ValidateText(FBook.SaveToString, fromT, toT);
  if res.OK then SetStatus('Validate: OK')
  else SetStatus('Validate: ' + res.FirstError);
end;

{ Open the curation window on the file currently loaded here. Curation moves
  VERBATIM block text and deliberately does NOT go through this form's canonical
  re-emitter, so a block that was merely moved stays byte-identical. It works on
  the file ON DISK, so unsaved edits here are invisible to it: Yes = save first,
  No = curate the on-disk version anyway, Cancel = out. }
procedure TConvRulesForm.DoCurate(Sender: TObject);
var
  Reload: string;
begin
  if (FFilePath <> '') and (FBook.Nodes.Count > 0) then
    case MessageDlg('Curation works on the file on disk. Save your edits first?',
           mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrCancel: Exit;
      mrYes   :
        // The user asked to save FIRST. If that failed, opening curation anyway
        // would curate the STALE disk file and the reload afterwards would throw
        // the unsaved edits away -- so stop here instead. DoSave has already put
        // the reason on the status bar; do not overwrite it.
        if not DoSave(nil) then
        begin
          SetError('Curation not opened: the save failed, so your edits are still '
            + 'only in this editor and nothing on disk changed.');
          Exit;
        end;
    end;

  Reload := TCurationForm.Execute(Self, FFilePath);
  if Reload <> '' then
  begin
    LoadFile(Reload);
    SetStatus('Reloaded ' + ExtractFileName(Reload) + ' after curation.');
  end;
end;

procedure TConvRulesForm.DoSaveClick(Sender: TObject);
begin
  DoSave(Sender);
end;

function TConvRulesForm.DoSave(Sender: TObject): Boolean;
var
  bak: string;
  res: TValidateResult;
  Node: TRuleNode;
  fromT, toT: string;
begin
  Result := False;   // every early Exit below means nothing reached disk
  var LGuard: IInterface := HourGlass;
  if FFilePath = '' then
  begin
    var Dlg: TSaveDialog := TSaveDialog.Create(Self);
    try
      Dlg.Filter := 'Conversion rules (*.rules)|*.rules';
      Dlg.DefaultExt := 'rules';
      if not Dlg.Execute then Exit;
      FFilePath := Dlg.FileName;
      FLblFile.Caption := FFilePath;
    finally Dlg.Free; end;
  end;

  // 1) backup existing
  if TFile.Exists(FFilePath) then
  begin
    bak := BackupPath(FFilePath);
    try TFile.Copy(FFilePath, bak); except on E: Exception do
      begin SetStatus('Backup failed: ' + E.Message); Exit; end; end;
  end;

  // 2) write canonical DSL (ASCII/CRLF) -- only COMPLETE rules (a #convert block
  //    with at least one #link). A From/To pair with nothing mapped yet is scratch
  //    and is not persisted.
  var dropped: Integer;
  var outText: string := FBook.SaveCompleteToString(dropped);
  TFile.WriteAllText(FFilePath, outText, TEncoding.ASCII);

  // 3) validate the saved file
  fromT := ''; toT := '';
  if FActiveHdr >= 0 then
  begin
    Node := FBook.Nodes[FActiveHdr];
    fromT := Node.FromType; toT := Node.ToType;
  end;
  res := FEngine.ValidateText(outText, fromT, toT);
  var droppedMsg: string := '';
  if dropped > 0 then
    droppedMsg := Format(' (%d empty rule(s) not saved)', [dropped]);
  if res.OK then
    SetStatus(Format('Saved %s (backup %s)%s. Validate: OK',
      [ExtractFileName(FFilePath), ExtractFileName(bak), droppedMsg]))
  else
    SetStatus(Format('Saved %s (backup %s)%s. Validate: %s',
      [ExtractFileName(FFilePath), ExtractFileName(bak), droppedMsg, res.FirstError]));

  // Surface unit-rule conflicts (ADD wins) after every save, non-blocking.
  RefreshUnitList;
  var us: TUnitSets := NormalizeUnitSets(FBook);
  if Length(us.Conflicts) > 0 then
    SetError(Format('Note: unit conflicts (ADD wins): %s',
      [string.Join(', ', us.Conflicts)]));

  Result := True;   // the file IS on disk; a failed validation is a report, not a failure
end;

{ ---- Unit Rules tab ---- }

procedure TConvRulesForm.InsertUnitNode(ANode: TRuleNode);
var
  Heads: TArray<Integer>;
begin
  // Unit directives live in the top file-level section (before the first #convert)
  // so SaveCompleteToString always preserves them -- a trailing incomplete #convert
  // block would otherwise swallow nodes appended at EOF.
  Heads := FBook.ConvertHeaders;
  if Length(Heads) = 0 then FBook.Add(ANode)
  else FBook.Nodes.Insert(Heads[0], ANode);
end;

{ The list shows the rule book's unit directives first, then -- underneath them -- the
  units Examine harvested that STILL have no rule of their own (Item.Data = nil marks a
  candidate). Candidates are re-filtered on every refresh rather than pruned once, so
  authoring a #use/#unuse/#useswap for one silently retires its candidate row, and one
  source unit can fan out to several replacements through the existing #useswap. }
procedure TConvRulesForm.RefreshUnitList;
var
  N   : TRuleNode;
  Item: TListItem;
  S   : TUnitSets;
  Cand: string;

  function InConflict(const AUnit: string): Boolean;
  var c: string;
  begin
    Result := False;
    if AUnit = '' then Exit;
    for c in S.Conflicts do
      if SameText(c, AUnit) then Exit(True);
  end;

  { Does a unit directive already speak about AUnit? SwapOld, not SwapNew: a #useswap's
    new units are replacements the legacy form would not itself have used. }
  function HasRuleFor(const AUnit: string): Boolean;
  var n: TRuleNode;
  begin
    Result := True;
    for n in FBook.UnitNodes do
      case n.Kind of
        rnkUse    : if SameText(n.UseUnit,   AUnit) then Exit;
        rnkUnuse  : if SameText(n.UnuseUnit, AUnit) then Exit;
        rnkUseSwap: if SameText(n.SwapOld,   AUnit) then Exit;
      end;
    Result := False;
  end;

begin
  if FUnitList = nil then Exit;
  S := NormalizeUnitSets(FBook);
  FUnitList.Items.BeginUpdate;
  try
    FUnitList.Items.Clear;
    for N in FBook.UnitNodes do
    begin
      Item := FUnitList.Items.Add;
      case N.Kind of
        rnkUse:
          begin
            Item.Caption := '#use';
            Item.SubItems.Add('');
            Item.SubItems.Add(N.UseUnit);
            Item.SubItems.Add(IfThen(InConflict(N.UseUnit), '(!) ADD wins', ''));
          end;
        rnkUnuse:
          begin
            Item.Caption := '#unuse';
            Item.SubItems.Add(N.UnuseUnit);
            Item.SubItems.Add('');
            Item.SubItems.Add(IfThen(InConflict(N.UnuseUnit), '(!) also added', ''));
          end;
        rnkUseSwap:
          begin
            Item.Caption := '#useswap';
            Item.SubItems.Add(N.SwapOld);
            Item.SubItems.Add(string.Join(', ', N.SwapNew));
            Item.SubItems.Add(IfThen(InConflict(N.SwapOld), '(!) also added', ''));
          end;
      end;
      Item.Data := Pointer(N);
    end;

    for Cand in FUnitCandidates do
      if not HasRuleFor(Cand) then
      begin
        Item := FUnitList.Items.Add;
        Item.Caption := '(candidate)';
        Item.SubItems.Add(Cand);
        Item.SubItems.Add('');
        Item.SubItems.Add('from Examine');
        Item.Data := nil;   // NOT a rule -- see DoDeleteUnit
      end;
  finally
    FUnitList.Items.EndUpdate;
  end;
end;

procedure TConvRulesForm.DoAddSwap(Sender: TObject);
var
  oldU, newU: string;
  N    : TRuleNode;
  parts: TArray<string>;
  tmp  : TList<string>;
  p    : string;
begin
  oldU := '';
  if not InputQuery('Add unit swap', 'Old unit to replace:', oldU) then Exit;
  oldU := Trim(oldU);
  if oldU = '' then Exit;
  newU := '';
  if not InputQuery('Add unit swap', 'New unit(s), comma-separated:', newU) then Exit;
  N := TRuleNode.Create;
  N.Kind := rnkUseSwap;
  N.SwapOld := oldU;
  N.Dirty := True;
  parts := newU.Split([',']);
  tmp := TList<string>.Create;
  try
    for p in parts do
      if Trim(p) <> '' then tmp.Add(Trim(p));
    N.SwapNew := tmp.ToArray;
  finally
    tmp.Free;
  end;
  InsertUnitNode(N);
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus(Format('Added #useswap %s -> %s', [oldU, string.Join(', ', N.SwapNew)]));
end;

procedure TConvRulesForm.DoAddUse(Sender: TObject);
var
  u: string;
  N: TRuleNode;
begin
  u := '';
  if not InputQuery('Add unit', 'Unit to ADD to the uses clause:', u) then Exit;
  u := Trim(u);
  if u = '' then Exit;
  N := TRuleNode.Create; N.Kind := rnkUse; N.UseUnit := u; N.Dirty := True;
  InsertUnitNode(N);
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus('Added #use ' + u);
end;

procedure TConvRulesForm.DoAddUnuse(Sender: TObject);
var
  u: string;
  N: TRuleNode;
begin
  u := '';
  if not InputQuery('Remove unit', 'Unit to REMOVE from the uses clause:', u) then Exit;
  u := Trim(u);
  if u = '' then Exit;
  N := TRuleNode.Create; N.Kind := rnkUnuse; N.UnuseUnit := u; N.Dirty := True;
  InsertUnitNode(N);
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus('Added #unuse ' + u);
end;

procedure TConvRulesForm.DoDeleteUnit(Sender: TObject);
var
  N   : TRuleNode;
  Cand: string;
  Kept: TArray<string>;
  U   : string;
begin
  if FUnitList.Selected = nil then
  begin
    SetStatus('Select a unit rule to delete.');
    Exit;
  end;
  N := TRuleNode(FUnitList.Selected.Data);

  // Data = nil is an Examine CANDIDATE, not a rule: dismissing it drops it from the
  // harvested set only. The rule book is untouched, so no SyncRawFromModel either.
  if N = nil then
  begin
    Cand := FUnitList.Selected.SubItems[0];
    Kept := nil;
    for U in FUnitCandidates do
      if not SameText(U, Cand) then Kept := Kept + [U];
    FUnitCandidates := Kept;
    RefreshUnitList;
    UpdateToolbarEnabled;
    SetStatus('Dismissed candidate unit ' + Cand + '.');
    Exit;
  end;

  FBook.Nodes.Remove(N); // TObjectList owns its items -> frees N
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus('Deleted unit rule.');
end;

procedure TConvRulesForm.DoDeriveUnits(Sender: TObject);
var
  Pairs   : TArray<TConvPair>;
  Heads   : TArray<Integer>;
  S       : TUnitSets;
  existing: TArray<TRuleNode>;
  addUse, addUnuse, i: Integer;
  u: string;
  N: TRuleNode;

  function HasUse(const uu: string): Boolean;
  var n: TRuleNode;
  begin
    Result := False;
    for n in existing do
      if (n.Kind = rnkUse) and SameText(n.UseUnit, uu) then Exit(True);
  end;

  function HasUnuse(const uu: string): Boolean;
  var n: TRuleNode;
  begin
    Result := False;
    for n in existing do
      if (n.Kind = rnkUnuse) and SameText(n.UnuseUnit, uu) then Exit(True);
  end;

begin
  var LGuard: IInterface := HourGlass;
  Heads := FBook.ConvertHeaders;
  if Length(Heads) = 0 then
  begin
    SetStatus('No #convert rules to derive units from.');
    Exit;
  end;
  SetLength(Pairs, Length(Heads));
  for i := 0 to High(Heads) do
  begin
    Pairs[i].FromType := FBook.Nodes[Heads[i]].FromType;
    Pairs[i].ToType   := FBook.Nodes[Heads[i]].ToType;
  end;
  SetStatus('Deriving units (resolving declaring units)...');
  S := DeriveUnits(Pairs,
    function(const t: string): string
    begin
      Result := FEngine.DeclaringUnitOf(t);
    end);
  existing := FBook.UnitNodes;
  addUse := 0; addUnuse := 0;
  for u in S.Adds do
    if not HasUse(u) then
    begin
      N := TRuleNode.Create; N.Kind := rnkUse; N.UseUnit := u; N.Dirty := True;
      InsertUnitNode(N); Inc(addUse);
    end;
  for u in S.Removes do
    if not HasUnuse(u) then
    begin
      N := TRuleNode.Create; N.Kind := rnkUnuse; N.UnuseUnit := u; N.Dirty := True;
      InsertUnitNode(N); Inc(addUnuse);
    end;
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus(Format('Derived: +%d #use, +%d #unuse (deduped against existing).',
    [addUse, addUnuse]));
end;

procedure TConvRulesForm.DoCheckUnits(Sender: TObject);
var
  S: TUnitSets;
begin
  S := NormalizeUnitSets(FBook);
  RefreshUnitList;
  if Length(S.Conflicts) > 0 then
    SetError(Format('Unit conflicts (ADD wins): %s', [string.Join(', ', S.Conflicts)]))
  else
    SetStatus(Format('Units OK: %d add, %d remove, no doubles.',
      [Length(S.Adds), Length(S.Removes)]));
end;

procedure TConvRulesForm.RulesFilterChange(Sender: TObject);
begin
  RefreshRulesList;
end;

end.
