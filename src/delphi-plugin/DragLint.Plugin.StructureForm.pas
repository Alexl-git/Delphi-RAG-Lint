unit DragLint.Plugin.StructureForm;

{ v0.30 Structure form: stay-on-top non-modal TForm with a TTreeView
  showing two roots per active editor file:
    "Diagnostics (N)"  -- from v0.29 TDragLintDiagnosticCache
    "Code Elements (M)"-- from TDragLintStructureCache (drag-lint surface)
  Refresh button re-reads both.
  Double-click on any node jumps the active editor to that line.

  Not a true docked form -- v0.31+ may revisit native docking.
  For v0.30 we register as a standalone fsStayOnTop TForm. }

interface

uses
  System.Classes
  , Vcl.Controls
  , Vcl.Forms
  ;

procedure ShowDragLintStructure;
procedure HideDragLintStructure;

{ v0.42: build the Structure UI embedded inside a host container (a tab of the
  drag-lint dock panel) rather than as a standalone stay-on-top window. The
  returned form is owned by AOwner; call RefreshEmbeddedStructure when its tab
  is activated to re-read the active editor file. }
function CreateEmbeddedStructure(AOwner: TComponent; AParent: TWinControl): TForm;
procedure RefreshEmbeddedStructure(AForm: TForm);
{ v0.46: cheap diagnostics-only refresh (no symbol re-shell). }
procedure RefreshEmbeddedStructureDiagnostics(AForm: TForm);
{ v0.48: scroll an embedded Structure form to its Diagnostics section if it has any. }
procedure ScrollEmbeddedStructureToDiagnostics(AForm: TForm);
{ v(session 73): select the embedded Structure form's Diagnostics row for ALine.
  Same shape as the two helpers above -- the caller holds the embedded form as a
  plain TForm and must not need TDragLintStructureForm in its uses clause.
  False when the form is not a Structure form or the line carries no finding. }
function SelectEmbeddedStructureDiagnosticForLine(AForm: TForm; ALine: Integer): Boolean;

var { v0.48: set True by a compile that just pushed findings; the dock watch timer
    consumes it to auto-scroll the Structure to the Diagnostics section (if any). }
  GScrollStructureToDiagPending: Boolean = False;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.RegularExpressions
  , System.IOUtils
  , System.JSON
  , System.Generics.Collections
  , System.Generics.Defaults
  , Vcl.ComCtrls
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Menus
  , Vcl.Clipbrd
  , Vcl.Dialogs { Task 5: ShowMessage for the no-index guard in ShowInButterflyClick }
  , System.UITypes { mtConfirmation / mbYes / mrYes for the multi-project rename confirmation }
  , Winapi.Windows
  , ToolsAPI
  , DragLint.Plugin.DiagnosticCache
  , DragLint.Plugin.Telemetry
  , { TEMP debug telemetry }
    DragLint.Plugin.StructureCache
  , DragLint.Plugin.UsagesForm
  , DragLint.Plugin.DbResolver
  , DragLint.Plugin.Settings
  , DragLint.Plugin.ExeResolver
  , Vcl.ImgList
  , { per-severity row icons; one asset shared with the editor gutter }
    DragLint.Plugin.SeverityGlyph
  , DragLint.Plugin.Editor { v0.88 AutoFix: RunAndCaptureStdout for the fix verbs }
  , { 2026-10-13: row order, nearest row, clipboard text, autofix summary }
    DragLint.Plugin.DiagList
  , { Fix all runs as a queued job -> status-bar progress }
    DragLint.Plugin.JobQueue
  , { SetDragLintNote: what the fix did }
    DragLint.Plugin.StatusBar
  , { EnqueueReindexThenRelint: Rescan this unit }
    DragLint.Plugin.SaveNotifier
  ;

{ ---- TStructureNodeData: stores line info in tree node.Data ---- }

type
  TStructureNodeData = class
    Line : Integer    ; { 1-based declaration line; 0 = no navigation }
    Name : string     ; { symbol name -- for Find Usages }
    QName: string     ; { qualified name -- for Go to Implementation }
    Kind : TSymbolKind; { so we only offer impl/usages on proc-likes }
    Code : string     ; { v0.88 AutoFix: rule-id on a diagnostic node ('' on symbol nodes) }
    DiagIndex: Integer; { index into FDiags on a diagnostic node; -1 on every other node }
    constructor Create;
  end;

  { ---- TDragLintStructureForm ---- }

type
  TDragLintStructureForm = class(TForm)
    private
      FTree       : TTreeView                  ;
      FBtnRefresh : TButton                    ;
      FBtnDiag    : TButton                    ; { v0.47: scroll to the top Diagnostics message }
      FLblFile    : TLabel                     ;
      FSearch     : TEdit                      ; { v0.42: on-the-fly filter }
      FRegex      : TCheckBox                  ; { v0.42: treat filter as regex }
      FCurrentFile: string                     ;
      FSyms       : TArray<TSymbolInfo>        ; { cached so filtering doesn't re-shell }
      FDiags      : TArray<TDragLintDiagnostic>;
      FPopup      : TPopupMenu                 ; { v0.43: right-click nav menu }
      { v0.88 AutoFix: right-click Fix menu state. }
      FItemFixIt      : TMenuItem   ; { 'Fix it' -- single fixable finding }
      FItemFixUnit    : TMenuItem   ; { 'Fix all in unit' -- Diagnostics root }
      FItemFixProject : TMenuItem   ; { 'Fix all in project' -- Diagnostics root }
      FItemDocIt      : TMenuItem   ; { v0.90 AutoDocument: 'Document it' -- symbol node with a qname }
      FItemDocUnit    : TMenuItem   ; { ADF T10 AutoDocument: 'Document unit' -- any node, active editor file }
      FItemDocProject : TMenuItem   ; { ADF T10 AutoDocument: 'Document project' -- any node, active .dproj }
      FItemEnumHelper : TMenuItem   ; { Task 8 enum-helper: 'Create helper class' -- skEnum/skEnumValue node, no existing helper }
      FItemAllow      : TMenuItem   ; { 'Allow this message' -- dl:ok review of a single finding }
      FRootDiag       : TTreeNode   ; { the current 'Diagnostics (N)' root, for node discrimination }
      FFixableRules   : TStringList ; { lower-case rule-ids with a registered fix; nil until first fetched }
      { fix_opt_in naming rules: 'Fix it' on ONE finding is the opt-in (the engine
        treats --fix-line + --fix-rule so); 'Fix all in unit' counts them when an
        index resolves and opts in with --fix-naming, always after a confirm }
      FOptInFixRules  : TStringList ;
      FItemCopySel    : TMenuItem   ; { 'Copy' -- the selected Diagnostics rows }
      FItemRescan     : TMenuItem   ; { 'Rescan this unit' -- reindex + re-lint now }
      { The last fix result for FActionNoteFile, shown on the Diagnostics root row. }
      FActionNote     : string      ;
      FActionNoteFile : string      ;
      procedure BtnRefreshClick(Sender: TObject);
      procedure BtnDiagClick   (Sender: TObject);
      procedure FormActivate   (Sender: TObject);
      procedure TreeDblClick   (Sender: TObject);
      procedure TreeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
      procedure FormDestroy  (Sender: TObject);
      procedure SearchChanged(Sender: TObject);
      procedure ClearNodeData;
      procedure RefreshForFile(const AFilePath: string);
      procedure BuildTree     (const AFilter  : string);
      function SymMatches(const ASym: TSymbolInfo; const AFilter: string): Boolean;
      function GetActiveFilePath: string                                          ;
      function SelectedNodeData: TStructureNodeData                               ;
      procedure NavigateToLine         (ALine : Integer);
      procedure GoToDeclarationClick   (Sender: TObject);
      procedure GoToImplementationClick(Sender: TObject);
      procedure FindUsagesClick        (Sender: TObject);
      procedure ShowInButterflyClick   (Sender: TObject); { Task 5: 'Show in Call Graph' -> butterfly tab }
      procedure CopyDiagnosticsClick   (Sender: TObject);
      { Copy only the selected Diagnostics rows (multi-select; Ctrl+C). }
      procedure CopySelectedDiagnosticsClick(Sender: TObject);
      procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      { Re-index the project and re-lint this unit on demand. }
      procedure RescanUnitClick        (Sender: TObject);
      function  SelectedDiagIndices: TArray<Integer>;
      { One queued autofix run: progress in the status bar, summary on done.
        AUsesUnit <> '' marks a uses-fix run about that unit (JSON summary). }
      procedure RunFixJob(const ATitle, ACmd: string; ATimeoutMs: Integer; const AUsesUnit: string = '');
      function  IsNamingFixRule(const ACode: string): Boolean;
      function  UnusedUnitOfNode(ANode: TTreeNode): string;
      { v0.88 AutoFix handlers + helpers. }
      procedure EnsureFixableRules;
      function  NodeIsDiagnosticsRoot(ANode: TTreeNode): Boolean;
      function  NodeIsFixableFinding (ANode: TTreeNode): Boolean;
      { 'Allow this message': record a dl:ok review of ONE finding on ONE line. }
      function  NodeIsAllowableFinding(ANode: TTreeNode): Boolean;
      procedure AllowClick             (Sender: TObject);
      procedure ReloadCurrentFileBuffer;
      procedure PopupPopup             (Sender: TObject);
      procedure FixItClick             (Sender: TObject);
      procedure FixAllInUnitClick      (Sender: TObject);
      procedure FixAllInProjectClick   (Sender: TObject);
      { v0.90 AutoDocument: 'Document it' handler + its enablement predicate. }
      function  NodeIsDocumentable     (ANode: TTreeNode): Boolean;
      procedure DocumentItClick        (Sender: TObject);
      { ADF T10 AutoDocument: 'Document unit' / 'Document project' -- act on the
        active editor file / active .dproj regardless of which node is clicked. }
      function  GetActiveProjectFilePath: string;
      procedure DocumentUnitClick      (Sender: TObject);
      procedure DocumentProjectClick   (Sender: TObject);
      { Task 8 enum-helper: 'Create helper class' handler + its enablement
        predicate + the enum-qname resolver shared by both. }
      function  EnumQNameForNode       (ANode: TTreeNode): string;
      function  NodeIsEnumHelperTarget (ANode: TTreeNode): Boolean;
      procedure CreateEnumHelperClick  (Sender: TObject);
    public
      constructor Create(AOwner: TComponent); override;
      procedure RefreshActive; { v0.42: re-read the active editor file }
      { v0.46: cheap re-read of just the diagnostics from the cache for the
      already-loaded file (no symbol re-shell) -- fixes "Diagnostics (0)" when
      the lint populates the cache AFTER the structure was last refreshed. }
      procedure RefreshDiagnosticsOnly;
      { v0.48: scroll the tree so the Diagnostics section is pinned to the top and
      the first message selected (shared by the 'Diag' button + the auto-jump). }
      procedure ScrollToDiagnostics;
      function HasDiagnostics: Boolean;

      /// <summary>Selects the Diagnostics row NEAREST to ALine and scrolls it
      /// into view, so the panel follows the caret through the file.</summary>
      /// <param name="ALine">1-based editor line the caret is on.</param>
      /// <returns>True when a row was selected; False when there are no rows.</returns>
      /// <remarks>Does NOT take focus and does NOT move the editor caret --
      /// this is the editor -> panel direction only, and the panel already
      /// navigates the editor on double-click, so moving the caret here would
      /// close a feedback loop (select row -> jump editor -> caret moves ->
      /// select row). Nearest, not exact (owner ask 2026-10-13): an exact-only
      /// match left nothing lit between findings. An exact line still wins
      /// (its first row); a tie between rows above and below picks the one
      /// ABOVE -- see DiagList.NearestDiagRow. Replaces a multi-row selection
      /// with the single nearest row.</remarks>
      function SelectDiagnosticForLine(ALine: Integer): Boolean;

      /// <summary>Shows ANote on the Diagnostics root row while AFile is the panel's file.</summary>
      /// <param name="AFile">The unit the note is about; ignored by a panel showing another file.</param>
      /// <param name="ANote">One line, e.g. the outcome of a fix.</param>
      /// <remarks>Main thread. The note stays until the panel switches to another
      /// file or the next note replaces it.</remarks>
      procedure ShowActionNote(const AFile, ANote: string);
  end;

const
  { the one rule 'Fix it' routes to uses-fix instead of `lint --fix` }
  CUnusedUnitRule = 'unused-unit-in-uses';

var
  GStructureForm: TDragLintStructureForm = nil;
  { Every live Structure panel (standalone and docked). A queued job's OnDone
    reaches a panel ONLY through this list, never through a captured Self, so a
    panel closed while the job ran is simply not in it. }
  GLiveStructureForms: TList<TDragLintStructureForm> = nil;

  { ---- helpers ---- }

function SeverityPrefix(ASev: TDragLintSeverity): string;
begin
  case ASev of
    dlsError  : Result:= '[E] ';
    dlsWarning: Result:= '[W] ';
    dlsHint   : Result:= '[H] ';
    dlsInfo   : Result:= '[I] ';
    else Result:= '    ';
  end;
end;

{ Which glyph class a Structure row belongs to.

  Lives HERE, not in DragLint.Plugin.SeverityGlyph, because the TSymbolKind in
  scope for this tree is DragLint.Plugin.StructureCaches -- a smaller enum
  than DRagLint.Core.Models and one that starts at skUnknown. A drawing unit
  must not have to pick between two models it does not own.

  TOTAL BY CONSTRUCTION: anything unmapped becomes kgOther, a neutral dot. The
  defect this replaces was an unmapped node keeping TTreeNodes default
  ImageIndex of 0 -- which, with the severity-only image list, was the ERROR
  glyph. Every root and every code element was badged as an error. }
function GlyphClassFor(AKind: TSymbolKind): TKindGlyph;
begin
  case AKind of
    skUnit                      : Result:= kgUnit;
    skClass                     : Result:= kgClass;
    skInterface                 : Result:= kgInterface;
    skRecord, skType            : Result:= kgRecord;
    skEnum, skEnumValue         : Result:= kgEnum;
    skProcedure, skFunction,
    skMethod, skConstructor,
    skDestructor                : Result:= kgRoutine;
    skProperty                  : Result:= kgProperty;
    skConstant                  : Result:= kgConst;
    skField, skVariable         : Result:= kgData;
    else                          Result:= kgOther;
  end; // case
end;

{ ONE rule for putting a glyph on a node.

  -1 is the VCL "no image" sentinel, and it is what must be used when the image
  list could not be built -- NOT 0, which is a real entry. Leaving the default 0
  in place is exactly the bug this replaces: every node that never assigned an
  index rendered the ERROR glyph, so the Diagnostics root, the Code Elements
  root and every symbol in the tree were badged as errors.

  Centralised rather than repeated at each of the four call sites, because the
  failure mode is a node someone forgot -- and a forgotten node does not look
  blank, it looks like a finding. }
procedure SetNodeGlyph(ANode: TTreeNode; AIndex: Integer);
begin
  if ANode = nil then Exit;
  if AIndex < 0 then AIndex:= -1;
  ANode.ImageIndex   := AIndex;
  ANode.SelectedIndex:= AIndex;
end;

function KindPrefix(AKind: TSymbolKind): string;
begin
  case AKind of
    skUnit       : Result:= '[unit] ';
    skClass      : Result:= '[cls]  ';
    skInterface  : Result:= '[intf] ';
    skRecord     : Result:= '[rec]  ';
    skEnum       : Result:= '[enum] ';
    skEnumValue  : Result:= '[val]  ';
    skProcedure  : Result:= '[proc] ';
    skFunction   : Result:= '[func] ';
    skMethod     : Result:= '[meth] ';
    skConstructor: Result:= '[ctor] ';
    skDestructor : Result:= '[dtor] ';
    skProperty   : Result:= '[prop] ';
    skField      : Result:= '[fld]  ';
    skConstant   : Result:= '[const]';
    skType       : Result:= '[type] ';
    skVariable   : Result:= '[var]  ';
    else Result:= '[?]    ';
  end; // case
end; // function

function ResolveExePath: string;
begin
  Result:= DragLintExe;
end;

procedure AddPopupItem(AMenu: TPopupMenu; const ACaption: string; AHandler: TNotifyEvent);
var
  Item: TMenuItem;
begin
  Item:= TMenuItem.Create(AMenu);
  Item.Caption:= ACaption;
  Item.OnClick:= AHandler;
  AMenu.Items.Add(Item);
end;

{ v0.43: scan a .pas on disk for the implementation-section body of
  <AClass>.<AMethod> (or a standalone proc when AClass is empty). Returns the
  1-based line, or 0 if not found. We read the file rather than the live buffer;
  the Structure already navigates by indexed line numbers, so this stays
  consistent and self-contained. }
function FindImplementationLine(const AFilePath, AClass, AMethod: string): Integer;
var
  Lines: TStringList;
  Re   : TRegEx     ;
  Pat  : string     ;
  i    : Integer    ;
begin
  Result:= 0;
  if (AMethod = '') or not TFile.Exists(AFilePath) then Exit;
  if AClass <> '' then Pat:= '^\s*(class\s+)?(procedure|function|constructor|destructor|operator)\s+' + TRegEx.Escape(AClass) + '\.' + TRegEx.Escape(AMethod) + '\b'
  else Pat:= '^\s*(procedure|function)\s+' + TRegEx.Escape(AMethod) + '\b';
  Re:= TRegEx.Create(Pat, [roIgnoreCase]);
  Lines:= TStringList.Create;
  try
    Lines.LoadFromFile(AFilePath);
    for i:= 0 to Lines.Count - 1 do
      if Re.IsMatch(Lines[i]) then Exit(i + 1);
  finally
    Lines.Free;
  end;
end; // function

var
  { The file the Structure form is currently showing, mirrored out of
    TDragLintStructureForm.FCurrentFile by RefreshForFile so the unit-level
    ResolveDbForFile can see it. }
  GStructureCurrentFile: string = '';

  { Memo for ResolveDbForFile: one engine round-trip per file, not per menu
    click. Nine call sites share this function and most fire from popup handlers,
    so an unmemoised spawn would be paid again for every Find Usages, Fix-all and
    Document-it on the same file. Invalidated by path, so switching files (or
    switching active project, which changes the answer) re-probes. }
  GDbForFileKey  : string = '';
  GDbForFileValue: string = '';

function ResolveDbForOpenFile(const AFilePath: string): string;
{ v0.42: the Structure outline must query a database that ACTUALLY CONTAINS the
  active file -- this is the one caller in the plugin that uses a SINGLE db
  rather than passing the whole list to the engine, so if the first entry is
  wrong there is no second chance and the result is silence, not an error.

  v(project-scoped): resolving that db is no longer a pure path/manifest
  question. Since the manifest was split per project, two projects can share a
  directory, and which of their indexes holds a given file is a property of the
  INDEX CONTENT -- only a `files` lookup can answer it. The engine does that
  (resolve-dbs --in <file> --project <active>, which orders by membership and
  breaks ties with the active project), so ask it rather than guess here: the
  BPL has no SQLite of its own, and giving a design-time package a FireDAC
  dependency to run one SELECT is a far worse trade than one cached spawn.

  Falls back to the old take-the-first-resolved-db behaviour when the engine
  cannot answer, so nothing regresses to empty. Empty => let the exe
  self-resolve. }
var
  Dbs       : TArray<string>;
  Key       : string        ;
  Cmd       : string        ;
  Output    : string        ;
  Lines     : TArray<string>;
  L         : string        ;
  ActiveProj: string        ;
begin
  Result:= '';
  try
    { QUALIFIED: TDragLintStructureForm has a method of the same name, and this is
      a unit-level function that must not accidentally shadow-resolve to it. }
    ActiveProj:= DragLint.Plugin.DbResolver.GetActiveProjectFilePath;
    Key:= LowerCase(AFilePath) + '|' + LowerCase(ActiveProj);
    if (Key = GDbForFileKey) and (GDbForFileValue <> '') then Exit(GDbForFileValue);

    if AFilePath <> '' then
    begin
      Cmd:= Format('"%s" resolve-dbs --in "%s"', [ResolveExePath, AFilePath]);
      if ActiveProj <> '' then Cmd:= Cmd + Format(' --project "%s"', [ActiveProj]);
      Output:= '';
      if RunAndCaptureStdout(Cmd, Output, 15000) = 0 then
      begin
        Lines:= Output.Split([#13#10, #10], TStringSplitOptions.ExcludeEmpty);
        for L in Lines do
          if (Trim(L) <> '') and TFile.Exists(Trim(L)) then
          begin
            Result:= Trim(L);
            Break;
          end;
      end;
    end;

    { Fallback: the resolver's own order, exactly as before. }
    if Result = '' then
    begin
      Dbs:= ResolveActiveIndexDbs(LoadSettings);
      if Length(Dbs) > 0 then Result:= Dbs[0];
    end;

    if Result <> '' then
    begin
      GDbForFileKey  := Key;
      GDbForFileValue:= Result;
    end;
  except
    Result:= '';
  end;
end;

{ Zero-arg form for the call sites that have no file to hand (they act on the
  form's current file). Deliberately NOT an overload of ResolveDbForOpenFile: a
  same-named pair here needs the `overload` directive on both, and getting that
  wrong produced a cascade of confusing errors elsewhere in the unit. Two names
  cost nothing. }
function ResolveDbForFile: string;
begin
  Result:= ResolveDbForOpenFile(GStructureCurrentFile);
end;

constructor TStructureNodeData.Create;
begin
  inherited Create;
  DiagIndex:= -1;
end;

{ ---- TDragLintStructureForm ---- }

constructor TDragLintStructureForm.Create(AOwner: TComponent);
var
  PanelFile  : TPanel;
  PanelSearch: TPanel;
  LblFilter  : TLabel;
begin
  inherited CreateNew(AOwner);
  Caption  := 'drag-lint Structure';
  Width    := 380;
  Height   := 520;
  Position := poDefaultPosOnly;
  FormStyle:= fsStayOnTop;
  BorderIcons:= [biSystemMenu, biMinimize, biMaximize];
  OnActivate:= FormActivate;
  OnDestroy := FormDestroy;

  { Row 1: file label + refresh button. Created first so it docks topmost. }
  PanelFile:= TPanel.Create(Self);
  PanelFile.Parent    := Self;
  PanelFile.Align     := alTop;
  PanelFile.Height    := 30;
  PanelFile.BevelOuter:= bvNone;

  FBtnRefresh:= TButton.Create(PanelFile);
  FBtnRefresh.Parent := PanelFile;
  FBtnRefresh.Caption:= 'Refresh';
  FBtnRefresh.Align  := alRight;
  FBtnRefresh.Width  := 72;
  FBtnRefresh.Hint   := 'Re-read this unit, then reindex the project and re-lint it';
  FBtnRefresh.ShowHint:= True;
  FBtnRefresh.OnClick:= BtnRefreshClick;

  { v0.47: jump to Diagnostics. A refresh leaves the tree scrolled to Code
    Elements, hiding the Diagnostics section above the visible area; this scrolls
    it back so the top message is visible + selected. Docks left of Refresh. }
  FBtnDiag:= TButton.Create(PanelFile);
  FBtnDiag.Parent  := PanelFile;
  FBtnDiag.Caption := 'Diag';
  FBtnDiag.Hint    := 'Scroll to the top Diagnostics message';
  FBtnDiag.ShowHint:= True;
  FBtnDiag.Align   := alRight;
  FBtnDiag.Width   := 44;
  FBtnDiag.OnClick := BtnDiagClick;

  FLblFile:= TLabel.Create(PanelFile);
  FLblFile.Parent          := PanelFile;
  FLblFile.Align           := alClient;
  FLblFile.Caption         := '(no file)';
  FLblFile.Layout          := tlCenter;
  FLblFile.EllipsisPosition:= epPathEllipsis;

  { Row 2: filter edit + regex checkbox. Created after Row 1 so it docks below. }
  PanelSearch:= TPanel.Create(Self);
  PanelSearch.Parent:= Self;
  PanelSearch.Align := alTop;
  PanelSearch.Top:= PanelFile.Height; { ensure it sits below Row 1 }
  PanelSearch.Height    := 28;
  PanelSearch.BevelOuter:= bvNone;

  FRegex:= TCheckBox.Create(PanelSearch);
  FRegex.Parent := PanelSearch;
  FRegex.Align  := alRight;
  FRegex.Width  := 64;
  FRegex.Caption:= 'regex';
  FRegex.OnClick:= SearchChanged;

  LblFilter:= TLabel.Create(PanelSearch);
  LblFilter.Parent := PanelSearch;
  LblFilter.Align  := alLeft;
  LblFilter.Layout := tlCenter;
  LblFilter.Caption:= ' Filter: ';

  FSearch:= TEdit.Create(PanelSearch);
  FSearch.Parent  := PanelSearch;
  FSearch.Align   := alClient;
  FSearch.TextHint:= 'type to filter (substring, or regex)';
  FSearch.OnChange:= SearchChanged;

  { tree view }
  FTree:= TTreeView.Create(Self);
  FTree.Parent       := Self;
  FTree.Align        := alClient;
  FTree.ReadOnly     := True;
  FTree.ShowLines    := True;
  FTree.HideSelection:= False;
  FTree.OnDblClick   := TreeDblClick;
  FTree.OnMouseDown  := TreeMouseDown;
  { 2026-10-13: Ctrl/Shift-click several Diagnostics rows, then Copy / Ctrl+C. }
  FTree.MultiSelect     := True;
  FTree.MultiSelectStyle:= [msControlSelect, msShiftSelect];
  FTree.OnKeyDown       := TreeKeyDown;

  { v0.43: right-click navigation menu. Single/double-click stays as the
    primary "go to declaration"; the secondary actions live here. }
  FPopup:= TPopupMenu.Create(Self);
  AddPopupItem(FPopup, 'Go to &Declaration'          , GoToDeclarationClick   );
  AddPopupItem(FPopup, 'Go to &Implementation (body)', GoToImplementationClick);
  AddPopupItem(FPopup, 'Find &Usages'                , FindUsagesClick        );
  AddPopupItem(FPopup, 'Show in Call &Graph'         , ShowInButterflyClick   );
  { v0.90 AutoDocument: 'Document it' acts on a symbol node (like Find Usages),
    so it is grouped with the symbol nav items. Enablement is set per-popup. }
  AddPopupItem(FPopup, '&Document it'                , DocumentItClick        );
  FItemDocIt:= FPopup.Items[FPopup.Items.Count - 1];
  { ADF T10 AutoDocument: whole-file / whole-project batch. Unlike 'Document it'
    these do not need a symbol node -- they act on the active editor file / the
    active .dproj regardless of what is clicked, so enablement is "always on"
    (guarded only by having an active file/project at all; see PopupPopup). }
  AddPopupItem(FPopup, 'Document &unit'              , DocumentUnitClick      );
  FItemDocUnit:= FPopup.Items[FPopup.Items.Count - 1];
  AddPopupItem(FPopup, 'Document &project'           , DocumentProjectClick   );
  FItemDocProject:= FPopup.Items[FPopup.Items.Count - 1];
  { Task 8 enum-helper: 'Create helper class' acts on a symbol node (an enum or
    one of its values), so it is grouped with the other symbol-scoped items.
    Enablement is set per-popup in PopupPopup. }
  AddPopupItem(FPopup, 'Create &helper class'        , CreateEnumHelperClick  );
  FItemEnumHelper:= FPopup.Items[FPopup.Items.Count - 1];
  AddPopupItem(FPopup, '-'                           , nil                    ); { separator }
  { The 'Ctrl+C' is caption text, not a ShortCut: TreeKeyDown owns the key,
    and a ShortCut too would copy twice when both see it. }
  AddPopupItem(FPopup, '&Copy'#9'Ctrl+C'             , CopySelectedDiagnosticsClick);
  FItemCopySel:= FPopup.Items[FPopup.Items.Count - 1];
  AddPopupItem(FPopup, 'Copy &All Diagnostics'       , CopyDiagnosticsClick  );
  AddPopupItem(FPopup, '&Rescan this unit'           , RescanUnitClick       );
  FItemRescan:= FPopup.Items[FPopup.Items.Count - 1];
  { v0.88 AutoFix: run the CLI fix verbs on the clicked node. Enablement is set
    per-popup by PopupPopup, so we keep references to the three items. }
  AddPopupItem(FPopup, '-'                           , nil                    ); { separator }
  AddPopupItem(FPopup, '&Fix it'                     , FixItClick             );
  AddPopupItem(FPopup, 'Fix all in &unit'            , FixAllInUnitClick      );
  AddPopupItem(FPopup, 'Fix all in &project'         , FixAllInProjectClick   );
  FItemFixIt     := FPopup.Items[FPopup.Items.Count - 3];
  FItemFixUnit   := FPopup.Items[FPopup.Items.Count - 2];
  FItemFixProject:= FPopup.Items[FPopup.Items.Count - 1];
  { 'Allow this message' sits with the fix verbs because it is the other answer
    to a finding: fix the code, or record that a human looked and accepted it.
    Deliberately LAST, and deliberately not the default -- suppression should
    take one more deliberate movement than fixing. }
  AddPopupItem(FPopup, '&Allow this message'         , AllowClick             );
  FItemAllow:= FPopup.Items[FPopup.Items.Count - 1];
  FPopup.OnPopup := PopupPopup;
  FTree.PopupMenu:= FPopup;
  if GLiveStructureForms = nil then GLiveStructureForms:= TList<TDragLintStructureForm>.Create;
  GLiveStructureForms.Add(Self);
end; // constructor

procedure TDragLintStructureForm.FormDestroy(Sender: TObject);
begin
  if GLiveStructureForms <> nil then GLiveStructureForms.Remove(Self);
  ClearNodeData;
  FreeAndNil(FFixableRules); { v0.88 AutoFix: release the cached fixable-rule set }
  FreeAndNil(FOptInFixRules);
end;

procedure TDragLintStructureForm.ClearNodeData;

  procedure ClearTree(ANode: TTreeNode);
  begin
    while ANode <> nil do
    begin
      if Assigned(ANode.Data) then
      begin
        TStructureNodeData(ANode.Data).Free;
        ANode.Data:= nil;
      end;
      ClearTree(ANode.getFirstChild);
      ANode:= ANode.getNextSibling;
    end;
  end;

begin
  if FTree.Items.Count > 0 then ClearTree(FTree.Items[0]);
end;

function TDragLintStructureForm.GetActiveFilePath: string;
var
  ESS: IOTAEditorServices;
  EV : IOTAEditView      ;
begin
  Result:= '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if EV = nil then Exit;
  Result:= EV.Buffer.FileName;
end;

procedure TDragLintStructureForm.RefreshForFile(const AFilePath: string);
var
  ExePath: string;
  DbPath : string;
begin
  FCurrentFile:= AFilePath;
  { Mirror it unit-level: ResolveDbForFile is a plain function (it predates the
    form and is called from handlers that have no Self), and it now needs to know
    WHICH file it is resolving for. }
  GStructureCurrentFile:= AFilePath;
  if AFilePath = '' then
  begin
    FLblFile.Caption:= '(no active editor)';
    SetLength(FDiags, 0);
    SetLength(FSyms , 0);
    BuildTree(FSearch.Text);
    Exit;
  end;
  FLblFile.Caption:= ExtractFileName(AFilePath);

  { Re-shell once; cache the results so the filter re-renders without re-running
    drag-lint on every keystroke. }
  StructureCache.InvalidateForFile(AFilePath);
  FDiags:= Cache.GetForFile(AFilePath);
  ExePath:= ResolveExePath;
  DbPath := ResolveDbForOpenFile(AFilePath); { explicit: do not depend on the mirror being set first }
  FSyms:= StructureCache.GetSymbolsForFile(AFilePath, ExePath, DbPath);

  DLT(
    'structure', Format('RefreshForFile %s -> %d diag(s), %d sym(s) [exe=%s db=%s]', [ExtractFileName(AFilePath), Length(FDiags), Length(FSyms), ExtractFileName(ExePath),
        ExtractFileName(DbPath)]));
  BuildTree(FSearch.Text);
end; // procedure

function TDragLintStructureForm.SymMatches(const ASym: TSymbolInfo; const AFilter: string): Boolean;
begin
  if AFilter = '' then Exit(True);
  if FRegex.Checked then
  begin
    try
      Result:= TRegEx.IsMatch(ASym.Name, AFilter, [roIgnoreCase]) or TRegEx.IsMatch(ASym.QName, AFilter, [roIgnoreCase]);
    except
      Result:= False; { incomplete/invalid regex while typing -> match none }
    end;
  end
  else Result:= ContainsText(ASym.Name, AFilter) or ContainsText(ASym.QName, AFilter);
end;

procedure TDragLintStructureForm.BuildTree(const AFilter: string);
var
  RootDiag   : TTreeNode          ;
  RootSym    : TTreeNode          ;
  Node       : TTreeNode          ;
  ND         : TStructureNodeData ;
  D          : TDragLintDiagnostic;
  S          : TSymbolInfo        ;
  i          : Integer            ;
  Shown      : Integer            ;
  Caption    : string             ;
  DiagOrder  : TArray<Integer>    ; { indices into FDiags, sorted by (Line, original index) }
  Imgs       : TCustomImageList   ; { severity icons; nil when unavailable }
  GlyphPx    : Integer            ;
begin
  FTree.Items.BeginUpdate;
  try
    FRootDiag:= nil; { v0.88 AutoFix: about to invalidate all nodes; reassigned below }
    ClearNodeData;
    FTree.Items.Clear;

    { --- Diagnostics root (not filtered: diagnostics are about lines/messages,
          not symbol names) ---
      v0.86: with ~hundreds of findings per file, CLI/cache order (typically
      rule-then-file order) is unusable -- display in ascending-line order so
      the list reads top-to-bottom like the file. FDiags itself is left
      untouched; the rows are an INDEX permutation of it. The order comes from
      DiagList.DiagDisplayOrder -- (line, column, original index) -- which the
      clipboard copies use too, so the paste always matches the screen (it
      did not until 2026-10-13: Copy All walked the raw cache order). }
    DiagOrder:= DiagDisplayOrder(FDiags);

    { --- Severity icons on the message rows (2026-08-25) ---
      The owner's reference surface is VS Code's PROBLEMS tab, where every row
      carries a severity icon. This tree carried a text tag instead -- '[E] ',
      '[W] ' -- which is what "no icon on the message rows" meant.

      Sized from the screen DPI rather than hardcoded, since a TTreeView grows
      its row height to fit the image list and a 16px list on a 200% display
      would give tiny icons beside large text. SeverityGlyphImages caches, so
      calling it on every rebuild costs a comparison. }
    GlyphPx:= MulDiv(16, Screen.PixelsPerInch, 96);
    { StructureGlyphImages, NOT SeverityGlyphImages: this ONE list is assigned
      to the whole tree, and a TTreeView node that never assigns ImageIndex
      keeps the default 0. With the severity-only list that default WAS THE
      ERROR GLYPH, so both roots and every code element were badged as errors
      -- reported from a live IDE, 2026-08-27. The combined list keeps
      severity at 0..3 and adds a kind glyph per element, and every node
      below now sets an index explicitly. }
    Imgs   := StructureGlyphImages(GlyphPx);
    FTree.Images:= Imgs;

    RootDiag:= FTree.Items.Add(nil, Format('Diagnostics (%d)', [Length(FDiags)])
      + (if (FActionNote <> '') and SameText(FActionNoteFile, FCurrentFile) then '  --  ' + FActionNote else ''));
    RootDiag.Data:= nil;
    SetNodeGlyph(RootDiag, KindGlyphIndex(kgFolder));
    FRootDiag:= RootDiag; { v0.88 AutoFix: remember the root for node discrimination }
    for i:= 0 to High(DiagOrder) do
    begin
      D:= FDiags[DiagOrder[i]];
      ND:= TStructureNodeData.Create;
      ND.Line:= D.Line + 1;
      ND.Code:= D.Code; { v0.88 AutoFix: rule-id so the popup can offer a per-finding fix }
      ND.DiagIndex:= DiagOrder[i]; { so Copy can emit exactly the selected rows }
      { The '[E] ' text tag and the icon are alternatives, not companions:
        showing both is noise. But the tag is only dropped when an icon will
        actually appear -- SeverityGlyphImages returns nil if the list cannot
        be built, and dropping the tag on that path would leave the row with NO
        severity at all. Degrade to a tag, never to nothing.
        CopyDiagnosticsClick keeps the tag unconditionally: clipboard text has
        no icons. }
      if Assigned(Imgs) then Caption:= Format('(%d) ', [D.Line + 1]) + D.Message
      else Caption:= SeverityPrefix(D.Severity) + Format('(%d) ', [D.Line + 1]) + D.Message;
      Node:= FTree.Items.AddChild(RootDiag, Caption);
      Node.Data:= ND;
      { Not Ord(D.Severity) -- the enum orders hint before info. }
      SetNodeGlyph(Node, SeverityGlyphIndex(D.Severity));
    end;

    { --- Code Elements root (filtered by AFilter) --- }
    Shown:= 0;
    RootSym:= FTree.Items.Add(nil, ''); { caption set after we count }
    RootSym.Data:= nil;
    SetNodeGlyph(RootSym, KindGlyphIndex(kgFolder));
    for i:= 0 to High(FSyms) do
    begin
      S:= FSyms[i];
      if not SymMatches(S, AFilter) then Continue;
      Inc(Shown);
      ND:= TStructureNodeData.Create;
      ND.Line := S.Line;
      ND.Name := S.Name;
      ND.QName:= S.QName;
      ND.Kind := S.Kind;
      Caption:= KindPrefix(S.Kind) + S.Name;
      if S.Signature <> '' then
      begin
        if (S.Signature[1] = '(') or (S.Signature[1] = ':') then Caption:= Caption + S.Signature
        else Caption:= Caption + ': ' + S.Signature;
      end;
      Node:= FTree.Items.AddChild(RootSym, Caption);
      Node.Data:= ND;
      SetNodeGlyph(Node, KindGlyphIndex(GlyphClassFor(S.Kind)));
    end; // for

    if AFilter = '' then RootSym.Text:= Format('Code Elements (%d)', [Shown])
    else RootSym.Text:= Format('Code Elements (%d of %d)', [Shown, Length(FSyms)]);

    RootDiag.Expand(False);
    RootSym .Expand(False);
  finally
    FTree.Items.EndUpdate;
  end; // try
end; // procedure

procedure TDragLintStructureForm.SearchChanged(Sender: TObject);
begin
  { Re-filter the already-loaded symbols on every keystroke (no re-shell). }
  BuildTree(FSearch.Text);
end;

{ Refresh = a real rescan (owner ask 2026-10-13): re-read the panel NOW, and
  queue an incremental reindex of the project followed by a re-lint, so the
  index-backed rules catch up too. Same path as 'Rescan this unit'. }
procedure TDragLintStructureForm.BtnRefreshClick(Sender: TObject);
begin
  RefreshForFile(GetActiveFilePath);
  RescanUnitClick(Sender);
end;

{ v0.47: scroll the tree so the Diagnostics section is at the top of the view
  and select its first message. After a refresh the tree is scrolled to Code
  Elements, leaving Diagnostics above the visible area. Diagnostics is always the
  first root node (added first in BuildTree). }
function TDragLintStructureForm.HasDiagnostics: Boolean;
begin
  Result:= Length(FDiags) > 0;
end;

{ v(session 73): caret line -> panel selection.
  docs\INBOX-caret-line-should-select-its-finding-in-the-panel.md, the owner's
  ask from live IDE use: "when I highlight a line in the editor, if this line
  has a message in drag-lint structure, we need to highlight this message there
  so we could see it and maybe easier to right-click".

  Wiring, not new machinery: the diagnostic rows are already the children of
  FRootDiag, each carrying a TStructureNodeData with the 1-based Line.

  DESIGN POINTS:

  * No focus change and no caret move (see the declaration's remarks). Only the
    tree's selection + MakeVisible are touched, which is what ScrollToDiagnostics
    already does.
  * NEAREST row, not exact (owner ask 2026-10-13; this used to CLEAR the
    selection on a line with no finding, which left the panel blank for most
    caret positions). The choice is DiagList.NearestDiagRow, pinned by
    tests\autotest\run_diaglist_harness.ps1.
  * MORE THAN ONE FINDING ON A LINE is normal. The FIRST row on that line wins
    -- the rows are in (line, column) order, so that is the leftmost finding.
  * Cost: this runs off a caret poll, so it walks FRootDiag's children -- tens
    of nodes for a file, not the whole tree, and only when the caret's LINE
    changed (the caller debounces on line, not on position).

  The fifth (re-entrancy) is the CALLER's, because the loop it guards against
  runs through the caller: this function cannot move the editor. }
function TDragLintStructureForm.SelectDiagnosticForLine(ALine: Integer): Boolean;
var
  N    : TTreeNode;
  Nodes: TArray<TTreeNode>;
  Lines: TArray<Integer>;
  Row  : Integer;
begin
  Result:= False;
  if (FTree = nil) or (FRootDiag = nil) or (ALine <= 0) then Exit;

  N:= FRootDiag.getFirstChild;
  while N <> nil do
  begin
    if N.Data <> nil then
    begin
      Nodes:= Nodes + [N];
      Lines:= Lines + [TStructureNodeData(N.Data).Line];
    end;
    N:= N.getNextSibling;
  end;

  Row:= NearestDiagRow(Lines, ALine);
  if Row < 0 then Exit;
  N:= Nodes[Row];
  if (FTree.Selected = N) and (FTree.SelectionCount = 1) then Exit(True);
  // MakeVisible before selecting: selecting a node that is scrolled out of
  // view leaves the tree showing the wrong region until the next paint.
  N.MakeVisible;
  FTree.Select(N); { a plain Select replaces any multi-row selection }
  Result:= True;
end;

procedure TDragLintStructureForm.ScrollToDiagnostics;
var
  Root: TTreeNode;
begin
  if (FTree = nil) or (FTree.Items.Count = 0) then Exit;
  Root:= FTree.Items.GetFirstNode; { Diagnostics root }
  if Root = nil then Exit;
  FTree.Items.BeginUpdate;
  try
    Root.Expand(False);
    if Root.getFirstChild <> nil then FTree.Select(Root.getFirstChild) { focus the top message line }
    else FTree.Select(Root); { no messages -> just the header }
    FTree.TopItem:= Root; { pin the Diagnostics header to the top of the view }
  finally
    FTree.Items.EndUpdate;
  end;
end; // procedure

procedure TDragLintStructureForm.BtnDiagClick(Sender: TObject);
begin
  ScrollToDiagnostics;
end;

procedure TDragLintStructureForm.FormActivate(Sender: TObject);
var
  FilePath: string;
begin
  FilePath:= GetActiveFilePath;
  { Only auto-refresh when the active file changes }
  if not SameText(FilePath, FCurrentFile) then RefreshForFile(FilePath);
end;

function TDragLintStructureForm.SelectedNodeData: TStructureNodeData;
var
  Node: TTreeNode;
begin
  Result:= nil;
  Node:= FTree.Selected;
  if (Node <> nil) and (Node.Data <> nil) then Result:= TStructureNodeData(Node.Data);
end;

procedure TDragLintStructureForm.NavigateToLine(ALine: Integer);
var
  ESS: IOTAEditorServices;
  EV : IOTAEditView      ;
  Pos: IOTAEditPosition  ;
begin
  if ALine <= 0 then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if EV = nil then Exit;
  Pos:= EV.Position;
  if Pos = nil then Exit;
  Pos.GotoLine(ALine);
  EV.Paint;
end;

procedure TDragLintStructureForm.TreeDblClick(Sender: TObject);
var
  ND: TStructureNodeData;
begin
  ND:= SelectedNodeData;
  if ND <> nil then NavigateToLine(ND.Line);
end;

procedure TDragLintStructureForm.TreeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  N: TTreeNode;
begin
  { Right-click should target the node under the cursor (TTreeView doesn't
    select on right-click by itself), so the popup acts on what was clicked. }
  if Button = mbRight then
  begin
    N:= FTree.GetNodeAt(X, Y);
    { A right-click INSIDE a multi-row selection keeps it, so 'Copy' acts on
      every row the user picked; a click elsewhere selects just that node. }
    if (N <> nil) and not N.Selected then FTree.Select(N);
  end;
end;

procedure TDragLintStructureForm.GoToDeclarationClick(Sender: TObject);
var
  ND: TStructureNodeData;
begin
  ND:= SelectedNodeData;
  if ND <> nil then NavigateToLine(ND.Line);
end;

procedure TDragLintStructureForm.GoToImplementationClick(Sender: TObject);
var
  ND   : TStructureNodeData;
  Parts: TArray<string>    ;
  Cls  : string            ;
  Mth  : string            ;
  Ln   : Integer           ;
begin
  ND:= SelectedNodeData;
  if (ND = nil) or (ND.Name = '') then Exit;

  { derive class + method from the qualified name (Unit.TClass.Method or
    Unit.Proc). }
  Cls:= '';
  Mth:= ND.Name;
  if ND.QName <> '' then
  begin
    Parts:= ND.QName.Split(['.']);
    if Length(Parts) >= 3 then
    begin
      Cls:= Parts[High(Parts) - 1];
      Mth:= Parts[High(Parts)];
    end
    else if Length(Parts) = 2 then Mth:= Parts[High(Parts)];
  end;

  Ln:= FindImplementationLine(FCurrentFile, Cls, Mth);
  if Ln > 0 then NavigateToLine(Ln)
  else { no separate body found (e.g. abstract, interface method, or inline) --
      fall back to the declaration so the click is never a no-op. }
    NavigateToLine(ND.Line);
end; // procedure

procedure TDragLintStructureForm.FindUsagesClick(Sender: TObject);
var
  ND: TStructureNodeData;
  Db: string            ;
begin
  ND:= SelectedNodeData;
  if (ND = nil) or (ND.Name = '') then Exit;
  Db:= ResolveDbForFile;
  if Db <> '' then ShowFindUsages(ND.Name, ResolveExePath, [Db])
  else ShowFindUsages(ND.Name, ResolveExePath, TArray<string>.Create());
end;

procedure TDragLintStructureForm.ShowInButterflyClick(Sender: TObject);
{ Task 5: right-click nav -- surfaces the selected symbol in the Call Graph
  (butterfly) tab. User-initiated only (popup click); no auto-select on mere
  tree navigation (Batch D T9 dock-self-focus lesson). }
var
  ND: TStructureNodeData;
  Db: string            ;
begin
  ND:= SelectedNodeData;
  if (ND = nil) or (ND.Name = '') then Exit;
  Db:= ResolveDbForFile;
  if Db = '' then
  begin
    ShowMessage('drag-lint: no project index for this symbol.');
    Exit;
  end;
  ShowButterflyForQName(ND.Name, Db);
end;

{ Copy All: every finding, in the SAME order as the rows on screen (the raw
  cache order is rule-grouped -- that mismatch was the 2026-10-13 report). }
procedure TDragLintStructureForm.CopyDiagnosticsClick(Sender: TObject);
var
  Txt: string;
begin
  Txt:= DiagClipboardText(FCurrentFile, FDiags, DiagDisplayOrder(FDiags));
  if Txt <> '' then Clipboard.AsText:= Txt;
end;

{ Indices into FDiags of the selected Diagnostics rows, in row order. Walks
  the rows rather than FTree.Selections, whose order is CLICK order. }
function TDragLintStructureForm.SelectedDiagIndices: TArray<Integer>;
var
  N: TTreeNode;
begin
  Result:= [];
  if FRootDiag = nil then Exit;
  N:= FRootDiag.getFirstChild;
  while N <> nil do
  begin
    if N.Selected and (N.Data <> nil) and (TStructureNodeData(N.Data).DiagIndex >= 0) then
      Result:= Result + [TStructureNodeData(N.Data).DiagIndex];
    N:= N.getNextSibling;
  end;
end;

{ Copy: just the selected rows, no file header -- what was picked is what is
  pasted. With only the Diagnostics root selected it copies everything, which
  is what selecting the root means. }
procedure TDragLintStructureForm.CopySelectedDiagnosticsClick(Sender: TObject);
var
  Txt: string;
begin
  if NodeIsDiagnosticsRoot(FTree.Selected) and (FTree.SelectionCount <= 1) then
  begin
    CopyDiagnosticsClick(Sender);
    Exit;
  end;
  Txt:= DiagClipboardText('', FDiags, SelectedDiagIndices);
  if Txt <> '' then Clipboard.AsText:= Txt;
end;

procedure TDragLintStructureForm.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = Ord('C')) and (Shift = [ssCtrl]) then
  begin
    CopySelectedDiagnosticsClick(Sender);
    Key:= 0;
  end;
end;

{ Rescan this unit: the on-demand answer to "the panel still shows findings I
  already fixed". Reindexes the active project incrementally (the project rules
  -- unused-unit-in-uses and friends -- read the INDEX, not the buffer) and
  re-lints the buffer when that lands. Runs on the job queue, so the status bar
  shows it working and the IDE never blocks. }
procedure TDragLintStructureForm.RescanUnitClick(Sender: TObject);
begin
  try
    if FCurrentFile = '' then Exit;
    SetDragLintNote('Rescanning ' + ExtractFileName(FCurrentFile) + '...');
    if not EnqueueReindexThenRelint('Rescan ' + ExtractFileName(FCurrentFile)) then
      DLT('structure', 'Rescan: no active project/DB -- re-lint only');
  except
    on E: Exception do DLT('structure', 'RescanUnitClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ ---- v0.88 AutoFix: right-click Fix it / Fix all ---- }

{ Fetch (once, then cache) the set of rule-ids the CLI reports as having a
  registered quick-fix. We ask the same exe every other spawn site uses:
  "drag-lint rules --json" emits a top-level "rules" array whose objects each
  carry an "id" string and a "fixable" boolean. Rule-ids are stored lower-cased
  so membership tests are case-insensitive. Any spawn/parse failure leaves
  FFixableRules an EMPTY (non-nil) list -- the popup then simply never offers
  'Fix it', which is the safe degradation. }
procedure TDragLintStructureForm.EnsureFixableRules;
var
  Cmd    : string      ;
  Output : string      ;
  ExitVal: Integer     ;
  Root   : TJSONObject ;
  Arr    : TJSONArray  ;
  V      : TJSONValue  ;
  Obj    : TJSONObject ;
  IdV    : TJSONValue  ;
  FixV   : TJSONValue  ;
  OptV   : TJSONValue  ;
begin
  if FFixableRules <> nil then Exit;
  FFixableRules:= TStringList.Create;
  FFixableRules.CaseSensitive:= False;
  FFixableRules.Duplicates   := dupIgnore;
  FFixableRules.Sorted       := True;
  FOptInFixRules:= TStringList.Create;
  FOptInFixRules.CaseSensitive:= False;
  FOptInFixRules.Duplicates   := dupIgnore;
  FOptInFixRules.Sorted       := True;
  try
    Cmd    := Format('"%s" rules --json', [ResolveExePath]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 15000);
    if (ExitVal <> 0) or (Output = '') then
    begin
      DLT('autofix', Format('rules --json failed (exit=%d, len=%d)', [ExitVal, Length(Output)]));
      Exit;
    end;
    Root:= TJSONObject.ParseJSONValue(Output) as TJSONObject;
    if Root = nil then
    begin
      DLT('autofix', 'rules --json: not a JSON object');
      Exit;
    end;
    try
      Arr:= Root.GetValue('rules') as TJSONArray;
      if Arr = nil then Exit;
      for V in Arr do
      begin
        Obj:= V as TJSONObject;
        if Obj = nil then Continue;
        FixV:= Obj.GetValue('fixable');
        IdV := Obj.GetValue('id'     );
        { fix_opt_in: a naming fix the engine applies only when the config opts it
          in. Counting those offered 'Fix all in unit (78)' on ORM3 BASICS.PAS and
          then fixed nothing (2026-10-13). An engine without the field reads False. }
        OptV:= Obj.GetValue('fix_opt_in');
        if (OptV is TJSONBool) and TJSONBool(OptV).AsBoolean then
        begin
          if IdV <> nil then FOptInFixRules.Add(LowerCase(IdV.Value));
          Continue;
        end;
        if (FixV is TJSONBool) and TJSONBool(FixV).AsBoolean and (IdV <> nil) then
          FFixableRules.Add(LowerCase(IdV.Value));
      end;
      DLT('autofix', Format('fixable rules cached: %d', [FFixableRules.Count]));
    finally
      Root.Free;
    end;
  except
    on E: Exception do
      DLT('autofix', 'EnsureFixableRules failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ The 'Diagnostics (N)' root is the node we cached in BuildTree: top-level
  (Parent = nil), Data = nil. Identity against FRootDiag is the primary test;
  the caption/shape check is a belt-and-braces fallback should the reference go
  stale. Code Elements' root also has Data = nil, so we must not treat it as the
  diagnostics root -- the FRootDiag identity check keeps them apart. }
function TDragLintStructureForm.NodeIsDiagnosticsRoot(ANode: TTreeNode): Boolean;
begin
  Result:= (ANode <> nil) and (ANode = FRootDiag)
       and (ANode.Parent = nil) and (ANode.Data = nil);
end;

{ A fixable finding node hangs off the Diagnostics root, carries per-finding
  node data (Data <> nil) whose Code is a rule-id in the cached fixable set. }
function TDragLintStructureForm.NodeIsFixableFinding(ANode: TTreeNode): Boolean;
var
  ND: TStructureNodeData;
begin
  Result:= False;
  if (ANode = nil) or (ANode.Data = nil) then Exit;
  if ANode.Parent <> FRootDiag then Exit; { only diagnostics children are findings }
  ND:= TStructureNodeData(ANode.Data);
  if ND.Code = '' then Exit;
  { unused-unit-in-uses is fixed by the compiler-verified uses-fix verb, not
    by `lint --fix`, so it is not in the engine's fixable set. Offered when
    the finding names a unit and there is a project + index to verify in. }
  if SameText(ND.Code, CUnusedUnitRule) then
    Exit((UnusedUnitOfNode(ANode) <> '') and (GetActiveProjectFilePath <> '') and (GLastProjectDb <> ''));
  EnsureFixableRules;
  Result:= (FFixableRules <> nil) and (FFixableRules.IndexOf(LowerCase(ND.Code)) >= 0);
  { a naming rename finds every use through the index, so it needs one }
  if (not Result) and (FOptInFixRules <> nil) and (FOptInFixRules.IndexOf(LowerCase(ND.Code)) >= 0) then
    Result:= ResolveDbForFile <> '';
end;

{ The unit an unused-unit-in-uses row names, read from its finding's message. }
function TDragLintStructureForm.UnusedUnitOfNode(ANode: TTreeNode): string;
var
  ND: TStructureNodeData;
begin
  Result:= '';
  if (ANode = nil) or (ANode.Data = nil) then Exit;
  ND:= TStructureNodeData(ANode.Data);
  if (ND.DiagIndex < 0) or (ND.DiagIndex > High(FDiags)) then Exit;
  Result:= UnusedUnitFromMessage(FDiags[ND.DiagIndex].Message);
end;

{ Reload the on-disk file into the IDE editor buffer AFTER the current callback
  unwinds. Copied from Keyboard.pas:284-297 (Extract Method): the closure must
  capture ONLY the FilePath string -- no OTAPI interface may outlive this
  callback or the module's edit-buffer refcount dangles and the tab closes. The
  module is re-resolved inside the queued proc; exceptions are swallowed into the
  plugin log (a queued proc must never throw into the IDE message loop). Refresh
  the diagnostics tree afterwards so it reflects the just-applied fix. }
procedure TDragLintStructureForm.ReloadCurrentFileBuffer;
var
  FilePath: string;
begin
  FilePath:= FCurrentFile; { capture as a plain string only }
  if FilePath = '' then Exit;
  TThread.ForceQueue(nil,
    procedure
    var
      QMS : IOTAModuleServices;
      QMod: IOTAModule        ;
    begin
      try
        if not Supports(BorlandIDEServices, IOTAModuleServices, QMS) then Exit;
        QMod:= QMS.FindModule(FilePath);
        if QMod <> nil then QMod.Refresh(True);
      except
        on E: Exception do DLT('autofix', 'deferred Refresh failed: ' + E.ClassName + ': ' + E.Message);
      end; // try
    end);
  { Re-read diagnostics + rebuild the tree so fixed findings drop off. Also
    deferred, and after the buffer reload is queued, so it runs on a settled UI. }
  TThread.ForceQueue(nil,
    procedure
    begin
      try
        RefreshDiagnosticsOnly;
      except
        on E: Exception do DLT('autofix', 'deferred diag refresh failed: ' + E.ClassName + ': ' + E.Message);
      end; // try
    end);
end; // procedure

{ Enable exactly the item(s) that apply to the clicked/selected node:
  - Diagnostics root or row -> 'Copy'; 'Fix all in unit (N)' when N > 0
                               findings have a registered fix.
  - Diagnostics root        -> 'Fix all in project'.
  - fixable finding         -> 'Fix it'.
  - an active file          -> 'Rescan this unit'.
  Everything else is disabled (nav items are untouched). }
procedure TDragLintStructureForm.PopupPopup(Sender: TObject);
var
  Node     : TTreeNode;
  IsRoot   : Boolean  ;
  IsFinding: Boolean  ;
  InDiags  : Boolean  ;
  FixCount : Integer  ;
begin
  Node     := FTree.Selected;
  IsRoot   := NodeIsDiagnosticsRoot(Node);
  IsFinding:= NodeIsFixableFinding (Node);
  InDiags  := IsRoot or ((Node <> nil) and (Node.Parent = FRootDiag) and (FRootDiag <> nil));
  { 'Fix all in unit' is offered only when there is something to fix, and says
    how much (owner ask 2026-10-13: it was always enabled and ran ~10 s to fix
    nothing). Available from any Diagnostics row, not only the root. }
  FixCount:= 0;
  if InDiags then
  begin
    EnsureFixableRules;
    if FFixableRules <> nil then FixCount:= CountFixableDiags(FDiags, FFixableRules.ToStringArray);
    { the opt-in naming rules too, gated on an index exactly as Fix it is
      (NodeIsFixableFinding): Fix all sends --fix-naming after a confirm }
    if (FOptInFixRules <> nil) and (FOptInFixRules.Count > 0) and (ResolveDbForFile <> '') then
      Inc(FixCount, CountFixableDiags(FDiags, FOptInFixRules.ToStringArray));
  end;
  FItemFixIt     .Enabled:= IsFinding;
  FItemFixUnit   .Enabled:= InDiags and (FixCount > 0);
  FItemFixUnit   .Caption:= if FixCount > 0 then Format('Fix all in &unit (%d)', [FixCount]) else 'Fix all in &unit';
  FItemFixProject.Enabled:= IsRoot   ;
  FItemCopySel   .Enabled:= InDiags and (Length(FDiags) > 0);
  FItemRescan    .Enabled:= FCurrentFile <> '';
  FItemDocIt     .Enabled:= NodeIsDocumentable(Node); { v0.90 AutoDocument: symbol node with a qname }
  { ADF T10: file-/project-scoped batch actions are node-independent -- only
    gated on there being an active file / active project to run against. }
  FItemDocUnit   .Enabled:= FCurrentFile <> '';
  FItemDocProject.Enabled:= GetActiveProjectFilePath <> '';
  FItemEnumHelper.Enabled:= NodeIsEnumHelperTarget(Node); { Task 8: skEnum/skEnumValue node, no existing helper }
  FItemAllow     .Enabled:= NodeIsAllowableFinding(Node);
end;

{ Defined beside RunFixJob, below. }
procedure EnqueueRenamePreviewJob(const AFilePath, ATitle, APreviewCmd, AApplyCmd, AProject: string; ATimeoutMs: Integer); forward;

{ 'Fix it' -- apply the single fixable finding under the cursor:
  drag-lint lint --file <FCurrentFile> --fix --fix-line <L> --fix-rule <id> --apply
  On exit 0, reload the buffer + refresh the tree; otherwise log and do nothing.
  A naming rule runs the same command without --apply first
  (EnqueueRenamePreviewJob): a unit several projects own is confirmed first. }
procedure TDragLintStructureForm.FixItClick(Sender: TObject);
const
  CFixItTimeoutMs   = 60000;
  { uses-fix shadow-compiles the unit once for a baseline and once per try;
    ORM3's BASICS.PAS measured ~50 s for one unit }
  CUsesFixTimeoutMs = 300000;
var
  ND      : TStructureNodeData;
  UnitName: string;
begin
  try
    if not NodeIsFixableFinding(FTree.Selected) then Exit;
    ND:= TStructureNodeData(FTree.Selected.Data);
    if FCurrentFile = '' then Exit;
    if SameText(ND.Code, CUnusedUnitRule) then
    begin
      { Owner ask 2026-10-13: decide whether the unit can go entirely or must
        move to the implementation section. uses-fix answers by COMPILING:
        remove when nothing needs it and it has no initialization section,
        else move when only the implementation needs it, else leave it. }
      UnitName:= UnusedUnitOfNode(FTree.Selected);
      RunFixJob('Fix unused unit ' + UnitName,
        Format('"%s" uses-fix "%s" --project "%s" --db "%s" --platform %s --remove-unused --only "%s" --apply --format json',
          [ResolveExePath, FCurrentFile, GetActiveProjectFilePath, GLastProjectDb,
           LowerCase(GetActivePlatformForLibrary), UnitName]),
        CUsesFixTimeoutMs, UnitName);
      Exit;
    end;
    { --db: a naming fix renames every use the index knows about, and the
      store-backed fixes (doc-drift, missing-doc) need it too }
    var Db: string:= ResolveDbForFile;
    var Cmd: string:= Format('"%s" lint --file "%s" --fix --fix-line %d --fix-rule "%s"',
        [ResolveExePath, FCurrentFile, ND.Line, ND.Code])
        + (if Db <> '' then Format(' --db "%s"', [Db]) else '');
    { a naming rename may span several projects: preview, then confirm }
    if IsNamingFixRule(ND.Code) then
      EnqueueRenamePreviewJob(FCurrentFile, Format('Fix %s line %d', [ND.Code, ND.Line]), Cmd, Cmd + ' --apply', '', CFixItTimeoutMs)
    else RunFixJob(Format('Fix %s line %d', [ND.Code, ND.Line]), Cmd + ' --apply', CFixItTimeoutMs);
  except
    on E: Exception do DLT('autofix', 'FixItClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ Post one line to the IDE Messages pane -- the surface every Delphi user
  already watches, so an autofix result is seen even with the dock hidden. }
procedure PostIdeMessage(const AText: string);
var
  Svc: IOTAMessageServices;
begin
  try
    if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then Svc.AddTitleMessage(AText);
  except
    on E: Exception do DLT('autofix', 'PostIdeMessage failed: ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ Reload AFilePath from disk into its editor buffer, deferred until the
  current callback unwinds. Only the path string is captured -- no OTAPI
  interface may outlive the callback (see ReloadCurrentFileBuffer). }
procedure ReloadModuleFromDisk(const AFilePath: string);
begin
  if AFilePath = '' then Exit;
  TThread.ForceQueue(nil,
    procedure
    var
      QMS : IOTAModuleServices;
      QMod: IOTAModule        ;
    begin
      try
        if not Supports(BorlandIDEServices, IOTAModuleServices, QMS) then Exit;
        QMod:= QMS.FindModule(AFilePath);
        if QMod <> nil then QMod.Refresh(True);
      except
        on E: Exception do DLT('autofix', 'deferred Refresh failed: ' + E.ClassName + ': ' + E.Message);
      end;
    end);
end;

{ One autofix run, on the JOB QUEUE rather than the UI thread (owner report
  2026-10-13: Fix all took 10+ s with no sign of life, and afterwards gave no
  sign of what it had done). The status bar shows the job while it runs; on
  completion the engine's 'autofix:' summary goes to the status bar AND the
  Messages pane. When edits were applied the buffer is reloaded and the
  project reindexed, and the re-lint that follows refreshes the panel.

  OnDone deliberately captures no Self: the panel can be closed while the job
  runs, and a closure over a freed form is an AV in the IDE message loop. }
procedure TDragLintStructureForm.ShowActionNote(const AFile, ANote: string);
begin
  FActionNote    := FormatDateTime('hh:nn', Now) + ' ' + ANote;
  FActionNoteFile:= AFile;
  if (FRootDiag <> nil) and SameText(AFile, FCurrentFile) then
    FRootDiag.Text:= Format('Diagnostics (%d)', [Length(FDiags)]) + '  --  ' + FActionNote;
end;

{ Put a fix result on every live panel showing AFile -- the panel the user is
  looking at, which the status strip and the Messages pane are not (owner
  report 2026-10-13: "nothing was reported back"). }
procedure ShowFixResultInPanels(const AFile, ANote: string);
begin
  if GLiveStructureForms = nil then Exit;
  for var F: TDragLintStructureForm in GLiveStructureForms do
    try
      F.ShowActionNote(AFile, ANote);
    except
      on E: Exception do DLT('autofix', 'ShowActionNote failed: ' + E.ClassName + ': ' + E.Message);
    end;
end;
{ Does any editor of AFilePath hold unsaved changes? A fix rewrites the file
  ON DISK and then reloads the buffer from disk, so running one over unsaved
  edits would silently throw those edits away. }
function BufferIsModified(const AFilePath: string): Boolean;
var
  QMS : IOTAModuleServices;
  QMod: IOTAModule        ;
  I   : Integer           ;
begin
  Result:= False;
  try
    if not Supports(BorlandIDEServices, IOTAModuleServices, QMS) then Exit;
    QMod:= QMS.FindModule(AFilePath);
    if QMod = nil then Exit;
    for I:= 0 to QMod.ModuleFileCount - 1 do
      if QMod.ModuleFileEditors[I].Modified then Exit(True);
  except
    on E: Exception do DLT('autofix', 'BufferIsModified failed: ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ The first non-blank line of a failed run's output -- usually the engine's
  own ERROR line, which says more than an exit code does. }
function FirstOutputLine(const AOutput: string): string;
begin
  Result:= '';
  for var Line: string in AOutput.Split([#13#10, #10]) do
    if (Line.Trim <> '') and not Line.Trim.StartsWith('(loaded defaults') then Exit(Line.Trim);
end;

const
  CLogExcerptChars = 400; { enough of a failed run's output to diagnose it in the log }

{ The body of RunFixJob, standalone so a rename preview's OnDone -- which must
  not capture a form -- can queue the --apply run for AFilePath. }
procedure EnqueueFixJob(const AFilePath, ATitle, ACmd: string; ATimeoutMs: Integer; const AUsesUnit: string);
var
  Job     : TDragLintJob;
  FilePath: string;
  Title   : string;
  UsesUnit: string; { a local, so the OnDone closure captures a copy }
begin
  FilePath:= AFilePath;
  UsesUnit:= AUsesUnit;
  Title   := ATitle + ' -- ' + ExtractFileName(FilePath);
  if BufferIsModified(FilePath) then
  begin
    SetDragLintNote(Title + ': not run -- save the unit first (a fix rewrites the file on disk and reloads it)');
    PostIdeMessage('drag-lint: ' + Title + ': not run -- the unit has unsaved changes; save it first.');
    Exit;
  end;
  Job:= TDragLintJob.Create;
  Job.Kind       := jkGeneric;
  Job.Title      := Title;
  Job.CoalesceKey:= 'autofix:' + LowerCase(FilePath) + ':' + ATitle;
  Job.CmdLine    := ACmd;
  Job.TimeoutMs  := ATimeoutMs;
  Job.Streaming  := False;
  Job.OnDone:=
    procedure(AExit: Integer; AOutput: string)
    var
      Summary: string;
    begin
      try
        Summary:= if UsesUnit <> '' then UsesFixSummary(AOutput, UsesUnit) else AutofixSummary(AOutput);
        DLT('autofix', Format('%s -> exit=%d summary=[%s]', [Title, AExit, Summary]));
        if AExit <> 0 then
        begin
          DLT('autofix', Title + ' non-zero exit; output: ' + Copy(AOutput, 1, CLogExcerptChars));
          Summary:= Format('FAILED (exit %d): %s', [AExit, FirstOutputLine(AOutput)]);
        end
        else if Summary = '' then Summary:= 'finished, but the engine printed no autofix summary';
        var OptOut: string:= AutofixOptOutRules(AOutput);
        if (AExit = 0) and (OptOut <> '') then
          Summary:= Summary + ' -- naming fixes not opted in: ' + OptOut + ' (add them to "autofix" in drag-lint-lint.json)';
        ShowFixResultInPanels(FilePath, Title + ': ' + Summary);
        SetDragLintNote(Title + ': ' + Summary);
        PostIdeMessage('drag-lint: ' + Title + ': ' + Summary);
        { a rename refused AFTER other fixes on the line were written leaves the
          refusal as the summary, but the file on disk has still changed }
        if (AExit = 0) and (AutofixApplied(Summary) or ((UsesUnit = '') and AutofixAppliedInOutput(AOutput))) then
        begin
          ReloadModuleFromDisk(FilePath);
          EnqueueReindexThenRelint('');
        end;
      except
        on E: Exception do DLT('autofix', 'fix job OnDone failed: ' + E.ClassName + ': ' + E.Message);
      end;
    end;
  SetDragLintNote(Title + '...');
  JobQueue.Enqueue(Job);
end;

{ A naming fix in a unit several project indexes own renames it in all of them
  (spec 2026-10-13-multi-project-rename, criteria 16-19). So it runs twice: this
  PREVIEW (APreviewCmd, the fix without --apply) writes nothing; its OnDone then
    - shows a refusal on the Diagnostics root row and stops (criterion 18);
    - for 2+ owners, unknown ownership, or any 'rename-unindexed:' project
      (even with one indexed owner, owner decision 2026-10-14) asks first, and
      queues AApplyCmd only on Yes -- No writes nothing (criteria 16, 17, 19);
    - for one owner queues AApplyCmd at once, as before -- unless the preview
      printed 'rename-local: N' (Fix all, --fix-naming), which is confirmed as
      'Rename N identifier(s) in AProject?' first.
  Every rename confirm defaults to No. OnDone runs on the main thread (TDragLintJobQueue posts it with TThread.Queue),
  so the dialog is modal over the IDE; like EnqueueFixJob it captures no form. }
procedure EnqueueRenamePreviewJob(const AFilePath, ATitle, APreviewCmd, AApplyCmd, AProject: string; ATimeoutMs: Integer);
var
  Job     : TDragLintJob;
  FilePath: string;
  Title   : string;
  ApplyCmd: string;
begin
  FilePath:= AFilePath;
  ApplyCmd:= AApplyCmd;
  Title   := ATitle + ' -- ' + ExtractFileName(FilePath);
  if BufferIsModified(FilePath) then
  begin
    SetDragLintNote(Title + ': not run -- save the unit first (a fix rewrites the file on disk and reloads it)');
    PostIdeMessage('drag-lint: ' + Title + ': not run -- the unit has unsaved changes; save it first.');
    Exit;
  end;
  Job:= TDragLintJob.Create;
  Job.Kind       := jkGeneric;
  Job.Title      := Title + ' (preview)';
  Job.CoalesceKey:= 'autofix-preview:' + LowerCase(FilePath) + ':' + ATitle;
  Job.CmdLine    := APreviewCmd;
  Job.TimeoutMs  := ATimeoutMs;
  Job.Streaming  := False;
  Job.OnDone:=
    procedure(AExit: Integer; AOutput: string)
    var
      Preview: TRenamePreview;
      Note   : string;
    begin
      try
        Preview:= ParseRenamePreview(AOutput);
        DLT('autofix', Format('%s preview -> exit=%d owners=%d of %d refused=[%s]',
          [Title, AExit, Preview.OwnerCount, Preview.Probed, Preview.Refused]));
        Note:= '';
        if AExit <> 0 then
        begin
          DLT('autofix', Title + ' preview non-zero exit; output: ' + Copy(AOutput, 1, CLogExcerptChars));
          Note:= Format('FAILED (exit %d): %s -- nothing written', [AExit, FirstOutputLine(AOutput)]);
        end
        else
          case RenamePreviewAction(Preview) of
            rpaRefuse : Note:= 'rename refused -- ' + Preview.Refused;
            rpaConfirm, rpaConfirmLocal:
              if MessageDlg(
                   if RenamePreviewAction(Preview) = rpaConfirm
                     then RenameConfirmText(ExtractFileName(FilePath), Preview.OldName, Preview.NewName, Preview)
                     else RenameLocalConfirmText(AProject, Preview),
                   mtConfirmation, [mbYes, mbNo], 0, mbNo) = mrYes then EnqueueFixJob(FilePath, ATitle, ApplyCmd, ATimeoutMs, '')
              else Note:= 'cancelled -- nothing written';
            rpaApply  : EnqueueFixJob(FilePath, ATitle, ApplyCmd, ATimeoutMs, '');
          end; // case
        if Note = '' then Exit;
        ShowFixResultInPanels(FilePath, Title + ': ' + Note);
        SetDragLintNote(Title + ': ' + Note);
        PostIdeMessage('drag-lint: ' + Title + ': ' + Note);
      except
        on E: Exception do DLT('autofix', 'rename preview OnDone failed: ' + E.ClassName + ': ' + E.Message);
      end;
    end;
  SetDragLintNote(Title + ' (preview)...');
  JobQueue.Enqueue(Job);
end;

procedure TDragLintStructureForm.RunFixJob(const ATitle, ACmd: string; ATimeoutMs: Integer; const AUsesUnit: string);
begin
  EnqueueFixJob(FCurrentFile, ATitle, ACmd, ATimeoutMs, AUsesUnit);
end;

{ Is ACode a naming rule whose fix renames call sites (the engine's fix_opt_in
  set)? Those may span several projects, so they are previewed first. }
function TDragLintStructureForm.IsNamingFixRule(const ACode: string): Boolean;
begin
  EnsureFixableRules;
  Result:= (ACode <> '') and (FOptInFixRules <> nil) and (FOptInFixRules.IndexOf(LowerCase(ACode)) >= 0);
end;

{ An allowable finding node hangs off the Diagnostics root and carries a rule-id.
  Unlike 'Fix it' there is no fixable-rule set to consult: ANY finding can be
  reviewed and accepted -- that is the whole point, and it is how a project gets
  to zero without pretending the remaining findings are not there.

  The two review-marker bookkeeping rules are the exception. Allowing
  review-marker-stale would let a review outlive the code it reviewed, which is
  the single failure the hash exists to prevent; the cure is to allow the REAL
  finding again, which re-hashes its marker. review-marker-unused is cured by
  deleting the marker. The engine refuses both as well -- this predicate only
  greys them out so the refusal is visible before the click. }
function TDragLintStructureForm.NodeIsAllowableFinding(ANode: TTreeNode): Boolean;
var
  ND: TStructureNodeData;
begin
  Result:= False;
  if (ANode = nil) or (ANode.Data = nil) then Exit;
  if ANode.Parent <> FRootDiag then Exit; { only diagnostics children are findings }
  ND:= TStructureNodeData(ANode.Data);
  if ND.Code = '' then Exit;
  if SameText(ND.Code, 'review-marker-stale' ) then Exit;
  if SameText(ND.Code, 'review-marker-unused') then Exit;
  Result:= True;
end;

{ 'Allow this message' -- record that a human read this one finding on this one
  line and accepted it:
    drag-lint allow <file> --fix-line <L> --fix-rule <id> --apply
  The marker text is built by the ENGINE (TReviewMarkers.InsertInto), never here.
  One formatter and one hash rule means the IDE, the CLI and any future editor
  produce byte-identical markers; a second implementation here would drift the
  first time the format changed.

  On exit 0 the buffer is reloaded, the live runner re-lints, and the message
  drops off the Diagnostics list on the next tick. Other findings on the same
  line are untouched -- the marker names one rule. }
procedure TDragLintStructureForm.AllowClick(Sender: TObject);
var
  ND     : TStructureNodeData;
  Cmd    : string           ;
  Output : string           ;
  ExitVal: Integer          ;
begin
  try
    if not NodeIsAllowableFinding(FTree.Selected) then Exit;
    ND:= TStructureNodeData(FTree.Selected.Data);
    if FCurrentFile = '' then Exit;
    Cmd:= Format('"%s" allow "%s" --fix-line %d --fix-rule "%s" --apply',
      [ResolveExePath, FCurrentFile, ND.Line, ND.Code]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 30000);
    DLT('allow', Format('Allow %s line %d rule %s -> exit=%d', [ExtractFileName(FCurrentFile), ND.Line, ND.Code, ExitVal]));
    if ExitVal = 0 then ReloadCurrentFileBuffer
    else DLT('allow', 'Allow non-zero exit; output: ' + Copy(Output, 1, 400));
  except
    on E: Exception do DLT('allow', 'AllowClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ ---- v0.90 AutoDocument: right-click Document it ---- }

{ A documentable node is a symbol node (from the Code Elements root) carrying a
  resolvable qualified name. Diagnostic finding nodes carry Code (a rule-id) and
  QName = ''; symbol nodes carry QName (set in BuildTree) and Code = ''. The
  QName test alone is therefore the discriminator -- only symbol nodes have one. }
function TDragLintStructureForm.NodeIsDocumentable(ANode: TTreeNode): Boolean;
begin
  Result:= (ANode <> nil) and (ANode.Data <> nil)
       and (TStructureNodeData(ANode.Data).QName <> '');
end;

{ 'Document it' -- generate/repair the DocInsight doc-comment for the selected
  symbol via the CLI:
    drag-lint document --qname <q> --db <projDb> --apply
  Unlike the Fix verbs (which take --file), document is qname-driven and resolves
  the declaration through the index, so we pass --db (ResolveDbForFile = the same
  first/highest-priority index DB Find Usages / Fix-all use), NOT --file. The
  --apply write updates the source file (+ a .bak) on disk; on exit 0 we reload
  the buffer so the new comment appears in the editor and the tree refreshes.
  Everything is wrapped in try/except -> DLT so a plugin fault never reaches the
  IDE message loop. }
procedure TDragLintStructureForm.DocumentItClick(Sender: TObject);
var
  ND     : TStructureNodeData;
  Cmd    : string           ;
  Output : string           ;
  Db     : string           ;
  ExitVal: Integer          ;
begin
  try
    if not NodeIsDocumentable(FTree.Selected) then Exit;
    ND:= TStructureNodeData(FTree.Selected.Data);
    if FCurrentFile = '' then Exit;
    Db:= ResolveDbForFile; { same DB resolver Find Usages / Fix-all use }
    if Db = '' then
    begin
      DLT('autodoc', 'Document it: no index DB for ' + FCurrentFile);
      Exit;
    end;
    Cmd:= Format('"%s" document --qname "%s" --db "%s" --apply', [ResolveExePath, ND.QName, Db]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 60000);
    DLT('autodoc', Format('Document it %s -> exit=%d', [ND.QName, ExitVal]));
    if ExitVal = 0 then ReloadCurrentFileBuffer
    else DLT('autodoc', 'Document it non-zero exit; output: ' + Copy(Output, 1, 400));
  except
    on E: Exception do DLT('autodoc', 'DocumentItClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ ---- Task 8 enum-helper: right-click Create helper class ---- }

{ Resolves the enum qname a right-clicked node targets:
  - a skEnum node targets itself (ND.QName is already the enum's qname).
  - a skEnumValue node targets its PARENT enum. The tree is flat (Code
    Elements children are siblings, not nested under their declaring type --
    see BuildTree), so there is no tree-parent link to walk; instead the value's
    own QName carries the enum name as its second-to-last dotted segment (the
    outline emits 'Unit.TEnum.Value' for enum values vs 'Unit.TEnum' for the
    enum itself -- mirrors DRagLint.Parser.Delphi13's QName + '.' + ValName
    emission). Stripping the trailing '.<Value>' segment recovers 'Unit.TEnum'.
  Returns '' for any other node shape (including a malformed QName with no dot,
  which cannot be a nested enum value). }
function TDragLintStructureForm.EnumQNameForNode(ANode: TTreeNode): string;
var
  ND     : TStructureNodeData;
  DotPos : Integer           ;
begin
  Result:= '';
  if (ANode = nil) or (ANode.Data = nil) then Exit;
  ND:= TStructureNodeData(ANode.Data);
  if ND.Kind = skEnum then Exit(ND.QName);
  if ND.Kind = skEnumValue then
  begin
    DotPos:= ND.QName.LastDelimiter('.');
    if DotPos > 0 then Result:= Copy(ND.QName, 1, DotPos - 1);
  end;
end;

{ An enum-helper target is a skEnum node, or a skEnumValue node whose parent
  enum resolves (EnumQNameForNode <> ''), AND that enum has no existing helper
  yet. The existing-helper check shells out to the read-only query verb:
    drag-lint helpers-of <qname> --json --db <projDb>
  which per its own doc-comment exits 0 with an empty "[]" for "no helper
  found" (Task 5 designed the verb this way specifically so callers here don't
  have to distinguish "no helper" from "query failed" by exit code alone --
  we still treat any non-zero exit or unparseable output as "not a target", the
  same safe-degradation the AutoFix EnsureFixableRules cache uses). Unlike
  EnsureFixableRules this is NOT cached: helpers-of is a cheap single-symbol
  lookup (not a whole-rules-catalog fetch), and the answer can change between
  popups as the user runs 'Create helper class' on other enums, so a stale
  cached "no helper" would wrongly re-enable the item. }
function TDragLintStructureForm.NodeIsEnumHelperTarget(ANode: TTreeNode): Boolean;
var
  QName  : string     ;
  Db     : string     ;
  Cmd    : string     ;
  Output : string     ;
  ExitVal: Integer    ;
  Arr    : TJSONValue ;
begin
  Result:= False;
  QName:= EnumQNameForNode(ANode);
  if QName = '' then Exit;
  Db:= ResolveDbForFile; { same DB resolver Find Usages / Fix-all / Document it use }
  if Db = '' then Exit;
  try
    Cmd:= Format('"%s" helpers-of "%s" --json --db "%s"', [ResolveExePath, QName, Db]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 15000);
    if ExitVal <> 0 then Exit;
    Arr:= TJSONObject.ParseJSONValue(Output);
    if Arr = nil then Exit;
    try
      Result:= (Arr is TJSONArray) and (TJSONArray(Arr).Count = 0);
    finally
      Arr.Free;
    end;
  except
    on E: Exception do
    begin
      DLT('enumhelper', 'NodeIsEnumHelperTarget failed: ' + E.ClassName + ': ' + E.Message);
      Result:= False;
    end;
  end;
end; // function

{ 'Create helper class' -- generate a Byte-family record helper for the
  targeted enum via the CLI:
    drag-lint create-enum-helper --qname <TEnum> --db <projDb> --apply
  Same --db reasoning as 'Document it' (qname-driven, resolves through the
  index, so --db not --file). --apply writes the source file (+ a .bak) on
  disk; DoCreateEnumHelper exits 0 only when Action=ehaBuilt (a refusal, e.g.
  helper-already-exists or no-impl-section, exits 1 and makes no edit), so the
  same "ExitVal = 0 -> reload" gate DocumentItClick uses is exactly correct
  here too. Wrapped in try/except -> DLT so a plugin fault never reaches the
  IDE message loop. }
procedure TDragLintStructureForm.CreateEnumHelperClick(Sender: TObject);
var
  QName  : string ;
  Cmd    : string ;
  Output : string ;
  Db     : string ;
  ExitVal: Integer;
begin
  try
    QName:= EnumQNameForNode(FTree.Selected);
    if QName = '' then Exit;
    if FCurrentFile = '' then Exit;
    Db:= ResolveDbForFile; { same DB resolver Find Usages / Fix-all / Document it use }
    if Db = '' then
    begin
      DLT('enumhelper', 'Create helper class: no index DB for ' + FCurrentFile);
      Exit;
    end;
    Cmd:= Format('"%s" create-enum-helper --qname "%s" --db "%s" --apply', [ResolveExePath, QName, Db]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 60000);
    DLT('enumhelper', Format('Create helper class %s -> exit=%d', [QName, ExitVal]));
    if ExitVal = 0 then ReloadCurrentFileBuffer
    else DLT('enumhelper', 'Create helper class non-zero exit; output: ' + Copy(Output, 1, 400));
  except
    on E: Exception do DLT('enumhelper', 'CreateEnumHelperClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ ---- ADF T10 AutoDocument: right-click Document unit / Document project ---- }

{ Returns the absolute path of the .dproj owning the currently-active project,
  or '' if none is open. Local ToolsAPI-only helper (mirrors the identically
  shaped resolvers in DragLint.Plugin.Editor / DbResolver / LintOptionsFrame --
  each of those keeps its own copy rather than exporting one, since the walk is
  three ToolsAPI calls and self-contained try/except is cheap to duplicate). }
function TDragLintStructureForm.GetActiveProjectFilePath: string;
var
  MS        : IOTAModuleServices;
  ProjGroup : IOTAProjectGroup  ;
  ActiveProj: IOTAProject       ;
begin
  Result:= '';
  try
    if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
    if MS = nil then Exit;
    ProjGroup:= MS.MainProjectGroup;
    if ProjGroup = nil then Exit;
    ActiveProj:= ProjGroup.ActiveProject;
    if ActiveProj = nil then Exit;
    Result:= ActiveProj.FileName;
  except
    Result:= '';
  end;
end;

{ 'Document unit' -- generate/repair DocInsight comments for every public decl
  in the ACTIVE EDITOR FILE (not just the one clicked node) via the CLI:
    drag-lint document --unit <FCurrentFile> --db <projDb> --apply
  Same --db reasoning as 'Document it' (document --unit still resolves through
  the index, so it needs --db, not just the file path). --apply writes the
  source file (+ .bak) directly; on exit 0 reload the buffer so the new
  comments appear and the Diagnostics/Code Elements tree refreshes. }
procedure TDragLintStructureForm.DocumentUnitClick(Sender: TObject);
var
  Cmd    : string ;
  Output : string ;
  Db     : string ;
  ExitVal: Integer;
begin
  try
    if FCurrentFile = '' then Exit;
    Db:= ResolveDbForFile; { same DB resolver Find Usages / Fix-all / Document it use }
    if Db = '' then
    begin
      DLT('autodoc', 'Document unit: no index DB for ' + FCurrentFile);
      Exit;
    end;
    Cmd:= Format('"%s" document --unit "%s" --db "%s" --apply', [ResolveExePath, FCurrentFile, Db]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 120000);
    DLT('autodoc', Format('Document unit %s -> exit=%d', [ExtractFileName(FCurrentFile), ExitVal]));
    if ExitVal = 0 then ReloadCurrentFileBuffer
    else DLT('autodoc', 'Document unit non-zero exit; output: ' + Copy(Output, 1, 400));
  except
    on E: Exception do DLT('autodoc', 'DocumentUnitClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ 'Document project' -- generate/repair DocInsight comments for every public
  decl across the ACTIVE PROJECT's compile closure via the CLI:
    drag-lint document --project <activeDproj> --db <projDb> --apply
  The project path comes from GetActiveProjectFilePath (the true active .dproj,
  NOT ResolveDbForFile's file-owning-project walk); the --db is still the same
  shared resolver every other spawn site uses. Only the CURRENT file's buffer is
  reloaded (mirrors 'Fix all in project' -- other open files stay stale in their
  editor buffers until reopened; documented in the smoke notes). }
procedure TDragLintStructureForm.DocumentProjectClick(Sender: TObject);
var
  ProjFile: string ;
  Db      : string ;
  Cmd     : string ;
  Output  : string ;
  ExitVal : Integer;
begin
  try
    ProjFile:= GetActiveProjectFilePath;
    if ProjFile = '' then
    begin
      DLT('autodoc', 'Document project: no active project');
      Exit;
    end;
    Db:= ResolveDbForFile;
    if Db = '' then
    begin
      DLT('autodoc', 'Document project: no index DB for ' + ProjFile);
      Exit;
    end;
    Cmd:= Format('"%s" document --project "%s" --db "%s" --apply', [ResolveExePath, ProjFile, Db]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 600000);
    DLT('autodoc', Format('Document project %s -> exit=%d', [ExtractFileName(ProjFile), ExitVal]));
    if ExitVal = 0 then ReloadCurrentFileBuffer
    else DLT('autodoc', 'Document project non-zero exit; output: ' + Copy(Output, 1, 400));
  except
    on E: Exception do DLT('autodoc', 'DocumentProjectClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ 'Fix all in unit' -- apply every fixable finding in the current file:
  drag-lint lint --file <FCurrentFile> --fix --apply.
  With any naming finding in the unit, previewed first with --fix-naming and always
  confirmed before the --apply run (EnqueueRenamePreviewJob). }
procedure TDragLintStructureForm.FixAllInUnitClick(Sender: TObject);
const
  CFixUnitTimeoutMs = 120000;
begin
  try
    if FCurrentFile = '' then Exit;
    { --db: the naming fixes need the index to find every use, and without it
      the engine neither applies an opted-in one nor says which are opted out. }
    var Db: string:= ResolveDbForFile;
    var Cmd: string:= Format('"%s" lint --file "%s" --fix', [ResolveExePath, FCurrentFile])
        + (if Db <> '' then Format(' --db "%s"', [Db]) else '');
    { any naming finding in the unit may rename across projects: preview first }
    var HasNaming: Boolean:= False;
    for var D: TDragLintDiagnostic in FDiags do
      if IsNamingFixRule(D.Code) then
      begin
        HasNaming:= True;
        Break;
      end;
    { --fix-naming: the naming fixes are consented to here, by the confirm that
      always follows the preview, not by an "autofix" entry in the config }
    var Project: string:= if Db <> '' then ChangeFileExt(ExtractFileName(Db), '')
                          else ChangeFileExt(ExtractFileName(GetActiveProjectFilePath), '');
    if HasNaming then
      EnqueueRenamePreviewJob(FCurrentFile, 'Fix all in unit', Cmd + ' --fix-naming', Cmd + ' --fix-naming --apply', Project, CFixUnitTimeoutMs)
    else RunFixJob('Fix all in unit', Cmd + ' --apply', CFixUnitTimeoutMs);
  except
    on E: Exception do DLT('autofix', 'FixAllInUnitClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ 'Fix all in project' -- apply every fixable finding across the indexed project:
  drag-lint lint-all --db <projDb> --fix --apply, where <projDb> is resolved the
  same way the outline uses (ResolveDbForFile = first/highest-priority index DB).
  Only the CURRENT file's buffer is reloaded here; OTHER edited files stay stale
  in their editor buffers until re-opened (documented in the smoke notes) --
  sweeping every open module is intentionally out of scope for this chunk. }
procedure TDragLintStructureForm.FixAllInProjectClick(Sender: TObject);
const
  CFixProjectTimeoutMs = 600000;
var
  Db: string;
begin
  try
    Db:= ResolveDbForFile;
    if Db = '' then
    begin
      DLT('autofix', 'Fix all in project: no index DB resolved -- aborted');
      SetDragLintNote('Fix all in project: no index DB for this file -- nothing run');
      Exit;
    end;
    RunFixJob('Fix all in project',
      Format('"%s" lint-all --db "%s" --fix --apply', [ResolveExePath, Db]),
      CFixProjectTimeoutMs);
  except
    on E: Exception do DLT('autofix', 'FixAllInProjectClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ ---- public factory ---- }

procedure TDragLintStructureForm.RefreshActive;
begin
  RefreshForFile(GetActiveFilePath);
end;

procedure TDragLintStructureForm.RefreshDiagnosticsOnly;
begin
  if FCurrentFile = '' then
  begin
    FCurrentFile:= GetActiveFilePath;
    if FCurrentFile = '' then Exit;
  end;
  { re-read just the diagnostics (cheap) and rebuild the tree using the already
    cached symbols (BuildTree reads FSyms; no engine shell-out here). }
  FDiags:= Cache.GetForFile(FCurrentFile);
  DLT('structure', Format('RefreshDiagnosticsOnly %s -> %d diag(s)', [ExtractFileName(FCurrentFile), Length(FDiags)]));
  BuildTree(FSearch.Text);
end;

{ v0.42: embedded-in-a-tab factory. The form is created child-style (no border,
  fsNormal) and parented into AParent (a dock-panel TTabSheet), so the same
  tree + refresh logic serves both the standalone window and the dock tab.

  Batch D / Task 9: the constructor wires OnActivate := FormActivate for the
  STANDALONE window (so it self-refreshes when the user alt-tabs back to it).
  That is still a real TForm registered with Screen/Application even once
  embedded (TDragLintStructureForm = class(TForm), reparented rather than a
  true TFrame), so it keeps receiving CM_ACTIVATE whenever the IDE app
  activates -- e.g. on any tab switch, not just a Structure-tab switch. This
  is the one code-level anomaly distinguishing Structure's embed from its
  Search/Usages siblings (neither wires OnActivate), and the leading suspect
  for the dock's host window self-selecting to the front on tab switches. The
  dock's own timer (TDragLintDockFrame.HandleWatchTimer, 400ms) and
  HandlePageChange already drive RefreshActive/RefreshForFile for the
  embedded case, so FormActivate is redundant here -- drop it so the embedded
  instance carries no activation wiring at all. }
function CreateEmbeddedStructure(AOwner: TComponent; AParent: TWinControl): TForm;
var
  F: TDragLintStructureForm;
begin
  F:= TDragLintStructureForm.Create(AOwner);
  F.BorderStyle:= bsNone;
  F.FormStyle  := fsNormal;
  F.OnActivate := nil; { v0.96 Batch D Task 9: see comment above -- embedded tab must not react to app-level activation }
  F.Align      := alClient;
  F.Parent     := AParent;
  F.Visible    := True;
  F.RefreshActive;
  Result:= F;
end;

procedure RefreshEmbeddedStructure(AForm: TForm);
begin
  if AForm is TDragLintStructureForm then TDragLintStructureForm(AForm).RefreshActive;
end;

procedure RefreshEmbeddedStructureDiagnostics(AForm: TForm);
begin
  if AForm is TDragLintStructureForm then TDragLintStructureForm(AForm).RefreshDiagnosticsOnly;
end;

procedure ScrollEmbeddedStructureToDiagnostics(AForm: TForm);
begin
  if (AForm is TDragLintStructureForm) and TDragLintStructureForm(AForm).HasDiagnostics then TDragLintStructureForm(AForm).ScrollToDiagnostics;
end;

function SelectEmbeddedStructureDiagnosticForLine(AForm: TForm; ALine: Integer): Boolean;
begin
  Result:= (AForm is TDragLintStructureForm)
           and TDragLintStructureForm(AForm).SelectDiagnosticForLine(ALine);
end;

procedure ShowDragLintStructure;
begin
  if GStructureForm = nil then GStructureForm:= TDragLintStructureForm.Create(nil);

  if not GStructureForm.Visible then GStructureForm.Show;

  GStructureForm.RefreshForFile( (GStructureForm as TDragLintStructureForm).GetActiveFilePath);
  GStructureForm.BringToFront;
end;

procedure HideDragLintStructure;
begin
  if GStructureForm <> nil then
  begin
    GStructureForm.Hide;
    FreeAndNil(GStructureForm);
  end;
end;

initialization

finalization
if GStructureForm <> nil then FreeAndNil(GStructureForm);
FreeAndNil(GLiveStructureForms);

end.
