unit DRagLint.MenuTree.Dfm;

/// <summary>menu-tree --with-dfm (spec docs\superpowers\specs\2026-10-24-dxbar-menus.md,
/// decisions 2-8): the .dfm-declared menu surfaces of a project's forms --
/// DevExpress bars, ribbon tabs, bar popups, backstage views, VCL TMainMenu /
/// TPopupMenu -- become menu-tree roots, and the code-added links the walker
/// found under a form's components (external roots) are grafted into them.</summary>
/// <remarks>Reads each .dfm FILE with TFormDfmTree at query time; the index
/// only lists the .dfm files and their sha. No extractor surface. Read-only on
/// the DB. Not thread-safe.</remarks>

interface

uses
  DRagLint.MenuTree
  ;

/// <summary>Adds one root per .dfm-declared menu surface of every text .dfm
/// indexed under the project's folder, then moves the children of each
/// external root whose identifier names a component (or Bars[n] /
/// MainMenuBar / BarByCaption) of the form whose .pas the root came from
/// under the matching .dfm node(s).</summary>
/// <param name="pTree">The walker's tree (TMenuWalker.Walk); roots are added
/// and grafted external roots are removed from it. Must not be nil.</param>
/// <param name="pDb">The project DB (read-only).</param>
/// <param name="pProject">The .dproj / .dpr; its folder scopes the .dfm files.</param>
/// <exception cref="EMenuTreeStale">A .dfm changed since it was indexed.</exception>
/// <remarks>Root caption = the forms-csv location prefix ("Main menu",
/// "Ribbon: Tab > Bar", "Toolbar 'X'", "Right-click menu pop", "File menu");
/// root Ident = FormClass.component, IdentPath = the .dfm path, Form = the form
/// class. An item linked N times is N nodes. Grafted nodes found by position or
/// lookup (Bars[n], MainMenuBar, BarBy*) become derived. Binary and inherited
/// .dfm files are skipped with a note; a bar item linked nowhere gives a note.</remarks>
procedure AddDfmRoots(pTree: TMenuTree; const pDb, pProject: string);

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils
  , System.Hash
  , System.Generics.Collections
  , Data.DB
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param  // dl:ok unused-unit-in-uses@c61d -- TFDQuery.Params[I].AsString needs TFDParam, declared there
  , DRagLint.Storage.SQLite
  , DRagLint.FormsMap.Dfm
  ;

const
  MAX_LINK_DEPTH    = 8;   { sub-item nesting deeper than this is not followed (as forms-csv) }
  SEPARATOR_CAPTION = '-';
  BINARY_SIGNATURE  = 'TPF0';
  { component classes that own links or sit around them -- never "unlinked items" }
  NON_ITEM_BAR_CLASSES: array[0..5] of string = ('TdxBar', 'TdxBarManager', 'TdxBarPopupMenu',
    'TdxBarApplicationMenu', 'TdxBarDockControl', 'TdxBarDockControlEx');

type
  TDfmRootBuilder = class  // dl:ok high-response@6525 -- one builder per form: the DB lookups, the .dfm walk and the graft share the per-form maps; splitting would only move the same calls
  private
    FTree   : TMenuTree;
    FStore  : TSQLiteSymbolStore;
    FProject: string;
    FDb     : string;
    FDfm    : TFormDfmTree;
    FDfmPath: string;
    FPasPath: string;
    FForm   : string;
    FMap    : TObjectDictionary<TFormDfmNode, TList<TMenuNode>>;
    FLinked : TDictionary<string, Boolean>;
    function Q(const pSql: string; const pParams: array of string): TFDQuery;
    function QualifyHandler(const pBare: string): string;
    function Src(pNode: TFormDfmNode): string;
    procedure Remember(pDfmNode: TFormDfmNode; pMenu: TMenuNode);
    function NodeForItem(pItem: TFormDfmNode): TMenuNode;
    procedure AddLinks(pOwner: TFormDfmNode; pParent: TMenuNode; pDepth: Integer; pVisited: TList<TFormDfmNode>);
    procedure NoteUnlinked;
    procedure Graft;
    procedure DoForm(const pPath, pSha: string);
  public
    constructor Create(pTree: TMenuTree; const pDb, pProject: string);
    destructor Destroy; override;
    procedure Run;
  end;

{ Caption as menu-tree stores it ('&&' = a literal '&'): accelerators dropped,
  as forms-csv shows them. }
function DfmCaption(const pRaw: string): string;
var
  SB: TStringBuilder;
  I : Integer;
begin
  SB:= TStringBuilder.Create;
  try
    I:= 1;
    while I <= Length(pRaw) do
    begin
      if pRaw[I] <> '&' then SB.Append(pRaw[I])
      else if (I < Length(pRaw)) and (pRaw[I + 1] = '&') then
      begin
        SB.Append('&&');
        Inc(I);
      end;
      Inc(I);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function CloneNode(pNode: TMenuNode): TMenuNode;
var
  C: TMenuNode;
begin
  Result:= TMenuNode.Create(pNode.Kind, pNode.Caption, pNode.Source);
  Result.Handler   := pNode.Handler;
  Result.Confidence:= pNode.Confidence;
  Result.Ident     := pNode.Ident;
  Result.IdentPath := pNode.IdentPath;
  Result.HasClick  := pNode.HasClick;
  Result.Disabled  := pNode.Disabled;
  Result.LinkIndex := pNode.LinkIndex;
  for C in pNode.Children do Result.AddChild(CloneNode(C));
end;

procedure MarkDerived(pNode: TMenuNode);
var
  C: TMenuNode;
begin
  if pNode.Confidence = mcCertain then pNode.Confidence:= mcDerived;
  for C in pNode.Children do MarkDerived(C);
end;

function IsBarItemClass(const pClass: string): Boolean;
begin
  Result:= StartsText('TdxBar', pClass) and not MatchText(pClass, NON_ITEM_BAR_CLASSES);
end;

{ TDfmRootBuilder }

constructor TDfmRootBuilder.Create(pTree: TMenuTree; const pDb, pProject: string);
begin
  inherited Create;
  FTree   := pTree;
  FDb     := pDb;
  FProject:= pProject;
  FStore  := TSQLiteSymbolStore.Create(pDb, True);
  FMap    := TObjectDictionary<TFormDfmNode, TList<TMenuNode>>.Create([doOwnsValues]);
  FLinked := TDictionary<string, Boolean>.Create;
end;

destructor TDfmRootBuilder.Destroy;
begin
  FLinked.Free;
  FMap.Free;
  FDfm.Free;
  FStore.Free;
  inherited Destroy;
end;

function TDfmRootBuilder.Q(const pSql: string; const pParams: array of string): TFDQuery;
var
  I: Integer;
begin
  Result:= TFDQuery.Create(nil);
  try
    Result.Connection:= FStore.GetConnection;
    Result.SQL.Text:= pSql;
    for I:= 0 to High(pParams) do Result.Params[I].AsString:= pParams[I];
    Result.Open;  // dl:ok dataset-open-without-close@f8d5 -- Q hands the OPEN query to its caller, which frees it in a finally (Free closes the cursor)
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

function TDfmRootBuilder.QualifyHandler(const pBare: string): string;
var
  QH: TFDQuery;
begin
  Result:= '';
  if pBare = '' then Exit;
  QH:= Q('SELECT s.qualified_name AS q FROM symbols s JOIN files f ON f.id = s.file_id '
    + 'WHERE s.name = :n COLLATE NOCASE AND lower(s.qualified_name) LIKE :o '
    + 'ORDER BY (lower(f.path) = :f) DESC, s.id LIMIT 1',
    [pBare, '%.' + LowerCase(FForm) + '.' + LowerCase(pBare), LowerCase(FPasPath)]);
  try
    Result:= if QH.Eof then FForm + '.' + pBare else QH.FieldByName('q').AsString;
  finally
    QH.Free;
  end;
end;

function TDfmRootBuilder.Src(pNode: TFormDfmNode): string;
begin
  Result:= FDfmPath + ':' + IntToStr(pNode.Line);
end;

procedure TDfmRootBuilder.Remember(pDfmNode: TFormDfmNode; pMenu: TMenuNode);
var
  L: TList<TMenuNode>;
begin
  if not FMap.TryGetValue(pDfmNode, L) then
  begin
    L:= TList<TMenuNode>.Create;
    FMap.Add(pDfmNode, L);
  end;
  L.Add(pMenu);
end;

{ decision 4: sub-item -> submenu; static / label -> header; anything else
  button-like -> item, handler OnClick else Action.OnExecute; VCL '-' -> separator. }
function TDfmRootBuilder.NodeForItem(pItem: TFormDfmNode): TMenuNode;
var
  Act    : TFormDfmNode;
  Cap    : string;
  Handler: string;
  Kind   : TMenuNodeKind;
begin
  Act:= FDfm.ItemByName(pItem.Prop('Action'));
  Cap:= pItem.Prop('Caption');
  if (Cap = '') and (Act <> nil) then Cap:= Act.Prop('Caption');
  Handler:= pItem.Prop('OnClick');
  if (Handler = '') and (Act <> nil) then Handler:= Act.Prop('OnExecute');
  if SameText(pItem.CompClass, 'TMenuItem') then
  begin
    if Cap = SEPARATOR_CAPTION then Kind:= mnkSeparator
    else if Length(FDfm.LinksOf(pItem)) > 0 then Kind:= mnkSubmenu
    else Kind:= mnkItem;
  end
  else if ContainsText(pItem.CompClass, 'SubItem') or ContainsText(pItem.CompClass, 'ContainerItem') then Kind:= mnkSubmenu
  else if ContainsText(pItem.CompClass, 'Static') or ContainsText(pItem.CompClass, 'Label') then Kind:= mnkHeader
  else Kind:= mnkItem;
  Result:= TMenuNode.Create(Kind, DfmCaption(Cap), Src(pItem));
  if Kind = mnkItem then
  begin
    Result.Handler := QualifyHandler(Handler);
    Result.HasClick:= Handler <> '';
  end;
end;

procedure TDfmRootBuilder.AddLinks(pOwner: TFormDfmNode; pParent: TMenuNode; pDepth: Integer; pVisited: TList<TFormDfmNode>);
var
  L: TBarLink;
  N: TMenuNode;
begin
  for L in FDfm.LinksOf(pOwner) do
  begin
    if L.BeginGroup then pParent.AddChild(TMenuNode.Create(mnkSeparator, SEPARATOR_CAPTION, Src(L.Link)));
    if L.Item = nil then
    begin
      FTree.AddNote(Format('link to unknown component %s at %s', [L.ItemName, Src(L.Link)]));
      Continue;
    end;
    FLinked.AddOrSetValue(LowerCase(L.ItemName), True);
    N:= pParent.AddChild(NodeForItem(L.Item));
    Remember(L.Item, N);
    { a sub-item linked under itself: the depth cap and the visited set stop it }
    if (N.Kind = mnkSubmenu) and (pDepth < MAX_LINK_DEPTH) and not pVisited.Contains(L.Item) then
    begin
      pVisited.Add(L.Item);
      AddLinks(L.Item, N, pDepth + 1, pVisited);
      pVisited.Remove(L.Item);
    end;
  end;
end;

procedure TDfmRootBuilder.NoteUnlinked;
var
  N: TFormDfmNode;
begin
  for N in FDfm.Nodes do
    if (N <> FDfm.Root) and not N.IsItem and IsBarItemClass(N.CompClass) and not FLinked.ContainsKey(LowerCase(N.Name)) then
      FTree.AddNote(Format('unlinked bar item %s.%s at %s: declared in the .dfm, linked nowhere', [FForm, N.Name, Src(N)]));
end;

{ decisions 2 + 7: the walker's external roots named after this form's
  components (or Bars[n] / MainMenuBar / BarBy*) move under the .dfm nodes.
  A node with a LinkIndex (code Insert(i)) goes to that index; the others append. }
procedure TDfmRootBuilder.Graft;
var
  Ext    : TMenuNode;
  Owner  : TFormDfmNode;
  Derived: Boolean;
  Targets: TList<TMenuNode>;
  Moved  : TList<TMenuNode>;
  C, X   : TMenuNode;
  I      : Integer;
begin
  Moved:= TList<TMenuNode>.Create;
  try
    for Ext in FTree.External.ToArray do
    begin
      if not SameText(Ext.IdentPath, FPasPath) then Continue;
      Owner:= FDfm.FindBarLinkOwner(Ext.Ident, Derived);
      if (Owner = nil) or not FMap.TryGetValue(Owner, Targets) then Continue;
      Moved.Clear;
      while Ext.Children.Count > 0 do Moved.Add(Ext.Children.Extract(Ext.Children[0]));
      for I:= 0 to Targets.Count - 1 do
        for C in Moved do
        begin
          X:= if I = 0 then C else CloneNode(C);
          if Derived then MarkDerived(X);
          if X.LinkIndex >= 0 then Targets[I].InsertChild(X.LinkIndex, X) else Targets[I].AddChild(X);
        end;
      FTree.External.Remove(Ext);
    end;
  finally
    Moved.Free;
  end;
end;

procedure TDfmRootBuilder.DoForm(const pPath, pSha: string);
var
  Bytes  : TBytes;
  Head   : string;
  S      : TBarSurface;
  Root   : TMenuNode;
  Visited: TList<TFormDfmNode>;
begin
  if not TFile.Exists(pPath) then
    raise EMenuTreeStale.CreateFmt('%s changed since it was indexed; reindex first: drag-lint index --project "%s" --db "%s"',
      [pPath, FProject, FDb]);
  Bytes:= TFile.ReadAllBytes(pPath);
  if (Length(Bytes) >= Length(BINARY_SIGNATURE)) and (TEncoding.ANSI.GetString(Bytes, 0, Length(BINARY_SIGNATURE)) = BINARY_SIGNATURE) then
  begin
    FTree.AddNote(Format('binary .dfm not read: %s', [pPath]));
    Exit;
  end;
  { decision 5: same sha basis as the indexer (and the walker's LoadFile) }
  if not SameText(pSha, THashSHA2.GetHashString(TEncoding.ANSI.GetString(Bytes))) then
    raise EMenuTreeStale.CreateFmt('%s changed since it was indexed; reindex first: drag-lint index --project "%s" --db "%s"',
      [pPath, FProject, FDb]);
  Head:= TrimLeft(TEncoding.ANSI.GetString(Bytes, 0, Length(Bytes)));
  if StartsText('inherited ', Head) then
  begin
    FTree.AddNote(Format('inherited form not read: %s (ancestor .dfm merge is deferred)', [pPath]));
    Exit;
  end;
  FreeAndNil(FDfm);
  FMap.Clear;
  FLinked.Clear;
  FDfm:= TFormDfmTree.Create;
  FDfm.LoadFromFile(pPath);
  if FDfm.Root = nil then Exit;
  FDfmPath:= pPath;
  FPasPath:= ChangeFileExt(pPath, '.pas');
  FForm   := FDfm.Root.CompClass;
  Visited:= TList<TFormDfmNode>.Create;
  try
    for S in FDfm.BarSurfaces do
    begin
      Root:= TMenuNode.Create(mnkRoot, DfmCaption(S.Prefix.Replace('&', '&&')), Src(S.Node));
      Root.Ident    := FForm + '.' + S.Node.Name;
      Root.IdentPath:= pPath;
      Root.Form     := FForm;
      FTree.AdoptRoot(Root);
      Remember(S.Node, Root);
      AddLinks(S.Node, Root, 0, Visited);
    end;
  finally
    Visited.Free;
  end;
  NoteUnlinked;
  Graft;
end;

procedure TDfmRootBuilder.Run;
var
  QF   : TFDQuery;
  Dir  : string;
  Paths: TList<TPair<string, string>>;
  P    : TPair<string, string>;
  PFld : TField;
  SFld : TField;
begin
  Dir:= IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(FProject)));
  Paths:= TList<TPair<string, string>>.Create;
  try
    QF:= Q('SELECT path AS p, sha256 AS s FROM files WHERE lower(path) LIKE :d AND lower(path) LIKE ''%.dfm'' ORDER BY lower(path)',
      [LowerCase(Dir) + '%']);
    try
      PFld:= QF.FieldByName('p');
      SFld:= QF.FieldByName('s');
      while not QF.Eof do
      begin
        Paths.Add(TPair<string, string>.Create(PFld.AsString, SFld.AsString));
        QF.Next;
      end;
    finally
      QF.Free;
    end;
    for P in Paths do DoForm(P.Key, P.Value);
  finally
    Paths.Free;
  end;
end;

procedure AddDfmRoots(pTree: TMenuTree; const pDb, pProject: string);
var
  B: TDfmRootBuilder;
begin
  B:= TDfmRootBuilder.Create(pTree, pDb, pProject);
  try
    B.Run;
  finally
    B.Free;
  end;
end;

end.
