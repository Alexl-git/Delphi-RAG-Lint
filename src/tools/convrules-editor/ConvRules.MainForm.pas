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
  Vcl.ExtCtrls, Vcl.Grids, Vcl.Dialogs, Vcl.Menus, Vcl.Graphics,
  ConvRules.Model, ConvRules.Casts, ConvRules.Engine, ConvRules.Platform, ConvRules.CastLib;

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

    // toolbar
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
    FPool     : TListBox;             // unassigned T pool
    FPoolFind : TEdit;
    FBtnAssign: TButton;
    FBtnUnasgn: TButton;
    FBtnAuto  : TButton;
    FBtnFindFrom: TButton;            // pool: select the From-grid row of the same name
    FBtnOnlyType: TButton;            // pool: toggle filter to the highlighted leaf's type
    FPoolTypeFilter: string;          // active pool type-narrowing ('' = off)
    // directives / raw
    FTabs     : TPageControl;
    FRaw      : TMemo;
    // unit rules tab + rules-library filter
    FUnitList   : TListView;
    FRulesFilter: TEdit;

    procedure BuildUI;
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
    procedure RefreshPool;
    procedure DoAssign(Sender: TObject);
    procedure DoUnassign(Sender: TObject);
    procedure PoolFilter(Sender: TObject);
    procedure DoFindInFrom(Sender: TObject);
    procedure DoOnlyType(Sender: TObject);
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
  { Defaults come from ConvRules.Platform so the .dpr and this unit cannot drift
    apart; the .dpr overwrites both from --from-platform / --to-platform, which
    still accept win32|win64|both. FROM was cpBoth until 2026-07-29 -- see
    DEFAULT_FROM_PLATFORM for the measurements behind the change. }
  GEditorFromPlatform: TConvPlatform = DEFAULT_FROM_PLATFORM;
  GEditorToPlatform: TConvPlatform = DEFAULT_TO_PLATFORM;

implementation

uses
  System.StrUtils, System.Math, ConvRules.Units, ConvRules.WorkingSet,
  ConvRules.CurationForm;

{ ---- helpers ---- }

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
  OnClose := FormCloseHandler;
  Visible := True;  // ensure the CreateNew form is shown by Run
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
  inherited;
end;

procedure TConvRulesForm.BuildUI;
var
  Split1: TSplitter;
  Split2: TSplitter;
  LeftPanel, GridPanel, PoolPanel: TPanel;
  TabRules, TabRaw, TabUnits: TTabSheet;
  BtnLoad, BtnSave, BtnValidate: TButton;
begin
  Caption := 'ConvRulesEditor -- conversion rule-book editor';
  Width := 1600; Height := 720;
  Position := poScreenCenter;

  // --- bottom status bar (created first so it reserves the bottom edge; the top
  //     status label stays too, but this makes the current message visible even
  //     when the window is short and the top toolbar scrolls off) ---
  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.SimplePanel := True;
  FStatusBar.SimpleText := 'Ready.';

  // --- top toolbar: file actions / class builder / project-unit helper / path ---
  FPanelTop := TPanel.Create(Self);
  FPanelTop.Parent := Self; FPanelTop.Align := alTop; FPanelTop.Height := 122;
  FPanelTop.BevelOuter := bvNone;

  BtnLoad := TButton.Create(Self);
  BtnLoad.Parent := FPanelTop; BtnLoad.SetBounds(8, 6, 90, 25);
  BtnLoad.Caption := 'Open...'; BtnLoad.OnClick := DoLoad;

  BtnSave := TButton.Create(Self);
  BtnSave.Parent := FPanelTop; BtnSave.SetBounds(104, 6, 90, 25);
  BtnSave.Caption := 'Save'; BtnSave.OnClick := DoSaveClick;

  BtnValidate := TButton.Create(Self);
  BtnValidate.Parent := FPanelTop; BtnValidate.SetBounds(200, 6, 90, 25);
  BtnValidate.Caption := 'Validate'; BtnValidate.OnClick := DoValidate;

  var BtnCurate: TButton := TButton.Create(Self);
  BtnCurate.Parent := FPanelTop; BtnCurate.SetBounds(296, 6, 90, 25);
  BtnCurate.Caption := 'Curate...';
  BtnCurate.Hint := 'Split / copy / delete / merge blocks across several rule-books, '
    + 'or compose them into one file for the engine';
  BtnCurate.ShowHint := True;
  BtnCurate.OnClick := DoCurate;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := FPanelTop; FLblStatus.SetBounds(392, 11, 688, 15);

  // --- row 1: From Unit [v]  [Fill From-classes] -- pick a unit first, then its
  //     component classes drop into the rules library as From-only conversions ---
  var LblUnit: TLabel := TLabel.Create(Self);
  LblUnit.Parent := FPanelTop; LblUnit.SetBounds(8, 42, 58, 15); LblUnit.Caption := 'From Unit:';
  FCbUnit := TComboBox.Create(Self);
  FCbUnit.Parent := FPanelTop; FCbUnit.SetBounds(68, 39, 276, 23);
  FCbUnit.AutoComplete := True; FCbUnit.DropDownCount := 24;
  FCbUnit.Hint := 'Pick a project unit to add a From-only conversion per component class on its form (optional)';
  FCbUnit.ShowHint := True; FCbUnit.OnDropDown := CbLoadUnits;

  var BtnFillUnit: TButton := TButton.Create(Self);
  BtnFillUnit.Parent := FPanelTop; BtnFillUnit.SetBounds(350, 38, 150, 25);
  BtnFillUnit.Caption := 'Fill From-classes'; BtnFillUnit.OnClick := DoLoadUnit;

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

  var BtnNew: TButton := TButton.Create(Self);
  BtnNew.Parent := FPanelTop; BtnNew.SetBounds(706, 70, 130, 25);
  BtnNew.Caption := '+ New Conversion'; BtnNew.OnClick := DoNewConversion;

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
  var UPanel: TPanel := TPanel.Create(Self);
  UPanel.Parent := TabUnits; UPanel.Align := alTop; UPanel.Height := 64;
  UPanel.BevelOuter := bvNone;
  var BSwap: TButton := TButton.Create(Self);
  BSwap.Parent := UPanel; BSwap.SetBounds(6, 6, 104, 25);
  BSwap.Caption := '+ Swap'; BSwap.OnClick := DoAddSwap;
  BSwap.Hint := 'Add #useswap Old -> New1[, New2 ...]'; BSwap.ShowHint := True;
  var BUse: TButton := TButton.Create(Self);
  BUse.Parent := UPanel; BUse.SetBounds(114, 6, 104, 25);
  BUse.Caption := '+ Add unit'; BUse.OnClick := DoAddUse;
  var BUnuse: TButton := TButton.Create(Self);
  BUnuse.Parent := UPanel; BUnuse.SetBounds(222, 6, 110, 25);
  BUnuse.Caption := '+ Remove unit'; BUnuse.OnClick := DoAddUnuse;
  var BDel: TButton := TButton.Create(Self);
  BDel.Parent := UPanel; BDel.SetBounds(6, 34, 104, 25);
  BDel.Caption := 'Delete'; BDel.OnClick := DoDeleteUnit;
  var BDerive: TButton := TButton.Create(Self);
  BDerive.Parent := UPanel; BDerive.SetBounds(114, 34, 104, 25);
  BDerive.Caption := 'Derive units'; BDerive.OnClick := DoDeriveUnits;
  BDerive.Hint := 'Add #use/#unuse from every #convert To/From type (deduped)';
  BDerive.ShowHint := True;
  var BCheck: TButton := TButton.Create(Self);
  BCheck.Parent := UPanel; BCheck.SetBounds(222, 34, 110, 25);
  BCheck.Caption := 'Check units'; BCheck.OnClick := DoCheckUnits;
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

  FBtnAuto := TButton.Create(Self);
  FBtnAuto.Parent := PoolPanel; FBtnAuto.SetBounds(6, 6, 388, 27);
  FBtnAuto.Caption := 'Auto-Match unambiguous properties';
  FBtnAuto.Anchors := [akLeft, akTop, akRight];
  FBtnAuto.OnClick := DoAutoMatch;

  var LblPool: TLabel := TLabel.Create(Self);
  LblPool.Parent := PoolPanel; LblPool.SetBounds(6, 40, 388, 15);
  LblPool.Caption := 'To (unassigned pool) -- search:';

  FPoolFind := TEdit.Create(Self);
  FPoolFind.Parent := PoolPanel; FPoolFind.SetBounds(6, 58, 388, 23);
  FPoolFind.Anchors := [akLeft, akTop, akRight];
  FPoolFind.OnChange := PoolFilter;

  // Pool helpers, acting on the HIGHLIGHTED pool leaf: align it to its same-named
  // From-grid row, or narrow the pool to a single type (a toggle).
  FBtnFindFrom := TButton.Create(Self);
  FBtnFindFrom.Parent := PoolPanel; FBtnFindFrom.SetBounds(6, 86, 190, 25);
  FBtnFindFrom.Caption := 'Find in From by name';
  FBtnFindFrom.Hint := 'Select the From-grid row whose property has the SAME name as the highlighted To leaf';
  FBtnFindFrom.ShowHint := True; FBtnFindFrom.Anchors := [akLeft, akTop];
  FBtnFindFrom.OnClick := DoFindInFrom;

  FBtnOnlyType := TButton.Create(Self);
  FBtnOnlyType.Parent := PoolPanel; FBtnOnlyType.SetBounds(202, 86, 192, 25);
  FBtnOnlyType.Caption := 'Only this type';
  FBtnOnlyType.Hint := 'Show only pool leaves whose TYPE matches the highlighted leaf (toggle)';
  FBtnOnlyType.ShowHint := True; FBtnOnlyType.Anchors := [akLeft, akTop, akRight];
  FBtnOnlyType.OnClick := DoOnlyType;

  FBtnAssign := TButton.Create(Self);
  FBtnAssign.Parent := PoolPanel; FBtnAssign.SetBounds(6, 116, 190, 25);
  FBtnAssign.Caption := '<- Assign to From'; FBtnAssign.OnClick := DoAssign;

  FBtnUnasgn := TButton.Create(Self);
  FBtnUnasgn.Parent := PoolPanel; FBtnUnasgn.SetBounds(202, 116, 192, 25);
  FBtnUnasgn.Caption := 'Unassign ->'; FBtnUnasgn.OnClick := DoUnassign;
  FBtnUnasgn.Anchors := [akLeft, akTop, akRight];

  FPool := TListBox.Create(Self);
  FPool.Parent := PoolPanel; FPool.SetBounds(6, 146, 388, 496);
  FPool.Anchors := [akLeft, akTop, akRight, akBottom];

  Split2 := TSplitter.Create(Self);
  Split2.Parent := Self; Split2.Align := alRight; Split2.Width := 4;

  GridPanel := TPanel.Create(Self);
  GridPanel.Parent := Self; GridPanel.Align := alClient; GridPanel.BevelOuter := bvNone;

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
end;

procedure TConvRulesForm.SetStatus(const S: string);
begin
  FLblStatus.Font.Color := clWindowText;
  FLblStatus.Font.Style := [];
  FLblStatus.Caption := S;
  if FStatusBar <> nil then FStatusBar.SimpleText := S;
end;

{ Show a message in RED bold -- for blocked assignments and errors. }
procedure TConvRulesForm.SetError(const S: string);
begin
  FLblStatus.Font.Color := clRed;
  FLblStatus.Font.Style := [fsBold];
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
  if total = 0 then Exit(0);
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
  Node: TRuleNode;
  Err : string;
  i   : Integer;
  Leaf: TPropLeaf;
  Link: TRuleNode;
begin
  var LGuard: IInterface := HourGlass;
  FActiveHdr := AHdrIdx;
  // A fresh block: drop any pool type-narrowing carried over from the last selection.
  FPoolTypeFilter := '';
  if FBtnOnlyType <> nil then FBtnOnlyType.Caption := 'Only this type';
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
  if not FEngine.GetProptree(Node.FromType, FFromTree, Err, FSurfaceMinVis) then
  begin
    SetStatus('From tree: ' + Err);
    FFromTree := Default(TProptree);
  end;
  if Trim(Node.ToType) = '' then
    FToTree := Default(TProptree)   // From-only rule: no To tree yet
  else if not FEngine.GetProptree(Node.ToType, FToTree, Err, FSurfaceMinVis) then
  begin
    SetStatus('To tree: ' + Err);
    FToTree := Default(TProptree);
  end;

  // column 1 = F leaves; column 2 = the To assigned to that F (from #link);
  // column 3 (cast) shows any cast on that link. RowCount must stay > FixedRows
  // (1), so a 0-leaf tree still needs at least 2 rows (header + one blank).
  FGrid.RowCount := Max(2, Length(FFromTree.Leaves) + 1);
  // clear any stale trailing cells from a previous, larger selection
  for i := 1 to FGrid.RowCount - 1 do
  begin
    FGrid.Cells[0, i] := ''; FGrid.Cells[1, i] := ''; FGrid.Cells[2, i] := '';
  end;
  for i := 0 to High(FFromTree.Leaves) do
  begin
    Leaf := FFromTree.Leaves[i];
    FGrid.Cells[0, i + 1] := Format('%s : %s', [Leaf.Path, Leaf.TypeName]);
    Link := FindLinkForFrom(Leaf.Path);
    if Link <> nil then
    begin
      FGrid.Cells[1, i + 1] := Link.LinkTo;
      FGrid.Cells[2, i + 1] := Link.Cast;
    end
    else
    begin
      FGrid.Cells[1, i + 1] := '';
      FGrid.Cells[2, i + 1] := '';
    end;
  end;

  RefreshPool;
  SetStatus(Format('%s -> %s : %d From leaves, %d To leaves.',
    [Node.FromType, Node.ToType, Length(FFromTree.Leaves), Length(FToTree.Leaves)]));
end;

procedure TConvRulesForm.RefreshPool;
var
  Assigned: TDictionary<string, Boolean>;
  Link: TRuleNode;
  Leaf: TPropLeaf;
  Filter: string;
begin
  // pool = T leaves not currently assigned to any From (via #link ToPath)
  Assigned := TDictionary<string, Boolean>.Create;
  try
    for Link in ActiveLinks do
      if Link.LinkTo <> '' then Assigned.AddOrSetValue(LowerCase(Link.LinkTo), True);

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
              var disp: string := Format('%s : %s', [Leaf.Path, Leaf.TypeName]);
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
    FBtnOnlyType.Caption := 'Only this type';
    RefreshPool;
    SetStatus('Pool type filter cleared.');
    Exit;
  end;
  if FPool.ItemIndex < 0 then
  begin SetStatus('Highlight a To leaf whose type to filter by.'); Exit; end;
  t := TypeOfCell(FPool.Items[FPool.ItemIndex]);
  if t = '' then begin SetStatus('That leaf has no resolved type to filter by.'); Exit; end;
  FPoolTypeFilter := t;
  FBtnOnlyType.Caption := 'Show all types';
  RefreshPool;
  SetStatus(Format('Pool narrowed to type "%s".', [t]));
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
  fromType, toType: string;
begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  if FPool.ItemIndex < 0 then begin SetStatus('Pick a To property from the pool (right) first.'); Exit; end;
  row := FGrid.Row;
  if row < 1 then begin SetStatus('Pick a From row in the grid (left) first.'); Exit; end;

  FromPath := PathOfGridCell(FGrid.Cells[0, row]);
  ToPath   := PathOfGridCell(FPool.Items[FPool.ItemIndex]);
  if (FromPath = '') or (ToPath = '') then Exit;

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
  FGrid.Cells[1, row] := ToPath;
  FGrid.Cells[2, row] := FindLinkForFrom(FromPath).Cast;
  RefreshPool;
  SyncRawFromModel;
  RefreshRulesList;
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
  if not FEngine.GetProptree(fromT, tree, err) or (Length(tree.Leaves) = 0) then
  begin
    SetError(Format('From class "%s" is not indexed (no properties found). %s', [fromT, err]));
    Exit;
  end;
  if not FEngine.GetProptree(toT, tree, err) or (Length(tree.Leaves) = 0) then
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
  SetStatus(Format('Conversion %s -> %s set and auto-matched. Review, then Save.',
    [fromT, toT]));
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

procedure TConvRulesForm.RefreshUnitList;
var
  N   : TRuleNode;
  Item: TListItem;
  S   : TUnitSets;

  function InConflict(const AUnit: string): Boolean;
  var c: string;
  begin
    Result := False;
    if AUnit = '' then Exit;
    for c in S.Conflicts do
      if SameText(c, AUnit) then Exit(True);
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
  N: TRuleNode;
begin
  if FUnitList.Selected = nil then
  begin
    SetStatus('Select a unit rule to delete.');
    Exit;
  end;
  N := TRuleNode(FUnitList.Selected.Data);
  if N = nil then Exit;
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
