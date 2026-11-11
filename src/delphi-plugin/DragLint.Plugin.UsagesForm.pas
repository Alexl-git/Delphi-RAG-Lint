unit DragLint.Plugin.UsagesForm;

{ v0.33 Find Usages form.
  Non-modal fsStayOnTop TForm showing all callers of a symbol, grouped by
  file in a TTreeView.  Double-click on a child node navigates the editor.

  Call ShowFindUsages() from the main IDE thread only.
  The form is self-freeing (Action := caFree) and singleton-guarded. }

interface

uses
  System.Classes
  , System.SysUtils
  , Vcl.Controls
  , DragLint.Plugin.LspClient
  ;

/// <summary><!-- drag-lint:auto sum -->---- public API ----</summary>
/// <param name="ASymbolName"><!-- drag-lint:auto type -->const string</param>
/// <param name="AExePath"><!-- drag-lint:auto type -->const string</param>
/// <param name="ADbPath"><!-- drag-lint:auto type -->const string</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.InvokeFindUsages (DragLint.Plugin.Editor.pas), DragLint.Plugin.StructureForm.TDragLintStructureForm.FindUsagesClick (DragLint.Plugin.StructureForm.pas)</para>
/// <para>Calls: DragLint.Plugin.UsagesForm.TDragLintUsagesForm.Create, DragLint.Plugin.UsagesForm.TDragLintUsagesForm.LoadUsages/3</para>
/// <para>Overload 1 of 2</para>
/// <para>Directives: overload</para>
/// <seealso cref="DragLint.Plugin.UsagesForm.TDragLintUsagesForm.Create"/>
/// <seealso cref="DragLint.Plugin.UsagesForm.TDragLintUsagesForm.LoadUsages"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ShowFindUsages(const ASymbolName, AExePath, ADbPath: string); overload;
{ v0.40.3: pass every --db path the resolver picked so callers from
  SERVER + COMMON + library DBs show up alongside the active project's. }
/// <summary><!-- drag-lint:auto sum -->v0.40.3: pass every --db path the resolver picked
/// so callers from SERVER + COMMON + library DBs show up alongside the active project's.</summary>
/// <param name="ASymbolName"><!-- drag-lint:auto type -->const string</param>
/// <param name="AExePath"><!-- drag-lint:auto type -->const string</param>
/// <param name="ADbPaths"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.StructureForm.TDragLintStructureForm.FindUsagesClick (DragLint.Plugin.StructureForm.pas)</para>
/// <para>Calls: DragLint.Plugin.UsagesForm.TDragLintUsagesForm.Create, DragLint.Plugin.UsagesForm.TDragLintUsagesForm.LoadUsages/3</para>
/// <para>Overload 2 of 2</para>
/// <para>Directives: overload</para>
/// <seealso cref="DragLint.Plugin.UsagesForm.TDragLintUsagesForm.Create"/>
/// <seealso cref="DragLint.Plugin.UsagesForm.TDragLintUsagesForm.LoadUsages"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ShowFindUsages(const ASymbolName, AExePath: string; const ADbPaths: TArray<string>); overload;
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.UnregisterDragLintMenu (DragLint.Plugin.Editor.pas)</para>
/// <para>Calls: FreeAndNil</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure HideFindUsages;

{ v0.42: build the Find-Usages UI in a dock-panel tab: a symbol search box on
  top of the (reparented, non-modal) usages tree. Enter runs find-callers for
  the typed symbol against the resolved project DBs. }
/// <summary><!-- drag-lint:auto sum -->v0.42: build the Find-Usages UI in a dock-panel
/// tab: a symbol search box on top of the (reparented, non-modal) usages tree. Enter runs
/// find-callers for the typed symbol against the resolved project DBs.</summary>
/// <param name="AOwner"><!-- drag-lint:auto type -->TComponent</param>
/// <param name="AParent"><!-- drag-lint:auto type -->TWinControl</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DockForm.TDragLintDockFrame.HandleInitTimer (DragLint.Plugin.DockForm.pas)</para>
/// <para>Calls: DragLint.Plugin.UsagesForm.TDragLintUsagesForm.Create, DragLint.Plugin.UsagesForm.TUsagesEmbedCtl.ComboChange, DragLint.Plugin.UsagesForm.TUsagesEmbedCtl.EditKeyDown</para>
/// <para>UI thread only -- touches AParent, Frm</para>
/// <seealso cref="DragLint.Plugin.UsagesForm.TDragLintUsagesForm.Create"/>
/// <seealso cref="DragLint.Plugin.UsagesForm.TUsagesEmbedCtl.ComboChange"/>
/// <seealso cref="DragLint.Plugin.UsagesForm.TUsagesEmbedCtl.EditKeyDown"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure CreateEmbeddedUsages(AOwner: TComponent; AParent: TWinControl);

var
  /// <summary>Hands over the running LSP client, or nil; set by DragLint.Plugin.Editor to
  /// CurrentLspClient, which never spawns. A hook because Editor already uses this unit.</summary>
  /// <remarks>With a connected client whose databases cover the query, Find Usages asks
  /// `draglint/usages` and spawns nothing. Otherwise, and when the server is late (10 s) or
  /// answers an error, it runs `drag-lint usages`. Both give the same document. A client
  /// stopped or replaced mid-question is noticed within LSP_WATCH_MS and the CLI answers.
  /// Main thread only.</remarks>
  GUsagesLspClient: TFunc<TDragLintLspClient> = nil;

implementation

uses
  System.JSON
  , System.StrUtils
  , Vcl.Forms
  , Vcl.ComCtrls
  , Vcl.StdCtrls
  , Vcl.ToolWin
  , Vcl.ExtCtrls
  , Vcl.Graphics
  , Winapi.Windows
  , ToolsAPI
  , DragLint.Plugin.DbResolver
  , DragLint.Plugin.Settings
  , DragLint.Plugin.CliAsync
  , DragLint.Plugin.ExeResolver
  , DragLint.Plugin.UsagesQuery
  ;

{ v0.40.5: local copy of the BPL build-stamp helper to avoid circular use
  with DragLint.Plugin.Editor (which already imports this unit). Same
  semantics as Editor.PluginBuildTag -- reads the loaded BPL's file modtime. }
function LocalBuildTag: string;
var
  ModName: string   ;
  Age    : TDateTime;
begin
  ModName:= GetModuleName(HInstance);
  Result:= if (ModName <> '') and FileAge(ModName, Age) then 'v1.50.0-alpha (BPL built ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Age) + ')'
    else 'v1.50.0-alpha';
end;

{ ---- TUsageNodeData: stores file + line in tree node.Data ---- }

const
  USAGES_QUERY_STALL_MS = 30000;
  { A server still silent after this has its question dropped and the CLI answers: a
    wide query on a large index can outlast it, and the CLI then has its own budget. }
  USAGES_LSP_BUDGET_MS = 10000;
  { How often a question in flight checks that the client it asked is still the running one. }
  LSP_WATCH_MS = 1000;

type
  TUsageNodeData = class
    FilePath: string ;
    Line    : Integer;
  end;

  { ---- TDragLintUsagesForm ---- }

type
  TDragLintUsagesForm = class(TForm)
    private
      FLblTitle      : TLabel        ;
      FToolBar       : TToolBar      ;
      FBtnRefresh    : TToolButton   ;
      FBtnClose      : TToolButton   ;
      FTree          : TTreeView     ;
      FSymbolName    : string        ;
      FExePath       : string        ;
      FDbPath        : string        ; { kept for legacy single-DB callers }
      FDbPaths       : TArray<string>; { v0.40.3: multi-DB list }
      FWidth         : string        ; { v0.42: narrow|wide|very-wide }
      FLastCallerNode: TTreeNode     ;
      FRun           : TCliRunSlot   ; { the query in flight; a newer one supersedes it }
      FLspId         : Integer       ; { the server request in flight, 0 for none }
      FLspClient     : TDragLintLspClient; { who FLspId belongs to; compared, never called unchecked }
      FLspWatch      : TTimer        ; { while FLspId <> 0: notices a stopped / replaced client (148 XP3) }
      procedure BtnRefreshClick(Sender: TObject);
      procedure BtnCloseClick  (Sender: TObject);
      procedure TreeDblClick   (Sender: TObject);
      procedure TreeAdvancedCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
      procedure FormClose(Sender: TObject; var Action: TCloseAction);
      procedure FormDestroy(Sender: TObject);
      procedure ClearNodeData;
      procedure RunQuery;
      procedure RunCliQuery;
      function TryLspQuery: Boolean;
      procedure CancelLspQuery;
      procedure LspAnswered(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue);
      procedure LspWatchTick(Sender: TObject);
      procedure ShowResult(AExitCode: Integer; const AOutput: string);
      procedure ParseUsagesGrouped(const AOutput: string; out AParsed: Boolean);
      procedure NavigateToNode(ANode: TTreeNode);
      procedure ParseTextOutput(const AOutput: string);
      function AddNodeData(AParent: TTreeNode; const AText, AFile: string; ALine: Integer): TTreeNode;
    public
      constructor Create(AOwner: TComponent); override;
      procedure SetWidth(const AWidth: string); { v0.42: narrow|wide|very-wide }
      procedure LoadUsages(const ASymbolName, AExePath, ADbPath: string); overload;
      procedure LoadUsages(const ASymbolName, AExePath: string; const ADbPaths: TArray<string>); overload;
  end;

var
  GUsagesForm: TDragLintUsagesForm = nil;

{ ---- TDragLintUsagesForm ---- }

constructor TDragLintUsagesForm.Create(AOwner: TComponent);
var
  Panel: TPanel;
begin
  inherited CreateNew(AOwner);
  { v0.40.5: stamp the form caption with the loaded BPL's modtime so a
    glance at the title bar tells the user which build is live. Mirrors
    the Test Connection dialog's PluginBuildTag pattern. }
  Caption:= 'drag-lint Find Usages  -  ' + LocalBuildTag;
  Width    := 520;
  Height   := 420;
  Position := poDefaultPosOnly;
  FormStyle:= fsStayOnTop;
  BorderIcons:= [biSystemMenu, biMinimize, biMaximize];
  OnClose  := FormClose;
  OnDestroy:= FormDestroy;

  Panel:= TPanel.Create(Self);
  Panel.Parent    := Self;
  Panel.Align     := alTop;
  Panel.Height    := 56;
  Panel.BevelOuter:= bvNone;

  FLblTitle:= TLabel.Create(Panel);
  FLblTitle.Parent := Panel;
  FLblTitle.Align  := alTop;
  FLblTitle.Caption:= 'Find usages of: (none)';
  FLblTitle.Height := 24;
  FLblTitle.Layout := tlCenter;

  FToolBar:= TToolBar.Create(Panel);
  FToolBar.Parent      := Panel;
  FToolBar.Align       := alClient;
  FToolBar.ShowCaptions:= True;
  FToolBar.Flat        := True;
  FToolBar.Height      := 28;

  FBtnRefresh:= TToolButton.Create(FToolBar);
  FBtnRefresh.Parent := FToolBar;
  FBtnRefresh.Caption:= 'Refresh';
  FBtnRefresh.OnClick:= BtnRefreshClick;

  FBtnClose:= TToolButton.Create(FToolBar);
  FBtnClose.Parent := FToolBar;
  FBtnClose.Caption:= 'Close';
  FBtnClose.OnClick:= BtnCloseClick;

  FTree:= TTreeView.Create(Self);
  FTree.Parent       := Self;
  FTree.Align        := alClient;
  FTree.ReadOnly     := True;
  FTree.ShowLines    := True;
  FTree.HideSelection:= False;
  FTree.OnDblClick   := TreeDblClick;
  { v0.42: custom-draw caller rows so the searched identifier is highlighted
    (bold + amber) inside the code snippet. }
  FTree.OnAdvancedCustomDrawItem:= TreeAdvancedCustomDrawItem;

  FLastCallerNode:= nil;
  FWidth:= 'narrow';
  FRun:= TCliRunSlot.Create;
  FLspWatch:= TTimer.Create(Self);
  FLspWatch.Enabled := False;
  FLspWatch.Interval:= LSP_WATCH_MS;
  FLspWatch.OnTimer := LspWatchTick;
end; // constructor

procedure TDragLintUsagesForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action:= caFree;
  GUsagesForm:= nil;
  FRun.Cancel;  { nobody is left to read the answer }
  CancelLspQuery;
end;

procedure TDragLintUsagesForm.FormDestroy(Sender: TObject);
begin
  CancelLspQuery;    { its callback holds this form }
  FreeAndNil(FRun);  { abandons the run in flight: its answer never reaches a dead form }
  ClearNodeData;
end;

procedure TDragLintUsagesForm.ClearNodeData;

  procedure WalkNodes(ANode: TTreeNode);
  begin
    while ANode <> nil do
    begin
      WalkNodes(ANode.getFirstChild);
      if Assigned(ANode.Data) then
      begin
        TUsageNodeData(ANode.Data).Free;
        ANode.Data:= nil;
      end;
      ANode:= ANode.getNextSibling;
    end;
  end;

begin
  FLastCallerNode:= nil;
  if FTree.Items.Count > 0 then WalkNodes(FTree.Items[0]);
end;

function TDragLintUsagesForm.AddNodeData(AParent: TTreeNode; const AText, AFile: string; ALine: Integer): TTreeNode;
var
  ND: TUsageNodeData;
begin
  ND:= TUsageNodeData.Create;
  ND.FilePath:= AFile;
  ND.Line    := ALine;
  if AParent = nil then Result:= FTree.Items.Add(nil, AText)
  else Result:= FTree.Items.AddChild(AParent, AText);
  Result.Data:= ND;
end;

function IsIdentBoundary(const AText: string; AIndex: Integer): Boolean;
{ True when position AIndex (1-based; may be 0 or > length for the edges) is
  NOT part of a Pascal identifier -- used to keep highlighting to whole-word
  matches of the symbol, so "Foo" doesn't light up inside "FooBar". }
var
  C: Char;
begin
  if (AIndex < 1) or (AIndex > Length(AText)) then Exit(True);
  C:= AText[AIndex];
  Result:= not (CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

procedure TDragLintUsagesForm.TreeAdvancedCustomDrawItem(
  Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
{ v0.42: full self-draw of caller rows so we can render the matched identifier
  in bold amber while leaving the rest of the snippet plain. Self-drawing (vs
  overlaying) guarantees exact alignment because every segment's X is computed
  from one origin. Only caller rows (Data with a real Line) are custom-drawn;
  file headers / debug nodes fall through to the default renderer. }
var
  ND      : TUsageNodeData;
  Txt     : string        ;
  Term    : string        ;
  R       : TRect         ;
  Cv      : TCanvas       ;
  Selected: Boolean       ;
  X       : Integer       ;
  P       : Integer       ;
  StartAt : Integer       ;
  Seg     : string        ;
begin
  DefaultDraw:= True;
  if Stage <> cdPrePaint then Exit;
  if FSymbolName = '' then Exit;
  if not (TObject(Node.Data) is TUsageNodeData) then Exit;
  ND:= TUsageNodeData(Node.Data);
  if ND.Line <= 0 then Exit; { only real caller rows }

  Txt:= Node.Text;
  Term:= FSymbolName;
  if Pos(LowerCase(Term), LowerCase(Txt)) = 0 then Exit; { nothing to mark }

  Cv:= Sender.Canvas;
  R:= Node.DisplayRect(True);
  Selected:= (cdsSelected in State) or (cdsMarked in State);

  Cv.Font.Assign(FTree.Font);
  if Selected then
  begin
    Cv.Brush.Color:= clHighlight;
    Cv.Font .Color:= clHighlightText;
  end
  else
  begin
    Cv.Brush.Color:= clWindow;
    Cv.Font .Color:= clWindowText;
  end;
  Cv.FillRect(R);
  Cv.Brush.Style:= bsClear;

  X:= R.Left + 2;
  StartAt:= 1;
  repeat
    { next whole-word, case-insensitive occurrence at/after StartAt }
    P:= PosEx(LowerCase(Term), LowerCase(Txt), StartAt);
    while (P > 0) and not (IsIdentBoundary(Txt, P - 1) and IsIdentBoundary(Txt, P + Length(Term))) do P:= PosEx(LowerCase(Term), LowerCase(Txt), P + 1);

    if P = 0 then
    begin
      Seg:= Copy(Txt, StartAt, MaxInt);
      if Seg <> '' then
      begin
        Cv.Font.Style:= [];
        if not Selected then Cv.Font.Color:= clWindowText;
        Cv.TextOut(X, R.Top, Seg);
      end;
      Break;
    end;

    { plain text before the match }
    if P > StartAt then
    begin
      Seg:= Copy(Txt, StartAt, P - StartAt);
      Cv.Font.Style:= [];
      if not Selected then Cv.Font.Color:= clWindowText;
      Cv.TextOut(X, R.Top, Seg);
      Inc(X, Cv.TextWidth(Seg));
    end;

    { the matched identifier: bold + amber (plain bold when selected) }
    Seg:= Copy(Txt, P, Length(Term));
    Cv.Font.Style:= [fsBold];
    if not Selected then Cv.Font.Color:= TColor($004080FF) { amber/orange BGR };
    Cv.TextOut(X, R.Top, Seg);
    Inc(X, Cv.TextWidth(Seg));

    StartAt:= P + Length(Term);
  until False;

  DefaultDraw:= False;
end; // procedure

procedure TDragLintUsagesForm.SetWidth(const AWidth: string);
begin
  FWidth:= AWidth;
  if FSymbolName <> '' then RunQuery; { re-run at the new width (cheap; query-time over the index) }
end;

procedure TDragLintUsagesForm.ParseUsagesGrouped(const AOutput: string; out AParsed: Boolean);
{ v0.42: render the grouped JSON from `drag-lint usages`. Top-level keys:
  declarations (kind/qname/file/line), reads/writes/calls/types/attributes/
  events/raises/handles (each file/line/col), and impact (depth/callers/units). Each category
  becomes a root tree node with navigable child rows. }
var
  Root: TJSONValue ;
  Obj : TJSONObject;

  procedure AddRefGroup(const AKey, ACaption: string);
  var
    Arr      : TJSONArray ;
    i        : Integer    ;
    Ln       : Integer    ;
    Cl       : Integer    ;
    O        : TJSONObject;
    F        : string     ;
    GroupNode: TTreeNode  ;
  begin
    if not Obj.TryGetValue<TJSONArray>(AKey, Arr) then Exit;
    if Arr.Count = 0 then Exit;
    GroupNode:= AddNodeData(nil, Format('%s (%d)', [ACaption, Arr.Count]), '', 0);
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      F:= ''; Ln:= 0; Cl:= 0;
      O.TryGetValue<string>('file', F);
      O.TryGetValue<Integer>('line', Ln);
      O.TryGetValue<Integer>('col' , Cl);
      AddNodeData(GroupNode, Format('%s:%d', [ExtractFileName(F), Ln]), F, Ln);
    end;
    GroupNode.Expand(False);
  end; // procedure

  procedure AddDeclGroup;
  var
    Arr      : TJSONArray ;
    i        : Integer    ;
    Ln       : Integer    ;
    O        : TJSONObject;
    F        : string     ;
    QN       : string     ;
    Kd       : string     ;
    GroupNode: TTreeNode  ;
  begin
    if not Obj.TryGetValue<TJSONArray>('declarations', Arr) then Exit;
    if Arr.Count = 0 then Exit;
    GroupNode:= AddNodeData(nil, Format('Declaration (%d)', [Arr.Count]), '', 0);
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      F:= ''; QN:= ''; Kd:= ''; Ln:= 0;
      O.TryGetValue<string>('kind' , Kd);
      O.TryGetValue<string>('qname', QN);
      O.TryGetValue<string>('file' , F );
      O.TryGetValue<Integer>('line', Ln);
      AddNodeData(GroupNode, Format('%s  %s  (%s:%d)', [Kd, QN, ExtractFileName(F), Ln]), F, Ln);
    end;
    GroupNode.Expand(False);
  end; // procedure

  procedure AddImpactGroup;
  var
    Arr      : TJSONArray ;
    i        : Integer    ;
    Dp       : Integer    ;
    Ca       : Integer    ;
    Un       : Integer    ;
    O        : TJSONObject;
    GroupNode: TTreeNode  ;
  begin
    if not Obj.TryGetValue<TJSONArray>('impact', Arr) then Exit;
    if Arr.Count = 0 then Exit;
    GroupNode:= AddNodeData(nil, 'Impact (transitive callers)', '', 0);
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      Dp:= 0; Ca:= 0; Un:= 0;
      O.TryGetValue<Integer>('depth'  , Dp);
      O.TryGetValue<Integer>('callers', Ca);
      O.TryGetValue<Integer>('units'  , Un);
      AddNodeData(GroupNode, Format('depth %d: %d callers across %d units', [Dp, Ca, Un]), '', 0);
    end;
    GroupNode.Expand(False);
  end; // procedure

begin
  AParsed:= False;
  Root:= TJSONObject.ParseJSONValue(AOutput);
  if not (Root is TJSONObject) then
  begin
    if Root <> nil then Root.Free;
    Exit;
  end;
  try
    Obj:= TJSONObject(Root);
    if Obj.GetValue('reads') = nil then Exit; { not the usages shape }
    AParsed:= True;
    AddDeclGroup;
    AddRefGroup('reads'     , 'Reads'         );
    AddRefGroup('writes'    , 'Writes'        );
    AddRefGroup('calls'     , 'Calls'         );
    AddRefGroup('types'     , 'Type uses'     );
    AddRefGroup('attributes', 'Attributes'    );
    AddRefGroup('events'    , 'Event handlers');
    AddRefGroup('raises'    , 'Raised at'     ); { exception classes: raise sites (146 p1 tail) }
    AddRefGroup('handles'   , 'Handled at'    ); { ... and the except clauses that catch them }
    AddImpactGroup;
  finally
    Root.Free;
  end;
end; // begin

procedure TDragLintUsagesForm.ParseTextOutput(const AOutput: string);
{ v0.40.5: the CLI's `query find-callers` text output format is:
    <file>:<line>:<col>  <symbol_name>
       <ctx_line>: <code>
       <ctx_line>: <code>
    <file>:<line>:<col>  <symbol_name>
       ...
    N caller(s)
  No '->' anywhere. Earlier parser looked for ' -> ' and so dropped
  every match. Fix: recognise the header by trailing :LINE:COL pattern
  at the position before the symbol name (two spaces separator). }
var
  Lines     : TStringList   ;
  i         : Integer       ;
  Line      : string        ;
  Location  : string        ;
  CFile     : string        ;
  CLine     : Integer       ;
  HdrSep    : Integer       ;
  p1        : Integer       ;
  p2        : Integer       ;
  k         : Integer       ;
  LastFile  : string        ;
  FileNode  : TTreeNode     ;
  CallerNode: TTreeNode     ;
  ND        : TUsageNodeData;
  SymName   : string        ;
begin
  Lines:= TStringList.Create;
  LastFile:= '';
  FileNode  := nil;
  CallerNode:= nil;
  try
    Lines.Text:= AOutput;
    for i:= 0 to Lines.Count - 1 do
    begin
      Line:= Lines[i];
      if Line = '' then Continue;

      { Context sub-line (indented) }
      if Line[1] = ' ' then
      begin
        if CallerNode <> nil then
        begin
          ND:= TUsageNodeData.Create;
          ND.FilePath:= TUsageNodeData(CallerNode.Data).FilePath;
          ND.Line:= 0;
          var SubNode: TTreeNode;
          SubNode:= FTree.Items.AddChild(CallerNode, Trim(Line));
          SubNode.Data:= ND;
        end;
        Continue;
      end;

      { Skip the trailing "N caller(s)" summary line. }
      if Pos(' caller(s)'    , Line) > 0 then Continue;
      if Pos(' callers found', Line) > 0 then Continue;

      { Caller header line: <file>:<line>:<col>  <symbol_name>
        Two-space separator between location and name. }
      HdrSep:= Pos('  ', Line);
      if HdrSep <= 0 then Continue;
      Location:= Copy(Line, 1, HdrSep - 1);
      SymName:= Trim(Copy(Line, HdrSep, MaxInt));
      { Skip if SymName contains spaces (not a caller header). }
      if Pos(' ', SymName) > 0 then Continue;

      p1:= 0;
      p2:= 0;
      for k:= Length(Location) downto 1 do
        if Location[k] = ':' then
        begin
          if p2      = 0 then p2:= k
          else if p1 = 0 then
          begin
            p1:= k;
            Break;
          end;
        end;
      if (p1 > 0) and (p2 > p1) then
      begin
        CFile:= Copy(Location, 1, p1 - 1);
        CLine:= StrToIntDef(Copy(Location, p1 + 1, p2 - p1 - 1), 0);
      end
      else
      begin
        CFile:= Location;
        CLine:= 0;
      end;

      if not SameText(CFile, LastFile) then
      begin
        LastFile:= CFile;
        FileNode:= AddNodeData(nil, ExtractFileName(CFile) + '  [' + CFile + ']', CFile, 0);
      end;

      CallerNode:= AddNodeData(FileNode, Format('Line %d  %s', [CLine, SymName]), CFile, CLine);
      FLastCallerNode:= CallerNode;
    end; // for
  finally
    Lines.Free;
  end; // try
end; // procedure

procedure TDragLintUsagesForm.CancelLspQuery;
begin
  { FLspClient is only compared: the shared client may have been freed and replaced,
    and its request died with it (nothing is told after Stop). }
  if (FLspId <> 0) and Assigned(GUsagesLspClient) and (GUsagesLspClient() = FLspClient) and (FLspClient <> nil) then
    FLspClient.CancelRequest(FLspId);
  FLspId    := 0;
  FLspClient:= nil;
  FLspWatch.Enabled:= False;
end;

function TDragLintUsagesForm.TryLspQuery: Boolean;
var
  Client: TDragLintLspClient;
  Dbs   : TArray<string>    ;
  Params: TJSONObject       ;
begin
  Result:= False;
  if not Assigned(GUsagesLspClient) then Exit;
  Client:= GUsagesLspClient();
  if (Client = nil) or (Client.State <> dlsConnected) or not Client.IsAlive then Exit;
  Dbs:= FDbPaths;
  if Length(Dbs) = 0 then Dbs:= [FDbPath];
  if not ServerCoversDbs(Dbs, Client.DbPaths) then Exit;
  Params:= UsagesLspParams(FSymbolName, FWidth);
  try
    FLspId:= Client.RequestAsync('draglint/usages', Params, USAGES_LSP_BUDGET_MS, LspAnswered);
  finally
    Params.Free;
  end;
  if FLspId = 0 then Exit;
  FLspClient:= Client;
  FLspWatch.Enabled:= True;
  Result:= True;
end;

procedure TDragLintUsagesForm.LspWatchTick(Sender: TObject);
var
  Cur: TDragLintLspClient;
begin
  { A stopped client runs no callback, so a request on it would leave "(searching...)" until
    Refresh. Cur is called only when it IS the asked client (then it is live, not freed). }
  Cur:= if Assigned(GUsagesLspClient) then GUsagesLspClient() else nil;
  if not UsagesRequestOrphaned(FLspId, FLspClient, Cur, (Cur <> nil) and (Cur = FLspClient) and Cur.IsAlive) then
  begin
    if FLspId = 0 then FLspWatch.Enabled:= False;
    Exit;
  end;
  FLspWatch.Enabled:= False;
  FLspId           := 0;
  FLspClient       := nil;
  RunCliQuery; { the server that was asked is gone: the CLI answers }
end;

procedure TDragLintUsagesForm.LspAnswered(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue);
var
  Json: string;
begin
  if AId <> FLspId then Exit; { superseded }
  if (AStatus = lrsResult) and UsagesFromReply(AReply, Json) then
  begin
    FLspId    := 0;
    FLspClient:= nil;
    ShowResult(0, Json);
    Exit;
  end;
  { Late (the notice, not an answer), an engine without the method, or a reply this
    form cannot read: the CLI answers, and the server's own answer is no longer wanted. }
  CancelLspQuery;
  RunCliQuery;
end;

procedure TDragLintUsagesForm.RunQuery;
begin
  FRun.Cancel;
  CancelLspQuery;
  FTree.Items.BeginUpdate;
  try
    ClearNodeData;
    FTree.Items.Clear;
    if FExePath = '' then AddNodeData(nil, '(drag-lint.exe path not configured)', '', 0)
    else AddNodeData(nil, '(searching...)', '', 0);
  finally
    FTree.Items.EndUpdate;
  end;
  if FExePath = '' then Exit;
  if FWidth = '' then FWidth:= 'narrow';
  if TryLspQuery then Exit;
  RunCliQuery;
end; // procedure

procedure TDragLintUsagesForm.RunCliQuery;
var
  CmdLine : string ;
begin
  { v0.42: the new 'usages' command finds reads/writes/etc. (not just calls)
    and supports the width selector. }
  CmdLine:= Format('"%s" usages --name "%s" --width %s', [FExePath, FSymbolName, FWidth]);
  { v0.40.3: emit one --db per resolved path. Falls back to legacy
    single-DB if FDbPaths is empty but FDbPath is set. }
  if Length(FDbPaths) > 0 then
  begin
    for var P in FDbPaths do
      if P <> '' then CmdLine:= CmdLine + Format(' --db "%s"', [P]);  // dl:ok concat-in-loop@48d4 -- one --db per index in use, a handful, once per query
  end
  else if FDbPath <> '' then CmdLine:= CmdLine + Format(' --db "%s"', [FDbPath]);
  CmdLine:= CmdLine + ' --format json';

  { IDE-MAINTHREAD-CLI: a wide usages query can take many seconds on a large index. }
  FRun.Start(CmdLine, USAGES_QUERY_STALL_MS, ShowResult);
end; // procedure

procedure TDragLintUsagesForm.ShowResult(AExitCode: Integer; const AOutput: string);
var
  Output  : string ;
  Parsed  : Boolean;
  i       : Integer;
begin
  FTree.Items.BeginUpdate;
  try
    ClearNodeData;
    FTree.Items.Clear;

    if AExitCode < 0 then
    begin
      AddNodeData(nil, '(failed to spawn drag-lint.exe)', '', 0);
      Exit;
    end;

    Output:= Trim(AOutput);

    if (Length(Output) > 0) and (Output[1] = '{') then
    begin
      ParseUsagesGrouped(Output, Parsed); { v0.42 grouped usages JSON }
      if not Parsed then ParseTextOutput(Output);
    end
    else ParseTextOutput(Output);

    if FTree.Items.Count = 0 then
    begin
      var Hint: string;
      Hint:= '(no usages found)';
      if (Length(FSymbolName) > 1) and CharInSet(FSymbolName[1], ['A', 'a']) and CharInSet(FSymbolName[2], ['A'..'Z']) then
        Hint:= Hint + '  -  "' + FSymbolName + '" looks like a parameter (A-prefix); drag-lint does not index parameters or local variables.'
      else if (Length(FSymbolName) > 1) and CharInSet(FSymbolName[1], ['F', 'f']) and CharInSet(FSymbolName[2], ['A'..'Z']) then
        Hint:= Hint + '  -  "' + FSymbolName + '" looks like a private field; make sure the project DB is current (Tools > drag-lint > Lint Buffer).'
      else
        Hint:= Hint + '  -  if "' + FSymbolName + '" is a parameter or local variable, that is expected - drag-lint indexes types, methods, fields and constants only.';
      AddNodeData(nil, Hint, '', 0);
    end; // if

    for i:= 0 to FTree.Items.Count - 1 do
      if FTree.Items[i].Level = 0 then FTree.Items[i].Expand(False);
  finally
    FTree.Items.EndUpdate;
  end; // try
end; // procedure

procedure TDragLintUsagesForm.BtnRefreshClick(Sender: TObject);
begin
  RunQuery;
end;

procedure TDragLintUsagesForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

function ShowSourceEditorFor(const AFile: string): Boolean;
{ v0.46: open and bring forward the CODE view of a unit. For a FORM unit,
  IOTAActionServices.OpenFile (and re-opening an already-open module) can
  surface the form designer / DFM view instead of the .pas source, so
  Find-Usages navigation landed in the DFM. Showing the IOTASourceEditor
  explicitly forces the code editor. }
var
  MS    : IOTAModuleServices;
  Module: IOTAModule        ;
  Editor: IOTAEditor        ;
  Src   : IOTASourceEditor  ;
  i     : Integer           ;
begin
  Result:= False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
  Module:= MS.OpenModule(AFile);
  if Module = nil then Exit;
  for i:= 0 to Module.GetModuleFileCount - 1 do
  begin
    Editor:= Module.GetModuleFileEditor(i);
    if Supports(Editor, IOTASourceEditor, Src) then
    begin
      Src.Show; { brings the .pas code view forward, not the form designer }
      Exit(True);
    end;
  end;
end;

procedure TDragLintUsagesForm.NavigateToNode(ANode: TTreeNode);
var
  ND : TUsageNodeData    ;
  ESS: IOTAEditorServices;
  AS_: IOTAActionServices;
  EV : IOTAEditView      ;
  Pos: IOTAEditPosition  ;
begin
  if ANode      = nil then Exit;
  if ANode.Data = nil then Exit;
  ND:= TUsageNodeData(ANode.Data);
  if (ND.FilePath = '') or (ND.Line <= 0) then Exit;

  { v0.46: force the source (code) view; fall back to OpenFile if that fails. }
  if not ShowSourceEditorFor(ND.FilePath) then
    if Supports(BorlandIDEServices, IOTAActionServices, AS_) then AS_.OpenFile(ND.FilePath);

  if Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    EV:= ESS.TopView;
    if EV <> nil then
    begin
      Pos:= EV.Position;
      if Pos <> nil then
      begin
        Pos.GotoLine(ND.Line);
        EV.Paint;
      end;
    end;
  end;
end; // procedure

procedure TDragLintUsagesForm.TreeDblClick(Sender: TObject);
begin
  NavigateToNode(FTree.Selected);
end;

procedure TDragLintUsagesForm.LoadUsages(const ASymbolName, AExePath, ADbPath: string);
begin
  FSymbolName:= ASymbolName;
  FExePath   := AExePath;
  FDbPath    := ADbPath;
  SetLength(FDbPaths, 0);
  FLblTitle.Caption:= 'Find usages of: ' + ASymbolName;
  RunQuery;
end;

procedure TDragLintUsagesForm.LoadUsages(const ASymbolName, AExePath: string; const ADbPaths: TArray<string>);
begin
  FSymbolName:= ASymbolName;
  FExePath   := AExePath;
  FDbPath    := '';
  FDbPaths   := ADbPaths;
  FLblTitle.Caption:= 'Find usages of: ' + ASymbolName;
  RunQuery;
end;

{ ---- embedded (dock tab) ---- }

type { Holds the search edit + reparented usages form for a dock tab, and runs the
    query on Enter. Owned by the dock frame (AOwner) so it lives/dies with it. }
  TUsagesEmbedCtl = class(TComponent)
    public
      FUsages: TDragLintUsagesForm ;
      FEdit  : TEdit               ;
      FCombo : TComboBox           ;
      function CurrentWidth: string;
      procedure RunFor(const ASym: string);
      procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure ComboChange(Sender: TObject);
  end;

function TUsagesEmbedCtl.CurrentWidth: string;
begin
  if FCombo = nil then Exit('narrow');
  case FCombo.ItemIndex of
    1: Result:= 'wide';
    2: Result:= 'very-wide';
    else Result:= 'narrow';
  end;
end;

procedure TUsagesEmbedCtl.RunFor(const ASym: string);
var
  Exe: string        ;
  Dbs: TArray<string>;
begin
  if (ASym = '') or (FUsages = nil) then Exit;
  if not RequireEngine(Exe) then Exit;
  Dbs:= ResolveActiveIndexDbs(LoadSettings);
  FUsages.SetWidth(CurrentWidth); { set width before the query }
  FUsages.LoadUsages(ASym, Exe, Dbs);
end;

procedure TUsagesEmbedCtl.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key <> VK_RETURN then Exit;
  Key:= 0;
  RunFor(Trim(FEdit.Text));
end;

procedure TUsagesEmbedCtl.ComboChange(Sender: TObject);
begin
  { re-run at the new width if a symbol is already loaded }
  RunFor(Trim(FEdit.Text));
end;

procedure CreateEmbeddedUsages(AOwner: TComponent; AParent: TWinControl);
var
  Pnl  : TPanel             ;
  Lbl  : TLabel             ;
  Edit : TEdit              ;
  Combo: TComboBox          ;
  Frm  : TDragLintUsagesForm;
  Ctl  : TUsagesEmbedCtl    ;
begin
  { search row on top: label + edit + width selector }
  Pnl:= TPanel.Create(AOwner);
  Pnl.Parent    := AParent;
  Pnl.Align     := alTop;
  Pnl.Height    := 28;
  Pnl.BevelOuter:= bvNone;

  Lbl:= TLabel.Create(AOwner);
  Lbl.Parent := Pnl;
  Lbl.Align  := alLeft;
  Lbl.Layout := tlCenter;
  Lbl.Caption:= ' Usages of: ';

  Combo:= TComboBox.Create(AOwner);
  Combo.Parent:= Pnl;
  Combo.Align := alRight;
  Combo.Width := 110;
  Combo.Style := csDropDownList;
  Combo.Items.Add('Narrow'   );
  Combo.Items.Add('Wide'     );
  Combo.Items.Add('Very wide');
  Combo.ItemIndex:= 0;

  Edit:= TEdit.Create(AOwner);
  Edit.Parent  := Pnl;
  Edit.Align   := alClient;
  Edit.TextHint:= 'symbol name, then Enter';

  { reparented usages tree fills the rest }
  Frm:= TDragLintUsagesForm.Create(AOwner);
  Frm.BorderStyle:= bsNone;
  Frm.FormStyle  := fsNormal;
  Frm.Align      := alClient;
  Frm.Parent     := AParent;
  Frm.Visible    := True;

  Ctl:= TUsagesEmbedCtl.Create(AOwner);
  Ctl.FUsages:= Frm;
  Ctl.FEdit  := Edit;
  Ctl.FCombo := Combo;
  Edit .OnKeyDown:= Ctl.EditKeyDown;
  Combo.OnChange := Ctl.ComboChange;
end; // procedure

{ ---- public API ---- }

procedure ShowFindUsages(const ASymbolName, AExePath, ADbPath: string);
begin
  if GUsagesForm = nil then GUsagesForm:= TDragLintUsagesForm.Create(nil);

  GUsagesForm.LoadUsages(ASymbolName, AExePath, ADbPath);

  if not GUsagesForm.Visible then GUsagesForm.Show;
  GUsagesForm.BringToFront;
end;

procedure ShowFindUsages(const ASymbolName, AExePath: string; const ADbPaths: TArray<string>);
begin
  if GUsagesForm = nil then GUsagesForm:= TDragLintUsagesForm.Create(nil);

  GUsagesForm.LoadUsages(ASymbolName, AExePath, ADbPaths);

  if not GUsagesForm.Visible then GUsagesForm.Show;
  GUsagesForm.BringToFront;
end;

procedure HideFindUsages;
begin
  if GUsagesForm <> nil then
  begin
    GUsagesForm.Hide;
    FreeAndNil(GUsagesForm);
  end;
end;

initialization

finalization
if GUsagesForm <> nil then FreeAndNil(GUsagesForm);

end.
