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
  System.Classes, Vcl.Controls, Vcl.Forms;

procedure ShowDragLintStructure;
procedure HideDragLintStructure;

{ v0.42: build the Structure UI embedded inside a host container (a tab of the
  drag-lint dock panel) rather than as a standalone stay-on-top window. The
  returned form is owned by AOwner; call RefreshEmbeddedStructure when its tab
  is activated to re-read the active editor file. }
function CreateEmbeddedStructure(AOwner: TComponent; AParent: TWinControl): TForm;
procedure RefreshEmbeddedStructure(AForm: TForm);

implementation

uses
  System.SysUtils, System.StrUtils, System.RegularExpressions,
  Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Winapi.Windows,
  ToolsAPI,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.StructureCache,
  DragLint.Plugin.DbResolver,
  DragLint.Plugin.Settings;

{ ---- TStructureNodeData: stores line info in tree node.Data ---- }

type
  TStructureNodeData = class
    Line: Integer;   { 1-based; 0 = no navigation }
  end;

{ ---- TDragLintStructureForm ---- }

type
  TDragLintStructureForm = class(TForm)
  private
    FTree:       TTreeView;
    FBtnRefresh: TButton;
    FLblFile:    TLabel;
    FSearch:     TEdit;          { v0.42: on-the-fly filter }
    FRegex:      TCheckBox;      { v0.42: treat filter as regex }
    FCurrentFile: string;
    FSyms:       TArray<TSymbolInfo>;           { cached so filtering doesn't re-shell }
    FDiags:      TArray<TDragLintDiagnostic>;
    procedure BtnRefreshClick(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure SearchChanged(Sender: TObject);
    procedure ClearNodeData;
    procedure RefreshForFile(const AFilePath: string);
    procedure BuildTree(const AFilter: string);
    function  SymMatches(const ASym: TSymbolInfo; const AFilter: string): Boolean;
    function  GetActiveFilePath: string;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshActive;   { v0.42: re-read the active editor file }
  end;

var
  GStructureForm: TDragLintStructureForm = nil;

{ ---- helpers ---- }

function SeverityPrefix(ASev: TDragLintSeverity): string;
begin
  case ASev of
    dlsError:   Result := '[E] ';
    dlsWarning: Result := '[W] ';
    dlsHint:    Result := '[H] ';
    dlsInfo:    Result := '[I] ';
  else
    Result := '    ';
  end;
end;

function KindPrefix(AKind: TSymbolKind): string;
begin
  case AKind of
    skUnit:        Result := '[unit] ';
    skClass:       Result := '[cls]  ';
    skInterface:   Result := '[intf] ';
    skRecord:      Result := '[rec]  ';
    skEnum:        Result := '[enum] ';
    skEnumValue:   Result := '[val]  ';
    skProcedure:   Result := '[proc] ';
    skFunction:    Result := '[func] ';
    skMethod:      Result := '[meth] ';
    skConstructor: Result := '[ctor] ';
    skDestructor:  Result := '[dtor] ';
    skProperty:    Result := '[prop] ';
    skField:       Result := '[fld]  ';
    skConstant:    Result := '[const]';
    skType:        Result := '[type] ';
    skVariable:    Result := '[var]  ';
  else
    Result := '[?]    ';
  end;
end;

function ResolveExePath: string;
begin
  Result := LoadSettings.ExePath;
  if (Result = '') or not FileExists(Result) then
    Result := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(Result) then
    Result := 'drag-lint.exe';
end;

function ResolveDbForFile: string;
{ v0.42: the Structure outline must query the SAME database the rest of the
  plugin uses for the active file. Reuse the shared DbResolver and take the
  primary (first, highest-priority) DB. Empty => let the exe self-resolve. }
var
  Dbs: TArray<string>;
begin
  Result := '';
  try
    Dbs := ResolveActiveIndexDbs(LoadSettings);
    if Length(Dbs) > 0 then
      Result := Dbs[0];
  except
    Result := '';
  end;
end;

{ ---- TDragLintStructureForm ---- }

constructor TDragLintStructureForm.Create(AOwner: TComponent);
var
  PanelFile, PanelSearch: TPanel;
  LblFilter: TLabel;
begin
  inherited CreateNew(AOwner);
  Caption       := 'drag-lint Structure';
  Width         := 380;
  Height        := 520;
  Position      := poDefaultPosOnly;
  FormStyle     := fsStayOnTop;
  BorderIcons   := [biSystemMenu, biMinimize, biMaximize];
  OnActivate    := FormActivate;
  OnDestroy     := FormDestroy;

  { Row 1: file label + refresh button. Created first so it docks topmost. }
  PanelFile := TPanel.Create(Self);
  PanelFile.Parent      := Self;
  PanelFile.Align       := alTop;
  PanelFile.Height      := 30;
  PanelFile.BevelOuter  := bvNone;

  FBtnRefresh := TButton.Create(PanelFile);
  FBtnRefresh.Parent  := PanelFile;
  FBtnRefresh.Caption := 'Refresh';
  FBtnRefresh.Align   := alRight;
  FBtnRefresh.Width   := 72;
  FBtnRefresh.OnClick := BtnRefreshClick;

  FLblFile := TLabel.Create(PanelFile);
  FLblFile.Parent     := PanelFile;
  FLblFile.Align      := alClient;
  FLblFile.Caption    := '(no file)';
  FLblFile.Layout     := tlCenter;
  FLblFile.EllipsisPosition := epPathEllipsis;

  { Row 2: filter edit + regex checkbox. Created after Row 1 so it docks below. }
  PanelSearch := TPanel.Create(Self);
  PanelSearch.Parent      := Self;
  PanelSearch.Align       := alTop;
  PanelSearch.Top         := PanelFile.Height;  { ensure it sits below Row 1 }
  PanelSearch.Height      := 28;
  PanelSearch.BevelOuter  := bvNone;

  FRegex := TCheckBox.Create(PanelSearch);
  FRegex.Parent   := PanelSearch;
  FRegex.Align    := alRight;
  FRegex.Width    := 64;
  FRegex.Caption  := 'regex';
  FRegex.OnClick  := SearchChanged;

  LblFilter := TLabel.Create(PanelSearch);
  LblFilter.Parent  := PanelSearch;
  LblFilter.Align   := alLeft;
  LblFilter.Layout  := tlCenter;
  LblFilter.Caption := ' Filter: ';

  FSearch := TEdit.Create(PanelSearch);
  FSearch.Parent      := PanelSearch;
  FSearch.Align       := alClient;
  FSearch.TextHint    := 'type to filter (substring, or regex)';
  FSearch.OnChange    := SearchChanged;

  { tree view }
  FTree := TTreeView.Create(Self);
  FTree.Parent     := Self;
  FTree.Align      := alClient;
  FTree.ReadOnly   := True;
  FTree.ShowLines  := True;
  FTree.HideSelection := False;
  FTree.OnDblClick := TreeDblClick;
end;

procedure TDragLintStructureForm.FormDestroy(Sender: TObject);
begin
  ClearNodeData;
end;

procedure TDragLintStructureForm.ClearNodeData;

  procedure ClearTree(ANode: TTreeNode);
  begin
    while ANode <> nil do
    begin
      if Assigned(ANode.Data) then
      begin
        TStructureNodeData(ANode.Data).Free;
        ANode.Data := nil;
      end;
      ClearTree(ANode.getFirstChild);
      ANode := ANode.getNextSibling;
    end;
  end;

begin
  if FTree.Items.Count > 0 then
    ClearTree(FTree.Items[0]);
end;

function TDragLintStructureForm.GetActiveFilePath: string;
var
  ESS: IOTAEditorServices;
  EV:  IOTAEditView;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV := ESS.TopView;
  if EV = nil then Exit;
  Result := EV.Buffer.FileName;
end;

procedure TDragLintStructureForm.RefreshForFile(const AFilePath: string);
var
  ExePath, DbPath: string;
begin
  FCurrentFile := AFilePath;
  if AFilePath = '' then
  begin
    FLblFile.Caption := '(no active editor)';
    SetLength(FDiags, 0);
    SetLength(FSyms, 0);
    BuildTree(FSearch.Text);
    Exit;
  end;
  FLblFile.Caption := ExtractFileName(AFilePath);

  { Re-shell once; cache the results so the filter re-renders without re-running
    drag-lint on every keystroke. }
  StructureCache.InvalidateForFile(AFilePath);
  FDiags := Cache.GetForFile(AFilePath);
  ExePath := ResolveExePath;
  DbPath  := ResolveDbForFile;
  FSyms   := StructureCache.GetSymbolsForFile(AFilePath, ExePath, DbPath);

  BuildTree(FSearch.Text);
end;

function TDragLintStructureForm.SymMatches(const ASym: TSymbolInfo;
  const AFilter: string): Boolean;
begin
  if AFilter = '' then Exit(True);
  if FRegex.Checked then
  begin
    try
      Result := TRegEx.IsMatch(ASym.Name, AFilter, [roIgnoreCase]) or
                TRegEx.IsMatch(ASym.QName, AFilter, [roIgnoreCase]);
    except
      Result := False;   { incomplete/invalid regex while typing -> match none }
    end;
  end
  else
    Result := ContainsText(ASym.Name, AFilter) or
              ContainsText(ASym.QName, AFilter);
end;

procedure TDragLintStructureForm.BuildTree(const AFilter: string);
var
  RootDiag, RootSym, Node: TTreeNode;
  ND: TStructureNodeData;
  D:  TDragLintDiagnostic;
  S:  TSymbolInfo;
  i, Shown: Integer;
  Caption: string;
begin
  FTree.Items.BeginUpdate;
  try
    ClearNodeData;
    FTree.Items.Clear;

    { --- Diagnostics root (not filtered: diagnostics are about lines/messages,
          not symbol names) --- }
    RootDiag := FTree.Items.Add(nil,
      Format('Diagnostics (%d)', [Length(FDiags)]));
    RootDiag.Data := nil;
    for i := 0 to High(FDiags) do
    begin
      D := FDiags[i];
      ND := TStructureNodeData.Create;
      ND.Line := D.Line + 1;
      Node := FTree.Items.AddChild(RootDiag,
        SeverityPrefix(D.Severity) + Format('(%d) ', [D.Line + 1]) + D.Message);
      Node.Data := ND;
    end;

    { --- Code Elements root (filtered by AFilter) --- }
    Shown := 0;
    RootSym := FTree.Items.Add(nil, '');  { caption set after we count }
    RootSym.Data := nil;
    for i := 0 to High(FSyms) do
    begin
      S := FSyms[i];
      if not SymMatches(S, AFilter) then Continue;
      Inc(Shown);
      ND := TStructureNodeData.Create;
      ND.Line := S.Line;
      Caption := KindPrefix(S.Kind) + S.Name;
      if S.Signature <> '' then
      begin
        if (S.Signature[1] = '(') or (S.Signature[1] = ':') then
          Caption := Caption + S.Signature
        else
          Caption := Caption + ': ' + S.Signature;
      end;
      Node := FTree.Items.AddChild(RootSym, Caption);
      Node.Data := ND;
    end;

    if AFilter = '' then
      RootSym.Text := Format('Code Elements (%d)', [Shown])
    else
      RootSym.Text := Format('Code Elements (%d of %d)', [Shown, Length(FSyms)]);

    RootDiag.Expand(False);
    RootSym.Expand(False);
  finally
    FTree.Items.EndUpdate;
  end;
end;

procedure TDragLintStructureForm.SearchChanged(Sender: TObject);
begin
  { Re-filter the already-loaded symbols on every keystroke (no re-shell). }
  BuildTree(FSearch.Text);
end;

procedure TDragLintStructureForm.BtnRefreshClick(Sender: TObject);
begin
  RefreshForFile(GetActiveFilePath);
end;

procedure TDragLintStructureForm.FormActivate(Sender: TObject);
var
  FilePath: string;
begin
  FilePath := GetActiveFilePath;
  { Only auto-refresh when the active file changes }
  if not SameText(FilePath, FCurrentFile) then
    RefreshForFile(FilePath);
end;

procedure TDragLintStructureForm.TreeDblClick(Sender: TObject);
var
  Node: TTreeNode;
  ND:   TStructureNodeData;
  ESS:  IOTAEditorServices;
  EV:   IOTAEditView;
  Pos:  IOTAEditPosition;
begin
  Node := FTree.Selected;
  if Node = nil then Exit;
  if Node.Data = nil then Exit;
  ND := TStructureNodeData(Node.Data);
  if ND.Line <= 0 then Exit;

  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV := ESS.TopView;
  if EV = nil then Exit;
  Pos := EV.Position;
  if Pos = nil then Exit;
  Pos.GotoLine(ND.Line);
  EV.Paint;
end;

{ ---- public factory ---- }

procedure TDragLintStructureForm.RefreshActive;
begin
  RefreshForFile(GetActiveFilePath);
end;

{ v0.42: embedded-in-a-tab factory. The form is created child-style (no border,
  fsNormal) and parented into AParent (a dock-panel TTabSheet), so the same
  tree + refresh logic serves both the standalone window and the dock tab. }
function CreateEmbeddedStructure(AOwner: TComponent;
  AParent: TWinControl): TForm;
var
  F: TDragLintStructureForm;
begin
  F := TDragLintStructureForm.Create(AOwner);
  F.BorderStyle := bsNone;
  F.FormStyle   := fsNormal;
  F.Align       := alClient;
  F.Parent      := AParent;
  F.Visible     := True;
  F.RefreshActive;
  Result := F;
end;

procedure RefreshEmbeddedStructure(AForm: TForm);
begin
  if AForm is TDragLintStructureForm then
    TDragLintStructureForm(AForm).RefreshActive;
end;

procedure ShowDragLintStructure;
begin
  if GStructureForm = nil then
    GStructureForm := TDragLintStructureForm.Create(nil);

  if not GStructureForm.Visible then
    GStructureForm.Show;

  GStructureForm.RefreshForFile(
    (GStructureForm as TDragLintStructureForm).GetActiveFilePath);
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
  if GStructureForm <> nil then
    FreeAndNil(GStructureForm);

end.
