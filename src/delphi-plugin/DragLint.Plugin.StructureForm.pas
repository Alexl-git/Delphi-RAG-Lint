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

procedure ShowDragLintStructure;
procedure HideDragLintStructure;

implementation

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Winapi.Windows,
  ToolsAPI,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.StructureCache,
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
    FCurrentFile: string;
    procedure BtnRefreshClick(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ClearNodeData;
    procedure RefreshForFile(const AFilePath: string);
    function  GetActiveFilePath: string;
  public
    constructor Create(AOwner: TComponent); override;
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
    skUnit:      Result := '[unit] ';
    skClass:     Result := '[cls]  ';
    skInterface: Result := '[intf] ';
    skRecord:    Result := '[rec]  ';
    skProcedure: Result := '[proc] ';
    skFunction:  Result := '[func] ';
    skProperty:  Result := '[prop] ';
    skField:     Result := '[fld]  ';
    skConstant:  Result := '[const]';
    skType:      Result := '[type] ';
    skVariable:  Result := '[var]  ';
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

{ ---- TDragLintStructureForm ---- }

constructor TDragLintStructureForm.Create(AOwner: TComponent);
var
  Panel: TPanel;
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

  { top panel: label + refresh button }
  Panel := TPanel.Create(Self);
  Panel.Parent      := Self;
  Panel.Align       := alTop;
  Panel.Height      := 32;
  Panel.BevelOuter  := bvNone;

  FBtnRefresh := TButton.Create(Panel);
  FBtnRefresh.Parent  := Panel;
  FBtnRefresh.Caption := 'Refresh';
  FBtnRefresh.Align   := alRight;
  FBtnRefresh.Width   := 72;
  FBtnRefresh.OnClick := BtnRefreshClick;

  FLblFile := TLabel.Create(Panel);
  FLblFile.Parent     := Panel;
  FLblFile.Align      := alClient;
  FLblFile.Caption    := '(no file)';
  FLblFile.Layout     := tlCenter;
  FLblFile.EllipsisPosition := epPathEllipsis;

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
  Diags:    TArray<TDragLintDiagnostic>;
  Syms:     TArray<TSymbolInfo>;
  RootDiag, RootSym: TTreeNode;
  Node:     TTreeNode;
  ND:       TStructureNodeData;
  D:        TDragLintDiagnostic;
  S:        TSymbolInfo;
  ExePath:  string;
  i:        Integer;
begin
  FTree.Items.BeginUpdate;
  try
    ClearNodeData;
    FTree.Items.Clear;
    FCurrentFile := AFilePath;

    if AFilePath = '' then
    begin
      FLblFile.Caption := '(no active editor)';
      Exit;
    end;
    FLblFile.Caption := ExtractFileName(AFilePath);

    { Invalidate structure cache so a Refresh always re-shells }
    StructureCache.InvalidateForFile(AFilePath);

    { --- Diagnostics root --- }
    Diags := Cache.GetForFile(AFilePath);
    RootDiag := FTree.Items.Add(nil,
      Format('Diagnostics (%d)', [Length(Diags)]));
    RootDiag.Data := nil;

    for i := 0 to High(Diags) do
    begin
      D := Diags[i];
      ND := TStructureNodeData.Create;
      ND.Line := D.Line + 1;  { cache stores 0-based }
      Node := FTree.Items.AddChild(RootDiag,
        SeverityPrefix(D.Severity) +
        Format('(%d) ', [D.Line + 1]) +
        D.Message);
      Node.Data := ND;
    end;

    { --- Code Elements root --- }
    ExePath := ResolveExePath;
    Syms    := StructureCache.GetSymbolsForFile(AFilePath, ExePath);

    RootSym := FTree.Items.Add(nil,
      Format('Code Elements (%d)', [Length(Syms)]));
    RootSym.Data := nil;

    for i := 0 to High(Syms) do
    begin
      S  := Syms[i];
      ND := TStructureNodeData.Create;
      ND.Line := S.Line;
      Node := FTree.Items.AddChild(RootSym,
        KindPrefix(S.Kind) + S.Name);
      Node.Data := ND;
    end;

    RootDiag.Expand(False);
    RootSym.Expand(False);
  finally
    FTree.Items.EndUpdate;
  end;
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
