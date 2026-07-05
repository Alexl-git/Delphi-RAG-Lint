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
  , DragLint.Plugin.Editor { v0.88 AutoFix: RunAndCaptureStdout for the fix verbs }
  ;

{ ---- TStructureNodeData: stores line info in tree node.Data ---- }

type
  TStructureNodeData = class
    Line : Integer    ; { 1-based declaration line; 0 = no navigation }
    Name : string     ; { symbol name -- for Find Usages }
    QName: string     ; { qualified name -- for Go to Implementation }
    Kind : TSymbolKind; { so we only offer impl/usages on proc-likes }
    Code : string     ; { v0.88 AutoFix: rule-id on a diagnostic node ('' on symbol nodes) }
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
      FRootDiag       : TTreeNode   ; { the current 'Diagnostics (N)' root, for node discrimination }
      FFixableRules   : TStringList ; { lower-case rule-ids with a registered fix; nil until first fetched }
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
      procedure CopyDiagnosticsClick   (Sender: TObject);
      { v0.88 AutoFix handlers + helpers. }
      procedure EnsureFixableRules;
      function  NodeIsDiagnosticsRoot(ANode: TTreeNode): Boolean;
      function  NodeIsFixableFinding (ANode: TTreeNode): Boolean;
      procedure ReloadCurrentFileBuffer;
      procedure PopupPopup             (Sender: TObject);
      procedure FixItClick             (Sender: TObject);
      procedure FixAllInUnitClick      (Sender: TObject);
      procedure FixAllInProjectClick   (Sender: TObject);
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
  end;

var
  GStructureForm: TDragLintStructureForm = nil;

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

function ResolveDbForFile: string;
{ v0.42: the Structure outline must query the SAME database the rest of the
  plugin uses for the active file. Reuse the shared DbResolver and take the
  primary (first, highest-priority) DB. Empty => let the exe self-resolve. }
var
  Dbs: TArray<string>;
begin
  Result:= '';
  try
    Dbs:= ResolveActiveIndexDbs(LoadSettings);
    if Length(Dbs) > 0 then Result:= Dbs[0];
  except
    Result:= '';
  end;
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

  { v0.43: right-click navigation menu. Single/double-click stays as the
    primary "go to declaration"; the secondary actions live here. }
  FPopup:= TPopupMenu.Create(Self);
  AddPopupItem(FPopup, 'Go to &Declaration'          , GoToDeclarationClick   );
  AddPopupItem(FPopup, 'Go to &Implementation (body)', GoToImplementationClick);
  AddPopupItem(FPopup, 'Find &Usages'                , FindUsagesClick        );
  AddPopupItem(FPopup, '-'                           , nil                    ); { separator }
  AddPopupItem(FPopup, '&Copy All Diagnostics'       , CopyDiagnosticsClick  );
  { v0.88 AutoFix: run the CLI fix verbs on the clicked node. Enablement is set
    per-popup by PopupPopup, so we keep references to the three items. }
  AddPopupItem(FPopup, '-'                           , nil                    ); { separator }
  AddPopupItem(FPopup, '&Fix it'                     , FixItClick             );
  AddPopupItem(FPopup, 'Fix all in &unit'            , FixAllInUnitClick      );
  AddPopupItem(FPopup, 'Fix all in &project'         , FixAllInProjectClick   );
  FItemFixIt     := FPopup.Items[FPopup.Items.Count - 3];
  FItemFixUnit   := FPopup.Items[FPopup.Items.Count - 2];
  FItemFixProject:= FPopup.Items[FPopup.Items.Count - 1];
  FPopup.OnPopup := PopupPopup;
  FTree.PopupMenu:= FPopup;
end; // constructor

procedure TDragLintStructureForm.FormDestroy(Sender: TObject);
begin
  ClearNodeData;
  FreeAndNil(FFixableRules); { v0.88 AutoFix: release the cached fixable-rule set }
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
  DbPath := ResolveDbForFile;
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
      untouched (CopyDiagnosticsClick and RefreshDiagnosticsOnly both still
      want the original cache order). TArray.Sort is not guaranteed stable, so
      we sort an INDEX array instead, comparing by Line and breaking ties by
      the original index -- that tie-break makes the ordering stable (diags on
      the same line keep their original relative order) without depending on
      the sort algorithm's own stability. }
    SetLength(DiagOrder, Length(FDiags));
    for i:= 0 to High(DiagOrder) do DiagOrder[i]:= i;
    TArray.Sort<Integer>(DiagOrder, TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result:= FDiags[A].Line - FDiags[B].Line;
        if Result = 0 then Result:= A - B;
      end));

    RootDiag:= FTree.Items.Add(nil, Format('Diagnostics (%d)', [Length(FDiags)]));
    RootDiag.Data:= nil;
    FRootDiag:= RootDiag; { v0.88 AutoFix: remember the root for node discrimination }
    for i:= 0 to High(DiagOrder) do
    begin
      D:= FDiags[DiagOrder[i]];
      ND:= TStructureNodeData.Create;
      ND.Line:= D.Line + 1;
      ND.Code:= D.Code; { v0.88 AutoFix: rule-id so the popup can offer a per-finding fix }
      Node:= FTree.Items.AddChild(RootDiag, SeverityPrefix(D.Severity) + Format('(%d) ', [D.Line + 1]) + D.Message);
      Node.Data:= ND;
    end;

    { --- Code Elements root (filtered by AFilter) --- }
    Shown:= 0;
    RootSym:= FTree.Items.Add(nil, ''); { caption set after we count }
    RootSym.Data:= nil;
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

procedure TDragLintStructureForm.BtnRefreshClick(Sender: TObject);
begin
  RefreshForFile(GetActiveFilePath);
end;

{ v0.47: scroll the tree so the Diagnostics section is at the top of the view
  and select its first message. After a refresh the tree is scrolled to Code
  Elements, leaving Diagnostics above the visible area. Diagnostics is always the
  first root node (added first in BuildTree). }
function TDragLintStructureForm.HasDiagnostics: Boolean;
begin
  Result:= Length(FDiags) > 0;
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
    if Root.getFirstChild <> nil then FTree.Selected:= Root.getFirstChild { focus the top message line }
    else FTree.Selected:= Root; { no messages -> just the header }
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
    if N <> nil then FTree.Selected:= N;
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

procedure TDragLintStructureForm.CopyDiagnosticsClick(Sender: TObject);
var
  SB: TStringBuilder;
  D : TDragLintDiagnostic;
  Line: string;
begin
  if Length(FDiags) = 0 then Exit;
  SB:= TStringBuilder.Create;
  try
    if FCurrentFile <> '' then
      SB.AppendLine(FCurrentFile);
    for D in FDiags do
    begin
      Line:= SeverityPrefix(D.Severity)
           + Format('(%d:%d) ', [D.Line + 1, D.StartCol + 1])
           + D.Message;
      if D.Code <> '' then Line:= Line + '  [' + D.Code + ']';
      SB.AppendLine(Line);
    end;
    Clipboard.AsText:= SB.ToString;
  finally
    SB.Free;
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
begin
  if FFixableRules <> nil then Exit;
  FFixableRules:= TStringList.Create;
  FFixableRules.CaseSensitive:= False;
  FFixableRules.Duplicates   := dupIgnore;
  FFixableRules.Sorted       := True;
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
  EnsureFixableRules;
  Result:= (FFixableRules <> nil) and (FFixableRules.IndexOf(LowerCase(ND.Code)) >= 0);
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
  - Diagnostics root  -> 'Fix all in unit' + 'Fix all in project'; 'Fix it' off.
  - fixable finding    -> 'Fix it'; both 'Fix all' off.
  - anything else      -> all three disabled (nav items are untouched). }
procedure TDragLintStructureForm.PopupPopup(Sender: TObject);
var
  Node    : TTreeNode;
  IsRoot  : Boolean  ;
  IsFinding: Boolean ;
begin
  Node     := FTree.Selected;
  IsRoot   := NodeIsDiagnosticsRoot(Node);
  IsFinding:= NodeIsFixableFinding (Node);
  FItemFixIt     .Enabled:= IsFinding;
  FItemFixUnit   .Enabled:= IsRoot   ;
  FItemFixProject.Enabled:= IsRoot   ;
end;

{ 'Fix it' -- apply the single fixable finding under the cursor:
  drag-lint lint --file <FCurrentFile> --fix --fix-line <L> --fix-rule <id> --apply
  On exit 0, reload the buffer + refresh the tree; otherwise log and do nothing. }
procedure TDragLintStructureForm.FixItClick(Sender: TObject);
var
  ND     : TStructureNodeData;
  Cmd    : string           ;
  Output : string           ;
  ExitVal: Integer          ;
begin
  try
    if not NodeIsFixableFinding(FTree.Selected) then Exit;
    ND:= TStructureNodeData(FTree.Selected.Data);
    if FCurrentFile = '' then Exit;
    Cmd:= Format('"%s" lint --file "%s" --fix --fix-line %d --fix-rule "%s" --apply',
      [ResolveExePath, FCurrentFile, ND.Line, ND.Code]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 60000);
    DLT('autofix', Format('Fix it %s line %d rule %s -> exit=%d', [ExtractFileName(FCurrentFile), ND.Line, ND.Code, ExitVal]));
    if ExitVal = 0 then ReloadCurrentFileBuffer
    else DLT('autofix', 'Fix it non-zero exit; output: ' + Copy(Output, 1, 400));
  except
    on E: Exception do DLT('autofix', 'FixItClick failed: ' + E.ClassName + ': ' + E.Message);
  end;
end; // procedure

{ 'Fix all in unit' -- apply every fixable finding in the current file:
  drag-lint lint --file <FCurrentFile> --fix --apply. }
procedure TDragLintStructureForm.FixAllInUnitClick(Sender: TObject);
var
  Cmd    : string ;
  Output : string ;
  ExitVal: Integer;
begin
  try
    if FCurrentFile = '' then Exit;
    Cmd:= Format('"%s" lint --file "%s" --fix --apply', [ResolveExePath, FCurrentFile]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 120000);
    DLT('autofix', Format('Fix all in unit %s -> exit=%d', [ExtractFileName(FCurrentFile), ExitVal]));
    if ExitVal = 0 then ReloadCurrentFileBuffer
    else DLT('autofix', 'Fix all in unit non-zero exit; output: ' + Copy(Output, 1, 400));
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
var
  Db     : string ;
  Cmd    : string ;
  Output : string ;
  ExitVal: Integer;
begin
  try
    Db:= ResolveDbForFile;
    if Db = '' then
    begin
      DLT('autofix', 'Fix all in project: no index DB resolved -- aborted');
      Exit;
    end;
    Cmd:= Format('"%s" lint-all --db "%s" --fix --apply', [ResolveExePath, Db]);
    ExitVal:= RunAndCaptureStdout(Cmd, Output, 600000);
    DLT('autofix', Format('Fix all in project db=%s -> exit=%d', [ExtractFileName(Db), ExitVal]));
    if ExitVal = 0 then ReloadCurrentFileBuffer
    else DLT('autofix', 'Fix all in project non-zero exit; output: ' + Copy(Output, 1, 400));
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
  tree + refresh logic serves both the standalone window and the dock tab. }
function CreateEmbeddedStructure(AOwner: TComponent; AParent: TWinControl): TForm;
var
  F: TDragLintStructureForm;
begin
  F:= TDragLintStructureForm.Create(AOwner);
  F.BorderStyle:= bsNone;
  F.FormStyle  := fsNormal;
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

end.
