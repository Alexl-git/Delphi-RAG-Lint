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
  ConvRules.Model, ConvRules.Casts, ConvRules.Engine;

type
  TConvRulesForm = class(TForm)
  private
    FBook     : TRuleBook;
    FEngine   : TEngineAdapter;
    FFilePath : string;
    FActiveHdr: Integer;              // index of the selected #convert node (-1 none)
    FFromTree : TProptree;            // active F property tree
    FToTree   : TProptree;            // active T property tree

    FAllClasses: TArray<string>;      // all indexed component classes (for pickers)

    // toolbar
    FPanelTop : TPanel;
    FLblFile  : TLabel;
    FLblStatus: TLabel;
    // new-conversion row
    FCbFrom   : TComboBox;
    FCbTo     : TComboBox;
    // rules library
    FRules    : TListView;
    // grid
    FGrid     : TStringGrid;          // col0 From, col1 To-assigned, col2 cast
    FPool     : TListBox;             // unassigned T pool
    FPoolFind : TEdit;
    FBtnAssign: TButton;
    FBtnUnasgn: TButton;
    FBtnAuto  : TButton;
    // directives / raw
    FTabs     : TPageControl;
    FRaw      : TMemo;

    procedure BuildUI;
    procedure FormCloseHandler(Sender: TObject; var Action: TCloseAction);
    procedure DoLoad(Sender: TObject);
    procedure DoSave(Sender: TObject);
    procedure DoValidate(Sender: TObject);
    procedure DoNewConversion(Sender: TObject);
    procedure DoAutoMatch(Sender: TObject);
    procedure RefreshRulesList;
    procedure RulesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure LoadGridForBlock(AHdrIdx: Integer);
    procedure RefreshPool;
    procedure DoAssign(Sender: TObject);
    procedure DoUnassign(Sender: TObject);
    procedure PoolFilter(Sender: TObject);
    procedure SyncRawFromModel;
    procedure SetStatus(const S: string);
    procedure SetError(const S: string);
    procedure LoadAllClasses;
    procedure CbLoadClasses(Sender: TObject);
    procedure AssignLink(const AFromPath, AToPath, AFromType, AToType: string);
    function  BlockPercent(AHdrIdx: Integer): Integer;
    function  ActiveLinks: TArray<TRuleNode>;
    function  FindLinkForFrom(const AFromPath: string): TRuleNode;
    function  LeafType(const ATree: TProptree; const APath: string): string;
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
  GEditorDbs: TArray<string>;

implementation

uses
  System.StrUtils, System.Math;

{ ---- helpers ---- }

function BackupPath(const APath: string): string;
var
  n: Integer;
begin
  // <file>.rules.bak, then .bak.2, .bak.3 ... so a short history is kept.
  Result := APath + '.bak';
  n := 2;
  while TFile.Exists(Result) do
  begin
    Result := APath + '.bak.' + IntToStr(n);
    Inc(n);
    if n > 99 then Break; // cap
  end;
end;

{ TConvRulesForm }

constructor TConvRulesForm.Create(AOwner: TComponent);
begin
  // Route the standard constructor to CreateNew (no DFM); GlobalNameSpace-free.
  inherited CreateNew(AOwner);
  FBook := TRuleBook.Create;
  FEngine := TEngineAdapter.Create(GEditorExe, GEditorDbs);
  FActiveHdr := -1;
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
  TabRules, TabRaw: TTabSheet;
  BtnLoad, BtnSave, BtnValidate: TButton;
begin
  Caption := 'ConvRulesEditor -- conversion rule-book editor';
  Width := 1100; Height := 720;
  Position := poScreenCenter;

  // --- top toolbar (two rows: file actions, then new-conversion builder) ---
  FPanelTop := TPanel.Create(Self);
  FPanelTop.Parent := Self; FPanelTop.Align := alTop; FPanelTop.Height := 92;
  FPanelTop.BevelOuter := bvNone;

  BtnLoad := TButton.Create(Self);
  BtnLoad.Parent := FPanelTop; BtnLoad.SetBounds(8, 6, 90, 25);
  BtnLoad.Caption := 'Open...'; BtnLoad.OnClick := DoLoad;

  BtnSave := TButton.Create(Self);
  BtnSave.Parent := FPanelTop; BtnSave.SetBounds(104, 6, 90, 25);
  BtnSave.Caption := 'Save'; BtnSave.OnClick := DoSave;

  BtnValidate := TButton.Create(Self);
  BtnValidate.Parent := FPanelTop; BtnValidate.SetBounds(200, 6, 90, 25);
  BtnValidate.Caption := 'Validate'; BtnValidate.OnClick := DoValidate;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := FPanelTop; FLblStatus.SetBounds(300, 11, 780, 15);

  // --- new-conversion builder row: From [v]  ->  To [v]  [New Conversion] ---
  var LblFrom: TLabel := TLabel.Create(Self);
  LblFrom.Parent := FPanelTop; LblFrom.SetBounds(8, 42, 34, 15); LblFrom.Caption := 'From:';
  FCbFrom := TComboBox.Create(Self);
  FCbFrom.Parent := FPanelTop; FCbFrom.SetBounds(44, 39, 300, 23);
  FCbFrom.AutoComplete := True; FCbFrom.DropDownCount := 20;
  FCbFrom.Hint := 'Type to search all known component classes';
  FCbFrom.ShowHint := True; FCbFrom.OnDropDown := CbLoadClasses;

  var LblArrow: TLabel := TLabel.Create(Self);
  LblArrow.Parent := FPanelTop; LblArrow.SetBounds(350, 42, 20, 15); LblArrow.Caption := '->';
  var LblTo: TLabel := TLabel.Create(Self);
  LblTo.Parent := FPanelTop; LblTo.SetBounds(374, 42, 22, 15); LblTo.Caption := 'To:';
  FCbTo := TComboBox.Create(Self);
  FCbTo.Parent := FPanelTop; FCbTo.SetBounds(398, 39, 300, 23);
  FCbTo.AutoComplete := True; FCbTo.DropDownCount := 20;
  FCbTo.Hint := 'Type to search all known component classes';
  FCbTo.ShowHint := True; FCbTo.OnDropDown := CbLoadClasses;

  var BtnNew: TButton := TButton.Create(Self);
  BtnNew.Parent := FPanelTop; BtnNew.SetBounds(706, 38, 130, 25);
  BtnNew.Caption := '+ New Conversion'; BtnNew.OnClick := DoNewConversion;

  FLblFile := TLabel.Create(Self);
  FLblFile.Parent := FPanelTop; FLblFile.SetBounds(8, 70, 1080, 15);
  FLblFile.Caption := '(no file)';

  // --- left: rules library + tabs ---
  LeftPanel := TPanel.Create(Self);
  LeftPanel.Parent := Self; LeftPanel.Align := alLeft; LeftPanel.Width := 380;
  LeftPanel.BevelOuter := bvNone;

  FTabs := TPageControl.Create(Self);
  FTabs.Parent := LeftPanel; FTabs.Align := alClient;

  TabRules := TTabSheet.Create(FTabs); TabRules.PageControl := FTabs;
  TabRules.Caption := 'Rules Library';
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

  Split1 := TSplitter.Create(Self);
  Split1.Parent := Self; Split1.Align := alLeft; Split1.Left := LeftPanel.Width + 1;
  Split1.Width := 4;

  // --- right: 3-column grid (From | To-assigned | cast) + pool ---
  PoolPanel := TPanel.Create(Self);
  PoolPanel.Parent := Self; PoolPanel.Align := alRight; PoolPanel.Width := 280;
  PoolPanel.BevelOuter := bvNone;

  FBtnAuto := TButton.Create(Self);
  FBtnAuto.Parent := PoolPanel; FBtnAuto.SetBounds(6, 6, 268, 27);
  FBtnAuto.Caption := 'Auto-Match unambiguous properties';
  FBtnAuto.OnClick := DoAutoMatch;

  var LblPool: TLabel := TLabel.Create(Self);
  LblPool.Parent := PoolPanel; LblPool.SetBounds(6, 40, 260, 15);
  LblPool.Caption := 'To (unassigned pool) -- search:';

  FPoolFind := TEdit.Create(Self);
  FPoolFind.Parent := PoolPanel; FPoolFind.SetBounds(6, 58, 268, 23);
  FPoolFind.OnChange := PoolFilter;

  FBtnAssign := TButton.Create(Self);
  FBtnAssign.Parent := PoolPanel; FBtnAssign.SetBounds(6, 86, 130, 25);
  FBtnAssign.Caption := '<- Assign to From'; FBtnAssign.OnClick := DoAssign;

  FBtnUnasgn := TButton.Create(Self);
  FBtnUnasgn.Parent := PoolPanel; FBtnUnasgn.SetBounds(144, 86, 130, 25);
  FBtnUnasgn.Caption := 'Unassign ->'; FBtnUnasgn.OnClick := DoUnassign;

  FPool := TListBox.Create(Self);
  FPool.Parent := PoolPanel; FPool.SetBounds(6, 116, 268, 526);
  FPool.Anchors := [akLeft, akTop, akRight, akBottom];

  Split2 := TSplitter.Create(Self);
  Split2.Parent := Self; Split2.Align := alRight; Split2.Width := 4;

  GridPanel := TPanel.Create(Self);
  GridPanel.Parent := Self; GridPanel.Align := alClient; GridPanel.BevelOuter := bvNone;

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := GridPanel; FGrid.Align := alClient;
  // RowCount must stay > FixedRows: start at 2 (header + one blank data row).
  FGrid.ColCount := 3; FGrid.RowCount := 2; FGrid.FixedRows := 1; FGrid.FixedCols := 0;
  FGrid.Options := FGrid.Options + [goRowSelect, goVertLine, goHorzLine];
  FGrid.DefaultRowHeight := 20;
  FGrid.Cells[0, 0] := 'From property (: type)';
  FGrid.Cells[1, 0] := 'To (assigned)';
  FGrid.Cells[2, 0] := 'cast';
  FGrid.ColWidths[0] := 250; FGrid.ColWidths[1] := 250; FGrid.ColWidths[2] := 90;
end;

procedure TConvRulesForm.SetStatus(const S: string);
begin
  FLblStatus.Font.Color := clWindowText;
  FLblStatus.Font.Style := [];
  FLblStatus.Caption := S;
end;

{ Show a message in RED bold -- for blocked assignments and errors. }
procedure TConvRulesForm.SetError(const S: string);
begin
  FLblStatus.Font.Color := clRed;
  FLblStatus.Font.Style := [fsBold];
  FLblStatus.Caption := S;
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

{ Load every indexed component class name into the From/To pickers, once. Uses
  the engine's workspace-symbols LSP-style query via drag-lint; falls back to a
  small built-in list if the query yields nothing (so the pickers are never
  empty and the New Conversion flow always works). }
procedure TConvRulesForm.LoadAllClasses;
var
  Names: TArray<string>;
  Err  : string;
begin
  if Length(FAllClasses) > 0 then Exit; // already loaded
  if not FEngine.ListComponentClasses(Names, Err) or (Length(Names) = 0) then
    Names := ['Vcl.StdCtrls.TEdit', 'Vcl.StdCtrls.TMemo', 'Vcl.StdCtrls.TButton',
              'Vcl.StdCtrls.TLabel', 'Vcl.StdCtrls.TCheckBox', 'Vcl.Graphics.TFont'];
  FAllClasses := Names;
  FCbFrom.Items.BeginUpdate; FCbTo.Items.BeginUpdate;
  try
    FCbFrom.Items.Clear; FCbTo.Items.Clear;
    for var N in FAllClasses do
    begin
      FCbFrom.Items.Add(N);
      FCbTo.Items.Add(N);
    end;
  finally
    FCbFrom.Items.EndUpdate; FCbTo.Items.EndUpdate;
  end;
end;

{ Lazy-load the class list the first time a picker is dropped down (enumerating
  every indexed class is slow, so we defer it until actually needed). }
procedure TConvRulesForm.CbLoadClasses(Sender: TObject);
begin
  if Length(FAllClasses) > 0 then Exit;
  Screen.Cursor := crHourGlass;
  SetStatus('Loading component classes from the index (first time only)...');
  try
    Application.ProcessMessages;
    LoadAllClasses;
    SetStatus(Format('%d component classes available. Type to filter.',
      [Length(FAllClasses)]));
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
begin
  FRules.Items.Clear;
  Heads := FBook.ConvertHeaders;
  for H in Heads do
  begin
    Node := FBook.Nodes[H];
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
  FActiveHdr := AHdrIdx;
  Node := FBook.Nodes[AHdrIdx];
  SetStatus(Format('Loading property trees for %s -> %s ...', [Node.FromType, Node.ToType]));
  Application.ProcessMessages;

  // fetch F + T trees from the engine
  if not FEngine.GetProptree(Node.FromType, FFromTree, Err) then
  begin
    SetStatus('From tree: ' + Err);
    FFromTree := Default(TProptree);
  end;
  if not FEngine.GetProptree(Node.ToType, FToTree, Err) then
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
        if not Assigned.ContainsKey(LowerCase(Leaf.Path)) then
          if (Filter = '') or (Pos(Filter, LowerCase(Leaf.Path)) > 0) then
            FPool.Items.Add(Format('%s : %s', [Leaf.Path, Leaf.TypeName]));
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

{ Create or update the #link mapping ToPath <- FromPath in the active block,
  choosing a default cast from the leaf types (identity when same type). Shared by
  the manual Assign and the Auto-Match pass. Does NOT touch the grid/UI -- callers
  refresh. Assumes IsCastable(AFromType, AToType) was already checked. }
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

  if not IsCastable(fromType, toType) then
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
  L: TRuleNode;
  matchType: string;

  function LeafName(const APath: string): string;
  begin
    Result := APath;
    if LastDelimiter('.', Result) > 0 then
      Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;

begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  nMatched := 0;
  assignedTo := TDictionary<string, Boolean>.Create;
  try
    for L in ActiveLinks do
      if L.LinkTo <> '' then assignedTo.AddOrSetValue(LowerCase(L.LinkTo), True);

    for fromLeaf in FFromTree.Leaves do
    begin
      // skip From leaves already mapped
      if FindLinkForFrom(fromLeaf.Path) <> nil then Continue;
      fromName := LowerCase(LeafName(fromLeaf.Path));

      nCand := 0; candidate := Default(TPropLeaf); matchType := '';
      for toLeaf in FToTree.Leaves do
      begin
        if assignedTo.ContainsKey(LowerCase(toLeaf.Path)) then Continue;
        toName := LowerCase(LeafName(toLeaf.Path));
        if (fromName = toName) and IsCastable(fromLeaf.TypeName, toLeaf.TypeName) then
        begin
          Inc(nCand);
          candidate := toLeaf;
        end;
      end;

      if nCand = 1 then
      begin
        AssignLink(fromLeaf.Path, candidate.Path, fromLeaf.TypeName, candidate.TypeName);
        assignedTo.AddOrSetValue(LowerCase(candidate.Path), True);
        Inc(nMatched);
      end;
    end;
  finally
    assignedTo.Free;
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

  RefreshRulesList;
  // select the new rule (also fires LoadGridForBlock)
  if FRules.Items.Count > 0 then
  begin
    FRules.ItemIndex := FRules.Items.Count - 1;
    FRules.Items[FRules.Items.Count - 1].Selected := True;
  end
  else
    LoadGridForBlock(newHdrIdx);

  // pre-fill the obvious matches
  DoAutoMatch(nil);
  SyncRawFromModel;
  SetStatus(Format('New conversion %s -> %s created and auto-matched. '
    + 'Review, then Save.', [fromT, toT]));
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

procedure TConvRulesForm.DoSave(Sender: TObject);
var
  bak: string;
  res: TValidateResult;
  Node: TRuleNode;
  fromT, toT: string;
begin
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

  // 2) write canonical DSL (ASCII/CRLF)
  TFile.WriteAllText(FFilePath, FBook.SaveToString, TEncoding.ASCII);

  // 3) validate the saved file
  fromT := ''; toT := '';
  if FActiveHdr >= 0 then
  begin
    Node := FBook.Nodes[FActiveHdr];
    fromT := Node.FromType; toT := Node.ToType;
  end;
  res := FEngine.ValidateText(FBook.SaveToString, fromT, toT);
  if res.OK then
    SetStatus(Format('Saved %s (backup %s). Validate: OK',
      [ExtractFileName(FFilePath), ExtractFileName(bak)]))
  else
    SetStatus(Format('Saved %s (backup %s). Validate: %s',
      [ExtractFileName(FFilePath), ExtractFileName(bak), res.FirstError]));
end;

end.
