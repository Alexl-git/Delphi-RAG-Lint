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
  Vcl.ExtCtrls, Vcl.Grids, Vcl.Dialogs, Vcl.Menus,
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

    // toolbar
    FPanelTop : TPanel;
    FLblFile  : TLabel;
    FLblStatus: TLabel;
    // rules library
    FRules    : TListView;
    // grid
    FGrid     : TStringGrid;          // col0 From, col1 To-assigned, col2 cast
    FPool     : TListBox;             // unassigned T pool
    FPoolFind : TEdit;
    FBtnAssign: TButton;
    FBtnUnasgn: TButton;
    // directives / raw
    FTabs     : TPageControl;
    FRaw      : TMemo;

    procedure BuildUI;
    procedure FormCloseHandler(Sender: TObject; var Action: TCloseAction);
    procedure DoLoad(Sender: TObject);
    procedure DoSave(Sender: TObject);
    procedure DoValidate(Sender: TObject);
    procedure RefreshRulesList;
    procedure RulesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure LoadGridForBlock(AHdrIdx: Integer);
    procedure RefreshPool;
    procedure DoAssign(Sender: TObject);
    procedure DoUnassign(Sender: TObject);
    procedure PoolFilter(Sender: TObject);
    procedure SyncRawFromModel;
    procedure SetStatus(const S: string);
    function  BlockPercent(AHdrIdx: Integer): Integer;
    function  ActiveLinks: TArray<TRuleNode>;
    function  FindLinkForFrom(const AFromPath: string): TRuleNode;
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
  SetStatus('Ready. Open a .rules file to begin.');
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

  // --- top toolbar ---
  FPanelTop := TPanel.Create(Self);
  FPanelTop.Parent := Self; FPanelTop.Align := alTop; FPanelTop.Height := 56;
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

  FLblFile := TLabel.Create(Self);
  FLblFile.Parent := FPanelTop; FLblFile.SetBounds(8, 36, 900, 15);
  FLblFile.Caption := '(no file)';

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := FPanelTop; FLblStatus.SetBounds(300, 10, 780, 15);

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

  var LblPool: TLabel := TLabel.Create(Self);
  LblPool.Parent := PoolPanel; LblPool.SetBounds(6, 6, 260, 15);
  LblPool.Caption := 'To (unassigned pool) -- search:';

  FPoolFind := TEdit.Create(Self);
  FPoolFind.Parent := PoolPanel; FPoolFind.SetBounds(6, 24, 260, 23);
  FPoolFind.OnChange := PoolFilter;

  FBtnAssign := TButton.Create(Self);
  FBtnAssign.Parent := PoolPanel; FBtnAssign.SetBounds(6, 52, 125, 25);
  FBtnAssign.Caption := '<- Assign to From'; FBtnAssign.OnClick := DoAssign;

  FBtnUnasgn := TButton.Create(Self);
  FBtnUnasgn.Parent := PoolPanel; FBtnUnasgn.SetBounds(140, 52, 125, 25);
  FBtnUnasgn.Caption := 'Unassign ->'; FBtnUnasgn.OnClick := DoUnassign;

  FPool := TListBox.Create(Self);
  FPool.Parent := PoolPanel; FPool.SetBounds(6, 82, 268, 560);
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
  FLblStatus.Caption := S;
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

procedure TConvRulesForm.DoAssign(Sender: TObject);
var
  FromPath, ToPath: string;
  fromLeaf: TPropLeaf;
  toLeaf  : TPropLeaf;
  Link    : TRuleNode;
  row     : Integer;
  i       : Integer;
  fromType, toType: string;
begin
  if FActiveHdr < 0 then Exit;
  if FPool.ItemIndex < 0 then begin SetStatus('Pick a To property from the pool first.'); Exit; end;
  row := FGrid.Row;
  if row < 1 then begin SetStatus('Pick a From row in the grid first.'); Exit; end;

  FromPath := PathOfGridCell(FGrid.Cells[0, row]);
  ToPath   := PathOfGridCell(FPool.Items[FPool.ItemIndex]);
  if (FromPath = '') or (ToPath = '') then Exit;

  // resolve leaf types for cast classification
  fromType := ''; toType := '';
  for fromLeaf in FFromTree.Leaves do if fromLeaf.Path = FromPath then fromType := fromLeaf.TypeName;
  for toLeaf in FToTree.Leaves do if toLeaf.Path = ToPath then toType := toLeaf.TypeName;

  if not IsCastable(fromType, toType) then
  begin
    SetStatus(Format('Blocked: %s (%s) and %s (%s) are not castable.',
      [FromPath, fromType, ToPath, toType]));
    Exit;
  end;

  // create or update the #link for this From. Insert right after the header if new.
  Link := FindLinkForFrom(FromPath);
  if Link = nil then
  begin
    Link := TRuleNode.Create;
    Link.Kind := rnkLink;
    Link.LinkFrom := FromPath;
    Link.Dirty := True;
    // insert as the last node of the active block
    var insertAt: Integer := FActiveHdr + 1;
    for i := FActiveHdr + 1 to FBook.Nodes.Count - 1 do
    begin
      if FBook.Nodes[i].Kind = rnkConvert then Break;
      insertAt := i + 1;
    end;
    FBook.Nodes.Insert(insertAt, Link);
  end;
  Link.LinkTo := ToPath;
  Link.Dirty := True;

  // default cast: if same family, none; else first valid cast
  if SameFamily(fromType, toType) then
    Link.Cast := ''
  else
  begin
    var casts := ValidCasts(fromType, toType);
    var c: TCastFn;
    for c := Low(TCastFn) to High(TCastFn) do
      if c in casts then begin Link.Cast := CastFnName(c); Break; end;
  end;

  FGrid.Cells[1, row] := ToPath;
  FGrid.Cells[2, row] := Link.Cast;
  RefreshPool;
  SyncRawFromModel;
  RefreshRulesList;
  SetStatus(Format('Assigned %s <- %s%s', [ToPath, FromPath,
    IfThen(Link.Cast <> '', ' : ' + Link.Cast, '')]));
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
