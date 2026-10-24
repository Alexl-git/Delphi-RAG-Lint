program MenuTreeTests;

{ Console tests for DRagLint.MenuTree (code-built menu reader) and
  DRagLint.MenuDrift. Run by tests\autotest\run_menu_tree_tests.ps1, which
  compiles this with dcc64 (search path read from src\cli\drag-lint.dproj) and
  passes the scratch fixture DB + fixture dir for the walker tests.
  Usage: MenuTreeTests.exe [<fixture.sqlite> <fixture dir> [<renamed.sqlite>]]
  Last line: "menutree-tests: N passed, M failed"; exit code 1 on any failure. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.StrUtils
  , Winapi.Windows
  , DRagLint.MenuTree
  , DRagLint.MenuTree.Dfm
  , DRagLint.MenuDrift
  , DRagLint.FormsMap.Dfm
  ;

var
  GPassed: Integer = 0;
  GFailed: Integer = 0;

procedure Check(const pName: string; pOk: Boolean; const pDetail: string = '');
begin
  if pOk then
  begin
    Inc(GPassed);
    Writeln('  PASS ', pName);
  end
  else
  begin
    Inc(GFailed);
    Writeln('  FAIL ', pName, ' ', pDetail);
  end;
end;

procedure CheckEq(const pName, pWant, pGot: string);
begin
  Check(pName, pWant = pGot, Format('want [%s] got [%s]', [pWant, pGot]));
end;

{ ---- Task 2: keys and the model ---- }

procedure TestCaptionKeyVector;
begin
  { The shared vector (spec 6): featuregen's FeatureGenTests carries the SAME
    four rows, so a divergence between the two CaptionKeys fails a battery. }
  CheckEq('key: && and ...', 'uses & deps tab -- review & apply fixes',
    MenuCaptionKey('Uses && Deps Tab -- review && apply fixes...'));
  CheckEq('key: trailing ...', 'find usages', MenuCaptionKey('Find Usages...'));
  CheckEq('key: plain', 'reports', MenuCaptionKey('Reports'));
  CheckEq('key: trim ) only at the end', 'drag-lint (!', MenuCaptionKey('drag-lint (!)'));
  CheckEq('key: quote chars and whitespace', 'a b c', MenuCaptionKey('  `A`  *b*  "C" '));
  CheckEq('path key', 'fixture > tools > find usages', MenuPathKey('Fixture > Tools  > Find Usages...'));
  CheckEq('path key drops empty segments', 'a > b', MenuPathKey('A > ... > B'));
end;

procedure TestToPaths;
var
  Tree: TMenuTree;
  Root, Sub, N: TMenuNode;
  Lines: TArray<string>;
begin
  Tree:= TMenuTree.Create;
  try
    Root:= Tree.AddRoot('Top', 'u.pas:1');
    N:= Root.AddChild(TMenuNode.Create(mnkItem, 'First...', 'u.pas:2'));
    N.Handler:= 'U.DoFirst';
    Root.AddChild(TMenuNode.Create(mnkSeparator, '-', 'u.pas:3'));
    Root.AddChild(TMenuNode.Create(mnkHeader, 'A Header', 'u.pas:4'));
    Sub:= Root.AddChild(TMenuNode.Create(mnkSubmenu, 'Sub && More', 'u.pas:5'));
    N:= Sub.AddChild(TMenuNode.Create(mnkItem, 'Second', 'u.pas:6'));
    N.Handler:= 'U.DoSecond';
    N.Confidence:= mcDerived;
    Lines:= Tree.ToPaths.Trim.Split([#13#10]);
    Check('ToPaths: two leaf lines', Length(Lines) = 2, Tree.ToPaths);
    if Length(Lines) = 2 then
    begin
      CheckEq('ToPaths line 1', 'Top > First...'#9'U.DoFirst'#9'u.pas:2'#9'certain', Lines[0]);
      CheckEq('ToPaths line 2', 'Top > Sub & More > Second'#9'U.DoSecond'#9'u.pas:6'#9'derived', Lines[1]);
    end;
    CheckEq('node key', 'sub & more', Sub.CaptionKey);
  finally
    Tree.Free;
  end;
end;

{ ---- Task 3/4: the walker on tests\fixtures\menutree ---- }

/// <summary>expected-paths.txt / ToPaths rows as 'path|handler|confidence'
/// ('## external' lines kept verbatim). ToPaths carries file:line as its third
/// column; the golden does not, so it is dropped here.</summary>
function PathRows(const pText: string; pHasSource: Boolean): TArray<string>;
var
  Line: string;
  C   : TArray<string>;
begin
  Result:= nil;
  for Line in pText.Replace(#13#10, #10).Split([#10]) do
  begin
    if Line.Trim = '' then Continue;
    if Line.StartsWith('## ') then begin Result:= Result + [Line.Trim]; Continue; end;
    C:= Line.Split([#9]);
    if pHasSource and (Length(C) = 4) then Result:= Result + [C[0] + '|' + C[1] + '|' + C[3]]
    else if (not pHasSource) and (Length(C) = 3) then Result:= Result + [C[0] + '|' + C[1] + '|' + C[2]]
    else Result:= Result + ['<malformed: ' + Line + '>'];
  end;
end;

procedure CheckRows(const pTag: string; const pWant, pGot: TArray<string>);
var
  I: Integer;
  W, G: string;
begin
  CheckEq(pTag + ': row count', IntToStr(Length(pWant)), IntToStr(Length(pGot)));
  for I:= 0 to High(pWant) do
  begin
    W:= pWant[I];
    if I <= High(pGot) then G:= pGot[I] else G:= '<no row>';
    CheckEq(Format('%s: row %d', [pTag, I + 1]), W, G);
  end;
end;

function FindChild(pNode: TMenuNode; const pCaption: string): TMenuNode;
var
  C: TMenuNode;
begin
  Result:= nil;
  if pNode = nil then Exit;
  for C in pNode.Children do
    if C.Caption = pCaption then Exit(C);
end;

function HasNote(pTree: TMenuTree; const pPart: string): Boolean;
var
  S: string;
begin
  Result:= False;
  for S in pTree.Notes do
    if Pos(pPart, S) > 0 then Exit(True);
end;

{ forms-csv v8: a code-added item grafted under a .dfm TMenuItem is found by
  handler with the full main-menu path; a TMainMenu of the same name is not
  a graft target; the design-time child stays. }
procedure TestDfmGraft;
var
  T      : TFormDfmTree;
  Tools  : TFormDfmNode;
  Sub    : TFormDfmNode;
  W      : TArray<TNavWay>;
begin
  T:= TFormDfmTree.Create;
  try
    T.LoadFromLines(['object frmX: TfrmX', '  object mnuMain: TMainMenu', '    object mnuTools: TMenuItem',
      '      Caption = ''&Tools''', '      object mnuDesign: TMenuItem', '        Caption = ''Design''',
      '        OnClick = DesignClick', '      end', '    end', '  end', 'end']);
    Check('graft: no way before the graft (positive control)', Length(T.WaysForHandler('CodeClick')) = 0);
    Check('graft: a TMainMenu is not a graft target', T.FindMenuItem('mnuMain') = nil);
    Tools:= T.FindMenuItem('MNUTOOLS');
    Check('graft: FindMenuItem is case-insensitive', Tools <> nil);
    if Tools = nil then Exit;
    T.AddCodeMenuItem(Tools, 'Code &Item', 'CodeClick');
    Sub:= T.AddCodeMenuItem(Tools, 'More', '');
    T.AddCodeMenuItem(Sub, 'Deep', 'DeepClick');
    W:= T.WaysForHandler('CodeClick');
    CheckEq('graft: item path', 'Main menu: Tools > Code Item', if Length(W) > 0 then W[0].Location else '<none>');
    CheckEq('graft: item click', 'Code Item', if Length(W) > 0 then W[0].Click else '<none>');
    W:= T.WaysForHandler('DeepClick');
    CheckEq('graft: code submenu path', 'Main menu: Tools > More > Deep', if Length(W) > 0 then W[0].Location else '<none>');
    W:= T.WaysForHandler('DesignClick');
    CheckEq('graft: design-time child unchanged', 'Main menu: Tools > Design', if Length(W) > 0 then W[0].Location else '<none>');
  finally
    T.Free;
  end;
end;

procedure TestWalkerRoot(const pDb, pProject: string);
var
  W   : TMenuWalker;
  Tree: TMenuTree;
  Root, Sub: TMenuNode;
  Seps: Integer;
  C   : TMenuNode;
begin
  W:= TMenuWalker.Create([pDb], pProject);
  try
    Tree:= W.Walk('MT.Builder.BuildMainMenu');
    try
      { if MainMenu <> nil then MainMenu.Items.Add(Root) else AddActionMenu(.., Root, ..): ONE root }
      CheckEq('root: one root for the two-branch if', '1', IntToStr(Tree.Roots.Count));
      if Tree.Roots.Count = 0 then Exit;
      Root:= Tree.Roots[0];
      CheckEq('root: caption', 'Fixture', Root.Caption);
      Sub:= FindChild(Root, 'Tools && Options');
      Check('inline-var submenu is a child of the root', Sub <> nil);
      if Sub <> nil then CheckEq('inline-var submenu kind', 'submenu', MenuKindName(Sub.Kind));
      Check('Format caption keeps the pattern', FindChild(Root, 'Find %s...') <> nil);
      Check('const-identifier caption evaluates', FindChild(Root, 'Export Everything') <> nil);
      Check('literal + literal caption evaluates', FindChild(Root, 'Direct Item') <> nil);
      if Root.Children.Count > 0 then CheckEq('Insert(0, X) puts X first', 'Direct Item', Root.Children[0].Caption);
      Seps:= 0;
      for C in Root.Children do if C.Kind = mnkSeparator then Inc(Seps);
      CheckEq('separator helper: two separators', '2', IntToStr(Seps));
      if Sub <> nil then
      begin
        C:= FindChild(Sub, 'Formatting');
        Check('header helper (Enabled := False) gives a header', (C <> nil) and (C.Kind = mnkHeader));
        C:= FindChild(Sub, 'Format Unit');
        Check('item helper: handler through the wrapper', (C <> nil) and (C.Handler = 'MT.Builder.DoFormat'),
          IfThen(C = nil, '<none>', C.Handler));
      end;
      Check('--root: only the one builder (no external roots)', Tree.External.Count = 0);
    finally
      Tree.Free;
    end;
  finally
    W.Free;
  end;
end;

procedure TestWalkerFull(const pDb, pProject, pFixtureDir: string);
var
  W   : TMenuWalker;
  Tree: TMenuTree;
  Ext : TMenuNode;
begin
  W:= TMenuWalker.Create([pDb], pProject);
  try
    Tree:= W.Walk;
    try
      CheckRows('golden', PathRows(TFile.ReadAllText(TPath.Combine(pFixtureDir, 'expected-paths.txt')), False),
        PathRows(Tree.ToPaths, True));
      Check('dynamic caption -> a note', HasNote(Tree, 'dynamic caption'));
      Check('unparented item -> a note, in no root', HasNote(Tree, 'Orphan Item'));
      Check('catalog: one header per case arm', (Tree.Roots.Count > 0)
        and (FindChild(FindChild(Tree.Roots[0], 'Catalog'), 'Basic Group') <> nil)
        and (FindChild(FindChild(Tree.Roots[0], 'Catalog'), 'Advanced Group') <> nil));
      Ext:= nil;
      if Tree.External.Count > 0 then Ext:= Tree.External[0];
      Check('DFM mnuTools children land under external-root mnuTools',
        (Ext <> nil) and (Ext.Ident = 'mnuTools') and (Ext.Children.Count = 2));
    finally
      Tree.Free;
    end;
  finally
    W.Free;
  end;
end;

procedure TestWalkerRenamed(const pDb, pProject, pFixtureDir: string);
var
  W   : TMenuWalker;
  Tree: TMenuTree;
begin
  { spec 11 control 4: AddItem renamed PutItem in a copy -- recognition is by
    BODY, so the tree is unchanged. A leaf-regex scraper goes blind here. }
  W:= TMenuWalker.Create([pDb], pProject);
  try
    Tree:= W.Walk;
    try
      CheckRows('renamed helper', PathRows(TFile.ReadAllText(TPath.Combine(pFixtureDir, 'expected-paths.txt')), False),
        PathRows(Tree.ToPaths, True));
    finally
      Tree.Free;
    end;
  finally
    W.Free;
  end;
end;

{ ---- dxBar spec T4: walker code links on the formsmap-v9 fixture ---- }

const
  { command-line slots the runner passes for the formsmap-v9 copies }
  ARG_V9_DB   = 4;
  ARG_V9_DIR  = 5;
  ARG_V9R_DB  = 6;
  ARG_V9R_DIR = 7;
  V9_PROJECT  = 'Demo9.dproj';

procedure TestWalkerDxBar(const pDb, pProject, pFixtureDir, pTag: string);
var
  W    : TMenuWalker;
  Tree : TMenuTree;
  N    : TMenuNode;
  Ids  : string;
  Kinds: string;
begin
  W:= TMenuWalker.Create([pDb], pProject);
  try
    Tree:= W.Walk;
    try
      Ids:= '';
      for N in Tree.External do Ids:= Ids + (if Ids = '' then '' else ',') + N.Ident;
      { the helper's popup keeps the CALLER's name (popGrid), never pPopup }
      CheckEq(pTag + ': external roots (code links before the graft)', 'popGridMenu9,barLists,dxBarManager1.Bars[0],popGrid', Ids);
      Kinds:= '';
      if Tree.External.Count > 0 then
        for N in Tree.External[0].Children do Kinds:= Kinds + (if Kinds = '' then '' else ',') + MenuKindName(N.Kind);
      CheckEq(pTag + ': with-receiver BeginGroup + Insert(0) order', 'submenu,separator,item', Kinds);
      AddDfmRoots(Tree, pDb, pProject);
      CheckRows(pTag + ': --with-dfm paths', PathRows(TFile.ReadAllText(TPath.Combine(pFixtureDir, 'expected-paths.txt')), False),
        PathRows(Tree.ToPaths, True));
    finally
      Tree.Free;
    end;
  finally
    W.Free;
  end;
end;

{ ---- Task 6: drift classes on the fixture tree + fixture registry ---- }

function Drift(pTree: TMenuTree; const pRegDir: string; const pEdit: TProc<TMenuRegistry>): TMenuDriftReport;
var
  Reg: TMenuRegistry;
begin
  Reg:= TMenuRegistry.Create;
  try
    Reg.LoadFromDir(pRegDir);
    if Assigned(pEdit) then pEdit(Reg);
    Result:= ComputeMenuDrift(pTree, Reg);
  finally
    Reg.Free;
  end;
end;

procedure RemovePath(pReg: TMenuRegistry; const pPath: string);
var
  I: Integer;
begin
  for I:= pReg.Surfaces.Count - 1 downto 0 do
    if pReg.Surfaces[I].Path = pPath then pReg.Surfaces.Delete(I);
end;

procedure CheckCounts(const pTag: string; pRep: TMenuDriftReport; pMissing, pUnreg, pMoved: Integer);
begin
  CheckEq(pTag + ': counts', Format('missing=%d unregistered=%d moved=%d', [pMissing, pUnreg, pMoved]),
    Format('missing=%d unregistered=%d moved=%d', [pRep.Missing.Count, pRep.Unregistered.Count, pRep.Moved.Count]));
end;

procedure TestDrift(const pDb, pFixtureDir: string);
var
  W     : TMenuWalker;
  Tree  : TMenuTree;
  RegDir: string;
  Rep   : TMenuDriftReport;
  Base  : Integer;
  Hand  : TMenuTree;
  N     : TMenuNode;
  FamDir: string;
begin
  RegDir:= TPath.Combine(pFixtureDir, 'registry');
  W:= TMenuWalker.Create([pDb], TPath.Combine(pFixtureDir, 'MenuTreeFixture.dproj'));
  try
    Tree:= W.Walk;
  finally
    W.Free;
  end;
  try
    Rep:= Drift(Tree, RegDir, nil);
    try
      CheckCounts('unseeded', Rep, 0, 0, 0);
      Check('unseeded: no drift', not Rep.HasDrift, Rep.ToText);
      Base:= Rep.Notes.Count;
    finally
      Rep.Free;
    end;
    Rep:= Drift(Tree, RegDir, procedure(R: TMenuRegistry) begin RemovePath(R, 'Fixture > About'); end);
    try
      CheckCounts('entry deleted', Rep, 0, 1, 0);
      if Rep.Unregistered.Count = 1 then
        CheckEq('entry deleted: skeleton', '{ "type": "ide-menu", "path": "Fixture > About" }', Rep.Unregistered[0].Skeleton);
    finally
      Rep.Free;
    end;
    Rep:= Drift(Tree, RegDir, procedure(R: TMenuRegistry)
      begin
        RemovePath(R, 'Fixture > Export Everything');
        R.AddSurface('export', 'Fixture > Export Everything Now');
      end);
    try
      CheckCounts('caption changed', Rep, 1, 0, 0);
      if Rep.Missing.Count = 1 then
        CheckEq('caption changed: renamed hint', 'renamed? -> ''Export Everything''', Rep.Missing[0].Hint);
    finally
      Rep.Free;
    end;
    Rep:= Drift(Tree, RegDir, procedure(R: TMenuRegistry)
      begin
        RemovePath(R, 'Fixture > About');
        R.AddSurface('about', 'Fixture > Catalog > About');
      end);
    try
      CheckCounts('parent changed', Rep, 0, 0, 1);
      if Rep.Moved.Count = 1 then CheckEq('parent changed: nowAt', 'Fixture > About', Rep.Moved[0].NowAt);
    finally
      Rep.Free;
    end;
    Rep:= Drift(Tree, RegDir, procedure(R: TMenuRegistry)
      begin
        RemovePath(R, 'Fixture > About');
        R.Exempt.Add('About');
      end);
    try
      CheckCounts('exempt live caption', Rep, 0, 0, 0);
    finally
      Rep.Free;
    end;
    Rep:= Drift(Tree, RegDir, procedure(R: TMenuRegistry) begin R.Exempt.Add('Catalog'); end);
    try
      CheckEq('stale-looking exemption (a submenu) -> one more note', IntToStr(Base + 1), IntToStr(Rep.Notes.Count));
      CheckCounts('a submenu caption is never unregistered', Rep, 0, 0, 0);
    finally
      Rep.Free;
    end;
    { Task 8 (reader): a registered path that names a live SUBMENU is the
      submenu's own surface (drag-lint > Reports), not a missing item }
    Rep:= Drift(Tree, RegDir, procedure(R: TMenuRegistry) begin R.AddSurface('catalog', 'Fixture > Catalog'); end);
    try
      CheckCounts('registered submenu path', Rep, 0, 0, 0);
    finally
      Rep.Free;
    end;
    { Task 8 (reader): family children (generated\manifest.json "families",
      e.g. chart-questions = the Reports items) are registry surfaces too }
    FamDir:= TPath.Combine(TPath.GetTempPath, 'menutree-family-' + IntToStr(GetCurrentProcessId));
    TDirectory.CreateDirectory(TPath.Combine(FamDir, 'entries'));
    TDirectory.CreateDirectory(TPath.Combine(FamDir, 'generated'));
    for var F in TDirectory.GetFiles(TPath.Combine(RegDir, 'entries'), '*.json') do
      if not SameText(TPath.GetFileName(F), 'basic-report.json') then
        TFile.Copy(F, TPath.Combine(TPath.Combine(FamDir, 'entries'), TPath.GetFileName(F)), True);
    TFile.WriteAllText(TPath.Combine(TPath.Combine(FamDir, 'generated'), 'manifest.json'),
      '{ "entries": [], "families": { "fixture-family": [ { "id": "fam.basic", "surfaces": [ ' +
      '{ "type": "ide-menu", "path": "Fixture > Catalog > Basic Report..." } ] } ] } }');
    Rep:= Drift(Tree, FamDir, nil);
    try
      CheckCounts('family child registers an item', Rep, 0, 0, 0);
    finally
      Rep.Free;
    end;  finally
    Tree.Free;
  end;

  { a dynamic node: one note, never a missing for a path under its parent }
  Hand:= TMenuTree.Create;
  try
    N:= Hand.AddRoot('Top', 'u.pas:1');
    N:= N.AddChild(TMenuNode.Create(mnkDynamic, '<dynamic: S>', 'u.pas:2'));
    N.Confidence:= mcUnknown;
    Hand.AddNote('dynamic caption at u.pas:2: X.Caption:= S');
    Rep:= Drift(Hand, RegDir, procedure(R: TMenuRegistry)
      begin
        R.Surfaces.Clear;
        R.AddSurface('x', 'Top > Something');
      end);
    try
      CheckCounts('dynamic node', Rep, 0, 0, 0);
      CheckEq('dynamic node: notes', '1', IntToStr(Rep.Notes.Count));
    finally
      Rep.Free;
    end;
  finally
    Hand.Free;
  end;
end;

{ ---- dxBar spec T2: the TFormDfmTree structural API ---- }

function LinkNames(const pLinks: TArray<TBarLink>): string;
var
  L: TBarLink;
begin
  Result:= '';
  for L in pLinks do Result:= Result + (if Result = '' then '' else ',') + L.ItemName + (if L.BeginGroup then '+' else '');
end;

procedure TestDfmBarApi(const pDfm: string);
var
  T      : TFormDfmTree;
  S      : TBarSurface;
  Txt    : string;
  Derived: Boolean;
  Bar    : TFormDfmNode;
  Sub    : TFormDfmNode;
  Ways   : TArray<TNavWay>;
begin
  T:= TFormDfmTree.Create;
  try
    T.LoadFromFile(pDfm);
    Check('dfm api: fixture loaded', (T.Root <> nil) and SameText(T.Root.CompClass, 'TfrmMain9'), pDfm);
    Txt:= '';
    for S in T.BarSurfaces do Txt:= Txt + (if Txt = '' then '' else '|') + S.Prefix;
    CheckEq('dfm api: BarSurfaces in .dfm order',
      'Main menu|Ribbon: Lists > Lists Bar|Ribbon: Main|Toolbar ''Quick Access Toolbar''|Right-click menu popGrid|File menu', Txt);
    Bar:= T.ItemByName('barLists');
    Check('dfm api: ItemByName barLists has a line', (Bar <> nil) and (Bar.Line > 0));
    CheckEq('dfm api: LinksOf barLists (BeginGroup +)', 'btnCustomers,btnSuppliers+', LinkNames(T.LinksOf(Bar)));
    CheckEq('dfm api: LinksOf backstage = Buttons', 'btnOptions,btnExit', LinkNames(T.LinksOf(T.ItemByName('dxRibbonBackstageView1'))));
    CheckEq('dfm api: LinksOf sub-item', 'btnGroups,btnUsers+', LinkNames(T.LinksOf(T.ItemByName('subSetup'))));
    CheckEq('dfm api: ItemByName class', 'TdxBarSubItem', T.ItemByName('subSetup').CompClass);
    CheckEq('dfm api: SurfacePrefixes of a sub-item', 'Main menu > Setup', string.Join('|', T.SurfacePrefixes(T.ItemByName('subSetup'))));
    Check('dfm api: ItemByName unknown = nil', T.ItemByName('nope') = nil);
    Check('dfm api: Bars[0] = the first TdxBar, derived',
      (T.FindBarLinkOwner('dxBarManager1.Bars[0]', Derived) = T.ItemByName('barMainMenu')) and Derived);
    Check('dfm api: Self.barLists by name, not derived', (T.FindBarLinkOwner('Self.barLists', Derived) = Bar) and not Derived);
    Check('dfm api: MainMenuBar', T.FindBarLinkOwner('dxBarManager1.MainMenuBar', Derived) = T.ItemByName('barMainMenu'));
    Check('dfm api: BarByCaption', T.FindBarLinkOwner('dxBarManager1.BarByCaption(''Lists Bar'')', Derived) = Bar);
    Check('dfm api: Bars[9] = nil', T.FindBarLinkOwner('dxBarManager1.Bars[9]', Derived) = nil);
    { code links: appended to a bar, and a sub-item inserted at 0 with a child }
    T.AddCodeBarItem(Bar, 'Vendor List', 'btnVendorsClick', 'TdxBarButton', -1);
    CheckEq('dfm api: code link appended', 'btnCustomers,btnSuppliers+,codeBarItem1', LinkNames(T.LinksOf(Bar)));
    Ways:= T.WaysForHandler('btnVendorsClick');
    Check('dfm api: code button way', (Length(Ways) = 1) and (Ways[0].Location = 'Ribbon: Lists > Lists Bar > Vendor List')
      and (Ways[0].CtrlClass = 'TdxBarButton'), if Length(Ways) > 0 then Ways[0].Location else '(none)');
    Sub:= T.AddCodeBarItem(T.ItemByName('barMainMenu'), 'Presets', '', 'TdxBarSubItem', 0);
    T.AddCodeBarItem(Sub, 'Reset Presets', 'btnResetClick', 'TdxBarButton', -1);
    Check('dfm api: code sub-item inserted at 0', T.LinksOf(T.ItemByName('barMainMenu'))[0].Item = Sub);
    Ways:= T.WaysForHandler('btnResetClick');
    Check('dfm api: code sub-item child way', (Length(Ways) = 1) and (Ways[0].Location = 'Main menu: Presets > Reset Presets'),
      if Length(Ways) > 0 then Ways[0].Location else '(none)');
  finally
    T.Free;
  end;
end;

begin
  try
    TestCaptionKeyVector;
    TestToPaths;
    TestDfmGraft;
    if ParamCount >= 2 then
    begin
      TestDfmBarApi(TPath.Combine(TPath.Combine(ExtractFileDir(ExcludeTrailingPathDelimiter(ParamStr(2))), 'formsmap-v9'), 'uMain9.dfm'));
      TestWalkerRoot(ParamStr(1), TPath.Combine(ParamStr(2), 'MenuTreeFixture.dproj'));
      TestWalkerFull(ParamStr(1), TPath.Combine(ParamStr(2), 'MenuTreeFixture.dproj'), ParamStr(2));
      TestDrift(ParamStr(1), ParamStr(2));
    end
    else Check('walker tests need <db> <fixture dir>', False);
    if ParamCount >= ARG_V9R_DIR then
    begin
      TestWalkerDxBar(ParamStr(ARG_V9_DB), TPath.Combine(ParamStr(ARG_V9_DIR), V9_PROJECT), ParamStr(ARG_V9_DIR), 'dxbar');
      TestWalkerDxBar(ParamStr(ARG_V9R_DB), TPath.Combine(ParamStr(ARG_V9R_DIR), V9_PROJECT), ParamStr(ARG_V9R_DIR), 'dxbar renamed helper');
    end
    else Check('dxbar walker tests need <v9.sqlite> <v9 dir> <v9-renamed.sqlite> <v9-renamed dir>', False);
    if ParamCount >= 3 then
      TestWalkerRenamed(ParamStr(3), TPath.Combine(TPath.Combine(ExtractFilePath(ParamStr(3)), 'renamed'), 'MenuTreeFixture.dproj'), ParamStr(2));
  except
    on E: Exception do
    begin
      Inc(GFailed);
      Writeln('  FAIL unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln(Format('menutree-tests: %d passed, %d failed', [GPassed, GFailed]));
  if GFailed > 0 then ExitCode:= 1;
end.
